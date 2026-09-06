# Phase 1 File Architecture

This document shows exactly where every Phase 1 file, configuration, and security setting lives on your system.

---

## Directory Structure Overview

```
C:\
├── Users\
│   └── ADMIN\
│       ├── helios-platform\
│       │   └── phases\
│       │       └── 1-security\
│       │           ├── README.md
│       │           ├── PLAIN_ENGLISH_GUIDE.md
│       │           ├── FILE_ARCHITECTURE.md (this file)
│       │           ├── BEFORE_AND_AFTER.md
│       │           ├── SCRIPTS_INDEX.md
│       │           ├── TESTING_GUIDE.md
│       │           ├── scripts\
│       │           │   ├── 01-applocker-setup.ps1
│       │           │   ├── 02-firewall-hardening.ps1
│       │           │   ├── 03-vault-encryption-setup.ps1
│       │           │   ├── 04-quarantine-system-init.ps1
│       │           │   ├── 05-user-account-protection.ps1
│       │           │   ├── 06-threat-detection-config.ps1
│       │           │   └── utils\
│       │           │       ├── logging.ps1
│       │           │       ├── validation.ps1
│       │           │       └── rollback-helper.ps1
│       │           └── config\
│       │               ├── applocker-rules.xml
│       │               ├── firewall-rules.json
│       │               └── threat-definitions.xml
│       └── Vault\
│           ├── .encrypted
│           ├── Recovery-Key.txt
│           ├── Passwords\
│           ├── Certificates\
│           ├── Financial\
│           └── Quarantine\
│               ├── Active\
│               ├── Archive\
│               ├── Recovery\
│               └── Log.txt
└── Windows\
    ├── System32\
    │   ├── drivers\
    │   │   └── etc\
    │   │       └── hosts (AppLocker blocked domains)
    │   └── Microsoft\
    │       ├── Windows\
    │       │   ├── AppLocker\
    │       │   ├── Defender\
    │       │   ├── SrpV2\
    │       │   └── Firewall\
    │       └── Cryptography\
    │           └── RSA\
    └── Temp\
        └── (Phase 1 temporary files during setup)
```

---

## 1. AppLocker Configuration

### Primary Location

```
HKLM:\Software\Policies\Microsoft\Windows\SrpV2
```

### AppLocker Paths

| Item | Path | Owner | Readable |
|------|------|-------|----------|
| **Policy Storage** | `C:\ProgramData\AppLocker\` | SYSTEM | ❌ No (encrypted) |
| **Policy Cache** | `C:\Windows\System32\AppLocker\` | SYSTEM | ❌ No |
| **Whitelist Definition** | `C:\Users\ADMIN\helios-platform\phases\1-security\config\applocker-rules.xml` | ADMIN | ✅ Yes |
| **Blocked Programs Log** | `C:\Windows\System32\winevt\Logs\Application.evtx` | SYSTEM | ✅ Yes (Event Viewer) |
| **Audit Logs** | `C:\Windows\System32\winevt\Logs\Security.evtx` | SYSTEM | ✅ Yes (Admin only) |

### AppLocker Registry Keys

```
HKEY_LOCAL_MACHINE (HKLM)
│
├── Software\
│   ├── Policies\
│   │   └── Microsoft\
│   │       ├── Windows\
│   │       │   ├── SrpV2\
│   │       │   │   ├── AppIdExt (AppLocker enabled flag)
│   │       │   │   ├── EnforceReputationBasedTrustForExecutables
│   │       │   │   ├── Executable (EXE files rules)
│   │       │   │   │   ├── EnforcementMode (Enforce/Audit)
│   │       │   │   │   └── Rules\ (individual rules)
│   │       │   │   ├── Msi (MSI installer rules)
│   │       │   │   ├── Script (Script files rules)
│   │       │   │   └── Appx (UWP app rules)
│   │       │   └── DeviceGuard\
│   │       │       └── EnableVirtualizationBasedSecurity
│   │       └── AppLocker\
│   │           ├── Configuration\
│   │           └── EnforcedPolicies\
│   │
│   └── Microsoft\
│       ├── Windows\
│       │   ├── CurrentVersion\
│       │   │   └── Policies\
│       │   │       └── System\
│       │   │           ├── EnableLUA (User Account Control)
│       │   │           └── PromptOnSecureDesktop
│       │   │
│       │   └── AppLocker\
│       │       ├── PolicyVersion
│       │       ├── LastPolicyUpdate
│       │       └── ExecutionLog\
│       │           ├── BlockedExecutables
│       │           └── AllowedExecutables
│       │
│       └── Cryptography\
│           └── RNG\ (Random Number Generator for signing)
│
└── System\
    ├── CurrentControlSet\
    │   ├── Services\
    │   │   ├── AppLocker (service control)
    │   │   │   ├── Start (0=disabled, 4=manual)
    │   │   │   └── ImagePath
    │   │   │
    │   │   └── HealthAttestationWmiProvider
    │   │
    │   └── Control\
    │       ├── ServiceGroupOrder
    │       └── GroupOrderList
