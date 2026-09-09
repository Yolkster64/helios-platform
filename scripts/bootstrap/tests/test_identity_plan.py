"""Offline identity handoff contracts; no Azure tenant or token is used."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("identity_plan", ROOT / "scripts/bootstrap/identity_plan.py")
identity_plan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(identity_plan)
TARGET = {
    "AZURE_TENANT_ID": "11111111-1111-4111-8111-111111111111",
    "AZURE_SUBSCRIPTION_ID": "22222222-2222-4222-8222-222222222222",
    "AZURE_CLIENT_ID": "33333333-3333-4333-8333-333333333333",
    "AZURE_RESOURCE_GROUP": "helios-dev-rg",
    "AZURE_LOCATION": "eastus2",
    "AZURE_KEY_VAULT_NAME": "kv-helios-plan",
}


class IdentityPlanTests(unittest.TestCase):
    def test_empty_target_reports_missing_without_assuming_live_defaults(self):
        plan = identity_plan.build_plan({})
        self.assertEqual(plan["schemaVersion"], 1)
        self.assertEqual(plan["status"], "incomplete")
        self.assertEqual(set(plan["missingInputs"]), set(TARGET))
        self.assertIsNone(plan["target"]["resourceGroupId"])
        self.assertFalse(plan["liveVerified"])
        self.assertFalse(plan["applyEnabled"])

    def test_complete_target_is_only_prepared_and_never_live(self):
        plan = identity_plan.build_plan(TARGET)
        self.assertEqual(plan["status"], "prepared")
        self.assertEqual(plan["missingInputs"], [])
        self.assertEqual(plan["invalidInputs"], [])
        self.assertFalse(plan["liveVerified"])
        self.assertFalse(plan["bicep"]["executed"])
        self.assertIn("Microsoft.Authorization/roleAssignments/write", " ".join(plan["remainingGates"]))

    def test_federation_pins_protected_environment_not_pull_request(self):
        github = identity_plan.build_plan(TARGET)["github"]
        self.assertEqual(github["federatedCredential"], {
            "issuer": "https://token.actions.githubusercontent.com",
            "subject": "repo:Yolkster64/helios-platform:environment:azure-dev",
            "audiences": ["api://AzureADTokenExchange"],
        })
        self.assertEqual(github["event"], "workflow_dispatch")
        self.assertEqual(github["ref"], "refs/heads/main")
        self.assertEqual(github["requiredProtection"]["deploymentBranches"], ["main"])
        self.assertFalse(github["requiredProtection"]["verified"])

    def test_roles_use_resource_scopes_and_separate_deploy_from_runtime(self):
        plan = identity_plan.build_plan(TARGET)
        scope = f'/subscriptions/{TARGET["AZURE_SUBSCRIPTION_ID"]}/resourceGroups/helios-dev-rg'
        self.assertEqual(plan["deploymentIdentity"]["roles"][0]["scope"]["resourceId"], scope)
        self.assertEqual(plan["deploymentIdentity"]["roles"][1]["scope"]["resourceId"],
                         scope + '/providers/Microsoft.KeyVault/vaults/kv-helios-plan')
        self.assertEqual({role["role"] for role in plan["runtimeIdentity"]["roles"]},
                         {"Key Vault Secrets User", "Azure AI User", "Storage Table Data Contributor"})
        self.assertNotEqual(plan["runtimeIdentity"]["runtimeEnvironment"]["AZURE_CLIENT_ID"],
                            plan["deploymentIdentity"]["clientId"])
        self.assertIn("required-separately", plan["runtimeIdentity"]["hostAttachment"])

    def test_generated_parameters_use_selected_target_and_no_secret_fields(self):
        plan = identity_plan.build_plan(TARGET)
        params = plan["bicep"]["parameterDocument"]["parameters"]
        self.assertEqual(params["keyVaultName"], {"value": TARGET["AZURE_KEY_VAULT_NAME"]})
        self.assertEqual(params["location"], {"value": "eastus2"})
        self.assertEqual(params["deployRuntimeIdentity"], {"value": True})
        self.assertNotIn("deployLearningStorage", params)
        self.assertFalse(any("key" in key.lower() and key != "keyVaultName" for key in params))

    def test_existing_principal_preserves_explicit_identity_without_inventing_client_id(self):
        principal = "44444444-4444-4444-8444-444444444444"
        plan = identity_plan.build_plan({**TARGET, "HELIOS_RUNTIME_PRINCIPAL_ID": principal})
        self.assertFalse(plan["bicep"]["parameters"]["deployRuntimeIdentity"])
        self.assertEqual(plan["bicep"]["parameters"]["principalId"], principal)
        self.assertEqual(plan["bicep"]["parameters"]["learningStorePrincipalId"], principal)
        self.assertIsNone(plan["runtimeIdentity"]["clientIdOutput"])
        self.assertNotIn("AZURE_CLIENT_ID", plan["runtimeIdentity"]["runtimeEnvironment"])

    def test_optional_resource_names_flow_as_parameters(self):
        plan = identity_plan.build_plan({**TARGET, "HELIOS_RUNTIME_IDENTITY_NAME": "id-helios-worker",
                                        "AZURE_LEARNING_STORAGE_ACCOUNT_NAME": "helioslearn123"})
        self.assertEqual(plan["bicep"]["parameters"]["runtimeManagedIdentityName"], "id-helios-worker")
        self.assertEqual(plan["bicep"]["parameters"]["learningStorageAccountName"], "helioslearn123")

    def test_identity_ids_are_canonical_non_nil_uuids(self):
        for name in ["AZURE_TENANT_ID", "AZURE_SUBSCRIPTION_ID", "AZURE_CLIENT_ID", "HELIOS_RUNTIME_PRINCIPAL_ID"]:
            for invalid in ["tenant-guess", "0" * 32, "00000000-0000-0000-0000-000000000000", 123, True,
                            "{11111111-1111-4111-8111-111111111111}"]:
                with self.subTest(name=name, value=invalid):
                    plan = identity_plan.build_plan({**TARGET, name: invalid})
                    self.assertEqual(plan["status"], "incomplete")
                    self.assertIn(name, plan["invalidInputs"])
                    self.assertEqual(plan["verification"], [])

    def test_invalid_user_values_do_not_leak_or_form_commands(self):
        for name in TARGET.keys() | {"HELIOS_RUNTIME_IDENTITY_NAME", "AZURE_LEARNING_STORAGE_ACCOUNT_NAME",
                                      "HELIOS_GITHUB_REPOSITORY", "HELIOS_AZURE_ENVIRONMENT"}:
            for payload in ["UNSAFE$(touch /tmp/secret);do-not-print", "UNSAFE\nvalue", {"secret": "UNSAFE"}, ["UNSAFE"]]:
                with self.subTest(name=name, payload=payload):
                    plan = identity_plan.build_plan({**TARGET, name: payload})
                    self.assertEqual(plan["status"], "incomplete")
                    self.assertIn(name, plan["invalidInputs"])
                    self.assertNotIn("UNSAFE", json.dumps(plan))
                    self.assertEqual(plan["verification"], [])

    def test_invalid_repository_or_environment_is_not_replaced_with_trusted_default(self):
        plan = identity_plan.build_plan({**TARGET, "HELIOS_AZURE_ENVIRONMENT": "production",
                                        "HELIOS_GITHUB_REPOSITORY": "owner/repo:pull_request"})
        self.assertIsNone(plan["github"]["repository"])
        self.assertIsNone(plan["github"]["environment"])
        self.assertIsNone(plan["github"]["federatedCredential"]["subject"])

    def test_resource_name_constraints_and_region_format(self):
        for name, values in {
            "AZURE_KEY_VAULT_NAME": ["-vault", "va--ult", "vault-", "va", "v" * 25],
            "AZURE_RESOURCE_GROUP": ["rg.", "group/other", "r" * 91],
            "AZURE_LOCATION": ["East US 2", "../eastus2"],
            "AZURE_LEARNING_STORAGE_ACCOUNT_NAME": ["st-with-hyphen", "UPPER", "x" * 25],
            "HELIOS_GITHUB_REPOSITORY": ["../repo", "owner/.."],
        }.items():
            for value in values:
                with self.subTest(name=name, value=value):
                    self.assertIn(name, identity_plan.build_plan({**TARGET, name: value})["invalidInputs"])

    def test_guid_case_normalization_and_deterministic_hash(self):
        env = {**TARGET, "AZURE_TENANT_ID": "ABCDEF01-1111-4111-8111-111111111111"}
        a = identity_plan.build_plan(env)
        b = identity_plan.build_plan(dict(reversed(list(env.items()))))
        self.assertEqual(a, b)
        self.assertEqual(a["target"]["tenantId"], env["AZURE_TENANT_ID"].lower())
        payload = copy.deepcopy(a)
        digest = payload.pop("planSha256")
        self.assertEqual(digest, hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()).hexdigest())
        changed = identity_plan.build_plan({**env, "AZURE_RESOURCE_GROUP": "another-rg"})
        self.assertNotEqual(digest, changed["planSha256"])

    def test_ignores_all_secret_variables_and_does_not_mutate_input(self):
        class GuardedEnvironment(dict):
            def get(self, key, default=None):
                if key.endswith(("SECRET", "TOKEN", "API_KEY")):
                    raise AssertionError("Secret value requested")
                return super().get(key, default)
        source = GuardedEnvironment({**TARGET, "AZURE_CLIENT_SECRET": "PRIVATE_VALUE",
                                     "OPENAI_API_KEY": "PRIVATE_VALUE", "GITHUB_TOKEN": "PRIVATE_VALUE"})
        snapshot = dict(source)
        plan = identity_plan.build_plan(source)
        self.assertEqual(dict(source), snapshot)
        self.assertNotIn("PRIVATE_VALUE", json.dumps(plan))

    def test_plan_does_not_run_commands_or_network(self):
        with patch("subprocess.run", side_effect=AssertionError("Unexpected process")), \
             patch("socket.socket", side_effect=AssertionError("Unexpected network")), \
             patch("builtins.open", side_effect=AssertionError("Unexpected file access")):
            plan = identity_plan.build_plan(TARGET)
        self.assertEqual(plan["status"], "prepared")
        self.assertTrue(all(check["readOnly"] for check in plan["verification"]))
        for check in plan["verification"]:
            self.assertIsInstance(check["argv"], list)
            self.assertFalse({"--apply", "create", "set", "delete", "login"} & set(check["argv"]))

    def test_cli_strict_reports_missing_noninteractively(self):
        env = {key: value for key, value in os.environ.items() if key not in identity_plan.REQUIRED + identity_plan.OPTIONAL}
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/bootstrap/identity_plan.py'), '--strict'],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["status"], "incomplete")
        self.assertEqual(result.stderr, "")


class RuntimeIdentityTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.arm = json.loads((ROOT / 'infra/arm/main.json').read_text())

    def test_runtime_identity_is_opt_in_and_does_not_deploy_hosts(self):
        self.assertFalse(self.arm["parameters"]["deployRuntimeIdentity"]["defaultValue"])
        resources = self.arm['resources']
        resources = resources.values() if isinstance(resources, dict) else resources
        deployment = next(resource for resource in resources
                          if "runtime-identity-" in resource.get('name', ''))
        self.assertEqual(deployment['condition'], "[parameters('deployRuntimeIdentity')]")
        resource_types = {resource['type'] for resource in deployment['properties']['template']['resources']}
        self.assertEqual(resource_types, {'Microsoft.ManagedIdentity/userAssignedIdentities'})

    def test_generated_plan_references_actual_template_contract(self):
        plan = identity_plan.build_plan(TARGET)
        for name, parameter in plan['bicep']['parameterDocument']['parameters'].items():
            self.assertIn(name, self.arm['parameters'])
            expected_type = self.arm['parameters'][name]['type']
            self.assertIsInstance(parameter['value'], bool if expected_type == 'bool' else str)
        for name in ['clientIdOutput', 'resourceIdOutput', 'principalIdOutput']:
            self.assertIn(plan['runtimeIdentity'][name], self.arm['outputs'])
        for grant in plan['runtimeIdentity']['roles']:
            if 'bicepOutput' in grant['scope']:
                self.assertIn(grant['scope']['bicepOutput'], self.arm['outputs'])

    def test_runtime_credentials_have_nonsecret_outputs(self):
        for output in ['runtimeManagedIdentityId', 'runtimeManagedIdentityClientId', 'runtimeManagedIdentityPrincipalId']:
            self.assertEqual(self.arm['outputs'][output]['type'], 'string')
        self.assertFalse(any('secret' in output.lower() for output in self.arm['outputs']))

    def test_explicit_principals_keep_existing_grants(self):
        # Existing grants must not move to the new identity as a side effect of opt-in.
        for condition, original in [('runtimeOwnsProviderAccess', 'principalId'),
                                    ('runtimeOwnsLearningAccess', 'learningStorePrincipalId')]:
            expression = self.arm['variables'][condition]
            self.assertIn("parameters('deployRuntimeIdentity')", expression)
            self.assertIn(f"empty(parameters('{original}'))", expression)


if __name__ == '__main__':
    unittest.main()
