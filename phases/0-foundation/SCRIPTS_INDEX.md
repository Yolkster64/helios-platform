# HELIOS Phase 0: Scripts Index

Complete list of all Phase 0 scripts with descriptions and quick reference.

---

## Quick Reference Table

| Script | Purpose | Run | Admin? | Time |
|--------|---------|-----|--------|------|
| usb-creator.ps1 | Create Windows 11 bootable USB | 1st | Yes | 10-20m |
| windows-installer.ps1 | Install Windows on computer | 2nd | Yes | 20-30m |
| partition-manager.ps1 | Set up disk partitions (C:, D:) | 3rd | Yes | 5-10m |
| storage-setup.ps1 | Create folder structure | 4th | Yes | 2-5m |
| system-baseline.ps1 | Configure system baseline | 5th | Yes | 5-10m |

---

## Detailed Script Descriptions

### 1. usb-creator.ps1

**Location**: `C:\HELIOS\phases\0-foundation\scripts\usb-creator.ps1`

**Purpose**: Creates a bootable Windows 11 installation USB drive

**What It Does**:

- Takes Windows 11 ISO file
- Copies files to USB drive
- Makes USB bootable
- Validates installation media

**Dependencies**: Windows 11 ISO file (7GB+)

**Inputs** (Script Prompts You For):

```
1. Path to Windows 11 ISO file
   Example: D:\Downloads\Windows11.iso

2. USB drive letter
   Example: E:

3. Confirmation to erase USB
   Example: Y (yes, erase it)
```

**Outputs Created**:

- Bootable USB drive with Windows 11 files
- No files created on your computer
- USB becomes unusable for regular storage

**Exit Codes**:

```
0 = Success (USB created)
1 = ISO file not found
2 = USB drive not found
3 = User cancelled
4 = Write error to USB
```

**Estimated Runtime**: 10-20 minutes

**Command**:

```powershell
# Run as Administrator
cd C:\HELIOS\phases\0-foundation\scripts
.\usb-creator.ps1
```

**Related Files**:

- Reads: Windows 11 ISO file (your Downloads folder typically)
- Writes: USB drive (all data erased)
- Logs: C:\HELIOS\logs\phase0\usb-creator-[DATE].log

---

### 2. windows-installer.ps1

**Location**: `C:\HELIOS\phases\0-foundation\scripts\windows-installer.ps1`

**Purpose**: Performs fresh Windows 11 installation

**What It Does**:

- Starts Windows Setup wizard
- Guides you through installation
- Installs Windows to selected drive
- Creates initial system partitions

**Dependencies**:

- Bootable USB (from usb-creator.ps1)
- Blank or wipeable hard drive
- 30-60 minutes free
- Restart capability

**How To Execute**:

1. Insert USB created by usb-creator.ps1
2. Restart computer
3. Press boot menu key (F12, F2, ESC, DEL)
4. Select USB drive
5. Follow Windows Setup wizard
6. Accept license, select drive, wait

**Inputs** (Windows Setup Asks You For):

```
1. Accept Windows 11 License
   Choose: Accept

2. Which drive to install on?
   Choose: Usually C: or largest drive

3. User account creation
   Enter: Username, password

4. Express or Custom settings?
   Choose: Express (simpler) or Custom (detailed)
```

**Outputs Created**:

- Fresh Windows 11 installation
- System partitions created
- New user account created
- Empty program folders
- ~30 GB used on drive

**Estimated Runtime**: 20-30 minutes for installation + 10-15 min initial setup

**Important Notes**:

- Computer will restart multiple times (normal)
- Screen may go black briefly (normal)
- No user input needed during copying phase
- Internet helpful (but not required)

**Troubleshooting**:

- If USB won't boot: Try different USB port; check BIOS boot order
- If installation fails: Try different USB drive; verify ISO integrity
- If slow: Using USB 2.0 port (try USB 3.0); older USB drive

**Related Files**:

- Reads: USB drive (Windows installation files)
- Writes: Hard drive (entire drive if not partitioned)
- Logs: C:\Windows\Logs\Setup\

---

### 3. partition-manager.ps1

**Location**: `C:\HELIOS\phases\0-foundation\scripts\partition-manager.ps1`

**Purpose**: Sets up disk partitions (C: system, D: data)

**What It Does**:

- Analyzes current disk layout
- Creates system partition (C:)
- Creates data partition (D:)
- Creates recovery partition
- Formats and assigns drive letters

**Dependencies**:

- Windows installed and running
- Administrator access
- At least 100GB free space
- Admin PowerShell session

**Inputs** (Script Prompts You For):

```
1. Which disk to partition? (usually Disk 0)
   Choose: 0, 1, 2, etc.

2. How big should C: drive be? (in GB)
   Default: 150 GB
   Range: 100-500 GB

3. Rest goes to D: drive (automatic)
   Remaining space becomes D:
   Example: 500GB disk = C:150GB + D:350GB

4. Proceed? (warning displayed)
   Choose: Y (yes) or N (no)
```

**Outputs Created**:

