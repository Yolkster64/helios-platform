#!/usr/bin/env bash
# GitHub Actions -> Azure OIDC federation bootstrap (re-runnable).
#
# Creates the Entra ID pieces that let .github/workflows/helios-deploy.yml deploy
# infra/main.bicep with NO stored cloud credential anywhere:
#
#   * app registration "helios-github-deploy" + service principal — no client secret
#     is ever created, so there is nothing to leak or rotate;
#   * one federated credential trusting GitHub's OIDC issuer for the protected
#     azure-dev environment; production and branch trust are disabled;
#   * Contributor scoped to the resource group ONLY (least privilege: the workflow
#     deploys one template into one RG — nothing subscription-wide, and the identity
#     cannot create resource groups or assign roles);
#   * Key Vault Secrets Officer scoped to the provider-key vault ONLY — main.bicep
#     conditionally creates Microsoft.KeyVault/vaults/secrets on an RBAC-mode vault,
#     and ARM authorizes those writes against DATA-plane RBAC, so Contributor alone
#     fails with Forbidden the moment a secure param (anthropicApiKey, ...) is passed.
#
# Finishes by printing the five GitHub Actions VARIABLES to set on azure-dev
# (identifiers, not secrets) and the gh CLI one-liners. Never prints or stores a
# secret. Safe to re-run: every step checks for the existing object before creating.
#
# Run as a user who can create app registrations (Application Developer role or the
# tenant's default user setting) AND assign roles on the scopes below (Owner or User
# Access Administrator on the resource group).
#
# Usage:
#   scripts/bootstrap/azure-oidc-setup.sh --tenant <id> --subscription <id> \
#     --resource-group <rg> --key-vault <vault>       # read-only plan
#   Add --apply only after reviewing the target and planned permissions.
set -euo pipefail

app_name="helios-github-deploy"
repo="Yolkster64/helios-platform"
tenant=""
subscription=""
resource_group=""
key_vault=""
apply=false
environment="azure-dev"
issuer="https://token.actions.githubusercontent.com"
audience="api://AzureADTokenExchange"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--app-name) app_name="${2:?--app-name needs a value}"; shift 2 ;;
    --repo) repo="${2:?--repo needs a value}"; shift 2 ;;
    --apply) apply=true; shift ;;
    --tenant) tenant="${2:?--tenant needs a value}"; shift 2 ;;
    --subscription) subscription="${2:?--subscription needs a value}"; shift 2 ;;
    -g|--resource-group) resource_group="${2:?--resource-group needs a value}"; shift 2 ;;
    --key-vault) key_vault="${2:?--key-vault needs a value}"; shift 2 ;;
    --environment) environment="${2:?--environment needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$environment" != "azure-dev" ]]; then
  echo "error: only the protected azure-dev environment is supported; production is disabled." >&2
  exit 2
fi
if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "error: --repo must be an owner/repository name." >&2
  exit 2
fi

# A plan must not change the shared CLI account, identity, resources or permissions.
# Require the selected account to match: Graph/Entra commands use its active tenant.
for target in tenant subscription resource_group key_vault; do
  if [[ -z "${!target}" ]]; then
    echo "error: explicit --tenant, --subscription, --resource-group and --key-vault are required." >&2
    exit 2
  fi
done
if ! command -v az >/dev/null 2>&1; then
  echo "error: Azure CLI is not installed; install it, then authenticate interactively." >&2
  exit 2
fi
active_subscription="$(az account show --query id --output tsv)"
tenant_id="$(az account show --query tenantId --output tsv)"
account_state="$(az account show --query state --output tsv)"
if [[ "${active_subscription,,}" != "${subscription,,}" || "${tenant_id,,}" != "${tenant,,}" || "$account_state" != "Enabled" ]]; then
  echo "error: the active Azure subscription/tenant must match the explicit target and be Enabled." >&2
  echo "       Review az account list, authenticate to the intended tenant and select its subscription first." >&2
  exit 2
fi
rg_scope="/subscriptions/${subscription}/resourceGroups/${resource_group}"
rg_id="$(az group show --name "$resource_group" --subscription "$subscription" --query id --output tsv)"
vault_id="$(az keyvault show --name "$key_vault" --resource-group "$resource_group" --subscription "$subscription" --query id --output tsv)"
vault_tenant="$(az keyvault show --name "$key_vault" --resource-group "$resource_group" --subscription "$subscription" --query properties.tenantId --output tsv)"
vault_rbac="$(az keyvault show --name "$key_vault" --resource-group "$resource_group" --subscription "$subscription" --query properties.enableRbacAuthorization --output tsv)"
resource_location="$(az group show --name "$resource_group" --subscription "$subscription" --query location --output tsv)"
expected_vault="${rg_scope}/providers/Microsoft.KeyVault/vaults/${key_vault}"
if [[ -z "$resource_location" || "${rg_id,,}" != "${rg_scope,,}" || "${vault_id,,}" != "${expected_vault,,}" || "${vault_tenant,,}" != "${tenant,,}" || "${vault_rbac,,}" != "true" ]]; then
  echo "error: resource-group/vault identity, tenant or RBAC mode does not match the intended target." >&2
  exit 2
fi
# Duplicate display names must not silently select an arbitrary deploy principal.
app_count="$(az ad app list --display-name "$app_name" --query 'length(@)' --output tsv)"
if [[ "$app_count" != "0" && "$app_count" != "1" ]]; then
  echo "error: app registration lookup is ambiguous; choose a unique --app-name." >&2
  exit 2
fi
printf 'Azure OIDC plan\nTenant: %s\nSubscription: %s\nResource group: %s\nKey Vault: %s\nApp: %s\n' \
  "$tenant_id" "$subscription" "$rg_id" "$vault_id" "$app_name"
