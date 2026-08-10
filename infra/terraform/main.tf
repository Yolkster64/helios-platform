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
}

# Key Vault Secrets User — read secret contents via RBAC.
resource "azurerm_role_assignment" "key_vault_secrets_user" {
  count = var.principal_id != "" ? 1 : 0

  scope              = azurerm_key_vault.main.id
  role_definition_id = "${local.role_definition_prefix}/${local.key_vault_secrets_user_role_id}"
  principal_id       = var.principal_id
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

# ---------------------------------------------------------------------------
# Fleet burst VMSS (modules/fleet-vmss.bicep) — opt-in cloud fleet-worker lanes
# ---------------------------------------------------------------------------

locals {
  # Doubly gated like the Bicep (deployFleetVmss && vmssAdminPublicKey != ''):
  # SSH-key-only auth means a VMSS without a key would be undeployable anyway.
  # vmss_admin_public_key is NOT sensitive (public keys are not secrets), so —
  # unlike the API-key emptiness checks above — no nonsensitive() unwrap is
  # needed to use it in a count.
  fleet_vmss_enabled = var.deploy_fleet_vmss && var.vmss_admin_public_key != ""
  fleet_vmss_name    = "vmss-helios-${local.unique_suffix}"

  # Mirrors the module defaults in modules/fleet-vmss.bicep (not surfaced as
  # main.bicep parameters, so locals here, not variables).
  fleet_vnet_address_prefix   = "10.44.0.0/24"
  fleet_subnet_address_prefix = "10.44.0.0/24"

  # cloud-init: lane toolchain (dotnet-runtime-8.0, python3, pwsh via snap), an
  # anonymous clone of the public repo, and fleet_workers_per_instance stub
  # fleet workers as systemd template units honoring the HERMES_KANBAN_* lane
  # contract against a local seed board. HERMES_KANBAN_MAX_IDLE_POLLS=0 makes
  # cloud lanes poll forever — scale-in is autoscale's job, not the worker's
  # idle exit. NO secrets in cloud-init.
  fleet_cloud_init = <<-CLOUDINIT
    #cloud-config
    package_update: true
    packages:
      - git
      - python3
      - dotnet-runtime-8.0
    write_files:
      - path: /etc/systemd/system/helios-fleet-worker@.service
        permissions: '0644'
        content: |
          [Unit]
          Description=HELIOS fleet worker lane %i (cloud-burst stub)
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=simple
          User=heliosfleet
          WorkingDirectory=/opt/helios/src/ai/python
          Environment=HELIOS_FLEET_POOL=${var.fleet_pool}
          Environment=HERMES_KANBAN_DB=/var/lib/helios-fleet/boards/${var.fleet_pool}.json
          Environment=HERMES_KANBAN_CLAIM_LOCK=/var/lib/helios-fleet/boards/${var.fleet_pool}.json.lock
          Environment=HERMES_KANBAN_TASK=*
          Environment=HERMES_KANBAN_RUN_ID=${var.fleet_pool}-%H
          Environment=HERMES_KANBAN_ASSIGNEE=%H-lane-%i
          Environment=HERMES_KANBAN_MAX_IDLE_POLLS=0
          ExecStart=/usr/bin/python3 -m helios_agents.fleet_worker
          Restart=always
          RestartSec=5

          [Install]
          WantedBy=multi-user.target
      - path: /var/lib/helios-fleet/boards/${var.fleet_pool}.json
        permissions: '0664'
        content: |
          { "tasks": [] }
    runcmd:
      - snap install powershell --classic
      - useradd --system --create-home --shell /usr/sbin/nologin heliosfleet
      - git clone --depth 1 --branch ${var.fleet_repo_ref} ${var.fleet_repo_url} /opt/helios
      - chown -R heliosfleet:heliosfleet /var/lib/helios-fleet
      - systemctl daemon-reload
      - for i in $(seq 1 ${var.fleet_workers_per_instance}); do systemctl enable --now helios-fleet-worker@$i.service; done
  CLOUDINIT
}

# NSG default rules deny all inbound from the internet; the Bicep module's
# optional operator-SSH rule maps to a main.bicep-level knob that does not
# exist, so this mirror ships the default-deny NSG only.
resource "azurerm_network_security_group" "fleet" {
  count = local.fleet_vmss_enabled ? 1 : 0

  name                = "${local.fleet_vmss_name}-nsg"
  location            = local.effective_location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_virtual_network" "fleet" {
  count = local.fleet_vmss_enabled ? 1 : 0

  name                = "${local.fleet_vmss_name}-vnet"
  location            = local.effective_location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = [local.fleet_vnet_address_prefix]
  tags                = var.tags
}

resource "azurerm_subnet" "fleet" {
  count = local.fleet_vmss_enabled ? 1 : 0

  name                 = "fleet"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = one(azurerm_virtual_network.fleet[*].name)
  address_prefixes     = [local.fleet_subnet_address_prefix]
}

# Flexible orchestration (Bicep: orchestrationMode 'Flexible'), Ubuntu 24.04
# LTS Gen2, SSH-key-only, system-assigned identity. azapi rather than
# azurerm_orchestrated_virtual_machine_scale_set because that resource's
# identity block is UserAssigned-only and cannot express the SystemAssigned
# identity the Bicep module carries (same azapi-where-azurerm-falls-short
# pattern as the Foundry account above). The per-instance Standard public IP is
# for OUTBOUND access only (NSG blocks inbound; default outbound access is
# retired for new deployments) and — unlike a NAT gateway — costs nothing while
# the set is scaled to zero. sku.capacity only seeds initial capacity: the
# autoscale setting below owns the instance count afterwards, so a re-apply
# resetting capacity toward the floor is benign and reconciled by autoscale
# (identical behavior to redeploying the Bicep).
resource "azapi_resource" "fleet_vmss" {
  count = local.fleet_vmss_enabled ? 1 : 0

  type      = "Microsoft.Compute/virtualMachineScaleSets@2024-07-01"
  name      = local.fleet_vmss_name
  parent_id = data.azurerm_resource_group.main.id
  location  = local.effective_location
  tags      = var.tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name     = var.fleet_vm_sku
      tier     = "Standard"
      capacity = var.fleet_burst_min_instances
    }
    properties = {
      orchestrationMode        = "Flexible"
      platformFaultDomainCount = 1
      virtualMachineProfile = {
        osProfile = {
          computerNamePrefix = "hfleet"
          adminUsername      = var.vmss_admin_username
          customData         = base64encode(local.fleet_cloud_init)
          linuxConfiguration = {
            disablePasswordAuthentication = true
            ssh = {
              publicKeys = [
                {
                  path    = "/home/${var.vmss_admin_username}/.ssh/authorized_keys"
                  keyData = var.vmss_admin_public_key
                }
              ]
            }
          }
        }
        storageProfile = {
          imageReference = {
            # Ubuntu 24.04 LTS (noble); the 'server' SKU of this offer is Gen2 x64.
            publisher = "Canonical"
            offer     = "ubuntu-24_04-lts"
            sku       = "server"
            version   = "latest"
          }
          osDisk = {
            createOption = "FromImage"
            caching      = "ReadWrite"
            managedDisk = {
              storageAccountType = "StandardSSD_LRS"
            }
          }
        }
        networkProfile = {
          # Required for Flexible orchestration.
          networkApiVersion = "2020-11-01"
          networkInterfaceConfigurations = [
            {
              name = "${local.fleet_vmss_name}-nic"
              properties = {
                primary = true
                networkSecurityGroup = {
                  id = one(azurerm_network_security_group.fleet[*].id)
                }
                ipConfigurations = [
                  {
                    name = "ipconfig1"
                    properties = {
                      primary = true
                      subnet = {
                        id = one(azurerm_subnet.fleet[*].id)
                      }
                      publicIPAddressConfiguration = {
                        name = "${local.fleet_vmss_name}-pip"
                        sku = {
                          name = "Standard"
                        }
                        properties = {
                          idleTimeoutInMinutes = 15
                        }
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    }
  }

  response_export_values = ["identity.principalId"]
}

# CPU proxy for lane pressure: >70% for 5 min -> +1; <25% for
# fleet_scale_down_idle_seconds -> -1. Queue-depth-driven scaling
# (scaleUpQueueDepth in config/fleet/fleet-topology.json) arrives via
# scripts/fleet/scale-fleet.ps1 calling `az vmss scale` — Azure autoscale
# cannot see board queue depth without custom metrics in Application Insights,
# which is out of scope here.
resource "azurerm_monitor_autoscale_setting" "fleet" {
  count = local.fleet_vmss_enabled ? 1 : 0

  name                = "${local.fleet_vmss_name}-autoscale"
  location            = local.effective_location
  resource_group_name = data.azurerm_resource_group.main.name
  target_resource_id  = one(azapi_resource.fleet_vmss[*].id)
  enabled             = true
  tags                = var.tags

  profile {
    name = "fleet-burst"

    capacity {
      minimum = var.fleet_burst_min_instances
      maximum = var.fleet_burst_max_instances
      default = var.fleet_burst_min_instances
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        metric_resource_id = one(azapi_resource.fleet_vmss[*].id)
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
        metric_resource_id = one(azapi_resource.fleet_vmss[*].id)
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = format("PT%dS", var.fleet_scale_down_idle_seconds)
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = format("PT%dS", var.fleet_scale_down_idle_seconds)
      }
    }
  }
}
