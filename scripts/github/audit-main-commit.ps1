#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Reports a commit that reached the default branch without the review the ruleset requires.

.DESCRIPTION
    `.github/rulesets/main.json` requires eight status checks and a pull request before
    anything lands on main. It is not applied: `governance-apply.yml`'s plan job reports
    `no existing ruleset named 'main' -> create`, because creating it needs repository
    administration that no workflow token has. Until an administrator credential exists,
    every one of those rules is a description of intent rather than a control.

    This is the compensating control. It runs on push to main and asks, of the commit that
    just landed, the two questions the ruleset would have answered before the fact:

      1. Did it arrive through a pull request?  (GET /commits/{sha}/pulls)
      2. Were the ruleset's required contexts SUCCESSFUL on that pull request's head?

    It cannot undo a push - nothing can, after the fact - so its product is a loud, specific
    report: which commit, which contexts were missing or red, and what the ruleset would have
    done. That turns a silent bypass into a red run on main with the evidence attached.

    The required contexts are read from the ruleset files themselves, so this audit and the
    ruleset cannot drift apart. Adding a context to main.json extends this check for free.

    Deliberately NOT fail-closed on a read failure. This runs after the fact on main, where a
    5xx that reds the branch teaches people to ignore the signal; an unreadable answer is
    reported as `unknown` and exits 0. That is the opposite of verify-environment-gate.ps1,
    which gates a deployment before it happens and must refuse when it cannot tell.

.PARAMETER Repository
    owner/repo to read. Defaults to Yolkster64/helios-platform.

.PARAMETER Sha
    The commit that landed. Defaults to $env:GITHUB_SHA.

.PARAMETER RulesetDirectory
    Where the ruleset JSON lives. Defaults to .github/rulesets.

.PARAMETER Branch
    The branch the commit landed on, matched against each ruleset's ref_name include list.
    Defaults to main.

.PARAMETER PullLookupRetries
    How many times to RE-READ an empty commit-to-pull-request answer before believing it.
    GitHub indexes that association asynchronously and this runs seconds after the push, so an
    empty first answer can mean "not indexed yet". Defaults to 2 (three reads in all).

.PARAMETER RetryDelaySeconds
    Seconds between those re-reads. Defaults to 10; the offline suite passes 0.

.PARAMETER Json
    Emit one JSON verdict object on stdout instead of the human lines.

.NOTES
    Exit codes: 0 = the commit came through a pull request with every required context green,
    OR the answer could not be read (reported as unknown); 1 = it bypassed the rules the
    ruleset states, with the specifics printed.
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$Sha,
    [string]$RulesetDirectory,
    [string]$Branch = 'main',
    [int]$PullLookupRetries = 2,
    [int]$RetryDelaySeconds = 10,
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

$lines = [System.Collections.Generic.List[string]]::new()
function Write-Line { param([string]$Text = '') if (-not $Json) { Write-Host $Text }; $lines.Add($Text) | Out-Null }

# --- gh api wire layer (identical across scripts/github/*.ps1; keep in copy-sync) ------
$script:GhApiArgs = @('api', '-H', 'X-GitHub-Api-Version: 2022-11-28')
$script:LastMutationUtc = [DateTime]::UtcNow.AddSeconds(-5)

