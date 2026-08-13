#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Applies the repository rulesets in .github/rulesets/ to GitHub via `gh api`.

.DESCRIPTION
    Dry-run by default: prints the exact `gh api` calls it would make and changes
    nothing. Re-run with -Apply to execute them. Idempotent: it GETs the repo's
    existing rulesets first and matches by ruleset NAME — a ruleset that already
    exists is updated in place (PUT /repos/{owner}/{repo}/rulesets/{id}), otherwise
    it is created (POST /repos/{owner}/{repo}/rulesets). Re-running never duplicates.

    The ruleset JSON files are strict JSON (the API shape allows no comments), so
    this header is the runbook for what main.json pins and why.

    Required status checks in main.json — job-LEVEL names, each verified against the
    workflow source (a job's check context is its `name:` field, or the job id when
    unnamed):

      Context                        Source                                 Job
      -----------------------------  -------------------------------------  --------------
      Build solution & run tests     .github/workflows/dotnet-build.yml:44   build-and-test
      bicep-validate                 .github/workflows/infra-validate.yml:14 (job id, unnamed)
      arm-freshness                  .github/workflows/infra-validate.yml:33 (job id, unnamed)
      terraform-validate             .github/workflows/infra-validate.yml:83 (job id, unnamed)
      Preflight Validation           .github/workflows/ci-validation.yml:15  preflight
      PowerShell Syntax Validation   .github/workflows/ci-validation.yml:37  syntax-check
      File Structure Validation      .github/workflows/ci-validation.yml:197 file-integrity
      Quality Check Summary          .github/workflows/quality.yml:100       quality-summary

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

    Known behavior to expect: dotnet-build.yml and infra-validate.yml are
    path-filtered, so a PR outside those paths reports no run for their checks and
    GitHub shows the check as "Expected". Merges of such PRs need the owner to use
    admin override, or a future skipped-but-reports lane; tracked in
    docs/architecture/ROADMAP_MULTI_LLM.md.

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
    failure; 2 = gh CLI or authentication unavailable in -Apply mode.
    Secrets: this script never reads, stores, or prints token values — the auth
    probe uses `gh auth status`'s exit code only and its output is discarded.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$RulesetDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# --- Probe gh + auth. Exit-code-only: gh's own output can reference credentials,
# --- so it is discarded entirely rather than filtered.
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
$authOk = $false
if ($gh) {
    & $gh.Source auth status *> $null
    $authOk = ($LASTEXITCODE -eq 0)
}

if ($Apply -and -not $gh) {
    Write-Host 'apply-rulesets: FAILED PRECONDITION - the GitHub CLI (gh) is not on PATH.'
    Write-Host 'Install it (https://cli.github.com/), then authenticate with an identity that'
    Write-Host "has admin access to $Repository (classic PAT with the admin:repo scope, or an"
    Write-Host 'owner `gh auth login`). Re-run without -Apply for a dry run that needs neither.'
    exit 2
}
if ($Apply -and -not $authOk) {
    Write-Host 'apply-rulesets: FAILED PRECONDITION - "gh auth status" reports no usable login.'
    Write-Host 'Authenticate first: run "gh auth login", or set the GH_TOKEN environment variable'
    Write-Host '(the NAME of the variable to set - never put the value in a file or argument).'
    Write-Host "The identity must have admin access to $Repository (admin:repo scope for a"
    Write-Host 'classic PAT; "Administration: write" for a fine-grained PAT).'
    exit 2
}

# --- Fetch existing rulesets so re-runs update by name instead of duplicating.
$existing = @()
$existenceKnown = $false
if ($gh -and $authOk) {
    $raw = & $gh.Source api "repos/$Repository/rulesets?per_page=100" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $joined = ($raw | Out-String).Trim()
        if ($joined) {
            $existing = @($joined | ConvertFrom-Json)
        }
        $existenceKnown = $true
    }
    elseif ($Apply) {
        Write-Host "apply-rulesets: could not list existing rulesets for $Repository (gh api exited $LASTEXITCODE)."
        Write-Host 'The authenticated identity likely lacks admin access to the repository (rulesets'
        Write-Host 'require the admin:repo scope / "Administration" permission). Nothing was changed.'
        exit 2
    }
    else {
        Write-Warning "Could not list existing rulesets (gh api exited $LASTEXITCODE); dry run assumes POST (create)."
    }
}
else {
    Write-Warning 'gh CLI or authentication unavailable; dry run cannot check for existing rulesets and assumes POST (create).'
}

$failures = 0
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

    $match = $existing | Where-Object { $_.name -eq $rulesetName } | Select-Object -First 1
    if ($match) {
        $method = 'PUT'
        $endpoint = "repos/$Repository/rulesets/$($match.id)"
        $reason = "ruleset '$rulesetName' already exists (id $($match.id)) -> update in place"
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

    $call = "gh api --method $method $endpoint --input `"$($file.FullName)`""
    if ($Apply) {
        Write-Host "[apply] $reason"
        Write-Host "[apply] $call"
        & $gh.Source api --method $method $endpoint --input $file.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Error -ErrorAction Continue "gh api exited $LASTEXITCODE for $($file.Name)"
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
    Write-Host 'Dry run complete - nothing was changed. Re-run with -Apply to execute the calls above.'
}
exit 0
