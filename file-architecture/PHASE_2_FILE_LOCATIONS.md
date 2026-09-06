# Phase 2: Optimization - File Locations

Phase 2 deploys system optimization configurations, manages services, controls startup items, and handles system cleanup operations.

## Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| Service Configs | HKLM:\SYSTEM\CurrentControlSet\Services\ | Windows service definitions |
| Startup Items | C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\ | User-level auto-start programs |
| Optimization Profiles | C:\ProgramData\HELIOS\Optimization\Profiles\ | System optimization configurations |
| Cleanup Configs | C:\ProgramData\HELIOS\Optimization\Cleanup\ | Temporary file cleanup rules |
| Cache Management | C:\ProgramData\HELIOS\Optimization\Cache\ | Cache optimization policies |
| Performance Baselines | C:\ProgramData\HELIOS\Optimization\Baselines\ | Performance snapshots |
| Optimization Logs | C:\ProgramData\HELIOS\Logs\Phase2.log | Phase 2 diagnostic logs |
| Scheduled Tasks | C:\Windows\System32\Tasks\HELIOS\ | Automated optimization tasks |

---

## Service Configuration (Registry)

**Location**: `HKLM:\SYSTEM\CurrentControlSet\Services\`

**Purpose**: Define and configure Windows services for optimization

**Registry Structure**:

```
HKLM:\SYSTEM\CurrentControlSet\Services\
├── HELIOSMonitor                       # Main HELIOS monitoring service
│   ├── DisplayName                     # "HELIOS System Monitor"
│   ├── Description                     # Service description
│   ├── ImagePath                       # "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"
│   ├── Type                            # 16 (Service runs in own process)
│   ├── Start                           # 2 (Auto-start)
│   ├── ErrorControl                    # 1 (Log error, continue startup)
│   ├── ObjectName                      # "LocalSystem" (runs as SYSTEM)
│   ├── DependOnService                 # Dependencies list
│   ├── Parameters\
│   │   ├── EnableDebugLogging          # 0 or 1
│   │   ├── MonitorInterval             # 300 (5 minutes)
│   │   └── QuarantineCheckInterval     # 600 (10 minutes)
│   └── Security\                       # Service permissions
│       ├── Grant (Allow Read)          # For authenticated users
│       └── Grant (Allow Start/Stop)    # For Administrators
│
├── HELIOSOptimizer                     # Optimization service
│   ├── DisplayName                     # "HELIOS System Optimizer"
│   ├── ImagePath                       # "C:\Program Files\HELIOS\Optimizer\HELIOSOptimizer.exe"
│   ├── Type                            # 16
│   ├── Start                           # 2 (Auto-start)
│   ├── ObjectName                      # "LocalSystem"
│   └── Parameters\
│       ├── CleanupInterval             # 86400 (24 hours)
│       ├── CacheCleanupEnabled         # 1 (TRUE)
│       ├── TempFileCleanup             # 1 (TRUE)
│       └── PreserveDays                # 30 (preserve files <30 days)
│
├── HELIOSVaultMonitor                  # Vault monitoring service
│   ├── DisplayName                     # "HELIOS Vault Monitor"
│   ├── ImagePath                       # "C:\Program Files\HELIOS\Vault\VaultMonitor.exe"
│   ├── Type                            # 16
│   ├── Start                           # 2 (Auto-start)
│   ├── ObjectName                      # "LocalSystem"
│   └── Parameters\
│       ├── MonitorInterval             # 300 (5 minutes)
│       └── AutoLockTimeout             # 900 (15 minutes)
│
├── HELIOSAnalyzer                      # Analysis engine service
│   ├── DisplayName                     # "HELIOS Analysis Engine"
│   ├── ImagePath                       # "C:\Program Files\HELIOS\Analyzer\HELIOSAnalyzer.exe"
│   ├── Type                            # 16
│   ├── Start                           # 2 (Auto-start)
│   ├── ObjectName                      # "LocalSystem"
│   └── Parameters\
│       ├── AnalysisInterval            # 3600 (1 hour)
│       └── MaxConcurrentAnalysis       # 4
│
├── WdiSystemHost                       # Diagnostic tracking service (modified)
│   ├── Start                           # Modified: 2 (Auto-start) or 4 (Disabled)
│   └── (HELIOS may disable unnecessary services)
│
└── (Other services optimized by HELIOS)
    ├── Windows Update
    ├── Background Intelligent Transfer Service
    ├── Superfetch/Memory Compression
    └── Search Indexer
