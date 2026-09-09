#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Applies the deployment environments in config/github/environments.json to GitHub.

.DESCRIPTION
    Dry-run by default: prints the exact `gh api` calls it would make and changes nothing.
    Re-run with -Apply to execute them. Idempotent: it GETs each environment first and
    compares wait_timer, prevent_self_review, the reviewer set and the deployment branch
    policy, so an unchanged environment reads `in sync` and makes no call. It never deletes
    an environment and never removes a protection rule the manifest does not mention -
    absence here means unmanaged, not "set it to nothing".

    Why this exists: CLAUDE.md states that GitHub protected environments remain deployment
    authority, and .github/workflows/helios-deploy.yml names `production` on the job that
    runs `az deployment group create`. Naming an environment GitHub does not have CREATES
    it, with no protection rules at all - a gate in the YAML and none in reality. This
    script is how that gap becomes visible, and the dry run is the report.

    Reviewers are the one part this cannot settle alone. The API wants numeric ids, so a
    login is resolved through GET /users/{login} and a team slug through
    GET /orgs/{org}/teams/{slug}. A slug that cannot be resolved is reported as an owner
    action and the environment is left alone: a PUT carrying a partial reviewer list would
    quietly REMOVE the reviewers it could not resolve, which is the opposite of the intent.

    Secrets and variables are named, never valued. `secretNames` and `variableNames` are
    reported as owner actions with the exact `gh secret set --env` / `gh variable set --env`
    command; no value is read, printed or stored by this script.

.PARAMETER Apply
    Execute the calls. Without it nothing is changed and the calls are printed.

.PARAMETER Repository
    owner/repo to apply to. Defaults to Yolkster64/helios-platform.

.PARAMETER ManifestPath
    The environment manifest. Defaults to config/github/environments.json.

.PARAMETER Json
    Emit one JSON report object on stdout instead of the human table.

.EXAMPLE
    pwsh scripts/github/apply-environments.ps1
.EXAMPLE
    pwsh scripts/github/apply-environments.ps1 -Apply

.NOTES
    Exit codes: 0 = every environment is in sync and nothing is left for you;
    2 = owner items remain (they are listed, each with its command);
    1 = a call failed for a reason that is not yours to fix.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$ManifestPath,
    [switch]$Json
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

$mode = if ($Apply) { 'apply' } else { 'dry-run' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ManifestPath) { $ManifestPath = Join-Path $repoRoot 'config' 'github' 'environments.json' }

# Exit 2 means "a precondition is missing", and nothing else. .github/workflows/
# governance-run.yml reads exit 2 from an admin item during -Apply as "this admin
# credential was rejected" and turns the row red with a rotate-your-token message - so
# exiting 2 merely because a follow-up note remains (set this variable, paste that secret)
# would report a perfectly good App token as revoked. Pending dry-run changes are exit 0
# too: the runner counts the printed "would run:" lines to report them.
$script:precondition = $false
$lines = [System.Collections.Generic.List[string]]::new()
$ownerActions = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
function Write-Line { param([string]$Text = '') if (-not $Json) { Write-Host $Text }; $lines.Add($Text) | Out-Null }
function Add-OwnerAction { param([string]$Text) if (-not $ownerActions.Contains($Text)) { $ownerActions.Add($Text) | Out-Null } }

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

Write-Line "apply-environments: mode=$mode repository=$Repository manifest=$ManifestPath"

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Line "ERROR: manifest not found: $ManifestPath"
    if ($Json) { [pscustomobject]@{ mode = $mode; status = 'failed'; reason = 'manifest missing' } | ConvertTo-Json -Depth 6 }
    exit 1
}

try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
catch {
    Write-Line "ERROR: manifest is not valid JSON: $($_.Exception.Message)"
    if ($Json) { [pscustomobject]@{ mode = $mode; status = 'failed'; reason = 'manifest unparseable' } | ConvertTo-Json -Depth 6 }
    exit 1
}

$environments = @(Get-OptionalProperty $manifest 'environments' @())
if ($environments.Count -eq 0) {
    Write-Line 'ERROR: the manifest declares no environments.'
    if ($Json) { [pscustomobject]@{ mode = $mode; status = 'failed'; reason = 'no environments' } | ConvertTo-Json -Depth 6 }
    exit 1
}

# --- Wire-truth precondition: gh on PATH and a credential that reads the repo.
# --- Environments need admin to WRITE; a read-only credential still produces a useful
# --- dry run, so a missing one is an owner action rather than a hard failure.
$script:gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $script:gh) {
    Write-Line 'gh is not on PATH, so nothing could be compared against the live repository.'
    Add-OwnerAction 'install the GitHub CLI (https://cli.github.com), then re-run this script'
    $script:precondition = $true
}

$owner = $Repository.Split('/')[0]

