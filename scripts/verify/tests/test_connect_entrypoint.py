"""Inert contracts: no live login, credential reads, API calls or deployments."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("helios_connect", ROOT / "scripts/bootstrap/connect.py")
connect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connect)


class EntryPointTests(unittest.TestCase):
    def invoke(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = connect.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_default_inventory_is_offline_and_never_exposes_values(self):
        secret = "sentinel-private-value-do-not-display"
        with patch.dict(os.environ, {"OPENAI_API_KEY": secret, "LINEAR_API_KEY": secret}), patch.object(connect.subprocess, "run", side_effect=AssertionError("must stay offline")):
            code, out, err = self.invoke(["status", "--json"])
        self.assertEqual(code, 0)
        report = json.loads(out)
        self.assertFalse(report["authenticationProbed"])
        self.assertIn('OPENAI_API_KEY', out)
        self.assertNotIn(secret, out + err)
        self.assertIn("copilot", report["tools"])

    def test_empty_environment_is_absent(self):
        with patch.dict(os.environ, {"LINEAR_API_KEY": "  "}):
            report = connect.inventory()
        self.assertFalse(report["connectors"]["linear"]["environment"][0]["present"])

    def test_only_documented_environment_names_are_discovered(self):
        self.assertEqual(connect.env_refs({"keyEnv": "PRIVATE_KEY", "badEnv": "token-secret", "key": "SHOULD_NOT_READ"}), {"PRIVATE_KEY"})

    def test_malformed_configuration_does_not_echo_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config"
            path.mkdir()
            (path / "aihub.json").write_text('{"SECRET":"confidential"')
            with patch.object(connect, "ROOT", Path(directory)):
                code, out, err = self.invoke(["status"])
            self.assertEqual(code, 2)
            self.assertNotIn("confidential", out + err)

    def test_configuration_size_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "huge.json").write_text(" " * (connect.MAX_CONFIG + 1))
            with patch.object(connect, "ROOT", Path(directory)):
                with self.assertRaises(connect.ConnectionError): connect.config("huge.json")

    def test_login_and_full_setup_require_terminal(self):
        with patch.object(connect.sys.stdin, "isatty", return_value=False), patch.object(connect, "run") as run:
            for args in (["login", "github"], ["setup", "--connect"], ["cloud-shell", "--connect"]):
                self.assertEqual(self.invoke(args)[0], 2)
            run.assert_not_called()

    def test_setup_defaults_to_verification_and_preserves_arguments(self):
        with patch.object(connect, "WINDOWS", False), patch.object(connect, "run", return_value=0) as run:
            self.assertEqual(self.invoke(["setup", "--json"])[0], 0)
            self.assertEqual(run.call_args.args[1][-2:], ["--verify-only", "--json"])

    def test_setup_windows_flags(self):
        with patch.object(connect, "WINDOWS", True), patch.object(connect, "run", return_value=0) as run:
            self.invoke(["setup", "--skip-setup"])
            self.assertEqual(run.call_args.args[0], "pwsh")
            self.assertEqual(run.call_args.args[1][-2:], ["-VerifyOnly", "-SkipSetup"])

    def test_contradictory_setup_modes_fail_before_execution(self):
        with patch.object(connect, "run") as run:
            for args in (["setup", "--connect", "--json"], ["setup", "--connect", "--verify-only"]):
                self.assertEqual(self.invoke(args)[0], 2)
            run.assert_not_called()

    def test_auth_probes_are_bounded_and_quiet(self):
        with patch.object(connect, "run", side_effect=[0, 124, 1, 0]) as run:
            code, out, err = self.invoke(["auth", "status", "--json"])
            self.assertEqual(code, 2)
            self.assertTrue(json.loads(out)["authenticationProbed"])
            self.assertFalse(json.loads(out)["providerInferenceVerified"])
            self.assertEqual(len(run.call_args_list), 4)
            for call in run.call_args_list:
                self.assertTrue(call.kwargs["quiet"])
                self.assertEqual(call.kwargs["timeout"], 15)

    def test_native_execution_uses_argv_and_checkout_cwd(self):
        dangerous = 'spaces "quotes" $(not-a-command) & literal'
        with patch.object(connect, "native", return_value=(["/tools/claude"], {})), patch.object(connect.subprocess, "run") as run:
            run.return_value.returncode = 17
            self.assertEqual(connect.run("claude", [dangerous]), 17)
            self.assertEqual(run.call_args.args[0], ["/tools/claude", dangerous])
            self.assertIs(run.call_args.kwargs["shell"], False)
            self.assertEqual(run.call_args.kwargs["cwd"], ROOT)

    def test_timeout_has_stable_exit_code(self):
        with patch.object(connect, "native", return_value=(["/tools/gh"], {})), patch.object(connect.subprocess, "run", side_effect=subprocess.TimeoutExpired("gh", 15)):
            self.assertEqual(connect.run("gh", [], timeout=15, quiet=True), 124)

    def test_codex_uses_current_absolute_mcp_paths(self):
        with patch.object(connect, "run", return_value=0) as run:
            self.invoke(["codex", "exec", "literal prompt"])
            argv = run.call_args.args[1]
            self.assertIn('mcp_servers.helios.cwd=' + json.dumps(str(ROOT)), argv)
            self.assertEqual(argv[-2:], ["exec", "literal prompt"])

    def test_claude_and_copilot_use_same_checkout(self):
        with patch.object(connect, "run", return_value=0) as run:
            self.invoke(["claude", "--help"])
            self.assertEqual(run.call_args.args[1][:2], ["--plugin-dir", str(ROOT / "plugins/helios-operator")])
            self.invoke(["copilot", "--help"])
            self.assertEqual(run.call_args.args, ("copilot", ["--help"]))

    def test_mcp_build_logs_go_to_stderr_and_failures_stop_launch(self):
        with patch.object(connect, "run", return_value=1) as run:
            self.assertEqual(self.invoke(["mcp"])[0], 1)
            self.assertEqual(run.call_count, 1)
            self.assertTrue(run.call_args.kwargs["stderr_output"])

    def test_bridge_rejects_arbitrary_launch_options(self):
        with patch.object(connect, "run") as run:
            self.assertEqual(self.invoke(["bridge", "--urls", "http://0.0.0.0"])[0], 2)
            run.assert_not_called()

    def test_bridge_client_registration_validates_destination(self):
        with patch.object(connect, "run", return_value=0) as run:
            self.assertEqual(self.invoke(["bridge", "connect", "https://helios.example/mcp"])[0], 0)
            self.assertEqual(run.call_args.args[1][-3:], ["--scope", "local", "https://helios.example/mcp"])
        for url in ["http://example.com/mcp", "https://user:secret@example.com/mcp", "https://example.com/mcp?key=secret", "https://example.com/mcp#x", "https://example.com/other", "https://example.com/mcp\n", "https://example.com:bad/mcp"]:
            with self.subTest(url=url), patch.object(connect, "run") as run:
                self.assertEqual(self.invoke(["bridge", "connect", url])[0], 2)
                run.assert_not_called()

    def test_bridge_accepts_only_local_plain_http(self):
        for url in ["http://127.0.0.1:7078/mcp", "http://[::1]:7078/mcp"]:
            self.assertEqual(connect.endpoint(url), url)

    def test_cloud_shell_defaults_verify_and_connect_skips_smoke(self):
        with patch.object(connect, "WINDOWS", False), patch.object(connect, "terminal"), patch.object(connect, "run", return_value=0) as run:
            self.invoke(["cloud-shell"])
            self.assertEqual(run.call_args.args[1][-1], "--verify-only")
            self.invoke(["cloud-shell", "--connect"])
            self.assertEqual(run.call_args.args[1][-1], "--skip-smoke")

    def test_combo_requires_explicit_providers_and_learning_is_advisory(self):
        with patch.object(connect, "run", return_value=0) as run:
            self.assertEqual(self.invoke(["combo", "hello"])[0], 2)
            run.assert_not_called()
            self.invoke(["combo", "hello", "--providers", "claude-cli,codex"])
            self.assertEqual(run.call_args.args[1][-4:], ["compare", "hello", "--providers", "claude-cli,codex"])
            self.invoke(["learning"])
            self.assertEqual(run.call_args.args[1][-2:], ["fleet-plan", "--json"])

    def test_windows_known_azure_layout_uses_bundled_python(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / "wbin").mkdir()
            shim = root / "wbin/az.cmd"; shim.touch(); (root / "python.exe").touch()
            with patch.object(connect, "WINDOWS", True), patch.object(connect.shutil, "which", side_effect=lambda name: str(shim) if name == "az" else None):
                argv, env = connect.native("az")
                self.assertEqual(argv, [str(root / "python.exe"), "-IBm", "azure.cli"])
                self.assertEqual(env, {"AZ_INSTALLER": "MSI"})

    def test_unknown_windows_batch_layout_fails_closed(self):
        with patch.object(connect, "WINDOWS", True), patch.object(connect.shutil, "which", side_effect=lambda name: '/unknown/claude.cmd' if name == 'claude' else None):
            with self.assertRaises(connect.ConnectionError): connect.native("claude")

    def test_windows_copilot_platform_package_uses_native_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = root / "copilot.cmd"; shim.touch()
            binary = root / "node_modules/@github/copilot-win32-x64/copilot.exe"
            binary.parent.mkdir(parents=True); binary.touch()
            with patch.dict(os.environ, {"PROCESSOR_ARCHITECTURE": "AMD64"}), patch.object(connect, "WINDOWS", True), patch.object(connect.shutil, "which", side_effect=lambda name: str(shim) if name == "copilot" else None):
                self.assertEqual(connect.native("copilot"), ([str(binary)], {}))

    def test_helpers_preserve_stdin_and_argv_with_current_python(self):
        with patch.object(connect, "run", return_value=7) as run, patch.object(connect, "require"):
            for command, helper in [("return", "workspace_agent_handoff.py"), ("workspace", "agent_workspace.py")]:
                self.assertEqual(self.invoke([command, "status"])[0], 7)
                self.assertEqual(run.call_args.args, (connect.sys.executable, [str(ROOT / "scripts/bootstrap" / helper), "status"]))

    @unittest.skipUnless(shutil.which('bash'), 'Bash required')
    def test_real_bash_wrapper_from_directory_with_spaces(self):
        bash = shutil.which('bash')
        if os.name == 'nt':
            # Windows' PATH may find the WSL launcher even when no distribution
            # is installed. Exercise Git for Windows' actual Bash instead.
            git = Path(shutil.which('git') or '')
            candidates = [git.parent.parent / 'bin/bash.exe', git.parent / 'bash.exe']
            bash = next((str(path) for path in candidates if path.is_file()), None)
            self.assertIsNotNone(bash, 'Git for Windows Bash is required by this fixture')
        with tempfile.TemporaryDirectory(prefix="HELIOS space ") as directory:
            dest = Path(directory)
            for path in ['connect.sh', 'scripts/bootstrap/connect.py', 'config/aihub.json', 'config/connectors.json', 'config/control-project.json']:
                target = dest / path; target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, target)
            result = subprocess.run([bash, (dest / 'connect.sh').as_posix(), 'status', '--json'], capture_output=True, text=True, cwd=dest.parent, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertFalse(json.loads(result.stdout)['authenticationProbed'])


if __name__ == '__main__': unittest.main()