```

**Examples**:

```
HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSMonitor\ImagePath = 
  "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"

HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSOptimizer\Start = 2

HKLM:\SYSTEM\CurrentControlSet\Services\HELIOSOptimizer\Parameters\CleanupInterval = 86400
```

**Access**: Admin/SYSTEM required

**Persistence**: Permanent until service uninstalled

---

## User Startup Items

**Location**: `C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\`

**Purpose**: Programs to run automatically when user logs in

**Files Created**:

```
C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\
├── HELIOS-Monitor.lnk                  # Shortcut to monitoring app
│   # Target: C:\Program Files\HELIOS\Dashboard\HELIOSMonitor.exe
│   # Parameters: -minimize -autostart
│   # Run: Minimized
│
├── HELIOS-Vault-Monitor.lnk            # Vault monitoring shortcut
│   # Target: C:\Program Files\HELIOS\Vault\VaultMonitor.exe
│   # Parameters: -tray -silent
│   # Run: Hidden
│
└── HELIOS-Performance-Logger.lnk       # Performance logging shortcut
    # Target: C:\Program Files\HELIOS\Monitor\PerfLogger.exe
    # Parameters: -background
    # Run: Minimized
```

**Examples**:

```
C:\Users\Administrator\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\HELIOS-Monitor.lnk
C:\Users\jsmith\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\HELIOS-Vault-Monitor.lnk
```

**Access**: User can add/remove; admin can force deployment

**Size**: Each .lnk file ~1-2 KB

---

## System Startup Registry (Alternative)

**Location**: `HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\`

**Purpose**: System-wide startup items (runs for all users)

**Registry Entries Created**:

```
HKLM:\Software\Microsoft\Windows\CurrentVersion\
├── Run\
│   ├── HELIOSMonitor                   # Value: "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"
│   ├── HELIOSVaultMonitor              # Value: "C:\Program Files\HELIOS\Vault\VaultMonitor.exe -tray"
│   └── HELIOSAnalyzer                  # Value: "C:\Program Files\HELIOS\Analyzer\HELIOSAnalyzer.exe -background"
│
├── RunOnce\
│   ├── HELIOSFirstRunSetup             # One-time setup on next logon
│   └── HELIOSWelcomeTour               # One-time wizard on first run
│
└── RunServices\                        # For services that need UI
    └── (May be used for tray applications)
```

**Examples**:

```
HKLM:\Software\Microsoft\Windows\CurrentVersion\Run\HELIOSMonitor = 
  "C:\Program Files\HELIOS\Monitor\HELIOSMonitor.exe"

HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\HELIOSVaultMonitor = 
  "C:\Program Files\HELIOS\Vault\VaultMonitor.exe -tray"
