#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
Applies the repo's checked-in GitHub SETTINGS truth to the live repository —
Pages source, auto-merge, wiki, branch hygiene, and the automerge label — as an
idempotent GET-diff-then-apply pass. Dry-run by default; -Apply executes.

.DESCRIPTION
The settings sibling of scripts/github/apply-rulesets.ps1: that script owns the
data-driven branch RULESETS (.github/rulesets/*.json, PUT-by-name); this one owns
the scalar repository settings that the repo's automation assumes but that
otherwise need manual Settings clicks. Every item follows the same shape:

  GET the live value -> in sync? report a no-op : print the EXACT `gh api`
  command, then (only under -Apply) execute it.

The command is printed BEFORE execution on purpose: if the process dies mid-item
(network, environment policy), the operator still holds the replay line. A failed
item never aborts the pass — the remaining items still run, and the script exits
1 with a consolidated replay list of everything that did not land.

Items:
  pages                  Pages enabled with build_type=workflow (the source
                         .github/workflows/pages-dashboard.yml deploys through).
                         Only GitHub's own `"status":"404"` reply plans the POST;
                         any other failed read (a proxy 403, a 5xx, no reply) is
                         reported as `unknown (HTTP n / reason)`: no mutation is
                         planned, the row is a FAILED item under -Apply and
                         informational in a dry run (a blind POST would 409
                         against an existing site).
  auto-merge             allow_auto_merge=true (the auto-merge.yml arming contract).
  wiki                   has_wiki=true. Residual owner truth reported every run:
                         the wiki GIT repository only materializes after the first
                         page is created once in the UI — until that one click,
                         wiki-generator.yml green-skips by design.
  delete-branch-on-merge delete_branch_on_merge=true (train hygiene: merged PR
                         heads clean themselves up).
  label:automerge        the `automerge` label exists (arming label for
                         auto-merge.yml; see CONNECTIONS_SETUP.md). Its name,
                         color and description are read from
                         config/github/labels.json, the manifest that
                         apply-labels.ps1 reconciles, so the two scripts share one
                         source of truth; the built-in literal is only the
                         fallback when that entry is absent. Color/description
                         drift on an existing label is apply-labels.ps1's job.
                         Same 404-only rule as pages for the existence read.
  boards                 REPORT-ONLY: Projects v2 mutations need a classic PAT
                         with the `project` scope, which neither Actions tokens
                         nor injected transports carry — the exact owner commands
                         are printed, never run here.

.NOTES
    Exit codes: 0 = success (or clean dry run); 1 = one or more items failed to
    apply (replay list printed); 2 = gh CLI or a usable wire credential
    unavailable in -Apply mode.
    Auth precondition mirrors apply-rulesets.ps1 (kept in copy-sync by the
    cross-reference comments there and here — GitHubIntegration.psm1 is legacy
    simulation code and deliberately NOT a shared home): the probe is
    `gh api repos/{repo}`'s exit code plus one boolean permission field.
    `gh auth status` is never consulted — it can lie both ways; the REST wire is
    the ground truth (scripts/verify/rest-connect.ps1 doctrine).
    Secrets: no token value is ever read, stored, or printed.
    Wire: every `gh api` call carries `X-GitHub-Api-Version: 2022-11-28` (gh
    2.63.2 sends none by itself); a 429, or a 403 naming the rate/secondary
    limit, is retried once after Retry-After (60 s when absent); mutations are
    paced >= 1 s apart.

.EXAMPLE
    pwsh scripts/github/apply-repo-settings.ps1
    # dry run: shows the live-vs-desired diff and every command it would run

.EXAMPLE
    pwsh scripts/github/apply-repo-settings.ps1 -Apply
    # applies; requires a wire credential with admin on the repository
#>
[CmdletBinding()]
param(
    [switch]$Apply,

    [string]$Repository = 'Yolkster64/helios-platform'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = if ($Apply) { 'apply' } else { 'dry-run' }
Write-Host "apply-repo-settings: mode=$mode repository=$Repository"

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern).
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# POSIX-shell quoting for the printed replay line (the label description carries
# spaces, parentheses and a semicolon).
function ConvertTo-ShellArg {
    param([string]$Value)
    if ($Value -match '^[A-Za-z0-9_./:=@%-]+$') { return $Value }
    return "'" + ($Value -replace "'", "'\''") + "'"
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

# --- Wire-truth precondition (kept in sync with apply-rulesets.ps1 — see its
# --- .NOTES): gh present, and under -Apply a wire credential that reads the repo
# --- and holds admin. Capture-then-$LASTEXITCODE; output is one boolean field.
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
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
    Write-Host 'apply-repo-settings: FAILED PRECONDITION - the GitHub CLI (gh) is not on PATH.'
    Write-Host 'Install it (https://cli.github.com/); re-run without -Apply for a dry run.'
    exit 2
}
if ($Apply -and -not $wireOk) {
    Write-Host "apply-repo-settings: FAILED PRECONDITION - the wire probe could not read repos/$Repository."
    Write-Host 'No usable GitHub credential answered on the REST wire. Authenticate first:'
    Write-Host '"gh auth login", or scripts/bootstrap/connect-github.sh --from-env (persists a'
    Write-Host 'REST-valid GH_TOKEN non-interactively). Nothing was changed.'
    exit 2
}
if ($Apply -and -not $wireAdmin) {
    Write-Host "apply-repo-settings: FAILED PRECONDITION - the wire credential cannot administer $Repository."
    Write-Host 'Repository settings need admin access (admin:repo scope for a classic PAT, or'
    Write-Host '"Administration: write" for a fine-grained PAT). Nothing was changed.'
    exit 2
}

$failures = [System.Collections.Generic.List[string]]::new()
$inSync = 0
$unknown = 0

# Existence read with a three-way verdict. Only GitHub's own `"status":"404"` body
# means "absent" (plan the create); a 2xx with a body is "present"; everything
# else (a proxy 403 without a status field, a 5xx, no reply) is "unknown" and is
# never turned into a mutation, because a blind POST would 409 against a resource
# that exists. Reason is GitHub's message, or the exit code when there is none.
function Get-ReadVerdict {
    param([Parameter(Mandatory)][string]$Endpoint)
    $read = Invoke-GhApi -GhArgs @($Endpoint)
    $verdict = if ($read.ExitCode -eq 0 -and $null -ne $read.Json) { 'present' }
    elseif (([string](Get-OptionalProperty $read.Json 'status' '')) -eq '404') { 'absent' }
    else { 'unknown' }
    $reason = [string](Get-OptionalProperty $read.Json 'message' '')
    if (-not $reason) { $reason = "gh exited $($read.ExitCode)" }
    return [pscustomobject]@{ Verdict = $verdict; Json = $read.Json; HttpStatus = $read.HttpStatus; Reason = $reason }
}

# An unknown read: reported with the HTTP status and reason, no command planned.
# Under -Apply it is a failed item (the pass cannot prove the state it was asked
# to reconcile, and the replay line is the read to make succeed first); in a dry
# run it is informational, so a proxy that blocks one GET does not turn the plan red.
function Add-UnknownItem {
    param(
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)]$Read,
        [Parameter(Mandatory)][string]$Endpoint
    )
    Write-Host "  [$Item] unknown (HTTP $($Read.HttpStatus) / $($Read.Reason)) - state unreadable, no command planned"
    if ($Apply) {
        $failures.Add("[$Item] $script:GhApiReplay $Endpoint  (read failed: HTTP $($Read.HttpStatus) $($Read.Reason); make this read succeed, then re-run)")
    }
    else {
        $script:unknown++
        Write-Host "  [$Item] (informational in a dry run; a FAILED item under -Apply)"
    }
}

# One mutation: prints the exact command FIRST, executes only under -Apply, and
# on failure records the replay line and keeps going (classifier/permission
# honesty — a denied item must not hide the remaining diffs). $GhArgs is
# everything after `gh api`; the wrapper adds the version header.
function Invoke-RepoMutation {
    param(
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][string[]]$GhArgs
    )
    $rendered = $script:GhApiReplay + ' ' + (($GhArgs | ForEach-Object { ConvertTo-ShellArg $_ }) -join ' ')
    if (-not $Apply) {
        Write-Host "  [$Item] out of sync - would run: $rendered"
        return
    }
    Write-Host "  [$Item] applying: $rendered"
    $run = Invoke-GhApi -GhArgs $GhArgs -Mutating
    if ($run.ExitCode -eq 0) {
        Write-Host "  [$Item] applied."
    }
    else {
        Write-Host "  [$Item] FAILED (gh exited $($run.ExitCode), HTTP $($run.HttpStatus)) - replay: $rendered"
        $failures.Add("[$Item] $rendered")
    }
}

# --- pages ------------------------------------------------------------------------
Write-Host ''
Write-Host '-- pages (deploy source for .github/workflows/pages-dashboard.yml) --'
$pagesEndpoint = "repos/$Repository/pages"
$pagesRead = Get-ReadVerdict $pagesEndpoint
switch ($pagesRead.Verdict) {
    'absent' {
        Invoke-RepoMutation -Item 'pages' -GhArgs @('--method', 'POST', $pagesEndpoint, '-f', 'build_type=workflow')
    }
    'unknown' {
        Add-UnknownItem -Item 'pages' -Read $pagesRead -Endpoint $pagesEndpoint
    }
    default {
        if ([string](Get-OptionalProperty $pagesRead.Json 'build_type' '') -ne 'workflow') {
            Invoke-RepoMutation -Item 'pages' -GhArgs @('--method', 'PUT', $pagesEndpoint, '-f', 'build_type=workflow')
        }
        else {
            Write-Host '  [pages] in sync (enabled, build_type=workflow)'
            $inSync++
        }
    }
}

# --- scalar repository flags (one GET serves all three) ---------------------------
Write-Host ''
Write-Host '-- repository flags --'
$repoInfo = (Invoke-GhApi -GhArgs @("repos/$Repository")).Json
foreach ($flag in @(
        [pscustomobject]@{ Item = 'auto-merge'; Field = 'allow_auto_merge'; Why = 'auto-merge.yml arming contract' }
        [pscustomobject]@{ Item = 'wiki'; Field = 'has_wiki'; Why = 'wiki-generator.yml publish target' }
        [pscustomobject]@{ Item = 'delete-branch-on-merge'; Field = 'delete_branch_on_merge'; Why = 'merged PR heads clean themselves up' }
    )) {
    $live = Get-OptionalProperty $repoInfo $flag.Field $null
    if ($live -eq $true) {
        Write-Host "  [$($flag.Item)] in sync ($($flag.Field)=true)"
        $inSync++
    }
    else {
        $liveText = if ($null -eq $live) { 'unknown' } else { [string]$live }
        Write-Host "  [$($flag.Item)] live=$liveText desired=true ($($flag.Why))"
        Invoke-RepoMutation -Item $flag.Item -GhArgs @('--method', 'PATCH', "repos/$Repository", '-F', "$($flag.Field)=true")
    }
}
# Residual owner truth, every run (never silently implied): enabling has_wiki
# does not create the wiki's git repository — that materializes only after the
# first page is created once in the UI; wiki-generator.yml green-skips until then.
Write-Host '  [wiki] note: the wiki git repo appears only after the FIRST page is created in the UI once.'

# --- automerge label --------------------------------------------------------------
Write-Host ''
Write-Host '-- automerge label (arming label for auto-merge.yml) --'
# Name, color and description come from config/github/labels.json, the manifest
# apply-labels.ps1 reconciles, so the two scripts can never disagree about the
# label; the literal is only the fallback when the manifest or its entry is absent.
$automerge = [ordered]@{ name = 'automerge'; color = '0e8a16'; description = 'Arm auto-merge for this PR (see auto-merge.yml)' }
$automergeSource = 'built-in fallback (no automerge entry in config/github/labels.json)'
$labelsManifest = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config' 'github' 'labels.json'
if (Test-Path -LiteralPath $labelsManifest -PathType Leaf) {
    try {
        $labelsDoc = Get-Content -LiteralPath $labelsManifest -Raw | ConvertFrom-Json -NoEnumerate
        $labelEntries = if ($labelsDoc -is [System.Array]) { @($labelsDoc) } else { @(Get-OptionalProperty $labelsDoc 'labels' @()) }
        $manifestEntry = $labelEntries | Where-Object { ([string](Get-OptionalProperty $_ 'name' '')) -ieq 'automerge' } | Select-Object -First 1
        if ($null -ne $manifestEntry) {
            $automerge.name = ([string](Get-OptionalProperty $manifestEntry 'name' $automerge.name)).Trim()
            $automerge.color = ([string](Get-OptionalProperty $manifestEntry 'color' $automerge.color)).Trim().TrimStart('#').ToLowerInvariant()
            $automerge.description = [string](Get-OptionalProperty $manifestEntry 'description' $automerge.description)
            $automergeSource = 'config/github/labels.json'
        }
    }
    catch {
        $automergeSource = "built-in fallback (config/github/labels.json unreadable: $($_.Exception.Message))"
    }
}
Write-Host "  [label:automerge] definition source: $automergeSource"
$labelEndpoint = "repos/$Repository/labels/$([uri]::EscapeDataString($automerge.name))"
$labelRead = Get-ReadVerdict $labelEndpoint
switch ($labelRead.Verdict) {
    'absent' {
        Invoke-RepoMutation -Item 'label:automerge' -GhArgs @(
            '--method', 'POST', "repos/$Repository/labels",
            '-f', "name=$($automerge.name)", '-f', "color=$($automerge.color)",
            '-f', "description=$($automerge.description)")
    }
    'unknown' {
        Add-UnknownItem -Item 'label:automerge' -Read $labelRead -Endpoint $labelEndpoint
    }
    default {
        Write-Host '  [label:automerge] in sync (exists; color/description drift is apply-labels.ps1''s job)'
        $inSync++
    }
}

# --- boards (report-only) ---------------------------------------------------------
Write-Host ''
Write-Host '-- boards (REPORT-ONLY: Projects v2 needs a classic PAT with the project scope) --'
Write-Host '  Owner commands, from a workstation holding such a PAT:'
Write-Host '    pwsh scripts/board-setup/validate-board.ps1                       # read-only check'
Write-Host '    pwsh scripts/board-setup/setup-custom-fields.ps1 -GitHubToken <PAT>'
Write-Host '    pwsh scripts/board-setup/add-epics-to-board.ps1 -GitHubToken <PAT>'

# --- rollup -----------------------------------------------------------------------
Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "apply-repo-settings: $($failures.Count) item(s) FAILED to apply - replay list:"
    foreach ($f in $failures) { Write-Host "  $f" }
    Write-Host 'Each line is directly re-runnable by an identity with repo admin.'
    exit 1
}
if ($Apply) {
    Write-Host "apply-repo-settings: complete - $inSync item(s) were already in sync; the rest were applied."
    Write-Host 'Idempotence check: re-run this script and expect every row to read "in sync".'
}
else {
    Write-Host "apply-repo-settings: dry run complete - $inSync item(s) in sync; $unknown unknown (state unreadable, no command planned); commands above show the rest. Nothing was changed."
}
exit 0
