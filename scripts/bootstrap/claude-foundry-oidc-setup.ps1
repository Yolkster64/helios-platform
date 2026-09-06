<#
.SYNOPSIS
Create or verify the dedicated GitHub Actions -> Microsoft Foundry identity used by
Claude Code. No client secret is created.

.DESCRIPTION
This bootstrap intentionally does NOT reuse the HELIOS deployment identity. It creates
(or reuses) a dedicated Entra application/service principal whose only data-plane grant
is Cognitive Services User on the selected Microsoft Foundry account. The GitHub OIDC
credential trusts only the main branch of the selected repository.

When GitHub CLI is installed and authenticated, the script writes only non-secret
repository variables:
  CLAUDE_AZURE_CLIENT_ID
  CLAUDE_AZURE_TENANT_ID
  CLAUDE_AZURE_SUBSCRIPTION_ID
  ANTHROPIC_FOUNDRY_RESOURCE

The script never accepts Marketplace terms and never deploys a Claude model. It verifies
that the configured Foundry account contains Sonnet and Haiku deployment names and
reports Opus as optional.

.EXAMPLE
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1

.EXAMPLE
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -Subscription <id> -ResourceGroup rg-helios-ai -FoundryResource my-foundry

.EXAMPLE
pwsh scripts/bootstrap/claude-foundry-oidc-setup.ps1 -VerifyOnly
#>
[CmdletBinding()]
param(
    [string]$Repo = 'Yolkster64/helios-platform',
    [string]$AppName = 'helios-claude-foundry',
    [string]$Subscription = '',
    [string]$ResourceGroup = 'rg-helios-ai',
    [string]$FoundryResource = '',
    [string]$SonnetDeployment = 'claude-sonnet-4-6',
    [string]$HaikuDeployment = 'claude-haiku-4-5',
    [string]$OpusDeployment = 'claude-opus-4-6',
    [switch]$VerifyOnly,
    [switch]$SkipGitHubVariables
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issuer = 'https://token.actions.githubusercontent.com'
$audience = 'api://AzureADTokenExchange'
$subject = "repo:${Repo}:ref:refs/heads/main"

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$AzArgs)
    $output = & az @AzArgs
    if ($LASTEXITCODE -ne 0) {
        throw "az $($AzArgs -join ' ') failed with exit code $LASTEXITCODE"
    }
    if ($null -eq $output) { return '' }
    return ($output | Out-String).Trim()
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'az')) {
    throw 'Azure CLI is required. Open Azure Cloud Shell or install Azure CLI first.'
}

& az account show --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login (or use Azure Cloud Shell) first.'
}

if ($Subscription) {
    Invoke-Az @('account', 'set', '--subscription', $Subscription) | Out-Null
}

$subscriptionId = Invoke-Az @('account', 'show', '--query', 'id', '--output', 'tsv')
$subscriptionName = Invoke-Az @('account', 'show', '--query', 'name', '--output', 'tsv')
$tenantId = Invoke-Az @('account', 'show', '--query', 'tenantId', '--output', 'tsv')

Write-Host "Azure subscription: $subscriptionName"
Write-Host "Resource group: $ResourceGroup"

& az group show --name $ResourceGroup --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Resource group '$ResourceGroup' was not found in the active subscription. Select the correct subscription or pass -ResourceGroup."
}

if (-not $FoundryResource) {
    $foundryCandidates = @(
        (Invoke-Az @('cognitiveservices', 'account', 'list', '--resource-group', $ResourceGroup,
            '--query', "[?kind=='AIServices' && properties.allowProjectManagement==true].name", '--output', 'tsv')) -split "`n" |
            Where-Object { $_ }
    )
    if ($foundryCandidates.Count -ne 1) {
        throw "Expected exactly one Foundry account candidate (kind AIServices with allowProjectManagement=true) in '$ResourceGroup' but found $($foundryCandidates.Count). Pass -FoundryResource explicitly."
    }
    $FoundryResource = $foundryCandidates[0]
}

$foundryId = Invoke-Az @('cognitiveservices', 'account', 'show', '--name', $FoundryResource,
    '--resource-group', $ResourceGroup, '--query', 'id', '--output', 'tsv')
Write-Host "Foundry resource: $FoundryResource"

$deploymentNames = @(
    (Invoke-Az @('cognitiveservices', 'account', 'deployment', 'list', '--name', $FoundryResource,
        '--resource-group', $ResourceGroup, '--query', '[].name', '--output', 'tsv')) -split "`n" |
        Where-Object { $_ }
)

$missingRequired = [System.Collections.Generic.List[string]]::new()
foreach ($required in @($SonnetDeployment, $HaikuDeployment)) {
    if ($deploymentNames -notcontains $required) {
        $missingRequired.Add($required)
    }
}

if ($deploymentNames -contains $OpusDeployment) {
    Write-Host "Optional Opus deployment present: $OpusDeployment"
}
else {
    Write-Warning "Optional Opus deployment not found: $OpusDeployment"
}

$appId = Invoke-Az @('ad', 'app', 'list', '--display-name', $AppName, '--query', '[0].appId', '--output', 'tsv')
if (-not $appId -and $VerifyOnly) {
    throw "Dedicated Claude application '$AppName' does not exist. Run without -VerifyOnly to create it."
}

if (-not $VerifyOnly) {
    if (-not $appId) {
        Write-Host "Creating Entra application: $AppName"
        $appId = Invoke-Az @('ad', 'app', 'create', '--display-name', $AppName,
            '--sign-in-audience', 'AzureADMyOrg', '--query', 'appId', '--output', 'tsv')
    }
    else {
        Write-Host "Entra application exists: $AppName"
    }
}

