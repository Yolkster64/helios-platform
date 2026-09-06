# Performance AI Component

AI-powered performance optimization and system tuning for HELIOS Platform.

---

## Overview

Performance AI uses machine learning to analyze system behavior, predict bottlenecks, and automatically optimize performance. Learns your workload patterns and makes intelligent tuning recommendations.

**Key Facts:**

- **Phase:** 2
- **Standalone:** ⚠️ Partial (needs security-engine)
- **Requires:** security-engine (Phase 0), .NET Framework 4.8+, TensorFlow (bundled)
- **Version:** 0.8.1
- **Status:** Beta
- **Size:** 412 MB
- **Installation Time:** 8-12 minutes

---

## What It Does

### Core Features

1. **Workload Analysis**
   - Real-time performance metrics
   - Pattern recognition
   - Bottleneck identification
   - Resource utilization analysis

2. **Predictive Modeling**
   - Performance forecasting
   - Trend analysis
   - Peak load prediction
   - Anomaly detection

3. **Automatic Tuning**
   - CPU optimization
   - Memory optimization
   - Disk I/O optimization
   - Network optimization

4. **Recommendations**
   - AI-powered suggestions
   - Impact estimation
   - Risk assessment
   - Implementation automation

5. **Learning Phase**
   - Adapts to your workload
   - Improves recommendations over time
   - Learns application-specific patterns

---

## System Requirements

### Minimum

- **Requires:** security-engine (Phase 0) installed first
- **OS:** Windows Server 2019+ or Windows 10+
- **.NET Framework:** 4.8+
- **RAM:** 4 GB (more recommended, AI training intensive)
- **Disk:** 500 MB available for models
- **CPU:** Multi-core processor

### Recommended

- **OS:** Windows Server 2022+
- **.NET Framework:** 4.8.1+
- **RAM:** 8+ GB
- **Disk:** 1 GB available
- **CPU:** 4+ cores, SSE4.2 support
- **GPU:** NVIDIA/AMD GPU (optional, improves learning)

---

## Installation Procedure

### Important: Install security-engine First

Performance AI requires security-engine as a hard dependency:

```powershell
# Step 1: Install security engine (Phase 0)
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# Step 2: Install performance-ai (Phase 2)
cd ..\performance-ai
.\install.ps1
```

### With Learning Mode

```powershell
.\install.ps1 -LearningMode -LearningDurationHours 72
# AI trains on your workload for 72 hours before making recommendations
# Best for accurate recommendations
```

### With Aggressive Tuning

```powershell
.\install.ps1 -AggressiveTuning -WarningLevel high
# Makes more aggressive optimizations
# WARNING: May cause performance dips before optimization improves
```

### With Conservative Tuning

```powershell
.\install.ps1 -ConservativeTuning -WarningLevel low
# Makes minimal changes
# Best for production systems, safest approach
```

### Silent Installation

```powershell
.\install.ps1 -Silent -TuningLevel "balanced"
```

---

## Configuration

**Config File:** `C:\Program Files\HELIOS\performance-ai\config.json`

```json
{
  "learningPhase": {
    "enabled": true,
    "durationHours": 72,
    "dataCollectionInterval": 60,
    "minimumDataPoints": 1000
  },

  "optimization": {
    "level": "balanced",
    "autoTuning": true,
    "maxChangePercent": 20,
    "backupBeforeTuning": true,
    "allowRollback": true,
    "testRecommendations": true
  },

  "models": {
    "cpuOptimization": true,
    "memoryOptimization": true,
    "diskOptimization": true,
    "networkOptimization": true,
    "enableGPU": false
  },

  "alerts": {
    "anomalyDetection": true,
    "anomalySensitivity": 0.8,
    "performanceAlerts": true,
    "alertThreshold": "medium"
  },

  "logging": {
    "enabled": true,
    "path": "C:\\Program Files\\HELIOS\\performance-ai\\logs",
    "level": "Information",
    "retentionDays": 30
  }
}
```

### Tuning Levels

**Conservative:** 5-10% performance improvement, minimal risk
**Balanced:** 10-20% improvement, balanced risk/reward
**Aggressive:** 20-40% improvement, higher risk

---

## Usage Examples

### Get Performance Recommendations

```powershell
$perf = New-Object HeliosPlatform.PerformanceAI.PerformanceOptimizer
$recs = $perf.GetOptimizationRecommendations()

foreach ($rec in $recs) {
    Write-Host "Priority: $($rec.Priority) (Critical/High/Medium/Low)"
    Write-Host "Recommendation: $($rec.Description)"
    Write-Host "Expected Improvement: $($rec.ExpectedImprovementPercent)%"
    Write-Host "Risk Level: $($rec.RiskLevel)"
    Write-Host "---"
}
```

### Apply Optimization

```powershell
$rec = $recs[0]  # First recommendation

# Preview changes
$preview = $perf.PreviewOptimization($rec.Id)
Write-Host "Changes: $($preview.Changes)"
Write-Host "Estimated time to implement: $($preview.EstimatedTime) minutes"

# Apply it
$result = $perf.ApplyOptimization($rec.Id)

if ($result.Success) {
    Write-Host "Optimization applied"
    Write-Host "New performance score: $($result.NewScore)"
    Write-Host "Before: $($result.OldScore) → After: $($result.NewScore)"
    Write-Host "Improvement: $($result.ImprovementPercent)%"
} else {
    Write-Host "Failed: $($result.ErrorMessage)"
}
```