```

### AppLocker Rule Files

```
C:\Users\ADMIN\helios-platform\phases\1-security\config\applocker-rules.xml
├── <RuleCollection>
│   ├── <FilePublisherRule> (signed applications)
│   │   ├── <Name>Allow Windows System</Name>
│   │   ├── <Conditions>
│   │   │   └── <FilePublisherCondition Publisher="Microsoft" ProductName="Windows" />
│   │   └── <Action>Allow</Action>
│   │
│   ├── <FilePathRule> (specific paths)
│   │   ├── <Name>Allow C:\Program Files</Name>
│   │   ├── <Conditions>
│   │   │   └── <FilePathCondition Path="C:\Program Files\*" />
│   │   └── <Action>Allow</Action>
│   │
│   └── <FileHashRule> (by file hash)
│       ├── <Name>Allow Firefox.exe</Name>
│       ├── <Conditions>
│       │   └── <FileHashCondition FileHash="ABC123..." />
│       └── <Action>Allow</Action>
```

### AppLocker Event Logs

```
Windows Logs
├── Application
│   └── Source: AppLocker
│       ├── Event 8000: Rule evaluated
│       ├── Event 8001: Enforcement policy changed
│       └── Event 8005: AppLocker service started
│
└── Security
    └── Source: AppLocker
        ├── Event 4687: AppLocker rule applied
        ├── Event 4688: Process created
        └── Event 8004: AppLocker rule matched
```

---

## 2. Firewall Configuration

### Primary Location

```
HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy
```

### Firewall Paths

| Item | Path | Owner | Readable |
|------|------|-------|----------|
| **Rule Database** | `HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules` | SYSTEM | ❌ No (encrypted binary) |
| **Rule Backup** | `C:\Users\ADMIN\helios-platform\phases\1-security\config\firewall-rules.json` | ADMIN | ✅ Yes |
| **Firewall Logs** | `C:\Windows\System32\LogFiles\Firewall\` | SYSTEM | ✅ Yes (admin view) |
| **Network Statistics** | `C:\Windows\System32\wbem\Performance\` | SYSTEM | ✅ Yes |
| **Service Binary** | `C:\Windows\System32\svchost.exe` (SharedAccess) | SYSTEM | ❌ Protected |

### Firewall Registry Structure

```
HKEY_LOCAL_MACHINE (HKLM)
│
└── System\
    └── CurrentControlSet\
        └── Services\
            ├── SharedAccess\
            │   ├── Interfaces\ (NIC-specific settings)
            │   │   └── {InterfaceGUID}
            │   │       ├── Name (e.g., Ethernet)
            │   │       ├── Enabled
            │   │       └── FirewallEnabled
            │   │
            │   └── Parameters\
            │       ├── FirewallPolicy\
            │       │   ├── StandardProfile\
            │       │   │   ├── EnableFirewall (0=off, 1=on)
            │       │   │   ├── InboundPolicyDefault (0=allow, 1=block)
            │       │   │   ├── OutboundPolicyDefault (0=allow, 1=block)
            │       │   │   ├── LogDroppedPackets
            │       │   │   ├── LogSuccessfulConnections
            │       │   │   └── DisableNotifications
            │       │   │
            │       │   ├── PublicProfile\ (Wi-Fi networks)
            │       │   │   └── (same settings as StandardProfile)
            │       │   │
            │       │   └── DomainProfile\ (Active Directory domains)
            │       │       └── (same settings as StandardProfile)
            │       │
            │       └── FirewallRules\ ← MAIN RULES HERE
            │           ├── {GUID-1}=v2.30|Action=Block|Direction=Out|Protocol=tcp|RemotePort=3389|Name=Block RDP Out
            │           ├── {GUID-2}=v2.30|Action=Allow|Direction=In|Protocol=tcp|LocalPort=443|Name=Allow HTTPS In
            │           └── {GUID-3}=v2.30|Action=Block|Direction=In|Protocol=tcp|LocalPort=135|Name=Block RPC In
            │
            └── mpssvc (Windows Defender service)
                ├── Start (service start type)
                └── ObjectName (service account)

