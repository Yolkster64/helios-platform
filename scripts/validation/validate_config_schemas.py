#!/usr/bin/env python3
"""Validate HELIOS config manifests against their JSON Schemas.

The map of manifest -> schema is config/schemas/manifests.json (one place; the
helios_config_validate MCP tool reads the same file). Every schema under
config/schemas/ is draft 2020-12.

Engine: python-jsonschema when it is importable, otherwise a built-in validator
covering the keyword subset the repo's schemas use (type, required, enum, const,
pattern, format date / date-time, min/max length, min/max items, uniqueItems,
minimum / maximum, properties, patternProperties, additionalProperties,
propertyNames, min/maxProperties, items, contains, $ref, allOf / anyOf / oneOf /
not, if / then / else). The fallback is the engine CI actually runs (ubuntu
runners ship PyYAML but not jsonschema), so it refuses schemas that use a keyword
it does not implement instead of silently skipping the check.

Usage:
    validate_config_schemas.py                         # every mapped manifest
    validate_config_schemas.py config/github/labels.json
    validate_config_schemas.py --schema config/schemas/github-labels.schema.json draft.json
    validate_config_schemas.py --list                  # print the map
    validate_config_schemas.py --engine builtin        # force the fallback
    validate_config_schemas.py --json                  # one JSON object on stdout

Exit codes: 0 = every manifest valid; 1 = at least one invalid; 2 = an input
could not be read, a schema is malformed / unsupported, or a manifest has no
mapping and no --schema was given.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

try:
    import jsonschema
except ModuleNotFoundError:  # pragma: no cover - exercised on runners without the package
    jsonschema = None

REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPING_FILE = Path("config") / "schemas" / "manifests.json"


class SchemaError(Exception):
    """The schema itself is malformed or uses a keyword the built-in engine lacks."""


@dataclass(frozen=True)
class Issue:
    path: str
    message: str


@dataclass(frozen=True)
class Mapping:
    manifest: str
    schema: str
    consumer: str = ""


@dataclass
class Result:
    manifest: str
    schema: str
    valid: bool
    issues: list[Issue] = field(default_factory=list)
    engine: str = "builtin"


# --------------------------------------------------------------------------------------
# Built-in draft 2020-12 subset
# --------------------------------------------------------------------------------------

_ANNOTATIONS = {
    "$schema", "$id", "$comment", "$defs", "definitions", "title", "description",
    "default", "examples", "deprecated", "readOnly", "writeOnly",
}
_SUPPORTED = {
    "$ref", "type", "enum", "const", "properties", "patternProperties",
    "additionalProperties", "propertyNames", "required", "minProperties", "maxProperties",
    "items", "contains", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength",
    "pattern", "format", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
    "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
}
_TYPE_NAMES = ("null", "boolean", "object", "array", "number", "integer", "string")


def _is_integer(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and value.is_integer()


def _type_of(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "integer" if _is_integer(value) else "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    raise SchemaError(f"unsupported instance value {value!r}")


def _matches_type(value: Any, expected: str) -> bool:
    actual = _type_of(value)
    if expected == "number":
        return actual in ("number", "integer")
    if expected == "integer":
        return actual == "integer"
    return actual == expected


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def _brief(value: Any, limit: int = 120) -> str:
    """Canonical form for messages: a whole manifest quoted back is noise, not a hint."""
    text = _canonical(value)
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _json_equal(left: Any, right: Any) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left == right
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        return left == right
    return _canonical(left) == _canonical(right)


def _check_date(value: str) -> bool:
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        return False
    try:
        _dt.date.fromisoformat(value)
    except ValueError:
        return False
    return True


_DATE_TIME_SHAPE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?([Zz]|[+-][0-9]{2}:[0-9]{2})?$")

# Constructs .NET, Python and ECMA-262 do not share; refused by name so the C# engine
# (JsonSchemaLite, ECMAScript mode) and this one accept exactly the same patterns.
_NON_PORTABLE_REGEX = ("\\A", "\\Z", "\\z", "\\G", "(?<=", "(?<!", "\\p{", "\\P{", "(?i)", "(?m)", "(?s)", "(?x)", "(?#")


def _check_date_time(value: str) -> bool:
    # RFC 3339 shape first (fromisoformat is lenient about separators), then a real clock check.
    if not _DATE_TIME_SHAPE.match(value):
        return False
    try:
        _dt.datetime.fromisoformat(value.replace("z", "Z").replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


_FORMATS: dict[str, Callable[[str], bool]] = {
    "date": _check_date,
    "date-time": _check_date_time,
}


class MiniValidator:
    """Dependency-free validator for the keyword subset listed in the module docstring.

    Error messages follow python-jsonschema's wording where a message is likely to be
    matched in a test, so the two engines read the same in CI logs.
    """

    def __init__(self, schema: Any) -> None:
        self.root = schema
        self._regex: dict[str, re.Pattern[str]] = {}
        self.check_schema()

    # -- schema self-check ------------------------------------------------------------

    def check_schema(self) -> None:
        self._walk_schema(self.root, "#")

    def _walk_schema(self, node: Any, where: str) -> None:
        if isinstance(node, bool):
            return
        if not isinstance(node, dict):
            raise SchemaError(f"{where}: a schema must be an object or a boolean")
        for key, value in node.items():
            if key in _ANNOTATIONS:
                if key in ("$defs", "definitions") and isinstance(value, dict):
                    for name, sub in value.items():
                        self._walk_schema(sub, f"{where}/{key}/{name}")
                continue
            if key not in _SUPPORTED:
                raise SchemaError(
                    f"{where}: keyword '{key}' is not implemented by the built-in validator; "
                    "extend MiniValidator (and JsonSchemaLite.cs) or drop the keyword")
            if key in ("properties", "patternProperties"):
                if not isinstance(value, dict):
                    raise SchemaError(f"{where}/{key}: must be an object")
                for name, sub in value.items():
                    self._walk_schema(sub, f"{where}/{key}/{name}")
            elif key in ("additionalProperties", "propertyNames", "items", "contains",
                         "not", "if", "then", "else"):
                self._walk_schema(value, f"{where}/{key}")
            elif key in ("allOf", "anyOf", "oneOf"):
                if not isinstance(value, list) or not value:
                    raise SchemaError(f"{where}/{key}: must be a non-empty array")
                for index, sub in enumerate(value):
                    self._walk_schema(sub, f"{where}/{key}/{index}")
            elif key == "type":
                names = value if isinstance(value, list) else [value]
                for name in names:
                    if name not in _TYPE_NAMES:
                        raise SchemaError(f"{where}/type: unknown type {name!r}")
            elif key == "pattern":
                self._compile(value, where)
            elif key == "$ref":
                self._resolve(value, where)
            elif key == "format" and value not in _FORMATS:
                # Unknown formats are annotations per the spec; nothing to assert.
                pass

    def _compile(self, pattern: Any, where: str) -> re.Pattern[str]:
        if not isinstance(pattern, str):
            raise SchemaError(f"{where}/pattern: must be a string")
        compiled = self._regex.get(pattern)
        if compiled is None:
            unportable = next((token for token in _NON_PORTABLE_REGEX if token in pattern), None)
            if unportable is not None:
                raise SchemaError(f"{where}/pattern: '{unportable}' is outside the portable (ECMA-262) regex subset in {pattern!r}")
            try:
                compiled = re.compile(pattern)
            except re.error as exc:
                raise SchemaError(f"{where}/pattern: invalid regex {pattern!r}: {exc}") from exc
            self._regex[pattern] = compiled
        return compiled

    def _resolve(self, ref: Any, where: str) -> Any:
        if not isinstance(ref, str) or not ref.startswith("#"):
            raise SchemaError(f"{where}/$ref: only local '#/...' references are supported, got {ref!r}")
        node: Any = self.root
        pointer = ref[1:]
        if pointer.startswith("/"):
            for token in pointer[1:].split("/"):
                token = token.replace("~1", "/").replace("~0", "~")
                if isinstance(node, dict) and token in node:
                    node = node[token]
                elif isinstance(node, list) and token.isdigit() and int(token) < len(node):
                    node = node[int(token)]
                else:
                    raise SchemaError(f"{where}/$ref: {ref!r} does not resolve")
        elif pointer:
            raise SchemaError(f"{where}/$ref: unsupported reference {ref!r}")
        return node

    # -- validation -------------------------------------------------------------------

    def iter_errors(self, instance: Any) -> list[Issue]:
        errors: list[Issue] = []
        self._validate(self.root, instance, "$", errors)
        return errors

    def is_valid(self, instance: Any) -> bool:
        return not self.iter_errors(instance)

    def _validate(self, schema: Any, instance: Any, path: str, errors: list[Issue]) -> None:
        if schema is True:
            return
        if schema is False:
            errors.append(Issue(path, "False schema does not allow " + _brief(instance)))
            return

        if "$ref" in schema:
            self._validate(self._resolve(schema["$ref"], "#"), instance, path, errors)

        if "type" in schema:
            names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
            if not any(_matches_type(instance, name) for name in names):
                wanted = ", ".join(f"'{name}'" for name in names)
                errors.append(Issue(path, f"{_brief(instance)} is not of type {wanted}"))
                return  # type mismatches make the remaining keywords meaningless

        if "enum" in schema and not any(_json_equal(instance, option) for option in schema["enum"]):
            errors.append(Issue(path, f"{_brief(instance)} is not one of {_canonical(schema['enum'])}"))
        if "const" in schema and not _json_equal(instance, schema["const"]):
            errors.append(Issue(path, f"{_canonical(schema['const'])} was expected"))

        if isinstance(instance, str):
            self._validate_string(schema, instance, path, errors)
        elif isinstance(instance, (int, float)) and not isinstance(instance, bool):
            self._validate_number(schema, instance, path, errors)
        elif isinstance(instance, list):
            self._validate_array(schema, instance, path, errors)
        elif isinstance(instance, dict):
            self._validate_object(schema, instance, path, errors)

        for sub in schema.get("allOf", []):
            self._validate(sub, instance, path, errors)
        if "anyOf" in schema:
            self._validate_alternatives(schema["anyOf"], instance, path, errors, exactly_one=False)
        if "oneOf" in schema:
            self._validate_alternatives(schema["oneOf"], instance, path, errors, exactly_one=True)
        if "not" in schema and not self._errors_for(schema["not"], instance, path):
            errors.append(Issue(path, f"{_brief(instance)} should not be valid under {_brief(schema['not'])}"))
        if "if" in schema:
            branch = "then" if not self._errors_for(schema["if"], instance, path) else "else"
            if branch in schema:
                self._validate(schema[branch], instance, path, errors)

    def _errors_for(self, schema: Any, instance: Any, path: str) -> list[Issue]:
        collected: list[Issue] = []
        self._validate(schema, instance, path, collected)
        return collected

    def _validate_alternatives(self, options: list[Any], instance: Any, path: str,
                               errors: list[Issue], exactly_one: bool) -> None:
        outcomes = [self._errors_for(option, instance, path) for option in options]
        matches = [index for index, outcome in enumerate(outcomes) if not outcome]
        if not matches:
            # Report the closest branch: the one with the fewest errors, preferring a branch
            # whose declared type matches the instance so an object is judged as an object.
            def rank(index: int) -> tuple[int, int]:
                option = options[index]
                declared = option.get("type") if isinstance(option, dict) else None
                if isinstance(option, dict) and "$ref" in option and declared is None:
                    resolved = self._resolve(option["$ref"], "#")
                    declared = resolved.get("type") if isinstance(resolved, dict) else None
                declared_list = declared if isinstance(declared, list) else [declared]
                type_penalty = 0 if any(
                    name is not None and _matches_type(instance, name) for name in declared_list) else 1
                return (type_penalty, len(outcomes[index]))

            best = min(range(len(options)), key=rank)
            keyword = "oneOf" if exactly_one else "anyOf"
            errors.append(Issue(path, f"{_brief(instance)} is not valid under any of the given schemas ({keyword})"))
            errors.extend(outcomes[best])
        elif exactly_one and len(matches) > 1:
            errors.append(Issue(path, f"{_brief(instance)} is valid under each of {len(matches)} oneOf schemas"))

    def _validate_string(self, schema: dict[str, Any], value: str, path: str, errors: list[Issue]) -> None:
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(Issue(path, f"{_brief(value)} is too short (minLength {schema['minLength']})"))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(Issue(path, f"{_brief(value)} is too long (maxLength {schema['maxLength']})"))
        if "pattern" in schema and not self._compile(schema["pattern"], path).search(value):
            errors.append(Issue(path, f"{_brief(value)} does not match {_canonical(schema['pattern'])}"))
        checker = _FORMATS.get(schema.get("format", ""))
        if checker is not None and not checker(value):
            errors.append(Issue(path, f"{_brief(value)} is not a {_canonical(schema['format'])}"))

    @staticmethod
    def _validate_number(schema: dict[str, Any], value: float, path: str, errors: list[Issue]) -> None:
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(Issue(path, f"{_brief(value)} is less than the minimum of {schema['minimum']}"))
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(Issue(path, f"{_brief(value)} is greater than the maximum of {schema['maximum']}"))
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(Issue(path, f"{_brief(value)} is less than or equal to the minimum of {schema['exclusiveMinimum']}"))
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(Issue(path, f"{_brief(value)} is greater than or equal to the maximum of {schema['exclusiveMaximum']}"))

    def _validate_array(self, schema: dict[str, Any], items: list[Any], path: str, errors: list[Issue]) -> None:
        if "minItems" in schema and len(items) < schema["minItems"]:
            errors.append(Issue(path, f"{_brief(items)} is too short (minItems {schema['minItems']})"))
        if "maxItems" in schema and len(items) > schema["maxItems"]:
            errors.append(Issue(path, f"{_brief(items)} is too long (maxItems {schema['maxItems']})"))
        if schema.get("uniqueItems"):
            seen: set[str] = set()
            for index, item in enumerate(items):
                key = _canonical(item)
                if key in seen:
                    # python-jsonschema reports the array, not the duplicate's index
                    errors.append(Issue(path, f"{_brief(items)} has non-unique elements"))
                    break
                seen.add(key)
        if "items" in schema:
            for index, item in enumerate(items):
                self._validate(schema["items"], item, f"{path}[{index}]", errors)
        if "contains" in schema and not any(
                not self._errors_for(schema["contains"], item, f"{path}[{index}]")
                for index, item in enumerate(items)):
            errors.append(Issue(path, f"{_brief(items)} does not contain items matching the given schema"))

    def _validate_object(self, schema: dict[str, Any], obj: dict[str, Any], path: str, errors: list[Issue]) -> None:
        for name in schema.get("required", []):
            if name not in obj:
                errors.append(Issue(path, f"'{name}' is a required property"))
        if "minProperties" in schema and len(obj) < schema["minProperties"]:
            errors.append(Issue(path, f"{_brief(obj)} does not have enough properties (minProperties {schema['minProperties']})"))
        if "maxProperties" in schema and len(obj) > schema["maxProperties"]:
            errors.append(Issue(path, f"{_brief(obj)} has too many properties (maxProperties {schema['maxProperties']})"))
        properties = schema.get("properties", {})
        pattern_properties = schema.get("patternProperties", {})
        unexpected: list[str] = []
        for name, value in obj.items():
            child = f"{path}.{name}"
            matched = False
            if name in properties:
                matched = True
                self._validate(properties[name], value, child, errors)
            for pattern, sub in pattern_properties.items():
                if self._compile(pattern, path).search(name):
                    matched = True
                    self._validate(sub, value, child, errors)
            if not matched and "additionalProperties" in schema:
                extra = schema["additionalProperties"]
                if extra is False:
                    unexpected.append(name)
                else:
                    self._validate(extra, value, child, errors)
            if "propertyNames" in schema:
                # python-jsonschema reports a bad key at the object, not at the key's own path
                self._validate(schema["propertyNames"], name, path, errors)
        if unexpected:
            listed = ", ".join(f"'{name}'" for name in unexpected)
            plural = "were" if len(unexpected) > 1 else "was"
            errors.append(Issue(path, f"Additional properties are not allowed ({listed} {plural} unexpected)"))


# --------------------------------------------------------------------------------------
# Engines
# --------------------------------------------------------------------------------------

def _format_json_path(parts: Any) -> str:
    rendered = "$"
    for part in parts:
        rendered += f"[{part}]" if isinstance(part, int) else f".{part}"
    return rendered


def available_engines() -> list[str]:
    return ["jsonschema", "builtin"] if jsonschema is not None else ["builtin"]


def _descend_alternatives(errors: Any) -> list[tuple[Any, str]]:
    """Mirror the built-in engine's closest-branch rule for python-jsonschema.

    jsonschema reports a failed anyOf / oneOf as one error at the alternatives' own path
    ("... is not valid under any of the given schemas") and keeps the per-branch errors in
    error.context. For a manifest that is "an object with a labels array OR a bare array",
    that top-level error names neither the bad key nor the bad value, so a typo in a closed
    object would be reported at `$`. This walks into the closest branch — the one whose
    declared type matches the instance (no `type` error at the alternatives' path),
    then the one with the fewest errors — exactly as MiniValidator._validate_alternatives
    does, so both engines name the same paths and the tests hold under either.
    """
    flattened: list[tuple[Any, str]] = []
    for error in errors:
        if not error.context:
            flattened.append((error, error.message))
            continue
        branches: dict[int, list[Any]] = {}
        for sub in error.context:
            branches.setdefault(int(sub.relative_schema_path[0]), []).append(sub)

        def rank(index: int) -> tuple[int, int]:
            subs = branches[index]
            here = list(error.absolute_path)
            type_penalty = 1 if any(
                sub.validator == "type" and list(sub.absolute_path) == here for sub in subs) else 0
            return (type_penalty, len(subs))

        best = min(branches, key=rank)
        flattened.append((error, f"{_brief(error.instance)} is not valid under any of the given schemas ({error.validator})"))
        flattened.extend(_descend_alternatives(branches[best]))
    return flattened


def _refuse_non_portable_patterns(node: Any, where: str) -> None:
    """Walk the schema once so the library engine refuses the same regex constructs the built-in
    engine and the C# twin refuse (python-jsonschema would happily run `\\Z` or `(?i)`)."""
    if isinstance(node, dict):
        pattern = node.get("pattern")
        if isinstance(pattern, str):
            unportable = next((token for token in _NON_PORTABLE_REGEX if token in pattern), None)
            if unportable is not None:
                raise SchemaError(f"{where}/pattern: '{unportable}' is outside the portable (ECMA-262) regex subset in {pattern!r}")
        for key, value in node.items():
            if key not in ("enum", "const", "default", "examples"):
                _refuse_non_portable_patterns(value, f"{where}/{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            _refuse_non_portable_patterns(value, f"{where}/{index}")


def validate_instance(instance: Any, schema: Any, engine: str = "auto") -> tuple[list[Issue], str]:
    """Return (issues, engine_used). engine: auto | jsonschema | builtin."""
    if engine not in ("auto", "jsonschema", "builtin"):
        raise ValueError(f"unknown engine {engine!r}")
    use_library = engine == "jsonschema" or (engine == "auto" and jsonschema is not None)
    _refuse_non_portable_patterns(schema, "#")
    if use_library:
        if jsonschema is None:
            raise SchemaError("python package 'jsonschema' is not installed; use --engine builtin")
        validator_class = jsonschema.Draft202012Validator
        try:
            validator_class.check_schema(schema)
        except jsonschema.exceptions.SchemaError as exc:
            raise SchemaError(f"schema is invalid: {exc.message}") from exc
        checker = jsonschema.FormatChecker()
        # Register this module's date / date-time checks with the library engine: without the
        # optional rfc3339-validator package jsonschema's own FormatChecker silently accepts any
        # date-time, so the two engines would disagree on the shipped fabric contract.
        for format_name, check in _FORMATS.items():
            checker.checks(format_name)(lambda value, _check=check: not isinstance(value, str) or _check(value))
        validator = validator_class(schema, format_checker=checker)
        try:
            raw_errors = list(validator.iter_errors(instance))
        except Exception as exc:  # a $ref that does not resolve surfaces as a referencing error
            if any(token in type(exc).__name__ for token in ("Referencing", "RefResolution", "Unresolvable")):
                raise SchemaError(f"schema $ref does not resolve: {exc}") from exc
            raise
        issues = [
            Issue(_format_json_path(error.absolute_path), message)
            for error, message in sorted(
                _descend_alternatives(raw_errors),
                key=lambda pair: (list(map(str, pair[0].absolute_path)), pair[1]))
        ]
        return issues, "jsonschema"
    return MiniValidator(schema).iter_errors(instance), "builtin"


# --------------------------------------------------------------------------------------
# Repo wiring
# --------------------------------------------------------------------------------------

def load_json(path: Path, label: str) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream)
    except FileNotFoundError as exc:
        raise ValueError(f"{label} not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} is not valid JSON: {path} (line {exc.lineno}: {exc.msg})") from exc


def load_mappings(repo_root: Path = REPO_ROOT) -> list[Mapping]:
    data = load_json(repo_root / MAPPING_FILE, "manifest map")
    if not isinstance(data, dict) or not isinstance(data.get("mappings"), list):
        raise ValueError(f"{MAPPING_FILE}: top level must be an object with a 'mappings' array")
    mappings: list[Mapping] = []
    for index, entry in enumerate(data["mappings"]):
        if not isinstance(entry, dict) or not isinstance(entry.get("manifest"), str) \
                or not isinstance(entry.get("schema"), str):
            raise ValueError(f"{MAPPING_FILE}: mappings[{index}] must carry string 'manifest' and 'schema'")
        mappings.append(Mapping(entry["manifest"], entry["schema"], str(entry.get("consumer", ""))))
    return mappings


def find_mapping(rel_path: str, mappings: list[Mapping]) -> Mapping | None:
    wanted = rel_path.replace("\\", "/").lstrip("./")
    for mapping in mappings:
        if mapping.manifest == wanted:
            return mapping
    return None


def to_repo_relative(path: Path, repo_root: Path) -> str | None:
    """Repo-relative POSIX form of `path`, or None when it lies outside the repo."""
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return None


def validate_file(manifest_path: Path, schema_path: Path, engine: str = "auto",
                  repo_root: Path = REPO_ROOT) -> Result:
    schema = load_json(schema_path, "schema")
    label = to_repo_relative(manifest_path, repo_root) or str(manifest_path)
    schema_label = to_repo_relative(schema_path, repo_root) or str(schema_path)
    if not manifest_path.is_file():
        # A manifest that is not there is an input that could not be read (exit 2), not an
        # invalid manifest (exit 1): the caller named a path that does not exist.
        raise ValueError(f"manifest not found: {manifest_path}")
    try:
        instance = load_json(manifest_path, "manifest")
    except ValueError as exc:
        # A manifest that is not JSON is an invalid manifest, not a broken invocation.
        return Result(label, schema_label, False, [Issue("$", str(exc))], engine if engine != "auto" else "n/a")
    issues, used = validate_instance(instance, schema, engine)
    return Result(label, schema_label, not issues, issues, used)


def validate_mapping(mapping: Mapping, engine: str = "auto", repo_root: Path = REPO_ROOT) -> Result:
    return validate_file(repo_root / mapping.manifest, repo_root / mapping.schema, engine, repo_root)


def validate_all_mapped(engine: str = "auto", repo_root: Path = REPO_ROOT) -> list[Result]:
    return [validate_mapping(mapping, engine, repo_root) for mapping in load_mappings(repo_root)]


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def _resolve_manifest_argument(argument: str, repo_root: Path) -> Path:
    candidate = Path(argument)
    if candidate.is_absolute():
        return candidate
    if candidate.exists():
        return candidate.resolve()
    return repo_root / argument


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("manifests", nargs="*", help="manifest paths (repo-relative or absolute); default: every mapped manifest")
    parser.add_argument("--schema", help="validate the given manifests against this schema instead of the mapped one")
    parser.add_argument("--engine", choices=("auto", "jsonschema", "builtin"), default="auto")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--list", action="store_true", help="print the manifest -> schema map and exit")
    parser.add_argument("--json", action="store_true", help="emit one JSON object on stdout")
    args = parser.parse_args(argv[1:])
    repo_root: Path = args.repo_root.resolve()

    def emit(payload: dict[str, Any], code: int) -> int:
        if args.json:
            print(json.dumps(payload, indent=2))
        return code

    try:
        mappings = load_mappings(repo_root)
        if args.list:
            if args.json:
                return emit({"mappings": [mapping.__dict__ for mapping in mappings]}, 0)
            for mapping in mappings:
                print(f"{mapping.manifest}  ->  {mapping.schema}")
            return 0

        results: list[Result] = []
        if args.manifests:
            for argument in args.manifests:
                manifest_path = _resolve_manifest_argument(argument, repo_root)
                if args.schema:
                    schema_path = _resolve_manifest_argument(args.schema, repo_root)
                else:
                    rel = to_repo_relative(manifest_path, repo_root)
                    mapping = find_mapping(rel, mappings) if rel else None
                    if mapping is None:
                        raise ValueError(
                            f"no schema is mapped for '{argument}' in {MAPPING_FILE}; add a mapping there "
                            "or pass --schema config/schemas/<name>.schema.json")
                    schema_path = repo_root / mapping.schema
                results.append(validate_file(manifest_path, schema_path, args.engine, repo_root))
        else:
            results = [validate_mapping(mapping, args.engine, repo_root) for mapping in mappings]
    except (ValueError, SchemaError, OSError) as exc:
        if args.json:
            print(json.dumps({"status": "error", "error": str(exc)}, indent=2))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    invalid = [result for result in results if not result.valid]
    engine_used = results[0].engine if results else args.engine
    if args.json:
        return emit({
            "status": "failed" if invalid else "passed",
            "engine": engine_used,
            "results": [
                {
                    "manifest": result.manifest,
                    "schema": result.schema,
                    "valid": result.valid,
                    "errors": [issue.__dict__ for issue in result.issues],
                }
                for result in results
            ],
        }, 1 if invalid else 0)

    for result in results:
        if result.valid:
            print(f"OK    {result.manifest}  <-  {result.schema}")
        else:
            print(f"FAIL  {result.manifest}  <-  {result.schema}")
            for issue in result.issues:
                print(f"      {issue.path}: {issue.message}")
    print(f"config-schemas: {len(results) - len(invalid)} valid, {len(invalid)} invalid (engine: {engine_used})")
    return 1 if invalid else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
