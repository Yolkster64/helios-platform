# Phase 0: Foundation - File Locations

Phase 0 establishes the baseline installation framework. All files created in this phase serve as the foundation for subsequent phases.

## Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| USB Creator | C:\ProgramData\HELIOS\Foundation\USBCreator\ | Installation media creation |
| Install Scripts | C:\ProgramData\HELIOS\Foundation\InstallScripts\ | Phase deployment scripts |
| Partition Configs | C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\ | Drive configuration templates |
| Baseline Configs | C:\ProgramData\HELIOS\Foundation\Baselines\ | System baseline snapshots |
| Foundation Registry | HKLM:\Software\HELIOS\Foundation\ | Foundation configuration |
| Installation Logs | C:\ProgramData\HELIOS\Logs\Phase0.log | Installation diagnostic output |

---

## USB Creator Files

**Location**: `C:\ProgramData\HELIOS\Foundation\USBCreator\`

**Purpose**: Contains templates and scripts for creating bootable HELIOS USB media

**Files Created**:

```
C:\ProgramData\HELIOS\Foundation\USBCreator\
├── Creator.exe                          # USB creation application
├── Creator.config                       # USB creator configuration
├── ISO-Templates\
│   ├── HELIOS-Base.iso                 # Base system ISO
│   ├── HELIOS-Secure.iso               # Security-enhanced ISO
│   └── HELIOS-Full.iso                 # Complete feature set ISO
├── Boot-Images\
│   ├── bootmgr                         # Windows boot manager
│   ├── boot.ini                        # Boot configuration
│   └── boot-sector.bin                 # MBR/GPT boot code
├── Scripts\
│   ├── CreateUSB.ps1                   # PowerShell creation script
│   ├── VerifyUSB.ps1                   # Verification script
│   └── CleanUSB.ps1                    # USB cleanup script
├── Drivers\
│   ├── storage-drivers.inf             # Storage controller drivers
│   ├── network-drivers.inf             # Network adapter drivers
│   └── chipset-drivers.inf             # Chipset drivers
└── Logs\
    ├── USBCreation.log                 # Creation logs
    └── Errors.log                      # Error log
```

**Access**: Admin required

**Size**: ~2-5 GB (including ISO images)

**Examples**:

```
C:\ProgramData\HELIOS\Foundation\USBCreator\Creator.exe
C:\ProgramData\HELIOS\Foundation\USBCreator\ISO-Templates\HELIOS-Full.iso
C:\ProgramData\HELIOS\Foundation\USBCreator\Scripts\CreateUSB.ps1
```

---

## Installation Scripts

**Location**: `C:\ProgramData\HELIOS\Foundation\InstallScripts\`

**Purpose**: Scripts that orchestrate deployment of all phases

**Files Created**:

```
C:\ProgramData\HELIOS\Foundation\InstallScripts\
├── Phase0-Foundation.ps1               # Phase 0 main deployment script
├── Phase0-Prerequisites.ps1            # Prerequisite checks
├── Phase0-SystemPrep.ps1               # System preparation
├── Phase0-Registry-Setup.ps1           # Registry initialization
├── Phase0-Directories-Setup.ps1        # Directory structure creation
├── Phase0-Rollback.ps1                 # Rollback script
├── Helper-Functions.ps1                # Shared utility functions
├── Validation-Scripts\
│   ├── ValidateInstallation.ps1        # Installation verification
│   ├── CheckPrerequisites.ps1          # Check Windows version, disk space
│   ├── TestSystemAccess.ps1            # Test admin privileges
│   └── VerifyFileIntegrity.ps1         # Hash verification
├── Logs\
│   ├── Installation.log                # Main installation log
│   ├── Errors.log                      # Error details
│   └── Warnings.log                    # Non-fatal warnings
└── Config\
    └── InstallConfig.xml               # Installation configuration
