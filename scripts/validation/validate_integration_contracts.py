#!/usr/bin/env python3
"""Validate HELIOS integration schemas, registries, and examples without dependencies."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_ROOT = REPO_ROOT / "contracts"
EVENT_SCHEMA_PATH = CONTRACT_ROOT / "integration-event.v1.schema.json"
EVENT_TYPES_PATH = CONTRACT_ROOT / "integration-event-types.v1.json"
REPOSITORY_SCHEMA_PATH = CONTRACT_ROOT / "repository-capabilities.v1.schema.json"
REPOSITORY_REGISTRY_PATH = CONTRACT_ROOT / "repository-capabilities.v1.json"
EXAMPLES_PATH = CONTRACT_ROOT / "examples"

IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$")
CORRELATION_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{3,127}$")
EVENT_TYPE = re.compile(r"^[a-z0-9]+([._-][a-z0-9]+)*$")
REPOSITORY = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SOURCE_SHA = re.compile(r"^([0-9a-f]{40}|[0-9a-f]{64})$")
IDEMPOTENCY_KEY = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{7,255}$")
TRACEPARENT = re.compile(r"^[0-9a-f]{2}-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$")

EVENT_FAMILIES = {"command", "result", "approval", "deployment", "connector", "fleet"}
REPOSITORY_LIFECYCLES = {"active", "planned", "satellite", "historical", "recovery"}
INTEGRATION_MODES = {
    "canonical",
    "contract-governance",
    "planned-in-place-rename",
    "planned-extraction",
    "adapter",
    "versioned-package",
    "workload-manifest",
    "reference-only",
    "recovery-only",
    "historical-upstream",
}
IMPORT_POLICIES = {
    "native",
    "contract-mirror",
    "thin-adapter",
    "versioned-artifact",
    "selective-extraction",
    "read-only-reference",
    "never-wholesale",
}
REQUIRED_SURFACES = {
    "github",
    "linear",
    "slack",
    "sharepoint",
    "azure-devops",
    "chatgpt",
    "openai-api",
    "codex",
    "claude",
    "github-copilot",
    "microsoft-copilot",
    "hermes",
    "xcore",
    "azure",
}


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def _exact_keys(value: object, allowed: set[str], where: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{where}: expected object")
        return
    unknown = sorted(set(value) - allowed)
    if unknown:
        errors.append(f"{where}: unknown field(s): {', '.join(unknown)}")


def _require_keys(value: object, required: set[str], where: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        return
    missing = sorted(required - set(value))
    if missing:
        errors.append(f"{where}: missing field(s): {', '.join(missing)}")


def validate_event_types(catalog: object) -> tuple[set[str], list[str]]:
    errors: list[str] = []
    _exact_keys(catalog, {"schemaVersion", "eventTypes"}, "event type catalog", errors)
    if not isinstance(catalog, dict):
        return set(), errors
    if catalog.get("schemaVersion") != "1.0":
        errors.append("event type catalog: schemaVersion must be 1.0")
    entries = catalog.get("eventTypes")
    if not isinstance(entries, list) or not entries:
        errors.append("event type catalog: eventTypes must be a non-empty array")
        return set(), errors

    identifiers: set[str] = set()
    families: set[str] = set()
    for index, entry in enumerate(entries):
        where = f"eventTypes[{index}]"
        _exact_keys(entry, {"id", "family", "terminal", "description"}, where, errors)
        _require_keys(entry, {"id", "family", "terminal", "description"}, where, errors)
        if not isinstance(entry, dict):
            continue
        identifier = entry.get("id")
        family = entry.get("family")
        if not isinstance(identifier, str) or not EVENT_TYPE.fullmatch(identifier):
            errors.append(f"{where}.id: invalid event type")
        elif identifier in identifiers:
            errors.append(f"{where}.id: duplicate '{identifier}'")
        else:
            identifiers.add(identifier)
        if family not in EVENT_FAMILIES:
            errors.append(f"{where}.family: unsupported family '{family}'")
        elif isinstance(identifier, str) and identifier.split(".", 1)[0] != family:
            errors.append(f"{where}: family does not match id prefix")
        else:
            families.add(family)
        if type(entry.get("terminal")) is not bool:
            errors.append(f"{where}.terminal: expected boolean")
        if not isinstance(entry.get("description"), str) or not entry["description"].strip():
            errors.append(f"{where}.description: expected non-empty string")

    missing_families = sorted(EVENT_FAMILIES - families)
    if missing_families:
        errors.append(f"event type catalog: missing families: {', '.join(missing_families)}")
    return identifiers, errors


def validate_event_schema(schema: object, event_types: set[str]) -> list[str]:
    errors: list[str] = []
    if not isinstance(schema, dict):
        return ["event schema: expected object"]
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("event schema: must declare JSON Schema draft 2020-12")
    if schema.get("type") != "object" or schema.get("additionalProperties") is not False:
        errors.append("event schema: top level must be a closed object")
    properties = schema.get("properties")
    required = schema.get("required")
    if not isinstance(properties, dict) or not isinstance(required, list):
        return errors + ["event schema: properties and required must be present"]
    core = {
        "schemaVersion",
        "eventId",
        "eventType",
        "source",
        "repository",
        "sourceSha",
        "correlationId",
        "idempotencyKey",
        "environment",
        "occurredAt",
        "dataClassification",
        "actor",
        "links",
        "payload",
    }
    missing = sorted(core - set(required))
    if missing:
        errors.append(f"event schema: required list misses: {', '.join(missing)}")
    if set(required) - set(properties):
        errors.append("event schema: required contains undefined properties")
    receipt = properties.get("links", {}).get("contains", {}).get("properties", {}).get("rel", {}).get("const")
    if receipt != "receipt" or properties.get("links", {}).get("minContains") != 1:
        errors.append("event schema: links must require at least one receipt")
    pattern = properties.get("eventType", {}).get("pattern")
    try:
        compiled = re.compile(pattern)
    except (TypeError, re.error):
        errors.append("event schema: eventType pattern is invalid")
    else:
        for identifier in sorted(event_types):
            if not compiled.fullmatch(identifier):
                errors.append(f"event schema: registered type '{identifier}' does not match eventType pattern")
    sources = properties.get("source", {}).get("enum")
    if not isinstance(sources, list) or not sources or len(sources) != len(set(sources)):
        errors.append("event schema: source enum must be non-empty and unique")
    elif any(not isinstance(source, str) or not EVENT_TYPE.fullmatch(source) for source in sources):
        errors.append("event schema: source enum contains an invalid source name")
    return errors


def _valid_uri(value: object) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return (parsed.scheme == "https" and bool(parsed.netloc)) or (
        parsed.scheme == "urn" and bool(parsed.path)
    )


def validate_event(event: object, schema: dict, event_types: set[str], where: str = "event") -> list[str]:
    errors: list[str] = []
    if not isinstance(event, dict):
        return [f"{where}: expected object"]
    properties = schema["properties"]
    required = set(schema["required"])
    unknown = sorted(set(event) - set(properties))
    missing = sorted(required - set(event))
    if unknown:
        errors.append(f"{where}: unknown field(s): {', '.join(unknown)}")
    if missing:
        errors.append(f"{where}: missing field(s): {', '.join(missing)}")
    if event.get("schemaVersion") != "1.0":
        errors.append(f"{where}.schemaVersion: must be 1.0")

    identifier = event.get("eventId")
    if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
        errors.append(f"{where}.eventId: invalid identifier")
    event_type = event.get("eventType")
    if event_type not in event_types:
        errors.append(f"{where}.eventType: unregistered event type '{event_type}'")
    source = event.get("source")
    known_sources = set(schema["properties"]["source"].get("enum", []))
    if source not in known_sources:
        errors.append(f"{where}.source: unregistered source '{source}'")
    repository = event.get("repository")
    if repository is not None and (not isinstance(repository, str) or not REPOSITORY.fullmatch(repository)):
        errors.append(f"{where}.repository: invalid owner/name")
    source_sha = event.get("sourceSha")
    if not isinstance(source_sha, str) or not SOURCE_SHA.fullmatch(source_sha):
        errors.append(f"{where}.sourceSha: expected a lowercase 40- or 64-character Git SHA")
    correlation_id = event.get("correlationId")
    if not isinstance(correlation_id, str) or not CORRELATION_ID.fullmatch(correlation_id):
        errors.append(f"{where}.correlationId: invalid identifier")
    causation_id = event.get("causationId")
    if causation_id is not None and (not isinstance(causation_id, str) or not IDENTIFIER.fullmatch(causation_id)):
        errors.append(f"{where}.causationId: invalid identifier")
    key = event.get("idempotencyKey")
    if not isinstance(key, str) or not IDEMPOTENCY_KEY.fullmatch(key):
        errors.append(f"{where}.idempotencyKey: invalid key")
    if event.get("environment") not in {"local", "development", "test", "staging", "production"}:
        errors.append(f"{where}.environment: unsupported value")
    if event.get("dataClassification") not in {"public", "internal", "confidential", "restricted"}:
        errors.append(f"{where}.dataClassification: unsupported value")

    occurred_at = event.get("occurredAt")
    if not isinstance(occurred_at, str):
        errors.append(f"{where}.occurredAt: expected RFC 3339 timestamp")
    else:
        try:
            parsed = datetime.fromisoformat(occurred_at.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                raise ValueError("timezone required")
        except ValueError:
            errors.append(f"{where}.occurredAt: expected timezone-aware RFC 3339 timestamp")

    actor = event.get("actor")
    _exact_keys(actor, {"type", "id", "displayName"}, f"{where}.actor", errors)
    _require_keys(actor, {"type", "id"}, f"{where}.actor", errors)
    if isinstance(actor, dict):
        if actor.get("type") not in {"human", "service", "agent", "workflow"}:
            errors.append(f"{where}.actor.type: unsupported value")
        if not isinstance(actor.get("id"), str) or not actor["id"].strip():
            errors.append(f"{where}.actor.id: expected non-empty string")
        display_name = actor.get("displayName")
        if display_name is not None and not isinstance(display_name, str):
            errors.append(f"{where}.actor.displayName: expected string or null")

    trace = event.get("trace")
    if trace is not None:
        _exact_keys(trace, {"traceparent", "tracestate"}, f"{where}.trace", errors)
        _require_keys(trace, {"traceparent"}, f"{where}.trace", errors)
        if isinstance(trace, dict):
            traceparent = trace.get("traceparent")
            if not isinstance(traceparent, str) or not TRACEPARENT.fullmatch(traceparent):
                errors.append(f"{where}.trace.traceparent: invalid W3C trace context")
            tracestate = trace.get("tracestate")
            if tracestate is not None and (not isinstance(tracestate, str) or len(tracestate) > 512):
                errors.append(f"{where}.trace.tracestate: expected string or null up to 512 characters")

    links = event.get("links")
    receipts = 0
    seen_links: set[tuple[object, object]] = set()
    if not isinstance(links, list) or not links:
        errors.append(f"{where}.links: expected a non-empty array")
    else:
        for index, link in enumerate(links):
            link_where = f"{where}.links[{index}]"
            _exact_keys(link, {"rel", "href", "title"}, link_where, errors)
            _require_keys(link, {"rel", "href"}, link_where, errors)
            if not isinstance(link, dict):
                continue
            rel = link.get("rel")
            href = link.get("href")
            if rel not in {"source", "subject", "receipt", "approval", "evidence", "result", "parent"}:
                errors.append(f"{link_where}.rel: unsupported relation")
            if not _valid_uri(href):
                errors.append(f"{link_where}.href: expected an absolute HTTPS URL or URN")
            title = link.get("title")
            if title is not None and (not isinstance(title, str) or not title.strip() or len(title) > 256):
                errors.append(f"{link_where}.title: expected non-empty string up to 256 characters")
            if rel == "receipt":
                receipts += 1
            pair = (rel, href)
            if pair in seen_links:
                errors.append(f"{link_where}: duplicate link")
            seen_links.add(pair)
        if receipts == 0:
            errors.append(f"{where}.links: at least one receipt relation is required")
    if not isinstance(event.get("payload"), dict):
        errors.append(f"{where}.payload: expected object")
    return errors


def validate_repository_registry(schema: object, registry: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(schema, dict) or not isinstance(registry, dict):
        return ["repository schema and registry must be objects"]
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append("repository schema: must declare JSON Schema draft 2020-12")
    if schema.get("additionalProperties") is not False:
        errors.append("repository schema: top level must be closed")
    allowed = set(schema.get("properties", {}))
    required = set(schema.get("required", []))
    _exact_keys(registry, allowed, "repository registry", errors)
    missing = sorted(required - set(registry))
    if missing:
        errors.append(f"repository registry: missing field(s): {', '.join(missing)}")
    if registry.get("schemaVersion") != "1.0":
        errors.append("repository registry: schemaVersion must be 1.0")

    repositories = registry.get("repositories")
    repo_by_name: dict[str, dict] = {}
    if not isinstance(repositories, list) or not repositories:
        errors.append("repository registry: repositories must be a non-empty array")
    else:
        allowed_repo_fields = {"name", "lifecycle", "role", "integrationMode", "importPolicy"}
        for index, entry in enumerate(repositories):
            where = f"repositories[{index}]"
            _exact_keys(entry, allowed_repo_fields, where, errors)
            _require_keys(entry, allowed_repo_fields, where, errors)
            if not isinstance(entry, dict):
                continue
            name = entry.get("name")
            if not isinstance(name, str) or not REPOSITORY.fullmatch(name):
                errors.append(f"{where}.name: invalid owner/name")
                continue
            if name in repo_by_name:
                errors.append(f"{where}.name: duplicate '{name}'")
            repo_by_name[name] = entry
            if entry.get("lifecycle") not in REPOSITORY_LIFECYCLES:
                errors.append(f"{where}.lifecycle: unsupported value")
            if (
                not isinstance(entry.get("role"), str)
                or not entry["role"].strip()
                or len(entry["role"]) > 256
            ):
                errors.append(f"{where}.role: expected non-empty string")
            if entry.get("integrationMode") not in INTEGRATION_MODES:
                errors.append(f"{where}.integrationMode: unsupported value")
            if entry.get("importPolicy") not in IMPORT_POLICIES:
                errors.append(f"{where}.importPolicy: unsupported value")

    authority = registry.get("authority")
    authority_fields = {
        "currentProductRepository",
        "plannedProductRepository",
        "integrationGovernanceRepository",
        "historicalProductRepository",
        "transitionUrl",
    }
    _exact_keys(authority, authority_fields, "authority", errors)
    _require_keys(authority, authority_fields, "authority", errors)
    if isinstance(authority, dict):
        lifecycle_rules = {
            "currentProductRepository": "active",
            "plannedProductRepository": "planned",
            "integrationGovernanceRepository": "active",
            "historicalProductRepository": "historical",
        }
        for field, expected_lifecycle in lifecycle_rules.items():
            name = authority.get(field)
            repository = repo_by_name.get(name)
            if repository is None:
                errors.append(f"authority.{field}: repository '{name}' is not registered")
            elif repository.get("lifecycle") != expected_lifecycle:
                errors.append(f"authority.{field}: expected {expected_lifecycle} repository")
        if not _valid_uri(authority.get("transitionUrl")):
            errors.append("authority.transitionUrl: expected absolute HTTPS URL")

    external = registry.get("externalAuthorities")
    expected_external = {
        "sourceControl": "github",
        "deployment": "github-protected-environments",
        "identity": "azure-workload-identity-federation",
        "secrets": "azure-key-vault",
    }
    _exact_keys(external, set(expected_external), "externalAuthorities", errors)
    _require_keys(external, set(expected_external), "externalAuthorities", errors)
    if isinstance(external, dict):
        for field, expected in expected_external.items():
            if external.get(field) != expected:
                errors.append(f"externalAuthorities.{field}: expected '{expected}'")

    capabilities = registry.get("capabilities")
    capability_ids: set[str] = set()
    if not isinstance(capabilities, list) or not capabilities:
        errors.append("repository registry: capabilities must be a non-empty array")
    else:
        allowed_capability_fields = {"id", "authorityRepository", "status", "description", "consumers"}
        for index, capability in enumerate(capabilities):
            where = f"capabilities[{index}]"
            _exact_keys(capability, allowed_capability_fields, where, errors)
            _require_keys(capability, allowed_capability_fields, where, errors)
            if not isinstance(capability, dict):
                continue
            identifier = capability.get("id")
            if not isinstance(identifier, str) or not EVENT_TYPE.fullmatch(identifier):
                errors.append(f"{where}.id: invalid capability id")
            elif identifier in capability_ids:
                errors.append(f"{where}.id: duplicate '{identifier}'")
            else:
                capability_ids.add(identifier)
            authority_name = capability.get("authorityRepository")
            authority_repo = repo_by_name.get(authority_name)
            if authority_repo is None:
                errors.append(f"{where}.authorityRepository: unregistered repository '{authority_name}'")
            status = capability.get("status")
            if status not in {"active", "planned", "reference-only"}:
                errors.append(f"{where}.status: unsupported value")
            elif authority_repo is not None:
                lifecycle = authority_repo.get("lifecycle")
                valid_lifecycles = {
                    "active": {"active", "satellite"},
                    "planned": {"planned"},
                    "reference-only": {"satellite", "historical", "recovery"},
                }[status]
                if lifecycle not in valid_lifecycles:
                    errors.append(f"{where}: {status} capability cannot be owned by {lifecycle} repository")
            if (
                not isinstance(capability.get("description"), str)
                or not capability["description"].strip()
                or len(capability["description"]) > 512
            ):
                errors.append(f"{where}.description: expected non-empty string")
            consumers = capability.get("consumers")
            if not isinstance(consumers, list) or any(not isinstance(item, str) or not item for item in consumers):
                errors.append(f"{where}.consumers: expected string array")
            elif len(consumers) != len(set(consumers)):
                errors.append(f"{where}.consumers: duplicate consumer")

    surfaces = registry.get("surfaces")
    surface_names: set[str] = set()
    deployment_authorities: list[str] = []
    if not isinstance(surfaces, list) or not surfaces:
        errors.append("repository registry: surfaces must be a non-empty array")
    else:
        allowed_surface_fields = {"name", "role", "eventSource", "receiptRequired", "deploymentAuthority"}
        for index, surface in enumerate(surfaces):
            where = f"surfaces[{index}]"
            _exact_keys(surface, allowed_surface_fields, where, errors)
            _require_keys(surface, allowed_surface_fields, where, errors)
            if not isinstance(surface, dict):
                continue
            name = surface.get("name")
            if not isinstance(name, str) or not EVENT_TYPE.fullmatch(name):
                errors.append(f"{where}.name: invalid surface name")
            elif name in surface_names:
                errors.append(f"{where}.name: duplicate '{name}'")
            else:
                surface_names.add(name)
            if not isinstance(surface.get("role"), str) or not surface["role"].strip():
                errors.append(f"{where}.role: expected non-empty string")
            for field in ("eventSource", "receiptRequired", "deploymentAuthority"):
                if type(surface.get(field)) is not bool:
                    errors.append(f"{where}.{field}: expected boolean")
            if surface.get("deploymentAuthority") is True:
                deployment_authorities.append(str(name))
            if surface.get("eventSource") is True and surface.get("receiptRequired") is not True:
                errors.append(f"{where}: event sources must require receipts")
        missing_surfaces = sorted(REQUIRED_SURFACES - surface_names)
        if missing_surfaces:
            errors.append(f"repository registry: missing surfaces: {', '.join(missing_surfaces)}")
        if deployment_authorities != ["github"]:
            errors.append("repository registry: github must be the only deployment-authority surface")

    provenance = registry.get("provenance")
    required_sources = {
        ("M0nado/helios-platform", "config/integrations/event-contract.schema.json"),
        ("M0nado/helios-platform", "config/integrations/repositories.json"),
        ("Yolkster64/helios-platform", "config/migration/yolkster-control/topology.v1.json"),
    }
    observed_sources: set[tuple[object, object]] = set()
    if not isinstance(provenance, list) or not provenance:
        errors.append("repository registry: provenance must be a non-empty array")
    else:
        allowed_provenance_fields = {"repository", "path", "blobSha", "relationship"}
        for index, source in enumerate(provenance):
            where = f"provenance[{index}]"
            _exact_keys(source, allowed_provenance_fields, where, errors)
            _require_keys(source, allowed_provenance_fields, where, errors)
            if not isinstance(source, dict):
                continue
            pair = (source.get("repository"), source.get("path"))
            if pair in observed_sources:
                errors.append(f"{where}: duplicate provenance source")
            observed_sources.add(pair)
            if source.get("repository") not in repo_by_name:
                errors.append(f"{where}.repository: source repository is not registered")
            if not isinstance(source.get("path"), str) or not source["path"].strip():
                errors.append(f"{where}.path: expected non-empty path")
            sha = source.get("blobSha")
            if not isinstance(sha, str) or not SOURCE_SHA.fullmatch(sha):
                errors.append(f"{where}.blobSha: expected immutable Git blob SHA")
            if source.get("relationship") not in {"adapted-from", "supersedes", "mirrors"}:
                errors.append(f"{where}.relationship: unsupported value")
        missing_sources = sorted(required_sources - observed_sources)
        if missing_sources:
            errors.append(f"repository registry: missing historical provenance {missing_sources}")
    return errors


def validate_all() -> list[str]:
    errors: list[str] = []
    try:
        event_schema = load_json(EVENT_SCHEMA_PATH)
        event_catalog = load_json(EVENT_TYPES_PATH)
        repository_schema = load_json(REPOSITORY_SCHEMA_PATH)
        repository_registry = load_json(REPOSITORY_REGISTRY_PATH)
    except (OSError, json.JSONDecodeError) as exc:
        return [f"contract inputs are unreadable: {exc}"]

    event_types, type_errors = validate_event_types(event_catalog)
    errors.extend(type_errors)
    errors.extend(validate_event_schema(event_schema, event_types))
    errors.extend(validate_repository_registry(repository_schema, repository_registry))
    if isinstance(event_schema, dict) and isinstance(repository_registry, dict):
        source_names = set(event_schema.get("properties", {}).get("source", {}).get("enum", []))
        surface_names = {
            surface.get("name")
            for surface in repository_registry.get("surfaces", [])
            if isinstance(surface, dict)
        }
        missing_sources = sorted(surface_names - source_names)
        if missing_sources:
            errors.append(
                "event schema: repository surfaces missing from source enum: "
                + ", ".join(missing_sources)
            )
    if isinstance(event_schema, dict):
        for path in sorted(EXAMPLES_PATH.glob("*.json")):
            try:
                event = load_json(path)
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"{path.relative_to(REPO_ROOT)}: unreadable: {exc}")
                continue
            errors.extend(validate_event(event, event_schema, event_types, str(path.relative_to(REPO_ROOT))))
    return errors


def main() -> int:
    errors = validate_all()
    if errors:
        for error in errors:
            print(f"FAIL: {error}", file=sys.stderr)
        print(f"integration contract validation FAILED: {len(errors)} error(s)", file=sys.stderr)
        return 1
    event_types, _ = validate_event_types(load_json(EVENT_TYPES_PATH))
    examples = len(list(EXAMPLES_PATH.glob("*.json")))
    repositories = len(load_json(REPOSITORY_REGISTRY_PATH)["repositories"])
    print(
        "integration contracts OK: "
        f"{len(event_types)} event types, {examples} examples, {repositories} repositories"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
