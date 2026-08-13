<#
.SYNOPSIS
    Master board setup script - custom fields are REAL API provisioning; the other steps are local simulations
.DESCRIPTION
    Orchestrates the four board setup steps and is explicit about which are real:
      * Custom Fields  (setup-custom-fields.ps1)      - REAL: GraphQL mutations against
        api.github.com/graphql (plus a real token/project pre-flight in this script)
      * Phase Templates (setup-templates.ps1)         - LOCAL SIMULATION: the ProjectV2
        GraphQL API cannot create templates
      * Automation Rules (setup-automation-rules.ps1) - LOCAL SIMULATION: the ProjectV2
        GraphQL API cannot create built-in workflows
      * Board Views (setup-views.ps1)                 - LOCAL SIMULATION: the ProjectV2
        GraphQL API cannot create views
    The simulated steps write local JSON (templates/, .automation/, .views/) and generate
    manual click-path guides under logs/ - perform those steps in the GitHub UI.
    Afterwards: validate the real parts with validate-board.ps1 (real GraphQL read) and
    put the epic issues on the board with add-epics-to-board.ps1 (real GraphQL mutations).
.PARAMETER GitHubToken
    GitHub Personal Access Token (used for the real pre-flight and the Custom Fields step)
.PARAMETER ProjectNumber
    Project number to create/configure
.PARAMETER OrganizationName
    GitHub organization
.PARAMETER BoardName
    Name for the project board
.PARAMETER DryRun
    Preview mode
.PARAMETER SkipSteps
    Comma-separated list of steps to skip (fields,templates,automation,views)
.PARAMETER Verbose
    Detailed output
.EXAMPLE
    .\setup-board.ps1 -GitHubToken $token -ProjectNumber 1 -OrganizationName "helios" -BoardName "HELIOS Platform"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    
    [Parameter(Mandatory=$true)]
    [int]$ProjectNumber,
    
    [Parameter(Mandatory=$true)]
    [string]$OrganizationName,
    
    [Parameter(Mandatory=$false)]
    [string]$BoardName = 'HELIOS Platform',
    
    [switch]$DryRun,
    [string[]]$SkipSteps = @()
    # No explicit -Verbose switch: the [Parameter()] attributes make this an advanced
    # script, so the common -Verbose parameter already exists (an explicit one would
    # collide and make the script impossible to invoke).
)

$ErrorActionPreference = 'Stop'

# The documented -SkipSteps values (fields,templates,automation,views) are
# short aliases; the skip comparison below matches the full step names passed
# to Invoke-SetupStep. Translate aliases (and split any comma-joined single
# argument) so both forms — and the full names themselves — actually skip.
$stepAliases = @{
    fields     = 'Custom Fields'
    templates  = 'Phase Templates'
    automation = 'Automation Rules'
    views      = 'Board Views'
}
$SkipSteps = @($SkipSteps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } |
    ForEach-Object {
        if ($stepAliases.ContainsKey($_.ToLowerInvariant())) { $stepAliases[$_.ToLowerInvariant()] } else { $_ }
    })

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$logFile = "logs/board-setup_$timestamp.log"
$reportFile = "logs/board-setup-report_$timestamp.json"
$backupFile = "logs/board-backup_$timestamp.json"

if (-not (Test-Path 'logs')) { New-Item -ItemType Directory -Path 'logs' -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $entry
    if ($VerbosePreference -eq 'Continue' -or $Level -eq 'ERROR' -or $Level -eq 'SUCCESS') { Write-Host $entry }
}

function Invoke-SetupStep {
    param(
        [string]$StepName,
        [string]$ScriptPath,
        [hashtable]$Parameters
    )
    
    Write-Log "Starting: $StepName"
    
    if ($StepName -in $SkipSteps) {
        Write-Log "  Skipped (in skip list)" 'INFO'
        return @{ name = $StepName; status = 'skipped' }
    }
    
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "  Script not found: $ScriptPath" 'ERROR'
        return @{ name = $StepName; status = 'failed'; error = 'Script not found' }
    }
    
    try {
        $params = @{
            GitHubToken = $GitHubToken
            ProjectNumber = $ProjectNumber
            OrganizationName = $OrganizationName
        }
        
        # Add additional parameters
        foreach ($key in $Parameters.Keys) {
            $params[$key] = $Parameters[$key]
        }
        
        if ($DryRun) { $params['DryRun'] = $true }
        if ($VerbosePreference -eq 'Continue') { $params['Verbose'] = $true }
        
        # Execute script
        $result = & $ScriptPath @params
        
        Write-Log "  Completed: $StepName" 'SUCCESS'
        
        return @{
            name = $StepName
            status = 'completed'
            result = $result
        }
    }
    catch {
        Write-Log "  Failed: $StepName - $_" 'ERROR'
        return @{
            name = $StepName
            status = 'failed'
            error = $_
        }
    }
}

function Backup-Configuration {
    Write-Log 'Creating configuration backup...'
    
    $backup = @{
        timestamp = $timestamp
        organization = $OrganizationName
        projectNumber = $ProjectNumber
        boardName = $BoardName
        backupContents = @{
            fields = if (Test-Path '.fields') { Get-ChildItem '.fields' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count } else { 0 }
            templates = if (Test-Path 'templates') { Get-ChildItem 'templates' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count } else { 0 }
            views = if (Test-Path '.views') { Get-ChildItem '.views' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count } else { 0 }
            automation = if (Test-Path '.automation') { Get-ChildItem '.automation' -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count } else { 0 }
        }
    }
    
    $backup | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile
    Write-Log "  Backup saved: $backupFile" 'SUCCESS'
}

