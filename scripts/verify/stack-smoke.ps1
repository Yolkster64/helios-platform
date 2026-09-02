<#
.SYNOPSIS
One-command end-to-end communication proof for the whole local HELIOS stack: the HTTP
API, the stdio MCP server, and the CLI are each launched from the EXISTING Release build
and probed live. Report-first: degraded provider states are OK — providers without keys
are the designed pre-owner-unlock state, and this smoke proves the stack COMMUNICATES,
not that every provider is credentialed.

.DESCRIPTION
Codifies the manual end-to-end proof into one repeatable command. The script never
builds anything (`dotnet run ... --no-build` only — CI and the operator build first with
`dotnet build HELIOS.sln -c Release`); when dotnet or the Release outputs are absent it
reports state build-missing with the exact build command and exits 0 (report-only).

Lanes (one row each: {lane, state ok|degraded|failed|build-missing, detail}):

  preflight  dotnet on PATH + bin/Release outputs present for the Api, Cli, and Mcp
             projects. Missing => every live lane is skipped as build-missing, exit 0.
  api        helios-ai-api launched in the background
             (dotnet run --project src/ai/HELIOS.AIHub.Api -c Release --no-build --
              --urls http://127.0.0.1:0 — port 0 so the kernel picks a free port and the
             smoke never fights a dev instance on launchSettings' 5170). The bound URL is
             parsed from the process's OWN stdout ("Now listening on: ...") with a
             bounded wait — ports/URLs are never guessed. Then:
               /healthz                              must be 200
               /v1/status /v1/routing /v1/engines    must be 200 with parseable JSON
               /v1/learning /v1/insights (no taskType)  must be 400 with the
                 required-parameter error — the CONTRACT assertion (a suite that only
                 asserts 200s never notices the deny path breaking)
               /v1/learning /v1/insights ?taskType=code_generation  must be 200
             All probes are loopback, so no HELIOS_API_ACCESS_KEY is needed and none is
             ever read or printed. The API process is ALWAYS stopped in finally via the
             stored process handle (kill by PID including the dotnet-run child tree —
             never pkill by name, which could hit an unrelated operator process).
  metrics    /v1/metrics probed while the API is up: 200 = ok; 404 = failed — the
             endpoint is mapped in src/ai/HELIOS.AIHub.Api/ApiEndpoints.cs, so a 404
             from a live server means a stale build or a route regression, never
             "not shipped yet"; connection loss or any other status is degraded.
  mcp        the MCP server is spawned over stdio
             (dotnet run --project src/mcp/HELIOS.Mcp -c Release --no-build), given the
             newline-delimited JSON-RPC handshake (initialize ->
             notifications/initialized -> tools/list, following nextCursor pagination),
             and the returned tool names must MATCH the distinct helios_* tool names
             enumerated in docs/mcp/CLIENT_SETUP.md name-for-name (a bare count check
             would miss a rename) — parsed from the doc at RUN time, never hardcoded,
             so the doc and the server can never drift silently.
             The process is terminated in finally (stdin close, then tree kill by the
             stored handle).
  cli        `helios-ai status` must exit 0 (degraded '!' providers still exit 0 — the
             designed pre-owner-unlock state) and `fleet-plan --json` stdout must parse
             as JSON (advisory op: a nonzero exit or unparseable output is degraded,
             never a failure — same soft-degrade contract as scripts/fleet/learn-fleet.ps1).

Secrets policy (CLAUDE.md rule): nothing here reads or prints a credential value — the
loopback API needs no key, and no environment variable value ever enters the output.

Exit contract: 0 always in report mode EXCEPT a hard communication failure — the API
never binding, a must-be-200 endpoint answering 5xx or refusing the connection, the MCP
server never answering the handshake, or `helios-ai status` failing to run — exits 1.
Contract drift (wrong 400 body, tool-count mismatch, unparseable advisory JSON) is
degraded and exits 0: the stack communicated, the report says what drifted. Internal
script failure also exits 1.

.PARAMETER Json
Emit one machine-readable rollup object {script, generatedUtc, lanes[], summary,
exitCode} instead of the human table (nothing else on stdout — same convention as
scripts/bootstrap/auth-doctor.ps1 -Json / scripts/setup/setup-all.ps1 -Json). Ignored
when -DryRun is set (the dry run is a human plan printer).

.PARAMETER DryRun
Print the full probe plan — every command that would be launched, every endpoint that
would be asserted, and the tool count currently read from docs/mcp/CLIENT_SETUP.md —
without launching or probing anything, then exit 0 (mirrors
scripts/fleet/learn-fleet.ps1 -DryRun).

.PARAMETER TimeoutSeconds
Bound for each wait: the API's stdout bind wait, each MCP JSON-RPC response, and each
CLI invocation (default 90). Individual HTTP probes use a fixed 15s timeout.

.EXAMPLE
pwsh scripts/verify/stack-smoke.ps1

.EXAMPLE
pwsh scripts/verify/stack-smoke.ps1 -Json | ConvertFrom-Json

.EXAMPLE
pwsh scripts/verify/stack-smoke.ps1 -DryRun
#>
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Json,

    [switch]$DryRun,

    [ValidateRange(10, 600)]
    [int]$TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$clientSetupDoc = Join-Path $repoRoot 'docs' 'mcp' 'CLIENT_SETUP.md'
$buildCommand = 'dotnet build HELIOS.sln -c Release'
$apiProject = 'src/ai/HELIOS.AIHub.Api'
$mcpProject = 'src/mcp/HELIOS.Mcp'
$cliProject = 'src/ai/HELIOS.AIHub.Cli'
$httpProbeTimeoutSec = 15

# -Json promises one object and nothing else on stdout, and from an external caller's
# viewpoint Write-Host lands on stdout too — so all progress printing gates on it
# (auth-doctor.ps1 / setup-all.ps1 convention).
function Write-Report {
    param([string]$Message = '')
    if (-not $Json) { Write-Host $Message }
}

function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

function New-LaneResult {
    param(
        [Parameter(Mandatory)][string]$Lane,
        [Parameter(Mandatory)]
        [ValidateSet('ok', 'degraded', 'failed', 'build-missing')]
        [string]$State,
        [Parameter(Mandatory)][string]$Detail
    )
    [pscustomobject]@{
        lane   = $Lane
        state  = $State
        detail = $Detail
    }
}

# The tool inventory is COUNTED from the doc at run time — never hardcoded — so adding a
# tool without documenting it (or documenting one that was removed) shows up as drift.
# Underscore names only: helios-operator / helios-platform (hyphenated) never match, and
# trailing-underscore matches are dropped — they are wildcard prefixes in the doc's prose
# (`helios_ai_*`), not tool names (every real tool name ends alphanumeric).
function Get-DocumentedToolNames {
    if (-not (Test-Path -LiteralPath $clientSetupDoc)) { return @() }
    $text = Get-Content -Raw -LiteralPath $clientSetupDoc
    @([regex]::Matches($text, 'helios_[a-z0-9_]+') | ForEach-Object Value |
        Where-Object { $_ -notmatch '_$' } | Sort-Object -Unique)
}

# Capture ALL output first, THEN classify. Transport failures (connection refused,
# timeout) surface as Status 0; HTTP error statuses come back as data thanks to
# -SkipHttpErrorCheck — a bare probe that throws on 400 could never assert the deny path.
function Invoke-HttpProbe {
    param([Parameter(Mandatory)][string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $httpProbeTimeoutSec -SkipHttpErrorCheck
        [pscustomobject]@{ Status = [int]$response.StatusCode; Body = [string]$response.Content; Transport = '' }
    }
    catch {
        [pscustomobject]@{ Status = 0; Body = ''; Transport = $_.Exception.Message }
    }
}

function Test-ParsesAsJson {
    param([string]$Text = '')
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    try { $null = $Text | ConvertFrom-Json; return $true } catch { return $false }
}

# Bounded foreground dotnet invocation with file-redirected output: WaitForExit with a
# deadline, and an overrun kills the whole dotnet-run child TREE via the stored handle.
function Invoke-BoundedDotnet {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutSec
    )
    $stamp = [guid]::NewGuid().ToString('n')
    $outPath = Join-Path $script:workDir "run-$stamp.out"
    $errPath = Join-Path $script:workDir "run-$stamp.err"
    $proc = Start-Process -FilePath $script:dotnetExe -ArgumentList $Arguments `
        -WorkingDirectory $repoRoot -RedirectStandardOutput $outPath `
        -RedirectStandardError $errPath -PassThru -NoNewWindow
    $finished = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        $proc.Kill($true)
        $null = $proc.WaitForExit(5000)
    }
    [pscustomobject]@{
        TimedOut = -not $finished
        ExitCode = if ($finished) { $proc.ExitCode } else { -1 }
        Output   = @(if (Test-Path -LiteralPath $outPath) { Get-Content -LiteralPath $outPath })
    }
}

