#!/usr/bin/env bash
# GitHub Actions -> Azure OIDC federation bootstrap (re-runnable).
#
# Creates the Entra ID pieces that let .github/workflows/helios-deploy.yml deploy
# infra/main.bicep with NO stored cloud credential anywhere:
#
#   * app registration "helios-github-deploy" + service principal — no client secret
#     is ever created, so there is nothing to leak or rotate;
#   * federated credentials trusting GitHub's OIDC issuer for exactly three subjects:
#     the repo's main branch, pull requests, and the "production" environment;
#   * Contributor scoped to the resource group ONLY (least privilege: the workflow
#     deploys one template into one RG — nothing subscription-wide, and the identity
#     cannot create resource groups or assign roles);
#   * Key Vault Secrets Officer scoped to the provider-key vault ONLY — main.bicep
#     conditionally creates Microsoft.KeyVault/vaults/secrets on an RBAC-mode vault,
#     and ARM authorizes those writes against DATA-plane RBAC, so Contributor alone
#     fails with Forbidden the moment a secure param (anthropicApiKey, ...) is passed.
#
# Finishes by printing the three GitHub Actions VARIABLES to set on the repo
# (identifiers, not secrets) and the gh CLI one-liners. Never prints or stores a
# secret. Safe to re-run: every step checks for the existing object before creating.
#
# Run as a user who can create app registrations (Application Developer role or the
# tenant's default user setting) AND assign roles on the scopes below (Owner or User
# Access Administrator on the resource group).
#
# Usage:
#   scripts/bootstrap/azure-oidc-setup.sh                 # defaults below
#   scripts/bootstrap/azure-oidc-setup.sh -g my-rg --repo me/fork --subscription <id>
set -euo pipefail

app_name="helios-github-deploy"
repo="Yolkster64/helios-platform"
subscription="784565d3-c82a-4dba-b947-fc354c08a89d"
resource_group="rg-helios-ai"
key_vault="kv-helios-jcut"
environment="production"
issuer="https://token.actions.githubusercontent.com"
audience="api://AzureADTokenExchange"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--app-name) app_name="${2:?--app-name needs a value}"; shift 2 ;;
    --repo) repo="${2:?--repo needs a value}"; shift 2 ;;
    --subscription) subscription="${2:?--subscription needs a value}"; shift 2 ;;
    -g|--resource-group) resource_group="${2:?--resource-group needs a value}"; shift 2 ;;
    --key-vault) key_vault="${2:?--key-vault needs a value}"; shift 2 ;;
    --environment) environment="${2:?--environment needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if ! az account show --output none 2>/dev/null; then
  echo "error: not logged in — run az login (or scripts/bootstrap/connect-azure.sh) first." >&2
  exit 1
fi
az account set --subscription "$subscription"
tenant_id="$(az account show --query tenantId --output tsv)"

# The role scope must exist before we grant on it; the RG is created by the stack
# bring-up (scripts/bootstrap/azure-up.sh), not by CI.
if ! az group show --name "$resource_group" --output none 2>/dev/null; then
  echo "error: resource group $resource_group not found in subscription $subscription." >&2
  echo "       Deploy the stack first (scripts/bootstrap/azure-up.sh) or pass -g <rg>." >&2
  exit 1
fi

# --- App registration (idempotent) ------------------------------------------------
app_id="$(az ad app list --display-name "$app_name" --query "[0].appId" --output tsv)"
if [[ -z "$app_id" ]]; then
  echo "Creating app registration $app_name..."
  app_id="$(az ad app create --display-name "$app_name" --sign-in-audience AzureADMyOrg \
    --query appId --output tsv)"
else
  echo "App registration $app_name exists (appId $app_id)."
  dup_count="$(az ad app list --display-name "$app_name" --query "length(@)" --output tsv)"
  if [[ "$dup_count" -gt 1 ]]; then
    echo "warning: $dup_count app registrations named $app_name; using appId $app_id." >&2
  fi
fi

# --- Service principal (idempotent) -----------------------------------------------
sp_id="$(az ad sp list --filter "appId eq '$app_id'" --query "[0].id" --output tsv)"
if [[ -z "$sp_id" ]]; then
  echo "Creating service principal for $app_name..."
  sp_id="$(az ad sp create --id "$app_id" --query id --output tsv)"
else
  echo "Service principal exists (objectId $sp_id)."
fi

