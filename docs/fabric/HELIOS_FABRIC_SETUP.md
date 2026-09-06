# HELIOS Fabric Setup and Activation

This runbook turns the Yolkster HELIOS repositories, agents, connectors, cloud identity, and governance surfaces into one controlled fabric. It is intentionally **plan-first**. Production remains disabled until a separate, evidence-backed authorization.

## 1. Canonical topology

```text
Yolkster64/helios-control
  Core orchestration, AIHub, agents, MCP, Azure/Bicep, automation,
  Windows/recovery contracts, shared domain and integration contracts

Yolkster64/helios-gui
  Native C#/.NET 10 WinUI 3 Control Center, MSIX packaging, visual system

Yolkster64/Yolkster64
  Public profile README only

Yolkster64/.github-enterprise-control
  Repository factory, rulesets, runner policy, governance only
```

The active Yolkster source is currently `Yolkster64/helios-platform`. Rename it in place only after PR #154 and current-main CI are green. Never replace it wholesale with the older M0nado parent.

## 2. Binding UI architecture

The product desktop is:

```text
C# / .NET 10
WinUI 3
Windows App SDK
Microsoft.UI.Xaml
Microsoft.UI.Composition
single-project MSIX by default
```

There is no active WPF or UWP fallback. The existing `src/gui/HELIOS.Shell.sln` is the extraction source. Historical `MonadoBlade.GUI` code is design/porting input only; useful logic must be rewritten against `Microsoft.UI` types.

## 3. Fabric control model

Every operation follows:

```text
observe -> validate -> plan -> request approval -> execute bounded action -> verify -> publish receipt
```

Read operations may run automatically when scoped and redacted. Consequential writes require an idempotency key, source commit, approval receipt, and result receipt. Undeclared tools are denied.

## 4. Repository cutover

1. Merge the isolated current-main repair PR #155 only after every required exact-head check succeeds.
2. Rebase PR #154 onto the new `main` and remove duplicate repair changes.
3. Run complete CI, WinUI contract validation, provider tests, security scanning, and provenance review.
4. Export repository identity, issues, PRs, releases, tags, Actions, environments, rulesets, webhooks, and installed-app access.
5. Rename `Yolkster64/helios-platform` to `Yolkster64/helios-control` through an authenticated repository-administrator surface.
6. Verify redirects and every exported count/identifier.
7. Create `Yolkster64/helios-gui`, extract the active WinUI solution with history/provenance, and establish Windows-hosted build/package gates.
8. Retarget consumers only after both live repository identities are verified.

## 5. GitHub environments and OIDC

Create protected environments:

```text
azure-dev-plan
azure-dev-deploy
azure-test-plan
azure-test-deploy
azure-prod-plan
azure-prod-deploy
```

Expected OIDC subjects:

```text
repo:Yolkster64/helios-control:environment:azure-dev
repo:Yolkster64/helios-control:environment:azure-test
repo:Yolkster64/helios-control:environment:azure-prod
```

Use separate identities for planning, deployment, image build, runtime, and Claude/Foundry. Scope RBAC to the target resource group or resource. Never create a client secret for CI. Deployment jobs require protected approval and an immutable source/image reference.

## 6. Azure DevOps validation mirror

Azure DevOps organization: `Heli0sDev`.

Create Entra-issued workload-identity-federated service connections:

```text
helios-control-azure-wif-dev
helios-control-azure-wif-test
helios-control-azure-wif-prod
```

Azure DevOps may validate code, compile Bicep, run a development what-if, and mirror evidence. GitHub protected environments remain the deployment authority. Pipeline identities receive no Key Vault secret-read role.

## 7. SharePoint governance and evidence

Authorized path:

```text
heli0s-my.sharepoint.com
/personal/jmore_heli0s_onmicrosoft_com
Helios/Governance
```

Publish deterministic manifests and verified bytes to the existing Architecture, Runbooks, Security, Compliance, Deployment-Evidence, Releases, Rollback, AIHub, and MonadoBlade folders. Record file IDs, hashes, timestamps, and Graph request IDs; never publish tokens or secret values.

## 8. Slack and Linear routing

Requested operations destination:

```text
Slack workspace:    T0BAFGSNY5P
Slack conversation: D0BB80HRZFA
```

No fallback destination is allowed. The Slack app must be installed and authorized in that workspace before posting.

Linear project: `Helios Integration Fabric`. GitHub issues HC-001 through HC-028 are the implementation ledger. Linear issue JOH-208 is the cross-system coordination item. First events create once; later events update/comment using the same correlation key.

## 9. OpenAI, Claude, Copilot, Foundry, Hermes, and XCore

All providers implement a common task/result/capability/health/cost/latency/quality/approval/trace contract through AIHub. Credentials are environment or Key Vault references only.

- OpenAI/Codex: project-scoped restricted key or approved platform identity; bounded Responses/Agents/MCP operations.
- Claude Code: `CLAUDE.md`, skills, subagents, hooks, and project MCP; branch/build/test/plan authority only.
- Microsoft Copilot/Foundry: scoped agent and Graph permissions; tenant publication requires separate approval.
- Hermes/XCore: route, execute bounded workers, score, reflect, and write redacted memory; cannot self-enable tools or approvals.
- Local models: loopback-only provider endpoints unless a separate network/security design is approved.

## 10. AIHub hardening prerequisite

Before external binding or provider credentials:

- default-bind to `127.0.0.1`;
- authenticate and authorize non-health endpoints;
- bound request size, concurrency, rate, duration, and budget;
- use atomic state and replay/idempotency controls;
- separate read/plan tools from approval-pending writes;
- produce structured, redacted audit and health/readiness events.

HC-009 owns this gate.

## 11. Fork absorption

- Hermes repositories: import only original HELIOS contracts/adapters/skills/tests with source SHA and license.
- WindowsDeveloperConfig: convert Yolkster deltas to rerunnable declarative configs.
- Azure SDK forks: use released packages plus thin HELIOS adapters.
- Monado Blade: preserve immutable integration artifacts/provenance; archive only after destination proof.
- Unknown forks: manual classification; no automatic import or deletion.

## 12. First activation sequence

The first cloud run is development-only:

```text
validate repository and contracts
compile Bicep
run development what-if with apply=false
publish canonical plan JSON and hash
human review
stop
```

A later development apply requires a separate request and protected-environment approval. Test and production use independent identities, resource groups, evidence, and approvals.

## 13. Completion evidence

The fabric is not complete until all of the following are recorded:

- final core and GUI repository IDs/SHAs;
- issue and PR mappings;
- release/tag and package provenance;
- CI and Windows/MSIX results;
- OIDC/WIF identities and scoped role assignments;
- exact-source what-if hash;
- Slack message, Linear issue, and SharePoint file receipts;
- OpenAI/Claude/Copilot/Foundry health results without credentials;
- rollback rehearsal;
- explicit production authorization, if ever granted.
