#!/usr/bin/env pwsh
<#
.SYNOPSIS
HELIOS Platform - Complete Metrics Collection Orchestrator
Collects 120+ variables from 15 channels, syncs to board/pages/API, generates reports

.DESCRIPTION
Main orchestration script that:
1. Loads all metric collection modules
2. Collects execution, performance, quality, deployment, cost, security, team, business, data quality metrics
3. Stores in SQLite database
4. Syncs to GitHub Project Board
5. Generates GitHub Pages dashboard
6. Publishes API endpoints
7. Creates reports
8. Runs continuously with 5-minute intervals
#>

param(
    [string]$MetricType = "all",
    [string]$OutputFormat = "json",
    [int]$IntervalMinutes = 5,
    [bool]$Continuous = $false
)

# Set strict error handling
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Define paths
$scriptRoot = Split-Path -Parent $PSCommandPath
$modulePath = Join-Path $scriptRoot "metrics"
$dbPath = Join-Path $scriptRoot ".." "data" "database" "metrics.db"
$dataPath = Join-Path $scriptRoot ".." "data" "metrics"

# Import modules
Write-Output "========================================"
Write-Output "HELIOS Platform - Metrics Orchestrator"
Write-Output "========================================"
Write-Output ""

Write-Output "Loading metrics collection modules..."
Import-Module (Join-Path $modulePath "MetricsCollector.psm1") -Force
Import-Module (Join-Path $scriptRoot "database" "DatabaseHelper.psm1") -Force
Import-Module (Join-Path $scriptRoot "github" "GitHubIntegration.psm1") -Force

Write-Output "✓ Modules loaded"
Write-Output ""

# Initialize database
Write-Output "Initializing metrics database..."
Initialize-MetricsDatabase -DatabasePath $dbPath | Out-Null
Write-Output "✓ Database initialized"
Write-Output ""

