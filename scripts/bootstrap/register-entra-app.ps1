<#
.SYNOPSIS
Entra app-registration helper for the helios-ai-api identity-aware ingress —
dry-run by default, printing the exact az CLI commands (and JSON payloads) it
WOULD run; -Apply executes them against a logged-in az CLI.

.DESCRIPTION
Implements the ingress design in docs/architecture/IDENTITY_ARCHITECTURE.md (§1):

  * app registration (resource app) with the three AIHub app roles
    (AIHub.Read / AIHub.Invoke / AIHub.Learning.Write) — NO client secret is
    ever created, so there is nothing to leak or rotate;
  * App ID URI (api://<appId> unless -IdentifierUri overrides) and
    api.requestedAccessTokenVersion = 2;
  * one admin-consent-only delegated scope (AIHub.Access) via a Graph PATCH;
  * the service principal (enterprise app) for the registration;
  * optionally, a GitHub OIDC federated credential (-GitHubOidcSubject) so
    automation that must CALL the API authenticates with a short-lived token
    per run — the same zero-stored-secret pattern as azure-oidc-setup.ps1.

Role and scope IDs are deterministic (derived from the role value), so a re-run
never mints duplicate IDs — the same idempotency rule as guid() seeds in the
Bicep role assignments (infra/modules/keyvault.bicep).

Never prints or persists tokens or secrets; the only values handled are
identifiers. Granting callers a role and admin consent are owner actions with
rights this script does not assume — it prints the follow-up commands instead.

Exit codes: 0 = dry-run printed or apply succeeded; 2 = refused input
(a pull_request OIDC subject, or a malformed subject) or -Apply preconditions
missing (az CLI absent, or not logged in).

.EXAMPLE
pwsh scripts/bootstrap/register-entra-app.ps1
Dry run: print every command and payload, execute nothing.

.EXAMPLE
pwsh scripts/bootstrap/register-entra-app.ps1 -GitHubOidcSubject 'repo:Yolkster64/helios-platform:ref:refs/heads/main'
Dry run including the federated-credential command for a main-branch caller.

.EXAMPLE
pwsh scripts/bootstrap/register-entra-app.ps1 -Apply
Execute for real (requires az login; e.g. scripts/bootstrap/connect-azure.ps1).
#>
[CmdletBinding()]
param(
    [string]$DisplayName = 'helios-ai-api',

    # Empty = api://<appId>, the always-unique default. A vanity URI
    # (api://helios-ai-api) works only if the tenant allows it.
    [string]$IdentifierUri = '',

    # Full GitHub OIDC subject for automation that must call the API, e.g.
    # repo:<owner>/<repo>:ref:refs/heads/main or repo:<owner>/<repo>:environment:<name>.
    # Empty = no federated credential. pull_request subjects are refused — see
    # the rationale in infra/README.md ("OIDC identity") and azure-oidc-setup.ps1.
    [string]$GitHubOidcSubject = '',

    [string]$FederatedCredentialName = 'github-api-caller',

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$oidcIssuer = 'https://token.actions.githubusercontent.com'
$oidcAudience = 'api://AzureADTokenExchange'

# --- Input validation (refusals exit 2 with an explanation, never Write-Error) ----
if ($GitHubOidcSubject) {
    if ($GitHubOidcSubject -notmatch '^repo:[^/:]+/[^/:]+:') {
        Write-Host ("Refusing OIDC subject '{0}': expected the form " -f $GitHubOidcSubject)
        Write-Host '  repo:<owner>/<repo>:ref:refs/heads/<branch>  or  repo:<owner>/<repo>:environment:<name>'
        Write-Host 'The subject must match what the workflow run presents EXACTLY, or token'
        Write-Host 'exchange fails with AADSTS700213.'
        exit 2
    }
    if ($GitHubOidcSubject -match ':pull_request$') {
        Write-Host 'Refusing a pull_request OIDC subject: a PR workflow is modifiable by the'
        Write-Host 'PR itself, so the generic pull_request subject would let any PR with'
        Write-Host 'id-token: write mint tokens as this caller (which can spend provider'
        Write-Host 'quota through /v1/*). Use a branch or environment subject instead — the'
        Write-Host 'same stance azure-oidc-setup.ps1 takes for the deploy identity.'
        exit 2
    }
}

# --- Deterministic GUIDs -----------------------------------------------------------
# Non-cryptographic use: stable IDs mean a re-run of -Apply PATCHes identical
# content instead of minting new role/scope IDs that would orphan existing
# appRoleAssignments.
function Get-StableGuid {
    param([Parameter(Mandatory)][string]$Seed)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        [guid]::new($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("helios-ai-api:$Seed")))
    }
    finally {
        $md5.Dispose()
    }
}

