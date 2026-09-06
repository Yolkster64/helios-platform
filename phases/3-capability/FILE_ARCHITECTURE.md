# HELIOS Phase 3: File Architecture & Directory Structure

This document explains where Phase 3 components and data are stored on your system.

---

## 📁 High-Level Directory Structure

```
C:\
├─ Program Files\
│  └─ HELIOS\
│     ├─ Dashboard\              ← GUI monitoring interface
│     ├─ AI\                     ← Machine learning models
│     ├─ AutoHealing\            ← Auto-fix services
│     ├─ Profiles\               ← Custom profiles
│     ├─ Workflows\              ← Workflow definitions
│     ├─ PerformanceAI\          ← Performance optimization
│     ├─ Reporting\              ← Report generation
│     └─ Logs\                   ← All service logs
│
├─ helios\                        ← Installation root (if installed here)
│  ├─ scripts\                   ← Phase 3 PowerShell scripts
│  ├─ config\                    ← Configuration files
│  ├─ data\                      ← Temporary data
│  ├─ logs\                      ← Accessible logs
│  └─ reports\                   ← Generated reports (HTML, PDF)
│
├─ Users\ADMIN\AppData\Local\
│  └─ HELIOS\
│     └─ Cache\                  ← Dashboard cache
│
└─ ProgramData\HELIOS\
   ├─ database\                  ← PostgreSQL data directory
   ├─ models\                    ← ML model storage
   └─ workflows\                 ← Workflow execution temp files
```

---

## 🖥️ Component 1: Dashboard Application

### Location

```
C:\Program Files\HELIOS\Dashboard\
```

### Directory Structure

```
C:\Program Files\HELIOS\Dashboard\
├─ app\
│  ├─ index.js               ← Main application entry
│  ├─ server.js              ← Express.js web server
│  ├─ config.js              ← Dashboard configuration
│  └─ package.json           ← Node.js dependencies
│
├─ public\
│  ├─ index.html             ← Main dashboard page
│  ├─ css\                   ← Styling files
│  ├─ js\                    ← Client-side JavaScript
│  └─ img\                   ← Logos, icons
│
├─ views\
│  ├─ dashboard.html         ← Main dashboard view
│  ├─ metrics.html           ← Metrics & charts
│  ├─ alerts.html            ← Alert management
│  ├─ workflows.html         ← Workflow status
│  └─ settings.html          ← Configuration UI
│
├─ data\
│  ├─ themes.json            ← UI theme configurations
│  ├─ layout.json            ← Dashboard layout presets
│  └─ preferences.json       ← User preferences
│
├─ logs\
│  ├─ dashboard.log          ← Application logs
│  ├─ access.log             ← HTTP access log
│  └─ errors.log             ← Error log
│
└─ node_modules\             ← JavaScript dependencies (auto-installed)
```

### Key Files

| File | Purpose | Editable |
|------|---------|----------|
| `app/config.js` | Port, database connection, theme | ✅ Yes |
| `public/css/` | Customize dashboard appearance | ✅ Yes |
| `data/preferences.json` | User settings, saved views | ✅ Yes |
| `logs/dashboard.log` | Troubleshooting | ❌ Read-only |

### Access Points

- **Web Interface:** http://localhost:9000
- **API Endpoint:** http://localhost:9000/api
- **WebSocket:** ws://localhost:9000 (real-time updates)
- **Service Name:** HELIOS-Dashboard (Windows Service)

---

## 🤖 Component 2: AI Learning Engine

### Location

```
C:\Program Files\HELIOS\AI\
```

### Directory Structure

