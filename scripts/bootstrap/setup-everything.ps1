<#
.SYNOPSIS
One command that connects and verifies everything: a thin ordered chain over the
EXISTING scripts — toolchain -> identity -> auth -> inventory -> stack smoke —
ending in one consolidated, deduped owner-action list.

.DESCRIPTION
Orchestrator only (repo rule: PowerShell wraps, it never reimplements). Every step
runs the script that owns the area via `pwsh -NoProfile -File <script> -Json`,
capturing its report object and exit code:

  1. scripts/build/verify-readiness.ps1      toolchain
  2. scripts/bootstrap/connect-account.ps1   IDENTITY GATE: any mismatch lane aborts
                                             the chain immediately with exit 2 —
                                             connect-account's own rule: acting as the
                                             wrong account is worse than acting
                                             unauthenticated.
  3. scripts/bootstrap/auth-doctor.ps1       auth lanes (-Apply passes through; never
                                             applied by default, never interactive)
  4. scripts/setup/setup-all.ps1             unified readiness inventory
  5. scripts/verify/stack-smoke.ps1          SOFT: a missing script or failure is
                                             recorded (unavailable/failed) and the
                                             chain continues.

A step that emits invalid JSON is recorded as a failed step, never a crash. Default
output is one section per step plus the consolidated owner-action list (every
ownerAction/nextCommand field across the captured reports, deduped, order kept).
-Json emits one rollup object instead:

  {script, generatedUtc, mode, steps[{step, script, state, exitCode, summary}],
   ownerActions[], readinessIssues[], executionSucceeded, ready, exitCode}

executionSucceeded means every step returned successfully (a missing soft step is
allowed). ready additionally requires affirmative child readiness evidence, no
unresolved lanes/components, and no remaining owner actions. Neither flag proves
paid provider inference or a deployed environment.

