# HELIOS Azure AI Infrastructure

Bicep templates for the HELIOS multi-LLM hub: an Azure AI Foundry account + project
(modern model), parameterized model deployments, and a Key Vault for provider API keys.

## Why not the hub-based template?

The original "standard agent setup" quickstart used the hub/project model
(`Microsoft.MachineLearningServices/workspaces` + capability host). Microsoft now calls
that model **Foundry classic** and documents a migration away from it. These templates
re-express the same parameter surface on the modern Foundry account + project model
(`Microsoft.CognitiveServices/accounts@2025-06-01` with `allowProjectManagement: true`).

### Legacy → modern mapping

| Legacy hub parameter | Here |
|---|---|
| `aiServicesName`, `aiProjectName`, `location`, `tags` | Same names, same meaning |
| `modelName` / `modelFormat` / `modelVersion` / `modelSkuName` / `modelCapacity` / `modelLocation` | Same names — primary deployment quintet |
| `aiServiceAccountResourceId` (BYO) | Same name; when set, account/deployments/project creation is skipped (see below) |
| `aiHubName`, `aiHubFriendlyName`, `aiHubDescription` | N/A — there is no hub in the modern model |
| `capabilityHostName` | N/A — agents use the project endpoint directly |
| `aiSearchName`, `storageName`, key vault for hub | AI Search + BYO storage arrive in a follow-up PR; Key Vault here stores **provider API keys**, not hub config |
| `PROJECT_CONNECTION_STRING` output | `projectEndpoint` output (`https://<account>.services.ai.azure.com/api/projects/<project>`) |
| — (no legacy equivalent) | `deployLearningStorage` (default `false`) + `learningStorePrincipalId` — opt-in RBAC-only storage account + `aihubOutcomes` table for the AIHub learning store (`modules/learning-storage.bicep`); the `learningTableEndpoint` output feeds `AZURE_LEARNING_TABLE_ENDPOINT` for `learning.mode=azure`/hybrid |
| — (no legacy equivalent) | `claudeOrganizationName` (default `''`) + `claudeCountryCode` / `claudeIndustry` — the Marketplace attestation (`modelProviderData`) the Anthropic-format entries of `additionalModelDeployments` need (Claude in Foundry, below); the `aiServicesAccountName` / `anthropicFoundryBaseUrl` outputs feed `ANTHROPIC_FOUNDRY_RESOURCE` |

Other deliberate changes:

- **Stable resource suffix.** The quickstart mixed `utcNow()` into `uniqueString`, which
  creates brand-new resources on every deployment. Here the suffix is
  `uniqueString(resourceGroup().id)` so re-deployments are idempotent.
- **Multi-model deployments.** `additionalModelDeployments` is a typed array
  (`{name, modelName?, format?, version, skuName?, capacity?}`) concatenated after the
  primary quintet — add models in `main.bicepparam`, not in the template.
- **BYO account limitation.** When `aiServiceAccountResourceId` is set, this template does
  not create deployments or a project on the existing account (cross-scope child resources);
  manage those on the existing account and use its endpoints directly.

## Files

- `main.bicep` — entry point (resource-group scope)
- `main.bicepparam` — deployment parameters (edit models here)
- `modules/ai-foundry-account.bicep` — Foundry account + serialized model deployments (GA `2025-06-01` loop for first-party formats, chained `2025-10-01-preview` loop for Anthropic-format entries) + Azure AI User role
- `modules/ai-foundry-project.bicep` — Foundry project (endpoint output)
- `modules/keyvault.bicep` — RBAC Key Vault + conditional `anthropic-api-key` / `openai-api-key` / `github-models-token` secrets
- `modules/fleet-vmss.bicep` — opt-in fleet burst VMSS + autoscale, OFF by default (see "Fleet burst capacity (VMSS)" below)
- `modules/ai-search-connection.bicep` — opt-in Azure AI Search + project connection + agent capability hosts, OFF by default (see "AI Search connection (agents)" below)

## Three dialects

The infrastructure has three representations with distinct roles and coverage:

- **Bicep** (`main.bicep` + `modules/`) — the **source of truth** and the deployment of
  record. All changes start here; `helios-deploy.yml` deploys from it.
- **ARM JSON** (`arm/main.json`) — a **generated artifact** compiled from the Bicep
  (never hand-edited; see `arm/README.md`) for ARM-only surfaces: pipelines without a
  Bicep toolchain and Azure portal "Deploy a custom template". CI fails if it drifts
  from the Bicep source.
