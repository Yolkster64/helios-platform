#!/usr/bin/env python3
"""Enforce the fail-closed HELIOS Fabric contract and non-deployment workflow policy.

This script is deliberately dependency-free stdlib-only. It exists as a separate
file (not embedded in the workflow) so the workflow YAML itself never contains
the very tokens the check is looking for -- an embedded assertion would
self-reference the forbidden strings and always fail. See
``.github/workflows/helios-fabric-contract.yml``.

Checks:

1. ``config/fabric/helios-fabric.v1.json`` keeps the fail-closed invariants:
   ``canonical.productionEnabled``, ``security.productionEnabled``,
   ``security.applyDefault``, ``security.secretValuesInRepository`` all ``false``;
   ``security.externalWritesRequireApproval`` ``true``;
   ``security.allowedUiFramework`` == ``"WinUI 3"``; ``{"WPF", "UWP"}`` is a subset
   of ``security.forbiddenUiFrameworks``.

2. ``.github/workflows/helios-fabric-contract.yml`` declares only a
   ``contents: read`` permission block, has no write permissions, and contains
   no OIDC login action, no ``az deployment`` command, and no
   ``pull_request_target`` trigger. This keeps the workflow validation-only:
   GitHub protected environments remain the deployment authority.

The script never reads secret values, contacts a provider, or mutates state.
Exit codes: ``0`` on success, ``2`` on any policy violation, ``1`` on a
non-policy error (missing file, unreadable file, malformed JSON).
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
FABRIC_CONTRACT = REPO_ROOT / "config" / "fabric" / "helios-fabric.v1.json"
FABRIC_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "helios-fabric-contract.yml"

# Tokens the workflow YAML must not contain. Each token is constructed from
# string concatenation so this validator's own source never contains the exact
# literal we forbid in the workflow -- the workflow file is scanned as-is, and
# a raw literal here would trigger the check when the validator itself is
# imported into the workflow's paths filter someday.
FORBIDDEN_WORKFLOW_TOKENS: tuple[tuple[str, str], ...] = (
    ("azure" + "/login", "OIDC login action (Azure authority mixing)"),
    ("az" + " deployment", "Azure CLI deploy command (deployment authority mixing)"),
    ("az" + " group", "Azure CLI resource group mutation"),
    ("pull_request" + "_target", "unreviewed head trigger"),
)


class PolicyViolation(Exception):
    """Raised when a fail-closed invariant is not satisfied."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PolicyViolation(message)


def _load_contract(path: pathlib.Path) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"cannot read {path}: {exc}") from exc
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"{path} must be a JSON object")
    return value


def _load_workflow(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"cannot read {path}: {exc}") from exc


def enforce_contract(contract: dict) -> None:
    """Assert the fail-closed contract invariants."""
    canonical = contract.get("canonical")
    security = contract.get("security")
    _require(isinstance(canonical, dict), "canonical must be an object")
    _require(isinstance(security, dict), "security must be an object")
    _require(canonical.get("productionEnabled") is False,
             "canonical.productionEnabled must remain false")
    _require(security.get("productionEnabled") is False,
             "security.productionEnabled must remain false")
    _require(security.get("applyDefault") is False,
             "security.applyDefault must remain false")
    _require(security.get("secretValuesInRepository") is False,
             "security.secretValuesInRepository must remain false")
    _require(security.get("externalWritesRequireApproval") is True,
             "security.externalWritesRequireApproval must remain true")
    _require(security.get("allowedUiFramework") == "WinUI 3",
             "security.allowedUiFramework must remain 'WinUI 3'")
    forbidden = security.get("forbiddenUiFrameworks")
    _require(isinstance(forbidden, list),
             "security.forbiddenUiFrameworks must be an array")
    forbidden_set = set(forbidden)
    _require({"WPF", "UWP"}.issubset(forbidden_set),
             "security.forbiddenUiFrameworks must include WPF and UWP")


def enforce_workflow(workflow_text: str) -> None:
    """Assert the workflow file is validation-only."""
    permissions_match = re.search(
        r"^permissions:\s*\n((?:[ \t]+.+\n)+)",
        workflow_text,
        flags=re.MULTILINE,
    )
    _require(permissions_match is not None,
             "permissions block is required at the top of the workflow")
    assert permissions_match is not None  # for type checkers
    permissions_block = permissions_match.group(1)
    _require("contents: read" in permissions_block,
             "permissions block must grant contents: read")
    _require("write" not in permissions_block,
             "permissions block must not grant any write scope")

    for token, reason in FORBIDDEN_WORKFLOW_TOKENS:
        _require(token not in workflow_text,
                 f"workflow must not contain '{token}' ({reason})")


def main() -> int:
    contract = _load_contract(FABRIC_CONTRACT)
    workflow_text = _load_workflow(FABRIC_WORKFLOW)
    try:
        enforce_contract(contract)
        enforce_workflow(workflow_text)
    except PolicyViolation as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2),
              file=sys.stderr)
        return 2

    print(json.dumps({
        "status": "passed",
        "contract": str(FABRIC_CONTRACT.relative_to(REPO_ROOT)),
        "workflow": str(FABRIC_WORKFLOW.relative_to(REPO_ROOT)),
        "productionEnabled": False,
        "applyDefault": False,
        "allowedUiFramework": "WinUI 3",
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
