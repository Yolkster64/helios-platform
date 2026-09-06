#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Collapses branch sprawl on the remote: deletes fully merged branches and
    archives-then-deletes stale ones (a lightweight tag <ArchivePrefix><branch>
    at the tip is created BEFORE the branch goes), keeping the default branch,
    the keep-list and every open-PR head. Dry-run by default; -Apply executes.

.DESCRIPTION
    The branch-hygiene sibling of scripts/github/apply-rulesets.ps1 and
    apply-repo-settings.ps1: same wire-truth precondition, same GET-diff-then-
    print-then-apply shape per item, same exit contract. Every branch on the
    remote is classified from live API reads, never from a local clone:

      open-pr       head of an open pull request, in this repository OR in the
                    upstream parent when this repository is a fork      -> keep
                    (GitHub closes a PR the moment its head branch is deleted,
                    so a parent-repo PR whose head lives here is protected too;
                    a PR whose head lives in some OTHER fork is not affected)
      keep-list     default branch, main, develop, master, plus -Keep -> keep
      merged        compare/{default}...{tip sha} says ahead_by == 0  -> delete
                    (every commit is already reachable from the default branch,
                    so nothing is lost and no tag is needed)
      stale         everything else (has unmerged commits)            -> archive-then-delete:
                    POST git/refs {refs/tags/<ArchivePrefix><branch>, tip sha}
                    then DELETE git/refs/heads/<branch>. Tag creation is skipped
                    when the tag already exists at the same sha; a tag at a
                    DIFFERENT sha fails the item and the branch is left alone,
                    because deleting it would orphan commits the tag does not cover.
      unclassified  the compare read failed                            -> skip, exit 1
                    (a branch whose state could not be measured is never deleted)

    Reversibility: every deleted stale tip survives as the tag
    <ArchivePrefix><branch>. Restore a branch with

        git push origin refs/tags/archive/<branch>:refs/heads/<branch>

    A merged branch needs no tag because its tip is already on the default
    branch; the report keeps the sha, so `git branch <name> <sha>` recreates it.

    Order of operations under -Apply, per item: print the exact command, re-read
    the branch tip and refuse if it moved since enumeration (the archive tag must
    cover exactly what is deleted), create the tag, delete the ref. A failed item
    never aborts the pass: the remaining items still run and the script exits 1
    with a consolidated replay list of everything that did not land.

    Transport notes, measured against this repository: `gh api --paginate`
    follows GitHub's Link header, which points at repositories/{id}/... numeric
    paths that some egress proxies reject (HTTP 403), so this script pages
    explicitly with per_page=100&page=N (identical results on a plain transport).
    Classification never puts a branch NAME in a URL: the compare is
    compare/{default}...{tip sha} with the sha the enumeration already holds, so
    a proxy that cannot canonicalize '%23' ('#') still classifies such a branch
    (measured: HTTP 400 by encoded name, a normal ahead_by by sha). Branch names
    are percent-encoded only where the ref itself is addressed — the -Apply tip
    re-read (git/ref/heads) and the DELETE (git/refs/heads) — because '/', ','
    and '#' all occur in this repository's branch names and GitHub accepts the
    encoded form there. Behind such a proxy those two calls surface as a failed
    item with a replay line, never as a guess.
    Every call carries X-GitHub-Api-Version: 2022-11-28 (gh 2.63.2 sends none by
    itself); a 429, or a 403 naming the rate/secondary limit, is retried once
    after Retry-After (60 s when absent); tag and delete calls are paced >= 1 s
    apart, because an apply issues ~2 mutations per stale branch against
    GitHub's ~80/min secondary limit.

.PARAMETER Repository
    Target repository as owner/name. Defaults to Yolkster64/helios-platform.

.PARAMETER Apply
    Execute the tag and delete calls. Without it the script only prints them.

.PARAMETER Json
    Emit exactly one JSON object on stdout and nothing else there; human notes,
    progress and the per-item commands go to stderr instead. Shape:
    {repository, defaultBranch, parent, generatedUtc, apply, maxDelete,
     capExceeded, items[{branch, sha, class, aheadBy, action, result}],
     summary{total, openPr, keepList, merged, stale, unclassified, planned,
     failed}, replay[], error, nextStep, exitCode}. `parent` is the upstream
    repository when this one is a fork (else null); `nextStep` is the exact
    owner command that follows this run (the apply dispatch after a dry run,
    the raised-cap dispatch after a safety-cap refusal, the restore hint after
    an apply), so a job summary built from the object is never a dead end.