# --- Federated credentials (idempotent, matched on subject) -----------------------
# The subject string must match what the workflow run presents EXACTLY, or login
# fails with AADSTS70021/700213. A job that declares `environment:` presents the
# environment subject instead of the branch one.
existing_subjects="$(az ad app federated-credential list --id "$app_id" \
  --query "[].subject" --output tsv)"

ensure_fic() { # name subject description
  local name="$1" subject="$2" description="$3" params_file
  if grep -Fxq "$subject" <<<"$existing_subjects"; then
    echo "Federated credential for $subject exists."
    return 0
  fi
  echo "Creating federated credential $name ($subject)..."
  params_file="$(mktemp)"
  printf '{"name":"%s","issuer":"%s","subject":"%s","audiences":["%s"],"description":"%s"}\n' \
    "$name" "$issuer" "$subject" "$audience" "$description" > "$params_file"
  az ad app federated-credential create --id "$app_id" --parameters "@$params_file" --output none
  rm -f "$params_file"
}

ensure_fic "github-main" "repo:${repo}:ref:refs/heads/main" \
  "helios-deploy.yml on push/dispatch from main"
ensure_fic "github-pull-request" "repo:${repo}:pull_request" \
  "PR-triggered jobs that need Azure (infra PR validation stays offline)"
ensure_fic "github-env-${environment}" "repo:${repo}:environment:${environment}" \
  "jobs declaring environment: ${environment}"

# --- Role assignments (idempotent, retried) ---------------------------------------
ensure_role() { # role scope
  local role="$1" scope="$2" attempt
  if [[ -n "$(az role assignment list --assignee "$sp_id" --role "$role" --scope "$scope" \
        --query "[0].id" --output tsv)" ]]; then
    echo "'$role' on $scope already assigned."
    return 0
  fi
  echo "Assigning '$role' on $scope..."
  for attempt in 1 2 3 4 5; do
    # --assignee-object-id + --assignee-principal-type skips the Graph lookup a
    # just-created SP can fail; ARM itself is still eventually consistent
    # (PrincipalNotFound), so retry with backoff instead of failing once.
    if az role assignment create --assignee-object-id "$sp_id" \
         --assignee-principal-type ServicePrincipal \
         --role "$role" --scope "$scope" --output none; then
      return 0
    fi
    echo "  retry $attempt/5 (Entra/RBAC replication)..." >&2
    sleep $((attempt * 5))
  done
  echo "error: failed to assign '$role' on $scope after 5 attempts." >&2
  return 1
}

rg_scope="/subscriptions/${subscription}/resourceGroups/${resource_group}"
ensure_role "Contributor" "$rg_scope"

vault_id="$(az keyvault show --name "$key_vault" --resource-group "$resource_group" \
  --query id --output tsv 2>/dev/null || true)"
if [[ -n "$vault_id" ]]; then
  ensure_role "Key Vault Secrets Officer" "$vault_id"
else
  echo "warning: Key Vault $key_vault not found in $resource_group — skipping the" >&2
  echo "         Key Vault Secrets Officer grant. Re-run this script once the vault" >&2
  echo "         exists if deploys pass provider API keys (main.bicep writes them as" >&2
  echo "         vault secrets, which needs data-plane RBAC on an RBAC-mode vault)." >&2
fi

# --- Wiring instructions (identifiers only — never secrets) -----------------------
echo
echo "Done. No client secret was created at any point in this setup."
echo
echo "Set these on ${repo} as GitHub Actions VARIABLES (identifiers, not secrets):"
echo "  AZURE_CLIENT_ID       = $app_id"
echo "  AZURE_TENANT_ID       = $tenant_id"
echo "  AZURE_SUBSCRIPTION_ID = $subscription"
echo
echo "gh CLI one-liners:"
echo "  gh variable set AZURE_CLIENT_ID       --repo $repo --body \"$app_id\""
echo "  gh variable set AZURE_TENANT_ID       --repo $repo --body \"$tenant_id\""
echo "  gh variable set AZURE_SUBSCRIPTION_ID --repo $repo --body \"$subscription\""
echo
echo "Verify the grants with:"
echo "  az role assignment list --assignee $app_id --all --output table"
echo
echo "Then run 'Helios Platform Deploy' via workflow_dispatch FROM main (the federated"
echo "subject is branch-scoped) with what_if=true for a read-only rehearsal."
