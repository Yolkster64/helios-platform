"""Regression tests for the dependency-free HELIOS integration contract validator."""

from __future__ import annotations

import copy
import importlib.util
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[3]
VALIDATOR_PATH = REPO_ROOT / "scripts" / "validation" / "validate_integration_contracts.py"
SPEC = importlib.util.spec_from_file_location("integration_contracts", VALIDATOR_PATH)
contracts = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(contracts)


class IntegrationContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.event_schema = contracts.load_json(contracts.EVENT_SCHEMA_PATH)
        cls.catalog = contracts.load_json(contracts.EVENT_TYPES_PATH)
        cls.event_types, cls.catalog_errors = contracts.validate_event_types(cls.catalog)
        cls.registry_schema = contracts.load_json(contracts.REPOSITORY_SCHEMA_PATH)
        cls.registry = contracts.load_json(contracts.REPOSITORY_REGISTRY_PATH)
        cls.example = contracts.load_json(
            contracts.EXAMPLES_PATH / "command-requested.v1.json"
        )

    def test_checked_in_contracts_are_valid(self):
        self.assertEqual(contracts.validate_all(), [])

    def test_event_vocabulary_covers_every_required_family(self):
        self.assertEqual(self.catalog_errors, [])
        self.assertEqual(
            {event["family"] for event in self.catalog["eventTypes"]},
            contracts.EVENT_FAMILIES,
        )

    def test_every_checked_in_example_is_registered_and_valid(self):
        for path in sorted(contracts.EXAMPLES_PATH.glob("*.json")):
            with self.subTest(path=path.name):
                event = contracts.load_json(path)
                self.assertIn(event["eventType"], self.event_types)
                self.assertEqual(
                    contracts.validate_event(event, self.event_schema, self.event_types),
                    [],
                )

    def test_missing_receipt_is_rejected(self):
        event = copy.deepcopy(self.example)
        event["links"] = [link for link in event["links"] if link["rel"] != "receipt"]
        errors = contracts.validate_event(event, self.event_schema, self.event_types)
        self.assertTrue(any("receipt" in error for error in errors), errors)

    def test_malformed_source_sha_is_rejected(self):
        event = copy.deepcopy(self.example)
        event["sourceSha"] = "main"
        errors = contracts.validate_event(event, self.event_schema, self.event_types)
        self.assertTrue(any("sourceSha" in error for error in errors), errors)

    def test_unknown_top_level_field_is_rejected(self):
        event = copy.deepcopy(self.example)
        event["secretFallback"] = "must-not-be-accepted"
        errors = contracts.validate_event(event, self.event_schema, self.event_types)
        self.assertTrue(any("unknown field" in error for error in errors), errors)

    def test_unregistered_event_type_is_rejected(self):
        event = copy.deepcopy(self.example)
        event["eventType"] = "deployment.magically-applied"
        errors = contracts.validate_event(event, self.event_schema, self.event_types)
        self.assertTrue(any("unregistered" in error for error in errors), errors)

    def test_unregistered_source_is_rejected(self):
        event = copy.deepcopy(self.example)
        event["source"] = "mystery-bot"
        errors = contracts.validate_event(event, self.event_schema, self.event_types)
        self.assertTrue(any("unregistered source" in error for error in errors), errors)

    def test_event_string_length_boundaries_match_schema(self):
        boundaries = [
            (("eventId",), 8, 128),
            (("entityId",), 1, 256),
            (("correlationId",), 4, 128),
            (("idempotencyKey",), 8, 256),
            (("actor", "id"), 1, 256),
            (("actor", "displayName"), 0, 256),
            (("links", 0, "title"), 1, 256),
            (("trace", "tracestate"), 0, 512),
        ]
        for path, minimum, maximum in boundaries:
            definition = self.event_schema
            for segment in path:
                definition = definition["items"] if isinstance(segment, int) else definition["properties"][segment]
            if "pattern" in definition:
                self.assertIsNotNone(re.fullmatch(definition["pattern"], "a" * minimum))
                self.assertIsNotNone(re.fullmatch(definition["pattern"], "a" * maximum))
                self.assertIsNone(re.fullmatch(definition["pattern"], "a" * (minimum - 1)))
                self.assertIsNone(re.fullmatch(definition["pattern"], "a" * (maximum + 1)))
            else:
                self.assertEqual(definition.get("minLength", 0), minimum)
                self.assertEqual(definition["maxLength"], maximum)
            for length in {0, minimum, maximum, maximum + 1}:
                with self.subTest(path=path, length=length):
                    event = copy.deepcopy(self.example)
                    event.setdefault("trace", {"traceparent": "00-" + "1" * 32 + "-" + "2" * 16 + "-01"})
                    parent = event
                    for segment in path[:-1]:
                        parent = parent[segment]
                    parent[path[-1]] = "a" * length
                    errors = contracts.validate_event(event, self.event_schema, self.event_types)
                    self.assertEqual(bool(errors), not minimum <= length <= maximum, errors)

    def test_optional_null_values_follow_schema(self):
        nullable = [
            ("repository",), ("entityId",), ("causationId",),
            ("actor", "displayName"), ("trace", "tracestate"),
        ]
        nonnullable = [("trace",), ("links", 0, "title")]
        for path in nullable + nonnullable:
            with self.subTest(path=path):
                event = copy.deepcopy(self.example)
                event.setdefault("trace", {"traceparent": "00-" + "1" * 32 + "-" + "2" * 16 + "-01"})
                parent = event
                for segment in path[:-1]:
                    parent = parent[segment]
                parent[path[-1]] = None
                errors = contracts.validate_event(event, self.event_schema, self.event_types)
                self.assertEqual(bool(errors), path in nonnullable, errors)

    def test_each_required_event_field_is_enforced(self):
        for field in self.event_schema["required"]:
            with self.subTest(field=field):
                event = copy.deepcopy(self.example)
                del event[field]
                errors = contracts.validate_event(event, self.event_schema, self.event_types)
                self.assertTrue(any("missing field" in error for error in errors), errors)

    def test_each_required_nested_event_field_is_enforced(self):
        for path in [("actor", "type"), ("actor", "id"), ("trace", "traceparent"),
                     ("links", 0, "rel"), ("links", 0, "href")]:
            with self.subTest(path=path):
                event = copy.deepcopy(self.example)
                event.setdefault("trace", {"traceparent": "00-" + "1" * 32 + "-" + "2" * 16 + "-01"})
                parent = event
                for segment in path[:-1]:
                    parent = parent[segment]
                del parent[path[-1]]
                errors = contracts.validate_event(event, self.event_schema, self.event_types)
                self.assertTrue(any("missing field" in error for error in errors), errors)

    def test_wrong_event_json_types_are_errors_not_exceptions(self):
        paths = [(field,) for field in self.event_schema["properties"] if field != "payload"]
        paths += [("actor", field) for field in ("type", "id", "displayName")]
        paths += [("trace", field) for field in ("traceparent", "tracestate")]
        paths += [("links", 0, field) for field in ("rel", "href", "title")]
        for path in paths:
            for invalid in ([], {}, 42, True):
                with self.subTest(path=path, invalid=invalid):
                    event = copy.deepcopy(self.example)
                    event.setdefault("trace", {"traceparent": "00-" + "1" * 32 + "-" + "2" * 16 + "-01"})
                    parent = event
                    for segment in path[:-1]:
                        parent = parent[segment]
                    parent[path[-1]] = invalid
                    self.assertTrue(contracts.validate_event(event, self.event_schema, self.event_types))
        for invalid in ([], 42, True, None):
            event = copy.deepcopy(self.example)
            event["payload"] = invalid
            self.assertTrue(contracts.validate_event(event, self.event_schema, self.event_types))

    def test_rfc3339_timestamps_require_wire_format_and_real_dates(self):
        valid = [
            "2026-09-06T12:00:00Z", "2026-09-06t12:00:00z",
            "2026-09-06T12:00:00.123456789+05:30", "2026-09-06T12:00:00-00:00",
            "2024-02-29T23:59:59Z", "2016-12-31T23:59:60Z",
            "2017-01-01T00:59:60+01:00",
        ]
        invalid = [
            "20260906T120000+00:00", "2026-09-06 12:00:00+00:00",
            "2026-09-06T12:00:00", "2026-09-06T12:00Z", "2026-09-06T12:00:00+0000",
            "2026-09-06T12:00:00+02:60", "2026-09-06T12:00:00+24:00",
            "2026-09-06T12:00:00+01:00:30", "2026-02-29T12:00:00Z",
            "2026-09-06T24:00:00Z", "2026-09-06T12:00:61Z",
            "2026-09-06T12:00:60Z", "2026-09-06T23:59:60Z",
        ]
        for value in valid + invalid:
            with self.subTest(value=value):
                event = copy.deepcopy(self.example)
                event["occurredAt"] = value
                errors = contracts.validate_event(event, self.event_schema, self.event_types)
                self.assertEqual(bool(errors), value in invalid, errors)

    def test_receipt_uri_syntax_and_credential_rejection(self):
        valid = [
            "https://github.com/Yolkster64/helios-platform/actions/runs/123",
            "https://example.invalid:443/a%20b?view=1#receipt",
            "https://127.0.0.1:8443/receipt", "https://[2001:db8::1]:443/receipt",
            "urn:helios:receipt:example-1",
        ]
        invalid = [
            "https://bad host/receipt", "https://example.invalid/line\nbreak",
            "https://example.invalid/line\tbreak", "https://example.invalid/\x00receipt",
            "https://example.invalid/\x7freceipt", "https://example.invalid/é",
            "https://user:password@example.invalid/receipt", "https://user@example.invalid/receipt",
            "https://example.invalid/%", "https://example.invalid/%zz", "https://example.invalid/[bad]",
            "https://example.invalid/receipt#first#second",
            "https://", "https:///receipt", "https://[invalid]/receipt", "https://[::1]suffix/receipt",
            "https://example.invalid:/receipt", "https://example.invalid:65536/receipt",
            "https://example.invalid:invalid/receipt", "https://-example.invalid/receipt",
            "https://example..invalid/receipt", "https://256.0.0.1/receipt",
            "https://example.invalid\\evil/receipt", "https://%65xample.invalid/receipt",
            "urn:", "urn:helios:", "urn:x:receipt", "http://example.invalid/receipt",
        ]
        for value in valid + invalid:
            with self.subTest(value=value):
                event = copy.deepcopy(self.example)
                event["links"] = [{"rel": "receipt", "href": value}]
                errors = contracts.validate_event(event, self.event_schema, self.event_types)
                self.assertEqual(bool(errors), value in invalid, errors)

    def test_schema_uri_patterns_match_validator_restrictions(self):
        href_pattern = self.event_schema["properties"]["links"]["items"]["properties"]["href"]["pattern"]
        transition_pattern = self.registry_schema["properties"]["authority"]["properties"]["transitionUrl"]["pattern"]
        self.assertIsNotNone(re.fullmatch(href_pattern, "https://example.invalid/receipt"))
        self.assertIsNotNone(re.fullmatch(href_pattern, "urn:helios:receipt:example-1"))
        self.assertIsNone(re.fullmatch(href_pattern, "https://user@example.invalid/receipt"))
        self.assertIsNone(re.fullmatch(href_pattern, "urn:"))
        self.assertIsNotNone(
            re.fullmatch(transition_pattern, "https://github.com/Yolkster64/helios-platform/pull/185")
        )
        self.assertIsNone(re.fullmatch(transition_pattern, "https://user@example.invalid/pull/185"))

    def test_catalog_malformed_json_types_are_errors_not_exceptions(self):
        paths = [("schemaVersion",), ("eventTypes",)]
        paths += [("eventTypes", 0, field) for field in self.catalog["eventTypes"][0]]
        for path in paths:
            for invalid in ([], {}, 42, None):
                with self.subTest(path=path, invalid=invalid):
                    catalog = copy.deepcopy(self.catalog)
                    parent = catalog
                    for segment in path[:-1]:
                        parent = parent[segment]
                    parent[path[-1]] = invalid
                    _, errors = contracts.validate_event_types(catalog)
                    self.assertTrue(errors)

    def test_registry_malformed_json_types_are_errors_not_exceptions(self):
        paths = [(field,) for field in self.registry]
        for group in ("authority", "externalAuthorities"):
            paths += [(group, field) for field in self.registry[group]]
        for group in ("repositories", "capabilities", "surfaces", "provenance"):
            paths += [(group, 0, field) for field in self.registry[group][0]]
        for path in paths:
            for invalid in ([], {}, 42, None):
                if path[-1] == "consumers" and invalid == []:
                    continue  # This is an explicitly permitted empty array.
                with self.subTest(path=path, invalid=invalid):
                    registry = copy.deepcopy(self.registry)
                    parent = registry
                    for segment in path[:-1]:
                        parent = parent[segment]
                    parent[path[-1]] = invalid
                    self.assertTrue(contracts.validate_repository_registry(self.registry_schema, registry))
        for invalid_consumer in ([], {}):
            registry = copy.deepcopy(self.registry)
            registry["capabilities"][0]["consumers"] = [invalid_consumer]
            self.assertTrue(contracts.validate_repository_registry(self.registry_schema, registry))

    def test_registry_lengths_and_transition_https_are_enforced(self):
        for group, field, maximum in [("repositories", "role", 256),
                                      ("capabilities", "description", 512),
                                      ("surfaces", "role", 256)]:
            for length in (0, maximum, maximum + 1):
                with self.subTest(group=group, length=length):
                    registry = copy.deepcopy(self.registry)
                    registry[group][0][field] = "a" * length
                    errors = contracts.validate_repository_registry(self.registry_schema, registry)
                    self.assertEqual(bool(errors), length != maximum, errors)
        registry = copy.deepcopy(self.registry)
        registry["authority"]["transitionUrl"] = "urn:helios:transition"
        self.assertTrue(contracts.validate_repository_registry(self.registry_schema, registry))

    def test_each_required_registry_field_is_enforced(self):
        paths = [(field,) for field in self.registry_schema["required"]]
        for group in ("authority", "externalAuthorities"):
            paths += [(group, field) for field in self.registry_schema["properties"][group]["required"]]
        for group in ("repositories", "capabilities", "surfaces", "provenance"):
            definition = self.registry_schema["properties"][group]["items"]
            paths += [(group, 0, field) for field in definition["required"]]
        for path in paths:
            with self.subTest(path=path):
                registry = copy.deepcopy(self.registry)
                parent = registry
                for segment in path[:-1]:
                    parent = parent[segment]
                del parent[path[-1]]
                errors = contracts.validate_repository_registry(self.registry_schema, registry)
                self.assertTrue(any("missing field" in error for error in errors), errors)

    def test_aggregate_validation_reports_malformed_surface_without_crashing(self):
        original_load = contracts.load_json
        for malformed in (None, [{"name": []}], [{"name": {}}]):
            with self.subTest(malformed=malformed):
                registry = copy.deepcopy(self.registry)
                registry["surfaces"] = malformed

                def load_fixture(path):
                    return registry if path == contracts.REPOSITORY_REGISTRY_PATH else original_load(path)

                with patch.object(contracts, "load_json", side_effect=load_fixture):
                    self.assertTrue(contracts.validate_all())

    def test_duplicate_repository_is_rejected(self):
        registry = copy.deepcopy(self.registry)
        registry["repositories"].append(copy.deepcopy(registry["repositories"][0]))
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("duplicate" in error for error in errors), errors)

    def test_missing_repository_field_is_rejected(self):
        registry = copy.deepcopy(self.registry)
        del registry["repositories"][0]["integrationMode"]
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("missing field" in error for error in errors), errors)

    def test_invalid_repository_enum_is_rejected(self):
        registry = copy.deepcopy(self.registry)
        registry["repositories"][0]["importPolicy"] = "copy-everything"
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("importPolicy" in error for error in errors), errors)

    def test_historical_repository_cannot_own_active_capability(self):
        registry = copy.deepcopy(self.registry)
        registry["capabilities"][0]["authorityRepository"] = "M0nado/helios-platform"
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("active capability" in error for error in errors), errors)

    def test_current_yolkster_topology_provenance_is_required(self):
        registry = copy.deepcopy(self.registry)
        registry["provenance"] = [
            source
            for source in registry["provenance"]
            if source["path"] != "config/migration/yolkster-control/topology.v1.json"
        ]
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("missing historical provenance" in error for error in errors), errors)

    def test_only_github_is_deployment_authority(self):
        registry = copy.deepcopy(self.registry)
        next(surface for surface in registry["surfaces"] if surface["name"] == "azure")[
            "deploymentAuthority"
        ] = True
        errors = contracts.validate_repository_registry(self.registry_schema, registry)
        self.assertTrue(any("only deployment-authority" in error for error in errors), errors)

    def test_cli_resolves_contracts_outside_repository_working_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, str(VALIDATOR_PATH)],
                cwd=directory,
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("integration contracts OK", result.stdout)


if __name__ == "__main__":
    unittest.main()
