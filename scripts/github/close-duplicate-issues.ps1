#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Closes the GitHub issues that Linear's own GitHub integration re-imported from
    this repo's Linear mirrors (the "[GH-N] ..." twins of #54-#92) as duplicates of
    their originals: label `duplicate`, one explanatory comment, then
    state=closed / state_reason=duplicate. Dry-run by default; -Apply executes.

.DESCRIPTION
    The issue-hygiene sibling of scripts/github/apply-rulesets.ps1,
    apply-repo-settings.ps1 and apply-labels.ps1, kept in their shape (same wire
    precondition, print-before-execute, exit 0/1/2, -Json); unlike them it is
    NOT driven by .github/workflows/governance-apply.yml (its run_item list is
    rulesets/settings/labels/milestones), it runs from an owner login or the
    HELIOS_ADMIN_TOKEN PAT:

      GET every issue in the range -> classify it -> print the row (number,
      action, original, title) -> under -Apply run the mutations for each
      candidate, printing the EXACT `gh api` command BEFORE each one.

    A number is a LOOP DUPLICATE only when all four hold, so nothing hand-written
    can ever be swept up by accident:
      1. the issue is open;
      2. its title starts with the loop's marker, derived from the Linear
         connector's `linear.titlePrefix` in config/connectors.json (today
         `[GH-{number}] `, the value .github/workflows/linear-sync.yml reads too,
         bounced back by Linear's GitHub integration): the literal prefix is
         regex-escaped and `{number}` becomes the capture group. Only when the
         file, the key or the `{number}` slot is absent does the built-in
         `^\[GH-(\d+)\]` apply, and the report's "loop marker" line says so;
      3. its body carries the literal `GitHub (system of record)` line that the
         Linear-side importer writes (a human copying a title never writes it);
      4. the original issue <n> named in the title exists in this repository
         and is itself open (a closed original means the twin is no longer a
         plain duplicate and deserves a human look, so it is skipped).
    Belt on top of those: when the body's system-of-record link names a
    different issue number than the title, the row is skipped as a mismatch
    rather than closed against the wrong original.

    Per candidate, in order (each command printed first; a failure records the
    replay line and the pass continues with the next command and next issue):
      a. POST /issues/{n}/labels  labels[]=duplicate  (skipped if already present)
      b. POST /issues/{n}/comments with ONE comment: "Duplicate of #<orig>, ..."
         plus the mandatory Claude Code footer (skipped if that comment already
         exists — every comment page is read, per_page=100&page=N until a short
         page, so a partial re-run never double-comments however long the thread)
      c. PATCH /issues/{n}  state=closed state_reason=duplicate
         duplicate_issue_id=<original's database id> (the `.id` of the original
         fetched in rule 4, NOT its number, so GitHub links the canonical issue)

    OWNER STEP FIRST (why this script exists at all): these issues were closed
    once on 2026-08-12 and Linear's GitHub integration for team JOH REOPENED
    them, because that integration mirrors its issues back onto GitHub. Before
    running -Apply the owner must disable Linear's GitHub issue sync for team JOH:
    Linear -> Settings -> Integrations -> GitHub -> team John -> disable issue
    sync for Yolkster64/helios-platform (docs/architecture/CONNECTIONS_SETUP.md,
    "Owner action"). Until that switch is off the issues reopen again. This
    repo's own .github/workflows/linear-sync.yml skips `[GH-` titles on every
    event (and the `duplicate` label on `opened`/`labeled`, the two events that
    can create a mirror), so the closing itself never echoes back into Linear.

    Credential: labeling, commenting and closing are issue WRITES. The wire
    precondition is `gh api repos/{repo}` exit 0 plus `.permissions.push` = true
    (the REST-visible proof that the identity holds write on the repository; the
    rest-connect.ps1 doctrine that the wire is the ground truth and `gh auth
    status` is never consulted). Repository admin is NOT required. The proxy-
    backed token measured in the authoring container reports push=false, so from
    there only the dry run runs; -Apply is for an owner login or a PAT with
    "Issues: write". Note that the Actions GITHUB_TOKEN can also report push=false
    while holding `issues: write`; for that path run from a workstation or with
    the owner-stored HELIOS_ADMIN_TOKEN.

.PARAMETER Repository
    Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER Apply
    Execute the `gh api` mutations. Without it the script only classifies and
    prints them (dry run).

