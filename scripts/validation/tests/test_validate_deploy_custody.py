from __future__ import annotations

import pathlib
import tempfile
import unittest

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

    def test_fails_when_cli_exit_code_is_not_preserved(self) -> None:
        self._validate_mutation("          exit \"$rc\"", "          echo \"$rc\"", "preserve az CLI exit codes")

    def test_fails_when_raw_output_is_tee_d_to_record(self) -> None:
        self._validate_mutation(
            "            --output json > \"$stdout_file\" 2>\"$stderr_file\"",
            "            --output json 2>\"$stderr_file\" | tee \"$record\"",
            "must not archive raw command output",
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


if __name__ == "__main__":
    unittest.main()
