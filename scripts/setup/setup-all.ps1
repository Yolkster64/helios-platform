<#
.SYNOPSIS
Unified HELIOS readiness entrypoint (absorption ledger epic E1): one command that
inventories toolchain, auth state, AI CLI fleet, fleet topology, MCP registration, and
(informationally) whether the MCP server answers a stdio handshake.

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
  f. dotnet run --project src/mcp/HELIOS.Mcp -c Release --no-build (INFORMATIONAL: one
     JSON-RPC initialize request over stdio, 30 s budget; row reads ready | unhealthy |
     skipped when dotnet or the Release build is absent, and never changes the exit code)

The result is a single INVENTORY table: component / status (ready | needs-attention;
the mcp-health row uses ready | unhealthy | skipped) / detail / next command to fix.
Exit 0 when every gating component is ready, 2 otherwise; mcp-health never gates
because a fresh clone legitimately has no Release build yet.

-Fix runs the actual installers (setup-ai-clis.ps1 without -VerifyOnly). Authentication
is NEVER mutated in either mode: device-code logins stay behind the connect-* scripts,
run by a human when the inventory says so.

.PARAMETER Json
Emit a machine-readable inventory object instead of the table (nothing else on stdout —
same convention as verify-readiness.ps1 -Json).

.PARAMETER Fix
Install what can be installed non-interactively (currently: the AI CLIs via npm).
Verify-only otherwise, and still never auth-mutating.

.PARAMETER IncludeIssueSetup
Opt in to label and milestone readiness using existing dry-run JSON reports.
Never forwards -Fix or -Apply to issue setup. Readiness does not prove write access.

.PARAMETER Repository
Explicit owner/repo target, required with -IncludeIssueSetup. No inferred default.

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
    [switch]$Fix,
    [switch]$IncludeIssueSetup,
    [ValidatePattern('\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?/(?!\.{1,2}\z)[A-Za-z0-9_.-]{1,100}\z')]
    [string]$Repository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($IncludeIssueSetup -and -not $Repository) {
    [Console]::Error.WriteLine('setup-all: -IncludeIssueSetup requires explicit -Repository owner/repo.')
    exit 2
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$toolResolver = Join-Path $repoRoot 'scripts' 'build' 'tool-resolver.ps1'
if (-not (Test-Path -LiteralPath $toolResolver)) {
    # Not Write-Error: under ErrorActionPreference=Stop it throws and exits 1,
    # making the intended exit 2 unreachable.
    [Console]::Error.WriteLine("Missing shared tool resolver: $toolResolver")
    exit 2
}
. $toolResolver

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
        Component     = $Name
        Status        = if ($Ready) { 'ready' } else { 'needs-attention' }
        Detail        = $Detail
        Fix           = if ($Ready) { '' } else { $FixCommand }
        Informational = $false
    }
}

