# AI Dashboard Component

Professional GUI dashboard for HELIOS Platform system monitoring and management.

---

## Overview

The AI Dashboard is a web-based real-time monitoring interface for the HELIOS Platform. Monitor system performance, view alerts, and manage platform features through an intuitive graphical interface.

**Key Facts:**

- **Phase:** 3 (can be borrowed to earlier phases)
- **Standalone:** ✅ Yes - Works independently
- **Dependencies:** .NET Framework 4.8+, Windows Event Log
- **Version:** 2.1.0
- **Size:** 245 MB
- **Installation Time:** 5-10 minutes

---

## What It Does

### Core Features

1. **Real-Time Monitoring**
   - CPU, memory, disk, network usage
   - System health indicators
   - Performance scoring
   - Alert notifications

2. **Dashboard Customization**
   - Drag-and-drop widgets
   - Custom metric selection
   - Saved dashboard layouts
   - Light/dark theme

3. **Historical Analytics**
   - 30-day performance history
   - Trend analysis
   - Peak usage identification
   - Data export (Excel, PDF, CSV)

4. **Alert Management**
   - Configurable alert thresholds
   - Email notifications
   - Severity levels
   - Alert history

5. **Multi-User Support** (with security-engine)
   - User authentication
   - Role-based access
   - Audit logging
   - Session management

---

## System Requirements

### Minimum

- **OS:** Windows Server 2019+ or Windows 10 Pro+
- **.NET Framework:** 4.8+
- **RAM:** 2 GB
- **Disk:** 350 MB available
- **Port:** 8080 (configurable)
- **Browser:** Chrome 90+, Edge 90+, Firefox 88+

### Recommended

- **OS:** Windows Server 2022
- **.NET Framework:** 4.8.1+
- **RAM:** 4+ GB
- **Disk:** 1 GB available
- **CPU:** Multi-core processor
- **Internet:** Required for updates only

### Browser Compatibility

```
Chrome:     90+
Edge:       90+
Firefox:    88+
Safari:     14+
Opera:      76+

Not supported:
- Internet Explorer
- Legacy Edge (Chromium-based Edge only)
```

---

## Installation Procedure

### Quick Install

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\install.ps1
```

### With Custom Port

```powershell
.\install.ps1 -Port 9000
# Dashboard accessible at http://localhost:9000
```

### With HTTPS/SSL

```powershell
.\install.ps1 -UseSSL `
    -CertificatePath "C:\certs\dashboard.pfx" `
    -CertificatePassword "your-password"
```

### Silent Installation

```powershell
.\install.ps1 -Silent -Port 8080
# Installs without prompts
# Default credentials saved to: C:\Program Files\HELIOS\ai-dashboard\initial-password.txt
```

### With Security-Engine Integration

```powershell
# First install security-engine
..\security-engine\install.ps1

# Then install dashboard
.\install.ps1 -EnableAuthentication
# Dashboard now requires login
```

### Docker Installation (If Available)

```bash
docker pull helios/ai-dashboard:2.1.0
docker run -d \
  -p 8080:8080 \
  -v /var/helios/dashboard:/data \
  --name helios-dashboard \
  helios/ai-dashboard:2.1.0
```

---

## Configuration Options

**Config File:** `C:\Program Files\HELIOS\ai-dashboard\config.json`

```json
{
  "server": {
    "port": 8080,
    "host": "0.0.0.0",
    "useSSL": false,
    "certificatePath": null,
    "certificatePassword": null,
    "sessionTimeout": 3600,
    "maxConnections": 100
  },

  "display": {
    "theme": "dark",
    "language": "en-US",
    "refreshInterval": 5000,
    "chartHistorySize": 100,
    "dateFormat": "yyyy-MM-dd HH:mm:ss"
  },

  "security": {
    "requireAuth": false,
    "defaultUser": "admin",
    "allowRemoteAccess": false,
    "corsEnabled": false,
    "corsOrigins": []
  },

  "monitoring": {
    "cpuEnabled": true,
    "memoryEnabled": true,
    "diskEnabled": true,
    "networkEnabled": true,
    "processEnabled": true
  },

  "notifications": {
    "enabled": true,
    "emailAlerts": false,
    "emailAddress": null,
    "slackWebhook": null,
    "alertThresholds": {
      "cpuPercent": 80,
      "memoryPercent": 85,
      "diskPercent": 90
    }
  },

  "database": {
    "type": "embedded",
    "path": "C:\\Program Files\\HELIOS\\ai-dashboard\\data",
    "retentionDays": 30
  },

  "logging": {
    "enabled": true,
    "path": "C:\\Program Files\\HELIOS\\ai-dashboard\\logs",
    "level": "Info",
    "maxLogSize": "10MB"
  }
}
```

### Common Configuration Changes

**Enable Authentication:**

```json
{
  "security": {
    "requireAuth": true,
    "defaultUser": null
  }
}
```

**Allow Remote Access:**

```json
{
  "server": {
    "host": "0.0.0.0",
    "allowRemoteAccess": true
  },
  "security": {
    "corsEnabled": true,
    "corsOrigins": ["*"]
  }
}
```

**Change Refresh Rate (Slower = Less Load):**

```json
{
  "display": {
    "refreshInterval": 10000
  }
}
```

**Email Alerts:**

```json
{
  "notifications": {
    "emailAlerts": true,
    "emailAddress": "admin@company.com"
  }
}
```

---

## First Access

### Standalone Mode (No Authentication)

1. Install dashboard: `.\install.ps1`
2. Open browser: `http://localhost:8080`
3. No login required - dashboard loads immediately

