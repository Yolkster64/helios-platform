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

    The allowed branch PATTERNS are compared too, from their own endpoint, because a custom
    policy allowing feature/* has the same shape in the environment body as one allowing
    only main. A pattern the manifest wants and the repository lacks is added under -Apply;
    one the repository allows and the manifest does not is reported for you to remove, since
    removing it is a DELETE and this script makes none.

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
    Exit codes: 0 = the run did what it could, which INCLUDES a dry run with pending changes
    and an apply that left follow-up notes (setting a variable, pasting a secret) - those are
    listed but do not change the code; 2 = a PRECONDITION is missing (no gh, no administrator
    credential); 1 = something failed, including a reviewer this manifest names that GitHub
    does not have.

    Exit 2 is deliberately narrow because .github/workflows/governance-run.yml reads exit 2
    from an admin item during -Apply as "this admin credential was rejected" and tells the
    owner to rotate a token. Only a genuine credential/precondition fault may say that.
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
    # "every branch may deploy" are the same state said two ways. This is the SHAPE only -
    # the branch patterns live on their own endpoint and are compared separately, because a
    # live policy allowing feature/* has the same shape as one allowing only main while
    # granting far more.
    param($Policy)
    if ($null -eq $Policy) { return 'any-branch' }
    $protected = Get-OptionalProperty $Policy 'protected_branches' $false
    $custom = Get-OptionalProperty $Policy 'custom_branch_policies' $null
    if ($null -eq $custom) { $custom = Get-OptionalProperty $Policy 'custom_branches' $null }
    if ($protected -eq $true) { return 'protected-branches' }
    if ($custom) { return 'custom-branches' }
    return 'any-branch'
}

function Get-WantedBranchPatterns {
    # The manifest's friendly key. GitHub's own body carries only the two booleans; the
    # PATTERNS are a separate endpoint, which is why this translation has to exist rather
    # than the manifest key being passed through.
    param($Policy)
    if ($null -eq $Policy) { return @() }
    return @(Get-OptionalProperty $Policy 'custom_branches' @())
}

function Get-LiveBranchPatterns {
    # GET .../environments/{env}/deployment-branch-policies -> the names actually allowed.
    #
    # Returns @{ Ok; Patterns } rather than the array itself: PowerShell UNROLLS an empty
    # array returned from a function into $null, so `return @()` for "no patterns allowed"
    # is indistinguishable from `return $null` for "the read failed" - and those are opposite
    # verdicts. An environment with a custom policy and no patterns permits NOTHING; one that
    # could not be read permits we-do-not-know.
    param([Parameter(Mandatory)][string]$EnvName)
    if (-not $script:gh) { return @{ Ok = $false; Patterns = @() } }
    $reply = Invoke-GhApi -GhArgs @("repos/$Repository/environments/$EnvName/deployment-branch-policies")
    if ($reply.ExitCode -ne 0) { return @{ Ok = $false; Patterns = @() } }
    $names = @(@(Get-OptionalProperty $reply.Json 'branch_policies' @()) |
        ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') } | Where-Object { $_ })
    return @{ Ok = $true; Patterns = $names }
}

function ConvertTo-EnvironmentBody {
    # The PUT body as JSON. -F cannot express deployment_branch_policy, which is a nested
    # OBJECT requiring BOTH booleans - so the whole body goes through a file, the way
    # apply-rulesets.ps1 sends a ruleset. Sending it with the key omitted would leave a
    # hand-made policy in place; sending null clears it, which is what "any branch" means.
    param([int]$WaitTimer, [bool]$PreventSelfReview, $Resolved, $Policy)
    $body = [ordered]@{
        wait_timer          = $WaitTimer
        prevent_self_review = $PreventSelfReview
        reviewers           = @($Resolved | ForEach-Object { [ordered]@{ type = $_.Type; id = $_.Id } })
    }
    $shape = Get-BranchPolicyShape $Policy
    $body['deployment_branch_policy'] = switch ($shape) {
        'protected-branches' { [ordered]@{ protected_branches = $true;  custom_branch_policies = $false } }
        'custom-branches'    { [ordered]@{ protected_branches = $false; custom_branch_policies = $true  } }
        default              { $null }
    }
    return ($body | ConvertTo-Json -Depth 6 -Compress)
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
    $unreadable = $false
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
            # Not $failed: the siblings treat an unreadable live state as unknown and exit 0
            # (apply-rulesets warns, apply-repo-settings counts it), and run_item maps exit 1
            # to "FAILED (item failed)" which would red the whole governance workflow on every
            # pull request for one transient 5xx. It is reported and the environment is left
            # alone, because a PUT without a diff is a blind write.
            Write-Line "   live: could not be read (HTTP $($reply.HttpStatus)); leaving this environment alone"
            Add-OwnerAction "re-run when GitHub answers for environment '$name': pwsh scripts/github/apply-environments.ps1"
            $unreadable = $true
        }
    }

    $wantPatterns = @(Get-WantedBranchPatterns $policy)
    $extraPatterns = @()
    # Everything the manifest wants is missing until a live read says otherwise. Starting
    # this at @() meant an ABSENT environment - the only case that will ever run here for
    # real, since `production` does not exist yet - was created with custom_branch_policies
    # true and NO patterns: a policy that matches no branch, so every deployment would be
    # refused by the gate that was supposed to admit main.
    $missingPatterns = @($wantPatterns)
    $inSync = $false
    if ($live) {
        $liveWait = 0
        $liveReviewerIds = @()
        $livePreventSelf = $false
        foreach ($rule in @(Get-OptionalProperty $live 'protection_rules' @())) {
            switch ([string](Get-OptionalProperty $rule 'type' '')) {
                'wait_timer' { $liveWait = [int](Get-OptionalProperty $rule 'wait_timer' 0) }
                'required_reviewers' {
                    # prevent_self_review rides on this rule. It was sent but never compared,
                    # so the control the manifest's `because` specifically names could drift
                    # to false and this script would still print "in sync".
                    $livePreventSelf = [bool](Get-OptionalProperty $rule 'prevent_self_review' $false)
                    foreach ($rr in @(Get-OptionalProperty $rule 'reviewers' @())) {
                        $id = Get-OptionalProperty (Get-OptionalProperty $rr 'reviewer' $null) 'id' $null
                        if ($id) { $liveReviewerIds += [int]$id }
                    }
                }
            }
        }
        $wantIds = @($resolved | ForEach-Object { $_.Id })
        $sameReviewers = (@($liveReviewerIds | Sort-Object) -join ',') -eq (@($wantIds | Sort-Object) -join ',')
        $liveShape = Get-BranchPolicyShape (Get-OptionalProperty $live 'deployment_branch_policy' $null)
        $sameShape = $liveShape -eq (Get-BranchPolicyShape $policy)

        # The patterns, not just the shape: "custom branches" allowing feature/* has the same
        # shape as one allowing only main.
        # Two flags rather than one, because the two kinds of difference have opposite
        # owners. A MISSING pattern is this script's to add (a POST it makes under -Apply).
        # An EXTRA one WIDENS the gate and can only go away with a DELETE, which this script
        # never makes. Folding both into one "same patterns" boolean meant an extra pattern
        # printed the PUT - a call that cannot remove it - so -Apply reported `applied.` over
        # a gate that was still wide, and the next dry run printed the same useless PUT
        # again, forever. `$patternsKnown` is a third state: the read failed, which is not
        # "they differ" and not "they match".
        $patternsKnown = $true
        if ($liveShape -eq 'custom-branches' -or $wantPatterns.Count -gt 0) {
            $patternRead = Get-LiveBranchPatterns -EnvName $name
            if (-not $patternRead.Ok) {
                # Not knowing which patterns exist is not the same as knowing they are
                # missing. POSTing them blind would 422 on any that already exist, and
                # run_item turns that exit 1 into a red governance row - for one transient
                # read failure. The environment body is still written (a PUT is idempotent);
                # the patterns wait for a run that can see them.
                $patternsKnown = $false
                $missingPatterns = @()
                Write-Line '   branch patterns: could not be read; leaving the patterns alone this run'
            }
            else {
                $livePatterns = @($patternRead.Patterns)
                $missingPatterns = @($wantPatterns | Where-Object { $_ -notin $livePatterns })
                $extraPatterns = @($livePatterns | Where-Object { $_ -notin $wantPatterns })
                Write-Line "   branch patterns: live=[$($livePatterns -join ', ')] want=[$($wantPatterns -join ', ')]"
                foreach ($extra in $extraPatterns) {
                    # An extra pattern WIDENS the gate, so it is never left as "in sync" - but
                    # deleting is destructive, so it is the owner's call with the exact command.
                    Add-OwnerAction ("environment '$name' also allows deployments from '$extra', which the manifest does not: " +
                        "review it, then remove it with gh api --method DELETE repos/$Repository/environments/$name/deployment-branch-policies/<id>")
                }
            }
        }

        $inSync = ($liveWait -eq $waitTimer) -and $sameReviewers -and $sameShape -and $patternsKnown `
            -and $missingPatterns.Count -eq 0 -and ($livePreventSelf -eq $preventSelf) -and $unresolved.Count -eq 0
        Write-Line "   live: wait_timer=$liveWait reviewers=$($liveReviewerIds.Count) branch-policy=$liveShape prevent_self_review=$livePreventSelf"
    }

    Write-Line "   want: wait_timer=$waitTimer reviewers=$($resolved.Count) branch-policy=$(Get-BranchPolicyShape $policy) prevent_self_review=$preventSelf"

    if ($unreadable) {
        $results.Add([pscustomobject]@{ name = $name; state = 'unknown' }) | Out-Null
        continue
    }

    if ($inSync) {
        if ($extraPatterns.Count -gt 0) {
            # Everything this script owns matches; what is left is a DELETE it will not make.
            # Neither available word is true on its own here - "in sync" hides a gate wider
            # than the manifest, and "would change" promises a call that would not narrow it -
            # so the state says which it is and the removal is listed above as the owner's.
            Write-Line ("   in sync apart from $($extraPatterns.Count) branch pattern(s) only you can remove: " +
                ($extraPatterns -join ', '))
            $results.Add([pscustomobject]@{ name = $name; state = 'needs-owner' }) | Out-Null
            continue
        }
        Write-Line '   in sync; no call made.'
        $results.Add([pscustomobject]@{ name = $name; state = 'in-sync' }) | Out-Null
        continue
    }

    if ($unresolved.Count -gt 0) {
        # exit 1, not 2: a reviewer the manifest names and GitHub does not have is a fault in
        # THIS FILE, not a missing credential. governance-run.yml renders exit 2 from an admin
        # item as "your admin token was revoked - rotate it", which would send the owner
        # rotating a healthy token over a typo, or over a Team reviewer on a user-owned
        # account (which has no teams at all, so that lookup 404s by construction).
        Write-Line '   FAILED: a reviewer could not be resolved, and a partial write would shrink the gate.'
        $results.Add([pscustomobject]@{ name = $name; state = 'failed' }) | Out-Null
        $failed = $true
        continue
    }

    # Names only, never values: the owner sets these, and this script never reads one.
    # Listed BEFORE the write, so the dry run reports them too. They used to be added after
    # the PUT, which meant the preview showed one call and hid the five variables that go
    # with it - the owner only learned about them by running -Apply, which is the opposite
    # of what a dry run is for. An environment already in sync skips this block (it never
    # reaches here), so a clean run stays quiet.
    foreach ($secret in @(Get-OptionalProperty $env 'secretNames' @())) {
        Add-OwnerAction "gh secret set $secret --env $name --repo $Repository   # value entered at the prompt; never stored in this repository"
    }
    foreach ($variable in @(Get-OptionalProperty $env 'variableNames' @())) {
        Add-OwnerAction "gh variable set $variable --env $name --repo $Repository   # or confirm the repository-level variable already covers it"
    }

    $bodyJson = ConvertTo-EnvironmentBody -WaitTimer $waitTimer -PreventSelfReview $preventSelf `
        -Resolved $resolved -Policy $policy
    $replay = "$script:GhApiReplay --method PUT repos/$Repository/environments/$name --input - <<< '$bodyJson'"

    if (-not $Apply) {
        Write-Line "   would run: $replay"
        foreach ($pattern in $missingPatterns) {
            Write-Line ("   would run: $script:GhApiReplay --method POST " +
                "repos/$Repository/environments/$name/deployment-branch-policies -f name='$pattern'")
        }
        $results.Add([pscustomobject]@{ name = $name; state = 'would-change' }) | Out-Null
        continue
    }

    # --input, not -F: deployment_branch_policy is a nested object requiring BOTH booleans,
    # which -F cannot express. It was omitted entirely before, so custom_branches never
    # reached GitHub and the item could never converge - it reported "applied" and then
    # "would change" again on the very next run, forever.
    $bodyFile = (New-TemporaryFile).FullName
    try {
        Set-Content -LiteralPath $bodyFile -Value $bodyJson -Encoding utf8 -NoNewline
        $reply = Invoke-GhApi -GhArgs @('--method', 'PUT', "repos/$Repository/environments/$name",
                                        '--input', $bodyFile) -Mutating
    }
    finally { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }

    if ($reply.ExitCode -eq 0) {
        Write-Line '   applied.'
        # The patterns are their own endpoint; the PUT above only said WHICH KIND of policy.
        $patternFailed = $false
        foreach ($pattern in $missingPatterns) {
            $add = Invoke-GhApi -GhArgs @('--method', 'POST',
                "repos/$Repository/environments/$name/deployment-branch-policies",
                '-f', "name=$pattern") -Mutating
            if ($add.ExitCode -eq 0) { Write-Line "   branch pattern '$pattern' allowed." }
            else {
                Write-Line "   FAILED to add branch pattern '$pattern' (HTTP $($add.HttpStatus))"
                $patternFailed = $true
            }
        }
        if ($patternFailed) { $failed = $true }
        # `applied.` alone would claim the environment now matches the manifest. If a pattern
        # this script will not delete still allows deployments the manifest does not, it does
        # not - and re-running would say `applied.` again with nothing changed.
        if (-not $patternFailed -and $extraPatterns.Count -gt 0) {
            Write-Line ("   $($extraPatterns.Count) branch pattern(s) still allow deployments the manifest does not: " +
                ($extraPatterns -join ', ') + ' — removing one is a DELETE, listed for you above.')
        }
        $state = if ($patternFailed) { 'failed' } elseif ($extraPatterns.Count -gt 0) { 'needs-owner' } else { 'applied' }
        $results.Add([pscustomobject]@{ name = $name; state = $state }) | Out-Null
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
$ownerCount = @($results | Where-Object { $_.state -eq 'needs-owner' }).Count
if ($pendingCount -gt 0) {
    Write-Line "$pendingCount environment(s) would change. Nothing was changed: re-run with -Apply to make the call(s) above."
}
elseif ($ownerCount -gt 0) {
    # Otherwise this run would end on the owner list with no verdict at all: no pending call
    # to report and no clean sign-off to print, which reads as though the script forgot to say.
    Write-Line "$ownerCount environment(s) need a change only you can make (listed above); no call was made for them."
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
