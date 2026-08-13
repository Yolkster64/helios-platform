[CmdletBinding()]
param(
    [string]$ResourceGroup = $(if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } else { 'rg-helios-ai' }),
    [string]$FoundryResource = $env:ANTHROPIC_FOUNDRY_RESOURCE,
    [string]$SonnetModel = $(if ($env:ANTHROPIC_DEFAULT_SONNET_MODEL) { $env:ANTHROPIC_DEFAULT_SONNET_MODEL } else { 'claude-sonnet-4-6' }),
    [string]$HaikuModel = $(if ($env:ANTHROPIC_DEFAULT_HAIKU_MODEL) { $env:ANTHROPIC_DEFAULT_HAIKU_MODEL } else { 'claude-haiku-4-5' }),
    [string]$OpusModel = $(if ($env:ANTHROPIC_DEFAULT_OPUS_MODEL) { $env:ANTHROPIC_DEFAULT_OPUS_MODEL } else { 'claude-opus-4-6' }),
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-Command {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

Require-Command az

try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
}
catch {
    throw 'Azure CLI is not authenticated. Run az login, select the intended subscription, and retry.'
}

if (-not $account.id) {
    throw 'Azure CLI returned no active subscription.'
}

Write-Host "Azure subscription: $($account.name) ($($account.id))" -ForegroundColor Cyan
Write-Host "Tenant: $($account.tenantId)" -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($FoundryResource)) {
    $resourceNames = @(az cognitiveservices account list `
        --resource-group $ResourceGroup `
        --query "[?kind=='AIServices'].name" `
        --output tsv 2>$null)

    $resourceNames = @($resourceNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($resourceNames.Count -ne 1) {
        throw "Expected exactly one AIServices Foundry account in '$ResourceGroup' but found $($resourceNames.Count). Pass -FoundryResource explicitly."
    }
    $FoundryResource = $resourceNames[0].Trim()
}

$foundry = az cognitiveservices account show `
    --resource-group $ResourceGroup `
    --name $FoundryResource `
    --output json 2>$null | ConvertFrom-Json

if (-not $foundry.id) {
    throw "Foundry resource '$FoundryResource' was not found in '$ResourceGroup'."
}

$env:CLAUDE_CODE_USE_FOUNDRY = '1'
$env:ANTHROPIC_FOUNDRY_RESOURCE = $FoundryResource
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $SonnetModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $HaikuModel
$env:ANTHROPIC_DEFAULT_OPUS_MODEL = $OpusModel

Write-Host "Foundry resource: $FoundryResource" -ForegroundColor Green
Write-Host "Claude Sonnet deployment: $SonnetModel"
Write-Host "Claude Haiku deployment:  $HaikuModel"
Write-Host "Claude Opus deployment:   $OpusModel"

$deployments = @()
try {
    $deployments = @(az cognitiveservices account deployment list `
        --resource-group $ResourceGroup `
        --name $FoundryResource `
        --query "[].name" `
        --output tsv 2>$null)
}
catch {
    Write-Warning 'Could not enumerate model deployments. Environment configuration was still applied.'
}

if ($deployments.Count -gt 0) {
    $available = @($deployments | ForEach-Object { $_.Trim() })
    foreach ($model in @($SonnetModel, $HaikuModel, $OpusModel)) {
        if ($available -contains $model) {
            Write-Host "  available: $model" -ForegroundColor Green
        }
        else {
            Write-Warning "Deployment '$model' was not found. Override its ANTHROPIC_DEFAULT_* variable or deploy that model in Foundry."
        }
    }
}

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) {
    Write-Warning 'Claude Code is not installed on PATH.'
    Write-Host 'Anthropic installation option: npm install -g @anthropic-ai/claude-code'
    Write-Host 'After installation, rerun this script or invoke it with -Launch.'
    return
}

Write-Host "Claude Code: $($claude.Source)" -ForegroundColor Green
Write-Host 'Foundry environment is configured for this process.' -ForegroundColor Green

if ($Launch) {
    & claude
}
