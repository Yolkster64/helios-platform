#!/usr/bin/env python3
"""Validate config/model-catalog.json against config/schemas/model-catalog.schema.json.

Stdlib-only on purpose (json + manual structural checks — NO jsonschema dependency):
this runs in the dotnet-build workflow before the Build step, where installing
packages would slow every CI run for a handful of assertions.

The schema file is the single source of truth for the enums (provider keys, class,
relativeSpeed) and the required field list; this script reads them from the schema
and applies them by hand, so extending the catalog means editing the schema, not
this file. Checks performed:

  * top level is an object whose "models" is a non-empty array
  * every model entry is an object carrying every required field
  * field types match the C# binder (ModelCatalog.cs): strings, ints, numbers, list
  * "provider" is a known provider key; "class"/"relativeSpeed" are known enums
  * no empty ids: provider/model/strengths entries must be non-empty strings
  * contextTokens >= 1; prices >= 0; strengths non-empty
  * no unknown fields on a model entry, and no duplicate (provider, model) pair

Usage: validate-model-catalog.py [catalog-path [schema-path]]
Exit code 0 = valid; 1 = validation errors (all printed); 2 = unreadable inputs.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CATALOG = REPO_ROOT / "config" / "model-catalog.json"
DEFAULT_SCHEMA = REPO_ROOT / "config" / "schemas" / "model-catalog.schema.json"


def load_json(path: Path, label: str):
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError:
        print(f"ERROR: {label} not found: {path}", file=sys.stderr)
    except json.JSONDecodeError as exc:
        print(f"ERROR: {label} is not valid JSON ({path}): {exc}", file=sys.stderr)
    sys.exit(2)


def main(argv: list[str]) -> int:
    catalog_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_CATALOG
    schema_path = Path(argv[2]) if len(argv) > 2 else DEFAULT_SCHEMA

    catalog = load_json(catalog_path, "catalog")
    schema = load_json(schema_path, "schema")

    try:
        profile_schema = schema["$defs"]["modelProfile"]
        required_fields = list(profile_schema["required"])
        props = profile_schema["properties"]
        known_fields = set(props)
        known_providers = set(props["provider"]["enum"])
        known_classes = set(props["class"]["enum"])
        known_speeds = set(props["relativeSpeed"]["enum"])
    except (KeyError, TypeError) as exc:
        print(f"ERROR: schema shape unexpected ({schema_path}): missing {exc}", file=sys.stderr)
        return 2

    errors: list[str] = []

    def err(message: str) -> None:
        errors.append(message)

    if not isinstance(catalog, dict):
        err("top level: expected a JSON object")
        models = []
    else:
        for key in catalog:
            if key not in {"$comment", "models", "selectionPolicy"}:
                err(f"top level: unknown key '{key}'")
        models = catalog.get("models")
        if not isinstance(models, list):
            err("top level: 'models' must be an array")
            models = []
        elif not models:
            err("top level: 'models' must not be empty")

    seen: set[tuple[str, str]] = set()
    for index, entry in enumerate(models):
        where = f"models[{index}]"
        if not isinstance(entry, dict):
            err(f"{where}: expected an object")
            continue

        for field in required_fields:
            if field not in entry:
                err(f"{where}: missing required field '{field}'")
        for field in entry:
            if field not in known_fields:
                err(f"{where}: unknown field '{field}' (binder ignores it silently — add it to the schema first)")

        provider = entry.get("provider")
        model = entry.get("model")
        for name, value in (("provider", provider), ("model", model), ("note", entry.get("note"))):
            if name in entry and (not isinstance(value, str) or (name != "note" and not value.strip())):
                err(f"{where}: '{name}' must be a non-empty string")
        if isinstance(provider, str) and provider and provider not in known_providers:
            err(f"{where}: provider '{provider}' is not a known provider key {sorted(known_providers)}")

        clazz = entry.get("class")
        if "class" in entry and clazz not in known_classes:
            err(f"{where}: class '{clazz}' not in {sorted(known_classes)}")
        speed = entry.get("relativeSpeed")
        if "relativeSpeed" in entry and speed not in known_speeds:
            err(f"{where}: relativeSpeed '{speed}' not in {sorted(known_speeds)}")

        context_tokens = entry.get("contextTokens")
        if "contextTokens" in entry and (
            not isinstance(context_tokens, int) or isinstance(context_tokens, bool) or context_tokens < 1
        ):
            err(f"{where}: contextTokens must be an integer >= 1")
        for price_field in ("inputPerMillionUsd", "outputPerMillionUsd"):
            price = entry.get(price_field)
            if price_field in entry and (
                not isinstance(price, (int, float)) or isinstance(price, bool) or price < 0
            ):
                err(f"{where}: {price_field} must be a number >= 0")

        strengths = entry.get("strengths")
        if "strengths" in entry:
            if not isinstance(strengths, list) or not strengths:
                err(f"{where}: strengths must be a non-empty array")
            else:
                for pos, strength in enumerate(strengths):
                    if not isinstance(strength, str) or not strength.strip():
                        err(f"{where}: strengths[{pos}] must be a non-empty string")

        if isinstance(provider, str) and isinstance(model, str) and provider and model:
            pair = (provider, model)
            if pair in seen:
                err(f"{where}: duplicate entry for {provider}/{model}")
            seen.add(pair)

    if errors:
        for message in errors:
            print(f"FAIL: {message}", file=sys.stderr)
        print(f"model-catalog validation FAILED: {len(errors)} error(s) in {catalog_path}", file=sys.stderr)
        return 1

    print(f"model-catalog OK: {len(models)} model(s) across "
          f"{len({p for p, _ in seen})} provider(s) validated against {schema_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
