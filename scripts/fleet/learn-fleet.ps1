#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Runs ONE fleet tandem-learning cycle: start (or attach), seed synthetic
    tasks, drain the boards, stop, collect outcomes, and summarize.

.DESCRIPTION
    Orchestrates the sibling fleet scripts and the Python spoke into a single
    learning cycle against a stub (or real Hermes) fleet:

      1. Start a fleet run via scripts/fleet/start-fleet.ps1 (the stub path is
         fine - workers do no model work), or attach to an existing RUNNING
         run with -RunId.
      2. Seed -SeedSynthetic synthetic tasks, spread round-robin across every
         pool board the run carries, through the lock-aware enqueue
         (python3 -m helios_agents.fleet_worker --enqueue, run from
         src/ai/python with HERMES_KANBAN_DB/_CLAIM_LOCK set per board from
         the run manifest - never by hand-editing a live board). Task lanes
         cycle through each pool's taskTypes from
         config/fleet/fleet-topology.json; roughly 1 in 6 tasks carries
         "block": true (and no prompt) so the kanban_block path is exercised
         alongside kanban_complete (see helios_agents/fleet_worker.py).
      3. Drain: poll fleet-status.ps1 -Json until no board has open/claimed
         tasks, all workers have exited with work still queued (stall), or
         -TimeoutSeconds elapses.
      4. Stop the run via stop-fleet.ps1 -RunId <id>.
      5. Collect + summarize through the helios_agents fleet ops:
           python3 -m helios_agents fleet-collect --run-dir <runDir> --outcomes .helios/learning/outcomes.jsonl
           python3 -m helios_agents fleet-summary --outcomes .helios/learning/outcomes.jsonl --scale-log .helios/fleet/scale-log.jsonl
         These ops land in a parallel change; when they are not available yet
         the cycle degrades with a clear warning instead of failing.
      6. Advisory plan: `dotnet run --project src/ai/HELIOS.AIHub.Cli
         -c Release -- fleet-plan --json` (also landing in parallel). An
         unknown command or a missing dotnet is a soft degrade with a notice,
         never a failure - the plan is advisory and never auto-executes.
      7. Write .helios/fleet/learning-report.json:
         {at, runId, seeded, drained, collected, summary, fleetPlan} with
         fleetPlan null when unavailable.

    Exit 1 when any enqueue fails, the boards do not drain, or stop-fleet
    fails; missing collect/summary/fleet-plan ops are warnings only.

.PARAMETER RunId
    Attach to this existing run (its manifest must say status=running)
    instead of starting a new one. The run is still stopped at the end of the
    cycle - a learning cycle terminates its run so collection sees final
    board states.

.PARAMETER SeedSynthetic
    Number of synthetic tasks to enqueue across the pool boards (default 12).

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the boards to drain (default 300).

.PARAMETER DryRun
    Print the full cycle plan (including every task that would be enqueued)
    without starting, seeding, stopping, or writing anything.

.EXAMPLE
    pwsh scripts/fleet/learn-fleet.ps1 -DryRun
.EXAMPLE
    pwsh scripts/fleet/learn-fleet.ps1 -SeedSynthetic 24
.EXAMPLE
    pwsh scripts/fleet/learn-fleet.ps1 -RunId 20260813-120000-ab12cd
