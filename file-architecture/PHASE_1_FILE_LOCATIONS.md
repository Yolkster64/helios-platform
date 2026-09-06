# Phase 1: Security - File Locations

Phase 1 deploys comprehensive security controls including AppLocker rules, firewall configurations, vault systems, security logs, and quarantine functionality.

## Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| AppLocker Rules | HKLM:\Software\Policies\Microsoft\Windows\SrpV2\ | Application execution policies |
| Firewall Config | C:\Windows\System32\drivers\etc\ | Network security rules |
| Vault System | C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\ | Encrypted user vault |
| Security Logs | C:\Windows\System32\winevt\Logs\ | Event logs and audit trail |
| Quarantine | C:\ProgramData\HELIOS\Security\Quarantine\ | Isolated suspicious files |
| Security Policies | HKLM:\Software\Policies\Microsoft\Windows\ | Group policy settings |
| Threat Analysis | C:\ProgramData\HELIOS\Security\Analysis\ | Threat detection results |
| Security Logs (HELIOS) | C:\ProgramData\HELIOS\Logs\Phase1.log | Phase 1 diagnostic logs |

---

## AppLocker Rules (Registry)

**Location**: `HKLM:\Software\Policies\Microsoft\Windows\SrpV2\`

**Purpose**: Define executable application policies via AppLocker

**Registry Structure Created**:

```
HKLM:\Software\Policies\Microsoft\Windows\SrpV2\
├── Exe\                                # Executable rules
│   ├── EnforcementMode                 # Value: 2 (Enforce)
│   ├── {GUID-1}\
│   │   ├── Name                        # "Allow Windows System Executables"
│   │   ├── Description
│   │   ├── RuleType                    # "Path"
│   │   ├── Path                        # "%WINDIR%\System32\*"
│   │   ├── UserOrGroupSid              # "S-1-1-0" (Everyone)
│   │   └── Action                      # "Allow"
│   ├── {GUID-2}\
│   │   ├── Name                        # "Allow Program Files"
│   │   ├── Path                        # "C:\Program Files\*"
│   │   ├── Action                      # "Allow"
│   │   └── Exceptions                  # NULL or none
│   ├── {GUID-3}\
│   │   ├── Name                        # "Deny Untrusted Software"
│   │   ├── Path                        # "C:\Users\*\Downloads\*"
│   │   └── Action                      # "Deny"
│   └── {GUID-4}\
│       ├── Name                        # "Allow HELIOS Components"
│       ├── Path                        # "C:\Program Files\HELIOS\*"
│       └── Action                      # "Allow"
│
├── Dll\                                # DLL rules
│   ├── EnforcementMode                 # Value: 1 (Audit)
│   ├── {GUID-1}\
│   │   ├── Name                        # "Allow System DLLs"
│   │   ├── Path                        # "%WINDIR%\System32\*.dll"
│   │   └── Action                      # "Allow"
│   └── {GUID-2}\
│       ├── Name                        # "Audit Suspicious DLLs"
│       ├── Path                        # "C:\Users\*\AppData\*\*.dll"
│       └── Action                      # "Audit"
│
├── Msi\                                # Windows Installer rules
│   ├── EnforcementMode                 # Value: 0 (Not Enforced)
│   └── {GUID-1}\
│       ├── Name                        # "Allow All MSI"
│       └── Action                      # "Allow"
│
├── Script\                             # Script rules
│   ├── EnforcementMode                 # Value: 1 (Audit)
│   └── {GUID-1}\
│       ├── Name                        # "Audit PowerShell Scripts"
│       ├── Path                        # "%WINDIR%\System32\WindowsPowerShell\*"
│       └── Action                      # "Audit"
│
└── ApplockerPolicy\                    # Policy summary
    ├── LastApplied                     # Timestamp
    ├── RuleCount                       # Total rule count
    └── ConfigurationSource             # "HELIOS Phase 1"
