#################################################################################

# HELIOS Platform - Backup README

# Purpose: Documentation for backup and recovery system

# Version: 1.0.0

#################################################################################

# HELIOS Platform - Comprehensive Backup & Recovery System

## Overview

This backup and recovery system provides enterprise-grade backup capabilities for the HELIOS Platform, including:

- **Full System Backups**: Complete snapshots of all systems, configurations, and data
- **Incremental Backups**: Only changed data since last backup (4-6 hours frequency)
- **Differential Backups**: Changes since last full backup (daily)
- **Database Backups**: All 5 SQL Server databases with verification
- **Configuration Backup**: System configs, IIS settings, registry
- **File System Backup**: All user data with change tracking
- **Cloud Backup**: Replication to Azure with encryption
- **Point-in-Time Recovery**: Restore to any previous point
- **Disaster Recovery**: Complete system restoration
- **Verification**: Automated integrity checking

## Directory Structure

```
C:\HELIOS\Scripts\Backup\
├── 0_BackupCore.ps1              # Core infrastructure and utilities
├── 1_FullBackup.ps1              # Full system backup script
├── 2_IncrementalBackup.ps1       # Incremental backup script
├── 3_DifferentialBackup.ps1      # Differential backup script
├── 4_CloudBackup.ps1             # Cloud replication script
├── MasterOrchestrator.ps1        # Central operation controller
├── Utilities/
│   ├── 1_BackupVerification.ps1  # Backup integrity verification
│   ├── 2_BackupCleanup.ps1       # Retention policy enforcement
│   ├── 3_HealthCheck.ps1         # System health assessment
│   └── Send-BackupAlert.ps1      # Alert notifications
├── Recovery/
│   ├── 1_PointInTimeRecovery.ps1 # Point-in-time restoration
│   └── 2_DisasterRecovery.ps1    # Full system restoration
└── Scheduling/
    └── 1_ConfigureScheduling.ps1 # Windows Task Scheduler setup

D:\HELIOS\Backups/
├── Metadata/                      # Backup metadata (JSON)
├── System/                        # Full and differential backups
├── Databases/                     # Database backups
├── Configuration/                 # Config backups
├── FileSystem/                    # File system backups
├── Cloud/                         # Cloud staging area
└── Archive/                       # Archived backups

D:\HELIOS\Logs\Backup/
├── FullBackup/                    # Full backup logs
├── IncrementalBackup/             # Incremental backup logs
├── DifferentialBackup/            # Differential backup logs
├── CloudBackup/                   # Cloud sync logs
├── Verification/                  # Verification logs
└── ...
```

## Backup Strategy

### Retention Policy

- **Full Backups**: 90 days retention
- **Incremental Backups**: 30 days retention
- **Differential Backups**: 30 days retention
- **Metadata**: 30 days retention

### Backup Schedule

| Backup Type | Frequency | Time | Priority |
|-------------|-----------|------|----------|
| Full Backup | Daily | 22:00 (10 PM) | 7 |
| Differential | Daily | 12:00 (Noon) | 7 |
| Incremental | Every 6 hours | Starting 06:00 | 8 |
| Cloud Sync | Hourly | Starting 08:00 | 5 |
| Verification | Weekly | Sunday 03:00 | 6 |
| Cleanup | Weekly | Saturday 02:00 | 4 |
| Health Check | Daily | 06:00 | 9 |

## Database Backups

The system backs up all 5 HELIOS databases:

1. **HELIOS_Core**: Primary database (Full + TRN backups)
2. **HELIOS_Users**: User management database
3. **HELIOS_Analytics**: Analytics and reporting
4. **HELIOS_Config**: Configuration settings
5. **HELIOS_Audit**: Audit logging

Each database backup includes:

- Full backup for full system backups
- Transaction log backups for incremental recovery
- Differential backups for point-in-time recovery

## Configuration Backup

Backed up configuration includes:

- C:\HELIOS\Config\ - Application configuration
- C:\HELIOS\Settings\ - System settings
- C:\HELIOS\SSL\ - SSL certificates
- Registry: HKLM:\SOFTWARE\HELIOS
- Registry: HKLM:\SYSTEM\CurrentControlSet\Services\HELIOS*
- IIS Configuration (if applicable)
- System hosts file

## File System Backup

Backed up directories:

- D:\HELIOS\Data\ - Application data
- D:\HELIOS\Documents\ - Documents
- D:\HELIOS\Reports\ - Reports
- D:\HELIOS\Media\ - Media files

Exclusions:

- *.tmp files (temporary)
- *.log files (logs)

## Cloud Backup

### Azure Configuration

```powershell
$env:AZURE_ACCOUNT = "heliosbackup"
$env:AZURE_KEY = "<storage-account-key>"
```

### Features

- Automatic compression before upload
- GPG encryption (if available)
- Metadata tracking
- Bandwidth throttling
- Failed upload retry

## Scheduled Tasks

### Setup Scheduling

```powershell
C:\HELIOS\Scripts\Backup\Scheduling\1_ConfigureScheduling.ps1 -Action Setup
```

