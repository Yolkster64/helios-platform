#!/usr/bin/env bash
# GitHub's preview-only lane. Only the explicit "preview" mode invokes Azure CLI.
# Never source a downloaded script, change CLI subscription, create a group, or apply.
set -euo pipefail
export LC_ALL=C

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 2
}

valid_id() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

check_inputs() {
  [[ "${HELIOS_WHAT_IF:-}" == true ]] || fail 'Deployment is disabled; what_if must be true. There is no apply switch.'
  [[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]] || fail 'Only an explicit workflow_dispatch may preview Azure.'
  [[ "${GITHUB_REPOSITORY:-}" == Yolkster64/helios-platform ]] || fail 'The preview source must be Yolkster64/helios-platform.'
  [[ "${GITHUB_REF:-}" == refs/heads/main ]] || fail 'The preview source must be trusted main.'
  [[ "${HELIOS_AZURE_PREVIEW_ENABLED:-}" == true ]] || fail 'Azure preview is disabled. Review azure-dev protection and identity before enabling HELIOS_AZURE_PREVIEW_ENABLED.'
  valid_id "${AZURE_TENANT_ID:-}" || fail 'An explicit UUID AZURE_TENANT_ID is required.'
  valid_id "${AZURE_SUBSCRIPTION_ID:-}" || fail 'An explicit UUID AZURE_SUBSCRIPTION_ID is required.'
  [[ "${AZURE_RESOURCE_GROUP:-}" =~ ^[-a-zA-Z0-9_.()]{1,90}$ && "$AZURE_RESOURCE_GROUP" != *. ]] || fail 'An explicit existing AZURE_RESOURCE_GROUP is required (1-90 ASCII letters, digits, hyphens, underscores, periods or parentheses; no trailing period).'
}

check_binding() {
  check_inputs
  valid_id "${AZURE_CLIENT_ID:-}" || fail 'azure-dev must bind a preview-only AZURE_CLIENT_ID.'
  valid_id "${AZURE_BOUND_TENANT_ID:-}" || fail 'azure-dev must bind AZURE_TENANT_ID.'
  valid_id "${AZURE_BOUND_SUBSCRIPTION_ID:-}" || fail 'azure-dev must bind AZURE_SUBSCRIPTION_ID.'
  [[ -n "${AZURE_BOUND_RESOURCE_GROUP:-}" ]] || fail 'azure-dev must bind AZURE_RESOURCE_GROUP.'
  [[ "${AZURE_TENANT_ID,,}" == "${AZURE_BOUND_TENANT_ID,,}" ]] || fail 'Requested tenant differs from the azure-dev binding.'
  [[ "${AZURE_SUBSCRIPTION_ID,,}" == "${AZURE_BOUND_SUBSCRIPTION_ID,,}" ]] || fail 'Requested subscription differs from the azure-dev binding.'
  [[ "${AZURE_RESOURCE_GROUP,,}" == "${AZURE_BOUND_RESOURCE_GROUP,,}" ]] || fail 'Requested resource group differs from the azure-dev binding.'
}

preview() {
  check_binding
  command -v az >/dev/null 2>&1 || fail 'Azure CLI is required for preview.'
  local active_subscription active_tenant account_state group_id expected_group_id preview_root
  active_subscription="$(az account show --query id --output tsv --only-show-errors)"
  active_tenant="$(az account show --query tenantId --output tsv --only-show-errors)"
  account_state="$(az account show --query state --output tsv --only-show-errors)"
  [[ "${active_subscription,,}" == "${AZURE_SUBSCRIPTION_ID,,}" ]] || fail 'Authenticated subscription does not match the request.'
  [[ "${active_tenant,,}" == "${AZURE_TENANT_ID,,}" ]] || fail 'Authenticated tenant does not match the request.'
  [[ "$account_state" == Enabled ]] || fail 'Authenticated subscription is not Enabled.'
  expected_group_id="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}"
  group_id="$(az group show --subscription "$AZURE_SUBSCRIPTION_ID" --name "$AZURE_RESOURCE_GROUP" --query id --output tsv --only-show-errors)"
  [[ "${group_id,,}" == "${expected_group_id,,}" ]] || fail 'Existing resource-group ID differs from the explicit target.'
  preview_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
  [[ -f "$preview_root/infra/main.bicep" && -f "$preview_root/infra/main.bicepparam" ]] || fail 'Trusted checked-in Bicep template and parameters are required.'

  # Azure CLI 2.76+ supports ProviderNoRbac. It checks resource read permissions,
  # not hypothetical deployment privileges. Actual preview permission is still required.
  az deployment group validate \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --template-file "$preview_root/infra/main.bicep" \
    --parameters "$preview_root/infra/main.bicepparam" \
    --validation-level ProviderNoRbac --only-show-errors --output none
  az deployment group what-if \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --template-file "$preview_root/infra/main.bicep" \
    --parameters "$preview_root/infra/main.bicepparam" \
    --validation-level ProviderNoRbac \
    --result-format ResourceIdOnly --no-pretty-print --only-show-errors --output json
}

[[ $# == 1 ]] || fail 'Expected exactly one mode: check-inputs, check-binding, or preview.'
case "$1" in
  check-inputs) check_inputs ;;
  check-binding) check_binding ;;
  preview) preview ;;
  *) fail 'Unknown mode; only check-inputs, check-binding, and preview are supported.' ;;
esac