.PARAMETER Keep
    Extra branch names to keep, on top of the default branch, main, develop and
    master. Accepts an array or one comma-separated string.

.PARAMETER ArchivePrefix
    Tag namespace for archived stale tips. Defaults to 'archive/'.

.PARAMETER MaxDelete
    Safety cap. When the plan holds more deletions (merged + stale) than this,
    -Apply refuses with exit 2 and changes nothing; a dry run still prints the
    full plan and flags the overflow. Raise it deliberately: the refusal prints
    the exact re-dispatch (`gh workflow run branch-prune.yml ... -f max_delete=N`,
    the workflow's `max_delete` input maps 1:1 to this parameter). Defaults to 200.

.EXAMPLE
    pwsh scripts/github/prune-branches.ps1
    # dry run: prints the classification table and every gh api call it would make

.EXAMPLE
    pwsh scripts/github/prune-branches.ps1 -Json > branch-prune-report.json
    # same plan as one JSON object (what .github/workflows/branch-prune.yml stores)

.EXAMPLE
    pwsh scripts/github/prune-branches.ps1 -Apply -Keep 'spike/keep-me,experiment/keep-me-too'
    # applies; needs a wire credential with contents write. The intended path is
    # the workflow: gh workflow run branch-prune.yml -f apply=true -f keep=<a,b>
    # (open-PR heads, local and upstream, are protected without any -Keep entry)

.NOTES
    Exit codes: 0 = success (or clean dry run); 1 = one or more items failed or
    could not be classified (replay list printed); 2 = gh missing, repos/{repo}
    unreadable, -Apply without contents write (permissions.push), or the plan
    exceeds -MaxDelete under -Apply.
    Secrets: no token value is ever read, stored or printed; the auth probe is
    `gh api repos/{repo}`'s exit code plus three non-secret fields (default
    branch, the boolean permissions.push, the parent's name when a fork)
    (`gh auth status` is deliberately not consulted: it can lie both ways, and
    the REST wire is the ground truth, scripts/verify/rest-connect.ps1 doctrine).
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',
    [switch]$Apply,
    [switch]$Json,
    [string[]]$Keep = @(),
    [string]$ArchivePrefix = 'archive/',
    [ValidateRange(1, 100000)][int]$MaxDelete = 200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = if ($Apply) { 'apply' } else { 'dry-run' }
$generatedUtc = [DateTime]::UtcNow.ToString('o')
$defaultBranch = ''
$parentRepo = ''
$nextStep = ''
$items = [System.Collections.Generic.List[object]]::new()
$replay = [System.Collections.Generic.List[string]]::new()
$capExceeded = $false

# -Keep accepts one comma-separated string so a workflow input maps 1:1. It is
# parsed before the preconditions because the exact re-dispatch command that a
# refused run prints must carry the same keep list the owner asked for.
$keepExtra = [System.Collections.Generic.List[string]]::new()
foreach ($entry in @($Keep)) {
    foreach ($piece in ([string]$entry -split ',')) {
        $trimmed = $piece.Trim()
        if ($trimmed -and -not $keepExtra.Contains($trimmed)) { $keepExtra.Add($trimmed) }
    }
}

# The only apply path that holds contents write is the workflow, so every owner
# action is rendered as the exact `gh workflow run` dispatch: same keep list,
# plus the max_delete the plan needs when the safety cap was the reason.
function Get-DispatchCommand {
    param([int]$MaxDeleteValue = 0)
    $command = "gh workflow run branch-prune.yml --repo $Repository -f apply=true"
    if ($keepExtra.Count -gt 0) { $command += " -f keep='$($keepExtra -join ',')'" }
    if ($MaxDeleteValue -gt 0) { $command += " -f max_delete=$MaxDeleteValue" }
    return $command
}

# Human output goes to stdout normally; under -Json stdout is reserved for the
# single object, so every note moves to stderr (a workflow log still shows it).
function Out-Note {
    param([string]$Text = '')
    if ($Json) { [Console]::Error.WriteLine($Text) } else { Write-Host $Text }
}

# Progress always goes to stderr: ~100 sequential compare reads look like a hang
# otherwise, and stderr can never pollute a captured table or the JSON object.
function Out-Progress {
    param([string]$Text)
    [Console]::Error.WriteLine($Text)
}

# StrictMode-safe property access on parsed JSON (rest-connect.ps1 pattern):
# a missing property must read as the default, not throw mid-pass.
function Get-OptionalProperty {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop -and $null -ne $prop.Value) { return $prop.Value }
    return $Default
}

