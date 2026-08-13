<#
.SYNOPSIS
    Adds the epic issues (#14-#53 of Yolkster64/helios-platform) to the ProjectV2 board - REAL GraphQL mutations
.DESCRIPTION
    This script really calls the GitHub GraphQL API (unlike the setup-views/templates/
    automation siblings, which are local simulations because the ProjectV2 API cannot
    create those objects). It:

      1. resolves the ProjectV2 by owner login + project number, including its
         single-select fields and their options
      2. pages through the project's existing items (100/page) TO COMPLETION to
         learn what is already on the board; if the inventory cannot be completed
         (100-page runaway ceiling hit with more pages remaining) it aborts with
         exit 1 before any mutation - an incomplete presence check would let step 5
         overwrite fields on items that were already on the board
      3. resolves the issue node IDs for the epic issue range with one aliased query
         against the repository (missing issue numbers are tolerated and reported)
      4. adds each epic that is not already on the board via addProjectV2ItemById
      5. stamps Status and Priority on the NEWLY ADDED items via
         updateProjectV2ItemFieldValue - only where those single-select fields and the
         requested options actually exist on the project (otherwise it reports the skip)

    Idempotent: items already on the board are detected up front and skipped, and
    addProjectV2ItemById itself returns the existing item id when the content is already
    present, so re-runs never duplicate. Items that were already on the board are left
    untouched (their Status/Priority is not overwritten), so a re-run is a no-op.

    Degrades gracefully without credentials: if no token is available (-GitHubToken empty
    and the GITHUB_TOKEN environment variable unset), it prints exactly which GraphQL
    operations it would run under a "NO TOKEN - DRY-RUN" banner and exits 0. Token values
    are never printed.
.PARAMETER GitHubToken
    GitHub Personal Access Token (classic, 'project' scope plus repo read for issue
    lookups). Defaults to the GITHUB_TOKEN environment variable. Never printed.
.PARAMETER ProjectNumber
    ProjectV2 number that carries the board (default 1)
.PARAMETER OrganizationName
    Login of the project owner - organization or user account (default Yolkster64)
.PARAMETER RepositoryOwner
    Owner of the repository holding the epic issues (default Yolkster64)
.PARAMETER RepositoryName
    Repository holding the epic issues (default helios-platform)
.PARAMETER FirstIssue
    First epic issue number, inclusive (default 14)
.PARAMETER LastIssue
    Last epic issue number, inclusive (default 53)
.PARAMETER StatusValue
    Status single-select option to stamp on newly added items (default 'Todo')
.PARAMETER PriorityValue
    Priority single-select option to stamp on newly added items (default 'High')
.PARAMETER DryRun
    Perform the read-only queries and print the per-issue plan, but run NO mutations
.NOTES
    Exit codes (the contract):
      0 = every existing epic is on the board and field stamping succeeded where the
          fields exist; also -DryRun and the no-token dry-run
      1 = fatal: auth failure, project or repository not resolvable, or the
          existing-item inventory could not be completed (paging ceiling hit) -
          nothing is mutated in that case
      2 = partial: some issue numbers in the range do not exist, or some add/update
          mutations failed (details in the summary)
.EXAMPLE
    ./add-epics-to-board.ps1 -DryRun
.EXAMPLE
    ./add-epics-to-board.ps1 -ProjectNumber 1 -OrganizationName "Yolkster64"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter(Mandatory=$false)]
    [int]$ProjectNumber = 1,

    [Parameter(Mandatory=$false)]
    [string]$OrganizationName = 'Yolkster64',

    [Parameter(Mandatory=$false)]
    [string]$RepositoryOwner = 'Yolkster64',

    [Parameter(Mandatory=$false)]
    [string]$RepositoryName = 'helios-platform',

    [Parameter(Mandatory=$false)]
    [int]$FirstIssue = 14,

    [Parameter(Mandatory=$false)]
    [int]$LastIssue = 53,

    [Parameter(Mandatory=$false)]
    [string]$StatusValue = 'Todo',

    [Parameter(Mandatory=$false)]
    [string]$PriorityValue = 'High',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$graphQlEndpoint = 'https://api.github.com/graphql'

