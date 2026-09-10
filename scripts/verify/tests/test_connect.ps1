# Offline contract suite for scripts/bootstrap/connect.sh and its Windows twin
# scripts/bootstrap/connect.ps1.
#
# Both orchestrators are run for real. Every .ps1 child goes through a shim named by
# HELIOS_PWSH, and `gh`, `az` and `codex` are shimmed first on PATH, so nothing reaches
# GitHub, Entra or chatgpt.com - `codex cloud list` is a live HTTPS call and is shimmed for
# that reason. What is NOT shimmed is the bash side: the verify lane runs the real
# first-run.sh (and through it cloud-shell-setup.sh), which is deliberate, since the
# read-only contract this suite checks is precisely about what that child writes. Those
# scripts reach the network only through the shimmed CLIs. Every shim invocation is logged,
# which is how the suite proves what a read-only run does and does not do.
#
# The contracts here are the ones the review of PR #252 found broken, so each is a regression
# test with a story:
#   * --status / -Status must mutate NOTHING. It used to write .helios/connect-state.json and
#     leave a first-run report behind, and - the P1 - it called auto-login.ps1, which delegates
#     to auth-doctor.ps1 -Apply and can replace the Azure CLI profile.
#   * --json must emit the report THIS run built. It used to print the state file, which a
#     read-only run does not write, so it died on a clean checkout and served stale lanes
#     after a real one.
#   * A lane's state comes from the report it read, not from an exit code.
#   * The exit code is the contract: 0 = nothing left for you, 2 = owner items remain,
#     1 = a lane failed for a reason that is not yours to fix.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Get-ReportField($Object, [string]$Name) {
    # A property of a parsed report, or $null when it is absent. Set-StrictMode -Version
    # Latest turns a plain $report.thing into a terminating error when `thing` is not there,
    # which would replace a named assertion failure with a PowerShell stack trace.
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Assert-True($Value, $Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) { throw "$Message (expected '$Expected', got '$Actual')" }
    $script:cases++
}
$script:cases = 0

# The shims are #!/usr/bin/env bash scripts made executable with chmod, and the bash twin
# needs a POSIX shell to run at all, so this suite is a Linux/macOS suite. It says so and
# stops rather than failing on a missing chmod; CI runs it on ubuntu-latest.
if ($IsWindows) {
    Write-Host 'SKIPPED: this suite shims its children with bash scripts, so it needs a POSIX shell.'
    Write-Host '         Run it from WSL, or read the CI result (.github/workflows/auth-contracts.yml).'
    exit 0
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('helios-connect-suite-' + [guid]::NewGuid())
$bin = Join-Path $temp 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null
# A private temp directory for the runs under test, so "did this run leave a file behind"
# is answerable exactly: whatever appears here was put there by the twin, not by the rest
# of the machine. Both twins honour it - mktemp reads TMPDIR, New-TemporaryFile reads
# TMPDIR on Unix and TEMP/TMP on Windows.
$sandbox = Join-Path $temp 'sandbox-tmp'
New-Item -ItemType Directory -Path $sandbox | Out-Null
$log = Join-Path $temp 'shim.log'
$stateBackup = Join-Path $temp 'helios-backup'
$savedPath = $env:PATH
$savedPwsh = $env:HELIOS_PWSH
$savedTmp = @{ TMPDIR = $env:TMPDIR; TEMP = $env:TEMP; TMP = $env:TMP }
$stateDir = Join-Path $root '.helios'
$stateFile = Join-Path $stateDir 'connect-state.json'
$reportFile = Join-Path $stateDir 'connect-firstrun.json'
# An empty .helios/ appearing in a checkout that had none is a change too, so the state
# directory is part of the read-only contract - and not only its existence. On a developer's
# machine .helios/ is already there, so an existence check alone has no teeth locally and
# only fails in CI; the CONTENTS are compared, which is what catches a child writing into an
# existing .helios/ (first-run.sh does exactly that unless it is told where to put its state).
function Get-StateDirEntries {
    # Name AND content: first-run OVERWRITES .helios/bootstrap-state.json rather than adding
    # to it, so comparing the set of paths alone would call a rewritten state file unchanged.
    if (-not (Test-Path -LiteralPath $stateDir)) { return '<absent>' }
    $entries = foreach ($item in Get-ChildItem -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue) {
        if ($item.PSIsContainer) { "$($item.FullName)/" }
        else { "$($item.FullName) $((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)" }
    }
    return (($entries | Sort-Object) -join "`n")
}
$stateDirBefore = Get-StateDirEntries
$stateDirExisted = Test-Path -LiteralPath $stateDir

# The real interpreter, captured before `pwsh` on PATH means the shim: the ps1 twin has to be
# run by something that is actually PowerShell.
$realPwsh = [Environment]::ProcessPath
if (-not $realPwsh) { $realPwsh = 'pwsh' }

# A run that promises to change nothing must not change THESE either; the suite refuses to
# hide behind "the file happened not to exist".
function Get-Fingerprint([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

try {
    # The .ps1 shim: logs what it was asked to run and answers with a minimal report of the
    # shape each lane reader expects (auth-doctor speaks lanes[], auto-login ownerActions[]).
    # One lane is deliberately left needing the owner, so a hub lane that reported 'ok' from an
    # exit code rather than from the report would fail the assertion below.
    @'
#!/usr/bin/env bash
printf 'pwsh %s\n' "$*" >> "$CONNECT_SHIM_LOG"
for arg in "$@"; do
  case "$arg" in
    *auth-doctor.ps1) printf '{"lanes":[{"lane":"gh","state":"needs-owner"},{"lane":"az","state":"ready"}]}\n'; exit 0 ;;
    *auto-login.ps1)  printf '{"ownerActions":[{"Text":"set OPENAI_API_KEY"}]}\n'; exit 0 ;;
    *first-run.ps1)   printf '{"lanes":{"gh":{"state":"needs-owner"}}}\n'; exit 2 ;;
    # The inventory reports the state of the repository today: labels applied, the ruleset
    # and the environment not. Exit 2 is "ran and found gaps" - the surfaces lane must read
    # the ROWS, not the exit code, and must name the gaps rather than counting them.
    *inventory-surfaces.ps1)
      printf '{"state":"gaps","gaps":2,"surfaces":[{"surface":"rulesets","state":"absent"},{"surface":"labels","state":"in-force"},{"surface":"environments","state":"unknown"}]}\n'
      exit 2 ;;
  esac
