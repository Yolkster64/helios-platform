<#
.SYNOPSIS
GitHub Actions -> Azure OIDC federation bootstrap — PowerShell 7 twin of
azure-oidc-setup.sh, wrapping the exact same az CLI calls (re-runnable).

.DESCRIPTION
Creates the Entra ID pieces that let .github/workflows/helios-deploy.yml deploy
infra/main.bicep with NO stored cloud credential anywhere:

  * app registration "helios-github-deploy" + service principal — no client secret
    is ever created, so there is nothing to leak or rotate;
  * one federated credential trusting GitHub's OIDC issuer for the protected
    azure-dev environment; production and branch trust are disabled;
  * Contributor scoped to the resource group ONLY (least privilege: the workflow
    deploys one template into one RG — nothing subscription-wide, and the identity
    cannot create resource groups or assign roles);
  * Key Vault Secrets Officer scoped to the provider-key vault ONLY — main.bicep
    conditionally creates Microsoft.KeyVault/vaults/secrets on an RBAC-mode vault,
    and ARM authorizes those writes against DATA-plane RBAC, so Contributor alone
    fails with Forbidden the moment a secure param (anthropicApiKey, ...) is passed.

Finishes by printing the five GitHub Actions VARIABLES to set on azure-dev
(identifiers, not secrets) and the gh CLI one-liners. Never prints or stores a
secret. Safe to re-run: every step checks for the existing object before creating.

Run as a user who can create app registrations (Application Developer role or the
tenant's default user setting) AND assign roles on the scopes below (Owner or User
Access Administrator on the resource group).

.EXAMPLE
pwsh scripts/bootstrap/azure-oidc-setup.ps1 -Tenant <id> -Subscription <id> -ResourceGroup <rg> -KeyVault <vault>
# Read-only plan. Add -Apply only after reviewing the targets and permissions.

.EXAMPLE
pwsh scripts/bootstrap/azure-oidc-setup.ps1 -ResourceGroup my-rg -Repo me/fork -Tenant <id> -Subscription <id> -KeyVault <vault>
#>
[CmdletBinding()]
param(
    [string]$AppName = 'helios-github-deploy',
    [string]$Repo = 'Yolkster64/helios-platform',
    [string]$Tenant = '',
    [string]$Subscription = '',
    [string]$ResourceGroup = '',
    [string]$KeyVault = '',
    [switch]$Apply,
    [string]$EnvironmentName = 'azure-dev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issuer = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'

# Thin wrapper: run az, fail loudly on a non-zero exit code, return trimmed stdout.
function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$AzArgs)
    $out = & az @AzArgs
    if ($LASTEXITCODE -ne 0) {
        throw "az $($AzArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    if ($null -ne $out) { ($out | Out-String).Trim() } else { '' }
}

if ($EnvironmentName -cne 'azure-dev') {
    throw 'Only the protected azure-dev environment is supported; production is disabled.'
}
if ($Repo -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    throw '-Repo must be an owner/repository name.'
}

