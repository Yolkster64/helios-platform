#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Refuses a deployment when the environment it would run in has no human in the path.

.DESCRIPTION
    CLAUDE.md: "GitHub protected environments remain deployment authority."
    `.github/workflows/helios-deploy.yml` names `production` on the job that runs
    `az deployment group create`, which makes that sentence true of the YAML. It does not
    make it true of the repository: naming an environment GitHub does not have CREATES one,
    with no protection rules at all, so the gate reads as present and holds nothing back.
    `apply-environments.ps1` is how the rules get there - but it needs a credential with
    repository administration, and until the owner installs the HELIOS GitHub App or stores a
    PAT, `governance-apply.yml` correctly withholds `-Apply` and the environment stays absent.

    This script closes that window. It runs BEFORE the deploy job, in a job that does not
    name the environment (a verifier must not create what it verifies), and asks the one
    question that matters: does this environment require a reviewer? If it cannot answer YES
    it exits 1 and the deployment never starts.

    It fails CLOSED. Absent, no protection rules, a rule with an empty reviewer list, a
    credential that cannot read the environment, a 500 from GitHub - all refuse. That is the
    opposite of the dry-run scripts in this directory, which treat an unreadable state as
    unknown and exit 0 so one transient error cannot red a pull request. The trade goes the
    other way here: this is the last thing between a push and the tenant, and "I could not
    check" is not a reason to proceed.

    A wait timer is not a human. An environment whose only rule is `wait_timer` delays the
    deployment and then runs it unattended, so it is refused with that said out loud.

.PARAMETER Repository
    owner/repo to read. Defaults to Yolkster64/helios-platform.

.PARAMETER EnvironmentName
    The environment the deploy job names. Defaults to production.

.PARAMETER Json
    Emit one JSON verdict object on stdout instead of the human lines.

.EXAMPLE
    pwsh scripts/github/verify-environment-gate.ps1 -Repository Yolkster64/helios-platform

.NOTES
    Exit codes: 0 = a reviewer is required, so a human approves this deployment;
    1 = anything else, including "could not tell".

    There is deliberately no exit 2. Every other script in this directory reserves 2 for a
    missing precondition so `governance-run.yml` can report it without failing the run. A
    missing precondition HERE - no gh, no credential, no answer - is exactly the case that
    must stop the deployment, so it collapses into 1.
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$EnvironmentName = 'production',
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

# The one repair line, printed with every refusal. It is the owner's step because writing
# environment protection rules needs repository administration, which no workflow token has.
$repair = @(
    'Apply the environment manifest, then re-run:',
    "  1. pwsh scripts/bootstrap/connect-github-app.ps1 -Repository $Repository -DispatchGovernance",
    '     (from your own machine: one Create click, one Install click, then it re-dispatches',
    '      Governance Apply, which applies config/github/environments.json from main)',
    '  2. or, with an administrator credential in this shell:',
    '     pwsh scripts/github/apply-environments.ps1 -Apply',
    "  3. or, by hand: Settings -> Environments -> $EnvironmentName -> Required reviewers"
) -join "`n"

function Deny {
    # -Repair, because the manifest is not the answer to every refusal: a host with no gh, or
    # a credential that cannot read the environment, is not fixed by applying protection rules
    # that may already be there. Printing the wrong repair confidently is its own defect.
    param(
        [Parameter(Mandatory)][string]$Reason,
        [string]$State = 'refused',
        [string]$Repair = $repair
    )
    Write-Line "REFUSED: $Reason"
    Write-Line ''
    Write-Line 'This job exists so a deployment cannot reach the tenant with nobody approving it.'
    Write-Line $Repair
    if ($Json) {
        [pscustomobject]@{
            repository  = $Repository
            environment = $EnvironmentName
            verdict     = 'refused'
            state       = $State
            reason      = $Reason
        } | ConvertTo-Json -Depth 6
    }
    exit 1
}

Write-Line "verify-environment-gate: repository=$Repository environment=$EnvironmentName"

