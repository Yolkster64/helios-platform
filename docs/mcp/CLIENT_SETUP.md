# HELIOS MCP Server — Client Setup

One tool surface for every agent. The HELIOS MCP server (stdio) exposes the multi-LLM hub
(`helios_ai_ask`, `helios_ai_route`, `helios_ai_tandem`, `helios_ai_compare`,
`helios_ai_status`, `helios_providers_list`, `helios_optimal_provider_get`,
`helios_task_routing_get`, `helios_engine_catalog_get`, `helios_engine_mix_recommend`,
`helios_infra_validate`, `helios_foundry_agent_list`, `helios_foundry_agent_create`) to any MCP
client, so Claude Code, GitHub Copilot, Codex CLI, and Cursor all drive the same providers
with the same routing table. This is the cross-LLM fabric: each assistant can delegate to
whichever model is best for the task.

Prereqs: .NET 8 SDK; provider keys in the environment (see `.env.template`). Build once
with `dotnet build HELIOS.sln -c Release`.

## Claude Code

Already wired: `.mcp.json` at the repo root is picked up automatically when you open this
repo. Verify with `/mcp`.

## VS Code / GitHub Copilot

`.vscode/mcp.json`:

```json
{
  "servers": {
    "helios": {
      "type": "stdio",
      "command": "dotnet",
      "args": ["run", "--project", "src/mcp/HELIOS.Mcp", "-c", "Release"]
    }
  }
}
```

Then enable the tools in Copilot Chat's agent mode (Tools picker → MCP: helios).

## Codex CLI

`~/.codex/config.toml`:

```toml
[mcp_servers.helios]
command = "dotnet"
args = ["run", "--project", "/path/to/helios-platform/src/mcp/HELIOS.Mcp", "-c", "Release"]
```

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

All tools are non-destructive. `helios_ai_*` call LLM providers (network, token cost);
`helios_ai_status` / `helios_providers_list` / `helios_optimal_provider_get` /
`helios_task_routing_get` are pure reads;
`helios_engine_catalog_get` / `helios_engine_mix_recommend` are deterministic local reads
that separate implemented/runtime-available selections from candidates and never install
or execute candidates;
`helios_infra_validate` compiles `infra/main.bicep` locally with no subscription access;
`helios_foundry_agent_list` is a read against the Azure AI Foundry project
(DefaultAzureCredential) that reports `configured: false` with a fix hint when
`AZURE_FOUNDRY_PROJECT_ENDPOINT` is unset instead of failing.
The one explicit mutation is `helios_foundry_agent_create`: it creates a single
persistent agent on the Foundry project — parameters are validated before any network
call, exactly one create is issued per call (never retried), and nothing is deleted,
overwritten, or executed.
Deployment tools are deliberately absent from v1 — see `docs/architecture/ROADMAP_MULTI_LLM.md`.
