import asyncio
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest

SPEC = importlib.util.spec_from_file_location('mcp_health', Path(__file__).resolve().parents[1] / 'mcp-health.py')
health = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(health)

# Subprocess fixture exercises real pipes and timeouts, not mocked readers.
SERVER = r'''
import json, sys, time
mode, log, names = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
if mode == 'hang':
    time.sleep(20)
if mode == 'stderr':
    sys.stderr.write('inert-sensitive-fixture' * 100000)
    sys.stderr.flush()
for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    with open(log, 'a', encoding='utf-8') as stream:
        stream.write(method + '\n')
    if method == 'notifications/initialized':
        continue
    if mode == 'malformed':
        print('inert-sensitive-fixture', flush=True)
        continue
    if method == 'initialize':
        result = {'protocolVersion': 'unsupported' if mode == 'version' else '2025-11-25',
                  'capabilities': {'tools': {}}}
    elif method == 'tools/list':
        selected = [] if mode == 'missing' else names
        result = {'tools': [{'name': name} for name in selected]}
        if mode == 'pages' and not request.get('params', {}).get('cursor'):
            result = {'tools': [], 'nextCursor': 'second'}
        if mode == 'cursor':
            result['nextCursor'] = 'same'
    elif method == 'ping':
        result = {}
    else:
        raise RuntimeError('Probe must never invoke tools or request inference')
    response = {'jsonrpc': '2.0', 'id': 999 if mode == 'id' else request['id'], 'result': result}
    if mode == 'error':
        response = {'jsonrpc': '2.0', 'id': request['id'],
                    'error': {'code': -32603, 'message': 'inert-sensitive-fixture'}}
    print(json.dumps(response), flush=True)
'''


class McpHealthTests(unittest.TestCase):
    def run_probe(self, mode, timeout=2):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            server = root / 'server.py'
            server.write_text(SERVER, encoding='utf-8')
            log = root / 'methods.txt'
            command = [sys.executable, '-u', str(server), mode, str(log), json.dumps(sorted(health.REQUIRED_TOOLS))]
            result = asyncio.run(health.probe(command, root, timeout))
            methods = log.read_text(encoding='utf-8').splitlines() if log.exists() else []
            self.assertNotIn('inert-sensitive-fixture', json.dumps(result))
            self.assertNotIn('tools/call', methods)
            self.assertEqual(result['providerCalls'], 0)
            return result, methods

    def test_discovers_and_pings_without_invoking_tools(self):
        result, methods = self.run_probe('success')
        self.assertTrue(result['ready'], result)
        self.assertEqual(methods, ['initialize', 'notifications/initialized', 'tools/list', 'ping'])

    def test_pagination_and_large_stderr(self):
        for mode in ('pages', 'stderr'):
            with self.subTest(mode=mode):
                self.assertTrue(self.run_probe(mode)[0]['ready'])

    def test_protocol_failures_are_not_ready(self):
        for mode in ('malformed', 'version', 'missing', 'cursor', 'id', 'error'):
            with self.subTest(mode=mode):
                self.assertFalse(self.run_probe(mode)[0]['ready'])

    def test_hung_server_is_bounded_and_reaped(self):
        start = time.monotonic()
        result, _ = self.run_probe('hang', timeout=0.1)
        self.assertFalse(result['ready'])
        self.assertLess(time.monotonic() - start, 5)

    def test_client_configs_match_server_and_prebuilt_contract(self):
        import tomllib
        root = Path(__file__).resolve().parents[3]
        claude = json.loads((root / '.mcp.json').read_text())['mcpServers']['helios']
        codex = tomllib.loads((root / '.codex/config.toml').read_text())['mcp_servers']['helios']
        vscode = json.loads((root / '.vscode/mcp.json').read_text())['servers']['helios']
        self.assertEqual(claude['args'], codex['args'])
        self.assertEqual((root / '.codex' / codex['cwd']).resolve(), root)
        for client in (claude, codex, vscode):
            self.assertEqual(client['command'], 'dotnet')
            self.assertTrue({'--no-build', '--no-restore', '--no-launch-profile'} <= set(client['args']))
            self.assertIn('HELIOS_REPO_ROOT', client['env'])


if __name__ == '__main__':
    unittest.main()
