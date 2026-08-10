#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Reports fleet worker state from the run manifests start-fleet.ps1 writes.

.DESCRIPTION
    Reads every .helios/fleet/<runId>/manifest.json (or just -RunId), probes
    each recorded worker pid, and reports per-pool running/exited counts plus
    overall totals. Also shows each run's board task tallies (open / claimed /
    done / blocked) so progress is visible without opening the board files.

.PARAMETER RunId
    Restrict the report to one run.

.PARAMETER Json
    Emit the full report as JSON on stdout for machine consumption.

.EXAMPLE
    pwsh scripts/fleet/fleet-status.ps1
.EXAMPLE
    pwsh scripts/fleet/fleet-status.ps1 -RunId 20260810-120000-ab12cd -Json
#>
[CmdletBinding()]
param(
    [string]$RunId = '',
    [switch]$Json
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

function Test-WorkerRunning {
    param([int]$WorkerPid)
    if ($WorkerPid -le 0) { return $false }
    return $null -ne (Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue)
}

function Get-BoardTally {
    param([string]$DbPath)
    $tally = [ordered]@{ open = 0; claimed = 0; done = 0; blocked = 0; other = 0 }
    if (-not ($DbPath -and (Test-Path $DbPath))) { return $tally }
    try { $board = Get-Content -Raw -Path $DbPath | ConvertFrom-Json }
    catch { return $tally }
    foreach ($task in @(Get-OptionalProperty $board 'tasks' @())) {
        $status = [string](Get-OptionalProperty $task 'status' 'open')
        if ($tally.Contains($status)) { $tally[$status]++ } else { $tally['other']++ }
    }
    return $tally
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$fleetDir = Join-Path $repoRoot '.helios' 'fleet'
$manifestFiles = @()
if (Test-Path $fleetDir) {
    $manifestFiles = @(Get-ChildItem -Path $fleetDir -Directory | Sort-Object -Property Name |
            ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ })
}
if ($RunId) {
    $manifestFiles = @($manifestFiles | Where-Object {
            (Split-Path -Leaf (Split-Path -Parent $_)) -eq $RunId })
    if ($manifestFiles.Count -eq 0) {
        Write-Error "No manifest found for run '$RunId' under $fleetDir."
        exit 1
    }
}

$runs = [System.Collections.Generic.List[object]]::new()
$totalRunning = 0
$totalExited = 0
$totalWorkers = 0

foreach ($manifestPath in $manifestFiles) {
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    $poolReports = [System.Collections.Generic.List[object]]::new()
    $runRunning = 0
    $runExited = 0
    foreach ($pool in @(Get-OptionalProperty $manifest 'pools' @())) {
        $workerReports = [System.Collections.Generic.List[object]]::new()
        $poolRunning = 0
        $poolExited = 0
        foreach ($worker in @(Get-OptionalProperty $pool 'workers' @())) {
            $workerPid = [int](Get-OptionalProperty $worker 'pid' 0)
            $isRunning = Test-WorkerRunning -WorkerPid $workerPid
            if ($isRunning) { $poolRunning++ } else { $poolExited++ }
            $workerReports.Add([ordered]@{
                    assignee = [string](Get-OptionalProperty $worker 'assignee' '?')
                    pid      = $workerPid
                    state    = if ($isRunning) { 'running' } else { 'exited' }
                })
        }
        $runRunning += $poolRunning
        $runExited += $poolExited
        $poolReports.Add([ordered]@{
                pool    = [string](Get-OptionalProperty $pool 'pool' '?')
                board   = [string](Get-OptionalProperty $pool 'board' '?')
                running = $poolRunning
                exited  = $poolExited
                tasks   = Get-BoardTally -DbPath ([string](Get-OptionalProperty $pool 'db' ''))
                workers = $workerReports
            })
    }
    $totalRunning += $runRunning
    $totalExited += $runExited
    $totalWorkers += $runRunning + $runExited
    $runs.Add([ordered]@{
            runId      = [string](Get-OptionalProperty $manifest 'runId' '?')
            startedAt  = [string](Get-OptionalProperty $manifest 'startedAt' '?')
            status     = [string](Get-OptionalProperty $manifest 'status' '?')
            workerKind = [string](Get-OptionalProperty $manifest 'workerKind' '?')
            running    = $runRunning
            exited     = $runExited
            pools      = $poolReports
        })
}

$report = [ordered]@{
    runs   = $runs
    totals = [ordered]@{
        runs    = $runs.Count
        workers = $totalWorkers
        running = $totalRunning
        exited  = $totalExited
    }
}

if ($Json) {
    $report | ConvertTo-Json -Depth 10
    exit 0
}

if ($runs.Count -eq 0) {
    Write-Host "No fleet runs found under $fleetDir. Start one: pwsh scripts/fleet/start-fleet.ps1"
    exit 0
}

foreach ($run in $runs) {
    Write-Host ("Run {0}  started {1}  kind={2}  manifest-status={3}" -f
        $run['runId'], $run['startedAt'], $run['workerKind'], $run['status'])
    foreach ($pool in $run['pools']) {
        $tally = $pool['tasks']
        Write-Host ("  {0,-16} board {1,-14} {2} running / {3} exited   tasks: {4} open, {5} claimed, {6} done, {7} blocked" -f
            $pool['pool'], $pool['board'], $pool['running'], $pool['exited'],
            $tally['open'], $tally['claimed'], $tally['done'], $tally['blocked'])
        foreach ($worker in $pool['workers']) {
            Write-Host ("    {0,-12} pid {1,-8} {2}" -f $worker['assignee'], $worker['pid'], $worker['state'])
        }
    }
    Write-Host ''
}
Write-Host ("Totals: {0} worker(s) across {1} run(s) - {2} running, {3} exited" -f
    $report['totals']['workers'], $report['totals']['runs'], $totalRunning, $totalExited)
exit 0