if ($LastIssue -lt $FirstIssue) {
    Write-Host ("Invalid issue range: -FirstIssue {0} is greater than -LastIssue {1}." -f $FirstIssue, $LastIssue) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- GraphQL text

$projectAndFieldsQuery = @'
query ($login: String!, $projectNum: Int!) {
  repositoryOwner(login: $login) {
    ... on ProjectV2Owner {
      projectV2(number: $projectNum) {
        id
        title
        fields(first: 100) {
          nodes {
            ... on ProjectV2FieldCommon { id name dataType }
            ... on ProjectV2SingleSelectField { options { id name } }
          }
        }
      }
    }
  }
}
'@

$itemsPageQuery = @'
query ($login: String!, $projectNum: Int!, $cursor: String) {
  repositoryOwner(login: $login) {
    ... on ProjectV2Owner {
      projectV2(number: $projectNum) {
        items(first: 100, after: $cursor) {
          totalCount
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            content {
              ... on Issue { id number }
              ... on PullRequest { id number }
            }
          }
        }
      }
    }
  }
}
'@

$addItemMutation = @'
mutation ($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
    item { id }
  }
}
'@

$updateFieldMutation = @'
mutation ($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $projectId
    itemId: $itemId
    fieldId: $fieldId
    value: { singleSelectOptionId: $optionId }
  }) {
    projectV2Item { id }
  }
}
'@

# One aliased query resolves every epic issue node id in a single round trip.
$issueSelections = for ($n = $FirstIssue; $n -le $LastIssue; $n++) {
    '    i{0}: issue(number: {0}) {{ id number title state }}' -f $n
}
$issuesQuery = @"
query (`$owner: String!, `$name: String!) {
  repository(owner: `$owner, name: `$name) {
    id
$($issueSelections -join "`n")
  }
}
"@

# ---------------------------------------------------------------- helpers

function Invoke-GitHubGraphQL {
    param(
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Variables = @{},
        # Return data even when the response carries NOT_FOUND errors (used for the
        # aliased issue lookup, where gaps in the number range are expected).
        [switch]$TolerateNotFound
    )

    $headers = @{
        'Authorization'         = "bearer $GitHubToken"
        'Content-Type'          = 'application/json'
        'X-Github-Api-Version'  = '2022-11-28'
    }
    $body = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $graphQlEndpoint -Method Post `
                -Headers $headers -Body $body -TimeoutSec 60

            if ($response.PSObject.Properties['errors'] -and $response.errors) {
                $errors = @($response.errors)
                $fatal = @($errors | Where-Object {
                    -not ($_.PSObject.Properties['type'] -and $_.type -eq 'NOT_FOUND')
                })
                if (-not $TolerateNotFound -or $fatal.Count -gt 0) {
                    $messages = @($errors | ForEach-Object { $_.message }) -join '; '
                    throw "GraphQL error: $messages"
                }
            }
            return $response.data
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            # Retry only what is retryable: 429 and 5xx. Both mutations used here are
            # idempotent (addProjectV2ItemById returns the existing item), so a retry
            # cannot double-create. A non-429 4xx is deterministic - fail immediately.
            $status = [int]$_.Exception.Response.StatusCode
            if (-not ($status -eq 429 -or $status -ge 500) -or $attempt -eq $maxAttempts) { throw }
            $delaySeconds = [math]::Pow(2, $attempt) * (0.5 + (Get-Random -Minimum 0.0 -Maximum 0.5))
            $retryAfter = $_.Exception.Response.Headers.RetryAfter
            if ($null -ne $retryAfter -and $null -ne $retryAfter.Delta) {
                $delaySeconds = [math]::Max($delaySeconds, $retryAfter.Delta.TotalSeconds)
            }
            Write-Host ("  HTTP {0} from {1} - retrying in {2:n1}s (attempt {3}/{4})" -f `
                $status, $graphQlEndpoint, $delaySeconds, $attempt, $maxAttempts)
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Resolve-SingleSelectOption {
    param(
        [Parameter(Mandatory)][array]$FieldNodes,
        [Parameter(Mandatory)][string]$FieldName,
        [Parameter(Mandatory)][string]$OptionName
    )

    $field = $FieldNodes | Where-Object {
        $null -ne $_ -and $_.PSObject.Properties['name'] -and $_.name -eq $FieldName -and
        $_.PSObject.Properties['options']
    } | Select-Object -First 1

    if ($null -eq $field) {
        return @{ found = $false
                  reason = ("single-select field '{0}' does not exist on the project" -f $FieldName) }
    }
    $option = @($field.options) | Where-Object { $_.name -eq $OptionName } | Select-Object -First 1
    if ($null -eq $option) {
        # Parentheses around the concatenation matter: -f binds tighter than +.
        return @{ found = $false
                  reason = (("field '{0}' exists but has no option named '{1}' " +
                      '(available: {2})') -f $FieldName, $OptionName,
                      ((@($field.options) | ForEach-Object { $_.name }) -join ', ')) }
    }
    return @{ found = $true; fieldId = $field.id; optionId = $option.id }
}