# A reviewer must resolve to an id BEFORE anything is written. A PUT carrying a partial
# list silently drops the reviewers it could not resolve, so an unresolved one stops that
# environment rather than shrinking its gate.
function Resolve-Reviewer {
    param([Parameter(Mandatory)]$Reviewer)
    $type = [string](Get-OptionalProperty $Reviewer 'type' '')
    $name = [string](Get-OptionalProperty $Reviewer 'name' '')
    if (-not $script:gh) { return [pscustomobject]@{ Ok = $false; Reason = 'gh unavailable'; Type = $type; Name = $name } }
    if ($type -eq 'User') {
        $reply = Invoke-GhApi -GhArgs @("users/$name")
        $id = Get-OptionalProperty $reply.Json 'id' $null
        if ($reply.ExitCode -eq 0 -and $id) {
            return [pscustomobject]@{ Ok = $true; Type = $type; Name = $name; Id = [int]$id }
        }
        return [pscustomobject]@{ Ok = $false; Reason = "no such user (HTTP $($reply.HttpStatus))"; Type = $type; Name = $name }
    }
    $reply = Invoke-GhApi -GhArgs @("orgs/$owner/teams/$name")
    $id = Get-OptionalProperty $reply.Json 'id' $null
    if ($reply.ExitCode -eq 0 -and $id) {
        return [pscustomobject]@{ Ok = $true; Type = $type; Name = $name; Id = [int]$id }
    }
    # A user-owned repository has no teams at all; say which it is rather than "not found".
    $reason = if ($reply.HttpStatus -eq 404) {
        "no team '$name' under $owner (a user account has no teams; use a User reviewer)"
    } else { "team lookup failed (HTTP $($reply.HttpStatus))" }
    return [pscustomobject]@{ Ok = $false; Reason = $reason; Type = $type; Name = $name }
}

function Get-BranchPolicyShape {
    # The comparable shape of a branch policy: GitHub echoes extra keys, and null and
    # "every branch may deploy" are the same state said two ways.
    param($Policy)
    if ($null -eq $Policy) { return 'any-branch' }
    $protected = Get-OptionalProperty $Policy 'protected_branches' $false
    $custom = Get-OptionalProperty $Policy 'custom_branch_policies' $null
    if ($null -eq $custom) { $custom = Get-OptionalProperty $Policy 'custom_branches' $null }
    if ($protected -eq $true) { return 'protected-branches' }
    if ($custom) { return 'custom-branches' }
    return 'any-branch'
}

$failed = $false

