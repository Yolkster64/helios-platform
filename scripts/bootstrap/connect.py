#!/usr/bin/env python3
"""One native entry point; C# owns AIHub and both MCP transports.

Default status is offline. This module never reads a credential store or makes
HTTP requests. Explicit native commands retain their own identity and policy.
"""
from __future__ import annotations

import json
import importlib.util
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
WINDOWS = os.name == "nt"
TOOLS = ("dotnet", "pwsh", "gh", "az", "claude", "codex", "copilot")
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]*$")
MAX_CONFIG = 256 * 1024
HELP = """HELIOS — Connect → Unify → Automate → Validate

  connect.sh [status] [--json]       Offline inventory (default)
  connect.sh start [--json]        Unattended tools, build, workspaces and saved-session checks
  connect.sh start --serve         Prepare, then run the shared MCP bridge in foreground
  connect.sh project                Shared project and destination map
  connect.sh parts [NAME]          Core, Desktop, USB, Cloud and Fleet setup/test/release plans
  connect.sh test NAME             Run one part's fixed local checks
  connect.sh auth status [--json]   Explicit bounded CLI authentication checks
  connect.sh identity [--strict]   Offline Azure OIDC, runtime identity and Key Vault plan
  connect.sh login github|azure|claude|codex
  connect.sh setup [--verify-only]  Existing setup, verification first
  connect.sh setup --connect       Interactive full setup and logins
  connect.sh claude [ARGS...]       Claude Code + existing HELIOS plugin
  connect.sh codex [ARGS...]        Codex + the same checkout and C# MCP
  connect.sh copilot [ARGS...]      Copilot CLI + trusted repository MCP
  connect.sh cloud-shell           Verify the existing Cloud Shell setup
  connect.sh cloud-shell --connect Interactive setup; skips inference smoke calls
  connect.sh combo [ARGS...]        Existing AIHub compare (explicit provider list)
  connect.sh learning              Advisory fleet plan from recorded outcomes
  connect.sh fleet                 Offline fleet readiness and activation dependencies
  connect.sh analyze [ARGS...]     Offline analysis of an explicit outcome JSONL file
  connect.sh ai [ARGS...]           Existing C# AIHub CLI
  connect.sh mcp                    Existing C# stdio MCP server
  connect.sh bridge                 Shared Streamable HTTP MCP, local by default
  connect.sh bridge connect URL    Register the HTTP endpoint in Claude's local scope
  connect.sh return [ARGS...]      Shared ChatGPT Workspace Agent return channel
  connect.sh workspace [ARGS...]   Isolated agent worktrees in this project

Windows: pwsh -NoProfile -File ./connect.ps1 with the same arguments.
Python 3.10+ is required. Missing lanes do not prevent the offline inventory.
Start requires Git and the .NET 10 SDK. With PowerShell/npm it installs missing coding CLIs.
Optional tools and service logins never gate the core.
ChatGPT sign-in is not an OpenAI API key. App credentials stay with their apps.
"""
AUTH_PROBES = {
    "github": ("gh", ["auth", "status", "--hostname", "github.com"]),
    "azure": ("az", ["account", "get-access-token", "--output", "none"]),
    "claude": ("claude", ["auth", "status"]),
    "codex": ("codex", ["login", "status"]),
}


class ConnectionError(Exception):
    pass


