# HELIOS Phase 0: File Architecture

This document shows exactly where every file goes in the system and why.

---

## High-Level Storage Architecture

```
SYSTEM DRIVE (C:)
└── Operating System, Programs, System Files

DATA DRIVE (D:)
└── User Files, Documents, Backups, Projects

CLOUD/EXTERNAL
└── Backup copies (off-site security)
```

---

## C: Drive - System Drive

The C: drive contains Windows, programs, and system configuration.

### C:\HELIOS\

**Purpose**: Main HELIOS installation and configuration directory

```
C:\HELIOS\
├── phases\                              # All HELIOS phases
│   ├── 0-foundation/                    # This phase (startup)
│   │   ├── README.md
│   │   ├── PLAIN_ENGLISH_GUIDE.md
│   │   ├── FILE_ARCHITECTURE.md
│   │   ├── SCRIPTS_INDEX.md
│   │   ├── TESTING_GUIDE.md
│   │   └── scripts/
│   │       ├── usb-creator.ps1
│   │       ├── windows-installer.ps1
│   │       ├── partition-manager.ps1
│   │       ├── storage-setup.ps1
│   │       └── system-baseline.ps1
│   │
│   ├── 1-customization/                 # Phase 1 (next)
│   ├── 2-hardening/                     # Phase 2
│   ├── 3-security/                      # Phase 3
│   └── 4-optimization/                  # Phase 4
│
├── tools/                               # Utilities and scripts
│   ├── diagnostics/                     # System diagnostics
│   ├── utilities/                       # Helper scripts
│   └── recovery/                        # Recovery tools
│
├── config/                              # System configuration
│   ├── registry/                        # Registry templates
│   ├── group-policy/                    # GPO configurations
│   ├── startup/                         # Startup scripts
│   └── services/                        # Service configs
│
├── logs/                                # System logs
│   ├── phase0/                          # Phase 0 logs
│   ├── phase1/                          # Phase 1 logs
│   ├── system/                          # System event logs
│   └── errors/                          # Error logs
│
├── backups/                             # System backups (C: drive)
│   ├── registry-backups/
│   ├── config-backups/
│   └── snapshots/
│
└── docs/                                # Documentation
    ├── architecture/
    ├── troubleshooting/
    └── reference/
```

**Permissions:**