#>
[CmdletBinding()]
param(
    [string]$RunId = '',
    [ValidateRange(1, 500)]
    [int]$SeedSynthetic = 12,
    [ValidateRange(5, 86400)]
    [int]$TimeoutSeconds = 300,
    [switch]$DryRun
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

# ---- paths and topology ------------------------------------------------------
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$fleetDir = Join-Path $repoRoot '.helios' 'fleet'
$pythonWorkDir = Join-Path $repoRoot 'src' 'ai' 'python'
$outcomesPath = Join-Path $repoRoot '.helios' 'learning' 'outcomes.jsonl'
$scaleLogPath = Join-Path $fleetDir 'scale-log.jsonl'
$reportPath = Join-Path $fleetDir 'learning-report.json'
$startFleetScript = Join-Path $PSScriptRoot 'start-fleet.ps1'
$fleetStatusScript = Join-Path $PSScriptRoot 'fleet-status.ps1'
$stopFleetScript = Join-Path $PSScriptRoot 'stop-fleet.ps1'

$topologyPath = Join-Path $repoRoot 'config' 'fleet' 'fleet-topology.json'
if (-not (Test-Path $topologyPath)) {
    Write-Error "Fleet topology not found: $topologyPath"
    exit 1
}
$topology = Get-Content -Raw -Path $topologyPath | ConvertFrom-Json

# Seed targets come from the topology: one entry per pool with its board name
# and its taskTypes (the lanes its workers claim - a task in any other lane
# would sit unclaimed forever, see fleet_worker.py's lane filter).
$seedPools = @(foreach ($pool in @(Get-OptionalProperty $topology 'pools' @())) {
    $lanes = @(Get-OptionalProperty $pool 'taskTypes' @())
    if ($lanes.Count -eq 0) { continue }
    # Default arguments evaluate eagerly, so $pool.name inline here would throw
    # under StrictMode for a nameless pool — resolve it defensively first.
    $poolName = [string](Get-OptionalProperty $pool 'name' '?')
    [pscustomobject]@{
        Pool  = $poolName
        Board = [string](Get-OptionalProperty (Get-OptionalProperty $pool 'hermesFleet') 'board' $poolName)
        Lanes = $lanes
    }
})
if ($seedPools.Count -eq 0) {
    Write-Error "Topology $topologyPath declares no pools with taskTypes - nothing to seed."
    exit 1
}

# ---- synthetic seed plan -----------------------------------------------------
# Round-robin across pools; within a pool, cycle its lanes. Every 6th task is a
# block-path task ("block": true, no prompt) so both worker-lane terminations
# (kanban_complete / kanban_block) are exercised, matching fleet_worker.py.
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$laneCursor = @{}
$planTasks = [System.Collections.Generic.List[object]]::new()
for ($i = 1; $i -le $SeedSynthetic; $i++) {
    $pool = $seedPools[($i - 1) % $seedPools.Count]
    if (-not $laneCursor.ContainsKey($pool.Board)) { $laneCursor[$pool.Board] = 0 }
    $lane = [string]$pool.Lanes[$laneCursor[$pool.Board] % $pool.Lanes.Count]
    $laneCursor[$pool.Board]++
    $isBlock = (($i % 6) -eq 0)

    $task = [ordered]@{
        id     = "learn-$stamp-$i"
        lane   = $lane
        status = 'open'
    }
    if ($isBlock) {
        $task['block'] = $true
        $task['blockReason'] = 'synthetic kanban_block exercise (tandem learning cycle)'
    }
    else {
        $task['prompt'] = "Synthetic tandem-learning task $i (lane $lane): no real work - " +
            'the stub completes it to exercise kanban_complete.'
    }
    $planTasks.Add([pscustomobject]@{
            Id    = [string]$task['id']
            Board = $pool.Board
            Lane  = $lane
            Block = $isBlock
            Json  = ($task | ConvertTo-Json -Compress)
        })
}

# ---- plan (printed for dry runs AND before a live cycle) ---------------------
Write-Host ''
Write-Host "Tandem learning cycle plan ($SeedSynthetic synthetic task(s), drain timeout ${TimeoutSeconds}s):"
if ($RunId) {
    Write-Host "  run:     attach to existing run $RunId (must be status=running); the run is stopped at the end"
}
else {
    Write-Host "  run:     start a new fleet run via start-fleet.ps1 (stub lanes when 'hermes' is not on PATH)"
}
Write-Host '  seed (lock-aware enqueue: python3 -m helios_agents.fleet_worker --enqueue, per-board env from the manifest):'
foreach ($entry in $planTasks) {
    Write-Host ("    {0,-14} {1,-22} {2}{3}" -f
        $entry.Board, $entry.Lane, $entry.Id, $(if ($entry.Block) { '  (block-path)' } else { '' }))
}
Write-Host "  drain:   poll fleet-status.ps1 -Json every 5s until no open/claimed tasks (timeout ${TimeoutSeconds}s)"
Write-Host '  stop:    stop-fleet.ps1 -RunId <runId>'
Write-Host '  collect: python3 -m helios_agents fleet-collect --run-dir <runDir> --outcomes .helios/learning/outcomes.jsonl'
Write-Host '  summary: python3 -m helios_agents fleet-summary --outcomes .helios/learning/outcomes.jsonl --scale-log .helios/fleet/scale-log.jsonl'
Write-Host '           (fleet-collect/fleet-summary land in a parallel change - missing ops degrade with a warning)'
Write-Host '  plan:    dotnet run --project src/ai/HELIOS.AIHub.Cli -c Release -- fleet-plan --json (advisory; soft degrade)'
Write-Host "  report:  $reportPath"
if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run - nothing created, nothing started.'
    exit 0
}

