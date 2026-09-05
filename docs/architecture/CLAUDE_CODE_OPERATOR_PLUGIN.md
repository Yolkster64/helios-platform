# Claude Code Operator Plugin

## Outcome

`plugins/helios-operator` turns the existing HELIOS MCP server into a distributable Claude
Code plugin with an operating skill and specialist agent. It does not create a second AI
control plane. Claude Code, Codex, Copilot, ChatGPT, Hermes, and XCore use the same C# MCP
tools, `config/aihub.json` routing table, Git checkout, and optional Azure inventory.

The durable handoff is intentionally inspectable and local to a checkout:

```text
.helios/operator/profile.json   explicit non-sensitive preferences
.helios/operator/context.json   latest sanitized repo/Azure snapshot
.helios/operator/journal.jsonl  append-only sync and profile receipts
```

`.helios/` is gitignored. This state survives assistant sessions on the same checkout; it
is not silently uploaded, shared across machines, or used as a credential store.

## Wiring map

| Producer | Contract | Consumer | Guardrail |
|---|---|---|---|
| User-confirmed preferences | `profile.json` schema v1 | Every MCP-capable assistant | Credential-looking names and values are rejected |
| Git CLI | repo, branch, head, dirty flag | `context.json`, next-step engine | Remote URL is reduced to `owner/repo`; no credential-bearing URL is stored |
| Azure CLI | account, group, resource projections | `context.json`, delta engine | Only `account show`, `group list`, and optional `resource list`; tags are bounded and redacted |
| `config/aihub.json` | providers and task routing | HELIOS AI tools | Config stores environment-variable names, never key values |
| Prior and current snapshots | added, removed, changed identities | deterministic next steps | Truncated or incomplete inventories are marked non-comparable |
| Context/profile writes | SHA-256 receipt | `journal.jsonl` | Cross-process lock and atomic latest-snapshot replacement |
| Claude marketplace | `helios-operator` package path | Claude Code plugin cache | Plugin ships skill + agent only; the MCP server comes from the checkout's own `.mcp.json`, so no duplicate server is launched and no files are fetched by hooks |

## Components

- `.claude-plugin/marketplace.json` catalogs the plugin from this Git repository. The
  plugin manifest carries a semver release; bump it whenever the packaged components
  change so installed copies update predictably.
- The plugin bundles no MCP server of its own. Inside a HELIOS checkout the repo-level
  `.mcp.json` already starts `src/mcp/HELIOS.Mcp` (passing `HELIOS_REPO_ROOT`); a bundled
  duplicate would launch a second server instance with duplicate `helios_*` tools and two
  concurrent Release builds of the same output. `validate_contract.py` enforces this.
- `/helios-operator:operate-helios` establishes context, routes work deliberately, and
  preserves approval boundaries.
- `@helios-operator:fabric-operator` coordinates work that crosses code, CI, MCP, Azure,
  GitHub, or provider boundaries.
- `HeliosOperatorTools.cs` adds profile read/write, context sync, and deterministic
  next-step tools to the MCP assembly already used by other clients.

## Safety boundary

The operator may write its own local context files. Optional Azure sync is observation,
not deployment. There is no MCP tool for Azure apply/delete, role assignment, service
connection creation, GitHub merge, force push, or key creation. Those remain distinct
actions requiring a current, specific user instruction.

Provider tools may make network calls and incur token cost, so the skill uses one primary
operator and routes or compares only when another model adds a clear independent benefit.
Uploaded recovery scripts and partial `.crdownload` files remain untrusted reference
material and are never an execution source.

## Install and verify

Prerequisites: Claude Code and the .NET 10 SDK. Start from the HELIOS repository root.

```bash
dotnet build HELIOS.sln -c Release
python3 scripts/verify/mcp-health.py
claude --plugin-dir ./plugins/helios-operator
```

In Claude Code, run `/mcp`, invoke `/helios-operator:operate-helios`, and confirm the MCP
server exposes the `helios_operator_*` tools. For marketplace installation after merge:

```text
/plugin marketplace add Yolkster64/helios-platform
/plugin install helios-operator@helios-platform
```

Validate the package without starting a model session:

```bash
claude plugin validate ./plugins/helios-operator --strict
claude plugin validate . --strict
python3 plugins/helios-operator/tests/validate_contract.py
dotnet test tests/HELIOS.AIHub.Tests -c Release
```
