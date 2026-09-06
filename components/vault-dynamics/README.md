# Vault Dynamics Component

Enterprise-grade encryption and key management system for the HELIOS Platform.

---

## Overview

Vault Dynamics provides AES-256-GCM encryption with secure key management. Encrypt files, database fields, or custom data with automatic key rotation and optional hardware security module support.

**Key Facts:**

- **Phase:** 1 (can be borrowed to other phases)
- **Standalone:** ✅ Yes - Fully independent
- **Dependencies:** .NET Framework 4.6.1+, Windows CNG (built-in)
- **Version:** 1.5.2
- **Size:** 89 MB
- **Installation Time:** 2-3 minutes

---

## What It Does

### Core Features

1. **File Encryption**
   - Encrypt/decrypt individual files
   - Batch operations
   - Preserves file attributes
   - Progress tracking

2. **Data Encryption**
   - Encrypt strings (database fields, credentials)
   - Encrypt structured data (JSON, XML)
   - In-memory encryption
   - Stream-based encryption

3. **Secure Key Management**
   - Master key protection
   - Key storage (local or HSM)
   - Key rotation policies
   - Key hierarchy support

4. **Audit & Logging**
   - All operations logged
   - Failed decryption attempts
   - Key access tracking
   - Compliance reporting

5. **Recovery Features**
   - Backup encryption keys
   - Restore from backup
   - Recovery key system
   - Data recovery procedures

---

## System Requirements

### Minimum

- **OS:** Windows Server 2016+ or Windows 8.1+
- **.NET Framework:** 4.6.1+
- **RAM:** 1 GB
- **Disk:** 150 MB available
- **Crypto:** Windows CNG (built-in)

### Recommended

- **OS:** Windows Server 2019+
- **.NET Framework:** 4.8+
- **RAM:** 2+ GB
- **Disk:** 500 MB available
- **HSM:** (Optional) Hardware Security Module

### Hardware Security Module (Optional)

Supported HSMs:

- Thales Luna HSM
- Yubico HSM
- PKCS#11 compatible devices

---

## Installation Procedure

### Quick Install

```powershell
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics
.\install.ps1
```

### With Master Password

```powershell
.\install.ps1 -MasterPassword "YourComplexPassword123!"
# Master password required for all encryption operations
```

### With TPM (Windows 10+)

```powershell
.\install.ps1 -UseTPM
# Protects master key with TPM 2.0
```

### With Hardware Security Module

```powershell
.\install.ps1 -UseHSM `
    -HSMProvider "Thales Luna" `
    -HSMSlot 1 `
    -HSMPin "1234"
```

### Silent Installation

```powershell
.\install.ps1 -Silent -MasterPassword "YourPassword123!"
# Installs without prompts
```

---

## Configuration

**Config File:** `C:\Program Files\HELIOS\vault-dynamics\config.json`

```json
{
  "vault": {
    "masterPasswordHash": "bcrypt_hash_here",
    "requireMasterPassword": true,
    "masterPasswordTimeout": 300,
    "keyRotationEnabled": true,
    "rotationIntervalDays": 90,
    "backupPath": "C:\\Backups\\vault-keys",
    "recoveryKeyGenerated": true
  },

  "encryption": {
    "algorithm": "AES-256-GCM",
    "keySize": 256,
    "tagSize": 16,
    "saltSize": 16,
    "iterationCount": 100000
  },

  "storage": {
    "type": "filesystem",
    "path": "C:\\Program Files\\HELIOS\\vault-dynamics\\keys",
    "hsmEnabled": false,
    "hsmProvider": null,
    "tpmEnabled": false,
    "encryptionAtRest": true
  },

  "audit": {
    "enabled": true,
    "logPath": "C:\\Program Files\\HELIOS\\vault-dynamics\\logs",
    "logLevel": "Information",
    "trackDecryption": true,
    "trackFailedAttempts": true,
    "retentionDays": 365,
    "alertOnFailure": true
  }
}
```

### Common Configuration Changes

**Disable Master Password Requirement:**

```json
{
  "vault": {
    "requireMasterPassword": false
  }
}
```

**Change Key Rotation Schedule:**

```json
{
  "vault": {
    "keyRotationEnabled": true,
    "rotationIntervalDays": 30
  }
}
```

**Enable HSM:**

```json
{
  "storage": {
    "hsmEnabled": true,
    "hsmProvider": "Thales Luna"
  }
}
```

---

## Usage Examples

### Encrypt a File

```powershell
# Load the vault
$vault = New-Object HeliosPlatform.VaultDynamics.VaultClient
$vault.Initialize("your-master-password")

