from __future__ import annotations

import contextlib
import decimal
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import threading
import tempfile
import time
import unittest
import unittest.mock
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:  # lets `python3 scripts/validation/tests/test_validate_config_schemas.py` run from any cwd
    sys.path.insert(0, str(ROOT))

from scripts.validation import validate_config_schemas as target  # noqa: E402
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

    def test_unloadable_trusted_validator_is_an_error_not_a_crash(self) -> None:
        """The schema check is part of the sweep: a validator that cannot load must fail it
        (exit 1), never leave it green with every mapped manifest unchecked."""
        va = self._load_validate_all()
        with tempfile.TemporaryDirectory() as temp:
            broken = pathlib.Path(temp) / "validate_config_schemas.py"
            broken.write_text("raise RuntimeError('cannot import')\n", encoding="utf-8")
            va.trusted_validator = lambda: broken
            report = va.Report()
            va.check_config_schemas([ROOT / "config"], report)
            self.assertEqual(report.checked, 0)
            self.assertTrue(any("could not load the config schema validator" in e and "RuntimeError" in e for e in report.errors), report.errors)
            self.assertFalse(any("schema check skipped" in w for w in report.warnings), report.warnings)

    def test_real_checkout_config_manifests_are_checked(self) -> None:
        va = self._load_validate_all()
        report = va.Report()
        va.check_config_schemas([ROOT / "config"], report)
        expected = sum(1 for m in target.load_mappings(ROOT) if m.manifest.startswith("config/"))
        self.assertEqual(report.checked, expected)
        self.assertEqual(report.errors, [])


class EngineParityTests(unittest.TestCase):
    """The library engine and the built-in engine must give the same verdict, the same error
    paths and the same exit codes, so a runner with python-jsonschema and one without agree."""

    def _cli(self, *args: str) -> tuple[int, str]:
        proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validation" / "validate_config_schemas.py"), *args],
                              capture_output=True, text=True, cwd=ROOT)
        return proc.returncode, proc.stdout + proc.stderr

    def test_dangling_ref_is_a_schema_error_under_every_engine(self) -> None:
        schema = {"type": "object", "properties": {"a": {"$ref": "#/$defs/missing"}}}
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError, msg=engine):
                target.validate_instance({"a": 1}, schema, engine=engine)
        with tempfile.TemporaryDirectory() as temp:
            s = pathlib.Path(temp) / "s.json"; m = pathlib.Path(temp) / "m.json"
            s.write_text(json.dumps(schema), encoding="utf-8"); m.write_text("{\"a\": 1}", encoding="utf-8")
            for engine in target.available_engines():
                code, out = self._cli(str(m), "--schema", str(s), "--engine", engine)
                self.assertEqual(code, 2, (engine, out))
                self.assertNotIn("Traceback", out, engine)

    def test_date_time_format_is_enforced_under_every_engine(self) -> None:
        schema = {"type": "object", "properties": {"t": {"type": "string", "format": "date-time"}}}
        for engine in target.available_engines():
            bad, _ = target.validate_instance({"t": "not-a-date"}, schema, engine=engine)
            good, _ = target.validate_instance({"t": "2026-09-07T23:00:00Z"}, schema, engine=engine)
            self.assertTrue(bad, engine)
            self.assertEqual(good, [], engine)

    def test_error_paths_agree_for_property_names_and_unique_items(self) -> None:
        schema = {"type": "object", "propertyNames": {"pattern": "^[a-z]+$"},
                  "properties": {"xs": {"type": "array", "uniqueItems": True}}}
        paths = {}
        for engine in target.available_engines():
            issues, _ = target.validate_instance({"Bad": 1, "xs": [1, 1]}, schema, engine=engine)
            paths[engine] = sorted(issue.path for issue in issues)
        for engine, found in paths.items():
            self.assertEqual(found, ["$", "$.xs"], engine)

    def test_missing_manifest_path_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            s = pathlib.Path(temp) / "s.json"; s.write_text("{\"type\": \"object\"}", encoding="utf-8")
            code, out = self._cli(str(pathlib.Path(temp) / "nope.json"), "--schema", str(s))
            self.assertEqual(code, 2, out)
            self.assertIn("manifest not found", out)

    def test_date_time_shape_and_non_portable_patterns_agree_with_the_csharp_engine(self) -> None:
        schema = {"type": "object", "properties": {"t": {"type": "string", "format": "date-time"}}}
        for engine in target.available_engines():
            padded, _ = target.validate_instance({"t": " 2026-09-07T23:00:00Z"}, schema, engine=engine)
            prose, _ = target.validate_instance({"t": "Sept 7 2026 23:00"}, schema, engine=engine)
            self.assertTrue(padded, engine)
            self.assertTrue(prose, engine)
        for pattern in ("^a\\Z", "(?i)abc", "(?<=x)y"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=f"{engine} {pattern}"):
                    target.validate_instance("abc", {"type": "string", "pattern": pattern}, engine=engine)


