from __future__ import annotations

import json
import pathlib
import re
import tempfile
import unittest

from scripts.validation import validate_config_schemas as target

ROOT = pathlib.Path(__file__).resolve().parents[3]
SETTINGS = ROOT / ".vscode" / "settings.json"


def _mutate(manifest: str, before: str, after: str) -> str:
    text = (ROOT / manifest).read_text(encoding="utf-8")
    assert before in text, f"{manifest} no longer contains {before!r}"
    return text.replace(before, after, 1)


_DUE_ON = re.compile(r'"due_on": "\d{4}-\d{2}-\d{2}"')


def _first_due_on() -> str:
    """The first shipped `"due_on": "YYYY-MM-DD"` pair, so editing a milestone date does not break the mutations."""
    text = (ROOT / "config/github/milestones.json").read_text(encoding="utf-8")
    match = _DUE_ON.search(text)
    assert match, "config/github/milestones.json has no due_on to mutate"
    return match.group(0)


class MappingCoverageTests(unittest.TestCase):
    def test_every_mapped_manifest_passes_with_builtin_engine(self) -> None:
        results = target.validate_all_mapped(engine="builtin", repo_root=ROOT)
        self.assertGreaterEqual(len(results), 12)
        for result in results:
            self.assertEqual(result.engine, "builtin")
            self.assertTrue(result.valid, f"{result.manifest}: {[i.__dict__ for i in result.issues]}")

    @unittest.skipIf(target.jsonschema is None, "python-jsonschema not installed")
    def test_every_mapped_manifest_passes_with_jsonschema(self) -> None:
        for result in target.validate_all_mapped(engine="jsonschema", repo_root=ROOT):
            self.assertEqual(result.engine, "jsonschema")
            self.assertTrue(result.valid, f"{result.manifest}: {[i.__dict__ for i in result.issues]}")

    def test_map_validates_against_its_own_schema(self) -> None:
        mappings = target.load_mappings(ROOT)
        self.assertIn("config/schemas/manifests.json", [m.manifest for m in mappings])
        for mapping in mappings:
            self.assertTrue((ROOT / mapping.manifest).is_file(), mapping.manifest)
            self.assertTrue((ROOT / mapping.schema).is_file(), mapping.schema)

    def test_every_schema_uses_only_the_supported_subset(self) -> None:
        for schema_file in sorted((ROOT / "config" / "schemas").glob("*.schema.json")):
            schema = json.loads(schema_file.read_text(encoding="utf-8"))
            self.assertEqual(schema.get("$schema"), "https://json-schema.org/draft/2020-12/schema", schema_file.name)
            target.MiniValidator(schema)  # raises SchemaError on an unsupported keyword

    def test_vscode_settings_mirror_the_map(self) -> None:
        settings = json.loads(SETTINGS.read_text(encoding="utf-8"))
        entries = settings["json.schemas"]
        covered: dict[str, str] = {}
        for entry in entries:
            self.assertTrue(entry["url"].startswith("./config/schemas/"), entry["url"])
            self.assertTrue((ROOT / entry["url"][2:]).is_file(), entry["url"])
            for match in entry["fileMatch"]:
                covered[match.lstrip("/")] = entry["url"][2:]
        for mapping in target.load_mappings(ROOT):
            self.assertIn(mapping.manifest, covered, f".vscode/settings.json json.schemas lacks {mapping.manifest}")
            self.assertEqual(covered[mapping.manifest], mapping.schema, mapping.manifest)
        workflow_globs = settings["yaml.schemas"]["https://json.schemastore.org/github-workflow.json"]
        self.assertIn(".github/workflows/*.yml", workflow_globs)
        self.assertIn("templates/workflow.yml", workflow_globs)