```
C:\Program Files\HELIOS\AI\
├─ models\
│  ├─ baseline\
│  │  ├─ traffic-predictor.pkl     ← Traffic pattern ML model
│  │  ├─ resource-predictor.pkl    ← Resource usage model
│  │  ├─ error-detector.pkl        ← Error pattern detection
│  │  ├─ anomaly-detector.pkl      ← Anomaly detection model
│  │  ├─ correlation-analyzer.pkl  ← Multi-factor correlations
│  │  └─ performance-model.pkl     ← Performance patterns
│  │
│  ├─ v1\                          ← Model version 1 (backup)
│  ├─ v2\                          ← Model version 2 (current)
│  └─ latest\                      ← Symlink to current version
│
├─ training\
│  ├─ datasets\
│  │  ├─ phase2-historical.csv     ← Phase 2 baseline data
│  │  ├─ recent-7days.csv          ← Last 7 days training data
│  │  └─ recent-30days.csv         ← Last 30 days training data
│  │
│  ├─ logs\
│  │  ├─ training.log              ← Training progress
│  │  ├─ validation.log            ← Model validation results
│  │  └─ accuracy.log              ← Accuracy metrics over time
│  │
│  └─ checkpoints\
│     ├─ epoch-1.pkl               ← Training checkpoint 1
│     ├─ epoch-2.pkl               ← Training checkpoint 2
│     └─ best-model.pkl            ← Best model so far
│
├─ predictions\
│  ├─ next-24h.json               ← Next 24 hour predictions
│  ├─ next-7d.json                ← Next 7 day predictions
│  ├─ confidence.json             ← Confidence levels
│  └─ historical\
│     ├─ 2024-02-15.json          ← Predictions from that day
│     ├─ 2024-02-14.json          ← Previous day
│     └─ (archive of all predictions)
│
├─ engine\
│  ├─ learning.py                ← Main ML training script
│  ├─ predictor.py               ← Prediction engine
│  ├─ correlations.py            ← Pattern correlation module
│  ├─ requirements.txt            ← Python dependencies
│  └─ config.yaml                ← AI configuration
│
└─ logs\
   ├─ ai-engine.log             ← Main AI service log
   ├─ predictions.log           ← Prediction execution log
   └─ errors.log                ← Error log
```

### Key Files

| File | Purpose | Editable |
|------|---------|----------|
| `models/latest/` | Current active ML models | ❌ No (auto-updated) |
| `training/datasets/` | Historical data for training | ❌ No (system-managed) |
| `predictions/next-24h.json` | Current predictions | ❌ No (auto-updated) |
| `engine/config.yaml` | Learning parameters | ✅ Yes (advanced users) |

### How AI Models Are Updated

```
Daily 1:00 AM
├─ Load last 7 days of production data
├─ Retrain all 6 ML models
├─ Validate new models against test set
├─ Compare accuracy with current models
├─ If better: Deploy new model to 'latest\'
└─ If worse: Keep current model, alert engineer

Weekly 3:00 AM
├─ Full retraining on 30 days of data
├─ Deep accuracy analysis
├─ Update correlation models
└─ Archive old model versions
```

### Disk Space Usage

```
Typical Storage:
├─ Models: 50-100 MB (6 models, multiple versions)
├─ Training Datasets: 200-500 MB (7-30 days of data)
├─ Predictions Archive: 100-200 MB (90 days of predictions)
└─ Logs: 50-100 MB (rolling 30-day window)

Total: ~500 MB to 1 GB typical

Max: 5 GB (with full 365-day history)
```

---

## 🔧 Component 3: Auto-Healing System

### Location

```
C:\Program Files\HELIOS\AutoHealing\
```

### Directory Structure

```
C:\Program Files\HELIOS\AutoHealing\
├─ rules\
│  ├─ database-rules.json       ← Database healing rules
│  ├─ cache-rules.json          ← Cache healing rules
│  ├─ memory-rules.json         ← Memory management rules
│  ├─ disk-rules.json           ← Disk space rules
│  ├─ network-rules.json        ← Network connectivity rules
│  ├─ service-rules.json        ← Service restart rules
│  ├─ security-rules.json       ← Security incident rules
│  └─ custom-rules.json         ← User-defined rules
│
├─ actions\
│  ├─ restart-service.ps1       ← Service restart action
│  ├─ expand-pool.ps1           ← Connection pool expansion
│  ├─ flush-cache.ps1           ← Cache clearing action
│  ├─ archive-logs.ps1          ← Log archival action
│  ├─ cleanup-temp.ps1          ← Temp file cleanup
│  ├─ trigger-gc.ps1            ← Garbage collection trigger
│  ├─ scale-up.ps1              ← Resource scaling
│  └─ custom\                   ← User-defined actions
│
├─ detectors\
│  ├─ connection-pool-detector.exe
│  ├─ memory-leak-detector.exe
│  ├─ disk-space-detector.exe
│  ├─ response-time-detector.exe
│  └─ anomaly-detector.exe
│
├─ logs\
│  ├─ healing-engine.log        ← Main service log
│  ├─ healing-actions.log       ← Actions taken
│  ├─ healing-success.log       ← Successful heals
│  └─ healing-failures.log      ← Failed healing attempts
│
└─ tickets\
   ├─ auto-created-tickets.json ← Generated support tickets
   └─ healing-history.json      ← All healing events this month
```

