<#
.SYNOPSIS
Unified HELIOS readiness entrypoint (absorption ledger epic E1): one command that
inventories toolchain, auth state, AI CLI fleet, fleet topology, and MCP registration.

.DESCRIPTION
Orchestrator only — every check calls the existing script that owns the area (repo
convention: PowerShell wraps, it never reimplements):

  a. scripts/build/verify-readiness.ps1 -Json          (build/test toolchain)
  b. scripts/bootstrap/connect-github.sh --verify-only  and
     scripts/bootstrap/connect-azure.sh --verify-only / connect-azure.ps1 -VerifyOnly
     (auth state — read-only; login flows are never started from here)
  c. scripts/bootstrap/setup-ai-clis.ps1               (-VerifyOnly unless -Fix)
  d. config/fleet/fleet-topology.json                  (parses + pools listed)
  e. .mcp.json                                         (parses + server project exists)

The result is a single INVENTORY table: component / status (ready | needs-attention) /
detail / next command to fix. Exit 0 when everything is ready, 2 otherwise.

-Fix runs the actual installers (setup-ai-clis.ps1 without -VerifyOnly). Authentication
is NEVER mutated in either mode: device-code logins stay behind the connect-* scripts,
run by a human when the inventory says so.

.PARAMETER Json
Emit a machine-readable inventory object instead of the table (nothing else on stdout —
same convention as verify-readiness.ps1 -Json).

.PARAMETER Fix
Install what can be installed non-interactively (currently: the AI CLIs via npm).
Verify-only otherwise, and still never auth-mutating.

.EXAMPLE
pwsh scripts/setup/setup-all.ps1

.EXAMPLE
pwsh scripts/setup/setup-all.ps1 -Fix

.EXAMPLE
pwsh scripts/setup/setup-all.ps1 -Json | ConvertFrom-Json
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

# Child scripts run in their own process so their `exit`, StrictMode, and preference
# settings stay isolated, and their exit codes come back clean.
$pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pwshExe = if ($pwshCommand) { $pwshCommand.Source } else { [Environment]::ProcessPath }
if (-not $pwshExe) {
    # Fail fast: every child step runs through $pwshExe, and a null here would
    # surface later as an opaque "cannot bind argument" from Invoke-Step.
    Write-Error ("Cannot locate a PowerShell 7 executable (pwsh is not on PATH and the " +
        'host process path is unknown). Install PowerShell 7 or invoke this script via pwsh.')
    exit 2
}
# On Windows, a bash.exe on PATH is usually WSL's: it cannot resolve the Windows
# repo paths handed to the .sh probes, and that failure mode would mask the
# native gh/az fallbacks below. Windows always takes the native probe path.
$bashCommand = if ($IsWindows) { $null } else { Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }

function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @()
    )
    $lines = @(& $Executable @Arguments 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function New-Component {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Ready,
        [Parameter(Mandatory)][string]$Detail,
        [Parameter(Mandatory)][string]$FixCommand
    )
    [pscustomobject]@{
        Component = $Name
        Status    = if ($Ready) { 'ready' } else { 'needs-attention' }
        Detail    = $Detail
        Fix       = if ($Ready) { '' } else { $FixCommand }
    }
}

function Get-FirstLine {
    param([string[]]$Lines = @())
    $line = $Lines | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
    if ($line) { $line.Trim() } else { '(no output)' }
}

