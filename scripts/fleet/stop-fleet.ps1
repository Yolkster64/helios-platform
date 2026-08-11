#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Stops fleet workers started by scripts/fleet/start-fleet.ps1.

.DESCRIPTION
    Reads run manifest(s) from .helios/fleet/<runId>/manifest.json and stops
    every worker pid recorded there. On Linux/macOS workers get SIGTERM first
    (the stub exits cleanly, releasing any claim lock) and are force-killed only
    if still alive after ~2 seconds; on Windows they are stopped directly.
    The manifest is then marked status=stopped. Idempotent: already-exited
    workers are reported, never an error.

.PARAMETER RunId
    The run to stop. Default: the most recent run whose manifest still says
    status=running.

.PARAMETER All
    Stop every run whose manifest says status=running.

.EXAMPLE
    pwsh scripts/fleet/stop-fleet.ps1
.EXAMPLE
    pwsh scripts/fleet/stop-fleet.ps1 -RunId 20260810-120000-ab12cd
#>
[CmdletBinding()]
param(
    [string]$RunId = '',
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function Stop-FleetWorker {
    param([int]$WorkerPid, [string]$ExpectedStartTime)
    $proc = Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue
    if (-not $proc) { return 'already-exited' }

    # Identity check before killing: after a worker exits naturally its pid can be
    # reused by an unrelated process. The manifest records the worker's start time;
    # a mismatch (beyond 2s tolerance for clock rounding) means this is not our
    # process, so leave it alone. BOTH halves are required: start-fleet can record
    # a null start time when the read failed, and killing on pid alone would hit
    # whatever process reused it — unverifiable means untouchable.
    if (-not $ExpectedStartTime) { return 'pid-unverifiable' }
    $actualStart = $null
    try { $actualStart = $proc.StartTime.ToUniversalTime() } catch { }
    if ($null -eq $actualStart) { return 'pid-unverifiable' }
    $expected = $null
    try {
        $expected = [datetime]::Parse($ExpectedStartTime, $null,
            [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    }
    catch { return 'pid-unverifiable' }
    if ([math]::Abs(($actualStart - $expected).TotalSeconds) -gt 2) { return 'pid-reused' }

    if (-not $IsWindows) {
        & kill -TERM $WorkerPid 2> $null
        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 100
            if (-not (Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue)) { return 'stopped' }
        }
    }
    Stop-Process -Id $WorkerPid -Force -ErrorAction SilentlyContinue
    return 'killed'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$fleetDir = Join-Path $repoRoot '.helios' 'fleet'
if (-not (Test-Path $fleetDir)) {
    Write-Host "No fleet runs found ($fleetDir does not exist). Nothing to stop."
    exit 0
}

$manifestFiles = @(Get-ChildItem -Path $fleetDir -Directory | Sort-Object -Property Name |
        ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ })
if ($RunId) {
    $manifestFiles = @($manifestFiles | Where-Object {
            (Split-Path -Leaf (Split-Path -Parent $_)) -eq $RunId })
    if ($manifestFiles.Count -eq 0) {
        Write-Error "No manifest found for run '$RunId' under $fleetDir."
        exit 1
    }
}
else {
    # 'stopped-partial' is selectable on purpose: such a run may still have a
    # live-but-unverifiable worker, and excluding it would mean the orphan is
    # only ever retried when an operator hand-supplies -RunId.
    $stoppable = @($manifestFiles | ForEach-Object {
            [pscustomobject]@{
                Path   = $_
                Status = [string](Get-OptionalProperty (Get-Content -Raw -Path $_ | ConvertFrom-Json) 'status' 'running')
            }
        } | Where-Object { $_.Status -in @('running', 'stopped-partial') })
    if ($stoppable.Count -eq 0) {
        Write-Host 'No running (or partially stopped) fleet runs found. Nothing to stop.'
        exit 0
    }
    $manifestFiles = if ($All) { @($stoppable | ForEach-Object Path) }
    else {
        # The default stays "stop the most recent RUNNING run"; a
        # stopped-partial run is retried only when no running run exists.
        # Otherwise a newest run stuck partial on a permanently unverifiable
        # worker would be re-selected forever while older running runs'
        # workers were stranded.
        $runningOnly = @($stoppable | Where-Object { $_.Status -eq 'running' })
        $pick = if ($runningOnly.Count -gt 0) { $runningOnly[-1] } else { $stoppable[-1] }
        @($pick.Path)
    }
}

foreach ($manifestPath in $manifestFiles) {
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    $manifestRunId = [string](Get-OptionalProperty $manifest 'runId' '?')
    Write-Host "Stopping run $manifestRunId ..."
    $counts = @{ 'stopped' = 0; 'killed' = 0; 'already-exited' = 0; 'pid-reused' = 0; 'pid-unverifiable' = 0 }
    foreach ($pool in @(Get-OptionalProperty $manifest 'pools' @())) {
        foreach ($worker in @(Get-OptionalProperty $pool 'workers' @())) {
            $workerPid = [int](Get-OptionalProperty $worker 'pid' 0)
            $assignee = [string](Get-OptionalProperty $worker 'assignee' '?')
            $startTime = [string](Get-OptionalProperty $worker 'startTime' '')
            if ($workerPid -le 0) { continue }
            $outcome = Stop-FleetWorker -WorkerPid $workerPid -ExpectedStartTime $startTime
            $counts[$outcome]++
            Write-Host "  $assignee (pid $workerPid): $outcome"
        }
    }
    # A pid-unverifiable worker may STILL BE ALIVE (identity could not be
    # confirmed either way, so it was deliberately not killed). 'stopped-partial'
    # keeps the run visible AND selectable — default and -All stop passes
    # re-include it (see the discovery filter above) so the orphan is retried
    # automatically; pid-reused is different — that process is definitively
    # not ours.
    $manifest.status = if ($counts['pid-unverifiable'] -gt 0) { 'stopped-partial' } else { 'stopped' }
    $stoppedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($null -ne $manifest.PSObject.Properties['stoppedAt']) { $manifest.stoppedAt = $stoppedAt }
    else { $manifest | Add-Member -NotePropertyName 'stoppedAt' -NotePropertyValue $stoppedAt }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8
    Write-Host ("  run {0}: {1} stopped, {2} killed, {3} already exited, {4} pid reused/unverifiable (left alone)" -f
        $manifestRunId, $counts['stopped'], $counts['killed'], $counts['already-exited'],
        ($counts['pid-reused'] + $counts['pid-unverifiable']))
    if ($counts['pid-unverifiable'] -gt 0) {
        # Parentheses around the concatenation matter: -f binds tighter than
        # +, so without them the placeholders would print literally.
        Write-Warning (("run {0}: {1} worker(s) could not be identity-verified and were left " +
            "alone - they may still be running. Manifest kept as 'stopped-partial'; check the " +
            'pids above manually and rerun stop-fleet.ps1 -RunId {0} once resolved.') -f
            $manifestRunId, $counts['pid-unverifiable'])
    }
}
exit 0
