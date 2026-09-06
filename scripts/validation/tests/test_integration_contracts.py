"""Regression tests for the dependency-free HELIOS integration contract validator."""

from __future__ import annotations

import copy
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


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
