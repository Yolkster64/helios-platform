#Requires -Version 7
<#
.SYNOPSIS
One sitting for the two device codes a human must type - GitHub (gh) and Azure (az) -
then the whole bring-up chain without another prompt.

.DESCRIPTION
A device code is the one thing that cannot be automated: the flow exists so that a
human proves presence in a browser, and MFA cannot be delegated. Everything around
it can be, and this script does it:

  1. Verify-first. A lane that is already ready is skipped and reported as such:
     gh  -> `gh auth status --hostname github.com --active` (exit code only; the
            unknown-flag fallback of connect-all.ps1 for older gh builds)
     az  -> `az account get-access-token --output none` (exit code only - the
            cached-profile-but-MFA-expired state answers non-zero) on the tenant.
  2. Both flows start at the same time as two child processes with stdin closed
     (gh then prints its code instead of waiting for Enter) and stdout+stderr read
     asynchronously (both CLIs print the code on stderr):
       gh auth login --hostname github.com --git-protocol https --web
                     --scopes repo,workflow,project,read:org,models:read
       az login --use-device-code --tenant <tenant>
     GH_TOKEN / GITHUB_TOKEN are removed from the gh child's environment: a stub
     token in the parent (agent containers export one) would otherwise pre-empt the
     keyring and the login would be recorded for the wrong identity.
  3. One table with both codes and both URLs, printed as soon as both are known, so
     the owner enters them in one sitting. The device CODES are meant to be shown;
     no token value ever is.
  4. Both children are polled until they exit or the timeout passes. A lane ends
     ready (re-verified with the probes above), expired (the code aged out - -Retry
     re-issues it once), refused (AADSTS / declined / authentication failed), or
     failed (anything else; the last output line is the detail).
  5. When both lanes are ready the chain runs, in this order, each a sibling script
     with its own contract:
       GitHub Models token   dot-sourced only (`. scripts/bootstrap/connect-devices.ps1`):
                             $env:GITHUB_MODELS_TOKEN is set from the gh login, which
                             flips the github-models provider to Ready; when run as a
                             child the export line is printed instead (a child cannot
                             export into your shell).
       connect-github-app.ps1 -DispatchGovernance   the GitHub App (two browser clicks)
                             and the first governance apply; -SkipGitHubApp skips it.
       connect-admin.ps1 -SkipGitHub                the Azure ops identity via
                             setup-tenant.ps1 -OpsIdentity -Apply; -SkipOpsIdentity
                             skips it.
       auto-login.ps1        dot-sourced when this script is (vault keys into this
                             shell), otherwise run as a child for its report.
       auth-doctor.ps1 -Json and first-run.sh --verify-only   the final lane table and
                             the numbered owner checklist.
     -SkipChain stops after the logins (codes only).

Exit code 0 = every lane ready (or skipped by a switch); 1 = a chained script failed
(replay list printed); 2 = a login lane needs the owner (expired / refused / timed
out) or a precondition is missing. -Json prints exactly one object.

.PARAMETER VerifyOnly
Probe both lanes read-only, print the plan (the two commands that would run, the
chain), launch nothing.

.PARAMETER Json
Exactly one JSON object on stdout and nothing else.

.PARAMETER Retry
Re-issue a lane's device code once when the first one expires.

.PARAMETER Tenant
Azure tenant id for `az login --tenant`. Defaults to the HELIOS tenant.

.PARAMETER Repository
owner/name passed to the chained scripts. Defaults to Yolkster64/helios-platform.

.PARAMETER SkipGitHubApp
Do not run connect-github-app.ps1 after the logins.

.PARAMETER SkipOpsIdentity
Do not run connect-admin.ps1 -SkipGitHub (the ops identity) after the logins.

.PARAMETER SkipChain
Stop after the logins: codes, verification, nothing else.

.PARAMETER TimeoutMinutes
How long to wait for each device flow (both CLIs expire their codes after roughly
this long anyway). Fractions are accepted.

