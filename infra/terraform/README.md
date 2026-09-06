# HELIOS Azure AI Infrastructure — Terraform mirror

A Terraform mirror of the Bicep stack in `infra/` (`main.bicep` +
`modules/ai-foundry-account.bicep` / `ai-foundry-project.bicep` / `keyvault.bicep`),
for teams that operate Terraform-native pipelines.

**Bicep remains the deployment of record.** This directory is a faithful mirror for
TF-native shops, not a replacement: changes land in the Bicep first and are ported
here. If the two ever disagree, the Bicep wins.

## What it mirrors

| Bicep | Terraform |
|---|---|
| `Microsoft.CognitiveServices/accounts@2025-06-01` (kind `AIServices`, SystemAssigned identity, `allowProjectManagement`, custom subdomain, S0) | `azapi_resource.foundry_account` |
| `Microsoft.CognitiveServices/accounts/projects@2025-06-01` | `azapi_resource.foundry_project` |
| `Microsoft.CognitiveServices/accounts/deployments@2025-06-01` (primary quintet + `additionalModelDeployments`, every format except `Anthropic`) | `azapi_resource.model_deployment` (for_each) |
| `Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview` (Anthropic-format entries with the `modelProviderData` attestation — Claude in Foundry; skipped while `claudeOrganizationName` is empty) | `azapi_resource.claude_deployment` (for_each, `schema_validation_enabled = false` — the azapi analogue of the Bicep `BCP037` suppression) |
| `Microsoft.KeyVault/vaults@2024-11-01` (RBAC, standard, 90-day soft delete) + conditional secrets | `azurerm_key_vault.main` + `azurerm_key_vault_secret.*` |
| Azure AI User + Key Vault Secrets User role assignments (same role GUIDs, conditional on `principalId`) | `azurerm_role_assignment.*` |
| `aiServiceAccountResourceId` BYO short-circuit | `count` on the account/project resources + `local.effective_account_id` |
| `modules/fleet-vmss.bicep` (opt-in Flexible VMSS + vnet/NSG + CPU autoscale; `deployFleetVmss` gate) | `azapi_resource.fleet_vmss` + `azurerm_virtual_network`/`azurerm_subnet`/`azurerm_network_security_group` + `azurerm_monitor_autoscale_setting`, all `count`-gated on `local.fleet_vmss_enabled` |

Every Bicep parameter exists as a variable with the same name in snake_case
(`aiServicesName` → `ai_services_name`), the same default, and the same type;
`@secure()` parameters are `sensitive = true`. Outputs match `main.bicep`
one-for-one; secrets are never output.

Like the Bicep template, this configuration is resource-group scoped: it reads an
existing resource group (`var.resource_group_name`) and does not create it.

## Divergence: `uniqueString` naming — the two dialects MUST NOT share a deployment

The Bicep suffixes resource names with `substring(uniqueString(resourceGroup().id), 0, 4)`.
ARM's `uniqueString` is a proprietary hash that Terraform cannot reproduce. This mirror
uses `substr(sha1(<resource group id>), 0, 13)` as the deterministic analogue and takes
the same first 4 characters — deterministic for a given resource group, but a
**different value** than Bicep's.

Consequence: the two dialects generate **differently-named** accounts and Key Vaults
for the same resource group. They therefore describe two distinct deployments and must
never be pointed at the same one — do not `terraform import` the Bicep-created
resources, and do not run both stacks against one resource group expecting them to
converge.

## Divergence: serial model deployments

The Bicep creates model deployments with `@batchSize(1)` because parallel creation
races on account quota. Terraform has no per-resource batching for a dynamic-length
collection (`for_each` instances of one resource are created in parallel), so
reproduce the serial behavior with the global parallelism flag on any apply that
creates or replaces deployments:

```bash
terraform apply -parallelism=1 ...
```

Plans and applies that touch no deployments do not need the flag.

## Other minor divergences

- **Role assignment names.** Bicep names the two role assignments with ARM's
  deterministic `guid(scope, principalId, roleId)`; that hash is not reproducible in
  Terraform, so `azurerm_role_assignment` auto-generates its UUID name and Terraform
  state provides the idempotency instead. Role definition GUIDs, scope, and
  principal are identical. Neither dialect pins `principalType`: the deploying identity
  may be a user or a service principal (OIDC), and a hardcoded `User` fails the
  deployment for the latter.
- **`enableSoftDelete`.** Bicep sets it explicitly; the azurerm provider has no such
  argument because soft delete cannot be disabled — only
  `soft_delete_retention_days = 90` is set. Net effect is identical.
- **`location` default.** Bicep defaults to `resourceGroup().location`; a Terraform
  variable cannot default to a data-source value, so `location = ""` is the sentinel
  that resolves to the resource group's location in locals.
- **Secret write path.** `azurerm_key_vault_secret` writes via the data plane and
  stores the value in Terraform state (see the state warning below); ARM writes via
  the control plane and keeps no state.
- **Fleet VMSS via azapi.** `azurerm_orchestrated_virtual_machine_scale_set`'s
  `identity` block is UserAssigned-only and cannot express the SystemAssigned
  identity the Bicep module carries, so the scale set itself is an `azapi_resource`
  (same pattern as the Foundry account). The Bicep module's `sshSourceAddressPrefix`
  and vnet-prefix knobs are module-internal (not `main.bicep` parameters), so they
  appear here as locals, not variables.

## Quickstart

```bash
cd infra/terraform
terraform init
terraform plan \
  -var resource_group_name=helios-core-rg \
  -var "principal_id=$(az ad signed-in-user show --query id -o tsv)"
terraform apply -parallelism=1 \
  -var resource_group_name=helios-core-rg \
  -var "principal_id=$(az ad signed-in-user show --query id -o tsv)"
```

Add or resize models via `additional_model_deployments` (a
`{name, model_name?, format?, version, sku_name?, capacity?}` list, defaults
`OpenAI` / `GlobalStandard` / capacity 30), e.g. in a `*.tfvars` file.

Provider keys are passed at apply time and never committed — prefer `TF_VAR_*`
environment variables so keys stay out of shell history and state-file diffs on the
command line:

```bash
export TF_VAR_anthropic_api_key="$ANTHROPIC_API_KEY"
export TF_VAR_openai_api_key="$OPENAI_API_KEY"
```

Note that, as with any `azurerm_key_vault_secret`, supplied secret values are stored
in the Terraform state — protect the state accordingly (this is one more reason the
Bicep path, which has no state file, remains the deployment of record).

Offline validation (what CI would run — no backend, no subscription):

```bash
terraform init -backend=false
terraform validate
```

## Outputs

`ai_services_endpoint`, `open_ai_endpoint`, `project_endpoint`, `project_id`,
`key_vault_uri`, `ai_services_account_name`, `anthropic_foundry_base_url`,
`model_deployment_names`, `fleet_vmss_name`, `fleet_vmss_principal_id` — the same
names as the Bicep (the opt-in AI Search and learning-storage outputs are not mirrored). When
`ai_service_account_resource_id` is set (BYO account), account/project/deployment
outputs are empty, and the two fleet outputs are empty strings while
`deploy_fleet_vmss` is off, matching the Bicep behavior.