# Reads newline-delimited JSON-RPC from the MCP server's stdout until the response with
# the wanted id arrives or the per-call timeout passes. The deadline is derived HERE,
# fresh for every call — a single absolute deadline shared across the handshake would
# shrink with each earlier reply and mark a healthy-but-slow server as a hard failure
# (review finding: the timeout bounds EACH response, not the whole conversation).
# Server log lines never appear here (the server routes all logging to stderr —
# src/mcp/HELIOS.Mcp/Program.cs), but non-JSON or other-id lines are skipped
# defensively anyway.
function Read-McpResponse {
    param(
        [Parameter(Mandatory)]$Reader,
        [Parameter(Mandatory)][int]$WantId,
        [Parameter(Mandatory)][double]$TimeoutSeconds
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $pending = $null
    while ([datetime]::UtcNow -lt $deadline) {
        if ($null -eq $pending) { $pending = $Reader.ReadLineAsync() }
        $completed = $false
        try { $completed = $pending.Wait(250) } catch { return $null }
        if (-not $completed) { continue }
        $line = $pending.Result
        $pending = $null
        if ($null -eq $line) { return $null }   # EOF — the server exited
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $message = $null
        try { $message = $line | ConvertFrom-Json } catch { continue }
        $id = Get-OptionalProperty $message 'id'
        if ($null -ne $id -and [int]$id -eq $WantId) { return $message }
    }
    return $null
}

# --- Dry run: plan printer only — nothing is launched, probed, or written -------------
if ($DryRun) {
    $docNames = Get-DocumentedToolNames
    Write-Host ''
    Write-Host "Stack smoke plan (bounded waits: ${TimeoutSeconds}s; HTTP probes: ${httpProbeTimeoutSec}s each):"
    Write-Host "  preflight  dotnet on PATH + bin/Release present for $apiProject, $cliProject, $mcpProject"
    Write-Host "             (missing => every live lane reports build-missing with '$buildCommand'; exit 0)"
    Write-Host "  api        launch: dotnet run --project $apiProject -c Release --no-build -- --urls http://127.0.0.1:0"
    Write-Host '             parse the bound URL from the process stdout ("Now listening on: ..."), then assert:'
    Write-Host '               GET /healthz                                    -> 200'
    Write-Host '               GET /v1/status /v1/routing /v1/engines          -> 200 + parseable JSON'
    Write-Host '               GET /v1/learning /v1/insights (no taskType)     -> 400 + required-parameter error'
    Write-Host '               GET /v1/learning /v1/insights ?taskType=code_generation -> 200'
    Write-Host '             stop the API in finally (stored PID, tree kill — never pkill by name)'
    Write-Host '  metrics    GET /v1/metrics -> 200 = ok; 404 = failed (mapped route missing: stale build or regression); else degraded'
    Write-Host "  mcp        spawn: dotnet run --project $mcpProject -c Release --no-build"
    Write-Host '             JSON-RPC over stdio: initialize -> notifications/initialized -> tools/list (+pagination)'
    Write-Host ("             assert tool names match the distinct helios_* names in docs/mcp/CLIENT_SETUP.md " +
        "name-for-name (read at run time; currently $($docNames.Count))")
    Write-Host '             terminate in finally (stdin close, then tree kill by stored handle)'
    Write-Host "  cli        dotnet run --project $cliProject -c Release --no-build -- status          -> exit 0"
    Write-Host "             dotnet run --project $cliProject -c Release --no-build -- fleet-plan --json -> parses as JSON (soft)"
    Write-Host '  exit       0 unless a hard communication failure (5xx/refused on a must-200 endpoint,'
    Write-Host '             API never binding, MCP never answering, or the CLI status run failing) -> 1'
    Write-Host ''
    Write-Host 'Dry run - nothing launched, nothing probed, nothing written.'
    exit 0
}

# --- Live run --------------------------------------------------------------------------
$lanes = [System.Collections.Generic.List[object]]::new()
$hardFailure = $false
$script:workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('helios-stack-smoke-' + [guid]::NewGuid().ToString('n'))

try {
    Write-Report '== HELIOS stack smoke (end-to-end communication proof) =='
    Write-Report ''

    # --- preflight: never builds; report-only when the build is absent ----------------
    $dotnetCommand = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $script:dotnetExe = if ($dotnetCommand) { $dotnetCommand.Source } else { '' }

    $missingOutputs = [System.Collections.Generic.List[string]]::new()
    foreach ($project in @($apiProject, $cliProject, $mcpProject)) {
        $releaseDir = Join-Path $repoRoot $project 'bin' 'Release'
        $builtDll = if (Test-Path -LiteralPath $releaseDir) {
            Get-ChildItem -LiteralPath $releaseDir -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }
        else { $null }
        if ($null -eq $builtDll) { $missingOutputs.Add($project) }
    }

    if (-not $dotnetCommand -or $missingOutputs.Count -gt 0) {
        $why = if (-not $dotnetCommand) { 'dotnet is not on PATH' }
        else { 'no Release outputs for: ' + ($missingOutputs -join ', ') }
        # The exact build command IS the detail (this script itself never builds:
        # another workflow may own the build, and a surprise build here could race it).
        $lanes.Add((New-LaneResult -Lane 'preflight' -State 'build-missing' -Detail "$why — run: $buildCommand"))
        foreach ($skipped in @('api', 'metrics', 'mcp', 'cli')) {
            $lanes.Add((New-LaneResult -Lane $skipped -State 'build-missing' -Detail "skipped — run: $buildCommand"))
        }
    }
    else {
        $lanes.Add((New-LaneResult -Lane 'preflight' -State 'ok' `
            -Detail 'dotnet on PATH; Release outputs present for the Api, Cli, and Mcp projects (--no-build can run)'))
        New-Item -ItemType Directory -Path $script:workDir -Force | Out-Null

        # --- API lane (+ metrics lane, probed while the API is still up) --------------
        Write-Report '-- api: launching helios-ai-api in the background --'
        $apiChecks = [System.Collections.Generic.List[string]]::new()
        $apiState = 'ok'
        $apiProc = $null
        $metricsLane = $null
        $apiOut = Join-Path $script:workDir 'api.out'
        $apiErr = Join-Path $script:workDir 'api.err'
        try {
            # Port 0: the kernel assigns a free port, so this smoke never collides with a
            # dev instance on launchSettings' 5170 — and the URL is still taken ONLY from
            # the process's own stdout below, never guessed.
            $apiProc = Start-Process -FilePath $script:dotnetExe -ArgumentList @(
                'run', '--project', $apiProject, '-c', 'Release', '--no-build',
                '--', '--urls', 'http://127.0.0.1:0'
            ) -WorkingDirectory $repoRoot -RedirectStandardOutput $apiOut `
                -RedirectStandardError $apiErr -PassThru -NoNewWindow

            $boundUrl = ''
            $bindDeadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
            while (-not $boundUrl -and [datetime]::UtcNow -lt $bindDeadline) {
                if ($apiProc.HasExited) { break }
                Start-Sleep -Milliseconds 250
                if (Test-Path -LiteralPath $apiOut) {
                    $stdoutText = Get-Content -Raw -LiteralPath $apiOut -ErrorAction SilentlyContinue
                    if ($stdoutText -and $stdoutText -match 'Now listening on:\s+(https?://\S+)') {
                        $boundUrl = $Matches[1].TrimEnd('/')
                    }
                }
            }

            if (-not $boundUrl) {
                $apiState = 'failed'
                $hardFailure = $true
                $reason = if ($apiProc.HasExited) { "the process exited (code $($apiProc.ExitCode)) before binding" }
                else { "no 'Now listening on:' line on stdout within ${TimeoutSeconds}s" }
                $apiChecks.Add("bind FAILED — $reason (hard communication failure)")
                $metricsLane = New-LaneResult -Lane 'metrics' -State 'failed' -Detail 'not probed — the API lane failed to bind'
            }
            else {
                # Wildcard binds (0.0.0.0 / [::] / + / *) are listen addresses, not
                # probe addresses — normalize the HOST only; the PORT stays exactly as
                # the API reported it.
                $probeBase = $boundUrl -replace '://(\*|\+|0\.0\.0\.0|\[::\])', '://127.0.0.1'
                $apiChecks.Add("bound $boundUrl (from stdout)")
                Write-Report "  bound: $boundUrl"

                # /healthz must be 200. Hard-failure classification (5xx or refused)
                # per the exit contract; any other wrong status is drift, not death.
                $probe = Invoke-HttpProbe -Url "$probeBase/healthz"
                if ($probe.Status -eq 200) { $apiChecks.Add('healthz 200') }
                elseif ($probe.Status -eq 0 -or $probe.Status -ge 500) {
                    $apiState = 'failed'; $hardFailure = $true
                    $apiChecks.Add("healthz FAILED — $(if ($probe.Status -eq 0) { "connection: $($probe.Transport)" } else { "HTTP $($probe.Status)" }) (hard)")
                }
                else { if ($apiState -eq 'ok') { $apiState = 'degraded' }; $apiChecks.Add("healthz HTTP $($probe.Status) (expected 200)") }

                # Read endpoints: 200 + parseable JSON.
                foreach ($path in @('/v1/status', '/v1/routing', '/v1/engines')) {
                    $probe = Invoke-HttpProbe -Url "$probeBase$path"
                    if ($probe.Status -eq 200 -and (Test-ParsesAsJson $probe.Body)) {
                        $apiChecks.Add("$path 200 json")
                    }
                    elseif ($probe.Status -eq 0 -or $probe.Status -ge 500) {
                        $apiState = 'failed'; $hardFailure = $true
                        $apiChecks.Add("$path FAILED — $(if ($probe.Status -eq 0) { "connection: $($probe.Transport)" } else { "HTTP $($probe.Status)" }) (hard)")
                    }
                    elseif ($probe.Status -eq 200) {
                        if ($apiState -eq 'ok') { $apiState = 'degraded' }
                        $apiChecks.Add("$path 200 but body is not parseable JSON")
                    }
                    else {
                        if ($apiState -eq 'ok') { $apiState = 'degraded' }
                        $apiChecks.Add("$path HTTP $($probe.Status) (expected 200)")
                    }
                }

                # CONTRACT assertion — the deny path: without taskType these must be 400
                # with the required-parameter error (ApiError => {"error":"taskType query
                # parameter is required."}). Asserting only 200s would never notice the
                # parameter validation breaking.
                foreach ($path in @('/v1/learning', '/v1/insights')) {
                    $probe = Invoke-HttpProbe -Url "$probeBase$path"
                    if ($probe.Status -eq 400 -and $probe.Body -match 'taskType' -and $probe.Body -match '(?i)required') {
                        $apiChecks.Add("$path (no taskType) 400 contract ok")
                    }
                    elseif ($probe.Status -eq 0 -or $probe.Status -ge 500) {
                        $apiState = 'failed'; $hardFailure = $true
                        $apiChecks.Add("$path FAILED — $(if ($probe.Status -eq 0) { "connection: $($probe.Transport)" } else { "HTTP $($probe.Status)" }) (hard)")
                    }
                    else {
                        if ($apiState -eq 'ok') { $apiState = 'degraded' }
                        $apiChecks.Add("$path (no taskType) HTTP $($probe.Status) without the required-parameter error (contract drift; expected 400)")
                    }
                }

                # And the allow path with a real task type from config/aihub.json.
                foreach ($path in @('/v1/learning', '/v1/insights')) {
                    $probe = Invoke-HttpProbe -Url "$probeBase$path`?taskType=code_generation"
                    if ($probe.Status -eq 200) { $apiChecks.Add("$path`?taskType=code_generation 200") }
                    elseif ($probe.Status -eq 0 -or $probe.Status -ge 500) {
                        $apiState = 'failed'; $hardFailure = $true
                        $apiChecks.Add("$path`?taskType FAILED — $(if ($probe.Status -eq 0) { "connection: $($probe.Transport)" } else { "HTTP $($probe.Status)" }) (hard)")
                    }
                    else { if ($apiState -eq 'ok') { $apiState = 'degraded' }; $apiChecks.Add("$path`?taskType HTTP $($probe.Status) (expected 200)") }
                }

                # /v1/metrics: its own lane so a telemetry regression never muddies the
                # api core contract verdict. The endpoint shipped alongside this script
                # (ApiEndpoints.cs maps it), so 404 from a live server is contract
                # drift — a stale build or a lost route — not "pending" (review
                # finding: pending after shipping would disguise a regression).
                $probe = Invoke-HttpProbe -Url "$probeBase/v1/metrics"
                $metricsLane = if ($probe.Status -eq 200) {
                    New-LaneResult -Lane 'metrics' -State 'ok' -Detail '/v1/metrics 200 — the telemetry endpoint is live'
                }
                elseif ($probe.Status -eq 404) {
                    $hardFailure = $true
                    New-LaneResult -Lane 'metrics' -State 'failed' -Detail ('/v1/metrics 404 but the route is mapped in ' +
                        'ApiEndpoints.cs — stale build or route regression (rebuild: dotnet build HELIOS.sln -c Release)')
                }
                elseif ($probe.Status -eq 0) {
                    New-LaneResult -Lane 'metrics' -State 'degraded' -Detail "/v1/metrics unreachable ($($probe.Transport)) — never gates"
                }
                else {
                    New-LaneResult -Lane 'metrics' -State 'degraded' -Detail "/v1/metrics HTTP $($probe.Status) (expected 200 or 404) — never gates"
                }
            }
        }
        finally {
            # ALWAYS stop the API: stored process handle only (the PID captured at
            # spawn), tree kill so the dotnet-run child app dies too. Never pkill by
            # name — that could take down an unrelated operator process. Guarded so a
            # process that exits mid-kill cannot mask the lane result.
            if ($null -ne $apiProc) {
                try {
                    if (-not $apiProc.HasExited) {
                        $apiProc.Kill($true)
                        $null = $apiProc.WaitForExit(5000)
                    }
                }
                catch { Write-Verbose "API terminate: $($_.Exception.Message)" }
            }
        }
        $lanes.Add((New-LaneResult -Lane 'api' -State $apiState -Detail ($apiChecks -join '; ')))
        if ($null -ne $metricsLane) { $lanes.Add($metricsLane) }
        Write-Report "  api: $apiState"

        # --- MCP lane -----------------------------------------------------------------
        Write-Report '-- mcp: JSON-RPC handshake over stdio --'
        $mcpState = 'ok'
        $mcpDetail = ''
        $mcpProc = $null
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $script:dotnetExe
            foreach ($arg in @('run', '--project', $mcpProject, '-c', 'Release', '--no-build')) {
                $psi.ArgumentList.Add($arg)
            }
            $psi.WorkingDirectory = $repoRoot
            $psi.UseShellExecute = $false
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            # UTF-8 WITHOUT BOM: a BOM ahead of the first JSON-RPC message breaks the
            # server's parse of it.
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            $psi.StandardInputEncoding = $utf8NoBom
            $psi.StandardOutputEncoding = $utf8NoBom
            $psi.StandardErrorEncoding = $utf8NoBom
            $mcpProc = [System.Diagnostics.Process]::new()
            $mcpProc.StartInfo = $psi
            $null = $mcpProc.Start()
            # Drain stderr continuously (the server logs there): an unread pipe fills
            # its buffer and blocks the child mid-write.
            $null = $mcpProc.StandardError.ReadToEndAsync()

            $writer = $mcpProc.StandardInput
            $writer.AutoFlush = $true

            # Newline-delimited JSON-RPC handshake: initialize (await the reply), then
            # the initialized notification, then tools/list.
            $writer.WriteLine((@{
                jsonrpc = '2.0'; id = 1; method = 'initialize'
                params  = @{
                    protocolVersion = '2024-11-05'
                    capabilities    = @{}
                    clientInfo      = @{ name = 'stack-smoke'; version = '1.0.0' }
                }
            } | ConvertTo-Json -Compress -Depth 6))
            $initReply = Read-McpResponse -Reader $mcpProc.StandardOutput -WantId 1 -TimeoutSeconds $TimeoutSeconds
            if ($null -eq $initReply) {
                $mcpState = 'failed'; $hardFailure = $true
                $mcpDetail = "no initialize response within ${TimeoutSeconds}s (hard communication failure)"
            }
            else {
                $writer.WriteLine((@{ jsonrpc = '2.0'; method = 'notifications/initialized' } | ConvertTo-Json -Compress))

                $serverTools = [System.Collections.Generic.List[string]]::new()
                $cursor = $null
                $requestId = 2
                $listFailed = $false
                for ($page = 0; $page -lt 10; $page++) {
                    $listParams = @{}
                    if ($cursor) { $listParams['cursor'] = $cursor }
                    $writer.WriteLine((@{ jsonrpc = '2.0'; id = $requestId; method = 'tools/list'; params = $listParams } |
                        ConvertTo-Json -Compress -Depth 4))
                    $reply = Read-McpResponse -Reader $mcpProc.StandardOutput -WantId $requestId -TimeoutSeconds $TimeoutSeconds
                    if ($null -eq $reply) { $listFailed = $true; break }
                    $result = Get-OptionalProperty $reply 'result'
                    if ($null -eq $result) { $listFailed = $true; break }
                    foreach ($tool in @(Get-OptionalProperty $result 'tools' @())) {
                        $toolName = [string](Get-OptionalProperty $tool 'name' '')
                        if ($toolName) { $serverTools.Add($toolName) }
                    }
                    $cursor = Get-OptionalProperty $result 'nextCursor'
                    if (-not $cursor) { break }
                    $requestId++
                }

                if ($listFailed) {
                    $mcpState = 'failed'; $hardFailure = $true
                    $mcpDetail = 'initialize succeeded but tools/list got no result (hard communication failure)'
                }
                else {
                    $docNames = Get-DocumentedToolNames
                    $uniqueServer = @($serverTools | Sort-Object -Unique)
                    if ($docNames.Count -eq 0) {
                        $mcpState = 'degraded'
                        $mcpDetail = ("tools/list returned $($uniqueServer.Count) tool(s), but docs/mcp/CLIENT_SETUP.md " +
                            'yielded no helios_* names to compare against (doc missing or reshaped)')
                    }
                    else {
                        # Compare NAMES, not counts: a rename keeps the cardinality
                        # identical while the contract drifts (review finding), so
                        # equality is asserted on the two sets and the counts are
                        # only display.
                        $docOnly = @($docNames | Where-Object { $_ -notin $uniqueServer })
                        $serverOnly = @($uniqueServer | Where-Object { $_ -notin $docNames })
                        if ($docOnly.Count -eq 0 -and $serverOnly.Count -eq 0) {
                            $mcpDetail = ("tools/list returned $($uniqueServer.Count) tools matching the " +
                                "$($docNames.Count) distinct helios_* names in docs/mcp/CLIENT_SETUP.md " +
                                'name-for-name (compared at run time)')
                        }
                        else {
                            # Drift, not death: the server communicated — the doc and the tool
                            # assembly disagree. Name the drift so the fix is one edit.
                            $mcpState = 'degraded'
                            $mcpDetail = "tool drift: server $($uniqueServer.Count) vs doc $($docNames.Count)"
                            if ($docOnly.Count -gt 0) { $mcpDetail += '; doc-only: ' + ($docOnly -join ', ') }
                            if ($serverOnly.Count -gt 0) { $mcpDetail += '; server-only: ' + ($serverOnly -join ', ') }
                            $mcpDetail += ' — align docs/mcp/CLIENT_SETUP.md with src/mcp/HELIOS.Mcp'
                        }
                    }
                }
            }
        }
        catch {
            $mcpState = 'failed'; $hardFailure = $true
            $mcpDetail = "MCP spawn/handshake threw: $($_.Exception.Message) (hard communication failure)"
        }
        finally {
            # Terminate in finally: EOF on stdin lets a healthy server exit cleanly;
            # a tree kill by the stored handle covers the rest. Never pkill by name.
            # Every call is guarded: if Start() itself failed there is no associated OS
            # process and these members throw — that must not mask the lane result.
            if ($null -ne $mcpProc) {
                try { $mcpProc.StandardInput.Close() } catch { Write-Verbose "MCP stdin close: $($_.Exception.Message)" }
                try {
                    if (-not $mcpProc.WaitForExit(2000)) { $mcpProc.Kill($true) }
                    $null = $mcpProc.WaitForExit(5000)
                }
                catch { Write-Verbose "MCP terminate: $($_.Exception.Message)" }
                $mcpProc.Dispose()
            }
        }
        $lanes.Add((New-LaneResult -Lane 'mcp' -State $mcpState -Detail $mcpDetail))
        Write-Report "  mcp: $mcpState"

        # --- CLI lane -----------------------------------------------------------------
        Write-Report '-- cli: helios-ai status + fleet-plan --json --'
        $cliChecks = [System.Collections.Generic.List[string]]::new()
        $cliState = 'ok'

        $statusRun = Invoke-BoundedDotnet -TimeoutSec $TimeoutSeconds -Arguments @(
            'run', '--project', $cliProject, '-c', 'Release', '--no-build', '--', 'status')
        if ($statusRun.TimedOut) {
            $cliState = 'failed'; $hardFailure = $true
            $cliChecks.Add("status timed out after ${TimeoutSeconds}s (hard communication failure)")
        }
        elseif ($statusRun.ExitCode -ne 0) {
            # `status` exits 0 whenever the hub constructs — even with every provider
            # degraded — so a nonzero here means the hub itself cannot run.
            $cliState = 'failed'; $hardFailure = $true
            $cliChecks.Add("status exited $($statusRun.ExitCode) (hard communication failure — the hub could not run)")
        }
        else {
            $cliChecks.Add("status exit 0 ($(@($statusRun.Output).Count) provider line(s); degraded providers are the designed pre-owner-unlock state)")
        }

        # fleet-plan is ADVISORY (learn-fleet.ps1 contract): nonzero exit or unparseable
        # output degrades, never fails. stderr carries the human banner — file-split
        # redirection already keeps it out of the JSON we parse.
        $planRun = Invoke-BoundedDotnet -TimeoutSec $TimeoutSeconds -Arguments @(
            'run', '--project', $cliProject, '-c', 'Release', '--no-build', '--', 'fleet-plan', '--json')
        if ($planRun.TimedOut -or $planRun.ExitCode -ne 0) {
            if ($cliState -eq 'ok') { $cliState = 'degraded' }
            $cliChecks.Add("fleet-plan --json unavailable (exit $($planRun.ExitCode)$(if ($planRun.TimedOut) { '; timed out' })) — advisory, never gates")
        }
        else {
            # Tolerate residual preamble: join from the first line that opens JSON
            # (same idiom as scripts/fleet/learn-fleet.ps1).
            $planLines = @($planRun.Output)
            $openerIndex = -1
            for ($i = 0; $i -lt $planLines.Count; $i++) {
                if ($planLines[$i] -match '^\s*[\[{]') { $openerIndex = $i; break }
            }
            $planParsed = $false
            if ($openerIndex -ge 0) {
                $planParsed = Test-ParsesAsJson (@($planLines[$openerIndex..($planLines.Count - 1)]) -join "`n")
            }
            if ($planParsed) { $cliChecks.Add('fleet-plan --json parses as JSON') }
            else {
                if ($cliState -eq 'ok') { $cliState = 'degraded' }
                $cliChecks.Add('fleet-plan --json exit 0 but output did not parse as JSON — advisory, never gates')
            }
        }
        $lanes.Add((New-LaneResult -Lane 'cli' -State $cliState -Detail ($cliChecks -join '; ')))
        Write-Report "  cli: $cliState"
    }

    # --- Report -----------------------------------------------------------------------
    $summary = [ordered]@{
        ok           = @($lanes | Where-Object { $_.state -eq 'ok' }).Count
        degraded     = @($lanes | Where-Object { $_.state -eq 'degraded' }).Count
        failed       = @($lanes | Where-Object { $_.state -eq 'failed' }).Count
        buildMissing = @($lanes | Where-Object { $_.state -eq 'build-missing' }).Count
    }
    # Exit contract: report-only stays 0 — degraded/build-missing are truthful
    # states, not failures. Only a hard communication failure gates.
    $exitCode = if ($hardFailure) { 1 } else { 0 }

    if ($Json) {
        [ordered]@{
            script       = 'scripts/verify/stack-smoke.ps1'
            generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
            lanes        = @($lanes)
            summary      = $summary
            exitCode     = $exitCode
        } | ConvertTo-Json -Depth 6
    }
    else {
        Write-Report ''
        $table = $lanes |
            Format-Table -AutoSize -Property @(
                @{ n = 'Lane'; e = { $_.lane } }
                @{ n = 'State'; e = { $_.state } }
                @{ n = 'Detail'; e = { $_.detail } }
            ) |
            Out-String -Width 4096
        Write-Report $table.TrimEnd()
        Write-Report ''
        $verdict = if ($hardFailure) { 'HARD COMMUNICATION FAILURE — exit 1' }
        elseif ($summary.buildMissing -gt 0) { "build missing — run: $buildCommand (report-only, exit 0)" }
        else { 'stack communicates — exit 0 (degraded providers are the designed pre-owner-unlock state)' }
        Write-Report ("Stack smoke: {0} ok, {1} degraded, {2} failed, {3} build-missing — {4}" -f
            $summary.ok, $summary.degraded, $summary.failed, $summary.buildMissing, $verdict)
    }

    exit $exitCode
}
catch {
    [Console]::Error.WriteLine("stack-smoke: internal failure — $($_.Exception.Message)")
    exit 1
}
finally {
    if (Test-Path -LiteralPath $script:workDir) {
        Remove-Item -LiteralPath $script:workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
