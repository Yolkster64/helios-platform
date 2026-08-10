# HELIOS MCP Server — Client Setup

One tool surface for every agent. The HELIOS MCP server (stdio) exposes the multi-LLM hub
(`helios_ai_ask`, `helios_ai_route`, `helios_ai_compare`, `helios_ai_status`,
`helios_providers_list`, `helios_task_routing_get`, `helios_infra_validate`) to any MCP
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
`helios_ai_status` / `helios_providers_list` / `helios_task_routing_get` are pure reads;
`helios_infra_validate` compiles `infra/main.bicep` locally with no subscription access.
Deployment tools are deliberately absent from v1 — see `docs/architecture/ROADMAP_MULTI_LLM.md`.