### Monitor Learning Progress

```powershell
$status = $perf.GetLearningStatus()

Write-Host "Learning Progress: $($status.ProgressPercent)%"
Write-Host "Data Points Collected: $($status.DataPointsCount)"
Write-Host "Estimated Time Remaining: $($status.TimeRemainingHours) hours"
Write-Host "Confidence Level: $($status.ConfidencePercent)%"
```

### Revert Optimization

```powershell
# Get last applied optimization
$applied = $perf.GetAppliedOptimizations() | Select-Object -Last 1

# Rollback
$result = $perf.RollbackOptimization($applied.Id)

if ($result.Success) {
    Write-Host "Reverted to previous state"
}
```

### Get Performance Score

```powershell
$score = $perf.GetPerformanceScore()

Write-Host "Overall Score: $($score.OverallScore)/100"
Write-Host "CPU Score: $($score.CPUScore)/100"
Write-Host "Memory Score: $($score.MemoryScore)/100"
Write-Host "Disk Score: $($score.DiskScore)/100"
Write-Host "Network Score: $($score.NetworkScore)/100"
```

---

## Understanding AI Learning

### Learning Phase Duration

- **Short (24h):** Quick baseline, less accurate recommendations
- **Standard (72h):** Good balance, recommended for most
- **Extended (168h):** Excellent accuracy, best for variable workloads

### What AI Learns

```
- CPU usage patterns
- Memory allocation trends
- Disk I/O patterns
- Network traffic patterns
- Application-specific behavior
- Peak load times
- Off-peak patterns
- Resource competition
```

### Improving AI Accuracy

1. Let learning phase complete without major changes
2. Run typical workloads during learning
3. Don't make manual optimizations during learning
4. Keep system stable during learning period
5. Extend learning if workload is highly variable

---

## Performance Tuning

### Conservative Configuration (Safest)

```json
{
  "optimization": {
    "level": "conservative",
    "maxChangePercent": 5,
    "testRecommendations": true,
    "allowRollback": true
  }
}
```

Use for: Production systems, mission-critical

### Balanced Configuration (Recommended)

```json
{
  "optimization": {
    "level": "balanced",
    "maxChangePercent": 20,
    "testRecommendations": true,
    "allowRollback": true
  }
}
```

Use for: Most deployments

### Aggressive Configuration (High Risk)

```json
{
  "optimization": {
    "level": "aggressive",
    "maxChangePercent": 40,
    "testRecommendations": false,
    "allowRollback": true
  }
}
```

Use for: Development/testing, when speed matters

---

## Troubleshooting

### Performance AI Not Making Recommendations

```powershell
# Check learning status
$status = $perf.GetLearningStatus()

if ($status.ProgressPercent -lt 100) {
    Write-Host "Still learning: $($status.ProgressPercent)%"
    Write-Host "Remaining: $($status.TimeRemainingHours) hours"
}

# Not enough data
if ($status.DataPointsCount -lt 1000) {
    Write-Host "Need more data points: $($status.DataPointsCount)/1000"
    Write-Host "Increase learning duration"
}
```

### Models Failing to Load

```powershell
# Check model files
Test-Path "C:\Program Files\HELIOS\performance-ai\ml-models\"

# Reinstall models
.\reinstall-models.ps1

# Check logs
Get-Content "C:\Program Files\HELIOS\performance-ai\logs\performance-ai.log" -Tail 50
```

### Optimization Too Aggressive

```json
{
  "optimization": {
    "maxChangePercent": 10
  }
}
```

Then restart and re-run recommendations.

### Performance Degraded After Optimization

```powershell
# Immediate rollback
$perf.RollbackOptimization($lastOptimizationId)

# Change to more conservative
.\modify-config.ps1 -TuningLevel "conservative"
```

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\performance-ai\

Application Files:
├── bin\
│   ├── optimizer.exe
│   ├── optimizer.dll
│   └── tensorflow\

ML Models:
├── ml-models\
│   ├── cpu-optimizer.model
│   ├── memory-optimizer.model
│   ├── disk-optimizer.model
│   └── network-optimizer.model

Training Data:
├── data\
│   ├── training-data.db
│   ├── performance-history.db
│   └── recommendations.db

Configuration:
├── config.json

Logs:
├── logs\
│   ├── optimization.log
│   ├── learning.log
│   └── errors.log

Backups:
├── backups\
│   └── pre-optimization-configs\
```

---

## Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\performance-ai

# Revert all optimizations first
.\revert-optimizations.ps1

# Then uninstall
.\uninstall.ps1
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.8.1 | 2023-12-20 | Bug fixes, model improvements |
| 0.8.0 | 2023-12-01 | Initial beta release |

---

## Support

- **Learning Issues:** Review config learning parameters
- **Recommendations:** Check logs for analysis details
- **Troubleshooting:** See Troubleshooting section
- **Standalone Usage:** See INDEPENDENT_INSTALLATION.md (requires security-engine)
