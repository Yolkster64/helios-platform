# HELIOS MCP Server — Client Setup

One tool surface for every agent. The HELIOS MCP server (stdio) exposes the multi-LLM hub
(`helios_ai_ask`, `helios_ai_route`, `helios_ai_tandem`, `helios_ai_compare`,
`helios_ai_status`, `helios_providers_list`, `helios_optimal_provider_get`,
`helios_task_routing_get`, `helios_engine_catalog_get`, `helios_engine_mix_recommend`,
`helios_infra_validate`, `helios_azure_inventory_get`, `helios_auth_status_get`,
`helios_fleet_plan_get`, `helios_foundry_agent_list`,
`helios_foundry_agent_create`,
`helios_operator_profile_get`, `helios_operator_profile_save`,
`helios_operator_context_sync`, `helios_operator_next_steps_get`) to any MCP
client, so Claude Code, GitHub Copilot, Codex CLI, and Cursor all drive the same providers
with the same routing table. This is the cross-LLM fabric: each assistant can delegate to
whichever model is best for the task.

Prerequisites: .NET 10 SDK and Python 3.10+ for the connection check. Build explicitly
with `dotnet build HELIOS.sln -c Release`, then run:

```bash
python3 scripts/verify/mcp-health.py
```

The probe negotiates MCP, discovers the required HELIOS tools (including paginated
lists), and sends a protocol ping. It has a 30-second exchange timeout and bounded
shutdown. It never invokes a tool, acquires a credential, or calls a provider. Exit 0
means stdio discovery passed; exit 2 means attention is needed. Missing binaries,
invalid protocol output, and timeouts cannot become a ready result. Raw server logs
are discarded so credentials or exception details cannot enter the report.

The three checked-in client registrations use `--no-build --no-restore
--no-launch-profile` to keep build output and launch-profile overrides out of the MCP
transport. Rebuild after source changes. A successful probe establishes transport and
tool discovery only; assistant authentication and live provider readiness remain
separate checks. `scripts/setup/setup-all.ps1` now reports `mcp-runtime` separately
from `mcp-registration`.

## Claude Code

Already wired: `.mcp.json` at the repo root is picked up automatically when you open this
repo. Verify with `/mcp`.

For the packaged skill and specialist agent, test the checked-out plugin directly:

```bash
claude --plugin-dir ./plugins/helios-operator
```

Or install it from the repository marketplace after it reaches the default branch:

```text
/plugin marketplace add Yolkster64/helios-platform
/plugin install helios-operator@helios-platform
```

Choose project scope, then invoke `/helios-operator:operate-helios` or mention
`@helios-operator:fabric-operator`. The plugin adds the skill and agent only — the MCP
server itself still comes from the repo-level `.mcp.json`, so enabling the plugin does
not produce duplicate `helios_*` tools or a second server process.

## VS Code / GitHub Copilot

The checked-in `.vscode/mcp.json` registers HELIOS using `${workspaceFolder}` for
the project and repository root. Open the checkout as a folder, build, then use the
Copilot Chat Tools picker to enable MCP: helios. Workspace trust and the editor's
normal server approval still apply.

## Codex CLI

The checked-in `.codex/config.toml` registers the same server. Codex loads project
configuration only for a trusted checkout; it does not change user authentication,
model selection, sandbox settings, or approval policies. The working directory
resolves from `.codex/..` to the repository root, including when starting in a nested
source folder.

After building, run `codex mcp list` and inspect `/mcp` in the intended Codex session.
Remove an obsolete duplicate user-level HELIOS entry only if it conflicts with this
project registration. Do not put provider keys in MCP command arguments or tracked
configuration. A ChatGPT subscription session does not configure provider API access.

Official references: [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp),
[project configuration](https://learn.chatgpt.com/docs/config-file/config-advanced),
[MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle).

## Cursor

`.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{
  "mcpServers": {
    "helios": {
      "command": "dotnet",
      "args": ["run", "--project", "src/mcp/HELIOS.Mcp", "-c", "Release"]
    }
  }
}
```

## Inspector (debugging)

```bash
npx @modelcontextprotocol/inspector -- dotnet run --project src/mcp/HELIOS.Mcp -c Release
```

## Tool surface & safety

Tools have different effects. `helios_ai_ask`, `helios_ai_route`,
`helios_ai_tandem`, and `helios_ai_compare` call LLM providers (network, token cost);
`helios_ai_status` / `helios_providers_list` / `helios_optimal_provider_get` /
`helios_task_routing_get` are pure reads;
`helios_engine_catalog_get` / `helios_engine_mix_recommend` are deterministic local reads
that separate implemented/runtime-available selections from candidates and never install
or execute candidates;
`helios_infra_validate` compiles `infra/main.bicep` locally with no subscription access;
`helios_absorb_status_get` / `helios_fleet_status_get` are read-only local reads of the
absorption watchlist and fleet run state;
`helios_azure_inventory_get` is a strictly read-only Azure management-plane inventory
(subscription, resource groups, resources via DefaultAzureCredential) — it lists and
never creates, changes, or deletes anything, and without working credentials it returns
`authenticated: false` with a fix hint (run `az login`) instead of failing;
`helios_auth_status_get` is a diagnose-only read of the auth lanes (the
GITHUB_ACTIONS/GH_TOKEN/GITHUB_TOKEN environment, one DefaultAzureCredential
management-plane token probe, and each `config/aihub.json` provider's declared
`apiKeyEnv`) — environment variables are reported by NAME and set/unset state only,
values never enter the output, missing credentials return `authenticated: false` with a
fix hint, and it repairs nothing (repair is `scripts/bootstrap/auth-doctor.ps1`);
`helios_fleet_plan_get` is a purely local advisory read: it scores each fleet pool's
configured provider chain (`config/fleet/fleet-topology.json`) against the hub's learned
routing and only reports — learned chains are NEVER auto-applied, and a missing topology
or empty learning history returns a message / engine `none` instead of failing;
`helios_foundry_agent_list` is a read against the Azure AI Foundry project
(DefaultAzureCredential) that reports `configured: false` with a fix hint when
`AZURE_FOUNDRY_PROJECT_ENDPOINT` is unset instead of failing.
The one explicit mutation is `helios_foundry_agent_create`: it creates a single
persistent agent on the Foundry project — parameters are validated before any network
call, exactly one create is issued per call (never retried), and nothing is deleted,
overwritten, or executed.
`helios_operator_profile_save` and `helios_operator_context_sync` write only sanitized,
gitignored files under `.helios/operator/`; Azure inventory is opt-in and uses read-only
CLI commands. The other operator tools are local reads. Context is durable per checkout,
not a cross-machine secret store, and should be refreshed before external decisions.
Deployment tools are deliberately absent from v1 — see `docs/architecture/ROADMAP_MULTI_LLM.md`.
