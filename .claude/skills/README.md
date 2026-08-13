# HELIOS skills index

One row per skill directory under `.claude/skills/`. Two conventions apply to every
skill and are stated once, here:

1. **SKILL.md stays under 150 lines; depth goes in `references/*.md`.**
2. **No citation, no claim.** Every library/version/API claim names the repo file that
   proves it; claims that cannot be verified against the repo or official docs at
   authoring time are omitted. Each reference file opens with the maintenance rule:
   *"Versions and API claims mirror the cited repo files; update this file in the same
   PR that changes them."*

## Stack → skill → references → ground truth

| Stack | Skill | Reference files | Ground truth in this repo |
|---|---|---|---|
| C# / .NET 8 (hub, CLI, API, MCP) | `csharp-orchestrator` | `nuget-packages.md`, `provider-sdks.md`, `azure-management-sdk.md`, `testing.md` | `src/ai/HELIOS.AIHub/Providers/`, the `src/ai`/`src/mcp` csproj files, `tests/HELIOS.AIHub.Tests/` |
| PowerShell 7 automation | `powershell-automation` | `modules.md`, `script-patterns.md` | `.github/workflows/{code-checks,ci-validation,quality}.yml`, `.github/ps1-parse-baseline.txt`, `scripts/bootstrap/`, `scripts/fleet/stop-fleet.ps1` |
| GitHub Actions / JSON / MSBuild config | `pipelines-config` | `actions-tooling.md`, `msbuild-and-config.md` | `.github/workflows/`, `config/aihub.json`, the csproj files |
| Bicep / ARM / Terraform | `iac-azure` | `bicep-tooling.md`, `terraform-azurerm.md` | `infra/main.bicep`, `infra/terraform/`, `.github/workflows/helios-deploy.yml` |
| C++ native spoke | `cpp-performance` | `build-and-packaging.md`, `rendering-gpu.md` | `src/ai/HELIOS.AIHub.Native/CMakeLists.txt`, `scripts/build/build-native.sh`, `src/ai/HELIOS.AIHub/Native/NativeMethods.cs` |
| Python agents spoke | `python-agents` | `ml-and-rl.md` | `src/ai/python/` |
| F# domain modeling | `fsharp-functional` | `analytics-patterns.md` | `src/ai/HELIOS.AIHub.Domain/` |
| Cross-format wiring (workflows ↔ IaC ↔ config) | `automation-wiring` | `github-actions.md`, `bicep-arm.md`, `terraform.md`, `config-schemas.md`, `rest-curl.md` | `.github/workflows/`, `infra/`, `config/` |
| Hub extension recipes (provider / CLI / MCP tool) | `api-creator` | already deep — none | `src/ai/HELIOS.AIHub*`, `src/mcp/HELIOS.Mcp/`, `config/aihub.json` |
| WinUI 3 desktop shell | `winui3-shell` | `xaml-authoring.md`, `rendering-interop.md`, `interaction-and-motion.md`, `design-mining.md` | `src/gui/`, `docs/architecture/{GUI_THEME_ANALYSIS,GUI_UPGRADE_PLAN,INTERACTIVE_SHELL_EXPERIENCE}.md` |
| Microsoft ecosystem (Entra / M365 Copilot / Purview / Fabric) | `microsoft-ecosystem` | `graph-and-copilot.md`, `m365-copilot-tools.md`, `tenant-administration.md`, `fabric-and-powerbi.md` | `integrations/m365/`, `scripts/bootstrap/setup-tenant.ps1`, `docs/architecture/{IDENTITY_ARCHITECTURE,HYBRID_CLOUD_ARCHITECTURE,GOVERNANCE_PURVIEW_FABRIC,ENTERPRISE_AI_CONNECTIONS}.md` |
| GitHub Copilot (coding agent / review / CLI) | `github-copilot` | `copilot-surfaces.md` | `.github/workflows/copilot-dispatch.yml`, `.github/copilot-instructions.md`, `docs/architecture/FORWARD_PLAN.md` (operating model; merged agent PRs #95–#97) |
| ChatGPT / OpenAI Codex (cloud reviewer / CLI / API lane) | `openai-codex` | `codex-surfaces.md` | `config/aihub.json` (codex + openai-codex), `scripts/bootstrap/connect-all.ps1`, `docs/architecture/{CONNECTIONS_SETUP,REVIEW_LOOP}.md` |
| GitHub auth & control plane (tokens / OIDC / rulesets / Projects v2 / wiki / Pages) | `github-control` | `auth-topology.md`, `control-plane.md` | `.github/workflows/{claude-foundry,copilot-dispatch,wiki-generator,helios-deploy}.yml`, `scripts/board-setup/`, `scripts/bootstrap/azure-oidc-setup.sh`, `docs/architecture/{CONNECTIONS_SETUP,GITHUB_ECOSYSTEM_DESIGN,REVIEW_LOOP}.md` |

"Already deep": `automation-wiring` and `api-creator` carried real library
knowledge before the reference packs were added, so they get no new reference
files; `python-agents`, `fsharp-functional`, and `winui3-shell` were already strong
and received one deepening pack each (ML/RL, analytics, XAML+rendering). `automation-wiring`'s five
pre-existing references set the precedent for this layout.

## Ecosystem repos

Satellite repos (all under `Yolkster64/`) and what consumes each; topology background
in `docs/architecture/GITHUB_ECOSYSTEM_DESIGN.md`:

| Repo | Role | Consumer |
|---|---|---|
| `WindowsDeveloperConfig` | Dev-box provisioning; PS7 workloads (winget DSC) | `powershell-automation`; roadmap PR5 `cross-llm-shell` workload (`docs/architecture/ROADMAP_MULTI_LLM.md`) |
| `ai-hub-knowledge` | Bicep knowledge store; goal-registry pattern slated for AIHub absorption | `iac-azure`; the AIHub roadmap |
| `linear` | TypeScript fork of Linear | Connector reference for the Linear sync (`.github/workflows/linear-sync.yml`, `docs/architecture/CONNECTIONS_SETUP.md`) |
| `azure-sdk-for-net` | Fork of the Azure SDK for .NET | Source-level verification of SDK API claims (`csharp-orchestrator` → `provider-sdks.md`; Foundry provider work) |
| `rl` | RL toolkit fork (NeMo-RL lineage) | Advisory-only learning/routing experiments over hub outcome data — never auto-executes training |
