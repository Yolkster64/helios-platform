<#
.SYNOPSIS
    Alert management and notification system
.DESCRIPTION
    Manages alert lifecycle, escalation, and notifications
.VERSION
    1.0.0
#>

param()

. "$PSScriptRoot\..\lib\monitoring-library.ps1"

Initialize-MonitoringLog -Component "Alert-Management"

class AlertManager {
    [hashtable]$Alerts
    [int]$AlertCounter = 0
    [hashtable]$AlertPolicies
    
    AlertManager() {
        $this.Alerts = @{
            Critical = @()
            High = @()
            Medium = @()
            Low = @()
            Info = @()
        }
        $this.AlertPolicies = Get-AlertPolicies
    }
    
    [string]CreateAlert([string]$Title, [string]$Severity, [string]$Description, [string]$Source) {
        $alertId = "ALR-$(Get-Date -Format 'yyyyMMddHHmmss')-$(++$this.AlertCounter)"
        
        $alert = @{
            AlertId = $alertId
            Title = $Title
            Severity = $Severity
            Description = $Description
            Source = $Source
            CreatedTime = Get-Date -AsUTC
            Status = "Open"
            Acknowledged = $false
            AcknowledgedTime = $null
            AcknowledgedBy = $null
            ResolutionTime = $null
            LastModified = Get-Date -AsUTC
        }
        
        $this.Alerts[$Severity] += $alert
        Write-MonitoringLog "Alert created: $alertId - $Title" -Level "WARNING"
        
        return $alertId
    }
    
    [void]AcknowledgeAlert([string]$AlertId, [string]$AcknowledgedBy) {
        foreach ($severity in $this.Alerts.Keys) {
            $alert = $this.Alerts[$severity] | Where-Object { $_.AlertId -eq $AlertId } | Select-Object -First 1
            
            if ($alert) {
                $alert.Acknowledged = $true
                $alert.AcknowledgedTime = Get-Date -AsUTC
                $alert.AcknowledgedBy = $AcknowledgedBy
                $alert.LastModified = Get-Date -AsUTC
                Write-MonitoringLog "Alert acknowledged: $AlertId by $AcknowledgedBy"
                return
            }
        }
    }
    
    [void]ResolveAlert([string]$AlertId, [string]$Resolution) {
        foreach ($severity in $this.Alerts.Keys) {
            $alert = $this.Alerts[$severity] | Where-Object { $_.AlertId -eq $AlertId } | Select-Object -First 1
            
            if ($alert) {
                $alert.Status = "Resolved"
                $alert.ResolutionTime = Get-Date -AsUTC
                $alert.LastModified = Get-Date -AsUTC
                Write-MonitoringLog "Alert resolved: $AlertId - $Resolution"
                return
            }
        }
    }
    
    [array]GetActiveAlerts() {
        $active = @()
        foreach ($severity in $this.Alerts.Keys) {
            $active += $this.Alerts[$severity] | Where-Object { $_.Status -ne "Resolved" }
        }
        return $active
    }
    
    [array]GetAlertsByPriority() {
        $ordered = @()
        foreach ($severity in @("Critical", "High", "Medium", "Low", "Info")) {
            $ordered += $this.Alerts[$severity] | Where-Object { $_.Status -ne "Resolved" }
        }
        return $ordered
    }
    
    [hashtable]GetAlertStatistics() {
        $stats = @{
            Total = 0
            Open = 0
            Acknowledged = 0
            Resolved = 0
            BySeverity = @{}
        }
        
        foreach ($severity in $this.Alerts.Keys) {
            $severityAlerts = $this.Alerts[$severity]
            $stats.BySeverity[$severity] = @{
                Total = $severityAlerts.Count
                Open = @($severityAlerts | Where-Object { $_.Status -eq "Open" }).Count
                Acknowledged = @($severityAlerts | Where-Object { $_.Acknowledged }).Count
            }
            
            $stats.Total += $severityAlerts.Count
            $stats.Open += @($severityAlerts | Where-Object { $_.Status -eq "Open" }).Count
            $stats.Acknowledged += @($severityAlerts | Where-Object { $_.Acknowledged }).Count
            $stats.Resolved += @($severityAlerts | Where-Object { $_.Status -eq "Resolved" }).Count
        }
        
        return $stats
    }
    