Software\
│
├── Policies\
│   └── Microsoft\
│       └── WindowsFirewall\
│           ├── DomainProfile\
│           ├── StandardProfile\
│           └── PublicProfile\
│
└── Microsoft\
    └── Windows\
        └── CurrentVersion\
            └── Internet Settings\
                └── ZoneMap\ (zone-based rules)
```

### Firewall Rules Backup Format

```
C:\Users\ADMIN\helios-platform\phases\1-security\config\firewall-rules.json
{
  "inbound_rules": {
    "allow_https": {
      "Direction": "In",
      "Action": "Allow",
      "Protocol": "tcp",
      "LocalPort": "443",
      "Name": "Allow HTTPS Inbound"
    },
    "block_smb": {
      "Direction": "In",
      "Action": "Block",
      "Protocol": "tcp",
      "LocalPort": "445",
      "Name": "Block SMB (Ransomware)"
    }
  },
  "outbound_rules": {
    "block_rpc": {
      "Direction": "Out",
      "Action": "Block",
      "Protocol": "tcp",
      "RemotePort": "135",
      "Name": "Block RPC Outbound"
    }
  }
}
```

### Firewall Log Location

```
C:\Windows\System32\LogFiles\Firewall\
├── pfirewall.log (verbose logging)
├── pfirewall-high.log (high alert threshold)
└── pfirewall-activity.csv (activity summary)

Log Format:
"action","direction","protocol","src-ip","dst-ip","src-port","dst-port","size","tcpflags","tcpsyn","tcpack","tcpwin","icmptype","icmpcode","info","path"
```

---

## 3. Vault Encryption

### Primary Location

```
C:\Users\ADMIN\Vault\
(Or C:\Vault\ for system-wide vault)
```

### Vault Directory Structure

```
C:\Users\ADMIN\Vault\
│
├── .encrypted (encryption metadata file)
│   ├── EncryptionMethod (BitLocker or VeraCrypt)
│   ├── EncryptedBy (username)
│   ├── EncryptionDate (timestamp)
│   └── RecoveryKeyHash (checksum of recovery key)
│
├── Recovery-Key.txt ⚠️ SAVE THIS SOMEWHERE SAFE!
│   └── Contains 48-digit recovery key for unlock
│
├── Passwords\
│   ├── personal-accounts.txt
│   ├── work-accounts.txt
│   └── api-keys.txt
│
├── Certificates\
│   ├── ssh-keys\
│   │   ├── id_rsa (private SSH key)
│   │   └── id_rsa.pub (public SSH key)
│   ├── ssl-certs\
│   │   ├── server.crt
│   │   ├── server.key
│   │   └── ca-bundle.crt
│   └── gpg-keys\
│       ├── private-key.gpg
│       └── public-key.gpg
│
├── Financial\
│   ├── banking-info.txt
│   ├── tax-records.zip
│   └── crypto-wallets.txt
│
├── Sensitive\
│   ├── health-records\
│   ├── legal-docs\
│   └── personal-data\
│
└── Quarantine\
    ├── Active\
    ├── Archive\
    ├── Recovery\
    └── Log.txt
