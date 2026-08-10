# Same outputs as infra/main.bicep. Never output secrets.

output "ai_services_endpoint" {
  description = "Foundry account endpoint (empty when an existing account was supplied)."
  value       = local.ai_service_exists ? "" : try(one(azapi_resource.foundry_account[*].output).properties.endpoint, "")
}

output "open_ai_endpoint" {
  description = "Azure OpenAI-compatible endpoint on the Foundry account (empty when an existing account was supplied)."
  value       = local.ai_service_exists ? "" : "https://${local.account_name}.openai.azure.com/"
}

output "project_endpoint" {
  description = "Foundry project endpoint — the modern replacement for the legacy \"project connection string\"."
  value       = local.ai_service_exists ? "" : "https://${local.account_name}.services.ai.azure.com/api/projects/${local.project_name}"
}

output "project_id" {
  description = "Foundry project resource ID (empty when an existing account was supplied)."
  value       = local.ai_service_exists ? "" : one(azapi_resource.foundry_project[*].id)
}

output "key_vault_uri" {
  description = "Key Vault URI for provider API keys."
  value       = azurerm_key_vault.main.vault_uri
}

output "model_deployment_names" {
  description = "Names of all model deployments created on the account."
  value       = local.ai_service_exists ? [] : [for d in local.all_model_deployments : d.name]
}

output "fleet_vmss_name" {
  description = "Name of the fleet burst VM scale set — the az vmss scale target for scripts/fleet/scale-fleet.ps1 (empty string when the VMSS is disabled)."
  value       = local.fleet_vmss_enabled ? local.fleet_vmss_name : ""
}

output "fleet_vmss_principal_id" {
  description = "Principal ID of the fleet VMSS system-assigned identity — grant it roles (e.g. Key Vault Secrets User) if cloud lanes must read provider keys (empty string when the VMSS is disabled)."
  value       = local.fleet_vmss_enabled ? try(one(azapi_resource.fleet_vmss[*].identity[0].principal_id), "") : ""
}