### Healing Rules Example

```json
{
  "connection-pool-exhaustion": {
    "detector": "connection-pool-detector",
    "threshold": "pool usage > 95%",
    "action": "expand-pool.ps1",
    "parameters": {
      "increase-by": 30,
      "max-pool-size": 500
    },
    "alert": "create-ticket",
    "monitoring-after": true
  }
}
```

### Auto-Healing Log Example

```
[2024-02-15 14:32:15] DETECTION: Connection pool at 98%
[2024-02-15 14:32:16] ACTION: Executing expand-pool.ps1
[2024-02-15 14:32:18] SUCCESS: Pool expanded 100→130 connections
[2024-02-15 14:32:19] TICKET: Auto-created #4521 for follow-up review
[2024-02-15 14:32:20] MONITORING: Observing pool for 5 minutes
[2024-02-15 14:37:20] RESOLVED: Pool stable at 45%, issue resolved
```

---

## 👤 Component 4: Profile Management

### Location

```
C:\Program Files\HELIOS\Profiles\
```

### Directory Structure

```
C:\Program Files\HELIOS\Profiles\
├─ builtin\
│  ├─ normal.json              ← Default profile
│  ├─ high-traffic.json        ← Black Friday / peak times
│  ├─ low-cost.json            ← Off-hours cost minimization
│  ├─ latency-critical.json    ← Real-time trading / gaming
│  ├─ development.json         ← Testing / development
│  ├─ batch-processing.json    ← Large batch jobs
│  └─ backup-restore.json      ← Backup/restore operations
│
├─ custom\
│  ├─ my-app-startup.json      ← User-created profiles
│  ├─ my-app-steady.json       ← User-created profiles
│  └─ my-specific-workload.json ← User-created profiles
│
├─ scheduled\
│  ├─ business-hours.json      ← 7 AM-6 PM: Normal
│  │                           ← 6 PM-7 AM: LowCost
│  ├─ peak-season.json         ← Dec 1-Jan 15: HighTraffic
│  └─ maintenance-window.json  ← First Sunday: Maintenance
│
├─ active\
│  └─ current.json             ← Currently active profile (symlink)
│
└─ history\
   ├─ profile-changes.log      ← When profiles were switched
   ├─ 2024-02-15.json          ← Profile used that day
   └─ (archive of all daily profiles)
```

### Profile Definition Example

```json
{
  "name": "HighTraffic",
  "description": "For Black Friday / major events",
  "cache": {
    "strategy": "aggressive",
    "memory-allocation": "8GB",
    "ttl": "5m",
    "preload": true
  },
  "database": {
    "connection-pool": 500,
    "max-connections": 1000,
    "timeout": "30s"
  },
  "api": {
    "request-timeout": "30s",
    "rate-limiting": "disabled",
    "queue-size": 50000
  },
  "ai": {
    "prediction-window": "4h",
    "auto-scaling": "enabled",
    "learning-mode": false
  },
  "cost": {
    "expected-hourly": "$85",
    "budget-alert": "$1000"
  }
}
```

---

## ⚙️ Component 5: Automation Workflows

### Location

```
C:\Program Files\HELIOS\Workflows\
```

### Directory Structure

