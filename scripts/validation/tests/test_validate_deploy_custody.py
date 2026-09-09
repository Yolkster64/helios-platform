from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
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
        self.assertIn(before, self.workflow_text)
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
        self._validate_mutation(
            "        if: steps.creds.outputs.configured == 'true'",
            "        if: github.event_name == 'push'",
            "gated by the OIDC configuration guard",
        )

    def test_fails_when_contents_permission_is_elevated(self) -> None:
        self._validate_mutation("  contents: read", "  contents: write", "keep contents: read")

    def test_fails_when_resource_group_creation_is_added(self) -> None:
        self._validate_mutation("          account=", "          az group create -n surprise\n          account=", "never create a resource group")

    def test_fails_when_push_trigger_returns(self) -> None:
        self._validate_mutation("on:\n", "on:\n  push: {}\n", "only allow workflow_dispatch")

    def test_fails_when_wrong_environment(self) -> None:
        self._validate_mutation("environment: azure-dev", "environment: production", "protected azure-dev")

    def test_fails_when_dispatch_is_allowed_off_main(self) -> None:
        self._validate_mutation(" && github.ref == 'refs/heads/main'", "", "manual dispatch from main")

    def test_fails_when_what_if_default_is_false(self) -> None:
        self._validate_mutation("default: true", "default: false", "what_if must default")

    def test_fails_when_apply_confirmation_default_is_true(self) -> None:
        self._validate_mutation("default: false", "default: true", "deploy_confirmed must default")

    def test_fails_when_location_default_is_added(self) -> None:
        self._validate_mutation("${{ vars.AZURE_LOCATION }}", "${{ vars.AZURE_LOCATION || 'eastus2' }}", "explicit variable AZURE_LOCATION")

    def test_fails_when_target_no_longer_checks_location(self) -> None:
        self._validate_mutation("(.location | ascii_downcase)", "(.name | ascii_downcase)", "target precheck must verify")

    def test_fails_when_oidc_grant_is_global(self) -> None:
        self._validate_mutation("permissions:\n  contents: read", "permissions:\n  contents: read\n  id-token: write", "no global id-token")

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

    def test_fails_when_cli_exit_code_is_not_preserved(self) -> None:
        self._validate_mutation("          exit \"$rc\"", "          echo \"$rc\"", "preserve az CLI exit codes")

    def test_fails_when_deploy_dispatch_guard_is_broadened(self) -> None:
        self._validate_mutation(
            " && !inputs.what_if && inputs.deploy_confirmed",
            " && !inputs.what_if",
            "explicit confirmation",
        )

    def test_fails_when_raw_output_is_tee_d_to_record(self) -> None:
        self._validate_mutation(
            "            --output json > \"$stdout_file\" 2>\"$stderr_file\"",
            "            --output json 2>\"$stderr_file\" | tee \"$record\"",
            "must not archive raw command output",
        )

    def test_fails_when_helper_script_is_removed_from_deploy_step(self) -> None:
        self._validate_mutation(
            "python3 scripts/validation/emit_deploy_custody_record.py",
            "python3 -c 'print(42)'",
            "shared deploy custody record helper",
        )

    def test_fails_when_precheck_no_longer_retains_failure_evidence(self) -> None:
        self._validate_mutation(
            "record-target-precheck-",
            "record-what-if-skipped-",
            "precheck must retain failure evidence",
        )

    def test_fails_when_temp_cleanup_is_removed(self) -> None:
        self._validate_mutation(
            "          trap 'rm -f \"$stdout_file\" \"$stderr_file\"' EXIT\n          set +e",
            "          echo 'skip cleanup'\n          set +e",
            "clean up raw temp output files",
        )

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


class DeployTargetBehaviorTests(unittest.TestCase):
    def setUp(self) -> None:
        data = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
        self.steps = data["jobs"]["deploy"]["steps"]

    def test_target_precheck_rejects_mismatches_and_failed_reads(self) -> None:
        self.assertIsNotNone(shutil.which("jq"), "jq is required for the workflow shell gate")
        run = target._find_step(self.steps, "Verify Azure deployment target")["run"]
        fake_az = r"""
import json, os, sys
mode = os.environ['AZ_TEST_MODE']
args = sys.argv[1:]
if args[:2] == ['account', 'show']:
    if mode == 'account-error': sys.exit(23)
    obj = {'id': 'bad' if mode == 'subscription' else 'sub-a',
           'tenantId': 'bad' if mode == 'tenant' else 'tenant-a',
           'state': 'Disabled' if mode == 'disabled' else 'Enabled'}
elif args[:2] == ['group', 'show']:
    if mode == 'group-error': sys.exit(24)
    assert args[args.index('--subscription') + 1] == 'sub-a'
    obj = {'id': '/subscriptions/sub-a/resourceGroups/' + ('bad' if mode == 'group' else 'rg-a'),
           'location': 'bad' if mode == 'location' else 'eastus2'}
else:
    sys.exit('Unexpected Azure operation')
print(json.dumps(obj))
"""
        for mode in ("valid", "subscription", "tenant", "disabled", "group", "location", "account-error", "group-error"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                root = pathlib.Path(temp)
                (root / "custody").mkdir()
                helper = root / "scripts/validation/emit_deploy_custody_record.py"
                helper.parent.mkdir(parents=True)
                shutil.copyfile(target.RECORD_SCRIPT, helper)
                az = root / "az"
                az.write_text("#!" + sys.executable + "\n" + fake_az)
                az.chmod(0o755)
                output = root / "outputs"
                output.touch()
                env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                       "AZ_TEST_MODE": mode, "GITHUB_OUTPUT": str(output),
                       "GITHUB_RUN_ID": "1", "GITHUB_RUN_ATTEMPT": "1",
                       "AZURE_SUBSCRIPTION_ID": "sub-a", "AZURE_TENANT_ID": "tenant-a",
                       "AZURE_RESOURCE_GROUP": "rg-a", "AZURE_LOCATION": "eastus2"}
                result = subprocess.run(["bash", "-c", run], cwd=root, env=env, capture_output=True, text=True, timeout=15)
                if mode == "valid":
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("verified=true", output.read_text())
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("verified=true", output.read_text())
                    records = list((root / "custody").glob("record-*.json"))
                    self.assertEqual(len(records), 1, result.stderr)
                    self.assertEqual(json.loads(records[0].read_text())["exitCode"], 1)

    def test_configuration_guard_blocks_unconfirmed_apply_and_missing_values(self) -> None:
        run = target._find_step(self.steps, "Check Azure OIDC configuration")["run"]
        for mode in ("plan", "apply", "unconfirmed", "missing"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                output = pathlib.Path(temp) / "outputs"
                env = {**os.environ, "GITHUB_OUTPUT": str(output), "WHAT_IF": "true" if mode == "plan" else "false",
                       "DEPLOY_CONFIRMED": "true" if mode in ("apply", "missing") else "false",
                       "AZURE_CLIENT_ID": "app-a", "AZURE_TENANT_ID": "tenant-a",
                       "AZURE_SUBSCRIPTION_ID": "sub-a", "AZURE_RESOURCE_GROUP": "rg-a",
                       "AZURE_LOCATION": "" if mode == "missing" else "eastus2"}
                result = subprocess.run(["bash", "-c", run], env=env, capture_output=True, text=True, timeout=10)
                if mode in ("plan", "apply"):
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("configured=true", output.read_text())
                else:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("configured=true", output.read_text())


if __name__ == "__main__":
    unittest.main()