class HardeningTests(unittest.TestCase):
    """Round 4 of PR #252: the two engines refuse the same malformed schemas, read the same JSON,
    stay inside the checkout, and enforce the rules a schema cannot express."""

    def _cli(self, *args: str) -> tuple[int, str]:
        proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validation" / "validate_config_schemas.py"), *args],
                              capture_output=True, text=True, cwd=ROOT)
        return proc.returncode, proc.stdout + proc.stderr

    def test_cyclic_ref_is_a_schema_error_under_every_engine(self) -> None:
        for schema in ({"$ref": "#"}, {"$defs": {"a": {"$ref": "#/$defs/b"}, "b": {"$ref": "#/$defs/a"}}, "$ref": "#/$defs/a"}):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(engine, schema)) as caught:
                    target.validate_instance({"a": 1}, schema, engine=engine)
                self.assertIn("cycle", str(caught.exception))
        with tempfile.TemporaryDirectory() as temp:
            s = pathlib.Path(temp) / "s.json"; m = pathlib.Path(temp) / "m.json"
            s.write_text(json.dumps({"$ref": "#"}), encoding="utf-8"); m.write_text("{}", encoding="utf-8")
            for engine in target.available_engines():
                code, out = self._cli(str(m), "--schema", str(s), "--engine", engine)
                self.assertEqual(code, 2, (engine, out))
                self.assertNotIn("Traceback", out, engine)

    def test_non_finite_json_constants_are_not_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            s = pathlib.Path(temp) / "s.json"; m = pathlib.Path(temp) / "m.json"
            s.write_text(json.dumps({"type": "object", "properties": {"x": {"type": "number", "minimum": 0}}}), encoding="utf-8")
            for token in ("NaN", "Infinity", "-Infinity"):
                m.write_text('{"x": %s}' % token, encoding="utf-8")
                code, out = self._cli(str(m), "--schema", str(s))
                self.assertEqual(code, 1, (token, out))  # an unreadable manifest is an invalid manifest
                self.assertIn("non-finite number token", out, token)
            # ... and in a schema it is an unusable input (exit 2), never a silently accepted number.
            s.write_text('{"type": "number", "minimum": NaN}', encoding="utf-8"); m.write_text("1", encoding="utf-8")
            code, out = self._cli(str(m), "--schema", str(s))
            self.assertEqual(code, 2, out)

    def test_mapped_paths_are_confined_to_the_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / "tree"
            (root / "config" / "schemas").mkdir(parents=True)
            secret = pathlib.Path(temp) / "secret.json"
            secret.write_text(json.dumps({"const": "TOP-SECRET-VALUE"}), encoding="utf-8")
            (root / "config" / "thing.json").write_text("{}", encoding="utf-8")
            for escaping in ("../secret.json", str(secret)):
                (root / "config" / "schemas" / "manifests.json").write_text(json.dumps({
                    "mappings": [{"manifest": "config/thing.json", "schema": escaping}]}), encoding="utf-8")
                mapping = target.load_mappings(root)[0]
                with self.assertRaises(ValueError, msg=escaping) as caught:
                    target.validate_mapping(mapping, repo_root=root)
                self.assertIn("outside the checkout", str(caught.exception))
                self.assertNotIn("TOP-SECRET", str(caught.exception))
            (root / "config" / "schemas" / "manifests.json").write_text(json.dumps({
                "mappings": [{"manifest": "../secret.json", "schema": "config/schemas/manifests.json"}]}), encoding="utf-8")
            with self.assertRaises(ValueError):
                target.validate_mapping(target.load_mappings(root)[0], repo_root=root)

    def test_date_time_requires_seconds_and_an_offset_under_every_engine(self) -> None:
        schema = {"type": "object", "properties": {"t": {"type": "string", "format": "date-time"}}}
        for engine in target.available_engines():
            for bad in ("2026-09-06T12:00", "2026-09-06T12:00:00", "2026-09-06T12:00:00.5", "2026-09-06 12:00:00Z", "2026-09-06T25:00:00Z"):
                issues, _ = target.validate_instance({"t": bad}, schema, engine=engine)
                self.assertTrue(issues, (engine, bad))
            for good in ("2026-09-06T12:00:00Z", "2026-09-06T12:00:00.250+02:00", "2026-09-06t12:00:00z", "2026-09-06T12:00:00-07:00"):
                issues, _ = target.validate_instance({"t": good}, schema, engine=engine)
                self.assertEqual(issues, [], (engine, good))

    def test_nested_quantifier_patterns_are_refused_under_every_engine(self) -> None:
        # The classic shape - a group that is one quantified atom, quantified again - is refused ...
        for pattern in ("^(a+)+$", "^(?:\\d*)*$", "^([a-z]+){2,}$", "^(x{2,})+$", "^(a+?)+$", "^(a?)+$"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(engine, pattern)) as caught:
                    target.validate_instance("aaaaaaaaaaaaaaaaaaaaaaaaaaaab", {"type": "string", "pattern": pattern}, engine=engine)
                self.assertIn("catastrophic backtracking", str(caught.exception))
        # ... while a quantified group that must consume a literal each iteration is linear and
        # stays accepted (the manifests map's repo-relative path pattern is exactly that shape).
        for pattern, value in (("^[a-z]+(-[a-z]+)*$", "abc-def"),
                               ("^([A-Za-z0-9_-][A-Za-z0-9._-]*/)*[A-Za-z0-9_-][A-Za-z0-9._-]*\\.json$", "config/github/labels.json"),
                               ("^(?:ab*)*c$", "abbbabc")):
            for engine in target.available_engines():
                issues, _ = target.validate_instance(value, {"type": "string", "pattern": pattern}, engine=engine)
                self.assertEqual(issues, [], (engine, pattern))

    def test_keyword_values_of_the_wrong_shape_are_schema_errors(self) -> None:
        for schema in ({"minLength": "1"}, {"minimum": "0"}, {"required": "name"}, {"enum": []},
                       {"uniqueItems": "yes"}, {"maxItems": -1}, {"minItems": True}, {"format": 3}):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(engine, schema)):
                    target.validate_instance("x", schema, engine=engine)
        with tempfile.TemporaryDirectory() as temp:
            s = pathlib.Path(temp) / "s.json"; m = pathlib.Path(temp) / "m.json"
            s.write_text(json.dumps({"type": "string", "minLength": "1"}), encoding="utf-8"); m.write_text('"x"', encoding="utf-8")
            code, out = self._cli(str(m), "--schema", str(s), "--engine", "builtin")
            self.assertEqual(code, 2, out)
            self.assertNotIn("Traceback", out)

    def test_aihub_provider_and_cli_agent_names_are_one_registry(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            m = pathlib.Path(temp) / "aihub.json"
            m.write_text(json.dumps({
                "providers": {"codex": {"type": "openai", "model": "gpt-5.1-codex-max", "apiKeyEnv": "OPENAI_API_KEY"}},
                "cliAgents": [{"name": "codex", "command": "codex", "argsTemplate": "exec {prompt}"},
                              {"name": "claude-cli", "command": "claude", "argsTemplate": "-p {prompt}"},
                              {"name": "claude-cli", "command": "claude", "argsTemplate": "-p {prompt}"},
                              {"name": "claude-cli", "enabled": False}],
                "routing": {"defaultChain": ["codex"], "taskRouting": {}}}), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(m, schema_path, engine=engine, repo_root=ROOT)
                paths = sorted(issue.path for issue in result.issues)
                self.assertEqual(paths, ["$.cliAgents[0].name", "$.cliAgents[2].name"], (engine, result.issues))
                self.assertTrue(all("one registry" in issue.message for issue in result.issues), result.issues)
            # The shipped hub configuration has no such collision under either engine.
            for engine in target.available_engines():
                shipped = target.validate_file(ROOT / "config" / "aihub.json", schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual(shipped.issues, [], engine)

    def test_aihub_model_baseurl_and_disabled_cli_agent_rules(self) -> None:
        schema = json.loads((ROOT / "config" / "schemas" / "aihub.schema.json").read_text(encoding="utf-8"))
        base = {"providers": {"p": {"type": "ollama", "model": "llama3"}}, "routing": {"defaultChain": ["p"], "taskRouting": {}}}
        cases = [
            ({"providers": {"p": {"type": "ollama"}}}, ["$.providers.p"]),
            ({"providers": {"p": {"type": "ollama", "enabled": False}}}, []),
            ({"providers": {"p": {"type": "anthropic", "apiKeyEnv": "ANTHROPIC_API_KEY"}}}, []),
            ({"providers": {"p": {"type": "openai", "model": "m", "baseUrl": "https://user:token@host/v1"}}}, ["$.providers.p.baseUrl"]),
            ({"providers": {"p": {"type": "openai", "model": "m", "baseUrl": "https://host/v1?api-key=secret"}}}, ["$.providers.p.baseUrl"]),
            ({"providers": {"p": {"type": "openai", "model": "m", "baseUrl": "https://host:8443/v1/"}}}, []),
            ({"cliAgents": [{"name": None, "command": None, "argsTemplate": None, "enabled": False}]}, []),
            ({"cliAgents": [{"enabled": False}]}, []),
            ({"cliAgents": [{"name": "x", "command": "x", "argsTemplate": "run {prompt}"}]}, []),
            ({"cliAgents": [{"name": None, "command": None, "argsTemplate": None}]}, ["$.cliAgents[0].argsTemplate", "$.cliAgents[0].command", "$.cliAgents[0].name"]),
            ({"cliAgents": [{"name": "x", "command": "x", "argsTemplate": "no slot"}]}, ["$.cliAgents[0].argsTemplate"]),
        ]
        for overlay, expected in cases:
            instance = {**base, **overlay}
            for engine in target.available_engines():
                issues, _ = target.validate_instance(instance, schema, engine=engine)
                self.assertEqual(sorted(issue.path for issue in issues), expected, (engine, overlay, issues))


class Round5Tests(unittest.TestCase):
    """Round 5 of PR #252: ambiguous alternations, the type keyword's shape, one schema per
    manifest, case-insensitive label names, baseUrl as a real URI, disabled providers, and the
    two consumer bounds (ContextTokens as a C# int, the 64-worker pool ceiling)."""

    def _cli(self, *args: str) -> tuple[int, str]:
        proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validation" / "validate_config_schemas.py"), *args],
                              capture_output=True, text=True, cwd=ROOT)
        return proc.returncode, proc.stdout + proc.stderr

    def test_quantified_alternations_are_refused_and_plain_ones_accepted(self) -> None:
        for pattern in ("^(a|aa)+$", "^(?:ab|a)*$", "^(x|y){2,}$", "^(a|aa|aaa)+$", "^((a|b)|c)+$"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(engine, pattern)) as caught:
                    target.validate_instance("aaaaaaaaaaaaaaaaaaaaaaaaaaaab", {"type": "string", "pattern": pattern}, engine=engine)
                self.assertIn("alternation", str(caught.exception))
        for pattern, value in (("^(dev|prod)$", "dev"), ("^(?:https?|wss?)://[a-z]+$", "https://x"),
                               ("^(a|b)?c$", "c"), ("^[ab]+$", "abab"), ("^(a|b)c(d|e)f$", "acdf"),
                               # a '(' or '|' inside a character class is a literal, not structure
                               ("^[(a|b)+]$", "a"), ("^(a|b){0,1}c$", "c"), ("^(ab|cd){1}$", "ab")):
            for engine in target.available_engines():
                issues, _ = target.validate_instance(value, {"type": "string", "pattern": pattern}, engine=engine)
                self.assertEqual(issues, [], (engine, pattern))
        # Every pattern the shipped schemas use stays accepted by both engines.
        for schema_file in sorted((ROOT / "config" / "schemas").glob("*.schema.json")):
            schema = json.loads(schema_file.read_text(encoding="utf-8"))
            for engine in target.available_engines():
                target.validate_instance({}, schema, engine=engine)

    def test_type_keyword_shape_is_checked_under_every_engine(self) -> None:
        for schema in ({"type": 1}, {"type": []}, {"type": ["string", 2]}, {"type": None}):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(engine, schema)):
                    target.validate_instance("x", schema, engine=engine)

    def test_a_manifest_has_exactly_one_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "config" / "schemas").mkdir(parents=True)
            for name in ("manifests.schema.json", "github-labels.schema.json"):
                (root / "config" / "schemas" / name).write_text((ROOT / "config" / "schemas" / name).read_text(encoding="utf-8"), encoding="utf-8")
            (root / "config" / "labels.json").write_text(json.dumps({"labels": [{"name": "bug", "color": "d73a4a"}]}), encoding="utf-8")
            (root / "config" / "schemas" / "manifests.json").write_text(json.dumps({"mappings": [
                {"manifest": "config/labels.json", "schema": "config/schemas/github-labels.schema.json"},
                {"manifest": "./config/labels.json", "schema": "config/schemas/manifests.schema.json"}]}), encoding="utf-8")
            with self.assertRaises(ValueError) as caught:
                target.load_mappings(root)
            self.assertIn("mapped twice", str(caught.exception))
            code, out = self._cli("--repo-root", str(root))
            self.assertEqual(code, 2, out)
            self.assertNotIn("Traceback", out)
            # The map validated as a manifest names the duplicate entry under both engines (an
            # exact duplicate here: "./" also fails the map's own path pattern, a second issue).
            (root / "config" / "schemas" / "manifests.json").write_text(json.dumps({"mappings": [
                {"manifest": "config/labels.json", "schema": "config/schemas/github-labels.schema.json"},
                {"manifest": "config/labels.json", "schema": "config/schemas/manifests.schema.json"}]}), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(root / "config" / "schemas" / "manifests.json",
                                              ROOT / "config" / "schemas" / "manifests.schema.json", engine=engine, repo_root=root)
                self.assertEqual([issue.path for issue in result.issues], ["$.mappings[1].manifest"], (engine, result.issues))
        # find_mapping normalizes exactly like the loader: a leading "./" is dropped, nothing else is.
        mappings = target.load_mappings(ROOT)
        self.assertIsNotNone(target.find_mapping("./config/github/labels.json", mappings))
        self.assertIsNotNone(target.find_mapping("config\\github\\labels.json", mappings))

    def test_duplicate_label_names_are_reported_case_insensitively(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "github-labels.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            m = pathlib.Path(temp) / "labels.json"
            for text, expected in ((json.dumps({"labels": [{"name": "Bug", "color": "d73a4a"}, {"name": "bug", "color": "d73a4a"}]}), ["$.labels[1].name"]),
                                   # 'straße' folds onto 'strasse' under casefold but not under the
                                   # C# twin's OrdinalIgnoreCase; both engines must say the same.
                                   (json.dumps([{"name": "strasse", "color": "d73a4a"}, {"name": "STRASSE", "color": "d73a4a"}]), ["$[1].name"]),
                                   (json.dumps([{"name": "strasse", "color": "d73a4a"}, {"name": "strasse-b", "color": "d73a4a"}]), []),
                                   (json.dumps([{"name": "Bug", "color": "d73a4a"}, {"name": "BUG", "color": "d73a4a"}, {"name": "docs", "color": "0075ca"}]), ["$[1].name"]),
                                   (json.dumps({"labels": [{"name": "bug", "color": "d73a4a"}, {"name": "docs", "color": "0075ca"}]}), [])):
                m.write_text(text, encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(m, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, text, result.issues))

    def test_aihub_base_url_must_be_an_absolute_http_uri(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            m = pathlib.Path(temp) / "aihub.json"
            for base_url, expected in (("https://:80/x", ["$.providers.p.baseUrl"]), ("https://host:bad/x", ["$.providers.p.baseUrl"]),
                                       # urlsplit raises on this one; it is a verdict, not a traceback
                                       ("https://[bad]/", ["$.providers.p.baseUrl"]),
                                       ("https://host:99999/x", ["$.providers.p.baseUrl"]), ("https://host:8443/v1/", []),
                                       ("http://localhost:11434", []), ("https://[::1]:8080/", [])):
                m.write_text(json.dumps({"providers": {"p": {"type": "ollama", "model": "llama3", "baseUrl": base_url}},
                                         "routing": {"defaultChain": ["p"], "taskRouting": {}}}), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(m, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, base_url, result.issues))

    def test_disabled_provider_name_may_be_reused_by_an_enabled_cli_agent(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            m = pathlib.Path(temp) / "aihub.json"
            for enabled, expected in ((False, []), (True, ["$.cliAgents[0].name"])):
                m.write_text(json.dumps({"providers": {"codex": {"type": "openai", "model": "m", "apiKeyEnv": "OPENAI_API_KEY", "enabled": enabled},
                                                       "p": {"type": "ollama", "model": "llama3"}},
                                         "cliAgents": [{"name": "codex", "command": "codex", "argsTemplate": "exec {prompt}"}],
                                         "routing": {"defaultChain": ["p"], "taskRouting": {}}}), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(m, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, enabled, result.issues))

    def test_consumer_bounds_context_tokens_and_pool_size(self) -> None:
        catalog = json.loads((ROOT / "config" / "model-catalog.json").read_text(encoding="utf-8"))
        catalog["models"][0]["contextTokens"] = 2147483648
        topology = json.loads((ROOT / "config" / "fleet" / "fleet-topology.json").read_text(encoding="utf-8"))
        topology["defaults"]["poolSize"] = 65
        for instance, schema_name, fragment in ((catalog, "model-catalog.schema.json", "contextTokens"),
                                                (topology, "fleet-topology.schema.json", "poolSize")):
            schema = json.loads((ROOT / "config" / "schemas" / schema_name).read_text(encoding="utf-8"))
            for engine in target.available_engines():
                issues, _ = target.validate_instance(instance, schema, engine=engine)
                self.assertTrue(any(fragment in issue.path for issue in issues), (engine, schema_name, issues))


class Round6Tests(unittest.TestCase):
    """Round 6 of PR #252: a clock instead of a list of bad regex shapes, numbers that survive the
    round trip, reachable routing chains, and two more identity rules (milestone titles, pool
    names)."""

    def _cli(self, *args: str) -> tuple[int, str]:
        proc = subprocess.run([sys.executable, str(ROOT / "scripts" / "validation" / "validate_config_schemas.py"), *args],
                              capture_output=True, text=True, cwd=ROOT)
        return proc.returncode, proc.stdout + proc.stderr

    def test_a_backtracking_pattern_is_abandoned_under_every_engine(self) -> None:
        # ^(a+a+)+$ is NOT a shape _catastrophic_shape names - that is the point of this test. A
        # scanner only knows the shapes it enumerates; the deadline bounds the match either way.
        # Unguarded, this subject runs for minutes under both engines.
        pattern = "^(a+a+)+$"
        self.assertIsNone(target._catastrophic_shape(pattern))
        for engine in target.available_engines():
            start = time.monotonic()
            with self.assertRaises(target.SchemaError, msg=engine) as caught:
                target.validate_instance("a" * 32 + "b", {"type": "string", "pattern": pattern}, engine=engine)
            elapsed = time.monotonic() - start
            self.assertIn("abandoned", str(caught.exception))
            self.assertLess(elapsed, target._LIBRARY_PASS_BUDGET_SECONDS + 15, (engine, elapsed))
        # The timer is disarmed afterwards: ordinary validation still works in this process.
        for engine in target.available_engines():
            issues, _ = target.validate_instance("abc", {"type": "string", "pattern": "^[a-z]+$"}, engine=engine)
            self.assertEqual(issues, [], engine)

    def test_a_repetition_count_no_engine_can_hold_is_a_verdict(self) -> None:
        # re.compile raises OverflowError, not re.error, and the C# twin's QuantifierAt would
        # overflow an int: both must report an unusable schema rather than crash. Round 10 moved
        # the refusal earlier - such a count is outside the range every engine holds - so the
        # verdict now names the count rather than the failed compile.
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError, msg=engine) as caught:
                target.validate_instance("a", {"type": "string", "pattern": "a{999999999999999999999999}"}, engine=engine)
            self.assertIn("repetition count above", str(caught.exception))

    def test_a_number_out_of_double_range_is_not_json(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "model-catalog.json"
            path.write_text('{"models": [{"contextTokens": 1e400}]}', encoding="utf-8")
            with self.assertRaises(ValueError) as caught:
                target.load_json(path, "manifest")
            self.assertIn("out of range", str(caught.exception))
            # As a manifest it is invalid (exit 1 territory), never a traceback out of the sweep.
            result = target.validate_file(path, ROOT / "config" / "schemas" / "model-catalog.schema.json", repo_root=ROOT)
            self.assertFalse(result.valid)
            self.assertIn("not valid JSON", result.issues[0].message)
            # A number a double CAN hold still reads normally — as a Decimal, which is what keeps
            # 9007199254740993.0 and 9007199254740992.0 two numbers rather than one float.
            path.write_text('{"models": [{"contextTokens": 1e308}]}', encoding="utf-8")
            loaded = target.load_json(path, "manifest")["models"][0]["contextTokens"]
            self.assertEqual(loaded, decimal.Decimal("1e308"))
            self.assertEqual(float(loaded), 1e308)

    def test_routing_chains_must_be_reachable(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        base = {
            "providers": {"live": {"type": "ollama", "model": "llama3"},
                          "parked": {"type": "ollama", "model": "llama3", "enabled": False}},
            "cliAgents": [{"name": "cx", "command": "codex", "argsTemplate": "exec {prompt}"}],
            "routing": {"defaultChain": ["live"], "taskRouting": {}},
        }
        cases: tuple[tuple[dict[str, list[str]], list[str]], ...] = (
            ({}, []),
            ({"code_review": ["cx", "live"]}, []),
            ({"code_review": ["parked", "cx"]}, []),                      # disabled first is a fallback, not a fault
            ({"code_review": ["parked"]}, ["$.routing.taskRouting.code_review"]),
            ({"code_review": ["typo"]}, ["$.routing.taskRouting.code_review[0]",
                                         "$.routing.taskRouting.code_review"]),
            ({"code_review": ["live", "typo"]}, ["$.routing.taskRouting.code_review[1]"]),
        )
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "aihub.json"
            for task_routing, expected in cases:
                instance = json.loads(json.dumps(base))
                instance["routing"]["taskRouting"] = task_routing
                manifest.write_text(json.dumps(instance), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, task_routing, result.issues))
            # A chain of nothing but disabled names is reported wherever it sits.
            instance = json.loads(json.dumps(base))
            instance["routing"]["defaultChain"] = ["parked"]
            manifest.write_text(json.dumps(instance), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual([issue.path for issue in result.issues], ["$.routing.defaultChain"], (engine, result.issues))

    def test_history_window_is_bounded_by_the_binder(self) -> None:
        schema = json.loads((ROOT / "config" / "schemas" / "aihub.schema.json").read_text(encoding="utf-8"))
        instance = json.loads((ROOT / "config" / "aihub.json").read_text(encoding="utf-8"))
        instance["learning"]["historyWindow"] = 2147483648
        for engine in target.available_engines():
            issues, _ = target.validate_instance(instance, schema, engine=engine)
            self.assertEqual([issue.path for issue in issues], ["$.learning.historyWindow"], (engine, issues))

    def test_duplicate_milestone_titles_are_reported_case_insensitively(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "github-milestones.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "milestones.json"
            for text, expected in (
                    (json.dumps({"milestones": [{"title": "Control fabric"}, {"title": "control FABRIC"}]}), ["$.milestones[1].title"]),
                    (json.dumps([{"title": "Owner setup"}, {"title": "owner setup"}]), ["$[1].title"]),
                    (json.dumps([{"title": "Owner setup"}, {"title": "Owner setup 2"}]), [])):
                manifest.write_text(text, encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, text, result.issues))

    def test_duplicate_fleet_pool_names_are_reported(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "fleet-topology.schema.json"
        topology = json.loads((ROOT / "config" / "fleet" / "fleet-topology.json").read_text(encoding="utf-8"))
        topology["pools"].append(json.loads(json.dumps(topology["pools"][0])))
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "fleet-topology.json"
            manifest.write_text(json.dumps(topology), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual([issue.path for issue in result.issues],
                                 [f"$.pools[{len(topology['pools']) - 1}].name"], (engine, result.issues))

    def test_case_folding_matches_the_csharp_comparer(self) -> None:
        # .NET's OrdinalIgnoreCase is a per-character invariant uppercase: it folds 'ς' onto 'Σ'
        # (str.lower() does not) and leaves 'ß' alone (str.upper() expands it to 'SS'). The two
        # engines must judge the same manifest the same way, so the Python side folds that way too.
        for left, right, duplicate in (("Σ", "ς", True),          # Σ / ς
                                       ("straße", "STRASSE", False),   # straße / STRASSE
                                       ("İ", "i̇", False),        # İ / i + combining dot
                                       ("Bug", "bug", True)):
            self.assertEqual(target._ordinal_ignore_case(left) == target._ordinal_ignore_case(right), duplicate,
                             (left, right))
        schema_path = ROOT / "config" / "schemas" / "github-milestones.schema.json"
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "milestones.json"
            for left, right, expected in (("Σ", "ς", ["$[1].title"]),
                                          ("straße", "STRASSE", [])):
                manifest.write_text(json.dumps([{"title": left}, {"title": right}]), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, left, right, result.issues))

    def test_an_undeliverable_alarm_is_not_claimed_as_a_deadline(self) -> None:
        if not hasattr(signal, "setitimer"):
            self.skipTest("no setitimer on this platform")
        self.assertTrue(target._alarm_deliverable())
        # A caller's own ITIMER_REAL is not ours to take, and a blocked SIGALRM would never arrive:
        # in both states this must report "no alarm here" so the isolated path is used instead.
        signal.setitimer(signal.ITIMER_REAL, 20, 3)
        try:
            self.assertFalse(target._alarm_deliverable())
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGALRM})
        try:
            self.assertFalse(target._alarm_deliverable())
        finally:
            signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGALRM})
        self.assertTrue(target._alarm_deliverable())

    def test_validation_off_the_main_thread_is_isolated_and_bounded(self) -> None:
        # A worker thread cannot receive SIGALRM, so the pass runs in a child that is killed on the
        # budget. The failure must arrive as this thread's exception - killing the whole process
        # (what a faulthandler watchdog does) would take a caller's service down with the pattern.
        answers: list[Any] = []

        def run(instance: Any, schema: dict[str, Any]) -> None:
            try:
                answers.append(target.validate_instance(instance, schema, engine="builtin"))
            except BaseException as exc:  # noqa: BLE001 - the test inspects whatever comes back
                answers.append(exc)

        worker = threading.Thread(target=run, args=("abc", {"type": "string", "pattern": "^[a-z]+$"}))
        worker.start()
        worker.join(60)
        self.assertEqual(answers[-1], ([], "builtin"), answers[-1])

        previous = target._LIBRARY_PASS_BUDGET_SECONDS
        target._LIBRARY_PASS_BUDGET_SECONDS = 1.0
        try:
            worker = threading.Thread(target=run, args=("a" * 32 + "b", {"type": "string", "pattern": "^(a+a+)+$"}))
            started = time.monotonic()
            worker.start()
            worker.join(60)
        finally:
            target._LIBRARY_PASS_BUDGET_SECONDS = previous
        self.assertIsInstance(answers[-1], target.SchemaError)
        self.assertIn("isolated validator was killed", str(answers[-1]))
        self.assertLess(time.monotonic() - started, 30)


class Round7Tests(unittest.TestCase):
    """Round 7 of PR #252: a JSON number keeps its value through parsing, the regex preflight is
    linear, a schema cannot spend unbounded work on one instance, and every integer field is
    bounded at its consumer's limit."""

    @staticmethod
    def _doubling_schema(levels: int = 20) -> dict[str, Any]:
        """An acyclic $defs chain whose allOf repeats the next $ref: 2**levels evaluations, with
        nesting far below the depth guard, so only a work budget stops it."""
        defs: dict[str, Any] = {f"l{levels}": {"type": "object"}}
        for level in range(levels - 1, -1, -1):
            nxt = {"$ref": f"#/$defs/l{level + 1}"}
            defs[f"l{level}"] = {"allOf": [nxt, dict(nxt)]}
        return {"$ref": "#/$defs/l0", "$defs": defs}

    def test_numbers_keep_their_value_through_parsing(self) -> None:
        # Two tokens that round to one float, and a token that underflows to zero: both engines
        # must keep them apart, exactly as the C# twin's CanonicalNumber does.
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "m.json"
            schema_file = pathlib.Path(temp) / "s.json"
            # BOTH sides are read through load_json: a Python float literal in this test would
            # collapse 9007199254740993.0 onto its neighbour before the engine ever saw it, which
            # is exactly the loss the round fixes.
            for schema_text, text, expected_valid in (
                    ('{"const": 9007199254740993.0}', '{"v": 9007199254740992.0}', False),
                    ('{"const": 9007199254740993.0}', '{"v": 9007199254740993.0}', True),
                    ('{"const": 0}', '{"v": 1e-324}', False),
                    ('{"const": 1}', '{"v": 1.0}', True),
                    ('{"const": 100}', '{"v": 1e2}', True),
                    ('{"type": "array", "uniqueItems": true}', '{"v": [9007199254740992.0, 9007199254740993.0]}', True),
                    ('{"type": "array", "uniqueItems": true}', '{"v": [1, 1.0]}', False),
                    ('{"type": "integer"}', '{"v": 4.0}', True),
                    ('{"type": "integer"}', '{"v": 4.5}', False),
                    ('{"minimum": 9007199254740993}', '{"v": 9007199254740992}', False)):
                manifest.write_text(text, encoding="utf-8")
                schema_file.write_text(schema_text, encoding="utf-8")
                schema = target.load_json(schema_file, "schema")
                instance = target.load_json(manifest, "manifest")["v"]
                for engine in target.available_engines():
                    issues, _ = target.validate_instance(instance, schema, engine=engine)
                    self.assertEqual(not issues, expected_valid, (engine, schema, text, issues))

    def test_the_regex_preflight_is_linear_in_the_pattern(self) -> None:
        # str.find per '{' made this quadratic: an 800 KB pattern of unmatched braces outran the
        # deadline before compilation started. The bounded window makes each position O(1).
        pattern = "{" * 200_000
        started = time.monotonic()
        self.assertIsNone(target._catastrophic_shape(pattern))
        self.assertLess(time.monotonic() - started, 2.0)
        # A real quantifier is still read as one, including the longest an engine can hold.
        self.assertEqual(target._quantifier_at("a{2,}", 1), (4, True))
        self.assertEqual(target._quantifier_at("a{1}", 1), (3, False))
        self.assertEqual(target._quantifier_at("a{" + "9" * 24 + "}", 1), (26, True))

    def test_a_schema_that_doubles_its_work_is_evaluated_once(self) -> None:
        # 2**40 evaluations of identical (schema node, instance node) pairs, with nesting far below
        # the depth guard. Memoized, it costs one evaluation per pair; the evaluation budget is the
        # backstop behind that, not what saves this case.
        started = time.monotonic()
        issues, _ = target.validate_instance({}, self._doubling_schema(levels=40), engine="builtin")
        self.assertEqual(issues, [])
        self.assertLess(time.monotonic() - started, 10)
        # Ordinary linear work is untouched by the budget: every array item is a distinct pair.
        issues, _ = target.validate_instance([0] * 199_998, {"items": {}}, engine="builtin")
        self.assertEqual(issues, [])

    def test_an_exponent_no_decimal_can_hold_is_a_verdict(self) -> None:
        # float() reads these as 0.0 or inf, so the finite check passes and the Decimal constructor
        # raises: that is the manifest's verdict, not a traceback through --json.
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "m.json"
            for token in ("1e-999999999999999999999999", "0e999999999999999999999999", "1e400"):
                manifest.write_text('{"v": %s}' % token, encoding="utf-8")
                with self.assertRaises(ValueError, msg=token) as caught:
                    target.load_json(manifest, "manifest")
                self.assertIn("out of range", str(caught.exception))

    def test_the_isolated_pass_keeps_exact_numbers(self) -> None:
        # The child is fed by _canonical, not json.dumps: a Decimal is not JSON-serializable, and
        # that TypeError would have been swallowed into an unbounded in-process validation.
        answers: list[Any] = []

        def run() -> None:
            try:
                answers.append(target.validate_instance(
                    {"n": decimal.Decimal("9007199254740993.0"), "s": "abc"},
                    {"properties": {"n": {"const": decimal.Decimal("9007199254740993.0")},
                                    "s": {"pattern": "^[a-z]+$"}}},
                    engine="builtin"))
            except BaseException as exc:  # noqa: BLE001 - the test inspects whatever comes back
                answers.append(exc)

        worker = threading.Thread(target=run)   # no deliverable alarm here, so the pass is isolated
        worker.start()
        worker.join(60)
        self.assertEqual(answers[-1], ([], "builtin"), answers[-1])

    def test_every_integer_field_is_bounded_at_its_consumer(self) -> None:
        topology = json.loads((ROOT / "config" / "fleet" / "fleet-topology.json").read_text(encoding="utf-8"))
        topology["defaults"]["hermesFleet"] = {"maxConcurrentLanes": 2147483648}
        schema = json.loads((ROOT / "config" / "schemas" / "fleet-topology.schema.json").read_text(encoding="utf-8"))
        for engine in target.available_engines():
            issues, _ = target.validate_instance(topology, schema, engine=engine)
            self.assertTrue(any("maxConcurrentLanes" in issue.path for issue in issues), (engine, issues))
        # Every integer field in every shipped schema carries an upper bound or a const.
        for schema_file in sorted((ROOT / "config" / "schemas").glob("*.schema.json")):
            document = json.loads(schema_file.read_text(encoding="utf-8"))
            unbounded: list[str] = []

            def walk(node: Any, where: str) -> None:
                if isinstance(node, dict):
                    if node.get("type") == "integer" and "maximum" not in node and "const" not in node:
                        unbounded.append(where)
                    for key, value in node.items():
                        walk(value, f"{where}/{key}")
                elif isinstance(node, list):
                    for index, value in enumerate(node):
                        walk(value, f"{where}/{index}")

            walk(document, "#")
            self.assertEqual(unbounded, [], f"{schema_file.name} has integer fields with no upper bound")


class Round8Tests(unittest.TestCase):
    """Round 8 of PR #252: shorthand classes that mean one thing in both engines, patternProperties
    keys that are compiled, semantics bound to the schema file rather than to an editable `$id`,
    and three more rules a schema cannot express."""

    def test_shorthand_classes_are_ascii_in_both_engines(self) -> None:
        # ECMA-262 (and the C# engine's ECMAScript mode) read \\d \\w \\s as ASCII; Python's default
        # is Unicode, so the same manifest would be valid in CI and invalid through the MCP tool.
        for pattern, value, expected_valid in (("^\\d+$", "123", True), ("^\\d+$", "٣٤", False),
                                               ("^\\w+$", "abc", True), ("^\\w+$", "é", False),
                                               ("^\\S+$", "a b", True)):
            for engine in target.available_engines():
                issues, _ = target.validate_instance(value, {"type": "string", "pattern": pattern}, engine=engine)
                self.assertEqual(not issues, expected_valid, (engine, pattern, value, issues))

    def test_a_pattern_properties_key_is_compiled(self) -> None:
        # With an instance that has no properties, nothing else would ever compile the key, and the
        # schema would pass as usable while python-jsonschema refuses it.
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError, msg=engine) as caught:
                target.validate_instance({}, {"type": "object", "patternProperties": {"[": {}}}, engine=engine)
            self.assertIn("pattern", str(caught.exception).lower())

    def test_case_insensitive_aliases_of_known_keys_are_refused(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        base: dict[str, Any] = {
            "providers": {"live": {"type": "ollama", "model": "llama3"}},
            "routing": {"defaultChain": ["live"], "taskRouting": {}},
        }
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "aihub.json"
            for overlay, expected in (
                    ({}, []),
                    ({"Providers": None}, ["$.Providers"]),
                    ({"Routing": {}}, ["$.Routing"]),
                    # 'LIVE' also fails the map's own propertyNames pattern, so both issues stand.
                    ({"providers": {"live": {"type": "ollama", "model": "llama3"}, "LIVE": {"type": "ollama", "model": "m"}}},
                     ["$.providers", "$.providers.LIVE"]),
                    ({"providers": {"live": {"type": "ollama", "model": "llama3", "Type": "openai"}}},
                     ["$.providers.live.Type"])):
                instance = json.loads(json.dumps(base))
                instance.update(overlay)
                manifest.write_text(json.dumps(instance), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual([issue.path for issue in result.issues], expected, (engine, overlay, result.issues))

    def test_duplicate_watchlist_pull_requests_are_reported(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "absorption-pr-watchlist.schema.json"
        watchlist = json.loads((ROOT / "config" / "absorption" / "pr-watchlist.json").read_text(encoding="utf-8"))
        candidates = watchlist["candidates"] if isinstance(watchlist, dict) else watchlist
        candidates.append(json.loads(json.dumps(candidates[0])))
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "pr-watchlist.json"
            manifest.write_text(json.dumps(watchlist), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual([issue.path for issue in result.issues],
                                 [f"$.candidates[{len(candidates) - 1}].pr"], (engine, result.issues))

    def test_semantics_follow_the_schema_file_not_its_id(self) -> None:
        # Removing or mistyping one `$id` line used to switch every semantic rule off silently.
        # The rule is now the schema FILE — but a file name alone is not identity, so it only
        # counts for a schema that lives in this checkout's config/schemas/.
        schema = json.loads((ROOT / "config" / "schemas" / "aihub.schema.json").read_text(encoding="utf-8"))
        schema.pop("$id", None)
        instance = {"providers": {"codex": {"type": "ollama", "model": "llama3"}},
                    "cliAgents": [{"name": "codex", "command": "codex", "argsTemplate": "exec {prompt}"}],
                    "routing": {"defaultChain": ["codex"], "taskRouting": {}}}
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "config" / "schemas").mkdir(parents=True)
            shipped = root / "config" / "schemas" / "aihub.schema.json"
            shipped.write_text(json.dumps(schema), encoding="utf-8")
            manifest = root / "config" / "aihub.json"
            manifest.write_text(json.dumps(instance), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, shipped, engine=engine, repo_root=root)
                self.assertEqual([issue.path for issue in result.issues], ["$.cliAgents[0].name"], (engine, result.issues))
            # The same file name somewhere else in the tree, with no HELIOS $id, is just a schema:
            # its name must not attach this repository's rules to it.
            elsewhere = root / "scratch"
            elsewhere.mkdir()
            (elsewhere / "aihub.schema.json").write_text(json.dumps(schema), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, elsewhere / "aihub.schema.json", engine=engine, repo_root=root)
                self.assertEqual(result.issues, [], (engine, result.issues))
        # And every shipped schema still carries the `$id` its file name implies, so the fallback
        # for an unmapped schema keeps working.
        for schema_file in sorted((ROOT / "config" / "schemas").glob("*.schema.json")):
            document = json.loads(schema_file.read_text(encoding="utf-8"))
            self.assertEqual(document.get("$id"), f"helios://config/schemas/{schema_file.name}", schema_file.name)

    def test_title_prefix_needs_a_marker_before_the_slot(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "connectors.schema.json"
        connectors = json.loads((ROOT / "config" / "connectors.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "connectors.json"
            for prefix, expected_valid in (("[GH-{number}] ", True), ("{number}", False),
                                           ("{number} [GH]", False), ("GH-", False),
                                           ("[GH-{number}]-{number} ", False)):
                connectors["linear"]["titlePrefix"] = prefix
                manifest.write_text(json.dumps(connectors), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual(result.valid, expected_valid, (engine, prefix, result.issues))


class Round8ParityTests(unittest.TestCase):
    """The parity gaps the local reviewer found inside round 8: the library engine decides
    pattern coverage and formats for itself, a nested dialect would hand a subtree back to it,
    and three rules read a value rather than a spelling."""

    def test_additional_properties_uses_the_same_matcher(self) -> None:
        # The library decides which properties patternProperties covers with its own Unicode
        # matcher: overriding patternProperties alone left a property matched there and validated
        # nowhere, so `additionalProperties: false` never fired.
        schema = {"type": "object", "patternProperties": {"^\\d+$": {"type": "integer"}},
                  "additionalProperties": False}
        for instance, expected_valid in (({"123": 4}, True), ({"٣": "wrong"}, False), ({"x": 1}, False)):
            for engine in target.available_engines():
                issues, _ = target.validate_instance(instance, schema, engine=engine)
                self.assertEqual(not issues, expected_valid, (engine, instance, issues))

    def test_a_nested_dialect_is_refused(self) -> None:
        # python-jsonschema re-selects a validator for a subschema that declares its own $schema,
        # which would drop this module's regex and number rules for that subtree.
        schema = {"properties": {"x": {"$schema": "https://json-schema.org/draft/2020-12/schema",
                                       "pattern": "^\\d+$"}}}
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError, msg=engine) as caught:
                target.validate_instance({"x": "٣"}, schema, engine=engine)
            self.assertIn("root of a schema", str(caught.exception))

    def test_only_this_modules_formats_are_checked(self) -> None:
        # The library's default checker also validates "regex", "uri" and more when their optional
        # packages are present, and would refuse a manifest both other engines accept.
        for engine in target.available_engines():
            issues, _ = target.validate_instance("[", {"type": "string", "format": "regex"}, engine=engine)
            self.assertEqual(issues, [], engine)
            issues, _ = target.validate_instance("not a date", {"type": "string", "format": "date"}, engine=engine)
            self.assertEqual(len(issues), 1, engine)

    def test_an_offset_is_a_real_offset(self) -> None:
        # fromisoformat normalizes +15:60 into +16:00 rather than refusing it; the shape fixes each
        # field's width, not its range, and the C# twin reads the digits.
        for value, expected_valid in (("2026-01-01T00:00:00+15:00", True), ("2026-01-01T00:00:00+23:59", True),
                                      ("2026-01-01T00:00:00+15:60", False), ("2026-01-01T00:00:00+24:00", False),
                                      ("2026-01-01T00:00:00Z", True)):
            for engine in target.available_engines():
                issues, _ = target.validate_instance(value, {"type": "string", "format": "date-time"}, engine=engine)
                self.assertEqual(not issues, expected_valid, (engine, value, issues))

    def test_metadata_keys_are_not_binder_collisions(self) -> None:
        # $comment and $schema bind to nothing, so a differently cased spelling cannot replace a
        # section - it is an unknown key, which this schema tolerates on purpose.
        schema_path = ROOT / "config" / "schemas" / "aihub.schema.json"
        instance = {"$Comment": "harmless metadata",
                    "providers": {"live": {"type": "ollama", "model": "llama3"}},
                    "routing": {"defaultChain": ["live"], "taskRouting": {}}}
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "aihub.json"
            manifest.write_text(json.dumps(instance), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual(result.issues, [], (engine, result.issues))

    def test_a_pull_request_number_is_a_value_not_a_spelling(self) -> None:
        schema_path = ROOT / "config" / "schemas" / "absorption-pr-watchlist.schema.json"
        watchlist = json.loads((ROOT / "config" / "absorption" / "pr-watchlist.json").read_text(encoding="utf-8"))
        candidates = watchlist["candidates"] if isinstance(watchlist, dict) else watchlist
        twin = json.loads(json.dumps(candidates[0]))
        twin["pr"] = float(twin["pr"])   # 191.0 is the same pull request as 191
        candidates.append(twin)
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "pr-watchlist.json"
            manifest.write_text(json.dumps(watchlist), encoding="utf-8")
            for engine in target.available_engines():
                result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                self.assertEqual([issue.path for issue in result.issues],
                                 [f"$.candidates[{len(candidates) - 1}].pr"], (engine, result.issues))

    def test_a_whitespace_only_loop_marker_is_refused(self) -> None:
        # linear-sync.yml derives the guard with `sed 's/{number}.*//'`; a marker of whitespace
        # collapses to the empty string in command substitution and the guard stops working.
        schema_path = ROOT / "config" / "schemas" / "connectors.schema.json"
        connectors = json.loads((ROOT / "config" / "connectors.json").read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as temp:
            manifest = pathlib.Path(temp) / "connectors.json"
            for prefix, expected_valid in (("[GH-{number}] ", True), ("\n{number}", False),
                                           ("   {number}", False), ("x{number}", True)):
                connectors["linear"]["titlePrefix"] = prefix
                manifest.write_text(json.dumps(connectors), encoding="utf-8")
                for engine in target.available_engines():
                    result = target.validate_file(manifest, schema_path, engine=engine, repo_root=ROOT)
                    self.assertEqual(result.valid, expected_valid, (engine, repr(prefix), result.issues))


class Round9Tests(unittest.TestCase):
    """Round 9 of PR #252: pattern-property matching is charged to the work budget, and the
    fleet's capacity fields carry an operational ceiling rather than an int one."""

    def test_pattern_property_matching_is_charged_to_the_budget(self) -> None:
        # P patterns against N keys is P×N matches; only _validate used to touch the budget, so a
        # large pair could spend millions of matches against one instance evaluation.
        patterns = {f"^a{index}[0-9]*$": {} for index in range(2000)}
        instance = {f"b{index}": 1 for index in range(2000)}
        started = time.monotonic()
        with self.assertRaises(target.SchemaError) as caught:
            target.validate_instance(instance, {"type": "object", "patternProperties": patterns}, engine="builtin")
        self.assertIn("keyword evaluations", str(caught.exception))
        self.assertLess(time.monotonic() - started, 60)
        # An ordinary manifest is nowhere near it: the shipped map has a handful of patterns.
        issues, _ = target.validate_instance({"a1": 1}, {"type": "object", "patternProperties": {"^a[0-9]$": {}}},
                                             engine="builtin")
        self.assertEqual(issues, [])

    def test_fleet_capacity_fields_have_an_operational_ceiling(self) -> None:
        schema = json.loads((ROOT / "config" / "schemas" / "fleet-topology.schema.json").read_text(encoding="utf-8"))
        base = json.loads((ROOT / "config" / "fleet" / "fleet-topology.json").read_text(encoding="utf-8"))
        for field, value, expected_valid in (("maxLocalLanes", 64, True), ("maxLocalLanes", 65, False),
                                             ("minLocalLanes", 65, False),
                                             ("maxBurstLanes", 256, True), ("maxBurstLanes", 257, False),
                                             ("maxBurstLanes", 2147483647, False),
                                             # a queue depth is a threshold, not a capacity
                                             ("scaleUpQueueDepth", 100000, True)):
            topology = json.loads(json.dumps(base))
            topology["defaults"]["autoscaling"][field] = value
            for engine in target.available_engines():
                issues, _ = target.validate_instance(topology, schema, engine=engine)
                self.assertEqual(not issues, expected_valid, (engine, field, value, issues))


class Round10Tests(unittest.TestCase):
    """Round 10 of PR #252: the work budget follows the library engine, the self-check has a
    depth of its own, integer tokens are held to the range a consumer can bind, one regex dialect
    covers Python's possessive quantifiers, and three more rules a schema cannot express."""

    def test_library_pattern_property_matching_is_charged_to_the_budget(self) -> None:
        # Round 9 charged the built-in engine's loop; python-jsonschema runs its own, and this
        # module's overridden keywords are where that work has to be counted. `auto` picks the
        # library whenever it is installed, so this is the DEFAULT path in CI.
        if target.jsonschema is None:
            self.skipTest("python-jsonschema is not installed")
        patterns = {f"^a{index}[0-9]*$": {} for index in range(2000)}
        instance = {f"b{index}": 1 for index in range(2000)}
        started = time.monotonic()
        with self.assertRaises(target.SchemaError) as caught:
            target.validate_instance(instance, {"type": "object", "patternProperties": patterns},
                                     engine="jsonschema")
        self.assertIn("keyword evaluations", str(caught.exception))
        self.assertLess(time.monotonic() - started, 60)

    def test_library_additional_property_coverage_is_charged_to_the_budget(self) -> None:
        if target.jsonschema is None:
            self.skipTest("python-jsonschema is not installed")
        # additionalProperties repeats the coverage matches; with additionalProperties present and
        # no property matching, every key is tried against every pattern a second time.
        patterns = {f"^a{index}[0-9]*$": {} for index in range(2000)}
        instance = {f"b{index}": 1 for index in range(2000)}
        with self.assertRaises(target.SchemaError) as caught:
            target.validate_instance(instance,
                                     {"type": "object", "patternProperties": patterns,
                                      "additionalProperties": True},
                                     engine="jsonschema")
        self.assertIn("keyword evaluations", str(caught.exception))

    def test_ordinary_manifests_are_nowhere_near_the_budget(self) -> None:
        for mapping in target.load_mappings():
            instance = target.load_json(ROOT / mapping.manifest, "manifest")
            schema = target.load_json(ROOT / mapping.schema, "schema")
            for engine in target.available_engines():
                issues, _ = target.validate_instance(instance, schema, engine=engine)
                self.assertEqual(issues, [], (mapping.manifest, engine, issues))

    def test_a_deeply_nested_schema_is_a_verdict_not_a_recursion_error(self) -> None:
        # CountEvaluation bounds the NUMBER of nodes, not the depth of the call stack: the walk
        # ran before any instance keyword and took the whole sweep down with a traceback.
        deep: dict[str, Any] = {}
        cursor = deep
        for _ in range(5000):
            cursor["not"] = {}
            cursor = cursor["not"]
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError) as caught:
                target.validate_instance({}, deep, engine=engine)
            self.assertIn("nesting deeper than", str(caught.exception), engine)

    def test_an_integer_token_no_consumer_can_hold_is_refused_while_reading(self) -> None:
        # json's own parser builds an int of any size, so only fractional and exponent tokens went
        # through the double-range check: a 400-digit price passed the model-catalog gate while
        # ModelCatalog.TryLoad could not bind it.
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "catalog.json"
            path.write_text('{"inputPerMillionUsd": ' + "9" * 400 + "}", encoding="utf-8")
            with self.assertRaises(ValueError) as caught:
                target.load_json(path, "manifest")
            self.assertIn("out of range for a JSON number", str(caught.exception))
            path.write_text('{"pr": 191, "delta": -3, "zero": 0}', encoding="utf-8")
            self.assertEqual(target.load_json(path, "manifest"), {"pr": 191, "delta": -3, "zero": 0})

    def test_possessive_quantifiers_are_outside_the_shared_dialect(self) -> None:
        # Python 3.11 accepts these; .NET's ECMAScript parser reads the second '+' as a nested
        # quantifier and refuses the pattern, so one schema had two verdicts.
        for pattern in ("a++", "a*+", "a?+", "a{2,3}+", "(ab)++", "(?>ab)+"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(pattern, engine)):
                    target.validate_instance("x", {"type": "string", "pattern": pattern}, engine=engine)
        # A literal plus, a lazy quantifier and every shipped pattern stay legal.
        for pattern in (r"\++", "a+?", "^[a-z]+(-[a-z]+)*$", r"^[A-Za-z0-9_-]+\.json$"):
            for engine in target.available_engines():
                target.validate_instance("a", {"type": "string", "pattern": pattern}, engine=engine)

    def test_a_model_catalog_pair_identifies_one_profile(self) -> None:
        catalog = target.load_json(ROOT / "config" / "model-catalog.json", "manifest")
        self.assertEqual(target._check_model_catalog(catalog), [])
        first = json.loads(json.dumps(catalog["models"][0], default=str))
        clashing = {"models": catalog["models"] + [dict(first, contextTokens=1)]}
        issues = target._check_model_catalog(clashing)
        self.assertEqual(len(issues), 1, issues)
        self.assertIn("identify one profile", issues[0].message)

    def test_the_fabric_contract_may_not_carry_secret_material(self) -> None:
        contract = target.load_json(ROOT / "config" / "fabric" / "helios-fabric.v1.json", "manifest")
        self.assertEqual(target._check_fabric_contract(contract), [])
        for value in ("sk-" + "a" * 24, "ghp_" + "b" * 24, "https://user:secret@example.invalid/x"):
            issues = target._check_fabric_contract({"checklist": [{"notes": value}]})
            self.assertEqual(len(issues), 1, (value, issues))
            self.assertEqual(issues[0].path, "$.checklist[0].notes")
        # A secret NAME is exactly what the contract is for.
        self.assertEqual(target._check_fabric_contract({"secretName": "openai-api-key"}), [])

    def test_the_fleet_is_bounded_in_aggregate_not_only_per_pool(self) -> None:
        schema = target.load_json(ROOT / "config" / "schemas" / "fleet-topology.schema.json", "schema")
        base = target.load_json(ROOT / "config" / "fleet" / "fleet-topology.json", "manifest")
        for engine in target.available_engines():
            issues, _ = target.validate_instance(base, schema, engine=engine)
            self.assertEqual(issues, [], (engine, issues))
        # The pool ARRAY is bounded: 1,000 pools of 64 workers used to validate.
        many = json.loads(json.dumps(base, default=str))
        pool = many["pools"][0]
        many["pools"] = [dict(pool, name=f"pool-{index}") for index in range(17)]
        for engine in target.available_engines():
            issues, _ = target.validate_instance(many, schema, engine=engine)
            self.assertTrue(issues, engine)
        # And so are the totals the scripts act on, inside the array bound.
        heavy = json.loads(json.dumps(base, default=str))
        heavy["defaults"]["poolSize"] = 64
        heavy["defaults"]["autoscaling"]["maxBurstLanes"] = 256
        # No hermesFleet cap on these: a declared maxConcurrentLanes clamps the spawn size, and
        # this is the case where nothing else stands between the topology and the host.
        heavy["pools"] = [{key: value for key, value in
                           dict(pool, name=f"pool-{index}", poolSize=64,
                                autoscaling=dict(pool.get("autoscaling", {}), maxBurstLanes=256)).items()
                           if key != "hermesFleet"}
                          for index in range(16)]
        messages = " ".join(issue.message for issue in target._check_fleet_pools(heavy))
        self.assertIn("worker processes together", messages)
        self.assertIn("az vmss scale", messages)



class Round10bTests(unittest.TestCase):
    """The defects the local reviewer found inside round 10: a cache that cached nothing, an
    exponent range the two engines did not share, a $ref the self-check never followed, a
    substring refusal that hit a character class, and fleet totals that did not resolve the way
    the fleet scripts resolve them."""

    def test_the_enum_cache_renders_the_instance_once(self) -> None:
        # dict.setdefault evaluates its default whether or not the key is present, so the instance
        # was still rendered once per option and the cache saved nothing.
        renders = 0
        original = target._canonical_key

        def counting(value: Any) -> str:
            nonlocal renders
            if value is instance:
                renders += 1
            return original(value)

        instance = "x" * 4096
        with unittest.mock.patch.object(target, "_canonical_key", counting):
            issues, _ = target.validate_instance(instance, {"enum": [f"o{index}" for index in range(500)]},
                                                 engine="builtin")
        self.assertEqual(len(issues), 1)
        self.assertEqual(renders, 1, f"the instance was rendered {renders} times")

    def test_both_engines_stop_at_the_same_exponent(self) -> None:
        # Decimal carries an exponent the C# normalizer cannot hold, and a token only one engine
        # can order is a manifest with two verdicts.
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "m.json"
            path.write_text('{"n": 1e-1000000000000000000}', encoding="utf-8")
            with self.assertRaises(ValueError) as caught:
                target.load_json(path, "manifest")
            self.assertIn("exponent is past", str(caught.exception))
            # Just inside the range is still exact, and still refused against a positive minimum.
            path.write_text('{"n": 1e-1000000001}', encoding="utf-8")
            instance = target.load_json(path, "manifest")
            for engine in target.available_engines():
                issues, _ = target.validate_instance(instance,
                                                     {"properties": {"n": {"minimum": 0, "exclusiveMinimum": 0}}},
                                                     engine=engine)
                self.assertEqual(issues, [], engine)

    def test_a_ref_may_only_point_where_the_self_check_walks(self) -> None:
        # Only $defs and definitions are walked as annotations, so a $ref into `default` validated
        # against a subschema whose keywords, patterns and numbers nothing had checked.
        # ...and naming a definition is not the same as descending into one: '#/$defs/a/default'
        # reached exactly the same unchecked place, one level lower.
        for pointer in ("#/default", "#/examples/0", "#/title", "#/$defs/a/default", "#/$defs"):
            schema = {"$ref": pointer, "default": {"pattern": "^(a+)+$"},
                      "examples": [{"pattern": "^(a+)+$"}], "title": "x",
                      "$defs": {"a": {"default": {"pattern": "^(a+)+$"}}}}
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(pointer, engine)) as caught:
                    target.validate_instance("a", schema, engine=engine)
                self.assertIn("$defs", str(caught.exception))
        # The shapes every shipped schema uses stay legal, cycles included.
        cyclic = {"$defs": {"a": {"not": {"$ref": "#/$defs/a"}}}, "$ref": "#/$defs/a"}
        target.MiniValidator(cyclic)
        target.MiniValidator({"properties": {"next": {"$ref": "#"}}})
        # ...including a root that declares its own dialect and is then referenced.
        target.MiniValidator({"$schema": "https://json-schema.org/draft/2020-12/schema",
                              "type": "object", "properties": {"next": {"$ref": "#"}}})

    def test_a_repetition_python_alone_understands_is_refused(self) -> None:
        # Python reads {,3} as {0,3} and .NET reads three literal characters, so `^a{,3}$` matches
        # "aa" in one engine and only the text "a{,3}" in the other - and `a{,3}+` is a possessive
        # quantifier that a scan needing a lower bound never sees.
        for pattern in ("a{,3}", "a{,3}+", "^a{,3}$", "a{,}", "a{,}+", "a{,}?"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(pattern, engine)):
                    target.validate_instance("aa", {"type": "string", "pattern": pattern}, engine=engine)
        # A brace that is not a repetition stays a literal in both.
        for engine in target.available_engines():
            issues, _ = target.validate_instance("a{,x}", {"type": "string", "pattern": "^a\\{,x\\}$"},
                                                 engine=engine)
            self.assertEqual(issues, [], engine)

    def test_a_repetition_count_no_engine_holds_is_refused(self) -> None:
        # Python compiles it; .NET refuses the pattern outright ("Quantifier and capture group
        # numbers must be less than or equal to Int32.MaxValue").
        for pattern in ("^a{0,2147483648}$", "a{2147483648}", "a{2147483648,}"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(pattern, engine)):
                    target.validate_instance("", {"type": "string", "pattern": pattern}, engine=engine)
        # The largest count both hold is still legal, however it is spelled.
        for pattern in ("a{2147483647}", "a{0002147483647}"):
            for engine in target.available_engines():
                target.validate_instance("a", {"type": "string", "pattern": pattern}, engine=engine)

    def test_an_exponents_leading_zeros_are_not_its_magnitude(self) -> None:
        # int() on a 4,301-digit string is refused outright by CPython, so reading the literal that
        # way refused `1e-000...01` - the exponent -1 - which .NET's long.TryParse accepts.
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "m.json"
            path.write_text('{"n": 1e-' + "0" * 4300 + '1}', encoding="utf-8")
            self.assertEqual(target._canonical(target.load_json(path, "manifest")), '{"n":0.1}')
            self.assertFalse(target._exponent_out_of_range("-" + "0" * 4300 + "1"))
            self.assertTrue(target._exponent_out_of_range("-1000000000000000000"))

    def test_the_two_engines_stop_at_the_exponent_as_written(self) -> None:
        # Judging a NORMALIZED exponent put these two on opposite sides of the limit in the two
        # engines: one is scaled up by its fraction, the other down by its trailing zero.
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "m.json"
            for token, readable in (("1.1e-999999999999999999", True),
                                    ("10e-1000000000000000000", False),
                                    ("0e-1000000001", True),
                                    ("0e1000000000000000000", False),
                                    # A large POSITIVE exponent is out of double range as well, so
                                    # both engines refuse it before the exponent limit is reached.
                                    ("1e999999999999999999", False),
                                    ("1e1000000000000000000", False)):
                path.write_text('{"n": ' + token + "}", encoding="utf-8")
                if readable:
                    self.assertIn("n", target.load_json(path, "manifest"), token)
                else:
                    with self.assertRaises(ValueError, msg=token):
                        target.load_json(path, "manifest")

    def test_a_character_class_is_not_an_atomic_group(self) -> None:
        # "(?>" as a raw substring hit "[(?>]" — three literal characters in a class.
        for engine in target.available_engines():
            issues, _ = target.validate_instance(">", {"type": "string", "pattern": "[(?>]"}, engine=engine)
            self.assertEqual(issues, [], engine)
            with self.assertRaises(target.SchemaError, msg=engine):
                target.validate_instance("ab", {"type": "string", "pattern": "(?>ab)"}, engine=engine)

    def test_fleet_totals_resolve_the_way_the_scripts_resolve_them(self) -> None:
        base = {"version": 2, "defaults": {}, "pools": []}

        def topology(pools: list[dict[str, Any]], defaults: dict[str, Any] | None = None) -> dict[str, Any]:
            return dict(base, defaults=defaults or {},
                        pools=[dict(pool, name=f"pool-{index}", taskTypes=["code"], providerChain=["openai"])
                               for index, pool in enumerate(pools)])

        # scale-fleet.ps1 defaults maxLocalLanes to minLocalLanes: a lone minimum IS the capacity.
        heavy = topology([{} for _ in range(5)], {"autoscaling": {"minLocalLanes": 64}})
        self.assertIn("maxLocalLanes totals 320",
                      " ".join(issue.message for issue in target._check_fleet_capacity(heavy)))
        # ...and it raises the maximum back to the minimum, so a small maximum does not help.
        heavy = topology([{} for _ in range(5)], {"autoscaling": {"minLocalLanes": 64, "maxLocalLanes": 1}})
        self.assertTrue(target._check_fleet_capacity(heavy))
        # A cloud pool holds no local lanes at all, so this one is safe and must pass.
        cloud = topology([{} for _ in range(5)], {"autoscaling": {"mode": "cloud", "maxLocalLanes": 64}})
        self.assertEqual([issue.message for issue in target._check_fleet_capacity(cloud)], [])
        # hermesFleet.maxConcurrentLanes clamps both the spawn size and the lane ceiling.
        capped = topology([{"poolSize": 64} for _ in range(5)],
                          {"autoscaling": {"maxLocalLanes": 64}, "hermesFleet": {"maxConcurrentLanes": 2}})
        self.assertEqual([issue.message for issue in target._check_fleet_capacity(capped)], [])
        # Burst counts only for a pool that may burst.
        local = topology([{} for _ in range(5)], {"autoscaling": {"mode": "local", "maxBurstLanes": 256}})
        self.assertEqual([issue.message for issue in target._check_fleet_capacity(local)], [])
        bursting = topology([{} for _ in range(5)], {"autoscaling": {"mode": "hybrid", "maxBurstLanes": 256}})
        self.assertIn("maxBurstLanes totals 1280",
                      " ".join(issue.message for issue in target._check_fleet_capacity(bursting)))
        # A whole number however it is spelled: PowerShell's [int] cast reads 64.0 as 64.
        spelled = topology([{} for _ in range(5)], {"poolSize": decimal.Decimal("64.0")})
        self.assertIn("worker processes together",
                      " ".join(issue.message for issue in target._check_fleet_capacity(spelled)))


class Round11Tests(unittest.TestCase):
    """Round 11 of PR #252: an error message renders only as far as the message will show it."""

    def test_a_message_does_not_render_the_whole_instance(self) -> None:
        # Brief built the entire canonical form and sliced it afterwards, so one failing branch
        # against a large instance paid for a full serialization to print 120 characters - and
        # every branch of an allOf paid again, all inside the evaluation budget.
        instance = {f"k{index}": "y" * 200 for index in range(200_000)}
        started = time.monotonic()
        text = target._brief(instance)
        self.assertLessEqual(len(text), 120)
        self.assertLess(time.monotonic() - started, 5)
        # A long scalar is the same cost by another route.
        started = time.monotonic()
        self.assertLessEqual(len(target._brief("z" * 5_000_000)), 120)
        self.assertLess(time.monotonic() - started, 5)

    def test_short_values_read_exactly_as_before(self) -> None:
        # The bound must not change any message a manifest actually produces.
        for value in ({"a": 1, "b": [1, 2]}, [1, 2, 3], "x", 1.5, None, True, {}, []):
            self.assertEqual(target._brief(value), target._canonical(value), value)

    def test_many_failing_branches_stay_cheap(self) -> None:
        # 2,000 false allOf branches against a large instance: the schema is well inside the
        # evaluation budget, so only the rendering bound keeps this finite.
        schema = {"allOf": [{"type": "string"} for _ in range(2_000)]}
        instance = {f"k{index}": "y" * 200 for index in range(20_000)}
        started = time.monotonic()
        issues, _ = target.validate_instance(instance, schema, engine="builtin")
        self.assertEqual(len(issues), 2_000)
        self.assertTrue(all(len(issue.message) < 200 for issue in issues))
        self.assertLess(time.monotonic() - started, 20)

    def test_the_schemas_own_values_are_bounded_too(self) -> None:
        # `enum` and `const` render the SCHEMA's value into the message, which is just as unbounded.
        issues, _ = target.validate_instance("no", {"enum": ["y" * 200_000, "b"]}, engine="builtin")
        self.assertEqual(len(issues), 1)
        self.assertLess(len(issues[0].message), 400)
        issues, _ = target.validate_instance("no", {"const": "y" * 200_000}, engine="builtin")
        self.assertEqual(len(issues), 1)
        self.assertLess(len(issues[0].message), 400)


class Round12Tests(unittest.TestCase):
    """Round 12 of PR #252: the isolating child's own import path, a self-check timeout that is a
    verdict, $defs shape, charged required-property checks, size bounds both engines hold, and
    three schema rules aligned with their consumers."""

    def test_the_isolating_child_does_not_import_from_the_scanned_tree(self) -> None:
        # P1: `python -c` puts the working directory at the FRONT of sys.path and honours
        # PYTHONPATH, so the child started while scanning an untrusted tree resolved `decimal`
        # from that tree and ran it - the code-execution path round 1 closed for the parent,
        # reopened by the isolation added later.
        with tempfile.TemporaryDirectory() as directory:
            tree = pathlib.Path(directory)
            sentinel = tree / "EXECUTED"
            (tree / "decimal.py").write_text(
                f"import pathlib\npathlib.Path({str(sentinel)!r}).write_text('ran')\n", encoding="utf-8")
            (tree / "json.py").write_text(
                f"import pathlib\npathlib.Path({str(sentinel)!r}).write_text('ran')\n", encoding="utf-8")
            here = pathlib.Path.cwd()
            previous = os.environ.get("PYTHONPATH")
            try:
                os.chdir(tree)
                os.environ["PYTHONPATH"] = str(tree)
                issues, _ = target._validate_in_child({"a": 1}, {"type": "object"}, "auto")
            finally:
                os.chdir(here)
                if previous is None:
                    os.environ.pop("PYTHONPATH", None)
                else:
                    os.environ["PYTHONPATH"] = previous
            self.assertEqual(issues, [])
            self.assertFalse(sentinel.exists(), "the scanned tree's module was imported by the child")

    def test_a_self_check_that_outruns_its_deadline_is_a_verdict(self) -> None:
        # _MatchTimeout is private to this module; the CLI and validate_all.py catch SchemaError,
        # so letting it escape the constructor aborted a whole sweep with a traceback.
        @contextlib.contextmanager
        def expired(_budget: float = 0.0):
            raise target._MatchTimeout()
            yield   # pragma: no cover - unreachable, keeps this a generator

        with unittest.mock.patch.object(target, "_match_deadline", expired):
            with self.assertRaises(target.SchemaError) as caught:
                target.MiniValidator({"type": "object"})
        self.assertIn("did not finish within", str(caught.exception))

    def test_defs_must_be_an_object(self) -> None:
        # python-jsonschema's own check_schema refuses this, so skipping it silently made a schema
        # usable in one engine and unusable in the other.
        for engine in target.available_engines():
            with self.assertRaises(target.SchemaError, msg=engine) as caught:
                target.validate_instance({}, {"$defs": [], "type": "object"}, engine=engine)
            self.assertIn("object of named schemas", str(caught.exception))
        for engine in target.available_engines():
            issues, _ = target.validate_instance({}, {"$defs": {}, "type": "object"}, engine=engine)
            self.assertEqual(issues, [], engine)

    def test_required_property_checks_are_charged(self) -> None:
        # A schema with 200,000 required names spent ONE evaluation and produced 200,000 issues,
        # so the budget could not see the work at all.
        names = [f"p{index}" for index in range(50_000)]
        checked = target.MiniValidator({"type": "object", "required": names})
        checked.iter_errors({})
        self.assertGreaterEqual(checked._evaluations, len(names),
                                "the required loop is not charged to the budget")
        # And past the ceiling it is a verdict rather than a list of a million issues.
        schema = {"type": "object", "required": [f"p{index}" for index in range(1_000_001)]}
        with self.assertRaises(target.SchemaError) as caught:
            target.validate_instance({}, schema, engine="builtin")
        self.assertIn("keyword evaluations", str(caught.exception))
        # An ordinary required list is nowhere near it.
        issues, _ = target.validate_instance({"a": 1}, {"type": "object", "required": ["a", "b"]},
                                             engine="builtin")
        self.assertEqual(len(issues), 1)

    def test_a_size_bound_stays_inside_what_both_engines_hold(self) -> None:
        # The C# twin reads these into a .NET int and compares them against a collection length,
        # so a larger bound was usable here and unusable there.
        for keyword in ("maxLength", "maxItems", "maxProperties", "minLength", "minItems"):
            for engine in target.available_engines():
                with self.assertRaises(target.SchemaError, msg=(keyword, engine)) as caught:
                    target.validate_instance("x", {keyword: 2147483648}, engine=engine)
                self.assertIn("2147483647", str(caught.exception))
                # The largest bound both hold is a usable schema (a min* bound legitimately fails
                # a short instance; what matters is that the SCHEMA is accepted).
                target.validate_instance("x", {keyword: 2147483647}, engine=engine)
        for engine in target.available_engines():
            issues, _ = target.validate_instance("x", {"maxLength": 2147483647}, engine=engine)
            self.assertEqual(issues, [], engine)

    def test_an_effective_assignee_prefix_is_unique(self) -> None:
        schema = target.load_json(ROOT / "config" / "schemas" / "fleet-topology.schema.json", "schema")
        base = target.load_json(ROOT / "config" / "fleet" / "fleet-topology.json", "manifest")
        for engine in target.available_engines():
            issues, _ = target.validate_instance(base, schema, engine=engine)
            self.assertEqual(issues, [], engine)
        # Two pools resolving to one prefix: both spawn "<prefix>-1" and write the same log path.
        clashing = json.loads(json.dumps(base, default=str))
        clashing["pools"][1]["assigneePrefix"] = clashing["pools"][0]["assigneePrefix"]
        issues = target._check_fleet_pools(clashing)
        self.assertEqual(len(issues), 1, issues)
        self.assertIn("effective assignee prefix", issues[0].message)
        # A pool that declares no prefix defaults to its name, so this collides too.
        defaulted = json.loads(json.dumps(base, default=str))
        defaulted["pools"][1].pop("assigneePrefix")
        defaulted["pools"][0]["assigneePrefix"] = defaulted["pools"][1]["name"]
        self.assertEqual(len(target._check_fleet_pools(defaulted)), 1)
        # A duplicate NAME is reported once, by the name rule, not twice.
        renamed = json.loads(json.dumps(base, default=str))
        renamed["pools"][1]["name"] = renamed["pools"][0]["name"]
        renamed["pools"][1]["assigneePrefix"] = renamed["pools"][0]["assigneePrefix"]
        self.assertEqual(len(target._check_fleet_pools(renamed)), 1)

    def test_a_qualified_pool_task_type_may_name_a_hyphenated_language(self) -> None:
        # TaskTypeRoutingStrategy.NormalizeLanguage leaves objective-c alone and the aihub schema
        # accepts it, so the topology must too.
        schema = target.load_json(ROOT / "config" / "schemas" / "fleet-topology.schema.json", "schema")
        base = target.load_json(ROOT / "config" / "fleet" / "fleet-topology.json", "manifest")
        topology = json.loads(json.dumps(base, default=str))
        topology["pools"][0]["taskTypes"] = ["code_generation:objective-c", "code_review:f_sharp"]
        for engine in target.available_engines():
            issues, _ = target.validate_instance(topology, schema, engine=engine)
            self.assertEqual(issues, [], (engine, issues))

    def test_the_watch_list_is_bounded_and_its_reasons_are_non_blank(self) -> None:
        schema = target.load_json(ROOT / "config" / "schemas" / "fork-watch.schema.json", "schema")
        base = target.load_json(ROOT / "config" / "fork-watch.json", "manifest")
        for engine in target.available_engines():
            issues, _ = target.validate_instance(base, schema, engine=engine)
            self.assertEqual(issues, [], engine)
        # fork-observation.yml walks the list serially with two 30-second requests per entry.
        long_list = json.loads(json.dumps(base, default=str))
        entry = long_list["repos"][0]
        long_list["repos"] = [dict(entry, repo=f"o/r{index}") for index in range(51)]
        for engine in target.available_engines():
            issues, _ = target.validate_instance(long_list, schema, engine=engine)
            self.assertTrue(issues, engine)
        # A reason of Unicode whitespace satisfies an ASCII \S but not the consumer's str.strip().
        blank = json.loads(json.dumps(base, default=str))
        blank["repos"][0]["because"] = "\u00a0\u2003"
        for engine in target.available_engines():
            issues, _ = target.validate_instance(blank, schema, engine=engine)
            self.assertEqual(issues, [], (engine, "the pattern alone still accepts it"))
        issues = target._check_fork_watch(blank)
        self.assertEqual(len(issues), 1, issues)
        self.assertIn("str.strip()", issues[0].message)