Exit codes: 0 = every step clean or degraded-as-designed (degradation is reported,
report-first contract of the chained scripts); 2 = identity mismatch (always, even
report-only) or an -Apply run that left auth-doctor with unresolved gating lanes;
1 = internal failure — this script's own, or any required (non-soft) step that
could not run at all (script missing, unparsable output, or the child's exit 1).

.PARAMETER Apply
Pass -Apply through to auth-doctor.ps1: automatic NON-INTERACTIVE repair only
(service principal / managed identity). Off by default.

.PARAMETER Json
Emit the single rollup object (nothing else on stdout — chained-script convention).

.PARAMETER RequireReady
Exit 2 if reported readiness is incomplete. Default report-only exit behavior stays
unchanged; automation can opt into this stricter gate without enabling -Apply.

.EXAMPLE
pwsh scripts/bootstrap/setup-everything.ps1

.EXAMPLE
pwsh scripts/bootstrap/setup-everything.ps1 -Apply

.EXAMPLE
pwsh scripts/bootstrap/setup-everything.ps1 -Json | ConvertFrom-Json
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Apply,

    [switch]$Json,

    [switch]$RequireReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modeLabel = if ($Apply) { 'apply' } else { 'report-only' }

# -Json promises one object and nothing else on stdout (auth-doctor convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

# Children run in their own pwsh process so exit codes and StrictMode stay isolated
# and their -Json stdout comes back clean (setup-all.ps1 pattern).
$pwshCommand = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$pwshExe = if ($pwshCommand) { $pwshCommand.Source } else { [Environment]::ProcessPath }

function Get-StepSummary {
    # Summary-ish extract, shape-tolerant: summary objects (connect-account,
    # auth-doctor, stack-smoke) or ready/required/components (verify-readiness,
    # setup-all). Extraction only — the child report stays the source of truth.
    param($Report, [int]$ExitCode)
    if ($null -eq $Report) { return "no parseable JSON (exit $ExitCode) — recorded as a failed step" }
    if ($Report.PSObject.Properties['summary'] -and $null -ne $Report.summary) {
        if ($Report.summary -is [string]) { return $Report.summary }
        return (@($Report.summary.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ' ')
    }
    if ($Report.PSObject.Properties['ready']) {
        $extract = "ready=$($Report.ready)"
        if ($Report.PSObject.Properties['required']) {
            $missing = @($Report.required | Where-Object { -not $_.Found } | ForEach-Object Tool)
            if ($missing.Count -gt 0) { $extract += '; missing required: ' + ($missing -join ', ') }
        }
        if ($Report.PSObject.Properties['components']) {
            $attention = @($Report.components | Where-Object { $_.status -ne 'ready' } | ForEach-Object component)
            if ($attention.Count -gt 0) { $extract += '; needs-attention: ' + ($attention -join ', ') }
        }
        return $extract
    }
    return "exit $ExitCode"
}

function Get-OwnerAction {
    # Harvest every ownerAction/nextCommand a captured report carries — lanes
    # (connect-account, auth-doctor, stack-smoke) and components (setup-all) alike.
    param($Report)
    if ($null -eq $Report) { return }
    if ($Report.PSObject.Properties['ownerActions']) {
        foreach ($action in @($Report.ownerActions)) {
            if ($action -is [string] -and $action.Trim()) { $action.Trim() }
        }
    }
    foreach ($listName in 'lanes', 'components', 'steps') {
        if (-not $Report.PSObject.Properties[$listName]) { continue }
        foreach ($item in @($Report.$listName)) {
            if ($null -eq $item) { continue }
            foreach ($field in 'ownerAction', 'nextCommand') {
                if ($item.PSObject.Properties[$field] -and "$($item.$field)".Trim()) {
                    "$($item.$field)".Trim()
                }
            }
        }
    }
}

function Get-ReadinessIssue {
    # A child's exit 0 only proves that its reporting command completed. Keep its
    # readiness assertions separate, including non-gating and soft-step gaps.
    param($Step)
    $report = $Step.report
    if ($null -eq $report) { "$($Step.step): readiness unavailable"; return }
    if ($Step.exitCode -ne 0) { "$($Step.step): exit $($Step.exitCode)" }
    $hasEvidence = $false
    if ($report.PSObject.Properties['ready']) {
        $hasEvidence = $true
        if ($report.ready -isnot [bool] -or -not $report.ready) {
            "$($Step.step): ready is not true"
        }
    }
    foreach ($listName in 'lanes', 'components') {
        if (-not $report.PSObject.Properties[$listName]) { continue }
        $items = @($report.$listName)
        if ($items.Count -eq 0) { "$($Step.step): empty $listName" }
        foreach ($item in $items) {
            $hasEvidence = $true
            if ($null -eq $item) { "$($Step.step): missing $listName entry"; continue }
            $stateField = if ($listName -eq 'lanes') { 'state' } else { 'status' }
            $nameField = if ($listName -eq 'lanes') { 'lane' } else { 'component' }
            if (-not $item.PSObject.Properties[$stateField]) {
                "$($Step.step): $listName entry has no $stateField"; continue
            }
            $label = if ($item.PSObject.Properties[$nameField]) { [string]$item.$nameField } else { $listName }
            if ($item.$stateField -notin @('ready', 'ok', 'repaired')) {
                "$($Step.step)/${label}: $($item.$stateField)"
            }
        }
    }
    if (-not $hasEvidence) { "$($Step.step): no readiness evidence" }
}

function Invoke-ChainStep {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Script,
        [string[]]$Arguments = @(),
        [bool]$Soft = $false
    )
    $scriptPath = Join-Path $repoRoot $Script
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $note = if ($Soft) { 'soft step — recorded, chain continues' } else { 'recorded as failed' }
        return [pscustomobject]@{
            step = $Step; script = $Script; state = if ($Soft) { 'unavailable' } else { 'failed' }
            exitCode = -1; summary = "script not found ($note)"; report = $null
        }
    }
    # Capture ALL output first, THEN read $LASTEXITCODE (repo pipeline-trap rule).
    $lines = @(& $pwshExe -NoProfile -File $scriptPath @Arguments 2>&1 | ForEach-Object { "$_" })
    $exit = [int]$LASTEXITCODE
    $report = $null
    try { $report = ($lines -join "`n") | ConvertFrom-Json -NoEnumerate }
    catch { Write-Verbose "$Step emitted invalid JSON: $($_.Exception.Message)" }
    # JSON scalars and arrays are not child report objects.
    if ($report -is [Array] -or $report -isnot [pscustomobject]) { $report = $null }
    if ($Step -eq 'identity' -and $null -ne $report) {
        $lanesProperty = $report.PSObject.Properties['lanes']
        $lanes = if ($lanesProperty) { @($lanesProperty.Value) } else { @() }
        $invalidLanes = @($lanes | Where-Object {
                $null -eq $_ -or -not $_.PSObject.Properties['lane'] -or
                -not $_.PSObject.Properties['state'] -or
                $_.state -notin @('ready', 'repaired', 'mismatch', 'needs-owner', 'unavailable')
            })
        if ($lanes.Count -eq 0 -or $invalidLanes.Count -gt 0) { $report = $null }
    }
    $state = if ($null -eq $report) { 'failed' } elseif ($exit -eq 0) { 'ok' } else { 'degraded' }
    [pscustomobject]@{
        step = $Step; script = $Script; state = $state; exitCode = $exit
        summary = (Get-StepSummary -Report $report -ExitCode $exit); report = $report
    }
}