```

**Examples**:

```
HKLM:\Software\Policies\Microsoft\Windows\SrpV2\Exe\{GUID-1}\Name = "Allow Windows System Executables"
HKLM:\Software\Policies\Microsoft\Windows\SrpV2\Exe\EnforcementMode = 2
HKLM:\Software\Policies\Microsoft\Windows\SrpV2\Dll\EnforcementMode = 1
```

**Access**: Admin/SYSTEM required

**Persistence**: Permanent until deleted

---

## Firewall Configuration Files

**Location**: `C:\Windows\System32\drivers\etc\`

**Purpose**: Network security rules and host file configuration

**Files Created/Modified**:

```
C:\Windows\System32\drivers\etc\
├── hosts                               # Host file (modified)
│   # Original file backed up to:
│   # C:\ProgramData\HELIOS\Security\Backups\hosts.backup
│   # Added entries:
│   # 127.0.0.1 malicious-domain.com   # Block malicious sites
│   # 127.0.0.1 ad-server.net
│   # 127.0.0.1 tracker.analytics.com
│
├── services                            # Network services (read-only reference)
├── protocol                            # Protocol definitions (read-only reference)
└── networks                            # Network definitions (read-only reference)
```

**Firewall Registry Rules**:

```
HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\
├── StandardProfile\
│   ├── AuthorizedApplications\
│   │   ├── "C:\Program Files\HELIOS\Dashboard\Dashboard.exe" = "1"
│   │   ├── "C:\Program Files\HELIOS\Dashboard\Dashboard.exe:*:Enabled:HELIOS Dashboard"
│   │   └── Other authorized apps...
│   ├── GloballyOpenPorts\
│   │   ├── "443:TCP" = "1" (HTTPS for AI communication)
│   │   ├── "8443:TCP" = "1" (Dashboard port)
│   │   └── "53:UDP" = "1" (DNS)
│   ├── InboundAllowedPrograms\
│   ├── OutboundAllowedPrograms\
│   ├── DefaultInboundAction = 1 (Block)
│   ├── DefaultOutboundAction = 0 (Allow)
│   └── DisableNotifications = 0
│
├── DomainProfile\                      # Domain network rules
│   └── (Same structure as StandardProfile)
│
└── PublicProfile\                      # Public network rules
    └── (More restrictive than StandardProfile)
```

**Example Host File Additions**:

```
# Added by HELIOS Phase 1 Security
127.0.0.1 malicious-domain.com
127.0.0.1 ad-server.net
127.0.0.1 tracker.analytics.com
127.0.0.1 suspicious-ip.xyz
::1 malicious-domain.com              # IPv6 equivalent
```

**Access**: Admin required to modify; everyone can read

**Size**: hosts file typically <10 KB (grows with blocked domains)

---

## Vault System (User)

**Location**: `C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\`

**Purpose**: Encrypted user vault for sensitive data storage

**Files Created**:

```
C:\Users\[USERNAME]\AppData\Local\HELIOS\Vault\
├── Vault.db                            # Encrypted vault database
│   # Binary encrypted SQLite database
│   # Size: 10-50 MB per vault
│   # Tables: secrets, credentials, certificates, keys
│
├── Vault.config                        # Vault configuration
│   # XML or JSON format:
│   # - Encryption type (AES-256)
│   # - Master key derivation method (PBKDF2)
│   # - Auto-lock timeout (15 minutes default)
│   # - Backup schedule (daily)
│
├── certificates\
│   ├── user-cert.pfx                   # User SSL certificate (encrypted)
│   ├── ca-chain.crt                    # Certificate authority chain
│   └── root-ca.crt                     # Root CA certificate
│
├── keys\
│   ├── encryption-key.bin              # Master encryption key (encrypted)
│   └── backup-keys\                    # Key backups
│       └── encryption-key-2024-01-15.bin.backup
│
├── cache\
│   ├── recent-credentials.cache        # Decrypted credentials cache (secured)
│   └── session-token.cache             # Session token cache
│
├── logs\
│   ├── Vault.log                       # Vault access logs
│   └── Vault-Audit.log                 # Audit trail
│
└── backups\
    ├── Vault-2024-01-15.backup         # Daily backup (encrypted)
    ├── Vault-2024-01-14.backup
    └── Vault-2024-01-13.backup
```

**Examples**:

```
C:\Users\Administrator\AppData\Local\HELIOS\Vault\Vault.db
C:\Users\jsmith\AppData\Local\HELIOS\Vault\Vault.config
C:\Users\Administrator\AppData\Local\HELIOS\Vault\certificates\user-cert.pfx
```

**Access**: User has full access; other users cannot access

**Size**: 20-50 MB per vault (database + backups)

**Key Vault Features**:

- Master password protected
- AES-256 encryption
- Auto-lock after 15 minutes inactivity
- Daily backup with encryption
- Access audit logging

**Vault Contents** (Vault.db structure):

```
VAULT.DB Tables:
├── secrets
│   ├── id INTEGER PRIMARY KEY
│   ├── name TEXT
│   ├── value BLOB (encrypted)
│   ├── type TEXT
│   ├── created_date DATETIME
│   └── modified_date DATETIME
│
├── credentials
│   ├── id INTEGER PRIMARY KEY
│   ├── username TEXT
│   ├── password BLOB (encrypted)
│   ├── service_name TEXT
│   ├── url TEXT
│   └── notes BLOB (encrypted)
│
├── certificates
│   ├── id INTEGER PRIMARY KEY
│   ├── subject TEXT
│   ├── issuer TEXT
│   ├── thumbprint TEXT
│   ├── certificate BLOB (PEM encoded)
│   ├── private_key BLOB (encrypted)
│   ├── expiration_date DATETIME
│   └── ca_chain BLOB
│
└── encryption_keys
    ├── id INTEGER PRIMARY KEY
    ├── key_id TEXT
    ├── key_data BLOB (encrypted with master key)
    ├── algorithm TEXT
    └── created_date DATETIME
