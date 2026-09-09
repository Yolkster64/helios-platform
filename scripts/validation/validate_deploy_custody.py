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
RECORD_SCRIPT = ROOT / "scripts/validation/emit_deploy_custody_record.py"


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


def _ensure_permissions_are_read_only(job: dict[str, Any], message_prefix: str) -> None:
    permissions = job.get("permissions")
    if permissions is None:
        return
    _require(isinstance(permissions, dict), f"{message_prefix} permissions must be a mapping when present")
    for scope, value in permissions.items():
        _require(
            str(value) == "read",
            f"{message_prefix} permissions must not elevate {scope} beyond read",
        )


def validate_workflow(path: pathlib.Path = WORKFLOW) -> dict[str, Any]:
    if not path.is_file():
        fail(f"deploy workflow missing: {path.relative_to(ROOT)}")
    try:
        workflow_path = str(path.relative_to(ROOT))
    except ValueError:
        workflow_path = str(path)

    text = path.read_text(encoding="utf-8")
    data = yaml.safe_load(text) or {}

    triggers = data.get("on", data.get(True)) or {}
    _require(set(triggers) == {"workflow_dispatch"}, "deploy workflow must only allow workflow_dispatch")
    inputs = (triggers["workflow_dispatch"] or {}).get("inputs") or {}
    _require((inputs.get("what_if") or {}).get("default") is True,
             "what_if must default to true")
    _require((inputs.get("deploy_confirmed") or {}).get("default") is False,
             "deploy_confirmed must default to false")
    permissions = data.get("permissions") or {}
    _require(permissions == {"contents": "read"}, "workflow must keep contents: read and grant no global id-token")
    jobs = data.get("jobs") or {}
    deploy_job = jobs.get("deploy")
    _require(isinstance(deploy_job, dict), "deploy workflow must define jobs.deploy")
    _require(deploy_job.get("if") == "github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
             "deploy job must require manual dispatch from main")
    _require(deploy_job.get("environment") == "azure-dev", "deploy job must use protected azure-dev environment")
    _require(deploy_job.get("permissions") == {"contents": "read", "id-token": "write"},
             "only deploy job must grant id-token: write with contents: read")
    expected_variables = ("AZURE_CLIENT_ID", "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID",
                          "AZURE_RESOURCE_GROUP", "AZURE_LOCATION")
    for name in expected_variables:
        _require((deploy_job.get("env") or {}).get(name) == "${{ vars." + name + " }}",
                 "deploy target must require explicit variable " + name)
    steps = deploy_job.get("steps") or []
    _require(isinstance(steps, list) and steps, "jobs.deploy.steps must be a non-empty list")

    creds = _find_step(steps, "Check Azure OIDC configuration")
    creds_run = str(creds.get("run", ""))
    _require("configured=false" in creds_run and "configured=true" in creds_run,
             "OIDC configuration step must explicitly emit configured=true/false")

    _require("DEPLOY_CONFIRMED" in creds_run and "exit 1" in creds_run,
             "apply must reject absent explicit confirmation")
    for name in expected_variables:
        _require(name in creds_run, "OIDC guard must check " + name)

    login = _find_step(steps, "Azure Login (OIDC)")
    _ensure_action(login, "azure/login", "deploy workflow must authenticate via azure/login")
    login_if = str(login.get("if", ""))
    _require("steps.creds.outputs.configured == 'true'" in login_if,
             "azure/login must be gated by the OIDC configuration guard")
    audience = (login.get("with") or {}).get("audience")
    _require(audience == "api://AzureADTokenExchange",
             "azure/login must pin audience api://AzureADTokenExchange")

    _require("az group create" not in text, "workflow must never create a resource group")
    _require("secrets.AZURE_" not in text, "workflow must not use legacy secret fallbacks")
    target = _find_step(steps, "Verify Azure deployment target")
    target_run = str(target.get("run", ""))
    for evidence in ("az account show", "tenantId", '"Enabled"', "az group show", ".location", "expectedId"):
        _require(evidence in target_run, "target precheck must verify account, tenant, group and location")

    what_if = _find_step(steps, "What-if (sanitized custody record)")
    what_if_if = str(what_if.get("if", ""))
    what_if_run = str(what_if.get("run", ""))
    _require("workflow_dispatch" in what_if_if and "inputs.what_if" in what_if_if and "steps.target.outputs.verified == 'true'" in what_if_if,
             "what-if step must be restricted to workflow_dispatch + what_if=true")
    _require("--result-format ResourceIdOnly" in what_if_run,
             "what-if custody must use ResourceIdOnly output to avoid sensitive payload capture")
    _require("record-what-if-" in what_if_run,
             "what-if must write a dedicated custody record")
    _require(str(RECORD_SCRIPT.relative_to(ROOT)) in what_if_run,
             "what-if step must use the shared deploy custody record helper")
    _require("exit \"$rc\"" in what_if_run,
             "what-if step must preserve az CLI exit codes")
    _require("trap 'rm -f \"$stdout_file\" \"$stderr_file\"' EXIT" in what_if_run,
             "what-if step must clean up raw temp output files")

    deploy = _find_step(steps, "Deploy Helios Infra (sanitized custody record)")
    deploy_if = str(deploy.get("if", ""))
    deploy_run = str(deploy.get("run", ""))
    _require(deploy_if == "steps.creds.outputs.configured == 'true' && steps.target.outputs.verified == 'true' && github.event_name == 'workflow_dispatch' && !inputs.what_if && inputs.deploy_confirmed",
             "deploy step must require verified target, manual dispatch and explicit confirmation")
    _require("record-deploy-" in deploy_run,
             "deploy step must write a dedicated custody record")
    _require("--query" in deploy_run and "provisioningState" in deploy_run,
             "deploy custody must capture allowlisted deployment fields only")
    _require(str(RECORD_SCRIPT.relative_to(ROOT)) in deploy_run,
             "deploy step must use the shared deploy custody record helper")
    _require("exit \"$rc\"" in deploy_run,
             "deploy step must preserve az CLI exit codes")
    _require("trap 'rm -f \"$stdout_file\" \"$stderr_file\"' EXIT" in deploy_run,
             "deploy step must clean up raw temp output files")

    precheck = target
    precheck_run = str(precheck.get("run", ""))
    _require("record-target-precheck-" in precheck_run,
             "target precheck must retain failure evidence")
    _require(str(RECORD_SCRIPT.relative_to(ROOT)) in precheck_run,
             "target precheck must use the shared deploy custody record helper")

    seal = _find_step(steps, "Seal custody manifest")
    seal_if = str(seal.get("if", ""))
    seal_run = str(seal.get("run", ""))
    _require("always()" in seal_if,
             "manifest sealing must still run on failures to retain diagnostics")
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
    _require("stderrPreview" not in text,
             "deploy workflow must not keep regex-redacted stderrPreview fields")

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
    jobs_map = data.get("jobs") or {}
    contract_job = jobs_map.get("contract")
    _require(isinstance(contract_job, dict), "contract workflow must define jobs.contract")
    _ensure_permissions_are_read_only(contract_job, "contract job")
    steps = contract_job.get("steps") or []
    runs = "\n".join(str(step.get("run", "")) for step in steps)
    _require("validate_deploy_custody.py" in runs,
             "contract workflow must run validate_deploy_custody.py")
    _require("test_emit_deploy_custody_record" in runs,
             "contract workflow must run deploy custody helper tests")
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
