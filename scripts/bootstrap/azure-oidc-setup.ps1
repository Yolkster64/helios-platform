<#
.SYNOPSIS
GitHub Actions -> Azure OIDC federation bootstrap — PowerShell 7 twin of
azure-oidc-setup.sh, wrapping the exact same az CLI calls (re-runnable).

.DESCRIPTION
Creates the Entra ID pieces that let .github/workflows/helios-deploy.yml deploy
infra/main.bicep with NO stored cloud credential anywhere:

  * app registration "helios-github-deploy" + service principal — no client secret
    is ever created, so there is nothing to leak or rotate;
  * federated credentials trusting GitHub's OIDC issuer for exactly two subjects:
    the repo's main branch and the "production" environment;
  * Contributor scoped to the resource group ONLY (least privilege: the workflow
    deploys one template into one RG — nothing subscription-wide, and the identity
    cannot create resource groups or assign roles);
  * Key Vault Secrets Officer scoped to the provider-key vault ONLY — main.bicep
    conditionally creates Microsoft.KeyVault/vaults/secrets on an RBAC-mode vault,
    and ARM authorizes those writes against DATA-plane RBAC, so Contributor alone
    fails with Forbidden the moment a secure param (anthropicApiKey, ...) is passed.

Finishes by printing the three GitHub Actions VARIABLES to set on the repo
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
    [string]$EnvironmentName = 'production'
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
if ($rgId -ine $rgScope -or $vaultId -ine "$rgScope/providers/Microsoft.KeyVault/vaults/$KeyVault" -or $vaultTenant -ine $Tenant -or $vaultRbac -ine 'true') {
    throw 'Resource-group/vault identity, tenant or RBAC mode does not match the intended target.'
}
$appCount = Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', 'length(@)', '--output', 'tsv')
if ($appCount -cnotin @('0','1')) { throw 'App registration lookup is ambiguous; choose a unique -AppName.' }
Write-Host "Azure OIDC plan`nTenant: $tenantId`nSubscription: $Subscription`nResource group: $rgId`nKey Vault: $vaultId`nApp: $AppName"
Write-Host "Trust: repo:${Repo}:ref:refs/heads/main`nTrust: repo:${Repo}:environment:$EnvironmentName"
Write-Host "Grants: Contributor on $rgId; Key Vault Secrets Officer on $vaultId"
Write-Host 'Also removes the legacy github-pull-request federated credential if present.'
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
$existingSubjects = @(
    (Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId,
        '--query', '[].subject', '--output', 'tsv')) -split "`n" | Where-Object { $_ }
)

function Add-FederatedCredential {
    param([string]$Name, [string]$Subject, [string]$Description)
    if ($existingSubjects -contains $Subject) {
        Write-Host "Federated credential for $Subject exists."
        return
    }
    Write-Host "Creating federated credential $Name ($Subject)..."
    $paramsFile = New-TemporaryFile
    @{ name = $Name; issuer = $issuer; subject = $Subject; audiences = @($audience); description = $Description } |
        ConvertTo-Json -Compress | Set-Content -Path $paramsFile
    Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $appId,
        '--parameters', "@$paramsFile", '--output', 'none') | Out-Null
    Remove-Item $paramsFile -Force
}

Add-FederatedCredential -Name 'github-main' -Subject "repo:${Repo}:ref:refs/heads/main" `
    -Description 'helios-deploy.yml on push/dispatch from main'
Add-FederatedCredential -Name "github-env-$EnvironmentName" -Subject "repo:${Repo}:environment:$EnvironmentName" `
    -Description "jobs declaring environment: $EnvironmentName"

# Deliberately NO repo:...:pull_request credential: this principal holds deploy
# rights, and a PR workflow is modifiable by the PR itself. PR validation stays
# offline; a separate read-only identity is the path if PRs ever need Azure.
# Remove the credential from earlier revisions of this script, if present.
& az ad app federated-credential show --id $appId `
    --federated-credential-id 'github-pull-request' --output none 2>$null
if ($LASTEXITCODE -eq 0) {
    Invoke-Az @('ad', 'app', 'federated-credential', 'delete', '--id', $appId,
        '--federated-credential-id', 'github-pull-request', '--output', 'none') | Out-Null
    Write-Host "Removed the over-privileged 'github-pull-request' federated credential."
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
Write-Host "Set these on $Repo as GitHub Actions VARIABLES (identifiers, not secrets):"
Write-Host "  AZURE_CLIENT_ID       = $appId"
Write-Host "  AZURE_TENANT_ID       = $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID = $Subscription"
Write-Host ''
Write-Host 'gh CLI one-liners:'
Write-Host "  gh variable set AZURE_CLIENT_ID       --repo $Repo --body `"$appId`""
Write-Host "  gh variable set AZURE_TENANT_ID       --repo $Repo --body `"$tenantId`""
Write-Host "  gh variable set AZURE_SUBSCRIPTION_ID --repo $Repo --body `"$Subscription`""
Write-Host ''
Write-Host 'Verify the grants with:'
Write-Host "  az role assignment list --assignee $appId --all --output table"
Write-Host ''
Write-Host "Then run 'Helios Platform Deploy' via workflow_dispatch FROM main (the federated"
Write-Host 'subject is branch-scoped) with what_if=true for a read-only rehearsal.'
