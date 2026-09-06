# Enterprise Monitoring System

A comprehensive, production-ready unified monitoring platform for enterprises managing on-premises infrastructure, Azure cloud services, and Microsoft 365 environments.

## 📊 System Overview

The Enterprise Monitoring System provides:

- **Unified Dashboard** - Real-time visualization of all monitored systems
- **On-Premises Monitoring** - Windows system health, resources, and performance
- **Azure Integration** - Cloud resource monitoring, cost tracking, and quota management
- **Microsoft 365 Monitoring** - Service health, mail flow, Teams, and SharePoint analytics
- **Compliance & Governance** - DLP enforcement, audit trails, and risk scoring
- **AI-Driven Analytics** - Anomaly detection and predictive alerting
- **Advanced Reporting** - Executive, technical, and compliance reports

## 🏗️ Architecture

```
enterprise-monitoring/
├── dashboard/              # Real-time monitoring UI
│   ├── dashboard-core.ps1
│   ├── real-time-metrics.ps1
│   ├── health-overview.ps1
│   ├── alert-management.ps1
│   └── dashboard-themes.ps1
├── on-prem/               # On-premises infrastructure monitoring
│   ├── system-health.ps1
│   ├── resource-tracking.ps1
│   ├── security-monitoring.ps1
│   └── performance-analytics.ps1
├── azure/                 # Azure cloud monitoring
│   ├── azure-monitor-integration.ps1
│   ├── vm-performance.ps1
│   ├── app-service-monitoring.ps1
│   ├── cost-tracking.ps1
│   └── quota-tracking.ps1
├── m365/                  # Microsoft 365 services
│   ├── m365-health.ps1
│   ├── user-activity.ps1
│   ├── mail-flow.ps1
│   ├── teams-activity.ps1
│   └── sharepoint-health.ps1
├── compliance/            # Compliance monitoring
│   ├── purview-alerts.ps1
│   ├── dlp-violations.ps1
│   ├── audit-trail.ps1
│   └── risk-scoring.ps1
├── analytics/             # AI & predictive analytics
│   ├── anomaly-detection.ps1
│   ├── predictive-alerts.ps1
│   ├── usage-predictions.ps1
│   └── cost-forecasting.ps1
├── reporting/             # Report generation
│   ├── executive-reports.ps1
│   ├── technical-reports.ps1
│   ├── compliance-reports.ps1
│   └── capacity-planning.ps1
├── lib/                   # Shared libraries
│   └── monitoring-library.ps1
├── config/                # Configuration files
│   ├── monitoring-config.json
│   ├── alert-policies.json
│   └── report-templates.json
├── logs/                  # Logs and reports
└── monitoring-orchestrator.ps1  # Main entry point
```

## 🚀 Getting Started

### Prerequisites

- PowerShell 5.0 or higher
- Windows 10/Server 2016+
- Administrator privileges
- For Azure: Azure PowerShell modules
- For M365: Microsoft Graph PowerShell SDK
- JSON configuration files

### Installation

1. Clone/extract to `C:\Users\ADMIN\helios-platform\scripts\enterprise-monitoring`

2. Configure settings:

```powershell
# Edit configuration files
notepad config\monitoring-config.json
notepad config\alert-policies.json
```

3. Set Azure credentials (optional):

```powershell
$config = Get-Content config\monitoring-config.json | ConvertFrom-Json
$config.monitoring.azure.subscriptionIds = @("sub-id-1", "sub-id-2")
$config.monitoring.m365.tenantId = "your-tenant-id"
$config | ConvertTo-Json | Out-File config\monitoring-config.json
```

### Quick Start

#### Start Dashboard

```powershell
cd C:\Users\ADMIN\helios-platform\scripts\enterprise-monitoring
.\monitoring-orchestrator.ps1 -StartModule Dashboard
```

#### Start On-Premises Monitoring

```powershell
.\monitoring-orchestrator.ps1 -StartModule OnPrem
```

#### Start Azure Monitoring

```powershell
.\monitoring-orchestrator.ps1 -StartModule Azure
```

#### Start Microsoft 365 Monitoring

```powershell
.\monitoring-orchestrator.ps1 -StartModule M365
```

#### Start All Modules

```powershell
.\monitoring-orchestrator.ps1 -StartModule All
```

For parallel execution, run each module in a separate PowerShell window.

## 📋 Features

### Dashboard Module (400+ lines)

