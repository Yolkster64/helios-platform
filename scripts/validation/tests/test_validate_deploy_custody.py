from __future__ import annotations

import pathlib
import tempfile
import unittest

import yaml

from scripts.validation import validate_deploy_custody as target

ROOT = pathlib.Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/helios-deploy.yml"
CONTRACT_WORKFLOW = ROOT / ".github/workflows/deploy-hardening-contract.yml"


class DeployCustodyValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow_text = WORKFLOW.read_text(encoding="utf-8")

    def _validate_mutation(self, before: str, after: str, expected_error: str) -> None:
        # The anchor must be UNIQUE, not merely present. This replaced the first occurrence,
        # so when the verify-gate job arrived carrying the same `if: github.ref ==` line as
        # jobs.deploy, the two ref-pin tests silently retargeted: they went on passing while
        # testing a different job than their names claimed. A count check turns that from a
        # quiet change of subject into a failure that says which anchor went ambiguous.
        occurrences = self.workflow_text.count(before)
        self.assertEqual(
            occurrences,
            1,
            f"mutation anchor must appear exactly once, found {occurrences}: {before!r}",
        )
        mutated = self.workflow_text.replace(before, after, 1)
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "helios-deploy.yml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, expected_error):
                target.validate_workflow(path)

    def test_current_workflow_passes(self) -> None:
        result = target.validate_workflow(WORKFLOW)
        self.assertEqual(result["status"], "passed")

    def test_fails_when_audience_only_appears_in_comment(self) -> None:
        self._validate_mutation(
            "          audience: api://AzureADTokenExchange",
            "          # audience: api://AzureADTokenExchange",
            "pin audience",
        )

    def test_fails_when_login_is_not_gated(self) -> None:
        # Six steps carry this guard; the login step is named by the line that follows it.
        self._validate_mutation(
            "        if: steps.creds.outputs.configured == 'true'\n        uses: azure/login@v2",
            "        if: github.event_name == 'push'\n        uses: azure/login@v2",
            "gated by the OIDC configuration guard",
        )

    def test_fails_when_the_deploy_job_leaves_the_protected_environment(self) -> None:
        """The environment is the only thing standing between a push to main and the tenant.

        CLAUDE.md calls protected environments the deployment authority, and until this
        check existed nothing enforced that: the job ran `az deployment group create` with
        no environment named at all, so the sentence was true only of the documentation.
        """
        self._validate_mutation(
            "    environment: production",
            "    # environment: production",
            "protected `production` environment",
        )

    def test_fails_when_the_deploy_job_is_not_pinned_to_main(self) -> None:
        """Removing the ref pin re-opens what naming the environment closed.

        The environment subject is branch-agnostic, and workflow_dispatch accepts any
        branch, so this guard is the only thing in the repository that stops a dispatch
        from a feature branch minting a token with Contributor + Key Vault Secrets Officer.
        """
        # Anchored on the line AND what follows it: jobs.verify-gate carries the same pin,
        # so the bare line is ambiguous and would retarget this test at the other job.
        self._validate_mutation(
            "    if: github.ref == 'refs/heads/main'\n    # CLAUDE.md:",
            "    # if: github.ref == 'refs/heads/main'\n    # CLAUDE.md:",
            "must be pinned to main",
        )

    def test_fails_when_the_ref_pin_is_widened(self) -> None:
        self._validate_mutation(
            "    if: github.ref == 'refs/heads/main'\n    # CLAUDE.md:",
            "    if: startsWith(github.ref, 'refs/heads/')\n    # CLAUDE.md:",
            "must be pinned to main",
        )

    def test_fails_without_the_gate_verification_job(self) -> None:
        """`environment: production` is a claim; this job is what checks it.

        Naming an environment GitHub does not have CREATES it with no protection rules, so
        the YAML can read as gated while nothing holds the deployment back. That is the
        state this repository is in until the manifest is applied, which needs a credential
        no workflow token has - so the check has to happen at deploy time, every time.
        """
        self._validate_mutation(
            "  verify-gate:\n    runs-on: ubuntu-latest",
            "  verify-gate-disabled:\n    runs-on: ubuntu-latest",
            "must define jobs.verify-gate",
        )

    def test_fails_when_the_verifier_names_the_environment_it_verifies(self) -> None:
        """A verifier that named `production` would create it, then wait for the approval it
        exists to prove is required - and an unprotected environment asks for none, so the
        check would sail through the very state it is meant to catch."""
        self._validate_mutation(
            "  verify-gate:\n    runs-on: ubuntu-latest\n",
            "  verify-gate:\n    runs-on: ubuntu-latest\n    environment: production\n",
            "must NOT name an environment",
        )

    def test_fails_when_the_deploy_job_does_not_wait_for_the_gate_check(self) -> None:
        # Without the needs edge the two jobs run concurrently: the deployment starts while
        # the check is still deciding, which is the same as not checking.
        self._validate_mutation(
            "    needs: verify-gate",
            "    # needs: verify-gate",
            "must declare `needs: verify-gate`",
        )

    def test_fails_when_the_verifier_stops_running_the_gate_script(self) -> None:
        self._validate_mutation(
            "./scripts/github/verify-environment-gate.ps1",
            "echo skipping the gate check #",
            "must run scripts/github/verify-environment-gate.ps1",
        )

    def test_fails_when_the_verifier_is_not_pinned_to_main(self) -> None:
        # A verifier that runs on branches the deploy job does not is not a problem; one that
        # runs on FEWER is, because a skipped `needs` job lets the deploy through.
        self._validate_mutation(
            "    if: github.ref == 'refs/heads/main'\n    permissions:",
            "    if: startsWith(github.ref, 'refs/heads/')\n    permissions:",
            "same main-only pin",
        )

    def test_fails_when_the_deploy_job_names_a_different_environment(self) -> None:
        # A workflow naming an environment the repository does not have gets one with NO
        # protection rules, so a renamed or misspelled environment is an ungated deploy that
        # still looks gated in the YAML.
        self._validate_mutation(
            "    environment: production",
            "    environment: prod",
            "protected `production` environment",
        )

    def test_fails_when_contents_permission_is_elevated(self) -> None:
        # Anchored to the WORKFLOW-level block: jobs.verify-gate declares its own
        # `contents: read`, so the bare line no longer names one place.
        self._validate_mutation(
            "  id-token: write\n  contents: read",
            "  id-token: write\n  contents: write",
            "keep contents: read",
        )

    def test_fails_when_resource_group_creation_runs_outside_push(self) -> None:
        self._validate_mutation(
            "if: steps.creds.outputs.configured == 'true' && github.event_name == 'push'",
            "if: steps.creds.outputs.configured == 'true' && (github.event_name == 'push' || !inputs.what_if)",
            "resource-group creation",
        )

    def test_fails_when_artifact_upload_is_removed(self) -> None:
        self._validate_mutation(
            "        uses: actions/upload-artifact@v4",
            "        run: echo 'removed upload'",
            "uploaded via actions/upload-artifact",
        )

    def test_fails_when_manifest_no_longer_binds_input_digests(self) -> None:
        self._validate_mutation(
            "templateDigestSha256:$templateDigest, parametersDigestSha256:$parametersDigest",
            "templateDigestSha256:$templateDigest",
            "bind template and parameters digests",
        )

    def test_fails_when_what_if_exit_code_is_not_preserved(self) -> None:
        self._validate_mutation(
            "Azure what-if failed (exit $rc). See sanitized custody artifact for diagnostics.\"\n            exit \"$rc\"",
            "Azure what-if failed (exit $rc). See sanitized custody artifact for diagnostics.\"\n            echo \"$rc\"",
            "what-if step must preserve az CLI exit codes",
        )

    def test_fails_when_deploy_exit_code_is_not_preserved(self) -> None:
        # The deploy step's own check, which the shared anchor never reached: `exit "$rc"`
        # appears in both steps and the mutation only ever replaced the first.
        self._validate_mutation(
            "Azure deployment failed (exit $rc). See sanitized custody artifact for diagnostics.\"\n            exit \"$rc\"",
            "Azure deployment failed (exit $rc). See sanitized custody artifact for diagnostics.\"\n            echo \"$rc\"",
            "deploy step must preserve az CLI exit codes",
        )

    def test_fails_when_deploy_dispatch_guard_is_broadened(self) -> None:
        self._validate_mutation(
            "if: steps.creds.outputs.configured == 'true' && (github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && !inputs.what_if))",
            "if: steps.creds.outputs.configured == 'true' && (github.event_name == 'push' || !inputs.what_if)",
            "explicitly guard non-what-if deploys to workflow_dispatch",
        )

    def test_fails_when_raw_output_is_tee_d_to_record(self) -> None:
        self._validate_mutation(
            "            --result-format ResourceIdOnly \\\n            --output json > \"$stdout_file\" 2>\"$stderr_file\"",
            "            --result-format ResourceIdOnly \\\n            --output json 2>\"$stderr_file\" | tee \"$record\"",
            "must not archive raw command output",
        )

    def test_fails_when_helper_script_is_removed_from_deploy_step(self) -> None:
        self._validate_mutation(
            "python3 scripts/validation/emit_deploy_custody_record.py \\\n            --phase deploy",
            "python3 -c 'print(42)' \\\n            --phase deploy",
            "deploy step must use the shared deploy custody record helper",
        )

    def test_fails_when_precheck_no_longer_retains_failure_evidence(self) -> None:
        self._validate_mutation(
            "record-what-if-precheck-",
            "record-what-if-skipped-",
            "precheck must retain failure evidence",
        )

    def test_fails_when_temp_cleanup_is_removed(self) -> None:
        self._validate_mutation(
            "record-deploy-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json\"\n"
            "          stdout_file=\"$(mktemp)\"\n          stderr_file=\"$(mktemp)\"\n"
            "          trap 'rm -f \"$stdout_file\" \"$stderr_file\"' EXIT",
            "record-deploy-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json\"\n"
            "          stdout_file=\"$(mktemp)\"\n          stderr_file=\"$(mktemp)\"\n"
            "          echo 'skip cleanup'",
            "deploy step must clean up raw temp output files",
        )

    def test_contract_workflow_must_run_the_gate_verifier_suite(self) -> None:
        """The verifier is the live gate while `production` is unprotected, so its suite is
        part of the contract rather than something a later edit can quietly drop."""
        contract_text = CONTRACT_WORKFLOW.read_text(encoding="utf-8")
        anchor = "./scripts/verify/tests/test_verify_environment_gate.ps1"
        self.assertEqual(contract_text.count(anchor), 1)
        mutated = contract_text.replace(anchor, "echo skipped", 1)
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "deploy-hardening-contract.yml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "environment-gate verifier suite"):
                target.validate_contract_workflow(path)

    def test_contract_workflow_must_run_unittest(self) -> None:
        contract_text = CONTRACT_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("python3 -m unittest", contract_text)
        mutated = contract_text.replace("python3 -m unittest", "echo", 1)
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "deploy-hardening-contract.yml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "regression tests"):
                target.validate_contract_workflow(path)

    def test_contract_workflow_must_run_helper_tests(self) -> None:
        contract_text = CONTRACT_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("test_emit_deploy_custody_record", contract_text)
        mutated = contract_text.replace(
            "          scripts.validation.tests.test_emit_deploy_custody_record\n",
            "",
            1,
        )
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "deploy-hardening-contract.yml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "helper tests"):
                target.validate_contract_workflow(path)

    def test_contract_workflow_requires_contract_job_mapping(self) -> None:
        contract_data = yaml.safe_load(CONTRACT_WORKFLOW.read_text(encoding="utf-8"))
        contract_data["jobs"]["contract"] = []
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "deploy-hardening-contract.yml"
            path.write_text(yaml.safe_dump(contract_data, sort_keys=False), encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "jobs.contract"):
                target.validate_contract_workflow(path)


if __name__ == "__main__":
    unittest.main()
