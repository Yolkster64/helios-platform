#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Brings up Hermes/Xcore agent-fleet workers from the declarative topology.

.DESCRIPTION
    Reads config/fleet/fleet-topology.json and launches one background worker
    process per pool slot, exporting the kanban env contract
    (HERMES_KANBAN_TASK / _DB / _RUN_ID / _CLAIM_LOCK) to each. Workers spawn
    through the real Hermes CLI when it is on PATH; otherwise the script says so
    and falls back to the dependency-free local stub
    (python3 -m helios_agents.fleet_worker) — never a crash.

    Per run it creates .helios/fleet/<runId>/ (gitignored) holding one JSON
    kanban board per pool (boards/<board>.json), worker logs (logs/), and the
    manifest.json that scripts/fleet/fleet-status.ps1 and stop-fleet.ps1 read.

.PARAMETER Fleet
    Pool name (xcore-9-code) or its board name (xcore-code) to start;
    'all' (default) starts every pool in the topology.

.PARAMETER PoolSize
    Override the per-pool worker count from the topology (applies to every
    selected pool). Workspace mode still caps the result.

.PARAMETER DryRun
    Print the launch plan without creating anything or starting processes.

.PARAMETER Workspace
    Force workspace mode (auto-detected when CODESPACES or CLOUD_SHELL is set):
    pool sizes are capped to the topology's workspaceProfile.poolSize (per-pool
    or defaults) when present, else to half the declared size, rounded up.

.EXAMPLE
    pwsh scripts/fleet/start-fleet.ps1 -DryRun
.EXAMPLE
    pwsh scripts/fleet/start-fleet.ps1 -Fleet xcore-9-code -PoolSize 3