```
Partition Layout:
├── C: drive (System)
│   ├── EFI System (100 MB, hidden)
│   ├── Windows Installation (~25 GB)
│   ├── Program Files
│   ├── Remaining space
│
├── D: drive (Data)
│   └── User files and backups
│
└── Recovery partition (hidden)
```

**System Changes**:

- C: drive formatted NTFS
- D: drive formatted NTFS
- Drive letters assigned (C: and D:)
- Recovery partition created

**Exit Codes**:

```
0 = Success (partitions created)
1 = Disk not found
2 = Insufficient space
3 = User cancelled
4 = Partitioning error
```

**Estimated Runtime**: 5-15 minutes (depending on drive size)

**Command**:

```powershell
# Run as Administrator
cd C:\HELIOS\phases\0-foundation\scripts
.\partition-manager.ps1
```

**Important Notes**:

- May require restart to apply changes
- Drive letters change may happen (D: might become E:)
- Recovery partition is hidden (normal)
- Can be run again to adjust sizes

**Related Files**:

- Reads: Disk configuration
- Writes: Partition table, drive formatting
- Logs: C:\HELIOS\logs\phase0\partition-manager-[DATE].log

---

### 4. storage-setup.ps1

**Location**: `C:\HELIOS\phases\0-foundation\scripts\storage-setup.ps1`

**Purpose**: Creates folder structure for file organization

**What It Does**:

- Creates C:\HELIOS\ directory tree
- Creates D:\Users\ folder structure
- Creates D:\Backups\ structure
- Sets folder permissions
- Verifies folder creation

**Dependencies**:

- Windows installed and running
- C: and D: drives exist
- Administrator access
- PowerShell admin session

**Inputs** (Script Prompts You For):

```
1. Confirm folder creation?
   Shows: Summary of folders to create
   Choose: Y (yes) or N (no)

2. Set user permissions? (optional)
   Default: Current user gets access
   Choose: Y or N
```

**Outputs Created**:

```
On C: drive:
├── C:\HELIOS\phases\
├── C:\HELIOS\tools\
├── C:\HELIOS\config\
├── C:\HELIOS\logs\
├── C:\HELIOS\backups\
└── C:\HELIOS\docs\

On D: drive:
├── D:\Users\[username]\Documents\
├── D:\Users\[username]\Downloads\
├── D:\Users\[username]\Pictures\
├── D:\Users\[username]\Videos\
├── D:\Backups\System\
├── D:\Backups\Configuration\
├── D:\Backups\Data\
├── D:\Projects\
└── D:\Archive\
```

**Total Folders**: ~30 main + subfolders

**Folder Permissions Set**:

- Current user (ADMIN): Full control
- SYSTEM: Full control
- Other users: None (private folders)

**Exit Codes**:

```
0 = Success (all folders created)
1 = Drives not found
2 = Insufficient permissions
3 = User cancelled
4 = Folder creation error
```

**Estimated Runtime**: 2-5 minutes

**Command**:

```powershell
# Run as Administrator
cd C:\HELIOS\phases\0-foundation\scripts
.\storage-setup.ps1
```

**Important Notes**:

- Safe to run multiple times (skips existing folders)
- No data loss (just creates empty folders)
- Creates hidden folders if needed
- Sets up for future phases

**Related Files**:

- Reads: Disk information
- Writes: Creates folders only (no files)
- Logs: C:\HELIOS\logs\phase0\storage-setup-[DATE].log

---

### 5. system-baseline.ps1

**Location**: `C:\HELIOS\phases\0-foundation\scripts\system-baseline.ps1`

**Purpose**: Configures initial system settings and baseline

**What It Does**:

- Enables required Windows features
- Disables unnecessary services
- Configures power settings
- Sets security baselines
- Creates system restore point
- Validates configuration

**Dependencies**:

- Windows 11 installed
- Administrator access
- PowerShell admin session
- Internet recommended (for updates)

**Inputs** (Script Prompts You For):

```
1. Windows version check
   Requirement: Windows 11 (will fail on earlier versions)

2. Proceed with baseline configuration?
   Shows: Summary of changes
   Choose: Y (yes) or N (no)

3. Restart required?
   Some changes need restart
   Choose: Yes (now) or No (later)
```

**Outputs Created**:

**Windows Features Enabled**:

```
- Hyper-V (virtualization)
- Windows Sandbox (isolated environment)
- .NET Framework 3.5 (legacy app support)
- Windows Subsystem for Linux (WSL2)
- Virtual Machine Platform
- Containers support
- BitLocker support
```

**Services Modified**:

```
Disabled (for performance):
- Search Indexer
- Cortana background process
- OneDrive sync
- Advertising ID
- Telemetry (partially)

Enabled (for security/function):
- Windows Defender
- Windows Update
- Device Guard
- Credential Guard
- Firewall
```

**Settings Changed**:

```
Power Plan: High Performance
- Sleep: Disabled
- Hibernate: Disabled
- USB selective suspend: Enabled
- Wake timers: Disabled

Display:
- Show hidden files: Enabled
- Show file extensions: Enabled
- Visual effects: Performance mode

Updates:
- Windows Update: Automatic
- Download updates: Automatic

Security:
- Windows Defender: Active
- Firewall: Enabled
- UAC: Standard
```

