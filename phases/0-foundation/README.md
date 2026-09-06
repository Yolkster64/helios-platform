# HELIOS Phase 0: Foundation (USB Installer & Fresh Install)

## Overview

Phase 0 is the critical starting point for HELIOS. It handles everything needed to go from a blank computer to a freshly installed Windows system ready for Phase 1 customization.

**Think of Phase 0 like building a house foundation** — before you can add walls and decorations, you need solid ground and the right structure.

## What Phase 0 Includes

| Component | Purpose |
|-----------|---------|
| **USB Creator** | Builds a bootable USB drive with Windows installation files |
| **Windows Installation** | Performs a clean Windows 11 installation from the USB |
| **Partition Manager** | Sets up disk partitions (C: drive, recovery, etc.) |
| **Storage Setup** | Creates folder structure for system organization |
| **System Baseline** | Configures initial system settings and baseline state |

## Time Estimate

- **USB Creation**: 10-20 minutes (first time, faster on subsequent runs)
- **Windows Installation**: 20-30 minutes
- **Partition Manager**: 5-10 minutes
- **Storage Setup**: 2-5 minutes
- **System Baseline**: 5-10 minutes
- **Total**: ~45-75 minutes for a complete fresh install

## Prerequisites

Before running Phase 0, you need:

1. **USB Drive**: 16GB or larger (will be completely erased)
2. **Windows 11 ISO File**: Official ISO from Microsoft
3. **Blank Computer**: Or one you're willing to completely wipe
4. **Admin Access**: You must be an administrator
5. **Internet Connection**: For downloading components (optional - USB can be self-contained)

## Quick Start

### Step 1: Create USB Installer

```powershell
cd C:\Users\ADMIN\helios-platform\phases\0-foundation
.\usb-creator.ps1
```

### Step 2: Boot from USB

1. Insert USB drive
2. Restart computer
3. Press appropriate boot menu key (F12, F2, ESC, DEL - varies by computer)
4. Select USB drive to boot

### Step 3: Install Windows

The Windows installation wizard will guide you through setup.

### Step 4: Run System Setup Scripts

```powershell
# After Windows is installed
.\partition-manager.ps1
.\storage-setup.ps1
.\system-baseline.ps1
```

## File Structure

```
0-foundation/
├── README.md                          # This file
├── PLAIN_ENGLISH_GUIDE.md            # Detailed explanations
├── FILE_ARCHITECTURE.md              # Where files go
├── SCRIPTS_INDEX.md                  # All scripts listed
├── TESTING_GUIDE.md                  # How to verify success
│
└── scripts/
    ├── usb-creator.ps1              # Creates bootable USB
    ├── windows-installer.ps1        # Performs Windows install
    ├── partition-manager.ps1        # Sets up disk partitions
    ├── storage-setup.ps1            # Creates folder structure
    └── system-baseline.ps1          # Initial system configuration
```

## Critical Information

### ⚠️ Important Warnings

- **Data Loss**: These scripts will completely erase selected drives. Back up all data first.
- **No Undo During Installation**: Once Windows installation starts, you cannot safely undo it.
- **Administrator Required**: All scripts must run with admin privileges.
- **Internet**: Required during Windows setup for drivers and Windows Update.

### Recovery Options

Each script has "undo" procedures documented in `PLAIN_ENGLISH_GUIDE.md`. However:

- USB Creator: Simply don't boot from USB (easy to undo)
- Windows Installation: Would require recovery media (hard to undo)
- Partition Manager: Requires partition recovery software or repartitioning
- Storage Setup: Folders can be manually deleted if needed
- System Baseline: Settings can be reverted through Windows Settings

## What Happens After Phase 0?

Once Phase 0 completes successfully, you have:

✓ A fresh Windows 11 system  
✓ Properly partitioned drives  
✓ Organized folder structure  
✓ System baseline configured  
✓ Ready for Phase 1: Customization  

You'll then move to **Phase 1** which adds:

- Application installations
- User customizations
- System tweaks and optimizations

## Troubleshooting

| Problem | Solution |
|---------|----------|
| USB won't boot | Check BIOS boot order; try different USB port |
| Windows install fails | Verify ISO integrity; try different USB drive |
| Scripts won't run | Right-click PowerShell > Run as Administrator |
| Partition errors | See FILE_ARCHITECTURE.md for expected layout |

## Next Steps

1. **Read First**: Start with `PLAIN_ENGLISH_GUIDE.md` to understand each component
2. **Review Architecture**: Check `FILE_ARCHITECTURE.md` to see where files will go
3. **Check Scripts**: Review `SCRIPTS_INDEX.md` for exact scripts you'll run
4. **Plan Testing**: Use `TESTING_GUIDE.md` to verify success
5. **Execute**: Run scripts in order (USB Creator → Windows Install → Partition → Storage → Baseline)

## Support

For detailed information on each component, see:

- **Individual script explanations**: `PLAIN_ENGLISH_GUIDE.md`
- **System file locations**: `FILE_ARCHITECTURE.md`
- **Verification procedures**: `TESTING_GUIDE.md`

---

**Phase 0 Status**: Foundation Layer  
**Depends On**: Nothing (starting point)  
**Required For**: Phase 1: Customization  
**Last Updated**: 2024