```

### Vault Encryption Methods

#### BitLocker (Preferred if TPM available)

```
HKLM:\Software\Microsoft\Windows\CurrentVersion\Encryption
├── VaultEncryption\
│   ├── Method (BitLocker)
│   ├── MountPoint (C:\Users\ADMIN\Vault)
│   ├── TpmPresent (1 if TPM 2.0 available)
│   ├── ProtectionStatus (Protected/Unprotected)
│   ├── EncryptionPercentage (0-100)
│   ├── ConvertsionStatus
│   └── RecoveryKey (encrypted)

C:\Windows\System32\manage-bde.exe -status
├── Volume: C:\Users\ADMIN\Vault
├── Size: X GB
├── State: Encrypted
├── Protection Status: Protection On
├── Encryption Method: AES 128-bit or XTS-AES 128-bit
├── Percentage Encrypted: 100%
└── Encryption Key: TPM only or TPM + PIN
```

#### VeraCrypt (if BitLocker not available)

```
C:\Users\ADMIN\Vault\.veracrypt
├── Container file (encrypted volume)
├── Password hash (PBKDF2-SHA512)
├── Encryption algorithm (AES-256)
└── Header size (512 bytes or 131072 bytes)

HKLM:\Software\Classes\VeraCryptVolume
└── MountedVolumes\
    ├── C:\Users\ADMIN\Vault
    ├── MountedLetter (Z: or other)
    ├── SlotNumber
    └── EncryptionAlgorithm
```

### Vault Encryption File Indicators

```
File Properties in Explorer:
├── Attributes: Encrypted (shown in blue text on NTFS)
├── Advanced Attributes: "Encrypt contents to secure data" (checked)
├── Security: Permission restricted to SYSTEM and owner
└── Size: May show differently depending on encryption type
```

---

## 4. Quarantine System

### Primary Location

```
C:\Vault\Quarantine\
```

### Quarantine Directory Structure

```
C:\Vault\Quarantine\
│
├── Active\
│   ├── malware-001.exe.quarantine
│   │   ├── OriginalName: malware.exe
│   │   ├── DetectionTime: 2026-04-12 14:32:05
│   │   ├── ThreatLevel: High
│   │   └── Encrypted: AES-256
│   │
│   ├── suspicious-script-002.vbs.quarantine
│   └── infected-document-003.docx.quarantine
│
├── Archive\
│   ├── 2026-04-12\
│   │   ├── Old-Threat-A.exe.quarantine
│   │   └── Old-Threat-B.zip.quarantine
│   │
│   └── 2026-04-11\
│       └── Previous-Threat.exe.quarantine
│
├── Recovery\
│   ├── (empty until you restore)
│   └── (files queued for restoration here)
│
├── Log.txt
│   └── Detailed quarantine history and events
│
└── Metadata\
    ├── quarantine-index.db (SQLite database)
    ├── threat-definitions.xml
    └── quarantine-config.json
```

### Quarantine Registry Settings

```
HKLM:\Software\Microsoft\Windows Security
│
└── WindowsDefender\
    └── Quarantine\
        ├── QuarantinePath (C:\Vault\Quarantine\)
        ├── MaxQuarantineSize (default: 1 GB)
        ├── MaxQuarantineSizeBytes (1000000000)
        ├── DeleteQuarantineAfterDays (180)
        ├── EnableQuarantine (1 = enabled)
        ├── DisableScanOnRestore (0 = re-scan on restore)
        └── LastQuarantineCleanup (timestamp)

HKLM:\Software\Policies\Microsoft\Windows Defender
└── MalwareProtection\
    ├── QuarantinePath (C:\Vault\Quarantine\)
    ├── QuarantineAutoDelete (0 = manual, 1 = auto after 180 days)
    └── RemediationScheduleDay (day of week for cleanup)