def identity_plan():
    # Load only the maintained sibling of this launcher, never a path supplied by
    # a scanned checkout, a plugin packet or an environment variable.
    path = Path(__file__).resolve().with_name("identity_plan.py")
    if not path.is_file():
        raise ConnectionError("The identity planner is missing from this checkout.")
    spec = importlib.util.spec_from_file_location("helios_identity_plan", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.build_plan()


def config(path):
    file = ROOT / path
    try:
        if file.stat().st_size > MAX_CONFIG:
            raise ConnectionError("Public configuration exceeds the size limit.")
        value = json.loads(file.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ConnectionError("Public configuration must be an object.")
        return value
    except (OSError, ValueError):
        raise ConnectionError("Public configuration is missing or invalid: " + path) from None


def env_refs(value):
    found = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key.endswith("Env") and isinstance(child, str) and ENV_NAME.fullmatch(child):
                found.add(child)
            else:
                found.update(env_refs(child))
    elif isinstance(value, list):
        for child in value:
            found.update(env_refs(child))
    return found


def lane(value):
    names = sorted(env_refs(value))
    return {"state": "unverified", "environment": [
        {"name": name, "present": bool(os.environ.get(name, "").strip())}
        for name in names
    ]}


def inventory():
    hub = config("config/aihub.json")
    connectors = config("config/connectors.json")
    project = config("config/control-project.json")
    integrations = project.get("integrations", {})
    providers = hub.get("providers", {})
    return {
        "projectId": project["projectId"],
        "mode": "offline-inventory", "authenticationProbed": False,
        "tools": {name: {"installed": shutil.which(name) is not None,
                         "authentication": "not-probed"} for name in TOOLS},
        "providers": {name: lane(value) for name, value in providers.items()},
        "connectors": {name: lane([value, connectors.get(name, {})])
                       for name, value in integrations.items()},
        "notes": [
            "Provider inventory uses config/aihub.json; AIHub owns custom AIHUB_CONFIG profiles.",
            "Environment presence does not prove authentication, service readiness or delivery.",
            "ChatGPT/Codex sign-in does not create an OpenAI API key.",
            "ChatGPT app sessions do not export credentials to local tools or Actions.",
        ],
    }


def show(report, as_json):
    if as_json:
        print(json.dumps(report, indent=2))
        return
    print("HELIOS — offline connection inventory")
    print("Tools: " + ", ".join(name + (" installed" if state["installed"] else " missing")
                                for name, state in report["tools"].items()))
    for group in ("providers", "connectors"):
        print("\n" + group.capitalize() + ":")
        for name, value in report[group].items():
            references = ", ".join(v["name"] + (" present" if v["present"] else " absent")
                                   for v in value["environment"])
            print("  " + name + ": unverified" + (" (" + references + ")" if references else ""))
    print("\n" + "\n".join(report["notes"]))
    print("\nNext: connect.sh project | auth status | setup | claude | codex | bridge")


def native(name):
    """Do not execute Windows batch shims; use known official native layouts.

    Sources: Azure azure-cli build_scripts/windows/scripts/az_{msi,zip}.cmd,
    OpenAI codex/codex-cli/bin/codex.js and Anthropic claude-code native package.
    No wrapper text or credential file is read.
    """
    candidate = shutil.which(name)
    if not candidate:
        raise ConnectionError("Required tool is not installed: " + name)
    path = Path(candidate)
    if not WINDOWS or path.suffix.lower() not in (".cmd", ".bat"):
        return [str(path)], {}
    native_exe = shutil.which(name + ".exe")
    if native_exe:
        return [native_exe], {}
    if name == "az" and path.name.lower() == "az.cmd":
        installer = {"wbin": "MSI", "bin": "ZIP"}.get(path.parent.name.lower())
        python = path.parent.parent / "python.exe"
        if installer and python.is_file():
            return [str(python), "-IBm", "azure.cli"], {"AZ_INSTALLER": installer}
    if name == "claude":
        binary = path.parent / "node_modules/@anthropic-ai/claude-code/bin/claude.exe"
        if binary.is_file():
            return [str(binary)], {}
    if name == "codex":
        package = path.parent / "node_modules/@openai/codex"
        arch = "aarch64" if os.environ.get("PROCESSOR_ARCHITECTURE", "").lower() == "arm64" else "x86_64"
        triple = arch + "-pc-windows-msvc"
        npm_arch = "arm64" if arch == "aarch64" else "x64"
        for base in (package, package / f"node_modules/@openai/codex-win32-{npm_arch}",
                     path.parent / f"node_modules/@openai/codex-win32-{npm_arch}"):
            binary = base / "vendor" / triple / "codex/codex.exe"
            if binary.is_file():
                return [str(binary)], {}
    if name == "copilot":
        # @github/copilot@1.0.83 npm-loader.js imports the platform package;
        # @github/copilot-win32-{x64,arm64} exports ./copilot.exe.
        arch = "arm64" if os.environ.get("PROCESSOR_ARCHITECTURE", "").lower() == "arm64" else "x64"
        package = "@github/copilot-win32-" + arch
        for base in (path.parent / "node_modules", path.parent / "node_modules/@github/copilot/node_modules"):
            binary = base / package / "copilot.exe"
            if binary.is_file():
                return [str(binary)], {}
    raise ConnectionError("Install a native executable for " + name + "; this batch-wrapper layout is unsupported.")


def run(name, args, *, timeout=None, quiet=False, stderr_output=False, additions=None,
        noninteractive=False):
    command, extra = native(name)
    env = dict(os.environ)
    env.update(extra)
    env.update(additions or {})
    if noninteractive:
        env.update({"CI": "true", "NO_COLOR": "1", "GH_PROMPT_DISABLED": "1",
                    "GIT_TERMINAL_PROMPT": "0", "DOTNET_NOLOGO": "1",
                    "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
                    "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                    "NUGET_EXE_NO_PROMPT": "true",
                    "NUGET_CREDENTIALPROVIDER_NONINTERACTIVE": "true"})
    try:
        options = {"cwd": ROOT, "env": env, "shell": False,
                   "stdin": subprocess.DEVNULL if noninteractive else None,
                   "stdout": subprocess.DEVNULL if quiet else sys.stderr if stderr_output else None,
                   "stderr": subprocess.DEVNULL if quiet else None}
        if noninteractive and timeout is not None:
            # A setup process can spawn npm, compiler or Git children. A timed-out
            # parent alone is not a stopped setup; bound and terminate its tree.
            taskkill = native("taskkill.exe")[0] if WINDOWS else None
            if WINDOWS:
                options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
            else:
                options["start_new_session"] = True
            child = subprocess.Popen(command + list(args), **options)
            try:
                return child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                return 124 if stop_process_tree(child, taskkill) else 125
            except KeyboardInterrupt:
                stop_process_tree(child, taskkill)
                raise
        return subprocess.run(command + list(args), timeout=timeout, check=False, **options).returncode
    except subprocess.TimeoutExpired:
        return 124
    except OSError:
        raise ConnectionError("The native command could not start; check its installation.") from None


def stop_process_tree(child, taskkill):
    """Stop the audited helper's ordinary descendants, then reap its parent.

    Windows taskkill keeps tree cleanup out of shell parsing. A failed cleanup is
    reported separately so automation never treats an uncertain stop as completed.
    """
    cleaned = False
    try:
        if taskkill is not None:
            cleaned = subprocess.run([*taskkill, "/PID", str(child.pid), "/T", "/F"],
                                     shell=False, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     timeout=15, check=False).returncode == 0
        else:
            os.killpg(child.pid, signal.SIGKILL)
            cleaned = True
    except ProcessLookupError:
        cleaned = True
    except (OSError, subprocess.TimeoutExpired):
        pass
    finally:
        # Also reap the parent when taskkill itself was unavailable or failed.
        try:
            child.kill()
        except OSError:
            pass
        try:
            child.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            cleaned = False
    return cleaned


def terminal():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise ConnectionError("Open an interactive terminal for login or full setup.")


def require(path):
    if not (ROOT / path).exists():
        raise ConnectionError("Required checkout path is missing: " + path)


def unattended_step(name, tool, argv, *, timeout, required, next_action):
    """Only fixed public diagnostics escape a child; neither logs nor tokens do."""
    try:
        code = run(tool, argv, timeout=timeout, quiet=True, noninteractive=True)
        status = "ready" if code == 0 else "timeout" if code == 124 else "cleanup-unverified" if code == 125 else "failed"
    except ConnectionError:
        code, status = 127, "unavailable"
    if code == 125:
        next_action = "Inspect remaining setup child processes before retrying. " + next_action
    return {"name": name, "status": status, "exitCode": code, "required": required,
            "nextAction": None if code == 0 else next_action}


def auth_steps():
    return [unattended_step("auth:" + name, tool, argv, timeout=15, required=False,
                           next_action="Install/check " + tool + "; if sign-in is missing: connect.sh login " + name)
            for name, (tool, argv) in AUTH_PROBES.items()]


def install_coding_tools():
    """Reuse the installation-only helper; do not run the broader login/setup chain."""
    if all(shutil.which(tool) for tool in ("claude", "codex", "copilot")):
        return []
    action = "Install/check PowerShell 7 and Node.js/npm, then rerun connect.sh start."
    installer = "scripts/bootstrap/setup-ai-clis.ps1"
    if not all(shutil.which(tool) for tool in ("pwsh", "npm")):
        return [{"name": "coding-tools", "status": "unavailable", "exitCode": 127,
                 "required": False, "nextAction": action}]
    if not (ROOT / installer).is_file():
        return [{"name": "coding-tools", "status": "failed", "exitCode": 2,
                 "required": False, "nextAction": "Restore scripts/bootstrap/setup-ai-clis.ps1 and rerun connect.sh start."}]
    return [unattended_step("coding-tools", "pwsh",
                             ["-NoProfile", "-NonInteractive", "-File", str(ROOT / installer), "-Skip", "gh"],
                             timeout=600, required=False,
                             next_action="Check npm installation permissions/network, then rerun connect.sh start.")]


def prepare_start():
    """Finite preparation, using existing validation and workspace ownership rules.

    Successful preparation is not a running server or a verified cloud integration.
    The existing workspace registry is the only persisted setup state. Reruns build
    incrementally and preserve worktree branches and edits instead of resetting them.
    """
    steps = []
    connection_inventory = {}
    validate = "scripts/validation/validate_config_schemas.py"
    workspace = "scripts/bootstrap/agent_workspace.py"
    try:
        for path in (validate, workspace, "HELIOS.sln", "src/mcp/HELIOS.RemoteMcp"):
            require(path)
        # Parse the public launch inputs before doing any build or workspace work.
        connection_inventory = inventory()
        roles = config("config/agent-catalog.json")["roles"]
        if not isinstance(roles, list) or not roles or not all(isinstance(role, str) for role in roles):
            raise ConnectionError("The agent catalog has no valid role list.")
    except (ConnectionError, KeyError, TypeError, ValueError, OSError):
        steps.append({"name": "configuration", "status": "failed", "exitCode": 2,
                      "required": True, "nextAction": "Restore the complete reviewed checkout and rerun connect.sh start."})
    else:
        steps.append(unattended_step("configuration", sys.executable,
                                     [str(ROOT / validate), "--engine", "builtin", "--json"],
                                     timeout=60, required=True,
                                     next_action="python3 scripts/validation/validate_config_schemas.py --engine builtin"))
    if steps[0]["exitCode"] == 0:
        steps.append(unattended_step("build", "dotnet",
                                     ["build", str(ROOT / "HELIOS.sln"), "-c", "Release", "--nologo",
                                      "-m:1", "-nodeReuse:false", "-p:UseSharedCompilation=false"],
                                     timeout=600, required=True,
                                     next_action="Install/check the .NET 10 SDK, then run: dotnet build HELIOS.sln -c Release"))
        steps.extend(install_coding_tools())
        listed = unattended_step("workspaces:list", sys.executable,
                                 [str(ROOT / workspace), "list"], timeout=120, required=True,
                                 next_action="connect.sh workspace list")
        steps.append(listed)
        if listed["exitCode"] == 0:
            for role in roles:
                # The catalog owns roles; the existing helper owns validation,
                # locking, fixed paths, branch ownership and idempotent creation.
                name = "operator" if role == "human" else role
                steps.append(unattended_step("workspace:" + name, sys.executable,
                                             [str(ROOT / workspace), "create", name, "--agent", role],
                                             timeout=120, required=True,
                                             next_action="connect.sh workspace create " + name + " --agent " + role))
    local_ready = any(step["name"] == "build" and step["exitCode"] == 0 for step in steps)
    workspace_checks = [step for step in steps if step["name"].startswith(("workspace:", "workspaces:"))]
    workspaces_ready = len(workspace_checks) > 1 and all(step["exitCode"] == 0 for step in workspace_checks)
    prepared = local_ready and workspaces_ready
    # Session checks are independent; a failed/missing optional service never
    # prevents the local runtime from building or the workspaces from preparing.
    authentication = auth_steps() if steps[0]["exitCode"] == 0 else []
    steps.extend(authentication)
    report = {"mode": "unattended-start", "status": "blocked" if not local_ready else
              "ready" if prepared and all(step["exitCode"] == 0 for step in steps) else "partial",
              "localCoreReady": local_ready, "workspacesReady": workspaces_ready,
              "exitCode": 0 if prepared else 2, "runtimeState": "stopped",
              "authenticationProbed": bool(authentication), "providerInferenceVerified": False,
              "liveConnectorsVerified": False, "steps": steps,
              "connectors": connection_inventory.get("connectors", {}),
              "identityPlan": identity_plan(),
              "integrationGuide": "docs/CONNECT.md",
              "nextAction": next((step["nextAction"] for step in steps
                                  if step["required"] and step["exitCode"] != 0),
                                 "connect.sh start --serve"),
              "notes": ["Readiness covers local preparation and bounded CLI session checks only.",
                        "Optional CLI/service gaps do not gate the local core; no login or model call was started.",
                        "Missing coding CLIs are installed with the existing helper when PowerShell/npm are available.",
                        "Existing workspaces keep their branches, commits and edits; agents were not launched.",
                        "SharePoint/Outlook adapters, hosted access and real fleet execution need separate runtime verification."]}
    return report


def show_start(report, as_json):
    if as_json:
        print(json.dumps(report, indent=2))
        return
    print("HELIOS — unattended preparation: " + report["status"])
    for step in report["steps"]:
        print("  " + step["name"] + ": " + step["status"] + " (exit " + str(step["exitCode"]) + ")")
    print("\nLocal core: " + ("built" if report["localCoreReady"] else "blocked") +
          "; runtime: stopped; live connectors and inference: unverified.")
    print("Integration setup and the two-way ChatGPT return path: " + report["integrationGuide"])
    print("Azure identity plan: " + report["identityPlan"]["status"] +
          "; details: connect.sh identity (no cloud changes).")
    print("Next: " + report["nextAction"])
    for step in report["steps"]:
        if not step["required"] and step["nextAction"]:
            print("Optional " + step["name"].removeprefix("auth:") + ": " + step["nextAction"])


def endpoint(value):
    try:
        uri = urlsplit(value)
        _ = uri.port
        local = uri.hostname in ("localhost", "127.0.0.1", "::1")
        if (uri.scheme != "https" and not (uri.scheme == "http" and local)) or not uri.hostname:
            raise ValueError()
        if uri.username is not None or uri.password is not None or uri.query or uri.fragment or uri.path != "/mcp":
            raise ValueError()
        if any(ord(c) <= 32 or ord(c) == 127 for c in value):
            raise ValueError()
    except ValueError:
        raise ConnectionError("Use an HTTPS /mcp URL without credentials or query parameters; HTTP is allowed only on loopback.") from None
    return value


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    if sys.version_info < (3, 10):
        print("HELIOS requires Python 3.10 or newer.", file=sys.stderr)
        return 2
    command = args.pop(0) if args else "status"
    try:
        if command in ("help", "--help", "-h"):
            print(HELP)
            return 0
        if command == "status" and args in ([], ["--json"]):
            show(inventory(), bool(args))
            return 0
        if command == "project" and not args:
            print(json.dumps(config("config/control-project.json"), indent=2))
            return 0
        if command == "parts" and len(args) <= 1:
            path = "scripts/bootstrap/components.py"
            require(path)
            return run(sys.executable, [str(ROOT / path), *(["plan", args[0]] if args else ["list"])])
        if command == "test" and len(args) == 1:
            path = "scripts/bootstrap/components.py"
            require(path)
            return run(sys.executable, [str(ROOT / path), "test", args[0]])
        if command == "identity" and args in ([], ["--json"], ["--strict"], ["--json", "--strict"], ["--strict", "--json"]):
            report = identity_plan()
            print(json.dumps(report, indent=2))
            return 2 if "--strict" in args and report["status"] != "prepared" else 0
        if command == "start" and args in ([], ["--json"], ["--serve"]):
            report = prepare_start()
            show_start(report, args == ["--json"])
            if args == ["--serve"] and report["localCoreReady"]:
                print("Starting the shared MCP bridge in the foreground; Ctrl+C stops it.", flush=True)
                return run("dotnet", ["run", "--project", str(ROOT / "src/mcp/HELIOS.RemoteMcp"),
                                      "-c", "Release", "--no-launch-profile", "--no-build"],
                           noninteractive=True, additions={"HELIOS_REPO_ROOT": str(ROOT)})
            return report["exitCode"]
        if command == "auth" and args in (["status"], ["status", "--json"]):
            states = {step["name"].removeprefix("auth:"):
                      "authenticated-cli" if step["exitCode"] == 0 else
                      "unavailable" if step["status"] == "unavailable" else "unverified"
                      for step in auth_steps()}
            print(json.dumps({"authenticationProbed": True, "cliSessions": states,
                              "providerInferenceVerified": False}, indent=2))
            return 0 if all(v == "authenticated-cli" for v in states.values()) else 2
        if command == "login" and len(args) == 1:
            logins = {"github": ("gh", ["auth", "login", "--web", "--hostname", "github.com"]),
                      "azure": ("az", ["login"]), "claude": ("claude", ["auth", "login"]),
                      "codex": ("codex", ["login"])}
            if args[0] in logins:
                terminal()
                tool, argv = logins[args[0]]
                return run(tool, argv)
        if command == "setup":
            if any(v not in ("--verify-only", "--connect", "--json", "--skip-setup") for v in args):
                raise ConnectionError("Unsupported setup option. Run connect.sh help.")
            if "--connect" in args and ("--verify-only" in args or "--json" in args):
                raise ConnectionError("Use --connect interactively, without --verify-only or --json.")
            if "--connect" in args:
                terminal()
            elif "--verify-only" not in args:
                args.insert(0, "--verify-only")
            if WINDOWS:
                flags = {"--connect": "-Connect", "--verify-only": "-VerifyOnly", "--json": "-Json", "--skip-setup": "-SkipSetup"}
                return run("pwsh", ["-NoProfile", "-File", str(ROOT / "scripts/bootstrap/first-run.ps1"),
                                    *[flags[v] for v in args]])
            return run("bash", [str(ROOT / "scripts/bootstrap/first-run.sh"), *args])
        if command == "cloud-shell" and args in ([], ["--verify-only"], ["--connect"]):
            connect = args == ["--connect"]
            if connect:
                terminal()
            if WINDOWS:
                return run("pwsh", ["-NoProfile", "-File", str(ROOT / "scripts/bootstrap/cloud-shell-setup.ps1"),
                                    "-SkipSmoke" if connect else "-VerifyOnly"])
            return run("bash", [str(ROOT / "scripts/bootstrap/cloud-shell-setup.sh"),
                                "--skip-smoke" if connect else "--verify-only"])
        if command in ("return", "workspace"):
            helper = {"return": "workspace_agent_handoff.py", "workspace": "agent_workspace.py"}[command]
            path = "scripts/bootstrap/" + helper
            require(path)
            return run(sys.executable, [str(ROOT / path), *args])
        if command == "combo":
            if not args:
                return main(["ai", "help"])
            if "--providers" not in args and not any(v.startswith("--providers=") for v in args):
                raise ConnectionError("Choose the intended providers explicitly: combo PROMPT --providers a,b")
            return main(["ai", "compare", *args])
        if command == "learning" and not args:
            return main(["ai", "fleet-plan", "--json"])
        if command == "fleet" and args in ([], ["--json"]):
            return main(["ai", "fleet-readiness", "--json"])
        if command == "analyze":
            return main(["ai", "combo-analyze", *args])
        if command in ("ai", "mcp", "bridge"):
            if command == "bridge" and len(args) == 2 and args[0] == "connect":
                return run("claude", ["mcp", "add", "--transport", "http", "helios-remote",
                                      "--scope", "local", endpoint(args[1])])
            if command != "ai" and args:
                raise ConnectionError("Unsupported MCP server arguments. Configure the documented environment variables.")
            project = {"ai": "src/ai/HELIOS.AIHub.Cli", "mcp": "src/mcp/HELIOS.Mcp",
                       "bridge": "src/mcp/HELIOS.RemoteMcp"}[command]
            require(project)
            if command == "mcp":
                code = run("dotnet", ["build", str(ROOT / project), "-c", "Release"], stderr_output=True)
                if code != 0:
                    return code
            argv = ["run", "--project", str(ROOT / project), "-c", "Release", "--no-launch-profile"]
            if command == "mcp":
                argv.append("--no-build")
            if command == "ai":
                argv.extend(["--", *args])
            return run("dotnet", argv, additions={"HELIOS_REPO_ROOT": str(ROOT)})
        if command == "claude":
            require("plugins/helios-operator")
            return run("claude", ["--plugin-dir", str(ROOT / "plugins/helios-operator"), *args])
        if command == "copilot":
            require(".mcp.json")
            return run("copilot", args)
        if command == "codex":
            require("src/mcp/HELIOS.Mcp")
            overrides = {"mcp_servers.helios.command": "dotnet",
                         "mcp_servers.helios.args": ["run", "--project", str(ROOT / "src/mcp/HELIOS.Mcp"), "-c", "Release"],
                         "mcp_servers.helios.cwd": str(ROOT),
                         "mcp_servers.helios.env.HELIOS_REPO_ROOT": str(ROOT)}
            argv = []
            for key, value in overrides.items():
                argv.extend(["-c", key + "=" + json.dumps(value)])
            return run("codex", [*argv, *args])
        raise ConnectionError("Unknown command or unsupported arguments. Run connect.sh help.")
    except ConnectionError as error:
        print("HELIOS: " + str(error), file=sys.stderr)
        return 2
    except (OSError, ValueError, KeyError, TypeError):
        print("HELIOS: Configuration or native command failed; diagnostic contents were suppressed.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
