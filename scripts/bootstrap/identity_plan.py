#!/usr/bin/env python3
"""Prepare a deterministic, offline Azure identity handoff; never authenticate or apply.

Only allowlisted nonsecret identifiers are read. Values rejected by validation
never enter the returned object. A prepared plan verifies input syntax only:
account ownership, deployment protection and RBAC need live owner verification.
"""
from __future__ import annotations

import argparse
from collections.abc import Mapping
import hashlib
import json
import os
import re
from typing import Any
import uuid

SCHEMA_VERSION = 1
REPOSITORY = "Yolkster64/helios-platform"
ENVIRONMENT = "azure-dev"
GUID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
# Deliberately a conservative interoperable subset of Azure naming rules.
PATTERNS = {
    "AZURE_RESOURCE_GROUP": r"[A-Za-z0-9_().-]{1,89}[A-Za-z0-9_()-]|[A-Za-z0-9_()-]",
    "AZURE_LOCATION": r"[a-z][a-z0-9]{1,31}",
    "AZURE_KEY_VAULT_NAME": r"[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]",
    "HELIOS_RUNTIME_IDENTITY_NAME": r"[a-zA-Z0-9][a-zA-Z0-9_-]{2,127}",
    "AZURE_LEARNING_STORAGE_ACCOUNT_NAME": r"[a-z0-9]{3,24}",
    "HELIOS_GITHUB_REPOSITORY": r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+",
}
REQUIRED = (
    "AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_RESOURCE_GROUP",
    "AZURE_LOCATION", "AZURE_KEY_VAULT_NAME", "AZURE_CLIENT_ID",
)
OPTIONAL = (
    "HELIOS_RUNTIME_IDENTITY_NAME", "AZURE_LEARNING_STORAGE_ACCOUNT_NAME",
    "HELIOS_RUNTIME_PRINCIPAL_ID", "HELIOS_GITHUB_REPOSITORY", "HELIOS_AZURE_ENVIRONMENT",
)
ROLE_IDS = {
    "Contributor": "b24988ac-6180-42a0-ab88-20f7382dd24c",
    "Key Vault Secrets Officer": "b86a8fe4-44ce-4948-aee5-eccb2c155cd7",
    "Key Vault Secrets User": "4633458b-17de-408a-b874-0445c86b69e6",
    "Azure AI User": "53ca6127-db72-4b80-b1b0-d745d6d5456d",
    "Storage Table Data Contributor": "0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3",
}


def _valid(name: str, value: object) -> bool:
    if not isinstance(value, str) or not value or len(value) > 256:
        return False
    if name.endswith("_ID"):
        return bool(GUID.fullmatch(value)) and uuid.UUID(value).int != 0
    if name == "HELIOS_AZURE_ENVIRONMENT":
        return value == ENVIRONMENT
    if not re.fullmatch(PATTERNS[name], value):
        return False
    if name == "AZURE_KEY_VAULT_NAME":
        return "--" not in value
    if name == "HELIOS_GITHUB_REPOSITORY":
        return all(part not in {".", ".."} for part in value.split("/"))
    return True