```

---

## Security Event Logs

**Location**: `C:\Windows\System32\winevt\Logs\`

**Purpose**: Windows event logs and HELIOS security audit trail

**Files Created/Modified**:

```
C:\Windows\System32\winevt\Logs\
├── Security.evtx                       # Security event log (modified/enhanced)
│   # Events added by Phase 1:
│   # - AppLocker events (Event ID 8001-8004)
│   # - Account logon/logoff
│   # - Privilege escalation attempts
│   # - Policy changes
│
├── System.evtx                         # System event log (modified)
│   # Events added by Phase 1:
│   # - Service start/stop
│   # - Driver load events
│   # - System errors
│
├── Application.evtx                    # Application event log
│   # Events added by Phase 1:
│   # - HELIOS application events
│
└── HELIOS\
    ├── Operational.evtx                # HELIOS operational log (new channel)
    ├── Analytic.evtx                   # HELIOS analytic log (new channel)
    ├── Debug.evtx                      # HELIOS debug log (new channel)
    └── Security-Audit.evtx             # HELIOS security audit log (new channel)
```

**Registry Event Log Configuration**:

```
HKLM:\System\CurrentControlSet\Services\EventLog\
├── Security\
│   ├── File = %SystemRoot%\System32\config\Security
│   ├── MaxSize = 536870912 (500 MB)    # Increased by Phase 1
│   ├── Retention = 604800 (7 days)     # Increased by Phase 1
│   └── AutoBackupLogFiles = 1          # Enable backup
│
├── System\
│   ├── File = %SystemRoot%\System32\config\System
│   └── MaxSize = 268435456 (250 MB)
│
├── Application\
│   ├── File = %SystemRoot%\System32\config\Application
│   └── MaxSize = 268435456 (250 MB)
│
└── HELIOS\
    ├── File = %SystemRoot%\System32\winevt\Logs\HELIOS.evtx
    ├── MaxSize = 104857600 (100 MB)
    ├── Retention = 2592000 (30 days)
    └── AutoBackupLogFiles = 1
```

**Access**: Admin to write/modify; authenticated users can read

**Size**: Security log typically 100-500 MB; expandable to 2-5 GB

---

## Quarantine Directory

**Location**: `C:\ProgramData\HELIOS\Security\Quarantine\`

**Purpose**: Isolated storage for suspicious or blocked files

**Files Created**:

```
C:\ProgramData\HELIOS\Security\Quarantine\
├── Quarantine.db                       # Quarantine database (SQLite)
│   # Tables:
│   # - quarantined_files
│   # - quarantine_history
│   # - quarantine_metadata
│
├── Active\
│   ├── File_2024-01-15_001.qtn        # Quarantined file (encrypted)
│   ├── File_2024-01-15_002.qtn
│   ├── File_2024-01-15_003.qtn
│   └── ... (one per quarantined item)
│
├── Archive\
│   ├── 2024-01\                        # Organized by month
│   │   ├── File_2024-01-01_001.qtn
│   │   └── File_2024-01-01_002.qtn
│   ├── 2024-02\
│   └── 2024-03\
│
├── Logs\
│   ├── Quarantine-Operations.log       # Quarantine actions
│   ├── Quarantine-Restore.log          # Restoration attempts
│   └── Quarantine-Analysis.log         # Analysis results
│
└── Metadata\
    ├── file-metadata.json              # Metadata for quarantined files
    ├── hash-database.db                # File hash database
    └── threat-analysis.csv             # Threat assessment results
```

**Quarantine.db Structure**:

```
Table: quarantined_files
├── id INTEGER PRIMARY KEY
├── original_path TEXT
├── quarantine_path TEXT
├── file_hash TEXT (SHA-256)
├── file_size INTEGER
├── threat_level TEXT (critical/high/medium/low/none)
├── threat_description TEXT
├── quarantine_date DATETIME
├── detection_source TEXT
└── user_id INTEGER

