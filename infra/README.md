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
az group create -n helios-core-rg -l centralus
az deployment group what-if -g helios-core-rg \
  --template-file infra/main.bicep --parameters infra/main.bicepparam
az deployment group create -g helios-core-rg \
  --template-file infra/main.bicep --parameters infra/main.bicepparam
```

Provider keys are passed as secure parameters at deploy time (never committed):

```bash
az deployment group create -g helios-core-rg \
  --template-file infra/main.bicep --parameters infra/main.bicepparam \
  --parameters anthropicApiKey="$ANTHROPIC_API_KEY" openaiApiKey="$OPENAI_API_KEY"
```

CI: `.github/workflows/infra-validate.yml` compiles + lints the Bicep, checks
`arm/main.json` freshness against it, and runs `terraform fmt`/`validate` on every PR
touching `infra/**` (all offline, no subscription). `.github/workflows/helios-deploy.yml` deploys on push to `main`
(or dispatch with a what-if option) and skips gracefully when the `AZURE_CLIENT_ID` /
`AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` OIDC secrets are absent.

## Outputs

`aiServicesEndpoint`, `openAiEndpoint`, `projectEndpoint`, `projectId`, `keyVaultUri`,
`modelDeploymentNames`. Secrets are never output. Wire the endpoints into the AIHub via
`.env` (see `.env.template`: `AZURE_OPENAI_ENDPOINT`, `AZURE_FOUNDRY_PROJECT_ENDPOINT`,
`AZURE_KEY_VAULT_URI`).
