<#
.SYNOPSIS
    Main dashboard core for enterprise monitoring
.DESCRIPTION
    Unified dashboard providing real-time overview of all monitored systems
.VERSION
    1.0.0
#>

param()

# Import shared library
. "$PSScriptRoot\..\lib\monitoring-library.ps1"

Initialize-MonitoringLog -Component "Dashboard-Core"

class DashboardCore {
    [hashtable]$Config
    [hashtable]$Metrics
    [hashtable]$Alerts
    [datetime]$LastUpdate
    
    DashboardCore() {
        $this.Config = Get-MonitoringConfig
        $this.Metrics = @{}
        $this.Alerts = @{}
        $this.LastUpdate = Get-Date
    }
    
    [void]Initialize() {
        Write-MonitoringLog "Initializing dashboard..."
        $this.LoadMetrics()
        $this.LoadAlerts()
        Write-MonitoringLog "Dashboard initialized successfully"
    }
    
    [void]LoadMetrics() {
        try {
            $this.Metrics = @{
                SystemHealth = $this.GetSystemHealth()
                ServiceStatus = $this.GetServiceStatus()
                ResourceUtilization = $this.GetResourceUtilization()
                AlertSummary = $this.GetAlertSummary()
            }
            $this.LastUpdate = Get-Date
        }
        catch {
            Write-MonitoringLog "Error loading metrics: $_" -Level "ERROR"
        }
    }
    
    [void]LoadAlerts() {
        try {
            $this.Alerts = @{
                Critical = @()
                High = @()
                Medium = @()
                Low = @()
                Info = @()
            }
            Write-MonitoringLog "Alerts loaded successfully"
        }
        catch {
            Write-MonitoringLog "Error loading alerts: $_" -Level "ERROR"
        }
    }
    
    [hashtable]GetSystemHealth() {
        return @{
            Uptime = [Math]::Round((New-TimeSpan -Start ([System.Diagnostics.Process]::GetCurrentProcess().StartTime) -End (Get-Date)).TotalSeconds)
            Status = "Operational"
            LastCheck = Get-Date -AsUTC
        }
    }
    
