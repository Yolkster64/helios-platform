#!/usr/bin/env python3
"""Prove the main-bypass audit is still wired to fire.

`.github/workflows/main-bypass-audit.yml` is the compensating control for a ruleset that is
not applied: it runs `scripts/github/audit-main-commit.ps1` on every push to main and reports
a commit that arrived without a merged pull request, or without its required contexts green.

That control has an unusual failure mode. A gate that breaks refuses, loudly. An AUDITOR that
breaks goes quiet, and quiet is exactly what a working auditor looks like on a clean
repository - so the day it stops running is the day nothing tells you. Four ordinary edits
disarm it without failing anything:

  - drop `push: branches: [main]` (it then only runs when a human dispatches it, i.e. never)
  - add a `paths:` filter (the tempting one: it reads as a CI saving, and it means the audit
    skips exactly the commits nobody looked at)
  - stop running the script, or rename it
  - grant the job write permissions it does not need

Comments in the workflow say all of this. Comments do not fail builds. This does.

Its sibling `validate_deploy_custody.py` does the same job for the deployment gate; the two
are deliberately alike, because the lesson that produced them is the same one.
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

try:
    import yaml
except ModuleNotFoundError as exc:  # pragma: no cover
    raise SystemExit(
        "PyYAML is required for main-audit wiring validation. Install with: pip install pyyaml==6.0.2"
    ) from exc

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/main-bypass-audit.yml"
AUDIT_SCRIPT = ROOT / "scripts/github/audit-main-commit.ps1"
SUITE = ROOT / "scripts/verify/tests/test_audit_main_commit.ps1"
QUALITY_WORKFLOW = ROOT / ".github/workflows/quality.yml"

AUDITED_BRANCH = "main"


def fail(message: str) -> None:
    raise AssertionError(message)


def _require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def _load(path: pathlib.Path) -> dict[Any, Any]:
    # dict[Any, Any], not dict[str, Any]: a workflow's top-level `on:` parses to the BOOLEAN
    # True under YAML 1.1, so the key type here is genuinely not str.
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _on_block(workflow: dict[Any, Any]) -> dict[str, Any]:
    for key in ("on", True):
        if key in workflow:
            block = workflow[key]
            return block if isinstance(block, dict) else {}
    fail("the audit workflow declares no triggers at all")
    return {}  # unreachable; keeps the type checker honest


def validate_workflow(path: pathlib.Path = WORKFLOW) -> dict[str, Any]:
    if not path.is_file():
        fail(f"main-bypass audit workflow missing: {path.name}")
    workflow = _load(path)
    triggers = _on_block(workflow)

    push = triggers.get("push")
    _require(
        "push" in triggers,
        "the audit must trigger on push: a commit reaches main by being pushed, and an audit "
        "that only runs on dispatch audits nothing",
    )
    _require(isinstance(push, dict), "push: must carry a branches list naming the audited branch")
    branches = [str(b) for b in (push.get("branches") or [])]
    _require(
        AUDITED_BRANCH in branches,
        f"push.branches must include {AUDITED_BRANCH!r}; found {branches}",
    )
    # A paths filter here is the quiet killer: it would skip precisely the pushes whose diff
    # nobody chose, which is the population this audit exists to examine.
    for key in ("paths", "paths-ignore"):
        _require(
            key not in push,
            f"push.{key} must not be set: it would silently exempt whole classes of commit "
            "from the only check that looks at what reached main",
        )

    jobs = workflow.get("jobs") or {}
    _require(isinstance(jobs, dict) and len(jobs) > 0, "the audit workflow defines no jobs")

    runs = []
    for name, job in jobs.items():
        _require(isinstance(job, dict), f"job {name} is not a mapping")
        permissions = job.get("permissions")
        if isinstance(permissions, dict):
            for scope, value in permissions.items():
                _require(
                    str(value) == "read",
                    f"job {name} must not hold {scope}: {value} - an auditor that can write is "
                    "a defect on its own",
                )
        for step in job.get("steps") or []:
            if isinstance(step, dict):
                runs.append(str(step.get("run", "")))
    combined = "\n".join(runs)

    top_permissions = workflow.get("permissions") or {}
    _require(isinstance(top_permissions, dict), "the workflow must declare permissions")
    for scope, value in top_permissions.items():
        _require(
            str(value) == "read",
            f"workflow permissions must not hold {scope}: {value} - every call this audit makes "
            "is a read, and its suite asserts it makes no mutating call",
        )

    _require(
        "audit-main-commit.ps1" in combined,
        "no job runs scripts/github/audit-main-commit.ps1; the workflow would report nothing",
    )
    _require(AUDIT_SCRIPT.is_file(), "scripts/github/audit-main-commit.ps1 is missing")
    _require(SUITE.is_file(), "scripts/verify/tests/test_audit_main_commit.ps1 is missing")

    return {
        "status": "passed",
        "workflow": path.name,
        "audited_branch": AUDITED_BRANCH,
        "checks": [
            "push-trigger-on-audited-branch",
            "no-path-filter",
            "read-only-permissions",
            "runs-the-auditor",
            "suite-present",
        ],
    }


def validate_suite_runs_in_ci(path: pathlib.Path = QUALITY_WORKFLOW) -> None:
    """The auditor's own contract suite must run somewhere a pull request sees it.

    Without this, the fifteen mutations the suite catches are caught only on the machine that
    happens to run it by hand.
    """
    if not path.is_file():
        fail(f"quality workflow missing: {path.name}")
    workflow = _load(path)
    runs = []
    for job in (workflow.get("jobs") or {}).values():
        if isinstance(job, dict):
            for step in job.get("steps") or []:
                if isinstance(step, dict):
                    runs.append(str(step.get("run", "")))
    _require(
        "test_audit_main_commit.ps1" in "\n".join(runs),
        "quality.yml must run scripts/verify/tests/test_audit_main_commit.ps1",
    )


def main() -> int:
    result = validate_workflow(WORKFLOW)
    validate_suite_runs_in_ci(QUALITY_WORKFLOW)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, KeyError, ValueError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
