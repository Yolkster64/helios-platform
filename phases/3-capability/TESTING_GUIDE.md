# HELIOS Phase 3: Testing Guide

Complete guide to verifying Phase 3 capabilities are working correctly.

---

## 🎯 Quick Verification (5 Minutes)

Run this first to confirm everything is basically working:

```powershell
cd C:\helios\scripts
.\test-phase3-complete.ps1 -Quick

# Expected Output:
# ✅ Dashboard responding
# ✅ AI engine running
# ✅ Auto-healing active
# ✅ Workflows ready
# ✅ Reporting working
# 
# All systems operational!
```

---

## 📊 Full Test Suite (20 Minutes)

Run comprehensive tests to verify all capabilities:

```powershell
cd C:\helios\scripts
.\test-phase3-complete.ps1

# Runs 42 tests across all capabilities
# Time: 15-20 minutes
# Output: HTML report at C:\helios\reports\phase3-verification.html
```

---

## 1. Dashboard Responsiveness Testing

### Objective

Verify the web dashboard loads, updates correctly, and displays real-time data.

### Manual Tests

**Test 1.1: Dashboard Accessibility**

```powershell
# Verify dashboard service is running
Get-Service -Name "HELIOS-Dashboard" | Select-Object Status

# Expected: Status = Running

# Try to access in browser
# URL: http://localhost:9000
# Expected: Dashboard loads, shows green "System Healthy" indicator
```

**Test 1.2: Real-Time Metric Updates**

```powershell
# Check dashboard is updating metrics every 2 seconds
# Look at dashboard metrics charts
# Observe: CPU, RAM, Disk charts should show continuous updates
# Expected: Charts update smoothly, no freezing

# Wait 30 seconds
# Expected: Clear progression of data points on charts
```

**Test 1.3: WebSocket Connection**

```powershell
# Check WebSocket is connected
# Dashboard browser console (F12 → Console):
console.log(window.websocket.readyState);

# Expected: 1 (OPEN)
```

**Test 1.4: Theme Switching**

```powershell
# On dashboard, switch theme (light ↔ dark)
# Expected: Theme changes immediately
# Expected: Preference saved (persists after refresh)
```

**Test 1.5: Data Accuracy**

```powershell
# Compare dashboard metrics with system metrics
.\get-dashboard-status.ps1

# Check that CPU % shown = actual system CPU %
# Check that RAM shown = actual RAM usage
# Allow ±3% variance (network latency)
```

### Automated Tests

```powershell
Script: test-dashboard.ps1
Tests: 5 total
├─ Service running
├─ Port 9000 responding
├─ Metrics loading
├─ WebSocket connected
└─ Data accuracy
Expected: All pass ✅
```

### Troubleshooting Dashboard

| Problem | Check | Fix |
|---------|-------|-----|
| Won't start | `Get-Service HELIOS-Dashboard` | Restart service or check logs |
| Shows "No Data" | Check telemetry collection | Verify Phase 2 metrics flowing |
| Slow loading | Check browser cache | `.\reset-dashboard-cache.ps1` |
| Charts frozen | WebSocket connection | Refresh browser page |
| Port 9000 in use | `netstat -ano \| find ":9000"` | Change port in config.js |

---

## 2. AI Learning Engine Testing

### Objective

Verify AI is learning patterns, making predictions, and improving accuracy over time.

### Manual Tests

**Test 2.1: AI Service Running**

```powershell
Get-Service -Name "HELIOS-AI-Learning" | Select-Object Status

# Expected: Running
```

**Test 2.2: Models Loaded**

```powershell
.\get-ai-status.ps1

# Expected Output:
# Service Status: Running
# Models Loaded: 6/6 ✅
#   - traffic-predictor (accuracy: 88%)
#   - resource-predictor (accuracy: 91%)
#   - error-detector (accuracy: 85%)
#   - anomaly-detector (accuracy: 79%)
#   - correlation-analyzer (accuracy: 92%)
#   - performance-model (accuracy: 86%)
# 
# Learning Status: Active
# Last Training: 1 day ago
# Next Training: Tomorrow 1:00 AM
```

