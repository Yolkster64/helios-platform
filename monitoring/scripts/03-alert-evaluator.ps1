<#
.SYNOPSIS
Alert evaluation and notification system for HELIOS Platform

.DESCRIPTION
Evaluates alert rules against current metrics and sends notifications via:
- Email
- Microsoft Teams
- Webhooks

.PARAMETER DatabasePath
Path to monitoring database

.PARAMETER ConfigPath
Path to alert rules configuration

.EXAMPLE
.\03-alert-evaluator.ps1
#>

param(
    [string]$DatabasePath = "C:\Users\ADMIN\helios-platform\monitoring\data\helios_monitoring.db",
    [string]$ConfigPath = "C:\Users\ADMIN\helios-platform\monitoring\config"
)

# Default alert rules
$DefaultAlertRules = @(
    @{
        Name                     = "High Error Rate 5xx"
        Description              = "Alert when 5xx errors exceed 1%"
        Component                = "All"
        Metric                   = "error_rate_5xx"
        Operator                 = "GreaterThan"
        Threshold                = 1.0
        DurationSeconds          = 300
        Severity                 = "CRITICAL"
        NotificationChannels     = @("email", "teams")
        EscalationPolicy         = "immediate"
        AggregationWindowSeconds = 300
    },
    @{
        Name                     = "High Latency P99"
        Description              = "Alert when P99 latency exceeds 1000ms"
        Component                = "All"
        Metric                   = "latency_p99"
        Operator                 = "GreaterThan"
        Threshold                = 1000
        DurationSeconds          = 600
        Severity                 = "WARNING"
        NotificationChannels     = @("email")
        EscalationPolicy         = "escalate_after_1h"
        AggregationWindowSeconds = 300
    },
    @{
        Name                     = "High CPU Usage"
        Description              = "Alert when CPU usage exceeds 85%"
        Component                = "All"
        Metric                   = "cpu_percent"
        Operator                 = "GreaterThan"
        Threshold                = 85
        DurationSeconds          = 300
        Severity                 = "WARNING"
        NotificationChannels     = @("email")
        EscalationPolicy         = "normal"
        AggregationWindowSeconds = 300
    },
    @{
        Name                     = "High Memory Usage"
        Description              = "Alert when memory usage exceeds 90%"
        Component                = "All"
        Metric                   = "memory_percent"
        Operator                 = "GreaterThan"
        Threshold                = 90
        DurationSeconds          = 300
        Severity                 = "CRITICAL"
        NotificationChannels     = @("email", "teams")
        EscalationPolicy         = "immediate"
        AggregationWindowSeconds = 300
    },
    @{
        Name                     = "Service Unavailable"
        Description              = "Alert when component health check fails"
        Component                = "All"
        Metric                   = "health_check_failed"
        Operator                 = "Equals"
        Threshold                = 1
        DurationSeconds          = 60
        Severity                 = "CRITICAL"
        NotificationChannels     = @("email", "teams", "webhook")
        EscalationPolicy         = "immediate"
        AggregationWindowSeconds = 60
    },
    @{
        Name                     = "Disk I/O Bottleneck"
        Description              = "Alert when disk I/O exceeds 500 MB/s"
        Component                = "Analytics-Core"
        Metric                   = "disk_io_mbps"
        Operator                 = "GreaterThan"
        Threshold                = 500
        DurationSeconds          = 300
        Severity                 = "WARNING"
        NotificationChannels     = @("email")
        EscalationPolicy         = "normal"
        AggregationWindowSeconds = 300
    },
    @{
        Name                     = "Network Saturation"
        Description              = "Alert when network bandwidth exceeds 1000 MB/s"
        Component                = "Cloud-Bridge"
        Metric                   = "network_bandwidth_mbps"
        Operator                 = "GreaterThan"
        Threshold                = 1000
        DurationSeconds          = 300
        Severity                 = "WARNING"
        NotificationChannels     = @("email", "teams")
        EscalationPolicy         = "escalate_after_30m"
        AggregationWindowSeconds = 300
    }
)

# Notification channels
$NotificationChannels = @{
    "email" = @{
        Type        = "SMTP"
        Server      = "smtp.office365.com"
        Port        = 587
        From        = "monitoring@helios.local"
        Recipients  = @("ops-team@helios.local", "sre@helios.local")
        UseSSL      = $true
    }
    "teams" = @{
        Type   = "Webhook"
        URL    = "https://outlook.webhook.office.com/webhookb2/your-teams-webhook-url"
        Method = "POST"
    }
    "webhook" = @{
        Type   = "Webhook"
        URL    = "https://your-incident-system/api/alerts"
        Method = "POST"
    }
}

# Function to evaluate alert condition
function Test-AlertCondition {
    param(
        [hashtable]$Rule,
        [hashtable]$CurrentMetrics
    )
    
    $MetricValue = $CurrentMetrics[$Rule.Metric]
    
    switch ($Rule.Operator) {
        "GreaterThan" { return $MetricValue -gt $Rule.Threshold }
        "GreaterThanOrEqual" { return $MetricValue -ge $Rule.Threshold }
        "LessThan" { return $MetricValue -lt $Rule.Threshold }
        "LessThanOrEqual" { return $MetricValue -le $Rule.Threshold }
        "Equals" { return $MetricValue -eq $Rule.Threshold }
        "NotEquals" { return $MetricValue -ne $Rule.Threshold }
        default { return $false }
    }
}

