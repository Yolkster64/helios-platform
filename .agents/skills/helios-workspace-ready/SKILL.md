---
name: helios-workspace-ready
description: Verify and prepare the existing HELIOS Codespace, shared MCP server, Claude operator plugin, and collaboration connections without duplicating infrastructure or claiming untested readiness.
---

# HELIOS workspace readiness

Use for requests to connect or prepare HELIOS with Codex, Claude Code, GitHub Copilot, Slack, Linear, SharePoint, Microsoft 365, Azure, Foundry, Hermes, or XCore.

## Establish the real checkout

Read `AGENTS.md`, `global.json`, `.mcp.json`, `scripts/bootstrap/README.md`, and `docs/CANONICAL_DECISIONS.md`. Inspect `git status`, the current SHA, and the sanitized origin owner/repository. Never print a credential-bearing remote URL. `Yolkster64/helios-platform` is the verified active developer workbench; older M0nado cloud contracts are not automatically authorized for this repository. Preserve that distinction.

Look for an existing issue and PR before opening anything. Setup repairs belong to PR #135; authentication/REST work belongs to PR #113 unless live repository evidence supersedes them. Do not create duplicate issues or PRs, merge, force-push, change protected environments, or promote to another repository as part of readiness.

## Reuse the existing implementation

Do not generate another all-in-one installer, broker, or MCP server. Use:

- `.devcontainer/devcontainer.json` and `.devcontainer/post-create.sh` for the cloud workspace;
- `scripts/setup/setup-all.ps1` for inventory; `-Fix` installs missing AI CLIs and requires an explicit request to install;
- `scripts/bootstrap/setup-everything.ps1 -RequireReady -Json` for strict readiness after this PR's changes are available;
- `src/mcp/HELIOS.Mcp` as the single HELIOS MCP implementation;
- `plugins/helios-operator` for Claude's existing skill and specialist agent;
- `config/aihub.json` and the existing fleet topology for provider/routing configuration.

Do not run `auth-doctor.ps1 -Apply`, `auto-login.ps1`, `azure-up.*`, Key Vault loaders, training loops, or paid provider operations merely to check readiness.

## Keyless validation

A trusted checkout may run these with provider credentials absent:

```text
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release --no-build
python3 -m pytest src/ai/python/tests -q
python3 plugins/helios-operator/tests/validate_contract.py
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release --no-build -- status
```

Build and test project code only on a trusted checkout or credential-free disposable runner. The .NET SDK must satisfy `global.json` (currently .NET 10). The Windows-only WinUI solution is separate and cannot be validated by a Linux build.

Provider `Unconfigured` means exactly that. A passing build, successful report exit, configured MCP entry, installed CLI, or populated credential variable is not proof of a working external connection.

## Client activation

Codex can use ChatGPT device-code login; an API key is not required for this keyless developer lane. Invoke interactive login only following an explicit user request and let the user complete browser/MFA authorization. Never print or move auth-cache contents.

Register one HELIOS MCP server in each client with an absolute project path and `HELIOS_REPO_ROOT` pointing to this checkout. Reuse an existing equivalent registration. Never overwrite an existing different registration silently. Build first and use `--no-build` for server startup to avoid concurrent builds.

Claude's `helios-operator` plugin deliberately contains no second MCP server. Load it from this checkout and verify the `helios_operator_*` tools through `/mcp`. Merely listing a plugin or server is configuration evidence, not a successful tool call.

Use narrow read-only HELIOS tools first: `helios_ai_status`, `helios_task_routing_get`, and `helios_operator_next_steps_get`. Do not invoke Foundry agent creation, model requests, or training during a keyless smoke test.

## Collaboration and cloud

Verify GitHub, Slack, Linear, SharePoint, Teams, and each client session independently. ChatGPT connector OAuth does not transfer to Codex, Claude, GitHub Actions, or the HELIOS worker.

Known scoped destinations: Slack `#helios-control-plane`; Linear `Helios Integration Fabric` with existing JOH-35/JOH-36; owner-scoped SharePoint `Helios/Governance`. Resolve current IDs through the relevant connector. Do not invent a SharePoint team site, publish externally, post repeated progress messages, or overwrite governance authority without review.

Record each connection as configured, authenticated, read-verified, write-verified, or blocked. A live test write needs destination-specific authorization and one receipt. Do not turn successful manual connector access into a claim that background workers/webhooks are enabled.

Azure tenant/subscription selection, OIDC, RBAC, Key Vault, Copilot/Graph consent, image publication, what-if, and deployment remain separate, specifically authorized operations. Derive OIDC for the actual repository and protected environment; never copy an M0nado subject into a Yolkster64 workflow. Production remains blocked by the applicable verified gates.

## Evidence and handoff

Return the inspected repository/SHA, changed paths, tests actually executed, current checks for the exact PR head, remaining owner actions, and links to confirmed external receipts. Mark unavailable .NET, PowerShell, Docker, Azure, Windows, or browser checks as not run.

Share only sanitized task packets and evidence between Codex and Claude. Use distinct branches/worktrees for concurrent coding. The durable `.helios/operator/` context is per checkout, not automatically synchronized across machines. Never share credentials, raw private memory, or hidden conversations.
