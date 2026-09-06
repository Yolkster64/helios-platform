# HELIOS workspace and connection decisions

Evidence date: 2026-09-05 (America/Mexico_City). This is a development-readiness checkpoint, not a production authorization.

## Source of truth and existing work

The live `Yolkster64/helios-platform` README identifies this repository as the active project/developer workbench. Its inspected `main` was `c21ec24f41e61941c7f335b9835aba965c8f298b`. The owner-scoped SharePoint authority still has a July 28 cutoff and identifies `M0nado/helios-platform` as the enterprise execution repository. These are different scopes; this document does not silently transfer cloud authority, rewrite federated credentials, or promote code between them.

- [Active workbench main](https://github.com/Yolkster64/helios-platform/commit/c21ec24f41e61941c7f335b9835aba965c8f298b)
- [Existing setup PR #135](https://github.com/Yolkster64/helios-platform/pull/135): .NET 10 Codespaces, visible bootstrap failures, strict readiness reporting. Continue this PR; do not create another setup PR.
- [Existing authentication PR #113](https://github.com/Yolkster64/helios-platform/pull/113): REST verification and non-interactive credential acquisition. It is a separate unmerged lane, not a prerequisite for a keyless local build.
- [Merged Claude operator PR #10](https://github.com/Yolkster64/helios-platform/pull/10): shared MCP, Claude skill/subagent, sanitized per-checkout context.
- [Enterprise OIDC correction #193](https://github.com/M0nado/helios-platform/pull/193): verified merged as `58c810140e64f371ad0716c9d593847e8650c343`. Its subject must not be copied to a different repository.

The July attachment is historical input. Do not restart the superseded #176/#177 Azure setup sequence simply because it appears in that attachment.

## Concrete setup correction

At the inspected workbench main, `global.json` selects .NET `10.0.100` with `latestFeature` roll-forward, but `.devcontainer/devcontainer.json` still selects .NET 8, links `net8.0/helios-ai`, and suppresses required build failures. PR #135 already corrects those problems. Its prior exact head `242614a55262c704fcca7ddcd013bf58e2dba71c` had eleven returned PR workflow runs, all successful; that evidence does not certify a later head.

PR #135's temporary `outcomeId: null` compatibility edit conflicted with merged main's deterministic UUIDv5 implementation. The reconciliation restores the exact current-main `fleet_learning.py` blob `2711a4a9210cfa51e2360780a88e76a5fa0b2ceb`; it introduces no new fleet behavior. The resulting reconciliation commit is `19e42cb6d151a734b73d02a3a535704a8b432df4`. GitHub then reported the PR mergeable again. It remains draft and requires current-head checks and review.

## Easiest developer path

Use an existing Codespace where available. Otherwise, creating one is an explicit GitHub compute operation subject to your account's quota/billing. For review, select branch `codex/setup-readiness-evidence` rather than the still-unfixed devcontainer on main. After the PR is reviewed and merged, ordinary new Codespaces can use main.

The browser is the client; builds/tests run inside the Codespace. A browser still consumes local resources. A Linux Codespace does not replace Windows for WinUI, device drivers, USB/VHDX execution, or physical device testing.

In the trusted review checkout:

```bash
git status --short
git rev-parse HEAD
dotnet --version
pwsh scripts/setup/setup-all.ps1
```

Install the missing AI CLIs only after reviewing the inventory:

```bash
pwsh scripts/setup/setup-all.ps1 -Fix
```

That existing script installs missing AI CLIs; it does not authenticate accounts. Then perform the keyless build/proof:

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release --no-build
python3 -m pytest src/ai/python/tests -q
python3 plugins/helios-operator/tests/validate_contract.py
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release --no-build -- status
pwsh scripts/bootstrap/setup-everything.ps1 -RequireReady -Json
```

`-RequireReady` belongs to this readiness PR. Do not assume it exists in an older checkout. A provider reported `Unconfigured` is not a failed keyless build and is not authenticated. Read the readiness details and owner actions rather than interpreting process exit alone as full activation.

## Codex and Claude together

Use the installed OpenAI Developers plugin in Codex for relevant development skills. This keyless workflow uses Codex's ChatGPT sign-in; it does not require generating another API key or copying tokens between clients.

```bash
codex login status
# Run only when sign-in is needed; finish authorization in your own browser.
codex login --device-auth
codex mcp list
```

After checking for an existing equivalent registration, add the single HELIOS MCP server:

```bash
codex mcp add helios --env HELIOS_REPO_ROOT="$PWD" -- \
  dotnet run --project "$PWD/src/mcp/HELIOS.Mcp" -c Release --no-build
```

The device-code method is documented by [OpenAI](https://developers.openai.com/codex/auth). MCP registration and OAuth login are documented in the [Codex MCP guide](https://developers.openai.com/codex/mcp). Keep any returned authorization code and auth cache out of logs, issues, and collaboration messages.

Claude already discovers the root `.mcp.json`. Use its existing plugin without adding another HELIOS server:

```bash
claude --plugin-dir ./plugins/helios-operator
```

Inside Claude, run `/mcp`, then `/helios-operator:operate-helios`. The installed marketplace path is also documented in `docs/architecture/CLAUDE_CODE_OPERATOR_PLUGIN.md`. Anthropic documents [local plugin loading](https://code.claude.com/docs/en/plugins) and [marketplace installation](https://code.claude.com/docs/en/discover-plugins).

Start with `helios_ai_status`, `helios_task_routing_get`, and `helios_operator_next_steps_get`. Status/catalog/plan checks are distinct from provider calls. `helios_foundry_agent_create` is a persistent cloud write and is not a readiness test.

Give each coding agent a different branch/worktree. Share approved task packets, commits, test results, and sanitized context; do not share credentials or hidden conversations. `.helios/operator/` persists per checkout only. Commit approved non-secret decisions when another machine or Codespace needs them.

## Slack, Linear, SharePoint, and Microsoft hosts

Current ChatGPT connector proof is not portable client OAuth. Each Codex/Claude/Microsoft client and any deployed worker must authorize independently.

| Surface | Verified or intended scope | What remains |
| --- | --- | --- |
| GitHub | Read/write access to the active workbench; existing PR #135 reused | Exact-head CI/review; no merge or enterprise promotion performed |
| Slack | `#helios-control-plane` resolved as `C0BHWDBHG1W` | Separate client OAuth and worker delivery proof; no claim of installed automation |
| Linear | Existing JOH-35 discussion readable under Helios Integration Fabric | Separate client OAuth; native GitHub/Slack integrations are not proven by reading an issue |
| SharePoint/OneDrive | Existing owner-scoped `Helios/Governance` library is accessible | `/sites/helios` returns 404; team-site creation/access is not complete |
| Teams/M365 Copilot | Existing Helios / Helios Ops remains the historical target | No new Teams, Copilot Studio, or Agent 365 activation proven by this checkpoint |
| Azure/azd/Foundry | Source-controlled operators and contracts exist | No authenticated Azure CLI/azd session or live what-if proven in this runtime |
| Azure DevOps | Historical target `Heli0sDev` | Organization/project session and service connection not reverified here |
| Hermes/XCore/AIHub | Current shared tools and fleet contracts | No worker launch, model training, paid inference, or cloud registration in this checkpoint |

Linear documents a direct [MCP client connection](https://linear.app/docs/mcp). Check existing configuration first, then authorize separately:

```bash
codex mcp add linear --url https://mcp.linear.app/mcp
codex mcp login linear
# For Claude, use one equivalent local registration and finish OAuth in /mcp:
claude mcp add --transport http --scope local linear https://mcp.linear.app/mcp
```

Do not replace existing different registrations automatically. Slack and Microsoft connections should use the approved client/plugin authorization flow; do not transplant ChatGPT connector tokens into a Codespace or guess tenant-specific MCP URLs. No raw API keys, webhooks, recovery keys, or credential-bearing output belong in this document.

## What readiness must prove

Track five separate states: configured, authenticated, read-verified, write-verified, and deployed-worker-verified. A configured server, successful HTTP discovery, non-empty credential variable, green workflow that skipped delivery, or registered agent name is not end-to-end proof.

Before Azure work, obtain the actual tenant/subscription context through the approved operator session, resolve repository-specific OIDC, verify scoped roles and current blockers, then produce the development what-if. Plan approval and deployment approval remain separate. M365/Copilot publication, Graph consent, Key Vault writes, Windows security changes, disks, and physical USB operations are not part of this developer-readiness pass.

## Verification scope

Locally executed in this checkpoint: four existing isolated bootstrap tests, Bash syntax, and Git blob equality for the retrieved bootstrap/test/fleet files. Those tests use inert substitutes for .NET, installers, and elevation; they do not prove a full Codespace build.

The active chat runtime has Git, Node, and Python, but no `gh`, `az`, `azd`, .NET, PowerShell, Docker, Codex, or Claude executable. Outbound DNS to GitHub fails. Connector access succeeds independently. Therefore local live CLI sign-in, native build, full MCP startup, provider inference, and Azure execution are not claimed.

No duplicate PR/issue, force-push, merge, production approval, credential creation, or cloud deployment is authorized by this record.