# Function to send email notification
function Send-EmailNotification {
    param(
        [string]$AlertName,
        [string]$AlertSeverity,
        [string]$ComponentName,
        [string]$Message,
        [hashtable]$AlertMetrics
    )
    
    try {
        $EmailBody = @"
HELIOS Platform - Alert Notification

Alert Name: $AlertName
Severity: $AlertSeverity
Component: $ComponentName
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Message: $Message

Metrics:
$($AlertMetrics | ConvertTo-Json)

Please investigate and take appropriate action.
"@
        
        Write-Host "  📧 Email notification prepared for: $AlertName" -ForegroundColor Yellow
        Write-Host "     Recipients: $($NotificationChannels['email'].Recipients -join ', ')"
        
        # In production, use Send-MailMessage or similar
        
    } catch {
        Write-Error "Failed to send email: $_"
    }
}

# Function to send Teams notification
function Send-TeamsNotification {
    param(
        [string]$AlertName,
        [string]$AlertSeverity,
        [string]$ComponentName,
        [string]$Message
    )
    
    try {
        $SeverityColor = switch ($AlertSeverity) {
            "CRITICAL" { "ff0000" }  # Red
            "WARNING" { "ffaa00" }   # Orange
            "INFO" { "0066ff" }      # Blue
            default { "666666" }     # Gray
        }
        
        $TeamsPayload = @{
            "@type"      = "MessageCard"
            "@context"   = "https://schema.org/extensions"
            "summary"    = "${AlertSeverity}: $AlertName"
            "themeColor" = $SeverityColor
            "sections"   = @(
                @{
                    "activityTitle"    = "🚨 HELIOS Platform Alert"
                    "activitySubtitle" = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                    "facts"            = @(
                        @{ "name" = "Alert"; "value" = $AlertName }
                        @{ "name" = "Component"; "value" = $ComponentName }
                        @{ "name" = "Severity"; "value" = $AlertSeverity }
                        @{ "name" = "Message"; "value" = $Message }
                    )
                    "markdown"         = $true
                }
            )
            "potentialAction" = @(
                @{
                    "@type" = "OpenUri"
                    "name"  = "View Dashboard"
                    "targets" = @(
                        @{ "os" = "default"; "uri" = "http://localhost:8080/dashboard" }
                    )
                }
            )
        }
        
        Write-Host "  💬 Teams notification prepared for: $AlertName" -ForegroundColor Yellow
        Write-Host "     Webhook: $($NotificationChannels['teams'].URL)"
        
        # In production, use Invoke-RestMethod to send
        
    } catch {
        Write-Error "Failed to prepare Teams notification: $_"
    }
}

# Function to send webhook notification
function Send-WebhookNotification {
    param(
        [string]$AlertName,
        [string]$AlertSeverity,
        [string]$ComponentName,
        [string]$Message,
        [hashtable]$MetricData
    )
    
    try {
        $WebhookPayload = @{
            alert_name     = $AlertName
            severity       = $AlertSeverity
            component      = $ComponentName
            message        = $Message
            timestamp      = Get-Date -Format "o"
            metric_data    = $MetricData
            source         = "HELIOS-Monitoring"
            environment    = "production"
        } | ConvertTo-Json
        
        Write-Host "  🔗 Webhook notification prepared for: $AlertName" -ForegroundColor Yellow
        Write-Host "     Endpoint: $($NotificationChannels['webhook'].URL)"
        
        # In production, use Invoke-RestMethod
        
    } catch {
        Write-Error "Failed to prepare webhook notification: $_"
    }
}

# Function to create incident from alert
function Create-IncidentFromAlert {
    param(
        [string]$AlertName,
        [string]$AlertSeverity,
        [string]$ComponentName,
        [string]$Message
    )
    
    try {
        $IncidentNumber = "INC-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Minimum 1000 -Maximum 9999)"
        
        Write-Host "  📋 Creating incident: $IncidentNumber" -ForegroundColor Green
        
        # In production, write to database
        $LogPath = Split-Path $DatabasePath -Parent
        $IncidentLog = Join-Path $LogPath "incidents.log"
        
        $IncidentEntry = @{
            IncidentNumber = $IncidentNumber
            AlertName      = $AlertName
            Severity       = $AlertSeverity
            Component      = $ComponentName
            Message        = $Message
            CreatedAt      = Get-Date -Format "o"
            Status         = "NEW"
        } | ConvertTo-Json -Compress
        
        Add-Content -Path $IncidentLog -Value $IncidentEntry -Force
        
        return $IncidentNumber
        
    } catch {
        Write-Error "Failed to create incident: $_"
        return $null
    }
}