# Main collection function
function Invoke-MetricsCollection {
    param(
        [string]$Type = "all"
    )
    
    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] Collecting metrics..."
    
    # Collect all metric types
    $timestamp = Get-Date -Format 'o'
    
    $allMetrics = @{
        timestamp = $timestamp
        collection_run = $timestamp
    }
    
    if ($Type -in "execution", "all") {
        Write-Output "  → Collecting execution metrics..."
        $allMetrics.execution = (Get-ExecutionMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "performance", "all") {
        Write-Output "  → Collecting performance metrics..."
        $allMetrics.performance = (Get-PerformanceMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "quality", "all") {
        Write-Output "  → Collecting quality metrics..."
        $allMetrics.quality = (Get-QualityMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "deployment", "all") {
        Write-Output "  → Collecting deployment metrics..."
        $allMetrics.deployment = (Get-DeploymentMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "cost", "all") {
        Write-Output "  → Collecting cost metrics..."
        $allMetrics.cost = (Get-CostMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "security", "all") {
        Write-Output "  → Collecting security metrics..."
        $allMetrics.security = (Get-SecurityMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "team", "all") {
        Write-Output "  → Collecting team metrics..."
        $allMetrics.team = (Get-TeamMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "business", "all") {
        Write-Output "  → Collecting business metrics..."
        $allMetrics.business = (Get-BusinessMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    if ($Type -in "data_quality", "all") {
        Write-Output "  → Collecting data quality metrics..."
        $allMetrics.data_quality = (Get-DataQualityMetrics -Database $dbPath).metrics
        Write-Output " ✓"
    }
    
    return $allMetrics
}

# Main sync function
function Invoke-MetricsSync {
    param([hashtable]$Metrics)
    
    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] Syncing metrics to all channels..."
    
    # Sync to GitHub Board
    Write-Output "  → Syncing to GitHub Project Board..."
    Sync-MetricsToGitHubBoard -Metrics $Metrics | Out-Null
    Write-Output " ✓"
    
    # Generate GitHub Pages dashboard
    Write-Output "  → Generating GitHub Pages dashboard..."
    Sync-MetricsToGitHubPages -Metrics $Metrics -OutputPath (Join-Path $scriptRoot ".." ".github" "pages") | Out-Null
    Write-Output " ✓"
    
    # Publish metrics API
    Write-Output "  → Publishing metrics API..."
    Publish-MetricsAPI -Metrics $Metrics -OutputPath (Join-Path $scriptRoot ".." ".github" "pages") | Out-Null
    Write-Output " ✓"
    
    # Update GitHub Issues
    Write-Output "  → Updating metrics in GitHub Issues..."
    Update-MetricsIssues -Metrics $Metrics | Out-Null
    Write-Output " ✓"
    
    # Export to storage formats
    Write-Output "  → Exporting to JSON..."
    Export-MetricsToJSON -Metrics $Metrics -OutputPath (Join-Path $dataPath "metrics.json") | Out-Null
    Write-Output " ✓"
    
    Write-Output "  → Exporting to CSV..."
    Export-MetricsToCSV -Metrics $Metrics -OutputPath (Join-Path $dataPath "metrics.csv") | Out-Null
    Write-Output " ✓"
}

# Main report function
function Invoke-MetricsReport {
    param([hashtable]$Metrics)
    
    Write-Output "[$(Get-Date -Format 'HH:mm:ss')] Generating metrics report..."
    $reportResult = Create-MetricsReport -Metrics $Metrics -OutputPath $dataPath
    Write-Output "  ✓ Report created: $reportResult"
}

# Single execution
function Invoke-SingleRun {
    param(
        [string]$Type = $MetricType,
        [string]$Format = $OutputFormat
    )

    try {
        Write-Output "Metric type: $Type"
        Write-Output "Output format: $Format"

        $metrics = Invoke-MetricsCollection -Type $Type
        Invoke-MetricsSync -Metrics $metrics
        Invoke-MetricsReport -Metrics $metrics
        
        Write-Output ""
        Write-Output "✅ Metrics collection complete"
        Write-Output ""
        Write-Output "Metrics Summary:"
        Write-Output "  • Execution:    $($metrics.execution.Count) variables"
        Write-Output "  • Performance:  $($metrics.performance.Count) variables"
        Write-Output "  • Quality:      $($metrics.quality.Count) variables"
        Write-Output "  • Deployment:   $($metrics.deployment.Count) variables"
        Write-Output "  • Cost:         $($metrics.cost.Count) variables"
        Write-Output "  • Security:     $($metrics.security.Count) variables"
        Write-Output "  • Team:         $($metrics.team.Count) variables"
        Write-Output "  • Business:     $($metrics.business.Count) variables"
        Write-Output "  • Data Quality: $($metrics.data_quality.Count) variables"
        Write-Output ""
    } catch {
        Write-Output "❌ Error during metrics collection:"
        Write-Output $_.Exception.Message
        exit 1
    }
}

# Continuous execution
function Invoke-ContinuousRun {
    param([int]$Interval = $IntervalMinutes)

    Write-Output "Starting continuous metrics collection..."
    Write-Output "Interval: $Interval minutes"
    Write-Output "Press Ctrl+C to stop"
    Write-Output ""
    
    $runCount = 0
    while ($true) {
        $runCount++
        Write-Output ""
        Write-Output "=== RUN #$runCount ==="
        
        try {
            $metrics = Invoke-MetricsCollection -Type $MetricType
            Invoke-MetricsSync -Metrics $metrics
            
            Write-Output ""
            Write-Output "✅ Collection complete at $(Get-Date -Format 'HH:mm:ss')"
            Write-Output "Next collection in $Interval minute(s)..."
            
            # Sleep until next interval
            Start-Sleep -Seconds ($Interval * 60)
        } catch {
            Write-Output ""
            Write-Output "⚠️  Error in run #$runCount : $($_.Exception.Message)"
            Write-Output "Retrying in 1 minute..."
            Start-Sleep -Seconds 60
        }
    }
}

# Main execution
if ($Continuous) {
    Invoke-ContinuousRun -Interval $IntervalMinutes
} else {
    Invoke-SingleRun -Type $MetricType -Format $OutputFormat
}