**Test 2.3: Predictions Available**

```powershell
.\get-ai-predictions.ps1 -Hours 24

# Expected: JSON with predictions for next 24 hours
# Each prediction should have:
# - timestamp
# - predicted value
# - confidence (typically 70-95% after 1+ weeks learning)
# - reasoning (why this prediction)

# Example:
# {
#   "timestamp": "2024-02-15 14:00",
#   "metric": "cpu_usage",
#   "prediction": "62%",
#   "confidence": 88,
#   "reasoning": "Matches Tuesday 2 PM pattern from last 4 weeks"
# }
```

**Test 2.4: Confidence Levels**

```powershell
.\get-ai-confidence.ps1

# Expected: All models show confidence
# Day 1-2: 70-80% confidence (learning)
# Day 3-4: 80-85% confidence
# Day 7: 88-92% confidence
# Day 14: 92-96% confidence
# Day 30+: 94-98% confidence

# Models with <70% confidence indicate insufficient data
```

**Test 2.5: Prediction Accuracy Verification**

```powershell
# Check past predictions vs actual results
.\get-ai-predictions.ps1 -Days 7 -Historical

# Compare Day 1's predictions with Day 7's actual results
# Expected: 85%+ of predictions within ±10% of actual values
```

**Test 2.6: Learning Progress**

```powershell
.\monitor-ai-learning.ps1 -Verbose

# Expected: Accuracy trending upward
# Day 1: 78% accuracy
# Day 2: 80% accuracy
# Day 3: 82% accuracy
# etc.
# Slope: ~2% improvement per day for first 2 weeks
```

### Automated Tests

```powershell
Script: test-ai-engine.ps1
Tests: 8 total
├─ Service running
├─ Models loaded (6/6)
├─ Predictions generated
├─ Confidence levels normal
├─ Accuracy trending up
├─ No stuck models
├─ Training running on schedule
└─ No data corruption
Expected: All pass ✅
```

### AI Learning Timeline Verification

```
Expected Progression:

Day 1 (Learning)
├─ Accuracy: ~78%
├─ Confidence: 70-75%
└─ Status: ⚠️ Learning mode

Day 3
├─ Accuracy: ~84%
├─ Confidence: 80-85%
└─ Status: 🟡 Still learning

Day 7
├─ Accuracy: ~91%
├─ Confidence: 88-92%
└─ Status: ✅ Reliable predictions

Day 14
├─ Accuracy: ~94%
├─ Confidence: 92-96%
└─ Status: ✅ Expert level

If not progressing as expected:
├─ Check: Sufficient data flowing in (24+ hours of metrics)
├─ Check: No data quality issues
├─ Fix: Restart training: .\retrain-ai-models.ps1 -Full
└─ Last resort: Reset and retry: .\reset-ai-learning.ps1
```

---

## 3. Auto-Healing System Testing

### Objective

Verify auto-healing detects problems and applies fixes automatically.

### Manual Tests

**Test 3.1: Healing Service Running**

```powershell
Get-Service -Name "HELIOS-AutoHealing" | Select-Object Status

# Expected: Running
```

**Test 3.2: Healing Rules Loaded**

```powershell
.\get-auto-heal-rules.ps1

# Expected: 10+ rules loaded
# Examples:
# - ConnectionPoolExpansion
# - CacheFlushing
# - LogArchival
# - MemoryCleanup
# - DiskSpaceManagement
# - ServiceRestart
# - etc.
```

**Test 3.3: Safe Trigger Test**

```powershell
# Manually trigger a test healing rule (safe, won't break anything)
.\test-auto-healing.ps1 -Rule "MemoryCleanup"

# Expected:
# ✅ Rule triggered
# ✅ Detector ran
# ✅ Analysis completed
# ✅ Action would execute (test mode)
# ✅ Ticket would be created
```

