#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Applies the repository rulesets in .github/rulesets/ to GitHub via `gh api`.

.DESCRIPTION
    Dry-run by default: prints the exact `gh api` calls it would make and changes
    nothing. Re-run with -Apply to execute them. Idempotent: it GETs the repo's
    existing rulesets first and matches by ruleset NAME among the repository's own
    rulesets only (GET /rulesets lists organization rulesets too, includes_parents
    defaults to true, and a same-named org ruleset must never be PUT). A match is
    read back (GET /repos/{owner}/{repo}/rulesets/{id}; the list omits rules and
    conditions) and compared with the file on enforcement, target, conditions,
    rules and bypass_actors — keys sorted, arrays order-insensitive, null values
    and server-added id/node_id/_links/source/timestamps ignored — so an unchanged
    ruleset reads `in sync` and makes no call. A differing one is updated in place
    (PUT /repos/{owner}/{repo}/rulesets/{id}), a missing one is created
    (POST /repos/{owner}/{repo}/rulesets). Re-running never duplicates.

    The ruleset JSON files are strict JSON (the API shape allows no comments), so
    this header is the runbook for what main.json pins and why.

    Required status checks in main.json — job-LEVEL names, each verified against the
    workflow source (a job's check context is its `name:` field, or the job id when
    unnamed; cited by job, not by line number, so edits to the workflows do not
    stale this table):

      Context                        Workflow                              Job
      -----------------------------  ------------------------------------  ----------------------------
      Build solution & run tests     .github/workflows/dotnet-build.yml    build-and-test (name:)
      bicep-validate                 .github/workflows/infra-validate.yml  bicep-validate (job id, unnamed)
      arm-freshness                  .github/workflows/infra-validate.yml  arm-freshness (job id, unnamed)
      terraform-validate             .github/workflows/infra-validate.yml  terraform-validate (job id, unnamed)
      Preflight Validation           .github/workflows/ci-validation.yml   preflight (name:)
      PowerShell Syntax Validation   .github/workflows/ci-validation.yml   syntax-check (name:)
      File Structure Validation      .github/workflows/ci-validation.yml   file-integrity (name:)
      Quality Check Summary          .github/workflows/quality.yml         quality-summary (name:)

    Deliberately NOT required:
      - dotnet-build.yml `net11-preview` (".NET 11 preview build (informational,
        allowed to fail)") — allowed-to-fail by design; never gate on a preview SDK.
      - dotnet-build.yml `legacy-core-status` — informational, never fails; no gate value.
      - ci-validation.yml markdown-check / documentation-check / test-scripts /
        security-scan / validation-summary — continue-on-error or never-fail jobs.
      - Everything in the known-red inventory (docs/architecture/ROADMAP_MULTI_LLM.md),
        plus status-dashboard.yml (scheduled publisher, not a PR gate) and verify.yml
        (asserts nonexistent files; keep non-required).

    Policy choices encoded in main.json:
      - pull_request with required_approving_review_count = 0: the review loop is
        bot-driven (Copilot + Codex auto-review); a human-approval gate would stall it.
        dismiss_stale_reviews_on_push = false for the same reason.
      - strict_required_status_checks_policy = false: branches need not be up to date
        with main before merging (auto-merge would otherwise thrash on rebases).
      - deletion + non_fast_forward rules: branch deletion and force pushes blocked.
      - bypass_actors = []: nobody bypasses; the repo admin can edit the ruleset itself.

    ORDERING CONSTRAINT — apply this ruleset only AFTER the no-path-filter
    pull_request triggers are on main. dotnet-build.yml and infra-validate.yml
    were path-filtered, so a PR outside those paths produced no run and the four
    contexts they own (Build solution & run tests, bicep-validate, arm-freshness,
    terraform-validate: 4 of the 8 required) stranded as "Expected" forever. With
    bypass_actors = [] NOBODY — not the owner, not an admin — can override a
    stranded check, so applying main.json first would block every docs-only
    merge. PR #113 replaces the filter with an unfiltered pull_request trigger
    plus a `changes` job that skips the heavy jobs (build-and-test; bicep-validate
    / arm-freshness / terraform-validate) on an irrelevant diff, and GitHub treats
    a skipped required check as satisfied. Merge that first, then apply.

.PARAMETER Apply
    Execute the `gh api` calls. Without it the script only prints them (dry run).

.PARAMETER Repository
    Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER RulesetDirectory
    Directory containing the ruleset *.json files. Defaults to .github/rulesets/
    relative to this checkout.

