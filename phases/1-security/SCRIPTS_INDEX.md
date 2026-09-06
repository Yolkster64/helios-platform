# Phase 1 Scripts Index

Complete list of all Phase 1 security scripts with descriptions, dependencies, and quick reference.

---

## Scripts Overview

```
Phase 1 Security Scripts
├── 01-applocker-setup.ps1              Application whitelisting
├── 02-firewall-hardening.ps1           Network security hardening
├── 03-vault-encryption-setup.ps1       Sensitive data encryption
├── 04-quarantine-system-init.ps1       Threat isolation system
├── 05-user-account-protection.ps1      Account tier creation
├── 06-threat-detection-config.ps1      Antivirus/malware setup
└── utils/                              Support utilities
    ├── logging.ps1                     Logging framework
    ├── validation.ps1                  Input validation
    └── rollback-helper.ps1             Undo script
```

---

## 1. AppLocker Setup

| Property | Value |
|----------|-------|
| **Filename** | `01-applocker-setup.ps1` |
| **Purpose** | Enables AppLocker and defines whitelist of allowed programs |
| **Runtime** | ~15-20 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ⚠️ Recommended |
| **Prerequisites** | Enterprise Services installed |
| **Dependencies** | utils/logging.ps1, utils/validation.ps1 |
| **Rollback Script** | `01-applocker-rollback.ps1` |

### What It Does

- Creates AppLocker policy rules
- Whitelists system programs (Windows, Office, etc.)
- Sets enforcement mode (audit or enforce)
- Generates rule report

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\01-applocker-setup.ps1 -EnforcementMode Audit
```

### Parameters

- `-EnforcementMode` : Audit (test mode) or Enforce (block mode)
- `-WhitelistPath` : Path to custom whitelist XML (optional)
- `-GenerateReport` : Save rule report to file (default: true)

### Output

- `applocker-rules.xml` - Generated rule file
- `applocker-report.txt` - Audit log of what was whitelisted
- Console output showing status

### Common Issues

- "AppLocker not available" = Enterprise Services required
- "Rule already exists" = Safe, will skip duplicates
- Program blocked unexpectedly = Add exception via `01-applocker-add-exception.ps1`

---

## 2. Firewall Hardening

| Property | Value |
|----------|-------|
| **Filename** | `02-firewall-hardening.ps1` |
| **Purpose** | Hardens Windows Firewall to block unauthorized traffic |
| **Runtime** | ~10-15 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ⚠️ Recommended |
| **Prerequisites** | Windows Firewall service running |
| **Dependencies** | utils/logging.ps1 |
| **Rollback Script** | `02-firewall-rollback.ps1` |

### What It Does

- Blocks dangerous inbound ports (3389, 445, 135, etc.)
- Restricts outbound to high-risk destinations
- Configures inbound/outbound policies to "block by default"
- Enables logging

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\02-firewall-hardening.ps1 -Profile StandardProfile
```

### Parameters

- `-Profile` : StandardProfile, DomainProfile, or PublicProfile
- `-EnableLogging` : Enable detailed firewall logging (default: true)
- `-BackupRules` : Save current rules before applying (default: true)

### Output

- `firewall-rules-backup.json` - Backup of original rules
- `firewall-rules-applied.json` - New rules applied
- Console output showing rules added

### Common Issues

- "Network is unavailable after running" = May have blocked too much
- Run rollback: `.\02-firewall-rollback.ps1`

---

## 3. Vault Encryption Setup

| Property | Value |
|----------|-------|
| **Filename** | `03-vault-encryption-setup.ps1` |
| **Purpose** | Creates and encrypts Vault for sensitive data storage |
| **Runtime** | ~20-30 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ⚠️ Possible (BitLocker) |
| **Prerequisites** | TPM 2.0 (for BitLocker) or VeraCrypt installed |
| **Dependencies** | utils/logging.ps1, utils/validation.ps1 |
| **Rollback Script** | `03-vault-decryption.ps1` |

### What It Does

