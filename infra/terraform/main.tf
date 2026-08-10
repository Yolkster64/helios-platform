# Terraform mirror of infra/main.bicep + infra/modules/*.bicep.
# Bicep remains the deployment of record; see README.md for the divergences
# (uniqueString naming, serial deployment batching).

data "azurerm_client_config" "current" {}

# The Bicep template is resource-group scoped; the mirror reads the existing
# group, it does not create it.
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

locals {
  # Bicep: substring(uniqueString(resourceGroup().id), 0, 4). ARM's uniqueString
  # hash is proprietary and cannot be reproduced in Terraform; substr(sha1(...), 0, 13)
  # is the deterministic-but-DIFFERENT analogue, so the two dialects produce
  # differently-named resources and must never manage the same deployment (README).
  unique_string = substr(sha1(data.azurerm_resource_group.main.id), 0, 13)
  unique_suffix = substr(local.unique_string, 0, 4)

  effective_location       = var.location != "" ? var.location : data.azurerm_resource_group.main.location
  effective_model_location = var.model_location != "" ? var.model_location : local.effective_location

  account_name             = lower("${var.ai_services_name}${local.unique_suffix}")
  project_name             = lower(var.ai_project_name)
  effective_key_vault_name = var.key_vault_name != "" ? var.key_vault_name : "kv-helios-${local.unique_suffix}"

  # BYO account short-circuit: when an existing account ID is supplied, no
  # account, deployments, or project are created (mirrors main.bicep).
  ai_service_exists    = var.ai_service_account_resource_id != ""
  effective_account_id = local.ai_service_exists ? var.ai_service_account_resource_id : one(azapi_resource.foundry_account[*].id)

  # Primary quintet first, then the additional deployments (Bicep: allModelDeployments).
  # model_name defaults to the deployment name here because Bicep resolves
  # d.?modelName ?? d.name at the use site.
  all_model_deployments = concat(
    [
      {
        name       = var.model_name
        model_name = var.model_name
        format     = var.model_format
        version    = var.model_version
        sku_name   = var.model_sku_name
        capacity   = var.model_capacity
      }
    ],
    [
      for d in var.additional_model_deployments : {
        name       = d.name
        model_name = coalesce(d.model_name, d.name)
        format     = d.format
        version    = d.version
        sku_name   = d.sku_name
        capacity   = d.capacity
      }
    ]
  )

  # Bicep: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', <id>)
  role_definition_prefix            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions"
  azure_ai_user_role_id             = "53ca6127-db72-4b80-b1b0-d745d6d5456d" # Azure AI User
  key_vault_secrets_user_role_id    = "4633458b-17de-408a-b874-0445c86b69e6" # Key Vault Secrets User
  key_vault_secrets_officer_role_id = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7" # Key Vault Secrets Officer

  # Emptiness checks on the sensitive secret variables, unwrapped with
  # nonsensitive(): a count may not be derived from a sensitive value, and
  # whether a secret was supplied at all is not itself secret.
  anthropic_key_supplied = nonsensitive(var.anthropic_api_key != null && var.anthropic_api_key != "")
  openai_key_supplied    = nonsensitive(var.openai_api_key != null && var.openai_api_key != "")
  github_token_supplied  = nonsensitive(var.github_models_token != null && var.github_models_token != "")
  any_secret_supplied    = local.anthropic_key_supplied || local.openai_key_supplied || local.github_token_supplied
}

# ---------------------------------------------------------------------------
# Foundry account (modules/ai-foundry-account.bicep)
# ---------------------------------------------------------------------------

resource "azapi_resource" "foundry_account" {
  count = local.ai_service_exists ? 0 : 1

  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.account_name
  parent_id = data.azurerm_resource_group.main.id
  location  = local.effective_model_location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      publicNetworkAccess    = "Enabled"
    }
  }

  response_export_values = ["properties.endpoint"]
}