# Percent-encode a ref name for a URL path segment. Branch names here carry
# '/', ',' and '#'; a raw '#' would be read as a URL fragment and a raw ','
# is ambiguous on some transports, while GitHub accepts the encoded form.
function ConvertTo-PathSegment {
    param([Parameter(Mandatory)][string]$Value)
    return [System.Uri]::EscapeDataString($Value)
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

# Explicit paging (see .DESCRIPTION for why --paginate is not used). Returns
# $null when any page fails so the caller can refuse to classify from a partial
# list: a branch missing from the enumeration would silently escape the plan,
# but a branch PRESENT in a partial list could be misjudged against missing PRs.
# The List is returned with the unary comma so an EMPTY result stays a List:
# a bare `return $all` unrolls it into the pipeline and an empty List comes
# back as $null, indistinguishable from the failure sentinel (measured: a
# repository with zero open PRs would fail the open-PR precondition).
function Get-GhApiPages {
    param([Parameter(Mandatory)][string]$Path)
    $all = [System.Collections.Generic.List[object]]::new()
    $page = 1
    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    while ($true) {
        $endpoint = "$Path${separator}per_page=100&page=$page"
        $response = Invoke-GhApi -GhArgs @($endpoint)
        if ($response.ExitCode -ne 0) {
            Out-Note "prune-branches: gh api exited $($response.ExitCode) for $endpoint"
            return $null
        }
        $batch = @($response.Json)
        if ($batch.Count -eq 0) { break }
        foreach ($entry in $batch) { $all.Add($entry) }
        if ($batch.Count -lt 100) { break }
        $page++
        # A runaway loop guard: 100 pages is 10,000 refs, far beyond any real
        # repository here; hitting it means the transport is replaying a page.
        if ($page -gt 100) {
            Out-Note "prune-branches: more than 100 pages from $Path; refusing to continue."
            return $null
        }
    }
    return , $all
}

# Single exit point so -Json always emits exactly one object, including on a
# precondition failure (the workflow's summary step reads that object).
function Complete-Run {
    param([int]$ExitCode, [string]$ErrorText = '')
    if ($Json) {
        $classCount = @{ 'open-pr' = 0; 'keep-list' = 0; 'merged' = 0; 'stale' = 0; 'unclassified' = 0 }
        $failed = 0
        foreach ($item in $items) {
            if ($classCount.ContainsKey($item.Class)) { $classCount[$item.Class]++ }
            if ($item.Result -like 'FAILED*') { $failed++ }
        }
        $plannedCount = @($items | Where-Object { $_.Action -in @('delete', 'archive-then-delete') }).Count
        $document = [ordered]@{
            repository    = $Repository
            defaultBranch = $defaultBranch
            parent        = $(if ($parentRepo) { $parentRepo } else { $null })
            generatedUtc  = $generatedUtc
            apply         = [bool]$Apply
            maxDelete     = $MaxDelete
            capExceeded   = $capExceeded
            items         = @($items | ForEach-Object {
                    [ordered]@{
                        branch  = $_.Branch
                        sha     = $_.Sha
                        class   = $_.Class
                        aheadBy = $_.AheadBy
                        action  = $_.Action
                        result  = $_.Result
                    }
                })
            summary       = [ordered]@{
                total        = $items.Count
                openPr       = $classCount['open-pr']
                keepList     = $classCount['keep-list']
                merged       = $classCount['merged']
                stale        = $classCount['stale']
                unclassified = $classCount['unclassified']
                planned      = $plannedCount
                failed       = $failed
            }
            replay        = @($replay)
            error         = $(if ($ErrorText) { $ErrorText } else { $null })
            nextStep      = $(if ($nextStep) { $nextStep } else { $null })
            exitCode      = $ExitCode
        }
        Write-Output ($document | ConvertTo-Json -Depth 6)
    }
    exit $ExitCode
}

Out-Note "prune-branches: mode=$mode repository=$Repository archivePrefix=$ArchivePrefix maxDelete=$MaxDelete"

# --- Wire-truth precondition (kept in sync with apply-rulesets.ps1 and
# --- apply-repo-settings.ps1): gh present, the repo readable on the REST wire,
# --- and under -Apply a credential holding contents write (.permissions.push).
# --- Capture-then-$LASTEXITCODE; the captured output is one boolean field.
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gh) {
    Out-Note 'prune-branches: FAILED PRECONDITION - the GitHub CLI (gh) is not on PATH.'
    Out-Note 'Install it (https://cli.github.com/) and authenticate; even the dry run needs it'
    Out-Note 'because every classification is a live API read.'
    $nextStep = 'Install the GitHub CLI (https://cli.github.com/), run `gh auth login`, then re-run'
    Complete-Run -ExitCode 2 -ErrorText 'gh CLI not on PATH'
}

