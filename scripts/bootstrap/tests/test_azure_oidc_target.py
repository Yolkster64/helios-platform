"""Run both entrypoints against an inert az; no Azure access or mutation."""
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
with open(os.environ['AZ_TEST_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\n')
def arg(name):
    return args[args.index(name) + 1]
mode = os.environ.get('AZ_TEST_MODE', '')
query = arg('--query') if '--query' in args else ''
scope = '/subscriptions/sub-a/resourceGroups/rg-a'
if args[:2] == ['account', 'show']:
    value = {'id': 'sub-b' if mode == 'subscription' else 'sub-a',
             'tenantId': 'tenant-b' if mode == 'tenant' else 'tenant-a',
             'state': 'Disabled' if mode == 'disabled' else 'Enabled'}[query]
elif args[:2] == ['group', 'show']:
    assert arg('--subscription') == 'sub-a'
    value = scope + ('-wrong' if mode == 'group' else '')
elif args[:2] == ['keyvault', 'show']:
    assert arg('--subscription') == 'sub-a'
    if mode == 'missing-vault': sys.exit(1)
    value = {'id': scope + '/providers/Microsoft.KeyVault/vaults/' + ('other' if mode == 'vault' else 'vault-a'),
             'properties.tenantId': 'tenant-b' if mode == 'vault-tenant' else 'tenant-a',
             'properties.enableRbacAuthorization': 'false' if mode == 'rbac' else 'true'}[query]
elif args[:3] == ['ad', 'app', 'list']:
    assert query == 'length(@)'
    value = '2' if mode == 'duplicate-app' else '0'
else:
    sys.exit('Unexpected operation: ' + ' '.join(args))
print(value)
'''

class AzureOidcTargetTests(unittest.TestCase):
    def run_script(self, shell, mode='', missing=False, apply=False):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            az = tmp / 'az'
            az.write_text('#!' + sys.executable + '\n' + FAKE_AZ)
            az.chmod(0o755)
            log = tmp / 'calls.jsonl'
            env = {**os.environ, 'PATH': str(tmp) + os.pathsep + os.environ['PATH'],
                   'AZ_TEST_LOG': str(log), 'AZ_TEST_MODE': mode}
            if shell == 'bash':
                command = ['bash', str(ROOT / 'scripts/bootstrap/azure-oidc-setup.sh')]
                args = ['--tenant','tenant-a','--subscription','sub-a','--resource-group','rg-a','--key-vault','vault-a']
                if apply: command.append('--apply')
            else:
                pwsh = shutil.which('pwsh')
                self.assertIsNotNone(pwsh, 'PowerShell 7 is required for the twin-script gate')
                command = [pwsh, '-NoProfile', '-NonInteractive', '-File', str(ROOT / 'scripts/bootstrap/azure-oidc-setup.ps1')]
                args = ['-Tenant','tenant-a','-Subscription','sub-a','-ResourceGroup','rg-a','-KeyVault','vault-a']
                if apply: command.append('-Apply')
            if not missing: command += args
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=20)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            for call in calls:
                self.assertNotIn('create', call)
                self.assertNotIn('set', call)
                self.assertNotIn('delete', call)
                self.assertNotIn('login', call)
            return result, calls

    def test_explicit_valid_target_is_read_only_in_both_shells(self):
        for shell in ['bash','pwsh']:
            with self.subTest(shell=shell):
                result, calls = self.run_script(shell)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Plan only.', result.stdout)
                self.assertEqual(len(calls), 8)

    def test_missing_targets_never_call_azure_even_with_apply(self):
        for shell in ['bash','pwsh']:
            with self.subTest(shell=shell):
                result, calls = self.run_script(shell, missing=True, apply=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_mismatches_and_missing_vault_block_apply(self):
        for shell in ['bash','pwsh']:
            for mode in ['subscription','tenant','disabled','group','vault','vault-tenant','rbac','missing-vault','duplicate-app']:
                with self.subTest(shell=shell, mode=mode):
                    result, _ = self.run_script(shell, mode=mode, apply=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn('Creating', result.stdout)

if __name__ == '__main__':
    unittest.main()
