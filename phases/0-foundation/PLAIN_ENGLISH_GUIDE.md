# HELIOS Phase 0: Plain English Guide

This guide explains what each Phase 0 script does in simple, everyday language. No technical jargon.

---

## 1. USB Creator Script

### What It Does

Takes a Windows 11 ISO file and puts it on a USB drive to create a bootable installer. Think of it like copying a recipe and all the ingredients onto a cookbook you can carry around.

### Why You Need It

- You need a way to install Windows on a computer without an existing operating system
- USB installers are more reliable than DVDs and faster than downloads
- This USB can be reused on multiple computers

### How To Run

```powershell
# Open PowerShell as Administrator
# Navigate to the Phase 0 folder
cd C:\Users\ADMIN\helios-platform\phases\0-foundation

# Run the USB creator
.\usb-creator.ps1
```

The script will ask you:

1. **Where is your Windows 11 ISO file?** - Point it to the ISO download
2. **Which USB drive should I use?** - Select from list (be careful!)
3. **Proceed with formatting?** - Confirm (this erases the USB)

### What It Changes

**On Your USB Drive:**

- All existing data is DELETED
- Windows 11 installation files are copied to USB
- USB becomes bootable (can be used to start a computer)
- Approximately 6-8 GB of space used

**On Your Computer:**

- Nothing changes (script only reads the ISO file)
- Temporary files are created during processing
- Temporary files are cleaned up when done

**What Gets Added to USB:**

- Windows 11 boot files
- Windows installation media
- System drivers
- Recovery environment

### How To Undo

**Option 1: Don't boot from it (easiest)**

- Simply don't use the USB to start your computer
- Format the USB normally when you're done
- Use it for regular file storage again

**Option 2: Erase and reformat USB**

```powershell
# In PowerShell (as Administrator):
# First, find your USB drive letter (e.g., E:)
Get-Disk | Where-Object { $_.BusType -eq "USB" }

# Format it (replace E: with your actual drive letter)
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel "USB Storage"
```

**Option 3: Just lose it**

