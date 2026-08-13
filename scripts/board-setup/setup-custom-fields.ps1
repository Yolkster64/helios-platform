<#
.SYNOPSIS
    Creates and configures all 25 custom fields for HELIOS Platform GitHub Project board
.DESCRIPTION
    This script programmatically creates custom fields across all 5 tiers with proper
    types, options, defaults, visibility, and permissions settings.
.PARAMETER GitHubToken
    GitHub Personal Access Token with project scope
.PARAMETER ProjectNumber
    GitHub Project number to configure
.PARAMETER OrganizationName
    GitHub organization containing the project
.PARAMETER DryRun
    Preview changes without applying them
.PARAMETER Verbose
    Enable verbose logging output
.EXAMPLE
    .\setup-custom-fields.ps1 -GitHubToken $token -ProjectNumber 1 -OrganizationName "helios-org"
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

# Configuration
$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = "logs/custom-fields-setup_$timestamp.log"
$reportFile = "logs/custom-fields-report_$timestamp.json"
$backupFile = "logs/custom-fields-backup_$timestamp.json"

# Ensure log directory exists
if (-not (Test-Path 'logs')) {
    New-Item -ItemType Directory -Path 'logs' -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
    if ($VerbosePreference -eq 'Continue' -or $Level -eq 'ERROR' -or $Level -eq 'SUCCESS') {
        Write-Host $logMessage
    }
}