.EXAMPLE
    pwsh scripts/github/apply-rulesets.ps1
    # dry run: prints the POST/PUT calls, changes nothing

.EXAMPLE
    pwsh scripts/github/apply-rulesets.ps1 -Apply
    # applies; requires `gh` authenticated with admin access (admin:repo scope PAT
    # or an owner `gh auth login`)

.NOTES
    Exit codes: 0 = success (or clean dry run); 1 = invalid ruleset file or API
    failure; 2 = gh CLI or a usable wire credential unavailable in -Apply mode.
    Secrets: this script never reads, stores, or prints token values — the auth
    probe is `gh api repos/{repo}`'s exit code plus one boolean permission field
    (`gh auth status` is deliberately not consulted: it can lie both ways, and
    the REST wire is the ground truth — scripts/verify/rest-connect.ps1 doctrine).
    Wire: every `gh api` call carries `X-GitHub-Api-Version: 2022-11-28` (gh
    2.63.2 sends none by itself); a 429, or a 403 naming the rate/secondary
    limit, is retried once after Retry-After (60 s when absent); mutations are
    paced >= 1 s apart.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$RulesetDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern).
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# --- gh api wire layer (identical across scripts/github/*.ps1; keep in copy-sync) ------
# Every call carries the pinned REST version: gh 2.63.2 sends no X-GitHub-Api-Version
# by itself, and an unpinned call opts into whatever the default becomes. The same
# prefix heads every printed replay line, so an operator retypes exactly this call.
$script:GhApiArgs = @('api', '-H', 'X-GitHub-Api-Version: 2022-11-28')
$script:GhApiReplay = "gh api -H 'X-GitHub-Api-Version: 2022-11-28'"
$script:LastMutationUtc = [DateTime]::UtcNow.AddSeconds(-5)

# One gh api call. -i puts the status line and headers in front of the body, so the
# HTTP status and Retry-After are known without echoing anything from the wire
# (stderr is discarded). Stdout is captured FIRST and $LASTEXITCODE read at once.
# On a non-zero exit the reply's own {status,message} decide whether GitHub was rate
# limiting (429, or a 403 whose message names the rate/secondary limit): the call
# then sleeps Retry-After seconds (60 when the header is absent) and retries ONCE.
# Every other failure returns as-is: a 4xx would fail identically, and a blind retry
# of a POST could double-create. -Mutating paces writes >= 1 s apart (GitHub's
# secondary limit is ~80 content-creating requests per minute).
# Returns {ExitCode, HttpStatus, Text, Json}; HttpStatus is 0 when no reply arrived.
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
        $lines = @($raw | ForEach-Object { ([string]$_).TrimEnd("`r") })
        $blank = [Array]::IndexOf($lines, '')
        $headers = @(if ($blank -gt 0) { $lines[0..($blank - 1)] })
        $body = @(if ($blank -ge 0) { $lines | Select-Object -Skip ($blank + 1) })
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

# Canonical text of one JSON value for the in-sync check: null-valued keys dropped
# (an omitted manifest key equals a server null), object keys sorted, arrays sorted
# by their own canonical text (rule and check order carry no meaning), scalars as
# compact JSON. Two documents are in sync when their canonical texts are equal.
function ConvertTo-CanonicalText {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return ($Value | ConvertTo-Json -Compress) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [datetime]) { return ($Value.ToUniversalTime().ToString('o') | ConvertTo-Json -Compress) }
    if ($Value -is [System.ValueType]) { return [string]$Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = foreach ($key in ($Value.Keys | Sort-Object)) {
            if ($null -eq $Value[$key]) { continue }
            ([string]$key | ConvertTo-Json -Compress) + ':' + (ConvertTo-CanonicalText $Value[$key])
        }
        return '{' + (@($parts) -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @(foreach ($element in $Value) { ConvertTo-CanonicalText $element })
        return '[' + (@($parts | Sort-Object) -join ',') + ']'
    }
    $parts = foreach ($prop in ($Value.PSObject.Properties | Sort-Object Name)) {
        if ($null -eq $prop.Value) { continue }
        ($prop.Name | ConvertTo-Json -Compress) + ':' + (ConvertTo-CanonicalText $prop.Value)
    }
    return '{' + (@($parts) -join ',') + '}'
}

