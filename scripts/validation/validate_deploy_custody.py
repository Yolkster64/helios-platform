#!/usr/bin/env python3
"""Absorption E5 contract: Azure activation hardening on the deploy path.

Asserts the invariants the E5 epic extracts from upstream and adapts to
`.github/workflows/helios-deploy.yml` (docs/architecture/ABSORPTION_LEDGER.md E5):

  * OIDC guard patterns   — id-token:write is granted, contents stays read, and the
                            workflow skips gracefully when the AZURE_* identifiers
                            are unset instead of failing every push to main;
  * audience hardening    — azure/login pins audience api://AzureADTokenExchange,
                            matching the federated credential
                            (scripts/bootstrap/azure-oidc-setup.sh);
  * MI->KV custody         — no stored client secret enters the deploy path (the
                            anti-pattern this architecture eliminates);
  * immutable plan/deploy custody — the plan/apply is captured, SHA-256 sealed, and
                            retained as an immutable artifact for audit.

Text-based (stdlib only) so it runs anywhere the repo is checked out, like
scripts/validation/validate_yolkster_cutover.py.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/helios-deploy.yml"


def fail(message: str) -> None:
    raise AssertionError(message)


def require(text: str, pattern: str, message: str) -> None:
    if not re.search(pattern, text):
        fail(message)


def validate_workflow_text(text: str) -> list[str]:
    errors: list[str] = []

    def check(pattern: str, message: str) -> None:
        if not re.search(pattern, text):
            errors.append(message)

    # --- OIDC guard patterns ---------------------------------------------------
    check(r"id-token:\s*write",
          "deploy workflow must grant id-token: write to mint the OIDC token")
    check(r"contents:\s*read",
          "deploy workflow must keep contents: read (least privilege)")
    check(r"configured=false",
          "deploy workflow must skip gracefully (configured=false) when AZURE_* identifiers are unset")
    check(r"steps\.creds\.outputs\.configured\s*==\s*'true'",
          "deploy/login steps must be gated on the resolved OIDC configuration guard")

    # --- Audience hardening ----------------------------------------------------
    check(r"uses:\s*azure/login@v2",
          "deploy workflow must authenticate with azure/login@v2 (OIDC)")
    check(r"audience:\s*api://AzureADTokenExchange",
          "azure/login must pin audience api://AzureADTokenExchange (audience hardening)")

    # --- MI->KV custody: no stored client secret on the deploy path -----------
    if re.search(r"AZURE_CLIENT_SECRET", text):
        errors.append("deploy workflow must not reference AZURE_CLIENT_SECRET — OIDC is secretless")
    if re.search(r"creds:\s*\$\{\{\s*secrets\.", text):
        errors.append("deploy workflow must not use a stored creds JSON — OIDC is secretless")

    # --- Immutable plan/deploy custody ----------------------------------------
    check(r'--name\s+"helios-\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}"',
          "deploy workflow must name deployments with run_id + run_attempt for immutable custody")
    check(r"record-what-if-\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}",
          "what-if custody record must include run_id + run_attempt")
    check(r"record-deploy-\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}",
          "deploy custody record must include run_id + run_attempt")
    check(r"uses:\s*actions/upload-artifact@v4",
          "deploy workflow must upload the plan/deploy custody record as an artifact")
    check(r"retention-days:\s*90",
          "custody artifact must retain records for 90 days")
    check(r"name:\s*helios-deploy-custody-\$\{\{\s*github\.run_id\s*\}\}-\$\{\{\s*github\.run_attempt\s*\}\}",
          "custody artifact name must include run_id + run_attempt")
    check(r"sha256sum\b",
          "deploy workflow must SHA-256 the captured plan/deploy record (tamper-evident custody)")
    check(r"az deployment group what-if",
          "deploy workflow must run what-if for the plan custody path")
    check(r"az deployment group create",
          "deploy workflow must apply using az deployment group create")
    check(r"--parameters infra/main\.bicepparam",
          "deploy workflow must deploy the committed infra/main.bicepparam")

    return errors


def main() -> int:
    if not WORKFLOW.is_file():
        fail(f"deploy workflow missing: {WORKFLOW.relative_to(ROOT)}")
    text = WORKFLOW.read_text(encoding="utf-8")
    errors = validate_workflow_text(text)
    if errors:
        fail("; ".join(errors))

    print(json.dumps({
        "status": "passed",
        "workflow": str(WORKFLOW.relative_to(ROOT)),
        "checks": [
            "oidc-guard",
            "audience-hardening",
            "no-stored-secret",
            "immutable-plan-deploy-custody",
        ],
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