```

---

## Optimization Profiles

**Location**: `C:\ProgramData\HELIOS\Optimization\Profiles\`

**Purpose**: System optimization configuration profiles

**Files Created**:

```
C:\ProgramData\HELIOS\Optimization\Profiles\
├── Default-Profile.opt                 # Default optimization profile
│   # Contains:
│   # - Service startup configurations
│   # - Performance tuning parameters
│   # - Memory optimization settings
│   # - Disk cleanup policies
│
├── Performance-Profile.opt             # High-performance profile
│   # Contains:
│   # - Aggressive service disabling
│   # - CPU priority boost
│   # - RAM caching enabled
│   # - Background task reduction
│
├── Security-Profile.opt                # Security-focused profile
│   # Contains:
│   # - Enhanced logging enabled
│   # - Threat monitoring active
│   # - Reduced automatic cleanup (preserve audit trails)
│   # - Firewall logging enabled
│
├── Balanced-Profile.opt                # Balanced approach
│   # Contains:
│   # - Moderate service optimization
│   # - Standard performance tuning
│   # - Normal logging
│   # - Balanced cleanup
│
├── Battery-Saving-Profile.opt          # Laptop/battery profile
│   # Contains:
│   # - Power-saving optimizations
│   # - Screen timeout reduction
│   # - CPU frequency scaling
│   # - Background service throttling
│
├── Custom-Profiles\
│   ├── UserProfile-1.opt
│   ├── UserProfile-2.opt
│   └── (user-defined profiles)
│
└── Active-Profile.txt                  # Currently active profile name
    # Contents: "Default-Profile.opt" or other profile name
```

**Profile Configuration Format** (JSON):

```json
{
  "profile_name": "Default-Profile",
  "version": "4.1.0",
  "description": "Default HELIOS optimization configuration",
  "created_date": "2024-01-15",
  "services": {
    "HELIOSMonitor": { "start_type": "auto", "enabled": true },
    "HELIOSOptimizer": { "start_type": "auto", "enabled": true },
    "HELIOSAnalyzer": { "start_type": "auto", "enabled": true },
    "SearchIndexer": { "start_type": "auto", "enabled": false },
    "DiagnosticTracking": { "start_type": "disabled", "enabled": false }
  },
  "performance_tuning": {
    "memory_optimization": true,
    "disk_cache": "aggressive",
    "cpu_priority_boost": false,
    "visual_effects": "optimal"
  },
  "cleanup": {
    "temp_files": true,
    "cache_cleanup": true,
    "preserve_days": 30,
    "cleanup_interval_hours": 24
  }
}
```

**Access**: Admin/SYSTEM to modify; all users can read

**Size**: Each profile ~10-50 KB

**Examples**:

```
C:\ProgramData\HELIOS\Optimization\Profiles\Default-Profile.opt
C:\ProgramData\HELIOS\Optimization\Profiles\Performance-Profile.opt
C:\ProgramData\HELIOS\Optimization\Profiles\Active-Profile.txt
```

---

## Cleanup Configuration

**Location**: `C:\ProgramData\HELIOS\Optimization\Cleanup\`

**Purpose**: Temporary file and cache cleanup rules

**Files Created**:

```
C:\ProgramData\HELIOS\Optimization\Cleanup\
├── Cleanup-Rules.cfg                   # Main cleanup rules file
│   # Defines:
│   # - Directories to clean
│   # - Age thresholds (preserve <X days)
│   # - Exclusion patterns
│   # - Compression settings
│
├── Default-Cleanup-Rules.cfg           # HELIOS default rules
│   # Targets:
│   # - C:\Windows\Temp\
│   # - C:\Users\[USERNAME]\AppData\Local\Temp\
│   # - C:\Users\[USERNAME]\AppData\Local\Cache\
│   # - %TEMP%
│   # - Browser caches (per user)
│   # - Application temp directories
│
├── Custom-Cleanup-Rules.cfg            # User-defined rules
│   # User can add custom cleanup targets
│
├── Exclusion-List.txt                  # Patterns to exclude from cleanup
│   # Examples:
│   # - *.lnk
│   # - IMPORTANT_FILE_*.tmp
│   # - C:\Windows\Temp\System-Critical\*
│
├── Cleanup-History.log                 # Log of cleanup operations
├── Cleanup-Report-2024-01-15.txt       # Daily cleanup report
└── Schedules\
    ├── Daily-Cleanup.xml               # Daily cleanup schedule
    └── Weekly-Deep-Cleanup.xml         # Weekly deep clean