# ---------------------------------------------------------------- no-token dry-run

$hasToken = -not [string]::IsNullOrWhiteSpace($GitHubToken)

if (-not $hasToken) {
    Write-Host '============================================================'
    Write-Host ' NO TOKEN - DRY-RUN (no GitHub API calls will be made)'
    Write-Host '============================================================'
    Write-Host 'No token available: -GitHubToken was empty and the GITHUB_TOKEN'
    Write-Host 'environment variable is not set. Token values are never printed.'
    Write-Host ''
    Write-Host ("Would POST these GraphQL operations to {0}:" -f $graphQlEndpoint)
    Write-Host ("  1. query    repositoryOwner(login: '{0}') -> projectV2(number: {1})" -f $OrganizationName, $ProjectNumber)
    Write-Host '              -> id, title, fields(first: 100) incl. single-select options'
    Write-Host '  2. query    projectV2 items (paged, 100/page) -> item id + content (Issue/PR) id and number'
    Write-Host ("  3. query    repository(owner: '{0}', name: '{1}')" -f $RepositoryOwner, $RepositoryName)
    Write-Host ("              -> issue node ids for issues #{0}..#{1} (one aliased query)" -f $FirstIssue, $LastIssue)
    Write-Host '  4. mutation addProjectV2ItemById for each epic not already on the board'
    Write-Host '              (idempotent: adding an existing item returns the existing item id)'
    Write-Host '  5. mutation updateProjectV2ItemFieldValue on newly added items only:'
    Write-Host ("              Status -> '{0}', Priority -> '{1}' (only where those single-select" -f $StatusValue, $PriorityValue)
    Write-Host '              fields and options exist on the project)'
    Write-Host ''
    Write-Host "To run for real: set GITHUB_TOKEN (classic PAT, 'project' scope + repo read) or pass"
    Write-Host '-GitHubToken. Add -DryRun to preview the per-issue plan (read-only, no mutations).'
    exit 0
}

# ---------------------------------------------------------------- read phase

try {
    $data = Invoke-GitHubGraphQL -Query $projectAndFieldsQuery -Variables @{
        login = $OrganizationName
        projectNum = $ProjectNumber
    }
}
catch {
    Write-Host ("Failed to resolve the project: {0}" -f $_) -ForegroundColor Red
    exit 1
}

$project = $null
if ($null -ne $data -and $data.PSObject.Properties['repositoryOwner'] -and $null -ne $data.repositoryOwner) {
    $repoOwnerNode = $data.repositoryOwner
    if ($repoOwnerNode.PSObject.Properties['projectV2']) { $project = $repoOwnerNode.projectV2 }
}
if ($null -eq $project) {
    Write-Host ("Project #{0} not found for owner '{1}' " -f $ProjectNumber, $OrganizationName) -ForegroundColor Red
    Write-Host '(check the owner login, the project number, and the token scopes).'
    exit 1
}
$projectId = $project.id
$fieldNodes = @($project.fields.nodes | Where-Object { $null -ne $_ })

