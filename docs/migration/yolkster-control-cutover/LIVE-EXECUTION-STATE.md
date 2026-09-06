# HELIOS Live Canonicalization State

Last updated: 2026-09-05

## Current repository authority

`Yolkster64/helios-platform` is the active, newer Yolkster line and the only repository eligible for the in-place rename to `Yolkster64/helios-control`.

The older `M0nado/helios-platform` repository is a historical upstream and migration source. It must not overwrite the Yolkster destination.

## Target topology

- Core and control plane: `Yolkster64/helios-control`
- Native desktop shell: `Yolkster64/helios-gui`
- Profile presentation: `Yolkster64/Yolkster64`
- GitHub governance: `Yolkster64/.github-enterprise-control`

## Active implementation

- PR #154 establishes the cutover contract, WinUI 3-only policy, Claude Code migration boundary, fork inventory, profile handoff, and HC-001 through HC-028 ledger.
- PR #155 repairs Python/C# fleet-learning outcome identity parity independently of the repository migration.
- GitHub issues #156 through #183 are the live canonical work graph.
- Linear issue JOH-208 is the urgent cross-system coordination record.

## WinUI 3 boundary

The compiled desktop solution is `src/gui/HELIOS.Shell.sln` with `<UseWinUI>true</UseWinUI>`. Its current .NET 8 target is a migration baseline; HC-002 owns the controlled upgrade to .NET 10.

`HELIOS.Platform.csproj` and `src/gui/MonadoBlade.GUI` are legacy or porting inputs. They are not an active WPF fallback, and no WPF/UWP code may be copied into `helios-gui` without being ported to `Microsoft.UI.Xaml` and `Microsoft.UI.Composition`.

## Collaboration targets

- Slack workspace: `T0BAFGSNY5P`
- Slack conversation: `D0BB80HRZFA`
- Linear project: `Helios Integration Fabric`
- SharePoint: `Helios/Governance`
- Azure DevOps organization: `Heli0sDev`

The currently connected Slack app is attached to a different workspace. The requested Slack post is therefore blocked until workspace `T0BAFGSNY5P` is connected; no fallback channel is authorized.

## Cloud safety state

- `productionEnabled=false`
- `applyDefault=false`
- GitHub protected environments remain deployment authority.
- Azure DevOps is validation and evidence mirroring only.
- No Azure deployment, Entra/RBAC mutation, secret write, repository archival, disk mutation, or production approval is authorized by this document.

## Controlled sequence

1. Merge PR #155 only after all exact-head checks succeed.
2. Rebase PR #154 onto the resulting current `main` and remove any duplicate repair commit.
3. Pass the complete CI matrix and review the exact migration head.
4. Rename the active repository in place through an authenticated GitHub administrator surface.
5. Verify redirects, issues, pull requests, releases, Actions, rulesets, environments, webhooks, and app access.
6. Extract `src/gui/HELIOS.Shell` to `Yolkster64/helios-gui` through a Windows-tested reviewed PR.
7. Retarget OIDC, Azure DevOps, Slack, Linear, SharePoint, OpenAI/Codex, Claude, and other connectors only after the final repository identities exist.
8. Run a development Azure `what-if` with `apply=false`; retain and review the evidence before any separate deployment request.
