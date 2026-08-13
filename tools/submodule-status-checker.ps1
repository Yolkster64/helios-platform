#!/usr/bin/env powershell
#
# submodule-status-checker.ps1
# 
# Checks status of all HELIOS submodules
# Shows dashboard with progress, blockers, and metrics
#

param(
    [switch]$Detailed,
    [switch]$OnlyBlockers,
    [switch]$ExportCSV,
    [string]$CSVPath = "submodule-status.csv"
)

function Get-SubmoduleStatus {
    param([string]$RootPath = "submodules")
    
    $statuses = @()
    
    if (-not (Test-Path $RootPath)) {
        Write-Error "Submodules directory not found: $RootPath"
        return
    }
    
    Get-ChildItem $RootPath -Directory -Filter "PHASE-*" -ErrorAction SilentlyContinue | ForEach-Object {
        $statusFile = Join-Path $_.FullName "STATUS.json"
        
        if (Test-Path $statusFile) {
            try {
                $status = Get-Content $statusFile -ErrorAction Stop | ConvertFrom-Json
                $status | Add-Member -NotePropertyName "Path" -NotePropertyValue $_.FullName
                $statuses += $status
            }
            catch {
                Write-Warning "Failed to read ${statusFile}: $_"
            }
        }
        else {
            # Create empty status for new submodules
            $status = @{
                module = $_.Name
                status = "Planned"
                version = "0.1.0-dev"
                progress_metrics = @{ overall_percent = 0 }
                quality_metrics = @{ unit_tests_passing = 0; test_coverage_percent = 0 }
                blockers = @()
                Path = $_.FullName
            }
            $statuses += $status
        }
    }
    
    return $statuses | Sort-Object { $_.module }
}

function Show-StatusDashboard {
    param([array]$Statuses)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          HELIOS PLATFORM SUBMODULE STATUS DASHBOARD             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    # Group by phase
    $phases = $Statuses | Group-Object { 
        if ($_.module -match "PHASE-(\d)") { "Phase $($matches[1])" } else { "Other" }
    } | Sort-Object Name
    
    foreach ($phase in $phases) {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        Write-Host $phase.Name -ForegroundColor Yellow -NoNewline
        
        $phaseStatus = $phase.Group | Measure-Object -Property progress_metrics.overall_percent -Average
        $phaseProgress = [int]$phaseStatus.Average
        $progressBar = (("█" * ($phaseProgress / 5)) + ("░" * ((100 - $phaseProgress) / 5))).Substring(0, 20)
        
        Write-Host " $progressBar $phaseProgress%" -ForegroundColor Green
        
        foreach ($submodule in $phase.Group) {
            $progress = $submodule.progress_metrics.overall_percent
            $status = $submodule.status
            
            # Color code status
            $statusColor = switch ($status) {
                "Done" { "Green" }
                "In Progress" { "Cyan" }
                "Testing" { "Blue" }
                "Blocked" { "Red" }
                "Planned" { "Gray" }
                "Stable" { "Green" }
                default { "White" }
            }
            
            $progressBar = (("▓" * ($progress / 5)) + ("░" * ((100 - $progress) / 5))).Substring(0, 20)
            
            Write-Host "  ├─ $($submodule.module)" -NoNewline
            Write-Host " $progressBar " -NoNewline
            Write-Host "$progress%" -ForegroundColor Green -NoNewline
            Write-Host " [$status]" -ForegroundColor $statusColor
            
            if ($submodule.blockers -and $submodule.blockers.Count -gt 0) {
                Write-Host "  │  ⚠️  Blockers: $($submodule.blockers.Count)" -ForegroundColor Red
            }
        }
    }
    
    # Summary statistics
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "SUMMARY STATISTICS" -ForegroundColor Yellow
    
    $statusCounts = $Statuses | Group-Object -Property status | Select-Object Name, Count
    $totalProgress = [int]($Statuses | Measure-Object -Property progress_metrics.overall_percent -Average).Average
    
    $totalCount = $Statuses.Count
    foreach ($count in $statusCounts) {
        $percent = [int]($count.Count / $totalCount * 100)
        Write-Host "  $($count.Name): $($count.Count)/$totalCount ($percent%)" -ForegroundColor Cyan
    }
    
    Write-Host "`n  Overall Progress: $totalProgress%" -ForegroundColor Green
    Write-Host "  Average Test Coverage: $([int]($Statuses | Measure-Object -Property quality_metrics.test_coverage_percent -Average).Average)%" -ForegroundColor Cyan
}

