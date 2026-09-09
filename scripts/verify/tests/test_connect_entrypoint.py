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
import time
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
                self.assertTrue(call.kwargs["noninteractive"])

    def test_start_prepares_without_a_terminal_or_starting_agents(self):
        with patch.object(connect.sys.stdin, "isatty", return_value=False), patch.object(connect, "terminal", side_effect=AssertionError("no prompts")), patch.object(connect.shutil, "which", side_effect=lambda tool: "/tools/" + tool), patch.object(connect, "run", return_value=0) as run:
            code, out, err = self.invoke(["start", "--json"])
        report = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "ready")
        self.assertTrue(report["localCoreReady"])
        self.assertTrue(report["workspacesReady"])
        self.assertEqual(report["runtimeState"], "stopped")
        self.assertFalse(report["providerInferenceVerified"])
        self.assertFalse(report["liveConnectorsVerified"])
        created = [call.args[1] for call in run.call_args_list if "create" in call.args[1]]
        self.assertEqual({argv[-1] for argv in created}, set(connect.config("config/agent-catalog.json")["roles"]))
        self.assertEqual(len(created), 7)
        for call in run.call_args_list:
            self.assertTrue(call.kwargs["noninteractive"])
            self.assertTrue(call.kwargs["quiet"])
            self.assertIsInstance(call.kwargs["timeout"], int)
        self.assertTrue(any("HELIOS.sln" in " ".join(call.args[1]) for call in run.call_args_list))
        build = next(call for call in run.call_args_list if call.args[0] == "dotnet")
        for option in ("-m:1", "-nodeReuse:false", "-p:UseSharedCompilation=false"):
            self.assertIn(option, build.args[1])
        self.assertFalse(any(call.args[1][:1] in (["login"], ["run"], ["exec"], ["ask"]) and call.args[1] != ["login", "status"] for call in run.call_args_list))

    def test_start_optional_services_do_not_gate_local_preparation(self):
        def execute(tool, args, **kwargs):
            if tool in ("gh", "az", "claude", "codex"):
                raise connect.ConnectionError("not installed, sentinel-secret")
            return 0
        with patch.object(connect, "run", side_effect=execute):
            code, out, err = self.invoke(["start", "--json"])
        report = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "partial")
        self.assertTrue(report["localCoreReady"])
        self.assertTrue(report["workspacesReady"])
        self.assertEqual(report["nextAction"], "connect.sh start --serve")
        self.assertEqual([step["exitCode"] for step in report["steps"] if step["name"].startswith("auth:")], [127] * 4)
        self.assertNotIn("sentinel-secret", out + err)
        self.assertEqual(set(report["connectors"]), set(connect.inventory()["connectors"]))
        self.assertTrue(all(value["state"] == "unverified" for value in report["connectors"].values()))

    def test_start_installs_missing_coding_clis_with_existing_noninteractive_helper(self):
        def which(tool):
            return None if tool in ("claude", "codex", "copilot") else "/tools/" + tool
        with patch.object(connect.shutil, "which", side_effect=which), patch.object(connect, "run", return_value=0) as run:
            code, out, err = self.invoke(["start", "--json"])
        self.assertEqual(code, 0)
        call = next(call for call in run.call_args_list if call.args[0] == "pwsh")
        self.assertEqual(call.args[1], ["-NoProfile", "-NonInteractive", "-File", str(ROOT / "scripts/bootstrap/setup-ai-clis.ps1"), "-Skip", "gh"])
        self.assertTrue(call.kwargs["noninteractive"])
        self.assertTrue(call.kwargs["quiet"])
        self.assertEqual(call.kwargs["timeout"], 600)
        self.assertNotIn("-ProbeAuth", call.args[1])

    def test_start_skips_installer_when_coding_clis_already_exist(self):
        with patch.object(connect.shutil, "which", return_value="/tools/present"), patch.object(connect, "run") as run:
            self.assertEqual(connect.install_coding_tools(), [])
        run.assert_not_called()

    def test_start_missing_installer_prerequisites_are_optional_and_bounded(self):
        for missing in ("pwsh", "npm"):
            with self.subTest(missing=missing), patch.object(connect.shutil, "which", side_effect=lambda tool: None if tool in (missing, "claude") else "/tools/" + tool), patch.object(connect, "run", return_value=0) as run:
                code, out, err = self.invoke(["start", "--json"])
            report = json.loads(out)
            self.assertEqual(code, 0)
            self.assertEqual(report["status"], "partial")
            self.assertTrue(report["localCoreReady"])
            self.assertEqual(next(step for step in report["steps"] if step["name"] == "coding-tools")["exitCode"], 127)
            self.assertFalse(any(call.args[0] == "pwsh" for call in run.call_args_list))

    def test_start_failed_cli_install_still_builds_and_prepares_workspaces(self):
        with patch.object(connect.shutil, "which", side_effect=lambda tool: None if tool == "claude" else "/tools/" + tool), patch.object(connect, "run", side_effect=lambda tool, args, **kwargs: 2 if tool == "pwsh" else 0):
            code, out, err = self.invoke(["start", "--json"])
        report = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(report["status"], "partial")
        self.assertTrue(report["workspacesReady"])
        self.assertEqual(next(step for step in report["steps"] if step["name"] == "coding-tools")["exitCode"], 2)

    def test_start_failed_build_preserves_independent_workspace_preparation(self):
        def execute(tool, args, **kwargs):
            return 17 if tool == "dotnet" else 0
        with patch.object(connect, "run", side_effect=execute) as run:
            code, out, err = self.invoke(["start", "--serve"])
        self.assertEqual(code, 2)
        self.assertIn("build: failed (exit 17)", out)
        self.assertIn("dotnet build HELIOS.sln -c Release", out)
        self.assertEqual(sum("create" in call.args[1] for call in run.call_args_list), 7)
        self.assertFalse(any(call.args[0] == "dotnet" and call.args[1][0] == "run" for call in run.call_args_list))

    def test_start_invalid_config_stops_before_build_workspaces_or_sessions(self):
        with patch.object(connect, "run", return_value=1) as run:
            code, out, err = self.invoke(["start", "--json"])
        self.assertEqual(code, 2)
        report = json.loads(out)
        self.assertEqual(report["status"], "blocked")
        self.assertFalse(report["authenticationProbed"])
        self.assertEqual(len(run.call_args_list), 1)
        self.assertIn("validate_config_schemas.py", run.call_args.args[1][0])

    def test_start_missing_checkout_returns_structured_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(connect, "ROOT", Path(directory)), patch.object(connect, "run") as run:
            code, out, err = self.invoke(["start", "--json"])
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(out)["status"], "blocked")
        run.assert_not_called()

    def test_start_serve_uses_built_bridge_even_when_optional_auth_is_missing(self):
        def execute(tool, args, **kwargs):
            if tool in ("gh", "az", "claude", "codex"):
                return 1
            return 19 if tool == "dotnet" and args[0] == "run" else 0
        with patch.object(connect, "run", side_effect=execute) as run:
            code, out, err = self.invoke(["start", "--serve"])
        self.assertEqual(code, 19)
        self.assertEqual(run.call_args.args[0], "dotnet")
        self.assertIn("--no-build", run.call_args.args[1])
        self.assertIn("--no-launch-profile", run.call_args.args[1])
        self.assertTrue(run.call_args.kwargs["noninteractive"])
        self.assertEqual(run.call_args.kwargs["additions"], {"HELIOS_REPO_ROOT": str(ROOT)})
        self.assertNotIn("quiet", run.call_args.kwargs)

    def test_start_rejects_serve_json_and_unknown_flags_before_mutation(self):
        with patch.object(connect, "run") as run:
            for args in (["start", "--serve", "--json"], ["start", "--connect"], ["start", "--client", "claude"]):
                self.assertEqual(self.invoke(args)[0], 2)
            run.assert_not_called()

    def test_unattended_child_gets_eof_and_output_never_echoes_secrets(self):
        secret = "sentinel-cli-secret-never-display"
        program = "import os,sys; assert sys.stdin.read() == ''; print(os.environ['HELIOS_TEST_SECRET']); print(os.environ['HELIOS_TEST_SECRET'], file=sys.stderr)"
        out, err = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"HELIOS_TEST_SECRET": secret}), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            step = connect.unattended_step("fixture", connect.sys.executable, ["-c", program], timeout=15, required=True, next_action="retry fixture")
        self.assertEqual(step["exitCode"], 0)
        self.assertNotIn(secret, json.dumps(step) + out.getvalue() + err.getvalue())

    def test_unattended_subprocess_disables_prompt_channels(self):
        with patch.object(connect, "native", return_value=(["/tools/dotnet"], {})), patch.object(connect.subprocess, "run") as run:
            run.return_value.returncode = 0
            connect.run("dotnet", ["build"], noninteractive=True, quiet=True)
        options = run.call_args.kwargs
        self.assertEqual(options["stdin"], subprocess.DEVNULL)
        self.assertEqual(options["stdout"], subprocess.DEVNULL)
        self.assertEqual(options["stderr"], subprocess.DEVNULL)
        self.assertEqual(options["env"]["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(options["env"]["GH_PROMPT_DISABLED"], "1")
        self.assertEqual(options["env"]["NUGET_CREDENTIALPROVIDER_NONINTERACTIVE"], "true")

    def test_unattended_timeout_stops_descendant_before_it_can_mutate(self):
        with tempfile.TemporaryDirectory(prefix="helios timeout ") as directory:
            ready = Path(directory) / "child-ready"
            mutation = Path(directory) / "late-write"
            child = "import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text('ready'); time.sleep(3); pathlib.Path(sys.argv[2]).write_text('must not happen')"
            parent = "import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', sys.argv[1], sys.argv[2], sys.argv[3]]); time.sleep(30)"
            code = connect.run(connect.sys.executable, ["-c", parent, child, str(ready), str(mutation)],
                               noninteractive=True, quiet=True, timeout=2)
            self.assertEqual(code, 124)
            self.assertTrue(ready.exists(), "The child must have started for this tree-cleanup fixture to prove anything.")
            time.sleep(3.2)
            self.assertFalse(mutation.exists(), "A timed-out setup child continued writing after the timeout receipt.")

    def test_windows_bounded_process_uses_native_taskkill_with_tree_flags(self):
        with patch.object(connect, "WINDOWS", True), patch.object(connect.subprocess, "CREATE_NEW_PROCESS_GROUP", 512, create=True), patch.object(connect, "native", side_effect=[(["C:/tools/dotnet.exe"], {}), (["C:/Windows/System32/taskkill.exe"], {})]), patch.object(connect.subprocess, "Popen") as popen, patch.object(connect.subprocess, "run") as execute:
            child = popen.return_value
            child.pid = 48123
            child.wait.side_effect = [subprocess.TimeoutExpired("dotnet", 2), 1]
            execute.return_value.returncode = 0
            self.assertEqual(connect.run("dotnet", ["build"], timeout=2, quiet=True, noninteractive=True), 124)
        self.assertEqual(popen.call_args.kwargs["creationflags"], 512)
        self.assertEqual(popen.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(execute.call_args.args[0], ["C:/Windows/System32/taskkill.exe", "/PID", "48123", "/T", "/F"])
        self.assertIs(execute.call_args.kwargs["shell"], False)
        self.assertEqual(execute.call_args.kwargs["timeout"], 15)

    def test_uncertain_timeout_cleanup_is_reported_before_retrying(self):
        with patch.object(connect, "WINDOWS", False), patch.object(connect, "native", return_value=(["/tools/dotnet"], {})), patch.object(connect.subprocess, "Popen") as popen, patch.object(connect, "stop_process_tree", return_value=False):
            popen.return_value.wait.side_effect = subprocess.TimeoutExpired("dotnet", 2)
            step = connect.unattended_step("build", "dotnet", ["build"], timeout=2, required=True, next_action="rerun connect.sh start")
        self.assertEqual(step["exitCode"], 125)
        self.assertEqual(step["status"], "cleanup-unverified")
        self.assertIn("Inspect remaining setup child processes before retrying", step["nextAction"])
        self.assertTrue(popen.call_args.kwargs["start_new_session"])

    def test_start_timeout_is_reported_with_no_child_diagnostics(self):
        def execute(tool, args, **kwargs):
            return 124 if tool == "claude" else 0
        with patch.object(connect, "run", side_effect=execute):
            code, out, err = self.invoke(["start", "--json"])
        report = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(next(step for step in report["steps"] if step["name"] == "auth:claude")["status"], "timeout")

    @unittest.skipUnless(shutil.which("git"), "Git required")
    def test_start_reruns_preserve_real_workspace_ids_branches_and_edits(self):
        real_run = connect.run
        with tempfile.TemporaryDirectory(prefix="helios start ") as directory:
            repo = Path(directory) / "repo"
            repo.mkdir()
            git_env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
            def git(*args):
                return subprocess.run(["git", "-C", str(repo), *args], env=git_env, check=True,
                                      capture_output=True, text=True, timeout=30).stdout
            git("init", "-b", "main")
            (repo / "README.md").write_text("original\n")
            git("add", "README.md")
            git("-c", "user.name=HELIOS Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull, "commit", "-m", "fixture")
            head = git("rev-parse", "HEAD").strip()
            for name in ("scripts/validation/validate_config_schemas.py", "scripts/bootstrap/agent_workspace.py", "HELIOS.sln"):
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, path)
            (repo / "src/mcp/HELIOS.RemoteMcp").mkdir(parents=True)
            def execute(tool, args, **kwargs):
                if args and args[0] == str(repo / "scripts/bootstrap/agent_workspace.py"):
                    return real_run(tool, args, **kwargs)
                return 0
            with patch.object(connect, "ROOT", repo), patch.object(connect, "inventory", return_value={}), patch.object(connect, "config", return_value={"roles": ["claude", "codex", "copilot", "chatgpt", "hermes", "xcore", "human"]}), patch.object(connect, "run", side_effect=execute):
                first, out, err = self.invoke(["start", "--json"])
                self.assertEqual(first, 0, out + err)
                registry_path = repo / ".git/helios/workspaces.json"
                registry = json.loads(registry_path.read_text())
                claude = Path(registry["workspaces"]["claude"]["path"])
                (claude / "README.md").write_text("preserved agent edits\n")
                (repo / "README.md").write_text("new canonical revision\n")
                git("add", "README.md")
                git("-c", "user.name=HELIOS Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=" + os.devnull, "commit", "-m", "advance main")
                second, out, err = self.invoke(["start", "--json"])
            self.assertEqual(second, 0, out + err)
            self.assertEqual(json.loads(registry_path.read_text()), registry)
            self.assertEqual(len(registry["workspaces"]), 7)
            self.assertEqual((claude / "README.md").read_text(), "preserved agent edits\n")
            self.assertEqual(git("rev-parse", "workspace/claude/claude").strip(), head)

    def test_start_workspace_conflict_is_visible_without_blocking_built_core(self):
        def execute(tool, args, **kwargs):
            return 2 if "create" in args and args[-1] == "claude" else 0
        with patch.object(connect, "run", side_effect=execute):
            code, out, err = self.invoke(["start", "--json"])
        report = json.loads(out)
        self.assertEqual(code, 2)
        self.assertEqual(report["status"], "partial")
        self.assertTrue(report["localCoreReady"])
        self.assertFalse(report["workspacesReady"])
        self.assertEqual(report["nextAction"], "connect.sh workspace create claude --agent claude")

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
