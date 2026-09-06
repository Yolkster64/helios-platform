# Uninstall Guide

Learn how to remove HELIOS components cleanly, with options for data preservation, rollback, and registry cleanup.

---

## Uninstall Overview

Each HELIOS component can be uninstalled independently without affecting others. Uninstall procedures preserve data by default but can clean everything if needed.

**Key Points:**

- ✅ Uninstalling one component doesn't affect others
- ✅ Configuration preserved by default
- ✅ Data preserved by default
- ✅ Complete cleanup available with flags
- ✅ Easy reinstall of uninstalled component

---

## Basic Uninstall

### Uninstall Single Component

```powershell
# Navigate to component directory
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Run uninstall
.\uninstall.ps1

# Component removes itself
# Configuration files preserved at: C:\Program Files\HELIOS\ai-dashboard\config-backup\
# Data preserved at: C:\Program Files\HELIOS\ai-dashboard\data-backup\
```

### Uninstall All Components

```powershell
cd C:\Users\ADMIN\helios-platform\components

# Uninstall everything
.\uninstall-all.ps1

# All components removed
# Each component's data backed up
# Can reinstall later with full data restore
```

---

## Uninstall Options

### Option 1: Remove Component, Keep Configuration

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\uninstall.ps1 -PreserveConfig

# ✅ Removes: Executable, DLLs, runtime files
# ✅ Keeps: Configuration files (config.json)
# ✅ Keeps: Data files
# ✅ Time: 1-2 minutes
```

**Use case:** Upgrading the same component version later

### Option 2: Remove Component, Keep Data

```powershell
.\uninstall.ps1 -PreserveData

# ✅ Removes: Executable, DLLs, configuration
# ✅ Keeps: Database files, metrics, logs
# ⚠️  Config may not match data after reinstall
# ✅ Time: 1-2 minutes
```

**Use case:** Migrating data to another system

### Option 3: Remove Component, Keep Everything

```powershell
.\uninstall.ps1 -PreserveAll

# ✅ Removes: Only executable and DLLs
# ✅ Keeps: Everything else (config, data, logs)
# ✅ Fastest option
# ✅ Time: 30 seconds
```

**Use case:** Quick uninstall before quick reinstall

### Option 4: Complete Cleanup (Remove Everything)

```powershell
.\uninstall.ps1 -CompleteCleanup

# ✅ Removes: All files including config, data, logs
# ✅ Removes: Registry entries
# ✅ Removes: Service registrations
# ⚠️  WARNING: Cannot recover data after this!
# ✅ Time: 2-3 minutes
```

**Use case:** Complete removal before new deployment

### Option 5: Backup Before Removal

```powershell
.\uninstall.ps1 -CreateBackup -BackupPath "C:\Backups\ai-dashboard-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"

# ✅ Creates: Complete backup in specified directory
# ✅ Removes: Component
# ✅ Can restore: Full state later
# ✅ Time: 3-5 minutes
```

**Use case:** Safe removal before major system changes

---

## Uninstall Examples

### Example 1: Upgrade Component

```powershell
# Current: ai-dashboard v2.0
# Goal: Upgrade to v2.1

# Step 1: Uninstall current version
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\uninstall.ps1 -PreserveConfig

# Step 2: Verify removal
Get-ChildItem "C:\Program Files\HELIOS\ai-dashboard\bin" -ErrorAction SilentlyContinue
# Should be empty or not exist

# Step 3: Install new version
.\install.ps1

# Configuration and settings preserved automatically
```

### Example 2: Safe Removal with Backup

```powershell
# Create backup first
.\components\ai-dashboard\uninstall.ps1 `
    -CreateBackup `
    -BackupPath "C:\Backup-2024-01-20\ai-dashboard"

# Backup location:
# C:\Backup-2024-01-20\ai-dashboard\
# ├── config.json
# ├── data\
# ├── logs\
# └── certificates\

# Component removed, but can restore if needed
```

### Example 3: Complete Cleanup Before Reinstall

```powershell
# Scenario: Dashboard corrupted, need clean start