# --- Role / scope definitions (docs/architecture/IDENTITY_ARCHITECTURE.md §1) ------
$appRoleSpecs = @(
    [pscustomobject]@{
        Value       = 'AIHub.Read'
        DisplayName = 'Read hub state'
        Description = 'GET /v1/status, /v1/routing, /v1/learning, /v1/insights, /v1/engines. No provider spend.'
    }
    [pscustomobject]@{
        Value       = 'AIHub.Invoke'
        DisplayName = 'Invoke orchestration'
        Description = 'POST /v1/ask, /v1/route, /v1/tandem, /v1/compare, /v1/engines/recommend. Can spend provider quota.'
    }
    [pscustomobject]@{
        Value       = 'AIHub.Learning.Write'
        DisplayName = 'Write learning outcomes'
        Description = 'POST /v1/learning — provenance-required advisory outcome ingestion.'
    }
)

$appRolesJson = ConvertTo-Json -Depth 4 @(
    foreach ($spec in $appRoleSpecs) {
        [ordered]@{
            id                 = (Get-StableGuid -Seed ('role:' + $spec.Value)).Guid
            value              = $spec.Value
            displayName        = $spec.DisplayName
            description        = $spec.Description
            allowedMemberTypes = @('User', 'Application')
            isEnabled          = $true
        }
    }
)

$oauth2ScopeJson = ConvertTo-Json -Depth 5 ([ordered]@{
        api = [ordered]@{
            oauth2PermissionScopes = @(
                [ordered]@{
                    id                      = (Get-StableGuid -Seed 'scope:AIHub.Access').Guid
                    value                   = 'AIHub.Access'
                    type                    = 'Admin'
                    adminConsentDisplayName = 'Access the HELIOS AI hub API'
                    adminConsentDescription = 'Allows the app to call helios-ai-api /v1/* on behalf of the signed-in user.'
                    isEnabled               = $true
                }
            )
        }
    })

# --- Print-or-execute plumbing -----------------------------------------------------
function Format-AzCommand {
    param([Parameter(Mandatory)][string[]]$AzArgs)
    $rendered = foreach ($arg in $AzArgs) {
        if ($arg -match '[\s''"@(){}\[\]<>|&;]') { '"' + ($arg -replace '"', '\"') + '"' }
        else { $arg }
    }
    'az ' + ($rendered -join ' ')
}