done
exit 0
'@ -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin 'pwsh') -NoNewline -Encoding utf8
    # gh and az: present but signed out, so no lane can reach a network call.
    foreach ($name in 'gh', 'az', 'codex') {
        @'
#!/usr/bin/env bash
printf 'NAME %s\n' "$*" >> "$CONNECT_SHIM_LOG"
exit 1
'@.Replace('NAME', $name) -replace "`r`n", "`n" | Set-Content -LiteralPath (Join-Path $bin $name) -NoNewline -Encoding utf8
    }
    foreach ($name in 'pwsh', 'gh', 'az', 'codex') { & chmod +x (Join-Path $bin $name) }

    # A copy, not just a fingerprint. When the read-only contract regresses - exactly what
    # this suite exists to catch - the bash twin runs the REAL first-run, which overwrites
    # .helios/bootstrap-state.json and rewrites the log and steps file. Detecting that and
    # leaving the damage behind would mean the suite destroys a developer's bootstrap record
    # every time it does its job.
    if ($stateDirExisted) {
        Copy-Item -LiteralPath $stateDir -Destination $stateBackup -Recurse -Force
    }

    $env:CONNECT_SHIM_LOG = $log
    $env:HELIOS_PWSH = Join-Path $bin 'pwsh'
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$savedPath"
    $env:TMPDIR = $sandbox; $env:TEMP = $sandbox; $env:TMP = $sandbox

    $laneOrder = @{}
    foreach ($twin in @(
            @{ Name = 'connect.sh'; Exe = 'bash'
               Args = @((Join-Path $root 'scripts/bootstrap/connect.sh'), '--status', '--json')
               Human = @((Join-Path $root 'scripts/bootstrap/connect.sh'), '--status')
               SkipVerify = @('--skip-verify') },
            @{ Name = 'connect.ps1'; Exe = $realPwsh
               Args = @('-NoProfile', '-File', (Join-Path $root 'scripts/bootstrap/connect.ps1'), '-Status', '-Json')
               Human = @('-NoProfile', '-File', (Join-Path $root 'scripts/bootstrap/connect.ps1'), '-Status')
               SkipVerify = @('-Skip', 'verify') })) {

        Set-Content -LiteralPath $log -Value '' -NoNewline
        $before = @{ State = Get-Fingerprint $stateFile; Report = Get-Fingerprint $reportFile }

        # @arguments, not @(...): an array in an argument position is one argument, which a
        # native command receives as a single space-joined string.
        $arguments = $twin.Args
        $json = & $twin.Exe @arguments 2>$null
        $exit = $LASTEXITCODE

        # 1. --json emits the report THIS run built, not a file it did not write.
        #    Read through Get-ReportField, never $report.thing: under Set-StrictMode -Version Latest a
        #    missing property throws, so a twin that emitted the wrong shape would blow up
        #    here with a PowerShell error instead of failing the assertion that names it.
        #    (That is the very defect this suite found in connect.ps1.)
        $report = ($json | Out-String) | ConvertFrom-Json
        $reportLanes = @(Get-ReportField $report 'lanes')
        Assert-True ($reportLanes.Count -gt 0) "$($twin.Name) read-only --json emitted no lanes"
        # The number docs/CONNECT.md and both script headers publish, not a floor: with a
        # floor of ten, four lanes could be deleted from both twins and the table would still
        # match the parity check, which compares names only.
        Assert-Equal 15 $reportLanes.Count "$($twin.Name) reported $($reportLanes.Count) lanes, and the docs say fifteen"
        Assert-True ((Get-ReportField $report 'verifyOnly') -eq $true) `
            "$($twin.Name) read-only did not mark the report read-only"
        $laneOrder[$twin.Name] = (($reportLanes | ForEach-Object { Get-ReportField $_ 'name' }) -join ',')

        # 2. The exit contract: read-only on a keyless host has owner items, so 2 - never 1.
        Assert-True ($exit -eq 0 -or $exit -eq 2) "$($twin.Name) read-only exited $exit (expected 0 or 2)"

        # 2b. The surfaces lane reads the inventory's ROWS, not its exit code. The shim exits
        #     2 with two surfaces not in force; a lane that read $? alone, or that counted
        #     rather than named, would pass a weaker assertion than this one.
        $surfaceLane = @($reportLanes | Where-Object { (Get-ReportField $_ 'name') -eq 'surfaces' })
        Assert-Equal 1 $surfaceLane.Count "$($twin.Name) did not report a surfaces lane"
        Assert-Equal 'needs-owner' (Get-ReportField $surfaceLane[0] 'state') `
            "$($twin.Name) surfaces lane did not read the gaps the inventory reported"
        $surfaceDetail = [string](Get-ReportField $surfaceLane[0] 'detail')
        foreach ($named in 'rulesets', 'environments') {
            Assert-True ($surfaceDetail -match $named) `
                "$($twin.Name) surfaces lane did not name the $named gap: $surfaceDetail"
        }
        # `labels` is in force, so naming it would be a false alarm in the owner's checklist.
        Assert-True ($surfaceDetail -notmatch 'labels') `
            "$($twin.Name) surfaces lane named a surface that IS in force: $surfaceDetail"

        # 3. It mutated nothing: not the two state files, not the state directory's existence,
        #    and not the temp directory - the first-run report a read-only run needs is a
        #    temporary copy, and a temporary copy that is never deleted is a file left behind.
        Assert-Equal $before.State (Get-Fingerprint $stateFile) "$($twin.Name) read-only wrote the state file"
        Assert-Equal $before.Report (Get-Fingerprint $reportFile) "$($twin.Name) read-only wrote a first-run report"
        # Named differences, not two full snapshots: the message lands in a CI log, where a
        # dump of every path and hash buries the one entry that moved.
        $stateDirAfter = Get-StateDirEntries
        if ($stateDirAfter -ne $stateDirBefore) {
            $changed = (Compare-Object ($stateDirBefore -split "`n") ($stateDirAfter -split "`n") |
                ForEach-Object { "$($_.SideIndicator) $(($_.InputObject -split ' ')[0])" } | Sort-Object -Unique) -join '; '
            throw "$($twin.Name) read-only changed what is under the .helios state directory: $changed"
        }
        $script:cases++
        # ($strays | ForEach-Object Name), not $strays.Name: member enumeration over an EMPTY
        # array throws under Set-StrictMode -Version Latest, so the message built for a failure
        # would itself fail on the passing path.
        $strays = @(Get-ChildItem -LiteralPath $sandbox -Force -ErrorAction SilentlyContinue)
        Assert-Equal 0 $strays.Count `
            "$($twin.Name) read-only left $($strays.Count) file(s) in the temp directory: $(($strays | ForEach-Object Name) -join ', ')"

        # 4. The P1: a read-only run must not reach auto-login, which repairs the az profile.
        #
        #    Asserted on a run with the VERIFY LANE SKIPPED, because the verify lane runs the
        #    real first-run, whose own chain calls auth-doctor and auto-login through this same
        #    shim. Matching the whole log therefore proved nothing about the hub lane: a hub
        #    lane that consulted nothing and fabricated a report still left `auth-doctor.ps1`
        #    in the log, courtesy of first-run. Skipping verify leaves only the lanes this
        #    orchestrator invokes itself.
        Set-Content -LiteralPath $log -Value '' -NoNewline
        $hubOnly = $twin.Args + $twin.SkipVerify
        $null = & $twin.Exe @hubOnly 2>$null
        $shimLog = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
        Assert-True ($shimLog -notmatch 'auto-login\.ps1') `
            "$($twin.Name) read-only invoked auto-login.ps1, which delegates to auth-doctor -Apply"
        $doctorCalls = ([regex]::Matches($shimLog, 'auth-doctor\.ps1')).Count
        Assert-Equal 1 $doctorCalls `
            "$($twin.Name) hub lane consulted auth-doctor $doctorCalls time(s) with verify skipped (expected exactly 1)"
        Assert-True ($shimLog -notmatch 'first-run') `
            "$($twin.Name) ran first-run even with the verify lane skipped"

        # 4b. The HUMAN output, not just --json. An owner reads this path, and it is where a
        #     read-only run claimed "State saved to .helios/connect-state.json" - naming a
        #     file it deliberately does not write, and on a clean checkout does not exist.
        #     Testing only the --json path is how that survived.
        $humanArgs = $twin.Human
        $human = (& $twin.Exe @humanArgs 2>$null | Out-String)
        Assert-True ($human -match 'Read-only run: nothing was written') `
            "$($twin.Name) read-only did not say it wrote nothing"
        Assert-True ($human -notmatch 'State saved to') `
            "$($twin.Name) read-only claimed it saved the state file"

        # 5. A lane's state comes from the report, not from an exit code: auth-doctor answered
        #    with one lane needing the owner, so the hub lane must not claim everything resolved.
        $hub = @($reportLanes | Where-Object { (Get-ReportField $_ 'name') -eq 'hub' })
        Assert-Equal 1 $hub.Count "$($twin.Name) reported no hub lane"
        Assert-True ((Get-ReportField $hub[0] 'state') -ne 'ok') `
            "$($twin.Name) hub lane said 'ok' while auth-doctor reported an outstanding lane"

        # 6. Every lane carries the fields the state file and the checklist read, and a lane
        #    that needs the owner names the one command that moves it - a checklist row with
        #    no command is the thing this whole lane exists to avoid.
        foreach ($lane in $reportLanes) {
            $laneName = Get-ReportField $lane 'name'
            foreach ($field in 'name', 'state', 'detail') {
                Assert-True ([bool](Get-ReportField $lane $field)) "$($twin.Name) lane '$laneName' has an empty $field"
            }
            $laneState = Get-ReportField $lane 'state'
            Assert-True ($laneState -in @('ok', 'needs-owner', 'skipped', 'failed')) `
                "$($twin.Name) lane '$laneName' has state '$laneState'"
            if ($laneState -eq 'needs-owner') {
                Assert-True ([bool](Get-ReportField $lane 'ownerAction')) `
                    "$($twin.Name) lane '$laneName' needs the owner but names no command"
            }
        }
    }

    # 7. The two twins describe the same lanes in the same order: an owner reading the Windows
    #    table and the Cloud Shell table must not be looking at two different products.
    Assert-Equal $laneOrder['connect.sh'] $laneOrder['connect.ps1'] 'the two twins report different lanes'

    # The bash twin's own syntax, checked here so a broken edit fails this suite too.
    & bash -n (Join-Path $root 'scripts/bootstrap/connect.sh')
    Assert-Equal 0 $LASTEXITCODE 'connect.sh does not parse'
    $errors = $null; $tokens = $null
    [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root 'scripts/bootstrap/connect.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Equal 0 $errors.Count 'connect.ps1 does not parse'
}
finally {
    # Restore .helios BEFORE the temp tree (which holds the backup) is removed.
    if ((Get-StateDirEntries) -ne $stateDirBefore) {
        Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($stateDirExisted -and (Test-Path -LiteralPath $stateBackup)) {
            Copy-Item -LiteralPath $stateBackup -Destination $stateDir -Recurse -Force
        }
        Write-Host 'NOTE: a run under test changed .helios/; it has been restored from the suite backup.'
    }
    $env:PATH = $savedPath
    $env:HELIOS_PWSH = $savedPwsh
    $env:TMPDIR = $savedTmp.TMPDIR; $env:TEMP = $savedTmp.TEMP; $env:TMP = $savedTmp.TMP
    [Environment]::SetEnvironmentVariable('CONNECT_SHIM_LOG', $null)
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed $($script:cases) offline connect cases."
# The suite's own status is the verdict: the orchestrators exit 2 on purpose when owner items
# remain, and would otherwise leave $LASTEXITCODE = 2 for a CI step's trailing exit check.
exit 0