# One read answers three questions: the default branch ("merged" is measured
# against it), contents write (.permissions.push, the -Apply gate) and the
# upstream parent (a fork's branches can be the heads of the PARENT's open PRs,
# which must be protected exactly like local ones). The --jq projection keeps
# the captured output to those three non-secret fields.
$repoProbe = Invoke-GhApi -GhArgs @("repos/$Repository", '--jq', '{default_branch: .default_branch, push: .permissions.push, parent: .parent.full_name}')
if ($repoProbe.ExitCode -ne 0 -or $null -eq $repoProbe.Json) {
    Out-Note "prune-branches: FAILED PRECONDITION - the wire probe could not read repos/$Repository (gh api exited $($repoProbe.ExitCode))."
    Out-Note 'No usable GitHub credential answered on the REST wire ("gh auth status" is'
    Out-Note 'deliberately not consulted - it can lie both ways; the REST probe is the ground'
    Out-Note 'truth, scripts/verify/rest-connect.ps1 doctrine). Authenticate first: "gh auth'
    Out-Note 'login", or scripts/bootstrap/connect-github.sh --from-env, or set the GH_TOKEN'
    Out-Note 'environment variable (the NAME of the variable to set - never put the value in a'
    Out-Note 'file or argument). Nothing was changed.'
    $nextStep = "gh auth login (or set the GH_TOKEN environment variable by NAME), then verify: gh api repos/$Repository --jq .permissions.push"
    Complete-Run -ExitCode 2 -ErrorText "wire probe could not read repos/$Repository"
}
$defaultBranch = [string](Get-OptionalProperty $repoProbe.Json 'default_branch' '')
$wirePush = ((Get-OptionalProperty $repoProbe.Json 'push' $false) -eq $true)
$parentRepo = [string](Get-OptionalProperty $repoProbe.Json 'parent' '')
if ($Apply -and -not $wirePush) {
    $nextStep = Get-DispatchCommand
    Out-Note "prune-branches: FAILED PRECONDITION - the wire credential cannot write refs in $Repository."
    Out-Note 'The probe read the repository but `gh api repos/{repo} --jq .permissions.push` is not'
    Out-Note 'true. Tag creation and branch deletion need contents write. Run the apply from the'
    Out-Note 'branch-prune workflow, whose GITHUB_TOKEN carries exactly that permission:'
    Out-Note "  $nextStep"
    Out-Note 'Nothing was changed.'
    Complete-Run -ExitCode 2 -ErrorText 'wire credential lacks contents write (permissions.push is not true)'
}
if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
    Out-Note "prune-branches: FAILED PRECONDITION - could not read the default branch of $Repository."
    $nextStep = "gh api repos/$Repository --jq .default_branch  (must print a branch name before a plan can be built)"
    Complete-Run -ExitCode 2 -ErrorText 'default branch unreadable'
}