```
C:\Program Files\HELIOS\Workflows\
├─ builtin\                    ← Pre-built by HELIOS
│  ├─ daily-backup.json
│  ├─ weekly-maintenance.json
│  ├─ monthly-optimization.json
│  ├─ high-traffic-response.json
│  ├─ quarterly-review.json
│  └─ (245 more pre-built workflows)
│
├─ custom\                     ← User-created workflows
│  ├─ my-custom-workflow.json
│  └─ (user workflows)
│
├─ execution\
│  ├─ logs\
│  │  ├─ daily-backup-2024-02-15.log
│  │  ├─ daily-backup-2024-02-14.log
│  │  └─ (execution logs for each workflow run)
│  │
│  └─ state\
│     ├─ daily-backup-current.json    ← Current execution state
│     ├─ weekly-maintenance-current.json
│     └─ (state for each running workflow)
│
├─ schedule\
│  ├─ daily.json               ← Daily workflows (250 workflows)
│  ├─ weekly.json              ← Weekly workflows (50 workflows)
│  ├─ monthly.json             ← Monthly workflows (25 workflows)
│  ├─ on-trigger.json          ← Event-triggered workflows (75)
│  └─ custom-schedule.json     ← User-defined schedules
│
└─ history\
   ├─ 2024-02-15\              ← Today's executions
   ├─ 2024-02-14/              ← Yesterday's executions
   └─ (rolling 90-day history)
```

### Workflow Definition Example

```json
{
  "name": "DailyBackup",
  "enabled": true,
  "schedule": "every day at 2:00 AM",
  "timeout": "30 minutes",
  "steps": [
    {
      "id": "step1",
      "name": "Create backup",
      "action": "backup-database",
      "parameters": {"target": "S3://backups/daily/"}
    },
    {
      "id": "step2",
      "name": "Verify backup",
      "action": "verify-backup",
      "depends-on": "step1"
    },
    {
      "id": "step3",
      "name": "Test restore",
      "action": "test-restore",
      "depends-on": "step2"
    },
    {
      "id": "step4",
      "name": "Send report",
      "action": "send-email",
      "parameters": {
        "to": "ops@company.com",
        "depends-on": "step3"
      }
    }
  ],
  "notifications": {
    "on-success": "admin@company.com",
    "on-failure": ["admin@company.com", "oncall@company.com"]
  }
}
```

---

## ⚡ Component 6: Performance AI

### Location

```
C:\Program Files\HELIOS\PerformanceAI\
```

### Directory Structure

```
C:\Program Files\HELIOS\PerformanceAI\
├─ models\
│  ├─ cache-optimizer.pkl      ← Cache optimization model
│  ├─ query-optimizer.pkl      ← Database query optimization
│  ├─ resource-allocator.pkl   ← Resource allocation model
│  └─ bottleneck-predictor.pkl ← Performance bottleneck detector
│
├─ analysis\
│  ├─ queries\
│  │  ├─ slow-queries.json     ← Queries taking >1 sec
│  │  ├─ missing-indexes.json  ← Missing database indexes
│  │  └─ join-analysis.json    ← Expensive joins detected
│  │
│  ├─ cache\
│  │  ├─ hit-rate.json         ← Cache hit/miss analysis
│  │  ├─ optimization.json     ← Cache tuning recommendations
│  │  └─ item-popularity.json  ← What's being cached
│  │
│  └─ resources\
│     ├─ memory-analysis.json
│     ├─ cpu-analysis.json
│     └─ bottleneck-report.json
│
├─ recommendations\
│  ├─ next-48h.json            ← Optimizations for next 2 days
│  ├─ priority.json            ← High-impact recommendations
│  └─ history\
│     ├─ 2024-02-15.json       ← Today's recommendations
│     └─ (daily recommendations archive)
│
└─ logs\
   ├─ optimization-engine.log
   ├─ recommendations.log
   └─ applied-optimizations.log
```

### Recommendation Example

```json
{
  "recommendation-id": "REC-00451",
  "type": "add-database-index",
  "impact": {
    "query": "SELECT * FROM orders WHERE user_id = ? AND status = 'pending'",
    "current-time": "2.3 seconds",
    "predicted-time": "185 milliseconds",
    "improvement": "92%",
    "confidence": 94
  },
  "implementation": "CREATE INDEX idx_orders_user_status ON orders(user_id, status);",
  "cost": "2 minutes downtime",
  "benefit": "40% reduction in peak load times",
  "priority": "high"
}
```