### View Task Status

```powershell
C:\HELIOS\Scripts\Backup\Scheduling\1_ConfigureScheduling.ps1 -Action List
```

### Disable All Tasks

```powershell
C:\HELIOS\Scripts\Backup\Scheduling\1_ConfigureScheduling.ps1 -Action Disable
```

## Usage Examples

### Execute Full Backup

```powershell
PS> C:\HELIOS\Scripts\Backup\1_FullBackup.ps1 -VerifyAfterBackup $true -CompressBackup $true
```

### Execute Incremental Backup

```powershell
PS> C:\HELIOS\Scripts\Backup\2_IncrementalBackup.ps1 -CompressBackup $true
```

### Verify Backup

```powershell
PS> C:\HELIOS\Scripts\Backup\Utilities\1_BackupVerification.ps1 -BackupId "<backup-guid>" -TestRestore $true
```

### Check System Health

```powershell
PS> C:\HELIOS\Scripts\Backup\Utilities\3_HealthCheck.ps1
```

### Perform Point-in-Time Recovery

```powershell
PS> C:\HELIOS\Scripts\Backup\Recovery\1_PointInTimeRecovery.ps1 -RecoveryTime "2024-04-10 14:30:00" -DryRun $true
```

### Execute Disaster Recovery

```powershell
PS> C:\HELIOS\Scripts\Backup\Recovery\2_DisasterRecovery.ps1 -BackupId "<backup-guid>" -DryRun $true
```

### Use Master Orchestrator

```powershell
PS> C:\HELIOS\Scripts\Backup\MasterOrchestrator.ps1 -Operation FullBackup -SendNotifications $true
```

## Backup Verification

The verification system checks:

1. **File Integrity**: SHA256 checksums for all files
2. **Database Backups**: RESTORE VERIFYONLY for each database
3. **Archive Integrity**: 7-Zip integrity verification
4. **Test Restore**: Extract and validate backup contents

## Alerting

Backup alerts can be sent via:

- **Email**: Configure SMTP settings in environment variables
- **Slack**: Configure SLACK_WEBHOOK_URL
- **Teams**: Can be added (see future enhancements)

Environment variables:

```powershell
$env:SMTP_SERVER = "smtp.example.com"
$env:SMTP_PORT = "587"
$env:SMTP_FROM = "backup@helios.local"
$env:SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/..."
```

## Performance Characteristics

### Typical Sizes

- **Full Backup**: 200-500 GB (depends on data volume)
- **Incremental Backup**: 10-50 GB (typical)
- **Differential Backup**: 30-100 GB (daily)
- **Compression Ratio**: 2:1 to 4:1 depending on data

### Typical Durations

- **Full Backup**: 4-6 hours
- **Incremental Backup**: 30-60 minutes
- **Differential Backup**: 1-2 hours
- **Cloud Upload**: Depends on bandwidth
- **Verification**: 30-45 minutes

## Recovery Time Objectives (RTO)

| Recovery Scope | RTO | Method |
|---|---|---|
| Single Database | 15 minutes | Database restore |
| Single File | 5 minutes | File restore |
| Point-in-Time | 30 minutes | Incremental chain restore |
| Full System | 2-4 hours | Disaster recovery |
| Cloud Restore | 4-8 hours | Download + restore |

## Troubleshooting

### Backup Fails

1. Check backup drive space
2. Review logs in D:\HELIOS\Logs\Backup\
3. Verify SQL Server service is running
4. Check file permissions

### Verification Failures

1. Check backup file integrity
2. Verify database consistency
3. Test with smaller backups first
4. Review compression settings

### Cloud Upload Issues

1. Verify Azure credentials
2. Check network connectivity
3. Review Azure storage quota
4. Check bandwidth limits

### Scheduled Tasks Not Running

1. Verify task scheduler service is running
2. Check task history in Event Viewer
3. Verify PowerShell execution policy
4. Test manual script execution

## Security Considerations

1. **Encryption**: GPG encryption supported for cloud storage
2. **Access Control**: Backups stored with restrictive NTFS permissions
3. **Credentials**: Azure keys stored in environment variables
4. **Audit**: All operations logged with timestamps
5. **Retention**: Old backups automatically deleted per policy

## Monitoring

Use the health check for continuous monitoring:

```powershell
PS> C:\HELIOS\Scripts\Backup\Utilities\3_HealthCheck.ps1
```

Monitors:

- Backup directory structure
- Disk space usage
- Last backup age
- Overall system health

## Future Enhancements

- [ ] Microsoft Teams integration
- [ ] Database transaction log shipping
- [ ] Rsync for offsite backups
- [ ] Backup deduplication
- [ ] Synthetic backups
- [ ] Incremental cloud uploads
- [ ] Backup encryption key rotation
- [ ] Machine learning-based anomaly detection
- [ ] REST API for backup management
- [ ] Web UI for monitoring and recovery

## Support and Contact

For issues, questions, or enhancement requests:

- Email: devops@helios.local
- Documentation: \\network\helios\backup-docs
- Runbooks: \\network\helios\runbooks
