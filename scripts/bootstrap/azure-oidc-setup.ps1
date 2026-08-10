<#
.SYNOPSIS
GitHub Actions -> Azure OIDC federation bootstrap — PowerShell 7 twin of
azure-oidc-setup.sh, wrapping the exact same az CLI calls (re-runnable).

.DESCRIPTION
Creates the Entra ID pieces that let .github/workflows/helios-deploy.yml deploy
infra/main.bicep with NO stored cloud credential anywhere:

  * app registration "helios-github-deploy" + service principal — no client secret
    is ever created, so there is nothing to leak or rotate;
  * federated credentials trusting GitHub's OIDC issuer for exactly three subjects:
    the repo's main branch, pull requests, and the "production" environment;
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
pwsh scripts/bootstrap/azure-oidc-setup.ps1

.EXAMPLE
pwsh scripts/bootstrap/azure-oidc-setup.ps1 -ResourceGroup my-rg -Repo me/fork -Subscription <id>
#>
[CmdletBinding()]
param(
    [string]$AppName = 'helios-github-deploy',
    [string]$Repo = 'Yolkster64/helios-platform',
    [string]$Subscription = '784565d3-c82a-4dba-b947-fc354c08a89d',
    [string]$ResourceGroup = 'rg-helios-ai',
    [string]$KeyVault = 'kv-helios-jcut',
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

& az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'not logged in — run az login (or scripts/bootstrap/connect-azure.ps1) first.'
}
Invoke-Az @('account', 'set', '--subscription', $Subscription) | Out-Null
$tenantId = Invoke-Az @('account', 'show', '--query', 'tenantId', '--output', 'tsv')

# The role scope must exist before we grant on it; the RG is created by the stack
# bring-up (scripts/bootstrap/azure-up.ps1), not by CI.
& az group show --name $ResourceGroup --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "resource group $ResourceGroup not found in subscription $Subscription — deploy the stack first (scripts/bootstrap/azure-up.ps1) or pass -ResourceGroup."
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
    $dupCount = [int](Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', 'length(@)', '--output', 'tsv'))
    if ($dupCount -gt 1) {
        Write-Warning "$dupCount app registrations named $AppName; using appId $appId."
    }
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
        '--role', $Role, '--scope', $Scope, '--query', '[0].id', '--output', 'tsv')
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
            --role $Role --scope $Scope --output none
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "  retry $attempt/5 (Entra/RBAC replication)..."
        Start-Sleep -Seconds ($attempt * 5)
    }
    throw "failed to assign '$Role' on $Scope after 5 attempts."
}

$rgScope = "/subscriptions/$Subscription/resourceGroups/$ResourceGroup"
Set-RoleGrant -Role 'Contributor' -Scope $rgScope

$vaultId = & az keyvault show --name $KeyVault --resource-group $ResourceGroup --query id --output tsv 2>$null
if ($LASTEXITCODE -ne 0) { $vaultId = '' }
if ($vaultId) {
    Set-RoleGrant -Role 'Key Vault Secrets Officer' -Scope $vaultId
}
else {
    Write-Warning ("Key Vault $KeyVault not found in $ResourceGroup — skipping the Key Vault " +
        'Secrets Officer grant. Re-run this script once the vault exists if deploys pass ' +
        'provider API keys (main.bicep writes them as vault secrets, which needs data-plane ' +
        'RBAC on an RBAC-mode vault).')
}

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