# The five API-owned keys of a ruleset, each as canonical text, so a drift report
# can name the key. Server-added fields (id, node_id, _links, source, source_type,
# created_at, updated_at, current_user_can_bypass) never enter: only these five do.
# An omitted target reads as 'branch' and omitted bypass_actors as [] (API defaults).
function Get-RulesetShape {
    param($Doc)
    return [ordered]@{
        enforcement   = ConvertTo-CanonicalText ([string](Get-OptionalProperty $Doc 'enforcement' ''))
        target        = ConvertTo-CanonicalText ([string](Get-OptionalProperty $Doc 'target' 'branch'))
        conditions    = ConvertTo-CanonicalText (Get-OptionalProperty $Doc 'conditions' $null)
        rules         = ConvertTo-CanonicalText @(Get-OptionalProperty $Doc 'rules' @())
        bypass_actors = ConvertTo-CanonicalText @(Get-OptionalProperty $Doc 'bypass_actors' @())
    }
}

if (-not $RulesetDirectory) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $RulesetDirectory = Join-Path $repoRoot '.github' 'rulesets'
}

if (-not (Test-Path -LiteralPath $RulesetDirectory -PathType Container)) {
    Write-Error -ErrorAction Continue "Ruleset directory not found: $RulesetDirectory"
    exit 1
}

$rulesetFiles = @(Get-ChildItem -LiteralPath $RulesetDirectory -Filter '*.json' -File | Sort-Object Name)
if ($rulesetFiles.Count -eq 0) {
    Write-Error -ErrorAction Continue "No *.json ruleset files found in $RulesetDirectory"
    exit 1
}

$mode = if ($Apply) { 'apply' } else { 'dry-run' }
Write-Host "apply-rulesets: mode=$mode repository=$Repository rulesets=$($rulesetFiles.Count) ($RulesetDirectory)"

# --- Probe the WIRE, not `gh auth status` (rest-connect.ps1 doctrine): the CLI's
# --- opinion can lie both ways — a REST-valid token can fail it, and an injecting
# --- transport can make a dead env token look valid. What -Apply actually needs
# --- is (1) gh on PATH to make the calls and (2) a wire credential that can read
# --- the repo and holds admin. Capture-then-$LASTEXITCODE; the captured output is
# --- one boolean permission field, never credential material.
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
$wireOk = $false
$wireAdmin = $false
if ($gh) {
    $probe = Invoke-GhApi -GhArgs @("repos/$Repository", '--jq', '.permissions.admin')
    if ($probe.ExitCode -eq 0) {
        $wireOk = $true
        $wireAdmin = ($probe.Text -eq 'true')
    }
}

if ($Apply -and -not $gh) {
    Write-Host 'apply-rulesets: FAILED PRECONDITION - the GitHub CLI (gh) is not on PATH.'
    Write-Host 'Install it (https://cli.github.com/), then authenticate with an identity that'
    Write-Host "has admin access to $Repository (classic PAT with the admin:repo scope, or an"
    Write-Host 'owner `gh auth login`). Re-run without -Apply for a dry run that needs neither.'
    exit 2
}
if ($Apply -and -not $wireOk) {
    Write-Host "apply-rulesets: FAILED PRECONDITION - the wire probe could not read repos/$Repository."
    Write-Host 'No usable GitHub credential answered on the REST wire ("gh auth status" is'
    Write-Host 'deliberately not consulted - it can lie both ways; the REST probe is the ground'
    Write-Host 'truth, scripts/verify/rest-connect.ps1 doctrine). Authenticate first: "gh auth'
    Write-Host 'login", or scripts/bootstrap/connect-github.sh --from-env (persists a REST-valid'
    Write-Host 'GH_TOKEN non-interactively), or set the GH_TOKEN environment variable (the NAME'
    Write-Host 'of the variable to set - never put the value in a file or argument).'
    exit 2
}
if ($Apply -and -not $wireAdmin) {
    Write-Host "apply-rulesets: FAILED PRECONDITION - the wire credential cannot administer $Repository."
    Write-Host 'The probe read the repository but .permissions.admin is not true. Rulesets need'
    Write-Host 'admin access: the admin:repo scope for a classic PAT, or "Administration: write"'
    Write-Host 'for a fine-grained PAT. Nothing was changed.'
    exit 2
}