# --- Enumerate: branches, open PR heads (local and upstream), archive tags --------
$branches = Get-GhApiPages -Path "repos/$Repository/branches"
if ($null -eq $branches) {
    Out-Note 'prune-branches: FAILED PRECONDITION - branch enumeration failed; nothing can be classified.'
    $nextStep = "gh api 'repos/$Repository/branches?per_page=100&page=1' --jq length  (must succeed, then re-run)"
    Complete-Run -ExitCode 2 -ErrorText 'branch enumeration failed'
}
$openPulls = Get-GhApiPages -Path "repos/$Repository/pulls?state=open"
if ($null -eq $openPulls) {
    Out-Note 'prune-branches: FAILED PRECONDITION - open PR enumeration failed; an open-PR head could be misclassified.'
    $nextStep = "gh api 'repos/$Repository/pulls?state=open&per_page=100&page=1' --jq length  (must succeed, then re-run)"
    Complete-Run -ExitCode 2 -ErrorText 'open PR enumeration failed'
}
# A fork's branch can also be the head of a PR opened against the upstream parent
# (GitHub closes that PR the moment its head is deleted), so the parent's open
# PRs are read too. A failure there is as fatal as a local one: a plan built
# from a partial PR set could delete a live head, which is the one mistake the
# archive tag does not undo (the PR has to be reopened by hand).
$parentPulls = [System.Collections.Generic.List[object]]::new()
if ($parentRepo) {
    $parentPulls = Get-GhApiPages -Path "repos/$parentRepo/pulls?state=open"
    if ($null -eq $parentPulls) {
        Out-Note "prune-branches: FAILED PRECONDITION - upstream PR enumeration failed for $parentRepo; a head of an upstream PR could be misclassified."
        $nextStep = "gh api 'repos/$parentRepo/pulls?state=open&per_page=100&page=1' --jq length  (must succeed, then re-run)"
        Complete-Run -ExitCode 2 -ErrorText "upstream PR enumeration failed ($parentRepo)"
    }
}

# Only heads that live in THIS repository protect a branch: a PR whose head sits
# in some other fork and happens to share a name with a local branch does not
# depend on the local ref. The value is the PR label the table shows: "#N" for a
# local PR, "<parent>#N" for an upstream one (both, comma-joined, when a branch
# heads a PR in each place).
$openHeads = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
$localHeadCount = 0
$upstreamHeadCount = 0
foreach ($source in @(@{ Pulls = $openPulls; Label = '' }, @{ Pulls = $parentPulls; Label = $parentRepo })) {
    foreach ($pull in @($source.Pulls)) {
        $head = Get-OptionalProperty $pull 'head' $null
        $headRepo = Get-OptionalProperty (Get-OptionalProperty $head 'repo' $null) 'full_name' ''
        $headRef = [string](Get-OptionalProperty $head 'ref' '')
        if ($headRef -and ([string]$headRepo).Equals($Repository, [System.StringComparison]::OrdinalIgnoreCase)) {
            $label = "$($source.Label)#$([int](Get-OptionalProperty $pull 'number' 0))"
            if ($source.Label) { $upstreamHeadCount++ } else { $localHeadCount++ }
            $openHeads[$headRef] = if ($openHeads.ContainsKey($headRef)) { "$($openHeads[$headRef]), $label" } else { $label }
        }
    }
}

# Keep-list: the default branch is always in it even when it is not named main,
# plus the -Keep entries parsed above.
$keepSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($name in @($defaultBranch, 'main', 'develop', 'master')) { [void]$keepSet.Add($name) }
foreach ($name in $keepExtra) { [void]$keepSet.Add($name) }

# One bulk read of the existing archive tags for the PLAN (dry run and apply
# table alike). The trailing slash is stripped from the URL because some
# transports refuse to canonicalize it, so the match below is by exact ref name
# rather than by prefix. Under -Apply each item re-reads its own tag at mutation
# time; this map is only advisory.
$archivePrefixTrimmed = $ArchivePrefix.TrimEnd('/')
$existingTags = @{}
$tagStateKnown = $false
if ($archivePrefixTrimmed) {
    $tagRead = Invoke-GhApi -GhArgs @("repos/$Repository/git/matching-refs/tags/$(ConvertTo-PathSegment $archivePrefixTrimmed)")
    if ($tagRead.ExitCode -eq 0) {
        $tagStateKnown = $true
        foreach ($ref in @($tagRead.Json)) {
            $refName = [string](Get-OptionalProperty $ref 'ref' '')
            $refSha = [string](Get-OptionalProperty (Get-OptionalProperty $ref 'object' $null) 'sha' '')
            if ($refName) { $existingTags[$refName] = $refSha }
        }
    }
    else {
        Out-Note "prune-branches: note - existing $ArchivePrefix* tags could not be listed (gh api exited $($tagRead.ExitCode)); the plan assumes none, a real run re-checks per item."
    }
}

Out-Note "prune-branches: default=$defaultBranch parent=$(if ($parentRepo) { $parentRepo } else { '-' }) branches=$($branches.Count) openPrHeads=$($openHeads.Count) (local $localHeadCount, upstream $upstreamHeadCount) keepList=$(($keepSet | Sort-Object) -join ',') archiveTags=$($existingTags.Count)"