.EXAMPLE
pwsh scripts/bootstrap/connect-devices.ps1                    # codes, then the chain
. scripts/bootstrap/connect-devices.ps1                        # same, exports into this shell
pwsh scripts/bootstrap/connect-devices.ps1 -VerifyOnly -Json   # plan only
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$Json,
    [switch]$Retry,
    [string]$Tenant = '349e1399-dccf-45b1-af7e-05d7b0676abf',
    [string]$Repository = 'Yolkster64/helios-platform',
    [switch]$SkipGitHubApp,
    [switch]$SkipOpsIdentity,
    [switch]$SkipChain,
    [double]$TimeoutMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:scriptRel = 'scripts/bootstrap/connect-devices.ps1'
$script:jsonMode = $false
$script:lanes = [System.Collections.Generic.List[object]]::new()
$script:replay = [System.Collections.Generic.List[string]]::new()
$script:ghScopes = 'repo,workflow,project,read:org,models:read'

# --- Report idioms (connect-admin.ps1) ------------------------------------------------
function Write-Report {
    param([string]$Message = '')
    if (-not $script:jsonMode) { Write-Host $Message }
}

function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSObject]) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Get-CliCommand {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Add-Lane {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ready', 'needs-owner', 'failed', 'skipped')][string]$State,
        [Parameter(Mandatory)][string]$Detail,
        [string]$OwnerAction = ''
    )
    $script:lanes.Add([ordered]@{ name = $Name; state = $State; detail = $Detail; ownerAction = $OwnerAction })
}

function Add-Replay {
    param([Parameter(Mandatory)][string]$Command)
    $script:replay.Add($Command)
}

function New-ReportObject {
    param([int]$ExitCode, [string]$Mode, [string]$Repository, [string]$Tenant, [string]$FailedPrecondition = '', [string[]]$Fix = @())
    $object = [ordered]@{
        script       = $script:scriptRel
        generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        mode         = $Mode
        repository   = $Repository
        tenant       = $Tenant
    }
    if ($FailedPrecondition) {
        $object['failedPrecondition'] = $FailedPrecondition
        $object['fix'] = @($Fix)
    }
    $object['lanes'] = @($script:lanes)
    $object['replay'] = @($script:replay)
    $object['exitCode'] = $ExitCode
    return $object
}

function Write-Precondition {
    param([Parameter(Mandatory)][string]$Message, [string[]]$Fix = @(), [string]$Mode = '', [string]$Repository = '', [string]$Tenant = '')
    if ($script:jsonMode) {
        New-ReportObject -ExitCode 2 -Mode $Mode -Repository $Repository -Tenant $Tenant -FailedPrecondition $Message -Fix $Fix | ConvertTo-Json -Depth 5
        return 2
    }
    Write-Report "connect-devices: FAILED PRECONDITION - $Message"
    foreach ($line in $Fix) { Write-Report "  $line" }
    Write-Report 'Nothing was changed.'
    return 2
}

function Write-Summary {
    param([string]$Mode, [string]$Repository, [string]$Tenant)
    $failedCount = @($script:lanes | Where-Object { $_.state -eq 'failed' }).Count
    $ownerCount = @($script:lanes | Where-Object { $_.state -eq 'needs-owner' }).Count
    $exitCode = if ($failedCount -gt 0 -or $script:replay.Count -gt 0) { 1 } elseif ($ownerCount -gt 0) { 2 } else { 0 }
    if ($script:jsonMode) {
        New-ReportObject -ExitCode $exitCode -Mode $Mode -Repository $Repository -Tenant $Tenant | ConvertTo-Json -Depth 5
        return $exitCode
    }
    Write-Report ''
    Write-Report '== Summary =='
    $rows = $script:lanes | ForEach-Object {
        [pscustomobject]@{ Lane = $_.name; State = $_.state; Next = $(if ($_.ownerAction) { $_.ownerAction } else { '-' }) }
    }
    $table = $rows | Format-Table -AutoSize -Property Lane, State, Next | Out-String -Width 4096
    Write-Report $table.TrimEnd()
    Write-Report ''
    if ($script:replay.Count -gt 0) {
        Write-Report "connect-devices: $($script:replay.Count) item(s) FAILED - replay list:"
        foreach ($r in $script:replay) { Write-Report "  $r" }
    }
    elseif ($ownerCount -gt 0) {
        Write-Report "connect-devices: $ownerCount lane(s) need the owner - the Next column names the step."
    }
    else {
        Write-Report "connect-devices: every lane is ready ($Mode)."
    }
    return $exitCode
}