# --- Fetch existing rulesets so re-runs update by name instead of duplicating.
# --- The list includes organization rulesets (includes_parents defaults to true);
# --- only this repository's own (source_type Repository) may be matched and PUT.
$existing = @()
$existenceKnown = $false
if ($gh -and $wireOk) {
    $listRead = Invoke-GhApi -GhArgs @("repos/$Repository/rulesets?per_page=100")
    if ($listRead.ExitCode -eq 0) {
        $repoShortName = $Repository.Split('/')[-1]
        $existing = @(@($listRead.Json) | Where-Object {
                $source = [string](Get-OptionalProperty $_ 'source' $Repository)
                ([string](Get-OptionalProperty $_ 'source_type' 'Repository')) -eq 'Repository' -and
                ($source -ieq $Repository -or $source -ieq $repoShortName)
            })
        $existenceKnown = $true
    }
    elseif ($Apply) {
        Write-Host "apply-rulesets: could not list existing rulesets for $Repository (gh api exited $($listRead.ExitCode), HTTP $($listRead.HttpStatus))."
        Write-Host 'The authenticated identity likely lacks admin access to the repository (rulesets'
        Write-Host 'require the admin:repo scope / "Administration" permission). Nothing was changed.'
        exit 2
    }
    else {
        Write-Warning "Could not list existing rulesets (gh api exited $($listRead.ExitCode), HTTP $($listRead.HttpStatus)); dry run assumes POST (create)."
    }
}
else {
    Write-Warning 'gh CLI or a usable wire credential unavailable; dry run cannot check for existing rulesets and assumes POST (create).'
}

$failures = 0
$inSyncCount = 0
foreach ($file in $rulesetFiles) {
    $doc = $null
    try {
        $doc = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
    catch {
        Write-Error -ErrorAction Continue "Invalid JSON in $($file.FullName): $($_.Exception.Message)"
        $failures++
        continue
    }

    $nameProp = $doc.PSObject.Properties['name']
    if (-not $nameProp -or [string]::IsNullOrWhiteSpace([string]$nameProp.Value)) {
        Write-Error -ErrorAction Continue "Ruleset file $($file.Name) has no top-level 'name' key - required to match existing rulesets."
        $failures++
        continue
    }
    $rulesetName = [string]$nameProp.Value

    $match = $existing | Where-Object { ([string](Get-OptionalProperty $_ 'name' '')) -eq $rulesetName } | Select-Object -First 1
    if ($match) {
        $method = 'PUT'
        $endpoint = "repos/$Repository/rulesets/$($match.id)"
        # Read the ruleset back and compare: only the per-id GET carries rules and
        # conditions, and only an equal shape may skip the PUT. An unreadable
        # detail falls back to the PUT, which is idempotent.
        $detail = Invoke-GhApi -GhArgs @($endpoint)
        if ($detail.ExitCode -eq 0 -and $null -ne $detail.Json) {
            $liveShape = Get-RulesetShape $detail.Json
            $wantShape = Get-RulesetShape $doc
            $drift = @($wantShape.Keys | Where-Object { $liveShape[$_] -cne $wantShape[$_] })
            if ($drift.Count -eq 0) {
                Write-Host "[$mode] ruleset '$rulesetName' (id $($match.id)) in sync with $($file.Name) - no call"
                $inSyncCount++
                continue
            }
            $reason = "ruleset '$rulesetName' already exists (id $($match.id)) and differs in $($drift -join ', ') -> update in place"
        }
        else {
            $reason = "ruleset '$rulesetName' already exists (id $($match.id)) but could not be read back (gh exited $($detail.ExitCode), HTTP $($detail.HttpStatus)) -> update in place"
        }
    }
    else {
        $method = 'POST'
        $endpoint = "repos/$Repository/rulesets"
        $reason = if ($existenceKnown) {
            "no existing ruleset named '$rulesetName' -> create"
        }
        else {
            "existing rulesets unknown -> showing create; a real run re-checks and switches to PUT if '$rulesetName' exists"
        }
    }

    $call = "$script:GhApiReplay --method $method $endpoint --input `"$($file.FullName)`""
    if ($Apply) {
        Write-Host "[apply] $reason"
        Write-Host "[apply] $call"
        $run = Invoke-GhApi -GhArgs @('--method', $method, $endpoint, '--input', $file.FullName) -Mutating
        if ($run.ExitCode -ne 0) {
            Write-Error -ErrorAction Continue "gh api exited $($run.ExitCode) (HTTP $($run.HttpStatus)) for $($file.Name)"
            $failures++
        }
        else {
            Write-Host "[apply] OK: $($file.Name) ($method)"
        }
    }
    else {
        Write-Host "[dry-run] $reason"
        Write-Host "[dry-run] $call"
    }
}

if ($failures -gt 0) {
    Write-Host "apply-rulesets: $failures ruleset(s) failed."
    exit 1
}
if (-not $Apply) {
    Write-Host "Dry run complete - $inSyncCount in sync, $($rulesetFiles.Count - $inSyncCount) call(s) shown; nothing was changed. Re-run with -Apply to execute the calls above."
}
exit 0
