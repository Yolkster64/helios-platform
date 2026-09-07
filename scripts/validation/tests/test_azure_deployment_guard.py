"""Dependency-free tests of the real preview helper and checked-in workflow guards."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "scripts/validation/azure_deployment_preview.sh"
WORKFLOW = ROOT / ".github/workflows/helios-deploy.yml"
CONTRACT_WORKFLOW = ROOT / ".github/workflows/azure-deployment-guard.yml"
FIXTURE = Path(__file__).parent / "fixtures/azure-preview-az.py"


class PreviewHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="helios preview contract ")
        self.addCleanup(self.temporary.cleanup)
        self.temp = Path(self.temporary.name)
        self.bin = self.temp / "bin"
        self.bin.mkdir()
        shutil.copy2(FIXTURE, self.bin / "az")
        (self.bin / "az").chmod(0o700)
        self.log = self.temp / "az-calls.jsonl"
        # Do not pass ambient credentials, Azure configuration, tokens, or session
        # environment into a fixture. PATH resolves az to our inert executable first.
        self.env = {
            "PATH": f"{self.bin}{os.pathsep}{os.defpath}",
            "PREVIEW_TEST_LOG": str(self.log),
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": "Yolkster64/helios-platform",
            "GITHUB_REF": "refs/heads/main",
            "HELIOS_WHAT_IF": "true",
            "HELIOS_AZURE_PREVIEW_ENABLED": "true",
            "AZURE_CLIENT_ID": "11111111-1111-1111-1111-111111111111",
            "AZURE_TENANT_ID": "22222222-2222-2222-2222-222222222222",
            "AZURE_SUBSCRIPTION_ID": "33333333-3333-3333-3333-333333333333",
            "AZURE_RESOURCE_GROUP": "rg-helios-preview_(test)",
            "AZURE_BOUND_TENANT_ID": "22222222-2222-2222-2222-222222222222",
            "AZURE_BOUND_SUBSCRIPTION_ID": "33333333-3333-3333-3333-333333333333",
            "AZURE_BOUND_RESOURCE_GROUP": "rg-helios-preview_(test)",
        }

    def run_helper(self, mode="preview", updates=None, helper=HELPER):
        environment = self.env | (updates or {})
        result = subprocess.run(
            ["bash", str(helper), mode], cwd=self.temp, env=environment,
            text=True, capture_output=True, check=False, timeout=15,
        )
        calls = []
        if self.log.exists():
            calls = [json.loads(line) for line in self.log.read_text(encoding="utf-8").splitlines()]
            self.log.unlink()
        return result, calls

    def test_check_modes_never_call_azure(self):
        for mode in ("check-inputs", "check-binding"):
            with self.subTest(mode=mode):
                result, calls = self.run_helper(mode)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual([], calls)

    def test_apply_and_unknown_modes_fail_without_azure(self):
        for mode in ("apply", "create", "--apply", "", "production"):
            with self.subTest(mode=mode):
                result, calls = self.run_helper(mode)
                self.assertNotEqual(0, result.returncode)
                self.assertEqual([], calls)

    def test_apply_request_fails_explicitly(self):
        for value in ("false", "", "1", "TRUE"):
            with self.subTest(value=value):
                result, calls = self.run_helper(updates={"HELIOS_WHAT_IF": value})
                self.assertEqual(2, result.returncode)
                self.assertIn("Deployment is disabled", result.stderr)
                self.assertEqual([], calls)

    def test_preview_disabled_unless_explicitly_enabled(self):
        for value in ("false", "", "1", "TRUE"):
            with self.subTest(value=value):
                result, calls = self.run_helper(updates={"HELIOS_AZURE_PREVIEW_ENABLED": value})
                self.assertEqual(2, result.returncode)
                self.assertIn("Azure preview is disabled", result.stderr)
                self.assertEqual([], calls)

    def test_untrusted_trigger_repository_or_ref_fails(self):
        for key, value in (
            ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_EVENT_NAME", "push"),
            ("GITHUB_EVENT_NAME", "workflow_run"), ("GITHUB_REF", "refs/heads/topic"),
            ("GITHUB_REF", "refs/pull/1/merge"), ("GITHUB_REF", "refs/tags/main"),
            ("GITHUB_REPOSITORY", "outsider/helios-platform"),
        ):
            with self.subTest(key=key, value=value):
                result, calls = self.run_helper(updates={key: value})
                self.assertEqual(2, result.returncode)
                self.assertEqual([], calls)

    def test_missing_identifiers_and_environment_bindings_fail(self):
        for key in (
            "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP",
            "AZURE_CLIENT_ID", "AZURE_BOUND_TENANT_ID", "AZURE_BOUND_SUBSCRIPTION_ID",
            "AZURE_BOUND_RESOURCE_GROUP",
        ):
            with self.subTest(key=key):
                result, calls = self.run_helper(updates={key: ""})
                self.assertEqual(2, result.returncode)
                self.assertEqual([], calls)

    def test_malformed_and_shell_metacharacter_inputs_are_rejected(self):
        for key, value in (
            ("AZURE_TENANT_ID", "not-a-guid"),
            ("AZURE_SUBSCRIPTION_ID", "--other-option"),
            ("AZURE_RESOURCE_GROUP", "rg with spaces"),
            ("AZURE_RESOURCE_GROUP", "rg;echo injected"),
            ("AZURE_RESOURCE_GROUP", "$(echo injected)"),
            ("AZURE_RESOURCE_GROUP", "rg\nother"),
            ("AZURE_RESOURCE_GROUP", "rg."),
            ("AZURE_RESOURCE_GROUP", "r" * 91),
        ):
            with self.subTest(key=key, value=value):
                result, calls = self.run_helper(updates={key: value})
                self.assertEqual(2, result.returncode)
                self.assertEqual([], calls)

    def test_target_must_match_bound_environment_before_any_azure_call(self):
        for key, value in (
            ("AZURE_BOUND_TENANT_ID", "99999999-9999-9999-9999-999999999999"),
            ("AZURE_BOUND_SUBSCRIPTION_ID", "99999999-9999-9999-9999-999999999999"),
            ("AZURE_BOUND_RESOURCE_GROUP", "some-other-group"),
        ):
            with self.subTest(key=key):
                result, calls = self.run_helper(updates={key: value})
                self.assertEqual(2, result.returncode)
                self.assertIn("differs from", result.stderr)
                self.assertEqual([], calls)

    def test_unavailable_or_mismatched_live_target_blocks_preview(self):
        for scenario in (
            "unauthenticated", "wrong-subscription", "wrong-tenant",
            "disabled-account", "missing-group", "wrong-group",
        ):
            with self.subTest(scenario=scenario):
                result, calls = self.run_helper(updates={"PREVIEW_TEST_SCENARIO": scenario})
                self.assertNotEqual(0, result.returncode)
                self.assertFalse(any(call[0] == "deployment" for call in calls))
                self.assertFalse(any("create" in call for call in calls))

    def test_validation_failure_prevents_what_if(self):
        result, calls = self.run_helper(updates={"PREVIEW_TEST_SCENARIO": "validation-failed"})
        self.assertEqual(21, result.returncode)
        self.assertFalse(any("what-if" in call for call in calls))

    def test_what_if_failure_is_not_reported_as_success(self):
        result, _ = self.run_helper(updates={"PREVIEW_TEST_SCENARIO": "what-if-failed"})
        self.assertEqual(22, result.returncode)
        self.assertNotIn("succeeded", result.stdout.lower())

    def test_preview_performs_exact_read_and_validation_commands(self):
        result, calls = self.run_helper()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            [["account", "show"]] * 3 + [["group", "show"]]
            + [["deployment", "group", "validate"], ["deployment", "group", "what-if"]],
            [call[:3] if call[0] == "deployment" else call[:2] for call in calls],
        )
        for call in calls[3:]:
            self.assertEqual(self.env["AZURE_SUBSCRIPTION_ID"], call[call.index("--subscription") + 1])
        for call in calls[4:]:
            self.assertEqual(self.env["AZURE_RESOURCE_GROUP"], call[call.index("--resource-group") + 1])
            self.assertEqual("ProviderNoRbac", call[call.index("--validation-level") + 1])
        self.assertIn("ResourceIdOnly", calls[-1])
        self.assertIn("--no-pretty-print", calls[-1])

    def test_checkout_paths_with_spaces_remain_single_arguments(self):
        checkout = self.temp / "checkout with spaces"
        copied_helper = checkout / "scripts/validation/azure_deployment_preview.sh"
        copied_helper.parent.mkdir(parents=True)
        (checkout / "infra").mkdir()
        shutil.copy2(HELPER, copied_helper)
        for name in ("main.bicep", "main.bicepparam"):
            shutil.copy2(ROOT / "infra" / name, checkout / "infra" / name)
        result, calls = self.run_helper(helper=copied_helper)
        self.assertEqual(0, result.returncode, result.stderr)
        for call in calls[-2:]:
            self.assertEqual(str(checkout / "infra/main.bicep"), call[call.index("--template-file") + 1])
            self.assertEqual(str(checkout / "infra/main.bicepparam"), call[call.index("--parameters") + 1])


class WorkflowBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_only_manual_trigger_no_fallback_targets(self):
        trigger = self.workflow.split("\non:\n", 1)[1].split("\npermissions:\n", 1)[0]
        self.assertEqual(["workflow_dispatch"], re.findall(r"^  ([a-z_]+):$", trigger, re.MULTILINE))
        self.assertIn("default: true", trigger)
        self.assertEqual(3, trigger.count("required: true"))
        self.assertNotIn("||", self.workflow)
        self.assertNotIn("secrets.", self.workflow)

    def test_oidc_only_in_environment_gated_preview_after_validation(self):
        global_permissions = self.workflow.split("\npermissions:\n", 1)[1].split("\nconcurrency:\n", 1)[0]
        self.assertEqual("contents: read", global_permissions.strip())
        request, preview = self.workflow.split("\n  preview:\n", 1)
        self.assertNotIn("id-token:", request)
        self.assertNotIn("azure/login", request)
        self.assertNotIn("environment:", request)
        for guard in (
            "needs: validate-request", "environment: azure-dev", "id-token: write",
            "github.event_name == 'workflow_dispatch'", "github.ref == 'refs/heads/main'",
            "github.repository == 'Yolkster64/helios-platform'", "inputs.what_if",
        ):
            self.assertIn(guard, preview)
        self.assertLess(preview.index("check-binding"), preview.index("uses: azure/login@v2"))
        self.assertLess(preview.index("uses: azure/login@v2"), preview.index("azure_deployment_preview.sh preview"))
        self.assertEqual(2, self.workflow.count("ref: ${{ github.sha }}"))
        self.assertEqual(2, self.workflow.count("persist-credentials: false"))

    def test_no_apply_mutations_or_production_environment(self):
        combined = self.workflow + HELPER.read_text(encoding="utf-8")
        self.assertNotRegex(combined, r"az\s+(?:group\s+create|deployment\s+group\s+create|account\s+set|role\s+assignment|ad\s+|keyvault\s+secret)")
        self.assertNotIn("environment: production", self.workflow)
        self.assertNotIn("continue-on-error", self.workflow)
        self.assertNotIn("always()", self.workflow)
        self.assertIn("No deployment, resource-group creation", self.workflow)

    def test_pull_request_contract_job_has_no_azure_authority(self):
        text = CONTRACT_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("pull_request:", text)
        self.assertIn("contents: read", text)
        self.assertNotIn("id-token:", text)
        self.assertNotIn("azure/login", text)
        self.assertNotIn("environment:", text)
        self.assertNotIn("secrets.", text)
        self.assertIn("test_azure_deployment_guard.py", text)


if __name__ == "__main__":
    unittest.main()