function Show-BlockersSummary {
    param([array]$Statuses)
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "CURRENT BLOCKERS" -ForegroundColor Yellow
    
    $blockerCount = 0
    foreach ($submodule in $Statuses) {
        if ($submodule.blockers -and $submodule.blockers.Count -gt 0) {
            Write-Host "`n  $($submodule.module):" -ForegroundColor Red
            foreach ($blocker in $submodule.blockers) {
                Write-Host "    ⚠️  $($blocker.issue)" -ForegroundColor Yellow
                Write-Host "       Severity: $($blocker.severity) | Blocking: $($blocker.blocker_module)" -ForegroundColor Gray
                $blockerCount++
            }
        }
    }
    
    if ($blockerCount -eq 0) {
        Write-Host "  ✓ No current blockers" -ForegroundColor Green
    }
}

function Show-DetailedStatus {
    param([array]$Statuses)
    
    foreach ($submodule in $Statuses) {
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        Write-Host $submodule.module -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
        
        Write-Host "  Status:           " -NoNewline
        Write-Host $submodule.status -ForegroundColor Green
        Write-Host "  Version:          $($submodule.version)" -ForegroundColor Cyan
        Write-Host "  Owner:            $($submodule.owner)" -ForegroundColor Cyan
        Write-Host "  Progress:         $($submodule.progress_metrics.overall_percent)%" -ForegroundColor Green
        Write-Host "  Test Coverage:    $($submodule.quality_metrics.test_coverage_percent)%" -ForegroundColor Cyan
        Write-Host "  Unit Tests:       $($submodule.quality_metrics.unit_tests_passing)/$($submodule.quality_metrics.unit_tests_total)" -ForegroundColor Cyan
        
        if ($submodule.blockers -and $submodule.blockers.Count -gt 0) {
            Write-Host "  Blockers:" -ForegroundColor Red
            foreach ($blocker in $submodule.blockers) {
                Write-Host "    - $($blocker.issue) ($($blocker.severity))" -ForegroundColor Yellow
            }
        }
        
        if ($submodule.dependencies -and $submodule.dependencies.Count -gt 0) {
            Write-Host "  Dependencies:" -ForegroundColor Blue
            foreach ($dep in $submodule.dependencies) {
                Write-Host "    - $($dep.module) v$($dep.version)" -ForegroundColor Gray
            }
        }
    }
}

# Main execution
try {
    Write-Host "Checking HELIOS Platform submodule status..." -ForegroundColor Cyan
    
    $statuses = Get-SubmoduleStatus
    
    if (-not $statuses -or $statuses.Count -eq 0) {
        Write-Host "No submodules found. Run from repository root." -ForegroundColor Yellow
        exit 1
    }
    
    if ($OnlyBlockers) {
        Show-BlockersSummary $statuses
    }
    elseif ($Detailed) {
        Show-StatusDashboard $statuses
        Show-BlockersSummary $statuses
        Show-DetailedStatus $statuses
    }
    else {
        Show-StatusDashboard $statuses
        Show-BlockersSummary $statuses
    }
    
    if ($ExportCSV) {
        Write-Host "`n`nExporting to CSV: $CSVPath" -ForegroundColor Cyan
        $export = $statuses | Select-Object module, status, version, @{
            Name = "Progress"; Expression = { $_.progress_metrics.overall_percent }
        }, @{
            Name = "TestCoverage"; Expression = { $_.quality_metrics.test_coverage_percent }
        }, owner, @{
            Name = "Blockers"; Expression = { $_.blockers.Count }
        }
        $export | Export-Csv -Path $CSVPath -NoTypeInformation
        Write-Host "✓ Export complete" -ForegroundColor Green
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}

Write-Host "`n✓ Status check complete" -ForegroundColor Green