**System Changes**:

- Registry modifications
- Service startup types changed
- Group Policy updates
- Power settings changed
- User Account Control configured

**Exit Codes**:

```
0 = Success (baseline configured)
1 = Not Windows 11
2 = Not running as Administrator
3 = User cancelled
4 = Configuration error
```

**Estimated Runtime**: 5-15 minutes

**Command**:

```powershell
# Run as Administrator
cd C:\HELIOS\phases\0-foundation\scripts
.\system-baseline.ps1
```

**Important Notes**:

- System may restart automatically
- Changes are comprehensive (affects many settings)
- Restore point created (can revert if needed)
- Safe to run multiple times (idempotent)

**Recovery**:

- Restore point: "HELIOS-Phase0-Baseline" created before changes
- Can revert via System Restore if needed
- No permanent changes (all reversible)

**Related Files**:

- Reads: Current system configuration
- Writes: Registry, services, settings
- Creates: System Restore Point
- Logs: C:\HELIOS\logs\phase0\system-baseline-[DATE].log

---

## Execution Order

**Must follow this sequence**:

```
1. usb-creator.ps1
   ↓ (Wait for completion, creates USB)
   
2. windows-installer.ps1
   ↓ (Boot from USB, install Windows)
   
3. partition-manager.ps1
   ↓ (Run on installed Windows)
   
4. storage-setup.ps1
   ↓ (Creates folder structure)
   
5. system-baseline.ps1
   ↓ (Final configuration)
   
Ready for Phase 1
```

**Can Skip?**

- USB Creator: Only if already have bootable media
- Windows Installer: Only if Windows already fresh-installed
- Partition Manager: Only if already have C: and D: drives
- Storage Setup: Only if folders already created
- System Baseline: Recommended to always run (safe to re-run)

**Run Together?**

- No. Each depends on previous step's output.
- Must complete one fully before starting next.
- Exception: Can re-run same script multiple times.

---

## Error Handling

### Common Errors & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| "Access Denied" | Not admin | Right-click PowerShell → Run as Administrator |
| "File not found" | Script path wrong | Use `cd` to navigate to correct folder |
| "USB not found" | Drive disconnected | Plug USB in, wait 5 seconds, retry |
| "Insufficient space" | Drive too small | Need larger drive or resize |
| "Registry error" | Permissions issue | Run as Administrator, disable antivirus |
| "Timeout" | Script taking too long | Wait longer, check for user prompts |

### Log Locations for Troubleshooting

```
C:\HELIOS\logs\phase0\
├── usb-creator-[DATE].log
├── partition-manager-[DATE].log
├── storage-setup-[DATE].log
└── system-baseline-[DATE].log
```

**View Logs**:

```powershell
# See recent logs
Get-ChildItem C:\HELIOS\logs\phase0\ | Sort-Object LastWriteTime -Descending

# Read specific log
Get-Content C:\HELIOS\logs\phase0\usb-creator-20240115.log

# Search logs for errors
Select-String -Path "C:\HELIOS\logs\phase0\*.log" -Pattern "ERROR"
```

---

## Script Features

### All Phase 0 Scripts Include:

✓ **Verbose logging** - All actions recorded  
✓ **Error handling** - Graceful failure with messages  
✓ **Validation** - Checks prerequisites before running  
✓ **Confirmation prompts** - Ask before making changes  
✓ **Progress display** - Shows what's happening  
✓ **Restore points** - Create backups of critical state  
✓ **Rollback info** - Tell you how to undo  
✓ **Exit codes** - Indicate success or failure  

### All Scripts Are Safe To Re-Run:

- Check if action already done
- Skip if not needed
- Won't double-apply changes
- Idempotent design

---

## Performance Notes

**Fastest Sequence on SSD**:

- usb-creator: ~10 min
- windows-installer: ~20 min
- partition-manager: ~5 min
- storage-setup: ~2 min
- system-baseline: ~8 min
- **Total**: ~45 minutes

**Slowest Sequence on HDD**:

- usb-creator: ~20 min (slow drive speed)
- windows-installer: ~35 min (HDD write speed)
- partition-manager: ~10 min (disk operations)
- storage-setup: ~5 min
- system-baseline: ~15 min
- **Total**: ~85 minutes

**Ways To Speed Up**:

- Use USB 3.0 port (not 2.0)
- Use high-speed USB drive (not cheap drive)
- Install on SSD (much faster than HDD)
- Close other programs (frees up RAM/CPU)
- Disable antivirus temporarily (careful!)

---

## Script Source Code

All scripts available at:

```
C:\HELIOS\phases\0-foundation\scripts\
```

Scripts are:

- PowerShell 5.1+ compatible
- Commented and documented
- Open source (readable)
- Tested on Windows 11

---

**Next Step**: Review `TESTING_GUIDE.md` to learn how to verify Phase 0 completed successfully.