# Consume only the dry-run contract, not raw notes, commands, names or errors.
# The producers may exit 0 while live state is unknown: exit alone is not readiness.
function Invoke-IssueSetup {
    foreach ($kind in 'labels', 'milestones') {
        $relativePath = "scripts/github/apply-$kind.ps1"
        $path = Join-Path $repoRoot $relativePath
        $ready = $false
        $detail = 'dry-run unavailable or malformed'
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                $step = Invoke-Step -Executable $pwshExe -Arguments @(
                    '-NoProfile', '-File', $path, '-Repository', $Repository, '-Json'
                )
                $text = $step.Output -join "`n"
                if ($text.Length -gt 1048576) { throw 'report exceeds limit' }
                $report = ConvertFrom-Json -InputObject $text -NoEnumerate
                if ($report -isnot [pscustomobject] -or
                    $report.script -isnot [string] -or $report.script -cne "apply-$kind" -or
                    $report.repository -isnot [string] -or $report.repository -ine $Repository -or
                    $report.mode -isnot [string] -or $report.mode -cne 'dry-run' -or
                    ($report.exitCode -isnot [long] -and $report.exitCode -isnot [int]) -or
                    $report.exitCode -ne $step.ExitCode -or $step.ExitCode -ne 0 -or
                    $report.precondition -isnot [pscustomobject] -or
                    $report.items -isnot [array] -or
                    $report.items.Count -eq 0 -or $report.items.Count -gt 2000) {
                    throw 'invalid dry-run contract'
                }
                $known = $true
                foreach ($field in 'ghFound', 'wireReadable', 'existenceKnown') {
                    if ($report.precondition.$field -isnot [bool]) { throw 'invalid precondition' }
                    $known = $known -and $report.precondition.$field
                }
                $states = @{ 'in-sync' = 0; create = 0; update = 0; invalid = 0; failed = 0 }
                if ($kind -eq 'milestones') { $states.closed = 0 }
                $identityField = if ($kind -eq 'labels') { 'name' } else { 'title' }
                foreach ($item in $report.items) {
                    if ($item -isnot [pscustomobject] -or
                        $item.$identityField -isnot [string] -or
                        [string]::IsNullOrWhiteSpace($item.$identityField) -or
                        $item.state -isnot [string] -or
                        $item.state -cnotin @($states.Keys) -or
                        $item.command -isnot [string] -or $item.detail -isnot [string] -or
                        ($item.state -ceq 'in-sync' -and $item.command -cne '')) {
                        throw 'invalid row'
                    }
                    $states[$item.state]++
                }
                if ($report.counts -isnot [pscustomobject]) { throw 'invalid counts' }
                foreach ($state in $states.Keys) {
                    $field = if ($state -eq 'in-sync') { 'inSync' } else { $state }
                    if (($report.counts.$field -isnot [long] -and $report.counts.$field -isnot [int]) -or
                        $report.counts.$field -ne $states[$state]) { throw 'inconsistent counts' }
                }
                $pending = $report.items.Count - $states['in-sync']
                $ready = $known -and $pending -eq 0
                $detail = if (-not $known) { 'dry-run live state unknown; not ready' }
                else { "dry-run: in-sync=$($states['in-sync']); needs-owner=$pending" }
            }
            catch {
                # Child JSON can contain credentials or mutation commands: never echo it,
                # even via verbose output or an exception containing a parse excerpt.
                $detail = 'dry-run unavailable or malformed'
            }
        }
        $detail += '; issue/project write access not verified'
        New-Component -Name "issue-$kind" -Ready $ready -Detail $detail `
            -FixCommand "pwsh $relativePath -Repository $Repository -Json"
    }
}

# Informational rows read ready | unhealthy | skipped and are excluded from the readiness
# verdict by construction: the exit-code filter below keys on the literal
# 'needs-attention', which these statuses never equal. A passing probe says 'ready' rather
# than a private word such as 'healthy' because setup-everything.ps1 extracts every
# component whose status is not 'ready' as needing attention, and a passing probe must not
# surface there. Fix is always empty for the same reason: the roll-ups harvest nextCommand
# into the owner checklist, and an informational probe must never mint an owner action;
# the remedy travels inside Detail instead, where a human still sees it.
function New-InformationalComponent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ready', 'unhealthy', 'skipped')][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    [pscustomobject]@{
        Component     = $Name
        Status        = $Status
        Detail        = $Detail
        Fix           = ''
        Informational = $true
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
    $pathAdditions = @(if ($toolchain.PSObject.Properties['effectivePathAdditions']) { $toolchain.effectivePathAdditions })
    $resolvedTools = if ($toolchain.PSObject.Properties['resolvedTools']) { $toolchain.resolvedTools } else { $null }
    $detail = if ($missingRequired.Count -eq 0) {
        "all required tools present; optional: $($optionalFound.Count)/$(@($toolchain.optional).Count)"
    }
    else {
        'missing required: ' + (($missingRequired | ForEach-Object Tool) -join ', ')
    }
    if ($pathAdditions.Count -gt 0) {
        $detail += '; repo-local PATH additions: ' + ($pathAdditions -join ', ')
    }
    # verify-readiness treats bicep and az as individually optional, but CI's
    # infra gate needs at least ONE Bicep compiler (standalone bicep, or az —
    # which fetches bicep itself on first `az bicep` use). Neither present
    # means the infra validation this repo runs everywhere cannot run here.
    $toolchainReady = [bool]$toolchain.ready
    $bicepResolved = if ($resolvedTools -and $resolvedTools.PSObject.Properties['bicep']) { [string]$resolvedTools.bicep } else { '' }
    $azResolved = if ($resolvedTools -and $resolvedTools.PSObject.Properties['az']) { [string]$resolvedTools.az } else { '' }
    if ($toolchainReady -and [string]::IsNullOrWhiteSpace($bicepResolved) -and [string]::IsNullOrWhiteSpace($azResolved)) {
        $toolchainReady = $false
        $detail += '; no Bicep compiler (need bicep or az for infra/main.bicep validation)'
    }
    # verify-readiness only proves `dotnet` EXISTS; every AIHub/MCP project
    # targets net10.0, so a host carrying only a pre-10 SDK would be declared
    # ready while the advertised `dotnet build HELIOS.sln` cannot run.
    # Require at least one SDK with major version >= 10.
    if ($toolchainReady) {
        $dotnetPath = if ($resolvedTools -and $resolvedTools.PSObject.Properties['dotnet']) { [string]$resolvedTools.dotnet } else { '' }
        if ([string]::IsNullOrWhiteSpace($dotnetPath)) {
            $dotnetResolution = Resolve-HeliosTool -Name 'dotnet' -RepoRoot $repoRoot
            if ($dotnetResolution.Found) { $dotnetPath = $dotnetResolution.Path }
        }
        $sdkOk = $false
        if (-not [string]::IsNullOrWhiteSpace($dotnetPath)) {
            foreach ($line in @(& $dotnetPath --list-sdks 2>$null)) {
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
            $pyResolution = Resolve-HeliosTool -Name $candidate -RepoRoot $repoRoot
            if ($pyResolution.Found) {
                & $pyResolution.Path -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
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
$ghResolution = Resolve-HeliosTool -Name 'gh' -RepoRoot $repoRoot
$ghExe = if ($ghResolution.Found) { $ghResolution.Path } else { $null }
$azResolution = Resolve-HeliosTool -Name 'az' -RepoRoot $repoRoot
$azExe = if ($azResolution.Found) { $azResolution.Path } else { $null }

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
elseif ($ghExe) {
    $step = Invoke-GhAuthStatus -GhExe $ghExe
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
if ($githubReady -and $ghExe) {
    $authView = Invoke-GhAuthStatus -GhExe $ghExe
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
if ($bashCommand -and $azExe) {
    $step = Invoke-Step -Executable $bashCommand.Source -Arguments @(($azureConnect -replace '\\', '/'), '--verify-only')
    $azureDetail = Get-FirstLine $step.Output
}
elseif ($azExe) {
    $step = Invoke-Step -Executable $azExe -Arguments @('account', 'show', '--output', 'none')
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

# --- f. MCP health (informational) --------------------------------------------------
Write-Section ''
Write-Section '-- f. MCP health (dotnet run --project src/mcp/HELIOS.Mcp -c Release --no-build; JSON-RPC initialize over stdio; 30 s budget) --'
# Registration (e) proves the files line up; this proves the server actually ANSWERS.
# Informational by design: a fresh clone has no Release build yet, so a readiness
# inventory must not turn that into a red verdict. The launch shape is the one every
# client config uses (.mcp.json, .vscode/mcp.json, write-codex-config.ps1) plus
# --no-build, for two reasons: an inventory is read-only and must not restore, compile,
# or write bin/obj (stack-smoke.ps1 keeps the same rule), and even an up-to-date build's
# MSBuild/NuGet evaluation has been measured well past a 20 s budget on a cold machine,
# which turned a working server into a spurious 'unhealthy' row. Without the build step
# the answer arrives in a few seconds, so a server that stays silent for the whole budget
# is a real finding rather than a slow build.
$mcpHealthTimeoutSeconds = 30
$mcpHealthProject = 'src/mcp/HELIOS.Mcp'
$mcpHealthBuildHint = 'run: dotnet build HELIOS.sln -c Release, then pwsh scripts/verify/stack-smoke.ps1 for the full handshake + tool-name check'
$mcpHealthStatus = 'skipped'
$mcpHealthDetail = ''
$dotnetResolution = Resolve-HeliosTool -Name 'dotnet' -RepoRoot $repoRoot
# --no-build needs Release output to exist, so the probe looks for it up front: a fresh
# clone then reads 'skipped' with the build command instead of burning the budget on a
# launch that cannot start. Any target framework directory under bin/Release counts, so a
# TFM bump in the csproj does not quietly turn this back into a false 'skipped'.
$mcpHealthBuiltAssembly = @(Get-ChildItem -Path (Join-Path $repoRoot $mcpHealthProject 'bin' 'Release') -Filter 'HELIOS.Mcp.dll' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue)
if (-not $dotnetResolution.Found) {
    $mcpHealthDetail = 'skipped: dotnet is not on PATH (nor under .tools/dotnet); install the .NET 10 SDK to probe the server'
}
elseif (-not (Test-Path -LiteralPath (Join-Path $repoRoot $mcpHealthProject) -PathType Container)) {
    $mcpHealthDetail = "skipped: $mcpHealthProject is not in this checkout"
}
elseif ($mcpHealthBuiltAssembly.Count -eq 0) {
    $mcpHealthDetail = "skipped: no Release build of $mcpHealthProject yet ($mcpHealthBuildHint)"
}
else {
    $mcpProc = $null
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $dotnetResolution.Path
        foreach ($arg in @('run', '--project', $mcpHealthProject, '-c', 'Release', '--no-build')) { $psi.ArgumentList.Add($arg) }
        $psi.WorkingDirectory = $repoRoot
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        # UTF-8 WITHOUT BOM: a BOM ahead of the first JSON-RPC frame breaks the server's
        # parse of it (stack-smoke.ps1 finding).
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $psi.StandardInputEncoding = $utf8NoBom
        $psi.StandardOutputEncoding = $utf8NoBom
        $psi.StandardErrorEncoding = $utf8NoBom
        # The same env the client configs pass, so the probe exercises the real launch.
        $psi.Environment['HELIOS_REPO_ROOT'] = $repoRoot
        $mcpProc = [System.Diagnostics.Process]::new()
        $mcpProc.StartInfo = $psi
        $null = $mcpProc.Start()
        # Drain stderr (server logs and build output land there): an unread pipe fills
        # and blocks the child mid-write. The content is discarded, never printed:
        # build and log lines can echo environment details this inventory must not.
        $null = $mcpProc.StandardError.ReadToEndAsync()
        $mcpProc.StandardInput.AutoFlush = $true
        $mcpProc.StandardInput.WriteLine((@{
                    jsonrpc = '2.0'; id = 1; method = 'initialize'
                    params  = @{
                        protocolVersion = '2024-11-05'
                        capabilities    = @{}
                        clientInfo      = @{ name = 'setup-all'; version = '1.0.0' }
                    }
                } | ConvertTo-Json -Compress -Depth 6))
        # Wait for the id=1 reply one line at a time, bounded by the budget. Non-JSON or
        # other-id lines are skipped defensively even though the server keeps stdout
        # clean (Program.cs routes all logging to stderr).
        $reply = $null
        $sawEof = $false
        $deadline = [datetime]::UtcNow.AddSeconds($mcpHealthTimeoutSeconds)
        $pending = $null
        while ([datetime]::UtcNow -lt $deadline -and $null -eq $reply) {
            if ($null -eq $pending) { $pending = $mcpProc.StandardOutput.ReadLineAsync() }
            $completed = $false
            try { $completed = $pending.Wait(250) } catch { $sawEof = $true; break }
            if (-not $completed) { continue }
            $line = $pending.Result
            $pending = $null
            if ($null -eq $line) { $sawEof = $true; break }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $message = $null
            try { $message = $line | ConvertFrom-Json } catch { continue }
            $idProp = $message.PSObject.Properties['id']
            if ($idProp -and $null -ne $idProp.Value -and [int]$idProp.Value -eq 1) { $reply = $message }
        }
        # EOF means the child is going away; give it a moment so the exit code below is
        # real instead of a race with process teardown.
        if ($sawEof) { $null = $mcpProc.WaitForExit(2000) }
        $stopwatch.Stop()
        $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        $replyResult = if ($null -ne $reply -and $reply.PSObject.Properties['result']) { $reply.result } else { $null }
        if ($null -ne $replyResult) {
            $mcpHealthStatus = 'ready'
            $serverInfo = if ($replyResult.PSObject.Properties['serverInfo']) { $replyResult.serverInfo } else { $null }
            $serverName = if ($serverInfo -and $serverInfo.PSObject.Properties['name']) { [string]$serverInfo.name } else { 'unnamed server' }
            $serverVersion = if ($serverInfo -and $serverInfo.PSObject.Properties['version']) { [string]$serverInfo.version } else { '' }
            $protocol = if ($replyResult.PSObject.Properties['protocolVersion']) { [string]$replyResult.protocolVersion } else { '?' }
            $mcpHealthDetail = "ready: initialize answered in ${elapsed}s ($serverName $serverVersion, protocol $protocol)".Replace('  ', ' ')
        }
        elseif ($null -ne $reply) {
            $mcpHealthStatus = 'unhealthy'
            $mcpHealthDetail = "unhealthy: initialize returned an error frame after ${elapsed}s ($mcpHealthBuildHint)"
        }
        elseif ($mcpProc.HasExited) {
            $mcpHealthStatus = 'unhealthy'
            $mcpHealthDetail = ("unhealthy: the server exited (code $($mcpProc.ExitCode)) after ${elapsed}s without answering initialize " +
                "(stale or broken Release output; stderr deliberately not echoed; $mcpHealthBuildHint)")
        }
        else {
            $mcpHealthStatus = 'unhealthy'
            $mcpHealthDetail = "unhealthy: no initialize response within ${mcpHealthTimeoutSeconds}s (the server started but never answered; $mcpHealthBuildHint)"
        }
    }
    catch {
        $stopwatch.Stop()
        $mcpHealthStatus = 'unhealthy'
        $mcpHealthDetail = "unhealthy: could not spawn or talk to the server ($($_.Exception.Message); $mcpHealthBuildHint)"
    }
    finally {
        # Tree kill: dotnet run wraps the server in a child process, and killing only the
        # parent would leave the server running against a closed stdin.
        if ($mcpProc -and -not $mcpProc.HasExited) {
            try { $mcpProc.Kill($true); $null = $mcpProc.WaitForExit(5000) }
            catch { Write-Verbose "mcp-health: could not stop the probe process: $($_.Exception.Message)" }
        }
        if ($mcpProc) { $mcpProc.Dispose() }
    }
}
$components += New-InformationalComponent -Name 'mcp-health' -Status $mcpHealthStatus -Detail $mcpHealthDetail
Write-ChildOutput @($mcpHealthDetail)

# --- g. Issue setup (explicit opt-in, dry-run only even with -Fix) ------------------
if ($IncludeIssueSetup) {
    Write-Section ''
    Write-Section '-- g. Issue setup (labels and milestones; dry-run only) --'
    $components += @(Invoke-IssueSetup)
}

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
                    component     = $_.Component
                    status        = $_.Status
                    detail        = $_.Detail
                    nextCommand   = $_.Fix
                    informational = [bool]$_.Informational
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
    Write-Host 'Informational rows (mcp-health: ready | unhealthy | skipped) never change the exit code.'
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
