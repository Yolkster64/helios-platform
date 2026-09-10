from __future__ import annotations

import json
import pathlib
import tempfile
import unittest

from scripts.validation import validate_ruleset_contexts as target

ROOT = pathlib.Path(__file__).resolve().parents[3]

# A ruleset gating main with one required check, and the workflow that produces it. Every
# case below changes ONE thing about this pair, so a failure names the thing that changed.
RULESET = {
    "name": "main",
    "target": "branch",
    "enforcement": "active",
    "conditions": {"ref_name": {"include": ["refs/heads/main"], "exclude": []}},
    "bypass_actors": [],
    "rules": [
        {
            "type": "required_status_checks",
            "parameters": {"required_status_checks": [{"context": "Build solution & run tests"}]},
        }
    ],
}

WORKFLOW = """
name: .NET Build & Test
on:
  pull_request:
    branches: [main]
jobs:
  build:
    name: Build solution & run tests
    runs-on: ubuntu-latest
    steps:
      - run: echo build
"""


class RulesetContextTests(unittest.TestCase):
    def _run(self, ruleset: dict, workflow: str):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "rulesets").mkdir()
            (root / "workflows").mkdir()
            (root / "rulesets" / "main.json").write_text(json.dumps(ruleset), encoding="utf-8")
            (root / "workflows" / "build.yml").write_text(workflow, encoding="utf-8")
            return target.validate(root / "rulesets", root / "workflows")

    def _expect_failure(self, ruleset: dict, workflow: str, expected: str) -> None:
        with self.assertRaises(target.ContextError) as caught:
            self._run(ruleset, workflow)
        self.assertIn(expected, str(caught.exception))

    def test_the_live_repository_is_safe_to_apply(self) -> None:
        """The real check, and the reason this file exists.

        `.github/rulesets/main.json` carries `bypass_actors: []`, so a required context that
        does not report on some pull request does not fail it - it strands it, unmergeable by
        anyone until an administrator edits the ruleset. Nothing has applied that ruleset yet,
        which means this trap is armed for the moment the owner installs the App.
        """
        result = target.validate()
        self.assertEqual(result["status"], "passed")
        self.assertTrue(result["requiredContexts"], "no required contexts were checked at all")

    def test_baseline_pair_passes(self) -> None:
        self.assertEqual(self._run(RULESET, WORKFLOW)["status"], "passed")

    def test_fails_when_no_job_produces_the_context(self) -> None:
        self._expect_failure(
            RULESET,
            WORKFLOW.replace("name: Build solution & run tests", "name: Build solution and test"),
            "produced by no job",
        )

    def test_fails_when_the_pull_request_trigger_carries_a_paths_filter(self) -> None:
        """The tempting change: it looks like a pure CI saving.

        GitHub treats a SKIPPED check as satisfied and an ABSENT one as pending, so skipping
        the work in a job-level `if:` is safe and filtering the trigger is not. Both
        dotnet-build.yml and infra-validate.yml carry a comment saying so; this is what makes
        the comment enforceable.
        """
        self._expect_failure(
            RULESET,
            WORKFLOW.replace(
                "  pull_request:\n    branches: [main]",
                "  pull_request:\n    branches: [main]\n    paths: ['src/**']",
            ),
            "carries `paths`",
        )

    def test_fails_when_the_pull_request_trigger_carries_paths_ignore(self) -> None:
        self._expect_failure(
            RULESET,
            WORKFLOW.replace(
                "  pull_request:\n    branches: [main]",
                "  pull_request:\n    branches: [main]\n    paths-ignore: ['docs/**']",
            ),
            "carries `paths-ignore`",
        )

    def test_fails_when_the_workflow_has_no_pull_request_trigger(self) -> None:
        self._expect_failure(
            RULESET,
            WORKFLOW.replace("  pull_request:\n    branches: [main]", "  push:\n    branches: [main]"),
            "no `pull_request` trigger",
        )

    def test_fails_when_the_trigger_branches_miss_the_branch_the_ruleset_gates(self) -> None:
        # The same strand in another dimension: the check reports on every PR it runs for, and
        # never runs for the branch that requires it.
        self._expect_failure(
            RULESET,
            WORKFLOW.replace("branches: [main]", "branches: [develop]"),
            "never reports on pull requests targeting",
        )

    def test_a_bare_pull_request_trigger_is_accepted(self) -> None:
        """`pull_request:` with no value parses as null, not as a missing key.

        infra-validate.yml is written exactly this way - the broadest, safest trigger there
        is - and a reader (or a checker) that tests for a dict rather than for the key reports
        it as having no trigger at all.
        """
        self.assertEqual(
            self._run(RULESET, WORKFLOW.replace("  pull_request:\n    branches: [main]", "  pull_request:"))[
                "status"
            ],
            "passed",
        )

    def test_a_matrix_job_is_not_claimed_as_a_producer(self) -> None:
        # A matrix job reports one check per combination, named `job (value)`, so the bare name
        # is not a context anything produces. Reported as unmatched rather than assumed present.
        self._expect_failure(
            RULESET,
            WORKFLOW.replace(
                "    runs-on: ubuntu-latest",
                "    strategy:\n      matrix:\n        os: [ubuntu-latest, windows-latest]\n    runs-on: ${{ matrix.os }}",
            ),
            "produced by no job",
        )

    def test_fails_on_required_checks_in_a_tag_ruleset(self) -> None:
        tag_ruleset = json.loads(json.dumps(RULESET))
        tag_ruleset["target"] = "tag"
        self._expect_failure(tag_ruleset, WORKFLOW, "only branch rulesets gate pull requests")

    def test_fails_on_an_empty_context(self) -> None:
        empty = json.loads(json.dumps(RULESET))
        empty["rules"][0]["parameters"]["required_status_checks"] = [{"context": "  "}]
        self._expect_failure(empty, WORKFLOW, "has no context")

    def test_a_ruleset_with_no_required_checks_is_fine(self) -> None:
        # Deletion and non-fast-forward rules gate nothing on a pull request, so there is
        # nothing here that can strand one.
        quiet = json.loads(json.dumps(RULESET))
        quiet["rules"] = [{"type": "deletion"}, {"type": "non_fast_forward"}]
        result = self._run(quiet, WORKFLOW)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["requiredContexts"], [])


if __name__ == "__main__":
    unittest.main()