- Creates `C:\Users\ADMIN\Vault\` directory
- Encrypts with BitLocker (if TPM available) or VeraCrypt
- Creates recovery key (⚠️ SAVE THIS!)
- Sets up subdirectories (Passwords, Certificates, Financial, etc.)
- Generates recovery key backup

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\03-vault-encryption-setup.ps1 -EncryptionMethod BitLocker
```

### Parameters

- `-EncryptionMethod` : BitLocker or VeraCrypt
- `-VaultPath` : Custom vault location (default: C:\Users\ADMIN\Vault)
- `-Password` : VeraCrypt password (if not BitLocker)
- `-SaveRecoveryKey` : Save recovery key (default: true)

### Output

- `C:\Users\ADMIN\Vault\` directory created
- `Recovery-Key.txt` - **SAVE IN SAFE PLACE!**
- `vault-setup-report.txt` - Setup details
- Console output with encryption status

### Important Notes

⚠️ **SAVE YOUR RECOVERY KEY!**

- Write it down and store it physically
- Store in safe deposit box
- Without it, encrypted data is unrecoverable

### Common Issues

- "BitLocker requires TPM" = Use VeraCrypt instead
- "Recovery key missing" = Can't recover if forgotten

---

## 4. Quarantine System Init

| Property | Value |
|----------|-------|
| **Filename** | `04-quarantine-system-init.ps1` |
| **Purpose** | Creates isolated quarantine directory for detected threats |
| **Runtime** | ~5-10 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ❌ No |
| **Prerequisites** | C:\Vault directory exists (from script 3) |
| **Dependencies** | utils/logging.ps1 |
| **Rollback Script** | `04-quarantine-cleanup.ps1` |

### What It Does

- Creates `C:\Vault\Quarantine\` directory structure
- Configures antivirus to use this directory
- Sets up archive system (daily backups)
- Initializes quarantine database
- Configures auto-cleanup policies

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\04-quarantine-system-init.ps1 -QuarantineSize 5GB
```

### Parameters

- `-QuarantineSize` : 1GB, 5GB, or 10GB (default: 1GB)
- `-AutoCleanupDays` : Days before auto-delete (default: 180)
- `-EnableArchive` : Keep daily archives (default: true)

### Output

- `C:\Vault\Quarantine\` directory structure created
- `quarantine-config.json` - Configuration file
- `quarantine-setup-report.txt` - Setup details
- Console output with status

### Common Issues

- "C:\Vault does not exist" = Run script 3 first
- "Quarantine full" = Increase size or enable auto-cleanup

---

## 5. User Account Protection

| Property | Value |
|----------|-------|
| **Filename** | `05-user-account-protection.ps1` |
| **Purpose** | Creates three-tier user account structure with different privilege levels |
| **Runtime** | ~15-20 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ⚠️ Recommended |
| **Prerequisites** | None |
| **Dependencies** | utils/logging.ps1, utils/validation.ps1 |
| **Rollback Script** | `05-user-account-cleanup.ps1` |

### What It Does

- Creates ADMIN-Master account (admin only)
- Creates Standard-User account (everyday use)
- Creates Restricted-Guest account (limited use)
- Sets permissions per account tier
- Configures UAC prompts appropriately
- Applies Group Policy restrictions

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\05-user-account-protection.ps1 -CreateAllAccounts
```

### Parameters

- `-CreateAllAccounts` : Create all three tiers (default: true)
- `-AdminPassword` : Password for ADMIN-Master (prompted if not provided)
- `-StandardPassword` : Password for Standard-User (prompted)
- `-RestrictedPassword` : Password for Restricted-Guest (prompted)
- `-ApplyGroupPolicy` : Apply restrictions (default: true)

### Output

- Three new user accounts created
- `account-setup-report.txt` - Account details
- Group Policy applied
- Console output with instructions

### Important Notes

- **Save passwords** for each account in Vault
- ADMIN-Master is for maintenance only
- Use Standard-User for everyday work
- Use Restricted-Guest for untrusted activities