# Function to display alert summary
function Show-AlertSummary {
    param(
        [array]$FiredAlerts
    )
    
    if ($FiredAlerts.Count -eq 0) {
        Write-Host "`n✓ All systems normal. No alerts triggered." -ForegroundColor Green
        return
    }
    
    Write-Host "`n════════════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "ALERTS FIRED - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Red
    Write-Host "════════════════════════════════════════════════════════════════════" -ForegroundColor Red
    
    foreach ($Alert in $FiredAlerts) {
        $SeverityColor = switch ($Alert.Severity) {
            "CRITICAL" { "Red" }
            "WARNING" { "Yellow" }
            default { "White" }
        }
        
        Write-Host "`n🚨 $($Alert.Name)" -ForegroundColor $SeverityColor
        Write-Host "   Component: $($Alert.Component)"
        Write-Host "   Severity: $($Alert.Severity)"
        Write-Host "   Message: $($Alert.Message)"
        Write-Host "   Metric: $($Alert.Metric) = $($Alert.MetricValue)"
        Write-Host "   Incident: $($Alert.IncidentNumber)"
    }
    
    Write-Host "`n════════════════════════════════════════════════════════════════════" -ForegroundColor Red
}

# Main evaluation loop
Write-Host "Starting alert evaluation system..."
Write-Host "Rules loaded: $($DefaultAlertRules.Count)"
Write-Host "Notification channels: $($NotificationChannels.Keys -join ', ')"
Write-Host "Press Ctrl+C to stop"

$Iteration = 0

while ($true) {
    $Iteration++
    $FiredAlerts = @()
    
    Write-Host "`n[Evaluation $Iteration - $(Get-Date -Format 'HH:mm:ss')]"
    
    # Load latest metrics
    $MetricsFile = Join-Path (Split-Path $DatabasePath -Parent) "latest_performance_metrics.json"
    if (Test-Path $MetricsFile) {
        try {
            $LatestMetrics = Get-Content $MetricsFile | ConvertFrom-Json
            
            foreach ($ComponentMetrics in $LatestMetrics) {
                $CurrentMetrics = $ComponentMetrics.Metrics | ConvertTo-Hashtable
                
                # Evaluate each alert rule
                foreach ($Rule in $DefaultAlertRules) {
                    # Check if rule applies to this component
                    if ($Rule.Component -eq "All" -or $Rule.Component -eq $ComponentMetrics.Component) {
                        
                        # Test condition
                        if (Test-AlertCondition -Rule $Rule -CurrentMetrics $CurrentMetrics) {
                            Write-Host "  ⚠️  Alert triggered: $($Rule.Name) on $($ComponentMetrics.Component)"
                            
                            $Alert = @{
                                Name           = $Rule.Name
                                Severity       = $Rule.Severity
                                Component      = $ComponentMetrics.Component
                                Metric         = $Rule.Metric
                                MetricValue    = $CurrentMetrics[$Rule.Metric]
                                Threshold      = $Rule.Threshold
                                Message        = $Rule.Description
                                IncidentNumber = ""
                            }
                            
                            # Send notifications
                            if ($Rule.NotificationChannels -contains "email") {
                                Send-EmailNotification -AlertName $Rule.Name `
                                    -AlertSeverity $Rule.Severity `
                                    -ComponentName $ComponentMetrics.Component `
                                    -Message $Rule.Description `
                                    -AlertMetrics $CurrentMetrics
                            }
                            
                            if ($Rule.NotificationChannels -contains "teams") {
                                Send-TeamsNotification -AlertName $Rule.Name `
                                    -AlertSeverity $Rule.Severity `
                                    -ComponentName $ComponentMetrics.Component `
                                    -Message $Rule.Description
                            }
                            
                            if ($Rule.NotificationChannels -contains "webhook") {
                                Send-WebhookNotification -AlertName $Rule.Name `
                                    -AlertSeverity $Rule.Severity `
                                    -ComponentName $ComponentMetrics.Component `
                                    -Message $Rule.Description `
                                    -MetricData $CurrentMetrics
                            }
                            
                            # Create incident for critical alerts
                            if ($Rule.Severity -eq "CRITICAL") {
                                $IncidentNumber = Create-IncidentFromAlert -AlertName $Rule.Name `
                                    -AlertSeverity $Rule.Severity `
                                    -ComponentName $ComponentMetrics.Component `
                                    -Message $Rule.Description
                                
                                $Alert.IncidentNumber = $IncidentNumber
                            }
                            
                            $FiredAlerts += $Alert
                        }
                    }
                }
            }
            
        } catch {
            Write-Error "Failed to evaluate alerts: $_"
        }
    }
    
    # Display alert summary
    Show-AlertSummary -FiredAlerts $FiredAlerts
    
    # Export alert status
    $AlertFile = Join-Path (Split-Path $DatabasePath -Parent) "alert_status.json"
    @{
        Timestamp = Get-Date -Format "o"
        Alerts    = $FiredAlerts
        TotalFired = $FiredAlerts.Count
    } | ConvertTo-Json | Out-File $AlertFile -Force
    
    # Wait for next evaluation
    Start-Sleep -Seconds 60
}