Table: quarantine_history
├── id INTEGER PRIMARY KEY
├── file_id INTEGER
├── action TEXT (quarantine/restore/delete/analyze)
├── action_date DATETIME
├── action_user TEXT
├── result TEXT
└── notes TEXT
```

**Example Quarantine Entries**:

```
Original: C:\Users\jsmith\Downloads\suspicious.exe
Quarantine: C:\ProgramData\HELIOS\Security\Quarantine\Active\File_2024-01-15_001.qtn
Threat Level: HIGH
Detection: AppLocker Rule Violation
Date: 2024-01-15 14:23:45
```

**Access**: Admin required to access; read-only for end users (via admin approval)

**Size**: 1-10 MB per quarantined file (grows over time)

---

## Security Policy Files

**Location**: `C:\ProgramData\HELIOS\Security\Policies\`

**Purpose**: Local security policies and configurations

**Files Created**:

```
C:\ProgramData\HELIOS\Security\Policies\
├── AppLocker-Rules.xml                 # AppLocker policy export
├── Firewall-Rules.xml                  # Firewall rules export
├── UAC-Settings.cfg                    # User Account Control configuration
├── Password-Policy.cfg                 # Password complexity requirements
├── Account-Lockout.cfg                 # Account lockout policy
├── Audit-Policy.cfg                    # Audit policy settings
├── Credential-Guard.cfg                # Windows Defender Credential Guard
├── Device-Guard.cfg                    # Windows Defender Device Guard
└── WDAC-Policy.bin                     # Windows Defender Application Control (binary)
```

**Examples**:

```
C:\ProgramData\HELIOS\Security\Policies\AppLocker-Rules.xml
C:\ProgramData\HELIOS\Security\Policies\Password-Policy.cfg
```

**Access**: Admin/SYSTEM required

**Size**: ~50-200 KB total

---

## Threat Analysis Results

**Location**: `C:\ProgramData\HELIOS\Security\Analysis\`

**Purpose**: Threat detection and analysis results

**Files Created**:

```
C:\ProgramData\HELIOS\Security\Analysis\
├── Threat-Database.db                  # Threat signatures and definitions
├── Analysis-Results.json               # Latest analysis results
├── Threat-Scan-2024-01-15.report       # Daily threat report
├── Anomaly-Detection-2024-01-15.csv    # Anomalies detected
├── Risk-Assessment-2024-01-15.json     # Risk scoring
├── Vulnerability-Scan-2024-01-15.xml   # Vulnerability assessment
└── Reports\
    ├── Weekly-Summary.pdf              # Weekly threat summary
    ├── Monthly-Trend.pdf               # Monthly threat trends
    └── Archive\
        ├── 2024-01\
        └── 2024-02\
```

**Examples**:

```
C:\ProgramData\HELIOS\Security\Analysis\Threat-Database.db
C:\ProgramData\HELIOS\Security\Analysis\Threat-Scan-2024-01-15.report
```

**Access**: Admin required; regular users can request access to sanitized reports

**Size**: Database ~50-200 MB; reports ~5-10 MB each

---

## Phase 1 Logs

**Location**: `C:\ProgramData\HELIOS\Logs\Phase1.log`

**Purpose**: Phase 1 deployment and operations diagnostic logs

**Files Created**:

```
C:\ProgramData\HELIOS\Logs\
├── Phase1.log                          # Main Phase 1 log
├── Phase1-Details.log                  # Verbose Phase 1 log
├── Phase1-Errors.log                   # Phase 1 errors only
├── Phase1-Warnings.log                 # Phase 1 warnings
├── Security-Deployment.log             # Security system deployment
├── AppLocker-Config.log                # AppLocker configuration
├── Firewall-Config.log                 # Firewall configuration
└── Vault-Operations.log                # Vault system operations
```

**Access**: Admin to write; everyone can read

**Size**: 50-100 MB with verbose logging

**Log Examples**:

```
[2024-01-15 10:30:15.234] [INFO] Phase 1 Security Deployment Started
[2024-01-15 10:30:16.456] [INFO] Configuring AppLocker rules...
[2024-01-15 10:30:22.891] [INFO] AppLocker rules applied: 15 rules
[2024-01-15 10:30:25.123] [INFO] Firewall configuration in progress...
[2024-01-15 10:30:30.567] [INFO] Firewall rules applied: 8 rules
[2024-01-15 10:30:35.789] [INFO] Creating vault system...
[2024-01-15 10:30:40.234] [INFO] Vault created at: C:\Users\Administrator\AppData\Local\HELIOS\Vault\
[2024-01-15 10:30:45.567] [INFO] Phase 1 Security Deployment Completed
```

---

## Registry Security Settings

**Location**: `HKLM:\Software\Policies\Microsoft\Windows\`

**Purpose**: Security-related Windows policies

**Keys Modified/Created**:

```
HKLM:\Software\Policies\Microsoft\Windows\
├── Defender\Real-Time Protection\
│   ├── DisableBehaviorMonitoring = 0 (enabled)
│   ├── DisableOnAccessProtection = 0 (enabled)
│   ├── DisableScanOnRealtimeEnable = 0 (enabled)
│   └── DisableRealtimeMonitoring = 0 (enabled)
│
├── WindowsUpdate\
│   ├── DisableWindowsUpdateAccess = 0 (allow updates)
│   ├── AutoUpdateNotificationLevel = 3
│   └── UpdateNotificationLevel = 3
│
├── System\Audit\
│   ├── ProcessCreation = 1 (enabled)
│   ├── Kerberos = 1 (enabled)
│   └── ObjectAccess = 1 (enabled)
│
└── Biometrics\
    ├── Facial\
    │   ├── EnhancedAntiSpoofing = 1 (enabled)
    │   └── UseEnhancedAntiSpoofingIfAvailable = 1
    └── Fingerprint\
        └── EnrollmentModality = 1
