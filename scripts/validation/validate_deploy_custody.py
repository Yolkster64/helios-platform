#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

try:
    import yaml
except ModuleNotFoundError as exc:  # pragma: no cover
    raise SystemExit(
        "PyYAML is required for deploy custody validation. Install with: pip install pyyaml==6.0.2"
    ) from exc

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/helios-deploy.yml"
CONTRACT_WORKFLOW = ROOT / ".github/workflows/deploy-hardening-contract.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def _require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def _find_step(steps: list[dict[str, Any]], name: str) -> dict[str, Any]:
    for step in steps:
        if step.get("name") == name:
            return step
    fail(f"missing workflow step: {name}")


def _ensure_action(step: dict[str, Any], expected_prefix: str, message: str) -> None:
    uses = str(step.get("uses", ""))
    _require(uses.startswith(expected_prefix + "@"), message)


def validate_workflow(path: pathlib.Path = WORKFLOW) -> dict[str, Any]:
    if not path.is_file():
        fail(f"deploy workflow missing: {path.relative_to(ROOT)}")
    try:
        workflow_path = str(path.relative_to(ROOT))
    except ValueError:
        workflow_path = str(path)

    text = path.read_text(encoding="utf-8")
    data = yaml.safe_load(text) or {}

    permissions = data.get("permissions") or {}
    _require(permissions.get("id-token") == "write", "deploy workflow must grant id-token: write")
    _require(permissions.get("contents") == "read", "deploy workflow must keep contents: read")

    jobs = data.get("jobs") or {}
    deploy_job = jobs.get("deploy")
    _require(isinstance(deploy_job, dict), "deploy workflow must define jobs.deploy")
    steps = deploy_job.get("steps") or []
    _require(isinstance(steps, list) and steps, "jobs.deploy.steps must be a non-empty list")

    creds = _find_step(steps, "Check Azure OIDC configuration")
    creds_run = str(creds.get("run", ""))
    _require("configured=false" in creds_run and "configured=true" in creds_run,
             "OIDC configuration step must explicitly emit configured=true/false")

    login = _find_step(steps, "Azure Login (OIDC)")
    _ensure_action(login, "azure/login", "deploy workflow must authenticate via azure/login")
    login_if = str(login.get("if", ""))
    _require("steps.creds.outputs.configured == 'true'" in login_if,
             "azure/login must be gated by the OIDC configuration guard")
    audience = (login.get("with") or {}).get("audience")
    _require(audience == "api://AzureADTokenExchange",
             "azure/login must pin audience api://AzureADTokenExchange")

    ensure_rg = _find_step(steps, "Ensure resource group for deploy")
    ensure_rg_if = str(ensure_rg.get("if", ""))
    expected_ensure_rg_if = "steps.creds.outputs.configured == 'true' && github.event_name == 'push'"
    _require(" ".join(ensure_rg_if.split()) == expected_ensure_rg_if,
             "resource-group creation must be limited to configured push deploys")

    what_if = _find_step(steps, "What-if (sanitized custody record)")
    what_if_if = str(what_if.get("if", ""))
    what_if_run = str(what_if.get("run", ""))
    _require("workflow_dispatch" in what_if_if and "inputs.what_if" in what_if_if,
             "what-if step must be restricted to workflow_dispatch + what_if=true")
    _require("--result-format ResourceIdOnly" in what_if_run,
             "what-if custody must use ResourceIdOnly output to avoid sensitive payload capture")
    _require("record-what-if-" in what_if_run,
             "what-if must write a dedicated custody record")
    _require("exit \"$rc\"" in what_if_run,
             "what-if step must preserve az CLI exit codes")

    deploy = _find_step(steps, "Deploy Helios Infra (sanitized custody record)")
    deploy_if = str(deploy.get("if", ""))
    deploy_run = str(deploy.get("run", ""))
    _require("github.event_name == 'push'" in deploy_if and "github.event_name == 'workflow_dispatch'" in deploy_if and "!inputs.what_if" in deploy_if,
             "deploy step must explicitly guard non-what-if deploys to workflow_dispatch")
    _require("record-deploy-" in deploy_run,
             "deploy step must write a dedicated custody record")
    _require("--query" in deploy_run and "provisioningState" in deploy_run,
             "deploy custody must capture allowlisted deployment fields only")
    _require("exit \"$rc\"" in deploy_run,
             "deploy step must preserve az CLI exit codes")

    seal = _find_step(steps, "Seal custody manifest")
    seal_if = str(seal.get("if", ""))
    seal_run = str(seal.get("run", ""))
    _require(
        "always()" in seal_if and "steps.custody.conclusion" in seal_if,
        "manifest sealing must run after custody setup, including preflight failures",
    )
    _require("sha256sum" in seal_run and "manifest.json" in seal_run,
             "manifest sealing must checksum records and include manifest")
    _require("templateDigestSha256" in text and "parametersDigestSha256" in text,
             "manifest must bind template and parameters digests")

    upload = _find_step(steps, "Upload plan/deploy custody")
    _ensure_action(upload, "actions/upload-artifact", "custody record must be uploaded via actions/upload-artifact")
    upload_if = str(upload.get("if", ""))
    upload_with = upload.get("with") or {}
    _require("always()" in upload_if,
             "custody upload must run with always() to retain failure evidence")
    _require("run_attempt" in str(upload_with.get("name", "")),
             "custody artifact name must include run_attempt for uniqueness")
    _require(str(upload_with.get("retention-days", "")).strip() != "",
             "custody artifact must set explicit retention-days")

    _require("AZURE_CLIENT_SECRET" not in text,
             "deploy workflow must not reference AZURE_CLIENT_SECRET")
    _require(not re.search(r"creds:\s*\$\{\{\s*secrets\.", text),
             "deploy workflow must not use stored creds JSON")
    _require("tee \"$record\"" not in text,
             "deploy workflow must not archive raw command output directly into custody records")

    return {
        "status": "passed",
        "workflow": workflow_path,
        "checks": [
            "oidc-guard",
            "audience-hardening",
            "no-stored-secret",
            "safe-custody-records",
            "manifest-and-upload",
        ],
    }


def validate_contract_workflow(path: pathlib.Path = CONTRACT_WORKFLOW) -> None:
    if not path.is_file():
        fail(f"contract workflow missing: {path.relative_to(ROOT)}")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    jobs = (data.get("jobs") or {}).get("contract") or {}
    steps = jobs.get("steps") or []
    runs = "\n".join(str(step.get("run", "")) for step in steps)
    _require("validate_deploy_custody.py" in runs,
             "contract workflow must run validate_deploy_custody.py")
    _require("unittest" in runs,
             "contract workflow must run deploy custody regression tests")


def main() -> int:
    result = validate_workflow(WORKFLOW)
    validate_contract_workflow(CONTRACT_WORKFLOW)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, KeyError, ValueError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