try {
    if (-not $pwshExe) {
        [Console]::Error.WriteLine('setup-everything: cannot locate a PowerShell 7 executable (pwsh not on PATH, host process path unknown)')
        exit 1
    }

    $chainSpecs = @(
        @{ Step = 'toolchain'; Script = 'scripts/build/verify-readiness.ps1'; Arguments = @('-Json') }
        @{ Step = 'identity'; Script = 'scripts/bootstrap/connect-account.ps1'; Arguments = @('-Json') }
        @{ Step = 'auth'; Script = 'scripts/bootstrap/auth-doctor.ps1'; Arguments = @('-Json') + @(if ($Apply) { '-Apply' }) }
        @{ Step = 'inventory'; Script = 'scripts/setup/setup-all.ps1'; Arguments = @('-Json') }
        @{ Step = 'stack-smoke'; Script = 'scripts/verify/stack-smoke.ps1'; Arguments = @('-Json'); Soft = $true }
        @{ Step = 'rest-connect'; Script = 'scripts/verify/rest-connect.ps1'; Arguments = @('-Json'); Soft = $true }
    )

    Write-Report "== HELIOS setup-everything ($modeLabel) — ordered chain over existing scripts =="
    $steps = [System.Collections.Generic.List[object]]::new()
    $mismatchLanes = @()
    $stepNumber = 0
    foreach ($spec in $chainSpecs) {
        $stepNumber++
        $result = Invoke-ChainStep @spec
        $steps.Add($result)
        Write-Report ''
        Write-Report ('-- {0}. {1} ({2}) --' -f $stepNumber, $result.step, $result.script)
        Write-Report ('   {0} (exit {1}): {2}' -f $result.state, $result.exitCode, $result.summary)

        if ($result.step -ne 'identity') { continue }
        # IDENTITY GATE — connect-account's own rule: acting as the wrong account is
        # worse than acting unauthenticated, so any mismatch aborts the chain NOW.
        if ($result.report -and $result.report.PSObject.Properties['lanes']) {
            $mismatchLanes = @($result.report.lanes | Where-Object { $_.state -eq 'mismatch' } | ForEach-Object lane)
        }
        if ($mismatchLanes.Count -gt 0 -or $result.exitCode -eq 2) {
            if ($mismatchLanes.Count -eq 0) { $mismatchLanes = @('(unparsed — connect-account exited 2)') }
            Write-Report ''
            Write-Report ('IDENTITY MISMATCH on: ' + ($mismatchLanes -join ', ') + ' — chain ABORTED; later steps never ran.')
            break
        }
        # An identity step that could not run at all (script missing, unparsable
        # output, or an internal error) is just as gating as a mismatch: nothing
        # verified WHO we are, so -Apply must never reach auth-doctor's mutating
        # repair on the strength of it (review finding). Aborting here feeds the
        # exit-1 required-step-failed contract below.
        if ($result.state -eq 'failed' -or $result.exitCode -notin 0, 2) {
            Write-Report ''
            Write-Report ('IDENTITY UNVERIFIED: connect-account ' + $result.summary +
                ' — chain ABORTED before any auth repair; later steps never ran.')
            break
        }
    }

    $identityMismatch = $mismatchLanes.Count -gt 0
    $authStep = $steps | Where-Object { $_.step -eq 'auth' } | Select-Object -First 1
    $ownerActions = @($steps | ForEach-Object { Get-OwnerAction -Report $_.report } | Select-Object -Unique)
    $executionSucceeded = (-not $identityMismatch) -and ($steps.Count -eq $chainSpecs.Count) -and
        (@($steps | Where-Object { $_.state -notin @('ok', 'unavailable') }).Count -eq 0)
    $readinessIssues = @($steps | ForEach-Object { Get-ReadinessIssue -Step $_ })
    if ($steps.Count -ne $chainSpecs.Count) { $readinessIssues += 'chain: later checks did not run' }
    if ($ownerActions.Count -gt 0) { $readinessIssues += "owner: $($ownerActions.Count) action(s) remain" }
    $ready = $executionSucceeded -and $readinessIssues.Count -eq 0

    # A required (non-soft) step that could not run at all — script missing, output
    # not parseable as JSON, or a child internal error (the child's own exit 1) — is
    # this script's exit-1 internal-failure contract (review finding: automation must
    # not read an unparsable toolchain/identity/auth/inventory run as success).
    # Degraded-with-a-report (child exit 2) stays exit 0: that is the designed
    # report-first state the chained scripts document.
    # Index syntax, not dot notation: only the smoke spec defines a Soft key, and
    # under Set-StrictMode Latest reading a missing hashtable member as a property
    # throws — $_['Soft'] returns $null for the others instead (review finding).
    $softStepNames = @($chainSpecs | Where-Object { $_['Soft'] } | ForEach-Object { $_['Step'] })
    $requiredFailed = @($steps | Where-Object {
            $_.step -notin $softStepNames -and ($_.state -eq 'failed' -or $_.exitCode -notin 0, 2)
        } | ForEach-Object step)

    # Exit contract: 2 = identity mismatch (always gates, report-only included) or an
    # -Apply run whose auth-doctor left gating lanes unresolved (its own exit 2);
    # 1 = a required step failed outright (above); otherwise 0 — degraded steps are
    # reported via ownerActions, report-first.
    $exitCode = 0
    if ($identityMismatch) { $exitCode = 2 }
    elseif ($Apply -and $authStep -and $authStep.exitCode -eq 2) { $exitCode = 2 }
    elseif ($requiredFailed.Count -gt 0) { $exitCode = 1 }
    elseif ($RequireReady -and -not $ready) { $exitCode = 2 }

    if ($Json) {
        [ordered]@{
            script       = 'scripts/bootstrap/setup-everything.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            mode         = $modeLabel
            steps        = @($steps | ForEach-Object {
                    [ordered]@{ step = $_.step; script = $_.script; state = $_.state; exitCode = $_.exitCode; summary = $_.summary }
                })
            ownerActions = @($ownerActions)
            readinessIssues = @($readinessIssues)
            executionSucceeded = $executionSucceeded
            ready        = $ready
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 4
    }
    else {
        Write-Report ''
        Write-Report '== OWNER ACTIONS (every ownerAction/nextCommand across the chain, deduped) =='
        if ($ownerActions.Count -eq 0) { Write-Report '   none — nothing is waiting on the owner.' }
        else {
            $i = 0
            foreach ($action in $ownerActions) { $i++; Write-Report ('   {0}. {1}' -f $i, $action) }
        }
        Write-Report ''
        if ($identityMismatch) {
            Write-Report 'NOT ready: identity mismatch — fix it before doing anything else (acting as the wrong account is worse than acting unauthenticated).'
        }
        elseif ($ready) { Write-Report 'All reported checks are ready. Scope: setup checks; live provider inference and deployment are unverified.' }
        else {
            Write-Report 'Setup incomplete. Readiness gaps:'
            foreach ($issue in $readinessIssues) { Write-Report "   $issue" }
        }
    }

    exit $exitCode
}
catch {
    [Console]::Error.WriteLine("setup-everything: internal failure — $($_.Exception.Message)")
    exit 1
}