# --- Classify ---------------------------------------------------------------------
$encodedDefault = ConvertTo-PathSegment $defaultBranch
$sorted = @($branches | Sort-Object { [string](Get-OptionalProperty $_ 'name' '') })
$compareTotal = @($sorted | Where-Object {
        $n = [string](Get-OptionalProperty $_ 'name' '')
        -not $openHeads.ContainsKey($n) -and -not $keepSet.Contains($n)
    }).Count
$compareDone = 0
foreach ($branch in $sorted) {
    $name = [string](Get-OptionalProperty $branch 'name' '')
    $sha = [string](Get-OptionalProperty (Get-OptionalProperty $branch 'commit' $null) 'sha' '')
    $class = ''
    $action = ''
    $aheadBy = $null
    $result = ''

    if ($openHeads.ContainsKey($name)) {
        $class = 'open-pr'
        $action = 'keep'
        $result = "head of open PR $($openHeads[$name])"
    }
    elseif ($keepSet.Contains($name)) {
        $class = 'keep-list'
        $action = 'keep'
        $result = if ($name -eq $defaultBranch) { 'default branch' } else { 'keep-list' }
    }
    else {
        $compareDone++
        # Every 10th read plus the last one: enough to prove liveness without
        # drowning a CI log in ~100 lines.
        if (($compareDone % 10) -eq 0 -or $compareDone -eq $compareTotal) {
            Out-Progress "  compare $compareDone/$compareTotal ($name)"
        }
        # The body is parsed rather than --jq'd because a 404 carries the one
        # failure that is still a verdict: "No common ancestor" means an
        # unrelated history, which is certainly not merged. The head is the
        # tip SHA, not the branch name: same answer, and no '#'/','/'/' ever
        # reaches a URL path that a proxy might refuse to canonicalize.
        $compareEndpoint = "repos/$Repository/compare/$encodedDefault...$sha"
        $compare = Invoke-GhApi -GhArgs @($compareEndpoint)
        $aheadRaw = Get-OptionalProperty $compare.Json 'ahead_by' $null
        $compareMessage = [string](Get-OptionalProperty $compare.Json 'message' '')
        if ($compare.ExitCode -eq 0 -and $null -ne $aheadRaw -and ([string]$aheadRaw) -match '^\d+$') {
            $aheadBy = [int]$aheadRaw
        }
        elseif ($compareMessage -like 'No common ancestor*') {
            # Unrelated history: ahead_by is undefined, but every commit is
            # unmerged, so the archive tag must cover the whole branch.
            $class = 'stale'
            $action = 'archive-then-delete'
            $result = "no common ancestor with $defaultBranch; whole branch archived"
        }
        else {
            $class = 'unclassified'
            $action = 'skip'
            $result = "FAILED: compare read failed (gh exited $($compare.ExitCode), HTTP $($compare.HttpStatus)); not deleted"
            $replay.Add("[$name] $script:GhApiReplay $compareEndpoint --jq .ahead_by")
        }
        if ($null -ne $aheadBy) {
            if ($aheadBy -eq 0) {
                $class = 'merged'
                $action = 'delete'
            }
            else {
                $class = 'stale'
                $action = 'archive-then-delete'
            }
        }
        # Plan-time note for every stale item (ahead or unrelated): an archive
        # tag already at the tip is skipped, one elsewhere is a foreseeable
        # failure the owner should see before dispatching an apply.
        if ($class -eq 'stale') {
            $tagRef = "refs/tags/$ArchivePrefix$name"
            if ($existingTags.ContainsKey($tagRef)) {
                $tagNote = if ($existingTags[$tagRef] -eq $sha) {
                    'tag exists at tip; creation skipped'
                }
                else {
                    "tag exists at DIFFERENT sha $($existingTags[$tagRef]); item will fail"
                }
                $result = if ($result) { "$result; $tagNote" } else { $tagNote }
            }
        }
    }

    $items.Add([pscustomobject]@{
            Branch  = $name
            Sha     = $sha
            Class   = $class
            AheadBy = $aheadBy
            Action  = $action
            Result  = $result
        })
}

