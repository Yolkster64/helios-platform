#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Seeds absorption-benchmark tasks from the watchlist onto a live fleet board.

.DESCRIPTION
    Connects the absorption program to the Hermes/XCore fleet: every watchlist
    candidate (config/absorption/pr-watchlist.json) becomes one kanban task
    whose prompt is the absorb-pr benchmark command for that PR, enqueued onto
    a RUNNING fleet run's board through the lock-aware enqueue
    (python3 -m helios_agents.fleet_worker --enqueue) — never by hand-editing
    the board, which can race the workers' claim mutations.

    The target board comes from the run manifest (.helios/fleet/<runId>/
    manifest.json), the same discovery stop-fleet.ps1 uses: pass -RunId, or the
    latest run with status 'running' is used. Tasks carry deterministic ids
    (absorb-pr-<N>), and candidates whose id already exists on the board are
    skipped, so re-seeding after adding watchlist entries is safe.

.PARAMETER RunId
    Fleet run to seed. Default: the latest run whose manifest status is 'running'.

.PARAMETER Board
    Board name within the run to seed (default xcore-infra — absorption
    benchmarks are infrastructure work per ABSORPTION_PIPELINE.md).

.PARAMETER Epic
    Only seed candidates tagged with this ledger epic (e.g. E14). Default: all.

.PARAMETER Status
    Only seed candidates with this watchlist status (default 'candidate';
    'benchmarked' re-queues already-benchmarked PRs, e.g. after a base change).

.PARAMETER Max
    Cap the number of tasks enqueued this pass (0 = no cap).

.PARAMETER DryRun
    Print the tasks that would be enqueued without touching the board.

.EXAMPLE
    pwsh scripts/fleet/seed-absorption-tasks.ps1 -DryRun
.EXAMPLE
    pwsh scripts/fleet/seed-absorption-tasks.ps1 -Epic E14 -Max 5
#>
[CmdletBinding()]
param(
    [string]$RunId = '',
    [string]$Board = 'xcore-infra',
    [string]$Epic = '',
    [string]$Status = 'candidate',
    [int]$Max = 0,
    [switch]$DryRun,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
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

# ---- watchlist -------------------------------------------------------------
$watchlistPath = Join-Path $RepoRoot 'config' 'absorption' 'pr-watchlist.json'
if (-not (Test-Path $watchlistPath)) {
    Write-Error "Watchlist not found: $watchlistPath"
    exit 1
}
$watchlist = Get-Content -Raw -Path $watchlistPath | ConvertFrom-Json
$candidates = @($watchlist.candidates | Where-Object {
        ([string](Get-OptionalProperty $_ 'status' '')) -eq $Status -and
        ($Epic -eq '' -or ([string](Get-OptionalProperty $_ 'epic' '')) -eq $Epic)
    })
if ($candidates.Count -eq 0) {
    Write-Host "No watchlist candidates match (status='$Status'$(if ($Epic) { ", epic='$Epic'" })) - nothing to seed."
    exit 0
}
if ($Max -gt 0 -and $candidates.Count -gt $Max) {
    $candidates = @($candidates | Select-Object -First $Max)
}

# ---- run + board discovery (same rules as stop-fleet.ps1) ------------------
$fleetDir = Join-Path $RepoRoot '.helios' 'fleet'
$manifestPath = $null
if ($RunId) {
    $manifestPath = Join-Path $fleetDir $RunId 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Write-Error "No manifest for run '$RunId' under $fleetDir."
        exit 1
    }
}
elseif (Test-Path $fleetDir) {
    $candidateManifests = @(Get-ChildItem -Directory $fleetDir | Sort-Object Name |
            ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ })
    $runningManifests = @($candidateManifests | Where-Object {
            (Get-OptionalProperty (Get-Content -Raw -Path $_ | ConvertFrom-Json) 'status' '') -eq 'running' })
    if ($runningManifests.Count -gt 0) { $manifestPath = $runningManifests[-1] }
}
if (-not $manifestPath) {
    Write-Error ("No running fleet run found under $fleetDir - start one first " +
        '(pwsh scripts/fleet/start-fleet.ps1) or pass -RunId.')
    exit 1
}
$manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
$pool = @(Get-OptionalProperty $manifest 'pools' @()) |
    Where-Object { ([string](Get-OptionalProperty $_ 'board' '')) -eq $Board } |
    Select-Object -First 1