function Invoke-GhApi {
    param(
        [Parameter(Mandatory)][string[]]$GhArgs,
        [switch]$Mutating
    )
    if (-not $script:gh) { return [pscustomobject]@{ ExitCode = 127; HttpStatus = 0; Text = ''; Json = $null } }
    $retried = $false
    while ($true) {
        if ($Mutating) {
            $elapsed = ([DateTime]::UtcNow - $script:LastMutationUtc).TotalMilliseconds
            if ($elapsed -lt 1000) { Start-Sleep -Milliseconds ([int](1000 - $elapsed)) }
        }
        $argv = $script:GhApiArgs + @('-i') + $GhArgs
        $raw = @(& $script:gh.Source @argv 2>$null)
        $code = $LASTEXITCODE
        if ($Mutating) { $script:LastMutationUtc = [DateTime]::UtcNow }
        $lines2 = @($raw | ForEach-Object { ([string]$_).TrimEnd("`r") })
        $blank = [Array]::IndexOf($lines2, '')
        $headers = @(if ($blank -gt 0) { $lines2[0..($blank - 1)] })
        $body = @(if ($blank -ge 0) { $lines2 | Select-Object -Skip ($blank + 1) })
        $status = 0
        if ($headers.Count -gt 0 -and $headers[0] -match '^HTTP/\S+\s+(\d{3})') { $status = [int]$Matches[1] }
        $text = ($body -join "`n").Trim()
        $parsed = $null
        if ($text) { try { $parsed = $text | ConvertFrom-Json -NoEnumerate } catch { $parsed = $null } }
        if ($code -ne 0 -and -not $retried) {
            $message = [string](Get-OptionalProperty $parsed 'message' '')
            if ($status -eq 0 -and ([string](Get-OptionalProperty $parsed 'status' '')) -match '^\d{3}$') { $status = [int]$Matches[0] }
            if ($status -eq 429 -or ($status -eq 403 -and $message -match 'rate limit|secondary')) {
                $retryAfter = 60
                foreach ($h in $headers) { if ($h -match '^Retry-After:\s*(\d+)') { $retryAfter = [int]$Matches[1] } }
                Start-Sleep -Seconds $retryAfter
                $retried = $true
                continue
            }
        }
        return [pscustomobject]@{ ExitCode = $code; HttpStatus = $status; Text = $text; Json = $parsed }
    }
}

function Complete-Audit {
    param([Parameter(Mandatory)][string]$State, [string]$Reason = '', [string[]]$Missing = @(), [int]$Exit = 0)
    if ($Json) {
        [pscustomobject]@{
            repository = $Repository
            sha        = $Sha
            branch     = $Branch
            state      = $State
            reason     = $Reason
            missing    = @($Missing)
        } | ConvertTo-Json -Depth 6
    }
    exit $Exit
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $RulesetDirectory) { $RulesetDirectory = Join-Path $repoRoot '.github' 'rulesets' }
if (-not $Sha) { $Sha = [string]$env:GITHUB_SHA }

Write-Line "audit-main-commit: repository=$Repository branch=$Branch sha=$Sha"

if (-not $Sha) {
    Write-Line 'No commit sha given and GITHUB_SHA is unset; nothing to audit.'
    Complete-Audit -State 'unknown' -Reason 'no sha'
}

# The contexts the ruleset would require on this branch, read from the ruleset itself so the
# two cannot drift. A ruleset that gates another branch says nothing about this commit.
$required = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $RulesetDirectory -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $RulesetDirectory -Filter '*.json' -File) {
        try { $ruleset = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json }
        catch {
            Write-Line "   ruleset $($file.Name) is not valid JSON; skipped"
            continue
        }
        $includes = @(Get-OptionalProperty (Get-OptionalProperty (Get-OptionalProperty $ruleset 'conditions' $null) 'ref_name' $null) 'include' @())
        $gatesThisBranch = $false
        foreach ($ref in $includes) {
            $name = ([string]$ref) -replace '^refs/heads/', ''
            if ($name -eq $Branch -or $name -eq '~DEFAULT_BRANCH' -or $name -eq '~ALL') { $gatesThisBranch = $true }
        }
        if (-not $gatesThisBranch) { continue }
        foreach ($rule in @(Get-OptionalProperty $ruleset 'rules' @())) {
            if ([string](Get-OptionalProperty $rule 'type' '') -ne 'required_status_checks') { continue }
            foreach ($entry in @(Get-OptionalProperty (Get-OptionalProperty $rule 'parameters' $null) 'required_status_checks' @())) {
                $context = [string](Get-OptionalProperty $entry 'context' '')
                if ($context -and -not $required.Contains($context)) { $required.Add($context) | Out-Null }
            }
        }
    }
}
Write-Line "   the ruleset requires $($required.Count) context(s) on $Branch"