- **Terraform** (`terraform/`) — an **independent, partial mirror** covering Foundry,
  Key Vault and fleet VMSS resources. AI Search and learning storage are not yet
  mirrored. Its resource-name hashes differ from Bicep; designate a separate target
  resource group and state owner. Do not let both dialects manage one target.
  See [hybrid execution](../docs/architecture/HYBRID_EXECUTION.md) for the ownership,
  worker and identity boundaries.

## Deploy

```bash
az group create -n rg-helios-ai -l eastus2
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam
az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam
```

Provider keys are passed as secure parameters at deploy time (never committed):

```bash
az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters anthropicApiKey="$ANTHROPIC_API_KEY" openaiApiKey="$OPENAI_API_KEY"
```

CI: `.github/workflows/infra-validate.yml` compiles + lints the Bicep, checks
`arm/main.json` freshness against it, and runs `terraform fmt`/`validate` on every PR
touching `infra/**` (all offline, no subscription). The deployment workflow is
manual only, runs from `main` under protected environment `azure-dev`, and defaults
to what-if. It requires five explicit environment variables:
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_RESOURCE_GROUP` and `AZURE_LOCATION`. Missing values fail before Azure login.
Apply additionally requires `what_if=false` and `deploy_confirmed=true`; no push
can deploy and the workflow never creates a resource group.

## Fleet burst capacity (VMSS)

`modules/fleet-vmss.bicep` adds opt-in cloud lanes for the Hermes/Xcore fleets — the
burst target for **fleet worker lanes** declared in `config/fleet/fleet-topology.json`
(docs/architecture/HERMES_FLEET_AND_XCORE.md, "Autoscaling (local / hybrid)"). It is a
Flexible-orchestration Linux VM scale set (Ubuntu 24.04 LTS Gen2, `Standard_B2s` by
default, system-assigned identity) whose instances cloud-init the lane toolchain
(dotnet-runtime-8.0, python3, pwsh), clone this repo anonymously (no secrets in
cloud-init), and run `fleetWorkersPerInstance` stub fleet workers
(`python3 -m helios_agents.fleet_worker`) with `HELIOS_FLEET_POOL` set (default
`cloud-burst`), so outcome analytics attribute cloud lanes to their pool.

> **Known limitation — board transport.** Cloud instances currently seed an EMPTY
> per-instance board: the host run's boards live on the host filesystem
> (`.helios/fleet/<runId>/boards/`), and no shared mount or sync exists yet, so
> burst lanes prove the runtime path but do not drain the host queue. Shared board
> storage (Azure Files mount or a queue-backed board) is the follow-up that makes
> burst capacity productive; until it lands, treat `scale-fleet.ps1`'s VMSS hook
> as capacity pre-provisioning.

**OFF by default — the live `rg-helios-ai` stack redeploys unchanged.** The module is
doubly gated: `deployFleetVmss` (default `false`) **and** a non-empty
`vmssAdminPublicKey`. Auth is SSH-key-only (password auth disabled); a public key is
not a secret, so it is a plain parameter passed at deploy time:

```bash
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployFleetVmss=true vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployFleetVmss=true vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
```

**What autoscale does vs what scale-fleet.ps1 adds.** The built-in Azure autoscale
setting is a CPU proxy for lane pressure: average CPU > 70% for 5 minutes adds one
instance (5-minute cooldown); average CPU < 25% for `fleetScaleDownIdleSeconds`
(default 300 — the topology's `scaleDownIdleSeconds`) removes one. The floor and
default are `fleetBurstMinInstances` (0) and the ceiling is `fleetBurstMaxInstances`
(5 — the topology's `maxBurstLanes`). Azure autoscale cannot see board queue depth
(`scaleUpQueueDepth`) without publishing custom metrics to Application Insights, so
queue-depth-driven scaling arrives separately via `scripts/fleet/scale-fleet.ps1`
calling `az vmss scale --new-capacity` against the `fleetVmssName` output.

**Cost.** `Standard_B2s` (2 vCPU / 4 GiB) runs roughly US$30–40 per instance-month
(region-dependent), plus small per-instance OS-disk and Standard public IP charges —
all billed only while instances exist. With `fleetBurstMinInstances = 0` the set
scales to zero: an idle enabled stack keeps only the vnet, NSG, and autoscale
setting, which are free. Instances are unreachable from the internet (the NSG ships
no inbound allow rules); the per-instance public IPs exist for outbound access only
(apt/snap/git), chosen over a NAT gateway precisely because they cost nothing at
zero instances.

**Two burst targets, deliberately.** ARC runner scale sets (`infra/runners/`) remain
the burst target for **CI lanes** (`runs-on: helios-runners`); this VMSS is the burst
target for **fleet worker lanes** (the Hermes/Xcore pools). They scale on different
signals — queued workflow jobs vs board queue depth and CPU — and must not be
conflated.

## AI Search connection (agents)

`modules/ai-search-connection.bicep` gives Foundry agents a bring-your-own vector
store: an Azure AI Search service (`basic` tier by default, **local/API-key auth
disabled** — identity-based access only), a `CognitiveSearch`-category `AAD` connection
on the Foundry project, `Search Index Data Contributor` + `Search Service Contributor`
role assignments for the project's system-assigned identity, and the account + project
capability hosts (`capabilityHostKind: 'Agents'`, `vectorStoreConnections`) that make
the Agent Service read it. No keys exist anywhere in the module, so none can be output.

**OFF by default — the live `rg-helios-ai` stack redeploys unchanged.** Gated on
`deployAiSearchConnection` (default `false`) and ignored when
`aiServiceAccountResourceId` points at an existing account (there is no
template-managed project to attach to). Two service-side constraints to know before
enabling: each account/project allows exactly **one** capability host (a pre-existing
one with a different name fails with 409), and capability hosts cannot be updated —
delete and recreate to change them. Full BYO "standard agent setup" would additionally
reference Cosmos DB (`threadStorageConnections`) and Storage (`storageConnections`)
connections; this module wires the vector-store third.

```bash
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters deployAiSearchConnection=true
```

## Claude in Foundry (Anthropic-format deployments)

The hub's `anthropic-foundry` provider and `scripts/ai-integration/Connect-ClaudeFoundry.ps1`
call Claude through this account's Messages API base URL,
`https://<account>.services.ai.azure.com/anthropic` (Entra scope `https://ai.azure.com/.default`,
`model` = deployment name), and expect deployments named `claude-sonnet-4-6`,
`claude-haiku-4-5` and `claude-opus-4-6` (`ANTHROPIC_DEFAULT_{SONNET,HAIKU,OPUS}_MODEL`).
Those three are declared as data in `main.bicepparam` — `additionalModelDeployments`
entries with `format: 'Anthropic'`, `version: '1'`, `GlobalStandard`, capacity 25 (K TPM) —
the shape the Learn deployment guide's starter kit uses ([Deploy Claude models in
Microsoft Foundry using Bicep or Terraform](https://learn.microsoft.com/azure/developer/ai/how-to/deploy-claude-foundry),
[Azure-Samples/claude](https://github.com/Azure-Samples/claude) `infra-bicep/infra/foundry.bicep`).

Facts that shape the template (all from Microsoft Learn):

- **Account.** Claude needs a Foundry project in a supported deployment location plus
  Azure Marketplace access ([Deploy and use Claude models](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/use-foundry-models-claude),
  Prerequisites) — this `kind: 'AIServices'` account with `allowProjectManagement: true`
  and its project already are that; nothing changes on the account.
- **Version.** `'1'` = Hosted on Anthropic infrastructure, `'2'` = Hosted on Azure.
  Sonnet 4.6 and Opus 4.6 exist only as `'1'`; Haiku 4.5 offers both
  ([Claude models in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/claude-models),
  "Available Claude models").
- **Region.** All three families are Global Standard in `eastus2` and `swedencentral`
  (`westus2`: Sonnet and Opus only) — [Region availability by deployment type](https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-from-partners#region-availability-by-deployment-type).
  `rg-helios-ai` is bootstrapped in `eastus2` (`azure-up.sh` default; the account follows
  the resource group's location), so the account qualifies — confirm with
  `az cognitiveservices account show -g rg-helios-ai -n helios-aijcut --query location`.
- **Quota.** Pay-as-you-go defaults: Sonnet 4.6 / Haiku 4.5 80K ITPM, Opus 4.6 40K ITPM
  (same Claude models page, "Quotas and rate limits"); `capacity` is K TPM, so 25 fits all
  three. Soft-deleted accounts hold Claude TPM quota for up to 48 hours (deployment guide,
  Troubleshooting).
- **Attestation.** Every Claude deployment must carry `modelProviderData`
  (`organizationName`, `countryCode`, `industry`) — the Cognitive Services RP uses it to
  accept the Anthropic Marketplace offer on your behalf, and a deployment without it fails
  with `AnthropicOrganizationCreationException` (deployment guide, "Terms of use"; starter
  kit README). That block exists only on `accounts/deployments@2025-10-01-preview`, so
  `modules/ai-foundry-account.bicep` deploys Anthropic-format entries through a second
  `@batchSize(1)` loop on that API version, chained after the GA `2025-06-01` loop; every
  other deployment keeps the GA pin. The property is untyped in Bicep (`BCP037`
  suppressed on that one line).

**OFF by default — the live `rg-helios-ai` stack redeploys unchanged.**
`claudeOrganizationName` is empty in `main.bicepparam`, and an empty organization name
skips the Anthropic-format entries. The legal entity name is not a secret, but it is an
attestation the owner makes (review the
[Anthropic Commercial Terms](https://www.anthropic.com/legal/commercial-terms) first), so
pass it at deploy time — what-if first:

```bash
az deployment group what-if -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters claudeOrganizationName="<legal entity name>" claudeCountryCode=US claudeIndustry=technology
az deployment group create -g rg-helios-ai \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters claudeOrganizationName="<legal entity name>" claudeCountryCode=US claudeIndustry=technology
```

Expect three `Create` entries (`helios-aijcut/claude-sonnet-4-6`, `/claude-haiku-4-5`,
`/claude-opus-4-6`) and no `Delete`. The `aiServicesAccountName` / `anthropicFoundryBaseUrl`
outputs feed `ANTHROPIC_FOUNDRY_RESOURCE` in `.helios/azure.env` and
`.helios/azure.env.ps1` (written by `scripts/bootstrap/azure-up.*`); calls authenticate
with Entra ID, and the account's existing Azure AI User grant to `principalId` is the
data-plane role this template manages.

## OIDC identity (GitHub Actions → Azure)

The setup twins `scripts/bootstrap/azure-oidc-setup.sh` and `.ps1` are read-only
by default and require explicit tenant, subscription, resource group and vault
parameters. They verify the active account, exact resource IDs and RBAC vault mode
without changing the Azure CLI account. The [owner checklist](../docs/OWNER_START_HERE.md#4-azure-oidc-for-deploys)
contains both commands and the Cloud Shell / provider-key handoff.

Only an explicitly requested `--apply` / `-Apply` can create the deploy app and
service principal, add scoped Contributor / Key Vault Secrets Officer grants,
and create this federation:

| Setting | Value |
| --- | --- |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Subject | `repo:Yolkster64/helios-platform:environment:azure-dev` |
| GitHub environment | `azure-dev`, required reviewers and `main` only |

The bootstrap refuses production, creates no branch or pull-request trust, and
only removes legacy named branch/PR/production credentials during explicit Apply.
It prints all five `gh variable set --env azure-dev` commands. It does not create
GitHub protections, issue a cloud client secret or deploy the template.

At runtime only the deploy job has `id-token: write`. `azure/login@v2` exchanges
that job's OIDC token using the pinned audience. The workflow validates the active
subscription, tenant, Enabled state and existing resource-group ID/location before
either what-if or apply. It never creates groups or falls back to historical
subscription, resource-group, location or credential values.

A manual `main` run defaults to `what_if=true`. Apply requires a separate manual
run with `what_if=false`, `deploy_confirmed=true` and protected-environment approval.
The confirmation records the operator's decision; it does not cryptographically
bind this run to a previous plan. Custody records preserve allowlisted summaries,
input digests and failure evidence; raw Azure output is discarded.

Keep `principalId` unset for CI unless a separately reviewed identity can assign
roles. The deploy principal's Contributor role does not grant that authority.
Fleet and learning resources remain governed by their existing opt-in parameters.

## Outputs

`aiServicesEndpoint`, `openAiEndpoint`, `projectEndpoint`, `projectId`, `keyVaultUri`,
`modelDeploymentNames`, `aiServicesAccountName` / `anthropicFoundryBaseUrl` (the Foundry
account name and its Claude Messages API base URL — `ANTHROPIC_FOUNDRY_RESOURCE` in
`.helios/azure.env`; empty strings when an existing account was supplied), plus
`fleetVmssName` / `fleetVmssPrincipalId` (both empty
strings while the fleet VMSS is disabled — consumed by `scripts/fleet/scale-fleet.ps1`
and by role assignments for cloud lanes respectively) and `aiSearchEndpoint` /
`aiSearchConnectionName` / `aiSearchServiceId` (empty strings while the AI Search
connection is disabled). Secrets are never output.
Wire the endpoints into the AIHub via
`.env` (see `.env.template`: `AZURE_OPENAI_ENDPOINT`, `ANTHROPIC_FOUNDRY_RESOURCE`,
`AZURE_FOUNDRY_PROJECT_ENDPOINT`, `AZURE_KEY_VAULT_URI`).
