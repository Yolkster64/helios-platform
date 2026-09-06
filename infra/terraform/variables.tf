# One variable per infra/main.bicep parameter, same names converted to snake_case,
# same defaults, same types. @secure() parameters are sensitive = true.

variable "resource_group_name" {
  description = "Existing resource group to deploy into. The Bicep template is resource-group scoped; this mirror reads the group, it does not create it."
  type        = string
}

variable "ai_services_name" {
  description = "Base name for the Azure AI Services (Foundry) account; a unique suffix is appended."
  type        = string
  default     = "helios-ai"

  validation {
    condition     = length(var.ai_services_name) >= 2 && length(var.ai_services_name) <= 12
    error_message = "ai_services_name must be 2-12 characters (Bicep @minLength(2)/@maxLength(12))."
  }
}

variable "ai_project_name" {
  description = "Name for the Foundry project."
  type        = string
  default     = "helios-project"
}

variable "ai_project_friendly_name" {
  description = "Friendly name for the Foundry project, shown in the Foundry portal."
  type        = string
  default     = "HELIOS AI Project"
}

variable "ai_project_description" {
  description = "Description of the Foundry project, shown in the Foundry portal."
  type        = string
  default     = "Multi-LLM hub project for the HELIOS platform."
}

variable "location" {
  description = "Azure region for all resources. Empty string means the resource group's location (Bicep default: resourceGroup().location, which Terraform cannot express as a static default)."
  type        = string
  default     = ""
}