# Graph uses the active tenant. Verify it without rewriting the shared az profile.
foreach ($target in @($Tenant, $Subscription, $ResourceGroup, $KeyVault)) {
    if ([string]::IsNullOrWhiteSpace($target)) {
        throw 'Explicit -Tenant, -Subscription, -ResourceGroup and -KeyVault are required.'
    }
}
$activeSubscription = Invoke-Az @('account', 'show', '--query', 'id', '--output', 'tsv')
$tenantId = Invoke-Az @('account', 'show', '--query', 'tenantId', '--output', 'tsv')
$accountState = Invoke-Az @('account', 'show', '--query', 'state', '--output', 'tsv')
if ($activeSubscription -ine $Subscription -or $tenantId -ine $Tenant -or $accountState -cne 'Enabled') {
    throw 'Active Azure subscription/tenant must match the explicit target and be Enabled. Review az account list and select the intended account first.'
}
$rgScope = "/subscriptions/$Subscription/resourceGroups/$ResourceGroup"
$rgId = Invoke-Az @('group', 'show', '--name', $ResourceGroup, '--subscription', $Subscription, '--query', 'id', '--output', 'tsv')
$vaultId = Invoke-Az @('keyvault', 'show', '--name', $KeyVault, '--resource-group', $ResourceGroup, '--subscription', $Subscription, '--query', 'id', '--output', 'tsv')
$vaultTenant = Invoke-Az @('keyvault', 'show', '--name', $KeyVault, '--resource-group', $ResourceGroup, '--subscription', $Subscription, '--query', 'properties.tenantId', '--output', 'tsv')
$vaultRbac = Invoke-Az @('keyvault', 'show', '--name', $KeyVault, '--resource-group', $ResourceGroup, '--subscription', $Subscription, '--query', 'properties.enableRbacAuthorization', '--output', 'tsv')
$resourceLocation = Invoke-Az @('group', 'show', '--name', $ResourceGroup, '--subscription', $Subscription, '--query', 'location', '--output', 'tsv')
if (-not $resourceLocation -or $rgId -ine $rgScope -or $vaultId -ine "$rgScope/providers/Microsoft.KeyVault/vaults/$KeyVault" -or $vaultTenant -ine $Tenant -or $vaultRbac -ine 'true') {
    throw 'Resource-group/vault identity, tenant or RBAC mode does not match the intended target.'
}
$appCount = Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', 'length(@)', '--output', 'tsv')
if ($appCount -cnotin @('0','1')) { throw 'App registration lookup is ambiguous; choose a unique -AppName.' }
Write-Host "Azure OIDC plan`nTenant: $tenantId`nSubscription: $Subscription`nResource group: $rgId`nKey Vault: $vaultId`nApp: $AppName"
Write-Host "Trust: repo:${Repo}:environment:$EnvironmentName"
Write-Host "Grants: Contributor on $rgId; Key Vault Secrets Officer on $vaultId"
Write-Host 'Apply removes legacy github-main, github-pull-request and github-env-production credentials if present.'
if (-not $Apply) {
    Write-Host 'Plan only. No account, identity, permission or resource changes. Review before adding -Apply.'
    return
}

# --- App registration (idempotent) ------------------------------------------------
$appId = Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', '[0].appId', '--output', 'tsv')
if (-not $appId) {
    Write-Host "Creating app registration $AppName..."
    $appId = Invoke-Az @('ad', 'app', 'create', '--display-name', $AppName,
        '--sign-in-audience', 'AzureADMyOrg', '--query', 'appId', '--output', 'tsv')
}
else {
    Write-Host "App registration $AppName exists (appId $appId)."

}

# --- Service principal (idempotent) -----------------------------------------------
$spId = Invoke-Az @('ad', 'sp', 'list', '--filter', "appId eq '$appId'", '--query', '[0].id', '--output', 'tsv')
if (-not $spId) {
    Write-Host "Creating service principal for $AppName..."
    $spId = Invoke-Az @('ad', 'sp', 'create', '--id', $appId, '--query', 'id', '--output', 'tsv')
}
else {
    Write-Host "Service principal exists (objectId $spId)."
}

# --- Federated credentials (idempotent, matched on subject) -----------------------
# The subject string must match what the workflow run presents EXACTLY, or login
# fails with AADSTS70021/700213. A job that declares `environment:` presents the
# environment subject instead of the branch one.
function Add-FederatedCredential {
    param([string]$Name, [string]$Subject, [string]$Description)
    # A matching subject alone is insufficient; do not overwrite a conflict.
    $conflicts = Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId,
        '--query', "length([?name=='$Name' || subject=='$Subject'])", '--output', 'tsv')
    $valid = Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId,
        '--query', "length([?subject=='$Subject' && issuer=='$issuer' && length(audiences)==``1`` && audiences[0]=='$audience'])", '--output', 'tsv')
    if ($conflicts -ceq '1' -and $valid -ceq '1') {
        Write-Host "Federated credential for $Subject has the expected issuer and audience."
        return
    }
    if ($conflicts -cne '0' -or $valid -cne '0') {
        throw 'Conflicting or ambiguous federated credential; review its name, subject, issuer and audience.'
    }
    Write-Host "Creating federated credential $Name ($Subject)..."
    $paramsFile = New-TemporaryFile
    @{ name = $Name; issuer = $issuer; subject = $Subject; audiences = @($audience); description = $Description } |
        ConvertTo-Json -Compress | Set-Content -Path $paramsFile
    Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $appId,
        '--parameters', "@$paramsFile", '--output', 'none') | Out-Null
    Remove-Item $paramsFile -Force
}

