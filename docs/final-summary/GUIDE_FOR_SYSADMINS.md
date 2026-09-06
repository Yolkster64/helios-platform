# HELIOS Platform - Guide for System Administrators

**Document Version:** 1.0  
**Date:** April 13, 2026  
**Audience:** System Administrators, Infrastructure Management

## Daily Operations

### Morning Checklist (9:00 AM)

```powershell
# 1. System Health Check (2 min)
.\scripts\health-check.ps1

# 2. Alert Review (3 min)
Get-AlertLog -Level Warning,Critical -LastHours 12

# 3. Backup Verification (2 min)
Get-BackupStatus -LastRun

# 4. Service Status (2 min)
Get-Service | Where-Object {$_.Name -like "*HELIOS*"} | Format-Table

# TOTAL: ~9 minutes
```

### Evening Checklist (5:00 PM)

```powershell
# 1. Daily Metrics Export (3 min)
Export-DailyMetrics -OutputPath "D:\Reports\$(Get-Date -Format 'yyyy-MM-dd')"

# 2. Security Log Review (5 min)
Get-EventLog -LogName Security -Newest 50 | Where-Object {$_.InstanceId -match "4624|4625"}

# 3. Verify Backups (3 min)
Get-BackupStatus -All

# 4. Tomorrow's Tasks (2 min)
Review-MaintenanceSchedule -Date (Get-Date).AddDays(1)

# TOTAL: ~13 minutes
```

## System Maintenance

### Weekly Maintenance (Friday, 2:00 PM)

**Time: 1.5 hours** (Scheduled downtime if needed)

```powershell
# 1. Full Backup Test (30 min)
$backup = Get-LatestBackup
Restore-Backup -TestMode $true -Destination "E:\Test-Restore"

# 2. Security Audit (20 min)
Get-SecurityEvent -LastDays 7
Update-FirewallRules -Verify $true

# 3. Performance Optimization (20 min)
Optimize-DiskSpace
Clear-CacheFiles -OlderThan 30

# 4. Documentation Update (20 min)
Update-SystemDocumentation -LatestMetrics
```

### Monthly Maintenance (First Friday)

**Time: 4 hours** (Scheduled maintenance window)

```powershell
# 1. Comprehensive Analysis (1 hour)
Analyze-Performance -Period Month
Review-SecurityCompliance
Review-CapacityTrends

# 2. Update Management (1 hour)
Get-WindowsUpdate -Available
Test-Updates -Environment Staging
# If OK: Install-Updates -Environment Production

# 3. Configuration Review (1 hour)
Review-HeliosConfiguration -CheckForUpdates
Verify-Hardening -Detailed

# 4. Reporting (1 hour)
New-MonthlyReport -IncludeAll
Send-Report -Distribution "management@org.com"
```

## Monitoring Setup

### Dashboard Configuration

**Create Daily Dashboard:**

```powershell
$dashboard = New-Dashboard -Name "Daily-Operations" -RefreshInterval 30
Add-DashboardPanel -Dashboard $dashboard -Name "System Health" -Type "Gauge"
Add-DashboardPanel -Dashboard $dashboard -Name "Performance" -Type "LineChart"
Add-DashboardPanel -Dashboard $dashboard -Name "Alerts" -Type "Timeline"
```

### Alert Configuration

**Critical Alerts (Must be configured):**

```powershell
# CPU Usage Alert
New-Alert -Name "HighCPUUsage" `
  -Condition "CPU > 80" `
  -Duration "5 minutes" `
  -Action @("Email", "Slack", "SMS")

# Memory Alert
New-Alert -Name "LowMemory" `
  -Condition "FreeMemory < 5%" `
  -Duration "2 minutes" `
  -Action @("Email", "Slack")

# Disk Space Alert
New-Alert -Name "LowDiskSpace" `
  -Condition "FreeDiskSpace < 10%" `
  -Action @("Email", "Slack", "Create-Ticket")

# Service Down Alert
New-Alert -Name "ServiceDown" `
  -Condition "ServiceStatus = Stopped" `
  -Action @("SMS", "PagerDuty", "Create-Incident")

# Backup Failure Alert
New-Alert -Name "BackupFailed" `
  -Condition "BackupStatus = Failed" `
  -Action @("Email", "Create-Ticket")
```

## Performance Management

### Performance Baseline

**Establish Baseline (Week 1):**