$script:gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $script:gh) {
    # Not a warning. Without gh this script cannot tell a protected environment from an
    # unprotected one, and proceeding would mean deploying on the strength of an assumption.
    Deny -Reason 'gh is not on PATH, so the environment could not be read' -State 'unknown' `
         -Repair ('Install the GitHub CLI (https://cli.github.com) on this runner and re-run. ' +
                  'The environment may well be protected already - this refusal is about not ' +
                  'being able to check, not about a rule being missing.')
}

$reply = Invoke-GhApi -GhArgs @("repos/$Repository/environments/$EnvironmentName")

if ($reply.ExitCode -ne 0 -or $reply.HttpStatus -ne 200) {
    switch ($reply.HttpStatus) {
        404 {
            # GitHub answers 404 both for "no such environment" and for "this token may not
            # see it", and the repair differs, so the refusal names both readings rather than
            # sending the owner to create something that is already there.
            Deny -State 'absent' -Reason (
                "environment '$EnvironmentName' does not exist, or this credential cannot see " +
                'it. The deploy job names it, and naming an environment GitHub does not have ' +
                'creates it with NO protection rules - so the gate would read as present in ' +
                'the YAML and hold nothing back')
        }
        403 {
            Deny -State 'unreadable' -Reason (
                "this credential cannot read environment '$EnvironmentName' (HTTP 403), so " +
                'whether a human approves this deployment is unknown') `
                -Repair ('Grant this job a credential that can read the environment, then ' +
                         're-run. Applying the manifest will not help: the rules may already ' +
                         'be in place and unreadable from here.')
        }
        default {
            Deny -State 'unreadable' -Reason (
                "environment '$EnvironmentName' could not be read (HTTP $($reply.HttpStatus)). " +
                'This check fails closed: "I could not tell" is not a reason to deploy')
        }
    }
}

# The rules, as GitHub reports them. Only one of them puts a person in the path.
$reviewerCount = 0
$preventSelfReview = $false
$hasReviewerRule = $false
$waitTimer = 0
foreach ($rule in @(Get-OptionalProperty $reply.Json 'protection_rules' @())) {
    switch ([string](Get-OptionalProperty $rule 'type' '')) {
        'wait_timer' { $waitTimer = [int](Get-OptionalProperty $rule 'wait_timer' 0) }
        'required_reviewers' {
            $hasReviewerRule = $true
            $preventSelfReview = [bool](Get-OptionalProperty $rule 'prevent_self_review' $false)
            $reviewerCount = @(Get-OptionalProperty $rule 'reviewers' @()).Count
        }
    }
}

$policy = Get-OptionalProperty $reply.Json 'deployment_branch_policy' $null
$policyText = if ($null -eq $policy) { 'any-branch' }
    elseif ((Get-OptionalProperty $policy 'protected_branches' $false) -eq $true) { 'protected-branches' }
    elseif (Get-OptionalProperty $policy 'custom_branch_policies' $false) { 'custom-branches' }
    else { 'any-branch' }

Write-Line "   live: reviewers=$reviewerCount wait_timer=$waitTimer prevent_self_review=$preventSelfReview branch-policy=$policyText"

if (-not $hasReviewerRule) {
    Deny -State 'no-reviewer-rule' -Reason (
        "environment '$EnvironmentName' exists with no required_reviewers rule" +
        $(if ($waitTimer -gt 0) {
            ". Its only rule is a $waitTimer-minute wait timer, which delays the deployment " +
            'and then runs it unattended - a timer is not a human'
        } else { '' }))
}

if ($reviewerCount -eq 0) {
    # GitHub keeps the rule with an empty list when the last reviewer is removed, so this is
    # the state a UI edit leaves behind - and it approves everything.
    Deny -State 'no-reviewers' -Reason (
        "environment '$EnvironmentName' has a required_reviewers rule with an EMPTY reviewer " +
        'list, which approves every deployment automatically')
}

# From here the gate holds. Two things are still worth saying out loud rather than refusing:
# both weaken the gate, neither removes the human.
if (-not $preventSelfReview) {
    Write-Line ''
    Write-Line ("   WARNING: prevent_self_review is off, so whoever triggered this deployment " +
                'can approve it themselves. config/github/environments.json asks for it to be on;')
    Write-Line '            pwsh scripts/github/apply-environments.ps1 -Apply restores it.'
}
if ($policyText -eq 'any-branch') {
    Write-Line ''
    Write-Line ('   WARNING: this environment admits deployments from any branch. The deploy job ' +
                "is pinned to main in the workflow, so nothing reaches the tenant from elsewhere,")
    Write-Line '            but the environment itself is not the thing enforcing that.'
}

Write-Line ''
Write-Line "OK: $reviewerCount reviewer(s) must approve a deployment to '$EnvironmentName'."

if ($Json) {
    [pscustomobject]@{
        repository        = $Repository
        environment       = $EnvironmentName
        verdict           = 'allowed'
        reviewers         = $reviewerCount
        waitTimerMinutes  = $waitTimer
        preventSelfReview = $preventSelfReview
        branchPolicy      = $policyText
    } | ConvertTo-Json -Depth 6
}

exit 0