**Test 3.4: Healing History**

```powershell
.\get-auto-heal-history.ps1 -Last 7d

# Expected: List of auto-healing actions
# Examples:
# Time      | Problem              | Action               | Success
# 14:32:15  | High CPU             | Cache flush          | ✅
# 09:47:22  | Connection timeout   | Restart pool         | ✅
# 03:15:08  | Memory leak          | GC trigger + restart | ✅

# Should show multiple successful healings (not just 1-2)
```

**Test 3.5: Auto-Created Tickets**

```powershell
.\get-auto-heal-tickets.ps1

# Expected: Tickets created for each healing event
# Each ticket should reference:
# - What problem was detected
# - What auto-healing did
# - When it happened
# - Reference: "Auto-healed #4521"
```

**Test 3.6: Monitoring After Heal**

```powershell
# Verify system continues monitoring after a heal
# Run 5 minute continuous monitoring
.\monitor-auto-healing.ps1 -Duration 5m

# Expected: Detectors actively monitoring
# Expected: No errors or warnings
```

### Automated Tests

```powershell
Script: test-auto-healing.ps1
Tests: 7 total
├─ Service running
├─ Detectors active
├─ Rules loaded
├─ Test triggers work
├─ Tickets created
├─ Monitoring continues
└─ No stuck processes
Expected: All pass ✅
```

### Auto-Healing Verification Scenarios

**Scenario 1: Connection Pool Expansion**

```
Trigger: Connection pool at 95% usage
Expected: Pool expanded by 20-30 connections
Monitor: Use dashboard, watch pool % drop
Ticket: Created automatically
Time: <10 seconds from detection to fix
```

**Scenario 2: Cache Flush**

```
Trigger: Cache hit rate below 60%
Expected: Cache flushed and reloaded
Result: Hit rate returns to 80%+
Ticket: Created with metrics before/after
Time: <5 seconds
```

**Scenario 3: Disk Space Management**

```
Trigger: Disk at 85% capacity
Expected: Old logs archived, cache optimized
Result: Disk drops to 70%
Freed: Amount logged in ticket
Time: <2 minutes
```

---

## 4. Profile Management Testing

### Objective

Verify profiles load, switch correctly, and change system behavior.

### Manual Tests

**Test 4.1: Profiles Load**

```powershell
.\get-profiles.ps1

# Expected: 7+ built-in profiles plus any custom
# - Normal
# - HighTraffic
# - LowCost
# - LatencyCritical
# - DevelopmentTesting
# - BatchProcessing
# - BackupRestore
```

**Test 4.2: Active Profile Check**

```powershell
.\get-active-profile.ps1

# Expected: Currently active profile name
# Expected: Settings displayed
# Normal profile should be default
```

**Test 4.3: Profile Switching**

```powershell
# Switch to HighTraffic profile
.\activate-profile.ps1 -Name "HighTraffic"

# Verify change
.\get-active-profile.ps1

# Expected: "HighTraffic" is now active
# Settings should reflect high-traffic config:
# - Cache: aggressive
# - Connections: 500
# - Timeout: 30s
```

**Test 4.4: System Behavior Change**

```powershell
# While in HighTraffic profile, observe:
# - Cache behavior: Should cache more
# - Connection pool: Should be at 500
# - Request handling: More aggressive

# Switch back to Normal
.\activate-profile.ps1 -Name "Normal"

# Verify revert
.\get-active-profile.ps1

# Expected: All settings back to normal
```

**Test 4.5: Profile Scheduled Switching**

```powershell
# If business hours profile scheduled:
.\get-profile-schedule.ps1

# Expected: Schedule showing weekday/time-based switches
# Verify manual override works:
.\activate-profile.ps1 -Name "LowCost" -Permanent

# Expected: Overrides schedule until reset
```

