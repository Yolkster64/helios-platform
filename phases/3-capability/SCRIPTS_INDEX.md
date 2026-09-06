# HELIOS Phase 3: Complete Scripts Index

Complete reference of all Phase 3 scripts and commands. Find what you need and how to run it.

---

## 📋 Quick Navigation

- **[Deployment Scripts](#-deployment-scripts)** - Install Phase 3
- **[Dashboard Scripts](#%EF%B8%8F-dashboard-scripts)** - Web UI and monitoring
- **[AI Scripts](#-ai-scripts)** - Machine learning and predictions
- **[Auto-Healing Scripts](#-auto-healing-scripts)** - Automatic fixes
- **[Profile Scripts](#-profile-scripts)** - Custom configurations
- **[Workflow Scripts](#%EF%B8%8F-workflow-scripts)** - Automation and scheduling
- **[Performance Scripts](#-performance-scripts)** - Optimization
- **[Reporting Scripts](#-reporting-scripts)** - Reports and metrics
- **[Testing Scripts](#-testing-scripts)** - Verification and validation
- **[Utility Scripts](#%EF%B8%8F-utility-scripts)** - Maintenance and tools

---

## 🚀 Deployment Scripts

### Main Installation

```powershell
Script: deploy-phase3-complete.ps1
Location: C:\helios\scripts\
Purpose: Complete Phase 3 deployment (all components)
Runtime: 45-60 minutes
Usage:
  .\deploy-phase3-complete.ps1
  .\deploy-phase3-complete.ps1 -Verbose
  .\deploy-phase3-complete.ps1 -DryRun (preview only)

What It Does:
  ├─ Installs Dashboard service
  ├─ Deploys AI Learning Engine
  ├─ Sets up Auto-Healing system
  ├─ Configures Profiles
  ├─ Deploys Workflow Engine
  ├─ Sets up Performance AI
  ├─ Configures Reporting system
  ├─ Creates all databases
  └─ Runs health checks
```

### Component-Specific Installers

```powershell
Script: install-dashboard.ps1
Purpose: Dashboard application only
Runtime: 10 minutes
Usage: .\install-dashboard.ps1

---

Script: install-ai-engine.ps1
Purpose: AI Learning Engine only
Runtime: 15 minutes
Usage: .\install-ai-engine.ps1

---

Script: install-auto-healing.ps1
Purpose: Auto-Healing System only
Runtime: 8 minutes
Usage: .\install-auto-healing.ps1

---

Script: install-workflows.ps1
Purpose: Workflow Engine with 250 pre-built workflows
Runtime: 12 minutes
Usage: .\install-workflows.ps1

---

Script: install-performance-ai.ps1
Purpose: Performance optimization AI only
Runtime: 10 minutes
Usage: .\install-performance-ai.ps1

---

Script: install-reporting.ps1
Purpose: Report generation system only
Runtime: 8 minutes
Usage: .\install-reporting.ps1
```

### Pre-Deployment Verification

```powershell
Script: verify-phase2-complete.ps1
Purpose: Ensure Phase 2 is ready for Phase 3
Runtime: 5 minutes
Usage: .\verify-phase2-complete.ps1
Returns: Green ✅ if ready, Red ❌ if problems found

Checks:
  ├─ Phase 2 all services running
  ├─ Database connectivity
  ├─ Telemetry flowing to central log
  ├─ Backup working
  ├─ Storage space (min 500GB free required)
  └─ System stable for 24+ hours
```

### Uninstall Scripts

```powershell
Script: uninstall-phase3-complete.ps1
Purpose: Remove all Phase 3 components
Runtime: 10 minutes
Usage: .\uninstall-phase3-complete.ps1 -ConfirmDelete

---

Script: uninstall-dashboard.ps1
Purpose: Remove Dashboard only
Usage: .\uninstall-dashboard.ps1

---

Script: uninstall-ai-engine.ps1
Purpose: Remove AI Engine (keep dashboard)
Usage: .\uninstall-ai-engine.ps1
```

---

## 🖥️ Dashboard Scripts

### Dashboard Service Management

```powershell
Script: start-dashboard.ps1
Purpose: Start Dashboard web service
Usage: .\start-dashboard.ps1
Alias: Start-Service -Name "HELIOS-Dashboard"

---

Script: stop-dashboard.ps1
Purpose: Stop Dashboard gracefully
Usage: .\stop-dashboard.ps1
Alias: Stop-Service -Name "HELIOS-Dashboard"

---

Script: restart-dashboard.ps1
Purpose: Restart Dashboard service
Usage: .\restart-dashboard.ps1
Alias: Restart-Service -Name "HELIOS-Dashboard"

---

Script: get-dashboard-status.ps1
Purpose: Check Dashboard health
Usage: .\get-dashboard-status.ps1
Output: Service running, port 9000, uptime, memory usage

---

Script: check-dashboard-logs.ps1
Purpose: View latest Dashboard errors
Usage:
  .\check-dashboard-logs.ps1 -Last 50
  .\check-dashboard-logs.ps1 -ErrorsOnly
  .\check-dashboard-logs.ps1 -Follow (stream mode)
```

### Dashboard Configuration

```powershell
Script: configure-dashboard.ps1
Purpose: Customize Dashboard settings
Usage:
  .\configure-dashboard.ps1 -Port 9001 (change port)
  .\configure-dashboard.ps1 -Theme dark (change theme)
  .\configure-dashboard.ps1 -RefreshRate 1000 (update interval ms)

---

Script: reset-dashboard-cache.ps1
Purpose: Clear Dashboard cache
Usage: .\reset-dashboard-cache.ps1
Effect: Forces dashboard reload on next access
```

---

## 🤖 AI Scripts

### AI Engine Management

```powershell
Script: initialize-ai-learning.ps1
Purpose: First-time AI setup, create baseline models
Runtime: 10-15 minutes
Usage: .\initialize-ai-learning.ps1
Output: "AI Learning Engine initialized. Accuracy: 78%"

---

Script: start-ai-engine.ps1
Purpose: Start AI Learning service
Usage: .\start-ai-engine.ps1
Alias: Start-Service -Name "HELIOS-AI-Learning"

---

Script: stop-ai-engine.ps1
Purpose: Stop AI Engine gracefully
Usage: .\stop-ai-engine.ps1

---

Script: restart-ai-engine.ps1
Purpose: Restart AI Engine
Usage: .\restart-ai-engine.ps1
```

### AI Training & Predictions

```powershell
Script: retrain-ai-models.ps1
Purpose: Immediately retrain AI models (normally daily 1 AM)
Usage:
  .\retrain-ai-models.ps1 (quick retrain)
  .\retrain-ai-models.ps1 -Full (full training)
  .\retrain-ai-models.ps1 -IncludeLastDays 7
Runtime: 5-30 minutes depending on data size

---

Script: get-ai-predictions.ps1
Purpose: Get AI predictions for next hours/days
Usage:
  .\get-ai-predictions.ps1 -Hours 24
  .\get-ai-predictions.ps1 -Days 7
  .\get-ai-predictions.ps1 -Metric cpu_usage
Output: JSON with predictions and confidence levels

---

Script: get-ai-confidence.ps1
Purpose: Check AI model confidence levels
Usage: .\get-ai-confidence.ps1
Output: Each model with accuracy and confidence

---

Script: get-ai-status.ps1
Purpose: Full AI Engine status report
Usage: .\get-ai-status.ps1
Output:
  ├─ Learning status
  ├─ Model accuracies
  ├─ Last training time
  ├─ Next training time
  └─ Current predictions
```

### AI Model Management

```powershell
Script: backup-ai-models.ps1
Purpose: Backup current AI models
Usage: .\backup-ai-models.ps1
Creates: Timestamped backup copy

---

Script: restore-ai-models.ps1
Purpose: Restore previous AI models
Usage:
  .\restore-ai-models.ps1 -Date "2024-02-14"
  .\restore-ai-models.ps1 -Backup "/path/to/backup"

---

Script: reset-ai-learning.ps1
Purpose: Reset AI to baseline (lose all learning, start over)
Usage: .\reset-ai-learning.ps1 -Confirm
Effect: AI accuracy drops to 78%, will relearn in 24 hours

---

Script: export-ai-analysis.ps1
Purpose: Export detailed AI analysis to file
Usage:
  .\export-ai-analysis.ps1 -Format JSON
  .\export-ai-analysis.ps1 -Format CSV
  .\export-ai-analysis.ps1 -OutputFile "C:\reports\analysis.json"
```

---

## 🔧 Auto-Healing Scripts

### Auto-Healing Management

```powershell
Script: deploy-auto-healing.ps1
Purpose: Deploy auto-healing services
Runtime: 8 minutes
Usage: .\deploy-auto-healing.ps1

---

Script: start-auto-healing.ps1
Purpose: Start Auto-Healing service
Usage: .\start-auto-healing.ps1
Alias: Start-Service -Name "HELIOS-AutoHealing"

---

Script: stop-auto-healing.ps1
Purpose: Stop Auto-Healing service
Usage: .\stop-auto-healing.ps1

---

Script: get-auto-healing-status.ps1
Purpose: Check Auto-Healing health
Usage: .\get-auto-healing-status.ps1
Output: Service running, rules loaded, detectors active
```

### Healing Rules Management

```powershell
Script: get-auto-heal-rules.ps1
Purpose: List all healing rules
Usage:
  .\get-auto-heal-rules.ps1 (all)
  .\get-auto-heal-rules.ps1 -Category database
  .\get-auto-heal-rules.ps1 -Enabled
Output: Rule name, trigger, action, status

---

Script: enable-healing-rule.ps1
Purpose: Enable specific healing rule
Usage:
  .\enable-healing-rule.ps1 -Rule "ConnectionPoolExpansion"

---

Script: disable-healing-rule.ps1
Purpose: Disable specific healing rule (keep others)
Usage:
  .\disable-healing-rule.ps1 -Rule "ConnectionPoolExpansion"

---

Script: add-custom-healing-rule.ps1
Purpose: Create new custom healing rule
Usage:
  .\add-custom-healing-rule.ps1 `
    -Name "MyCustomRule" `
    -Detector "my-detector" `
    -Action "my-action" `
    -Threshold "cpu > 95%"
```

### Healing History

```powershell
Script: get-auto-heal-history.ps1
Purpose: See all auto-healing actions
Usage:
  .\get-auto-heal-history.ps1 -Last 24h
  .\get-auto-heal-history.ps1 -SuccessOnly
  .\get-auto-heal-history.ps1 -Failed
Output:
  Time | Problem | Fix Applied | Success | Ticket

---

Script: get-auto-heal-tickets.ps1
Purpose: See auto-created support tickets
Usage: .\get-auto-heal-tickets.ps1
Output: Tickets for each auto-healing event

---

Script: test-auto-healing.ps1
Purpose: Manually trigger healing (for testing)
Usage: .\test-auto-healing.ps1 -Rule "ConnectionPoolExpansion"
Note: Safe to run, won't break anything
```

---

## 👤 Profile Scripts

### Profile Management

```powershell
Script: get-profiles.ps1
Purpose: List all available profiles
Usage: .\get-profiles.ps1
Output:
  Name | Type | Status | Description

---

Script: get-active-profile.ps1
Purpose: Show currently active profile
Usage: .\get-active-profile.ps1
Output: Profile name and settings

---

Script: activate-profile.ps1
Purpose: Switch to different profile
Usage:
  .\activate-profile.ps1 -Name "HighTraffic"
  .\activate-profile.ps1 -Name "LowCost" -Duration 8h
  .\activate-profile.ps1 -Name "LatencyCritical" -Permanent

---

Script: create-custom-profile.ps1
Purpose: Create new custom profile
Usage:
  .\create-custom-profile.ps1 `
    -Name "MyProfile" `
    -CachingLevel High `
    -MaxConnections 500 `
    -RequestTimeout 30

---

Script: delete-profile.ps1
Purpose: Remove custom profile (can't delete built-in)
Usage: .\delete-profile.ps1 -Name "MyProfile" -Confirm

---

Script: profile-details.ps1
Purpose: Show profile settings
Usage: .\profile-details.ps1 -Name "HighTraffic"
Output: JSON with all settings
```

### Profile Scheduling

```powershell
Script: schedule-profile-change.ps1
Purpose: Auto-switch profiles on schedule
Usage:
  .\schedule-profile-change.ps1 `
    -Name "BusinessHours" `
    -Weekday "MonTueWedThuFri" `
    -StartTime "7:00 AM" `
    -EndTime "6:00 PM" `
    -Profile "Normal" `
    -OffHourProfile "LowCost"

---

Script: get-profile-schedule.ps1
Purpose: See all scheduled profile changes
Usage: .\get-profile-schedule.ps1
Output: All scheduled profile changes
```

---

## ⚙️ Workflow Scripts

### Workflow Management

```powershell
Script: get-workflows.ps1
Purpose: List all workflows (built-in + custom)
Usage:
  .\get-workflows.ps1
  .\get-workflows.ps1 -Enabled
  .\get-workflows.ps1 -Category backup
Output: Name, type, status, schedule

---

Script: get-workflow.ps1
Purpose: See details of specific workflow
Usage: .\get-workflow.ps1 -Name "DailyBackup"
Output: Full workflow definition with all steps

---

Script: enable-workflow.ps1
Purpose: Turn on a workflow
Usage: .\enable-workflow.ps1 -Name "DailyBackup"
Result: Workflow runs on schedule

---

Script: disable-workflow.ps1
Purpose: Turn off a workflow (don't run)
Usage: .\disable-workflow.ps1 -Name "DailyBackup"

---

Script: run-workflow.ps1
Purpose: Manually execute workflow now
Usage: .\run-workflow.ps1 -Name "DailyBackup"
Output: Workflow ID for tracking
```

### Workflow Creation

```powershell
Script: create-workflow.ps1
Purpose: Create new custom workflow
Usage:
  .\create-workflow.ps1 `
    -Name "MyWorkflow" `
    -Trigger "Daily at 3:00 AM" `
    -Description "My automated process"

---

Script: add-workflow-step.ps1
Purpose: Add step to workflow
Usage:
  .\add-workflow-step.ps1 `
    -Workflow "MyWorkflow" `
    -Name "Step1" `
    -Command "Get-HeliosMetrics" `
    -Order 1

---

Script: delete-workflow.ps1
Purpose: Remove custom workflow
Usage: .\delete-workflow.ps1 -Name "MyWorkflow" -Confirm
```

### Workflow Execution

```powershell
Script: get-workflow-history.ps1
Purpose: See past workflow executions
Usage:
  .\get-workflow-history.ps1 -Workflow "DailyBackup" -Last 7d
Output: Each run: time, duration, status, errors

---

Script: get-workflow-run.ps1
Purpose: Details of specific workflow run
Usage: .\get-workflow-run.ps1 -RunID "WF-2024-02-15-001"
Output: Steps, timing, results

---

Script: retry-workflow-run.ps1
Purpose: Re-run failed workflow
Usage: .\retry-workflow-run.ps1 -RunID "WF-2024-02-15-001"
```

---

## ⚡ Performance Scripts

### Performance AI Management

```powershell
Script: enable-performance-ai.ps1
Purpose: Start Performance AI optimization
Runtime: 5 minutes
Usage: .\enable-performance-ai.ps1

---

Script: get-performance-ai-status.ps1
Purpose: Check Performance AI health
Usage: .\get-performance-ai-status.ps1
Output: Service running, analysis depth, recommendations pending

---

Script: get-performance-recommendations.ps1
Purpose: See AI recommendations
Usage:
  .\get-performance-recommendations.ps1 -Next 24h
  .\get-performance-recommendations.ps1 -HighImpactOnly
Output:
  Recommendation | Impact | Confidence | Cost/Benefit
```

### Optimization Application

```powershell
Script: apply-optimization.ps1
Purpose: Apply specific optimization
Usage:
  .\apply-optimization.ps1 -RecID "REC-00451" (add database index)

---

Script: apply-recommendations.ps1
Purpose: Apply all high-confidence recommendations
Usage:
  .\apply-recommendations.ps1 -MinConfidence 90
  .\apply-recommendations.ps1 -MaxConfidence 95 -MinConfidence 92

---

Script: get-optimization-history.ps1
Purpose: See all optimizations applied
Usage:
  .\get-optimization-history.ps1 -Last 7d
Output:
  Date | Optimization | Before | After | Improvement
```

### Performance Analysis

```powershell
Script: analyze-database-performance.ps1
Purpose: Deep analysis of database queries
Usage: .\analyze-database-performance.ps1
Output: Slow queries, missing indexes, optimization opportunities

---

Script: analyze-cache-performance.ps1
Purpose: Cache effectiveness analysis
Usage: .\analyze-cache-performance.ps1
Output: Hit rates, TTL recommendations, memory usage

---

Script: analyze-resource-bottlenecks.ps1
Purpose: Find what's limiting system
Usage: .\analyze-resource-bottlenecks.ps1
Output: CPU/Memory/Disk bottleneck analysis with fixes
```

---

## 📊 Reporting Scripts

### Report Generation

```powershell
Script: generate-daily-report.ps1
Purpose: Create executive summary
Usage: .\generate-daily-report.ps1 -SendTo "admin@company.com"
Output: HTML + PDF saved to C:\helios\reports\
Includes: Health, incidents, predictions

---

Script: generate-weekly-report.ps1
Purpose: Detailed technical report
Usage: .\generate-weekly-report.ps1
Output: 5-page technical analysis

---

Script: generate-monthly-report.ps1
Purpose: Business impact report
Usage: .\generate-monthly-report.ps1
Output: Cost analysis, trends, recommendations

---

Script: generate-quarterly-report.ps1
Purpose: Board-level report
Usage: .\generate-quarterly-report.ps1 -SendTo "cto@company.com"
Output: Executive-level ROI and impact analysis
```

### Report Scheduling

```powershell
Script: schedule-daily-report.ps1
Purpose: Automatic daily report generation
Usage:
  .\schedule-daily-report.ps1 `
    -Time "8:00 AM" `
    -Recipients "ops@company.com","cto@company.com" `
    -Format HTML,PDF

---

Script: schedule-weekly-report.ps1
Purpose: Automatic weekly report
Usage:
  .\schedule-weekly-report.ps1 `
    -Day Friday `
    -Time "5:00 PM" `
    -Recipients "ops@company.com"

---

Script: get-report-schedule.ps1
Purpose: See all scheduled reports
Usage: .\get-report-schedule.ps1
Output: All report schedules
```

### Report Retrieval

```powershell
Script: get-last-report.ps1
Purpose: Get most recent report
Usage:
  .\get-last-report.ps1 -Type Daily
  .\get-last-report.ps1 -Type Daily -Open (open in browser)

---

Script: list-reports.ps1
Purpose: List all generated reports
Usage:
  .\list-reports.ps1 -Last 30
  .\list-reports.ps1 -Type Daily -Last 90
```

---

## ✅ Testing Scripts

### Comprehensive Testing

```powershell
Script: test-phase3-complete.ps1
Purpose: Run all Phase 3 tests (42 total)
Runtime: 15-20 minutes
Usage: .\test-phase3-complete.ps1
Output: C:\helios\reports\phase3-verification.html
Exit Code: 0 (all pass) or # of failures

Tests Include:
  ├─ Dashboard responsiveness (5 tests)
  ├─ AI predictions accuracy (8 tests)
  ├─ Auto-healing triggers (7 tests)
  ├─ Profile switching (4 tests)
  ├─ Workflow execution (6 tests)
  ├─ Performance optimization (4 tests)
  └─ Reporting generation (3 tests)
```

### Component Testing

```powershell
Script: test-dashboard.ps1
Purpose: Test Dashboard functionality
Usage: .\test-dashboard.ps1
Tests: Port accessible, data loading, real-time updates

---

Script: test-ai-engine.ps1
Purpose: Test AI predictions
Usage: .\test-ai-engine.ps1
Tests: Models loaded, predictions generated, accuracy acceptable

---

Script: test-auto-healing.ps1
Purpose: Test auto-healing (safe triggers only)
Usage: .\test-auto-healing.ps1
Tests: Detectors working, actions executable, tickets created

---

Script: test-workflows.ps1
Purpose: Test workflow engine
Usage: .\test-workflows.ps1
Tests: Workflow definitions loaded, execution successful

---

Script: test-performance-ai.ps1
Purpose: Test optimization engine
Usage: .\test-performance-ai.ps1
Tests: Analysis running, recommendations generated
```

### Health Checks

```powershell
Script: health-check-phase3.ps1
Purpose: Quick system health verification
Usage: .\health-check-phase3.ps1
Output: Green ✅ or Red ❌ for each component

---

Script: deep-health-check.ps1
Purpose: Detailed system diagnosis
Usage: .\deep-health-check.ps1 -Verbose
Output: Detailed logs and recommendations
```

---

## 🛠️ Utility Scripts

### Maintenance

```powershell
Script: cleanup-phase3-logs.ps1
Purpose: Archive old logs, free space
Usage: .\cleanup-phase3-logs.ps1 -Older 30days
Effect: Compresses logs older than 30 days

---

Script: optimize-database.ps1
Purpose: PostgreSQL maintenance
Usage: .\optimize-database.ps1
Does: Vacuum, reindex, statistics update

---

Script: backup-phase3-config.ps1
Purpose: Backup all Phase 3 configuration
Usage: .\backup-phase3-config.ps1
Creates: Timestamped backup file

---

Script: restore-phase3-config.ps1
Purpose: Restore Phase 3 configuration
Usage:
  .\restore-phase3-config.ps1 -Backup "backup-2024-02-15.zip"
```

### Troubleshooting

```powershell
Script: troubleshoot-dashboard.ps1
Purpose: Diagnose Dashboard issues
Usage: .\troubleshoot-dashboard.ps1 -Verbose
Output: Detailed diagnostic information

---

Script: troubleshoot-ai.ps1
Purpose: Diagnose AI Engine issues
Usage: .\troubleshoot-ai.ps1
Output: Model status, training logs, errors

---

Script: troubleshoot-all.ps1
Purpose: Comprehensive Phase 3 diagnostics
Usage: .\troubleshoot-all.ps1 > "C:\helios\logs\diagnostics.log"
Output: Complete system analysis

---

Script: generate-support-bundle.ps1
Purpose: Create diagnostic bundle for support
Usage: .\generate-support-bundle.ps1
Creates: ZIP with logs, configs, system info
Safe to share: No credentials included
```

### Monitoring

```powershell
Script: watch-services.ps1
Purpose: Monitor Phase 3 services in real-time
Usage: .\watch-services.ps1
Displays: Service status, resource usage, updates every 2 sec

---

Script: monitor-ai-learning.ps1
Purpose: Watch AI training progress
Usage: .\monitor-ai-learning.ps1 -Verbose
Shows: Real-time accuracy, model performance, ETA

---

Script: follow-logs.ps1
Purpose: Stream live logs (tail -f equivalent)
Usage:
  .\follow-logs.ps1 -Service dashboard
  .\follow-logs.ps1 -Service ai -ErrorsOnly
  .\follow-logs.ps1 -All
```

---

## 🔍 Finding Scripts

### By Purpose

- **Need to install?** → See [Deployment Scripts](#-deployment-scripts)
- **Want to monitor?** → See [Dashboard Scripts](#%EF%B8%8F-dashboard-scripts) + [Utility Scripts](#%EF%B8%8F-utility-scripts)
- **Need to verify?** → See [Testing Scripts](#-testing-scripts)
- **Troubleshooting?** → See [Utility Scripts](#%EF%B8%8F-utility-scripts) Troubleshooting section
- **Creating automation?** → See [Workflow Scripts](#%EF%B8%8F-workflow-scripts)

### By Component

- **Dashboard:** Dashboard Scripts + Utility Scripts
- **AI:** AI Scripts + Performance Scripts
- **Auto-Healing:** Auto-Healing Scripts
- **Profiles:** Profile Scripts
- **Workflows:** Workflow Scripts
- **Reports:** Reporting Scripts

---

## 📖 Common Tasks

### "I want to see what's happening"

```powershell
.\test-phase3-complete.ps1
.\get-dashboard-status.ps1
.\watch-services.ps1
```

### "Something's wrong, help me diagnose"

```powershell
.\troubleshoot-all.ps1
.\generate-support-bundle.ps1
```

### "I want to enable all AI recommendations"

```powershell
.\apply-recommendations.ps1 -MinConfidence 90
```

### "I need to switch to high-traffic profile"

```powershell
.\activate-profile.ps1 -Name "HighTraffic"
```

### "Create a new workflow"

```powershell
.\create-workflow.ps1 -Name "MyWorkflow"
.\add-workflow-step.ps1 -Workflow "MyWorkflow"
.\enable-workflow.ps1 -Name "MyWorkflow"
```

---

**Last Updated:** 2024  
**For Phase 3.0.0**  
**Complete Scripts Reference**
