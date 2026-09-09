"""Exercise Azure setup against an inert CLI; neither shell can reach Azure.

CI runs both classes. A local machine without PowerShell can explicitly run
AzureOidcBashTests; that does not count as verification of its PowerShell twin.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
FAKE_AZ = r'''
import json, os, sys
args = sys.argv[1:]
def arg(name):
    return args[args.index(name) + 1]
entry = {'args': args}
if '--parameters' in args:
    with open(arg('--parameters').removeprefix('@')) as source:
        entry['parameters'] = json.load(source)
with open(os.environ['AZ_TEST_LOG'], 'a') as log:
    log.write(json.dumps(entry) + '\n')
mode = os.environ.get('AZ_TEST_MODE', '')
query = arg('--query') if '--query' in args else ''
scope = '/subscriptions/sub-a/resourceGroups/rg-a'
if args[:2] == ['account', 'show']:
    value = {'id': 'sub-b' if mode == 'subscription' else 'sub-a',
             'tenantId': 'tenant-b' if mode == 'tenant' else 'tenant-a',
             'state': 'Disabled' if mode == 'disabled' else 'Enabled'}[query]
elif args[:2] == ['group', 'show']:
    assert arg('--subscription') == 'sub-a'
    value = ('eastus2' if mode != 'location' else '') if query == 'location' else scope + ('-wrong' if mode == 'group' else '')
elif args[:2] == ['keyvault', 'show']:
    assert arg('--subscription') == 'sub-a'
    if mode == 'missing-vault': sys.exit(1)
    value = {'id': scope + '/providers/Microsoft.KeyVault/vaults/' + ('other' if mode == 'vault' else 'vault-a'),
             'properties.tenantId': 'tenant-b' if mode == 'vault-tenant' else 'tenant-a',
             'properties.enableRbacAuthorization': 'false' if mode == 'rbac' else 'true'}[query]
elif args[:3] == ['ad', 'app', 'list']:
    value = ('2' if mode == 'duplicate-app' else '1') if query == 'length(@)' else 'app-a'
elif args[:3] == ['ad', 'sp', 'list']:
    value = 'sp-a'
elif args[:3] == ['ad', 'app', 'federated-credential']:
    action = args[3]
    if action == 'list':
        if "issuer==" in query:
            assert "https://token.actions.githubusercontent.com" in query
            assert "length(audiences)==`1`" in query
            assert "api://AzureADTokenExchange" in query
            value = '1' if mode == 'existing-fic' else '0'
        elif "subject==" in query:
            assert "name=='github-env-azure-dev' || subject=='repo:Yolkster64/helios-platform:environment:azure-dev'" in query
            value = '2' if mode == 'duplicate-fic' else ('1' if mode in ['existing-fic', 'issuer', 'audience', 'conflicting-fic-name'] else '0')
        else:
            assert query in ["length([?name=='" + name + "'])" for name in ['github-main', 'github-pull-request', 'github-env-production']]
            value = '1'
    elif action == 'show': value = ''
    elif action == 'delete':
        assert arg('--federated-credential-id') in ['github-main', 'github-pull-request', 'github-env-production']
        value = ''
    elif action == 'create':
        assert entry['parameters']['subject'] == 'repo:Yolkster64/helios-platform:environment:azure-dev'
        value = ''
    else: sys.exit('Unexpected federated credential operation')
elif args[:3] == ['role', 'assignment', 'list']:
    assert arg('--subscription') == 'sub-a'
    value = 'existing-role'
else:
    sys.exit('Unexpected operation: ' + ' '.join(args))
print(value)
'''


class AzureOidcChecks:
    shell = None

    def run_script(self, mode='', missing=False, apply=False, environment=None, repo=None):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            az = tmp / 'az'
            az.write_text('#!' + sys.executable + '\n' + FAKE_AZ)
            az.chmod(0o755)
            log = tmp / 'calls.jsonl'
            env = {**os.environ, 'PATH': str(tmp) + os.pathsep + os.environ['PATH'],
                   'AZ_TEST_LOG': str(log), 'AZ_TEST_MODE': mode}
            if self.shell == 'bash':
                command = ['bash', str(ROOT / 'scripts/bootstrap/azure-oidc-setup.sh')]
                args = ['--tenant','tenant-a','--subscription','sub-a','--resource-group','rg-a','--key-vault','vault-a']
                if apply: command.append('--apply')
                if environment is not None: command += ['--environment', environment]
                if repo is not None: command += ['--repo', repo]
            else:
                pwsh = shutil.which('pwsh')
                self.assertIsNotNone(pwsh, 'PowerShell 7 is required for the twin-script gate')
                command = [pwsh, '-NoProfile', '-NonInteractive', '-File', str(ROOT / 'scripts/bootstrap/azure-oidc-setup.ps1')]
                args = ['-Tenant','tenant-a','-Subscription','sub-a','-ResourceGroup','rg-a','-KeyVault','vault-a']
                if apply: command.append('-Apply')
                if environment is not None: command += ['-EnvironmentName', environment]
                if repo is not None: command += ['-Repo', repo]
            if not missing: command += args
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=20)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def assert_read_only(self, calls):
        for call in calls:
            self.assertFalse(set(call['args']) & {'create', 'set', 'delete', 'login'}, call)

    def test_valid_target_defaults_to_read_only(self):
        result, calls = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Plan only.', result.stdout)
        self.assertIn('Trust: repo:Yolkster64/helios-platform:environment:azure-dev', result.stdout)
        self.assertNotIn('Trust: repo:Yolkster64/helios-platform:ref:', result.stdout)
        self.assertIn('github-main', result.stdout)
        self.assertEqual(len(calls), 9)
        self.assert_read_only(calls)

    def test_missing_targets_never_call_azure_even_with_apply(self):
        result, calls = self.run_script(missing=True, apply=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_production_never_calls_azure_even_with_apply(self):
        result, calls = self.run_script(environment='production', apply=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_bad_repository_never_calls_azure(self):
        result, calls = self.run_script(repo='owner/repo:pull_request', apply=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_apply_trusts_only_azure_dev_and_removes_legacy(self):
        result, calls = self.run_script(apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        mutations = [c for c in calls if set(c['args']) & {'create', 'delete', 'set', 'login'}]
        creates = [c for c in mutations if 'create' in c['args']]
        self.assertEqual(len(creates), 1)
        fic = creates[0]['parameters']
        self.assertEqual(fic['subject'], 'repo:Yolkster64/helios-platform:environment:azure-dev')
        self.assertEqual(fic['issuer'], 'https://token.actions.githubusercontent.com')
        self.assertEqual(fic['audiences'], ['api://AzureADTokenExchange'])
        self.assertEqual(len(mutations), 4)
        for key in ('AZURE_RESOURCE_GROUP', 'AZURE_LOCATION'):
            self.assertIn(key, result.stdout)
        self.assertIn('--env azure-dev', result.stdout)

    def test_existing_federation_requires_matching_issuer_and_audience(self):
        result, calls = self.run_script(mode='existing-fic', apply=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('expected issuer and audience', result.stdout)
        self.assertFalse(any('create' in c['args'] for c in calls))

    def test_conflicting_federation_refuses_writes(self):
        for mode in ('issuer', 'audience', 'conflicting-fic-name', 'duplicate-fic'):
            with self.subTest(mode=mode):
                result, calls = self.run_script(mode=mode, apply=True)
                self.assertNotEqual(result.returncode, 0)
                self.assert_read_only(calls)


def reject_mismatch(mode):
    def test(self):
        result, calls = self.run_script(mode=mode, apply=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Creating', result.stdout)
        self.assert_read_only(calls)
    return test


for _mode in ['subscription', 'tenant', 'disabled', 'group', 'vault', 'vault-tenant',
              'rbac', 'missing-vault', 'duplicate-app', 'location']:
    setattr(AzureOidcChecks, 'test_rejects_' + _mode.replace('-', '_'), reject_mismatch(_mode))


class AzureOidcBashTests(AzureOidcChecks, unittest.TestCase):
    shell = 'bash'


class AzureOidcPowerShellTests(AzureOidcChecks, unittest.TestCase):
    shell = 'pwsh'


if __name__ == '__main__':
    unittest.main()
