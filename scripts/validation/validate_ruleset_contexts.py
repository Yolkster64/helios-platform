#!/usr/bin/env python3
"""Every required status check in a ruleset must be a check that always reports.

A ruleset's `required_status_checks` names contexts by string. GitHub waits for each one
before it will merge, and `.github/rulesets/main.json` carries `bypass_actors: []` - nobody
can override. So a context that never REPORTS on some pull request does not fail that pull
request, it strands it: the check sits as "Expected" forever and the branch cannot merge, by
anyone, until a repository administrator edits the ruleset.

Two ways to reach that state, both of them ordinary-looking changes:

  * Rename a job, or a required context, so the two no longer match. The ruleset waits for a
    name nothing produces.
  * Add a `paths:` filter to a workflow's `pull_request` trigger. This is the tempting one -
    it looks like a pure CI saving - and it is why `dotnet-build.yml` and `infra-validate.yml`
    both carry a comment explaining that their pull_request trigger has no paths filter ON
    PURPOSE, with the skipping done by a `changes` job instead. GitHub treats a SKIPPED check
    as satisfied but an ABSENT one as pending, so the job-level skip is safe and the
    workflow-level filter is not.

Those comments are the only thing holding the contract today, and a comment does not fail a
build. This does. It is deliberately credential-free and offline: it reads the checked-in
rulesets and workflows, so it runs on every pull request long before anyone has the
administrator credential that would apply a ruleset for real.

Usage:
    python3 scripts/validation/validate_ruleset_contexts.py            # exit 0 / 1
    python3 scripts/validation/validate_ruleset_contexts.py --json     # machine-readable

Exit codes: 0 = every required context always reports; 1 = at least one can strand a merge.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

try:
    import yaml
except ModuleNotFoundError as exc:  # pragma: no cover - CI installs it
    raise SystemExit(
        "PyYAML is required for ruleset context validation. Install with: pip install pyyaml==6.0.2"
    ) from exc

ROOT = pathlib.Path(__file__).resolve().parents[2]
RULESET_DIR = ROOT / ".github/rulesets"
WORKFLOW_DIR = ROOT / ".github/workflows"


class ContextError(ValueError):
    """A required context that cannot be relied on to report."""


def _load_yaml(path: pathlib.Path) -> dict[Any, Any]:
    # dict[Any, Any], not dict[str, Any]: a workflow's top-level `on:` parses to the BOOLEAN
    # True under YAML 1.1, so the key type here is genuinely not str. Annotating it as str
    # would be a lie that a type checker rightly rejects at the lookup below.
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def _on_block(workflow: dict[Any, Any]) -> dict[str, Any]:
    # `on:` is the YAML 1.1 boolean True after parsing, which is the single most common way to
    # read a workflow's triggers and get nothing back.
    raw = workflow.get(True, workflow.get("on"))
    if raw is None:
        return {}
    if isinstance(raw, str):
        return {raw: None}
    if isinstance(raw, list):
        return {event: None for event in raw}
    return raw if isinstance(raw, dict) else {}


def _job_context_names(workflow: dict[Any, Any]) -> dict[str, str]:
    """Check-run name -> job id, for the jobs this workflow reports.

    A job reports under its `name:` when it has one and its id otherwise. Matrix jobs report
    one check per combination (`name (value)`) and reusable-workflow callers report
    `caller / called`, so neither is claimed here: a context that resolves to one of those is
    reported as unmatched rather than quietly assumed present.
    """
    names: dict[str, str] = {}
    for job_id, job in (workflow.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        if "strategy" in job or "uses" in job:
            continue
        name = job.get("name")
        names[str(name) if name else str(job_id)] = str(job_id)
    return names


def _pull_request_trigger(on_block: dict[str, Any]) -> tuple[bool, dict[str, Any]]:
    """(declared, options). `pull_request:` with no value is null, not missing."""
    if "pull_request" not in on_block:
        return False, {}
    options = on_block.get("pull_request")
    return True, options if isinstance(options, dict) else {}


def _ruleset_branches(ruleset: dict[str, Any]) -> list[str]:
    include = ((ruleset.get("conditions") or {}).get("ref_name") or {}).get("include") or []
    return [str(ref).removeprefix("refs/heads/") for ref in include]


def validate(
    ruleset_dir: pathlib.Path = RULESET_DIR,
    workflow_dir: pathlib.Path = WORKFLOW_DIR,
) -> dict[str, Any]:
    workflows = sorted(
        [p for p in workflow_dir.glob("*.yml")] + [p for p in workflow_dir.glob("*.yaml")]
    )
    if not workflows:
        raise ContextError(f"no workflows found under {workflow_dir}")

    # context name -> [(workflow path, job id)]
    producers: dict[str, list[tuple[pathlib.Path, str]]] = {}
    parsed: dict[pathlib.Path, dict[Any, Any]] = {}
    for path in workflows:
        workflow = _load_yaml(path)
        parsed[path] = workflow
        for context, job_id in _job_context_names(workflow).items():
            producers.setdefault(context, []).append((path, job_id))

    problems: list[str] = []
    checked: list[dict[str, Any]] = []

    rulesets = sorted(ruleset_dir.glob("*.json"))
    if not rulesets:
        raise ContextError(f"no rulesets found under {ruleset_dir}")

    for ruleset_path in rulesets:
        try:
            ruleset = json.loads(ruleset_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ContextError(f"{ruleset_path.name} is not valid JSON: {exc}") from exc
        # A tag ruleset has no pull requests at all, so required status checks would be
        # meaningless there; the shape check below still applies to whatever it does declare.
        target = str(ruleset.get("target", "branch"))
        branches = _ruleset_branches(ruleset)

        for rule in ruleset.get("rules") or []:
            if not isinstance(rule, dict) or rule.get("type") != "required_status_checks":
                continue
            if target != "branch":
                problems.append(
                    f"{ruleset_path.name}: required_status_checks on a `{target}` ruleset - "
                    "only branch rulesets gate pull requests"
                )
                continue
            contexts = ((rule.get("parameters") or {}).get("required_status_checks")) or []
            for entry in contexts:
                context = str((entry or {}).get("context", "")).strip()
                if not context:
                    problems.append(f"{ruleset_path.name}: a required status check has no context")
                    continue
                found = producers.get(context)
                if not found:
                    problems.append(
                        f"{ruleset_path.name}: required context '{context}' is produced by no job "
                        "in .github/workflows - a required check that never reports strands every "
                        "pull request on this branch, and bypass_actors is empty"
                    )
                    continue
                for path, job_id in found:
                    on_block = _on_block(parsed[path])
                    declared, options = _pull_request_trigger(on_block)
                    where = f"{ruleset_path.name}: required context '{context}' ({path.name})"
                    if not declared:
                        problems.append(
                            f"{where} - its workflow has no `pull_request` trigger, so the check "
                            "never reports on a pull request"
                        )
                        continue
                    for filter_key in ("paths", "paths-ignore"):
                        if filter_key in options:
                            problems.append(
                                f"{where} - its `pull_request` trigger carries `{filter_key}`, so "
                                "the check is ABSENT (not skipped) on a diff that misses the "
                                "filter. Skip the WORK in a job-level `if:` instead; GitHub "
                                "treats a skipped check as satisfied and a missing one as pending"
                            )
                    trigger_branches = options.get("branches")
                    if trigger_branches is not None:
                        missing = [b for b in branches if b not in [str(x) for x in trigger_branches]]
                        if missing:
                            problems.append(
                                f"{where} - its `pull_request` trigger is limited to "
                                f"{list(trigger_branches)}, so the check never reports on pull "
                                f"requests targeting {missing}, which this ruleset gates"
                            )
                    checked.append(
                        {
                            "ruleset": ruleset_path.name,
                            "context": context,
                            "workflow": path.name,
                            "job": job_id,
                        }
                    )

    if problems:
        raise ContextError("; ".join(problems))

    return {
        "status": "passed",
        "rulesets": [p.name for p in rulesets],
        "requiredContexts": checked,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    args = parser.parse_args()
    try:
        result = validate()
    except ContextError as exc:
        if args.json:
            print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        else:
            print("ruleset-contexts: FAILED", file=sys.stderr)
            for problem in str(exc).split("; "):
                print(f"  - {problem}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        by_ruleset: dict[str, list[str]] = {}
        for row in result["requiredContexts"]:
            by_ruleset.setdefault(row["ruleset"], []).append(f"{row['context']} <- {row['workflow']}")
        for ruleset, rows in by_ruleset.items():
            print(f"{ruleset}: {len(rows)} required context(s), each reporting on every pull request")
            for row in rows:
                print(f"  OK  {row}")
        if not by_ruleset:
            print("ruleset-contexts: no required status checks declared; nothing can strand.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
