# Windows System Paths & HELIOS File Placement

## Standard Windows Directory Structure

### System Directories

#### C:\Windows\System32\

**Purpose**: 64-bit system binaries, drivers, and configuration files

**HELIOS Usage**:

- HELIOS system drivers → `C:\Windows\System32\drivers\`
- HELIOS system services → `C:\Windows\System32\` (DLL/EXE files)
- Firewall rules database → `C:\Windows\System32\drivers\etc\` (hosts, rules)
- Event logs → `C:\Windows\System32\winevt\Logs\` (security, system, application)

**Example Paths**:

```
C:\Windows\System32\drivers\etc\hosts                    # Firewall/DNS rules
C:\Windows\System32\winevt\Logs\Security.evtx           # Security event log
C:\Windows\System32\winevt\Logs\System.evtx             # System event log
C:\Windows\System32\config\SAM                           # User accounts database
C:\Windows\System32\config\SECURITY                      # Security policies
C:\Windows\System32\config\SOFTWARE                      # Software registry hive
C:\Windows\System32\config\SYSTEM                        # System registry hive
```

**Access**: Admin/SYSTEM required

---

#### C:\Windows\SysWOW64\

**Purpose**: 32-bit system binaries (compatibility layer on 64-bit Windows)

**HELIOS Usage**:

- 32-bit drivers → `C:\Windows\SysWOW64\drivers\`
- 32-bit system services → `C:\Windows\SysWOW64\` (legacy components)
- 32-bit AppLocker policies reference this

**Example Paths**:

```
C:\Windows\SysWOW64\drivers\etc\hosts                    # 32-bit hosts file
C:\Windows\SysWOW64\drivers\                             # 32-bit device drivers
```

**Access**: Admin/SYSTEM required

**Note**: Windows automatically maintains both 64-bit and 32-bit versions; creating a file in System32 does NOT automatically copy to SysWOW64.

---

### Application Directories

#### C:\Program Files\ (64-bit Only)

**Purpose**: 64-bit application binaries and resources

**HELIOS Usage**:

```
C:\Program Files\HELIOS\
├── Dashboard\                    # Dashboard application
│   ├── Dashboard.exe
│   ├── Dashboard.config
│   └── resources\
├── Core\                         # Core HELIOS libraries
│   ├── HELIOS.Core.dll
│   ├── HELIOS.Security.dll
│   └── HELIOS.Optimization.dll
├── AI-Engine\                    # AI processing (64-bit)
│   ├── AIEngine.exe
│   └── dependencies\
└── bin\                          # Utilities and tools
    ├── HeliosAdmin.exe
    └── HeliosMonitor.exe
```

**Access**: Admin required for installation; user access for running

**Size**: ~500 MB typical installation

---

#### C:\Program Files (x86)\ (32-bit Legacy)

**Purpose**: 32-bit application binaries (if supporting legacy systems)

**HELIOS Usage** (Optional):

```
C:\Program Files (x86)\HELIOS\
├── Legacy-Components\           # 32-bit compatibility components
└── Support-Tools\
```

**Note**: HELIOS is primarily 64-bit; this is optional for legacy support.

**Access**: Admin required

---

### User Data Directories

#### C:\Users\[USERNAME]\AppData\Local\

**Purpose**: User-specific, machine-specific application data

**Characteristics**:

- Per-user, per-machine (not roamed)
- Typically smaller, ephemeral data
- Survives user account rename
- **Does NOT sync** between machines

**HELIOS Usage**:

```
C:\Users\[USERNAME]\AppData\Local\HELIOS\
├── Vault\
│   ├── Vault.db                 # Vault database (encrypted)
│   ├── Vault.config
│   └── certificates\            # User certificates
├── Cache\
│   ├── ProfileCache.db
│   ├── WorkflowCache.json
│   └── temp\
├── Logs\
│   ├── Dashboard.log
│   └── local-operations.log
└── Temp\
    └── analysis-temp\           # Temporary analysis files
```

**Example Paths**:

```
C:\Users\Administrator\AppData\Local\HELIOS\Vault\Vault.db
C:\Users\jsmith\AppData\Local\HELIOS\Cache\ProfileCache.db
```

**Access**: User owns directory; full access

**Size**: Typically <100 MB (watch database growth)

---

#### C:\Users\[USERNAME]\AppData\Roaming\

**Purpose**: User-specific, machine-independent application data

**Characteristics**:

- Per-user (synced across machines on domain)
- User preferences, settings, profiles
- Persists through user account rename (file migration)
- **CAN sync** between machines via roaming profiles

**HELIOS Usage**:

```
C:\Users\[USERNAME]\AppData\Roaming\HELIOS\
├── Profiles\
│   ├── Default.profile.json
│   ├── Security-Locked.profile.json
│   └── user-custom.profile.json
├── Workflows\
│   ├── DailyOptimization.workflow.json
│   └── SecurityScan.workflow.json
├── Settings\
│   ├── Dashboard.settings.xml
│   └── Preferences.config
└── Desktop-Links\                # Shortcut references
    └── shortcuts.json
