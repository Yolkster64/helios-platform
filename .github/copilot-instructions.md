# HELIOS Control — Copilot instructions

Read by GitHub Copilot (code review on every non-draft PR, the coding agent, and the
CLI / IDE surfaces). It mirrors `CLAUDE.md` section for section — the shared
sections below are compared by `scripts/verify/instructions-drift.ps1` in CI, so a
rule or inventory change lands in both files in the same commit. `AGENTS.md` (Codex)
states the same boundaries in its own structure and is the owner's cutover contract.

Enterprise Windows management and multi-agent control platform. The current repository is `Yolkster64/helios-platform`; after the reviewed in-place cutover it becomes `Yolkster64/helios-control`. Do not create a competing canonical copy.

The stack is C#/.NET 10 + PowerShell 7, with a multi-LLM hub under `src/ai`, an MCP server under `src/mcp`, Azure/Foundry infrastructure under `infra`, and the active native desktop shell under `src/gui`.

## Build and test

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests
bicep build infra/main.bicep --stdout
python3 scripts/validation/validate_yolkster_cutover.py
```

`HELIOS.sln` intentionally excludes the non-compiling legacy root/core project. The source-linked seams `Core/AI/Interfaces/IAgent.cs` and `Core/AI/Router/IRouter.cs` must remain dependency-free.

## Binding architecture rules

- **WinUI 3 is the only active desktop framework.** New desktop code uses C#/.NET 10, Windows App SDK, `Microsoft.UI.Xaml`, and `Microsoft.UI.Composition` under `src/gui`.
- No new WPF, UWP, `System.Windows`, `PresentationFramework`, `PresentationCore`, `Windows.UI.Xaml`, or PowerShell GUI host is permitted. The root `HELIOS.Platform.csproj` is a temporary, explicit legacy WPF baseline tracked by HC-002; it is not a fallback or migration layer.
- Windows-only GUI projects build through `src/gui/HELIOS.Shell.sln` on Windows runners and remain excluded from the portable Linux solution.
- The legacy root project recursively globs C# files. Until HC-002 removes it, every new C# directory outside `src/ai`, `src/mcp`, and the existing exclusions must update its `<Compile Remove>` guards in the same commit.
- No secrets in Git. Provider configuration stores environment-variable or Key Vault references only. Bicep uses secure parameters and must not output secret values.
- Root-level `*_COMPLETE`, `*_REPORT`, and `*_SUMMARY` documents are historical. Trust `docs/CONSOLIDATION_BLUEPRINT.md`, `docs/architecture`, and `docs/migration/yolkster-control-cutover`.
- GitHub protected environments remain deployment authority. Slack, Linear, SharePoint, Azure DevOps, Claude, Codex, Copilot, Hermes, and XCore cannot approve production.

## Repository cutover

- Current live authority: `Yolkster64/helios-platform`.
- Target after administrator rename: `Yolkster64/helios-control`.
- Target GUI repository: `Yolkster64/helios-gui`.
- Profile repository: `Yolkster64/Yolkster64`.
- Historical parent: `M0nado/helios-platform`.

Run `/review-yolkster-cutover` or the `canonical-migration` agent before any repository move. The migration is plan/read-first. Claude may prepare code, tests, evidence, draft issues, and draft PRs; it may not rename, transfer, archive, merge, force-push, deploy, alter RBAC/Entra, read secrets, or perform workstation administration.

## Claude Code and Microsoft Foundry

- `scripts/ai-integration/Connect-ClaudeFoundry.ps1` verifies Azure CLI context, resolves the Foundry resource, sets process-local variables, and can launch Claude.
- `.github/workflows/claude-foundry.yml` is owner-dispatched from trusted `main`; Azure-authenticated work has read-only GitHub authority and emits a patch. Validation/publishing has no Azure OIDC token and may create only a validated draft PR.
- Claude uses a dedicated least-privilege OIDC identity and `Cognitive Services User` scope on the selected Foundry account. It does not share the deployment identity and no client secret is created.
- Canonical identifiers are `CLAUDE_AZURE_CLIENT_ID`, `CLAUDE_AZURE_TENANT_ID`, `CLAUDE_AZURE_SUBSCRIPTION_ID`, and `ANTHROPIC_FOUNDRY_RESOURCE`.
- Project denials live in `.claude/settings.json`. Bypass-permission mode is forbidden in CI.
- Migration-specific limits are documented in `docs/architecture/CLAUDE-CODE-CANONICALIZATION.md`.

## Multi-LLM hub

`helios-ai` supports `ask`, `route`, `tandem`, `compare`, `status`, provider inspection, routing, engines, engine plans, and fleet plans. Provider and routing configuration lives in `config/aihub.json`; recommendations are advisory and never auto-execute.

`helios-ai-api` provides `/healthz`, status, routing, learning, insights, metrics, engines, provider operations, and bounded learning endpoints. `/v1/*` is loopback-only unless the caller supplies `HELIOS_API_ACCESS_KEY` as `X-HELIOS-Api-Key`; hosted use still requires identity-aware ingress.

The Python spoke provides analytics and engine recommendations behind a bounded process cap. Prototype engines never auto-execute. Hermes/XCore may route, simulate, score, reflect, and update redacted memory, but cannot grant itself cloud or production authority.

The MCP server in `.mcp.json` exposes the governed `helios_*` tools for AI routing, status, providers, engines, infrastructure validation, absorption/fleet/auth status, Azure inventory, Foundry agents, and sanitized operator context. The Claude plugin under `plugins/helios-operator` uses the same MCP server and stores durable sanitized handoff state under the gitignored `.helios/operator` directory.

## Key architecture references

- `docs/architecture/MULTI_LLM_INTEGRATION.md`
- `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md`
- `docs/architecture/HERMES_FLEET_AND_XCORE.md`
- `docs/architecture/GUI_THEME_ANALYSIS.md`
- `docs/architecture/GUI_UPGRADE_PLAN.md`
- `docs/architecture/CLAUDE_CODE_GITHUB_FOUNDRY.md`
- `docs/architecture/CLAUDE-CODE-CANONICALIZATION.md`
- `docs/architecture/ADR-0010-WINUI3-ONLY.md`
- `docs/migration/yolkster-control-cutover/CURRENT-AUTHORITY.md`
- `docs/migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md`