# --- Plan table -------------------------------------------------------------------
$branchWidth = [Math]::Max(6, (@($items | ForEach-Object { $_.Branch.Length }) | Measure-Object -Maximum).Maximum)
Out-Note ''
Out-Note ('{0} {1,-12} {2,8} {3,-19} {4}' -f 'branch'.PadRight($branchWidth), 'class', 'ahead_by', 'action', 'note')
Out-Note ('{0} {1} {2} {3} {4}' -f ('-' * $branchWidth), ('-' * 12), ('-' * 8), ('-' * 19), ('-' * 4))
foreach ($item in $items) {
    $aheadText = if ($null -eq $item.AheadBy) { '-' } else { [string]$item.AheadBy }
    Out-Note ('{0} {1,-12} {2,8} {3,-19} {4}' -f $item.Branch.PadRight($branchWidth), $item.Class, $aheadText, $item.Action, $item.Result)
}

$planned = @($items | Where-Object { $_.Action -in @('delete', 'archive-then-delete') })
$unclassifiedCount = @($items | Where-Object { $_.Class -eq 'unclassified' }).Count
Out-Note ''
Out-Note "prune-branches: $($items.Count) branches; keep $(@($items | Where-Object { $_.Action -eq 'keep' }).Count); delete $(@($planned | Where-Object { $_.Action -eq 'delete' }).Count) merged; archive-then-delete $(@($planned | Where-Object { $_.Action -eq 'archive-then-delete' }).Count) stale; unclassified $unclassifiedCount"
if (-not $tagStateKnown -and $archivePrefixTrimmed) {
    Out-Note "prune-branches: note - $ArchivePrefix* tag state unknown for this plan (see above)."
}

if ($planned.Count -gt $MaxDelete) {
    $capExceeded = $true
    # The cap is raised through the workflow's max_delete input, never by
    # editing the default: the exact dispatch is the only owner action offered.
    $nextStep = Get-DispatchCommand -MaxDeleteValue $planned.Count
    Out-Note "prune-branches: SAFETY CAP - the plan deletes $($planned.Count) branches, more than -MaxDelete $MaxDelete."
    if ($Apply) {
        Out-Note 'Nothing was changed. Once the table above has been reviewed, re-dispatch with the cap the plan needs:'
        Out-Note "  $nextStep"
        Complete-Run -ExitCode 2 -ErrorText "plan deletes $($planned.Count) branches, above -MaxDelete $MaxDelete"
    }
    Out-Note "An apply run would refuse until max_delete is raised to at least $($planned.Count):"
    Out-Note "  $nextStep"
}

