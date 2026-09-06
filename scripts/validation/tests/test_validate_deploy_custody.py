#!/usr/bin/env python3
from __future__ import annotations

import unittest

from scripts.validation.validate_deploy_custody import ROOT, WORKFLOW, validate_workflow_text


class ValidateDeployCustodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow_text = WORKFLOW.read_text(encoding="utf-8")

    def test_current_workflow_passes_contract(self) -> None:
        self.assertEqual(validate_workflow_text(self.workflow_text), [])

    def test_missing_audience_fails(self) -> None:
        mutated = self.workflow_text.replace("audience: api://AzureADTokenExchange", "")
        errors = validate_workflow_text(mutated)
        self.assertTrue(any("audience" in error for error in errors))

    def test_secret_regression_fails(self) -> None:
        mutated = self.workflow_text + "\n      creds: ${{ secrets.AZURE_CLIENT_SECRET }}\n"
        errors = validate_workflow_text(mutated)
        self.assertTrue(any("stored creds JSON" in error for error in errors))

    def test_custody_naming_regression_fails(self) -> None:
        mutated = self.workflow_text.replace(
            'name: helios-deploy-custody-${{ github.run_id }}-${{ github.run_attempt }}',
            "name: helios-deploy-custody",
        )
        errors = validate_workflow_text(mutated)
        self.assertTrue(any("artifact name must include run_id + run_attempt" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
