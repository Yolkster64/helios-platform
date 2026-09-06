# Registry Changes by Phase

Complete reference of all registry modifications made by HELIOS across all phases.

## Phase 0: Foundation - Registry Changes

### Installation Status Keys

**Location**: `HKLM:\Software\HELIOS\`

```
Foundation\ (REG_SZ/DWORD values)
├── InstallDate = "2024-01-15 08:30:15"                    # Installation timestamp
├── Version = "4.1.0"                                       # HELIOS version
├── SystemDrive = "C:"                                      # System drive letter
├── BaselineLocation = "C:\ProgramData\HELIOS\Foundation\Baselines"
├── DataDirectory = "C:\ProgramData\HELIOS"
├── InstalledFeatures = "Foundation,Security,Optimization,Capability"
├── PrerequisitesMet = 1                                    # Boolean (1=TRUE)
└── RollbackCapable = 1                                     # Can rollback Phase 0

Paths\ (REG_SZ values - paths to each component)
├── Foundation = "C:\ProgramData\HELIOS\Foundation"
├── Security = "C:\ProgramData\HELIOS\Security"
├── Optimization = "C:\ProgramData\HELIOS\Optimization"
├── Capability = "C:\ProgramData\HELIOS\Capability"
└── Database = "C:\ProgramData\HELIOS\Database"

Status\ (DWORD values - Boolean phase status)
├── Phase0-Complete = 1                                     # Phase 0 done
├── Phase1-Pending = 1                                      # Phase 1 ready
├── Phase2-Pending = 1                                      # Phase 2 ready
├── Phase3-Pending = 1                                      # Phase 3 ready
└── LastUpdated = FILETIME_VALUE                            # Last status update
```

**Registry Type Details**:

- REG_SZ: String values
- DWORD: 32-bit numbers (1=TRUE, 0=FALSE)
- FILETIME_VALUE: Windows timestamp

---

## Phase 1: Security - Registry Changes

### AppLocker Configuration

**Location**: `HKLM:\Software\Policies\Microsoft\Windows\SrpV2\`

```
Exe\ (Executable rules)
├── EnforcementMode = 2                                     # 2=Enforce, 1=Audit, 0=Off
├── {UUID1}\
│   ├── Name = "Allow Windows System Executables"           # Rule name
│   ├── Description = "Allows Windows system executables to run"
│   ├── RuleType = "Path"                                   # Or "Hash", "Publisher"
│   ├── RuleSid = "{GUID}"                                  # Unique rule ID
│   ├── Path = "%WINDIR%\System32\*"                        # Path pattern
│   ├── UserOrGroupSid = "S-1-1-0"                          # Everyone
│   └── Action = "Allow"                                    # Or "Deny"
├── {UUID2}\
│   ├── Name = "Allow Program Files"
│   ├── Path = "C:\Program Files\*"
│   └── Action = "Allow"
├── {UUID3}\
│   ├── Name = "Allow HELIOS"
│   ├── Path = "C:\Program Files\HELIOS\*"
│   └── Action = "Allow"
└── {UUID4}\
    ├── Name = "Deny Untrusted Downloads"
    ├── Path = "C:\Users\*\Downloads\*"
    ├── Action = "Deny"
    └── Exceptions = NULL

Dll\ (DLL rules)
├── EnforcementMode = 1                                     # 1=Audit only
├── {UUID1}\
│   ├── Name = "Allow System DLLs"
│   ├── Path = "%WINDIR%\System32\*.dll"
│   └── Action = "Allow"
└── {UUID2}\
    ├── Name = "Audit Suspicious DLLs"
    ├── Path = "C:\Users\*\AppData\*\*.dll"
    └── Action = "Audit"

Msi\ (Windows Installer rules)
├── EnforcementMode = 0                                     # Not enforced
└── {UUID1}\
    ├── Name = "Allow All MSI"
    └── Action = "Allow"

Script\ (Script rules)
├── EnforcementMode = 1                                     # Audit only
└── {UUID1}\
    ├── Name = "Audit PowerShell"
    ├── Path = "%WINDIR%\System32\WindowsPowerShell\*"
    └── Action = "Audit"

ApplockerPolicy\ (Policy summary)
├── LastApplied = FILETIME_VALUE
├── RuleCount = 15                                          # Total rule count
└── ConfigurationSource = "HELIOS Phase 1"
```

### Firewall Rules

**Location**: `HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\`

```
StandardProfile\
├── AuthorizedApplications\ (REG_SZ values)
│   ├── "C:\Program Files\HELIOS\Dashboard\Dashboard.exe" = "C:\Program Files\HELIOS\Dashboard\Dashboard.exe:*:Enabled:HELIOS Dashboard"
│   ├── "C:\Program Files\Office\Excel.exe" = "..."
│   └── (other authorized apps)
│
├── GloballyOpenPorts\ (REG_BINARY values)
│   ├── "443:TCP" = 0x01                                    # HTTPS open
│   ├── "8443:TCP" = 0x01                                   # Dashboard port
│   ├── "53:UDP" = 0x01                                     # DNS
│   └── (other ports)
│
├── DefaultInboundAction = 1                                # 1=Block by default
├── DefaultOutboundAction = 0                               # 0=Allow by default
├── DisableNotifications = 0                                # 0=Show notifications
├── LogDroppedPackets = 1                                   # 1=Log drops
└── LogSuccessfulConnections = 0                            # 0=Don't log success

