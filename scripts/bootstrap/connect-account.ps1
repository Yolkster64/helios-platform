<#
.SYNOPSIS
Account-connection orchestrator: verifies that every HELIOS surface is bound to the
RIGHT identity — Azure / M365 / SharePoint to the owner account
JMore@Heli0s.onmicrosoft.com, GitHub to Yolkster64 — and chains everything that can
be connected automatically, reporting the one step that never can (the owner's MFA
login) as an exact command.

.DESCRIPTION
The identity-pinning sibling of auth-doctor.ps1. auth-doctor answers "is each lane
authenticated?"; this script answers "is each lane authenticated AS THE INTENDED
ACCOUNT?" — no bootstrap script verified WHICH identity was logged in before this
one (they used exit codes only, on purpose, because raw auth output can embed
secrets; account NAMES are identities, not secrets, so pinning them is safe).

The account map this repo runs on:

  Azure CLI / ARM / Key Vault    JMore@Heli0s.onmicrosoft.com   tenant 349e1399-dccf-45b1-af7e-05d7b0676abf
  M365 / SharePoint / Graph      JMore@Heli0s.onmicrosoft.com   (operator side: the claude.ai
                                 Microsoft_365 connector; tenant side: integrations/m365 runbook)
  GitHub (gh, Actions, PRs)      Yolkster64
  OpenAI / Codex / ChatGPT       OPENAI_API_KEY from Key Vault kv-helios-jcut (owned by the
                                 jmore tenant) via load-env-from-keyvault.sh
  Claude Code                    ANTHROPIC_API_KEY from the same vault