```

**Example Paths**:

```
C:\Users\Administrator\AppData\Roaming\HELIOS\Profiles\
C:\Users\jsmith\AppData\Roaming\HELIOS\Settings\Dashboard.settings.xml
```

**Access**: User owns directory; full access

**Size**: Typically <50 MB

---

#### C:\Users\[USERNAME]\Desktop\

**Purpose**: User desktop shortcuts and files

**HELIOS Usage**:

```
C:\Users\[USERNAME]\Desktop\
├── HELIOS Dashboard.lnk          # Shortcut to Dashboard.exe
├── System Analysis Report.lnk    # Shortcut to last report
└── Vault Quick Access.lnk        # Shortcut to Vault
```

**Access**: User owns; full access

---

#### C:\Users\[USERNAME]\AppData\Local\Temp\

**Purpose**: Temporary files for current user

**HELIOS Usage**:

- Phase 2 cleanup operations manage this
- Temporary analysis scratch files
- Cache files from previous runs

**Access**: User owns; full access

**Note**: Windows automatically cleans old files; HELIOS may accelerate cleanup.

---

#### C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\

**Purpose**: Programs to run at user login

**HELIOS Usage**:

```
C:\Users\[USERNAME]\AppData\Roaming\Microsoft\Windows\Start Menu\Startup\
├── HELIOS-Monitor.lnk           # Monitor service startup (Phase 2)
└── HELIOS-Vault-Monitor.lnk     # Vault monitoring (Phase 1)
```

**Access**: User owns; full access

**Note**: These run when user logs in (not system startup)

---

### System-Wide Data Directory

#### C:\ProgramData\

**Purpose**: System-wide application data accessible to all users

**Characteristics**:

- All-user accessible
- System-level configuration
- Persistent across reboots
- Requires admin to modify

**HELIOS Main Structure**:

```
C:\ProgramData\HELIOS\
├── Foundation\                   # Phase 0 files
│   ├── USBCreator\
│   ├── Baselines\
│   └── InstallScripts\
├── Security\                     # Phase 1 files
│   ├── AppLocker\
│   ├── Firewall\
│   ├── Quarantine\
│   └── Policies\
├── Optimization\                 # Phase 2 files
│   ├── Services\
│   ├── Startup\
│   └── Profiles\
├── Capability\                   # Phase 3 files
│   ├── AI-Models\
│   ├── Dashboard-Config\
│   ├── Workflows\
│   └── Reports\
├── Database\
│   ├── master.db                 # Central database
│   ├── audit.db                  # Audit logs
│   └── backups\
├── Logs\
│   ├── Phase0.log
│   ├── Phase1.log
│   ├── Phase2.log
│   ├── Phase3.log
│   └── System.log
└── Config\
    ├── HELIOS.config.xml         # Main configuration
    └── encryption.config          # Encryption settings
```

**Example Paths**:

```
C:\ProgramData\HELIOS\Security\Quarantine\             # Quarantined files
C:\ProgramData\HELIOS\Capability\AI-Models\            # AI model files
C:\ProgramData\HELIOS\Database\master.db               # Central database
C:\ProgramData\HELIOS\Logs\Phase3.log                  # Phase 3 operations log
```

**Access**: Admin to create/modify; everyone can read

**Size**: Grows over time; monitor database and logs

---

### Temporary Directories

#### C:\Windows\Temp\

**Purpose**: System-wide temporary files

**HELIOS Usage**:

- Phase 2 cleanup operations target this
- Temporary installation files during Phase 0
- Diagnostic dumps

**Access**: Admin/SYSTEM manages this; user readable

**Note**: Windows can delete files here; not for persistent storage

---

### System Temporary Directory

#### %TEMP% Environment Variable

**Purpose**: User-specific temporary directory

**Resolves To**:

```
C:\Users\[USERNAME]\AppData\Local\Temp\
```

**HELIOS Usage**:

- Temporary analysis files
- Phase 2 cleanup manages this
- Cache operations

---

## Registry Structure

### HKEY_LOCAL_MACHINE (HKLM)

**Purpose**: Machine-wide configuration, system policies

**Location**: `C:\Windows\System32\config\SYSTEM` (hive file)

**HELIOS Usage**:

```
HKLM:\Software\
├── Policies\Microsoft\Windows\
│   └── SrpV2\                   # AppLocker policies
├── Policies\Microsoft\Windows Defender\
│   └── Real-time Protection\    # Antivirus settings
└── HELIOS\
    ├── Foundation\              # Phase 0 config
    ├── Security\                # Phase 1 config
    ├── Optimization\            # Phase 2 config
    └── Capability\              # Phase 3 config

