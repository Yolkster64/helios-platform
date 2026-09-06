#!/usr/bin/env python3
"""Validate the HELIOS model-provider registry without invoking providers."""

from __future__ import annotations

import json
import pathlib
import re
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "config/providers/helios-model-providers.v1.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    value: Any = json.loads(REGISTRY.read_text(encoding="utf-8"))
    require(isinstance(value, dict), "provider registry must be an object")
    require(value.get("defaultPolicy") == "deny", "provider registry must deny by default")

    providers = value.get("providers")
    require(isinstance(providers, list) and providers, "provider registry must be non-empty")
    provider_ids = [str(row.get("id")) for row in providers if isinstance(row, dict)]
    require(len(provider_ids) == len(set(provider_ids)), "provider IDs must be unique")
    required = {
        "openai",
        "anthropic",
        "azure-foundry",
        "microsoft-copilot",
        "ollama-local",
        "lm-studio-local",
        "hermes-xcore",
    }
    require(required.issubset(set(provider_ids)), "required provider missing")

    for row in providers:
        require(isinstance(row, dict), "provider entry must be an object")
        provider_id = str(row.get("id"))
        require(bool(row.get("client")), f"provider {provider_id} is missing client")
        require(bool(row.get("modes")), f"provider {provider_id} is missing modes")
        require(bool(row.get("allowed")), f"provider {provider_id} is missing allowed operations")
        require(bool(row.get("denied")), f"provider {provider_id} is missing denied operations")
        references = row.get("secretReferences", [])
        require(isinstance(references, list), f"provider {provider_id} secretReferences must be a list")
        for reference in references:
            require(re.fullmatch(r"[A-Z][A-Z0-9_]+", str(reference)) is not None,
                    f"provider {provider_id} contains invalid secret reference {reference!r}")

    common = value.get("commonContract")
    require(isinstance(common, dict), "common contract missing")
    for section in ("task", "result", "policy", "routing", "health"):
        require(bool(common.get(section)), f"common contract section {section} missing")

    rules = value.get("globalRules")
    require(isinstance(rules, dict), "global rules missing")
    require(rules.get("credentialsAreReferencesOnly") is True,
            "credentials must be references only")
    require(rules.get("providerBusinessLogicInGui") is False,
            "provider business logic must stay out of GUI")
    require(rules.get("unrestrictedToolExecution") is False,
            "unrestricted tool execution must be disabled")
    require(rules.get("automaticProductionAction") is False,
            "automatic production actions must be disabled")

    text = REGISTRY.read_text(encoding="utf-8")
    secret_patterns = [
        re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
        re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
        re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}"),
    ]
    for pattern in secret_patterns:
        require(pattern.search(text) is None, "possible embedded credential in provider registry")

    print(json.dumps({
        "status": "passed",
        "registryId": value.get("registryId"),
        "providers": provider_ids,
        "credentialsAreReferencesOnly": rules.get("credentialsAreReferencesOnly"),
        "automaticProductionAction": rules.get("automaticProductionAction"),
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, KeyError, OSError, TypeError, ValueError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, indent=2), file=sys.stderr)
        raise SystemExit(1)