**Test 4.6: Custom Profile**

```powershell
# Create custom profile
.\create-custom-profile.ps1 `
  -Name "TestProfile" `
  -CachingLevel High `
  -MaxConnections 250

# Verify it exists
.\get-profiles.ps1 | Where-Object Name -eq "TestProfile"

# Activate it
.\activate-profile.ps1 -Name "TestProfile"

# Verify it's active
.\get-active-profile.ps1

# Expected: TestProfile active with custom settings

# Clean up
.\delete-profile.ps1 -Name "TestProfile" -Confirm
```

### Automated Tests

```powershell
Script: test-profiles.ps1
Tests: 4 total
├─ Default profiles load
├─ Profile switching works
├─ Settings apply correctly
└─ Custom profiles work
Expected: All pass ✅
```

---

## 5. Workflow Execution Testing

### Objective

Verify workflows execute on schedule and complete successfully.

### Manual Tests

**Test 5.1: Workflows Load**

```powershell
.\get-workflows.ps1 | Select-Object Name, Status, Enabled

# Expected: 250+ pre-built workflows loaded
# Examples:
# - DailyBackup: Enabled
# - WeeklyMaintenance: Enabled
# - MonthlyOptimization: Enabled
# etc.
```

**Test 5.2: Manual Workflow Execution**

```powershell
# Run a test workflow (safe one)
.\run-workflow.ps1 -Name "HealthCheck"

# Expected: Workflow starts immediately
# Expected: RunID returned for tracking
# Example: "WF-2024-02-15-001"
```

**Test 5.3: Workflow Execution Monitoring**

```powershell
# Check workflow execution progress
.\get-workflow-run.ps1 -RunID "WF-2024-02-15-001"

# Expected Output:
# Workflow: HealthCheck
# Status: In Progress
# 
# Steps:
# Step 1: Collect metrics [Completed 2.3s]
# Step 2: Analyze patterns [In Progress 1.2s]
# Step 3: Generate report [Pending]
```

**Test 5.4: Workflow Completion**

```powershell
# Wait for workflow to complete
# Then check results
.\get-workflow-history.ps1 -Workflow "HealthCheck" -Last 1

# Expected Output:
# Started       | Completed  | Status   | Duration
# 14:32:15      | 14:35:22   | Success  | 3m 7s

# All steps completed successfully
```

**Test 5.5: Enable/Disable Workflow**

```powershell
# Disable a workflow
.\disable-workflow.ps1 -Name "DailyBackup"

# Check it's disabled
.\get-workflows.ps1 | Where-Object Name -eq "DailyBackup" | Select-Object Enabled

# Expected: False (won't run on schedule)

# Re-enable
.\enable-workflow.ps1 -Name "DailyBackup"

# Expected: True (will run on schedule again)
```

**Test 5.6: Workflow Scheduling**

```powershell
# Get DailyBackup schedule
.\get-workflow.ps1 -Name "DailyBackup"

# Expected Output includes:
# Schedule: "Every day at 2:00 AM"
# Next Run: "Tomorrow at 2:00 AM"
# Last Run: "Today at 2:00 AM - Success"
```

### Automated Tests

```powershell
Script: test-workflows.ps1
Tests: 6 total
├─ Workflows load (250+)
├─ Manual execution works
├─ Status tracking works
├─ Completion recorded
├─ Enable/disable works
└─ Scheduling accurate
Expected: All pass ✅
```

### Workflow Verification Checklist

- [ ] 250+ workflows loaded
- [ ] At least 3 enabled workflows
- [ ] Manual workflow execution succeeds
- [ ] Workflow appears in history with success status
- [ ] Workflow duration reasonable (not stuck)
- [ ] Can enable/disable without error
- [ ] Scheduled workflows have next run time
- [ ] Email notifications work (if configured)

---

## 6. Performance Optimization Testing

### Objective

Verify AI is generating optimization recommendations and applies them correctly.

### Manual Tests

**Test 6.1: Optimization Engine Running**

```powershell
.\get-performance-ai-status.ps1