class ShippedManifestMutationTests(unittest.TestCase):
    """Each mutation is a temp copy of the shipped file validated against its schema."""

    def _assert_invalid(self, manifest: str, before: str, after: str, path_fragment: str) -> None:
        mapping = target.find_mapping(manifest, target.load_mappings(ROOT))
        self.assertIsNotNone(mapping, manifest)
        mutated = _mutate(manifest, before, after)
        with tempfile.TemporaryDirectory() as temp:
            copy = pathlib.Path(temp) / pathlib.Path(manifest).name
            copy.write_text(mutated, encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(copy, ROOT / mapping.schema, engine=engine, repo_root=ROOT)
                self.assertFalse(result.valid, f"{engine}: {manifest} accepted {after!r}")
                self.assertTrue(
                    any(path_fragment in issue.path for issue in result.issues),
                    f"{engine}: no error at {path_fragment!r}: {[i.__dict__ for i in result.issues]}",
                )

    def test_label_seven_char_color(self) -> None:
        self._assert_invalid("config/github/labels.json", '"color": "d73a4a"', '"color": "d73a4a1"', "color")

    def test_label_unknown_key(self) -> None:
        self._assert_invalid("config/github/labels.json", '"color": "d73a4a"', '"colour": "d73a4a"', "labels[")

    def test_label_description_over_100_chars(self) -> None:
        self._assert_invalid(
            "config/github/labels.json",
            '"description": "Something isn\'t working"',
            '"description": "' + "x" * 101 + '"',
            "description",
        )

    def test_milestone_bad_calendar_date(self) -> None:
        self._assert_invalid("config/github/milestones.json", _first_due_on(), '"due_on": "2026-13-06"', "due_on")

    def test_milestone_impossible_date(self) -> None:
        self._assert_invalid("config/github/milestones.json", _first_due_on(), '"due_on": "2026-02-30"', "due_on")

    def test_milestone_unknown_key(self) -> None:
        self._assert_invalid("config/github/milestones.json", _first_due_on(), '"dueOn": "2026-09-06"', "milestones[")

    def test_connectors_bad_policy(self) -> None:
        self._assert_invalid("config/connectors.json", '"always"', '"sometimes"', "notifyOn")

    def test_connectors_env_name_is_a_value(self) -> None:
        self._assert_invalid("config/connectors.json", '"SLACK_WEBHOOK_URL"', '"https://hooks.example/abc"', "webhookUrlEnv")

    def test_connectors_typo_key(self) -> None:
        self._assert_invalid("config/connectors.json", '"notifyOn"', '"notifyon"', "slack")

    def test_fork_watch_unknown_signal(self) -> None:
        self._assert_invalid("config/fork-watch.json", '"signals": ["releases", "commits"]', '"signals": ["releases", "tags"]', "signals")

    def test_fork_watch_bad_slug(self) -> None:
        self._assert_invalid("config/fork-watch.json", '"repo": "linear/linear"', '"repo": "linear"', "repo")

    def test_watchlist_bad_status(self) -> None:
        self._assert_invalid("config/absorption/pr-watchlist.json", '"status": "absorbed"', '"status": "merged"', "status")

    def test_watchlist_pr_as_string(self) -> None:
        self._assert_invalid("config/absorption/pr-watchlist.json", '"pr": 222', '"pr": "222"', "pr")

    def test_fleet_topology_bad_mode(self) -> None:
        self._assert_invalid("config/fleet/fleet-topology.json", '"mode": "local"', '"mode": "remote"', "mode")

    def test_fleet_topology_wrong_version(self) -> None:
        self._assert_invalid("config/fleet/fleet-topology.json", '"version": 2', '"version": 3', "version")

    def test_fleet_topology_typo_key(self) -> None:
        self._assert_invalid("config/fleet/fleet-topology.json", '"maxLocalLanes": 4,', '"maxLocalLane": 4,', "autoscaling")

    def test_aihub_unknown_provider_type(self) -> None:
        self._assert_invalid("config/aihub.json", '"type": "ollama"', '"type": "llama"', "providers.ollama.type")

    def test_aihub_timeout_as_string(self) -> None:
        self._assert_invalid("config/aihub.json", '"timeoutSeconds": 300', '"timeoutSeconds": "300"', "timeoutSeconds")

    def test_aihub_secret_value_instead_of_env_name(self) -> None:
        self._assert_invalid("config/aihub.json", '"apiKeyEnv": "GITHUB_MODELS_TOKEN"', '"apiKeyEnv": "not-an-env-name"', "apiKeyEnv")

    def test_aihub_missing_routing(self) -> None:
        self._assert_invalid("config/aihub.json", '"routing": {', '"routes": {', "$")


class MiniValidatorTests(unittest.TestCase):
    def _errors(self, schema: dict, instance) -> list[str]:
        return [f"{i.path}: {i.message}" for i in target.MiniValidator(schema).iter_errors(instance)]

    def test_type_integer_accepts_integral_float_but_not_bool(self) -> None:
        schema = {"type": "integer"}
        self.assertEqual(self._errors(schema, 2.0), [])
        self.assertTrue(self._errors(schema, 2.5))
        self.assertTrue(self._errors(schema, True))

    def test_required_enum_const(self) -> None:
        schema = {"type": "object", "required": ["a"], "properties": {"a": {"enum": ["x", "y"]}, "b": {"const": 1}}}
        self.assertEqual(self._errors(schema, {"a": "x", "b": 1}), [])
        self.assertIn("$: 'a' is a required property", self._errors(schema, {}))
        self.assertTrue(self._errors(schema, {"a": "z"}))
        self.assertTrue(self._errors(schema, {"a": "x", "b": 2}))

    def test_pattern_is_unanchored_search(self) -> None:
        schema = {"type": "string", "pattern": "\\{number\\}"}
        self.assertEqual(self._errors(schema, "[GH-{number}] "), [])
        self.assertTrue(self._errors(schema, "[GH-] "))

    def test_length_and_item_bounds(self) -> None:
        self.assertTrue(self._errors({"maxLength": 3}, "abcd"))
        self.assertTrue(self._errors({"minLength": 1}, ""))
        self.assertTrue(self._errors({"minItems": 1}, []))
        self.assertTrue(self._errors({"maxItems": 1}, [1, 2]))
        self.assertTrue(self._errors({"uniqueItems": True}, [{"a": 1}, {"a": 1}]))
        self.assertEqual(self._errors({"uniqueItems": True}, [1, "1", True]), [])

    def test_additional_properties_false_names_the_keys(self) -> None:
        schema = {"type": "object", "properties": {"a": {}}, "additionalProperties": False}
        errors = self._errors(schema, {"a": 1, "b": 2, "c": 3})
        self.assertEqual(errors, ["$: Additional properties are not allowed ('b', 'c' were unexpected)"])

    def test_additional_properties_schema_and_property_names(self) -> None:
        schema = {"type": "object", "propertyNames": {"pattern": "^[a-z]+$"}, "additionalProperties": {"type": "integer"}}
        self.assertEqual(self._errors(schema, {"ab": 1}), [])
        self.assertTrue(self._errors(schema, {"Ab": 1}))
        self.assertTrue(self._errors(schema, {"ab": "1"}))

    def test_format_date_and_date_time(self) -> None:
        self.assertEqual(self._errors({"format": "date"}, "2028-02-29"), [])
        self.assertTrue(self._errors({"format": "date"}, "2026-02-29"))
        self.assertTrue(self._errors({"format": "date"}, "2026-9-6"))
        self.assertEqual(self._errors({"format": "date-time"}, "2026-09-06T12:00:00Z"), [])
        self.assertTrue(self._errors({"format": "date-time"}, "2026-09-06"))
        self.assertEqual(self._errors({"format": "uri"}, "not checked"), [])

    def test_ref_all_any_one_not_if(self) -> None:
        schema = {
            "$defs": {"s": {"type": "string"}},
            "type": "object",
            "properties": {
                "a": {"$ref": "#/$defs/s"},
                "b": {"anyOf": [{"type": "null"}, {"$ref": "#/$defs/s"}]},
                "c": {"oneOf": [{"type": "integer"}, {"type": "number"}]},
                "d": {"not": {"const": "no"}},
                "e": {"allOf": [{"minLength": 2}, {"maxLength": 3}]},
            },
            "if": {"properties": {"a": {"const": "done"}}},
            "then": {"required": ["r"]},
        }
        self.assertEqual(self._errors(schema, {"a": "x", "b": None, "c": 1.5, "d": "yes", "e": "ab"}), [])
        self.assertTrue(self._errors(schema, {"a": 1}))
        self.assertTrue(self._errors(schema, {"b": 1}))
        self.assertTrue(self._errors(schema, {"c": 1}))  # valid under both oneOf branches
        self.assertTrue(self._errors(schema, {"d": "no"}))
        self.assertTrue(self._errors(schema, {"e": "a"}))
        self.assertTrue(self._errors(schema, {"a": "done"}))
        self.assertEqual(self._errors(schema, {"a": "done", "r": 1}), [])

    def test_contains(self) -> None:
        schema = {"type": "array", "contains": {"const": 3}}
        self.assertEqual(self._errors(schema, [1, 3]), [])
        self.assertTrue(self._errors(schema, [1, 2]))

    def test_anyof_reports_closest_branch(self) -> None:
        schema = {"anyOf": [
            {"type": "object", "required": ["labels"], "additionalProperties": False, "properties": {"labels": {"type": "array"}}},
            {"type": "array"},
        ]}
        errors = self._errors(schema, {"label": []})
        self.assertIn("$: 'labels' is a required property", errors)
        self.assertTrue(any("'label' was unexpected" in e for e in errors))

    def test_unsupported_keyword_is_refused_not_ignored(self) -> None:
        with self.assertRaisesRegex(target.SchemaError, "dependentRequired"):
            target.MiniValidator({"type": "object", "dependentRequired": {"a": ["b"]}})
        with self.assertRaisesRegex(target.SchemaError, "does not resolve"):
            target.MiniValidator({"$ref": "#/$defs/missing"})
        with self.assertRaisesRegex(target.SchemaError, "invalid regex"):
            target.MiniValidator({"pattern": "("})

    @unittest.skipIf(target.jsonschema is None, "python-jsonschema not installed")
    def test_engines_agree_on_shipped_manifests_and_mutations(self) -> None:
        cases = [(m.manifest, m.schema) for m in target.load_mappings(ROOT)]
        for manifest, schema_path in cases:
            instance = json.loads((ROOT / manifest).read_text(encoding="utf-8"))
            schema = json.loads((ROOT / schema_path).read_text(encoding="utf-8"))
            library, _ = target.validate_instance(instance, schema, "jsonschema")
            builtin, _ = target.validate_instance(instance, schema, "builtin")
            self.assertEqual(bool(library), bool(builtin), manifest)


class CliTests(unittest.TestCase):
    def test_default_run_is_clean(self) -> None:
        self.assertEqual(target.main(["validate_config_schemas.py", "--repo-root", str(ROOT), "--engine", "builtin"]), 0)

    def test_list(self) -> None:
        self.assertEqual(target.main(["validate_config_schemas.py", "--repo-root", str(ROOT), "--list"]), 0)

    def test_broken_temp_copy_exits_1_and_unmapped_exits_2(self) -> None:
        mutated = _mutate("config/github/labels.json", '"color": "d73a4a"', '"color": "zzzzzz"')
        with tempfile.TemporaryDirectory() as temp:
            broken = pathlib.Path(temp) / "labels.json"
            broken.write_text(mutated, encoding="utf-8")
            self.assertEqual(
                target.main(["validate_config_schemas.py", "--repo-root", str(ROOT), "--engine", "builtin",
                             "--schema", "config/schemas/github-labels.schema.json", str(broken)]),
                1,
            )
            # No mapping and no --schema: the invocation is wrong, not the manifest.
            self.assertEqual(
                target.main(["validate_config_schemas.py", "--repo-root", str(ROOT), str(broken)]),
                2,
            )

    def test_single_mapped_manifest_by_relative_path(self) -> None:
        self.assertEqual(
            target.main(["validate_config_schemas.py", "--repo-root", str(ROOT), "--engine", "builtin",
                         "config/github/milestones.json"]),
            0,
        )


if __name__ == "__main__":
    unittest.main()


class ValidateAllDelegationTests(unittest.TestCase):
    """validate_all.py (the automation-wiring skill) delegates the schema check to THIS
    checkout's validator only; a scanned HELIOS-shaped tree is data, never code."""

    VALIDATE_ALL = ROOT / ".claude" / "skills" / "automation-wiring" / "scripts" / "validate_all.py"

    def _load_validate_all(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("helios_validate_all_under_test", self.VALIDATE_ALL)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        import sys
        sys.modules[spec.name] = module  # its dataclasses resolve their module at class creation
        spec.loader.exec_module(module)
        return module

    def test_trusted_validator_is_this_checkout(self) -> None:
        va = self._load_validate_all()
        self.assertEqual(va.trusted_validator(), ROOT / "scripts" / "validation" / "validate_config_schemas.py")

    def test_scanned_tree_validator_is_never_imported(self) -> None:
        """A crafted tree carries the two markers find_repo_root looks for plus a booby-trapped
        validator; the sweep must validate the tree's manifest as data with the trusted engine
        and never execute the tree's script."""
        import sys
        va = self._load_validate_all()
        with tempfile.TemporaryDirectory() as temp:
            tree = pathlib.Path(temp) / "crafted"
            (tree / "config" / "schemas").mkdir(parents=True)
            (tree / "scripts" / "validation").mkdir(parents=True)
            sentinel = pathlib.Path(temp) / "executed.txt"
            (tree / "scripts" / "validation" / "validate_config_schemas.py").write_text(
                f"open({str(sentinel)!r}, 'w').write('ran')\nraise RuntimeError('crafted validator executed')\n",
                encoding="utf-8")
            (tree / "config" / "schemas" / "manifests.json").write_text(json.dumps({
                "$comment": "crafted", "mappings": [{"manifest": "config/thing.json", "schema": "config/schemas/thing.schema.json"}]}),
                encoding="utf-8")
            (tree / "config" / "schemas" / "thing.schema.json").write_text(json.dumps({
                "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object",
                "required": ["name"], "additionalProperties": False, "properties": {"name": {"type": "string"}}}),
                encoding="utf-8")
            (tree / "config" / "thing.json").write_text(json.dumps({"nam": "typo"}), encoding="utf-8")
            report = va.Report()
            va.check_config_schemas([tree], report)
            self.assertFalse(sentinel.exists(), "the scanned tree's validator was executed")
            self.assertEqual(report.checked, 1)
            self.assertTrue(any("config/thing.json" in e or "thing.json" in e for e in report.errors), report.errors)
            self.assertTrue(any("'name' is a required property" in e or "name" in e for e in report.errors), report.errors)
            loaded = sys.modules.get("helios_validate_config_schemas")
            self.assertIsNotNone(loaded)
            self.assertEqual(pathlib.Path(loaded.__file__).resolve(),
                             (ROOT / "scripts" / "validation" / "validate_config_schemas.py").resolve())

    def test_real_checkout_config_manifests_are_checked(self) -> None:
        va = self._load_validate_all()
        report = va.Report()
        va.check_config_schemas([ROOT / "config"], report)
        expected = sum(1 for m in target.load_mappings(ROOT) if m.manifest.startswith("config/"))
        self.assertEqual(report.checked, expected)
        self.assertEqual(report.errors, [])