.PARAMETER Json
    Emit exactly one JSON object on stdout (mode, precondition, one item per
    issue number with its action/original/commands, counts, replay list, exit
    code) and nothing else; every human line is suppressed. The exit-code
    contract is unchanged.

.PARAMETER From
    First issue number of the sweep range (inclusive). Defaults to 54, the first
    loop re-import.

.PARAMETER To
    Last issue number of the sweep range (inclusive). Defaults to 92, the last
    loop re-import still open (#93 was already closed and stayed closed).

.PARAMETER SessionUrl
    Optional Claude Code session link (https://claude.ai/code/session_<id>)
    appended below the comment's attribution footer, the way this repository's
    PR bodies carry it. Not baked in because a session link inside a durable
    script would go stale; the operator running -Apply passes the live one.
    Any value not of that exact shape is rejected (exit 1) so no free text can
    reach the public comments. The comment dedupe keys on the lead sentence,
    so passing or omitting it never causes a second comment.

.PARAMETER ConnectorsPath
    Path to the connector config that owns the loop marker (`linear.titlePrefix`).
    Defaults to config/connectors.json relative to this checkout. Point it at a
    scratch copy to prove that a different prefix changes the classification.

.EXAMPLE
    pwsh scripts/github/close-duplicate-issues.ps1
    # dry run: prints the classification table and every command; changes nothing

.EXAMPLE
    pwsh scripts/github/close-duplicate-issues.ps1 -Apply
    # closes the candidates; needs a wire credential with write on the repository
    # AND the Linear-side issue sync for team JOH already switched off

.EXAMPLE
    pwsh scripts/github/close-duplicate-issues.ps1 -Json
    # one JSON object for a job summary or a ledger

.NOTES
    Exit codes: 0 = success (or clean dry run); 1 = invalid range/repository, or
    one or more mutations failed to apply (replay list printed); 2 = gh CLI or a
    usable wire credential unavailable (either mode: the sweep has no offline
    input, so without reads there is nothing to plan), or under -Apply the
    credential lacks write on the repository.
    Secrets: no token value is ever read, stored, or printed; gh reads its own
    credential (GH_TOKEN by NAME, or the keyring) and this script only sees exit
    codes and issue JSON. Issue bodies are inspected in memory and never echoed.
    Wire: every `gh api` call carries `X-GitHub-Api-Version: 2022-11-28` (gh
    2.63.2 sends none by itself); a 429, or a 403 naming the rate/secondary
    limit, is retried once after Retry-After (60 s when absent); mutations are
    paced >= 1 s apart (up to 3 per candidate, ~108 for the default range).
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',

    [switch]$Apply,

    [switch]$Json,

    [int]$From = 54,

    [int]$To = 92,

    [string]$SessionUrl = '',

    [string]$ConnectorsPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = if ($Apply) { 'apply' } else { 'dry-run' }

# The strings the classifier keys on. The body marker is a constant: it is the
# Linear-side importer's own footer line, which this repo does not control. The
# title marker is NOT: it is this repo's own linear-sync titlePrefix, owned by
# config/connectors.json (`linear.titlePrefix`), and is derived from that file
# below (after the helpers it needs are defined); this literal is only the
# fallback when the file or the key is absent.
$builtInTitlePattern = '^\[GH-(\d+)\]'
$titlePattern = $builtInTitlePattern
$titlePatternSource = 'built-in fallback'
$bodyMarker = 'GitHub (system of record)'
$duplicateLabel = 'duplicate'
# The comment footer is the attribution line this repository's PR bodies carry
# (the train's "footer exactly as the session prescribes" rule), optionally
# followed by the session link (-SessionUrl). The robot glyph is built from its
# code point so this file stays pure ASCII and no editor or checkout re-encodes it.
$footer = [char]::ConvertFromUtf32(0x1F916) + ' Generated with [Claude Code](https://claude.com/claude-code)'

# One result model feeds both the console lines and -Json, so the two views can
# never disagree about what was planned or what landed.
$result = [ordered]@{
    script       = 'close-duplicate-issues'
    mode         = $mode
    repository   = $Repository
    range        = [ordered]@{ from = $From; to = $To }
    ownerStep    = 'Disable Linear GitHub issue sync for team JOH first (docs/architecture/CONNECTIONS_SETUP.md), or the closed issues reopen.'
    loopMarker   = [ordered]@{ pattern = ''; source = '' }
    precondition = [ordered]@{ ghFound = $false; wireReadable = $false; push = $false }
    items        = [System.Collections.Generic.List[object]]::new()
    replay       = [System.Collections.Generic.List[string]]::new()
    notes        = [System.Collections.Generic.List[string]]::new()
    counts       = [ordered]@{ candidates = 0; closed = 0; skipped = 0; unreadable = 0; failed = 0 }
    exitCode     = 0
}

# Under -Json stdout must carry exactly one object, and pwsh routes Write-Host AND
# Write-Warning to stdout, so every human line goes through this gate instead.
function Write-Line {
    param([string]$Text)
    if (-not $Json) { Write-Host $Text }
}

function Add-Note {
    param([string]$Text)
    $result.notes.Add($Text)
    Write-Line "note: $Text"
}

# Single exit path: records the code in the result, emits the one JSON object when
# asked, and exits. Called from the top level only, so `exit` ends the script.
function Exit-With {
    param([int]$Code)
    $result.exitCode = $Code
    if ($Json) { $result | ConvertTo-Json -Depth 6 }
    exit $Code
}

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern): a
# missing property must read as the default, not throw.
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# Renders one argv element the way an operator would retype it in a POSIX shell,
# so the printed replay line is copy-paste safe even for the multi-line comment
# body (single quotes keep newlines literal in bash and pwsh alike).
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

# --- Loop marker from config/connectors.json (`linear.titlePrefix`), the same key
# --- linear-sync.yml derives its marker from, so one file owns the shape. The
# --- prefix is a literal: regex-escaped, `{number}` -> the capture group, trailing
# --- whitespace dropped so "[GH-54]" matches with or without the space after it.
if (-not $ConnectorsPath) {
    $ConnectorsPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config' 'connectors.json'
}
if (Test-Path -LiteralPath $ConnectorsPath -PathType Leaf) {
    try {
        $connectorsDoc = Get-Content -LiteralPath $ConnectorsPath -Raw | ConvertFrom-Json
        $prefix = [string](Get-OptionalProperty (Get-OptionalProperty $connectorsDoc 'linear' $null) 'titlePrefix' '')
        if ($prefix -and $prefix.Contains('{number}')) {
            $parts = $prefix.TrimEnd() -split '\{number\}', 2
            $tail = if ($parts.Count -gt 1) { [regex]::Escape($parts[1]) } else { '' }
            $titlePattern = '^' + [regex]::Escape($parts[0]) + '(\d+)' + $tail
            $titlePatternSource = "$ConnectorsPath linear.titlePrefix '$prefix'"
        }
        else {
            $titlePatternSource = "built-in fallback (linear.titlePrefix absent or without {number} in $ConnectorsPath)"
        }
    }
    catch {
        $titlePatternSource = "built-in fallback ($ConnectorsPath unreadable: $($_.Exception.Message))"
    }
}
else {
    $titlePatternSource = "built-in fallback ($ConnectorsPath not found)"
}
$result.loopMarker.pattern = $titlePattern
$result.loopMarker.source = $titlePatternSource

Write-Line "close-duplicate-issues: mode=$mode repository=$Repository range=#$From-#$To"
Write-Line "owner step: $($result.ownerStep)"
Write-Line "loop marker: $titlePattern (from $titlePatternSource)"

# --- Input validation before any wire call: a bad range or repo slug is an
# --- operator typo (exit 1), never a credential problem (exit 2). ------------------
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
    Write-Line "close-duplicate-issues: invalid -Repository '$Repository' (expected owner/name)."
    Add-Note 'invalid repository slug'
    Exit-With 1
}
if ($From -lt 1 -or $To -lt $From) {
    Write-Line "close-duplicate-issues: invalid range #$From-#$To (need 1 <= From <= To)."
    Add-Note 'invalid range'
    Exit-With 1
}
# The session link lands verbatim in public comments, so only the one shape the
# harness issues is accepted; anything else is an operator typo, not a credential
# problem (exit 1).
if ($SessionUrl -and $SessionUrl -notmatch '^https://claude\.ai/code/session_[A-Za-z0-9]+$') {
    Write-Line "close-duplicate-issues: invalid -SessionUrl (expected https://claude.ai/code/session_<id>)."
    Add-Note 'invalid session url'
    Exit-With 1
}
if ($SessionUrl) { $footer = $footer + "`n`n" + $SessionUrl }