if (-not $pool) {
    $known = (@(Get-OptionalProperty $manifest 'pools' @()) |
        ForEach-Object { Get-OptionalProperty $_ 'board' '?' }) -join ', '
    Write-Error "Run $($manifest.runId) has no board '$Board'. Boards: $known"
    exit 1
}
$db = [string]$pool.db
$lock = [string]$pool.claimLock
Write-Host "Seeding board '$Board' (run $($manifest.runId)): $($candidates.Count) candidate(s), lane 'infrastructure'."

# ---- python (the lock-aware enqueue lives in the fleet worker) -------------
$python = $null
foreach ($name in @('python3', 'python')) {
    $python = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($python) { break }
}
if (-not $python -and -not $DryRun) {
    Write-Error 'python3 is required for the lock-aware enqueue (helios_agents.fleet_worker).'
    exit 1
}

# Best-effort duplicate skip: deterministic ids make re-seeding idempotent.
# This read is advisory (unlocked); the enqueue itself re-reads under the lock.
$existingIds = @{}
if (Test-Path $db) {
    foreach ($task in @(Get-OptionalProperty (Get-Content -Raw -Path $db | ConvertFrom-Json) 'tasks' @())) {
        $tid = [string](Get-OptionalProperty $task 'id' '')
        if ($tid) { $existingIds[$tid] = $true }
    }
}

$enqueued = 0
$skipped = 0
$failed = 0
foreach ($candidate in $candidates) {
    $pr = [int]$candidate.pr
    $taskId = "absorb-pr-$pr"
    if ($existingIds.ContainsKey($taskId)) {
        $skipped++
        continue
    }
    $epicTag = [string](Get-OptionalProperty $candidate 'epic' '')
    $task = [ordered]@{
        id     = $taskId
        lane   = 'infrastructure'
        status = 'open'
        epic   = $epicTag
        prompt = ("Benchmark upstream PR #$pr for absorption: run " +
            "'pwsh scripts/absorption/absorb-pr.ps1 -PrNumber $pr' from the repo root, " +
            "then summarize the verdict from .helios/absorption/pr-$pr.json. " +
            "Epic $epicTag - $($candidate.title). Terminate via kanban_complete " +
            'with the verdict, or kanban_block if the benchmark cannot run.')
    } | ConvertTo-Json -Compress

    if ($DryRun) {
        Write-Host "  would enqueue: $taskId ($epicTag)"
        $enqueued++
        continue
    }

    $env:HERMES_KANBAN_DB = $db
    $env:HERMES_KANBAN_CLAIM_LOCK = $lock
    try {
        Push-Location (Join-Path $RepoRoot 'src' 'ai' 'python')
        try {
            & $python.Source -m helios_agents.fleet_worker --enqueue $task 2>&1 | Out-Null
            $exit = $LASTEXITCODE
        }
        finally { Pop-Location }
    }
    finally {
        Remove-Item -Path 'Env:HERMES_KANBAN_DB', 'Env:HERMES_KANBAN_CLAIM_LOCK' -ErrorAction SilentlyContinue
    }

    if ($exit -eq 0) {
        Write-Host "  enqueued: $taskId ($epicTag)"
        $enqueued++
    }
    else {
        Write-Warning "enqueue failed for $taskId (exit $exit)"
        $failed++
    }
}

Write-Host ''
Write-Host "Seeded: $enqueued$(if ($DryRun) { ' (dry run)' })  skipped-existing: $skipped  failed: $failed"
if (-not $DryRun -and $enqueued -gt 0) {
    Write-Host "Status: pwsh scripts/fleet/fleet-status.ps1 -RunId $($manifest.runId)"
}
exit $(if ($failed -gt 0) { 1 } else { 0 })