### Common Issues

- "Account already exists" = Safe, script will skip
- "Group Policy failed to apply" = May require additional restart

---

## 6. Threat Detection Configuration

| Property | Value |
|----------|-------|
| **Filename** | `06-threat-detection-config.ps1` |
| **Purpose** | Enables Windows Defender, installs Malwarebytes, configures scanning |
| **Runtime** | ~20-30 minutes |
| **Requires Admin** | ✅ Yes |
| **Requires Restart** | ⚠️ Recommended (for Malwarebytes) |
| **Prerequisites** | Internet connection for downloads |
| **Dependencies** | utils/logging.ps1 |
| **Rollback Script** | `06-threat-detection-disable.ps1` |

### What It Does

- Enables Windows Defender with aggressive settings
- Installs Malwarebytes (if not present)
- Updates threat definitions
- Configures scheduled scans
- Sets real-time protection to maximum
- Enables advanced threat protection features

### Usage

```powershell
cd C:\Users\ADMIN\helios-platform\phases\1-security\scripts
.\06-threat-detection-config.ps1 -ScanFrequency Daily -ScanType Full
```

### Parameters

- `-ScanFrequency` : Daily, Weekly, Monthly (default: Daily)
- `-ScanType` : Quick, Full, Custom (default: Quick)
- `-ScanTime` : Hour of day for scan (default: 2)
- `-InstallMalwarebytes` : Install Malwarebytes (default: true)
- `-EnableBehavioralDetection` : Enable behavior-based detection (default: true)

### Output

- Windows Defender enabled and configured
- Malwarebytes installed (if available)
- `threat-detection-config.json` - Configuration file
- `threat-detection-report.txt` - Setup details
- Console output with status

### Common Issues

- "Malwarebytes download failed" = Check internet connection
- "Antivirus conflict" = May need to disable other antiviruses
- "Scan takes very long" = Switch to Quick scan instead of Full

---

## Utility Scripts

### logging.ps1

| Property | Value |
|----------|-------|
| **Purpose** | Provides logging framework for all scripts |
| **Functions** | Write-Log, Start-Log, End-Log, Log-Status |
| **Used By** | All Phase 1 scripts |
| **Standalone** | No (imported by other scripts) |

### validation.ps1

| Property | Value |
|----------|-------|
| **Purpose** | Validates inputs and system requirements |
| **Functions** | Test-AdminPrivileges, Test-PathExists, Validate-Input |
| **Used By** | All Phase 1 scripts |
| **Standalone** | No (imported by other scripts) |

### rollback-helper.ps1

| Property | Value |
|----------|-------|
| **Purpose** | Centralized rollback functionality |
| **Functions** | Undo-AppLocker, Undo-Firewall, Undo-Vault, etc. |
| **Used By** | Individual rollback scripts |
| **Standalone** | Yes (can be called manually) |

---

## Execution Order

### Recommended Order

```
1. Read PLAIN_ENGLISH_GUIDE.md
2. Read BEFORE_AND_AFTER.md
3. Review TESTING_GUIDE.md
4. Execute in order:
   ├── 01-applocker-setup.ps1
   ├── 02-firewall-hardening.ps1
   ├── 03-vault-encryption-setup.ps1
   ├── 04-quarantine-system-init.ps1
   ├── 05-user-account-protection.ps1
   └── 06-threat-detection-config.ps1
5. Run tests from TESTING_GUIDE.md
```

### Why This Order

- **AppLocker First**: Needs to be active before threats detected
- **Firewall Second**: Network protection before data encryption
- **Vault Third**: Data must be secured before threats isolated
- **Quarantine Fourth**: Depends on Vault being set up
- **User Accounts Fifth**: Affects all scripts running after
- **Threat Detection Last**: Most important once other layers active

---

## Dependencies Graph