# --- Captured children ------------------------------------------------------------------
# Synchronous capture for the short probes (exit code is the verdict, output never
# echoed). -ClearGitHubTokens removes GH_TOKEN / GITHUB_TOKEN from the child so gh
# answers for the keyring login and not for a stub the parent exported.
function Invoke-Captured {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$ClearGitHubTokens
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($ClearGitHubTokens) { foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) } }
    $proc = [System.Diagnostics.Process]::Start($psi)
    try {
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.Close()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout; StdErr = $stderrTask.Result }
    }
    finally { $proc.Dispose() }
}

function Get-LastLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $line = (@(("$Text" -split "`n") | Where-Object { $_.Trim() }) | Select-Object -Last 1)
    $line = if ($line) { "$line".Trim() } else { '' }
    if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '...' }
    return $line
}

# --- Verify-first probes -----------------------------------------------------------------
function Test-GhReady {
    $gh = Get-CliCommand -Name 'gh'
    if (-not $gh) { return $false }
    $result = Invoke-Captured -FilePath $gh.Source -Arguments @('auth', 'status', '--hostname', 'github.com', '--active') -ClearGitHubTokens
    if ($result.ExitCode -ne 0 -and (("$($result.StdOut)`n$($result.StdErr)") -match 'unknown flag')) {
        $result = Invoke-Captured -FilePath $gh.Source -Arguments @('auth', 'status', '--hostname', 'github.com') -ClearGitHubTokens
    }
    return ($result.ExitCode -eq 0)
}

function Test-AzReady {
    param([Parameter(Mandatory)][string]$Tenant)
    $az = Get-CliCommand -Name 'az'
    if (-not $az) { return $false }
    $result = Invoke-Captured -FilePath $az.Source -Arguments @('account', 'get-access-token', '--tenant', $Tenant, '--output', 'none')
    return ($result.ExitCode -eq 0)
}

# --- Device flows ----------------------------------------------------------------------------
# Both CLIs print their one-time code on stderr; both streams feed one queue per lane
# so the table can be printed while the children are still polling GitHub / Entra.
function Get-DeviceFlowSpec {
    param([Parameter(Mandatory)][ValidateSet('github', 'azure')][string]$Lane, [string]$Tenant = '')
    switch ($Lane) {
        'github' {
            return [pscustomobject]@{
                Lane        = 'github'
                Command     = 'gh'
                Arguments   = @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web', '--scopes', $script:ghScopes)
                Url         = 'https://github.com/login/device'
                CodePattern = '(?i)one-time code:?\s*([A-Z0-9]{4}-[A-Z0-9]{4})'
                ClearTokens = $true
            }
        }
        'azure' {
            return [pscustomobject]@{
                Lane        = 'azure'
                Command     = 'az'
                Arguments   = @('login', '--use-device-code', '--tenant', $Tenant)
                Url         = 'https://microsoft.com/devicelogin'
                CodePattern = '(?i)enter the code\s+([A-Z0-9]{6,12})\s+to authenticate'
                ClearTokens = $false
            }
        }
    }
}

function Get-DeviceCode {
    param([Parameter(Mandatory)][string]$Pattern, [AllowEmptyCollection()][string[]]$Lines)
    foreach ($line in @($Lines)) {
        if ("$line" -match $Pattern) { return $Matches[1] }
    }
    return $null
}