# -Json promises "nothing else on stdout", and from an external caller's viewpoint
# Write-Host lands on stdout too — so all progress printing is gated on -not $Json.
function Write-Section {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Write-ChildOutput {
    param([string[]]$Lines = @())
    if ($Json) { return }
    $Lines | Where-Object { $null -ne $_ } | ForEach-Object { Write-Host "  $_" }
}

$components = @()
$modeLabel = if ($Fix) { 'fix' } else { 'verify' }
Write-Section "== HELIOS setup-all ($modeLabel mode) =="

# --- a. Toolchain readiness -------------------------------------------------------
Write-Section ''
Write-Section '-- a. Toolchain (scripts/build/verify-readiness.ps1) --'
$readinessScript = Join-Path $repoRoot 'scripts' 'build' 'verify-readiness.ps1'
$step = Invoke-Step -Executable $pwshExe -Arguments @('-NoProfile', '-File', $readinessScript, '-Json')
$toolchain = $null
try { $toolchain = ($step.Output -join "`n") | ConvertFrom-Json } catch { Write-Verbose "verify-readiness JSON parse failed: $_" }
if ($toolchain) {
    $missingRequired = @($toolchain.required | Where-Object { -not $_.Found })
    $optionalFound = @($toolchain.optional | Where-Object { $_.Found })
    $detail = if ($missingRequired.Count -eq 0) {
        "all required tools present; optional: $($optionalFound.Count)/$(@($toolchain.optional).Count)"
    }
    else {
        'missing required: ' + (($missingRequired | ForEach-Object Tool) -join ', ')
    }
    # verify-readiness treats bicep and az as individually optional, but CI's
    # infra gate needs at least ONE Bicep compiler (standalone bicep, or az —
    # which fetches bicep itself on first `az bicep` use). Neither present
    # means the infra validation this repo runs everywhere cannot run here.
    $toolchainReady = [bool]$toolchain.ready
    $bicepPath = (Get-Command bicep -CommandType Application -ErrorAction SilentlyContinue) -or
        (Get-Command az -CommandType Application -ErrorAction SilentlyContinue)
    if ($toolchainReady -and -not $bicepPath) {
        $toolchainReady = $false
        $detail += '; no Bicep compiler (need bicep or az for infra/main.bicep validation)'
    }
    # verify-readiness only proves `dotnet` EXISTS; every AIHub/MCP project
    # targets net10.0, so a host carrying only a pre-10 SDK would be declared
    # ready while the advertised `dotnet build HELIOS.sln` cannot run.
    # Require at least one SDK with major version >= 10.
    if ($toolchainReady) {
        $dotnetCommand = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $sdkOk = $false
        if ($dotnetCommand) {
            foreach ($line in @(& $dotnetCommand.Source --list-sdks 2>$null)) {
                if ("$line" -match '^(\d+)\.' -and [int]$Matches[1] -ge 10) { $sdkOk = $true; break }
            }
        }
        if (-not $sdkOk) {
            $toolchainReady = $false
            $detail += '; no .NET SDK >= 10 (HELIOS.sln targets net10.0; dotnet --list-sdks lists none)'
        }
    }
    # Same shape for Python: presence is not compatibility. The spoke declares
    # requires-python >= 3.10 (src/ai/python/pyproject.toml) and uses
    # 3.10-only syntax, so a 3.9-or-older interpreter fails the advertised
    # test lane and fleet stub despite readiness saying Found.
    if ($toolchainReady) {
        $pythonOk = $false
        foreach ($candidate in @('python3', 'python')) {
            $py = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($py) {
                & $py.Source -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
                if ($LASTEXITCODE -eq 0) { $pythonOk = $true; break }
            }
        }
        if (-not $pythonOk) {
            $toolchainReady = $false
            $detail += '; no Python >= 3.10 (src/ai/python requires-python >= 3.10)'
        }
    }
    $components += New-Component -Name 'toolchain' -Ready $toolchainReady -Detail $detail `
        -FixCommand 'pwsh scripts/build/verify-readiness.ps1   # lists each missing tool and why it is needed'
}
else {
    $components += New-Component -Name 'toolchain' -Ready $false -Detail 'verify-readiness.ps1 produced no parseable JSON' `
        -FixCommand 'pwsh scripts/build/verify-readiness.ps1'
}
Write-ChildOutput @($components[-1].Detail)

# --- b. Auth state (read-only) ----------------------------------------------------
Write-Section ''
Write-Section '-- b. Auth state (verify-only; nothing is mutated) --'
# Application only: the probes below launch $command.Source as an external
# executable, which a profile alias or function shadowing gh/az can never back.
$ghCommand = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$azCommand = Get-Command az -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

function Invoke-GhAuthStatus {
    # --active restricts the check to the account later gh commands actually
    # use — a stale token on some OTHER stored account must not fail readiness.
    # Older gh without the flag (pre-2.40) falls back to the all-accounts view.
    param([Parameter(Mandatory)][string]$GhExe)
    $result = Invoke-Step -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com', '--active')
    if ($result.ExitCode -ne 0 -and ((@($result.Output) -join ' ') -match 'unknown flag')) {
        $result = Invoke-Step -Executable $GhExe -Arguments @('auth', 'status', '--hostname', 'github.com')
    }
    $result
}

# GitHub: the connect script owns the check. Bash-less hosts (bare Windows) fall back
# to the exact probe connect-github.sh --verify-only runs — still read-only.
$githubConnect = Join-Path $repoRoot 'scripts' 'bootstrap' 'connect-github.sh'
if ($bashCommand) {
    $step = Invoke-Step -Executable $bashCommand.Source -Arguments @(($githubConnect -replace '\\', '/'), '--verify-only')
    $githubDetail = Get-FirstLine $step.Output
}
elseif ($ghCommand) {
    $step = Invoke-GhAuthStatus -GhExe $ghCommand.Source
    $githubDetail = if ($step.ExitCode -eq 0) { 'GitHub: authenticated (gh auth status; bash unavailable for connect-github.sh).' }
    else { 'GitHub: not authenticated (gh auth status).' }
}
else {
    $step = [pscustomobject]@{ ExitCode = 1; Output = @('gh (GitHub CLI) is not installed.') }
    $githubDetail = 'gh (GitHub CLI) is not installed.'
}
# A token can authenticate fine yet lack the models:read scope the gh-models
# cliAgent needs; the full connect-github.sh login treats that scope as
# required, so this readiness verdict must too. Read-only: parse the scopes
# line from `gh auth status`. Tokens whose scopes are not listed at all (some
# PAT shapes) stay ready but say the scope could not be verified.
$githubReady = ($step.ExitCode -eq 0)
if ($githubReady -and $ghCommand) {
    $authView = Invoke-GhAuthStatus -GhExe $ghCommand.Source
    $scopeLine = @($authView.Output |
            Where-Object { "$_" -match 'Token scopes:' } | Select-Object -First 1)
    if ($scopeLine.Count -gt 0) {
        if ("$($scopeLine[0])" -notmatch 'models') {
            $githubReady = $false
            $githubDetail = 'GitHub: authenticated, but the token lacks the models:read scope the gh-models agent requires.'
        }
    }
    else {
        $githubDetail += ' (models:read scope not verifiable from gh auth status)'
    }
}
$components += New-Component -Name 'github-auth' -Ready $githubReady -Detail $githubDetail `
    -FixCommand 'scripts/bootstrap/connect-github.sh   # device-code login + models:read scope'
Write-ChildOutput $step.Output

# Azure: prefer the bash connect script (reference environment); fall back to a
# read-only `az account show` probe, then to the Azure PowerShell twin.
$azureConnect = Join-Path $repoRoot 'scripts' 'bootstrap' 'connect-azure.sh'
$azureConnectPs = Join-Path $repoRoot 'scripts' 'bootstrap' 'connect-azure.ps1'
if ($bashCommand -and $azCommand) {
    $step = Invoke-Step -Executable $bashCommand.Source -Arguments @(($azureConnect -replace '\\', '/'), '--verify-only')
    $azureDetail = Get-FirstLine $step.Output
}
elseif ($azCommand) {
    $step = Invoke-Step -Executable $azCommand.Source -Arguments @('account', 'show', '--output', 'none')
    $azureDetail = if ($step.ExitCode -eq 0) { 'Azure: authenticated (az account show; bash unavailable for connect-azure.sh).' }
    else { 'Azure: not authenticated (az account show).' }
    $step.Output = @($azureDetail)
}
else {
    $step = Invoke-Step -Executable $pwshExe -Arguments @('-NoProfile', '-File', $azureConnectPs, '-VerifyOnly')
    $azureDetail = Get-FirstLine $step.Output
}
$components += New-Component -Name 'azure-auth' -Ready ($step.ExitCode -eq 0) -Detail $azureDetail `
    -FixCommand 'scripts/bootstrap/connect-azure.sh   # or connect-azure.ps1; device-code login'
Write-ChildOutput $step.Output

# --- c. AI CLI fleet --------------------------------------------------------------
Write-Section ''
Write-Section "-- c. AI CLI fleet (scripts/bootstrap/setup-ai-clis.ps1$(if (-not $Fix) { ' -VerifyOnly' })) --"
$aiCliScript = Join-Path $repoRoot 'scripts' 'bootstrap' 'setup-ai-clis.ps1'
$aiCliArgs = @('-NoProfile', '-File', $aiCliScript)
if (-not $Fix) { $aiCliArgs += '-VerifyOnly' }
$step = Invoke-Step -Executable $pwshExe -Arguments $aiCliArgs
$aiSummary = @($step.Output | Where-Object { $_ -like 'AI CLIs:*' }) | Select-Object -Last 1
$aiDetail = if ($aiSummary) { $aiSummary.Trim() } else { Get-FirstLine $step.Output }
# Installation-only verdict, and the detail says so: setup-ai-clis checks
# executables, not credentials. Claude/Codex auth rides on env keys or cached
# CLI logins this orchestrator cannot probe without side effects; GitHub/Azure
# auth have their own components above.
$aiDetail = "installed (auth not verified here - env keys or cached CLI logins; see the headless-auth guidance): $aiDetail"
$components += New-Component -Name 'ai-clis' -Ready ($step.ExitCode -eq 0) -Detail $aiDetail `
    -FixCommand 'pwsh scripts/bootstrap/setup-ai-clis.ps1   # installs missing CLIs via npm (or setup-all.ps1 -Fix)'
Write-ChildOutput $step.Output

# --- d. Fleet topology ------------------------------------------------------------
Write-Section ''
Write-Section '-- d. Fleet topology (config/fleet/fleet-topology.json) --'
$topologyPath = Join-Path $repoRoot 'config' 'fleet' 'fleet-topology.json'
$fleetReady = $false
$fleetDetail = 'config/fleet/fleet-topology.json not found'
if (Test-Path -LiteralPath $topologyPath) {
    try {
        $topology = Get-Content -Raw -LiteralPath $topologyPath | ConvertFrom-Json
        # @() OUTSIDE the if: an if-expression's output unrolls one-element arrays,
        # which would turn a single pool into a scalar with no .Count under StrictMode.
        $pools = @(if ($topology.PSObject.Properties['pools']) { $topology.pools })
        if ($pools.Count -gt 0) {
            $fleetReady = $true
            $fleetDetail = "$($pools.Count) pools: " + (($pools | ForEach-Object name) -join ', ')
        }
        else {
            $fleetDetail = 'parses but declares no pools'
        }
    }
    catch {
        $fleetDetail = "does not parse: $($_.Exception.Message)"
    }
}
$components += New-Component -Name 'fleet-topology' -Ready $fleetReady -Detail $fleetDetail `
    -FixCommand 'pwsh scripts/fleet/start-fleet.ps1 -DryRun   # after fixing config/fleet/fleet-topology.json'
Write-ChildOutput @($fleetDetail)

# --- e. MCP registration ----------------------------------------------------------
Write-Section ''
Write-Section '-- e. MCP registration (.mcp.json) --'
$mcpPath = Join-Path $repoRoot '.mcp.json'
$mcpReady = $false
$mcpDetail = '.mcp.json not found'
if (Test-Path -LiteralPath $mcpPath) {
    try {
        $mcp = Get-Content -Raw -LiteralPath $mcpPath | ConvertFrom-Json
        # @() OUTSIDE the if — same one-element unroll hazard as the pools check above.
        $serverProps = @(if ($mcp.PSObject.Properties['mcpServers']) { $mcp.mcpServers.PSObject.Properties })
        if ($serverProps.Count -eq 0) {
            $mcpDetail = 'parses but registers no mcpServers'
        }
        else {
            $descriptions = [System.Collections.Generic.List[string]]::new()
            $allProjectsFound = $true
            foreach ($prop in $serverProps) {
                $server = $prop.Value
                $projectArg = $null
                if ($server.PSObject.Properties['args']) {
                    $serverArgs = @($server.args)
                    $projectIndex = [Array]::IndexOf($serverArgs, '--project')
                    if ($projectIndex -ge 0 -and $projectIndex + 1 -lt $serverArgs.Count) {
                        $projectArg = $serverArgs[$projectIndex + 1]
                    }
                }
                if ($projectArg) {
                    $projectDir = Join-Path $repoRoot $projectArg
                    $csproj = @(Get-ChildItem -Path $projectDir -Filter '*.csproj' -ErrorAction SilentlyContinue)
                    if ($csproj.Count -gt 0) {
                        $descriptions.Add("$($prop.Name) -> $projectArg ($($csproj[0].Name))")
                    }
                    else {
                        $descriptions.Add("$($prop.Name) -> $projectArg (NO .csproj found)")
                        $allProjectsFound = $false
                    }
                }
                else {
                    $descriptions.Add("$($prop.Name) (no --project arg; path not checked)")
                }
            }
            $mcpReady = $allProjectsFound
            $mcpDetail = $descriptions -join '; '
        }
    }
    catch {
        $mcpDetail = ".mcp.json does not parse: $($_.Exception.Message)"
    }
}
$components += New-Component -Name 'mcp-registration' -Ready $mcpReady -Detail $mcpDetail `
    -FixCommand 'dotnet build HELIOS.sln -c Release   # builds src/mcp/HELIOS.Mcp; then re-check .mcp.json paths'
Write-ChildOutput @($mcpDetail)

# --- INVENTORY --------------------------------------------------------------------
$needsAttention = @($components | Where-Object { $_.Status -eq 'needs-attention' })
$allReady = $needsAttention.Count -eq 0

if ($Json) {
    [pscustomobject]@{
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $modeLabel
        ready        = $allReady
        components   = @($components | ForEach-Object {
                [pscustomobject]@{
                    component   = $_.Component
                    status      = $_.Status
                    detail      = $_.Detail
                    nextCommand = $_.Fix
                }
            })
    } | ConvertTo-Json -Depth 4
}
else {
    Write-Host ''
    Write-Host '== INVENTORY =='
    $table = $components |
        Format-Table Component, Status, Detail, @{ n = 'Next command'; e = { $_.Fix } } -AutoSize |
        Out-String -Width 4096
    Write-Host $table.TrimEnd()
    Write-Host ''
    if ($allReady) {
        Write-Host 'All components ready.'
    }
    else {
        Write-Host "Attention needed: $($needsAttention.Count) component(s) — run the 'Next command' column entries."
        if (@($needsAttention | Where-Object { $_.Component -like '*-auth' }).Count -gt 0) {
            Write-Host "Auth in one pass: pwsh scripts/bootstrap/connect-all.ps1   # verifies every login lane, then runs only the device-code logins still needed"
        }
    }
}

if (-not $allReady) { exit 2 }
exit 0
