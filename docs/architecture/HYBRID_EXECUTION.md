# One HELIOS project across local and Azure execution

HELIOS keeps one C# AIHub and one project contract across Claude Code, Codex,
Copilot, ChatGPT, Hermes and XCore. Client workspaces can be separate Git
worktrees; the shared project, handoff inbox and reviewed source remain common.
Start at [CONNECT](../CONNECT.md), then [agent workspaces](../AGENT_WORKSPACES.md).
This is a source-based execution map, checked on 2026-09-09. It records what the
repository implements; it is not evidence that cloud resources or workers are running.

## Where each decision belongs

| Decision | Existing source | Current behavior |
| --- | --- | --- |
| Project and client entry points | `config/control-project.json`, `AGENTS.md`, `CLAUDE.md` | One project identity and shared instructions; each client retains its own login and supported plugin format. |
| Provider and language routing | `config/aihub.json`, `src/ai/HELIOS.AIHub` | The C# core routes task/language requests through configured API and CLI providers. An installed CLI or listed provider is not an authenticated session. |
| Cross-client notes | `src/mcp/HELIOS.Mcp/HeliosHandoffTools.cs`, `src/mcp/HELIOS.RemoteMcp` | Local stdio and HTTP expose shared, immutable handoffs. Linked worktrees resolve the common store; `HELIOS_HANDOFF_ROOT` can select a trusted shared checkout. A recipient must retrieve the note. |
| Fleet placement | `config/fleet/fleet-topology.json`, `scripts/fleet/start-fleet.ps1`, `scripts/fleet/scale-fleet.ps1` | Four pool definitions, local process launch, board files and a VMSS capacity hook. Live placement requires configured workers and credentials. |
| Engine capabilities | `src/ai/python/helios_agents/engines.py`, `src/mcp/HELIOS.Mcp/HeliosAiTools.cs` | `helios_engine_catalog_get` and `helios_engine_mix_recommend` separate implemented code from prototype/concept candidates. They do not install or execute engines. |
| Fabric activation | `config/fabric/helios-fabric.v1.json`, `src/ai/HELIOS.AIHub/Fabric/FabricPlanService.cs` | The existing planner reports checklist and rename gates. Slack, Linear and SharePoint hold coordination/evidence; GitHub protected environments authorize deployment. |
| Learning | `src/ai/HELIOS.AIHub/Learning`, `src/ai/python/helios_agents/fleet_learning.py` | Local outcome recording and advisory fleet comparisons exist. Source-tagged fleet records do not count as organic provider evidence. |

Shared skills and agent definitions describe capabilities and work responsibilities.
They do not transfer permissions between clients, create Entra principals, or make
a fleet worker an approver. C#, F#, Python and native C++ retain their existing
boundaries behind AIHub; no additional orchestration engine is introduced here.
Recovered AIHub prototypes and training-loop examples remain evidence and design
inputs. Their algorithm names, simulated results and server stubs are not active
engines or additional Hermes/XCore capacity.

## Hosts and pools

| Host or pool | Implemented role | Evidence needed before calling it active |
| --- | --- | --- |
| Developer workstation, Codespace or Cloud Shell | Native client CLIs, local MCP, Git worktrees and explicit setup helpers | Client sign-in, trusted checkout and successful client/tool invocation |
| GitHub-hosted runner | Portable .NET/Python/infra validation and the manual Azure workflow | A successful run for the intended commit; a skipped job is not execution evidence |
| Self-hosted runner | Existing registration scripts and `runs-on: helios-runners` contract | Registered runner, required toolchain and runner smoke result |
| `xcore-9-code` | Code/refactor/test pool; hybrid policy, 2–4 local lanes and up to 5 burst lanes | Real Hermes spawn, task claim/completion and recorded process identity |
| `xcore-9-infra` | Bicep/Terraform/pipeline/config pool; hybrid policy, 1–3 local and up to 6 burst lanes | Same worker evidence; resource mutations still require the deployment authority |
| `xcore-9-review` | Review pool; hybrid policy, 1–4 local and up to 8 burst lanes | Independent findings with actual tool restrictions; topology tool names alone do not enforce a sandbox |
| `xcore-9-native` | Windows/WinUI/C++/GPU work; local policy, 1–3 local lanes | Windows SDK/MSVC and relevant hardware checks on the chosen host |
| Azure burst VMSS | Opt-in infrastructure for Python stub workers, system-assigned identity and CPU autoscaling | Deployed target, approved identity grants, connected task queue, real worker bootstrap and correlated task receipt |
| Edge/offline machine | Can host the existing local client/worker path when its prerequisites are installed | No dedicated edge provisioning or cross-host task transport is established by this branch |

Each pool declares `poolSize: 9`; that is a configured worker count, separate from
the autoscaling bounds above and from the number of verified live workers.
`start-fleet.ps1` uses Hermes when installed and explicitly falls back to the
Python stub otherwise. Stub completion proves board/claim plumbing, not model work.
The optional VMSS currently starts those same stubs against an empty board local
to each instance. Provisioning capacity does not connect that board to local tasks.

## One infrastructure owner per target

**Bicep is the deployment of record for the current HELIOS target.**
`infra/main.bicep` owns the resource graph; `infra/arm/main.json` is its generated
ARM representation. `.github/workflows/infra-validate.yml` checks compilation
and generated ARM freshness.