    [void]PruneResolvedAlerts([int]$DaysOld = 7) {
        $cutoffDate = (Get-Date).AddDays(-$DaysOld)
        $prunedCount = 0
        
        foreach ($severity in $this.Alerts.Keys) {
            $remaining = @()
            foreach ($alert in $this.Alerts[$severity]) {
                if ($alert.Status -eq "Resolved" -and $alert.ResolutionTime -lt $cutoffDate) {
                    $prunedCount++
                }
                else {
                    $remaining += $alert
                }
            }
            $this.Alerts[$severity] = $remaining
        }
        
        Write-MonitoringLog "Pruned $prunedCount resolved alerts older than $DaysOld days"
    }
}

function Start-AlertManagement {
    param(
        [int]$CheckIntervalSeconds = 60,
        [int]$PruneIntervalHours = 24
    )
    
    Write-MonitoringLog "Starting alert management..."
    
    $alertManager = [AlertManager]::new()
    $pruneCounter = 0
    
    while ($true) {
        try {
            # Check for pruning
            if ($pruneCounter % ($PruneIntervalHours * 3600 / $CheckIntervalSeconds) -eq 0) {
                $alertManager.PruneResolvedAlerts()
            }
            
            DisplayAlertDashboard -AlertManager $alertManager
            
            $pruneCounter++
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
        catch {
            Write-MonitoringLog "Alert management error: $_" -Level "ERROR"
            Start-Sleep -Seconds $CheckIntervalSeconds
        }
    }
}

function DisplayAlertDashboard {
    param([AlertManager]$AlertManager)
    
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ALERT MANAGEMENT CENTER                                      ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $stats = $AlertManager.GetAlertStatistics()
    
    Write-Host "ALERT STATISTICS" -ForegroundColor Yellow
    Write-Host "  Total Alerts: $($stats.Total)"
    Write-Host "  Open: $($stats.Open)" -ForegroundColor Red
    Write-Host "  Acknowledged: $($stats.Acknowledged)" -ForegroundColor Yellow
    Write-Host "  Resolved: $($stats.Resolved)" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "BY SEVERITY" -ForegroundColor Yellow
    foreach ($sev in @("Critical", "High", "Medium", "Low", "Info")) {
        if ($stats.BySeverity[$sev].Total -gt 0) {
            $sevColor = switch ($sev) {
                "Critical" { "Red" }
                "High" { "Yellow" }
                "Medium" { "Cyan" }
                default { "Green" }
            }
            Write-Host "  $($sev): $($stats.BySeverity[$sev].Total) total | $($stats.BySeverity[$sev].Open) open" -ForegroundColor $sevColor
        }
    }
    Write-Host ""
    
    $activeAlerts = $AlertManager.GetAlertsByPriority()
    
    if ($activeAlerts.Count -gt 0) {
        Write-Host "ACTIVE ALERTS (Latest 10)" -ForegroundColor Yellow
        $activeAlerts | Select-Object -Last 10 | ForEach-Object {
            $sevColor = switch ($_.Severity) {
                "Critical" { "Red" }
                "High" { "Yellow" }
                "Medium" { "Cyan" }
                default { "Green" }
            }
            
            $ackStatus = if ($_.Acknowledged) { "[ACK]" } else { "[OPEN]" }
            Write-Host "  [$($_.AlertId)] $ackStatus $($_.Title)" -ForegroundColor $sevColor
            Write-Host "    Source: $($_.Source) | Created: $($_.CreatedTime.ToString('HH:mm:ss'))"
        }
    }
    else {
        Write-Host "No active alerts" -ForegroundColor Green
    }
    Write-Host ""
    
    Write-Host "Last Updated: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
}

function New-TestAlert {
    param(
        [AlertManager]$AlertManager,
        [string]$Severity = "High"
    )
    
    $alertId = $AlertManager.CreateAlert(
        "Test Alert - $Severity Severity",
        $Severity,
        "This is a test alert for demonstration purposes",
        "Testing"
    )
    
    return $alertId
}

Export-ModuleMember -Function @('Start-AlertManagement', 'DisplayAlertDashboard', 'New-TestAlert')
Export-ModuleMember -Class 'AlertManager'
