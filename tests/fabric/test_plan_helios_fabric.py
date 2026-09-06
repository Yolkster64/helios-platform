from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "fabric" / "plan_helios_fabric.py"
CONFIG_PATH = ROOT / "config" / "fabric" / "helios-fabric.v1.json"

SPEC = importlib.util.spec_from_file_location("plan_helios_fabric", MODULE_PATH)
assert SPEC and SPEC.loader
fabric = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fabric)


class FabricContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))

    def test_canonical_contract_is_fail_closed(self) -> None:
        result = fabric.validate(self.config)
        self.assertEqual("1.0", result["schemaVersion"])
        self.assertEqual(14, result["integrations"])
        self.assertEqual(17, result["phases"])
        self.assertFalse(result["productionEnabled"])
        self.assertFalse(result["applyDefault"])
        self.assertEqual("F00", result["topologicalOrder"][0])
        self.assertEqual("F16", result["topologicalOrder"][-1])

    def test_plan_never_reads_secret_values(self) -> None:
        plan = fabric.build_plan(self.config, inspect_env=False)
        self.assertFalse(plan["environmentInspected"])
        self.assertFalse(plan["security"]["secretValuesRead"])
        self.assertFalse(plan["security"]["externalMutationPerformed"])
        self.assertEqual("WinUI 3", plan["security"]["activeUiFramework"])
        serialized = json.dumps(plan)
        self.assertNotIn("sk-proj-", serialized)
        self.assertNotIn("xoxb-", serialized)

    def test_production_phase_stays_disabled(self) -> None:
        plan = fabric.build_plan(self.config, inspect_env=False)
        phase = next(item for item in plan["phases"] if item["id"] == "F16")
        self.assertEqual("production-disabled", phase["readiness"])
        self.assertEqual("production-owner", phase["requiredApproval"])

    def test_mutating_phase_requires_approval(self) -> None:
        broken = copy.deepcopy(self.config)
        phase = next(item for item in broken["phases"] if item["id"] == "F02")
        phase["requiredApproval"] = "none"
        with self.assertRaisesRegex(fabric.ContractError, "mutates external state"):
            fabric.validate(broken)

    def test_cycle_is_rejected(self) -> None:
        broken = copy.deepcopy(self.config)
        first = next(item for item in broken["phases"] if item["id"] == "F00")
        first["dependsOn"] = ["F16"]
        with self.assertRaisesRegex(fabric.ContractError, "cycle"):
            fabric.validate(broken)

    def test_missing_integration_reference_is_rejected(self) -> None:
        broken = copy.deepcopy(self.config)
        broken["phases"][0]["requiredIntegrations"] = ["not-a-real-integration"]
        with self.assertRaisesRegex(fabric.ContractError, "missing integrations"):
            fabric.validate(broken)

    def test_secret_looking_value_is_rejected(self) -> None:
        broken = copy.deepcopy(self.config)
        broken["integrations"][0]["target"]["bad"] = "sk-proj-not-a-real-key"
        with self.assertRaisesRegex(fabric.ContractError, "credential value"):
            fabric.validate(broken)

    def test_allowed_denied_overlap_is_rejected(self) -> None:
        broken = copy.deepcopy(self.config)
        broken["integrations"][0]["allowed"].append(
            broken["integrations"][0]["denied"][0])
        with self.assertRaisesRegex(fabric.ContractError, "both allowed and denied"):
            fabric.validate(broken)

    def test_current_slack_target_has_no_fallback(self) -> None:
        slack = next(item for item in self.config["integrations"] if item["id"] == "slack")
        self.assertEqual("T0BAFGSNY5P", slack["target"]["workspaceId"])
        self.assertEqual("D0BB80HRZFA", slack["target"]["conversationId"])
        self.assertFalse(slack["target"]["fallbackAllowed"])

    def test_desktop_contract_is_winui_only(self) -> None:
        security = self.config["security"]
        self.assertEqual("WinUI 3", security["allowedUiFramework"])
        self.assertIn("WPF", security["forbiddenUiFrameworks"])
        self.assertIn("UWP", security["forbiddenUiFrameworks"])


if __name__ == "__main__":
    unittest.main()
