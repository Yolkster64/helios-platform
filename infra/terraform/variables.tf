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