# The three end states a device flow can reach, from its exit code and last lines.
function Get-FlowVerdict {
    param([int]$ExitCode, [AllowEmptyCollection()][string[]]$Lines, [switch]$TimedOut)
    if ($TimedOut) { return 'expired' }
    if ($ExitCode -eq 0) { return 'ready' }
    $tail = (@($Lines | Select-Object -Last 8) -join "`n")
    if ($tail -match '(?i)expired|timed out|time out|timeout') { return 'expired' }
    if ($tail -match '(?i)AADSTS|declined|denied|access_denied|authentication failed|cancel') { return 'refused' }
    return 'failed'
}

function Start-DeviceFlow {
    param([Parameter(Mandatory)]$Spec)
    $cli = Get-CliCommand -Name $Spec.Command
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $cli.Source
    foreach ($a in $Spec.Arguments) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($Spec.ClearTokens) { foreach ($name in 'GH_TOKEN', 'GITHUB_TOKEN') { $null = $psi.Environment.Remove($name) } }
    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $handler = { if ($null -ne $EventArgs.Data) { $Event.MessageData.Enqueue($EventArgs.Data) } }
    $subscriptions = @(
        (Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $queue),
        (Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $queue)
    )
    $null = $proc.Start()
    # stdin closed at once: with no terminal on stdin gh prints the code and proceeds
    # instead of waiting for Enter.
    $proc.StandardInput.Close()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    return [pscustomobject]@{
        Lane          = $Spec.Lane
        Spec          = $Spec
        Process       = $proc
        Queue         = $queue
        Lines         = [System.Collections.Generic.List[string]]::new()
        Subscriptions = $subscriptions
        Code          = $null
        StartedUtc    = [DateTime]::UtcNow
    }
}

function Update-DeviceFlow {
    param([Parameter(Mandatory)]$Flow)
    $line = $null
    while ($Flow.Queue.TryDequeue([ref]$line)) { $Flow.Lines.Add($line) }
    if (-not $Flow.Code) { $Flow.Code = Get-DeviceCode -Pattern $Flow.Spec.CodePattern -Lines $Flow.Lines }
}

function Stop-DeviceFlow {
    param([Parameter(Mandatory)]$Flow)
    foreach ($s in $Flow.Subscriptions) { Unregister-Event -SourceIdentifier $s.Name -ErrorAction SilentlyContinue; Remove-Job -Id $s.Id -Force -ErrorAction SilentlyContinue }
    # The whole tree: the CLI may have forked (az wraps python), and an orphaned poller
    # would keep asking GitHub or Entra about a code nobody will enter.
    try {
        if (-not $Flow.Process.HasExited) {
            $Flow.Process.Kill($true)
            $null = $Flow.Process.WaitForExit(3000)
        }
    }
    catch { Write-Verbose "kill failed: $($_.Exception.Message)" }
    $Flow.Process.Dispose()
}

function Write-CodeTable {
    param([Parameter(Mandatory)]$Flows)
    Write-Report ''
    Write-Report '  Enter these codes (any browser, any device):'
    foreach ($flow in $Flows) {
        $label = if ($flow.Lane -eq 'github') { 'GitHub' } else { 'Azure ' }
        $code = if ($flow.Code) { $flow.Code } else { '(waiting for the CLI to print it)' }
        Write-Report ("    {0} -> {1,-40} code {2}" -f $label, $flow.Spec.Url, $code)
    }
    Write-Report ''
}

