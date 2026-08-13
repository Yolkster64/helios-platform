#Requires -Version 7
Set-StrictMode -Version Latest

function Get-HeliosRepoToolPathAdditions {
    [CmdletBinding()]
    param(
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
        [switch]$ExistingOnly
    )

    $relativePaths = @(
        '.tools/dotnet',
        '.tools/azcli-venv/bin',
        '.tools/gh/bin',
        '.tools/bin'
    )

    $additions = foreach ($relative in $relativePaths) {
        $candidate = Join-Path $RepoRoot $relative
        if ($ExistingOnly -and -not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }

        $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue
        if ($resolved) { $resolved.Path } else { $candidate }
    }

    @($additions | Select-Object -Unique)
}

function Get-HeliosToolCandidateNames {
    param([Parameter(Mandatory)][string]$Name)

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($Name)
    if ($IsWindows) {
        foreach ($suffix in @('.exe', '.cmd', '.bat', '.ps1')) {
            if ($Name -notlike "*$suffix") {
                $candidates.Add("$Name$suffix")
            }
        }
    }

    @($candidates | Select-Object -Unique)
}

function Resolve-HeliosTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    )

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return [pscustomobject]@{
            Name   = $Name
            Found  = $true
            Path   = $command.Source
            Source = 'PATH'
        }
    }

    foreach ($dir in @(Get-HeliosRepoToolPathAdditions -RepoRoot $RepoRoot -ExistingOnly)) {
        foreach ($candidateName in @(Get-HeliosToolCandidateNames -Name $Name)) {
            $candidate = Join-Path $dir $candidateName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return [pscustomobject]@{
                    Name   = $Name
                    Found  = $true
                    Path   = (Resolve-Path -LiteralPath $candidate).Path
                    Source = 'repo-local'
                }
            }
        }
    }

    [pscustomobject]@{
        Name   = $Name
        Found  = $false
        Path   = ''
        Source = 'missing'
    }
}

function Get-HeliosResolvedTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Names,
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    )

    $resolved = [ordered]@{}
    foreach ($name in $Names) {
        $tool = Resolve-HeliosTool -Name $name -RepoRoot $RepoRoot
        $resolved[$name] = if ($tool.Found) { $tool.Path } else { $null }
    }

    [pscustomobject]$resolved
}