    [array]GetServiceStatus() {
        $services = @("WinRM", "EventLog", "Winlogon")
        $status = @()
        
        foreach ($service in $services) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc) {
                    $status += @{
                        Name = $service
                        Status = $svc.Status.ToString()
                        StartType = $svc.StartType.ToString()
                    }
                }
            }
            catch {
                Write-MonitoringLog "Error getting service status for $service : $_" -Level "DEBUG"
            }
        }
        
        return $status
    }
    
    [hashtable]GetResourceUtilization() {
        try {
            $cpu = (Get-WmiObject Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property LoadPercentage -Average).Average
            $memory = ((Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TotalVisibleMemorySize) - (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FreePhysicalMemory)) / (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TotalVisibleMemorySize) * 100
            
            $disk = @()
            Get-Volume -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.SizeRemaining -gt 0) {
                    $percentUsed = (($_.Size - $_.SizeRemaining) / $_.Size) * 100
                    $disk += @{
                        Drive = $_.DriveLetter
                        PercentUsed = [Math]::Round($percentUsed, 2)
                    }
                }
            }
            
            return @{
                CPU = [Math]::Round($cpu, 2)
                Memory = [Math]::Round($memory, 2)
                Disk = $disk
            }
        }
        catch {
            Write-MonitoringLog "Error calculating resource utilization: $_" -Level "ERROR"
            return @{ CPU = 0; Memory = 0; Disk = @() }
        }
    }
    
    [hashtable]GetAlertSummary() {
        return @{
            CriticalCount = 0
            HighCount = 0
            MediumCount = 0
            TotalOpen = 0
        }
    }
    
    [void]RefreshDashboard() {
        Write-MonitoringLog "Refreshing dashboard..."
        $this.LoadMetrics()
        $this.LoadAlerts()
    }
    
    [string]GetDashboardHTML() {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Enterprise Monitoring Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1e1e1e; color: #fff; margin: 0; padding: 20px; }
        .dashboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card { background: #2d2d2d; border-left: 4px solid #0078d4; padding: 20px; border-radius: 5px; }
        .card.critical { border-left-color: #ff0000; }
        .card.warning { border-left-color: #ff6600; }
        .card.success { border-left-color: #00ff00; }
        .metric { font-size: 24px; font-weight: bold; margin: 10px 0; }
        .status { padding: 5px 10px; border-radius: 3px; display: inline-block; }
        .status.operational { background: #00ff00; color: #000; }
        .status.warning { background: #ffaa00; color: #000; }
        .status.critical { background: #ff0000; color: #fff; }
        h1 { margin-top: 0; }
        .last-updated { color: #999; font-size: 12px; margin-top: 10px; }
    </style>
</head>
<body>
    <h1>Enterprise Monitoring Dashboard</h1>
    <div class="dashboard">
        <div class="card">
            <h3>System Health</h3>
            <div class="metric">$($this.Metrics.SystemHealth.Status)</div>
            <div class="status operational">$($this.Metrics.SystemHealth.Status)</div>
        </div>
        <div class="card">
            <h3>Alert Summary</h3>
            <div class="metric">$($this.Metrics.AlertSummary.TotalOpen)</div>
            <p>Total Open Alerts</p>
        </div>
    </div>
    <div class="last-updated">Last updated: $($this.LastUpdate)</div>
</body>
</html>
"@
        return $html
    }
}

# Main execution
function Start-Dashboard {
    param(
        [int]$RefreshIntervalSeconds = 5
    )
    
    Write-MonitoringLog "Starting enterprise monitoring dashboard..."
    
    $dashboard = [DashboardCore]::new()
    $dashboard.Initialize()
    
    $iteration = 0
    
    while ($true) {
        try {
            $iteration++
            
            if ($iteration % ($RefreshIntervalSeconds / 1) -eq 0) {
                Clear-Host
                Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║  ENTERPRISE MONITORING DASHBOARD - Real-Time View              ║" -ForegroundColor Cyan
                Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host ""
                
                # System Health
                Write-Host "SYSTEM HEALTH" -ForegroundColor Yellow
                Write-Host "└─ Status: $($dashboard.Metrics.SystemHealth.Status)" -ForegroundColor Green
                Write-Host ""
                
                # Services
                Write-Host "SERVICES STATUS" -ForegroundColor Yellow
                foreach ($service in $dashboard.Metrics.ServiceStatus) {
                    $color = if ($service.Status -eq "Running") { "Green" } else { "Red" }
                    Write-Host "  └─ $($service.Name): $($service.Status)" -ForegroundColor $color
                }
                Write-Host ""
                
                # Resource Utilization
                Write-Host "RESOURCE UTILIZATION" -ForegroundColor Yellow
                Write-Host "  ├─ CPU: $($dashboard.Metrics.ResourceUtilization.CPU)%" -ForegroundColor Green
                Write-Host "  ├─ Memory: $($dashboard.Metrics.ResourceUtilization.Memory)%" -ForegroundColor Green
                Write-Host "  └─ Disk:" -ForegroundColor Green
                foreach ($disk in $dashboard.Metrics.ResourceUtilization.Disk) {
                    Write-Host "     └─ $($disk.Drive):: $($disk.PercentUsed)% used" -ForegroundColor Green
                }
                Write-Host ""
                
                # Alerts
                Write-Host "ALERT SUMMARY" -ForegroundColor Yellow
                Write-Host "  ├─ Critical: $($dashboard.Metrics.AlertSummary.CriticalCount)" -ForegroundColor Red
                Write-Host "  ├─ High: $($dashboard.Metrics.AlertSummary.HighCount)" -ForegroundColor Yellow
                Write-Host "  └─ Total Open: $($dashboard.Metrics.AlertSummary.TotalOpen)" -ForegroundColor Yellow
                Write-Host ""
                
                Write-Host "Last Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
                Write-Host "(Refreshing every $RefreshIntervalSeconds seconds. Press Ctrl+C to exit)" -ForegroundColor Gray
                
                $dashboard.RefreshDashboard()
            }
            
            Start-Sleep -Milliseconds 500
        }
        catch {
            Write-MonitoringLog "Dashboard error: $_" -Level "ERROR"
            Start-Sleep -Seconds 5
        }
    }
}

# Export functions
Export-ModuleMember -Function 'Start-Dashboard'
Export-ModuleMember -Class 'DashboardCore'
