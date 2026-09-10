from __future__ import annotations

import pathlib
import tempfile
import unittest

from scripts.validation import validate_main_audit_wiring as target

ROOT = pathlib.Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/main-bypass-audit.yml"
QUALITY_WORKFLOW = ROOT / ".github/workflows/quality.yml"


class MainAuditWiringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow_text = WORKFLOW.read_text(encoding="utf-8")

    def _validate_mutation(self, before: str, after: str, expected_error: str) -> None:
        # The anchor must be UNIQUE, not merely present: replacing the first of several
        # occurrences lets a test go on passing while testing something other than what its
        # name claims. That happened once already, in test_validate_deploy_custody.py.
        occurrences = self.workflow_text.count(before)
        self.assertEqual(
            occurrences,
            1,
            f"mutation anchor must appear exactly once, found {occurrences}: {before!r}",
        )
        mutated = self.workflow_text.replace(before, after, 1)
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "main-bypass-audit.yml"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, expected_error):
                target.validate_workflow(path)

    def test_current_workflow_passes(self) -> None:
        result = target.validate_workflow(WORKFLOW)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["audited_branch"], "main")

    def test_quality_workflow_runs_the_contract_suite(self) -> None:
        target.validate_suite_runs_in_ci(QUALITY_WORKFLOW)

    def test_fails_when_the_push_trigger_is_dropped(self) -> None:
        # Left with only workflow_dispatch, the audit runs when a human remembers it - which
        # is never, and nothing goes red to say so.
        self._validate_mutation(
            "on:\n  push:\n    branches: [main]\n",
            "on:\n",
            "must trigger on push",
        )

    def test_fails_when_the_audited_branch_is_not_listed(self) -> None:
        self._validate_mutation(
            "    branches: [main]\n",
            "    branches: [develop]\n",
            "push.branches must include 'main'",
        )

    def test_fails_when_a_paths_filter_is_added(self) -> None:
        # The quiet killer: it reads as a CI saving and it exempts exactly the commits this
        # audit exists to look at.
        self._validate_mutation(
            "    branches: [main]\n",
            "    branches: [main]\n    paths: ['src/**']\n",
            "push.paths must not be set",
        )

    def test_fails_when_a_paths_ignore_filter_is_added(self) -> None:
        self._validate_mutation(
            "    branches: [main]\n",
            "    branches: [main]\n    paths-ignore: ['docs/**']\n",
            "push.paths-ignore must not be set",
        )

    def test_fails_when_the_auditor_is_no_longer_run(self) -> None:
        self._validate_mutation(
            "./scripts/github/audit-main-commit.ps1",
            "echo skipped",
            "no job runs scripts/github/audit-main-commit.ps1",
        )

    def test_fails_when_the_workflow_takes_write_permissions(self) -> None:
        # An auditor that can write is a defect on its own, and the offline suite asserts it
        # makes no mutating call. This keeps the TOKEN from contradicting that.
        self._validate_mutation(
            "  contents: read\n  checks: read",
            "  contents: write\n  checks: read",
            "workflow permissions must not hold contents",
        )

    def test_fails_when_a_job_takes_write_permissions(self) -> None:
        self._validate_mutation(
            "    timeout-minutes: 10\n",
            "    timeout-minutes: 10\n    permissions:\n      contents: write\n",
            "must not hold contents",
        )

    def test_fails_when_the_checkout_persists_credentials(self) -> None:
        # zizmor/artipacked: left at the default, actions/checkout writes the workflow token
        # into .git/config in the workspace. This audit reads files and calls the API with an
        # explicit GH_TOKEN, so the credential has no purpose there - and the one step that
        # would carry it off the runner (an artifact upload of the workspace) is one edit away.
        self._validate_mutation(
            "          persist-credentials: false\n",
            "          fetch-depth: 1\n",
            "must set persist-credentials: false",
        )

    def test_fails_when_the_checkout_takes_no_with_block(self) -> None:
        # Deleting the whole `with:` is the likelier regression than flipping the value, and
        # it restores the same default.
        text = self.workflow_text
        start = text.index("        with:\n")
        end = text.index("          persist-credentials: false\n") + len(
            "          persist-credentials: false\n"
        )
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "main-bypass-audit.yml"
            path.write_text(text[:start] + text[end:], encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "must set persist-credentials: false"):
                target.validate_workflow(path)

    def test_fails_when_the_workflow_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(AssertionError, "workflow missing"):
                target.validate_workflow(pathlib.Path(temp) / "main-bypass-audit.yml")

    def test_fails_when_the_workflow_declares_no_triggers(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "main-bypass-audit.yml"
            path.write_text("name: x\njobs:\n  a:\n    steps: []\n", encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "declares no triggers"):
                target.validate_workflow(path)

    def test_fails_when_quality_stops_running_the_suite(self) -> None:
        text = QUALITY_WORKFLOW.read_text(encoding="utf-8")
        occurrences = text.count("test_audit_main_commit.ps1")
        self.assertEqual(occurrences, 1, "the suite must be wired exactly once in quality.yml")
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "quality.yml"
            path.write_text(text.replace("test_audit_main_commit.ps1", "true", 1), encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, "must run scripts/verify/tests"):
                target.validate_suite_runs_in_ci(path)


if __name__ == "__main__":
    unittest.main()