`infra/terraform` is the existing alternative for a separately designated
Terraform target. Before using it, record the owner as **Terraform**, its
tenant/subscription/resource group, protected workflow and state backend.
Keep that target separate from the Bicep resource group. Its name hashes differ
from Bicep, and Terraform state does not make the two definitions converge.
Changing an existing target's owner requires a reviewed resource/state migration.

| Resource surface | Bicep source | Terraform coverage |
| --- | --- | --- |
| Foundry account, project and model deployments | `infra/modules/ai-foundry-account.bicep`, `infra/modules/ai-foundry-project.bicep` | `infra/terraform/main.tf` includes matching resource families and Claude attestation gates |
| Provider Key Vault and optional secret writes | `infra/modules/keyvault.bicep` | Vault, conditional secrets and role assignments are represented; supplied secret values enter Terraform state |
| Burst VMSS and network/autoscale | `infra/modules/fleet-vmss.bicep` | Represented through AzAPI/AzureRM resources; disabled by default in both surfaces |
| Optional AI Search connection | `infra/modules/ai-search-connection.bicep` | Not represented in the current Terraform mirror |
| Optional learning table storage | `infra/modules/learning-storage.bicep` | Not represented in the current Terraform mirror |

The Terraform mirror covers fewer features than the current Bicep source:
AI Search and learning-storage features are explicitly absent. Do not select
Terraform for a target that depends on those features until their deltas and
validation are added. No Terraform apply workflow or remote state backend is
configured by `infra/terraform/providers.tf`.

## Identity, Key Vault and Cloud Shell

Use [Owner setup](../OWNER_START_HERE.md#4-azure-oidc-for-deploys) for the existing
GitHub OIDC path. `azure-oidc-setup.sh` and its PowerShell twin require explicit
tenant, subscription, resource group and RBAC-enabled vault, and default to a
read-only plan. Their apply path creates no client secret. The supported trust
is `repo:Yolkster64/helios-platform:environment:azure-dev`.

`.github/workflows/helios-deploy.yml` runs only by dispatch from `main`, with
`azure-dev`, five required target variables and `what_if=true` by default.
Environment reviewers and branch protection require actual administrator setup.
The fleet's runtime managed identity is a separate principal from the deploy
identity; provider-key access is not implied by VMSS creation.

Cloud Shell is an operator terminal. `scripts/bootstrap/cloud-shell-setup.sh`
has a `--verify-only` mode. Its broader setup can install CLIs, change shell
persistence, start native sign-in flows and load configured Key Vault secrets.
Review and select the intended Azure account explicitly before the OIDC plan.
Existing `set-provider-secrets.ps1`, `load-env-from-keyvault.sh` and
`provision-github-secrets.ps1` have different storage/provisioning roles; the
owner guide describes those boundaries. ChatGPT app access does not populate
those runtime credentials.

## Verification before activation

Run from the repository root. The following commands validate files or display
local plans; they do not deploy resources or launch fleet workers:

```bash
python3 scripts/validation/validate_config_schemas.py
python3 scripts/validation/validate_helios_fabric_contract.py
bicep build infra/main.bicep --stdout
bicep build-params infra/main.bicepparam --stdout
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
pwsh scripts/fleet/start-fleet.ps1 -DryRun
pwsh scripts/fleet/scale-fleet.ps1 -DryRun
pwsh scripts/fleet/learn-fleet.ps1 -DryRun
```

Terraform initialization can download provider packages and writes local
initialization files; it needs neither a state backend nor resource deployment.
Bicep and Terraform require their installed toolchains. Schema validation of
the Fabric contract requires `jsonschema`.

After the portable solution builds, inspect the existing advisory surfaces:

```bash
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engines
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- engine-plan --fleet-size 9
dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- fleet-plan --json
pwsh scripts/fleet/fleet-status.ps1 -Json
```

`fleet-plan` may read the configured learning backend; it never reorders the
configuration itself. The default `config/aihub.json` records locally with
`adaptiveRouting: false`. `config/aihub.cloud.json` explicitly enables adaptive
routing while still using local learning storage. Selecting that profile changes
behavior. The weekly `fleet-learning.yml` cycle is informational and synthetic.

## Remaining integration work

1. Reconcile `defaults.autoscaling.burstTarget: "arc"` with the actual VMSS hook
   in `scale-fleet.ps1`. An ARC controller/scale-set integration is not implemented
   by that script; Actions Runner Controller and Azure Arc are different systems.
2. Add authenticated cross-host board transport, real Hermes worker provisioning
   and durable task/result receipts before describing VMSS instances as fleet capacity
   that can drain local work. Keep per-host and per-task identity explicit.
3. Route live scaling through the same verified target and protected authority as
   deployment. The existing direct `az vmss scale` hook uses the active CLI account
   and resource-group/name settings; it does not perform the new tenant/subscription
   preflight or enter a GitHub protected environment.
4. Align fleet status verification: the MCP status tool and scale/stop paths check
   PID plus start time; `fleet-status.ps1` currently checks PID presence only.
   A reused PID must not count as proof of a HELIOS worker.
5. Complete the missing Terraform features only for a selected Terraform target,
   then establish state custody and a protected plan/apply workflow. Preserve the
   single-owner rule throughout.

No infrastructure, identity, credential, worker, backend or cloud resource was
created or changed during this static architecture review.
