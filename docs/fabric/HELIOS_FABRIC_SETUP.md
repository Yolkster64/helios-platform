# HELIOS Fabric Setup

## Purpose

HELIOS Fabric is the governed connection plane joining the canonical source repository,
WinUI 3 operator shell, AIHub, local MCP tools, Claude Code, Codex/OpenAI, GitHub
Copilot, Azure AI Foundry, Hermes/XCore, GitHub Actions, Azure DevOps, Slack, Linear,
and SharePoint.

It is not a second deployment engine. GitHub protected environments remain the source,
review, and deployment authority; Azure DevOps is a validation and evidence mirror.
Every consequential action remains explicit, approval-gated, and receipt-backed.

## Canonical product topology

```text
Yolkster64/helios-platform
    current live repository
    administrator rename in place
              |
              v
Yolkster64/helios-control
    canonical core, AIHub, agents, MCP, Azure, security, recovery, contracts

Yolkster64/helios-gui
    native C#/.NET 10 WinUI 3 operator shell
    Microsoft.UI.Xaml + Microsoft.UI.Composition
```

`M0nado/helios-platform` is a historical upstream/migration source, not the destination.
The active Yolkster line contains newer work and must never be replaced by an older tree.

## Binding safety state

```text
productionEnabled=false
applyDefault=false
secretValuesInRepository=false
externalWritesRequireApproval=true
active desktop framework=WinUI 3
WPF/UWP active product use=forbidden
```

The machine-readable contract is `config/fabric/helios-fabric.v1.json`. Its schema is
`config/schemas/helios-fabric.schema.json`. The contract contains names, destinations,
allowed operations, denied operations, dependencies, and evidence fields; it contains no
credential value.

## Local validation and plan

From the repository root:

```bash
python scripts/fabric/plan_helios_fabric.py --mode validate
python scripts/fabric/plan_helios_fabric.py \
  --mode plan \
  --output .helios/evidence/fabric/fabric-plan.json
```

To check only whether named environment references exist, never their values:

```bash
python scripts/fabric/plan_helios_fabric.py \
  --mode plan \
  --inspect-env \
  --output .helios/evidence/fabric/fabric-plan.environment.json
```

`--strict-env` is suitable for an explicitly configured activation job. It exits with
status 3 when required environment references are absent. Missing credentials are a
blocked setup state, not a reason to weaken the contract.

## MCP visibility

The existing repository-level `.mcp.json` launches `src/mcp/HELIOS.Mcp`. The new
read-only tool is:

```text
helios_fabric_plan_get
```

It returns the canonical authority map, integration readiness, setup phases, approvals,
and evidence requirements. It reports environment-variable names and presence only.
It does not return values, contact providers, run shell commands, merge code, or mutate
Azure, GitHub, Slack, Linear, SharePoint, a workstation, or a secret store.

Build it with:

```bash
dotnet build src/mcp/HELIOS.Mcp/HELIOS.Mcp.csproj --configuration Release
```

## CLI visibility

The same sanitized envelope is reachable from the operator shell without an MCP client
through the `helios-ai fabric-plan` subcommand. It walks up from the current directory
to find `config/fabric/helios-fabric.v1.json`, applies the same fail-closed checks as
`helios_fabric_plan_get` (production disabled, apply off, no repository-stored secret
values, WinUI 3 active), and prints a compact JSON summary plus per-integration and
per-phase readiness. Nothing is contacted; no credential value is read, printed, or
serialized.

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli/HELIOS.AIHub.Cli.csproj \
  --configuration Release -- fabric-plan