- USB can be disposed of safely
- No data recovery issues (it's just Windows files)

---

## 2. Windows Installation Script

### What It Does

Runs the Windows installation process on your computer. The script starts the Windows Setup wizard which guides you through installing a fresh copy of Windows 11.

This is like building a new house on your land — everything gets wiped clean and rebuilt.

### Why You Need It

- Install Windows on a new computer
- Get a completely clean Windows system (no bloatware)
- Recover from system corruption
- Start fresh with HELIOS customizations

### How To Run

**Step 1: Boot from USB**

1. Insert USB drive created by USB Creator script
2. Restart your computer
3. As computer starts, hold down or repeatedly press the boot menu key:
   - Dell computers: Press F12
   - HP/Lenovo: Press F12 or ESC
   - ASUS: Press DEL or F2
   - Acer: Press F12
   - (Check your computer manual if unsure)
4. Select the USB drive from the menu

**Step 2: Windows Setup Wizard**

- Follow the on-screen prompts
- Accept the Windows 11 license
- Choose which drive to install on (usually C:)
- Wait for installation (20-30 minutes)

**Step 3: Initial Configuration**

- Windows will guide you through setup
- Create a user account when prompted
- Sign in with your username and password

### What It Changes

**Before Windows Install:**

- Blank hard drive (if new computer)
- Or: Old operating system if upgrading

**After Windows Install:**

- Fresh Windows 11 operating system installed
- New system user account created
- Approximately 25-30 GB of space used
- All old programs and files removed (if upgrading)
- Computer ready for Phase 1 customization

**Drive Layout Created:**

- C: drive (main system) - ~100 GB allocated
- Recovery partition (hidden) - ~500 MB

### How To Undo

**Option 1: Reinstall fresh (start over)**

```powershell
# Boot from USB again and select "Custom Install"
# Choose "Delete all partitions"
# Then reinstall (clean slate)
```

**Option 2: Use System Restore**

- Windows Save restore points (if enabled)
- Go to Settings > System > Recovery > System Restore
- Restore to a point before you made changes
- (Only works if restore points were created)

**Option 3: Factory Reset Windows**

```powershell
# Open Settings > System > Recovery
# Click "Reset this PC"
# Choose "Keep my files" or "Remove everything"
# Follow the wizard
```

**Option 4: Go back to previous OS**

- Would require having backup media for old OS
- Essentially requires reinstalling old OS
- Not practical for most scenarios

---

## 3. Partition Manager Script

### What It Does

Sets up how your hard drive is divided into sections (partitions). Think of it like dividing a plot of land into different zones.

This creates:

- **C: drive** (main Windows system)
- **D: drive** (data storage)
- **Recovery partition** (emergency Windows repair)
- **EFI partition** (boot information)

### Why You Need It

- Separates system files from your data (safer backup)
- If C: drive fails, D: drive data survives
- Clean organization of storage
- Allows easier recovery if Windows corrupts
- Meets HELIOS architecture requirements

### How To Run

```powershell
# After Windows is installed and you're logged in
# Open PowerShell as Administrator

cd C:\Users\ADMIN\helios-platform\phases\0-foundation
.\partition-manager.ps1
```

The script will:

1. Show current disk layout
2. Ask which drive to partition
3. Ask what size C: and D: drives should be
4. Confirm changes
5. Create partitions (may require restart)

### What It Changes

**Drive Letters Created:**

- **C:** System drive (Windows + Program Files)
  - Size: Usually 100-200 GB
  - Purpose: Operating system and applications
  
- **D:** Data drive (user files, documents, downloads)
  - Size: Remaining space
  - Purpose: Personal files and documents

**Partitions Created:**

- **EFI System Partition** (hidden)
  - Purpose: Boot files
  - Size: ~100 MB
  
- **Recovery Partition** (hidden)
  - Purpose: Windows recovery tools
  - Size: ~500 MB - 1 GB

**File System:**

- All partitions formatted as NTFS
- Modern, reliable file system
- Compatible with Windows 11

**Example Setup on 500GB Drive:**

```
Partition 1 (EFI):        100 MB   (hidden)
Partition 2 (System):     150 GB   → C: drive
Partition 3 (Recovery):   750 MB   (hidden)
Partition 4 (Data):       349 GB   → D: drive
```

### How To Undo

**Option 1: Repartition from scratch**

```powershell
# Run Partition Manager again
.\partition-manager.ps1
# Select "Reset to defaults"
# Choose new sizes
```

**Option 2: Merge drives back together**

```powershell
# Open Disk Management:
diskpart.exe

# Type these commands:
list disk
select disk 0
list partition
# (Follow on-screen instructions to delete partitions)
# (Then create single partition using all space)
```

**Option 3: Start Windows installation over**

- Reinstall Windows completely
- During installation, delete all partitions
- Windows will create default partitions

---

## 4. Storage Setup Script

### What It Does

Creates the folder structure on your new system. Builds organized directories where files will be stored.

Like creating file cabinets and folders in a new office before you start working.

### Why You Need It

- Organized file structure from day one
- Programs and scripts know where to find files
- Easier to back up and manage data
- HELIOS Phase 1 expects these folders to exist
- Prevents files scattered randomly across drives

### How To Run

```powershell
# After partitioning is complete
# Open PowerShell as Administrator

cd C:\Users\ADMIN\helios-platform\phases\0-foundation
.\storage-setup.ps1
```

The script will:

1. Verify drives exist (C: and D:)
2. Create directory structure
3. Set appropriate permissions
4. Display summary of created folders

### What It Changes

**On C: Drive (System Drive)**

Main folders created in `C:\`:

```
C:\HELIOS\                          ← Main HELIOS directory
├── phases\                         ← Phase scripts and data
│   ├── 0-foundation\
│   ├── 1-customization\
│   ├── 2-hardening\
│   └── ...
├── tools\                          ← Utilities and scripts
├── logs\                           ← System logs
└── config\                         ← Configuration files

C:\Program Files\                   ← Applications (already exists)
C:\Windows\System32\                ← System files (already exists)
```

**On D: Drive (Data Drive)**

Personal folders created in `D:\`:

```
D:\Users\                           ← User data
├── Documents\                      ← Documents
├── Downloads\                      ← Downloads
├── Pictures\                       ← Images
├── Videos\                         ← Video files
├── Desktop\                        ← Desktop files
└── AppData\                        ← Application data

D:\Backups\                         ← System backups
D:\Projects\                        ← Work projects
D:\Archive\                         ← Old files
```

**Folder Permissions:**

- Current user: Full access to all folders
- System: Full access (for administration)
- Other users: Limited access (for security)

**Total Folders Created:** ~30 main folders + subfolders

### How To Undo

**Option 1: Delete folders one by one**

```powershell
# Example: Delete HELIOS folder
Remove-Item C:\HELIOS -Recurse -Force

# Example: Clear D: drive folders
Remove-Item D:\Users -Recurse -Force
```

**Option 2: Delete everything and start over**

```powershell
# Run the script again
.\storage-setup.ps1
# It will detect existing folders and skip or overwrite
```

**Option 3: Reformat drives (nuclear option)**

```powershell
# This erases everything on the drives
Format-Volume -DriveLetter C -FileSystem NTFS
Format-Volume -DriveLetter D -FileSystem NTFS
```

---

## 5. System Baseline Script

### What It Does

Configures initial system settings and baseline state. Sets up Windows to have the right defaults before customizations.

Like setting up a blank canvas with the right paint, brushes, and lighting before an artist starts painting.

### Why You Need It

- Configures Windows for HELIOS requirements
- Disables unnecessary services (improves performance)
- Enables required features
- Sets security baseline
- Prepares for Phase 1 customizations

### How To Run

```powershell
# After storage setup is complete
# Open PowerShell as Administrator

cd C:\Users\ADMIN\helios-platform\phases\0-foundation
.\system-baseline.ps1
```

The script will:

1. Check Windows version (must be 11)
2. Enable required Windows features
3. Disable unnecessary services
4. Configure power settings
5. Set security policies
6. Create system restore point
7. Display summary of changes

### What It Changes

**Windows Features Enabled:**

- Hyper-V (virtualization support)
- Windows Sandbox (isolated environment)
- .NET Framework (application support)
- Windows Subsystem for Linux (WSL2)
- BitLocker support (encryption)

**Windows Services Modified:**

- **Disabled** (to improve performance):
  - OneDrive syncing
  - Cortana background listening
  - Advertising ID tracking
  - Telemetry collection (partially)
  - Search indexing (can be re-enabled)

- **Enabled** (for security/functionality):
  - Windows Defender
  - Windows Update
  - Device Guard (security feature)
  - Credential Guard (security feature)

**System Settings Changed:**

- Power plan: Performance (don't sleep automatically)
- File Explorer: Show hidden files and extensions
- Updates: Automatic (security patches)
- Firewall: Enabled (protection)
- User Account Control: Standard level
- Virtual memory: Optimized for SSD

**Registry Changes:**

```
HKLM:\SYSTEM\CurrentControlSet\Services\
- Multiple services set to Disabled or Automatic
```

**System Restore Point:**

- Created before changes
- Can revert to this point if needed
- Named: "HELIOS-Phase0-Baseline"

### How To Undo

**Option 1: Revert to Restore Point**

```powershell
# Open System Restore
# Select restore point "HELIOS-Phase0-Baseline"
# Click Restore
# Computer will restart and revert changes
```

**Option 2: Manually re-enable services**

```powershell
# Example: Re-enable OneDrive sync
Get-Service OneSyncSvc | Set-Service -StartupType Automatic
Start-Service OneSyncSvc

# Example: Re-enable Cortana
Get-Service CoreMessagingRegistrar | Set-Service -StartupType Automatic
```

**Option 3: Reset individual settings**

- Settings > Privacy & Security > (re-enable tracking)
- Control Panel > Power > (change power plan)
- Settings > System > (change display/sleep settings)

**Option 4: Complete Windows reset**

```powershell
# Remove everything from Phase 0 and start fresh
# Settings > System > Recovery > Reset this PC
# Choose "Remove everything"
```

---

## Summary Table

| Script | Runs On | Time | Data Loss? | Reversible? |
|--------|---------|------|-----------|------------|
| USB Creator | Your computer | 10-20 min | USB only | ✓ Easy |
| Windows Install | New/blank computer | 20-30 min | Entire drive | ✗ Hard |
| Partition Manager | Installed Windows | 5-10 min | None (reshuffles) | ✓ Medium |
| Storage Setup | Installed Windows | 2-5 min | None | ✓ Easy |
| System Baseline | Installed Windows | 5-10 min | None | ✓ Easy |

---

## Common Scenarios

### "I want to start completely over"

1. Use Windows reinstall USB (from USB Creator)
2. Delete all partitions during Windows setup
3. Reinstall Windows fresh
4. Run Partition Manager again
5. Run Storage Setup again
6. Run System Baseline again

### "I messed up partitions"

1. Restart computer from Windows installer USB
2. Run Windows setup again
3. Delete existing partitions
4. Let Windows create default partitions
5. Complete Windows setup
6. Run Partition Manager to fix layout

### "I want to keep my files but reset Windows"

1. Back up D: drive to external storage
2. Reinstall Windows (erases C: drive only)
3. D: drive data stays intact
4. Restore D: drive after Windows install

### "Something broke, I need to undo everything"

1. Try System Restore to HELIOS-Phase0-Baseline
2. If that fails, use Windows Reset (keeps files option)
3. If that fails, reinstall Windows completely

---

## Tips & Tricks

- **Before you start**: External backup of important data (always!)
- **USB creation speed**: First time is slower; subsequent runs are faster
- **Windows install speed**: SSD is much faster than HDD (~15 min vs ~30 min)
- **USB port matters**: Front USB ports may be slower; try back ports
- **Restart helps**: If script seems stuck, restart PowerShell
- **See progress**: All scripts have verbose output; watch for status messages

---

**Next Step**: Review `FILE_ARCHITECTURE.md` to see where all files will be stored.