- **Real-time System View** - Live CPU, memory, disk, and network metrics
- **Service Status** - Critical Windows services monitoring
- **Alert Summary** - Aggregated alerts by severity
- **Health Indicators** - Color-coded system health status
- **Multiple Themes** - Dark, Light, Ocean, Retro themes with CSS export

### On-Premises Monitoring (300+ lines)

- **System Health** - OS info, boot time, update status
- **Resource Tracking** - CPU, memory, disk I/O per-process metrics
- **Security Monitoring** - Windows Defender, Firewall, UAC status
- **Performance Analytics** - Trend analysis and historical data
- **Threshold Alerts** - Configurable CPU, memory, disk thresholds

### Azure Integration (350+ lines)

- **Subscription Health** - Real-time Azure resource status
- **VM Performance** - CPU, disk, network metrics per VM
- **App Service Monitoring** - Response time, error rates, HTTP metrics
- **Cost Tracking** - Real-time cost analysis by service/cost center
- **Quota Tracking** - Resource quota utilization monitoring

### Microsoft 365 Monitoring (300+ lines)

- **Service Health** - Exchange, Teams, SharePoint status
- **Mail Flow** - Message processing, queue, and latency metrics
- **Teams Activity** - Active users, meetings, call duration
- **SharePoint Analytics** - Storage, document indexing, performance
- **User Management** - Active/inactive users, licensing alerts

### Compliance Monitoring (300+ lines)

- **Purview Alerts** - Data governance and protection
- **DLP Violations** - Policy violation tracking and enforcement
- **Audit Trail** - Comprehensive activity logging
- **Risk Scoring** - AI-based risk assessment and trending

### Analytics Engine (350+ lines)

- **Anomaly Detection** - Z-score based statistical analysis
- **Predictive Alerts** - Linear regression forecasting
- **Usage Predictions** - Behavioral pattern analysis
- **Cost Forecasting** - Budget trend prediction

### Reporting (300+ lines)

- **Executive Reports** - High-level KPI dashboard (HTML)
- **Technical Reports** - Detailed performance metrics
- **Compliance Reports** - Audit and governance documentation
- **Capacity Planning** - Resource trend analysis
- **Scheduled Distribution** - Daily/weekly/monthly automated delivery

## ⚙️ Configuration

### Main Configuration (monitoring-config.json)

```json
{
  "monitoring": {
    "environment": "production",
    "dashboard": {
      "refreshInterval": 5000,
      "theme": "dark"
    },
    "onPrem": {
      "cpuThreshold": 80,
      "memoryThreshold": 85,
      "diskThreshold": 90
    },
    "azure": {
      "subscriptionIds": [],
      "resourceGroups": []
    },
    "m365": {
      "tenantId": "",
      "enableMailFlowAnalysis": true
    }
  }
}
```

### Alert Policies (alert-policies.json)

- Configure alert severity levels
- Define policy rules (threshold, duration, action)
- Set escalation procedures
- Enable/disable alerts
- Configure notification channels

### Report Templates (report-templates.json)

- Customize report sections
- Define chart types and data
- Set distribution schedules
- Configure export formats

## 📊 Monitoring Metrics

### System Performance

- CPU utilization and load
- Memory usage and available
- Disk I/O and space
- Network bandwidth
- Process-level metrics

### Service Health

- Service status and uptime
- Response times
- Error rates
- Queue depths
- Connection counts

### Cloud Resources

- VM performance (CPU, disk, network)
- App Service metrics (requests, latency, errors)
- Storage utilization
- Database performance
- API response times

### Microsoft 365

- Service operational status
- Mail flow metrics
- Teams meeting/call data
- SharePoint storage
- User activity trends

### Compliance

- Policy violations
- Audit events
- Risk scores
- Data access logs
- Configuration changes

## 🔔 Alert Management

### Alert Lifecycle

1. **Detection** - Metric exceeds threshold or anomaly detected
2. **Creation** - Alert generated with unique ID
3. **Escalation** - Automatic escalation if not acknowledged
4. **Notification** - Sent via configured channels
5. **Acknowledgment** - User acknowledges receipt
6. **Resolution** - Issue resolved and alert closed

### Severity Levels

- **Critical** - Immediate action required (15-min escalation)
- **High** - Urgent attention needed (30-min escalation)
- **Medium** - Non-urgent action (60-min escalation)
- **Low** - Informational only (240-min escalation)
- **Info** - Status updates only

### Notification Channels