```

**Cleanup Rules Format**:

```
[CLEANUP_RULE_1]
Name=Windows Temporary Files
Path=C:\Windows\Temp\
Age=7                          # Delete files older than 7 days
Pattern=*.tmp,*.log
Exclude=System32\*,Config\*
Recursive=true
Compress-Before-Delete=false

[CLEANUP_RULE_2]
Name=User Temporary Files
Path=C:\Users\[USERNAME]\AppData\Local\Temp\
Age=30                         # Delete files older than 30 days
Pattern=*.*
Exclude=Important.txt
Recursive=true
Compress-Before-Delete=true

[CLEANUP_RULE_3]
Name=Browser Cache
Path=C:\Users\[USERNAME]\AppData\Local\
Age=14                         # Delete files older than 14 days
Pattern=Cache\*
Recursive=true
Exclude=.nolog
```

**Access**: Admin/SYSTEM to modify; read-only for users

**Size**: ~100-200 KB total

---

## Cache Management

**Location**: `C:\ProgramData\HELIOS\Optimization\Cache\`

**Purpose**: Manage system and application caches

**Files Created**:

```
C:\ProgramData\HELIOS\Optimization\Cache\
├── Cache-Policy.cfg                    # Cache management policies
│   # Defines:
│   # - Cache size limits
│   # - Cache retention periods
│   # - Cache locations
│   # - Compression settings
│
├── Cache-Inventory.db                  # Database of cached items
│   # Tracks:
│   # - Cache location
│   # - Size
│   # - Last accessed date
│   # - Priority (keep/remove)
│
├── Browser-Cache-Rules.cfg             # Browser-specific cache rules
│   # Manages:
│   # - Chrome cache
│   # - Firefox cache
│   # - Edge cache
│   # - IE cache (legacy)
│
├── Application-Cache-Rules.cfg         # Application cache rules
│   # Manages:
│   # - .NET Framework cache
│   # - Java cache
│   # - Adobe cache
│   # - Microsoft Office cache
│
└── Cache-Optimization-Report.txt       # Cache optimization analysis
```

**Cache Locations Managed**:

```
C:\Users\[USERNAME]\AppData\Local\Cache\
├── Chrome Cache
├── Firefox Cache
├── Edge Cache
└── HELIOS Cache

C:\Windows\System32\Temp\
├── Windows Update cache
├── Windows Defender cache
└── System cache

C:\ProgramData\
├── Microsoft\Windows\Caches\
├── Package Cache\
└── Other application caches
```

**Access**: Admin/SYSTEM required to manage

**Size**: Database ~10-50 MB; varies by system

---

## Performance Baselines

**Location**: `C:\ProgramData\HELIOS\Optimization\Baselines\`

**Purpose**: Performance snapshots for comparison

**Files Created**:

```
C:\ProgramData\HELIOS\Optimization\Baselines\
├── Baseline-Pre-Optimization.snapshot   # Before Phase 2 optimizations
│   # Contains:
│   # - CPU performance metrics
│   # - Memory usage patterns
│   # - Disk I/O metrics
│   # - Service startup times
│
├── Baseline-Post-Optimization.snapshot  # After Phase 2 optimizations
│   # Contains:
│   # - Improved performance metrics
│   # - Reduced startup times
│   # - Memory improvements
│
├── Daily-Performance-Snapshots\
│   ├── 2024-01-15-08-00.snapshot
│   ├── 2024-01-15-16-00.snapshot
│   └── (one per day at multiple times)
│
├── Performance-Trends.csv              # Performance metrics over time
│   # Columns:
│   # - Timestamp
│   # - CPU Usage (avg, max)
│   # - Memory Usage (avg, max)
│   # - Disk I/O (read, write)
│   # - Services Running
│   # - Boot Time (seconds)
│
└── Improvement-Report.txt              # Summary of optimizations
    # Shows:
    # - Boot time reduction %
    # - Memory usage reduction %
    # - CPU usage reduction %
    # - Services optimized count
