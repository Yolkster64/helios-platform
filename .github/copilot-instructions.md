# HELIOS Platform

Enterprise Windows management platform. C#/.NET 8 + PowerShell 7, with a multi-LLM hub
(`src/ai/`), an MCP server (`src/mcp/`), and Azure AI Foundry infrastructure (`infra/`).

## Build & test (what CI runs)

```bash
dotnet build HELIOS.sln -c Release          # AIHub + CLI + MCP + tests ONLY
dotnet test tests/HELIOS.AIHub.Tests -c Release
bicep build infra/main.bicep --stdout       # or: az bicep build --file infra/main.bicep
```

**`HELIOS.sln` deliberately excludes `src/core/HELIOS.Platform`** — the core project does
not compile today (~323 errors). Do not add it back until it builds. The two seam files
`Core/AI/Interfaces/IAgent.cs` and `Core/AI/Router/IRouter.cs` are source-linked into
HELIOS.AIHub; keep them dependency-free (System.* usings only).

## Hard rules

- **Root `HELIOS.Platform.csproj` recursively globs `**/*.cs`.** Any new C# directory
  outside `src/ai`/`src/mcp` must be added to its `<Compile Remove>` list in the same
  commit, or it silently breaks the root WPF project.
- **New C# goes under `src/`** and must be added to `HELIOS.sln`. Exception:
  Windows-only UI projects (`src/gui/`) cannot compile on the Linux CI that builds
  `HELIOS.sln`, so they live in their own solution (`src/gui/HELIOS.Shell.sln`,
  built on Windows — see `src/gui/README.md`) and MUST still be covered by the
  root csproj's glob guards.
- **No secrets in the repo.** `config/aihub.json` carries env-var names only; keys come
  from the environment or Azure Key Vault (`AZURE_KEY_VAULT_URI`). Bicep takes secrets as
  `@secure()` parameters and never outputs them.
- Root-level `*_COMPLETE/*_REPORT/*_SUMMARY.md` status docs are historical and
  unreliable; trust `docs/CONSOLIDATION_BLUEPRINT.md` and `docs/architecture/`.

## Multi-LLM hub

- `helios-ai` (src/ai/HELIOS.AIHub.Cli): `ask` / `route <task-type>` / `compare` /
  `status` / `routing`. Providers and the task-routing table live in `config/aihub.json`.
- MCP server (src/mcp/HELIOS.Mcp, registered in `.mcp.json`): `helios_ai_ask`,
  `helios_ai_route`, `helios_ai_compare`, `helios_ai_status`, `helios_providers_list`,
  `helios_task_routing_get`, `helios_infra_validate`.
- Which model for which task: `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`.

## Architecture docs

`docs/architecture/MULTI_LLM_INTEGRATION.md` (this design), `GITHUB_ECOSYSTEM_DESIGN.md`
(runners/Projects/wiki/connectors), `HERMES_FLEET_AND_XCORE.md` (agent fleet),
`GUI_THEME_ANALYSIS.md` (WinUI 3 direction), `ROADMAP_MULTI_LLM.md` (follow-up PRs and
known-red workflow inventory). Coding skills live in `.claude/skills/`.