# --- Wire-truth precondition (same probe family as apply-rulesets.ps1 / apply-repo-
# --- settings.ps1, but the field is .permissions.push: issue writes need write on
# --- the repository, not admin). Capture-then-$LASTEXITCODE; the captured output is
# --- one boolean permission field, never credential material.
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$wireOk = $false
$wirePush = $false
if ($gh) {
    $result.precondition.ghFound = $true
    $probe = Invoke-GhApi -GhArgs @("repos/$Repository", '--jq', '.permissions.push')
    if ($probe.ExitCode -eq 0) {
        $wireOk = $true
        $wirePush = ($probe.Text -eq 'true')
    }
    $result.precondition.wireReadable = $wireOk
    $result.precondition.push = $wirePush
}
if (-not $gh) {
    Write-Line 'close-duplicate-issues: FAILED PRECONDITION - the GitHub CLI (gh) is not on PATH.'
    Write-Line 'Install it (https://cli.github.com/) and authenticate; even the dry run needs to read issues.'
    Add-Note 'gh CLI not on PATH'
    Exit-With 2
}
if (-not $wireOk) {
    Write-Line "close-duplicate-issues: FAILED PRECONDITION - the wire probe could not read repos/$Repository."
    Write-Line 'No usable GitHub credential answered on the REST wire ("gh auth status" is deliberately'
    Write-Line 'not consulted; the REST probe is the ground truth, scripts/verify/rest-connect.ps1'
    Write-Line 'doctrine). Authenticate first: "gh auth login", or scripts/bootstrap/connect-github.sh'
    Write-Line '--from-env, or set the GH_TOKEN environment variable (the NAME of the variable to set,'
    Write-Line 'never put the value in a file or argument). Nothing was changed.'
    Add-Note "wire probe could not read repos/$Repository"
    Exit-With 2
}
if ($Apply -and -not $wirePush) {
    Write-Line "close-duplicate-issues: FAILED PRECONDITION - the wire credential holds no write on $Repository."
    Write-Line 'The probe read the repository but .permissions.push is not true. Closing, labeling and'
    Write-Line 'commenting are issue writes: use an owner "gh auth login" or a fine-grained PAT with'
    Write-Line '"Issues: write" (the proxy-backed token measured here, and an Actions GITHUB_TOKEN granted'
    Write-Line 'only issues: write, report push=false). Nothing was changed.'
    Add-Note 'credential lacks write on the repository'
    Exit-With 2
}
if (-not $wirePush) {
    Add-Note 'credential reports push=false: this dry run is read-only anyway, but -Apply would be refused from it'
}