# Steps carry an optional JSON payload. Dry-run prints the payload under its
# file label and the command referencing @<label>; -Apply writes a temp file,
# swaps the '{jsonfile}' placeholder for its real path, runs az, fails loudly
# on a non-zero exit code, and returns trimmed stdout.
function Invoke-PlannedAz {
    param(
        [Parameter(Mandatory)][string[]]$AzArgs,
        [string]$JsonBody = '',
        [string]$JsonLabel = 'payload.json'
    )
    if (-not $Apply) {
        if ($JsonBody) {
            Write-Host ('--- {0} (write this file first) ---' -f $JsonLabel)
            Write-Host $JsonBody
            Write-Host '---'
        }
        $shown = foreach ($arg in $AzArgs) { if ($arg -eq '{jsonfile}') { '@' + $JsonLabel } else { $arg } }
        Write-Host ('  ' + (Format-AzCommand -AzArgs $shown))
        return ''
    }
    $tempFile = $null
    try {
        $realArgs = $AzArgs
        if ($JsonBody) {
            $tempFile = New-TemporaryFile
            Set-Content -Path $tempFile -Value $JsonBody
            $realArgs = foreach ($arg in $AzArgs) { if ($arg -eq '{jsonfile}') { '@' + $tempFile.FullName } else { $arg } }
        }
        Write-Host ('  ' + (Format-AzCommand -AzArgs $realArgs))
        $out = & az @realArgs
        if ($LASTEXITCODE -ne 0) {
            throw ('az {0} failed with exit code {1}' -f ($realArgs -join ' '), $LASTEXITCODE)
        }
        if ($null -ne $out) { ($out | Out-String).Trim() } else { '' }
    }
    finally {
        if ($tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# --- Preconditions -----------------------------------------------------------------
# Probe for the az BINARY (an alias/function shadowing 'az' would pass a bare
# Get-Command and then fail at first real invocation — script-patterns.md).
$azCommand = Get-Command az -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($Apply) {
    if (-not $azCommand) {
        Write-Host '-Apply requires the Azure CLI, and no ''az'' application was found on PATH.'
        Write-Host 'Install it (https://aka.ms/azure-cli) or run without -Apply for the dry run.'
        exit 2
    }
    & $azCommand.Source account show --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host '-Apply requires a logged-in az CLI, and ''az account show'' failed.'
        Write-Host 'Log in first (az login, or scripts/bootstrap/connect-azure.ps1), then re-run.'
        exit 2
    }
}
else {
    Write-Host 'DRY RUN — printing the commands this script would execute. Re-run with'
    Write-Host '-Apply (and a logged-in az CLI) to execute them. No command below creates'
    Write-Host 'a client secret at any point.'
    if (-not $azCommand) {
        Write-Host '(note: no az CLI found on PATH — -Apply will refuse until it is installed)'
    }
    Write-Host ''
}

# --- Step 1: app registration (idempotent under -Apply) ----------------------------
Write-Host '== 1. App registration (resource app, app roles, no client secret) =='
$appId = '<appId>'
$createNeeded = $true
if ($Apply) {
    $existingAppId = Invoke-PlannedAz -AzArgs @('ad', 'app', 'list',
        '--display-name', $DisplayName, '--query', '[0].appId', '--output', 'tsv')
    if ($existingAppId) {
        $appId = $existingAppId
        $createNeeded = $false
        Write-Host ("App registration {0} exists (appId {1}) — skipping create. App roles are" -f $DisplayName, $appId)
        Write-Host 'NOT overwritten on an existing app (replacing the collection can orphan'
        Write-Host 'assignments); review them in the portal under App roles if they drifted.'
    }
}
if ($createNeeded) {
    $created = Invoke-PlannedAz -JsonBody $appRolesJson -JsonLabel 'app-roles.json' -AzArgs @(
        'ad', 'app', 'create',
        '--display-name', $DisplayName,
        '--sign-in-audience', 'AzureADMyOrg',
        '--app-roles', '{jsonfile}',
        '--query', 'appId', '--output', 'tsv')
    if ($Apply) { $appId = $created }
}

# --- Step 2: App ID URI + v2 access tokens -----------------------------------------
Write-Host ''
Write-Host '== 2. App ID URI and v2 access tokens =='
$effectiveUri = if ($IdentifierUri) { $IdentifierUri } else { "api://$appId" }
Invoke-PlannedAz -AzArgs @('ad', 'app', 'update', '--id', $appId,
    '--identifier-uris', $effectiveUri) | Out-Null
Invoke-PlannedAz -AzArgs @('ad', 'app', 'update', '--id', $appId,
    '--set', 'api.requestedAccessTokenVersion=2') | Out-Null

# --- Step 3: delegated scope (Graph PATCH — az ad app has no scope subcommand) -----
Write-Host ''
Write-Host '== 3. Delegated scope AIHub.Access (admin consent only) =='
Invoke-PlannedAz -JsonBody $oauth2ScopeJson -JsonLabel 'oauth2-scope.json' -AzArgs @(
    'rest', '--method', 'PATCH',
    '--url', "https://graph.microsoft.com/v1.0/applications(appId='$appId')",
    '--headers', 'Content-Type=application/json',
    '--body', '{jsonfile}') | Out-Null

# --- Step 4: service principal (idempotent under -Apply) ---------------------------
Write-Host ''
Write-Host '== 4. Service principal (enterprise app) =='
$spNeeded = $true
if ($Apply) {
    $existingSpId = Invoke-PlannedAz -AzArgs @('ad', 'sp', 'list',
        '--filter', "appId eq '$appId'", '--query', '[0].id', '--output', 'tsv')
    if ($existingSpId) {
        $spNeeded = $false
        Write-Host ('Service principal exists (objectId {0}).' -f $existingSpId)
    }
}
if ($spNeeded) {
    Invoke-PlannedAz -AzArgs @('ad', 'sp', 'create', '--id', $appId) | Out-Null
}

# --- Step 5 (optional): GitHub OIDC federated credential ---------------------------
if ($GitHubOidcSubject) {
    Write-Host ''
    Write-Host '== 5. GitHub OIDC federated credential (zero stored secret) =='
    $ficJson = ConvertTo-Json -Depth 3 ([ordered]@{
            name        = $FederatedCredentialName
            issuer      = $oidcIssuer
            subject     = $GitHubOidcSubject
            audiences   = @($oidcAudience)
            description = ('GitHub Actions caller for {0} ({1})' -f $DisplayName, $GitHubOidcSubject)
        })
    $ficNeeded = $true
    if ($Apply) {
        $existingSubjects = @(
            (Invoke-PlannedAz -AzArgs @('ad', 'app', 'federated-credential', 'list',
                '--id', $appId, '--query', '[].subject', '--output', 'tsv')) -split "`n" |
                Where-Object { $_ }
        )
        if ($existingSubjects -contains $GitHubOidcSubject) {
            $ficNeeded = $false
            Write-Host ('Federated credential for {0} exists.' -f $GitHubOidcSubject)
        }
    }
    if ($ficNeeded) {
        Invoke-PlannedAz -JsonBody $ficJson -JsonLabel 'federated-credential.json' -AzArgs @(
            'ad', 'app', 'federated-credential', 'create',
            '--id', $appId, '--parameters', '{jsonfile}') | Out-Null
    }
}

# --- Owner follow-ups this script does not perform ---------------------------------
Write-Host ''
Write-Host '== Owner follow-ups (elevated rights; not executed by this script) =='
Write-Host ('  App ID URI: {0}' -f $effectiveUri)
Write-Host '  * Enterprise application -> Properties -> "Assignment required" = Yes.'
Write-Host '  * Grant each caller the LEAST role (role IDs above are deterministic):'
Write-Host ('      az rest --method POST --url ' +
    '"https://graph.microsoft.com/v1.0/servicePrincipals/<resourceSpObjectId>/appRoleAssignedTo" \')
Write-Host ('      --headers Content-Type=application/json --body ' +
    '''{"principalId":"<callerSpObjectId>","resourceId":"<resourceSpObjectId>","appRoleId":"<roleGuid>"}''')
Write-Host '  * Admin consent for AIHub.Access (delegated callers only): portal ->'
Write-Host '    API permissions -> Grant admin consent (Cloud Application Administrator).'
Write-Host '  * Wire token validation at the ingress per'
Write-Host '    docs/architecture/IDENTITY_ARCHITECTURE.md §1; leave HELIOS_API_ACCESS_KEY'
Write-Host '    unset in hosted config (env-var NAME only — never a value in any file).'
Write-Host ''
Write-Host 'Verify:'
Write-Host ("  az ad app federated-credential list --id {0} --query '[].subject' -o tsv" -f $appId)
Write-Host ("  az ad sp show --id {0} --query appRoles -o json" -f $appId)

exit 0