```

---

## Backup Locations

**Location**: `C:\ProgramData\HELIOS\Security\Backups\`

**Purpose**: Backups of files modified by Phase 1

**Files Created**:

```
C:\ProgramData\HELIOS\Security\Backups\
├── hosts.backup                        # Original hosts file
├── hosts.backup.2024-01-15-10-30     # Timestamped backup
├── Registry-Before-Phase1.hiv          # Registry export (pre-Phase 1)
├── Firewall-Rules-Before.xml           # Original firewall rules
├── AppLocker-Before.xml                # Original AppLocker (if existed)
└── SecurityPolicy-Before.xml           # Original security policy
```

**Access**: Admin required; read-only recommended

**Size**: ~50-100 MB total

---

## Complete Directory Tree

```
C:\ProgramData\HELIOS\
├── Security\                           # Phase 1 root
│   ├── Quarantine\                     # Quarantine system
│   │   ├── Active\
│   │   ├── Archive\
│   │   │   ├── 2024-01\
│   │   │   ├── 2024-02\
│   │   │   └── 2024-03\
│   │   ├── Logs\
│   │   ├── Metadata\
│   │   └── Quarantine.db
│   ├── Policies\                       # Security policies
│   │   ├── AppLocker-Rules.xml
│   │   ├── Firewall-Rules.xml
│   │   └── (other policy files)
│   ├── Analysis\                       # Threat analysis
│   │   ├── Threat-Database.db
│   │   ├── Analysis-Results.json
│   │   ├── Reports\
│   │   └── (threat reports)
│   ├── Backups\                        # Pre-Phase 1 backups
│   │   └── (backup files)
│   └── (other security files)
│
└── Logs\
    ├── Phase1.log
    ├── Phase1-Details.log
    └── (other Phase 1 logs)

C:\Users\[USERNAME]\AppData\Local\HELIOS\
├── Vault\                              # Vault system (per user)
│   ├── Vault.db
│   ├── Vault.config
│   ├── certificates\
│   ├── keys\
│   ├── cache\
│   ├── logs\
│   └── backups\

C:\Windows\System32\drivers\etc\
├── hosts                               # Modified by Phase 1

C:\Windows\System32\winevt\Logs\
├── Security.evtx                       # Enhanced by Phase 1
├── System.evtx
├── Application.evtx
└── HELIOS\
    ├── Operational.evtx
    ├── Analytic.evtx
    └── Debug.evtx

HKLM:\Software\Policies\Microsoft\Windows\
└── SrpV2\                              # AppLocker policies
    ├── Exe\
    ├── Dll\
    ├── Msi\
    └── Script\
```

---

## File Size Summary

| Component | Size |
|-----------|------|
| Vault.db (per user) | 20-50 MB |
| Vault certificates & keys | 5-10 MB |
| Vault backups (3-5 files) | 20-100 MB |
| Security.evtx (log) | 100-500 MB |
| Quarantine database | 10-50 MB |
| Quarantine active files | 5-100+ MB |
| Threat analysis database | 50-200 MB |
| Policy files | <1 MB |
| All Phase 1 files (system) | 200-1,000 MB |
| All Phase 1 files (per user) | 50-200 MB |

---

## Next Steps

After Phase 1 completes:

- Security controls are active
- Vault systems operational
- Event logging enhanced
- AppLocker rules enforced

See **PHASE_2_FILE_LOCATIONS.md** for next phase file placement.
