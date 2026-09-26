# HELIOS Control

Enterprise Windows management and multi-agent control platform. The current repository is `Yolkster64/helios-platform`; after the reviewed in-place cutover it becomes `Yolkster64/helios-control`. Do not create a competing canonical copy.

The product interface is the Electron + Electron Forge workbench under `apps/desktop`, with Electron Fiddle experiments under `experiments/electron-fiddle`. C#/.NET 10 + PowerShell 7 remain service/automation boundaries, with F# policy, Python analytics, C++ native specialists, a multi-LLM hub under `src/ai`, an MCP server under `src/mcp`, and Azure/Foundry infrastructure under `infra`. `src/gui` preserves the previous Windows UI implementation and its provenance; it is not an in-app fallback.

## Build and test

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
(cd src/ai/python && python3 -m pytest tests)
bicep build infra/main.bicep --stdout
python3 scripts/validation/validate_yolkster_cutover.py
npm --prefix apps/desktop ci
npm --prefix apps/desktop test
npm --prefix apps/desktop run package
```

`HELIOS.sln` intentionally excludes the non-compiling legacy root/core project. The source-linked seams `Core/AI/Interfaces/IAgent.cs` and `Core/AI/Router/IRouter.cs` must remain dependency-free.

The existing cutover validator continues to guard repository authority, disabled production, and the preserved WinUI tree through `config/ui/winui3-only.v1.json`; it is not an Electron validator. Desktop tests and Forge packaging are separate gates. Run platform makers on their matching operating systems; packaging alone does not prove a signed installer or launch test.

Self-hosted jobs use the single `runs-on: helios-runners` label (the ARC scale-set name; `scripts/runners/register-runner.*` applies it to hand-registered runners).

## Binding architecture rules

- **Electron is the active HELIOS product UI.** The owner's September 2026 overhaul supersedes the WinUI-only decision through `docs/architecture/ADR-0011-ELECTRON-WORKBENCH.md`. Launcher, settings, profiles, AIHub, USB planning, workbench, and future desktop-shell surfaces belong under `apps/desktop`; Forge packages the app and Fiddle hosts focused experiments.
- Keep Node integration disabled in renderers, context isolation and sandboxing enabled, and the preload API narrow and validated. Main-process adapters own credentials, network access, allowlisted resource launches, and bounded service calls. Do not expose raw IPC, arbitrary commands, filesystem access, or credentials to renderer code.
- Extend Electron through reviewed HELIOS capabilities and isolated native/service adapters where useful. Forge plugins are build tools; browser extensions have a different and incomplete API surface. The built-in capability catalog is not a third-party executable loader. No in-app WinUI fallback is part of the new product.
- No new WPF, UWP, `System.Windows`, `PresentationFramework`, `PresentationCore`, `Windows.UI.Xaml`, or PowerShell GUI host is permitted. The root `HELIOS.Platform.csproj` is a temporary, explicit legacy WPF baseline tracked by HC-002; it is not a fallback or migration layer.
- Preserve `src/gui` and its Windows build through `src/gui/HELIOS.Shell.sln` as migration evidence until parity and archival proof are reviewed. Its WinUI contract remains scoped to that tree. Do not delete it or silently reinterpret its legacy validator as proof of Electron readiness.
- C#, F#, Python, C++, PowerShell, MCP, and REST remain specialist boundaries. Windows sign-in, secure desktop, UAC, boot, firmware, and privileged disk/device operations remain native OS responsibilities; Electron presents status and requests. Explorer replacement is a future opt-in deployment with recovery and watchdog gates, not a startup side effect.
- The legacy root project recursively globs C# files. Until HC-002 removes it, every new C# directory outside `src/ai`, `src/mcp`, and the existing exclusions must update its `<Compile Remove>` guards in the same commit.
- No secrets in Git. Provider configuration stores environment-variable or Key Vault references only. Bicep uses secure parameters and must not output secret values.
- Root-level `*_COMPLETE`, `*_REPORT`, and `*_SUMMARY` documents are historical, and any `docs/` file still carrying `{{PLACEHOLDER}}` text is an unfilled generated template rather than documentation — 39 of them measured 2026-09-10, including `docs/API.md`, `docs/ARCHITECTURE.md`, `docs/QUICK_START.md` and all of `docs/security/`; `docs/TEMPLATES_SUMMARY.md` reports itself `✅ COMPLETE` under a `{{GENERATION_DATE}}` header. Trust `docs/CONSOLIDATION_BLUEPRINT.md`, `docs/architecture`, and `docs/migration/yolkster-control-cutover`.
- GitHub protected environments remain deployment authority. Slack, Linear, SharePoint, Azure DevOps, Claude, Codex, Copilot, Hermes, and XCore cannot approve production.

## Repository cutover

- Current live authority: `Yolkster64/helios-platform`.
- Target after administrator rename: `Yolkster64/helios-control`.
- Previously planned GUI extraction: `Yolkster64/helios-gui`; reassess after Electron parity. Keep the active `apps/desktop` in this monorepo during the overhaul.
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

`helios-ai route`, `POST /v1/route`, and `helios_ai_route` accept an optional language (`csharp`, `fsharp`, `cpp`, `python`, `powershell`, `bicep`, `yaml`, `json`); a `taskRouting` key of the form `<taskType>:<language>` in `config/aihub.json` is tried before the bare task type, then `routing.defaultChain`, and the normalized language is recorded with each outcome so learning keys on (taskType, language). Adaptive routing is off by default in both the shipped config and the C# default; recording still happens when it is off.

Model, provider and combination choices are reasoned in the `aihub-unity` skill and reported by the read-only `aihub-strategist` agent, grounded in `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md` and `docs/architecture/AIHUB_LANGUAGE_ROLES.md`; the absorption program's beginner path is `docs/absorption/START_HERE.md`.

## Key architecture references

- `docs/architecture/MULTI_LLM_INTEGRATION.md`
- `docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`
- `docs/architecture/AIHUB_LANGUAGE_ROLES.md`
- `docs/architecture/LLM_STRENGTHS_PLAYBOOK.md`
- `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md`
- `docs/architecture/HERMES_FLEET_AND_XCORE.md`
- `docs/architecture/GUI_THEME_ANALYSIS.md`
- `docs/architecture/GUI_UPGRADE_PLAN.md`
- `docs/architecture/CLAUDE_CODE_GITHUB_FOUNDRY.md`
- `docs/architecture/CLAUDE-CODE-CANONICALIZATION.md`
- `docs/architecture/ADR-0011-ELECTRON-WORKBENCH.md`
- `docs/migration/electron-overhaul/README.md`
- `docs/architecture/ADR-0010-WINUI3-ONLY.md` (superseded desktop direction; retained legacy-tree boundary)
- `docs/migration/yolkster-control-cutover/CURRENT-AUTHORITY.md`
- `docs/migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md`