# Complete cleanup
.\uninstall.ps1 -CompleteCleanup -Force

# Verify cleanup
Test-Path "C:\Program Files\HELIOS\ai-dashboard"
# Returns: $false (all gone)

# Get-Service helios-dashboard -ErrorAction SilentlyContinue
# Returns: Nothing (service removed)

# Fresh reinstall
.\install.ps1
```

### Example 4: Uninstall Everything, Preserve All Data

```powershell
# Uninstall all components but keep everything
cd C:\Users\ADMIN\helios-platform\components

.\uninstall-all.ps1 -PreserveAll

# All components removed, but can access data:
# C:\Program Files\HELIOS\<component>\data\
# C:\Program Files\HELIOS\<component>\config.json
# Migrate data to new system or new installation
```

---

## Uninstall Command Reference

### ai-dashboard Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Default (preserve config and data)
.\uninstall.ps1

# Preserve configuration
.\uninstall.ps1 -PreserveConfig

# Preserve data only
.\uninstall.ps1 -PreserveData

# Remove everything
.\uninstall.ps1 -CompleteCleanup

# Create backup before uninstall
.\uninstall.ps1 -CreateBackup -BackupPath "C:\Backups\dashboard-backup"

# Silent uninstall
.\uninstall.ps1 -Silent
```

### vault-dynamics Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics

# Default (preserve keys)
.\uninstall.ps1

# IMPORTANT: Preserve encryption keys!
.\uninstall.ps1 -PreserveKeys -BackupPath "C:\Vault-Backup"

# Backup before removing
.\uninstall.ps1 -CreateBackup -BackupPath "C:\Backup-Vault"

# Remove keys (WARNING: Cannot decrypt data after!)
.\uninstall.ps1 -CompleteCleanup
```

### security-engine Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\security-engine

# Default (preserve users)
.\uninstall.ps1

# Preserve user database
.\uninstall.ps1 -PreserveData

# Remove everything
.\uninstall.ps1 -CompleteCleanup
```

### analytics-core Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\analytics-core

# Default (preserve data)
.\uninstall.ps1

# Export data before removal
.\uninstall.ps1 -ExportData -ExportPath "C:\Analytics-Export" -Format "Excel"

# Remove everything
.\uninstall.ps1 -CompleteCleanup
```

### performance-ai Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\performance-ai

# Default (preserve settings)
.\uninstall.ps1

# Revert optimizations first
.\uninstall.ps1 -RevertOptimizations

# Backup before removal
.\uninstall.ps1 -CreateBackup -BackupPath "C:\Backup-AI"
```

### cloud-bridge Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\cloud-bridge

# Default (preserve configuration)
.\uninstall.ps1

# Disconnect from cloud first
.\uninstall.ps1 -DisconnectCloud

# Remove everything
.\uninstall.ps1 -CompleteCleanup
```

---

## Rollback Procedures

### Rollback After Uninstall

If you uninstalled a component and want to restore it:

```powershell
# Method 1: Reinstall with preserved config
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

.\install.ps1 -UseExistingConfig

# Configuration automatically loaded from backup
# Data may need to be restored manually
```

### Restore from Backup

```powershell
# If you created a backup before uninstall
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Create backup before uninstall (if you did this)
.\uninstall.ps1 -CreateBackup -BackupPath "C:\Backups\dashboard-20240120"

# Later, restore from backup
.\restore-from-backup.ps1 -BackupPath "C:\Backups\dashboard-20240120"

# Component fully restored with all data
```

### Partial Rollback (Revert Optimizations)

```powershell
# If performance-ai made changes you want to undo:
cd ..\performance-ai

# Revert all AI optimizations to baseline
.\revert-optimizations.ps1

