#Requires -Version 7
<#
.SYNOPSIS
PowerShell developer helper commands for this repository.

.DESCRIPTION
PS7 port of the upstream helios.sh helper behaviors:
  - pr-update         Generate a PR body draft from local git state.
  - prune-generated   Remove local generated artifacts that should stay uncommitted.
  - verify            Run the local CI-equivalent checks, optionally including readiness.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$prBodyPath = Join-Path $repoRoot '.github' 'PULL_REQUEST_BODY.md'
$toolResolver = Join-Path $repoRoot 'scripts' 'build' 'tool-resolver.ps1'
if (-not (Test-Path -LiteralPath $toolResolver)) {
    throw "Missing shared tool resolver: $toolResolver"
}
. $toolResolver

function Show-Usage {
    @'
HELIOS developer helper (PowerShell)

Usage:
  pwsh scripts/dev/helios.ps1 <command> [options]

Commands:
  pr-update [--dry-run]
      Generate .github/PULL_REQUEST_BODY.md from current git state.

  prune-generated
      Remove generated artifacts from the working tree.

  verify [--include-readiness] [--dry-run]
      Run the local CI-equivalent verification commands.
      --include-readiness also runs scripts/build/verify-readiness.ps1 first.

  help
      Show this usage text.
'@ | Write-Host
}

function Invoke-GitCommand {
    param([string[]]$Arguments)
    $output = @(& git -C $repoRoot @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Get-CurrentBranch {
    $branch = Invoke-GitCommand -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($branch.ExitCode -eq 0 -and $branch.Output.Count -gt 0) {
        return $branch.Output[0].Trim()
    }
    'unknown'
}

function Get-BaseRef {
    foreach ($ref in @('origin/main', 'origin/master', 'main', 'master')) {
        $probe = Invoke-GitCommand -Arguments @('rev-parse', '--verify', '--quiet', $ref)
        if ($probe.ExitCode -eq 0) { return $ref }
    }
    'HEAD~1'
}

function Get-DiffRange {
    $base = Get-BaseRef
    $probe = Invoke-GitCommand -Arguments @('rev-parse', '--verify', '--quiet', $base)
    if ($probe.ExitCode -eq 0) { return "$base..HEAD" }
    'HEAD~1..HEAD'
}

function Invoke-PrUpdate {
    param([switch]$DryRun)

    $branch = Get-CurrentBranch
    $range = Get-DiffRange

    $recentCommitsResult = Invoke-GitCommand -Arguments @('log', '--oneline', '--decorate', '-n', '12')
    $recentCommits = if ($recentCommitsResult.ExitCode -eq 0 -and $recentCommitsResult.Output.Count -gt 0) {
        $recentCommitsResult.Output -join "`n"
    }
    else {
        '_Not available in this checkout._'
    }

    $changedFilesResult = Invoke-GitCommand -Arguments @('diff', '--name-status', $range, '--', '.')
    $changedFilesLines = @($changedFilesResult.Output | Where-Object { $_ -and $_ -notmatch '\.github/PULL_REQUEST_BODY\.md$' })
    $changedFiles = if ($changedFilesResult.ExitCode -eq 0 -and $changedFilesLines.Count -gt 0) {
        $changedFilesLines -join "`n"
    }
    else {
        "_No changed files detected for range $range._"
    }

    $content = @"
# Pull Request Summary

## Overview

This PR updates the HELIOS platform repository from branch `$branch`.

## Generated Review Notes

- This draft is generated from local git state for review prep.
- `.github/PULL_REQUEST_BODY.md` is intentionally git-ignored.
- Review and edit this body before publishing the pull request.

## Recent Commits

$recentCommits

## Changed Files

$changedFiles

## Validation Checklist

- [ ] Run repository build/test commands relevant to touched projects.
- [ ] Validate script and CLI paths affected by this PR.
- [ ] Confirm generated artifacts are not committed.

## Testing

- [ ] Add exact commands and outcomes before opening the PR.
"@

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $prBodyPath) | Out-Null
    Set-Content -Path $prBodyPath -Value $content -Encoding utf8

    if ($DryRun) {
        Write-Host 'Dry run complete. Generated .github/PULL_REQUEST_BODY.md'
    }
    else {
        Write-Host 'Generated .github/PULL_REQUEST_BODY.md'
    }
}

function Invoke-PruneGenerated {
    $removed = [System.Collections.Generic.List[string]]::new()

    $reportsRoot = Join-Path $repoRoot 'reports'
    if (Test-Path -LiteralPath $reportsRoot -PathType Container) {
        $reportChildren = @(Get-ChildItem -LiteralPath $reportsRoot -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'README.md' })
        foreach ($child in $reportChildren) {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $removed.Add("reports/$($child.Name)")
        }
        if (-not (Test-Path -LiteralPath (Join-Path $reportsRoot 'README.md'))) {
            Remove-Item -LiteralPath $reportsRoot -Recurse -Force -ErrorAction SilentlyContinue
            $removed.Add('reports')
        }
    }

    foreach ($relativePath in @(
            'status-site/index.html',
            'status-site/actions.md',
            'status-site/reports',
            'status-site/wiki-export',
            '.github/PULL_REQUEST_BODY.md'
        )) {
        $fullPath = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $fullPath) {
            Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
            $removed.Add($relativePath)
        }
    }

    if ($removed.Count -eq 0) {
        Write-Host 'No generated artifacts found to prune.'
    }
    else {
        $removed | Sort-Object -Unique | ForEach-Object { Write-Host "removed $_" }
    }
}

