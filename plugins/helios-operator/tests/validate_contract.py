#!/usr/bin/env python3
"""Validate the repository-to-plugin contracts without network or third-party packages."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
PLUGIN_ROOT = REPO_ROOT / "plugins" / "helios-operator"
EXPECTED_TOOLS = {
    "helios_operator_profile_get",
    "helios_operator_profile_save",
    "helios_operator_context_sync",
    "helios_operator_next_steps_get",
}


def load_json(path: Path, errors: list[str]) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{path.relative_to(REPO_ROOT)}: {exc}")
        return {}
    if not isinstance(value, dict):
        errors.append(f"{path.relative_to(REPO_ROOT)}: top level must be an object")
        return {}
    return value


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []
    manifest = load_json(PLUGIN_ROOT / ".claude-plugin" / "plugin.json", errors)
    marketplace = load_json(REPO_ROOT / ".claude-plugin" / "marketplace.json", errors)
    mcp = load_json(REPO_ROOT / ".mcp.json", errors)
    settings = load_json(REPO_ROOT / ".claude" / "settings.json", errors)

    require(manifest.get("name") == "helios-operator", "plugin name must be helios-operator", errors)
    require(manifest.get("version") == "0.1.0", "plugin version must be 0.1.0", errors)
    require(marketplace.get("name") == "helios-platform", "marketplace name must be helios-platform", errors)
    require(isinstance(marketplace.get("description"), str) and marketplace["description"].strip(),
            "marketplace description must be a non-empty string", errors)
    owner = marketplace.get("owner", {})
    require(owner.get("url") == "https://github.com/Yolkster64",
            "marketplace owner URL must point to Yolkster64", errors)
    entries = marketplace.get("plugins", [])
    require(isinstance(entries, list) and len(entries) == 1, "marketplace must expose one plugin", errors)
    if isinstance(entries, list) and entries:
        entry = entries[0]
        require(entry.get("name") == "helios-operator", "marketplace plugin name drifted", errors)
        require(entry.get("source") == "./plugins/helios-operator", "marketplace source drifted", errors)
        require(entry.get("category") == "development", "marketplace plugin category drifted", errors)
        require(isinstance(entry.get("tags"), list) and len(entry["tags"]) > 0,
                "marketplace plugin tags must be a non-empty list", errors)
        source = entry.get("source", "")
        require(source.startswith("./"), "marketplace plugin source must stay repository-relative", errors)
        plugin_path = (REPO_ROOT / source[2:]).resolve() if source.startswith("./") else REPO_ROOT
        require(plugin_path.is_dir(), "marketplace plugin source directory is missing", errors)
        require((plugin_path / ".claude-plugin" / "plugin.json").is_file(),
                "plugin source must include .claude-plugin/plugin.json", errors)
        require((plugin_path / "README.md").is_file(), "plugin source must include README.md", errors)
        require((plugin_path / "skills" / "operate-helios" / "SKILL.md").is_file(),
                "plugin source must include the operate-helios skill manifest", errors)
        require((plugin_path / "agents" / "fabric-operator.md").is_file(),
                "plugin source must include the fabric-operator agent manifest", errors)

    # The plugin deliberately bundles NO MCP server: inside a HELIOS checkout the
    # repo-level .mcp.json already launches src/mcp/HELIOS.Mcp, and a bundled duplicate
    # would start a second server instance with duplicate helios_* tools and racing
    # Release builds of the same output.
    require(
        not (PLUGIN_ROOT / ".mcp.json").exists(),
        "plugin must not bundle a second MCP server; the repo-level .mcp.json provides it",
        errors,
    )
    server = mcp.get("mcpServers", {}).get("helios", {})
    args = server.get("args", [])
    require(server.get("command") == "dotnet", "repo-level MCP command must be dotnet", errors)
    require(
        "src/mcp/HELIOS.Mcp" in args,
        "repo-level MCP must launch src/mcp/HELIOS.Mcp",
        errors,
    )
    require(
        server.get("env", {}).get("HELIOS_REPO_ROOT") == ".",
        "repo-level MCP must pass the HELIOS repo root",
        errors,
    )

    known = settings.get("extraKnownMarketplaces", {}).get("helios-platform", {})
    require(
        known.get("source", {}).get("repo") == "Yolkster64/helios-platform",
        "Claude project settings must point to the canonical GitHub repository",
        errors,
    )
    require(
        settings.get("enabledPlugins", {}).get("helios-operator@helios-platform") is True,
        "Claude project settings must enable the operator plugin",
        errors,
    )

    source_path = REPO_ROOT / "src" / "mcp" / "HELIOS.Mcp" / "HeliosOperatorTools.cs"
    source = source_path.read_text(encoding="utf-8")
    actual_tools = set(re.findall(r'McpServerTool\(Name = "([^"]+)"', source))
    require(EXPECTED_TOOLS <= actual_tools, f"operator MCP tools missing: {sorted(EXPECTED_TOOLS - actual_tools)}", errors)

    skill = (PLUGIN_ROOT / "skills" / "operate-helios" / "SKILL.md").read_text(encoding="utf-8")
    agent = (PLUGIN_ROOT / "agents" / "fabric-operator.md").read_text(encoding="utf-8")
    require(skill.startswith("---\n") and "name: operate-helios" in skill, "operate-helios skill frontmatter is missing", errors)
    require(agent.startswith("---\n") and "name: fabric-operator" in agent, "fabric-operator frontmatter is missing", errors)
    for tool in EXPECTED_TOOLS:
        require(tool in skill, f"operate-helios does not reference {tool}", errors)

    if errors:
        print("HELIOS Claude plugin contract validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("HELIOS Claude plugin contract validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