# Expected:
# Service Status: Running
# Last Analysis: 2 hours ago
# Recommendations Pending: 3
# Optimizations This Week: 7
```

**Test 6.2: Recommendations Generated**

```powershell
.\get-performance-recommendations.ps1 -Next 48h

# Expected: Multiple recommendations
# Examples:
# - Add database index on orders(user_id) [Impact: +35%] [Confidence: 92%]
# - Increase cache memory [Impact: +15%] [Confidence: 88%]
# - Archive old audit logs [Impact: +20% disk speed] [Confidence: 95%]

# Should show:
# ├─ Recommendation description
# ├─ Estimated impact
# ├─ Confidence level
# ├─ Cost/benefit analysis
# └─ Implementation steps
```

**Test 6.3: Recommendation Application**

```powershell
# Get high-confidence recommendation
.\get-performance-recommendations.ps1 -HighImpactOnly | Select-Object -First 1

# Apply it
.\apply-optimization.ps1 -RecID "REC-00451"

# Expected: Success message
```

**Test 6.4: Before/After Metrics**

```powershell
# Get optimization results
.\get-optimization-history.ps1 -Last 7d

# Expected:
# Date      | Optimization          | Before  | After   | Improvement
# 2024-02-14| Add database index    | 2.3s    | 180ms   | +92%
# 2024-02-13| Cache TTL adjustment  | 73%     | 89%     | +22%
# 2024-02-12| Memory optimization   | 16GB    | 14GB    | +12%

# Each should show measurable improvement
```

**Test 6.5: Deep Performance Analysis**

```powershell
# Run database analysis
.\analyze-database-performance.ps1

# Expected: 
# ├─ Slow Queries: List of queries >1 second
# ├─ Missing Indexes: Identified missing indexes
# ├─ Join Analysis: Expensive joins
# └─ Recommendations: Specific fixes with impact

# Cache analysis
.\analyze-cache-performance.ps1

# Expected:
# ├─ Hit Rate: Current percentage
# ├─ TTL Effectiveness: How well TTL is working
# └─ Tuning Recommendations: What to change
```

### Automated Tests

```powershell
Script: test-performance-ai.ps1
Tests: 4 total
├─ Engine running
├─ Recommendations generated
├─ Applications work
└─ Metrics tracked
Expected: All pass ✅
```

---

## 7. Reporting System Testing

### Objective

Verify reports generate correctly and contain accurate information.

### Manual Tests

**Test 7.1: Report Generation**

```powershell
# Generate a daily report
.\generate-daily-report.ps1

# Expected: Report generated successfully
# Output location: C:\helios\reports\daily\
```

**Test 7.2: Report Contents**

```powershell
# Open generated report in browser
.\get-last-report.ps1 -Type Daily -Open

# Expected content:
# ├─ System Health Score
# ├─ Uptime percentage
# ├─ Incidents today
# ├─ AI Predictions next week
# ├─ Performance trends
# ├─ Cost analysis
# └─ Recommendations
```

**Test 7.3: Report Accuracy**

```powershell
# Compare report data with actual metrics
.\get-dashboard-status.ps1  (actual)
.\get-last-report.ps1       (report)

# Expected: Matching values (within 1% margin)
# - Uptime % should match
# - Incident count should match
# - Resource usage should be similar
```

**Test 7.4: Scheduled Reports**

```powershell
# Check report schedule
.\get-report-schedule.ps1

# Expected: 3+ scheduled reports
# - Daily at 8 AM
# - Weekly at Friday 5 PM
# - Monthly on 1st at 7 AM

# Verify recipients configured:
.\get-report-schedule.ps1 | Select-Object Recipients