DomainProfile\
└── (Same settings as StandardProfile for domain networks)

PublicProfile\
└── (More restrictive than StandardProfile)
```

### Security Policies

**Location**: `HKLM:\Software\Policies\Microsoft\Windows\`

```
Defender\Real-Time Protection\
├── DisableBehaviorMonitoring = 0                          # 0=Enabled
├── DisableOnAccessProtection = 0
├── DisableScanOnRealtimeEnable = 0
├── DisableRealtimeMonitoring = 0
├── DisableIOAVProtection = 0
├── RealtimeScanning = 1                                   # 1=Enabled
└── PUAProtection = 1                                      # Potentially unwanted apps

WindowsUpdate\
├── DisableWindowsUpdateAccess = 0                         # 0=Allow updates
├── AutoUpdateNotificationLevel = 3                        # 3=Auto install
└── UpdateNotificationLevel = 3

System\Audit\
├── ProcessCreation = 1                                    # Audit process creation
├── Kerberos = 1                                           # Audit Kerberos
└── ObjectAccess = 1                                       # Audit object access

Biometrics\Facial\
├── EnhancedAntiSpoofing = 1                               # 1=Enabled
└── UseEnhancedAntiSpoofingIfAvailable = 1

Biometrics\Fingerprint\
└── EnrollmentModality = 1                                 # Allow enrollment

Internet Connection Sharing\
└── EnableSharedAccessOnNextConnection = 0                 # 0=Disabled
```

### Phase 1 Status

**Location**: `HKLM:\Software\HELIOS\Status\`

```
Phase1-Complete = 1                                         # Phase 1 done
Phase1-Started = FILETIME_VALUE                            # When started
Phase1-Completed = FILETIME_VALUE                          # When completed
Phase1-RulesApplied = 15                                   # AppLocker rules
Phase1-FirewallRules = 8                                   # Firewall rules
Phase1-VaultCreated = 1                                    # Vault initialized
Phase1-ErrorCount = 0                                      # No errors
```

---

## Phase 2: Optimization - Registry Changes

### Service Configuration

**Location**: `HKLM:\SYSTEM\CurrentControlSet\Services\`

```
HELIOSMonitor\
├── DisplayName = "HELIOS System Monitor"
├── Description = "Monitors system health and threats"
├── ImagePath = "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"
├── Type = 16                                              # 16=Own process
├── Start = 2                                              # 2=Auto-start
├── ErrorControl = 1                                       # 1=Log, continue
├── ObjectName = "LocalSystem"                             # Runs as SYSTEM
├── Parameters\
│   ├── EnableDebugLogging = 0
│   ├── MonitorInterval = 300                              # 5 minutes
│   └── QuarantineCheckInterval = 600                      # 10 minutes
└── Security\ (Permissions, not shown in detail)

HELIOSOptimizer\
├── DisplayName = "HELIOS System Optimizer"
├── ImagePath = "C:\Program Files\HELIOS\Optimizer\HELIOSOptimizer.exe"
├── Type = 16
├── Start = 2
├── ObjectName = "LocalSystem"
└── Parameters\
    ├── CleanupInterval = 86400                            # 24 hours
    ├── CacheCleanupEnabled = 1
    ├── TempFileCleanup = 1
    └── PreserveDays = 30

HELIOSVaultMonitor\
├── DisplayName = "HELIOS Vault Monitor"
├── ImagePath = "C:\Program Files\HELIOS\Vault\VaultMonitor.exe"
├── Start = 2
└── Parameters\
    ├── MonitorInterval = 300
    └── AutoLockTimeout = 900                              # 15 minutes

HELIOSAnalyzer\
├── DisplayName = "HELIOS Analysis Engine"
├── ImagePath = "C:\Program Files\HELIOS\Analyzer\HELIOSAnalyzer.exe"
├── Start = 2
└── Parameters\
    ├── AnalysisInterval = 3600                            # 1 hour
    └── MaxConcurrentAnalysis = 4

(Services Optimized by HELIOS)
SearchIndexer\
├── Start = 4                                              # 4=Disabled
└── DelayedAutoStart = 0