#>
[CmdletBinding()]
param(
    [string]$Fleet = 'all',
    [int]$PoolSize = 0,
    [switch]$DryRun,
    [switch]$Workspace
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

function ConvertTo-ProcessArgument {
    # Start-Process joins -ArgumentList with spaces and .NET re-parses the string,
    # so any element containing whitespace or quotes must be quoted here.
    param([string]$Value)
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function ConvertTo-ShellWord {
    # Single-quote a word for POSIX sh.
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

if ($PoolSize -lt 0 -or $PoolSize -gt 64) {
    Write-Error '-PoolSize must be between 1 and 64 (0 / omitted = use the topology).'
    exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$topologyPath = Join-Path $repoRoot 'config' 'fleet' 'fleet-topology.json'
if (-not (Test-Path $topologyPath)) {
    Write-Error "Fleet topology not found: $topologyPath"
    exit 1
}
$topology = Get-Content -Raw -Path $topologyPath | ConvertFrom-Json
$defaults = Get-OptionalProperty $topology 'defaults'
$spawn = Get-OptionalProperty $defaults 'spawn'
$envContract = @(Get-OptionalProperty $spawn 'envContract' @(
        'HERMES_KANBAN_TASK', 'HERMES_KANBAN_DB', 'HERMES_KANBAN_RUN_ID', 'HERMES_KANBAN_CLAIM_LOCK'))

# ---- pool selection --------------------------------------------------------
$pools = @($topology.pools)
if ($Fleet -ne 'all') {
    $pools = @($pools | Where-Object {
            $_.name -eq $Fleet -or (Get-OptionalProperty (Get-OptionalProperty $_ 'hermesFleet') 'board') -eq $Fleet
        })
    if ($pools.Count -eq 0) {
        $known = ($topology.pools | ForEach-Object { $_.name }) -join ', '
        Write-Error "Unknown fleet '$Fleet'. Known pools: $known (or their board names, or 'all')."
        exit 1
    }
}

# ---- workspace mode --------------------------------------------------------
$workspaceMode = $Workspace.IsPresent -or
    (-not [string]::IsNullOrEmpty($env:CODESPACES)) -or
    (-not [string]::IsNullOrEmpty($env:CLOUD_SHELL))
if ($workspaceMode -and -not $Workspace.IsPresent) {
    Write-Host 'Workspace detected (CODESPACES/CLOUD_SHELL set) - pool sizes will be capped.'
}

function Get-EffectivePoolSize {
    param($Pool, $Defaults, [int]$Override, [bool]$WorkspaceMode)
    $size = [int](Get-OptionalProperty $Pool 'poolSize' (Get-OptionalProperty $Defaults 'poolSize' 1))
    if ($Override -gt 0) { $size = $Override }
    if ($WorkspaceMode) {
        $wsProfile = Get-OptionalProperty $Pool 'workspaceProfile' (Get-OptionalProperty $Defaults 'workspaceProfile')
        $cap = [int](Get-OptionalProperty $wsProfile 'poolSize' 0)
        if ($cap -le 0) { $cap = [int][math]::Ceiling($size / 2.0) }
        if ($size -gt $cap) {
            Write-Host "  $($Pool.name): workspace cap $cap (was $size)"
            $size = $cap
        }
    }
    return $size
}

# ---- worker command: real hermes CLI, else the local stub ------------------
$hermesCommand = [string](Get-OptionalProperty $spawn 'command' 'hermes')
$argsTemplate = [string](Get-OptionalProperty $spawn 'argsTemplate' '-p {assignee} chat -q {prompt}')
$hermesCli = Get-Command -Name $hermesCommand -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

$python = $null
if ($hermesCli) {
    $workerKind = 'hermes'
    Write-Host "Using Hermes CLI: $($hermesCli.Source)"
}
else {
    $workerKind = 'stub'
    foreach ($candidate in @('python3', 'python')) {
        $python = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($python) { break }
    }
    if (-not $python) {
        Write-Error ("Neither '$hermesCommand' nor python3/python is on PATH - install the Hermes CLI " +
            'or Python 3 to run the local stub (python3 -m helios_agents.fleet_worker).')
        exit 1
    }
    Write-Host "NOTICE: '$hermesCommand' CLI not found on PATH - falling back to the local stub"
    Write-Host "        ($($python.Source) -m helios_agents.fleet_worker). Workers honor the same"
    Write-Host '        kanban contract but do no model work. Install Hermes for real lanes.'
}

# ---- plan ------------------------------------------------------------------
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + '-' +
    [guid]::NewGuid().ToString('N').Substring(0, 6)
$runDir = Join-Path $repoRoot '.helios' 'fleet' $runId
$stubWorkDir = Join-Path $repoRoot 'src' 'ai' 'python'

$plan = @(foreach ($pool in $pools) {
    $board = [string](Get-OptionalProperty (Get-OptionalProperty $pool 'hermesFleet') 'board' $pool.name)
    $lanes = @(Get-OptionalProperty $pool 'taskTypes' @()) -join ','
    [pscustomobject]@{
        Pool     = [string]$pool.name
        Board    = $board
        Prefix   = [string](Get-OptionalProperty $pool 'assigneePrefix' $pool.name)
        Lanes    = $lanes
        Workers  = Get-EffectivePoolSize -Pool $pool -Defaults $defaults -Override $PoolSize -WorkspaceMode $workspaceMode
        Db       = Join-Path $runDir 'boards' "$board.json"
        Lock     = Join-Path $runDir 'locks' "$board.lock"
    }
})

Write-Host ''
Write-Host "Fleet plan (run $runId, worker kind: $workerKind$(if ($workspaceMode) { ', workspace mode' })):"
foreach ($entry in $plan) {
    Write-Host ("  {0,-16} board {1,-14} {2} worker(s)  lanes: {3}" -f
        $entry.Pool, $entry.Board, $entry.Workers, $entry.Lanes)
}
if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run - nothing created, nothing started.'
    exit 0
}

# ---- launch ----------------------------------------------------------------
foreach ($sub in @('boards', 'locks', 'logs')) {
    New-Item -ItemType Directory -Path (Join-Path $runDir $sub) -Force | Out-Null
}

$manifestPools = [System.Collections.Generic.List[object]]::new()
$tempKnobs = @()
if ($workerKind -eq 'stub') {
    # Give interactive bring-up time to seed the boards: poll every 2s, idle-exit
    # after 60 empty polls (~2 minutes). Export either var beforehand to override.
    if ([string]::IsNullOrEmpty($env:HERMES_KANBAN_POLL_SECONDS)) {
        Set-Item -Path 'Env:HERMES_KANBAN_POLL_SECONDS' -Value '2'
        $tempKnobs += 'HERMES_KANBAN_POLL_SECONDS'
    }
    if ([string]::IsNullOrEmpty($env:HERMES_KANBAN_MAX_IDLE_POLLS)) {
        Set-Item -Path 'Env:HERMES_KANBAN_MAX_IDLE_POLLS' -Value '60'
        $tempKnobs += 'HERMES_KANBAN_MAX_IDLE_POLLS'
    }
}
try {
    foreach ($entry in $plan) {
        if (-not (Test-Path $entry.Db)) {
            [ordered]@{
                board     = $entry.Board
                runId     = $runId
                createdAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                tasks     = @()
            } | ConvertTo-Json -Depth 4 | Set-Content -Path $entry.Db -Encoding utf8
        }

        $workers = [System.Collections.Generic.List[object]]::new()
        for ($slot = 1; $slot -le $entry.Workers; $slot++) {
            $assignee = "$($entry.Prefix)-$slot"

            # Export the kanban env contract (child processes inherit it).
            $contractValues = @{
                HERMES_KANBAN_TASK       = $entry.Lanes
                HERMES_KANBAN_DB         = $entry.Db
                HERMES_KANBAN_RUN_ID     = $runId
                HERMES_KANBAN_CLAIM_LOCK = $entry.Lock
            }
            foreach ($name in $envContract) {
                if ($contractValues.ContainsKey($name)) {
                    Set-Item -Path "Env:$name" -Value $contractValues[$name]
                }
                else {
                    Write-Warning "Topology envContract names '$name' which this script does not know; skipping."
                }
            }
            Set-Item -Path 'Env:HERMES_KANBAN_ASSIGNEE' -Value $assignee

            $outLog = Join-Path $runDir 'logs' "$assignee.out.log"
            $errLog = Join-Path $runDir 'logs' "$assignee.err.log"
            if ($workerKind -eq 'hermes') {
                $prompt = "Work board '$($entry.Board)' (run $runId): claim tasks in lanes [$($entry.Lanes)]; " +
                    'terminate each via kanban_complete or kanban_block.'
                $workerExe = $hermesCli.Source
                $workerArgs = @(@($argsTemplate -split '\s+') | ForEach-Object {
                        $_ -replace '\{assignee\}', $assignee -replace '\{prompt\}', $prompt
                    })
                $workDir = $repoRoot
            }
            else {
                $workerExe = $python.Source
                $workerArgs = @('-m', 'helios_agents.fleet_worker')
                # On Windows the worker keeps a log sink by opening the file itself.
                if ($IsWindows) { $workerArgs += @('--log-file', $errLog) }
                $workDir = $stubWorkDir
            }

            # NOTE: launch mechanics matter here.
            # - Never use Start-Process -RedirectStandardOutput/-RedirectStandardError:
            #   pwsh pumps those through pipes owned by THIS process, so worker logs
            #   (and the workers themselves, via BrokenPipe on write) die when this
            #   script exits.
            # - On Unix, wrap in sh -c 'exec ... </dev/null >out 2>err': exec keeps the
            #   worker's pid, and the worker owns its log fds and holds no inherited
            #   stdio, so it outlives this script and never blocks a pipeline reading
            #   this script's output.
            if ($IsWindows) {
                $proc = Start-Process -FilePath $workerExe `
                    -ArgumentList @($workerArgs | ForEach-Object { ConvertTo-ProcessArgument $_ }) `
                    -WorkingDirectory $workDir -PassThru -WindowStyle Hidden
            }
            else {
                $shCmd = 'exec ' +
                    ((@($workerExe) + $workerArgs | ForEach-Object { ConvertTo-ShellWord $_ }) -join ' ') +
                    ' </dev/null >' + (ConvertTo-ShellWord $outLog) + ' 2>' + (ConvertTo-ShellWord $errLog)
                $proc = Start-Process -FilePath 'sh' `
                    -ArgumentList @('-c', ('"' + ($shCmd -replace '"', '\"') + '"')) `
                    -WorkingDirectory $workDir -PassThru
            }
            $workers.Add([ordered]@{
                    assignee = $assignee
                    pid      = $proc.Id
                    command  = "$workerExe $($workerArgs -join ' ')"
                    log      = $errLog
                })
            Write-Host "  started $assignee (pid $($proc.Id))"
        }

        $manifestPools.Add([ordered]@{
                pool      = $entry.Pool
                board     = $entry.Board
                lanes     = $entry.Lanes
                db        = $entry.Db
                claimLock = $entry.Lock
                workers   = $workers
            })
    }
}
finally {
    foreach ($name in @($envContract) + @('HERMES_KANBAN_ASSIGNEE') + $tempKnobs) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
}

# ---- manifest --------------------------------------------------------------
$manifestPath = Join-Path $runDir 'manifest.json'
[ordered]@{
    runId         = $runId
    startedAt     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    repoRoot      = $repoRoot
    topology      = $topologyPath
    workerKind    = $workerKind
    workspaceMode = [bool]$workspaceMode
    status        = 'running'
    stoppedAt     = $null
    pools         = $manifestPools
} | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8

$totalWorkers = ($plan | Measure-Object -Property Workers -Sum).Sum
Write-Host ''
Write-Host "Started $totalWorkers worker(s) across $($plan.Count) pool(s). Manifest: $manifestPath"
Write-Host "Feed the boards by appending tasks to .helios/fleet/$runId/boards/<board>.json, e.g.:"
Write-Host '  { "id": "T-1", "lane": "code_generation", "status": "open", "prompt": "..." }'
Write-Host "Status: pwsh scripts/fleet/fleet-status.ps1 -RunId $runId"
Write-Host "Stop:   pwsh scripts/fleet/stop-fleet.ps1 -RunId $runId"
exit 0