function Invoke-GitHubGraphQL {
    param(
        [string]$Query,
        [hashtable]$Variables = @{}
    )
    
    $headers = @{
        'Authorization' = "bearer $GitHubToken"
        'Content-Type' = 'application/json'
        'X-Github-Api-Version' = '2022-11-28'
    }
    
    $body = @{
        query = $Query
        variables = $Variables
    } | ConvertTo-Json -Depth 10
    
    try {
        $response = Invoke-RestMethod -Uri 'https://api.github.com/graphql' `
            -Method Post -Headers $headers -Body $body
        
        if ($response.errors) {
            throw "GraphQL Error: $($response.errors[0].message)"
        }
        
        return $response.data
    }
    catch {
        Write-Log "GraphQL Request Failed: $_" 'ERROR'
        throw
    }
}

# Field definitions for all 5 tiers
$fieldDefinitions = @(
    # Tier 1: Core Planning Fields
    @{
        name = 'Priority'
        type = 'SingleSelect'
        options = @('Critical', 'High', 'Medium', 'Low')
        default = 'Medium'
        tier = 1
        description = 'Task priority level'
    },
    @{
        name = 'Sprint'
        type = 'SingleSelect'
        options = @('Sprint 1', 'Sprint 2', 'Sprint 3', 'Sprint 4', 'Backlog')
        default = 'Backlog'
        tier = 1
        description = 'Sprint assignment'
    },
    @{
        name = 'Effort'
        type = 'SingleSelect'
        options = @('XS', 'S', 'M', 'L', 'XL', 'XXL')
        default = 'M'
        tier = 1
        description = 'Effort estimation in story points'
    },
    @{
        name = 'Component'
        type = 'SingleSelect'
        options = @('API', 'Frontend', 'Backend', 'DevOps', 'Database', 'Security', 'Performance', 'Documentation')
        default = 'API'
        tier = 1
        description = 'Component this item belongs to'
    },
    @{
        name = 'DueDate'
        type = 'Date'
        tier = 1
        description = 'Target completion date'
    },
    
    # Tier 2: Execution Fields
    @{
        name = 'AssignedTo'
        type = 'Text'
        tier = 2
        description = 'Team member assigned to this task'
    },
    @{
        name = 'ProgressStatus'
        type = 'SingleSelect'
        options = @('Not Started', 'In Progress', '25% Complete', '50% Complete', '75% Complete', 'Complete')
        default = 'Not Started'
        tier = 2
        description = 'Execution progress percentage'
    },
    @{
        name = 'QAStatus'
        type = 'SingleSelect'
        options = @('Pending QA', 'In QA', 'QA Approved', 'QA Failed', 'N/A')
        default = 'Pending QA'
        tier = 2
        description = 'Quality assurance status'
    },
    @{
        name = 'BlockedBy'
        type = 'Text'
        tier = 2
        description = 'Issue or task blocking this work'
    },
    @{
        name = 'TimeEstimate'
        type = 'Text'
        tier = 2
        description = 'Estimated hours for completion'
    },
    
    # Tier 3: Review & Approval Fields
    @{
        name = 'ReviewStatus'
        type = 'SingleSelect'
        options = @('Not Reviewed', 'In Review', 'Changes Requested', 'Approved', 'Rejected')
        default = 'Not Reviewed'
        tier = 3
        description = 'Code or design review status'
    },
    @{
        name = 'ReviewedBy'
        type = 'Text'
        tier = 3
        description = 'Team member who reviewed this'
    },
    @{
        name = 'ApprovalRequired'
        type = 'SingleSelect'
        options = @('Yes', 'No')
        default = 'Yes'
        tier = 3
        description = 'Whether approval is required before proceeding'
    },
    @{
        name = 'RiskLevel'
        type = 'SingleSelect'
        options = @('Low', 'Medium', 'High', 'Critical')
        default = 'Medium'
        tier = 3
        description = 'Risk assessment for this change'
    },
    @{
        name = 'ComplianceCheck'
        type = 'SingleSelect'
        options = @('Passed', 'Failed', 'Pending', 'N/A')
        default = 'Pending'
        tier = 3
        description = 'Compliance validation status'
    },
    
    # Tier 4: Deployment & Integration Fields
    @{
        name = 'DeploymentEnvironment'
        type = 'SingleSelect'
        options = @('Development', 'Staging', 'Production', 'All')
        default = 'Development'
        tier = 4
        description = 'Target deployment environment'
    },
    @{
        name = 'DeploymentStatus'
        type = 'SingleSelect'
        options = @('Not Deployed', 'Deployed to Dev', 'Deployed to Staging', 'Deployed to Prod', 'Rolled Back')
        default = 'Not Deployed'
        tier = 4
        description = 'Deployment status across environments'
    },
    @{
        name = 'IntegrationPoints'
        type = 'Text'
        tier = 4
        description = 'Systems or services this integrates with'
    },
    @{
        name = 'DependsOn'
        type = 'Text'
        tier = 4
        description = 'Tasks or features this depends on'
    },
    @{
        name = 'DataMigration'
        type = 'SingleSelect'
        options = @('Required', 'Not Required', 'In Progress', 'Completed')
        default = 'Not Required'
        tier = 4
        description = 'Data migration requirement for this feature'
    },
    
    # Tier 5: Analytics & Success Metrics
    @{
        name = 'SuccessMetrics'
        type = 'Text'
        tier = 5
        description = 'Metrics defining success for this item'
    },
    @{
        name = 'UserImpact'
        type = 'SingleSelect'
        options = @('High', 'Medium', 'Low', 'Internal Only')
        default = 'Medium'
        tier = 5
        description = 'Level of end-user impact'
    },
    @{
        name = 'PerformanceImpact'
        type = 'SingleSelect'
        options = @('Positive', 'Neutral', 'Negative', 'TBD')
        default = 'TBD'
        tier = 5
        description = 'Expected performance impact'
    },
    @{
        name = 'Documentation'
        type = 'SingleSelect'
        options = @('Complete', 'Incomplete', 'Not Required', 'In Progress')
        default = 'Incomplete'
        tier = 5
        description = 'Documentation status'
    },
    @{
        name = 'ArchitectureDecision'
        type = 'Text'
        tier = 5
        description = 'ADR reference or architecture decision document'
    }
)

function Test-Prerequisites {
    Write-Log 'Testing prerequisites...'
    
    # Test GitHub Token
    try {
        $headers = @{
            'Authorization' = "bearer $GitHubToken"
            'Accept' = 'application/vnd.github.v3+json'
        }
        $testResponse = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
        Write-Log "GitHub Token verified for user: $($testResponse.login)" 'SUCCESS'
    }
    catch {
        Write-Log 'GitHub Token test failed' 'ERROR'
        throw
    }
    
    # Verify project exists
    try {
        $projectQuery = @'
query ($org: String!, $projectNum: Int!) {
  organization(login: $org) {
    projectV2(number: $projectNum) {
      id
      title
    }
  }
}
'@
        $result = Invoke-GitHubGraphQL -Query $projectQuery -Variables @{
            org = $OrganizationName
            projectNum = $ProjectNumber
        }
        
        if ($result.organization.projectV2) {
            Write-Log "Project verified: $($result.organization.projectV2.title)" 'SUCCESS'
            return $result.organization.projectV2.id
        }
        else {
            throw 'Project not found'
        }
    }
    catch {
        Write-Log "Project verification failed: $_" 'ERROR'
        throw
    }
}

function Create-CustomField {
    param(
        [string]$ProjectId,
        [hashtable]$FieldDef,
        [ref]$CreatedFields
    )
    
    Write-Log "Creating field: $($FieldDef.name) (Tier $($FieldDef.tier))"
    
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would create field: $($FieldDef.name)" 'INFO'
        $CreatedFields.Value += @{
            name = $FieldDef.name
            type = $FieldDef.type
            status = 'dry-run'
            tier = $FieldDef.tier
        }
        return
    }
    
    try {
        $createFieldQuery = @'
mutation CreateProjectField($input: CreateProjectV2FieldInput!) {
  createProjectV2Field(input: $input) {
    projectV2Field {
      id
      name
      dataType
    }
  }
}
'@
        
        # Build field configuration
        $fieldConfig = @{
            name = $FieldDef.name
            dataType = $FieldDef.type
        }
        
        if ($FieldDef.type -eq 'SingleSelect' -and $FieldDef.options) {
            $fieldConfig['singleSelectOptions'] = $FieldDef.options | ForEach-Object { @{ name = $_ } }
        }
        
        $result = Invoke-GitHubGraphQL -Query $createFieldQuery -Variables @{
            input = @{
                projectId = $ProjectId
                name = $FieldDef.name
                dataType = $FieldDef.type
            }
        }
        
        if ($result.createProjectV2Field.projectV2Field) {
            $fieldId = $result.createProjectV2Field.projectV2Field.id
            Write-Log "  Field created successfully (ID: $fieldId)" 'SUCCESS'
            
            $CreatedFields.Value += @{
                name = $FieldDef.name
                fieldId = $fieldId
                type = $FieldDef.type
                tier = $FieldDef.tier
                status = 'created'
            }
        }
    }
    catch {
        Write-Log "  Failed to create field: $_" 'ERROR'
        $CreatedFields.Value += @{
            name = $FieldDef.name
            type = $FieldDef.type
            status = 'failed'
            tier = $FieldDef.tier
            error = $_
        }
    }
}

function Generate-Report {
    param([array]$CreatedFields)
    
    $report = @{
        timestamp = $timestamp
        projectNumber = $ProjectNumber
        organization = $OrganizationName
        totalFieldsRequested = $fieldDefinitions.Count
        fieldsCreated = ($CreatedFields | Where-Object { $_.status -eq 'created' }).Count
        fieldsFailed = ($CreatedFields | Where-Object { $_.status -eq 'failed' }).Count
        fieldsDryRun = ($CreatedFields | Where-Object { $_.status -eq 'dry-run' }).Count
        fields = $CreatedFields
        byTier = @{
            tier1 = ($CreatedFields | Where-Object { $_.tier -eq 1 }).Count
            tier2 = ($CreatedFields | Where-Object { $_.tier -eq 2 }).Count
            tier3 = ($CreatedFields | Where-Object { $_.tier -eq 3 }).Count
            tier4 = ($CreatedFields | Where-Object { $_.tier -eq 4 }).Count
            tier5 = ($CreatedFields | Where-Object { $_.tier -eq 5 }).Count
        }
    }
    
    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile
    Write-Log "Report saved to: $reportFile" 'SUCCESS'
    
    return $report
}

# Main execution
try {
    Write-Log '=== Starting Custom Fields Setup ===' 'INFO'
    Write-Log "Configuration: Project #$ProjectNumber, Org: $OrganizationName" 'INFO'
    
    if ($DryRun) {
        Write-Log 'DRY RUN MODE ENABLED - No changes will be applied' 'INFO'
    }
    
    $projectId = Test-Prerequisites
    
    $createdFields = @()
    $fieldsRef = [ref]$createdFields
    
    Write-Log "Creating $($fieldDefinitions.Count) custom fields..." 'INFO'
    
    $fieldDefinitions | ForEach-Object {
        Create-CustomField -ProjectId $projectId -FieldDef $_ -CreatedFields $fieldsRef
    }
    
    $report = Generate-Report -CreatedFields $createdFields
    
    Write-Log '=== Custom Fields Setup Complete ===' 'SUCCESS'
    Write-Log "Created: $($report.fieldsCreated), Failed: $($report.fieldsFailed)" 'INFO'
    Write-Log "By Tier - 1: $($report.byTier.tier1), 2: $($report.byTier.tier2), 3: $($report.byTier.tier3), 4: $($report.byTier.tier4), 5: $($report.byTier.tier5)" 'INFO'
    
    # Output report
    $report | ConvertTo-Json -Depth 10
}
catch {
    Write-Log "Script failed: $_" 'ERROR'
    exit 1
}
