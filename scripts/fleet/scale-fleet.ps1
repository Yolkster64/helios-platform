#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Reconciles live fleet worker counts against the topology's autoscaling
    policy - the local half for real, with a cloud-burst hook.

.DESCRIPTION
    One reconciliation pass per invocation (cron/loop friendly; -Watch adds an
    internal loop). For each pool in config/fleet/fleet-topology.json carrying
    an autoscaling block (the pool's block merged over defaults.autoscaling),
    a pass reads the latest running run's manifest
    (.helios/fleet/<runId>/manifest.json - the same contract fleet-status.ps1
    and stop-fleet.ps1 read) and that pool's board (boards/<board>.json), then
    computes:

        queueDepth   = open tasks in the pool's lanes, plus claimed tasks
                       whose claim lease expired (stale claims from crashed
                       lanes; the lease mirrors claim_lease_seconds = 300s in
                       helios_agents/fleet_worker.py)
        demand       = ceil(queueDepth / scaleUpQueueDepth)
        desiredLocal = clamp(minLocalLanes, demand, maxLocalLanes)

    Scale UP (currentLocal < desiredLocal) spawns additional workers through
    start-fleet.ps1's spawn contract - same env vars, same launch mechanics,
    same manifest worker shape - and records them in the run manifest so
    fleet-status.ps1 and stop-fleet.ps1 see them like any other worker.
    Scale DOWN (currentLocal > desiredLocal) happens only after the pool's
    queue has been empty for scaleDownIdleSeconds, tracked as lastNonEmptyAt
    per pool in .helios/fleet/scale-state.json; the newest excess workers are
    stopped with stop-fleet.ps1's identity-verified kill (pid + recorded
    process start time - never a stranger's reused pid).

    Cloud burst: when hybrid pools' demand still exceeds their maxLocalLanes,
    the excess lanes (per pool capped at maxBurstLanes, and the sum capped at
    the participating pools' combined maxBurstLanes) are AGGREGATED across
    pools and offered to one Azure VMSS. Lanes are not instances: each
    instance runs HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE worker lanes
    (default 2, matching infra/main.bicep's fleetWorkersPerInstance), and
    `az vmss scale` sets an ABSOLUTE capacity, so per-pool calls would
    overwrite each other. If the az CLI is on PATH and
    HELIOS_FLEET_VMSS_NAME + HELIOS_FLEET_VMSS_RG are set, the pass makes at
    most ONE call per pass:
    `az vmss scale --new-capacity ceil(totalBurstLanes / workersPerInstance)`;
    otherwise it prints a "burst wanted: N lane(s) (VMSS not configured)"
    notice and moves on - unconfigured burst is never an error.

    Every scaling ACTION appends one advisory JSON line to
    .helios/fleet/scale-log.jsonl for the learning/insights side: local
    scales as {at, pool, from, to, reason, burst: 0}; an actual az call as
    one aggregate entry {at, pool: 'vmss-burst', pools, burst, instances,
    workersPerInstance, reason} listing the contributing pools.

.PARAMETER RepoRoot
    Root holding config/fleet/fleet-topology.json and .helios/fleet/.
    Default: this checkout's root. Exists so tests can point the reconciler
    at a scratch tree without touching the real .helios/.

.PARAMETER DryRun
    Print the full reconciliation decision table (pool, queueDepth,
    currentLocal, desiredLocal, action, burst) without spawning or stopping
    workers, calling az, or writing the state file / action log.

.PARAMETER Watch
    Keep reconciling every -IntervalSeconds until Ctrl+C (clean stop).

.PARAMETER IntervalSeconds
    Seconds between passes in -Watch mode (default 60).

.EXAMPLE
    pwsh scripts/fleet/scale-fleet.ps1 -DryRun
.EXAMPLE
    pwsh scripts/fleet/scale-fleet.ps1              # one pass - cron-friendly
.EXAMPLE
    pwsh scripts/fleet/scale-fleet.ps1 -Watch -IntervalSeconds 30
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [switch]$DryRun,
    [switch]$Watch,
    [ValidateRange(5, 86400)]
    [int]$IntervalSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Claimed tasks older than this count as queued again (crashed lane whose
# lease expired) - mirrors claim_lease_seconds in helios_agents/fleet_worker.py.
$script:ClaimLeaseSeconds = 300

function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function ConvertTo-ProcessArgument {
    # Mirrors start-fleet.ps1 - keep in sync. Start-Process joins -ArgumentList
    # with spaces and .NET re-parses the string, so any element containing
    # whitespace or quotes must be quoted here.
    param([string]$Value)
    if ($Value -match '[\s"]') { return '"' + ($Value -replace '"', '\"') + '"' }
    return $Value
}

function ConvertTo-ShellWord {
    # Mirrors start-fleet.ps1 - keep in sync. Single-quote a word for POSIX sh.
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function ConvertTo-UtcDateTime {
    # Manifest/board/state timestamps arrive either as ISO strings or as
    # [datetime] (ConvertFrom-Json parses ISO-8601 into DateTime); normalize
    # to a UTC [datetime], or $null when unusable.
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return [datetime]::Parse($text, [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
            [System.Globalization.DateTimeStyles]::AdjustToUniversal)
    }
    catch { return $null }
}

function ConvertTo-IsoStringInPlace {
    # ConvertFrom-Json turns ISO strings into [datetime]; before writing the
    # manifest back, restore round-trippable strings on the named properties
    # so stop-fleet.ps1's identity check keeps parsing them cleanly.
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return }
    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop -and $prop.Value -is [datetime]) {
            $prop.Value = $prop.Value.ToUniversalTime().ToString('o')
        }
    }
}

function Get-PoolAutoscaling {
    # Pool autoscaling block merged over defaults.autoscaling, property by
    # property (pools typically declare mode/min/max and inherit the rest).
    param($Pool, $Defaults)
    $base = Get-OptionalProperty $Defaults 'autoscaling'
    $own = Get-OptionalProperty $Pool 'autoscaling'
    if ($null -eq $base -and $null -eq $own) { return $null }
    $merged = [ordered]@{}
    foreach ($name in @('mode', 'minLocalLanes', 'maxLocalLanes', 'maxBurstLanes',
            'scaleUpQueueDepth', 'scaleDownIdleSeconds', 'burstTarget')) {
        $value = Get-OptionalProperty $own $name (Get-OptionalProperty $base $name)
        if ($null -ne $value) { $merged[$name] = $value }
    }
    return [pscustomobject]$merged
}

function Get-QueueDepth {
    # Open tasks in the pool's lanes + claimed tasks whose lease expired.
    param([string]$DbPath, [string]$LaneSpec, [datetime]$NowUtc)
    if (-not ($DbPath -and (Test-Path $DbPath))) { return 0 }
    try { $board = Get-Content -Raw -Path $DbPath | ConvertFrom-Json }
    catch { return 0 }   # torn/hand-edited board read = idle poll, never a crash

    $lanes = @($LaneSpec -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $anyLane = ($lanes.Count -eq 0) -or ($lanes -contains '*')
    $depth = 0
    foreach ($task in @(Get-OptionalProperty $board 'tasks' @())) {
        if ($null -eq $task) { continue }
        $lane = [string](Get-OptionalProperty $task 'lane' (Get-OptionalProperty $task 'taskType' ''))
        if (-not ($anyLane -or ($lanes -contains $lane))) { continue }
        $status = [string](Get-OptionalProperty $task 'status' 'open')
        if ($status -eq 'open') { $depth++ }
        elseif ($status -eq 'claimed') {
            $claimedAt = ConvertTo-UtcDateTime (Get-OptionalProperty $task 'claimedAt')
            if ($null -eq $claimedAt -or
                ($NowUtc - $claimedAt).TotalSeconds -ge $script:ClaimLeaseSeconds) { $depth++ }
        }
    }
    return $depth
}

function Get-PoolWorkerState {
    # Live workers for a manifest pool and the highest assignee slot number,
    # so new workers continue the numbering. Identity-verified, not a bare pid
    # probe: a pid can be reused by an unrelated process after a worker exits,
    # and counting a stranger as a live lane inflates $current and suppresses
    # needed scale-ups. Same start-time check as Stop-FleetWorker (2s
    # tolerance); an unreadable start time means it is not a process we
    # spawned, so it does not count.
    param($ManifestPool)
    $running = [System.Collections.Generic.List[object]]::new()
    $unverifiable = 0
    $maxSlot = 0
    foreach ($worker in @(Get-OptionalProperty $ManifestPool 'workers' @())) {
        $assignee = [string](Get-OptionalProperty $worker 'assignee' '')
        if ($assignee -match '-(\d+)$') {
            $slot = [int]$Matches[1]
            if ($slot -gt $maxSlot) { $maxSlot = $slot }
        }
        $workerPid = [int](Get-OptionalProperty $worker 'pid' 0)
        if ($workerPid -le 0) { continue }
        $proc = Get-Process -Id $workerPid -ErrorAction SilentlyContinue
        if ($null -eq $proc) { continue }
        # Identity contract (keep in sync with stop-fleet.ps1 and the MCP
        # workersLive counter): a worker counts as Running only when the
        # recorded start time AND the process start time are both readable
        # and match. Unverifiable identities are excluded — counting them
        # would hand scale-down stop targets Stop-FleetWorker must refuse,
        # burning the whole Delta on unstoppable entries — but they are
        # tallied so the reconciler can warn that a possibly-live worker
        # sits outside its control.
        $expected = ConvertTo-UtcDateTime (Get-OptionalProperty $worker 'startTime')
        $actualStart = $null
        try { $actualStart = $proc.StartTime.ToUniversalTime() } catch { }
        if ($null -eq $expected -or $null -eq $actualStart) {
            $unverifiable++
            continue
        }
        if ([math]::Abs(($actualStart - $expected).TotalSeconds) -gt 2) { continue }
        $running.Add($worker)
    }
    return [pscustomobject]@{ Running = $running; MaxSlot = $maxSlot; Unverifiable = $unverifiable }
}

function Stop-FleetWorker {
    # stop-fleet.ps1's identity-verified kill - keep in sync. A pid alone can
    # be reused by an unrelated process after a worker exits; the manifest's
    # recorded start time must match (2s tolerance for clock rounding) before
    # killing. If either side is unreadable, skip rather than kill a stranger.
    param([int]$WorkerPid, $ExpectedStartTime)
    $proc = Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue
    if (-not $proc) { return 'already-exited' }

    # Both halves of the identity are required — a null recorded start time
    # means unverifiable, never kill-on-pid-alone (keep in sync with
    # stop-fleet.ps1 and start-fleet.ps1).
    $expected = ConvertTo-UtcDateTime $ExpectedStartTime
    if ($null -eq $expected) { return 'pid-unverifiable' }
    $actualStart = $null
    try { $actualStart = $proc.StartTime.ToUniversalTime() } catch { }
    if ($null -eq $actualStart) { return 'pid-unverifiable' }
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

function Start-FleetWorkerLane {
    # Spawns one additional worker honoring start-fleet.ps1's spawn contract
    # (env contract, launch mechanics, manifest worker shape) - keep in sync
    # with its launch block. Returns the manifest worker entry; throws on a
    # failed spawn (the caller counts it as an action failure).
    param(
        [string]$Assignee,
        $ManifestPool,
        [string]$RunId,
        [string]$RunDir,
        [string]$WorkerKind,
        $HermesCli,
        [string]$ArgsTemplate,
        $Python,
        [string]$CheckoutRoot,
        [string[]]$EnvContract
    )

    $board = [string](Get-OptionalProperty $ManifestPool 'board' '?')
    $lanes = [string](Get-OptionalProperty $ManifestPool 'lanes' '')
    $db = [string](Get-OptionalProperty $ManifestPool 'db' '')
    $lock = [string](Get-OptionalProperty $ManifestPool 'claimLock' "$db.lock")
    $logsDir = Join-Path $RunDir 'logs'
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    $outLog = Join-Path $logsDir "$Assignee.out.log"
    $errLog = Join-Path $logsDir "$Assignee.err.log"

    $contractValues = @{
        HERMES_KANBAN_TASK       = $lanes
        HERMES_KANBAN_DB         = $db
        HERMES_KANBAN_RUN_ID     = $RunId
        HERMES_KANBAN_CLAIM_LOCK = $lock
    }
    try {
        # Export the kanban env contract (child processes inherit it).
        foreach ($name in $EnvContract) {
            if ($contractValues.ContainsKey($name)) {
                Set-Item -Path "Env:$name" -Value $contractValues[$name]
            }
            else {
                Write-Warning "Topology envContract names '$name' which this script does not know; skipping."
            }
        }
        Set-Item -Path 'Env:HERMES_KANBAN_ASSIGNEE' -Value $Assignee

        if ($WorkerKind -eq 'hermes') {
            $prompt = "Work board '$board' (run $RunId): claim tasks in lanes [$lanes]; " +
                'terminate each via kanban_complete or kanban_block.'
            $workerExe = $HermesCli.Source
            $workerArgs = @(@($ArgsTemplate -split '\s+') | ForEach-Object {
                    $_ -replace '\{assignee\}', $Assignee -replace '\{prompt\}', $prompt
                })
            $workDir = $CheckoutRoot
        }
        else {
            $workerExe = $Python.Source
            $workerArgs = @('-m', 'helios_agents.fleet_worker')
            # On Windows the worker keeps a log sink by opening the file itself.
            if ($IsWindows) { $workerArgs += @('--log-file', $errLog) }
            $workDir = Join-Path $CheckoutRoot 'src' 'ai' 'python'
        }

        # Same launch mechanics as start-fleet.ps1 (see the NOTE there): never
        # Start-Process stdio redirection; on Unix wrap in sh -c 'exec ...' so
        # the worker owns its log fds and outlives this script.
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
        # Process start time is the identity check Stop-FleetWorker uses.
        $procStart = $null
        try { $procStart = $proc.StartTime.ToUniversalTime().ToString('o') } catch { }
        return [ordered]@{
            assignee  = $Assignee
            pid       = $proc.Id
            startTime = $procStart
            command   = "$workerExe $($workerArgs -join ' ')"
            log       = $errLog
        }
    }
    finally {
        foreach ($name in @($EnvContract) + @('HERMES_KANBAN_ASSIGNEE')) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ReconcilePass {
    # One full reconciliation pass. Returns the number of failed actions
    # (0 = clean pass; a missing run or unconfigured VMSS is not a failure).
    param(
        [string]$RepoRootPath,
        [string]$CheckoutRoot,
        [bool]$DryRunMode
    )

    $nowUtc = (Get-Date).ToUniversalTime()
    $failures = 0

    $topologyPath = Join-Path $RepoRootPath 'config' 'fleet' 'fleet-topology.json'
    if (-not (Test-Path $topologyPath)) {
        Write-Warning "Fleet topology not found: $topologyPath - nothing to reconcile."
        return 1
    }
    $topology = Get-Content -Raw -Path $topologyPath | ConvertFrom-Json
    $defaults = Get-OptionalProperty $topology 'defaults'
    $spawn = Get-OptionalProperty $defaults 'spawn'
    $envContract = @(Get-OptionalProperty $spawn 'envContract' @(
            'HERMES_KANBAN_TASK', 'HERMES_KANBAN_DB', 'HERMES_KANBAN_RUN_ID', 'HERMES_KANBAN_CLAIM_LOCK'))
    $argsTemplate = [string](Get-OptionalProperty $spawn 'argsTemplate' '-p {assignee} chat -q {prompt}')

    # ---- latest running run (same discovery as stop-fleet.ps1) -------------
    $fleetDir = Join-Path $RepoRootPath '.helios' 'fleet'
    $manifestPath = $null
    if (Test-Path $fleetDir) {
        $candidates = @(Get-ChildItem -Path $fleetDir -Directory | Sort-Object -Property Name |
                ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ })
        $runningManifests = @($candidates | Where-Object {
                (Get-OptionalProperty (Get-Content -Raw -Path $_ | ConvertFrom-Json) 'status' 'running') -eq 'running' })
        if ($runningManifests.Count -gt 0) { $manifestPath = $runningManifests[-1] }
    }
    if (-not $manifestPath) {
        Write-Host ("No running fleet run under $fleetDir - nothing to reconcile " +
            '(start one: pwsh scripts/fleet/start-fleet.ps1).')
        return 0
    }
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    $runId = [string](Get-OptionalProperty $manifest 'runId' '?')
    $runDir = Split-Path -Parent $manifestPath
    $workerKind = [string](Get-OptionalProperty $manifest 'workerKind' 'stub')
    $manifestPools = @(Get-OptionalProperty $manifest 'pools' @())

    # ---- idle-tracking state (lastNonEmptyAt per pool, scoped to the run) --
    $statePath = Join-Path $fleetDir 'scale-state.json'
    $statePools = $null
    if (Test-Path $statePath) {
        try {
            $state = Get-Content -Raw -Path $statePath | ConvertFrom-Json
            if ([string](Get-OptionalProperty $state 'runId' '') -eq $runId) {
                $statePools = Get-OptionalProperty $state 'pools'
            }
        }
        catch { Write-Warning "Unreadable scale state ($statePath); starting fresh." }
    }

    # ---- decide (pure - no side effects yet) -------------------------------
    $rows = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($pool in @(Get-OptionalProperty $topology 'pools' @())) {
        $poolName = [string](Get-OptionalProperty $pool 'name' '')
        $auto = Get-PoolAutoscaling -Pool $pool -Defaults $defaults
        if (-not $poolName -or $null -eq $auto) { continue }

        $mode = [string](Get-OptionalProperty $auto 'mode' 'local')
        $minLanes = [int](Get-OptionalProperty $auto 'minLocalLanes' 1)
        $maxLanes = [int](Get-OptionalProperty $auto 'maxLocalLanes' $minLanes)
        $maxBurst = [int](Get-OptionalProperty $auto 'maxBurstLanes' 0)
        $scaleUpDepth = [math]::Max(1, [int](Get-OptionalProperty $auto 'scaleUpQueueDepth' 3))
        $idleWindow = [math]::Max(0, [int](Get-OptionalProperty $auto 'scaleDownIdleSeconds' 300))
        if ($mode -eq 'cloud') { $minLanes = 0; $maxLanes = 0 }   # cloud pools hold no local lanes
        if ($maxLanes -lt $minLanes) { $maxLanes = $minLanes }

        $manifestPool = @($manifestPools | Where-Object {
                [string](Get-OptionalProperty $_ 'pool' '') -eq $poolName }) | Select-Object -First 1
        if ($null -eq $manifestPool) {
            $skipped.Add($poolName)
            continue
        }

        $queueDepth = Get-QueueDepth `
            -DbPath ([string](Get-OptionalProperty $manifestPool 'db' '')) `
            -LaneSpec ([string](Get-OptionalProperty $manifestPool 'lanes' '')) `
            -NowUtc $nowUtc
        $workerState = Get-PoolWorkerState -ManifestPool $manifestPool
        $current = $workerState.Running.Count
        if ($workerState.Unverifiable -gt 0) {
            # Parentheses around the concatenation matter: -f binds tighter
            # than +, so without them the placeholders would print literally.
            Write-Warning (("pool {0}: {1} worker(s) with unverifiable identity (missing/unreadable " +
                'start time) are excluded from lane counts and cannot be scaled down - check the ' +
                'manifest pids by hand and rerun stop-fleet.ps1 -RunId once resolved.') -f
                $poolName, $workerState.Unverifiable)
        }
        $demand = [int][math]::Ceiling($queueDepth / [double]$scaleUpDepth)
        $desired = [math]::Min($maxLanes, [math]::Max($minLanes, $demand))

        # Idle clock: a non-empty queue (or a pool never seen before) resets it.
        $lastNonEmpty = ConvertTo-UtcDateTime (Get-OptionalProperty `
            (Get-OptionalProperty $statePools $poolName) 'lastNonEmptyAt')
        if ($queueDepth -gt 0 -or $null -eq $lastNonEmpty) { $lastNonEmpty = $nowUtc }
        $idleSeconds = [int][math]::Floor(($nowUtc - $lastNonEmpty).TotalSeconds)

        $action = 'none'
        $delta = 0
        if ($current -lt $desired) {
            $action = 'scale-up'
            $delta = $desired - $current
        }
        elseif ($current -gt $desired) {
            if ($queueDepth -eq 0 -and $idleSeconds -ge $idleWindow) {
                $action = 'scale-down'
                $delta = $current - $desired
            }
            elseif ($queueDepth -eq 0) {
                $action = 'hold'   # drained, but still inside the idle window
            }
            # queue still non-empty: excess lanes keep draining it - no action
        }

        $burst = 0
        if (($mode -eq 'hybrid' -or $mode -eq 'cloud') -and $maxBurst -gt 0 -and $demand -gt $maxLanes) {
            $burst = [math]::Min($demand - $maxLanes, $maxBurst)
        }

        $rows.Add([pscustomobject]@{
                Pool         = $poolName
                ManifestPool = $manifestPool
                Mode         = $mode
                Queue        = $queueDepth
                Current      = $current
                Desired      = $desired
                Action       = $action
                Delta        = $delta
                Burst        = $burst
                MaxBurst     = $maxBurst
                IdleSeconds  = $idleSeconds
                IdleWindow   = $idleWindow
                LastNonEmpty = $lastNonEmpty
                Running      = $workerState.Running
                MaxSlot      = $workerState.MaxSlot
                Prefix       = [string](Get-OptionalProperty $pool 'assigneePrefix' $poolName)
            })
    }

    # ---- decision table ----------------------------------------------------
    Write-Host ''
    Write-Host ("Reconcile pass for run {0} at {1}{2}:" -f $runId,
        $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'), $(if ($DryRunMode) { ' (dry run)' } else { '' }))
    Write-Host ("  {0,-16} {1,5} {2,8} {3,8}  {4,-24} {5}" -f
        'pool', 'queue', 'current', 'desired', 'action', 'burst')
    foreach ($row in $rows) {
        $actionText = switch ($row.Action) {
            'scale-up' { "scale-up (+$($row.Delta))" }
            'scale-down' { "scale-down (-$($row.Delta))" }
            'hold' { "hold (idle $($row.IdleSeconds)s/$($row.IdleWindow)s)" }
            default { 'none' }
        }
        $burstText = if ($row.Mode -eq 'local') { '-' } else { [string]$row.Burst }
        Write-Host ("  {0,-16} {1,5} {2,8} {3,8}  {4,-24} {5}" -f
            $row.Pool, $row.Queue, $row.Current, $row.Desired, $actionText, $burstText)
    }
    foreach ($name in $skipped) {
        Write-Host "  $name : not in this run's manifest - skipped."
    }

    # ---- burst configuration (advisory when absent - never an error) -------
    $azCli = Get-Command -Name 'az' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $vmssName = [string]$env:HELIOS_FLEET_VMSS_NAME
    $vmssRg = [string]$env:HELIOS_FLEET_VMSS_RG
    $burstConfigured = ($null -ne $azCli) -and
        (-not [string]::IsNullOrEmpty($vmssName)) -and (-not [string]::IsNullOrEmpty($vmssRg))

    # ---- cloud burst: ONE aggregate VMSS call per pass ---------------------
    # Lanes are not instances (one instance runs workersPerInstance lanes) and
    # `az vmss scale` sets an ABSOLUTE capacity, so per-pool calls would both
    # overwrite each other and overprovision. Sum the burst LANE demand across
    # pools (each row's Burst is already capped at that pool's maxBurstLanes;
    # cap the sum at the participating pools' combined maxBurstLanes), then
    # convert lanes -> instances with ceil.
    $scaleLogPath = Join-Path $fleetDir 'scale-log.jsonl'
    $burstRows = @($rows | Where-Object { $_.Burst -gt 0 })
    $burstPoolNames = @($burstRows | ForEach-Object { $_.Pool })
    $totalBurstLanes = 0
    $burstLaneCap = 0
    foreach ($burstRow in $burstRows) {
        $totalBurstLanes += [int]$burstRow.Burst
        $burstLaneCap += [math]::Max(0, [int]$burstRow.MaxBurst)
    }
    if ($totalBurstLanes -gt $burstLaneCap) { $totalBurstLanes = $burstLaneCap }

    $workersPerInstance = 2   # default matches infra/main.bicep fleetWorkersPerInstance
    $rawWorkersPerInstance = [string]$env:HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE
    if (-not [string]::IsNullOrWhiteSpace($rawWorkersPerInstance)) {
        $parsedWorkersPerInstance = 0
        if ([int]::TryParse($rawWorkersPerInstance, [ref]$parsedWorkersPerInstance) -and
            $parsedWorkersPerInstance -ge 1) {
            $workersPerInstance = $parsedWorkersPerInstance
        }
        else {
            Write-Warning ("Ignoring HELIOS_FLEET_VMSS_WORKERS_PER_INSTANCE='$rawWorkersPerInstance' " +
                '(not a positive integer); using the default of 2 workers per instance.')
        }
    }

    if ($totalBurstLanes -gt 0) {
        $burstInstances = [int][math]::Ceiling($totalBurstLanes / [double]$workersPerInstance)
        $burstPoolsText = $burstPoolNames -join ', '
        if (-not $burstConfigured) {
            Write-Host (('  burst wanted: {0} lane(s) across {1} (VMSS not configured - set ' +
                    'HELIOS_FLEET_VMSS_NAME and HELIOS_FLEET_VMSS_RG, with the az CLI on PATH)') -f
                    $totalBurstLanes, $burstPoolsText)
        }
        elseif ($DryRunMode) {
            Write-Host (('  burst: would run az vmss scale --name {0} --resource-group {1} ' +
                    '--new-capacity {2} ({3} lane(s) at {4}/instance; pools: {5})') -f
                    $vmssName, $vmssRg, $burstInstances, $totalBurstLanes, $workersPerInstance,
                    $burstPoolsText)
        }
        else {
            Write-Host (('  burst: az vmss scale --name {0} --resource-group {1} ' +
                    '--new-capacity {2} ({3} lane(s) at {4}/instance; pools: {5})') -f
                    $vmssName, $vmssRg, $burstInstances, $totalBurstLanes, $workersPerInstance,
                    $burstPoolsText)
            & $azCli.Source vmss scale --name $vmssName --resource-group $vmssRg `
                --new-capacity $burstInstances --output none | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "az vmss scale failed (exit $LASTEXITCODE)."
                $failures++
            }
            else {
                # One advisory line for the aggregate call, listing the pools
                # whose lane demand it carries.
                $logEntry = [ordered]@{
                    at                 = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    pool               = 'vmss-burst'
                    pools              = $burstPoolNames
                    burst              = $totalBurstLanes
                    instances          = $burstInstances
                    workersPerInstance = $workersPerInstance
                    reason             = "burst: $totalBurstLanes lane(s) exceed local capacity across $burstPoolsText"
                }
                ($logEntry | ConvertTo-Json -Compress) | Add-Content -Path $scaleLogPath -Encoding utf8
            }
        }
    }

    # ---- resolve the spawn command once, only if a scale-up will happen ----
    $hermesCli = $null
    $python = $null
    $spawnReady = $false
    if (-not $DryRunMode -and @($rows | Where-Object { $_.Action -eq 'scale-up' }).Count -gt 0) {
        if ($workerKind -eq 'hermes') {
            $hermesCommand = [string](Get-OptionalProperty $spawn 'command' 'hermes')
            $hermesCli = Get-Command -Name $hermesCommand -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hermesCli) { $spawnReady = $true }
            else {
                Write-Warning ("Run $runId was started with the '$hermesCommand' CLI, " +
                    'which is no longer on PATH - cannot scale up.')
            }
        }
        else {
            foreach ($candidate in @('python3', 'python')) {
                $python = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($python) { break }
            }
            if ($python) { $spawnReady = $true }
            else { Write-Warning 'Neither python3 nor python is on PATH - cannot scale up stub workers.' }
        }
    }

    # ---- act (local lanes; the aggregate burst already ran above) ----------
    $manifestDirty = $false
    foreach ($row in $rows) {
        if ($DryRunMode) { continue }

        $from = $row.Current
        $to = $row.Current
        $reason = ''
        if ($row.Action -eq 'scale-up') {
            $reason = "scale-up: queueDepth $($row.Queue) wants $($row.Desired) local lane(s)"
            if (-not $spawnReady) { $failures++ }
            else {
                $newWorkers = [System.Collections.Generic.List[object]]::new()
                $slot = $row.MaxSlot
                for ($i = 1; $i -le $row.Delta; $i++) {
                    $slot++
                    $assignee = "$($row.Prefix)-$slot"
                    try {
                        $entry = Start-FleetWorkerLane -Assignee $assignee -ManifestPool $row.ManifestPool `
                            -RunId $runId -RunDir $runDir -WorkerKind $workerKind -HermesCli $hermesCli `
                            -ArgsTemplate $argsTemplate -Python $python -CheckoutRoot $CheckoutRoot `
                            -EnvContract $envContract
                        $newWorkers.Add($entry)
                        Write-Host "  started $assignee (pid $($entry.pid)) for $($row.Pool)"
                    }
                    catch {
                        Write-Warning "Failed to start $assignee for $($row.Pool): $_"
                        $failures++
                    }
                }
                if ($newWorkers.Count -gt 0) {
                    $combined = @(Get-OptionalProperty $row.ManifestPool 'workers' @()) + @($newWorkers)
                    if ($null -ne $row.ManifestPool.PSObject.Properties['workers']) {
                        $row.ManifestPool.workers = $combined
                    }
                    else {
                        $row.ManifestPool | Add-Member -NotePropertyName 'workers' -NotePropertyValue $combined
                    }
                    $manifestDirty = $true
                    $to = $from + $newWorkers.Count
                }
            }
        }
        elseif ($row.Action -eq 'scale-down') {
            $reason = "scale-down: queue empty for $($row.IdleSeconds)s (window $($row.IdleWindow)s)"
            # Newest first: highest assignee slot numbers are the extra lanes
            # this reconciler (or a late start-fleet slot) added most recently.
            $targets = @($row.Running | Sort-Object -Property {
                    if ([string](Get-OptionalProperty $_ 'assignee' '') -match '-(\d+)$') { [int]$Matches[1] }
                    else { -1 }
                } -Descending | Select-Object -First $row.Delta)
            $stoppedCount = 0
            foreach ($worker in $targets) {
                $workerPid = [int](Get-OptionalProperty $worker 'pid' 0)
                $assignee = [string](Get-OptionalProperty $worker 'assignee' '?')
                $startTime = Get-OptionalProperty $worker 'startTime' $null
                if ($workerPid -le 0) { continue }
                $outcome = Stop-FleetWorker -WorkerPid $workerPid -ExpectedStartTime $startTime
                Write-Host "  $assignee (pid $workerPid): $outcome"
                if ($outcome -in @('stopped', 'killed', 'already-exited')) { $stoppedCount++ }
            }
            $to = $from - $stoppedCount
        }

        # One advisory line per local scaling ACTION for the learning/insights
        # side (burst is logged once, aggregated, above - never per pool).
        if ($to -ne $from) {
            $logEntry = [ordered]@{
                at     = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
                pool   = $row.Pool
                from   = $from
                to     = $to
                reason = $reason
                burst  = 0
            }
            ($logEntry | ConvertTo-Json -Compress) | Add-Content -Path $scaleLogPath -Encoding utf8
        }
    }

    # ---- persist state and manifest (never in dry-run) ---------------------
    if (-not $DryRunMode) {
        $statePoolsOut = [ordered]@{}
        foreach ($row in $rows) {
            $statePoolsOut[$row.Pool] = [ordered]@{
                lastNonEmptyAt = $row.LastNonEmpty.ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        }
        [ordered]@{
            runId     = $runId
            updatedAt = $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
            pools     = $statePoolsOut
        } | ConvertTo-Json -Depth 4 | Set-Content -Path $statePath -Encoding utf8

        if ($manifestDirty) {
            ConvertTo-IsoStringInPlace -Object $manifest -Names @('startedAt', 'stoppedAt')
            foreach ($manifestPool in $manifestPools) {
                foreach ($worker in @(Get-OptionalProperty $manifestPool 'workers' @())) {
                    ConvertTo-IsoStringInPlace -Object $worker -Names @('startTime')
                }
            }
            $manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding utf8
            Write-Host "  manifest updated: $manifestPath"
        }
    }

    return $failures
}

# ---- main ------------------------------------------------------------------
$checkoutRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
if ([string]::IsNullOrEmpty($RepoRoot)) {
    $repoRootPath = $checkoutRoot
}
else {
    if (-not (Test-Path $RepoRoot -PathType Container)) {
        Write-Error "-RepoRoot '$RepoRoot' does not exist or is not a directory."
        exit 1
    }
    $repoRootPath = (Resolve-Path $RepoRoot).Path
}

if ($Watch) {
    Write-Host "scale-fleet watch: one pass every $IntervalSeconds s (Ctrl+C to stop)."
    try {
        while ($true) {
            $null = Invoke-ReconcilePass -RepoRootPath $repoRootPath -CheckoutRoot $checkoutRoot `
                -DryRunMode $DryRun.IsPresent
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    finally {
        Write-Host 'scale-fleet watch stopped.'
    }
}
else {
    $failures = Invoke-ReconcilePass -RepoRootPath $repoRootPath -CheckoutRoot $checkoutRoot `
        -DryRunMode $DryRun.IsPresent
    if ($failures -gt 0) { exit 1 }
    exit 0
}
