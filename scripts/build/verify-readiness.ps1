<#
.SYNOPSIS
Full-stack readiness check: reports whether the tools the HELIOS build/test lanes
need are on PATH, split into required and optional.

.DESCRIPTION
Required tools are what CLAUDE.md's build/test commands need on every box:
dotnet (HELIOS.sln build + tests), pwsh (the automation layer itself), and
python3 (the src/ai/python spoke). Optional tools unlock extra lanes and never
fail the check: bicep/az (infra validation and Azure bring-up), terraform
(the infra/terraform dialect), cmake and g++ (the native spoke via
scripts/build/build-native.*), and docker (docker-compose.yml).

Each tool is reported as found/version/path. Default output is a human table;
-Json emits a machine-readable object instead (nothing else on stdout).

Exit codes: 0 when every REQUIRED tool is present, 2 otherwise. Optional gaps
are reported but never change the exit code.

.EXAMPLE
pwsh scripts/build/verify-readiness.ps1

.EXAMPLE
pwsh scripts/build/verify-readiness.ps1 -Json
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Json,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$toolResolver = Join-Path $PSScriptRoot 'tool-resolver.ps1'
if (-not (Test-Path -LiteralPath $toolResolver)) {
    # Not Write-Error: under ErrorActionPreference=Stop it throws and exits 1,
    # making the intended exit 2 unreachable.
    [Console]::Error.WriteLine("Missing shared tool resolver: $toolResolver")
    exit 2
}
. $toolResolver
$effectivePathAdditions = @(Get-HeliosRepoToolPathAdditions -RepoRoot $RepoRoot -ExistingOnly)

# Candidates: the first name found on PATH wins. python3 falls back to python for
# hosts (typically Windows) that only ship the unversioned launcher.
$toolSpecs = @(
    @{ Name = 'dotnet';    Required = $true;  Candidates = @('dotnet');            VersionArgs = @('--version'); Purpose = 'dotnet build/test HELIOS.sln' }
    @{ Name = 'pwsh';      Required = $true;  Candidates = @('pwsh');              VersionArgs = @('--version'); Purpose = 'automation scripts (scripts/**)' }
    @{ Name = 'python3';   Required = $true;  Candidates = @('python3', 'python'); VersionArgs = @('--version'); Purpose = 'Python spoke tests (src/ai/python)' }
    @{ Name = 'bicep';     Required = $false; Candidates = @('bicep');             VersionArgs = @('--version'); Purpose = 'bicep build infra/main.bicep (az bicep works too)' }
    @{ Name = 'az';        Required = $false; Candidates = @('az');                VersionArgs = @('--version'); Purpose = 'Azure login/deploy (scripts/bootstrap)' }
    @{ Name = 'terraform'; Required = $false; Candidates = @('terraform');         VersionArgs = @('version');   Purpose = 'infra/terraform dialect' }
    @{ Name = 'cmake';     Required = $false; Candidates = @('cmake');             VersionArgs = @('--version'); Purpose = 'native spoke (scripts/build/build-native.*)' }
    @{ Name = 'g++';       Required = $false; Candidates = @('g++');               VersionArgs = @('--version'); Purpose = 'native spoke compiler (Linux/macOS)' }
    @{ Name = 'docker';    Required = $false; Candidates = @('docker');            VersionArgs = @('--version'); Purpose = 'docker-compose.yml stack' }
)

function Get-ToolReport {
    param([hashtable]$Spec)

    $resolution = $null
    foreach ($candidate in $Spec.Candidates) {
        $candidateResolution = Resolve-HeliosTool -Name $candidate -RepoRoot $RepoRoot
        if ($candidateResolution.Found) {
            $resolution = $candidateResolution
            break
        }
    }

    if (-not $resolution) {
        return [pscustomobject]@{
            Tool     = $Spec.Name
            Required = [bool]$Spec.Required
            Found    = $false
            Version  = ''
            Path     = ''
            Source   = 'missing'
            Purpose  = $Spec.Purpose
        }
    }

    # Version probe: first line only (cmake/g++/az print multi-line banners). Capture
    # all output, THEN slice — piping into Select-Object -First 1 stops the pipeline
    # before $LASTEXITCODE is set, which is an error under StrictMode. A tool that is
    # present but fails its own version command is still reported as found.
    $version = 'unknown'
    try {
        $raw = @(& $resolution.Path @($Spec.VersionArgs) 2>$null)
        if ($LASTEXITCODE -eq 0 -and $raw.Count -gt 0 -and $raw[0]) {
            $version = ([string]$raw[0]).Trim()
        }
    }
    catch {
        Write-Verbose "Version probe failed for $($Spec.Name): $_"
    }

    [pscustomobject]@{
        Tool     = $Spec.Name
        Required = [bool]$Spec.Required
        Found    = $true
        Version  = $version
        Path     = $resolution.Path
        Source   = $resolution.Source
        Purpose  = $Spec.Purpose
    }
}

$reports = @(foreach ($spec in $toolSpecs) { Get-ToolReport -Spec $spec })
$resolvedTools = [ordered]@{}
foreach ($report in $reports) {
    $resolvedTools[$report.Tool] = if ($report.Found) { $report.Path } else { $null }
}
$missingRequired = @($reports | Where-Object { $_.Required -and -not $_.Found })
$ready = $missingRequired.Count -eq 0

if ($Json) {
    [pscustomobject]@{
        generatedUtc           = (Get-Date).ToUniversalTime().ToString('o')
        ready                  = $ready
        effectivePathAdditions = $effectivePathAdditions
        resolvedTools          = [pscustomobject]$resolvedTools
        required               = @($reports | Where-Object { $_.Required })
        optional               = @($reports | Where-Object { -not $_.Required })
    } | ConvertTo-Json -Depth 4
}
else {
    if ($effectivePathAdditions.Count -gt 0) {
        Write-Host 'Repo-local PATH additions used for tool resolution:'
        $effectivePathAdditions | ForEach-Object { Write-Host "  $_" }
        Write-Host ''
    }

    # Render through Out-String and print explicitly — Format-Table defers output
    # while sizing columns, and the explicit exit below can swallow it otherwise.
    $table = $reports |
        Select-Object Tool,
            @{ n = 'Tier';    e = { if ($_.Required) { 'required' } else { 'optional' } } },
            @{ n = 'Status';  e = { if ($_.Found) { 'found' } else { 'MISSING' } } },
            @{ n = 'Resolved by'; e = { $_.Source } },
            Version, Path, Purpose |
        Format-Table -AutoSize | Out-String -Width 4096
    Write-Host $table.TrimEnd()
    Write-Host ''

    if ($ready) {
        Write-Host 'Ready: all required tools are present.'
    }
    else {
        Write-Host "NOT ready: missing required tool(s): $(($missingRequired.Tool) -join ', ')"
    }
}

if (-not $ready) { exit 2 }
exit 0