function Test-Prerequisites {
    Write-Log 'Testing prerequisites...'
    
    # Test GitHub Token
    try {
        $headers = @{
            'Authorization' = "bearer $GitHubToken"
            'Accept' = 'application/vnd.github.v3+json'
        }
        $userResponse = Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers $headers
        Write-Log "  GitHub authenticated as: $($userResponse.login)" 'SUCCESS'
    }
    catch {
        Write-Log "  GitHub authentication failed: $_" 'ERROR'
        return $false
    }
    
    # Test directory structure
    $requiredDirs = @('logs', '.fields', 'templates', '.automation', '.views')
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Write-Log '  Directory structure ready' 'SUCCESS'
    
    return $true
}

function Generate-Report {
    param([array]$StepResults)
    
    $report = @{
        timestamp = $timestamp
        organization = $OrganizationName
        projectNumber = $ProjectNumber
        boardName = $BoardName
        dryRun = $DryRun
        steps = $StepResults
        summary = @{
            total = $StepResults.Count
            completed = ($StepResults | Where-Object { $_.status -eq 'completed' }).Count
            failed = ($StepResults | Where-Object { $_.status -eq 'failed' }).Count
            skipped = ($StepResults | Where-Object { $_.status -eq 'skipped' }).Count
        }
    }
    
    $report | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile
    
    Write-Log "Report saved: $reportFile" 'SUCCESS'
    
    return $report
}

function Display-Summary {
    param([hashtable]$Report)
    
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         HELIOS PLATFORM - BOARD SETUP SUMMARY          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`nProject Configuration:" -ForegroundColor Green
    Write-Host "  Organization: $($Report.organization)"
    Write-Host "  Project #: $($Report.projectNumber)"
    Write-Host "  Board Name: $($Report.boardName)"
    Write-Host "  Timestamp: $($Report.timestamp)"
    
    Write-Host "`nSetup Summary:" -ForegroundColor Green
    Write-Host "  Total Steps: $($Report.summary.total)"
    Write-Host "  Completed: $($Report.summary.completed)" -ForegroundColor Green
    Write-Host "  Failed: $($Report.summary.failed)" -ForegroundColor $(if ($Report.summary.failed -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Skipped: $($Report.summary.skipped)" -ForegroundColor Yellow
    
    Write-Host "`nStep Details:" -ForegroundColor Green
    foreach ($step in $Report.steps) {
        $status = switch ($step.status) {
            'completed' { '✓ COMPLETED' }
            'failed' { '✗ FAILED' }
            'skipped' { '⊘ SKIPPED' }
            default { $step.status }
        }
        Write-Host "  $($step.name): $status"
    }
    
    Write-Host "`nWhat was real vs simulated:" -ForegroundColor Yellow
    Write-Host "  Custom Fields ran against the GitHub API. Phase Templates, Automation Rules,"
    Write-Host "  and Board Views were LOCAL SIMULATIONS (the ProjectV2 GraphQL API cannot"
    Write-Host "  create them) - configure those manually in the GitHub UI using the generated"
    Write-Host "  guides under logs/."

    Write-Host "`nNext Steps:" -ForegroundColor Green
    Write-Host "  1. Create views/templates/workflows manually in the GitHub UI (guides in logs/)"
    Write-Host "  2. Run validation (real GraphQL read of fields + items): .\validate-board.ps1"
    Write-Host "  3. Put the epics on the board (real GraphQL mutations): .\add-epics-to-board.ps1"
    Write-Host "  4. Review logs: logs/board-setup_$timestamp.log"
    Write-Host "  5. Review report: logs/board-setup-report_$timestamp.json"
    
    if ($DryRun) {
        Write-Host "`n⚠️  DRY RUN MODE - No changes were actually applied" -ForegroundColor Yellow
    }
    
    Write-Host "`n"
}

# Main execution
try {
    Write-Log '╔═══════════════════════════════════════════════════════╗'
    Write-Log '║    HELIOS PLATFORM - MASTER BOARD SETUP SCRIPT       ║'
    Write-Log '╚═══════════════════════════════════════════════════════╝'
    Write-Log "Started: $timestamp"
    Write-Log "Organization: $OrganizationName, Project: $ProjectNumber"
    Write-Log "DryRun: $DryRun"
    
    if (-not (Test-Prerequisites)) {
        throw 'Prerequisites test failed'
    }
    
    Backup-Configuration
    
    $steps = @()
    
    # Execute setup steps
    $steps += Invoke-SetupStep -StepName 'Custom Fields' `
        -ScriptPath 'scripts/board-setup/setup-custom-fields.ps1' `
        -Parameters @{}
    
    $steps += Invoke-SetupStep -StepName 'Phase Templates' `
        -ScriptPath 'scripts/board-setup/setup-templates.ps1' `
        -Parameters @{}
    
    $steps += Invoke-SetupStep -StepName 'Automation Rules' `
        -ScriptPath 'scripts/board-setup/setup-automation-rules.ps1' `
        -Parameters @{}
    
    $steps += Invoke-SetupStep -StepName 'Board Views' `
        -ScriptPath 'scripts/board-setup/setup-views.ps1' `
        -Parameters @{}
    
    $report = Generate-Report -StepResults $steps
    Display-Summary -Report $report
    
    Write-Log '═══════════════════════════════════════════════════════'
    Write-Log "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'SUCCESS'
    
    # Return report for integration
    $report | ConvertTo-Json -Depth 10
}
catch {
    Write-Log "FATAL ERROR: $_" 'ERROR'
    Write-Host "`nSetup failed. Check logs at: $logFile" -ForegroundColor Red
    exit 1
}