# Runs the given lanes concurrently until both exit or the deadline passes. Returns a
# hashtable lane -> @{ Verdict; Detail; Code }.
function Invoke-DeviceFlows {
    param([Parameter(Mandatory)]$Specs, [double]$TimeoutMinutes = 15)
    $flows = @($Specs | ForEach-Object { Start-DeviceFlow -Spec $_ })
    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $TimeoutMinutes * 60))
    $tablePrinted = $false
    $results = @{}
    try {
        while ($true) {
            foreach ($flow in $flows) { Update-DeviceFlow -Flow $flow }
            if (-not $tablePrinted) {
                $allCodes = @($flows | Where-Object { -not $_.Code }).Count -eq 0
                $anyExited = @($flows | Where-Object { $_.Process.HasExited }).Count -gt 0
                $waitedLong = ([DateTime]::UtcNow - $flows[0].StartedUtc).TotalSeconds -gt 20
                if ($allCodes -or $anyExited -or $waitedLong) { Write-CodeTable -Flows $flows; $tablePrinted = $true }
            }
            $running = @($flows | Where-Object { -not $_.Process.HasExited })
            if ($running.Count -eq 0) { break }
            if ([DateTime]::UtcNow -gt $deadline) { break }
            Start-Sleep -Milliseconds 500
        }
        foreach ($flow in $flows) {
            Update-DeviceFlow -Flow $flow
            $timedOut = -not $flow.Process.HasExited
            $exitCode = if ($timedOut) { -1 } else { $flow.Process.ExitCode }
            $verdict = Get-FlowVerdict -ExitCode $exitCode -Lines $flow.Lines -TimedOut:$timedOut
            $detail = if ($timedOut) { "no completion within $TimeoutMinutes min" } else { Get-LastLine ($flow.Lines -join "`n") }
            $results[$flow.Lane] = @{ Verdict = $verdict; Detail = $detail; Code = $flow.Code }
        }
    }
    finally {
        foreach ($flow in $flows) { Stop-DeviceFlow -Flow $flow }
    }
    return $results
}

# --- Chain ----------------------------------------------------------------------------------
# Sibling scripts run with the console inherited so their own prompts and browser
# steps keep working; only the exit code is interpreted.
function Invoke-SiblingScript {
    param([Parameter(Mandatory)][string]$ScriptPath, [string[]]$Arguments = @())
    $pwshExe = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $pwshExe) { $pwshExe = [Environment]::ProcessPath }
    & $pwshExe -NoProfile -File $ScriptPath @Arguments
    return $LASTEXITCODE
}