# Encrypt a file
$result = $vault.EncryptFile("C:\sensitive-data\document.pdf")

# Result:
# $result.Success = $true
# $result.EncryptedFile = "C:\sensitive-data\document.pdf.encrypted"
# $result.KeyId = "key-uuid-12345"
```

### Decrypt a File

```powershell
$vault.DecryptFile(
    "C:\sensitive-data\document.pdf.encrypted",
    "C:\decrypted\document.pdf"
)

# File is now decrypted to specified location
```

### Encrypt a String (Database Credential)

```powershell
$connectionString = "Server=localhost;User=admin;Password=secret123"

$encrypted = $vault.EncryptString($connectionString)

# Store encrypted in config
# $encrypted looks like: "AES256:dvkL8k9...encrypted_data..."

# Later, decrypt for use
$decrypted = $vault.DecryptString($encrypted)
# $decrypted = "Server=localhost;User=admin;Password=secret123"
```

### Encrypt JSON Data

```powershell
$sensitiveData = @{
    ApiKey = "sk-1234567890"
    ApiSecret = "secret-key-here"
    AccountId = "12345"
} | ConvertTo-Json

$encrypted = $vault.EncryptString($sensitiveData)

# Later, decrypt and parse
$json = $vault.DecryptString($encrypted)
$decrypted = $json | ConvertFrom-Json
```

### List All Encryption Keys

```powershell
$keys = $vault.GetAllKeyMetadata()

foreach ($key in $keys) {
    Write-Host "Key ID: $($key.Id)"
    Write-Host "  Created: $($key.CreatedDate)"
    Write-Host "  Rotated: $($key.LastRotatedDate)"
    Write-Host "  Algorithm: $($key.Algorithm)"
    Write-Host "  Status: $($key.Status)"
}
```

### Rotate Encryption Keys

```powershell
# Manual rotation
$result = $vault.RotateKeys()

if ($result.Success) {
    Write-Host "Keys rotated successfully"
    Write-Host "Old key archived"
    Write-Host "New key active"
} else {
    Write-Host "Rotation failed: $($result.ErrorMessage)"
}
```

### Create Backup

```powershell
$backupPath = "C:\Backups\vault-backup-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').bak"

$result = $vault.CreateBackup($backupPath)

if ($result.Success) {
    Write-Host "Backup created: $backupPath"
} else {
    Write-Host "Backup failed: $($result.ErrorMessage)"
}
```

### Restore from Backup

```powershell
$result = $vault.RestoreBackup("C:\Backups\vault-backup-2024-01-15-120000.bak")

if ($result.Success) {
    Write-Host "Keys restored"
    Write-Host "Restarting service..."
} else {
    Write-Host "Restore failed: $($result.ErrorMessage)"
}
```

---

## Encryption Methods

### Method 1: PowerShell API

Most flexible, programmatic control:

```powershell
$vault = New-Object HeliosPlatform.VaultDynamics.VaultClient
$vault.Initialize("password")
$vault.EncryptFile("file.txt")
```

### Method 2: Command-Line Tool

Quick encryption from scripts:

```powershell
"C:\Program Files\HELIOS\vault-dynamics\bin\vault.exe" `
    encrypt `
    --password "mypassword" `
    --file "C:\data\document.pdf"
```

### Method 3: Windows Explorer Context Menu

Right-click files (if enabled):

```
Right-click file → Vault Dynamics → Encrypt
```

---

## Security Best Practices

### Master Password

```
✅ Do:
- Use strong password (12+ characters, mixed case, numbers, symbols)
- Store securely (password manager, not in code)
- Change periodically
- Rotate through secure channel only

❌ Don't:
- Store in code or config files
- Use simple passwords
- Share master password
- Write down password unsecured
```

### Key Management

```
✅ Do:
- Enable automatic key rotation (every 90 days recommended)
- Backup keys regularly
- Test restore procedures
- Monitor key access logs

❌ Don't:
- Manually export keys unless necessary
- Disable key rotation
- Allow unlimited key access
```

