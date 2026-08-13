<#
.SYNOPSIS
    LOCAL SIMULATION - documents 6 board views; makes NO GitHub API calls
.DESCRIPTION
    What is real vs simulated: GitHub's ProjectV2 GraphQL API cannot create or configure
    project views (there is no createProjectV2View mutation - views are readable but not
    writable). That is a real API limitation, not a script shortcut, so this script never
    touches the GitHub API. What it actually does, locally:
      * validates the 6 view definitions
      * writes them to .views/*.json
      * generates logs/views-guide_<timestamp>.md - the manual click-path for creating
        each view in the GitHub UI (Project -> "New view" -> configure filter/group/sort)
    The views themselves must be created by hand in the GitHub UI using that guide.
    Compare: setup-custom-fields.ps1 (real GraphQL mutations), validate-board.ps1 (real
    GraphQL read), add-epics-to-board.ps1 (real GraphQL mutations).
.PARAMETER GitHubToken
    Accepted only for interface parity with the sibling scripts; NOT used - this script
    makes no API calls
.PARAMETER ProjectNumber
    Project number (recorded in the report; no API call is made against it)
.PARAMETER OrganizationName
    Organization name (recorded in the report; no API call is made against it)
.PARAMETER DryRun
    Preview mode (skips even the local .views/*.json writes)
.PARAMETER Verbose
    Detailed output
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$true)]
    [int]$ProjectNumber,
    
    [Parameter(Mandatory=$true)]
    [string]$OrganizationName,
    
    [switch]$DryRun
    # No explicit -Verbose switch: the [Parameter()] attributes make this an advanced
    # script, so the common -Verbose parameter already exists (an explicit one would
    # collide and make the script impossible to invoke).
)

$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = "logs/views-setup_$timestamp.log"
$reportFile = "logs/views-report_$timestamp.json"

if (-not (Test-Path 'logs')) { New-Item -ItemType Directory -Path 'logs' -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    if ($VerbosePreference -eq 'Continue' -or $Level -eq 'ERROR' -or $Level -eq 'SUCCESS') { Write-Host $entry }
}

# 6 Board Views Definition
$views = @(
    @{
        name = 'All Tasks - By Priority'
        id = 'view-priority'
        description = 'All tasks organized by priority level'
        filters = @()
        groupBy = 'Priority'
        sortBy = @{ field = 'DueDate'; order = 'ascending' }
        layout = 'table'
        purpose = 'Executive overview of work by priority'
        fieldVisibility = @('Status', 'Priority', 'AssignedTo', 'DueDate', 'Effort', 'ProgressStatus')
    },
    @{
        name = 'Sprint View - Current Sprint'
        id = 'view-sprint'
        description = 'Items assigned to current sprint'
        filters = @(
            @{ field = 'Sprint'; operator = 'equals'; value = 'Sprint 1' }
        )
        groupBy = 'Component'
        sortBy = @{ field = 'Priority'; order = 'descending' }
        layout = 'board'
        purpose = 'Sprint tracking and coordination'
        fieldVisibility = @('Status', 'Priority', 'AssignedTo', 'Effort', 'ProgressStatus', 'ReviewStatus')
    },
    @{
        name = 'Critical & High Priority'
        id = 'view-critical'
        description = 'Filter for critical and high priority items only'
        filters = @(
            @{ field = 'Priority'; operator = 'in'; value = @('Critical', 'High') }
            @{ field = 'Status'; operator = 'notEquals'; value = 'Done' }
        )
        groupBy = 'Status'
        sortBy = @{ field = 'Priority'; order = 'descending' }
        layout = 'table'
        purpose = 'Management view of high-impact work'
        fieldVisibility = @('Status', 'Priority', 'RiskLevel', 'AssignedTo', 'DueDate', 'BlockedBy')
    },
    @{
        name = 'Deployment Pipeline'
        id = 'view-deployment'
        description = 'Items in deployment workflow'
        filters = @(
            @{ field = 'DeploymentEnvironment'; operator = 'notEquals'; value = 'null' }
            @{ field = 'Status'; operator = 'notIn'; value = @('Backlog', 'Done') }
        )
        groupBy = 'DeploymentStatus'
        sortBy = @{ field = 'Priority'; order = 'descending' }
        layout = 'board'
        purpose = 'DevOps view of deployment readiness'
        fieldVisibility = @('DeploymentStatus', 'DeploymentEnvironment', 'AssignedTo', 'QAStatus', 'DataMigration')
    },
    @{
        name = 'Review Required'
        id = 'view-review'
        description = 'Items awaiting code or design review'
        filters = @(
            @{ field = 'ReviewStatus'; operator = 'in'; value = @('Not Reviewed', 'In Review', 'Changes Requested') }
            @{ field = 'ApprovalRequired'; operator = 'equals'; value = 'Yes' }
        )
        groupBy = 'ReviewStatus'
        sortBy = @{ field = 'Priority'; order = 'descending' }
        layout = 'table'
        purpose = 'Review queue management'
        fieldVisibility = @('ReviewStatus', 'Priority', 'ReviewedBy', 'Component', 'Effort', 'RiskLevel')
    },
    @{
        name = 'Team Workload'
        id = 'view-workload'
        description = 'Items by assignee and progress'
        filters = @()
        groupBy = 'AssignedTo'
        sortBy = @{ field = 'ProgressStatus'; order = 'descending' }
        layout = 'table'
        purpose = 'Team capacity and workload tracking'
        fieldVisibility = @('AssignedTo', 'Priority', 'ProgressStatus', 'Effort', 'TimeEstimate', 'BlockedBy')
    }
)

function Validate-View {
    param([hashtable]$View)
    
    $validation = @{
        viewName = $View.name
        viewId = $View.id
        isValid = $true
        issues = @()
    }
    
    # Validate required fields
    if (-not $View.name) {
        $validation.isValid = $false
        $validation.issues += 'View name is required'
    }
    
    if (-not $View.id) {
        $validation.isValid = $false
        $validation.issues += 'View ID is required'
    }
    
    if (-not $View.groupBy) {
        $validation.isValid = $false
        $validation.issues += 'GroupBy field is required'
    }
    
    if (-not $View.layout -or $View.layout -notin @('table', 'board', 'roadmap')) {
        $validation.isValid = $false
        $validation.issues += 'Invalid layout type'
    }
    
    # Validate filters
    if ($View.filters.Count -gt 0) {
        foreach ($filter in $View.filters) {
            if (-not $filter.field -or -not $filter.operator) {
                $validation.isValid = $false
                $validation.issues += "Invalid filter: $($filter | ConvertTo-Json -Compress)"
            }
        }
    }
    
    return $validation
}

function Create-View {
    param([hashtable]$View)
    
    Write-Log "Creating view: $($View.name)"
    
    # Validate first
    $validation = Validate-View -View $View
    if (-not $validation.isValid) {
        Write-Log "  Validation failed: $(($validation.issues) -join ', ')" 'ERROR'
        return @{
            name = $View.name
            id = $View.id
            status = 'failed'
            error = 'Validation failed'
        }
    }
    
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would create view: $($View.name)" 'INFO'
        return @{
            name = $View.name
            id = $View.id
            status = 'dry-run'
            layout = $View.layout
            groupBy = $View.groupBy
        }
    }
    
    try {
        # Save view configuration
        $viewConfig = @{
            id = $View.id
            name = $View.name
            description = $View.description
            purpose = $View.purpose
            filters = $View.filters
            groupBy = $View.groupBy
            sortBy = $View.sortBy
            layout = $View.layout
            fieldVisibility = $View.fieldVisibility
            createdAt = Get-Date -Format 'o'
            isActive = $true
        }
        
        if (-not (Test-Path '.views')) { New-Item -ItemType Directory -Path '.views' -Force | Out-Null }
        $viewConfig | ConvertTo-Json -Depth 10 | Set-Content -Path ".views/$($View.id).json"
        
        Write-Log "  View created successfully" 'SUCCESS'
        
        return @{
            name = $View.name
            id = $View.id
            status = 'created'
            layout = $View.layout
            groupBy = $View.groupBy
            filters = $View.filters.Count
        }
    }
    catch {
        Write-Log "  Failed to create view: $_" 'ERROR'
        return @{
            name = $View.name
            id = $View.id
            status = 'failed'
            error = $_
        }
    }
}

function Generate-ViewGuide {
    param([array]$Views)
    
    $doc = @"
# HELIOS Platform - Board Views

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Quick View Index

| View Name | Purpose | Grouped By | Layout |
|-----------|---------|-----------|--------|
$(foreach ($v in $Views) {
"| $($v.name) | $($v.purpose) | $($v.groupBy) | $($v.layout) |`n"
})

## Detailed View Configurations

$(foreach ($view in $Views) {
@"
### $($view.name)

**ID**: $($view.id)  
**Description**: $($view.description)  
**Purpose**: $($view.purpose)  
**Layout**: $($view.layout)  
**Grouped By**: $($view.groupBy)  
**Sorted By**: $($view.sortBy.field) ($($view.sortBy.order))

#### Filters
$(if ($view.filters.Count -eq 0) {
    "- No filters (shows all items)`n"
} else {
    foreach ($filter in $view.filters) {
        "- $($filter.field) $($filter.operator) $($filter.value -join ', ')`n"
    }
})

#### Visible Fields
$(foreach ($field in $view.fieldVisibility) {
"- $field`n"
})

---
"@
})

## View Usage Guide

### For Different Roles

**Project Manager**: Use "Critical & High Priority" and "Team Workload"
**Development Team**: Use "Sprint View - Current Sprint" and "Review Required"
**DevOps**: Use "Deployment Pipeline"
**Executive**: Use "All Tasks - By Priority"

### Switching Views

Views can be switched by clicking the view selector at the top of the board.
Each view maintains its own filter and grouping configuration.

### Creating Custom Views

To create additional views:
1. Click "Add View"
2. Configure filters, grouping, and layout
3. Save with descriptive name
4. Share view link with team

"@

    $doc | Set-Content -Path "logs/views-guide_$timestamp.md"
    Write-Log "Board views guide generated" 'SUCCESS'
}

try {
    Write-Log '=== Starting Board Views Setup ===' 'INFO'
    
    if ($DryRun) {
        Write-Log 'DRY RUN MODE - No changes applied' 'INFO'
    }
    
    $createdViews = @()
    
    Write-Log "Creating $($views.Count) board views..."
    
    $views | ForEach-Object {
        $result = Create-View -View $_
        $createdViews += $result
    }
    
    Generate-ViewGuide -Views $views
    
    $report = @{
        timestamp = $timestamp
        mode = 'local-simulation (ProjectV2 GraphQL API cannot create views; no API calls made)'
        projectNumber = $ProjectNumber
        organization = $OrganizationName
        totalViews = $views.Count
        created = ($createdViews | Where-Object { $_.status -eq 'created' }).Count
        failed = ($createdViews | Where-Object { $_.status -eq 'failed' }).Count
        views = $createdViews
        viewTypes = @{
            table = ($createdViews | Where-Object { $_.layout -eq 'table' }).Count
            board = ($createdViews | Where-Object { $_.layout -eq 'board' }).Count
            roadmap = ($createdViews | Where-Object { $_.layout -eq 'roadmap' }).Count
        }
    }
    
    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile
    
    Write-Log '=== Board Views Setup Complete (LOCAL SIMULATION) ===' 'SUCCESS'
    Write-Log "Saved locally: $($report.created), Failed: $($report.failed)" 'INFO'
    Write-Host 'NOTE: local simulation only - no GitHub API calls were made.' -ForegroundColor Yellow
    Write-Host '      The ProjectV2 GraphQL API cannot create views; create them manually in the'
    Write-Host "      GitHub UI using the click-path guide: logs/views-guide_$timestamp.md"

    $report | ConvertTo-Json -Depth 10
}
catch {
    Write-Log "Script failed: $_" 'ERROR'
    exit 1
}