Add-FederatedCredential -Name "github-env-$EnvironmentName" -Subject "repo:${Repo}:environment:$EnvironmentName" `
    -Description "jobs declaring environment: $EnvironmentName"

# Deliberately NO repo:...:pull_request credential: this principal holds deploy
# rights, and a PR workflow is modifiable by the PR itself. PR validation stays
# offline; a separate read-only identity is the path if PRs ever need Azure.
# Only reached after explicit -Apply and all target preflight checks.
foreach ($legacyName in @('github-main', 'github-pull-request', 'github-env-production')) {
    $legacyCount = Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId,
        '--query', "length([?name=='$legacyName'])", '--output', 'tsv')
    if ($legacyCount -ceq '1') {
        Invoke-Az @('ad', 'app', 'federated-credential', 'delete', '--id', $appId,
            '--federated-credential-id', $legacyName, '--output', 'none') | Out-Null
        Write-Host "Removed legacy '$legacyName' federated credential."
    }
    elseif ($legacyCount -cne '0') {
        throw 'Ambiguous legacy credential lookup; cleanup did not complete.'
    }
}

# --- Role assignments (idempotent, retried) ---------------------------------------
function Set-RoleGrant {
    param([string]$Role, [string]$Scope)
    $existing = Invoke-Az @('role', 'assignment', 'list', '--assignee', $spId,
        '--role', $Role, '--scope', $Scope, '--subscription', $Subscription, '--query', '[0].id', '--output', 'tsv')
    if ($existing) {
        Write-Host "'$Role' on $Scope already assigned."
        return
    }
    Write-Host "Assigning '$Role' on $Scope..."
    foreach ($attempt in 1..5) {
        # --assignee-object-id + --assignee-principal-type skips the Graph lookup a
        # just-created SP can fail; ARM itself is still eventually consistent
        # (PrincipalNotFound), so retry with backoff instead of failing once.
        & az role assignment create --assignee-object-id $spId `
            --assignee-principal-type ServicePrincipal `
            --role $Role --scope $Scope --subscription $Subscription --output none
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "  retry $attempt/5 (Entra/RBAC replication)..."
        Start-Sleep -Seconds ($attempt * 5)
    }
    throw "failed to assign '$Role' on $Scope after 5 attempts."
}

Set-RoleGrant -Role 'Contributor' -Scope $rgScope
Set-RoleGrant -Role 'Key Vault Secrets Officer' -Scope $vaultId

# --- Wiring instructions (identifiers only — never secrets) -----------------------
Write-Host ''
Write-Host 'Done. No client secret was created at any point in this setup.'
Write-Host ''
Write-Host "Set these on $Repo as protected environment azure-dev VARIABLES (identifiers, not secrets):"
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $Subscription"
Write-Host "  AZURE_RESOURCE_GROUP  = $ResourceGroup"
Write-Host "  AZURE_LOCATION        = $resourceLocation"
Write-Host ''
Write-Host 'gh CLI one-liners:'
Write-Host "  gh variable set AZURE_CLIENT_ID       --repo $Repo --env azure-dev --body `"$appId`""
Write-Host "  gh variable set AZURE_TENANT_ID       --repo $Repo --env azure-dev --body `"$tenantId`""
Write-Host "  gh variable set AZURE_SUBSCRIPTION_ID --repo $Repo --env azure-dev --body `"$Subscription`""
Write-Host ''
Write-Host "  gh variable set AZURE_RESOURCE_GROUP --repo $Repo --env azure-dev --body `"$ResourceGroup`""
Write-Host "  gh variable set AZURE_LOCATION --repo $Repo --env azure-dev --body `"$resourceLocation`""
Write-Host ''
Write-Host 'Verify the grants with:'
Write-Host "  az role assignment list --assignee $appId --all --output table"
Write-Host ''
Write-Host 'Protect azure-dev with required reviewers and main-only deployment branches.'
Write-Host 'Then dispatch Helios Platform Deploy FROM main with what_if=true (read-only).'
Write-Host 'Applying a reviewed plan also requires deploy_confirmed=true and what_if=false.'