- Email (SMTP/Office 365)
- Microsoft Teams webhooks
- Slack webhooks
- PagerDuty integration
- Custom webhooks

## 📈 Reporting

### Report Types

**Executive Summary**

- KPI overview (uptime, availability)
- Incident summary
- Compliance status
- Cost summary

**Technical Report**

- Infrastructure performance
- Application metrics
- Azure resource performance
- Error and warning analysis

**Compliance Report**

- Framework compliance status
- DLP violation trends
- Audit trail summary
- Risk assessment

**Capacity Planning**

- Current utilization trends
- 12-month projections
- Azure quota analysis
- Recommendations

### Report Scheduling

- Daily: 02:00 UTC
- Weekly: Sunday 03:00 UTC
- Monthly: 1st day 04:00 UTC
- Custom schedules supported

## 🔐 Security

### Authentication

- Windows Authentication for on-premises
- Azure AD for cloud services
- Multi-factor authentication supported
- Service principal support

### Data Protection

- TLS encryption for data in transit
- Encrypted credential storage
- RBAC-based access control
- Audit logging of all actions

### Compliance

- GDPR compliant
- HIPAA ready
- SOC 2 Type II controls
- ISO 27001 alignment

## 📝 Logging

### Log Files

- Located in: `enterprise-monitoring\logs\`
- Daily log rotation (YYYY-MM-DD.log)
- Retention: 30 days (configurable)
- Format: [TIMESTAMP] [LEVEL] [COMPONENT] Message

### Log Levels

- **INFO** - General informational messages
- **WARNING** - Non-critical issues
- **ERROR** - Error conditions
- **DEBUG** - Detailed debugging information

### Viewing Logs

```powershell
# View today's logs
Get-Content "logs\$(Get-Date -Format 'yyyy-MM-dd').log" -Tail 50

# Search logs
Select-String "ERROR" logs\*.log

# Archive old logs
Remove-Item logs\*.log -Older 30days
```

## 🛠️ Customization

### Creating Custom Alerts

```powershell
$alert = New-AlertEvent `
    -AlertId "CUSTOM-001" `
    -Title "Custom Alert" `
    -Severity "High" `
    -Description "Custom monitoring condition met" `
    -Source "CustomMonitor"
```

### Adding Custom Metrics

```powershell
$metric = New-MetricValue `
    -Name "CustomMetric" `
    -Value 42 `
    -Unit "units" `
    -Source "CustomSource"
```

### Creating Custom Reports

- Edit report templates in `config\report-templates.json`
- Add new sections and charts
- Configure data sources
- Set distribution schedule

## 🐛 Troubleshooting

### Common Issues

**Module fails to load**

```powershell
# Check module paths
Test-Path "C:\Users\ADMIN\helios-platform\scripts\enterprise-monitoring\lib\monitoring-library.ps1"

# Verify PowerShell version
$PSVersionTable.PSVersion
```

**Azure connection fails**

```powershell
# Reconnect to Azure
Connect-AzAccount -TenantId "your-tenant-id"

# Verify subscription
Get-AzSubscription
```

**M365 authentication errors**

```powershell
# Clear cached credentials
Remove-Item "$env:APPDATA\Microsoft\*" -Force -Recurse

# Reconnect
Connect-MgGraph -Scopes "Organization.Read.All"
```

### Performance Optimization

- Increase cache duration for high-latency networks
- Reduce refresh intervals on powerful servers
- Enable batch processing for large datasets
- Archive old reports to external storage

## 📞 Support & Contribution

For issues or feature requests:

1. Check logs for error messages
2. Review configuration files
3. Consult module-specific documentation
4. Open issue with detailed logs

## 📄 License

Production-Ready Enterprise Software. All rights reserved.

## 🎯 Roadmap

- [ ] Grafana integration
- [ ] Prometheus metrics export
- [ ] Mobile app for alerts
- [ ] Advanced ML models
- [ ] Multi-tenant support
- [ ] API gateway
- [ ] Custom dashboard builder
- [ ] Webhook triggers

## 📚 Additional Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [Azure PowerShell](https://docs.microsoft.com/powershell/azure/)
- [Microsoft Graph PowerShell](https://docs.microsoft.com/graph/powershell/overview)
- [Windows Performance Toolkit](https://docs.microsoft.com/windows-hardware/test/wpt/)

---

**Version:** 1.0.0  
**Last Updated:** 2024-Q2  
**Support Email:** monitoring-support@enterprise.com