foreach ($env in $environments) {
    $name = [string](Get-OptionalProperty $env 'name' '')
    $because = [string](Get-OptionalProperty $env 'because' '')
    $waitTimer = [int](Get-OptionalProperty $env 'wait_timer' 0)
    $preventSelf = [bool](Get-OptionalProperty $env 'prevent_self_review' $false)
    $reviewers = @(Get-OptionalProperty $env 'reviewers' @())
    $policy = Get-OptionalProperty $env 'deployment_branch_policy' $null

    Write-Line ''
    Write-Line "-- $name --"
    if ($because) { Write-Line "   why: $because" }

    # An environment with no reviewer gates nothing. That is a valid, deliberate state, but
    # it is never the state a reader assumes from the word "protected", so it is said aloud.
    if ($reviewers.Count -eq 0) {
        Write-Line '   NOTE: no reviewers are declared, so this environment holds nothing back.'
    }

    $resolved = @()
    $unresolved = @()
    foreach ($r in $reviewers) {
        $answer = Resolve-Reviewer -Reviewer $r
        if ($answer.Ok) { $resolved += $answer } else { $unresolved += $answer }
    }
    foreach ($u in $unresolved) {
        Write-Line "   reviewer unresolved: $($u.Type) '$($u.Name)' — $($u.Reason)"
        Add-OwnerAction "resolve the reviewer $($u.Type) '$($u.Name)' for environment '$name' (edit config/github/environments.json, or grant this credential access), then re-run this script"
        $script:precondition = $true
    }

    $live = $null
    if ($script:gh) {
        $reply = Invoke-GhApi -GhArgs @("repos/$Repository/environments/$name")
        if ($reply.ExitCode -eq 0) { $live = $reply.Json }
        elseif ($reply.HttpStatus -eq 404) { Write-Line '   live: absent (the workflow that names it would create it UNPROTECTED)' }
        elseif ($reply.HttpStatus -eq 403) {
            Write-Line '   live: cannot read (403) — this credential is not an administrator of the repository'
            Add-OwnerAction "run this script with an administrator credential: gh auth login, then pwsh scripts/github/apply-environments.ps1 -Apply"
            $script:precondition = $true
        }
        else {
            Write-Line "   live: lookup failed (HTTP $($reply.HttpStatus))"
            $failed = $true
        }
    }

    $inSync = $false
    if ($live) {
        $liveWait = 0
        $liveReviewerIds = @()
        foreach ($rule in @(Get-OptionalProperty $live 'protection_rules' @())) {
            switch ([string](Get-OptionalProperty $rule 'type' '')) {
                'wait_timer' { $liveWait = [int](Get-OptionalProperty $rule 'wait_timer' 0) }
                'required_reviewers' {
                    foreach ($rr in @(Get-OptionalProperty $rule 'reviewers' @())) {
                        $id = Get-OptionalProperty (Get-OptionalProperty $rr 'reviewer' $null) 'id' $null
                        if ($id) { $liveReviewerIds += [int]$id }
                    }
                }
            }
        }
        $wantIds = @($resolved | ForEach-Object { $_.Id })
        $sameReviewers = (@($liveReviewerIds | Sort-Object) -join ',') -eq (@($wantIds | Sort-Object) -join ',')
        $samePolicy = (Get-BranchPolicyShape (Get-OptionalProperty $live 'deployment_branch_policy' $null)) -eq (Get-BranchPolicyShape $policy)
        $inSync = ($liveWait -eq $waitTimer) -and $sameReviewers -and $samePolicy -and $unresolved.Count -eq 0
        Write-Line "   live: wait_timer=$liveWait reviewers=$($liveReviewerIds.Count) branch-policy=$(Get-BranchPolicyShape (Get-OptionalProperty $live 'deployment_branch_policy' $null))"
    }

    Write-Line "   want: wait_timer=$waitTimer reviewers=$($resolved.Count) branch-policy=$(Get-BranchPolicyShape $policy) prevent_self_review=$preventSelf"

    if ($inSync) {
        Write-Line '   in sync; no call made.'
        $results.Add([pscustomobject]@{ name = $name; state = 'in-sync' }) | Out-Null
        continue
    }

    if ($unresolved.Count -gt 0) {
        Write-Line '   SKIPPED: a reviewer could not be resolved, and a partial write would shrink the gate.'
        $results.Add([pscustomobject]@{ name = $name; state = 'blocked' }) | Out-Null
        continue
    }

    $bodyArgs = @('--method', 'PUT', "repos/$Repository/environments/$name",
                  '-F', "wait_timer=$waitTimer", '-F', "prevent_self_review=$($preventSelf.ToString().ToLowerInvariant())")
    $replay = "$script:GhApiReplay --method PUT repos/$Repository/environments/$name -F wait_timer=$waitTimer -F prevent_self_review=$($preventSelf.ToString().ToLowerInvariant())"
    foreach ($r in $resolved) {
        $bodyArgs += @('-F', "reviewers[][type]=$($r.Type)", '-F', "reviewers[][id]=$($r.Id)")
        $replay += " -F 'reviewers[][type]=$($r.Type)' -F 'reviewers[][id]=$($r.Id)'"
    }

    if (-not $Apply) {
        Write-Line "   would run: $replay"
        if ($policy) {
            Write-Line '   (the deployment branch policy is a second call; -Apply prints and makes both)'
        }
        $results.Add([pscustomobject]@{ name = $name; state = 'would-change' }) | Out-Null
        continue
    }

    $reply = Invoke-GhApi -GhArgs $bodyArgs -Mutating
    if ($reply.ExitCode -eq 0) {
        Write-Line '   applied.'
        $results.Add([pscustomobject]@{ name = $name; state = 'applied' }) | Out-Null
    }
    else {
        Write-Line "   FAILED (HTTP $($reply.HttpStatus)): $([string](Get-OptionalProperty $reply.Json 'message' 'no message'))"
        $results.Add([pscustomobject]@{ name = $name; state = 'failed' }) | Out-Null
        if ($reply.HttpStatus -eq 403 -or $reply.HttpStatus -eq 404) {
            Add-OwnerAction "grant an administrator credential and re-run: pwsh scripts/github/apply-environments.ps1 -Apply"
            $script:precondition = $true
        }
        else { $failed = $true }
    }

    # Names only, never values: the owner sets these, and this script never reads one.
    foreach ($secret in @(Get-OptionalProperty $env 'secretNames' @())) {
        Add-OwnerAction "gh secret set $secret --env $name --repo $Repository   # value entered at the prompt; never stored in this repository"
    }
    foreach ($variable in @(Get-OptionalProperty $env 'variableNames' @())) {
        Add-OwnerAction "gh variable set $variable --env $name --repo $Repository   # or confirm the repository-level variable already covers it"
    }
}

Write-Line ''
if ($ownerActions.Count -gt 0) {
    Write-Line '== what is left for you =='
    $n = 0
    foreach ($action in $ownerActions) { $n++; Write-Line "  $n. $action" }
}
# "Nothing left for you" is a claim about the REPOSITORY, and it used to be printed whenever
# the owner-action list happened to be empty - so a dry run that had just reported an absent
# environment and printed the PUT it would make signed off with "every environment matches".
# The pending set is its own question, and is answered separately.
$pendingCount = @($results | Where-Object { $_.state -eq 'would-change' }).Count
if ($pendingCount -gt 0) {
    Write-Line "$pendingCount environment(s) would change. Nothing was changed: re-run with -Apply to make the call(s) above."
}
elseif ($ownerActions.Count -eq 0) {
    Write-Line 'Nothing left for you: every environment in the manifest matches the repository.'
}

if ($Json) {
    [pscustomobject]@{
        mode         = $mode
        repository   = $Repository
        environments = $results
        ownerActions = @($ownerActions)
    } | ConvertTo-Json -Depth 6
}

if ($failed) { exit 1 }
if ($script:precondition) { exit 2 }
exit 0