### With Authentication (security-engine installed)

1. Check initial credentials: `type "C:\Program Files\HELIOS\ai-dashboard\initial-password.txt"`
2. Open browser: `http://localhost:8080`
3. Login with credentials
4. Change password immediately: Dashboard → Settings → Security

---

## Usage Examples

### Monitor System in Real-Time

```
1. Open http://localhost:8080
2. Dashboard shows:
   - Current CPU: 25%
   - Current Memory: 60%
   - Disk Usage: 45%
   - Network: 150 Mbps
   - Alert status
3. Metrics update every 5 seconds (configurable)
```

### Set Alert Thresholds

```
1. Dashboard → Settings → Alerts
2. Set thresholds:
   - CPU Alert: 80%
   - Memory Alert: 85%
   - Disk Alert: 90%
3. When exceeded, alert displays in dashboard
4. Optional: Email notification (configure in config.json)
```

### Export Performance Report

```
1. Dashboard → Reports
2. Select date range
3. Export format:
   - Excel (.xlsx)
   - PDF (.pdf)
   - CSV (.csv)
4. Download generated report
```

### View Historical Trends

```
1. Dashboard → Analytics → Trends
2. Select metric (CPU, Memory, Disk)
3. Select time range (1 week, 1 month, custom)
4. View trend graph
5. Identify patterns and peaks
```

---

## Troubleshooting

### Can't Access Dashboard

**Error:** "Cannot connect to localhost:8080"

**Causes and Solutions:**

```powershell
# Check if service is running
Get-Service "HELIOS-Dashboard" | Select-Object Status

# If stopped, start it
Start-Service "HELIOS-Dashboard"

# Check if port is in use
netstat -ano | findstr :8080

# If port in use, change it in config.json
# Edit: "port": 8080 → "port": 9000
# Restart service

# Check firewall
netsh advfirewall firewall add rule name="HELIOS-Dashboard" dir=in action=allow protocol=tcp localport=8080
```

### High Memory Usage

**Symptom:** Dashboard uses lots of RAM

**Solutions:**

```json
{
  "display": {
    "refreshInterval": 10000,
    "chartHistorySize": 50
  },
  "database": {
    "retentionDays": 7
  }
}
```

Then restart service.

### Dashboard Slow or Unresponsive

**Causes:**

1. Too many connected clients
2. Slow system collecting metrics
3. Large chart history

**Solutions:**

```powershell
# Reduce max connections in config.json
# "maxConnections": 50

# Disable unnecessary metrics
{
  "monitoring": {
    "processEnabled": false,
    "networkEnabled": false
  }
}

# Increase chart history size limit
{
  "display": {
    "chartHistorySize": 50
  }
}

# Restart
Restart-Service "HELIOS-Dashboard"
```

### Login Issues

**Error:** "Invalid credentials"

**Solution:**

```powershell
# Reset to default credentials
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

.\reset-credentials.ps1

# View new credentials
type "C:\Program Files\HELIOS\ai-dashboard\initial-password.txt"

# Login again
# Change password immediately
```

---

## Performance Tuning

### For High-Traffic Monitoring

```json
{
  "server": {
    "maxConnections": 200,
    "sessionTimeout": 1800
  },
  "display": {
    "refreshInterval": 2000
  },
  "database": {
    "retentionDays": 90
  }
}
```

### For Low-Resource Systems