# Bicep creates these with @batchSize(1) because parallel creation races on
# account quota. Terraform cannot express per-resource batching for a
# dynamic-length collection, so reproduce the serial behavior with
# `terraform apply -parallelism=1` (see README.md).
resource "azapi_resource" "model_deployment" {
  for_each = { for d in local.all_model_deployments : d.name => d if !local.ai_service_exists }

  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = each.value.name
  parent_id = local.effective_account_id

  body = {
    sku = {
      name     = each.value.sku_name
      capacity = each.value.capacity
    }
    properties = {
      model = {
        format  = each.value.format
        name    = each.value.model_name
        version = each.value.version
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Foundry project (modules/ai-foundry-project.bicep)
# ---------------------------------------------------------------------------

resource "azapi_resource" "foundry_project" {
  count = local.ai_service_exists ? 0 : 1

  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.project_name
  parent_id = local.effective_account_id
  location  = local.effective_model_location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = var.ai_project_friendly_name
      description = var.ai_project_description
    }
  }
}

# ---------------------------------------------------------------------------
# Key Vault (modules/keyvault.bicep)
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "main" {
  name                = local.effective_key_vault_name
  location            = local.effective_location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  tags                = var.tags

  rbac_authorization_enabled = true
  # Bicep sets enableSoftDelete: true explicitly; in azurerm soft delete is
  # always on, only the retention window is configurable.
  soft_delete_retention_days = 90
}

# Secrets are only created when a non-empty value is supplied; nothing is ever output.

resource "azurerm_key_vault_secret" "anthropic_api_key" {
  count = local.anthropic_key_supplied ? 1 : 0

  name         = "anthropic-api-key"
  value        = var.anthropic_api_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer_deployer]
}

resource "azurerm_key_vault_secret" "openai_api_key" {
  count = local.openai_key_supplied ? 1 : 0

  name         = "openai-api-key"
  value        = var.openai_api_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer_deployer]
}

resource "azurerm_key_vault_secret" "github_models_token" {
  count = local.github_token_supplied ? 1 : 0

  name         = "github-models-token"
  value        = var.github_models_token
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer_deployer]
}

# ---------------------------------------------------------------------------
# Role assignments (RBAC grants from both Bicep modules)
# ---------------------------------------------------------------------------

# Azure AI User on the Foundry account — data-plane access to build/run against
# the account and its projects. Skipped for BYO accounts (the Bicep module that
# carries this assignment is not deployed then).
resource "azurerm_role_assignment" "ai_user" {
  count = !local.ai_service_exists && var.principal_id != "" ? 1 : 0

  scope              = one(azapi_resource.foundry_account[*].id)
  role_definition_id = "${local.role_definition_prefix}/${local.azure_ai_user_role_id}"
  principal_id       = var.principal_id
  principal_type     = "User"
}

# Key Vault Secrets User — read secret contents via RBAC.
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  count = var.principal_id != "" ? 1 : 0

  scope              = azurerm_key_vault.main.id
  role_definition_id = "${local.role_definition_prefix}/${local.key_vault_secrets_user_role_id}"
  principal_id       = var.principal_id
  principal_type     = "User"
}

# Key Vault Secrets Officer for the principal RUNNING terraform, only when any
# secret is being written: azurerm_key_vault_secret uses the data plane, and on
# an RBAC-mode vault Secrets User is read-only — without this grant the
# documented first apply 403s at the secret step. nonsensitive() unwraps only
# the emptiness check, never a value; Terraform rejects a count derived from a
# sensitive value otherwise.
resource "azurerm_role_assignment" "key_vault_secrets_officer_deployer" {
  count = local.any_secret_supplied ? 1 : 0

  scope              = azurerm_key_vault.main.id
  role_definition_id = "${local.role_definition_prefix}/${local.key_vault_secrets_officer_role_id}"
  principal_id       = data.azurerm_client_config.current.object_id
}
