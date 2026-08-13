<#
.SYNOPSIS
    Validates the HELIOS Platform board with a REAL ProjectV2 GraphQL read (fields + items)
.DESCRIPTION
    What is real vs simulated in this directory: setup-custom-fields.ps1 performs real
    GraphQL mutations, and THIS script performs a real read-only GraphQL query against
    https://api.github.com/graphql. The setup-views.ps1 / setup-templates.ps1 /
    setup-automation-rules.ps1 siblings are LOCAL SIMULATIONS because the ProjectV2
    GraphQL API cannot create views, item templates, or built-in workflows.

    This script:
      * resolves the ProjectV2 by owner login + project number (works for both user and
        organization owners via repositoryOwner { ... on ProjectV2Owner })
      * reads the project's fields (first 100) and items (first 100)
      * verifies the 25 expected custom fields (the exact list setup-custom-fields.ps1
        creates) exist on the project
      * reports field/item counts and names any missing fields

    What it deliberately does NOT validate (real API limitation, not a script choice):
    board views, phase templates, and built-in workflow/automation configuration are not
    creatable through the ProjectV2 GraphQL API and are configured manually in the GitHub
    UI - verify those by hand there.

    Degrades gracefully without credentials: if no token is available (-GitHubToken empty
    and the GITHUB_TOKEN environment variable unset), it prints exactly what it would
    query under a "NO TOKEN - DRY-RUN" banner and exits 0. Token values are never printed.
.PARAMETER GitHubToken
    GitHub Personal Access Token (classic, 'project' scope; read access suffices).
    Defaults to the GITHUB_TOKEN environment variable. Never printed.
.PARAMETER ProjectNumber
    Project number to validate
.PARAMETER OrganizationName
    Login of the project owner (organization or user account)
.PARAMETER GenerateReport
    Also write the validation result JSON to logs/validation-report_<timestamp>.json
.PARAMETER DryRun
    Print exactly what would be queried without calling the GitHub API, then exit 0
.NOTES
    Exit codes (the contract):
      0 = validation passed, or -DryRun / no-token dry-run
      1 = API/auth failure, or the project could not be resolved
      2 = query succeeded but one or more expected custom fields are missing
.EXAMPLE
    ./validate-board.ps1 -ProjectNumber 1 -OrganizationName "Yolkster64"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$GitHubToken = $env:GITHUB_TOKEN,

    [Parameter(Mandatory=$true)]
    [int]$ProjectNumber,

    [Parameter(Mandatory=$true)]
    [string]$OrganizationName,

    [switch]$GenerateReport,
    [switch]$DryRun
    # No explicit -Verbose switch: the [Parameter()] attributes make this an advanced
    # script, so the common -Verbose parameter already exists (an explicit one would
    # collide and make the script impossible to invoke).
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$reportFile = "logs/validation-report_$timestamp.json"
$graphQlEndpoint = 'https://api.github.com/graphql'

# The 25 custom fields setup-custom-fields.ps1 creates (keep the two lists in sync).
$expectedFields = @(
    'Priority', 'Sprint', 'Effort', 'Component', 'DueDate',
    'AssignedTo', 'ProgressStatus', 'QAStatus', 'BlockedBy', 'TimeEstimate',
    'ReviewStatus', 'ReviewedBy', 'ApprovalRequired', 'RiskLevel', 'ComplianceCheck',
    'DeploymentEnvironment', 'DeploymentStatus', 'IntegrationPoints', 'DependsOn', 'DataMigration',
    'SuccessMetrics', 'UserImpact', 'PerformanceImpact', 'Documentation', 'ArchitectureDecision'
)

# Single read-only query: project identity + fields + items.
$projectQuery = @'
query ($login: String!, $projectNum: Int!) {
  repositoryOwner(login: $login) {
    ... on ProjectV2Owner {
      projectV2(number: $projectNum) {
        id
        title
        fields(first: 100) {
          totalCount
          nodes {
            ... on ProjectV2FieldCommon { id name dataType }
          }
        }
        items(first: 100) {
          totalCount
          nodes { id type }
        }
      }
    }
  }
}
'@

