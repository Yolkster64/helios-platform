#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Reports which governed GitHub surfaces are actually IN FORCE, in one read-only pass.

.DESCRIPTION
    This repository has five reconcilers - apply-rulesets, apply-environments, apply-labels,
    apply-milestones and apply-repo-settings - and each reports its own slice honestly. What
    none of them answers is the question every recent change has run into: of everything this
    repository declares about itself, what is a CONTROL right now and what is still only a
    description?

    That question has a real cost when it goes unasked. `.github/rulesets/main.json` states
    that main takes changes only through a reviewed pull request with eight green contexts. It
    is not applied - creating a ruleset needs repository administration no workflow token has -
    so for months that file has read like a guarantee while enforcing nothing, and the gap only
    surfaced when a workflow turned out to be one bug away from pushing to main unreviewed.

    So this walks each manifest, asks the live repository whether the thing it declares exists,
    and prints one row per surface with the reconciler that owns it. It is deliberately NOT a
    drift checker: whether an existing label has the right colour is apply-labels' job, and
    duplicating that judgement here would create a second opinion to keep in sync. This answers
    presence, which is the part nobody currently owns.

    Every call is a GET. The script makes no mutating call at all, and its offline suite
    asserts that rather than assuming it.

.PARAMETER Repository
    owner/repo to inventory. Defaults to Yolkster64/helios-platform.

.PARAMETER ConfigDirectory
    Where the manifests live. Defaults to config/github.

.PARAMETER RulesetDirectory
    Where the ruleset JSON lives. Defaults to .github/rulesets.

.PARAMETER Json
    Emit one JSON object on stdout instead of the table.