```powershell
# Collect baseline metrics over 7 days
$baseline = Measure-Performance -Days 7 -Detailed

# Results show:
# - Average CPU: 25%
# - Average Memory: 55%
# - Average Disk I/O: 15%
# - Boot Time: 45 seconds
# - Service Response: 200ms

# Store for comparison
Save-Baseline -Name "Production-Baseline" -Data $baseline
```

**Ongoing Monitoring:**

```powershell
# Daily comparison
Compare-Performance -Baseline "Production-Baseline"

# If degradation > 20%:
1. Identify bottleneck process
2. Review recent changes
3. Optimize or rollback
4. Document findings
```

### Performance Tuning

**CPU Optimization:**

```powershell
# Identify high-CPU processes
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10

# If HELIOS system high:
1. Check what task is running
2. Verify it's expected
3. Optimize if possible
4. Or just monitor
```

**Memory Optimization:**

```powershell
# Clear working set
[gc]::Collect()
Get-Process | ForEach-Object {$_.MaxWorkingSet = $_.MaxWorkingSet}

# Check for memory leaks
Get-PerformanceMemory -Days 7 -TrendAnalysis

# If growing: Restart service
Restart-Service -Name "HELIOS*" -Force
```

**Disk Optimization:**

```powershell
# Find large files
Get-ChildItem -Path "C:\" -Recurse -File | `
  Sort-Object Length -Descending | `
  Select-Object -First 20 FullName, @{N="Size(GB)";E={$_.Length/1GB}}

# Archive old logs
Move-OldLogs -Days 30 -Destination "D:\Archive"

# Defragment
Optimize-Disk -Defrag
```

## Backup & Recovery

### Backup Verification

**Daily Quick Check (5 min):**

```powershell
# Status check
Get-BackupStatus
  # Expected: Green, Completed successfully

# File count check
(Get-ChildItem "D:\Backups" -Recurse -File).Count
  # Should match: baseline file count
```

**Weekly Full Test (30 min):**

```powershell
# Restore to test location
Restore-Backup `
  -Source "D:\Backups\Full-2026-04-13" `
  -Destination "E:\Backup-Test" `
  -TestMode $true

# Verify restored files
Test-BackupIntegrity -Path "E:\Backup-Test"

# File and data integrity checks
Compare-BackupContent -Original "C:\" -Restored "E:\Backup-Test"
```

### Recovery Procedures

**Emergency File Recovery (< 10 minutes):**

```powershell
# 1. Find file in backup
$file = Find-FileInBackup -Name "ImportantFile.txt" -BackupList @(
  "Full-2026-04-13",
  "Full-2026-04-06",
  "Full-2026-03-30"
)

# 2. Restore specific file
Restore-FileFromBackup -File $file -Destination "C:\Restored\"

# 3. Verify file integrity
Test-FileIntegrity -File "C:\Restored\ImportantFile.txt"

# Result: File recovered ✅
```

**Full System Recovery (1 hour):**

```powershell
# 1. Boot from recovery media
# 2. Select backup to restore
#    Options: Recent backups shown

# 3. Initiate restore
$restoreJob = Start-FullRestore -Backup "Full-2026-04-13"

# 4. Monitor progress (will take ~30-40 min)
Get-RestoreProgress -Job $restoreJob

# 5. System reboots, verify startup
Test-SystemAfterRecovery

# Result: System fully recovered ✅
```

## Updates & Patches

### Windows Update Process

**Check for Updates:**

```powershell
Get-WindowsUpdate -Available | Format-Table Title, Classification
```

**Test Updates (Staging Environment):**

```powershell
# 1. Install in staging
Install-WindowsUpdate -Environment Staging

# 2. Run tests
Run-UpdateTests -Environment Staging

# 3. Check for issues
Get-EventLog -LogName System -After (Get-Date).AddHours(-2) | Where-Object Level -LT 3

# 4. Decision:
#    ✅ PASS: Safe to deploy to production
#    ❌ FAIL: Investigate before production
```

**Deploy Updates (Production):**

```powershell
# 1. Announce maintenance window
Send-MaintenanceNotification -StartTime "Saturday 2:00 AM" -Duration "2 hours"

# 2. Backup system
Create-Backup -Type Full -Name "Pre-Update-$(Get-Date -Format yyyy-MM-dd)"

# 3. Install updates
Install-WindowsUpdate -Environment Production -Schedule "2:00 AM"