printf 'Trust: repo:%s:environment:%s\n' "$repo" "$environment"
printf 'Grants: Contributor on %s; Key Vault Secrets Officer on %s\n' "$rg_id" "$vault_id"
echo 'Apply removes legacy github-main, github-pull-request and github-env-production credentials if present.'
if [[ "$apply" != true ]]; then
  echo 'Plan only. No account, identity, permission or resource changes. Review before adding --apply.'
  exit 0
fi

# --- App registration (idempotent) ------------------------------------------------
app_id="$(az ad app list --display-name "$app_name" --query "[0].appId" --output tsv)"
if [[ -z "$app_id" ]]; then
  echo "Creating app registration $app_name..."
  app_id="$(az ad app create --display-name "$app_name" --sign-in-audience AzureADMyOrg \
    --query appId --output tsv)"
else
  echo "App registration $app_name exists (appId $app_id)."

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
ensure_fic() { # name subject description
  local name="$1" subject="$2" description="$3" params_file conflicts valid
  # A matching subject with a different issuer/audience is not a working identity.
  # Treat a conflicting name or duplicate as owner work; never overwrite it.
  conflicts="$(az ad app federated-credential list --id "$app_id" \
    --query "length([?name=='$name' || subject=='$subject'])" --output tsv)"
  valid="$(az ad app federated-credential list --id "$app_id" \
    --query "length([?subject=='$subject' && issuer=='$issuer' && length(audiences)==\`1\` && audiences[0]=='$audience'])" --output tsv)"
  if [[ "$conflicts" == "1" && "$valid" == "1" ]]; then
    echo "Federated credential for $subject has the expected issuer and audience."
    return 0
  fi
  if [[ "$conflicts" != "0" || "$valid" != "0" ]]; then
    echo "error: conflicting or ambiguous federated credential; review its name, subject, issuer and audience." >&2
    return 1
  fi
  echo "Creating federated credential $name ($subject)..."
  params_file="$(mktemp)"
  printf '{"name":"%s","issuer":"%s","subject":"%s","audiences":["%s"],"description":"%s"}\n' \
    "$name" "$issuer" "$subject" "$audience" "$description" > "$params_file"
  az ad app federated-credential create --id "$app_id" --parameters "@$params_file" --output none
  rm -f "$params_file"
}

ensure_fic "github-env-${environment}" "repo:${repo}:environment:${environment}" \
  "jobs declaring environment: ${environment}"

# Deliberately NO repo:...:pull_request credential: this principal holds deploy
# rights (Contributor + Secrets Officer), and a PR workflow can be modified by
# the PR itself — trusting the generic pull_request subject would let any PR
# with id-token:write exchange its token for those rights. PR validation stays
# offline (infra-validate.yml); if PRs ever need Azure, create a SEPARATE
# read-only identity for them.

# Only reached after explicit --apply and all target preflight checks.
for legacy_name in github-main github-pull-request github-env-production; do
  legacy_count="$(az ad app federated-credential list --id "$app_id" \
    --query "length([?name=='$legacy_name'])" --output tsv)"
  if [[ "$legacy_count" == "1" ]]; then
    az ad app federated-credential delete --id "$app_id" \
      --federated-credential-id "$legacy_name" --output none
    echo "Removed legacy '$legacy_name' federated credential."
  elif [[ "$legacy_count" != "0" ]]; then
    echo "error: ambiguous legacy credential lookup; cleanup did not complete." >&2
    exit 1
  fi
done

# --- Role assignments (idempotent, retried) ---------------------------------------
ensure_role() { # role scope
  local role="$1" scope="$2" attempt
  if [[ -n "$(az role assignment list --assignee "$sp_id" --role "$role" --scope "$scope" --subscription "$subscription" \
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
         --role "$role" --scope "$scope" --subscription "$subscription" --output none; then
      return 0
    fi
    echo "  retry $attempt/5 (Entra/RBAC replication)..." >&2
    sleep $((attempt * 5))
  done
  echo "error: failed to assign '$role' on $scope after 5 attempts." >&2
  return 1
}

ensure_role "Contributor" "$rg_scope"
ensure_role "Key Vault Secrets Officer" "$vault_id"

# --- Wiring instructions (identifiers only — never secrets) -----------------------
echo
echo "Done. No client secret was created at any point in this setup."
echo
echo "Set these on ${repo} as protected environment azure-dev VARIABLES (identifiers, not secrets):"
echo "  AZURE_CLIENT_ID       = $app_id"
echo "  AZURE_TENANT_ID       = $tenant_id"
echo "  AZURE_SUBSCRIPTION_ID = $subscription"
echo "  AZURE_RESOURCE_GROUP  = $resource_group"
echo "  AZURE_LOCATION        = $resource_location"
echo
echo "gh CLI one-liners:"
echo "  gh variable set AZURE_CLIENT_ID       --repo $repo --env azure-dev --body \"$app_id\""
echo "  gh variable set AZURE_TENANT_ID       --repo $repo --env azure-dev --body \"$tenant_id\""
echo "  gh variable set AZURE_SUBSCRIPTION_ID --repo $repo --env azure-dev --body \"$subscription\""
echo
echo "  gh variable set AZURE_RESOURCE_GROUP --repo $repo --env azure-dev --body \"$resource_group\""
echo "  gh variable set AZURE_LOCATION --repo $repo --env azure-dev --body \"$resource_location\""
echo
echo "Verify the grants with:"
echo "  az role assignment list --assignee $app_id --all --output table"
echo
echo "Protect azure-dev with required reviewers and main-only deployment branches."
echo "Then dispatch Helios Platform Deploy FROM main with what_if=true (read-only)."
echo "Applying a reviewed plan also requires deploy_confirmed=true and what_if=false."