# Expected: Email addresses listed
```

**Test 7.5: Report Formats**

```powershell
# Verify HTML format
.\get-last-report.ps1 -Type Daily -Format HTML

# Expected: Opens in browser correctly

# Verify PDF format
.\get-last-report.ps1 -Type Daily -Format PDF

# Expected: PDF viewer opens
```

**Test 7.6: Email Delivery**

```powershell
# Check if scheduled report was emailed
# Check inbox for reports
# Look for: "HELIOS Daily Report - 2024-02-15"

# Expected: Email in inbox
# Expected: Report attachment or link
# Expected: Professional formatting
```

### Automated Tests

```powershell
Script: test-reporting.ps1
Tests: 3 total
├─ Reports generate
├─ Content accurate
└─ Scheduling works
Expected: All pass ✅
```

---

## 📋 Complete Test Execution Workflow

### Full Verification (Do this after deployment)

```powershell
# Step 1: Run quick checks (5 min)
.\test-phase3-complete.ps1 -Quick

# Step 2: Run full test suite (20 min)
.\test-phase3-complete.ps1

# Step 3: Review test report
.\get-last-report.ps1 -Type Test -Open

# Step 4: Verify each component individually

# Dashboard
.\test-dashboard.ps1

# AI
.\test-ai-engine.ps1

# Auto-Healing
.\test-auto-healing.ps1

# Profiles
.\test-profiles.ps1

# Workflows
.\test-workflows.ps1

# Performance
.\test-performance-ai.ps1

# Reporting
.\test-reporting.ps1

# Health
.\health-check-phase3.ps1

# Step 5: If any failed, troubleshoot
.\troubleshoot-all.ps1 > "C:\helios\logs\troubleshooting-report.log"

# Step 6: Generate support bundle if needed
.\generate-support-bundle.ps1
```

---

## ✅ Sign-Off Checklist

Use this checklist to confirm Phase 3 is ready for production:

### Dashboard

- [ ] Accessible at http://localhost:9000
- [ ] Service running and auto-restart on reboot
- [ ] Real-time metrics updating
- [ ] WebSocket connected
- [ ] Theme switching works
- [ ] Data accuracy ±3%

### AI Engine

- [ ] Service running
- [ ] All 6 models loaded
- [ ] Predictions generated for 24 hours ahead
- [ ] Confidence levels 70%+ for all models
- [ ] Accuracy improving daily (2%+ per day)
- [ ] Last training time recent

### Auto-Healing

- [ ] Service running
- [ ] 10+ healing rules loaded and enabled
- [ ] Test trigger successfully completes
- [ ] Healing events appear in history
- [ ] Auto-created tickets working
- [ ] Monitoring continues after heal

### Profiles

- [ ] 7+ built-in profiles available
- [ ] Can switch between profiles
- [ ] Settings apply when switching
- [ ] Custom profiles can be created
- [ ] Profile history tracked

### Workflows

- [ ] 250+ workflows loaded
- [ ] Manual workflow execution succeeds
- [ ] Workflow execution tracked in history
- [ ] Can enable/disable workflows
- [ ] Scheduled workflows have next run time

### Performance AI

- [ ] Service running
- [ ] Recommendations generated
- [ ] Recommendations applied successfully
- [ ] Before/after metrics showing improvement
- [ ] Analysis accurate

### Reporting

- [ ] Reports generate successfully
- [ ] Content accurate and complete
- [ ] Multiple formats supported (HTML, PDF)
- [ ] Scheduled reports email correctly
- [ ] Professional formatting

### Overall

- [ ] All 42 tests pass
- [ ] No critical errors
- [ ] All services healthy
- [ ] No resource warnings
- [ ] All logs clean
- [ ] Docs reviewed

---

**Status:** Ready for Phase 3 Deployment ✅

Once all checkboxes are checked, Phase 3 is operational!

---

**Last Updated:** 2024  
**For Phase 3.0.0**  
**Complete Testing Guide**