# Existing items: content node id -> project item id, paged to COMPLETION. The
# presence check must be exhaustive: addProjectV2ItemById returns the EXISTING
# item when the content is already on the board, so an epic missed by an
# incomplete inventory would be "re-added" and then have its Status/Priority
# overwritten by the field stamping below - violating the documented promise
# that items already on the board are left untouched. $maxItemPages is a
# runaway guard, not a sampling cap: hitting it (or pageInfo still reporting
# more) aborts BEFORE any mutation.
$existingItems = @{}
$cursor = $null
$itemsTotal = 0
$maxItemPages = 100
$inventoryComplete = $false
for ($page = 1; $page -le $maxItemPages; $page++) {
    try {
        $pageData = Invoke-GitHubGraphQL -Query $itemsPageQuery -Variables @{
            login = $OrganizationName
            projectNum = $ProjectNumber
            cursor = $cursor
        }
        $itemsConn = $pageData.repositoryOwner.projectV2.items
    }
    catch {
        Write-Host ("Failed to read project items (page {0}): {1}" -f $page, $_) -ForegroundColor Red
        exit 1
    }
    $itemsTotal = $itemsConn.totalCount
    foreach ($node in @($itemsConn.nodes)) {
        if ($null -eq $node) { continue }
        $content = if ($node.PSObject.Properties['content']) { $node.content } else { $null }
        if ($null -ne $content -and $content.PSObject.Properties['id'] -and $content.id) {
            $existingItems[[string]$content.id] = [string]$node.id
        }
    }
    if (-not $itemsConn.pageInfo.hasNextPage) {
        $inventoryComplete = $true
        break
    }
    $cursor = $itemsConn.pageInfo.endCursor
}
if (-not $inventoryComplete) {
    # Parentheses around the concatenation matter: -f binds tighter than +.
    Write-Host (("ABORT: the project still reported more items after {0} pages ({1} items); " +
        'the already-on-board presence check is incomplete. Mutating on an incomplete ' +
        'inventory could overwrite Status/Priority on items already on the board ' +
        '(addProjectV2ItemById returns the existing item), so NO mutations were run.') -f
        $maxItemPages, ($maxItemPages * 100)) -ForegroundColor Red
    exit 1
}