$spId = ''
if ($appId) {
    $spId = Invoke-Az @('ad', 'sp', 'list', '--filter', "appId eq '$appId'", '--query', '[0].id', '--output', 'tsv')
}

if (-not $VerifyOnly -and -not $spId) {
    Write-Host 'Creating service principal...'
    $spId = Invoke-Az @('ad', 'sp', 'create', '--id', $appId, '--query', 'id', '--output', 'tsv')
}
elseif ($VerifyOnly -and -not $spId) {
    throw 'The Claude Entra application exists but its service principal is missing.'
}

$ficExists = $false
if ($appId) {
    $subjects = @(
        (Invoke-Az @('ad', 'app', 'federated-credential', 'list', '--id', $appId,
            '--query', '[].subject', '--output', 'tsv')) -split "`n" | Where-Object { $_ }
    )
    $ficExists = $subjects -contains $subject
}

if (-not $VerifyOnly -and -not $ficExists) {
    Write-Host "Creating GitHub OIDC credential for $subject"
    $ficFile = New-TemporaryFile
    @{
        name = 'github-main-claude-foundry'
        issuer = $issuer
        subject = $subject
        audiences = @($audience)
        description = 'Claude Code on Microsoft Foundry from Yolkster64/helios-platform main'
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $ficFile -Encoding utf8
    try {
        Invoke-Az @('ad', 'app', 'federated-credential', 'create', '--id', $appId,
            '--parameters', "@$ficFile", '--output', 'none') | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $ficFile -Force -ErrorAction SilentlyContinue
    }
}
elseif ($VerifyOnly -and -not $ficExists) {
    throw "GitHub OIDC credential for '$subject' is missing."
}

$roleName = 'Cognitive Services User'
$roleAssignment = ''
if ($spId) {
    $roleAssignment = Invoke-Az @('role', 'assignment', 'list', '--assignee', $spId,
        '--role', $roleName, '--scope', $foundryId, '--query', '[0].id', '--output', 'tsv')
}

if (-not $VerifyOnly -and -not $roleAssignment) {
    Write-Host "Assigning '$roleName' on the Foundry account only..."
    $assigned = $false
    foreach ($attempt in 1..5) {
        & az role assignment create --assignee-object-id $spId `
            --assignee-principal-type ServicePrincipal `
            --role $roleName --scope $foundryId --output none
        if ($LASTEXITCODE -eq 0) {
            $assigned = $true
            break
        }
        Start-Sleep -Seconds ($attempt * 5)
    }
    if (-not $assigned) {
        throw "Failed to assign '$roleName' after 5 attempts. The operator needs role-assignment permission on the Foundry account."
    }
}
elseif ($VerifyOnly -and -not $roleAssignment) {
    throw "The dedicated Claude service principal is missing '$roleName' on the Foundry account."
}

# VerifyOnly is strictly non-mutating: it never writes repository variables.
if (-not $VerifyOnly -and -not $SkipGitHubVariables) {
    if (Test-Command 'gh') {
        & gh auth status *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Host 'Writing non-secret GitHub repository variables...'
            & gh variable set CLAUDE_AZURE_CLIENT_ID --repo $Repo --body $appId
            if ($LASTEXITCODE -ne 0) { throw 'Failed to set CLAUDE_AZURE_CLIENT_ID.' }
            & gh variable set CLAUDE_AZURE_TENANT_ID --repo $Repo --body $tenantId
            if ($LASTEXITCODE -ne 0) { throw 'Failed to set CLAUDE_AZURE_TENANT_ID.' }
            & gh variable set CLAUDE_AZURE_SUBSCRIPTION_ID --repo $Repo --body $subscriptionId
            if ($LASTEXITCODE -ne 0) { throw 'Failed to set CLAUDE_AZURE_SUBSCRIPTION_ID.' }
            & gh variable set ANTHROPIC_FOUNDRY_RESOURCE --repo $Repo --body $FoundryResource
            if ($LASTEXITCODE -ne 0) { throw 'Failed to set ANTHROPIC_FOUNDRY_RESOURCE.' }
        }
        else {
            Write-Warning 'GitHub CLI is installed but not authenticated. Run gh auth login, then rerun this script.'
        }
    }
    else {
        Write-Warning 'GitHub CLI not found. Install/authenticate gh, or set the four printed repository variables manually.'
    }
}

Write-Host ''
Write-Host 'Claude Foundry OIDC identity status:'
Write-Host "  application      : $AppName"
Write-Host "  client identifier: $appId"
Write-Host "  OIDC subject     : $subject"
Write-Host "  role              : $roleName (Foundry account scope only)"
Write-Host "  Foundry resource  : $FoundryResource"
Write-Host '  client secret     : NONE'
Write-Host ''
Write-Host 'GitHub variables required by .github/workflows/claude-foundry.yml:'
Write-Host '  CLAUDE_AZURE_CLIENT_ID'
Write-Host '  CLAUDE_AZURE_TENANT_ID'
Write-Host '  CLAUDE_AZURE_SUBSCRIPTION_ID'
Write-Host '  ANTHROPIC_FOUNDRY_RESOURCE'

if ($missingRequired.Count -gt 0) {
    Write-Error ("Identity wiring is complete, but required Claude deployment(s) are missing from '$FoundryResource': " + ($missingRequired -join ', ') + '. Deploy them in Microsoft Foundry after accepting the applicable Marketplace terms, then rerun with -VerifyOnly.')
    exit 2
}

Write-Host "Required Claude deployments present: $SonnetDeployment, $HaikuDeployment"
Write-Host 'Run the GitHub workflow "Claude Code on Microsoft Foundry" from main to verify the end-to-end handshake.'
