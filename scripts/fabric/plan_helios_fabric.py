#!/usr/bin/env python3
"""Validate and render the HELIOS Fabric setup plan.

The planner is deliberately local, deterministic, and dependency-free. It reads only the
machine-readable Fabric contract, reports whether named environment references are
present, and emits a sanitized phase graph. It never reads or prints credential values,
contacts a provider, mutates an external system, or authorizes deployment.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
from collections import deque
from typing import Any

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPO_ROOT / "config" / "fabric" / "helios-fabric.v1.json"
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")
PHASE_ID = re.compile(r"^F[0-9]{2}$")
INTEGRATION_ID = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SECRET_PREFIXES = (
    "sk-",
    "sk-proj-",
    "ghp_",
    "github_pat_",
    "xoxb-",
    "xoxp-",
    "lin_api_",
)


class ContractError(ValueError):
    """Raised when the Fabric contract violates a fail-closed invariant."""


def _read_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ContractError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ContractError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ContractError("Fabric configuration must be a JSON object")
    return value


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def _all_strings(value: Any, field: str) -> list[str]:
    _require(isinstance(value, list), f"{field} must be an array")
    _require(all(isinstance(item, str) and item for item in value),
             f"{field} must contain non-empty strings")
    return list(value)


def _walk_strings(value: Any):
    if isinstance(value, dict):
        for child in value.values():
            yield from _walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk_strings(child)
    elif isinstance(value, str):
        yield value


def _validate_no_secret_values(config: dict[str, Any]) -> None:
    for value in _walk_strings(config):
        lowered = value.lower()
        if any(lowered.startswith(prefix) for prefix in SECRET_PREFIXES):
            raise ContractError("Fabric contract appears to contain a credential value")
        if "-----begin private key-----" in lowered:
            raise ContractError("Fabric contract contains private-key material")


def _validate_integrations(config: dict[str, Any]) -> tuple[list[dict[str, Any]], set[str]]:
    integrations = config.get("integrations")
    _require(isinstance(integrations, list) and integrations,
             "integrations must be a non-empty array")
    ids: set[str] = set()
    for index, integration in enumerate(integrations):
        field = f"integrations[{index}]"
        _require(isinstance(integration, dict), f"{field} must be an object")
        integration_id = integration.get("id")
        _require(isinstance(integration_id, str) and INTEGRATION_ID.fullmatch(integration_id) is not None,
                 f"{field}.id is invalid")
        _require(integration_id not in ids, f"duplicate integration id {integration_id}")
        ids.add(integration_id)
        _require(isinstance(integration.get("role"), str) and integration["role"],
                 f"{field}.role is required")
        _require(isinstance(integration.get("authority"), str) and integration["authority"],
                 f"{field}.authority is required")
        _require(integration.get("desiredState") in {
            "connected", "configured", "admin-binding-required",
            "connection-required", "disabled"
        }, f"{field}.desiredState is invalid")
        required_env = _all_strings(integration.get("requiredEnv", []), f"{field}.requiredEnv")
        _require(len(required_env) == len(set(required_env)),
                 f"{field}.requiredEnv contains duplicates")
        for env_name in required_env:
            _require(ENV_NAME.fullmatch(env_name) is not None,
                     f"{field}.requiredEnv contains invalid name {env_name!r}")
        health = _all_strings(integration.get("healthChecks"), f"{field}.healthChecks")
        _require(bool(health), f"{field}.healthChecks must not be empty")
        allowed = set(_all_strings(integration.get("allowed", []), f"{field}.allowed"))
        denied = set(_all_strings(integration.get("denied"), f"{field}.denied"))
        _require(bool(denied), f"{field}.denied must not be empty")
        overlap = allowed & denied
        _require(not overlap,
                 f"{field} has operations in both allowed and denied: {sorted(overlap)}")
    return integrations, ids


def _topological_order(phases: list[dict[str, Any]], ids: set[str]) -> list[str]:
    incoming: dict[str, int] = {phase_id: 0 for phase_id in ids}
    outgoing: dict[str, list[str]] = {phase_id: [] for phase_id in ids}
    for phase in phases:
        phase_id = phase["id"]
        for dependency in phase["dependsOn"]:
            incoming[phase_id] += 1
            outgoing[dependency].append(phase_id)
    ready = deque(sorted(phase_id for phase_id, count in incoming.items() if count == 0))
    ordered: list[str] = []
    while ready:
        phase_id = ready.popleft()
        ordered.append(phase_id)
        for child in sorted(outgoing[phase_id]):
            incoming[child] -= 1
            if incoming[child] == 0:
                ready.append(child)
    _require(len(ordered) == len(ids), "phase dependency graph contains a cycle")
    return ordered


def _validate_phases(config: dict[str, Any], integration_ids: set[str]) -> tuple[list[dict[str, Any]], list[str]]:
    phases = config.get("phases")
    _require(isinstance(phases, list) and phases, "phases must be a non-empty array")
    ids: set[str] = set()
    for index, phase in enumerate(phases):
        field = f"phases[{index}]"
        _require(isinstance(phase, dict), f"{field} must be an object")
        phase_id = phase.get("id")
        _require(isinstance(phase_id, str) and PHASE_ID.fullmatch(phase_id) is not None,
                 f"{field}.id is invalid")
        _require(phase_id not in ids, f"duplicate phase id {phase_id}")
        ids.add(phase_id)
        _require(isinstance(phase.get("title"), str) and phase["title"],
                 f"{field}.title is required")
        _require(phase.get("execution") in {"automated", "operator", "administrator"},
                 f"{field}.execution is invalid")
        _require(isinstance(phase.get("mutatesExternalState"), bool),
                 f"{field}.mutatesExternalState must be boolean")
        _require(phase.get("requiredApproval") in {
            "none", "operator", "repository-admin", "tenant-admin", "production-owner"
        }, f"{field}.requiredApproval is invalid")
        if phase["mutatesExternalState"]:
            _require(phase["requiredApproval"] != "none",
                     f"{field} mutates external state but has no approval")
        _require(bool(_all_strings(phase.get("outputs"), f"{field}.outputs")),
                 f"{field}.outputs must not be empty")

    for index, phase in enumerate(phases):
        field = f"phases[{index}]"
        dependencies = _all_strings(phase.get("dependsOn", []), f"{field}.dependsOn")
        required_integrations = _all_strings(
            phase.get("requiredIntegrations", []), f"{field}.requiredIntegrations")
        _require(phase["id"] not in dependencies,
                 f"{field} cannot depend on itself")
        missing_phases = sorted(set(dependencies) - ids)
        _require(not missing_phases,
                 f"{field} references missing phases {missing_phases}")
        missing_integrations = sorted(set(required_integrations) - integration_ids)
        _require(not missing_integrations,
                 f"{field} references missing integrations {missing_integrations}")

    return phases, _topological_order(phases, ids)


def validate(config: dict[str, Any]) -> dict[str, Any]:
    _require(config.get("schemaVersion") == "1.0", "schemaVersion must be 1.0")
    canonical = config.get("canonical")
    _require(isinstance(canonical, dict), "canonical must be an object")
    _require(canonical.get("currentRepository") == "Yolkster64/helios-platform",
             "currentRepository must remain the live pre-rename repository")
    _require(canonical.get("targetRepository") == "Yolkster64/helios-control",
             "targetRepository must be Yolkster64/helios-control")
    _require(canonical.get("guiRepository") == "Yolkster64/helios-gui",
             "guiRepository must be Yolkster64/helios-gui")
    _require(canonical.get("renameMode") == "in-place",
             "the core cutover must remain an in-place rename")
    _require(canonical.get("productionEnabled") is False,
             "canonical.productionEnabled must remain false")

    security = config.get("security")
    _require(isinstance(security, dict), "security must be an object")
    _require(security.get("applyDefault") is False, "applyDefault must remain false")
    _require(security.get("productionEnabled") is False,
             "security.productionEnabled must remain false")
    _require(security.get("secretValuesInRepository") is False,
             "secretValuesInRepository must remain false")
    _require(security.get("externalWritesRequireApproval") is True,
             "externalWritesRequireApproval must remain true")
    _require(security.get("allowedUiFramework") == "WinUI 3",
             "WinUI 3 must be the only active desktop framework")
    forbidden_ui = set(_all_strings(
        security.get("forbiddenUiFrameworks", []), "security.forbiddenUiFrameworks"))
    _require({"WPF", "UWP"}.issubset(forbidden_ui),
             "WPF and UWP must remain forbidden in active product code")

    authorities = config.get("authorities")
    _require(isinstance(authorities, dict), "authorities must be an object")
    for name in ("source", "deployment", "workGraph", "operations",
                 "governance", "validationMirror", "secrets"):
        _require(isinstance(authorities.get(name), str) and authorities[name],
                 f"authorities.{name} is required")

    integrations, integration_ids = _validate_integrations(config)
    phases, order = _validate_phases(config, integration_ids)
    evidence = config.get("evidence")
    _require(isinstance(evidence, dict), "evidence must be an object")
    required_fields = set(_all_strings(evidence.get("requiredFields"),
                                       "evidence.requiredFields"))
    _require({"eventId", "correlationId", "sourceSha", "result", "receiptUri"}
             .issubset(required_fields),
             "evidence.requiredFields lacks required trace fields")
    _require(isinstance(evidence.get("retentionDays"), int)
             and evidence["retentionDays"] >= 30,
             "evidence.retentionDays must be at least 30")
    _validate_no_secret_values(config)

    return {
        "schemaVersion": config["schemaVersion"],
        "integrations": len(integrations),
        "phases": len(phases),
        "topologicalOrder": order,
        "productionEnabled": False,
        "applyDefault": False,
    }


def _integration_plan(integration: dict[str, Any], inspect_env: bool) -> dict[str, Any]:
    env_names = integration["requiredEnv"]
    present = [name for name in env_names if inspect_env and name in os.environ]
    missing = [name for name in env_names if name not in present]
    desired = integration["desiredState"]
    if desired == "disabled":
        readiness = "disabled"
    elif desired in {"admin-binding-required", "connection-required"}:
        readiness = desired
    elif inspect_env and missing:
        readiness = "environment-reference-missing"
    elif env_names and not inspect_env:
        readiness = "environment-not-inspected"
    else:
        readiness = "contract-ready"
    return {
        "id": integration["id"],
        "role": integration["role"],
        "authority": integration["authority"],
        "desiredState": desired,
        "readiness": readiness,
        "requiredEnvNames": env_names,
        "presentEnvNames": present,
        "missingEnvNames": missing if inspect_env else [],
        "healthChecks": integration["healthChecks"],
        "target": integration.get("target", {}),
    }


def build_plan(config: dict[str, Any], inspect_env: bool) -> dict[str, Any]:
    validation = validate(config)
    integration_plans = {
        item["id"]: _integration_plan(item, inspect_env)
        for item in config["integrations"]
    }
    phases_by_id = {phase["id"]: phase for phase in config["phases"]}
    phase_plans: list[dict[str, Any]] = []
    completed_for_planning: set[str] = set()
    for phase_id in validation["topologicalOrder"]:
        phase = phases_by_id[phase_id]
        integration_states = {
            integration_id: integration_plans[integration_id]["readiness"]
            for integration_id in phase["requiredIntegrations"]
        }
        blocked_integrations = sorted(
            integration_id for integration_id, state in integration_states.items()
            if state in {"disabled", "admin-binding-required", "connection-required",
                         "environment-reference-missing"}
        )
        unmet_dependencies = sorted(set(phase["dependsOn"]) - completed_for_planning)
        if phase_id == "F16" and not config["security"]["productionEnabled"]:
            readiness = "production-disabled"
        elif blocked_integrations:
            readiness = "blocked-by-integration"
        elif unmet_dependencies:
            readiness = "blocked-by-dependency"
        elif phase["requiredApproval"] != "none":
            readiness = "approval-required"
        else:
            readiness = "ready"
            completed_for_planning.add(phase_id)
        phase_plans.append({
            "id": phase_id,
            "title": phase["title"],
            "readiness": readiness,
            "dependsOn": phase["dependsOn"],
            "unmetDependencies": unmet_dependencies,
            "requiredIntegrations": phase["requiredIntegrations"],
            "blockedIntegrations": blocked_integrations,
            "execution": phase["execution"],
            "mutatesExternalState": phase["mutatesExternalState"],
            "requiredApproval": phase["requiredApproval"],
            "outputs": phase["outputs"],
        })

    counts: dict[str, int] = {}
    for phase in phase_plans:
        counts[phase["readiness"]] = counts.get(phase["readiness"], 0) + 1
    return {
        "contract": validation,
        "canonical": config["canonical"],
        "authorities": config["authorities"],
        "integrations": list(integration_plans.values()),
        "phases": phase_plans,
        "phaseReadinessCounts": dict(sorted(counts.items())),
        "environmentInspected": inspect_env,
        "security": {
            "productionEnabled": False,
            "applyDefault": False,
            "secretValuesRead": False,
            "externalMutationPerformed": False,
            "activeUiFramework": "WinUI 3",
        },
    }


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path, default=DEFAULT_CONFIG)
    parser.add_argument("--mode", choices=("validate", "plan"), default="plan")
    parser.add_argument("--inspect-env", action="store_true",
                        help="Report only whether named variables exist; values are never read back")
    parser.add_argument("--strict-env", action="store_true",
                        help="Exit 3 when configured provider environment references are absent")
    parser.add_argument("--output", type=pathlib.Path,
                        help="Write the sanitized JSON result to this path")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        config = _read_object(args.config.resolve())
        result = validate(config) if args.mode == "validate" else build_plan(config, args.inspect_env)
    except ContractError as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        return 2

    payload = json.dumps({"status": "passed", "result": result}, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    sys.stdout.write(payload)

    if args.strict_env and args.inspect_env and args.mode == "plan":
        missing = {
            item["id"]: item["missingEnvNames"]
            for item in result["integrations"] if item["missingEnvNames"]
        }
        if missing:
            return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
