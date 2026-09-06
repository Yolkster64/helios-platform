# HELIOS Control Agent Contract

The current repository is `Yolkster64/helios-platform`; the reviewed target is an in-place rename to `Yolkster64/helios-control`. `Yolkster64/helios-gui` is the separate native desktop target. Agents must not create a competing canonical copy.

## Required local gates

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests
bicep build infra/main.bicep --stdout
python3 scripts/validation/validate_yolkster_cutover.py
```

The portable solution covers AIHub, CLI, MCP, and tests. Windows-only GUI code builds through `src/gui/HELIOS.Shell.sln` on a Windows runner.

## Non-negotiable boundaries

- Active desktop work is **WinUI 3 only**: C#/.NET 10, Windows App SDK, `Microsoft.UI.Xaml`, and `Microsoft.UI.Composition`.
- Do not add WPF, UWP, `System.Windows`, `PresentationFramework`, `PresentationCore`, `Windows.UI.Xaml`, or a PowerShell GUI host.
- The root `HELIOS.Platform.csproj` is a known legacy WPF baseline tracked by HC-002. Do not expand it, use it as a fallback, or re-add it to the portable solution.
- New C# goes under `src` and must be included in the correct solution. Until HC-002 removes the legacy root glob, maintain its explicit compile exclusions.
- Never commit secret values. Use environment-variable names, workload identity, managed identity, or Azure Key Vault references.
- Never weaken a required check, mark skipped work as passed, fabricate a receipt, or claim a connector write without its returned identifier.
- Production is disabled. GitHub protected environments are the only deployment authority.

## Repository and fork policy

- Start from the latest `Yolkster64/helios-platform/main`; it is newer than the M0nado parent.
- Prefer an administrator rename to `Yolkster64/helios-control` after CI. Do not copy the old M0nado tree over the Yolkster line.
- Extract `src/gui` into `Yolkster64/helios-gui` through a reviewed, provenance-preserving change.
- Import only original HELIOS deltas from Hermes, WindowsDeveloperConfig, or other forks.
- Consume Azure SDKs as versioned packages with thin HELIOS adapters; do not vendor upstream SDK repositories.
- Never delete or archive a source repository until target SHA, CI, issue mapping, releases, licenses, and checksums are proven.

## Agent authority

Agents may inspect, edit allowlisted repository paths, build, test, validate Bicep, produce plans, prepare a development `what-if`, and open draft issues or pull requests when authorized.

Agents may not merge, force-push, rename/transfer/archive repositories, change rulesets or protected environments, deploy Azure, mutate Entra/RBAC/Graph, read back secrets, approve production, or perform disk/driver/Defender/BitLocker/TPM/firmware operations.

Hermes and XCore are planning, routing, simulation, evaluation, and redacted-memory systems. They are not human approvers or cloud principals. Slack, Linear, SharePoint, Teams, and Azure DevOps are coordination/evidence surfaces, not alternate deployment authorities.

## Multi-LLM and MCP

The provider-neutral AIHub routes OpenAI, Azure/Foundry, Claude, Copilot, local models, Hermes, and XCore through typed task/result, capability, approval, redaction, tracing, and evidence contracts. Provider-specific business logic must not leak into the WinUI application.

The local MCP server in `.mcp.json` exposes bounded `helios_*` tools, including the read-only `helios_fabric_plan_get` that reports the sanitized HELIOS Fabric authority map, integration readiness, and gated phases from `config/fabric/helios-fabric.v1.json` (environment-variable names and presence only — values are never returned). Consequential operations are separate request/approval flows. Project MCP configuration from an untrusted branch must never be loaded in a credential-bearing workflow.

## Authoritative references

- `CLAUDE.md`
- `docs/architecture/ADR-0010-WINUI3-ONLY.md`
- `docs/architecture/CLAUDE-CODE-CANONICALIZATION.md`
- `docs/migration/yolkster-control-cutover/CURRENT-AUTHORITY.md`
- `docs/migration/yolkster-control-cutover/CUTOVER-RUNBOOK.md`
- `docs/migration/yolkster-control-cutover/CANONICAL-ISSUE-LEDGER.md`
- `docs/repository/FORK-INVENTORY-2026-09-05.md`