# ---- python (enqueue + collect/summary run through the spoke) ----------------
# Resolved before starting the fleet: failing here must not orphan a fresh run.
$python = $null
foreach ($candidate in @('python3', 'python')) {
    $python = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($python) { break }
}
if (-not $python) {
    Write-Error ('python3 is required for the lock-aware enqueue and the learning collection ' +
        '(helios_agents runs from src/ai/python, dependency-free).')
    exit 1
}

# ---- start or attach ---------------------------------------------------------
if ($RunId) {
    $manifestPath = Join-Path $fleetDir $RunId 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Write-Error "No manifest for run '$RunId' under $fleetDir."
        exit 1
    }
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    $manifestStatus = [string](Get-OptionalProperty $manifest 'status' '')
    if ($manifestStatus -ne 'running') {
        Write-Error "Run '$RunId' has status '$manifestStatus' - a learning cycle needs a running fleet."
        exit 1
    }
}
else {
    & $startFleetScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "start-fleet.ps1 failed (exit $LASTEXITCODE)."
        exit 1
    }
    # Latest running run - the same discovery stop-fleet.ps1 uses.
    $candidateManifests = @(Get-ChildItem -Path $fleetDir -Directory | Sort-Object -Property Name |
            ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ })
    $runningManifests = @($candidateManifests | Where-Object {
            (Get-OptionalProperty (Get-Content -Raw -Path $_ | ConvertFrom-Json) 'status' '') -eq 'running' })
    if ($runningManifests.Count -eq 0) {
        Write-Error "start-fleet.ps1 succeeded but no running manifest was found under $fleetDir."
        exit 1
    }
    $manifestPath = $runningManifests[-1]
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
}
$runId = [string](Get-OptionalProperty $manifest 'runId' '?')
$runDir = Split-Path -Parent $manifestPath
$manifestPools = @(Get-OptionalProperty $manifest 'pools' @())
Write-Host ''
Write-Host "Learning cycle against run $runId ($runDir)."

$failures = 0

# ---- seed --------------------------------------------------------------------
# Grouped per board so the kanban env contract is exported once per board and
# always cleaned up; the enqueue itself re-reads the board under the claim
# lock (never hand-edit a live board - a concurrent worker save can drop the
# task silently).
$enqueued = 0
$failedEnqueue = 0
foreach ($group in ($planTasks | Group-Object -Property Board)) {
    $manifestPool = @($manifestPools | Where-Object {
            [string](Get-OptionalProperty $_ 'board' '') -eq $group.Name }) | Select-Object -First 1
    if ($null -eq $manifestPool) {
        Write-Warning ("Run $runId carries no board '$($group.Name)' (started with -Fleet?) - " +
            "skipping $($group.Group.Count) planned task(s) for it.")
        continue
    }
    $db = [string](Get-OptionalProperty $manifestPool 'db' '')
    $lock = [string](Get-OptionalProperty $manifestPool 'claimLock' "$db.lock")

    $env:HERMES_KANBAN_DB = $db
    $env:HERMES_KANBAN_CLAIM_LOCK = $lock
    try {
        Push-Location $pythonWorkDir
        try {
            foreach ($entry in $group.Group) {
                & $python.Source -m helios_agents.fleet_worker --enqueue $entry.Json 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ("  enqueued: {0} onto {1} [{2}]{3}" -f
                        $entry.Id, $entry.Board, $entry.Lane, $(if ($entry.Block) { ' (block-path)' } else { '' }))
                    $enqueued++
                }
                else {
                    Write-Warning "enqueue failed for $($entry.Id) on $($entry.Board) (exit $LASTEXITCODE)"
                    $failedEnqueue++
                }
            }
        }
        finally { Pop-Location }
    }
    finally {
        Remove-Item -Path 'Env:HERMES_KANBAN_DB', 'Env:HERMES_KANBAN_CLAIM_LOCK' -ErrorAction SilentlyContinue
    }
}
if ($failedEnqueue -gt 0) { $failures += $failedEnqueue }
Write-Host "Seeded $enqueued task(s) ($failedEnqueue failed)."

