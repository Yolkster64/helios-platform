"""Run the real orchestrator against inert child reports; no accounts or APIs used."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
SCRIPT = Path("scripts/bootstrap/setup-everything.ps1")
CHILDREN = {
    "toolchain": "scripts/build/verify-readiness.ps1",
    "identity": "scripts/bootstrap/connect-account.ps1",
    "auth": "scripts/bootstrap/auth-doctor.ps1",
    "inventory": "scripts/setup/setup-all.ps1",
    "stack-smoke": "scripts/verify/stack-smoke.ps1",
    # PR #113 appends this step. Fixtures cover either chain without importing it.
    "rest-connect": "scripts/verify/rest-connect.ps1",
}


@unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 is required")
class SetupReadinessTests(unittest.TestCase):
    def run_chain(self, overrides=None, *, missing=(), flags=(), human=False):
        reports = {
            "toolchain": ({"ready": True}, 0),
            "identity": ({"lanes": [{"lane": "account", "state": "ready"}]}, 0),
            "auth": ({"lanes": [{"lane": "auth", "state": "ready"}]}, 0),
            "inventory": ({"ready": True, "components": [{"component": "tools", "status": "ready"}]}, 0),
            "stack-smoke": ({"lanes": [{"lane": "api", "state": "ok"}]}, 0),
            "rest-connect": ({"lanes": [{"lane": "github", "state": "ready"}]}, 0),
        }
        reports.update(overrides or {})
        with tempfile.TemporaryDirectory(prefix="helios-readiness-") as directory:
            root = Path(directory)
            target = root / SCRIPT
            target.parent.mkdir(parents=True)
            shutil.copyfile(REPO / SCRIPT, target)
            for name, relative in CHILDREN.items():
                if name in missing:
                    continue
                report, exit_code = reports[name]
                output = report if isinstance(report, str) else json.dumps(report)
                child = root / relative
                child.parent.mkdir(parents=True, exist_ok=True)
                child.write_text(
                    "param([switch]$Json, [switch]$Apply)\n"
                    f"Add-Content -LiteralPath (Join-Path $PSScriptRoot '../../calls.txt') -Value '{name}'\n"
                    f"Write-Output '{output.replace(chr(39), chr(39) * 2)}'\nexit {exit_code}\n",
                    encoding="utf-8",
                )
            args = ["pwsh", "-NoProfile", "-File", str(target)]
            if not human:
                args.append("-Json")
            result = subprocess.run(args + list(flags), capture_output=True, text=True, timeout=45)
            self.assertTrue(result.stdout.strip(), result.stderr)
            calls = (root / "calls.txt").read_text().splitlines()
            return result.returncode, result.stdout if human else json.loads(result.stdout), calls

    def test_affirmative_reports_are_ready(self):
        code, report, _ = self.run_chain(flags=("-RequireReady",))
        self.assertEqual(code, 0)
        self.assertTrue(report["executionSucceeded"])
        self.assertTrue(report["ready"])
        self.assertEqual(report["readinessIssues"], [])

    def test_successful_exit_cannot_hide_missing_build(self):
        code, report, _ = self.run_chain({"stack-smoke": ({"lanes": [{"lane": "api", "state": "build-missing"}]}, 0)})
        self.assertEqual(code, 0)  # Preserve the existing report-only contract.
        self.assertTrue(report["executionSucceeded"])
        self.assertFalse(report["ready"])
        self.assertIn("stack-smoke/api: build-missing", report["readinessIssues"])

    def test_require_ready_fails_on_unresolved_non_gating_auth(self):
        code, report, _ = self.run_chain({"auth": ({"lanes": [{"lane": "sharepoint", "state": "needs-owner", "gates": False}]}, 0)}, flags=("-RequireReady",))
        self.assertEqual(code, 2)
        self.assertFalse(report["ready"])

    def test_top_level_owner_actions_are_preserved_and_deduplicated(self):
        _, report, _ = self.run_chain({"auth": ({"ownerActions": ["configure destination", "configure destination"], "lanes": [{"lane": "auth", "state": "ready", "ownerAction": "configure destination"}]}, 0)})
        self.assertEqual(report["ownerActions"], ["configure destination"])
        self.assertFalse(report["ready"])

    def test_missing_soft_step_is_not_ready(self):
        code, report, _ = self.run_chain(missing=("stack-smoke",), flags=("-RequireReady",))
        self.assertEqual(code, 2)
        self.assertTrue(report["executionSucceeded"])
        self.assertFalse(report["ready"])

    def test_empty_report_has_no_readiness_evidence(self):
        _, report, _ = self.run_chain({"auth": ({}, 0)})
        self.assertFalse(report["ready"])
        self.assertIn("auth: no readiness evidence", report["readinessIssues"])

    def test_string_true_is_not_boolean_readiness(self):
        _, report, _ = self.run_chain({"toolchain": ({"ready": "true"}, 0)})
        self.assertFalse(report["ready"])

    def test_identity_mismatch_stops_before_apply(self):
        code, report, calls = self.run_chain({"identity": ({"lanes": [{"lane": "account", "state": "mismatch"}]}, 2)}, flags=("-Apply", "-RequireReady"))
        self.assertEqual(code, 2)
        self.assertEqual(calls, ["toolchain", "identity"])
        self.assertFalse(report["ready"])

    def test_invalid_identity_json_stops_before_apply(self):
        code, report, calls = self.run_chain({"identity": ("invalid JSON", 0)}, flags=("-Apply", "-RequireReady"))
        self.assertEqual(code, 1)
        self.assertEqual(calls, ["toolchain", "identity"])
        self.assertFalse(report["ready"])

    def test_json_array_is_not_an_identity_report(self):
        code, report, calls = self.run_chain({"identity": ('[{"ready": true}]', 0)}, flags=("-Apply",))
        self.assertEqual(code, 1)
        self.assertEqual(calls, ["toolchain", "identity"])
        self.assertFalse(report["ready"])

    def test_explicit_false_overrides_healthy_components(self):
        _, report, _ = self.run_chain({"inventory": ({"ready": False, "components": [{"component": "tools", "status": "ready"}]}, 0)})
        self.assertFalse(report["ready"])

    def test_unknown_lane_state_cannot_pass(self):
        _, report, _ = self.run_chain({"auth": ({"lanes": [{"lane": "auth", "state": "future-state"}]}, 0)})
        self.assertFalse(report["ready"])

    def test_human_output_does_not_announce_ready_with_missing_build(self):
        _, output, _ = self.run_chain({"stack-smoke": ({"lanes": [{"lane": "api", "state": "build-missing"}]}, 0)}, human=True)
        self.assertIn("Setup incomplete", output)
        self.assertNotIn("All reported checks are ready", output)


if __name__ == "__main__":
    # A directly invoked CI gate must fail when the runtime is absent, not pass
    # after silently skipping every regression check.
    if not shutil.which("pwsh"):
        raise SystemExit("PowerShell 7 is required; readiness tests were not run")
    unittest.main()