---

## 📊 Component 7: Reporting System

### Location

```
C:\Program Files\HELIOS\Reporting\
```

### Directory Structure

```
C:\Program Files\HELIOS\Reporting\
├─ templates\
│  ├─ daily-executive.html     ← 1-page executive summary
│  ├─ daily-executive.pdf      ← PDF version
│  ├─ weekly-technical.html    ← 5-page technical report
│  ├─ weekly-technical.pdf     ← PDF version
│  ├─ monthly-business.html    ← Business impact report
│  ├─ quarterly-board.html     ← Board-level report
│  └─ custom-template.html     ← User-defined templates
│
├─ generated\
│  ├─ 2024-02-15\
│  │  ├─ daily-executive.html
│  │  ├─ daily-executive.pdf
│  │  ├─ weekly-technical.html
│  │  └─ weekly-technical.pdf
│  │
│  ├─ 2024-02-14/
│  └─ (rolling 365-day archive)
│
├─ data\
│  ├─ metrics.json             ← Aggregated metrics for reports
│  ├─ predictions.json         ← AI predictions included in reports
│  ├─ incidents.json           ← Incidents that occurred
│  └─ costs.json               ← Cost data
│
├─ schedules\
│  ├─ daily.json               ← Daily report at 8 AM
│  ├─ weekly.json              ← Weekly Friday 5 PM
│  ├─ monthly.json             ← Monthly 1st at 7 AM
│  └─ quarterly.json           ← Quarterly schedule
│
└─ logs\
   ├─ report-generation.log    ← Report creation logs
   └─ email-delivery.log       ← Email sending logs
```

### Typical Report Storage

```
Generate rate:
├─ Daily Report: 1 per day = 30/month = 360/year
├─ Weekly Report: 1 per week = 4/month = 52/year
├─ Monthly Report: 1 per month
├─ Quarterly Report: 1 per quarter

Approximate Storage (HTML + PDF):
├─ Each Daily Report: 2-5 MB
├─ Each Weekly Report: 8-15 MB
├─ Each Monthly Report: 15-25 MB
├─ Each Quarterly Report: 30-50 MB

Annual Storage:
├─ Daily + Weekly: ~500 MB
├─ Add Monthly + Quarterly: ~600 MB total
└─ 7-year archive: ~4.2 GB
```

---

## 🗄️ Database Storage

### Location

```
C:\ProgramData\HELIOS\database\
```

### PostgreSQL Tables Structure

```
PostgreSQL Database: helios_phase3

Key Tables:
├─ metrics (active data)            ← Real-time metrics
│  ├─ timestamp, cpu_usage, memory_usage, disk_usage
│  ├─ response_time, error_rate, request_count
│  └─ Retention: 90 days (rolling)
│
├─ metrics_archive (historical)     ← Compressed archive
│  ├─ Same schema as metrics
│  └─ Retention: 7 years
│
├─ predictions                      ← AI predictions
│  ├─ timestamp, prediction_type, value, confidence
│  └─ Retention: 30 days
│
├─ workflows                        ← Workflow definitions
│  ├─ id, name, schedule, enabled, definition_json
│
├─ workflow_runs                    ← Workflow execution history
│  ├─ run_id, workflow_id, start_time, end_time, status
│  └─ Retention: 90 days
│
├─ profiles                         ← Profile definitions
│  ├─ id, name, config_json, enabled
│
├─ auto_heal_rules                  ← Healing rules
│  ├─ rule_id, rule_name, detector, action, parameters
│
├─ auto_heal_events                 ← Healing actions taken
│  ├─ event_id, rule_id, timestamp, status, ticket_created
│  └─ Retention: 365 days
│
├─ ai_models                        ← ML model metadata
│  ├─ model_id, model_name, version, accuracy, last_trained
│
└─ reports                          ← Report metadata
   ├─ report_id, type, generated_at, file_path, recipients
```

### Disk Space Usage