function Invoke-Chain {
    param([string]$Repository, [switch]$SkipGitHubApp, [switch]$SkipOpsIdentity, [switch]$DotSourced)
    $bootstrap = $PSScriptRoot

    # GitHub Models token: an export only reaches the caller when this script was
    # dot-sourced; a child process cannot set the parent's environment.
    if ($DotSourced) {
        if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_MODELS_TOKEN)) {
            Add-Lane -Name 'github-models-export' -State 'ready' -Detail 'GITHUB_MODELS_TOKEN already set (name checked only)'
        }
        else {
            $gh = Get-CliCommand -Name 'gh'
            $token = Invoke-Captured -FilePath $gh.Source -Arguments @('auth', 'token', '--hostname', 'github.com') -ClearGitHubTokens
            if ($token.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($token.StdOut)) {
                $exported = "$($token.StdOut)".Trim()
                [Environment]::SetEnvironmentVariable('GITHUB_MODELS_TOKEN', $exported)
                $exported = $null
                Add-Lane -Name 'github-models-export' -State 'ready' -Detail 'GITHUB_MODELS_TOKEN exported into this shell from the gh login (value not shown)'
            }
            else {
                Add-Lane -Name 'github-models-export' -State 'needs-owner' -Detail 'gh yielded no token' -OwnerAction 'export GITHUB_MODELS_TOKEN=$(gh auth token)'
            }
        }
    }
    else {
        Add-Lane -Name 'github-models-export' -State 'needs-owner' -Detail 'a child process cannot export into your shell' -OwnerAction 'dot-source instead: . scripts/bootstrap/connect-devices.ps1   (bash: source scripts/bootstrap/connect-github.sh)'
    }

    if ($SkipGitHubApp) {
        Add-Lane -Name 'github-app' -State 'skipped' -Detail '-SkipGitHubApp'
    }
    else {
        $path = Join-Path $bootstrap 'connect-github-app.ps1'
        Write-Report "  + pwsh $path -Repository $Repository -DispatchGovernance"
        $code = Invoke-SiblingScript -ScriptPath $path -Arguments @('-Repository', $Repository, '-DispatchGovernance')
        switch ($code) {
            0 { Add-Lane -Name 'github-app' -State 'ready' -Detail 'App registered, installed, governance dispatched' }
            2 { Add-Lane -Name 'github-app' -State 'needs-owner' -Detail 'connect-github-app.ps1 exited 2' -OwnerAction "pwsh scripts/bootstrap/connect-github-app.ps1 -DispatchGovernance (its Next column names the step)" }
            default { Add-Lane -Name 'github-app' -State 'failed' -Detail "connect-github-app.ps1 exited $code"; Add-Replay -Command "pwsh scripts/bootstrap/connect-github-app.ps1 -Repository $Repository -DispatchGovernance" }
        }
    }

    if ($SkipOpsIdentity) {
        Add-Lane -Name 'ops-identity' -State 'skipped' -Detail '-SkipOpsIdentity'
    }
    else {
        $path = Join-Path $bootstrap 'connect-admin.ps1'
        Write-Report "  + pwsh $path -SkipGitHub -Repository $Repository"
        $code = Invoke-SiblingScript -ScriptPath $path -Arguments @('-SkipGitHub', '-Repository', $Repository)
        switch ($code) {
            0 { Add-Lane -Name 'ops-identity' -State 'ready' -Detail 'setup-tenant -OpsIdentity applied; export the three AZURE_* names it printed' }
            2 { Add-Lane -Name 'ops-identity' -State 'needs-owner' -Detail 'connect-admin.ps1 exited 2' -OwnerAction 'pwsh scripts/bootstrap/connect-admin.ps1 -SkipGitHub (its Next column names the step)' }
            default { Add-Lane -Name 'ops-identity' -State 'failed' -Detail "connect-admin.ps1 exited $code"; Add-Replay -Command "pwsh scripts/bootstrap/connect-admin.ps1 -SkipGitHub -Repository $Repository" }
        }
    }

    $autoLogin = Join-Path $bootstrap 'auto-login.ps1'
    if ($DotSourced) {
        Write-Report "  + . $autoLogin"
        try { . $autoLogin; Add-Lane -Name 'vault-keys' -State 'ready' -Detail 'auto-login.ps1 dot-sourced (its own report above)' }
        catch { Add-Lane -Name 'vault-keys' -State 'failed' -Detail (Get-LastLine $_.Exception.Message); Add-Replay -Command '. scripts/bootstrap/auto-login.ps1' }
    }
    else {
        Write-Report "  + pwsh $autoLogin"
        $code = Invoke-SiblingScript -ScriptPath $autoLogin
        Add-Lane -Name 'vault-keys' -State $(if ($code -eq 0) { 'ready' } else { 'needs-owner' }) -Detail "auto-login.ps1 exited $code (exports need dot-sourcing)" -OwnerAction '. scripts/bootstrap/auto-login.ps1'
    }

    $doctor = Join-Path $bootstrap 'auth-doctor.ps1'
    Write-Report "  + pwsh $doctor -Json"
    $code = Invoke-SiblingScript -ScriptPath $doctor -Arguments @('-Json')
    Add-Lane -Name 'doctor' -State $(if ($code -eq 0) { 'ready' } else { 'needs-owner' }) -Detail "auth-doctor.ps1 -Json exited $code" -OwnerAction $(if ($code -eq 0) { '' } else { 'pwsh scripts/bootstrap/auth-doctor.ps1 (read its lane table)' })

    $bash = Get-CliCommand -Name 'bash'
    $firstRunSh = Join-Path $bootstrap 'first-run.sh'
    if ($bash -and (Test-Path -LiteralPath $firstRunSh)) {
        Write-Report "  + bash $firstRunSh --verify-only"
        & $bash.Source $firstRunSh --verify-only
        $code = $LASTEXITCODE
    }
    else {
        $firstRunPs = Join-Path $bootstrap 'first-run.ps1'
        Write-Report "  + pwsh $firstRunPs -VerifyOnly"
        $code = Invoke-SiblingScript -ScriptPath $firstRunPs -Arguments @('-VerifyOnly')
    }
    Add-Lane -Name 'first-run' -State $(if ($code -eq 0) { 'ready' } else { 'failed' }) -Detail "first-run verify-only exited $code (its checklist lists what is left)"
    if ($code -ne 0) { Add-Replay -Command 'bash scripts/bootstrap/first-run.sh --verify-only' }
}