```json
{
  "server": {
    "maxConnections": 20
  },
  "display": {
    "refreshInterval": 15000,
    "chartHistorySize": 20
  },
  "monitoring": {
    "processEnabled": false
  },
  "database": {
    "retentionDays": 7
  }
}
```

---

## Integration with Other Components

### With security-engine

```powershell
# Install security-engine first
..\security-engine\install.ps1

# Reinstall dashboard to enable authentication
.\install.ps1

# Dashboard now:
# ✅ Requires login
# ✅ Supports multiple users
# ✅ Has role-based access
# ✅ Logs all access
```

### With vault-dynamics

Dashboard shows vault status in:

- Dashboard → Components → Vault Status
- Encryption statistics
- Key rotation schedule

### With analytics-core

Dashboard displays analytics data:

- Dashboard → Analytics
- Custom reports
- Data visualization

### With performance-ai

Dashboard shows AI recommendations:

- Dashboard → Insights → AI Recommendations
- Performance scores
- Optimization suggestions

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\ai-dashboard\

Application Files:
├── bin\
│   ├── dashboard.exe (main executable)
│   ├── dashboard.dll (core library)
│   ├── dependencies\ (support DLLs)
│   └── ...

Configuration:
├── config.json (main configuration)
├── initial-password.txt (default credentials)

Data:
├── data\
│   ├── metrics.db (metrics database)
│   └── ...

Web Files:
├── www\
│   ├── index.html
│   ├── css\ (stylesheets)
│   ├── js\ (client-side scripts)
│   └── assets\

Logs:
├── logs\
│   ├── dashboard.log (application log)
│   └── errors.log (error log)

Certificates (if SSL):
├── certificates\
│   └── dashboard.pfx
```

---

## Security Considerations

### Standalone Mode Risks

When running without security-engine:

- Anyone with network access can view metrics
- No user authentication
- No audit logging
- Recommend for isolated/internal networks only

**Fix:**

```powershell
# Install security-engine for authentication
..\security-engine\install.ps1
```

### HTTPS/SSL Best Practice

```powershell
# Always use HTTPS for remote access
.\install.ps1 -UseSSL `
    -CertificatePath "C:\certs\dashboard.pfx"

# Redirect HTTP to HTTPS in config.json
{
  "server": {
    "redirectHttpToHttps": true
  }
}
```

### Restrict Network Access

```powershell
# Only allow specific IPs
netsh advfirewall firewall add rule name="HELIOS-Dashboard" `
    dir=in action=allow protocol=tcp localport=8080 `
    remoteip=192.168.1.0/24
```

---

## Backup and Recovery

### Backup Dashboard Data

```powershell
# Backup configuration and metrics
Copy-Item "C:\Program Files\HELIOS\ai-dashboard\data" `
    -Destination "C:\Backup\dashboard-data" -Recurse

Copy-Item "C:\Program Files\HELIOS\ai-dashboard\config.json" `
    -Destination "C:\Backup\dashboard-config.json"
```

### Restore Dashboard

```powershell
# Stop service
Stop-Service "HELIOS-Dashboard"

# Restore from backup
Copy-Item "C:\Backup\dashboard-data" `
    -Destination "C:\Program Files\HELIOS\ai-dashboard\data" -Recurse -Force

Copy-Item "C:\Backup\dashboard-config.json" `
    -Destination "C:\Program Files\HELIOS\ai-dashboard\config.json" -Force

# Start service
Start-Service "HELIOS-Dashboard"
```

---

## Uninstall

### Remove Dashboard

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Keep configuration and data
.\uninstall.ps1 -PreserveConfig

# Remove everything
.\uninstall.ps1 -CompleteCleanup
```

### Verify Removal

```powershell
# Check if directory removed
Test-Path "C:\Program Files\HELIOS\ai-dashboard"
# Should be: $false

# Check if service removed
Get-Service "HELIOS-Dashboard" -ErrorAction SilentlyContinue
# Should return: Nothing
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | 2024-01-15 | Improved chart rendering, new alert system |
| 2.0.5 | 2023-12-20 | Bug fixes, security enhancements |
| 2.0.0 | 2023-11-01 | Major redesign, new UI |
| 1.5.0 | 2023-09-15 | Initial stable release |

---

## Support

- **Issues:** See troubleshooting section above
- **Configuration Help:** Review COMPONENT_CATALOG.md
- **Borrowing Usage:** See BORROWING_GUIDE.md
- **Standalone Usage:** See INDEPENDENT_INSTALLATION.md