# --- Per-item commands: print first, execute only under -Apply -------------------
Out-Note ''
foreach ($item in $planned) {
    $name = $item.Branch
    $encoded = ConvertTo-PathSegment $name
    $tagRef = "refs/tags/$ArchivePrefix$name"
    $encodedTag = ConvertTo-PathSegment "$ArchivePrefix$name"
    $deleteArgs = @('--method', 'DELETE', "repos/$Repository/git/refs/heads/$encoded")
    $deleteCmd = "$script:GhApiReplay --method DELETE repos/$Repository/git/refs/heads/$encoded"
    $tagArgs = @('--method', 'POST', "repos/$Repository/git/refs", '-f', "ref=$tagRef", '-f', "sha=$($item.Sha)")
    $tagCmd = "$script:GhApiReplay --method POST repos/$Repository/git/refs -f 'ref=$tagRef' -f 'sha=$($item.Sha)'"
    $needsTag = ($item.Action -eq 'archive-then-delete')

    if (-not $Apply) {
        Out-Note "[dry-run] $name ($($item.Class)):"
        if ($needsTag) { Out-Note "[dry-run]   $tagCmd" }
        Out-Note "[dry-run]   $deleteCmd"
        continue
    }

    # 1. The tip must still be what the plan measured: the archive tag (or the
    #    merged verdict) covers that sha and nothing newer.
    $tipRead = Invoke-GhApi -GhArgs @("repos/$Repository/git/ref/heads/$encoded", '--jq', '.object.sha')
    if ($tipRead.ExitCode -ne 0 -or $tipRead.Text -ne $item.Sha) {
        $seen = if ($tipRead.ExitCode -eq 0) { $tipRead.Text } else { "unreadable (gh exited $($tipRead.ExitCode))" }
        $item.Result = "FAILED: tip moved since enumeration (planned $($item.Sha), now $seen); not deleted"
        Out-Note "[apply] $name FAILED - $($item.Result)"
        $replay.Add("[$name] re-run prune-branches.ps1 -Apply (the plan is re-measured on every run)")
        continue
    }

    # 2. Archive tag (stale only): skip when it already points at the tip, refuse
    #    when it points elsewhere, create it when absent. 404 is the only reply
    #    that means "absent"; any other failure is unknown state, never a go-ahead.
    if ($needsTag) {
        $tagRead = Invoke-GhApi -GhArgs @("repos/$Repository/git/ref/tags/$encodedTag")
        $tagStatus = [string](Get-OptionalProperty $tagRead.Json 'status' '')
        if ($tagRead.ExitCode -eq 0) {
            $tagSha = [string](Get-OptionalProperty (Get-OptionalProperty $tagRead.Json 'object' $null) 'sha' '')
            if ($tagSha -eq $item.Sha) {
                Out-Note "[apply] $name - tag $tagRef already at tip; creation skipped"
            }
            else {
                $item.Result = "FAILED: tag $tagRef exists at $tagSha, tip is $($item.Sha); not deleted"
                Out-Note "[apply] $name FAILED - $($item.Result)"
                $replay.Add("[$name] inspect: $script:GhApiReplay repos/$Repository/git/ref/tags/$encodedTag  (move or delete the tag deliberately, then re-run)")
                continue
            }
        }
        elseif ($tagStatus -eq '404') {
            Out-Note "[apply] $name - $tagCmd"
            $tagCreate = Invoke-GhApi -GhArgs $tagArgs -Mutating
            if ($tagCreate.ExitCode -ne 0) {
                $item.Result = "FAILED: tag creation failed (gh exited $($tagCreate.ExitCode), HTTP $($tagCreate.HttpStatus)); not deleted"
                Out-Note "[apply] $name FAILED - $($item.Result)"
                $replay.Add("[$name] $tagCmd")
                continue
            }
            Out-Note "[apply] $name - tag created"
        }
        else {
            $item.Result = "FAILED: tag state unknown (gh exited $($tagRead.ExitCode), HTTP $($tagRead.HttpStatus)); not deleted"
            Out-Note "[apply] $name FAILED - $($item.Result)"
            $replay.Add("[$name] $script:GhApiReplay repos/$Repository/git/ref/tags/$encodedTag")
            continue
        }
    }

    # 3. Delete the branch ref.
    Out-Note "[apply] $name - $deleteCmd"
    $deleteRun = Invoke-GhApi -GhArgs $deleteArgs -Mutating
    if ($deleteRun.ExitCode -ne 0) {
        $item.Result = "FAILED: delete failed (gh exited $($deleteRun.ExitCode), HTTP $($deleteRun.HttpStatus))" + $(if ($needsTag) { '; tag exists, branch remains' } else { '' })
        Out-Note "[apply] $name FAILED - $($item.Result)"
        $replay.Add("[$name] $deleteCmd")
        continue
    }
    $item.Result = if ($needsTag) { "archived as $tagRef and deleted" } else { 'deleted (merged)' }
    Out-Note "[apply] $name - $($item.Result)"
}

# --- Rollup -----------------------------------------------------------------------
Out-Note ''
$failedItems = @($items | Where-Object { $_.Result -like 'FAILED*' })
if ($failedItems.Count -gt 0) {
    Out-Note "prune-branches: $($failedItems.Count) item(s) FAILED - replay list:"
    foreach ($line in $replay) { Out-Note "  $line" }
    Out-Note 'Each line is directly re-runnable by an identity with contents write; a re-run of'
    Out-Note 'this script re-measures every branch and skips tags that already sit at the tip.'
    # An unclassified branch is skipped, never deleted, so a dry run with failed
    # items still has the apply dispatch as its next step; an apply with failed
    # items is re-dispatched (the plan is re-measured on every run).
    if (-not $nextStep) { $nextStep = Get-DispatchCommand }
    Out-Note "Next: $nextStep"
    Complete-Run -ExitCode 1
}
if ($Apply) {
    $nextStep = "git push origin refs/tags/$ArchivePrefix<branch>:refs/heads/<branch>  (restores an archived branch; nothing else is pending)"
    Out-Note "prune-branches: complete - $($planned.Count) branch(es) removed. Restore any archived one with:"
    Out-Note "  git push origin refs/tags/$ArchivePrefix<branch>:refs/heads/<branch>"
}
else {
    if (-not $nextStep) { $nextStep = Get-DispatchCommand }
    Out-Note 'Dry run complete - nothing was changed. Next: review the table, then dispatch the apply:'
    Out-Note "  $nextStep"
    if ($keepExtra.Count -eq 0) { Out-Note "  (add -f keep='<a,b>' to keep more branches; open-PR heads need no entry)" }
}
Complete-Run -ExitCode 0
