#!/usr/bin/env python3
"""One native entry point; C# owns AIHub and both MCP transports.

Default status is offline. This module never reads a credential store or makes
HTTP requests. Explicit native commands retain their own identity and policy.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
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
  connect.sh project                Shared project and destination map
  connect.sh auth status [--json]   Explicit bounded CLI authentication checks
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
  connect.sh ai [ARGS...]           Existing C# AIHub CLI
  connect.sh mcp                    Existing C# stdio MCP server
  connect.sh bridge                 Shared Streamable HTTP MCP, local by default
  connect.sh bridge connect URL    Register the HTTP endpoint in Claude's local scope
  connect.sh return [ARGS...]      Shared ChatGPT Workspace Agent return channel
  connect.sh workspace [ARGS...]   Isolated agent worktrees in this project

Windows: pwsh -NoProfile -File ./connect.ps1 with the same arguments.
Python 3.10+ is required. Missing lanes do not prevent the offline inventory.
ChatGPT sign-in is not an OpenAI API key. App credentials stay with their apps.
"""


class ConnectionError(Exception):
    pass


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


def run(name, args, *, timeout=None, quiet=False, stderr_output=False, additions=None):
    command, extra = native(name)
    env = dict(os.environ)
    env.update(extra)
    env.update(additions or {})
    try:
        return subprocess.run(command + list(args), cwd=ROOT, env=env, shell=False,
                              timeout=timeout, check=False,
                              stdout=subprocess.DEVNULL if quiet else sys.stderr if stderr_output else None,
                              stderr=subprocess.DEVNULL if quiet else None).returncode
    except subprocess.TimeoutExpired:
        return 124
    except OSError:
        raise ConnectionError("The native command could not start; check its installation.") from None


def terminal():
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise ConnectionError("Open an interactive terminal for login or full setup.")


def require(path):
    if not (ROOT / path).exists():
        raise ConnectionError("Required checkout path is missing: " + path)


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
        if command == "auth" and args in (["status"], ["status", "--json"]):
            probes = {"github": ("gh", ["auth", "status", "--hostname", "github.com"]),
                      "azure": ("az", ["account", "get-access-token", "--output", "none"]),
                      "claude": ("claude", ["auth", "status"]),
                      "codex": ("codex", ["login", "status"])}
            states = {}
            for name, (tool, argv) in probes.items():
                try:
                    code = run(tool, argv, timeout=15, quiet=True)
                    states[name] = "authenticated-cli" if code == 0 else "unverified"
                except ConnectionError:
                    states[name] = "unavailable"
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
