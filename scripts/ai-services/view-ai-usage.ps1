<#
.SYNOPSIS
View AI Services Usage Statistics

.DESCRIPTION
Displays detailed usage statistics for all AI services including requests,
tokens, costs, and performance metrics.

.EXAMPLE
.\view-ai-usage.ps1
.\view-ai-usage.ps1 -Service "chatgpt-pro"
.\view-ai-usage.ps1 -DateRange "week"
#>

param(
    [string]$Service = "all",
    [ValidateSet("today", "week", "month", "all")]
    [string]$DateRange = "today",
    [string]$LogPath = "C:\Users\ADMIN\helios-platform\logs\ai-services",
    [switch]$ExportCsv,
    [string]$ExportPath = "C:\Users\ADMIN\helios-platform\data\ai-services\usage_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Parse-LogFile {
    param(
        [string]$LogFile,
        [string]$Service,
        [DateTime]$DateFilter
    )
    
    $entries = @()
    
    if (-not (Test-Path $LogFile)) {
        return $entries
    }
    
    $content = Get-Content $LogFile -Raw
    $lines = $content -split "`n"
    
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Parse timestamp
        if ($line -match "\[(.*?)\].*\[INFO\].*Tokens used:.*?(\d+)") {
            $timestamp = [DateTime]::Parse($matches[1])
            
            if ($timestamp -ge $DateFilter) {
                $entries += [PSCustomObject]@{
                    Timestamp = $timestamp
                    Service = (Split-Path $LogFile -Leaf) -replace "\.log", ""
                    Line = $line
                }
            }
        }
    }
    
    return $entries
}

function Get-DateFilter {
    param([string]$DateRange)
    
    $now = Get-Date
    switch ($DateRange) {
        "today" { return $now.Date }
        "week" { return $now.AddDays(-7) }
        "month" { return $now.AddDays(-30) }
        default { return [DateTime]::MinValue }
    }
}

function Get-ServiceStats {
    param(
        [PSCustomObject[]]$LogEntries,
        [string]$Service
    )
    
    if ($Service -eq "all") {
        $services = $LogEntries | Select-Object -ExpandProperty Service -Unique
    }
    else {
        $services = @($Service)
    }
    
    $stats = @()
    
    foreach ($svc in $services) {
        $entries = $LogEntries | Where-Object { $_.Service -eq $svc }
        
        $totalTokens = 0
        $totalCost = 0
        $requestCount = $entries.Count
        
        foreach ($entry in $entries) {
            # Extract tokens (simple parsing)
            if ($entry.Line -match "Tokens used:.*?(\d+)") {
                $totalTokens += [int]$matches[1]
            }
            
            if ($entry.Line -match 'Cost:.*?\$([\d.]+)') {
                $totalCost += [double]$matches[1]
            }
        }
        
        $stats += [PSCustomObject]@{
            Service = $svc
            Requests = $requestCount
            TotalTokens = $totalTokens
            AvgTokensPerRequest = if ($requestCount -gt 0) { [Math]::Round($totalTokens / $requestCount, 2) } else { 0 }
            TotalCost = [Math]::Round($totalCost, 4)
            AvgCostPerRequest = if ($requestCount -gt 0) { [Math]::Round($totalCost / $requestCount, 4) } else { 0 }
            CostPerThousandTokens = if ($totalTokens -gt 0) { [Math]::Round(($totalCost / $totalTokens * 1000), 2) } else { 0 }
        }
    }
    
    return $stats
}

function Display-UsageReport {
    param([PSCustomObject[]]$Stats)
    
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                    AI SERVICES USAGE STATISTICS REPORT" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "`n"
    
    Write-Host "Date Range: $DateRange" -ForegroundColor Yellow
    Write-Host "Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
    Write-Host "`n"
    
    # Display table
    $Stats | Format-Table -AutoSize -Property @(
        "Service",
        @{ Label = "Requests"; Expression = { "{0:N0}" -f $_.Requests } },
        @{ Label = "Total Tokens"; Expression = { "{0:N0}" -f $_.TotalTokens } },
        @{ Label = "Avg Tokens"; Expression = { "{0:N0}" -f $_.AvgTokensPerRequest } },
        @{ Label = "Total Cost"; Expression = { "` ${0:N4}" -f $_.TotalCost } },
        @{ Label = "Avg Cost"; Expression = { "` ${0:N4}" -f $_.AvgCostPerRequest } }
    )
    
    # Summary statistics
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "SUMMARY STATISTICS" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $totalRequests = ($Stats | Measure-Object -Property Requests -Sum).Sum
    $totalTokens = ($Stats | Measure-Object -Property TotalTokens -Sum).Sum
    $totalCost = ($Stats | Measure-Object -Property TotalCost -Sum).Sum
    
    Write-Host "Total Requests:      $('{0:N0}' -f $totalRequests)"
    Write-Host "Total Tokens Used:   $('{0:N0}' -f $totalTokens)"
    Write-Host "Total Cost:          $ $('{0:N4}' -f $totalCost)"
    Write-Host "Average Cost/Token:  $ $('{0:N6}' -f ($totalCost / $totalTokens * 1000)) per 1K tokens"
    
    # Service comparison
    Write-Host "`n" -ForegroundColor Cyan
    Write-Host "SERVICE COMPARISON" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────────────────────────────────────────────────" -ForegroundColor Cyan
    
    $sorted = $Stats | Sort-Object -Property TotalCost -Descending
    foreach ($stat in $sorted) {
        $percentage = if ($totalCost -gt 0) { ($stat.TotalCost / $totalCost * 100) } else { 0 }
        Write-Host "$($stat.Service): $('{0:N1}' -f $percentage)% of total cost"
    }
    
    Write-Host "`n"
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "Reading log files from: $LogPath" -ForegroundColor Gray
    
    $dateFilter = Get-DateFilter $DateRange
    $logFiles = Get-ChildItem $LogPath -Filter "*.log" -ErrorAction SilentlyContinue
    
    if ($logFiles.Count -eq 0) {
        Write-Host "No log files found in $LogPath" -ForegroundColor Yellow
        exit 0
    }
    
    # Parse all log files
    $allEntries = @()
    foreach ($logFile in $logFiles) {
        $entries = Parse-LogFile -LogFile $logFile.FullName -Service $Service -DateFilter $dateFilter
        $allEntries += $entries
    }
    
    if ($allEntries.Count -eq 0) {
        Write-Host "No log entries found for the specified date range and service." -ForegroundColor Yellow
        exit 0
    }
    
    # Generate statistics
    $stats = Get-ServiceStats -LogEntries $allEntries -Service $Service
    
    # Display report
    Display-UsageReport -Stats $stats
    
    # Export if requested
    if ($ExportCsv) {
        $stats | Export-Csv -Path $ExportPath -NoTypeInformation
        Write-Host "Report exported to: $ExportPath" -ForegroundColor Green
    }
}
catch {
    Write-Error "Error generating usage report: $_"
    exit 1
}