# GET helper: $null on any failure (non-2xx, unparsable). Callers decide whether
# "unknown" means unreadable (range member) or missing (original).
function Get-GhApiJson {
    param([Parameter(Mandatory)][string]$Endpoint)
    $read = Invoke-GhApi -GhArgs @($Endpoint)
    if ($read.ExitCode -ne 0) { return $null }
    return $read.Json
}

# Originals are looked up once each: several twins can name the same original,
# and every extra GET is a wire call the proxy has to answer. The database id
# (.id, distinct from .number) is kept because the close PATCH names it as
# duplicate_issue_id.
$originals = @{}
function Get-Original {
    param([int]$Number)
    if ($originals.ContainsKey($Number)) { return $originals[$Number] }
    $doc = Get-GhApiJson "repos/$Repository/issues/$Number"
    $state = if ($null -eq $doc) { 'missing' }
    elseif ($null -ne (Get-OptionalProperty $doc 'pull_request' $null)) { 'pull-request' }
    else { [string](Get-OptionalProperty $doc 'state' 'unknown') }
    $entry = [pscustomobject]@{ State = $state; Id = [string](Get-OptionalProperty $doc 'id' '') }
    $originals[$Number] = $entry
    return $entry
}

# One mutation: prints the exact command FIRST, executes only under -Apply, and
# on failure records the replay line and keeps going (a denied command must not
# hide the remaining candidates). Returns $true when the command is considered
# done (dry run, or applied successfully).
function Invoke-IssueMutation {
    param(
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string[]]$GhArgs,
        # Not Mandatory on purpose: PowerShell rejects an EMPTY collection bound to a
        # mandatory parameter, and the per-issue command list is empty at first call.
        [AllowEmptyCollection()][System.Collections.Generic.List[string]]$Commands
    )
    $rendered = $script:GhApiReplay + ' ' + (($GhArgs | ForEach-Object { ConvertTo-ShellArg $_ }) -join ' ')
    $Commands.Add($rendered)
    if (-not $Apply) {
        Write-Line "    [$Step] would run: $rendered"
        return $true
    }
    Write-Line "    [$Step] applying: $rendered"
    $run = Invoke-GhApi -GhArgs $GhArgs -Mutating
    if ($run.ExitCode -eq 0) {
        Write-Line "    [$Step] applied."
        return $true
    }
    Write-Line "    [$Step] FAILED (gh exited $($run.ExitCode), HTTP $($run.HttpStatus); a 403 here means the credential lacks issue write) - replay: $rendered"
    $result.replay.Add("[#$Number $Step] $rendered")
    return $false
}