# Then uninstall if desired
.\uninstall.ps1
```

---

## Files Left Behind

### After Default Uninstall (data preserved)

```
C:\Program Files\HELIOS\<component>\
├── config.json (preserved)
├── config-backup\ (preserved)
├── data\ (preserved)
│   └── (all data files)
├── logs\ (preserved)
│   └── (log files)
└── bin\ (REMOVED)
```

### Registry Entries

After uninstall, some registry entries may remain:

```
HKEY_LOCAL_MACHINE\SOFTWARE\HELIOS\<component>
├── Version: Preserved
├── InstallPath: Points to removed location (safe)
├── LastRun: Preserved for records
└── Config: Preserved or removed based on flags
```

To clean registry:

```powershell
# Option 1: Automatic cleanup
.\uninstall.ps1 -CleanRegistry

# Option 2: Manual cleanup
Remove-Item 'HKLM:\SOFTWARE\HELIOS\ai-dashboard' -Force
```

### Windows Services

Uninstall removes services:

```powershell
# Check if service exists after uninstall
Get-Service -Name "HELIOS-ai-dashboard" -ErrorAction SilentlyContinue
# Should return: Nothing

# If service remains (error condition)
Remove-Service -Name "HELIOS-ai-dashboard" -Force
```

---

## Uninstall for Specific Scenarios

### Scenario 1: Replace Component Version

```powershell
# Remove old version but keep config
.\uninstall.ps1 -PreserveConfig

# Install new version
.\install.ps1

# New version reads old config automatically
# Settings maintained, but code updated
```

### Scenario 2: Migrate to New Server

```powershell
# Before uninstalling on old server:
.\uninstall.ps1 -CreateBackup -BackupPath "\\NewServer\Backups\ai-dashboard"

# On new server:
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

.\install.ps1
.\restore-from-backup.ps1 -BackupPath "\\NewServer\Backups\ai-dashboard"

# Dashboard restored on new server with all history
```

### Scenario 3: Disable Component Without Removing

```powershell
# If you just want to stop it (not uninstall):
Get-Service -Name "HELIOS-ai-dashboard" | Stop-Service

# Component still installed, just not running
# Can restart: Start-Service -Name "HELIOS-ai-dashboard"
```

### Scenario 4: Complete Clean Uninstall

```powershell
# For fresh installation (remove everything):
.\uninstall.ps1 -CompleteCleanup -Force

# Verify complete removal
Test-Path "C:\Program Files\HELIOS\ai-dashboard"
# Should be: $false

Get-Service "HELIOS-ai-dashboard" -ErrorAction SilentlyContinue
# Should be: Nothing
```

---

## Data Preservation Guide

### Important Data by Component

**ai-dashboard:**

```
PRESERVE: C:\Program Files\HELIOS\ai-dashboard\data\metrics.db
PRESERVE: C:\Program Files\HELIOS\ai-dashboard\config.json
PRESERVE: C:\Program Files\HELIOS\ai-dashboard\logs\
```

**vault-dynamics:**

```
PRESERVE: C:\Program Files\HELIOS\vault-dynamics\keys\master-key.encrypted
PRESERVE: C:\Program Files\HELIOS\vault-dynamics\keys\key-store.db
PRESERVE: C:\Program Files\HELIOS\vault-dynamics\backups\
WARNING:  Without keys, cannot decrypt any data!
```

**security-engine:**

```
PRESERVE: C:\Program Files\HELIOS\security-engine\database\users.db
PRESERVE: C:\Program Files\HELIOS\security-engine\logs\audit.log
```

**analytics-core:**

```
PRESERVE: C:\Program Files\HELIOS\analytics-core\data\analytics.db
PRESERVE: C:\Program Files\HELIOS\analytics-core\logs\
```

**performance-ai:**

```
PRESERVE: C:\Program Files\HELIOS\performance-ai\data\training-data.db
PRESERVE: C:\Program Files\HELIOS\performance-ai\ml-models\
```

### Pre-Uninstall Data Export

```powershell
# Export analytics data before uninstall
cd C:\Users\ADMIN\helios-platform\components\analytics-core

.\uninstall.ps1 -ExportData `
    -ExportPath "C:\Data-Export\analytics" `
    -Format "Excel" `
    -IncludeMetadata

# Exports to: C:\Data-Export\analytics\data.xlsx

# Export vault keys
cd ..\vault-dynamics

.\uninstall.ps1 -ExportKeys `
    -ExportPath "C:\Backups\vault-keys"