# ---- drain -------------------------------------------------------------------
$drained = $false
$deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
while ($true) {
    $statusRaw = & $fleetStatusScript -RunId $runId -Json
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "fleet-status.ps1 failed (exit $LASTEXITCODE) - abandoning the drain wait."
        break
    }
    $status = (@($statusRaw) -join "`n") | ConvertFrom-Json
    $run = @(Get-OptionalProperty $status 'runs' @()) | Select-Object -First 1
    $openClaimed = 0
    $runningWorkers = 0
    foreach ($poolReport in @(Get-OptionalProperty $run 'pools' @())) {
        $tally = Get-OptionalProperty $poolReport 'tasks'
        $openClaimed += [int](Get-OptionalProperty $tally 'open' 0) +
            [int](Get-OptionalProperty $tally 'claimed' 0)
        $runningWorkers += [int](Get-OptionalProperty $poolReport 'running' 0)
    }
    if ($openClaimed -eq 0) {
        $drained = $true
        Write-Host 'Boards drained: no open or claimed tasks remain.'
        break
    }
    if ($runningWorkers -eq 0) {
        # Stub workers idle-exit after HERMES_KANBAN_MAX_IDLE_POLLS empty
        # polls; all-exited with work still queued means no further progress
        # is possible - waiting out the timeout would only hide the stall.
        Write-Warning ("all workers have exited but $openClaimed task(s) are still open/claimed - " +
            'the boards cannot drain (stalled).')
        break
    }
    if ([datetime]::UtcNow -ge $deadline) {
        Write-Warning "drain timeout: $openClaimed task(s) still open/claimed after ${TimeoutSeconds}s."
        break
    }
    Write-Host "  draining: $openClaimed open/claimed task(s), $runningWorkers worker(s) running ..."
    Start-Sleep -Seconds 5
}
if (-not $drained) { $failures++ }

# ---- stop --------------------------------------------------------------------
& $stopFleetScript -RunId $runId
if ($LASTEXITCODE -ne 0) {
    Write-Warning "stop-fleet.ps1 -RunId $runId failed (exit $LASTEXITCODE)."
    $failures++
}

# ---- collect (parallel-landing op: degrade with a warning, never fail) -------
# Empty stdin is piped on purpose: the helios_agents entry point historically
# reads a JSON request from stdin, so a build without the fleet-collect op
# exits promptly (non-zero) instead of blocking on an open stdin.
$collected = $false
New-Item -ItemType Directory -Path (Split-Path -Parent $outcomesPath) -Force | Out-Null
Push-Location $pythonWorkDir
try {
    $collectOutput = @('' | & $python.Source -m helios_agents fleet-collect `
            --run-dir $runDir --outcomes $outcomesPath)
    $collectExit = $LASTEXITCODE
}
finally { Pop-Location }
if ($collectExit -eq 0) {
    $collected = $true
    Write-Host "Collected outcomes -> $outcomesPath"
}
else {
    Write-Warning (("fleet-collect unavailable or failed (exit {0}) - the op lands in a parallel " +
        'change; skipping collection this cycle. Output: {1}') -f
        $collectExit, ((@($collectOutput) -join ' ')))
}

# ---- summarize (same parallel-landing contract) -------------------------------
$summary = $null
if (Test-Path $outcomesPath) {
    Push-Location $pythonWorkDir
    try {
        $summaryOutput = @('' | & $python.Source -m helios_agents fleet-summary `
                --outcomes $outcomesPath --scale-log $scaleLogPath)
        $summaryExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($summaryExit -eq 0) {
        $summaryText = (@($summaryOutput) -join "`n")
        try { $summary = $summaryText | ConvertFrom-Json }
        catch {
            # Non-JSON summary output is still worth keeping verbatim.
            $summary = $summaryText
        }
        Write-Host 'Summary computed from outcomes + scale log.'
    }
    else {
        Write-Warning (("fleet-summary unavailable or failed (exit {0}) - the op lands in a " +
            'parallel change; summary: null this cycle.') -f $summaryExit)
    }
}
else {
    Write-Warning "No outcomes file at $outcomesPath - skipping fleet-summary (summary: null)."
}