- Owner: SYSTEM and Administrators
- User: Read/Execute (can't delete system files)
- Size: ~10-15 GB initially

**What Gets Here & Why**:

- Phase scripts must be on C: to run during startup
- HELIOS needs centralized command center
- On system drive for faster access
- Backed up regularly

### C:\Program Files\

**Purpose**: Installed applications (already exists, created by Windows)

```
C:\Program Files\
├── HELIOS Tools\                        # HELIOS utilities
│   ├── system-monitor.exe
│   ├── config-manager.exe
│   └── tools/
│
├── Common Files\                        # Shared libraries
├── Application Data\                    # App-specific data
└── [Other applications installed]
```

**Permissions**:

- Owner: SYSTEM
- User: Read/Execute
- Size: Grows as applications installed

**What Gets Here & Why**:

- Standard Windows convention for programs
- Central location for all apps
- Protected from accidental deletion

### C:\Windows\

**Purpose**: Core Windows operating system (already exists)

```
C:\Windows\
├── System32/                            # Critical system files
│   ├── drivers/                         # Device drivers
│   ├── config/                          # Registry backup
│   ├── driverstore/                     # Driver storage
│   └── [~10,000 system files]
│
├── SysWOW64/                            # 32-bit compatibility
├── Temp/                                # Temporary files
├── System32\config\                     # Registry hives
│   ├── SAM                              # User accounts
│   ├── SECURITY                         # Security settings
│   ├── SOFTWARE                         # Software configs
│   ├── SYSTEM                           # System config
│   └── DEFAULT                          # Default user profile
│
├── WinSxS/                              # Side-by-side assemblies
├── AppCompat/                           # Compatibility info
└── Prefetch/                            # Performance optimization
```

**Permissions**:

- Owner: SYSTEM
- User: Limited (read only)
- Size: ~25-30 GB

**What Gets Here & Why**:

- This is where Windows MUST be installed
- Cannot be changed during Phase 0
- Protected from user modification

### C:\ProgramData\

**Purpose**: Application data shared across all users

```
C:\ProgramData\
├── Microsoft\                           # Microsoft applications
├── HELIOS\                              # HELIOS shared config
│   ├── settings/
│   ├── cache/
│   └── shared-resources/
│
└── [Other apps' shared data]
```

**Permissions**:

- Owner: SYSTEM
- Apps: Read/Write
- Users: Read only

**What Gets Here & Why**:

- Shared between all user accounts
- Programs need centralized configuration
- Not backed up to user profiles

### C:\Users\[Username]\AppData\

**Purpose**: Per-user application data

```
C:\Users\ADMIN\AppData\
├── Local/                               # Local machine only
│   ├── HELIOS\                          # HELIOS user config
│   ├── Temp\                            # User temp files
│   └── Cache\
│
├── LocalLow/                            # Low-integrity temp
│
└── Roaming/                             # Roams with user (if networked)
    └── HELIOS\
        ├── preferences/
        └── user-config/
```

**Permissions**:

- Owner: User (ADMIN)
- User: Full access
- Others: No access

**What Gets Here & Why**:

- User-specific settings stored here
- Separate from system settings
- Can be backed up per-user
- Size: ~500 MB - 2 GB per user

---

## D: Drive - Data Drive

The D: drive stores user files, documents, and backups.

### D:\Users\

**Purpose**: Personal user files and documents

```
D:\Users\ADMIN\
├── Documents/                           # Office documents
│   ├── HELIOS/                          # Phase documentation
│   ├── Projects/                        # Work projects
│   └── Archive/                         # Old documents
│
├── Downloads/                           # Downloaded files
│   └── ISOs/                            # Installation files
│
├── Pictures/                            # Image files
│
├── Videos/                              # Video files
│
├── Desktop/                             # Desktop shortcuts/files
│
├── Music/                               # Audio files
│
└── AppData/                             # User application data
    ├── Local/
    └── Roaming/
```

**Permissions**:

- Owner: User (ADMIN)
- User: Full access
- Others: No access (or read-only)

**Size**: Grows with user files (0 - unlimited)

**What Gets Here & Why**:

- Separated from system drive for safety
- Easy to back up as single unit
- If C: fails, D: data survives
- Standard Windows user data location

### D:\Backups\

**Purpose**: System and data backups

```
D:\Backups\
├── System/                              # Windows system backups
│   ├── winsysimg-2024-01-15/
│   ├── registry-backup-2024-01-15/
│   └── boot-files-backup/
│
├── Configuration/                       # Config file backups
│   ├── registry-exports/
│   └── app-settings/
│
├── Data/                                # User data backups
│   ├── weekly-full/
│   ├── daily-incremental/
│   └── archive/
│
└── Recovery/                            # Recovery media
    ├── windows-recovery/
    └── boot-disks/
```

**Permissions**:

- Owner: SYSTEM and ADMIN
- User: Read/Write for management
- Others: No access

**Size**: 100 GB - 300 GB+ depending on backup strategy

**What Gets Here & Why**:

- On separate drive for redundancy
- Can be backed up to external storage
- Never deleted during Windows reinstall
- System Restore points kept here

### D:\Projects\

**Purpose**: Active work projects

```
D:\Projects\
├── HELIOS-Platform/                     # HELIOS development
│   ├── Phase-0-Documentation/
│   ├── Phase-1-Customization/
│   └── scripts/
│
├── [Other Projects]/
│
└── Archive/                             # Completed projects
    └── [Old Projects]/
```

**Permissions**:

- Owner: User/Project owner
- Collaborators: Shared access if needed
- Others: No access

**What Gets Here & Why**:

- Active work stays accessible on D:
- Separates in-progress from completed work
- Can be backed up to external storage
- Survives OS reinstall

### D:\Archive\

**Purpose**: Old files and historical data

```
D:\Archive\
├── 2023/
│   ├── Projects/
│   ├── Documents/
│   └── Media/
│
├── 2022/
│
└── [Other years]/
```

**Permissions**:

- Owner: User
- Access: Read-only (prevents accidental deletion)
- Others: No access

**What Gets Here & Why**:

- Historical data kept for reference
- Not actively used but kept for records
- Can be archived to external storage
- Separated from active files

---

## Registry Structure

### HKEY_LOCAL_MACHINE (HKLM) - System-wide settings

```
HKLM:\SYSTEM\
└── CurrentControlSet\
    └── Services\                        # Windows services
        ├── (Service status/config)
        ├── (Startup type - Automatic/Manual/Disabled)
        └── (Triggers and dependencies)

HKLM:\SOFTWARE\
├── Microsoft\
│   ├── Windows\                         # Windows configuration
│   ├── WindowsNT\CurrentVersion\        # OS version info
│   └── [Installed software]
│
└── HELIOS\                              # HELIOS settings
    ├── Phase0/
    ├── Configuration/
    └── Baseline/
```

**Permissions**:

- SYSTEM: Full access
- Administrators: Full access
- Users: Read only (mostly)

**What Gets Here & Why**:

- System-wide settings must be here
- Cannot be changed by regular users
- Critical to Windows operation
- Backed up automatically

### HKEY_CURRENT_USER (HKCU) - User settings

```
HKCU:\Software\
├── Microsoft\
│   ├── Windows\                         # User's Windows config
│   ├── Office\                          # Office app settings
│   └── [User's programs]
│
└── HELIOS\                              # HELIOS user settings
    ├── Preferences/
    └── UserConfig/
```

**Permissions**:

- Current User: Full access
- Others: No access

**What Gets Here & Why**:

- User-specific preferences stored here
- Roams if in network domain
- Backed up as part of user profile
- Different for each user account

---

## Configuration File Locations

### Phase 0 Specific Configs

```
C:\HELIOS\config\phase0-baseline.json    # Phase 0 settings
C:\HELIOS\config\partition-layout.json   # Partition configuration
C:\HELIOS\config\storage-folders.json    # Folder structure config
```

**Format**: JSON for easy reading and parsing

**Backed Up**: Yes, in C:\HELIOS\backups\config-backups\

### Application Configs

```
C:\ProgramData\HELIOS\                   # Shared app config
C:\Users\ADMIN\AppData\Local\HELIOS\     # User-specific config
C:\Users\ADMIN\AppData\Roaming\HELIOS\   # Roaming config
```

**Format**: JSON, INI, or XML depending on app

---

## Log File Locations

### Phase 0 Logs

```
C:\HELIOS\logs\phase0\
├── usb-creator-20240115.log             # USB creation log
├── partition-manager-20240115.log       # Partition log
├── storage-setup-20240115.log           # Storage setup log
├── system-baseline-20240115.log         # Baseline config log
└── errors/                              # Error logs
    └── error-20240115.log

C:\Windows\Logs\                         # Windows system logs
├── System\                              # System events
├── Security\                            # Security events
└── Application\                         # App events
```

**Format**: Structured text (PSLogParser format for PowerShell logs)

**Retention**:

- Recent (current month): C:\HELIOS\logs\
- Archived (by month): D:\Backups\Logs\Archive\

### System Event Logs

Visible in Event Viewer:

```
Windows Logs\
├── System                               # Hardware, driver, services
├── Security                             # Login, permissions
├── Application                          # Program events
└── Setup                                # Windows setup/update

Applications and Services Logs\
├── HELIOS\                              # HELIOS-specific events
└── Microsoft\Windows\                   # Windows subsystem logs
```

---

## Environmental Variables Used

```
%SYSTEMROOT%        → C:\Windows\                     (Windows location)
%SYSTEMDRIVE%       → C:\                             (System drive letter)
%PROGRAMFILES%      → C:\Program Files\               (64-bit apps)
%PROGRAMFILES(X86)% → C:\Program Files (x86)\        (32-bit apps)
%APPDATA%           → C:\Users\[User]\AppData\Roaming\ (User data)
%LOCALAPPDATA%      → C:\Users\[User]\AppData\Local\  (Local user data)
%ALLUSERSPROFILE%   → C:\ProgramData\                (Shared app data)
%TEMP%              → C:\Users\[User]\AppData\Local\Temp\ (Temp files)
%USERPROFILE%       → C:\Users\[User]\                (User home)
```

---

## Important Hidden Folders

Shown if "Show hidden files" is enabled in File Explorer:

```
C:\$Recycle.Bin\                        # Recycle bin
C:\ProgramData\                         # Hidden by default
C:\Users\[User]\AppData\                # Hidden by default
D:\System Volume Information\           # Hidden by default
```

**Why Hidden**:

- Prevent accidental deletion
- Keep user interface cleaner
- System internals

---

## Storage Summary Table

| Location | Purpose | Size | Backup? | Backed to |
|----------|---------|------|---------|-----------|
| C:\HELIOS | HELIOS core | ~10-15 GB | Yes | D:\Backups |
| C:\Program Files | Applications | ~50-200 GB | Sometimes | External |
| C:\Windows | OS | ~25-30 GB | Yes | D:\Backups |
| C:\Users\AppData | User config | ~500 MB - 2 GB | Yes | User backup |
| D:\Users | User files | 0 - unlimited | Yes | External |
| D:\Backups | System backups | 100-300+ GB | Yes | External |
| D:\Projects | Active work | Variable | Yes | External |
| D:\Archive | Historical data | Variable | As needed | External |

---

## Backup Strategy

### What Gets Backed Up (Phase 0)

```
AUTOMATIC (handled by HELIOS):
├── C:\HELIOS\        → D:\Backups\system\
├── Registry          → D:\Backups\registry-backup\
└── System config     → D:\Backups\configuration\

MANUAL (user responsibility):
├── D:\Users\         → External storage
├── D:\Projects\      → External storage
└── D:\Archive\       → External storage (optional)
```

### Backup Locations

```
Primary:    D:\Backups\                  (on-system backup)
Secondary:  External USB/Drive           (off-system backup)
Cloud:      Cloud storage (optional)     (cloud backup)
```

---

## Quick Reference Path Map

| Need | Path |
|------|------|
| Phase 0 scripts | C:\HELIOS\phases\0-foundation\scripts\ |
| Phase 0 docs | C:\HELIOS\phases\0-foundation\ |
| HELIOS config | C:\HELIOS\config\ |
| HELIOS logs | C:\HELIOS\logs\ |
| User docs | D:\Users\ADMIN\Documents\ |
| Backups | D:\Backups\ |
| Downloads | D:\Users\ADMIN\Downloads\ |
| Windows system | C:\Windows\ |
| Installed programs | C:\Program Files\ |
| App configs | C:\ProgramData\HELIOS\ |
| User app data | C:\Users\ADMIN\AppData\ |
| Temp files | C:\Users\ADMIN\AppData\Local\Temp\ |

---

**Next Step**: Review `SCRIPTS_INDEX.md` to see all Phase 0 scripts available.