def build_plan(environment: Mapping[str, str] | None = None) -> dict[str, Any]:
    """Return a pure-data plan. No file reads/writes, subprocesses, tokens or network."""
    source = os.environ if environment is None else environment
    values: dict[str, str] = {}
    missing: list[str] = []
    invalid: list[str] = []
    for name in REQUIRED + OPTIONAL:
        value = source.get(name)
        if value is None or value == "":
            if name in REQUIRED:
                missing.append(name)
        elif _valid(name, value):
            values[name] = value.lower() if name.endswith("_ID") else value
        else:
            invalid.append(name)

    # An explicitly invalid repository/environment is never silently used as a fallback.
    repo = values.get("HELIOS_GITHUB_REPOSITORY", REPOSITORY) if "HELIOS_GITHUB_REPOSITORY" not in invalid else None
    env = ENVIRONMENT if "HELIOS_AZURE_ENVIRONMENT" not in invalid else None
    subscription = values.get("AZURE_SUBSCRIPTION_ID")
    group = values.get("AZURE_RESOURCE_GROUP")
    vault = values.get("AZURE_KEY_VAULT_NAME")
    group_id = f"/subscriptions/{subscription}/resourceGroups/{group}" if subscription and group else None
    vault_id = f"{group_id}/providers/Microsoft.KeyVault/vaults/{vault}" if group_id and vault else None
    runtime_principal = values.get("HELIOS_RUNTIME_PRINCIPAL_ID")
    runtime_name = values.get("HELIOS_RUNTIME_IDENTITY_NAME")
    storage_name = values.get("AZURE_LEARNING_STORAGE_ACCOUNT_NAME")

    def role(name: str, scope: dict[str, Any], purpose: str) -> dict[str, Any]:
        return {"role": name, "roleDefinitionId": ROLE_IDS[name], "scope": scope, "purpose": purpose}

    # Values are argv elements, never embedded in a shell program. These commands
    # describe read-only checks and are not run by this helper or by startup.
    checks: list[dict[str, Any]] = []
    if subscription and group and vault and values.get("AZURE_TENANT_ID"):
        checks.append({
            "name": "verify-target-and-prepare-oidc-plan", "readOnly": True,
            "argv": ["bash", "scripts/bootstrap/azure-oidc-setup.sh", "--tenant", values["AZURE_TENANT_ID"],
                     "--subscription", subscription, "--resource-group", group, "--key-vault", vault,
                     "--repo", repo or REPOSITORY],
        })
    if repo and env:
        checks.append({"name": "inspect-protected-environment", "readOnly": True,
                       "argv": ["gh", "api", f"repos/{repo}/environments/{env}"]})
    parameters: dict[str, Any] = {"deployRuntimeIdentity": not bool(runtime_principal)}
    if runtime_name:
        parameters["runtimeManagedIdentityName"] = runtime_name
    if runtime_principal:
        parameters.update(principalId=runtime_principal, learningStorePrincipalId=runtime_principal)
    if vault:
        parameters["keyVaultName"] = vault
    if values.get("AZURE_LOCATION"):
        parameters["location"] = values["AZURE_LOCATION"]
    if storage_name:
        parameters["learningStorageAccountName"] = storage_name
    plan: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "status": "incomplete" if missing or invalid else "prepared",
        "mode": "offline-plan", "liveVerified": False, "applyEnabled": False,
        "missingInputs": missing, "invalidInputs": invalid,
        "target": {"tenantId": values.get("AZURE_TENANT_ID"), "subscriptionId": subscription,
                   "resourceGroup": group, "resourceGroupId": group_id, "location": values.get("AZURE_LOCATION"),
                   "keyVaultName": vault, "keyVaultId": vault_id},
        "github": {
            "repository": repo, "environment": env, "workflow": ".github/workflows/helios-deploy.yml",
            "ref": "refs/heads/main", "event": "workflow_dispatch",
            "permissions": {"contents": "read", "id-token": "write"},
            "federatedCredential": {
                "issuer": "https://token.actions.githubusercontent.com",
                "subject": f"repo:{repo}:environment:{env}" if repo and env else None,
                "audiences": ["api://AzureADTokenExchange"],
            },
            "environmentVariables": {name: values.get(name) for name in REQUIRED if name != "AZURE_KEY_VAULT_NAME"},
            "requiredProtection": {"requiredReviewers": True, "deploymentBranches": ["main"], "verified": False},
        },
        "deploymentIdentity": {
            "clientId": values.get("AZURE_CLIENT_ID"), "authentication": "github-oidc",
            "credentialCreation": False,
            "roles": [role("Contributor", {"resourceId": group_id}, "manage reviewed resources in the target group"),
                      role("Key Vault Secrets Officer", {"resourceId": vault_id}, "write only already-supplied provider keys")],
        },
        "runtimeIdentity": {
            "kind": "existing-principal" if runtime_principal else "proposed-user-assigned-managed-identity",
            "principalId": runtime_principal, "name": runtime_name,
            "principalIdOutput": None if runtime_principal else "runtimeManagedIdentityPrincipalId",
            "clientIdOutput": None if runtime_principal else "runtimeManagedIdentityClientId",
            "resourceIdOutput": None if runtime_principal else "runtimeManagedIdentityId",
            "authentication": "DefaultAzureCredential",
            "runtimeEnvironment": {"AZURE_CLIENT_ID": {"bicepOutput": "runtimeManagedIdentityClientId"},
                                   "AZURE_KEY_VAULT_URI": {"bicepOutput": "keyVaultUri"},
                                   "AZURE_LEARNING_TABLE_ENDPOINT": {"bicepOutput": "learningTableEndpoint"}},
            "roles": [role("Key Vault Secrets User", {"resourceId": vault_id}, "resolve configured provider secrets"),
                      role("Azure AI User", {"bicepOutput": "aiServicesAccountId"}, "Foundry account and project data plane"),
                      {**role("Storage Table Data Contributor", {"bicepOutput": "learningStorageAccountId"}, "persist AIHub learning outcomes"),
                       "condition": "deployLearningStorage=true"}],
            "hostAttachment": "required-separately; identity creation and grants do not attach it to an executor",
        },
        "bicep": {
            "authority": "infra/main.bicep", "parameters": parameters,
            "optionalParameters": {"deployLearningStorage": True},
            "parameterDocument": {"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
                                  "contentVersion": "1.0.0.0", "parameters": {key: {"value": value} for key, value in parameters.items()}},
            "terraformOwnership": "separate state and resource group; do not apply both engines to HELIOS resources",
            "executed": False,
        },
        "verification": checks if not invalid else [],
        "remainingGates": [
            "Verify live tenant/subscription, resource group and RBAC vault against the explicit target.",
            "Verify GitHub azure-dev reviewers and main-only deployment branches; OIDC alone does not enforce the branch.",
            "Review scoped Microsoft.Authorization/roleAssignments/write authority separately: Contributor and Secrets Officer cannot grant runtime RBAC.",
            "Review Bicep what-if and model capacity before an authorized apply; no cloud resources or model calls were made.",
            "Attach the managed identity to the chosen Azure runtime and set its client ID there; do not reuse the deployment client ID.",
            "Verify provider/Key Vault/learning access from that runtime; a proposed grant is not a runtime receipt.",
        ],
    }
    if runtime_principal:
        # An object ID does not identify its client ID or prove it is a managed identity.
        plan["runtimeIdentity"]["runtimeEnvironment"].pop("AZURE_CLIENT_ID")
    encoded = json.dumps(plan, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()
    plan["planSha256"] = hashlib.sha256(encoded).hexdigest()
    return plan


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="exit 2 for incomplete or invalid input")
    parser.add_argument("--json", action="store_true", help="JSON is the default output")
    args = parser.parse_args(argv)
    plan = build_plan()
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 2 if args.strict and plan["status"] != "prepared" else 0


if __name__ == "__main__":
    raise SystemExit(main())