# 4. Monitor during and after
Monitor-UpdateProcess
Verify-SystemHealth -Post-Update

# 5. Confirm success
Test-UpdateCompleted
# Result: Updates installed successfully ✅
```

## Security Management

### Daily Security Tasks

```powershell
# 1. Review failed login attempts
Get-EventLog -LogName Security -InstanceId 4625 -After (Get-Date).AddDays(-1) | Measure-Object
# Should be <5, investigate if >10

# 2. Check for unauthorized access
Get-SecurityEvent -Type "Unauthorized" -LastHours 24

# 3. Verify firewall rules
Get-NetFirewallRule | Where-Object Enabled -EQ $false | Measure-Object
# Should be 0 disabled security rules

# 4. Check antivirus status
Get-AntivirusStatus
# Status should be: Active, definitions current
```

### Monthly Security Audit

```powershell
# 1. Permission audit (30 min)
Audit-Permissions -Path "C:\Program Files\HELIOS" -Recursive

# 2. Account audit (20 min)
Get-LocalUser | Select-Object Name, LastLogon, PasswordExpires | Where-Object {$_.Enabled}

# 3. Security event analysis (30 min)
Analyze-SecurityEvents -Days 30 -IncludeThreats

# 4. Compliance check (20 min)
Verify-Compliance -Standard "CIS" -Detailed
```

## Troubleshooting

### Issue: System Running Slow

```powershell
# 1. Check CPU/Memory
Get-SystemMetrics
# If CPU >80%, identify process:
Get-Process | Sort CPU -Desc | Select -First 5

# 2. Check disk
Get-Disk | Select DriveLetter, @{N="Free(%)";E={($_.Free/$_.Total)*100}}
# If <20%, run cleanup

# 3. Check services
Get-Service | Where Status -NE Running | Select-Object Name
# If HELIOS services down, restart them

# 4. Reboot if needed
Restart-Computer -Force
```

### Issue: Deployment Failed

```powershell
# 1. Check logs
Get-DeploymentLog -LastHours 2 -Errors

# 2. Verify connectivity
Test-Connection github.com
Test-Connection nuget.org -Port 443

# 3. Check system requirements
$dotnet = dotnet --version
$ps = $PSVersionTable.PSVersion
# .NET 6+, PS 7+ required

# 4. Attempt rollback
.\scripts\rollback.ps1 -Confirm $false

# 5. Escalate if unresolved
Create-Ticket -Priority High -Category "Deployment"
```

### Issue: High Alerts

```powershell
# 1. Identify alert source
Get-AlertLog -Level Critical -Details

# 2. Check affected service/system
Get-Service "AlertedService" | Format-List

# 3. Determine cause
# - Temporary spike? Wait and monitor
# - Sustained high? Investigate
# - Configuration issue? Fix config

# 4. Clear alert once resolved
Clear-Alert -AlertID 12345
```

## Documentation

### Update System Documentation

**Monthly Update Template:**

```
SYSTEM DOCUMENTATION UPDATE - April 2026

1. Performance Summary
   - CPU (avg): 25%
   - Memory (avg): 55%
   - Disk (free): 300 GB
   - Uptime: 99.9%

2. Changes Made
   - Updated firewall rules (added port X)
   - Patched OS (April 2026 updates)
   - Upgraded HELIOS to v2.1.0

3. Issues Encountered
   - Temporary spike on Apr 10 - resolved
   - DNS issue Apr 15 - firewall rule added

4. Next Month's Tasks
   - Monthly backup test (May 3)
   - Security audit (May 15)
   - Update Windows (May 20)

5. Recommendations
   - Monitor CPU trend
   - Plan capacity expansion Q3
```

## Key Contacts

| Role | Name | Email | Phone | Hours |
|------|------|-------|-------|-------|
| On-Call Admin | [Name] | [Email] | [Phone] | 24/7 |
| Manager | [Name] | [Email] | [Phone] | Business |
| Director | [Name] | [Email] | [Phone] | On Demand |
| Vendor Support | N/A | support@helios.org | 1-800-XXX-XXXX | Business |

## Important Paths

```
Backups:           D:\Backups\
Logs:              D:\Logs\
Reports:           D:\Reports\
Scripts:           C:\Scripts\
Config:            C:\Program Files\HELIOS\Config\
Database:          C:\Program Files\HELIOS\Data\
```

---

**Status: ✅ COMPREHENSIVE SYSADMIN GUIDE READY**