```
05-user-account-protection.ps1
    ├── utils/logging.ps1
    └── utils/validation.ps1

01-applocker-setup.ps1
    ├── utils/logging.ps1
    ├── utils/validation.ps1
    └── (may require restart)

02-firewall-hardening.ps1
    ├── utils/logging.ps1
    └── (backs up current rules)

03-vault-encryption-setup.ps1
    ├── utils/logging.ps1
    ├── utils/validation.ps1
    ├── BitLocker service (if TPM available)
    └── VeraCrypt (alternative)

04-quarantine-system-init.ps1
    ├── utils/logging.ps1
    └── Requires: 03-vault-encryption-setup.ps1

06-threat-detection-config.ps1
    ├── utils/logging.ps1
    ├── Windows Defender service
    ├── Malwarebytes (optional download)
    └── Internet connection (for updates)
```

---

## Quick Reference Table

| Script | Time | Admin | Restart | Difficulty |
|--------|------|-------|---------|-----------|
| 01-applocker-setup.ps1 | 15-20 min | ✅ | ⚠️ | Medium |
| 02-firewall-hardening.ps1 | 10-15 min | ✅ | ⚠️ | Medium |
| 03-vault-encryption-setup.ps1 | 20-30 min | ✅ | ⚠️ | Medium |
| 04-quarantine-system-init.ps1 | 5-10 min | ✅ | ❌ | Easy |
| 05-user-account-protection.ps1 | 15-20 min | ✅ | ⚠️ | Medium |
| 06-threat-detection-config.ps1 | 20-30 min | ✅ | ⚠️ | Easy |

---

## Running Scripts Safely

### Before Running Any Script

```powershell
# 1. Review the script
notepad .\01-applocker-setup.ps1

# 2. Check current state
Get-ExecutionPolicy
Get-AppLockerPolicy -Effective

# 3. Enable script execution (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 4. Run with error output
$ErrorActionPreference = "Continue"
```

### Running Scripts

```powershell
# Option 1: Interactive (recommended)
.\01-applocker-setup.ps1

# Option 2: With output logging
.\01-applocker-setup.ps1 | Tee-Object -FilePath "script-output.txt"

# Option 3: With error handling
try {
    .\01-applocker-setup.ps1
} catch {
    Write-Error "Script failed: $_"
    .\01-applocker-rollback.ps1
}
```

### After Running Each Script

```powershell
# Check logs
Get-Content "Phase1-Setup.log"

# Verify changes
Get-AppLockerPolicy -Effective
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*Block*"}
Get-BitLockerVolume -MountPoint C:\Users\ADMIN\Vault

# Test functionality
Test-AppLockerConfiguration
Test-FirewallRules
```

---

## Rollback Procedures

### Individual Rollbacks

```powershell
# Undo AppLocker
.\01-applocker-rollback.ps1

# Undo Firewall
.\02-firewall-rollback.ps1

# Undo Vault Encryption
.\03-vault-decryption.ps1

# Clean Quarantine
.\04-quarantine-cleanup.ps1

# Remove User Accounts
.\05-user-account-cleanup.ps1

# Disable Threat Detection
.\06-threat-detection-disable.ps1
```

### Full Rollback (if needed)

```powershell
# Run in reverse order
.\06-threat-detection-disable.ps1
.\05-user-account-cleanup.ps1
.\04-quarantine-cleanup.ps1
.\03-vault-decryption.ps1
.\02-firewall-rollback.ps1
.\01-applocker-rollback.ps1
```

---

## Troubleshooting

### Script Won't Run

```powershell
# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
Write-Host "Is Admin: $isAdmin"

# Check script execution policy
Get-ExecutionPolicy

# Set if needed
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

### Script Errors

```powershell
# Enable verbose output
$VerbosePreference = "Continue"
.\script-name.ps1 -Verbose

# Check error details
$Error[0] | Format-List -Property *

# Check system logs
Get-WinEvent -LogName "Application" -MaxEvents 100 | Sort-Object TimeCreated
```

---

**Last Updated**: April 12, 2026  
**Version**: 1.0  
**Maintained By**: HELIOS Platform Team