```

### Quarantine Log Format

```
C:\Vault\Quarantine\Log.txt

Format:
[TIMESTAMP] | [SEVERITY] | [THREAT_NAME] | [FILE_PATH] | [DETECTION_METHOD] | [ACTION]

Examples:
[2026-04-12 14:32:05] | HIGH | Trojan.Win32.Generic | C:\Users\ADMIN\Downloads\setup.exe | Signature Match | QUARANTINED
[2026-04-12 15:18:22] | MEDIUM | PUA.Adware.Bundler | C:\Users\ADMIN\AppData\Local\Temp\installer.exe | Behavior Analysis | QUARANTINED
[2026-04-13 09:05:10] | LOW | PUA.PotentiallyUnwanted | C:\Users\ADMIN\Desktop\tool.exe | Heuristic | QUARANTINED
```

### Quarantine File Format

```
Quarantined File Structure:
├── File Header (256 bytes)
│   ├── Magic Number (0x51554152 = "QUAR")
│   ├── Version (1.0)
│   ├── Encryption Algorithm (AES-256)
│   └── Original Filename Hash
│
├── File Metadata (512 bytes)
│   ├── Original Path
│   ├── Detection Time
│   ├── Threat Level
│   ├── Detection Engine
│   └── CRC32 Checksum
│
└── Encrypted File Content
    └── Original file data (AES-256 encrypted)
