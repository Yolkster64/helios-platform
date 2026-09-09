# HELIOS Connect

An optional Codex plugin for the existing HELIOS stdio MCP server. It packages
connection wiring only. Claude Code keeps using `plugins/helios-operator` and
the repository's `.mcp.json`; both clients reach the same C# implementation.

Prerequisites: `python3` on PATH, .NET 10, and a trusted HELIOS checkout with
`scripts/bootstrap/connect.py`. Set `HELIOS_REPO_ROOT` to that checkout's absolute
path in the environment of the Codex host. The plugin cache is not the checkout.
On Windows, verify `python3 --version`; if only `python` or `py` is installed,
use the repository's `connect.ps1 codex` path instead.

The launcher accepts no arguments and delegates to `connect.py mcp`. Build
diagnostics go to stderr through that existing launcher, preserving MCP stdout.
This package contains no copied MCP core, login tokens, browser cookies, provider
keys, hooks, or automatic permission grants.

Use one HELIOS registration per client. The regular repository setup already
registers `helios`; it does not need this optional plugin. Before enabling the
plugin in that same Codex host, disable its existing non-plugin HELIOS server
registration to avoid duplicate tools and simultaneous builds.

See [installation and client mapping](../../docs/mcp/PLUGIN_SETUP.md) in the
source repository. The package is available from the repo's `HELIOS Workspace`
catalog; installation remains an action in the consuming client.
