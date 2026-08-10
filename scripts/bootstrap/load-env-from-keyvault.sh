#!/usr/bin/env bash
# Pull AIHub provider secrets from Azure Key Vault into environment variables.
#
# MUST be sourced ('source scripts/bootstrap/load-env-from-keyvault.sh') — exports
# from a child process cannot reach your shell. Secrets go only into process
# environment, never onto disk, matching the repo's no-secrets policy.
#
# Secret names match what infra/main.bicep provisions; env-var names match what
# config/aihub.json declares. Missing secrets are skipped silently — providers
# without keys simply stay Unconfigured, which the AIHub treats as routine.
#
# Requires: az login (scripts/bootstrap/connect-azure.sh) and AZURE_KEY_VAULT_URI,
# e.g. AZURE_KEY_VAULT_URI=https://<vault>.vault.azure.net/
set -uo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "error: this script must be sourced, not executed:" >&2
  echo "  source scripts/bootstrap/load-env-from-keyvault.sh" >&2
  exit 1
fi

if [[ -z "${AZURE_KEY_VAULT_URI:-}" ]]; then
  echo "error: AZURE_KEY_VAULT_URI is not set (e.g. https://<vault>.vault.azure.net/)." >&2
  return 1
fi
if ! command -v az >/dev/null 2>&1 || ! az account show >/dev/null 2>&1; then
  echo "error: az is not logged in — run scripts/bootstrap/connect-azure.sh first." >&2
  return 1
fi

_helios_vault_name="$(echo "$AZURE_KEY_VAULT_URI" | sed -E 's#https?://([^./]+).*#\1#')"

_helios_load_secret() {
  local secret_name="$1" env_name="$2" value
  if [[ -n "${!env_name:-}" ]]; then
    echo "  $env_name: already set, leaving as-is."
    return 0
  fi
  value="$(az keyvault secret show --vault-name "$_helios_vault_name" \
    --name "$secret_name" --query value --output tsv 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    export "$env_name"="$value"
    echo "  $env_name: loaded from Key Vault secret '$secret_name'."
  else
    echo "  $env_name: secret '$secret_name' not found — provider stays Unconfigured."
  fi
}

echo "Loading AIHub secrets from vault '$_helios_vault_name'..."
_helios_load_secret openai-api-key OPENAI_API_KEY
_helios_load_secret anthropic-api-key ANTHROPIC_API_KEY
_helios_load_secret github-models-token GITHUB_MODELS_TOKEN

unset -f _helios_load_secret
unset _helios_vault_name
