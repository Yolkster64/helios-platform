#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

try:
    import jsonschema
except ModuleNotFoundError:  # pragma: no cover - surfaced in validate_schema_instance
    jsonschema = None

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = ROOT / "config/fabric/helios-fabric.v1.json"
DEFAULT_SCHEMA = ROOT / "config/schemas/helios-fabric.v1.schema.json"
EXPECTED_SOURCE_REPOSITORY = "Yolkster64/helios-platform"
EXPECTED_SOURCE_PR_NUMBER = 154
EXPECTED_REQUIRED_CHECKS = (
    "CI - Code Validation & Testing",
    "PR Pipeline",
    "Infra Validation",
)

SECRET_PATTERNS = (
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{20,}"),
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    re.compile(r"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9._-]{12,}\.[A-Za-z0-9._-]{12,}"),
    re.compile(r"https?://[^/\s:@]+:[^/\s@]+@"),
)


def load_json(path: pathlib.Path, label: str) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError as exc:
        raise ValueError(f"{label} not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} is not valid JSON: {path} ({exc})") from exc


def ensure(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def iter_strings(value: Any, path: str = "$"):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from iter_strings(item, f"{path}[{index}]")
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from iter_strings(item, f"{path}.{key}")


def format_json_path(path_parts: Any) -> str:
    rendered = "$"
    for part in path_parts:
        if isinstance(part, int):
            rendered += f"[{part}]"
        else:
            rendered += f".{part}"
    return rendered


def validate_schema_instance(contract: dict[str, Any], schema: dict[str, Any], errors: list[str]) -> None:
    if jsonschema is None:
        raise ValueError(
            "python package 'jsonschema' is required to validate "
            "config/schemas/helios-fabric.v1.schema.json"
        )
    try:
        validator = jsonschema.Draft202012Validator(schema)
    except jsonschema.exceptions.SchemaError as exc:
        raise ValueError(f"schema is invalid: {exc.message}") from exc

    schema_errors = sorted(
        validator.iter_errors(contract),
        key=lambda error: (list(error.absolute_path), error.message),
    )
    for error in schema_errors:
        errors.append(f"schema validation failed at {format_json_path(error.absolute_path)}: {error.message}")


def validate_contract(
    contract_path: pathlib.Path = DEFAULT_CONTRACT,
    schema_path: pathlib.Path = DEFAULT_SCHEMA,
) -> dict[str, Any]:
    contract = load_json(contract_path, "contract")
    schema = load_json(schema_path, "schema")
    errors: list[str] = []

    ensure(isinstance(contract, dict), "contract top level must be an object", errors)
    ensure(isinstance(schema, dict), "schema top level must be an object", errors)
    if errors:
        raise AssertionError("; ".join(errors))

    validate_schema_instance(contract, schema, errors)

    try:
        checklist_schema = schema["$defs"]["checklistItem"]
        status_enum = set(checklist_schema["properties"]["status"]["enum"])
        category_enum = set(checklist_schema["properties"]["category"]["enum"])
    except (KeyError, TypeError) as exc:
        raise ValueError(f"schema shape unexpected: missing {exc}") from exc

    ensure(contract.get("version") == 1, "version must be 1", errors)
    ensure(contract.get("migrationIssue") == "HC-029", "migrationIssue must be HC-029", errors)

    source_pr = contract.get("sourcePullRequest")
    ensure(isinstance(source_pr, dict), "sourcePullRequest must be an object", errors)
    if isinstance(source_pr, dict):
        ensure(
            source_pr.get("repository") == EXPECTED_SOURCE_REPOSITORY,
            f"sourcePullRequest.repository must be {EXPECTED_SOURCE_REPOSITORY}",
            errors,
        )
        ensure(
            source_pr.get("number") == EXPECTED_SOURCE_PR_NUMBER,
            f"sourcePullRequest.number must be {EXPECTED_SOURCE_PR_NUMBER}",
            errors,
        )
        merge_sha = source_pr.get("mergeSha")
        ensure(
            isinstance(merge_sha, str) and bool(re.fullmatch(r"[0-9a-f]{40}", merge_sha)),
            "sourcePullRequest.mergeSha must be a 40-character lowercase SHA-1 digest",
            errors,
        )
        required_checks = source_pr.get("requiredChecks")
        ensure(isinstance(required_checks, list), "sourcePullRequest.requiredChecks must be an array", errors)
        if isinstance(required_checks, list):
            names = [item.get("name") if isinstance(item, dict) else None for item in required_checks]
            ensure(
                names == list(EXPECTED_REQUIRED_CHECKS),
                "sourcePullRequest.requiredChecks must preserve the exact check names/order",
                errors,
            )

    safety = contract.get("safetyState")
    ensure(isinstance(safety, dict), "safetyState must be an object", errors)
    if isinstance(safety, dict):
        ensure(
            safety.get("productionEnabled") is False,
            "safetyState.productionEnabled must be false",
            errors,
        )
        ensure(safety.get("applyDefault") is False, "safetyState.applyDefault must be false", errors)
        ensure(
            safety.get("secretValuesInRepository") is False,
            "safetyState.secretValuesInRepository must be false",
            errors,
        )
        ensure(
            safety.get("activeUiFramework") == "WinUI 3",
            "safetyState.activeUiFramework must be WinUI 3",
            errors,
        )

    mcp = contract.get("mcp")
    ensure(isinstance(mcp, dict), "mcp must be an object", errors)
    if isinstance(mcp, dict):
        ensure(
            mcp.get("requiredTool") == "helios_fabric_plan_get",
            "mcp.requiredTool must be helios_fabric_plan_get",
            errors,
        )
        ensure(
            mcp.get("verificationMethod") == "stdio-jsonrpc-tools-list",
            "mcp.verificationMethod must be stdio-jsonrpc-tools-list",
            errors,
        )

    connectors = contract.get("connectors")
    ensure(isinstance(connectors, dict), "connectors must be an object", errors)
    if isinstance(connectors, dict):
        slack = connectors.get("slack")
        linear = connectors.get("linear")
        ensure(isinstance(slack, dict), "connectors.slack must be an object", errors)
        ensure(isinstance(linear, dict), "connectors.linear must be an object", errors)
        if isinstance(slack, dict):
            ensure(
                slack.get("workspaceId") == "T0BAFGSNY5P",
                "connectors.slack.workspaceId must remain T0BAFGSNY5P",
                errors,
            )
            ensure(
                slack.get("conversationId") == "D0BB80HRZFA",
                "connectors.slack.conversationId must remain D0BB80HRZFA",
                errors,
            )
        if isinstance(linear, dict):
            ensure(
                linear.get("teamKey") == "JOH",
                "connectors.linear.teamKey must remain JOH",
                errors,
            )
            ensure(
                isinstance(linear.get("issueKey"), str)
                and bool(re.fullmatch(r"[A-Z]+-[0-9]+", linear["issueKey"])),
                "connectors.linear.issueKey must match TEAM-123 style",
                errors,
            )

    azure = contract.get("azureActivation")
    ensure(isinstance(azure, dict), "azureActivation must be an object", errors)
    if isinstance(azure, dict):
        ensure(
            azure.get("renameTarget") == "Yolkster64/helios-control",
            "azureActivation.renameTarget must be Yolkster64/helios-control",
            errors,
        )
        what_if = azure.get("whatIf")
        ensure(isinstance(what_if, dict), "azureActivation.whatIf must be an object", errors)
        if isinstance(what_if, dict):
            ensure(what_if.get("apply") is False, "azureActivation.whatIf.apply must be false", errors)
            plan_hash = what_if.get("planHash")
            ensure(
                plan_hash is None or (isinstance(plan_hash, str) and bool(re.fullmatch(r"[0-9a-f]{64}", plan_hash))),
                "azureActivation.whatIf.planHash must be null or a lowercase SHA-256 hex digest",
                errors,
            )

    checklist = contract.get("checklist")
    ensure(isinstance(checklist, list) and len(checklist) > 0, "checklist must be a non-empty array", errors)
    ids: list[str] = []
    status_counts = {status: 0 for status in sorted(status_enum)}
    if isinstance(checklist, list):
        for index, item in enumerate(checklist):
            where = f"checklist[{index}]"
            ensure(isinstance(item, dict), f"{where} must be an object", errors)
            if not isinstance(item, dict):
                continue
            item_id = item.get("id")
            ensure(
                isinstance(item_id, str) and bool(re.fullmatch(r"[a-z0-9-]+", item_id)),
                f"{where}.id must be lowercase kebab-case",
                errors,
            )
            if isinstance(item_id, str):
                ids.append(item_id)

            status = item.get("status")
            ensure(status in status_enum, f"{where}.status must be one of {sorted(status_enum)}", errors)
            if status in status_counts:
                status_counts[status] += 1

            category = item.get("category")
            ensure(category in category_enum, f"{where}.category must be one of {sorted(category_enum)}", errors)

            ensure(isinstance(item.get("owner"), str) and item["owner"].strip(), f"{where}.owner must be non-empty", errors)
            ensure(isinstance(item.get("requiresRename"), bool), f"{where}.requiresRename must be boolean", errors)
            ensure(isinstance(item.get("externalAction"), bool), f"{where}.externalAction must be boolean", errors)

            depends_on = item.get("dependsOn")
            ensure(isinstance(depends_on, list), f"{where}.dependsOn must be an array", errors)
            if isinstance(depends_on, list):
                for dep_index, dependency in enumerate(depends_on):
                    ensure(
                        isinstance(dependency, str) and bool(re.fullmatch(r"[a-z0-9-]+", dependency)),
                        f"{where}.dependsOn[{dep_index}] must be lowercase kebab-case",
                        errors,
                    )

            if status == "done":
                ensure(
                    isinstance(item.get("receiptRef"), str) and item["receiptRef"].strip(),
                    f"{where} done items must include receiptRef",
                    errors,
                )

    if len(ids) != len(set(ids)):
        duplicates = sorted({item_id for item_id in ids if ids.count(item_id) > 1})
        errors.append(f"checklist IDs must be unique; duplicates: {duplicates}")

    id_set = set(ids)
    if isinstance(checklist, list):
        for index, item in enumerate(checklist):
            if not isinstance(item, dict):
                continue
            for dependency in item.get("dependsOn", []):
                if isinstance(dependency, str) and dependency not in id_set:
                    errors.append(f"checklist[{index}] dependsOn unknown id '{dependency}'")

    for path, value in iter_strings(contract):
        for pattern in SECRET_PATTERNS:
            if pattern.search(value):
                errors.append(f"{path} contains a secret-like value; store names/references only")
                break

    if errors:
        raise AssertionError("\n".join(errors))

    return {
        "status": "passed",
        "contractPath": str(contract_path.relative_to(ROOT)),
        "schemaPath": str(schema_path.relative_to(ROOT)),
        "checklistItems": len(ids),
        "statusCounts": status_counts,
        "blockedByRename": sum(
            1
            for item in checklist
            if isinstance(item, dict)
            and item.get("requiresRename") is True
            and item.get("status") != "done"
        ),
        "externalActions": sum(
            1
            for item in checklist
            if isinstance(item, dict) and item.get("externalAction") is True
        ),
    }


def main(argv: list[str]) -> int:
    contract_path = pathlib.Path(argv[1]) if len(argv) > 1 else DEFAULT_CONTRACT
    schema_path = pathlib.Path(argv[2]) if len(argv) > 2 else DEFAULT_SCHEMA
    result = validate_contract(contract_path, schema_path)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except (AssertionError, ValueError, OSError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
