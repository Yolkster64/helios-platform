# HELIOS Control Agent Contract

The current repository is `Yolkster64/helios-platform`; the reviewed target is an in-place rename to `Yolkster64/helios-control`. The active Electron workbench stays in `apps/desktop` in this monorepo; the previously planned `Yolkster64/helios-gui` extraction is reassessed after Electron parity. Agents must not create a competing canonical copy.

## Required local gates

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

The portable solution covers AIHub, CLI, MCP, and tests. Preserved Windows UI code builds through `src/gui/HELIOS.Shell.sln` on a Windows runner. The cutover validator and `config/ui/winui3-only.v1.json` still guard that legacy tree, repository authority, and disabled production; Electron uses separate tests and Forge packaging. Run platform makers on matching operating systems, and distinguish packaging from signed installer and runtime verification.

## Non-negotiable boundaries

- Active desktop work uses **Electron + Electron Forge** under `apps/desktop`, with focused experiments under `experiments/electron-fiddle`. The owner's overhaul supersedes the global WinUI-only direction through ADR-0011. All HELIOS product UI moves here, including launcher, settings, profiles, AIHub, workbench, and USB planning.
- Keep renderer Node integration disabled, context isolation and sandboxing enabled, and the preload API narrow. Validate IPC senders and payloads; main-process adapters own credentials, network access, and allowlisted resource launches. Never expose raw IPC, arbitrary commands, filesystem access, or credentials to renderer code.
- Preserve C#/F#/Python/C++ services and native specialists behind explicit contracts. Keep the old `src/gui` tree and its WinUI gate as provenance until reviewed parity and archival proof. There is no in-app WinUI fallback.
- Forge plugins are build tools, HELIOS plugins are capability-scoped product modules, and browser extensions use a different partial API surface. A catalog entry is not an installed or authenticated capability. No third-party executable loading is implied.
- Windows sign-in, secure desktop, UAC, firmware, and boot remain native OS boundaries. Future Explorer replacement must be opt-in, reversible, and verified with a native watchdog and recovery path; it must never happen as an Electron startup side effect.
- Do not add WPF, UWP, `System.Windows`, `PresentationFramework`, `PresentationCore`, `Windows.UI.Xaml`, or a PowerShell GUI host.
- The root `HELIOS.Platform.csproj` is a known legacy WPF baseline tracked by HC-002. Do not expand it, use it as a fallback, or re-add it to the portable solution.
- New C# goes under `src` and must be included in the correct solution. Until HC-002 removes the legacy root glob, maintain its explicit compile exclusions.
- Never commit secret values. Use environment-variable names, workload identity, managed identity, or Azure Key Vault references.
- Never weaken a required check, mark skipped work as passed, fabricate a receipt, or claim a connector write without its returned identifier.
- Production is disabled. GitHub protected environments are the only deployment authority.

## Repository and fork policy

- Start from the latest `Yolkster64/helios-platform/main`; it is newer than the M0nado parent.
- Prefer an administrator rename to `Yolkster64/helios-control` after CI. Do not copy the old M0nado tree over the Yolkster line.
- Reassess the previously proposed GUI extraction after Electron parity. Keep `apps/desktop` in this monorepo and preserve `src/gui` provenance; any later extraction requires a separate reviewed change.
- Import only original HELIOS deltas from Hermes, WindowsDeveloperConfig, or other forks.
- Consume Azure SDKs as versioned packages with thin HELIOS adapters; do not vendor upstream SDK repositories.
- Never delete or archive a source repository until target SHA, CI, issue mapping, releases, licenses, and checksums are proven.

## Agent authority

Agents may inspect, edit allowlisted repository paths, build, test, validate Bicep, produce plans, prepare a development `what-if`, and open draft issues or pull requests when authorized.

Agents may not merge, force-push, rename/transfer/archive repositories, change rulesets or protected environments, deploy Azure, mutate Entra/RBAC/Graph, read back secrets, approve production, or perform disk/driver/Defender/BitLocker/TPM/firmware operations.

Hermes and XCore are planning, routing, simulation, evaluation, and redacted-memory systems. They are not human approvers or cloud principals. Slack, Linear, SharePoint, Teams, and Azure DevOps are coordination/evidence surfaces, not alternate deployment authorities.

## Multi-LLM and MCP

The provider-neutral AIHub routes OpenAI, Azure/Foundry, Claude, Copilot, local models, Hermes, and XCore through typed task/result, capability, approval, redaction, tracing, and evidence contracts. Provider-specific business logic must not leak into the Electron renderer. ChatGPT connector access does not confer credentials or an authenticated session on the desktop app.

Routing accepts an optional language: a `<taskType>:<language>` key in `config/aihub.json` is tried before the bare task type, adaptive routing stays off by default, and every outcome is recorded either way (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`). Self-hosted jobs use the single `runs-on: helios-runners` label.

The per-language reviewers (`fsharp-reviewer`, `python-reviewer`, `powershell-reviewer`) and the report-only `aihub-strategist` never route, edit configuration, or approve; model and tool choices are reasoned in the `aihub-unity` skill, and absorption stays advisory per `docs/absorption/START_HERE.md`.

The local MCP server in `.mcp.json` exposes bounded `helios_*` tools. Consequential operations are separate request/approval flows. Project MCP configuration from an untrusted branch must never be loaded in a credential-bearing workflow.

## Authoritative references

- `CLAUDE.md`
- `docs/architecture/ADR-0011-ELECTRON-WORKBENCH.md`
- `docs/migration/electron-overhaul/README.md`
- `docs/architecture/ADR-0010-WINUI3-ONLY.md` (superseded desktop direction; retained legacy-tree boundary)
- `docs/architecture/CLAUDE-CODE-CANONICALIZATION.md`
- `docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`
- `docs/migration/yolkster-control-cutover/CURRENT-AUTHORITY.md`
- `docs/migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md`
- `docs/migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md`
- `docs/repository/FORK-INVENTORY-2026-09-05.md`