```

**Access**: Admin/SYSTEM required

**Size**: ~50 MB

**Examples**:

```
C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase0-Foundation.ps1
C:\ProgramData\HELIOS\Foundation\InstallScripts\Validation-Scripts\CheckPrerequisites.ps1
C:\ProgramData\HELIOS\Foundation\InstallScripts\Logs\Installation.log
```

**Key Scripts**:

- **Phase0-Foundation.ps1**: Master orchestration script
  - Validates prerequisites
  - Creates directory structure
  - Initializes registry
  - Deploys base system

- **Phase0-Prerequisites.ps1**: Pre-installation checks
  - Verifies Windows version (10/11)
  - Checks disk space (5 GB minimum)
  - Validates admin privileges
  - Tests network connectivity

---

## Partition Configuration Files

**Location**: `C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\`

**Purpose**: Disk and partition layout templates

**Files Created**:

```
C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\
├── Standard-GPT.cfg                    # GPT partition layout (modern)
├── Legacy-MBR.cfg                      # MBR partition layout (legacy)
├── Custom-Layouts\
│   ├── SingleDrive.cfg                 # Single drive configuration
│   ├── DualDrive.cfg                   # Two drive configuration
│   ├── RAID0.cfg                       # RAID 0 striped
│   └── RAID1.cfg                       # RAID 1 mirrored
├── Disk-Sizes\
│   ├── 256GB.cfg
│   ├── 512GB.cfg
│   ├── 1TB.cfg
│   └── 2TB.cfg
└── Schemas\
    ├── partition-schema.xml            # Schema definition
    └── validation.xsd                  # Validation schema
```

**Access**: Admin/SYSTEM required

**Size**: <5 MB

**Examples**:

```
C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\Standard-GPT.cfg
C:\ProgramData\HELIOS\Foundation\Baselines\Partitions\Custom-Layouts\DualDrive.cfg
```

**File Format Example (Standard-GPT.cfg)**:

```
[PARTITION_CONFIG]
Format=GPT
BootPartition=500MB,FAT32,System
SystemPartition=Remaining,NTFS,Boot

[DISK_0]
Size=Auto
PartitionTable=GPT
Partitions=2
Partition1=EFI,500MB,FAT32
Partition2=Windows,Remaining,NTFS
```

---

## Baseline Configuration Files

**Location**: `C:\ProgramData\HELIOS\Foundation\Baselines\`

**Purpose**: Snapshots of baseline system configuration

**Files Created**:

```
C:\ProgramData\HELIOS\Foundation\Baselines\
├── System-Baseline.snapshot            # Complete system baseline
├── Registry-Baseline.hiv               # Registry snapshot
├── Drivers-Baseline.list               # Installed drivers list
├── Services-Baseline.cfg               # Service configuration snapshot
├── Permissions-Baseline.cfg            # File permissions snapshot
├── Network-Baseline.cfg                # Network configuration snapshot
├── Security-Baseline.cfg               # Security settings snapshot
├── Performance-Baseline.cfg            # Performance counters baseline
├── Software-Inventory.json             # Installed software list
├── Hardware-Inventory.json             # Hardware inventory snapshot
└── Timestamps\
    └── 2024-01-15-08-30.baseline       # Timestamped baseline archive
