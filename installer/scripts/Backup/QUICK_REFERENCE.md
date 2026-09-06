# HELIOS Backup & Recovery - Quick Reference

## 🎯 Essential Commands

### Initial Setup

```powershell
# Create scheduled tasks
C:\HELIOS\Scripts\Backup\Scheduling\1_ConfigureScheduling.ps1 -Action Setup

# View task status
C:\HELIOS\Scripts\Backup\Scheduling\1_ConfigureScheduling.ps1 -Action List
```

### Running Backups Manually

```powershell
# Full system backup
C:\HELIOS\Scripts\Backup\1_FullBackup.ps1

# Incremental backup
C:\HELIOS\Scripts\Backup\2_IncrementalBackup.ps1

# Differential backup
C:\HELIOS\Scripts\Backup\3_DifferentialBackup.ps1

# Cloud sync
C:\HELIOS\Scripts\Backup\4_CloudBackup.ps1 -BackupId "<guid>"
```

### Verification & Health

```powershell
# Check system health
C:\HELIOS\Scripts\Backup\Utilities\3_HealthCheck.ps1

# Verify specific backup
C:\HELIOS\Scripts\Backup\Utilities\1_BackupVerification.ps1 -BackupId "<guid>"

# Cleanup old backups
C:\HELIOS\Scripts\Backup\Utilities\2_BackupCleanup.ps1
```

### Recovery Operations

```powershell
# Point-in-time recovery (dry run)
C:\HELIOS\Scripts\Backup\Recovery\1_PointInTimeRecovery.ps1 `
    -RecoveryTime ([DateTime]"2024-04-10 14:30:00") `
    -DryRun $true

# Disaster recovery (dry run)
C:\HELIOS\Scripts\Backup\Recovery\2_DisasterRecovery.ps1 `
    -BackupId "<guid>" `
    -DryRun $true
```

## 📁 Key Paths

| Purpose | Path |
|---------|------|
| Scripts | C:\HELIOS\Scripts\Backup |
| Backups | D:\HELIOS\Backups |
| Metadata | D:\HELIOS\Backups\Metadata |
| Logs | D:\HELIOS\Logs\Backup |
| Databases | D:\HELIOS\Backups\Databases |

## 📊 Backup Schedule

| Operation | When | Duration |
|-----------|------|----------|
| Full Backup | Daily 22:00 | 4-6 hours |
| Differential | Daily 12:00 | 1-2 hours |
| Incremental | Every 6 hours | 30-60 min |
| Cloud Sync | Hourly | 15-30 min |
| Verification | Weekly Sun 03:00 | 30-45 min |
| Cleanup | Weekly Sat 02:00 | 30 min |
| Health Check | Daily 06:00 | 10 min |

## 🚨 Troubleshooting

### Backup fails

1. Check D:\HELIOS\Logs\Backup\FullBackup\*.log
2. Verify D:\HELIOS\Backups has >50% free space
3. Ensure SQL Server service is running

### No backups scheduled

1. Run: `1_ConfigureScheduling.ps1 -Action Setup`
2. Check Task Scheduler: Backup tasks under \HELIOS\Backup\
3. Verify task runs as NT AUTHORITY\SYSTEM

### Recovery dry run before actual restore

Always run with `-DryRun $true` first to validate

### Storage full

1. Run cleanup: `2_BackupCleanup.ps1`
2. Review retention policy (currently 30-90 days)
3. Consider archiving to external storage

## ✨ Features at a Glance

| Feature | Details |
|---------|---------|
| Databases | 5 SQL Server databases with RESTORE VERIFYONLY |
| Incremental | Transaction logs + changed files only |
| Differential | All changes since last full backup |
| Cloud | Azure with 7-Zip compression & GPG encryption |
| Point-in-Time | Restore to any historical point |
| Disaster Recovery | Complete system from scratch |
| Verification | SHA256 checksums + integrity checks |
| Monitoring | Health checks, alerts via Email/Slack |

## 🔐 Environment Variables (Optional)

```powershell
# Azure cloud backup
$env:AZURE_ACCOUNT = "heliosbackup"
$env:AZURE_KEY = "<storage-account-key>"

# Email alerts
$env:SMTP_SERVER = "smtp.example.com"
$env:SMTP_PORT = "587"
$env:SMTP_FROM = "backup@helios.local"
$env:SMTP_USESSL = "true"

# Slack alerts
$env:SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/..."
```

## 📈 Performance Stats

| Operation | Size | Duration |
|-----------|------|----------|
| Full Backup | 200-500 GB | 4-6 hours |
| Incremental | 10-50 GB | 30-60 min |
| Differential | 30-100 GB | 1-2 hours |
| Compressed | 2:1 to 4:1 ratio | +30-60 min |

## 📞 Support Resources

- Full Documentation: IMPLEMENTATION_SUMMARY.md
- User Guide: README.md
- Logs: D:\HELIOS\Logs\Backup\{operation}\
- Metadata: D:\HELIOS\Backups\Metadata\{guid}.json

## ⏱️ Recovery Time Objectives

| Scenario | Time |
|----------|------|
| Single database | 15 minutes |
| Single file | 5 minutes |
| Point-in-time recovery | 30-45 minutes |
| Full system | 2-4 hours |
| From cloud | 4-8 hours |