.NOTES
    Exit codes:
      0 = every surface this repository declares is in force
      2 = the inventory ran and at least one surface is absent, partial or unreadable
          (each named) - the ordinary state until the owner installs the App or stores a PAT
      1 = the inventory could not run at all: no gh on PATH, or the repository itself
          unreadable. A report nobody can trust is worse than no report, so this is separate
          from 2 rather than folded into it.

    The `gh api` wire layer below is kept in copy-sync with the other scripts/github/*.ps1
    (see apply-rulesets.ps1 .NOTES): GitHubIntegration.psm1 is legacy simulation code and is
    deliberately not a shared home.
#>
[CmdletBinding()]
param(
    [string]$Repository = 'Yolkster64/helios-platform',
    [string]$ConfigDirectory,
    [string]$RulesetDirectory,
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

function Write-Line { param([string]$Text = '') if (-not $Json) { Write-Host $Text } }

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

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $ConfigDirectory) { $ConfigDirectory = Join-Path $repoRoot 'config' 'github' }
if (-not $RulesetDirectory) { $RulesetDirectory = Join-Path $repoRoot '.github' 'rulesets' }

$rows = [System.Collections.Generic.List[object]]::new()
function Add-Row {
    param(
        [Parameter(Mandatory)][string]$Surface,
        [Parameter(Mandatory)][string]$State,
        [Parameter(Mandatory)][string]$Detail,
        [Parameter(Mandatory)][string]$Owner
    )
    $rows.Add([pscustomobject]@{ surface = $Surface; state = $State; detail = $Detail; owner = $Owner }) | Out-Null
}

function Read-Manifest {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { return $null }
    return @(Get-OptionalProperty $doc $Key @())
}

# `unknown` is a first-class answer here. An inventory that reports a 403 as "absent" would
# tell the owner to create something that already exists.
function Get-LiveList {
    param([Parameter(Mandatory)][string]$Endpoint, [string]$Key)
    $reply = Invoke-GhApi -GhArgs @($Endpoint)
    if ($reply.ExitCode -ne 0 -or $null -eq $reply.Json) {
        return [pscustomobject]@{ Ok = $false; Status = $reply.HttpStatus; Items = @() }
    }
    $items = if ($Key) { @(Get-OptionalProperty $reply.Json $Key @()) } else { @($reply.Json) }
    return [pscustomobject]@{ Ok = $true; Status = $reply.HttpStatus; Items = $items }
}

function Compare-Declared {
    param(
        [Parameter(Mandatory)][string]$Surface,
        [Parameter(Mandatory)][string]$Owner,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Declared,
        [Parameter(Mandatory)]$Live,
        [Parameter(Mandatory)][string]$Endpoint
    )
    if ($Declared.Count -eq 0) {
        Add-Row -Surface $Surface -State 'none-declared' -Detail 'no manifest entries to compare' -Owner $Owner
        return
    }
    if (-not $Live.Ok) {
        Add-Row -Surface $Surface -State 'unknown' -Detail "could not read $Endpoint (HTTP $($Live.Status))" -Owner $Owner
        return
    }
    $missing = @($Declared | Where-Object { $_ -notin $Live.Names })
    if ($missing.Count -eq 0) {
        Add-Row -Surface $Surface -State 'in-force' -Detail "all $($Declared.Count) present" -Owner $Owner
    }
    elseif ($missing.Count -eq $Declared.Count) {
        Add-Row -Surface $Surface -State 'absent' -Detail "none of the $($Declared.Count) declared exist: $($missing -join ', ')" -Owner $Owner
    }
    else {
        Add-Row -Surface $Surface -State 'partial' -Detail "$($missing.Count) of $($Declared.Count) missing: $($missing -join ', ')" -Owner $Owner
    }
}

$script:gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $script:gh) {
    if ($Json) { [pscustomobject]@{ repository = $Repository; state = 'unavailable'; reason = 'gh is not on PATH'; surfaces = @() } | ConvertTo-Json -Depth 6 }
    else { Write-Host 'inventory-surfaces: gh is not on PATH, so nothing could be read.' }
    exit 1
}

$repo = Invoke-GhApi -GhArgs @("repos/$Repository")
if ($repo.ExitCode -ne 0 -or $null -eq $repo.Json) {
    if ($Json) { [pscustomobject]@{ repository = $Repository; state = 'unavailable'; reason = "repository unreadable (HTTP $($repo.HttpStatus))"; surfaces = @() } | ConvertTo-Json -Depth 6 }
    else { Write-Host "inventory-surfaces: $Repository could not be read (HTTP $($repo.HttpStatus)); nothing to report." }
    exit 1
}

Write-Line "inventory-surfaces: repository=$Repository"
Write-Line ''

# --- rulesets -------------------------------------------------------------------------
# Repository rulesets only. GET /rulesets also lists ORG rulesets, which this repository
# does not own and cannot be asked to create - counting one as ours would report a control
# that nobody here can reconcile.
$declaredRulesets = @()
if (Test-Path -LiteralPath $RulesetDirectory -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $RulesetDirectory -Filter '*.json' -File) {
        try { $doc = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json } catch { continue }
        $name = [string](Get-OptionalProperty $doc 'name' '')
        if ($name) { $declaredRulesets += $name }
    }
}
$liveRulesets = Get-LiveList -Endpoint "repos/$Repository/rulesets?per_page=100"
$liveRulesets | Add-Member -NotePropertyName Names -NotePropertyValue @(
    $liveRulesets.Items | Where-Object { [string](Get-OptionalProperty $_ 'source_type' 'Repository') -eq 'Repository' } |
        ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') }
)
Compare-Declared -Surface 'rulesets' -Owner 'apply-rulesets.ps1' -Declared $declaredRulesets `
    -Live $liveRulesets -Endpoint 'rulesets'

# --- environments ---------------------------------------------------------------------
$declaredEnvironments = @(
    (Read-Manifest -Path (Join-Path $ConfigDirectory 'environments.json') -Key 'environments') |
        ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') } | Where-Object { $_ }
)
$liveEnvironments = Get-LiveList -Endpoint "repos/$Repository/environments?per_page=100" -Key 'environments'
$liveEnvironments | Add-Member -NotePropertyName Names -NotePropertyValue @(
    $liveEnvironments.Items | ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') }
)
Compare-Declared -Surface 'environments' -Owner 'apply-environments.ps1' -Declared $declaredEnvironments `
    -Live $liveEnvironments -Endpoint 'environments'

# --- labels ---------------------------------------------------------------------------
$declaredLabels = @(
    (Read-Manifest -Path (Join-Path $ConfigDirectory 'labels.json') -Key 'labels') |
        ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') } | Where-Object { $_ }
)
$liveLabels = Get-LiveList -Endpoint "repos/$Repository/labels?per_page=100"
$liveLabels | Add-Member -NotePropertyName Names -NotePropertyValue @(
    $liveLabels.Items | ForEach-Object { [string](Get-OptionalProperty $_ 'name' '') }
)
Compare-Declared -Surface 'labels' -Owner 'apply-labels.ps1' -Declared $declaredLabels `
    -Live $liveLabels -Endpoint 'labels'

# --- milestones -----------------------------------------------------------------------
# state=all: a closed milestone still EXISTS, and reporting it absent would ask the owner to
# create a duplicate.
$declaredMilestones = @(
    (Read-Manifest -Path (Join-Path $ConfigDirectory 'milestones.json') -Key 'milestones') |
        ForEach-Object { [string](Get-OptionalProperty $_ 'title' '') } | Where-Object { $_ }
)
$liveMilestones = Get-LiveList -Endpoint "repos/$Repository/milestones?state=all&per_page=100"
$liveMilestones | Add-Member -NotePropertyName Names -NotePropertyValue @(
    $liveMilestones.Items | ForEach-Object { [string](Get-OptionalProperty $_ 'title' '') }
)
Compare-Declared -Surface 'milestones' -Owner 'apply-milestones.ps1' -Declared $declaredMilestones `
    -Live $liveMilestones -Endpoint 'milestones'

# --- scalar repository settings -------------------------------------------------------
# Read from the repository object already fetched: no second call, and no way for the two
# reads to disagree.
foreach ($setting in @(
    @{ Field = 'allow_auto_merge';        Label = 'settings:auto-merge' },
    @{ Field = 'has_wiki';                Label = 'settings:wiki' },
    @{ Field = 'delete_branch_on_merge';  Label = 'settings:delete-branch-on-merge' }
)) {
    $value = Get-OptionalProperty $repo.Json $setting.Field $null
    if ($null -eq $value) {
        Add-Row -Surface $setting.Label -State 'unknown' -Detail "the repository reply carries no $($setting.Field)" -Owner 'apply-repo-settings.ps1'
    }
    elseif ($value -eq $true) {
        Add-Row -Surface $setting.Label -State 'in-force' -Detail "$($setting.Field)=true" -Owner 'apply-repo-settings.ps1'
    }
    else {
        Add-Row -Surface $setting.Label -State 'absent' -Detail "$($setting.Field)=false" -Owner 'apply-repo-settings.ps1'
    }
}

# --- pages ----------------------------------------------------------------------------
# Its own call: Pages is not a field on the repository object. The 404 rule is
# apply-repo-settings.ps1's and is copied deliberately - only GitHub's own `"status":"404"`
# body means "no site". Any OTHER failed read (this proxy answers 403 on this endpoint, as
# that script measured) is unreadable, and reporting unreadable as absent would tell the
# owner to POST a site that already exists, which answers 409.
$pages = Invoke-GhApi -GhArgs @("repos/$Repository/pages")
if ($pages.ExitCode -eq 0 -and $null -ne $pages.Json) {
    $buildType = [string](Get-OptionalProperty $pages.Json 'build_type' '')
    if ($buildType -eq 'workflow') {
        Add-Row -Surface 'settings:pages' -State 'in-force' -Detail 'enabled, build_type=workflow' -Owner 'apply-repo-settings.ps1'
    }
    else {
        # Enabled, but deploying from somewhere other than the workflow that builds the
        # dashboard. The site exists, so this is not absence.
        Add-Row -Surface 'settings:pages' -State 'partial' `
            -Detail "enabled, but build_type=$(if ($buildType) { $buildType } else { 'unreported' }) rather than workflow" `
            -Owner 'apply-repo-settings.ps1'
    }
}
elseif ([string](Get-OptionalProperty $pages.Json 'status' '') -eq '404') {
    Add-Row -Surface 'settings:pages' -State 'absent' -Detail 'no Pages site' -Owner 'apply-repo-settings.ps1'
}
else {
    Add-Row -Surface 'settings:pages' -State 'unknown' -Detail "could not read pages (HTTP $($pages.HttpStatus))" -Owner 'apply-repo-settings.ps1'
}

# --- report ---------------------------------------------------------------------------
$notInForce = @($rows | Where-Object { $_.state -notin @('in-force', 'none-declared') })

if ($Json) {
    [pscustomobject]@{
        repository = $Repository
        state      = if ($notInForce.Count -eq 0) { 'all-in-force' } else { 'gaps' }
        gaps       = $notInForce.Count
        surfaces   = @($rows)
    } | ConvertTo-Json -Depth 6
}
else {
    $width = ($rows | ForEach-Object { $_.surface.Length } | Measure-Object -Maximum).Maximum
    foreach ($row in $rows) {
        Write-Line ("  {0}  {1,-13} {2}" -f $row.surface.PadRight($width), $row.state, $row.detail)
    }
    Write-Line ''
    if ($notInForce.Count -eq 0) {
        Write-Line 'Every surface this repository declares is in force.'
    }
    else {
        Write-Line "$($notInForce.Count) surface(s) are not in force:"
        foreach ($row in $notInForce) {
            Write-Line "  - $($row.surface): $($row.state) -> reconcile with $($row.owner)"
        }
        Write-Line ''
        Write-Line 'Rulesets and environments need a credential with repository administration,'
        Write-Line 'which no workflow token carries; see docs/architecture/CONNECTIONS_SETUP.md.'
    }
}

exit $(if ($notInForce.Count -eq 0) { 0 } else { 2 })