### File Encryption

```
✅ Do:
- Encrypt sensitive files at rest
- Use for: PII data, credentials, tokens
- Backup encrypted files with keys

❌ Don't:
- Encrypt frequently accessed files (slows down I/O)
- Lose backup of encrypted keys
- Share encryption keys
```

---

## Troubleshooting

### Master Password Issues

**Error:** "Master password required but not provided"

```powershell
# Set master password
cd C:\Program Files\HELIOS\vault-dynamics

.\set-master-password.ps1
# Follow prompts to set password
```

**Error:** "Invalid master password"

```powershell
# Reset master password (WARNING: Keys become inaccessible)
.\reset-master-password.ps1 -Force

# Restore from backup if available
$vault.RestoreBackup("C:\Backups\vault-backup.bak")
```

### Key Rotation Failed

```powershell
# Check for errors
Get-Content "C:\Program Files\HELIOS\vault-dynamics\logs\vault.log" | Tail -50

# Ensure vault is running
Get-Service "HELIOS-Vault" | Select-Object Status

# Retry rotation
$vault.RotateKeys()
```

### Backup/Restore Issues

```powershell
# Verify backup exists and is accessible
Test-Path "C:\Backups\vault-backup.bak"

# Check disk space
Get-PSDrive C | Select-Object Used, Free

# If full, free up space and retry backup
```

### Decryption Fails

```powershell
# Verify key exists
$keys = $vault.GetAllKeyMetadata()
$keys | Where-Object {$_.Id -eq "your-key-id"}

# If missing, restore from backup
$vault.RestoreBackup("C:\Backups\vault-backup.bak")

# Retry decryption
$vault.DecryptFile("file.encrypted", "file.decrypted")
```

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\vault-dynamics\

Application Files:
├── bin\
│   ├── vault.exe (main executable)
│   ├── vault.dll (core library)
│   └── crypto\
│       └── (cryptography libraries)

Keys:
├── keys\
│   ├── master-key.encrypted
│   ├── key-store.db
│   ├── key-metadata.json
│   └── backups\

Configuration:
├── config.json

Logs:
├── logs\
│   ├── vault.log
│   ├── errors.log
│   └── audit.log

Backups:
├── backups\
│   └── (manual backups saved here)

Certificates (if using HSM):
├── certificates\
│   └── hsm-cert.pem
```

---

## Backup Procedures

### Schedule Regular Backups

```powershell
# Create PowerShell scheduled task

$action = New-ScheduledTaskAction -Execute `
    "C:\Program Files\HELIOS\vault-dynamics\bin\vault.exe" `
    -Argument "backup --output C:\Backups\vault-backup-`$(Get-Date -Format 'yyyy-MM-dd').bak"

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "Vault-Daily-Backup" -Description "Daily vault key backup"
```

### Manual Backup

```powershell
$vault = New-Object HeliosPlatform.VaultDynamics.VaultClient
$vault.Initialize("password")

$backupPath = "C:\Backups\vault-backup-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').bak"
$vault.CreateBackup($backupPath)

Write-Host "Backup created: $backupPath"
```

### Backup Encryption

Backups are encrypted with the current master password. Test restoration:

```powershell
# Verify backup
$vault.TestBackupIntegrity("C:\Backups\vault-backup.bak")

# Should return: $true
```

---

## Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics

# Preserve keys (critical!)
.\uninstall.ps1 -PreserveKeys -BackupPath "C:\Vault-Backup"

# Or remove everything (WARNING: Can't decrypt after!)
.\uninstall.ps1 -CompleteCleanup
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.5.2 | 2024-01-10 | HSM improvements, performance fixes |
| 1.5.0 | 2023-12-01 | TPM support added, key rotation improved |
| 1.4.0 | 2023-10-15 | Backup system enhanced |
| 1.3.0 | 2023-08-01 | Initial stable release |

---

## Support

- **Configuration:** Review config.json options above
- **Errors:** Check logs in C:\Program Files\HELIOS\vault-dynamics\logs\
- **Backup Recovery:** Use RestoreBackup procedures
- **Standalone Usage:** See INDEPENDENT_INSTALLATION.md
