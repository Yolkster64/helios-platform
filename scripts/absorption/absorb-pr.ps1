<#
.SYNOPSIS
Benchmark an upstream PR for absorption: trial-merge it, run the full local gate,
score it, and record an advisory learning outcome.

.DESCRIPTION
The absorption pipeline's engine (docs/architecture/ABSORPTION_PIPELINE.md).
Fetches refs/pull/<N>/head from the upstream repo, trial-merges it onto the
current branch in a DISPOSABLE git worktree, runs the same gate CI runs
(native C++ build, solution build, Bicep compile, .NET tests, Python tests),
and writes a scored report under .helios/absorption/. Nothing ever merges into
the real working tree: -Apply only keeps the scratch worktree around (merge
staged, conflicts included) so a human can inspect, cherry-pick, and commit
deliberately.

If helios-ai-api is reachable (HELIOS_API_URL, default http://localhost:5170),
the verdict is also recorded as an ADVISORY outcome via POST /v1/learning with
source "absorption-benchmark" — visible to /v1/insights, ignored by routing.

.EXAMPLE
pwsh scripts/absorption/absorb-pr.ps1 -PrNumber 222
pwsh scripts/absorption/absorb-pr.ps1 -PrNumber 294 -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$PrNumber,
    [string]$Upstream = 'M0nado/helios-platform',
    [switch]$Apply,
    [switch]$SkipTests,
    [string]$ApiKey = $env:HELIOS_API_ACCESS_KEY,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $Body
        return [ordered]@{ step = $Name; ok = $true; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    }
    catch {
        return [ordered]@{ step = $Name; ok = $false; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); error = "$_" }
    }
}

$upstreamUrl = "https://github.com/$Upstream"
$started = Get-Date
$reportDir = Join-Path $RepoRoot '.helios' 'absorption'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$worktree = Join-Path $reportDir "wt-pr-$PrNumber"

Write-Host "== Absorption benchmark: $Upstream#$PrNumber =="

git -C $RepoRoot fetch $upstreamUrl "refs/pull/$PrNumber/head" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Could not fetch refs/pull/$PrNumber/head from $upstreamUrl."
    exit 1
}
$prSha = (git -C $RepoRoot rev-parse FETCH_HEAD).Trim()
Write-Host "PR head: $prSha"

if (Test-Path $worktree) {
    git -C $RepoRoot worktree remove --force $worktree 2>$null
    Remove-Item -Recurse -Force $worktree -ErrorAction SilentlyContinue
}
git -C $RepoRoot worktree add --detach $worktree HEAD | Out-Null

$steps = [System.Collections.Generic.List[object]]::new()
$conflicts = @()
try {
    git -C $worktree merge --no-commit --no-ff $prSha 2>&1 | Out-Null
    $mergeClean = ($LASTEXITCODE -eq 0)
    if (-not $mergeClean) {
        $conflicts = @(git -C $worktree diff --name-only --diff-filter=U)
    }
    $stat = git -C $worktree diff --cached --shortstat 2>$null
    $steps.Add([ordered]@{ step = 'trial-merge'; ok = $mergeClean; conflicts = $conflicts; diffstat = "$stat".Trim() })

    if ($mergeClean) {
        $env:PATH = "$env:PATH$([IO.Path]::PathSeparator)/root/.dotnet"

        $nativeBuild = Join-Path $worktree 'scripts/build/build-native.sh'
        if (Test-Path $nativeBuild) {
            $steps.Add((Invoke-Step 'native-build' {
                if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
                    throw 'bash is required to build the native C++ spoke.'
                }
                $out = bash $nativeBuild 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($out | Select-Object -Last 10 | Out-String) }
            }))
        }

        $steps.Add((Invoke-Step 'dotnet-build' {
            $out = dotnet build (Join-Path $worktree 'HELIOS.sln') -c Release --nologo 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($out | Select-Object -Last 5 | Out-String) }
        }))

        # infra/main.bicep is a required repository entrypoint. A candidate that
        # deletes or renames it must fail the absorption gate rather than silently
        # skipping infrastructure validation.
        $bicepFile = Join-Path $worktree 'infra/main.bicep'
        $steps.Add((Invoke-Step 'bicep-build' {
            if (-not (Test-Path -LiteralPath $bicepFile)) {
                throw 'Required Bicep entrypoint infra/main.bicep is missing from the merged tree.'
            }
            if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
                throw 'Azure CLI is required to compile infra/main.bicep.'
            }
            $bicepOut = Join-Path $reportDir "pr-$PrNumber-main.arm.json"
            try {
                $out = az bicep build --file $bicepFile --outfile $bicepOut 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($out | Select-Object -Last 10 | Out-String) }
            }
            finally {
                Remove-Item -LiteralPath $bicepOut -Force -ErrorAction SilentlyContinue
            }
        }))

        if (-not $SkipTests) {
            $steps.Add((Invoke-Step 'dotnet-test' {
                $out = dotnet test (Join-Path $worktree 'tests/HELIOS.AIHub.Tests') -c Release --nologo -v q 2>&1
                if ($LASTEXITCODE -ne 0) { throw ($out | Select-Object -Last 5 | Out-String) }
            }))
            $steps.Add((Invoke-Step 'pytest' {
                Push-Location (Join-Path $worktree 'src/ai/python')
                try {
                    $out = python3 -m pytest tests -q 2>&1
                    if ($LASTEXITCODE -ne 0) { throw ($out | Select-Object -Last 5 | Out-String) }
                }
                finally { Pop-Location }
            }))
        }
    }
}
finally {
    if (-not $Apply) {
        git -C $worktree merge --abort 2>$null
        git -C $RepoRoot worktree remove --force $worktree 2>$null
    }
}