# --- Main flow -------------------------------------------------------------------------------
function Invoke-ConnectDevices {
    param(
        [switch]$VerifyOnly,
        [switch]$Json,
        [switch]$Retry,
        [string]$Tenant = '349e1399-dccf-45b1-af7e-05d7b0676abf',
        [string]$Repository = 'Yolkster64/helios-platform',
        [switch]$SkipGitHubApp,
        [switch]$SkipOpsIdentity,
        [switch]$SkipChain,
        [double]$TimeoutMinutes = 15,
        [switch]$DotSourced
    )
    $script:jsonMode = [bool]$Json
    $script:lanes = [System.Collections.Generic.List[object]]::new()
    $script:replay = [System.Collections.Generic.List[string]]::new()
    $mode = if ($VerifyOnly) { 'verify-only' } else { 'apply' }
    if ($TimeoutMinutes -le 0) { $TimeoutMinutes = 15 }

    Write-Report "connect-devices: mode=$mode tenant=$Tenant repository=$Repository"
    if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') {
        return (Write-Precondition -Message "-Repository must be owner/name (got '$Repository')" -Mode $mode -Repository $Repository -Tenant $Tenant)
    }
    if ($Tenant -notmatch '^[0-9a-fA-F-]{36}$') {
        return (Write-Precondition -Message "-Tenant must be a tenant id (got '$Tenant')" -Mode $mode -Repository $Repository -Tenant $Tenant)
    }
    $missing = @()
    foreach ($cli in 'gh', 'az') { if (-not (Get-CliCommand -Name $cli)) { $missing += $cli } }
    if ($missing.Count -gt 0) {
        return (Write-Precondition -Message "not installed: $($missing -join ', ')" -Fix @('gh: https://cli.github.com', 'az: https://aka.ms/installazurecli', 'or: pwsh scripts/bootstrap/setup-all.ps1') -Mode $mode -Repository $Repository -Tenant $Tenant)
    }

    # Verify-first: a lane that already holds a session is never asked for a code.
    $ghReady = Test-GhReady
    $azReady = Test-AzReady -Tenant $Tenant
    $ghSpec = Get-DeviceFlowSpec -Lane 'github'
    $azSpec = Get-DeviceFlowSpec -Lane 'azure' -Tenant $Tenant
    $pending = @()
    if ($ghReady) { Add-Lane -Name 'github-login' -State 'ready' -Detail 'gh already logged in to github.com (active account)' } else { $pending += $ghSpec }
    if ($azReady) { Add-Lane -Name 'azure-login' -State 'ready' -Detail "az already holds a live token for tenant $Tenant" } else { $pending += $azSpec }

    if ($VerifyOnly) {
        foreach ($spec in $pending) {
            $lane = if ($spec.Lane -eq 'github') { 'github-login' } else { 'azure-login' }
            Add-Lane -Name $lane -State 'needs-owner' -Detail 'not logged in' -OwnerAction "$($spec.Command) $($spec.Arguments -join ' ')   # or: pwsh $($script:scriptRel)"
        }
        $chainText = if ($SkipChain) { 'skipped (-SkipChain)' } else { "connect-github-app$(if ($SkipGitHubApp) { ' (skipped)' }), connect-admin -SkipGitHub$(if ($SkipOpsIdentity) { ' (skipped)' }), auto-login, auth-doctor -Json, first-run --verify-only" }
        Add-Lane -Name 'chain' -State 'skipped' -Detail "verify-only; would run: $chainText"
        return (Write-Summary -Mode $mode -Repository $Repository -Tenant $Tenant)
    }

    if ($pending.Count -gt 0) {
        Write-Report "  starting $($pending.Count) device flow(s) together:"
        foreach ($spec in $pending) { Write-Report "    $($spec.Command) $($spec.Arguments -join ' ')" }
        $results = Invoke-DeviceFlows -Specs $pending -TimeoutMinutes $TimeoutMinutes
        $expired = @($pending | Where-Object { $results[$_.Lane].Verdict -eq 'expired' })
        if ($Retry -and $expired.Count -gt 0) {
            Write-Report "  re-issuing $($expired.Count) expired code(s) once (-Retry):"
            $again = Invoke-DeviceFlows -Specs $expired -TimeoutMinutes $TimeoutMinutes
            foreach ($lane in $again.Keys) { $results[$lane] = $again[$lane] }
        }
        foreach ($spec in $pending) {
            $lane = if ($spec.Lane -eq 'github') { 'github-login' } else { 'azure-login' }
            $outcome = $results[$spec.Lane]
            $verified = if ($outcome.Verdict -eq 'ready') { if ($spec.Lane -eq 'github') { Test-GhReady } else { Test-AzReady -Tenant $Tenant } } else { $false }
            if ($outcome.Verdict -eq 'ready' -and $verified) {
                Add-Lane -Name $lane -State 'ready' -Detail "device code accepted; $($spec.Command) session verified"
                if ($spec.Lane -eq 'github') { $ghReady = $true } else { $azReady = $true }
            }
            elseif ($outcome.Verdict -eq 'ready') {
                Add-Lane -Name $lane -State 'failed' -Detail "$($spec.Command) exited 0 but the session probe still fails" -OwnerAction "$($spec.Command) $($spec.Arguments -join ' ')"
                Add-Replay -Command "$($spec.Command) $($spec.Arguments -join ' ')"
            }
            else {
                $action = if ($outcome.Verdict -eq 'expired') { "pwsh $($script:scriptRel) -Retry" } else { "pwsh $($script:scriptRel)" }
                Add-Lane -Name $lane -State 'needs-owner' -Detail "$($outcome.Verdict): $($outcome.Detail)" -OwnerAction $action
            }
        }
    }

    if ($SkipChain) {
        Add-Lane -Name 'chain' -State 'skipped' -Detail '-SkipChain'
    }
    elseif (-not ($ghReady -and $azReady)) {
        Add-Lane -Name 'chain' -State 'skipped' -Detail 'both logins must be ready first'
    }
    else {
        Write-Report ''
        Write-Report '  both logins ready - running the chain:'
        Invoke-Chain -Repository $Repository -SkipGitHubApp:$SkipGitHubApp -SkipOpsIdentity:$SkipOpsIdentity -DotSourced:$DotSourced
    }
    return (Write-Summary -Mode $mode -Repository $Repository -Tenant $Tenant)
}

# Dot-sourced (`. scripts/bootstrap/connect-devices.ps1`) the script must `return`, not
# `exit` - `exit` would close the caller's shell - and only then can it export into it.
$connectDevicesDotSourced = ($MyInvocation.InvocationName -eq '.')
$connectDevicesExit = Invoke-ConnectDevices @PSBoundParameters -DotSourced:$connectDevicesDotSourced
if ($connectDevicesDotSourced) { return }
exit $connectDevicesExit