HKLM:\SYSTEM\
├── CurrentControlSet\Services\ # Service definitions
├── CurrentControlSet\Control\ # System controls
└── CurrentVersion\             # System version info
```

**Access**: Admin/SYSTEM required

**Persistence**: Permanent until explicitly deleted

---

### HKEY_CURRENT_USER (HKCU)

**Purpose**: User-specific configuration

**Location**: `C:\Users\[USERNAME]\NTUSER.DAT` (hive file)

**HELIOS Usage**:

```
HKCU:\Software\
├── HELIOS\
│   ├── Dashboard\Settings
│   ├── Profiles\LastUsed
│   └── Notifications\
├── Microsoft\Windows\
│   └── CurrentVersion\Explorer\ # User shell folders
```

**Access**: User has full access; others restricted

**Persistence**: Permanent until explicitly deleted

---

## Access Level Summary

| Location | Access Level | HELIOS Requirement |
|----------|--------------|-------------------|
| C:\Windows\System32\ | Admin/SYSTEM | Install drivers, security policies |
| C:\Windows\SysWOW64\ | Admin/SYSTEM | 32-bit compatibility |
| C:\Program Files\ | Admin | Install application binaries |
| C:\Program Files (x86)\ | Admin | 32-bit legacy components |
| C:\Users\[USERNAME]\AppData\Local\ | User | Store user vaults, local cache |
| C:\Users\[USERNAME]\AppData\Roaming\ | User | Store user profiles, settings |
| C:\ProgramData\ | Admin | Store system-wide data |
| HKLM:\ | Admin/SYSTEM | System policies, services |
| HKCU:\ | User | User preferences |

---

## Storage Planning

### Typical Space Usage

| Component | Size | Location |
|-----------|------|----------|
| HELIOS binaries | ~300 MB | C:\Program Files\HELIOS\ |
| AI models (Phase 3) | ~400-800 MB | C:\ProgramData\HELIOS\AI-Models\ |
| Databases | ~100-500 MB | C:\ProgramData\HELIOS\Database\ |
| Logs (6 months) | ~50-200 MB | C:\ProgramData\HELIOS\Logs\ |
| User vault (per user) | ~10-50 MB | C:\Users\[USERNAME]\AppData\Local\HELIOS\ |
| **Total per system** | **~1-2 GB** | Various locations |

### Recommendations

- **System Drive**: Ensure 5 GB free minimum before installation
- **Database Growth**: Monitor quarterly; archive old logs to external storage
- **User Vaults**: Each active vault ~20-50 MB; plan for 5-10 users typical
- **AI Models**: Don't store on network shares; use local SSD for performance

---

## Common Path References

| Shorthand | Expands To | Usage |
|-----------|-----------|-------|
| %SystemRoot% | C:\Windows\ | System directory |
| %System32% | C:\Windows\System32\ | System binaries |
| %ProgramFiles% | C:\Program Files\ | 64-bit apps |
| %ProgramFiles(x86)% | C:\Program Files (x86)\ | 32-bit apps |
| %APPDATA% | C:\Users\[USERNAME]\AppData\Roaming\ | Roaming data |
| %LOCALAPPDATA% | C:\Users\[USERNAME]\AppData\Local\ | Local data |
| %TEMP% | C:\Users\[USERNAME]\AppData\Local\Temp\ | Temp files |
| %WINDIR% | C:\Windows\ | Windows directory |
| %PROGRAMDATA% | C:\ProgramData\ | All-user data |

---

## Permission Model

### File Ownership

- **System32, System Drivers**: Owned by SYSTEM
- **Program Files**: Owned by TrustedInstaller
- **ProgramData**: Owned by SYSTEM or Administrators
- **User AppData**: Owned by user

### Typical Permission Structure

```
C:\Program Files\HELIOS\
├── SYSTEM: Read, Execute
├── Administrators: Read, Write, Execute
└── Users: Read, Execute

C:\ProgramData\HELIOS\
├── SYSTEM: Full Control
├── Administrators: Full Control
└── Users: Read, Execute (not write)

C:\Users\[USERNAME]\AppData\Local\HELIOS\
├── [USERNAME]: Full Control
├── SYSTEM: Read, Execute
└── Administrators: Full Control
```

---

## Next Steps

- See **PHASE_X_FILE_LOCATIONS.md** for specific phase file placement
- See **REGISTRY_CHANGES.md** for registry key modifications
- See **DIRECTORY_TREE.md** for complete structure visualization