What is automatic and what is not, end to end:

  1. az session as jmore  — NOT automatable while the workload identity is absent:
     MFA/device-code needs the owner (AADSTS50078 is the measured state,
     docs/architecture/ENTERPRISE_AI_CONNECTIONS.md §0/§1). One command, ~2 min.
  2. everything after it — automatic: load-env-from-keyvault.sh pulls
     openai-api-key / anthropic-api-key / github-models-token into the env,
     which flips the openai-codex and claude lanes to ready; gh rides GH_TOKEN /
     its keyring; auth-doctor -Apply handles service-principal / managed-identity
     re-login without a human.
  3. permanently automatic — the helios-ops-automation workload identity
     (scripts/bootstrap/setup-tenant.ps1 -OpsIdentity, cert-in-Key-Vault, no client
     secret): once the owner applies it and exports AZURE_CLIENT_ID +
     AZURE_TENANT_ID + AZURE_CLIENT_CERTIFICATE_PATH, auth-doctor -Apply logs in
     with no MFA ever again. This script reports that bridge's state. The apply
     steps are owner actions BY DESIGN: .claude/settings.json denies
     `az role assignment create`, `az ad app credential`, and reads of *.pem/*.pfx
     to agents.

Exit codes: 0 = report-only run, or -Apply run with every gating lane ready/repaired;
2 = an identity MISMATCH was found (wrong account logged in — always gates, report-only
included, because acting as the wrong identity is worse than acting unauthenticated),
or an -Apply run left a gating lane needs-owner; 1 = internal failure.

.PARAMETER ExpectedAzureUpn
UPN the az session must belong to. Default JMore@Heli0s.onmicrosoft.com.

.PARAMETER ExpectedGitHubLogin
GitHub login the gh session must belong to. Default Yolkster64.

.PARAMETER ExpectedTenantId
Entra tenant the az session must be in. Default 349e1399-dccf-45b1-af7e-05d7b0676abf.

.PARAMETER Apply
Delegate automatic non-interactive repair to auth-doctor.ps1 -Apply (service
principal / managed identity only), then re-verify identity. Never interactive.

.PARAMETER Json
Emit one machine-readable report object (auth-doctor.ps1 -Json convention).

.EXAMPLE
pwsh scripts/bootstrap/connect-account.ps1

.EXAMPLE
pwsh scripts/bootstrap/connect-account.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/bootstrap/connect-account.ps1 -Apply
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [string]$ExpectedAzureUpn = 'JMore@Heli0s.onmicrosoft.com',

    [string]$ExpectedGitHubLogin = 'Yolkster64',

    [string]$ExpectedTenantId = '349e1399-dccf-45b1-af7e-05d7b0676abf',

    [switch]$Apply,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modeLabel = if ($Apply) { 'apply' } else { 'report-only' }

function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function New-LaneResult {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)]
        [ValidateSet('ready', 'repaired', 'mismatch', 'needs-owner', 'unavailable')]
        [string]$State,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = '',
        [bool]$Gates = $true
    )
    [pscustomobject]@{
        lane        = $Lane
        state       = $State
        method      = $Method
        detail      = $Detail
        ownerAction = $OwnerAction
        gates       = $Gates
    }
}

# --- azure-account: is az logged in AS the owner account, in the owner tenant? --------
function Test-AzureAccountLane {
    $azCmd = Get-CliCommand -Name 'az'
    if (-not $azCmd) {
        return New-LaneResult -Lane 'azure-account' -State 'unavailable' -Method 'none' `
            -Detail 'az is not on PATH (scripts/bootstrap/cloud-shell-setup.sh installs it)'
    }
    # user.name and tenantId are identities, not secrets — pinning them is the point.
    $probe = & $azCmd.Source account show --query '{upn:user.name, tenant:tenantId}' --output json 2>$null
    if ($LASTEXITCODE -ne 0) {
        return New-LaneResult -Lane 'azure-account' -State 'needs-owner' -Method 'device-code' `
            -Detail 'az has no cached login at all — the tenant-scoped MFA login is the one step that cannot be automated (ENTERPRISE_AI_CONNECTIONS.md §1)' `
            -OwnerAction ('az login --tenant "{0}"' -f $ExpectedTenantId)
    }
    $who = ($probe -join '') | ConvertFrom-Json
    $upnOk = [string]::Equals([string]$who.upn, $ExpectedAzureUpn, [StringComparison]::OrdinalIgnoreCase)
    $tenantOk = [string]::Equals([string]$who.tenant, $ExpectedTenantId, [StringComparison]::OrdinalIgnoreCase)
    if (-not ($upnOk -and $tenantOk)) {
        # Wrong identity ALWAYS gates: acting as the wrong account is worse than
        # acting unauthenticated.
        return New-LaneResult -Lane 'azure-account' -State 'mismatch' -Method 'cached-login' `
            -Detail ("az session belongs to '{0}' in tenant '{1}' — expected '{2}' in '{3}'" -f $who.upn, $who.tenant, $ExpectedAzureUpn, $ExpectedTenantId) `
            -OwnerAction ('az logout; az login --tenant "{0}"' -f $ExpectedTenantId)
    }
    # Right account; is the token actually usable? (auth-doctor's freshness probe —
    # a cached profile stays green through an expired MFA session.)
    & $azCmd.Source account get-access-token --output none 2>$null
    if ($LASTEXITCODE -eq 0) {
        return New-LaneResult -Lane 'azure-account' -State 'ready' -Method 'identity-verified' `
            -Detail ("az session is {0} in tenant {1} and a live token refresh succeeds — Azure, Key Vault, and Foundry all run as the owner account" -f $ExpectedAzureUpn, $ExpectedTenantId)
    }
    return New-LaneResult -Lane 'azure-account' -State 'needs-owner' -Method 'mfa-expired' `
        -Detail ("az session IS {0} (identity verified) but the token refresh fails — the MFA session expired (AADSTS50078, the measured state in ENTERPRISE_AI_CONNECTIONS.md §0). Repair is automatic only once the helios-ops-automation workload identity is applied (see workload-identity lane); until then this is the one owner step" -f $ExpectedAzureUpn) `
        -OwnerAction ('az login --tenant "{0}"' -f $ExpectedTenantId)
}

# --- github-account: is gh operating AS the owner login? -------------------------------
function Test-GitHubAccountLane {
    $ghCmd = Get-CliCommand -Name 'gh'
    if (-not $ghCmd) {
        return New-LaneResult -Lane 'github-account' -State 'unavailable' -Method 'none' `
            -Detail 'gh is not on PATH — note GitHub automation in this repo also runs through Actions GITHUB_TOKEN and the session MCP identity, which are pinned by the platform, not by gh'
    }
    # `gh api user` returns the authenticated login — a public identity, safe to pin.
    $login = & $ghCmd.Source api user --jq '.login' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return New-LaneResult -Lane 'github-account' -State 'needs-owner' -Method 'device-code' `
            -Detail 'gh has no usable login in this shell (no env token, no keyring session) — the device-code web login needs a human' `
            -OwnerAction 'gh auth login --web   # then re-run this script; expects login Yolkster64'
    }
    $login = ($login -join '').Trim()
    if (-not [string]::Equals($login, $ExpectedGitHubLogin, [StringComparison]::OrdinalIgnoreCase)) {
        return New-LaneResult -Lane 'github-account' -State 'mismatch' -Method 'gh-login' `
            -Detail ("gh is authenticated as '{0}' — expected '{1}'" -f $login, $ExpectedGitHubLogin) `
            -OwnerAction 'gh auth logout; gh auth login --web'
    }
    return New-LaneResult -Lane 'github-account' -State 'ready' -Method 'identity-verified' `
        -Detail ("gh is authenticated as {0} — the owner login that fronts the repo, Actions, Copilot, and the PR pipeline" -f $ExpectedGitHubLogin)
}

# --- sharepoint-m365: two surfaces, only one verifiable from a shell -------------------
function Test-SharePointLane {
    # No headless shell probe exists (Graph consent + MFA — auth-doctor's sharepoint
    # lane). The operator-side surface (the claude.ai Microsoft_365 connector) is
    # verified in-session via its get_me tool, not from here; this lane exists so the
    # report tells the whole account story in one place.
    return New-LaneResult -Lane 'sharepoint-m365' -State 'needs-owner' -Method 'admin-consent' -Gates $false `
        -Detail ('two surfaces: (1) operator side — the claude.ai Microsoft_365 connector authenticates as the owner account and is verified from a session with its get_me tool, not from a shell; (2) tenant side — integrations/m365/ (Graph connector + declarative agent) needs admin consent under {0}, and Graph calls stay MFA-bound (AADSTS50078)' -f $ExpectedAzureUpn) `
        -OwnerAction ('az login --tenant "{0}"   # then integrations/m365/README.md admin-consent runbook' -f $ExpectedTenantId)
}

# --- key-custody lanes: OpenAI/Codex/ChatGPT + Claude Code ride the owner vault --------
function Test-KeyCustodyLane {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)][string]$EnvName,
        [Parameter(Mandatory)][string]$SecretName,
        [Parameter(Mandatory)][string]$Covers
    )
    if (Test-Path "env:$EnvName") {
        return New-LaneResult -Lane $Lane -State 'ready' -Method 'env-token' `
            -Detail ("$EnvName is set (name checked only, value never read) — $Covers run on the owner tenant's key custody (Key Vault secret $SecretName)")
    }
    return New-LaneResult -Lane $Lane -State 'needs-owner' -Method 'keyvault-env' `
        -Detail ("$EnvName is not set; it loads automatically from the owner tenant's Key Vault once the az session is healthy — $Covers stay unconfigured until then") `
        -OwnerAction 'source scripts/bootstrap/load-env-from-keyvault.sh   # after the az lane is ready; pulls the vault secrets into the env'
}

# --- workload-identity: the bridge that makes ALL future auth automatic ----------------
function Test-WorkloadIdentityLane {
    $names = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_CLIENT_CERTIFICATE_PATH')
    $present = @($names | Where-Object { Test-Path "env:$_" })
    if ($present.Count -eq $names.Count) {
        return New-LaneResult -Lane 'workload-identity' -State 'ready' -Method 'service-principal' `
            -Detail 'AZURE_CLIENT_ID + AZURE_TENANT_ID + AZURE_CLIENT_CERTIFICATE_PATH are set (names checked only) — auth-doctor -Apply can log in with no MFA, ever; sessions are fully automatic'
    }
    $missing = @($names | Where-Object { -not (Test-Path "env:$_") }) -join ', '
    return New-LaneResult -Lane 'workload-identity' -State 'needs-owner' -Method 'setup-tenant-3c' -Gates $false `
        -Detail ("the helios-ops-automation workload identity env bridge is not wired ($missing unset). Provisioning and the cert download are owner actions BY DESIGN — .claude/settings.json denies 'az role assignment create', 'az ad app credential', and *.pem/*.pfx reads to agents. Once wired, every future session authenticates automatically") `
        -OwnerAction 'pwsh scripts/bootstrap/setup-tenant.ps1 -OpsIdentity          # dry-run first; then -Apply, then the printed cert-download + az login --service-principal commands, exporting the three AZURE_* vars'
}

try {
    Write-Report "== HELIOS account connection ($modeLabel) =="
    Write-Report ("   expected: Azure/M365 -> {0} (tenant {1}); GitHub -> {2}" -f $ExpectedAzureUpn, $ExpectedTenantId, $ExpectedGitHubLogin)
    Write-Report ''

    if ($Apply) {
        # The only safe non-interactive mutations live in auth-doctor -Apply
        # (service principal / managed identity re-login). Delegate, then re-verify
        # identity below — repair must never change WHICH account we are.
        Write-Report '-- delegating non-interactive repair to auth-doctor.ps1 -Apply --'
        & pwsh -NoProfile (Join-Path $PSScriptRoot 'auth-doctor.ps1') -Apply | Out-Null
        Write-Report ("   auth-doctor exit: {0} (2 = a core lane still needs the owner)" -f $LASTEXITCODE)
        Write-Report ''
    }

    $laneResults = @(
        Test-AzureAccountLane
        Test-GitHubAccountLane
        Test-SharePointLane
        Test-KeyCustodyLane -Lane 'openai-codex' -EnvName 'OPENAI_API_KEY' -SecretName 'openai-api-key' `
            -Covers 'the codex CLI, ChatGPT lane, and the openai/openai-codex providers'
        Test-KeyCustodyLane -Lane 'claude-code' -EnvName 'ANTHROPIC_API_KEY' -SecretName 'anthropic-api-key' `
            -Covers 'the claude CLI and the anthropic provider'
        Test-WorkloadIdentityLane
    )

    $mismatches = @($laneResults | Where-Object { $_.state -eq 'mismatch' })
    $readyCount = @($laneResults | Where-Object { $_.state -in 'ready', 'repaired' }).Count
    $needsOwner = @($laneResults | Where-Object { $_.state -eq 'needs-owner' })

    # Wrong identity always gates, even report-only: every action taken under a wrong
    # account is a real mistake, not a missing convenience. Otherwise report-only
    # exits 0 (auth-doctor contract); -Apply gates on gating needs-owner lanes.
    $exitCode = 0
    if ($mismatches.Count -gt 0) { $exitCode = 2 }
    elseif ($Apply -and @($needsOwner | Where-Object gates).Count -gt 0) { $exitCode = 2 }

    if ($Json) {
        [ordered]@{
            script       = 'scripts/bootstrap/connect-account.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            mode         = $modeLabel
            expected     = [ordered]@{
                azureUpn    = $ExpectedAzureUpn
                tenantId    = $ExpectedTenantId
                gitHubLogin = $ExpectedGitHubLogin
            }
            lanes        = @($laneResults)
            summary      = [ordered]@{
                ready      = $readyCount
                mismatch   = $mismatches.Count
                needsOwner = $needsOwner.Count
            }
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 6
    }
    else {
        $table = $laneResults |
            Format-Table -AutoSize -Property @(
                @{ n = 'Lane'; e = { $_.lane } }
                @{ n = 'State'; e = { $_.state } }
                @{ n = 'Method'; e = { $_.method } }
                @{ n = 'Owner action (exact command)'; e = { $_.ownerAction } }
            ) |
            Out-String -Width 4096
        Write-Report $table.TrimEnd()
        Write-Report ''
        if ($mismatches.Count -gt 0) {
            Write-Report ('IDENTITY MISMATCH on: ' + (@($mismatches | ForEach-Object lane) -join ', ') + ' — fix before doing anything else.')
        }
        else {
            Write-Report ("Account lanes: $readyCount/$($laneResults.Count) verified/ready; the rest are listed owner actions — after the single MFA login, 'source scripts/bootstrap/load-env-from-keyvault.sh' + 'pwsh scripts/bootstrap/auth-doctor.ps1 -Apply' complete every remaining lane automatically.")
        }
    }

    exit $exitCode
}
catch {
    [Console]::Error.WriteLine("connect-account: internal failure — $($_.Exception.Message)")
    exit 1
}