```

**Performance Snapshot Contents**:

```json
{
  "timestamp": "2024-01-15T08:00:00Z",
  "phase": "pre-optimization",
  "metrics": {
    "boot_time_seconds": 45,
    "startup_programs": 12,
    "services_running": 87,
    "memory_usage_mb": 6200,
    "memory_available_mb": 1800,
    "cpu_usage_percent": 15,
    "disk_usage_percent": 65,
    "active_processes": 156
  },
  "services": {
    "enabled": ["Windows Update", "Superfetch", "DiagnosticTracking"],
    "disabled": ["SensorService", "dmwappushservice"]
  }
}
```

**Access**: Admin/SYSTEM to create; all users can read

**Size**: Each snapshot ~5-10 MB; baselines directory ~500 MB - 2 GB

---

## Scheduled Tasks

**Location**: `C:\Windows\System32\Tasks\HELIOS\`

**Purpose**: Automated optimization tasks

**Files Created**:

```
C:\Windows\System32\Tasks\HELIOS\
├── Daily-Optimization.xml              # Daily optimization task
│   # Runs: 2:00 AM daily
│   # Executes: C:\Program Files\HELIOS\Optimizer\DailyOptimizer.exe
│   # Actions:
│   #   - Cleanup temporary files
│   #   - Analyze performance
│   #   - Defragment cache
│
├── Weekly-Deep-Clean.xml               # Weekly deep clean task
│   # Runs: Saturday 3:00 AM
│   # Executes: C:\Program Files\HELIOS\Optimizer\DeepCleaner.exe
│   # Actions:
│   #   - Comprehensive cache cleanup
│   #   - Log rotation
│   #   - Database optimization
│
├── Hourly-Monitor.xml                  # Hourly monitoring task
│   # Runs: Every hour
│   # Executes: C:\Program Files\HELIOS\Monitor\HourlyMonitor.exe
│   # Actions:
│   #   - Performance checks
│   #   - Health monitoring
│   #   - Alert generation
│
├── Monthly-Report-Generation.xml       # Monthly report generation
│   # Runs: 1st of month at 1:00 AM
│   # Executes: C:\Program Files\HELIOS\Reports\ReportGenerator.exe
│   # Generates: Performance, security, and optimization reports
│
└── Startup-Optimization-Task.xml       # Runs at system startup
    # Runs: At system startup (after SYSTEM services)
    # Executes: C:\Program Files\HELIOS\Startup\StartupOptimizer.exe
    # Actions:
    #   - Pre-load optimization profiles
    #   - Start monitoring services
    #   - Initialize performance counters
```

**Task Scheduler Registry**:

```
HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Schedule\
├── TaskCache\Tree\
│   └── HELIOS\
│       ├── Daily-Optimization
│       ├── Weekly-Deep-Clean
│       ├── Hourly-Monitor
│       ├── Monthly-Report-Generation
│       └── Startup-Optimization-Task
│
└── TaskCache\Tasks\
    └── (Binary task definitions)
```

**Example Task XML Structure**:

```xml
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>HELIOS</Author>
    <Description>Daily System Optimization</Description>
    <Date>2024-01-15T08:00:00</Date>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>2024-01-15T02:00:00</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </TimeTrigger>
  </Triggers>
  <Actions>
    <Exec>
      <Command>C:\Program Files\HELIOS\Optimizer\DailyOptimizer.exe</Command>
      <Arguments>-full-cleanup -profile:Default</Arguments>
    </Exec>
  </Actions>
  <Settings>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Priority>7</Priority>
  </Settings>