$script:gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $script:gh) {
    # Reported, not failed. This runs after the push; a red main because a tool was missing
    # teaches people to ignore the signal, and the signal is the whole product here.
    Write-Line 'gh is not on PATH, so this commit could not be audited.'
    Complete-Audit -State 'unknown' -Reason 'gh unavailable'
}

# GitHub indexes the commit-to-pull-request association asynchronously, and this job runs
# seconds after the push that created the commit. An empty first answer is therefore as likely
# to mean "not indexed yet" as "nobody reviewed it" - and reporting the second when it was the
# first is a false accusation on main, which is exactly what teaches people to ignore this job.
# So an empty answer is re-read before it is believed. A genuine direct push simply stays empty
# and costs this run the retry window; nothing else about it changes.
$merged = @()
for ($attempt = 0; $attempt -le $PullLookupRetries; $attempt++) {
    if ($attempt -gt 0) {
        Write-Line "   no pull request is associated with this commit yet; re-reading ($($attempt + 1) of $($PullLookupRetries + 1))"
        if ($RetryDelaySeconds -gt 0) { Start-Sleep -Seconds $RetryDelaySeconds }
    }
    $pulls = Invoke-GhApi -GhArgs @("repos/$Repository/commits/$Sha/pulls")
    if ($pulls.ExitCode -ne 0) {
        Write-Line "   could not read the pull requests for this commit (HTTP $($pulls.HttpStatus)); not audited"
        Complete-Audit -State 'unknown' -Reason "pull lookup failed (HTTP $($pulls.HttpStatus))"
    }
    # A commit with no pull requests answers `[]`, which parses to an EMPTY ARRAY, not null.
    # Null here means the body did not parse at all, and an unparsed answer read as "no pull
    # requests" would accuse a properly reviewed commit of bypassing review.
    if ($null -eq $pulls.Json) {
        Write-Line '   the pull request list did not parse; not audited'
        Complete-Audit -State 'unknown' -Reason 'pull list unreadable'
    }
    $merged = @(@($pulls.Json) | Where-Object { $null -ne $_ -and (Get-OptionalProperty $_ 'merged_at' $null) })
    if ($merged.Count -gt 0) { break }
}
if ($merged.Count -eq 0) {
    Write-Line ''
    Write-Line "BYPASS: commit $Sha reached $Branch without a merged pull request."
    Write-Line ''
    Write-Line 'The ruleset in .github/rulesets/ states that main takes changes only through a'
    Write-Line 'pull request. It is not applied yet - creating it needs repository administration -'
    Write-Line 'so this ran after the fact instead of refusing before it. What landed is not undone'
    Write-Line 'by this job; read the commit and decide.'
    Write-Line ''
    Write-Line "  gh api repos/$Repository/commits/$Sha"
    Complete-Audit -State 'no-pull-request' -Reason 'the commit is not the head of any merged pull request' -Exit 1
}

$pr = $merged[0]
$number = Get-OptionalProperty $pr 'number' '?'
$prHead = [string](Get-OptionalProperty (Get-OptionalProperty $pr 'head' $null) 'sha' '')
Write-Line "   arrived through pull request #$number (head $($prHead.Substring(0, [Math]::Min(8, $prHead.Length))))"

if ($required.Count -eq 0) {
    Write-Line '   no ruleset requires any context on this branch; nothing further to check.'
    Complete-Audit -State 'reviewed' -Reason "pull request #$number, no required contexts declared"
}

if (-not $prHead) {
    Write-Line '   the pull request reports no head sha; the contexts could not be checked'
    Complete-Audit -State 'unknown' -Reason 'pull request head sha missing'
}

