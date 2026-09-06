#!/usr/bin/env python3
"""Cross-check HELIOS Fabric collaboration, SharePoint, and DevOps activation contracts."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
FILES = {
    "fabric": ROOT / "config/fabric/helios-fabric.v1.json",
    "connections": ROOT / "config/connectors/helios-fabric.connections.v1.json",
    "roles": ROOT / "config/agents/helios-fabric-roles.v1.json",
    "providers": ROOT / "config/providers/helios-model-providers.v1.json",
    "devops": ROOT / "config/devops/azure-devops-wif.v1.json",
    "sharepoint": ROOT / "config/sharepoint/governance-publication.v1.json",
    "collaboration": ROOT / "config/collaboration/slack-linear-routing.v1.json",
}


def load(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.relative_to(ROOT)} must contain an object")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    data = {name: load(path) for name, path in FILES.items()}
    fabric = data["fabric"]
    devops = data["devops"]
    sharepoint = data["sharepoint"]
    collaboration = data["collaboration"]

    core = fabric["targetTopology"]["coreRepository"]
    gui = fabric["targetTopology"]["guiRepository"]
    require(core == "Yolkster64/helios-control", "core target mismatch")
    require(gui == "Yolkster64/helios-gui", "GUI target mismatch")
    require(devops["repositoryTarget"] == core, "Azure DevOps target mismatch")
    require(devops["role"] == "validation-and-evidence-mirror",
            "Azure DevOps authority is too broad")
    require(devops["permissions"]["deploymentAuthority"] is False,
            "Azure DevOps cannot be deployment authority")
    require(devops["pipeline"]["applyParameterExists"] is False,
            "Azure DevOps validation pipeline cannot expose apply")
    require(devops["pipeline"]["productionDeploymentExists"] is False,
            "Azure DevOps validation pipeline cannot deploy production")

    fabric_slack = fabric["collaboration"]["slack"]
    route_slack = collaboration["slack"]
    require(route_slack["workspaceId"] == fabric_slack["workspaceId"],
            "Slack workspace mismatch")
    require(route_slack["conversationId"] == fabric_slack["conversationId"],
            "Slack conversation mismatch")
    require(route_slack["fallbackAllowed"] is False,
            "Slack fallback must remain denied")
    require(collaboration["linear"]["coordinationIssue"] == "JOH-208",
            "Linear coordination issue mismatch")
    for value in collaboration["authorityBoundaries"].values():
        require(value is False, "collaboration authority boundary must be false")

    fabric_sp = fabric["collaboration"]["sharePoint"]
    require(sharepoint["hostname"] == fabric_sp["hostname"],
            "SharePoint hostname mismatch")
    require(sharepoint["sitePath"] == fabric_sp["sitePath"],
            "SharePoint site path mismatch")
    require(sharepoint["rootPath"] == fabric_sp["governancePath"],
            "SharePoint governance path mismatch")
    rules = sharepoint["publicationRules"]
    require(rules["deterministicManifestRequired"] is True,
            "SharePoint manifest must be deterministic")
    require(rules["sha256Required"] is True and rules["readbackVerificationRequired"] is True,
            "SharePoint hash/readback verification required")
    require(rules["secretValuePublicationAllowed"] is False,
            "SharePoint secret publication must be denied")

    pipeline = ROOT / devops["pipeline"]["entryPoint"]
    require(pipeline.is_file(), "Azure DevOps validation pipeline missing")
    pipeline_text = pipeline.read_text(encoding="utf-8")
    require("deployment group what-if" in pipeline_text,
            "Azure DevOps pipeline must run what-if")
    require("deployment group create" not in pipeline_text,
            "Azure DevOps validation mirror must not deploy")
    require("runDevelopmentWhatIf" in pipeline_text,
            "Azure DevOps what-if parameter missing")

    all_text = "\n".join(path.read_text(encoding="utf-8") for path in FILES.values())
    secret_patterns = [
        re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
        re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
        re.compile(r"\bghp_[A-Za-z0-9]{20,}"),
        re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}"),
    ]
    for pattern in secret_patterns:
        require(pattern.search(all_text) is None, "possible embedded credential")

    require(fabric["safety"]["productionEnabled"] is False,
            "production must remain disabled")
    require(fabric["safety"]["applyDefault"] is False,
            "apply must remain disabled by default")

    print(json.dumps({
        "status": "passed",
        "coreRepository": core,
        "guiRepository": gui,
        "azureDevOpsRole": devops["role"],
        "slackTarget": f"{route_slack['workspaceId']}/{route_slack['conversationId']}",
        "sharePointPath": sharepoint["rootPath"],
        "linearIssue": collaboration["linear"]["coordinationIssue"],
        "productionEnabled": fabric["safety"]["productionEnabled"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, TypeError, ValueError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