```

Exit code `0` when the contract validates. Exit code `1` when the file is missing,
unreadable, or violates a fail-closed invariant — a one-line diagnostic goes to stderr,
the JSON envelope is not printed, and no partial state leaks.

## Integration authorities

| Integration | Role | Activation boundary |
|---|---|---|
| GitHub | Source, review, release, deployment authority | Repository administrator for rename/rulesets/environments |
| WinUI 3 GUI | Native operator surface | Separate repository extraction and Windows x64/MSIX proof |
| HELIOS MCP | Shared typed read/plan/status tools | Local stdio by default; no generic shell |
| OpenAI/Codex | Coding, reasoning, evaluation | Project-scoped key or managed reference; no readback |
| Anthropic/Claude | Long-context engineering and review | Project instructions/MCP; trusted config; no admin rights |
| Azure Foundry | Managed agents and enterprise-data work | Dedicated identity and project-scoped RBAC |
| Hermes/XCore | Routing, bounded execution, scoring, reflection | Owned deltas only; no deployment or self-authorization |
| Slack | Operations and incident surface | Exact workspace/conversation connection and message receipt |
| Linear | Execution graph | Create-once/idempotent synchronization |
| SharePoint | Governance and evidence | Selected/delegated scope and post-upload hash verification |
| Azure | Development cloud control plane | Environment OIDC, resource-scoped RBAC, reviewed what-if |
| Azure DevOps | Validation/evidence mirror | Entra-issued WIF; cannot bypass GitHub environments |
| Azure Key Vault | Secret-reference authority | Runtime identity references only; pipeline readback denied |

## Current named destinations

```text
Slack workspace:      T0BAFGSNY5P
Slack conversation:   D0BB80HRZFA
Linear project:       Helios Integration Fabric
Linear cutover issue: JOH-208
SharePoint root:      Helios/Governance
Azure DevOps org:     Heli0sDev
```

The Slack destination must be connected to the app before posting. Cross-workspace
fallback is explicitly forbidden; a message in the wrong workspace is not success.

## Ordered setup phases

The contract defines `F00` through `F16`:

1. Validate the contract and dependency graph.
2. Inventory repositories, forks, source SHAs, and licenses.
3. Rename the current Yolkster repository in place through an authenticated admin.
4. Extract the native WinUI 3 GUI repository.
5. Build/test/package the WinUI shell on Windows.
6. Build and enumerate the shared MCP surface.
7. Validate provider and AIHub contracts without credentials.
8. Import selected Hermes/XCore deltas through a reviewed PR.
9. Bind Slack and Linear with signature, replay, and idempotency tests.
10. Publish and byte-verify governance evidence in SharePoint.
11. Create environment-bound Azure identities and minimum RBAC.
12. Create Azure DevOps Entra-issued WIF connections.
13. Bind Key Vault provider references and prove secret readback is denied.
14. Run a development-only Azure `what-if` and retain the canonical plan hash.
15. Run correlated end-to-end smoke tests and a rollback rehearsal.
16. Seal source SHAs, checksums, receipts, releases, and issue mappings.
17. Consider production in a distinct owner decision; it stays disabled here.

Phases that mutate external state declare an approval class. The planner must never
convert “approval required” into “approved.”

## GitHub Actions contract

`.github/workflows/helios-fabric-contract.yml` performs only validation:

- parse and validate the Fabric topology;
- build the sanitized setup plan;
- execute planner regression tests;
- build the .NET 10 MCP server;
- verify WinUI 3-only and fail-closed invariants;
- enforce the non-deployment Fabric boundary via
  `scripts/validation/validate_helios_fabric_policy.py` (contract fail-closed markers,
  workflow `contents: read`-only permission, and forbidden Azure-apply/OIDC tokens);
- upload plan/evidence artifacts.

The workflow has `contents: read` only. It receives no OIDC token and contains no Azure
apply, secret write, repository mutation, or connector write.

## Azure DevOps parity

`.azuredevops/pipelines/helios-fabric-validate.yml` runs the same contract, tests, and
MCP build on a Microsoft-hosted agent. It needs no service connection and cannot deploy.

Later activation uses Entra-issued workload identity federation through separately
approved connections:

```text
helios-control-azure-wif-dev
helios-control-azure-wif-test
helios-control-azure-wif-prod
```

The first cloud action is development `what-if` with `apply=false`. Pipeline identities
receive resource-group or resource scope only and do not receive Key Vault secret-read
permissions.

## Provider setup

Provider configuration stays in `config/aihub.json` and environment/Key Vault references.
HELIOS never stores a raw OpenAI, Anthropic, GitHub, Slack, Linear, Microsoft, or Azure
credential in source control.

Before provider activation:

1. Harden the AIHub network/authentication boundary.
2. Create or select a project-scoped credential outside chat and source control.
3. Store only the approved secret version in Key Vault or a local ignored environment.
4. Grant the runtime identity access to that reference—not to list unrelated secrets.
5. Run one minimal request, timeout, rate, budget, fallback, and redaction test.
6. Publish sanitized metadata and a receipt; never publish the value.

## WinUI 3 boundary

The active desktop architecture is C# and WinUI 3. The GUI migration must reject:

```text
<UseWPF>true</UseWPF>
System.Windows
PresentationFramework
PresentationCore
Windows.UI.Xaml
PowerShell PresentationFramework GUI hosts
```

Historical WPF-era files may be used as design/porting inputs only. Visual logic must be
ported to `Microsoft.UI.Xaml` and `Microsoft.UI.Composition`, then built on a Windows
runner. There is no WPF bridge, fallback shell, or migration phase in the final product.

## Completion standard

An integration is complete only when all of these exist:

- exact source and target identity;
- authenticated health check;
- minimum permission scope;
- successful contract/smoke test;
- correlation ID and immutable source SHA;
- redacted receipt or verified file identifier;
- rollback path;
- owner approval where required.

A prepared file, claimed upload, queued workflow, old mergeability snapshot, or message in
the wrong Slack workspace does not satisfy the standard.
