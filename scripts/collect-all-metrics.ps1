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
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HELIOS Platform - Metrics Orchestrator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Loading metrics collection modules..." -ForegroundColor Yellow
Import-Module (Join-Path $modulePath "MetricsCollector.psm1") -Force
Import-Module (Join-Path $scriptRoot "database" "DatabaseHelper.psm1") -Force
Import-Module (Join-Path $scriptRoot "github" "GitHubIntegration.psm1") -Force

Write-Host "✓ Modules loaded" -ForegroundColor Green
Write-Host ""

# Initialize database
Write-Host "Initializing metrics database..." -ForegroundColor Yellow
$schema = Initialize-MetricsDatabase -DatabasePath $dbPath
Write-Host "✓ Database initialized" -ForegroundColor Green
Write-Host ""

# Main collection function
function Invoke-MetricsCollection {
    param(
        [string]$Type = "all"
    )
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Collecting metrics..." -ForegroundColor Cyan
    
    # Collect all metric types
    $timestamp = Get-Date -Format 'o'
    
    $allMetrics = @{
        timestamp = $timestamp
        collection_run = $timestamp
    }
    
    if ($Type -in "execution", "all") {
        Write-Host "  → Collecting execution metrics..." -NoNewline
        $allMetrics.execution = (Get-ExecutionMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "performance", "all") {
        Write-Host "  → Collecting performance metrics..." -NoNewline
        $allMetrics.performance = (Get-PerformanceMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "quality", "all") {
        Write-Host "  → Collecting quality metrics..." -NoNewline
        $allMetrics.quality = (Get-QualityMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "deployment", "all") {
        Write-Host "  → Collecting deployment metrics..." -NoNewline
        $allMetrics.deployment = (Get-DeploymentMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "cost", "all") {
        Write-Host "  → Collecting cost metrics..." -NoNewline
        $allMetrics.cost = (Get-CostMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "security", "all") {
        Write-Host "  → Collecting security metrics..." -NoNewline
        $allMetrics.security = (Get-SecurityMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "team", "all") {
        Write-Host "  → Collecting team metrics..." -NoNewline
        $allMetrics.team = (Get-TeamMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "business", "all") {
        Write-Host "  → Collecting business metrics..." -NoNewline
        $allMetrics.business = (Get-BusinessMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    if ($Type -in "data_quality", "all") {
        Write-Host "  → Collecting data quality metrics..." -NoNewline
        $allMetrics.data_quality = (Get-DataQualityMetrics -Database $dbPath).metrics
        Write-Host " ✓" -ForegroundColor Green
    }
    
    return $allMetrics
}

# Main sync function
function Invoke-MetricsSync {
    param([hashtable]$Metrics)
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Syncing metrics to all channels..." -ForegroundColor Cyan
    
    # Sync to GitHub Board
    Write-Host "  → Syncing to GitHub Project Board..." -NoNewline
    $boardResult = Sync-MetricsToGitHubBoard -Metrics $Metrics
    Write-Host " ✓" -ForegroundColor Green
    
    # Generate GitHub Pages dashboard
    Write-Host "  → Generating GitHub Pages dashboard..." -NoNewline
    $dashboardResult = Sync-MetricsToGitHubPages -Metrics $Metrics -OutputPath (Join-Path $scriptRoot ".." ".github" "pages")
    Write-Host " ✓" -ForegroundColor Green
    
    # Publish metrics API
    Write-Host "  → Publishing metrics API..." -NoNewline
    $apiResult = Publish-MetricsAPI -Metrics $Metrics -OutputPath (Join-Path $scriptRoot ".." ".github" "pages")
    Write-Host " ✓" -ForegroundColor Green
    
    # Update GitHub Issues
    Write-Host "  → Updating metrics in GitHub Issues..." -NoNewline
    $issueResult = Update-MetricsIssues -Metrics $Metrics
    Write-Host " ✓" -ForegroundColor Green
    
    # Export to storage formats
    Write-Host "  → Exporting to JSON..." -NoNewline
    $jsonResult = Export-MetricsToJSON -Metrics $Metrics -OutputPath (Join-Path $dataPath "metrics.json")
    Write-Host " ✓" -ForegroundColor Green
    
    Write-Host "  → Exporting to CSV..." -NoNewline
    $csvResult = Export-MetricsToCSV -Metrics $Metrics -OutputPath (Join-Path $dataPath "metrics.csv")
    Write-Host " ✓" -ForegroundColor Green
}

# Main report function
function Invoke-MetricsReport {
    param([hashtable]$Metrics)
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Generating metrics report..." -ForegroundColor Cyan
    $reportResult = Create-MetricsReport -Metrics $Metrics -OutputPath $dataPath
    Write-Host "  ✓ Report created: $reportResult" -ForegroundColor Green
}

# Single execution
function Invoke-SingleRun {
    try {
        $metrics = Invoke-MetricsCollection -Type $MetricType
        Invoke-MetricsSync -Metrics $metrics
        Invoke-MetricsReport -Metrics $metrics
        
        Write-Host ""
        Write-Host "✅ Metrics collection complete" -ForegroundColor Green
        Write-Host ""
        Write-Host "Metrics Summary:" -ForegroundColor Cyan
        Write-Host "  • Execution:    $($metrics.execution.Count) variables" -ForegroundColor Gray
        Write-Host "  • Performance:  $($metrics.performance.Count) variables" -ForegroundColor Gray
        Write-Host "  • Quality:      $($metrics.quality.Count) variables" -ForegroundColor Gray
        Write-Host "  • Deployment:   $($metrics.deployment.Count) variables" -ForegroundColor Gray
        Write-Host "  • Cost:         $($metrics.cost.Count) variables" -ForegroundColor Gray
        Write-Host "  • Security:     $($metrics.security.Count) variables" -ForegroundColor Gray
        Write-Host "  • Team:         $($metrics.team.Count) variables" -ForegroundColor Gray
        Write-Host "  • Business:     $($metrics.business.Count) variables" -ForegroundColor Gray
        Write-Host "  • Data Quality: $($metrics.data_quality.Count) variables" -ForegroundColor Gray
        Write-Host ""
    } catch {
        Write-Host "❌ Error during metrics collection:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

# Continuous execution
function Invoke-ContinuousRun {
    Write-Host "Starting continuous metrics collection..." -ForegroundColor Yellow
    Write-Host "Interval: $IntervalMinutes minutes" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""
    
    $runCount = 0
    while ($true) {
        $runCount++
        Write-Host ""
        Write-Host "=== RUN #$runCount ===" -ForegroundColor Cyan
        
        try {
            $metrics = Invoke-MetricsCollection -Type $MetricType
            Invoke-MetricsSync -Metrics $metrics
            
            Write-Host ""
            Write-Host "✅ Collection complete at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
            Write-Host "Next collection in $IntervalMinutes minute(s)..." -ForegroundColor Yellow
            
            # Sleep until next interval
            Start-Sleep -Seconds ($IntervalMinutes * 60)
        } catch {
            Write-Host ""
            Write-Host "⚠️  Error in run #$runCount : $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Retrying in 1 minute..." -ForegroundColor Yellow
            Start-Sleep -Seconds 60
        }
    }
}

# Main execution
if ($Continuous) {
    Invoke-ContinuousRun
} else {
    Invoke-SingleRun
}