```

---

## Uninstall Checklist

Before uninstalling a component:

```
[ ] Identify which data to preserve
[ ] Create backup if concerned about data loss
[ ] Notify users if component is in use
[ ] Stop dependent services/components
[ ] Export critical data (analytics, reports)
[ ] For vault: Backup encryption keys to safe location
[ ] Choose uninstall flags (-PreserveConfig, -PreserveData, etc.)
[ ] Execute uninstall
[ ] Verify removal: Check C:\Program Files\HELIOS\<component>
[ ] Verify services removed: Get-Service "HELIOS-*"
[ ] Clean registry if needed: Remove-Item HKLM:\SOFTWARE\HELIOS\<component>
[ ] Restart if needed for cleanup
```

---

## Troubleshooting Uninstall Issues

### Issue: Uninstall Fails - File in Use

```powershell
# Component still running
Get-Service "HELIOS-ai-dashboard" | Stop-Service -Force

# Kill any running processes
Get-Process | Where-Object {$_.Name -like "*dashboard*"} | Stop-Process -Force

# Try uninstall again
.\uninstall.ps1
```

### Issue: Registry Entries Remain

```powershell
# Manual registry cleanup
Remove-Item 'HKLM:\SOFTWARE\HELIOS\ai-dashboard' -Force -ErrorAction SilentlyContinue

# Check for remaining entries
Get-ItemProperty -Path 'HKLM:\SOFTWARE\HELIOS' -ErrorAction SilentlyContinue
```

### Issue: Data Files Won't Delete

```powershell
# Take ownership of files
takeown /F "C:\Program Files\HELIOS\ai-dashboard" /R /D Y

# Give permissions
icacls "C:\Program Files\HELIOS\ai-dashboard" /grant "%username%:F" /T

# Try uninstall again
.\uninstall.ps1 -CompleteCleanup -Force
```

### Issue: Can't Restore Backup

```powershell
# Verify backup exists
Test-Path "C:\Backups\dashboard-20240120"

# Check permissions on backup
Get-Acl "C:\Backups\dashboard-20240120"

# Try restore with administrator privileges
.\restore-from-backup.ps1 -BackupPath "C:\Backups\dashboard-20240120" -Force
```

---

## Reinstalling After Uninstall

### Reinstall with Preserved Configuration

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Configuration preserved if you used -PreserveConfig
.\install.ps1 -UseExistingConfig

# Settings automatically loaded from backup
```

### Reinstall from Scratch (New Configuration)

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Install fresh, ignoring any existing backups
.\install.ps1 -Fresh

# New configuration created
# Old configuration and data still in backup directory
```

### Restore Full State from Backup

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard

# Step 1: Install component fresh
.\install.ps1

# Step 2: Restore from backup
.\restore-from-backup.ps1 -BackupPath "C:\Backups\dashboard-20240120"

# Full state restored: config, data, logs, everything
```

---

## Best Practices for Uninstalling

1. **Always create backup for important components**

   ```powershell
   .\uninstall.ps1 -CreateBackup -BackupPath "C:\Backup-$(Get-Date -Format 'yyyy-MM-dd')"
   ```

2. **Preserve data even if uninstalling permanently**

   ```powershell
   .\uninstall.ps1 -PreserveAll
   # Later analysis or migration possible
   ```

3. **Stop services gracefully before uninstall**

   ```powershell
   Get-Service "HELIOS-*" | Stop-Service -Force
   ```

4. **Export critical data before -CompleteCleanup**

   ```powershell
   .\uninstall.ps1 -ExportData -ExportPath "C:\Final-Export"
   # Then safe to complete cleanup
   ```

5. **Test reinstall after uninstall in dev environment**

   ```powershell
   # Uninstall on dev first
   # Verify restore works
   # Then do on production
   ```

---

## See Also

- **COMPONENT_CATALOG.md** - Component information
- **README.md** - Installation methods
- **INDEPENDENT_INSTALLATION.md** - Standalone installation
