# Analytics Core Component

Comprehensive data collection, analysis, and reporting system for HELIOS Platform.

---

## Overview

Analytics Core collects system and custom metrics, performs analysis, and generates reports. Build dashboards, track trends, and export data for business intelligence.

**Key Facts:**

- **Phase:** 1
- **Standalone:** ✅ Yes - Fully independent
- **Requires:** .NET Framework 4.6.1+, SQL Server Express (optional)
- **Version:** 1.0.3
- **Size:** 178 MB
- **Installation Time:** 4-6 minutes

---

## What It Does

### Core Features

1. **Data Collection**
   - System metrics collection
   - Custom metric ingestion
   - Event logging
   - Real-time data pipeline

2. **SQL Analysis**
   - Query builder interface
   - Custom SQL queries
   - Aggregations and grouping
   - Time-series analysis

3. **Report Generation**
   - Scheduled reports
   - Custom report builder
   - Multiple export formats
   - Email delivery

4. **Data Visualization**
   - Interactive charts
   - Trend graphs
   - Custom dashboards
   - Real-time streaming

5. **Data Export**
   - Excel (.xlsx)
   - PDF (.pdf)
   - CSV (.csv)
   - JSON (.json)

---

## System Requirements

### Minimum

- **OS:** Windows Server 2016+ or Windows 8.1+
- **.NET Framework:** 4.6.1+
- **RAM:** 2 GB
- **Disk:** 250 MB available
- **Database:** Embedded SQLite (included)

### Recommended

- **OS:** Windows Server 2019+
- **.NET Framework:** 4.8+
- **RAM:** 4+ GB
- **Disk:** 1 GB available
- **Database:** SQL Server Express (free)

---

## Installation Procedure

### Quick Install (Embedded Database)

```powershell
cd C:\Users\ADMIN\helios-platform\components\analytics-core
.\install.ps1

# Uses embedded SQLite
# Good for: Small deployments, development
# Limit: ~100K records max
```

### With SQL Server

```powershell
.\install.ps1 -DatabaseType "SqlServer" `
    -ConnectionString "Server=localhost\SQLEXPRESS;Database=HeliosAnalytics;Integrated Security=True"

# Better for: Production, large data volumes
# Supports: Unlimited records, advanced features
```

---

## Configuration

**Config File:** `C:\Program Files\HELIOS\analytics-core\config.json`

```json
{
  "database": {
    "type": "embedded",
    "path": "C:\\Program Files\\HELIOS\\analytics-core\\data",
    "retentionDays": 365,
    "autoArchive": true
  },

  "collection": {
    "enabled": true,
    "interval": 60,
    "batchSize": 100,
    "bufferSize": 10000
  },

  "reporting": {
    "formats": ["Excel", "PDF", "CSV", "JSON"],
    "defaultFormat": "Excel",
    "compression": true
  },

  "performance": {
    "maxQueryTime": 300,
    "cacheEnabled": true,
    "cacheTTL": 3600
  }
}
```

---

## Usage Examples

### Collect Custom Metrics

```powershell
$analytics = New-Object HeliosPlatform.AnalyticsCore.AnalyticsEngine

# Record application metrics
$metrics = @{
    Timestamp = Get-Date
    ApplicationName = "MyApp"
    ResponseTime = 120
    RequestCount = 1500
    ErrorCount = 3
}

$analytics.RecordMetrics($metrics)
```

### Query Data

```powershell
# Simple query
$data = $analytics.Query(@"
    SELECT * FROM metrics
    WHERE Timestamp > DATEADD(day, -7, GETDATE())
    ORDER BY Timestamp DESC
"@)

foreach ($row in $data) {
    Write-Host "$($row.Timestamp): $($row.Metric) = $($row.Value)"
}
```

### Generate Report

```powershell
$report = $analytics.CreateReport(
    "Performance Report",
    @"
        SELECT 
            DATE(Timestamp) as Date,
            AVG(ResponseTime) as AvgResponseTime,
            MAX(ResponseTime) as MaxResponseTime,
            COUNT(*) as RequestCount
        FROM metrics
        WHERE Timestamp > DATEADD(day, -30, GETDATE())
        GROUP BY DATE(Timestamp)
        ORDER BY Date DESC
    "@
)

$report.ExportToExcel("C:\Reports\performance-report.xlsx")
```

### Schedule Report

```powershell
$schedule = New-Object HeliosPlatform.AnalyticsCore.ReportSchedule

$schedule.CreateSchedule(
    -ReportName "Weekly Performance"
    -Query "SELECT * FROM metrics WHERE..."
    -Format "PDF"
    -Schedule "Weekly"
    -DayOfWeek "Monday"
    -Time "06:00"
    -EmailTo "admin@company.com"
)
```

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\analytics-core\

Application Files:
├── bin\
│   ├── analytics.exe
│   └── analytics.dll

Configuration:
├── config.json

Database:
├── data\
│   ├── analytics.db (if using embedded SQLite)
│   └── backups\

Reports:
├── reports\
│   ├── generated-reports\
│   └── templates\

Logs:
├── logs\
│   └── analytics.log
```

---

## Troubleshooting

### Database Connection Failed

```powershell
# For embedded database:
# Check file exists
Test-Path "C:\Program Files\HELIOS\analytics-core\data\analytics.db"

# For SQL Server:
# Test connection
sqlcmd -S localhost\SQLEXPRESS -d HeliosAnalytics -Q "SELECT 1"
```

### Reports Not Generating

```powershell
# Check query syntax
.\test-query.ps1 -Query "SELECT * FROM metrics"

# Verify permissions
.\check-permissions.ps1
```

---

## Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\analytics-core

# Preserve data
.\uninstall.ps1 -PreserveData

# Export before removal
.\uninstall.ps1 -ExportData -ExportPath "C:\Analytics-Export"
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.3 | 2023-12-15 | Performance improvements |
| 1.0.0 | 2023-11-01 | Initial release |

---

## Support

See main component documentation for details.