```

**Access**: Admin/SYSTEM required

**Size**: ~200-500 MB

**Examples**:

```
C:\ProgramData\HELIOS\Foundation\Baselines\System-Baseline.snapshot
C:\ProgramData\HELIOS\Foundation\Baselines\Registry-Baseline.hiv
C:\ProgramData\HELIOS\Foundation\Baselines\Timestamps\2024-01-15-08-30.baseline
```

**Baseline Contents**:

**System-Baseline.snapshot**:

- Operating system version
- Installed KB updates
- System drive configuration
- Available disk space
- RAM configuration
- BIOS/UEFI settings summary
- Hardware device list

**Registry-Baseline.hiv**:

- Export of HKLM:\Software\Microsoft\Windows\
- Network configuration
- Security policies (pre-HELIOS)
- User account list
- Installed software registry entries

**Software-Inventory.json**:

```json
{
  "timestamp": "2024-01-15T08:30:00Z",
  "installed_software": [
    {
      "name": "Microsoft Office 365",
      "version": "16.0.13001.20166",
      "publisher": "Microsoft Corporation",
      "install_date": "2023-12-01",
      "install_location": "C:\\Program Files\\Microsoft Office"
    },
    {
      "name": "Adobe Reader",
      "version": "23.006.20320",
      "publisher": "Adobe",
      "install_date": "2024-01-10",
      "install_location": "C:\\Program Files (x86)\\Adobe"
    }
  ]
}
```

---

## Foundation Registry Settings

**Location**: `HKLM:\Software\HELIOS\Foundation\`

**Purpose**: Foundation phase configuration keys

**Keys Created**:

```
HKLM:\Software\HELIOS\
├── Foundation\
│   ├── InstallDate                    # Installation timestamp
│   ├── Version                        # HELIOS version
│   ├── SystemDrive                    # System drive letter
│   ├── BaselineLocation               # Path to baseline files
│   ├── DataDirectory                  # C:\ProgramData\HELIOS\
│   ├── InstalledFeatures              # Comma-separated features
│   ├── PrerequisitesMet               # Boolean
│   └── RollbackCapable                # Boolean
│
├── Paths\
│   ├── Foundation                    # Path to Foundation directory
│   ├── Security                      # Path to Security directory
│   ├── Optimization                  # Path to Optimization directory
│   └── Capability                    # Path to Capability directory
│
└── Status\
    ├── Phase0-Complete               # Boolean
    ├── Phase1-Pending                # Boolean
    ├── Phase2-Pending                # Boolean
    ├── Phase3-Pending                # Boolean
    └── LastUpdated                   # Timestamp
```

**Access**: Admin/SYSTEM required

**Examples**:

```
HKLM:\Software\HELIOS\Foundation\InstallDate = "2024-01-15 08:30:15"
HKLM:\Software\HELIOS\Foundation\Version = "4.1.0"
HKLM:\Software\HELIOS\Paths\Foundation = "C:\ProgramData\HELIOS\Foundation"
HKLM:\Software\HELIOS\Status\Phase0-Complete = 1 (TRUE)
```

---

## Installation Log Files

**Location**: `C:\ProgramData\HELIOS\Logs\Phase0.log`

**Purpose**: Diagnostic and operational logs for Phase 0

**Files Created**:

```
C:\ProgramData\HELIOS\Logs\
├── Phase0.log                         # Main Phase 0 log
├── Phase0-Details.log                 # Detailed verbose log
├── Phase0-Errors.log                  # Errors only
├── Phase0-Warnings.log                # Warnings only
├── Phase0-Rollback.log                # Rollback operations
├── Installation-History.csv           # Installation history
└── Validation-Report.txt              # Pre-installation validation
```

**Access**: Admin to write; everyone can read

**Size**: 10-50 MB for full installation with verbose logging

**Log Format Example**:

```
[2024-01-15 08:30:15.234] [INFO] Phase 0 Foundation Installation Started
[2024-01-15 08:30:16.456] [INFO] Running prerequisite checks...
[2024-01-15 08:30:17.123] [INFO] Windows Version: Windows 11 Enterprise
[2024-01-15 08:30:17.789] [INFO] Admin privileges verified
[2024-01-15 08:30:18.234] [INFO] Available disk space: 250 GB
[2024-01-15 08:30:19.567] [INFO] Creating directory structure...
[2024-01-15 08:30:22.891] [INFO] Registry initialization in progress...
[2024-01-15 08:30:25.123] [INFO] Baseline snapshot created
[2024-01-15 08:30:27.456] [INFO] Phase 0 Foundation Installation Completed
[2024-01-15 08:30:27.789] [INFO] Elapsed time: 12.5 seconds
```

---

## Directory Creation Summary

### Complete Directory Tree Created by Phase 0

```
C:\ProgramData\HELIOS\
├── Foundation\
│   ├── USBCreator\                     # 2-5 GB
│   │   ├── Creator.exe
│   │   ├── ISO-Templates\
│   │   ├── Boot-Images\
│   │   ├── Scripts\
│   │   ├── Drivers\
│   │   └── Logs\
│   ├── InstallScripts\                 # 50 MB
│   │   ├── Phase0-Foundation.ps1
│   │   ├── Validation-Scripts\
│   │   ├── Logs\
│   │   └── Config\
│   └── Baselines\                      # 200-500 MB
│       ├── Partitions\
│       │   ├── Standard-GPT.cfg
│       │   ├── Custom-Layouts\
│       │   └── Disk-Sizes\
│       ├── System-Baseline.snapshot
│       ├── Registry-Baseline.hiv
│       ├── Software-Inventory.json
│       ├── Hardware-Inventory.json
│       └── Timestamps\
├── Logs\
│   ├── Phase0.log
│   ├── Phase0-Details.log
│   ├── Phase0-Errors.log
│   ├── Phase0-Warnings.log
│   ├── Phase0-Rollback.log
│   └── Installation-History.csv
├── Config\
│   └── HELIOS.config.xml               # Main config (placeholder)
└── Database\
    └── (Created empty, Phase 3 will populate)
