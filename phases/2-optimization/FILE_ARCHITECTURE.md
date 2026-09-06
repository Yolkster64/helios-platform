# HELIOS Phase 2: File Architecture & Registry Paths

## Where Optimization Settings Live

This document maps out every file and registry location that Phase 2 touches. Use this to understand what gets changed, where to find backups, and how to manually verify changes.

---

## FOLDER STRUCTURE

### Phase 2 Directory Tree

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\
├── README.md                                (Overview)
├── PLAIN_ENGLISH_GUIDE.md                   (This guide - explanations)
├── FILE_ARCHITECTURE.md                     (This document - where files/settings go)
├── BEFORE_AND_AFTER.md                      (Expected performance gains)
├── SCRIPTS_INDEX.md                         (List of all scripts)
├── TESTING_GUIDE.md                         (How to measure improvements)
├── scripts/
│   ├── optimize-services-disable.ps1        (Disables unnecessary services)
│   ├── undo-services-disable.ps1            (Re-enables services)
│   ├── optimize-startup-remove.ps1          (Removes startup clutter)
│   ├── undo-startup-remove.ps1              (Restores startup items)
│   ├── optimize-resources-tune.ps1          (RAM and CPU tuning)
│   ├── undo-resources-tune.ps1              (Restores resource settings)
│   ├── optimize-background-processes.ps1    (Controls background tasks)
│   ├── undo-background-processes.ps1        (Restores background control)
│   ├── optimize-visual-effects.ps1          (Reduces visual effects)
│   ├── undo-visual-effects.ps1              (Restores visual effects)
│   ├── optimize-network-settings.ps1        (TCP/IP tuning)
│   ├── undo-network-settings.ps1            (Restores network settings)
│   ├── optimize-storage-cleanup.ps1         (Defrag, cleanup, compress)
│   ├── undo-storage-cleanup.ps1             (N/A - cleanup can't be undone)
│   └── run-all-optimizations.ps1            (Runs all in sequence)
├── backups/
│   ├── services-backup.reg                  (Registry backup - services)
│   ├── startup-backup.reg                   (Registry backup - startup)
│   ├── resources-backup.reg                 (Registry backup - resources)
│   ├── processes-backup.reg                 (Registry backup - processes)
│   ├── visual-backup.reg                    (Registry backup - visual effects)
│   ├── network-backup.reg                   (Registry backup - network)
│   └── pre-phase2-full-backup.reg           (Full system registry backup)
├── logs/
│   ├── phase2-execution.log                 (What was run and when)
│   ├── services-disabled.log                (Which services were disabled)
│   ├── startup-removed.log                  (Which startup items removed)
│   ├── storage-cleanup.log                  (Files deleted, space freed)
│   └── before-after-comparison.log          (Performance metrics)
└── templates/
    ├── service-template.reg                 (Template for re-enabling services)
    └── startup-template.reg                 (Template for restoring startup)
```

---

## WINDOWS SYSTEM FOLDERS AFFECTED

### Startup Folder

**Location:**

```
C:\Users\ADMIN\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
```

**What Happens:**

- Shortcuts here automatically run when user logs in
- Phase 2 removes unnecessary shortcuts (OneDrive, Cortana, etc.)
- Each shortcut = 2-5 seconds to boot time

**Shortcuts Removed (Examples):**

```
OneDrive.lnk                    ← Cloud sync startup
Cortana.lnk                     ← Voice assistant startup
UpdateAssistant.lnk             ← Update checker
CCleaner.lnk                    ← Cleanup tool (if installed)
ZoomLauncher.lnk                ← Zoom app (if installed)
```

**How to Restore Manually:**

```powershell
# Recreate OneDrive startup
Copy-Item "C:\Program Files\Microsoft OneDrive\OneDrive.exe" `
  -Destination "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OneDrive.lnk"
```

### Temporary Files Folders

#### Windows Temp Folder

```
C:\Windows\Temp\
```

- Contains temporary files created by Windows and system processes
- Safe to delete entirely (rebuilds automatically)
- Typically contains: log files, crash dumps, temporary installers
- Phase 2 deletes all files here

#### User Temp Folder

```
C:\Users\ADMIN\AppData\Local\Temp\
```

- Contains temporary files created by applications
- Safe to delete entirely (applications recreate when needed)
- Typically contains: browser caches, installer temps, app logs
- Phase 2 deletes all files here (except those in use)

#### Update Installation Temp

```
C:\$Windows.~BT\
C:\$Windows.~LS\
```

- Temporary folders from Windows Update installation
- Only safe to delete if older than 30 days (no active updates)
- Can contain: Downloaded updates, installation media
- Phase 2 deletes if older than 30 days

**Total Space Freed:** 500 MB - 5 GB

### Recycle Bin

**Location:**

```
C:\$Recycle.Bin\
```

**Behavior:**

- Usually hidden folder
- Contains files deleted by users (recoverable until emptied)
- Phase 2 empties this folder
- Files here count toward used disk space

**To View:**

```powershell
# Show hidden files
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" `
  -Name "Hidden" -Value 1

# Now visible in C:\$Recycle.Bin
```

**Restoration:**

- Files cannot be restored after permanent deletion
- This is by design; recycle bin is for "trash"

---

## REGISTRY PATHS (HIVES & KEYS)

### HKLM: SYSTEM REGISTRY (Machine-wide, all users)

#### Services Configuration

**Base Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\
```

**Common Services Disabled by Phase 2:**

| Service Name | Registry Key | Type of Service | Impact When Disabled |
|---|---|---|---|
| DiagTrack | `Services\DiagTrack` | Telemetry | None (you won't miss it) |
| dmwappushservice | `Services\dmwappushservice` | Diagnostics | None |
| OneSyncSvc | `Services\OneSyncSvc` | Sync | Manual sync required |
| RetailDemo | `Services\RetailDemo` | Demo mode | None |
| WSearch | `Services\WSearch` | Search Indexer | Manual search only |
| SearchIndexer | `Services\SearchIndexer` | Indexing | Manual search only |
| SysMain | `Services\SysMain` | Prefetch/Superfetch | Slightly slower app starts |
| MapsBroker | `Services\MapsBroker` | Maps | Manual map launches |
| Spooler | `Services\Spooler` | Printing | Must re-enable to print |

**Actual Registry Location Examples:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack
  └─ Start: 2 (AutoStart) → 4 (Disabled)
  └─ DisplayName: "Connected User Experiences and Telemetry"
  └─ Description: "Collects usage data and sends to Microsoft"
  └─ ObjectName: "LocalSystem"

HKLM:\SYSTEM\CurrentControlSet\Services\WSearch
  └─ Start: 2 (AutoStart) → 4 (Disabled)
  └─ DisplayName: "Windows Search"
  └─ Description: "Indexes files on computer for faster search"
```

**Backup Location:**

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\services-backup.reg
```

**How to Restore One Service:**

```powershell
# Example: Restore Windows Search
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" `
  -Name "Start" -Value 2

# Then start it
Start-Service -Name "WSearch"
```

#### Memory Management

**Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management
```

**Settings Changed:**

| Setting | Before | After | Effect |
|---|---|---|---|
| DisablePagingExecutive | 0 (page OS code) | 1 (keep OS code in RAM) | OS runs faster, uses more RAM |
| LargeSystemCache | 0 (small cache) | 1 (large cache) | Better performance, less RAM free |
| ClearPageFileAtShutdown | 0 (keep data) | 1 (clear data) | Security improvement, slower shutdown |

**Backup Location:**

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\resources-backup.reg
```

**Registry View:**

```
Registry: HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management
  DisablePagingExecutive: 1         ← Phase 2 sets to 1
  LargeSystemCache: 1               ← Phase 2 sets to 1
  ClearPageFileAtShutdown: 1        ← Phase 2 sets to 1 (security)
```

#### TCP/IP Network Settings

**Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters
```

**Settings Optimized:**

| Setting | Default | Phase 2 Value | Effect |
|---|---|---|---|
| TcpWindowSize | 65535 (usually) | 1073741824 | Larger network packets = faster transfers |
| TcpTimestamps | 0 or missing | 1 | Better duplicate detection |
| Sack | 0 or missing | 1 | Smarter packet retransmission |
| SynAttackProtect | 1 | 2 | Better DDoS protection |
| TCPNoDelay | 0 or missing | 1 | Disable Nagle algorithm for faster sends |

**Full Registry Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters
  TcpWindowSize: REG_DWORD: (Hex) 0x40000000 (1 GB)
  TcpTimestamps: REG_DWORD: 1
  Sack: REG_DWORD: 1
  TCPNoDelay: REG_DWORD: 1
  EnableRSC: REG_DWORD: 1 (RSS enabled)
  RSSProfile: REG_DWORD: 2 (RSS enabled)
```

**Backup Location:**

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\network-backup.reg
```

#### Page File Configuration

**Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management
  PagingFiles: [registry value]
```

**Actual Entry:**

```
Registry Value: PagingFiles
  Type: REG_MULTI_SZ
  Content: 
    C:\pagefile.sys 2048 4096
    (Minimum 2 GB, Maximum 4 GB)

Before:
    C:\pagefile.sys 4096 16384
    (Much larger than needed)
```

**Actual File Location:**

```
C:\pagefile.sys                   ← Hidden system file
  Before: 4 GB - 16 GB (wasteful)
  After:  2 GB - 4 GB  (optimal)
```

---

### HKCU: USER REGISTRY (Current user only)

#### Visual Effects

**Base Path:**

```
HKCU:\Control Panel\Desktop
```

**Settings Changed:**

| Setting | Before | After | Effect |
|---|---|---|---|
| UserPreferencesMask | [various bits] | [optimized bits] | Multiple visual effect toggles |
| MinAnimate | 1 (enabled) | 0 (disabled) | Window minimize animation |
| ComposedScreenshots | 1 (on) | 0 (off) | Screenshot animation |
| MenuShowDelay | 400ms | 0ms | Menu fade delay |

**Window Metrics Sub-key:**

```
HKCU:\Control Panel\Desktop\WindowMetrics
  CaptionFont: [font object] → [optimized font] (less anti-alias)
  TransparencyOn: 1 → 0 (disable transparency)
```

**Registry Snapshot:**

```
HKCU:\Control Panel\Desktop
  UserPreferencesMask: (Binary) 
    BE 00 00 80 1E 00 00 00 ... (before)
    98 02 00 80 1E 00 00 00 ... (after - visual effects off)
```

**Backup Location:**

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\visual-backup.reg
```

#### Startup Programs (Run Keys)

**Path:**

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce
```

**Before Phase 2:**

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
  OneDrive: "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
  Cortana: "C:\Windows\System32\SearchIndexer.exe /start"
  UpdateAssistant: "C:\Program Files\UpdateAssistant\UpdateAssistant.exe"
  ZoomLauncher: "C:\Program Files\Zoom\ZoomLauncher.exe"
  CCleaner: "C:\Program Files\CCleaner\CCleaner.exe"
  ... (10-15 more entries)
```

**After Phase 2:**

```
HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
  (Most entries removed; only essential ones remain)
```

**Backup Location:**

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\startup-backup.reg
```

---

### HKLM: SOFTWARE REGISTRY (Software configuration)

#### Explorer Advanced Settings

**Path:**

```
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced
```

**Settings Changed:**

| Setting | Before | After | Effect |
|---|---|---|---|
| DisablePreload | 0 (preload enabled) | 1 (disabled) | Doesn't preload DLLs into memory |
| ListviewAlphaBlending | 1 (enabled) | 0 (disabled) | File list doesn't fade/blend |
| IconsOnly | 0 (show all) | 1 (only icons) | Simpler appearance |

**Registry Example:**

```
HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced
  DisablePreload: REG_DWORD: 1
  ListviewAlphaBlending: REG_DWORD: 0
  IconsOnly: REG_DWORD: 1
```

---

### HKLM: SERVICES\EVENTLOG (Event Log Configuration)

**Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\EventLog
```

**What Gets Changed:**

- Log file sizes optimized (not delete, just reduce size)
- Old logs may be archived instead of deleted
- Some debug logs disabled

**Paths:**

```
C:\Windows\System32\winevt\Logs\
  ├─ System.evtx              (System events)
  ├─ Application.evtx         (App events)
  ├─ Security.evtx            (Security events)
  └─ ... (other event logs)

Backup: C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\*-backup.reg
```

---

## WINDOWS SCHEDULER TASKS

### Task Scheduler Base Path

```
%windir%\System32\Tasks\
```

### Tasks Disabled by Phase 2

#### Microsoft Windows Tasks

**Path:**

```
%windir%\System32\Tasks\Microsoft\Windows\
```

**Disabled Tasks:**

| Task Path | Full Path | Reason Disabled |
|---|---|---|
| UpdateOrchestrator\* | Tasks\Microsoft\Windows\UpdateOrchestrator\ | Throttle Windows Update; don't disable entirely |
| Application Experience\ProgramDataUpdater | Tasks\Microsoft\Windows\Application Experience\ | Diagnostic data collection |
| Autochk\Scheduled | Tasks\Microsoft\Windows\Autochk\ | Weekly chkdsk; schedule off-hours instead |
| CacheTask\Regular Maintenance | Tasks\Microsoft\Windows\CacheTask\ | Unnecessary cache maintenance |
| Customer Experience Improvement Program | Tasks\Microsoft\Windows\Customer Experience... | Telemetry; optional |
| Defrag\ScheduledDefrag | Tasks\Microsoft\Windows\Defrag\ | Manually scheduled instead |
| Disk Cleanup\SilentCleanup | Tasks\Microsoft\Windows\Disk Cleanup\ | Manually triggered instead |
| File History\File History (maintenance) | Tasks\Microsoft\Windows\File History\ | Manual backup method |
| MobilePC\DisplayLink | Tasks\Microsoft\Windows\MobilePC\ | Obsolete |
| NetTrace\GatherNetDiagnostics | Tasks\Microsoft\Windows\NetTrace\ | Diagnostic telemetry |
| Registry\RegIdleBackup | Tasks\Microsoft\Windows\Registry\ | Unnecessary registry backup |
| Shell\IndexerService | Tasks\Microsoft\Windows\Shell\ | Manual search instead |
| SideShow\GadgetManager | Tasks\Microsoft\Windows\SideShow\ | Obsolete |
| System Restore\SR | Tasks\Microsoft\Windows\System Restore\ | Manual restore instead |

**Registry Path for Tasks:**

```
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tasks\
  {GUID-of-task}
    Enabled: 1 → 0  (Disabled)
    Path: \Microsoft\Windows\UpdateOrchestrator\...
```

**XML Task Definition:**

```
%windir%\System32\Tasks\Microsoft\Windows\UpdateOrchestrator\Regular Maintenance
  ← This file marks when task should run
  ← Phase 2 may set enabled=false in XML
```

### How to View Task Scheduler

```
Win + R → taskschd.msc
Navigate to: Task Scheduler Library → Microsoft → Windows → [Category]
Right-click task → Properties → General tab → Enabled checkbox
```

### Backup Task Configuration

```
Phase 2 Backup Location:
C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\tasks-backup.xml

Contains all task definitions and enabled/disabled states
```

---

## DRIVER & HARDWARE REGISTRY

### Network Driver Offloading

**Path:**

```
HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\
  [Device-specific subkeys]
```

**Settings Changed:**

| Setting | Before | After | Effect |
|---|---|---|---|
| *TCPChecksumOffloadIPv4 | 0 (off) | 3 (on) | Network card does checksum, CPU doesn't |
| *TCPChecksumOffloadIPv6 | 0 (off) | 3 (on) | Same for IPv6 |
| *LSOv2IPv4 | 0 (off) | 1 (on) | Large Segment Offload enabled |
| *LSOv2IPv6 | 0 (off) | 1 (on) | Same for IPv6 |
| *RSSProfile | 0 or 1 | 2 | Receive-Side Scaling enabled |

**Example:**

```
HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\0000
  DriverDesc: "Intel(R) Ethernet Connection I217-V"
  *TCPChecksumOffloadIPv4: 3
  *LSOv2IPv4: 1
  *RSSProfile: 2
```

---

## LOG FILES & DOCUMENTATION

### Phase 2 Logs Directory

```
C:\Users\ADMIN\helios-platform\phases\2-optimization\logs\
```

### Log Files Created During Phase 2

#### Execution Log

```
phase2-execution.log

Content:
  [2024-01-15 14:30:22] Starting Phase 2 Optimization
  [2024-01-15 14:30:25] Service Disabling started...
  [2024-01-15 14:31:45] Services disabled: DiagTrack, dmwappushservice, OneSyncSvc
  [2024-01-15 14:32:10] Startup Optimization started...
  [2024-01-15 14:33:22] Removed 12 startup items
  ...
  [2024-01-15 15:45:30] Phase 2 Optimization Complete
```

#### Services Disabled Log

```
services-disabled.log

Content:
  DiagTrack - Connected User Experiences and Telemetry (Disabled)
  dmwappushservice - dmwappushservice (Disabled)
  OneSyncSvc - Sync Host (Disabled)
  RetailDemo - Retail Demo Service (Disabled)
  WSearch - Windows Search Indexing (Disabled)
  ...
```

#### Startup Items Removed Log

```
startup-removed.log

Content:
  OneDrive.lnk - Removed from C:\Users\ADMIN\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup
  UpdateAssistant.lnk - Removed from HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
  CCleaner.lnk - Removed from HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
  ...
```

#### Storage Cleanup Log

```
storage-cleanup.log

Content:
  Cleaned: C:\Windows\Temp\
    Files deleted: 1,234
    Space freed: 523 MB
  
  Cleaned: C:\Users\ADMIN\AppData\Local\Temp\
    Files deleted: 856
    Space freed: 312 MB
  
  Cleaned: Recycle Bin
    Files deleted: 4,521
    Space freed: 2.3 GB
  
  Total space freed: 3.1 GB
```

#### Performance Comparison Log

```
before-after-comparison.log

Content:
  === BOOT TIME ===
  Before: 120.5 seconds
  After:  58.2 seconds
  Improvement: 62.3 seconds (51.7% faster)
  
  === APPLICATION LAUNCH ===
  Before: 5.2 seconds (average)
  After:  1.8 seconds (average)
  Improvement: 3.4 seconds (65.4% faster)
  
  === MEMORY USAGE ===
  Before: 2.8 GB idle
  After:  1.4 GB idle
  Improvement: 1.4 GB freed (50% more available)
  
  === CPU IDLE ===
  Before: 18%
  After:  6%
  Improvement: 12 percentage points (67% reduction)
```

---

## CONFIGURATION FILES

### Windows Configuration Files Modified

#### Group Policy Local Objects

```
%windir%\System32\GroupPolicy\
  ├─ gpt.ini                      (GP template info)
  └─ [Local policy applied via Registry, no direct file change]
```

#### Power Plans

```
%windir%\inf\power\
  └─ powerschemes\               (Power plan definitions)

Affected Plans:
  - Balanced (default)
  - Power Saver
  - High Performance

Changes: May adjust CPU scaling in power plan XML
```

#### Network Configuration

```
%windir%\System32\drivers\etc\
  ├─ hosts                        (Static DNS entries; may add)
  ├─ lmhosts                      (NetBIOS name mapping)
  └─ networks                     (Network definitions)
```

---

## SUMMARY TABLE: FILES & REGISTRY PATHS

| Category | Location | Type | Action |
|----------|----------|------|--------|
| **Services** | HKLM:\SYSTEM\CurrentControlSet\Services\ | Registry | Modify Start value (2→4) |
| **Startup Programs** | HKCU:\Software\Microsoft\Windows\CurrentVersion\Run | Registry | Delete entries |
| **Startup Shortcuts** | C:\Users\ADMIN\AppData\Roaming\...\Startup | Folder | Delete .lnk files |
| **Memory Settings** | HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\ | Registry | Modify memory tuning values |
| **TCP/IP Settings** | HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters | Registry | Modify network values |
| **Visual Effects** | HKCU:\Control Panel\Desktop | Registry | Modify effect settings |
| **Tasks** | %windir%\System32\Tasks\Microsoft\Windows\ | Files + Registry | Disable scheduled tasks |
| **Temp Files** | C:\Windows\Temp, C:\Users\...\AppData\Local\Temp\ | Folder | Delete all files |
| **Event Logs** | %windir%\System32\winevt\Logs\ | Files | Archive/compress |
| **Page File** | C:\pagefile.sys | System File | Resize via registry |
| **Recycle Bin** | C:\$Recycle.Bin\ | Folder | Empty |
| **Backups** | C:\Users\ADMIN\helios-platform\phases\2-optimization\backups\ | .reg files | Reference/restore |

---

## Verification Commands

### Verify Services Are Disabled

```powershell
# Check specific service
Get-Service -Name "DiagTrack" | Select-Object Name, StartType, Status

# Check multiple
"DiagTrack", "dmwappushservice", "OneSyncSvc" | ForEach-Object { 
  Get-Service -Name $_ | Select-Object Name, StartType, Status 
}
```

### Verify Registry Changes

```powershell
# Check memory settings
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"

# Check network settings
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" | 
  Select-Object TcpWindowSize, TcpTimestamps, Sack
```

### Verify Temporary Files Removed

```powershell
# Check Windows Temp folder
Get-ChildItem "C:\Windows\Temp\" | Measure-Object | Select-Object Count

# Check User Temp
Get-ChildItem "C:\Users\ADMIN\AppData\Local\Temp\" | Measure-Object | Select-Object Count
```

### Verify Visual Effects Disabled

```powershell
# Check visual effects registry
Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" | 
  Select-Object UserPreferencesMask, MinAnimate
```

---

## For Support & Troubleshooting

**Lost? Use this decision tree:**

1. **"I want to undo a change"**
   → Find the service/setting in this document
   → Use corresponding "undo-*.ps1" script
   → Or restore from backup: `REG RESTORE HKCU\... C:\backups\*-backup.reg`

2. **"What changed in [folder]?"**
   → Find folder name in this document
   → Check "Before Phase 2" vs. "After Phase 2"
   → Consult logs in `C:\Users\ADMIN\helios-platform\phases\2-optimization\logs\`

3. **"I need to verify a change was applied"**
   → Use verification commands above
   → Compare with "Expected Registry" values in this document
   → Check execution logs

4. **"Something's broken"**
   → Restore from `backups\pre-phase2-full-backup.reg`
   → Or use System Restore Point from Phase 1
   → Read: `PLAIN_ENGLISH_GUIDE.md` "How To Undo" section

---

**Next Steps:**

- Consult `PLAIN_ENGLISH_GUIDE.md` for explanations
- Check `TESTING_GUIDE.md` to measure improvements
- Review `BEFORE_AND_AFTER.md` for expected gains
