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
- `modules/ai-foundry-account.bicep` — Foundry account + serialized model deployments + Azure AI User role
- `modules/ai-foundry-project.bicep` — Foundry project (endpoint output)
- `modules/keyvault.bicep` — RBAC Key Vault + conditional `anthropic-api-key` / `openai-api-key` / `github-models-token` secrets

## Three dialects

The same stack exists in three IaC dialects with distinct roles:

- **Bicep** (`main.bicep` + `modules/`) — the **source of truth** and the deployment of
  record. All changes start here; `helios-deploy.yml` deploys from it.
- **ARM JSON** (`arm/main.json`) — a **generated artifact** compiled from the Bicep
  (never hand-edited; see `arm/README.md`) for ARM-only surfaces: pipelines without a
  Bicep toolchain and Azure portal "Deploy a custom template". CI fails if it drifts
  from the Bicep source.
- **Terraform** (`terraform/`) — an **independent mirror** of the same design for
  TF-native shops. Its resources are deliberately named differently from the Bicep
  stack's; deploy it into its own resource group and never point both dialects at one
  RG — neither tracks the other's state, so they would fight over the same resources.

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
touching `infra/**` (all offline, no subscription). `.github/workflows/helios-deploy.yml` deploys on push to `main`
(or dispatch with a what-if option) and skips gracefully when the `AZURE_CLIENT_ID` /
`AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` Actions variables are absent — see the
next section for how those come to exist without any stored secret.

## OIDC identity (GitHub Actions → Azure)

`helios-deploy.yml` authenticates with **federated identity — no cloud credential is
stored anywhere**: not in the repo, not in GitHub secrets. A one-time, re-runnable
bootstrap (`scripts/bootstrap/azure-oidc-setup.sh`, PowerShell twin
`azure-oidc-setup.ps1` wrapping the same az calls) creates:

- App registration **`helios-github-deploy`** + service principal — with **no client
  secret**, so there is nothing to leak, expire, or rotate.
- Three **federated credentials** (issuer `https://token.actions.githubusercontent.com`,
  audience `api://AzureADTokenExchange`) trusting exactly these subjects:

  | Subject | Used by |
  |---|---|
  | `repo:Yolkster64/helios-platform:ref:refs/heads/main` | `helios-deploy.yml` on push to `main` and `workflow_dispatch` runs *from* `main` (a dispatch from another branch presents that branch's ref and fails login) |
  | `repo:Yolkster64/helios-platform:pull_request` | any future PR-triggered job that needs Azure (infra PR validation deliberately stays offline) |
  | `repo:Yolkster64/helios-platform:environment:production` | pre-provisioned for adding `environment: production` (an approval gate) to the deploy job — a job that declares an environment presents this subject *instead of* the branch one |

- **`Contributor` scoped to `rg-helios-ai` only** — enough to run
  `az deployment group create` for this template; deliberately not subscription-wide,
  so the identity cannot create resource groups, touch other workloads, or assign
  roles. Narrowing further (e.g. per-resource data roles) breaks template deployment
  itself, which needs control-plane writes across the RG.
- **`Key Vault Secrets Officer` scoped to `kv-helios-jcut` only** — `main.bicep`
  conditionally creates `Microsoft.KeyVault/vaults/secrets` on an RBAC-mode vault,
  and ARM authorizes those writes against *data-plane* RBAC, so `Contributor` alone
  fails with Forbidden the moment a secure param (`anthropicApiKey`, …) is passed.

At run time the workflow's `permissions: id-token: write` lets the runner mint a
short-lived GitHub OIDC token; `azure/login@v2` exchanges it for an Entra token that
expires in minutes and never exists outside the run. The three values the workflow
needs — `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` — are
identifiers, not secrets; set them as **Actions variables** (the script prints the
exact `gh variable set` one-liners). The workflow targets `rg-helios-ai` (override
with the `AZURE_RESOURCE_GROUP` / `AZURE_LOCATION` repo variables) and only attempts
`az group create` when the RG is missing, since the RG-scoped principal cannot
create it.

Boundaries and operations:

- **One-time elevated clicks:** the bootstrap must run as a human who can create app
  registrations (Application Developer or the tenant's default user setting) and
  assign roles on the two scopes (Owner or User Access Administrator on
  `rg-helios-ai`). CI itself never needs those rights.
- **CI never passes `principalId`** to the template: the role assignments it would
  create require rights beyond `Contributor`; personal RBAC grants are the
  interactive `azure-up.sh` path's job.
- **Rotation / revocation:** there is no secret to rotate. To revoke, delete the app
  (`az ad app delete --id <AZURE_CLIENT_ID>`) — deploys stop immediately. To
  re-establish, re-run `azure-oidc-setup.sh` and update the `AZURE_CLIENT_ID`
  variable (a recreated app has a new appId).
- **Verify:** `az role assignment list --assignee <AZURE_CLIENT_ID> --all -o table`,
  then dispatch the workflow from `main` with `what_if=true` as a read-only
  rehearsal before letting a push deploy.

## Outputs

`aiServicesEndpoint`, `openAiEndpoint`, `projectEndpoint`, `projectId`, `keyVaultUri`,
`modelDeploymentNames`. Secrets are never output. Wire the endpoints into the AIHub via
`.env` (see `.env.template`: `AZURE_OPENAI_ENDPOINT`, `AZURE_FOUNDRY_PROJECT_ENDPOINT`,
`AZURE_KEY_VAULT_URI`).
