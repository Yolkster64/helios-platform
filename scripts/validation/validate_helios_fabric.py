#!/usr/bin/env python3
"""Validate HELIOS Fabric setup contracts without contacting external systems."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
FABRIC = ROOT / "config/fabric/helios-fabric.v1.json"
CONNECTIONS = ROOT / "config/connectors/helios-fabric.connections.v1.json"
ROLES = ROOT / "config/agents/helios-fabric-roles.v1.json"
SETUP = ROOT / "docs/fabric/HELIOS_FABRIC_SETUP.md"
MATRIX = ROOT / "docs/fabric/FABRIC_ACTIVATION_MATRIX.md"


def load_object(path: pathlib.Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    fabric = load_object(FABRIC)
    connections = load_object(CONNECTIONS)
    roles = load_object(ROLES)

    require(fabric["currentAuthority"]["repository"] == "Yolkster64/helios-platform",
            "current repository authority mismatch")
    require(fabric["targetTopology"]["coreRepository"] == "Yolkster64/helios-control",
            "canonical core repository mismatch")
    require(fabric["targetTopology"]["guiRepository"] == "Yolkster64/helios-gui",
            "canonical GUI repository mismatch")

    desktop = fabric["desktop"]
    require(desktop["framework"] == "WinUI 3", "WinUI 3 must be binding")
    require(desktop["targetFramework"] == "net10.0-windows", ".NET 10 target required")
    require(desktop["xamlNamespace"] == "Microsoft.UI.Xaml", "Microsoft.UI.Xaml required")
    require(desktop["compositionNamespace"] == "Microsoft.UI.Composition",
            "Microsoft.UI.Composition required")
    require(desktop["wpfFallback"] is False and desktop["uwpFallback"] is False,
            "WPF/UWP fallbacks must remain disabled")

    safety = fabric["safety"]
    for name in (
        "productionEnabled",
        "applyDefault",
        "automaticRepositoryMerge",
        "automaticAzureDeployment",
        "automaticTenantConsent",
        "automaticRbacMutation",
        "automaticSecretWrite",
        "automaticDiskOrFirmwareMutation",
    ):
        require(safety[name] is False, f"{name} must remain false")
    require(safety["sourceArchivalRequiresProof"] is True,
            "source archival must require proof")

    slack = fabric["collaboration"]["slack"]
    require(slack["workspaceId"] == "T0BAFGSNY5P", "Slack workspace mismatch")
    require(slack["conversationId"] == "D0BB80HRZFA", "Slack conversation mismatch")
    require(slack["fallbackAllowed"] is False, "Slack fallback must be denied")

    subjects = fabric["identity"]["githubOidcSubjects"]
    for environment in ("dev", "test", "prod"):
        expected = f"repo:Yolkster64/helios-control:environment:azure-{environment}"
        require(subjects[environment] == expected, f"OIDC subject mismatch for {environment}")
    require(fabric["identity"]["clientSecretsAllowed"] is False,
            "client-secret CI must remain prohibited")
    require(fabric["identity"]["credentialReadbackAllowed"] is False,
            "credential readback must remain prohibited")

    connection_rows = connections.get("connections")
    require(isinstance(connection_rows, list) and connection_rows,
            "connection registry must be non-empty")
    ids = [str(row.get("id")) for row in connection_rows if isinstance(row, dict)]
    require(len(ids) == len(set(ids)), "connection IDs must be unique")
    required_connections = {
        "github-canonical-control",
        "github-native-gui",
        "slack-operations",
        "linear-work-graph",
        "sharepoint-governance",
        "azure-devops-validation",
        "azure-resource-control",
        "openai-provider",
        "anthropic-provider",
        "helios-local-mcp",
    }
    require(required_connections.issubset(set(ids)), "required connection missing")

    role_rows = roles.get("roles")
    require(isinstance(role_rows, list) and role_rows, "role registry must be non-empty")
    role_ids = [str(row.get("id")) for row in role_rows if isinstance(row, dict)]
    require(len(role_ids) == len(set(role_ids)), "agent role IDs must be unique")
    for row in role_rows:
        require(isinstance(row, dict), "role entry must be an object")
        require(bool(row.get("allowed")), f"role {row.get('id')} has no allowed operations")
        require(bool(row.get("denied")), f"role {row.get('id')} has no denied operations")

    setup_text = SETUP.read_text(encoding="utf-8")
    matrix_text = MATRIX.read_text(encoding="utf-8")
    for marker in (
        "Yolkster64/helios-control",
        "Yolkster64/helios-gui",
        "Microsoft.UI.Xaml",
        "Microsoft.UI.Composition",
        "T0BAFGSNY5P",
        "D0BB80HRZFA",
        "productionEnabled=false",
        "apply=false",
    ):
        require(marker in setup_text, f"setup runbook missing {marker}")
    require("Never an approval or deployment authority" in matrix_text,
            "activation matrix must preserve collaboration safety boundary")

    # Static secret-value check. Names and references are allowed; likely key/token
    # values are not. This intentionally errs on the side of failing closed.
    checked = [FABRIC, CONNECTIONS, ROLES, SETUP, MATRIX]
    secret_patterns = [
        re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
        re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
        re.compile(r"\bghp_[A-Za-z0-9]{20,}"),
        re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}"),
    ]
    for path in checked:
        text = path.read_text(encoding="utf-8")
        for pattern in secret_patterns:
            require(pattern.search(text) is None,
                    f"possible embedded secret in {path.relative_to(ROOT)}")

    print(json.dumps({
        "status": "passed",
        "fabricId": fabric["fabricId"],
        "currentRepository": fabric["currentAuthority"]["repository"],
        "targetCoreRepository": fabric["targetTopology"]["coreRepository"],
        "targetGuiRepository": fabric["targetTopology"]["guiRepository"],
        "connections": len(ids),
        "agentRoles": len(role_ids),
        "productionEnabled": safety["productionEnabled"],
        "applyDefault": safety["applyDefault"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, ValueError, TypeError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