```
Typical Database Size (PostgreSQL):
├─ Active Metrics: 50-100 GB (3 months, high frequency)
├─ Historical Archive: 100-200 GB (7 years)
├─ Predictions: 5-10 GB
├─ Workflows & Rules: 100 MB
├─ Healing Events: 5-10 GB
├─ Reports: 2-5 GB
├─ Indexes: 30-50 GB
└─ Total: 200-400 GB typical

Recommended Storage: 500 GB - 1 TB
```

---

## 📝 Logging Locations

### All Log Files

```
Main Logs:
├─ C:\Program Files\HELIOS\Logs\
│  ├─ dashboard.log              (Dashboard service)
│  ├─ ai-engine.log              (AI Learning Engine)
│  ├─ auto-healing.log           (Auto-Healing Service)
│  ├─ workflows.log              (Workflow Engine)
│  ├─ performance-ai.log         (Performance Optimization)
│  ├─ reporting.log              (Report Generation)
│  └─ system.log                 (Overall system events)
│
├─ C:\helios\logs\               (User-accessible location)
│  ├─ phase3-startup.log         (Installation logs)
│  ├─ phase3-verification.log    (Test results)
│  └─ (any reports generated)
│
└─ Event Viewer:                 (Windows Event Log)
   ├─ Applications and Services → HELIOS Dashboard
   ├─ Applications and Services → HELIOS-AI
   └─ Applications and Services → HELIOS-AutoHealing
```

### Log Rotation

```
Daily Logs:
├─ Active log: dashboard.log
├─ When > 100 MB OR daily at 11:59 PM
├─ Archived to: dashboard-2024-02-15.log.gz
└─ Retention: 90 days (then deleted)

Monthly Archive:
├─ All month's logs compressed
└─ Stored: C:\Program Files\HELIOS\Logs\Archive\2024-02\
```

---

## 🔐 Security & Permissions

### File Permissions

```
C:\Program Files\HELIOS\       → Administrators: Full
                               → HELIOS Services: Read/Execute
                               → Everyone Else: Read-only

C:\Program Files\HELIOS\AI\    → HELIOS-AI service account: Full
                               → Dashboard service: Read-only

Sensitive Files:
├─ C:\Program Files\HELIOS\config\credentials.enc (encrypted)
├─ C:\Program Files\HELIOS\AI\models\ (access controlled)
└─ Database credentials (in Windows Credential Manager)
```

### Database Permissions

```
PostgreSQL helios_phase3 Database:
├─ helios_app user: Full access to all tables
├─ helios_readonly user: SELECT only (for reports)
└─ helios_dashboard user: SELECT + specific UPDATE
```

---

## 📈 Growth Projections

### Typical Storage Growth Over 1 Year

```
Month 1: 80 GB
├─ Metrics: 10 GB
├─ Database indexes: 30 GB
├─ Models: 1 GB
└─ Logs/Reports: 40 GB

Month 6: 180 GB (growth rate stabilizes)
├─ Data compresses and archives older data
├─ Database optimization reduces per-record size

Month 12: 300 GB
├─ 90-day active metrics fully populated
├─ 1-year prediction history
├─ 12 months of archived metrics

At this point, growth stabilizes around 25-30 GB/month
```

### Recommended Maintenance

```
Monthly:
├─ Review log sizes
├─ Check database size
└─ Archive old reports

Quarterly:
├─ Compress old metric files
├─ Verify backup sizes
└─ Audit access logs

Annually:
├─ Archive to cold storage (1+ year old data)
├─ Perform database optimization
└─ Clean up model versions >3 months old
```

---

## 🔗 Quick Reference Links

- **Dashboard:** C:\Program Files\HELIOS\Dashboard\
- **AI Models:** C:\Program Files\HELIOS\AI\models\latest\
- **Auto-Healing Rules:** C:\Program Files\HELIOS\AutoHealing\rules\
- **Profiles:** C:\Program Files\HELIOS\Profiles\active\current.json
- **Workflows:** C:\Program Files\HELIOS\Workflows\builtin\
- **Logs:** C:\helios\logs\
- **Reports:** C:\helios\reports\
- **Database:** PostgreSQL connection: localhost:5432/helios_phase3

---

**Last Updated:** 2024  
**For Phase 3.0.0**
