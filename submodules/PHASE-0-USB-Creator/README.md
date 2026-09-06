# PHASE-0-USB-Creator

## Quick Summary

Creates bootable Windows PE USB media with HELIOS Platform tools pre-loaded. Automates the entire USB creation process including validation and testing.

## Key Facts

- **Owner**: TBD
- **Status**: Planned
- **Version**: 0.1.0-dev
- **Phase**: 0 (Foundation)
- **Team Size**: 1 developer
- **Timeline**: Weeks 1-2
- **Dependencies**: None
- **Depends On Us**: PHASE-0-Windows-Installer

## What It Does

Provides automated PowerShell scripts to:

1. **Create Bootable USB**
   - Format USB drive
   - Copy Windows PE to USB
   - Add boot configuration
   - Install bootloader

2. **Pre-load HELIOS Tools**
   - Copy Phase 0 scripts to USB
   - Copy Phase 1+ scripts for reference
   - Include HELIOS configuration templates
   - Add documentation

3. **Validation & Testing**
   - Verify boot sector
   - Check file integrity
   - Test USB on VM
   - Generate validation report

## API Reference

### Public Functions

#### New-BootableUSB

```
New-BootableUSB -USBDrive <char> -WindowsPEPath <string> -HeliosPath <string> [-Verbose]
```

Creates bootable USB with HELIOS tools.

**Parameters**:

- USBDrive: Drive letter (E, F, G, etc)
- WindowsPEPath: Path to Windows PE ISO or extracted files
- HeliosPath: Path to HELIOS scripts folder

**Returns**: Object with Status, DriveInfo, FilesAdded

**Example**:

```powershell
New-BootableUSB -USBDrive "E" -WindowsPEPath "C:\WinPE" -HeliosPath "C:\HELIOS\Phase0"
```

#### Test-BootableUSB

```
Test-BootableUSB -USBDrive <char> [-TestVM]
```

Validates USB is bootable and functional.

**Parameters**:

- USBDrive: Drive letter to test
- TestVM: If specified, attempts boot in VM

**Returns**: Object with TestResults, Issues, Recommendations

**Example**:

```powershell
Test-BootableUSB -USBDrive "E" -TestVM
```

### Integration Points

- **Provides to**: PHASE-0-Windows-Installer (bootable media)
- **Inputs**: Windows PE ISO, HELIOS scripts
- **Outputs**: Bootable USB ready for installation

## Status & Metrics

| Metric | Value |
|---|---|
| Overall Progress | 0% (Planned) |
| Code Complete | 0% |
| Tests Written | 0% |
| Tests Passing | 0/0 |
| Code Quality | — |
| Blockers | None |

## Known Issues

None yet (design phase).

## Getting Started

### Prerequisites

- Windows 10 or later
- Administrator privileges
- USB 3.0 drive (16GB+)
- Windows PE ISO or extracted files

### Quick Start

1. **Prepare Windows PE**

   ```powershell
   # Download Windows ADK and extract Windows PE
   # Or use pre-built Windows PE ISO
   ```

2. **Get HELIOS Scripts**

   ```powershell
   # Clone HELIOS repository
   git clone https://github.com/your-org/helios-platform.git
   cd helios-platform
   ```

3. **Create USB**

   ```powershell
   Import-Module .\submodules\PHASE-0-USB-Creator\src\Module.psm1
   New-BootableUSB -USBDrive "E" `
     -WindowsPEPath "C:\WinPE" `
     -HeliosPath ".\submodules\PHASE-0-USB-Creator"
   ```

4. **Validate USB**

   ```powershell
   Test-BootableUSB -USBDrive "E"
   ```

## Next Steps

- [ ] Design: Define USB layout and file structure
- [ ] Code: Implement New-BootableUSB function
- [ ] Code: Implement Test-BootableUSB function
- [ ] Tests: Write unit tests (target 80% coverage)
- [ ] Docs: Write PLAIN_ENGLISH_GUIDE.md
- [ ] Testing: Manual USB creation and boot test
- [ ] Integration: Test with PHASE-0-Windows-Installer
- [ ] Release: v1.0.0

## Help & Contact

- **Owner**: [Owner Name] (owner@example.com)
- **Team Lead**: [Lead Name] (lead@example.com)
- **Slack**: #helios-phase-0

---

**Submodule Version**: 0.1.0-dev  
**Last Updated**: 2024-01-08  
**Maintained By**: Foundation Team