# Epic issue node ids (gaps in the range tolerated, reported below).
try {
    $issueData = Invoke-GitHubGraphQL -Query $issuesQuery -Variables @{
        owner = $RepositoryOwner
        name = $RepositoryName
    } -TolerateNotFound
}
catch {
    Write-Host ("Failed to resolve the epic issues: {0}" -f $_) -ForegroundColor Red
    exit 1
}
$repository = $null
if ($null -ne $issueData -and $issueData.PSObject.Properties['repository']) { $repository = $issueData.repository }
if ($null -eq $repository) {
    Write-Host ("Repository {0}/{1} not found (or token lacks read access)." -f $RepositoryOwner, $RepositoryName) -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- build the plan

$plan = [System.Collections.Generic.List[object]]::new()
$notFound = [System.Collections.Generic.List[int]]::new()
for ($n = $FirstIssue; $n -le $LastIssue; $n++) {
    $alias = "i$n"
    $issue = $null
    if ($repository.PSObject.Properties[$alias]) { $issue = $repository.$alias }
    if ($null -eq $issue) {
        $notFound.Add($n)
        continue
    }
    $contentId = [string]$issue.id
    $plan.Add([pscustomobject]@{
        Number    = $n
        Title     = [string]$issue.title
        ContentId = $contentId
        ItemId    = if ($existingItems.ContainsKey($contentId)) { $existingItems[$contentId] } else { $null }
    })
}
$toAdd = @($plan | Where-Object { $null -eq $_.ItemId })
$alreadyPresent = @($plan | Where-Object { $null -ne $_.ItemId })

$statusTarget = Resolve-SingleSelectOption -FieldNodes $fieldNodes -FieldName 'Status' -OptionName $StatusValue
$priorityTarget = Resolve-SingleSelectOption -FieldNodes $fieldNodes -FieldName 'Priority' -OptionName $PriorityValue

Write-Host '============================================================'
Write-Host (" ADD EPICS TO BOARD{0}" -f $(if ($DryRun) { ' - PLAN (dry-run, no mutations)' } else { '' }))
Write-Host '============================================================'
Write-Host ("Project:  {0}  (owner: {1}, number: {2})" -f $project.title, $OrganizationName, $ProjectNumber)
Write-Host ("Epics:    {0}/{1} issues #{2}..#{3}" -f $RepositoryOwner, $RepositoryName, $FirstIssue, $LastIssue)
Write-Host ("Board:    {0} existing item(s)" -f $itemsTotal)
Write-Host ''
foreach ($entry in $plan) {
    if ($null -ne $entry.ItemId) {
        Write-Host ("  skip  #{0}  {1}  (already on board: {2})" -f $entry.Number, $entry.Title, $entry.ItemId)
    }
    else {
        Write-Host ("  add   #{0}  {1}" -f $entry.Number, $entry.Title)
    }
}
foreach ($n in $notFound) {
    Write-Host ("  warn  #{0}  issue not found in {1}/{2}" -f $n, $RepositoryOwner, $RepositoryName) -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'Field stamping for newly added items:'
foreach ($pair in @(
        @{ Name = 'Status'; Value = $StatusValue; Target = $statusTarget },
        @{ Name = 'Priority'; Value = $PriorityValue; Target = $priorityTarget })) {
    if ($pair.Target.found) {
        Write-Host ("  {0} -> '{1}'" -f $pair.Name, $pair.Value)
    }
    else {
        Write-Host ("  {0} -> SKIPPED: {1}" -f $pair.Name, $pair.Target.reason) -ForegroundColor Yellow
    }
}
Write-Host ''
Write-Host ("Plan: {0} to add, {1} already on board, {2} not found." -f $toAdd.Count, $alreadyPresent.Count, $notFound.Count)

if ($DryRun) {
    Write-Host 'DRY RUN - no mutations were executed.' -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------- mutation phase

$added = 0
$addFailed = 0
$fieldUpdated = 0
$fieldFailed = 0
$fieldSkipped = 0

foreach ($entry in $toAdd) {
    try {
        $addData = Invoke-GitHubGraphQL -Query $addItemMutation -Variables @{
            projectId = $projectId
            contentId = $entry.ContentId
        }
        $itemId = [string]$addData.addProjectV2ItemById.item.id
        $entry.ItemId = $itemId
        $added++
        Write-Host ("  added #{0} -> item {1}" -f $entry.Number, $itemId)
    }
    catch {
        $addFailed++
        Write-Host ("  FAILED to add #{0}: {1}" -f $entry.Number, $_) -ForegroundColor Red
        continue
    }
    Start-Sleep -Milliseconds 250   # be gentle with the mutation secondary rate limit

    foreach ($pair in @(
            @{ Name = 'Status'; Target = $statusTarget },
            @{ Name = 'Priority'; Target = $priorityTarget })) {
        if (-not $pair.Target.found) {
            $fieldSkipped++
            continue
        }
        try {
            Invoke-GitHubGraphQL -Query $updateFieldMutation -Variables @{
                projectId = $projectId
                itemId    = $entry.ItemId
                fieldId   = $pair.Target.fieldId
                optionId  = $pair.Target.optionId
            } | Out-Null
            $fieldUpdated++
        }
        catch {
            $fieldFailed++
            Write-Host ("  FAILED to set {0} on #{1}: {2}" -f $pair.Name, $entry.Number, $_) -ForegroundColor Red
        }
        Start-Sleep -Milliseconds 250
    }
}

Write-Host ''
Write-Host 'Summary:'
Write-Host ("  added:            {0}" -f $added)
Write-Host ("  already on board: {0} (left untouched)" -f $alreadyPresent.Count)
Write-Host ("  add failures:     {0}" -f $addFailed) -ForegroundColor $(if ($addFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host ("  issues not found: {0}{1}" -f $notFound.Count, $(if ($notFound.Count -gt 0) { ' (#' + ($notFound -join ', #') + ')' } else { '' })) `
    -ForegroundColor $(if ($notFound.Count -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ("  field updates:    {0} succeeded, {1} failed, {2} skipped (field/option missing)" -f $fieldUpdated, $fieldFailed, $fieldSkipped)

if (($addFailed + $fieldFailed) -gt 0 -or $notFound.Count -gt 0) {
    Write-Host 'PARTIAL: some operations did not complete (see summary above).' -ForegroundColor Yellow
    exit 2
}
Write-Host 'DONE: all epics are on the board.' -ForegroundColor Green
exit 0