function Invoke-GitHubGraphQL {
    param(
        [Parameter(Mandatory)][string]$Query,
        [hashtable]$Variables = @{}
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
                $messages = @($response.errors | ForEach-Object { $_.message }) -join '; '
                throw "GraphQL error: $messages"
            }
            return $response.data
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            # Retry only what is retryable: 429 and 5xx. A non-429 4xx is deterministic.
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

$hasToken = -not [string]::IsNullOrWhiteSpace($GitHubToken)

if ($DryRun -or -not $hasToken) {
    Write-Host '============================================================'
    if (-not $hasToken) {
        Write-Host ' NO TOKEN - DRY-RUN (no GitHub API call will be made)'
    }
    else {
        Write-Host ' DRY-RUN (no GitHub API call will be made)'
    }
    Write-Host '============================================================'
    if (-not $hasToken) {
        Write-Host 'No token available: -GitHubToken was empty and the GITHUB_TOKEN'
        Write-Host 'environment variable is not set. Token values are never printed.'
    }
    Write-Host ''
    Write-Host ("Would POST one read-only GraphQL query to {0}:" -f $graphQlEndpoint)
    Write-Host ("  repositoryOwner(login: '{0}') -> projectV2(number: {1})" -f $OrganizationName, $ProjectNumber)
    Write-Host '    -> fields(first: 100): id, name, dataType'
    Write-Host '    -> items(first: 100):  id, type'
    Write-Host ''
    Write-Host ("Would verify these {0} expected custom fields (list from setup-custom-fields.ps1):" -f $expectedFields.Count)
    foreach ($fieldName in $expectedFields) { Write-Host ("  - {0}" -f $fieldName) }
    Write-Host ''
    Write-Host "To run for real: set GITHUB_TOKEN (classic PAT, 'project' scope) or pass -GitHubToken."
    exit 0
}

try {
    $data = Invoke-GitHubGraphQL -Query $projectQuery -Variables @{
        login = $OrganizationName
        projectNum = $ProjectNumber
    }
}
catch {
    Write-Host ("Validation failed: {0}" -f $_) -ForegroundColor Red
    exit 1
}

$project = $null
if ($null -ne $data -and $data.PSObject.Properties['repositoryOwner'] -and $null -ne $data.repositoryOwner) {
    $repoOwner = $data.repositoryOwner
    if ($repoOwner.PSObject.Properties['projectV2']) { $project = $repoOwner.projectV2 }
}
if ($null -eq $project) {
    Write-Host ("Validation failed: project #{0} not found for owner '{1}' " -f $ProjectNumber, $OrganizationName) -ForegroundColor Red
    Write-Host '(check the owner login, the project number, and that the token has the project scope).'
    exit 1
}

$fieldNodes = @($project.fields.nodes | Where-Object { $null -ne $_ -and $_.PSObject.Properties['name'] })
$foundNames = @($fieldNodes | ForEach-Object { $_.name })
$presentFields = @($expectedFields | Where-Object { $foundNames -contains $_ })
$missingFields = @($expectedFields | Where-Object { $foundNames -notcontains $_ })

$itemNodes = @($project.items.nodes | Where-Object { $null -ne $_ })
$itemsByType = [ordered]@{}
foreach ($item in $itemNodes) {
    $itemType = if ($item.PSObject.Properties['type'] -and $item.type) { [string]$item.type } else { 'UNKNOWN' }
    if (-not $itemsByType.Contains($itemType)) { $itemsByType[$itemType] = 0 }
    $itemsByType[$itemType]++
}

Write-Host '============================================================'
Write-Host ' BOARD VALIDATION (real ProjectV2 GraphQL read)'
Write-Host '============================================================'
Write-Host ("Project:                {0}  (owner: {1}, number: {2})" -f $project.title, $OrganizationName, $ProjectNumber)
Write-Host ("Fields on project:      {0} total ({1} read)" -f $project.fields.totalCount, $fieldNodes.Count)
Write-Host ("Expected custom fields: {0}/{1} present" -f $presentFields.Count, $expectedFields.Count) `
    -ForegroundColor $(if ($missingFields.Count -eq 0) { 'Green' } else { 'Red' })
if ($missingFields.Count -gt 0) {
    Write-Host ("Missing fields:         {0}" -f ($missingFields -join ', ')) -ForegroundColor Red
}
Write-Host ("Items on project:       {0} total ({1} read; first 100 only)" -f $project.items.totalCount, $itemNodes.Count)
foreach ($typeName in $itemsByType.Keys) {
    Write-Host ("  {0}: {1}" -f $typeName, $itemsByType[$typeName])
}
Write-Host 'Not validated here (ProjectV2 API cannot create them; check the GitHub UI):'
Write-Host '  views, phase templates, built-in workflow/automation rules.'

$result = [ordered]@{
    timestamp     = $timestamp
    organization  = $OrganizationName
    projectNumber = $ProjectNumber
    projectId     = $project.id
    projectTitle  = $project.title
    source        = 'live ProjectV2 GraphQL read (fields + items, first 100 each)'
    fieldsTotal   = $project.fields.totalCount
    expected      = $expectedFields.Count
    present       = $presentFields.Count
    missingFields = $missingFields
    itemsTotal    = $project.items.totalCount
    itemsRead     = $itemNodes.Count
    itemsByType   = $itemsByType
    isValid       = ($missingFields.Count -eq 0)
}

if ($GenerateReport) {
    if (-not (Test-Path 'logs')) { New-Item -ItemType Directory -Path 'logs' -Force | Out-Null }
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile
    Write-Host ("Report saved: {0}" -f $reportFile)
}

# Emit the result object as JSON for orchestrators that capture output.
$result | ConvertTo-Json -Depth 10

if ($missingFields.Count -gt 0) {
    Write-Host ("VALIDATION FAILED: {0} expected custom field(s) missing." -f $missingFields.Count) -ForegroundColor Red
    exit 2
}
Write-Host 'VALIDATION PASSED: all expected custom fields present.' -ForegroundColor Green
exit 0