# Both surfaces: modern check runs AND legacy commit statuses. A required context can be
# either, and reading only one would report a green check as missing.
$successful = [System.Collections.Generic.List[string]]::new()
# per_page=100 rather than --paginate: every call in this wire layer carries -i, and gh emits
# a header block PER PAGE, so a paginated reply puts page two's headers inside what this parser
# treats as the body and the JSON parse fails silently. A failed parse would read as zero check
# runs, which would report every required context missing - a FALSE bypass, on main, loudly.
# One page of 100 covers this repository (49 check runs on a recent head, against a default
# page of 30 that would itself have dropped 19 of them); when the server says there are more
# than arrived, the answer is unknown rather than a guess in the accusing direction.
$checks = Invoke-GhApi -GhArgs @("repos/$Repository/commits/$prHead/check-runs?per_page=100")
if ($checks.ExitCode -ne 0) {
    Write-Line "   could not read the check runs on the pull request head (HTTP $($checks.HttpStatus)); not audited"
    Complete-Audit -State 'unknown' -Reason "check-run lookup failed (HTTP $($checks.HttpStatus))"
}
if ($null -eq $checks.Json) {
    Write-Line '   the check-run list did not parse; not audited'
    Complete-Audit -State 'unknown' -Reason 'check-run list unreadable'
}
$checkRuns = @(Get-OptionalProperty $checks.Json 'check_runs' @())
$checkTotal = [int](Get-OptionalProperty $checks.Json 'total_count' $checkRuns.Count)
if ($checkTotal -gt $checkRuns.Count) {
    Write-Line "   this head has $checkTotal check runs and one page carried $($checkRuns.Count); not audited"
    Complete-Audit -State 'unknown' -Reason "check runs truncated ($($checkRuns.Count) of $checkTotal)"
}
foreach ($run in $checkRuns) {
    $name = [string](Get-OptionalProperty $run 'name' '')
    $conclusion = [string](Get-OptionalProperty $run 'conclusion' '')
    # `skipped` counts, and that is not a loophole: GitHub itself treats a skipped required
    # check as satisfied, which is exactly why the workflows that own these contexts trigger
    # on every pull request and skip the WORK in a job-level if:.
    if ($name -and $conclusion -in @('success', 'skipped', 'neutral') -and -not $successful.Contains($name)) {
        $successful.Add($name) | Out-Null
    }
}
$statusesRead = $true
$statuses = Invoke-GhApi -GhArgs @("repos/$Repository/commits/$prHead/status?per_page=100")
if ($statuses.ExitCode -ne 0 -or $null -eq $statuses.Json) {
    $statusesRead = $false
}
else {
    $statusList = @(Get-OptionalProperty $statuses.Json 'statuses' @())
    $statusTotal = [int](Get-OptionalProperty $statuses.Json 'total_count' $statusList.Count)
    if ($statusTotal -gt $statusList.Count) { $statusesRead = $false }
    foreach ($status in $statusList) {
        $context = [string](Get-OptionalProperty $status 'context' '')
        if ($context -and [string](Get-OptionalProperty $status 'state' '') -eq 'success' -and -not $successful.Contains($context)) {
            $successful.Add($context) | Out-Null
        }
    }
}

$missing = @($required | Where-Object { -not $successful.Contains($_) })
# An unreadable status list only changes the answer when something is still unaccounted for:
# a required context delivered as a legacy status would look missing purely because the list
# could not be read. Say so instead of accusing. When the check runs already account for every
# required context, an unreadable status list changes nothing and the OK below stands.
if ($missing.Count -gt 0 -and -not $statusesRead) {
    Write-Line "   $($missing.Count) context(s) did not report as a check run and the legacy commit statuses could not be read; not audited"
    Complete-Audit -State 'unknown' -Reason "legacy statuses unreadable, $($missing.Count) context(s) unaccounted" -Missing $missing
}
if ($missing.Count -gt 0) {
    Write-Line ''
    Write-Line "BYPASS: pull request #$number merged into $Branch without $($missing.Count) required context(s):"
    foreach ($context in $missing) { Write-Line "  - $context" }
    Write-Line ''
    Write-Line 'The ruleset would have held the merge until each of these reported success on the'
    Write-Line 'pull request head. It is not applied yet, so the merge went through and this is the'
    Write-Line 'record of it.'
    Complete-Audit -State 'missing-checks' -Reason "pull request #$number" -Missing $missing -Exit 1
}

Write-Line ''
Write-Line "OK: pull request #$number, and all $($required.Count) required context(s) reported success."
Complete-Audit -State 'reviewed' -Reason "pull request #$number"