```

---

## File Access & Permissions

### Directory Permissions

```
C:\ProgramData\HELIOS\Foundation\
├── Owner: SYSTEM
├── Administrators: Full Control
├── CREATOR OWNER: Full Control
└── Users: Read, Execute
```

### File Permissions

```
C:\ProgramData\HELIOS\Foundation\InstallScripts\*.ps1
├── Owner: SYSTEM
├── Administrators: Full Control
└── Users: Read, Execute (not modify)

C:\ProgramData\HELIOS\Logs\Phase0.log
├── Owner: SYSTEM
├── Administrators: Read, Write
└── Users: Read
```

---

## Phase 0 File Dependencies

### Execution Order

1. **Phase0-Prerequisites.ps1** (runs first)
   - Validates system
   - Creates baseline snapshots

2. **Phase0-SystemPrep.ps1** (runs second)
   - Creates directory structure
   - Deploys USB creator files
   - Sets up logging

3. **Phase0-Registry-Setup.ps1** (runs third)
   - Initializes registry keys
   - Sets foundation status

4. **Phase0-Directories-Setup.ps1** (runs fourth)
   - Creates all subdirectories
   - Sets permissions
   - Validates structure

### File Dependencies

```
Phase0-Foundation.ps1
├── Requires: Helper-Functions.ps1
├── Uses: Phase0-Prerequisites.ps1
├── Uses: Phase0-SystemPrep.ps1
├── Uses: Phase0-Registry-Setup.ps1
├── Uses: Phase0-Directories-Setup.ps1
└── Requires: ValidateInstallation.ps1

Phase0-SystemPrep.ps1
├── Uses: Creator.exe
├── Uses: Boot-Images/*
├── Uses: Drivers\*
└── Uses: ISO-Templates\*
```

---

## Rollback Procedure

**Location**: `C:\ProgramData\HELIOS\Foundation\InstallScripts\Phase0-Rollback.ps1`

**Function**: Removes all Phase 0 files and registry entries

**What It Removes**:

1. `C:\ProgramData\HELIOS\Foundation\` directory
2. `C:\ProgramData\HELIOS\Logs\Phase0.*` files
3. `HKLM:\Software\HELIOS\Foundation\` registry keys
4. `HKLM:\Software\HELIOS\Paths\Foundation` registry entry
5. Restores `HKLM:\Software\HELIOS\Status\Phase0-Complete` to 0

**What It Preserves** (for rollback recovery):

- `C:\ProgramData\HELIOS\Foundation\Baselines\` (backed up to timestamped folder)
- Original baseline snapshots (for reference)

---

## Typical File Sizes

| File/Directory | Size |
|---|---|
| Creator.exe | ~10 MB |
| HELIOS-Full.iso | ~2 GB |
| Boot-Images\ | ~500 MB |
| Drivers\ | ~1 GB |
| Phase0-Foundation.ps1 | ~100 KB |
| System-Baseline.snapshot | ~50 MB |
| Registry-Baseline.hiv | ~20 MB |
| Software-Inventory.json | ~5 MB |
| Entire Phase 0 directory | ~3-5 GB |

---

## Next Steps

After Phase 0 completes:

- All foundation files are in place
- Registry initialized
- Baselines captured
- Ready for Phase 1 (Security) deployment

See **PHASE_1_FILE_LOCATIONS.md** for next phase file placement.