Write-Line ''
Write-Line ('  {0,-6} {1,-24} {2,-9} {3}' -f 'issue', 'action', 'original', 'title')
Write-Line ('  {0,-6} {1,-24} {2,-9} {3}' -f '-----', '------', '--------', '-----')

$failedItems = 0
$readable = 0
for ($n = $From; $n -le $To; $n++) {
    $item = [ordered]@{
        number = $n; title = ''; original = $null; action = ''; detail = ''
        labelNeeded = $false; commentNeeded = $false; commands = [System.Collections.Generic.List[string]]::new()
    }

    $doc = Get-GhApiJson "repos/$Repository/issues/$n"
    if ($null -eq $doc) {
        $item.action = 'unreadable'
        $item.detail = 'GET failed (deleted, transferred, or not visible to this credential)'
        $result.counts.unreadable++
        Write-Line ('  {0,-6} {1,-24} {2,-9} {3}' -f "#$n", $item.action, '-', $item.detail)
        $result.items.Add([pscustomobject]$item)
        continue
    }
    $readable++
    $item.title = [string](Get-OptionalProperty $doc 'title' '')
    $state = [string](Get-OptionalProperty $doc 'state' '')
    $body = [string](Get-OptionalProperty $doc 'body' '')
    $labels = @(Get-OptionalProperty $doc 'labels' @() | ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') })

    # Classification, cheapest test first; the first failing rule names the skip
    # reason so the table explains itself without re-reading the issue.
    $skip = $null
    $origNumber = 0
    $original = $null
    if ($null -ne (Get-OptionalProperty $doc 'pull_request' $null)) { $skip = 'skip:pull-request' }
    elseif ($state -ne 'open') { $skip = 'skip:already-closed' }
    elseif ($item.title -notmatch $titlePattern) { $skip = 'skip:not-loop-title' }
    else {
        $origNumber = [int]$Matches[1]
        $item.original = $origNumber
        if ($body -notlike "*$bodyMarker*") { $skip = 'skip:no-record-marker' }
        elseif ($origNumber -eq $n) { $skip = 'skip:self-reference' }
        elseif ($body -match [regex]::Escape($bodyMarker) + '[^\r\n]*?/issues/(\d+)' -and ([int]$Matches[1]) -ne $origNumber) {
            $skip = 'skip:record-mismatch'
            $item.detail = "body names #$($Matches[1]) but the title names #$origNumber"
        }
        else {
            $original = Get-Original -Number $origNumber
            if ($original.State -eq 'missing') { $skip = 'skip:original-missing' }
            elseif ($original.State -eq 'pull-request') { $skip = 'skip:original-is-pr' }
            elseif ($original.State -ne 'open') { $skip = 'skip:original-closed' }
            elseif (-not $original.Id) { $skip = 'skip:original-id-unknown' }
        }
    }
    if ($skip) {
        $item.action = $skip
        $result.counts.skipped++
        $origText = if ($origNumber -gt 0) { "#$origNumber" } else { '-' }
        Write-Line ('  {0,-6} {1,-24} {2,-9} {3}' -f "#$n", $item.action, $origText, $item.title)
        if ($item.detail) { Write-Line "    $($item.detail)" }
        $result.items.Add([pscustomobject]$item)
        continue
    }

    # Candidate. Idempotence belts: the label is added only when absent, the
    # comment only when this script's own comment is not already there, so a
    # partial earlier run (say, close denied after the comment landed) replays
    # cleanly instead of stacking comments.
    $item.action = 'close-as-duplicate'
    $result.counts.candidates++
    $item.labelNeeded = -not ($labels -contains $duplicateLabel)
    $commentLead = "Duplicate of #$origNumber, created by the Linear sync loop (see docs/architecture/CONNECTIONS_SETUP.md, Linear team JOH sync). Closing as duplicate."
    $commentBody = $commentLead + "`n`n---`n" + $footer
    $item.commentNeeded = $true
    # Every comment page is read (per_page=100&page=N until a short page, capped
    # only as a runaway guard): a thread longer than one page must not re-comment.
    # A failed page leaves commentNeeded true, the existing "unknown -> post" rule.
    $page = 1
    while ($true) {
        $commentsRead = Invoke-GhApi -GhArgs @("repos/$Repository/issues/$n/comments?per_page=100&page=$page")
        if ($commentsRead.ExitCode -ne 0) { break }
        $batch = @($commentsRead.Json)
        foreach ($c in $batch) {
            if (([string](Get-OptionalProperty $c 'body' '')).StartsWith($commentLead)) { $item.commentNeeded = $false; break }
        }
        if (-not $item.commentNeeded -or $batch.Count -lt 100 -or $page -ge 20) { break }
        $page++
    }
    $item.detail = 'label ' + $(if ($item.labelNeeded) { 'add' } else { 'present' }) +
        ', comment ' + $(if ($item.commentNeeded) { 'post' } else { 'present' }) + ', then close'
    Write-Line ('  {0,-6} {1,-24} {2,-9} {3}' -f "#$n", $item.action, "#$origNumber", $item.title)
    Write-Line "    $($item.detail)"

    $ok = $true
    if ($item.labelNeeded) {
        $ok = (Invoke-IssueMutation -Number $n -Step 'label' -Commands $item.commands -GhArgs @(
                '--method', 'POST', "repos/$Repository/issues/$n/labels", '-f', "labels[]=$duplicateLabel")) -and $ok
    }
    if ($item.commentNeeded) {
        $ok = (Invoke-IssueMutation -Number $n -Step 'comment' -Commands $item.commands -GhArgs @(
                '--method', 'POST', "repos/$Repository/issues/$n/comments", '-f', "body=$commentBody")) -and $ok
    }
    # -F sends duplicate_issue_id as a number: it is the original's database id
    # (.id), never its number, which is what GitHub links as the canonical issue.
    $ok = (Invoke-IssueMutation -Number $n -Step 'close' -Commands $item.commands -GhArgs @(
            '--method', 'PATCH', "repos/$Repository/issues/$n", '-f', 'state=closed', '-f', 'state_reason=duplicate',
            '-F', "duplicate_issue_id=$($original.Id)")) -and $ok

    if ($Apply) {
        if ($ok) {
            $item.action = 'closed-as-duplicate'
            $result.counts.closed++
        }
        else {
            $item.action = 'failed'
            $result.counts.failed++
            $failedItems++
        }
    }
    $result.items.Add([pscustomobject]$item)
}

# Every GET in the range failing is a wire problem, not 39 coincidences: report it
# as the credential precondition so the operator fixes auth instead of the range.
if ($readable -eq 0) {
    Write-Line ''
    Write-Line "close-duplicate-issues: FAILED PRECONDITION - none of #$From-#$To could be read; the credential can reach the repository but not its issues."
    Add-Note 'no issue in the range was readable'
    Exit-With 2
}

# --- Rollup --------------------------------------------------------------------------
Write-Line ''
$c = $result.counts
if ($result.replay.Count -gt 0) {
    Write-Line "close-duplicate-issues: $failedItems issue(s) had a FAILED mutation - replay list:"
    foreach ($r in $result.replay) { Write-Line "  $r" }
    Write-Line 'Each command line is directly re-runnable by an identity with write on the repository;'
    Write-Line 're-running this script is also safe (label and comment are skipped where they already landed).'
    Exit-With 1
}
if ($Apply) {
    Write-Line "close-duplicate-issues: complete - closed=$($c.closed) skipped=$($c.skipped) unreadable=$($c.unreadable)."
    Write-Line 'Idempotence check: re-run this script and expect every former candidate to read "skip:already-closed".'
    Write-Line 'If any reopen within minutes, the Linear-side issue sync for team JOH is still on (owner step above).'
}
else {
    Write-Line "close-duplicate-issues: dry run complete - candidates=$($c.candidates) skipped=$($c.skipped) unreadable=$($c.unreadable). Nothing was changed."
    Write-Line 'Re-run with -Apply to execute the commands above, AFTER the Linear-side switch is off.'
}
Exit-With 0