DiagTrack\ (Diagnostic Tracking)
├── Start = 4                                              # 4=Disabled
└── (Registry path varies by OS)
```

### Startup Items (Registry)

**Location**: `HKLM:\Software\Microsoft\Windows\CurrentVersion\`

```
Run\ (System-wide startup)
├── HELIOSMonitor = "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"
├── HELIOSVaultMonitor = "C:\Program Files\HELIOS\Vault\VaultMonitor.exe -tray"
├── HELIOSAnalyzer = "C:\Program Files\HELIOS\Analyzer\HELIOSAnalyzer.exe -background"
└── (User can also add to HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\)

RunOnce\ (One-time startup)
├── HELIOSFirstRunSetup = "C:\Program Files\HELIOS\Setup\FirstRun.exe"
└── HELIOSWelcomeTour = "C:\Program Files\HELIOS\Docs\WelcomeWizard.exe"

RunServices\ (Services-like startup)
└── (May contain tray applications)
```

### Performance Tuning

**Location**: `HKLM:\SYSTEM\CurrentControlSet\Control\`

```
ProcessorEventLog\
├── EnableEventLog = 1                                     # Enable logging

FileCache\
├── MaximumWorkingSetBytes = 536870912                     # 512 MB limit

Session Manager\
├── DisableMMPageWriteOrdering = 0                         # Normal I/O
└── ProtectedMode = 1                                      # Enable DEP

Power Schemes\
├── ActivePowerScheme = UUID                               # Active power plan
└── (Defined in PowerProfile subdirectories)
```

### Phase 2 Status

**Location**: `HKLM:\Software\HELIOS\Status\`

```
Phase2-Complete = 1
Phase2-Started = FILETIME_VALUE
Phase2-Completed = FILETIME_VALUE
Phase2-ServicesConfigured = 5
Phase2-StartupItemsCreated = 3
Phase2-OptimizationProfileApplied = "Default-Profile.opt"
Phase2-CleanupJobsEnabled = 1
Phase2-ErrorCount = 0
```

---

## Phase 3: Capability - Registry Changes

### AI Settings

**Location**: `HKLM:\Software\HELIOS\Capability\`

```
AI-Settings\ (REG_SZ and DWORD values)
├── ModelPath = "C:\ProgramData\HELIOS\Capability\AI-Models"
├── ActiveModel = "threat-detection-v4.1.model"
├── InferenceThreads = 4                                   # DWORD
├── GPUAcceleration = 1                                    # DWORD (1=enabled)
├── ModelUpdateFrequency = 604800                          # DWORD (seconds)
├── ConfidenceThreshold = 0.75                             # REG_SZ or float
├── AutoRetraining = 1                                     # DWORD
└── MaxConcurrentAnalysis = 4                              # DWORD

Analysis-Settings\
├── DefaultProfile = "Enterprise-High-Security"
├── ScanFrequency = "hourly"
├── DeepInspection = 1
├── BehavioralAnalysis = 1
├── AnomalyDetection = 1
└── MaxConcurrentAnalysis = 4

Dashboard-Settings\
├── UITheme = "Dark"
├── Language = "en-US"
├── RefreshInterval = 5000                                 # Milliseconds
├── EnableNotifications = 1
└── TrayIconEnabled = 1

Reporting-Settings\
├── EnableAutoReporting = 1
├── ReportFrequency = "daily"
├── ReportFormat = "pdf"
├── EmailDistribution = "admin@company.com"
└── ArchiveReports = 1

Integration-Settings\
├── CloudSyncEnabled = 1
├── CloudProvider = "AWS" (or "Azure")
├── DataExportEnabled = 1
└── WebDashboardEnabled = 1

Feature-Flags\
├── BetaFeatures = 0                                       # 0=Off
├── AdvancedAI = 1                                         # 1=On
├── MachineLearning = 1
└── ExperimentalModels = 0
```

### Dashboard Application

**Location**: `HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\Dashboard.exe`

```
(Default) = "C:\Program Files\HELIOS\Dashboard\Dashboard.exe"
Path = "C:\Program Files\HELIOS\Dashboard"
UseUrl = 0
```

### Workflow Scheduling

**Location**: `HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\`

```
Tree\HELIOS\
├── Daily-Optimization
├── Weekly-Deep-Clean
├── Hourly-Monitor
├── Monthly-Report-Generation
└── Startup-Optimization-Task

Tasks\ (Binary task definitions)
└── (UUIDs mapping to task definitions)
```

### AI Model Registration

**Location**: `HKLM:\Software\HELIOS\Capability\AI-Models\`

```
threat-detection-v4.1\
├── Path = "C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\threat-detection-v4.1.model"
├── Version = "4.1.0"
├── Size = 157286400                                       # Bytes (150 MB)
├── Accuracy = 0.96                                        # Float
├── LastUpdated = FILETIME_VALUE
└── Active = 1                                             # 1=Current model

