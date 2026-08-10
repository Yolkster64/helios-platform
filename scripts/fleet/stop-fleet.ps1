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
    # process, so leave it alone. If either side is unreadable, be conservative
    # and skip rather than kill a stranger.
    if ($ExpectedStartTime) {
        $actualStart = $null
        try { $actualStart = $proc.StartTime.ToUniversalTime() } catch { }
        if ($null -eq $actualStart) { return 'pid-unverifiable' }
        $expected = [datetime]::Parse($ExpectedStartTime, $null,
            [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        if ([math]::Abs(($actualStart - $expected).TotalSeconds) -gt 2) { return 'pid-reused' }
    }

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
    $running = @($manifestFiles | Where-Object {
            (Get-OptionalProperty (Get-Content -Raw -Path $_ | ConvertFrom-Json) 'status' 'running') -eq 'running' })
    if ($running.Count -eq 0) {
        Write-Host 'No running fleet runs found. Nothing to stop.'
        exit 0
    }
    $manifestFiles = if ($All) { $running } else { @($running | Select-Object -Last 1) }
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
    $manifest.status = 'stopped'
    $stoppedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($null -ne $manifest.PSObject.Properties['stoppedAt']) { $manifest.stoppedAt = $stoppedAt }
    else { $manifest | Add-Member -NotePropertyName 'stoppedAt' -NotePropertyValue $stoppedAt }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8
    Write-Host ("  run {0}: {1} stopped, {2} killed, {3} already exited, {4} pid reused/unverifiable (left alone)" -f
        $manifestRunId, $counts['stopped'], $counts['killed'], $counts['already-exited'],
        ($counts['pid-reused'] + $counts['pid-unverifiable']))
}
exit 0