$allStepsOk = ($steps | Where-Object { -not $_.ok } | Measure-Object).Count -eq 0
$gatePassed = $allStepsOk -and -not $SkipTests
$elapsed = [math]::Round(((Get-Date) - $started).TotalMilliseconds)
$report = [ordered]@{
    upstream   = $Upstream
    pr         = $PrNumber
    prHead     = $prSha
    ourHead    = (git -C $RepoRoot rev-parse HEAD).Trim()
    benchmarked = $started.ToUniversalTime().ToString('o')
    gatePassed = $gatePassed
    steps      = $steps
    verdict    = if ($gatePassed) { 'absorbable: trial merge clean and full gate green' }
                 elseif ($conflicts.Count -gt 0) { "conflicts in $($conflicts.Count) file(s): manual reconciliation required" }
                 elseif ($allStepsOk -and $SkipTests) { 'partial: merge and build clean, but -SkipTests ran — rerun without it for a full verdict' }
                 else { 'gate failed on the merged tree: see steps' }
    worktree   = if ($Apply) { $worktree } else { $null }
}
$reportPath = Join-Path $reportDir "pr-$PrNumber.json"
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding utf8
Write-Host "Report: $reportPath"
Write-Host "Verdict: $($report.verdict)"
if ($Apply -and (Test-Path $worktree)) {
    Write-Host "Worktree kept for review: $worktree (merge staged; commit deliberately or 'git worktree remove --force' it)"
}

$apiBase = if ($env:HELIOS_API_URL) { $env:HELIOS_API_URL.TrimEnd('/') } else { 'http://localhost:5170' }
try {
    [Uri]$apiUri = $null
    if (-not [Uri]::TryCreate($apiBase, [UriKind]::Absolute, [ref]$apiUri) -or
        $apiUri.Scheme -notin @('http', 'https')) {
        throw "HELIOS_API_URL must be an absolute HTTP(S) URL."
    }
    if (-not $apiUri.IsLoopback -and $apiUri.Scheme -ne 'https') {
        throw "Remote HELIOS_API_URL values must use HTTPS."
    }
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
        $headers['X-HELIOS-Api-Key'] = $ApiKey
    }
    $body = @{
        taskType = 'absorption'
        source = 'absorption-benchmark'
        provider = "$Upstream#$PrNumber"
        model = $prSha.Substring(0, 12)
        success = $gatePassed
        latencyMs = $elapsed
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$apiBase/v1/learning" -ContentType 'application/json' `
        -Headers $headers -Body $body -TimeoutSec 5 -MaximumRedirection 0 | Out-Null
    Write-Host "Advisory outcome recorded at $apiBase/v1/learning."
}
catch {
    Write-Host "helios-ai-api unavailable or access denied at $apiBase — advisory outcome not recorded (report file is authoritative)."
}

exit $(if ($gatePassed) { 0 } else { 2 })