# ---- advisory fleet plan (soft degrade: notice, never a failure) --------------
$fleetPlan = $null
$dotnet = Get-Command -Name 'dotnet' -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $dotnet) {
    Write-Host 'NOTICE: dotnet is not on PATH - skipping the advisory fleet-plan (fleetPlan: null).'
}
else {
    Push-Location $repoRoot
    try {
        # stdout only: the CLI writes its advisory banner to stderr, and merging it
        # in (2>&1) puts human text AFTER the JSON, which ConvertFrom-Json rejects
        # as trailing content (found by the first live end-to-end cycle). --no-build
        # keeps build chatter out of stdout too; both the CI lane and the local
        # cycle build the solution before this script runs, and a missing build
        # simply lands in the nonzero-exit soft degrade below.
        $planOutput = @(& $dotnet.Source run --project 'src/ai/HELIOS.AIHub.Cli' -c Release --no-build -- `
                fleet-plan --json 2>$null | ForEach-Object { $_.ToString() })
        $planExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    if ($planExit -ne 0) {
        Write-Host ("NOTICE: 'fleet-plan --json' unavailable (exit $planExit; needs a prior " +
            "'dotnet build HELIOS.sln -c Release') - fleetPlan: null. The plan is advisory only.")
    }
    else {
        # fleet-plan --json emits a top-level ARRAY of rows; be tolerant of any
        # residual preamble by joining from the first line that opens JSON.
        $openerIndex = -1
        for ($i = 0; $i -lt $planOutput.Count; $i++) {
            if ($planOutput[$i] -match '^\s*[\[{]') { $openerIndex = $i; break }
        }
        if ($openerIndex -ge 0) {
            $planText = (@($planOutput[$openerIndex..($planOutput.Count - 1)]) -join "`n")
            try { $fleetPlan = $planText | ConvertFrom-Json }
            catch { Write-Host 'NOTICE: fleet-plan output was not parseable JSON - fleetPlan: null.' }
        }
        else {
            Write-Host 'NOTICE: fleet-plan emitted no JSON - fleetPlan: null.'
        }
        if ($null -ne $fleetPlan) { Write-Host 'Advisory fleet plan captured (never auto-executed).' }
    }
}

# ---- report ------------------------------------------------------------------
New-Item -ItemType Directory -Path $fleetDir -Force | Out-Null
[ordered]@{
    at        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    runId     = $runId
    seeded    = $enqueued
    drained   = $drained
    collected = $collected
    summary   = $summary
    fleetPlan = $fleetPlan
} | ConvertTo-Json -Depth 16 | Set-Content -Path $reportPath -Encoding utf8
Write-Host ''
Write-Host "Learning report written: $reportPath"
Write-Host ("Cycle result: seeded={0} drained={1} collected={2} summary={3} fleetPlan={4} failures={5}" -f
    $enqueued, $drained, $collected, $(if ($null -ne $summary) { 'yes' } else { 'null' }),
    $(if ($null -ne $fleetPlan) { 'yes' } else { 'null' }), $failures)
exit $(if ($failures -gt 0) { 1 } else { 0 })