</Task>
```

**Access**: Admin/SYSTEM to create/modify

**Size**: Each task XML ~10-50 KB

---

## Phase 2 Logs

**Location**: `C:\ProgramData\HELIOS\Logs\Phase2.log`

**Purpose**: Phase 2 deployment and optimization diagnostic logs

**Files Created**:

```
C:\ProgramData\HELIOS\Logs\
├── Phase2.log                          # Main Phase 2 log
├── Phase2-Details.log                  # Verbose Phase 2 log
├── Phase2-Errors.log                   # Phase 2 errors only
├── Phase2-Warnings.log                 # Phase 2 warnings
├── Service-Configuration.log           # Service setup logs
├── Startup-Configuration.log           # Startup item configuration
├── Optimization-Operations.log         # Daily optimization logs
├── Cleanup-Operations.log              # Cleanup operation logs
├── Performance-Tuning.log              # Performance tuning logs
└── Scheduled-Tasks-Setup.log           # Task scheduler setup logs
```

**Access**: Admin to write; everyone can read

**Size**: 50-200 MB with verbose logging

---

## Complete Directory Tree

```
C:\ProgramData\HELIOS\
├── Optimization\                       # Phase 2 root
│   ├── Profiles\                       # Optimization profiles
│   │   ├── Default-Profile.opt
│   │   ├── Performance-Profile.opt
│   │   ├── Security-Profile.opt
│   │   ├── Balanced-Profile.opt
│   │   ├── Battery-Saving-Profile.opt
│   │   ├── Custom-Profiles\
│   │   ├── Active-Profile.txt
│   │   └── (profile files)
│   ├── Cleanup\                        # Cleanup configuration
│   │   ├── Cleanup-Rules.cfg
│   │   ├── Default-Cleanup-Rules.cfg
│   │   ├── Custom-Cleanup-Rules.cfg
│   │   ├── Exclusion-List.txt
│   │   ├── Cleanup-History.log
│   │   ├── Cleanup-Report-*.txt
│   │   └── Schedules\
│   ├── Cache\                          # Cache management
│   │   ├── Cache-Policy.cfg
│   │   ├── Cache-Inventory.db
│   │   ├── Browser-Cache-Rules.cfg
│   │   ├── Application-Cache-Rules.cfg
│   │   └── Cache-Optimization-Report.txt
│   └── Baselines\                      # Performance baselines
│       ├── Baseline-Pre-Optimization.snapshot
│       ├── Baseline-Post-Optimization.snapshot
│       ├── Daily-Performance-Snapshots\
│       ├── Performance-Trends.csv
│       └── Improvement-Report.txt
│
└── Logs\
    ├── Phase2.log
    ├── Phase2-Details.log
    └── (other Phase 2 logs)

C:\Windows\System32\Tasks\HELIOS\
├── Daily-Optimization.xml
├── Weekly-Deep-Clean.xml
├── Hourly-Monitor.xml
├── Monthly-Report-Generation.xml
└── Startup-Optimization-Task.xml

C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\
├── HELIOS-Monitor.lnk
├── HELIOS-Vault-Monitor.lnk
└── HELIOS-Performance-Logger.lnk
```

---

## File Size Summary

| Component | Size |
|-----------|------|
| Optimization profiles | 10-50 KB each |
| Cleanup rules | ~100-200 KB |
| Cache inventory database | 10-50 MB |
| Performance baselines | 5-10 MB each |
| Performance trends (6 months) | 20-50 MB |
| Scheduled task definitions | 10-50 KB each |
| All Phase 2 files (system) | 200-500 MB |

---

## Service Optimization Examples

### Disabled Services (Reduced Resource Usage)

- Windows Search Indexer (if not needed)
- Diagnostic Tracking Service
- dmwappushservice
- DiagTrack

### Optimized Services (Auto-start)

- HELIOSMonitor
- HELIOSOptimizer
- HELIOSVaultMonitor
- HELIOSAnalyzer

### Critical Services (Unchanged)

- Windows Update
- Security Essentials
- Network services
- Storage services

---

## Next Steps

After Phase 2 completes:

- System services optimized
- Automatic cleanup active
- Performance profiles applied
- Monitoring and logging operational

See **PHASE_3_FILE_LOCATIONS.md** for next phase file placement.