behavior-analysis-v5.0\
├── Path = "C:\ProgramData\HELIOS\Capability\AI-Models\Core-Models\behavior-analysis-v5.0.model"
├── Version = "5.0.0"
├── Size = 209715200                                       # 200 MB
├── Accuracy = 0.94
├── LastUpdated = FILETIME_VALUE
└── Active = 1
```

### Phase 3 Status

**Location**: `HKLM:\Software\HELIOS\Status\`

```
Phase3-Complete = 1
Phase3-Started = FILETIME_VALUE
Phase3-Completed = FILETIME_VALUE
Phase3-DashboardDeployed = 1
Phase3-AIModelsLoaded = 5                                  # Count of models
Phase3-ProfilesCreated = 15                                # Count of profiles
Phase3-WorkflowsConfigured = 7                             # Count of workflows
Phase3-DatabaseInitialized = 1
Phase3-ErrorCount = 0
```

---

## Global HELIOS Registry

**Location**: `HKLM:\Software\HELIOS\`

```
Installation\ (Applies to all phases)
├── InstallDate = "2024-01-15 08:30:15"
├── Version = "4.1.0"
├── Edition = "Enterprise" (or "Home", "Professional")
├── SystemDrive = "C:"
├── UninstallString = "C:\Program Files\HELIOS\Uninstall.exe"
├── DisplayVersion = "4.1.0"
├── Publisher = "HELIOS Corporation"
└── URLInfoAbout = "https://helios-platform.com"

Paths\ (Paths to all major directories)
├── Root = "C:\ProgramData\HELIOS"
├── Foundation = "C:\ProgramData\HELIOS\Foundation"
├── Security = "C:\ProgramData\HELIOS\Security"
├── Optimization = "C:\ProgramData\HELIOS\Optimization"
├── Capability = "C:\ProgramData\HELIOS\Capability"
├── Database = "C:\ProgramData\HELIOS\Database"
├── Logs = "C:\ProgramData\HELIOS\Logs"
├── Dashboard = "C:\Program Files\HELIOS\Dashboard"
└── Config = "C:\ProgramData\HELIOS\Config"

Status\ (Phase completion and overall status)
├── Phase0-Complete = 1
├── Phase1-Complete = 1
├── Phase2-Complete = 1
├── Phase3-Complete = 1
├── InstallationComplete = 1
├── LastHealthCheck = FILETIME_VALUE
└── RollbackAvailable = 0

Configuration\ (Global settings)
├── EncryptionEnabled = 1
├── LogLevel = "Info" (or "Debug", "Warning", "Error")
├── MaxLogSizeMB = 500
├── LogRetentionDays = 90
├── AutoUpdateEnabled = 1
├── DailyMaintenanceTime = "02:00:00"
└── BackupFrequency = "daily"

Notifications\ (Alert settings)
├── EnableEmailAlerts = 1
├── AdminEmail = "admin@company.com"
├── AlertOnCritical = 1
├── AlertOnHighSeverity = 1
├── AlertOnMediumSeverity = 0
└── DigestFrequency = "daily"

Licensing\ (License info)
├── LicenseKey = (encrypted)
├── LicenseExpiration = FILETIME_VALUE
├── MaxUsers = 999999
├── ProductID = "HELIOS-ENTERPRISE-4.1"
└── ActivationStatus = "Active"
```

---

## Registry Backup Recommendations

Before Phase deployment, backup registry sections:

```
Registry Exports to Create:
├── Pre-Phase0-Registry.reg
│   └── HKLM:\Software\HELIOS (will be new)
├── Pre-Phase1-Registry.reg
│   └── HKLM:\Software\Policies\Microsoft\Windows\SrpV2
│   └── HKLM:\System\CurrentControlSet\Services\SharedAccess
│   └── HKLM:\Software\Policies\Microsoft\Windows\Defender
├── Pre-Phase2-Registry.reg
│   └── HKLM:\SYSTEM\CurrentControlSet\Services (all services)
│   └── HKLM:\Software\Microsoft\Windows\CurrentVersion\Run
└── Pre-Phase3-Registry.reg
    └── HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Schedule
    └── HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths
```

---

## Registry Size Impact

| Phase | Registry Hive Growth |
|-------|-----------------|
| Phase 0 | ~50 KB |
| Phase 1 | ~150 KB (AppLocker + Firewall) |
| Phase 2 | ~200 KB (Services + Startup) |
| Phase 3 | ~100 KB (AI + Dashboard config) |
| **Total** | **~500 KB** |

Registry remains well within safe limits.

---

## Rollback Registry Procedure

To rollback any phase, reverse registry changes by:

1. Restore from Pre-Phase backup (if available)
2. Or manually delete phase-specific registry keys
3. Or run phase-specific rollback script

See **FILE_BORROWING_GUIDE.md** for restoration examples.