```

---

## 5. User Account Protection

### Primary Location

```
HKLM:\SAM\SAM\Domains\Account\Users\
```

### User Accounts Registry

```
HKEY_LOCAL_MACHINE
│
├── SAM\
│   └── SAM\
│       └── Domains\
│           ├── Account\
│           │   ├── Users\ ← USER ACCOUNTS HERE
│           │   │   ├── 000001F4 (Administrator - RID 500)
│           │   │   ├── 000001F5 (ADMIN-Master - RID 501, our admin account)
│           │   │   ├── 000003ED (Standard-User - RID 1001)
│           │   │   └── 000003EE (Restricted-Guest - RID 1002)
│           │   │
│           │   ├── Groups\
│           │   │   ├── 000000220 (Administrators group)
│           │   │   ├── 000000221 (Users group)
│           │   │   ├── 000000222 (Guests group)
│           │   │   └── 000000223 (Power Users group)
│           │   │
│           │   └── Aliases\ (local groups)
│           │       ├── Administrators (members: ADMIN-Master)
│           │       ├── Power Users (members: Standard-User)
│           │       ├── Users (members: Standard-User, Restricted-Guest)
│           │       └── Guests (members: empty)
│           │
│           └── BuiltinDomain\
│               └── (default groups on Windows)
│
├── Software\
│   └── Microsoft\
│       ├── Windows NT\
│       │   ├── CurrentVersion\
│       │   │   └── ProfileList\
│       │   │       ├── S-1-5-21-...-500 (Administrator)
│       │   │       ├── S-1-5-21-...-1005 (ADMIN-Master profile)
│       │   │       ├── S-1-5-21-...-1001 (Standard-User profile)
│       │   │       └── S-1-5-21-...-1002 (Restricted-Guest profile)
│       │   │
│       │   └── WinLogon\ (login settings)
│       │       ├── DefaultDomainName
│       │       ├── DefaultUserName
│       │       └── Shell (explorer.exe or restricted shell)
│       │
│       └── Windows\
│           └── CurrentVersion\
│               └── Policies\
│                   ├── System\
│                   │   ├── EnableLUA (User Account Control 1=on)
│                   │   ├── PromptOnSecureDesktop (1=show UAC prompt)
│                   │   ├── ConsentPromptBehaviorAdmin (2=always prompt)
│                   │   └── ConsentPromptBehaviorUser (1=prompt for operations)
│                   │
│                   └── Accounts\
│                       ├── Administrator (0=disabled, 1=enabled)
│                       ├── Guest (0=disabled, 1=enabled)
│                       ├── PasswordExpirationWarning (14 days)
│                       └── MinimumPasswordLength (12 characters)
│
└── System\
    └── CurrentControlSet\
        ├── Control\
        │   ├── Lsa\ (security authority)
        │   │   ├── LmCompatibilityLevel (5=NTLM v2 only)
        │   │   ├── NoLMHash (1=don't store LM hash)
        │   │   ├── SCENoApplyLegacyAuditPolicy (0=use legacy)
        │   │   ├── RestrictAnonymousSam (1=restrict)
        │   │   └── EveryoneIncludesAnonymous (0=no anonymous)
        │   │
        │   └── Session Manager\
        │       ├── ProtectionMode (1=session 0 isolation)
        │       └── MemoryManagement\
        │           └── PoolTagTable
        │
        ├── Services\
        │   ├── TermService (Remote Desktop)
        │   │   └── Start (3=manual, 4=disabled)
        │   │
        │   └── (other services restricted per account tier)
        │
        └── SecurityProviders\
            └── SCHANNEL\
                └── (TLS/SSL settings per account)
```

### User Profile Locations

```
C:\Users\ADMIN-Master\
├── AppData\
│   ├── Roaming\ (admin config files)
│   └── Local\ (admin cache files)
├── Documents\
├── Desktop\
├── Downloads\
└── (permissions: ADMIN only)

C:\Users\Standard-User\
├── AppData\
│   ├── Roaming\ (user config)
│   └── Local\ (user cache)
├── Documents\
├── Desktop\
├── Downloads\
└── (permissions: POWER USERS can modify)

C:\Users\Restricted-Guest\
├── AppData\
│   ├── Roaming\ (restricted config)
│   └── Local\ (restricted cache)
├── Documents\
├── Desktop\
├── Downloads\
└── (permissions: USERS only, limited)
```

### Group Policy Settings Per Account

```
HKLM:\Software\Policies\Microsoft\Windows\
│
├── System\ (account restrictions)
│   ├── ConsentPromptBehaviorAdmin (2=always prompt for admin)
│   ├── ConsentPromptBehaviorUser (1=prompt for standard)
│   └── EnableSecureUIAPaths (1=secure UI for elevations)
│
├── AppCompat\ (compatibility mode restrictions)
│   ├── DisableCompatibilityMode (per account)
│   └── RestrictedCompatibilityMode
│
└── Credential UI\ (credential prompting)
    ├── EnumerateAdministrators (0=don't show admin accounts at login)
    └── CredUIBroker (1=use secure credential UI)
```

---

## 6. Threat Detection Configuration

### Primary Location

```
HKLM:\Software\Microsoft\Windows Defender
```

### Windows Defender Paths

```
C:\Program Files\Windows Defender\
├── MpCmdRun.exe (command-line scanning)
├── MpEngineRun.exe (scan engine)
├── MpClient.exe (client interface)
└── MpRun.exe (engine runner)

C:\ProgramData\Microsoft\Windows Defender\
├── Definition Updates\ (threat signatures)
│   ├── Default\ (latest definitions)
│   ├── Backup\ (backup definitions)
│   └── {timestamp}\
│       ├── mpavdlta.vdm (malware definitions)
│       ├── mpavdlts.vdm (spyware definitions)
│       ├── mpavdlte.vdm (exploit definitions)
│       └── mpasdlts.vdm (adware definitions)
│
├── Scans\ (scan results)
│   ├── History.txt (scan history)
│   └── DetailedScan\ (detailed results)
│       ├── ScanResults.xml
│       └── ScanLog.xml
│
├── QuickScan\ (quick scan cache)
├── FullScan\ (full scan cache)
└── Exclusions\ (excluded files/folders)
    ├── ExclusionPaths (registry)
    ├── ExclusionProcesses (registry)
    └── ExclusionExtensions (registry)
```

### Threat Detection Registry

```
HKEY_LOCAL_MACHINE
│
└── Software\
    ├── Microsoft\
    │   ├── Windows Defender\ ← MAIN SETTINGS
    │   │   ├── DisableRealtimeMonitoring (0=enabled, 1=disabled)
    │   │   ├── DisableBehaviorMonitoring (0=enabled)
    │   │   ├── DisableIOAVProtection (0=enabled)
    │   │   ├── DisableScriptScanning (0=enabled)
    │   │   ├── DisableBlockAtFirstSeen (0=block unknown, 1=scan first)
    │   │   │
    │   │   ├── Scan\ (scan configuration)
    │   │   │   ├── ScanType (1=quick, 2=full, 3=custom)
    │   │   │   ├── ScheduleDay (0-6 = Sun-Sat)
    │   │   │   ├── ScheduleTime (in minutes from midnight)
    │   │   │   ├── ScheduleQuickScanTime (in minutes)
    │   │   │   ├── CheckForSignaturesBeforeRunningScan
    │   │   │   ├── MissedScheduledScanCount
    │   │   │   ├── PurgeItemsAfterDelay
    │   │   │   ├── ScanOnlyIfIdleEnabled
    │   │   │   ├── ScanParameters
    │   │   │   ├── SignatureUpdateInterval
    │   │   │   ├── SignatureUpdateFileShare
    │   │   │   └── LowCpuPriority
    │   │   │
    │   │   ├── Remediation\ (threat actions)
    │   │   │   ├── HighThreatDefaultAction (1=quarantine, 2=remove, 3=allow)
    │   │   │   ├── ModerateThreatDefaultAction
    │   │   │   ├── LowThreatDefaultAction
    │   │   │   ├── SevereThreatDefaultAction
    │   │   │   └── UnknownThreatDefaultAction
    │   │   │
    │   │   ├── MalwareProtection\ (specific protections)
    │   │   │   ├── MalwareScanDays (days per week)
    │   │   │   ├── MalwareScansEnabled (1=enabled)
    │   │   │   ├── DisableArchiveScanning (0=scan archives)
    │   │   │   ├── DisableEmailScanning (0=scan email)
    │   │   │   ├── DisableRemovableDriveScanning (0=scan USB)
    │   │   │   └── RealTimeProtectionEnabled (1=enabled)
    │   │   │
    │   │   ├── NIS\ (Network Inspection Service)
    │   │   │   ├── DisableNIS (0=enabled)
    │   │   │   ├── NisEnabled (1=enabled)
    │   │   │   ├── Signatures\ (network signatures)
    │   │   │   └── IpsSignaturesUpdated (timestamp)
    │   │   │
    │   │   ├── SpynetReporting\ (MAPS submission)
    │   │   │   ├── SpyNetReportingLevel (1=basic, 2=advanced)
    │   │   │   ├── SubmitSamplesConsent (0=ask, 1=send, 2=never)
    │   │   │   └── SignatureUpdateNotificationInterval
    │   │   │
    │   │   └── ExclusionEngine\ (exclusion settings)
    │   │       ├── ExclusionPaths
    │   │       ├── ExclusionExtensions
    │   │       └── ExclusionProcesses
    │   │
    │   ├── Windows Defender\Signature Updates\
    │   │   ├── EngineVersion
    │   │   ├── SignatureVersion
    │   │   ├── SignatureVersionUpdate
    │   │   ├── SignatureUpdateInterval (hours)
    │   │   ├── SignatureUpdatePeriod
    │   │   ├── ForceSignatureUpdateNotificationInterval
    │   │   └── UpdateStatus (in progress, completed, failed)
    │   │
    │   └── Windows Defender\Exclusions\
    │       ├── Paths\ (excluded file paths)
    │       │   └── C:\Users\ADMIN\AppData\Roaming\Trusted-App (0=enabled)
    │       │
    │       ├── Extensions\ (excluded file types)
    │       │   └── .tmp (0=enabled)
    │       │
    │       └── Processes\ (excluded processes)
    │           └── explorer.exe (0=enabled)
    │
    └── Policies\
        └── Microsoft\
            └── Windows Defender\ (Group Policy overrides)
                ├── DisableAntiSpyware (0=enabled)
                ├── DisableAntiVirus (0=enabled)
                ├── DisableRealtimeMonitoring (0=enabled)
                └── ForceDefenderPassiveMode (0=not passive)
```

### Threat Detection Event Logs

```
Windows Logs
├── Application
│   └── Source: Windows Defender
│       ├── Event 1000: Antivirus scan started
│       ├── Event 1001: Antivirus scan completed
│       ├── Event 1002: Antivirus scan interrupted
│       ├── Event 1005: Antivirus real-time protection enabled
│       ├── Event 1006: Antivirus real-time protection disabled
│       ├── Event 1007: Antivirus real-time protection engine started
│       ├── Event 1116: Malware detected
│       └── Event 1117: Malware action taken
│
└── Security
    └── Source: Windows Defender ATP
        ├── Event 4688: Process creation
        ├── Event 4689: Process termination
        ├── Event 6005: Windows started
        └── Event 6006: Windows shut down
```

### Malwarebytes Configuration

```
C:\Program Files\Malwarebytes\
├── Malwarebytes Service.exe
├── mbam.exe (main executable)
├── mbamtray.exe (system tray)
└── definitions\
    ├── mb-rules.vdm
    ├── mb-signatures.vdm
    └── {timestamp}\
        ├── engine.dll
        └── (updated definitions)

C:\ProgramData\Malwarebytes\
├── MBamDB.json (scan database)
├── Detections\ (detected items)
└── Scans\ (scan history)

HKLM:\Software\Malwarebytes\
├── ScanEngine\
│   ├── Active (1=enabled)
│   ├── ScheduledScans\
│   │   ├── StartTime
│   │   ├── ScheduledDay
│   │   └── ScheduledFrequency
│   └── RealTime (1=enabled)
│
└── Settings\
    ├── AutomaticallyRemoveDetections
    ├── ShowNotifications
    └── UpdateFrequency
```

### Scheduled Scans Configuration

```
C:\Windows\System32\Tasks\Microsoft\Windows\Windows Defender\
├── Scheduled Scan
├── Scheduled Scan Fast
├── Scheduled Scan ASR
├── Refresh Managed State
├── Remediation
└── Windows Defender Cache Maintenance

Task Details:
├── Trigger: Daily 2:00 AM (configurable)
├── Action: MpCmdRun.exe -scan
├── ScanType: 1 (quick), 2 (full), or 3 (custom)
├── Priority: Background
├── IfNotIdleRestart: 1 (restart if idle)
└── StorageFolder: C:\ProgramData\Microsoft\Windows Defender\Scans\
```

### Hosts File (Blocked Domains)

```
C:\Windows\System32\drivers\etc\hosts

# Threat Detection blocked domains
127.0.0.1 malware-tracking.net
127.0.0.1 phishing-server.com
127.0.0.1 botnet-c2.ru
127.0.0.1 ransomware-payment.xyz
```

---

## Summary Table

| Component | Primary Path | Registry | Config File |
|-----------|---|---|---|
| **AppLocker** | `C:\ProgramData\AppLocker\` | `HKLM:\Software\Policies\Microsoft\Windows\SrpV2` | `applocker-rules.xml` |
| **Firewall** | `C:\Windows\System32\LogFiles\Firewall\` | `HKLM:\System\CurrentControlSet\Services\SharedAccess` | `firewall-rules.json` |
| **Vault** | `C:\Users\ADMIN\Vault\` | `HKLM:\Software\Microsoft\Windows\CurrentVersion\Encryption` | `.encrypted` metadata |
| **Quarantine** | `C:\Vault\Quarantine\` | `HKLM:\Software\Microsoft\Windows Security\WindowsDefender` | `Log.txt` |
| **User Accounts** | `C:\Users\{Username}\` | `HKLM:\SAM\SAM\Domains\Account` | Group Policy |
| **Threat Detection** | `C:\ProgramData\Microsoft\Windows Defender\` | `HKLM:\Software\Microsoft\Windows Defender` | `Definition Updates\` |

---

**Last Updated**: April 12, 2026  
**Version**: 1.0  
**Maintained By**: HELIOS Platform Team
