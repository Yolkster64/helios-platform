from __future__ import annotations

import pathlib
import tempfile
import unittest

from scripts.validation import validate_helios_fabric_contract as target

ROOT = pathlib.Path(__file__).resolve().parents[3]
CONTRACT = ROOT / "config/fabric/helios-fabric.v1.json"


class FabricContractValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.contract_text = CONTRACT.read_text(encoding="utf-8")

    def _validate_mutation(self, before: str, after: str, expected_error: str) -> None:
        self.assertIn(before, self.contract_text)
        mutated = self.contract_text.replace(before, after, 1)
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "helios-fabric.v1.json"
            path.write_text(mutated, encoding="utf-8")
            with self.assertRaisesRegex(AssertionError, expected_error):
                target.validate_contract(path)

    def test_current_contract_passes(self) -> None:
        result = target.validate_contract(CONTRACT)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["statusCounts"]["done"], 3)
        self.assertEqual(result["statusCounts"]["blocked"], 3)

    def test_fails_when_production_enabled_is_true(self) -> None:
        self._validate_mutation(
            '"productionEnabled": false',
            '"productionEnabled": true',
            "productionEnabled must be false",
        )

    def test_fails_when_slack_workspace_drifted(self) -> None:
        self._validate_mutation(
            '"workspaceId": "T0BAFGSNY5P"',
            '"workspaceId": "T0WRONG0000"',
            "workspaceId must remain T0BAFGSNY5P",
        )

    def test_fails_when_source_repository_drifted(self) -> None:
        self._validate_mutation(
            '"repository": "Yolkster64/helios-platform"',
            '"repository": "M0nado/helios-platform"',
            "sourcePullRequest.repository must be Yolkster64/helios-platform",
        )

    def test_fails_when_done_item_has_no_receipt(self) -> None:
        self._validate_mutation(
            '"status": "pending",',
            '"status": "done",',
            "done items must include receiptRef",
        )

    def test_fails_when_tool_name_drifted(self) -> None:
        self._validate_mutation(
            '"requiredTool": "helios_fabric_plan_get"',
            '"requiredTool": "helios_fabric_plan"',
            "mcp.requiredTool must be helios_fabric_plan_get",
        )

    def test_fails_when_required_check_name_drifted(self) -> None:
        self._validate_mutation(
            '"name": "PR Pipeline"',
            '"name": "Pipeline"',
            "exact check names/order",
        )

    def test_fails_when_checklist_id_is_duplicated(self) -> None:
        self._validate_mutation(
            '"id": "linear-joh-208-sync"',
            '"id": "slack-workspace-bind"',
            "checklist IDs must be unique",
        )

    def test_fails_when_secret_like_value_is_present(self) -> None:
        self._validate_mutation(
            '"issueKey": "JOH-208"',
            '"issueKey": "sk-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"',
            "secret-like value",
        )

    def test_fails_when_contract_has_unexpected_property(self) -> None:
        self._validate_mutation(
            '"migrationIssue": "HC-029",',
            '"migrationIssue": "HC-029",\n  "unexpectedFlag": true,',
            "schema validation failed at \\$: Additional properties are not allowed",
        )


if __name__ == "__main__":
    unittest.main()
