#requires -Version 7.4
<#+
.SYNOPSIS
Plans and validates the HELIOS Fabric setup without performing tenant, cloud,
repository-administration, connector, disk, or security mutations.

.DESCRIPTION
The default mode is Plan. Validate additionally executes local contract checks.
ExportEvidence writes a redacted JSON receipt. External activation remains a
separate administrator-approved workflow.

The script intentionally has no Deploy/Apply switch.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Plan', 'Validate', 'ExportEvidence')]
    [string]$Mode = 'Plan',

    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot '../../artifacts/helios-fabric'),

    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$FabricPath = Join-Path $RepositoryRoot 'config/fabric/helios-fabric.v1.json'
$ConnectionsPath = Join-Path $RepositoryRoot 'config/connectors/helios-fabric.connections.v1.json'
$RolesPath = Join-Path $RepositoryRoot 'config/agents/helios-fabric-roles.v1.json'
$CutoverValidator = Join-Path $RepositoryRoot 'scripts/validation/validate_yolkster_cutover.py'
$FabricValidator = Join-Path $RepositoryRoot 'scripts/validation/validate_helios_fabric.py'

function Read-JsonObject {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file not found: $Path"
    }

    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 100
    if ($null -eq $value) {
        throw "JSON file produced no object: $Path"
    }

    return $value
}

function Get-ToolState {
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    [ordered]@{
        name = $Name
        available = $null -ne $command
        source = if ($command) { $command.Source } else { $null }
        version = if ($command -and $command.Version) { $command.Version.ToString() } else { $null }
    }
}

function Invoke-PythonValidator {
    param([Parameter(Mandatory)][string]$Path)

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
    }
    if (-not $python) {
        throw 'Python 3 is required to execute HELIOS contract validation.'
    }

    $output = & $python.Source $Path 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Validator failed ($Path):`n$($output -join [Environment]::NewLine)"
    }

    return ($output -join [Environment]::NewLine)
}

$fabric = Read-JsonObject -Path $FabricPath
$connections = Read-JsonObject -Path $ConnectionsPath
$roles = Read-JsonObject -Path $RolesPath

if ($fabric.safety.productionEnabled -ne $false) {
    throw 'Refusing setup: productionEnabled must remain false.'
}
if ($fabric.safety.applyDefault -ne $false) {
    throw 'Refusing setup: applyDefault must remain false.'
}
if ($fabric.identity.clientSecretsAllowed -ne $false) {
    throw 'Refusing setup: client-secret CI must remain disabled.'
}

$tools = @(
    'git',
    'gh',
    'dotnet',
    'pwsh',
    'python',
    'az',
    'azd',
    'docker',
    'node',
    'npm',
    'bicep'
) | ForEach-Object { Get-ToolState -Name $_ }

$connectionSummary = @($connections.connections | ForEach-Object {
    [ordered]@{
        id = $_.id
        kind = $_.kind
        authority = $_.authority
        writePolicy = $_.writePolicy
        healthCheck = $_.healthCheck
    }
})

$roleSummary = @($roles.roles | ForEach-Object {
    [ordered]@{
        id = $_.id
        purpose = $_.purpose
        allowedCount = @($_.allowed).Count
        deniedCount = @($_.denied).Count
    }
})

$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('O')
    mode = $Mode
    repositoryRoot = $RepositoryRoot
    currentRepository = $fabric.currentAuthority.repository
    targetCoreRepository = $fabric.targetTopology.coreRepository
    targetGuiRepository = $fabric.targetTopology.guiRepository
    activationOrder = @($fabric.activationOrder)
    tools = $tools
    connections = $connectionSummary
    agentRoles = $roleSummary
    safety = [ordered]@{
        productionEnabled = $fabric.safety.productionEnabled
        applyDefault = $fabric.safety.applyDefault
        automaticAzureDeployment = $fabric.safety.automaticAzureDeployment
        automaticRbacMutation = $fabric.safety.automaticRbacMutation
        automaticSecretWrite = $fabric.safety.automaticSecretWrite
    }
}

$validation = [ordered]@{
    cutover = 'not-run'
    fabric = 'not-run'
}

if ($Mode -in @('Validate', 'ExportEvidence')) {
    $validation.cutover = Invoke-PythonValidator -Path $CutoverValidator
    $validation.fabric = Invoke-PythonValidator -Path $FabricValidator
}

$requiredToolsForStrict = @('git', 'dotnet', 'pwsh', 'python')
if ($Strict) {
    $missing = @($tools | Where-Object { $_.name -in $requiredToolsForStrict -and -not $_.available })
    if ($missing.Count -gt 0) {
        throw "Strict readiness failed; missing: $($missing.name -join ', ')"
    }
}

$result = [ordered]@{
    plan = $plan
    validation = $validation
    externalMutationsPerformed = $false
    nextAction = 'Review plan and obtain the specific administrator approvals required by each activation phase.'
}

if ($Mode -eq 'ExportEvidence') {
    if ($PSCmdlet.ShouldProcess($EvidenceDirectory, 'Write redacted HELIOS Fabric readiness evidence')) {
        New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
        $evidencePath = Join-Path $EvidenceDirectory 'helios-fabric-readiness.json'
        $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
        $hash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  helios-fabric-readiness.json" |
            Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'SHA256SUMS') -Encoding ASCII
        Write-Host "Evidence: $evidencePath"
        Write-Host "SHA-256: $hash"
    }
}

$result | ConvertTo-Json -Depth 100