variable "model_location" {
  description = "Region for the Foundry account when model availability requires a different region. Empty string means use location."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Set of tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "model_name" {
  description = "Model name for the primary deployment."
  type        = string
  default     = "gpt-5-mini"
}

variable "model_format" {
  description = "Model format for the primary deployment."
  type        = string
  default     = "OpenAI"
}

variable "model_version" {
  description = "Model version for the primary deployment."
  type        = string
  default     = "2025-08-07"
}

variable "model_sku_name" {
  description = "SKU name for the primary model deployment."
  type        = string
  default     = "GlobalStandard"
}

variable "model_capacity" {
  description = "Capacity for the primary model deployment, in thousands of tokens-per-minute."
  type        = number
  default     = 30
}

variable "additional_model_deployments" {
  description = "Additional model deployments beyond the primary one (multi-LLM surface)."
  type = list(object({
    # Deployment name (also the default model name).
    name = string
    # Model name if it differs from the deployment name (Bicep: d.?modelName ?? d.name,
    # resolved in locals because the default depends on `name`).
    model_name = optional(string)
    # Model format. Defaults to OpenAI.
    format = optional(string, "OpenAI")
    # Model version.
    version = string
    # Deployment SKU. Defaults to GlobalStandard.
    sku_name = optional(string, "GlobalStandard")
    # Deployment capacity in thousands of tokens-per-minute. Defaults to 30.
    capacity = optional(number, 30)
  }))
  default = [
    {
      name     = "text-embedding-3-small"
      version  = "1"
      capacity = 120
    }
  ]
}

variable "ai_service_account_resource_id" {
  description = "Full ARM resource ID of an existing Foundry/AI Services account. Empty string means create a new account (and project) here; when set, no account, deployments, or project are created — see README.md."
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Key Vault name for provider API keys. Empty string means a name is generated."
  type        = string
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key to store in Key Vault. Empty string means the secret is not created."
  type        = string
  default     = ""
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key to store in Key Vault. Empty string means the secret is not created."
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_models_token" {
  description = "GitHub token for GitHub Models to store in Key Vault. Empty string means the secret is not created."
  type        = string
  default     = ""
  sensitive   = true
}

variable "principal_id" {
  description = "Object ID of the principal granted Azure AI User and Key Vault Secrets User. Empty string means no role assignments are created."
  type        = string
  default     = ""
}

# --- Claude in Foundry: Azure Marketplace attestation (mirrors main.bicep) -----------

variable "claude_organization_name" {
  description = "Legal entity name sent to Anthropic as modelProviderData.organizationName with every Anthropic-format deployment (Azure Marketplace attestation — review the Anthropic Commercial Terms first). Empty string (the default) skips the Anthropic-format entries of additional_model_deployments: no Claude deployment is created or changed."
  type        = string
  default     = ""
}

variable "claude_country_code" {
  description = "Two-letter ISO country code of the organization using Claude, sent as modelProviderData.countryCode."
  type        = string
  default     = "US"

  validation {
    condition     = length(var.claude_country_code) == 2
    error_message = "claude_country_code must be exactly 2 characters (Bicep @minLength(2)/@maxLength(2))."
  }
}

variable "claude_industry" {
  description = "Industry of the organization using Claude, sent as modelProviderData.industry. Lowercase — the values the Foundry portal dropdown offers."
  type        = string
  default     = "technology"

  validation {
    condition     = contains(["technology", "finance", "healthcare", "education", "retail", "manufacturing", "government", "media", "other"], var.claude_industry)
    error_message = "claude_industry must be one of technology, finance, healthcare, education, retail, manufacturing, government, media, other (Bicep @allowed)."
  }
}

# --- Fleet burst VMSS (opt-in; mirrors the deployFleetVmss surface of main.bicep) ---

variable "deploy_fleet_vmss" {
  description = "Deploy the Hermes/Xcore fleet burst VM scale set (cloud fleet-worker lanes). OFF by default; also requires vmss_admin_public_key."
  type        = bool
  default     = false
}

variable "vmss_admin_username" {
  description = "Admin username on fleet VMSS instances. SSH-key-only; password auth is disabled."
  type        = string
  default     = "heliosadmin"
}

variable "vmss_admin_public_key" {
  description = "SSH public key for vmss_admin_username (e.g. contents of ~/.ssh/id_ed25519.pub). Deliberately NOT sensitive — public keys are not secrets, which also keeps the count gate free of nonsensitive() unwrapping. Empty string (the default) keeps the VMSS off even when deploy_fleet_vmss is true."
  type        = string
  default     = ""
}

variable "fleet_vm_sku" {
  description = "VM size for fleet burst instances."
  type        = string
  default     = "Standard_B2s"
}

variable "fleet_burst_min_instances" {
  description = "Autoscale floor and default instance count for the fleet VMSS. 0 = scale-to-zero when idle."
  type        = number
  default     = 0

  validation {
    condition     = var.fleet_burst_min_instances >= 0
    error_message = "fleet_burst_min_instances must be >= 0 (Bicep @minValue(0))."
  }
}

variable "fleet_burst_max_instances" {
  description = "Autoscale ceiling for the fleet VMSS — the topology default maxBurstLanes (config/fleet/fleet-topology.json)."
  type        = number
  default     = 5

  validation {
    condition     = var.fleet_burst_max_instances >= 1
    error_message = "fleet_burst_max_instances must be >= 1 (Bicep @minValue(1))."
  }
}

variable "fleet_scale_down_idle_seconds" {
  description = "Idle window in seconds before the fleet VMSS scales in — the topology default scaleDownIdleSeconds. Azure autoscale requires windows of at least 300 seconds."
  type        = number
  default     = 300

  validation {
    condition     = var.fleet_scale_down_idle_seconds >= 300 && var.fleet_scale_down_idle_seconds <= 43200
    error_message = "fleet_scale_down_idle_seconds must be 300-43200 (Bicep @minValue(300)/@maxValue(43200))."
  }
}

variable "fleet_workers_per_instance" {
  description = "Stub fleet worker lanes started per VMSS instance."
  type        = number
  default     = 2

  validation {
    condition     = var.fleet_workers_per_instance >= 1
    error_message = "fleet_workers_per_instance must be >= 1 (Bicep @minValue(1))."
  }
}

variable "fleet_pool" {
  description = "Pool name exported as HELIOS_FLEET_POOL on cloud lanes, so fleet outcomes attribute to the burst pool."
  type        = string
  default     = "cloud-burst"
}

variable "fleet_repo_url" {
  description = "Git repository cloned onto each VMSS instance. Must be public — cloud-init clones anonymously and never carries credentials."
  type        = string
  default     = "https://github.com/Yolkster64/helios-platform"
}

variable "fleet_repo_ref" {
  description = "Git ref (branch or tag) checked out on each VMSS instance."
  type        = string
  default     = "main"
}