function Resolve-FirstTool {
    param(
        [Parameter(Mandatory)][string[]]$Names,
        [switch]$Required
    )

    foreach ($name in $Names) {
        $resolution = Resolve-HeliosTool -Name $name -RepoRoot $repoRoot
        if ($resolution.Found) { return $resolution }
    }

    if ($Required) {
        throw "Required tool not found: $($Names -join ', ')"
    }

    $null
}

function Invoke-VerifyStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $repoRoot,
        [switch]$DryRun
    )

    $preview = "$Executable $($Arguments -join ' ')".Trim()
    Write-Host "== $Name =="
    if ($DryRun) {
        Write-Host "DRY RUN: $preview"
        return
    }

    Push-Location $WorkingDirectory
    try {
        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-Verify {
    param(
        [switch]$IncludeReadiness,
        [switch]$DryRun
    )

    $pwshResolution = Resolve-HeliosTool -Name 'pwsh' -RepoRoot $repoRoot
    $pwshExe = if ($pwshResolution.Found) { $pwshResolution.Path } else { [Environment]::ProcessPath }
    if (-not $pwshExe) {
        throw 'Cannot locate a PowerShell 7 executable (pwsh).'
    }

    $dotnet = Resolve-FirstTool -Names @('dotnet') -Required
    $python = Resolve-FirstTool -Names @('python3', 'python') -Required
    $bicep = Resolve-FirstTool -Names @('bicep')
    $az = Resolve-FirstTool -Names @('az')

    if ($IncludeReadiness) {
        Invoke-VerifyStep -Name 'readiness' -Executable $pwshExe `
            -Arguments @('-NoProfile', '-File', (Join-Path $repoRoot 'scripts' 'build' 'verify-readiness.ps1')) `
            -DryRun:$DryRun
    }

    Invoke-VerifyStep -Name 'dotnet-build' -Executable $dotnet.Path `
        -Arguments @('build', 'HELIOS.sln', '-c', 'Release') `
        -DryRun:$DryRun

    Invoke-VerifyStep -Name 'dotnet-test' -Executable $dotnet.Path `
        -Arguments @('test', 'tests/HELIOS.AIHub.Tests', '-c', 'Release') `
        -DryRun:$DryRun

    $bicepOut = Join-Path ([System.IO.Path]::GetTempPath()) ("helios-main-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    try {
        if ($bicep) {
            Invoke-VerifyStep -Name 'bicep-build' -Executable $bicep.Path `
                -Arguments @('build', (Join-Path $repoRoot 'infra' 'main.bicep'), '--outfile', $bicepOut) `
                -DryRun:$DryRun
        }
        elseif ($az) {
            Invoke-VerifyStep -Name 'bicep-build' -Executable $az.Path `
                -Arguments @('bicep', 'build', '--file', (Join-Path $repoRoot 'infra' 'main.bicep'), '--outfile', $bicepOut) `
                -DryRun:$DryRun
        }
        else {
            throw 'Neither bicep nor az was found (one is required to compile infra/main.bicep).'
        }
    }
    finally {
        Remove-Item -LiteralPath $bicepOut -Force -ErrorAction SilentlyContinue
    }

    Invoke-VerifyStep -Name 'python-tests' -Executable $python.Path `
        -Arguments @('-m', 'pytest', 'tests') `
        -WorkingDirectory (Join-Path $repoRoot 'src' 'ai' 'python') `
        -DryRun:$DryRun

    if (-not $DryRun) {
        Write-Host 'Verify completed successfully.'
    }
}

$commandName = if ($Command) { $Command.ToLowerInvariant() } else { 'help' }
switch ($commandName) {
    'help' {
        Show-Usage
        break
    }
    'pr-update' {
        $dryRun = $false
        foreach ($arg in $CommandArgs) {
            switch ($arg) {
                '--dry-run' { $dryRun = $true; continue }
                '-h' { Show-Usage; return }
                '--help' { Show-Usage; return }
                default { throw "Unknown pr-update option: $arg" }
            }
        }
        Invoke-PrUpdate -DryRun:$dryRun
        break
    }
    'prune-generated' {
        if ($CommandArgs.Count -gt 0) {
            if ($CommandArgs.Count -eq 1 -and $CommandArgs[0] -in @('-h', '--help')) {
                Show-Usage
                break
            }
            throw "prune-generated does not accept options: $($CommandArgs -join ' ')"
        }
        Invoke-PruneGenerated
        break
    }
    'verify' {
        $includeReadiness = $false
        $dryRun = $false
        foreach ($arg in $CommandArgs) {
            switch ($arg) {
                '--include-readiness' { $includeReadiness = $true; continue }
                '--dry-run' { $dryRun = $true; continue }
                '-h' { Show-Usage; return }
                '--help' { Show-Usage; return }
                default { throw "Unknown verify option: $arg" }
            }
        }
        Invoke-Verify -IncludeReadiness:$includeReadiness -DryRun:$dryRun
        break
    }
    default {
        throw "Unknown command: $Command"
    }
}
