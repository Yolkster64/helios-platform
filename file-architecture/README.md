# HELIOS File Architecture Documentation

## Overview

This directory contains comprehensive documentation of where every HELIOS component's files are stored in Windows. Use these guides to understand file locations, registry paths, and component deployment across different phases.

## What You'll Find Here

### Core Documentation Files

| File | Purpose |
|------|---------|
| **WINDOWS_SYSTEM_PATHS.md** | Standard Windows directories and what HELIOS places in each |
| **PHASE_0_FILE_LOCATIONS.md** | Foundation phase files (USB creator, install scripts, configs) |
| **PHASE_1_FILE_LOCATIONS.md** | Security phase files (AppLocker, firewall, vault, security logs) |
| **PHASE_2_FILE_LOCATIONS.md** | Optimization phase files (services, startup, temp cleanup, caches) |
| **PHASE_3_FILE_LOCATIONS.md** | Capability phase files (dashboard, AI models, profiles, workflows) |
| **REGISTRY_CHANGES.md** | Registry modifications by phase with exact key paths |
| **FILE_BORROWING_GUIDE.md** | Advanced: How to reuse files from one phase in another |
| **DIRECTORY_TREE.md** | Complete file structure visualization |
| **QUICK_LOOKUP_TABLE.md** | Quick reference: Component → Location mapping |

## Quick Start

### Find Where Something Goes

1. **If you know the component name**: Check **QUICK_LOOKUP_TABLE.md**
2. **If you know the phase**: Use **PHASE_X_FILE_LOCATIONS.md**
3. **If you want full structure**: See **DIRECTORY_TREE.md**
4. **If you need registry paths**: Consult **REGISTRY_CHANGES.md**

### Example Lookups

- "Where do AppLocker rules go?" → **PHASE_1_FILE_LOCATIONS.md** → Registry HKLM
- "What files does Phase 3 create?" → **PHASE_3_FILE_LOCATIONS.md**
- "Where's my Vault database?" → **QUICK_LOOKUP_TABLE.md** or **PHASE_1_FILE_LOCATIONS.md**
- "All System32 locations?" → **WINDOWS_SYSTEM_PATHS.md**

## File Location Conventions

### User-Specific Paths

When you see `[USERNAME]`, replace with actual username:

- `C:\Users\[USERNAME]\AppData\Local\` → `C:\Users\Administrator\AppData\Local\`
- `C:\Users\[USERNAME]\AppData\Roaming\` → `C:\Users\Administrator\AppData\Roaming\`

### Registry Paths

Registry paths follow hive notation:

- `HKLM:\` → HKEY_LOCAL_MACHINE (machine-wide)
- `HKCU:\` → HKEY_CURRENT_USER (current user only)
- `HKLM:\Software\...` → 64-bit on 64-bit Windows, 32-bit on 32-bit Windows
- `HKLM:\Software\Wow6432Node\...` → Always 32-bit applications on 64-bit Windows

### Directory Hierarchy

- **System directories**: Usually protected (require admin)
- **AppData Local**: Per-user, machine-specific data (not synced)
- **AppData Roaming**: Per-user, can sync across machines
- **ProgramData**: All-user accessible, shared application data

## Path Sizes & Capacity

| Location | Typical Size Limit | Notes |
|----------|-------------------|-------|
| C:\Windows\System32\ | ~50 GB system drive | System drive must have at least 20 GB free |
| C:\Program Files\ | 64-bit only, ~500 MB per app avg | Can grow beyond C:\ to other drives |
| C:\Users\[USERNAME]\AppData\Local\ | User quota if enabled | Often <10 MB per app |
| Registry HKLM | ~30 MB practical limit | Growing beyond 100 MB causes performance issues |
| C:\ProgramData\HELIOS\ | Configurable | Monitor for database and logs growth |

## Phase Overview

### Phase 0: Foundation

- Creates installation media and baseline configurations
- Files: USB scripts, partition configs, system baselines
- Location: Primarily `C:\ProgramData\HELIOS\Foundation\`

### Phase 1: Security

- Deploys security policies (AppLocker, firewall, vault)
- Files: Policy definitions, security rules, quarantine storage
- Location: Registry HKLM + `C:\ProgramData\HELIOS\Security\`

### Phase 2: Optimization

- Configures services, startup items, cleanup routines
- Files: Service definitions, optimization logs, cleanup configs
- Location: Registry HKLM:\SYSTEM + `C:\ProgramData\HELIOS\Optimization\`

### Phase 3: Capability

- Deploys AI dashboard, workflows, analysis profiles
- Files: Application binaries, AI models, databases
- Location: `C:\Program Files\HELIOS\` + `C:\ProgramData\HELIOS\Capability\`

## Usage Tips

### For Deployment Engineers

1. Use **PHASE_X_FILE_LOCATIONS.md** to verify all files are in place
2. Check **REGISTRY_CHANGES.md** to ensure registry is correctly configured
3. Use **DIRECTORY_TREE.md** to validate complete installation

### For System Administrators

1. Consult **QUICK_LOOKUP_TABLE.md** for quick lookups
2. Use **FILE_BORROWING_GUIDE.md** to customize phase dependencies
3. Check **WINDOWS_SYSTEM_PATHS.md** for storage planning

### For Developers

1. Reference **DIRECTORY_TREE.md** for component locations
2. Use **REGISTRY_CHANGES.md** to understand configuration storage
3. Check **FILE_BORROWING_GUIDE.md** for cross-phase dependencies

## Important Notes

### Permission Requirements

Most files are created with:

- **System32, SysWOW64, Registry HKLM**: Admin/SYSTEM privileges
- **Program Files**: Admin privileges
- **AppData Local/Roaming**: User privileges
- **ProgramData**: Admin privileges

### Backup Recommendations

Before Phase deployment, backup:

1. Registry: Export `HKLM:\Software\Policies\Microsoft\Windows\`
2. Files: Backup `C:\ProgramData\` and `C:\Program Files\HELIOS\`
3. System: Create system restore point (optional but recommended)

### Antivirus Considerations

Add to exclusions:

- `C:\ProgramData\HELIOS\` - All HELIOS data
- `C:\Program Files\HELIOS\` - Application files
- `C:\Users\[USERNAME]\Vault\` - Vault database

## Document Maintenance

| Document | Last Updated | Applies To |
|----------|--------------|-----------|
| This file | Current | All versions |
| WINDOWS_SYSTEM_PATHS.md | Current | Windows 10/11 |
| PHASE_0_FILE_LOCATIONS.md | Current | Current version |
| PHASE_1_FILE_LOCATIONS.md | Current | Current version |
| PHASE_2_FILE_LOCATIONS.md | Current | Current version |
| PHASE_3_FILE_LOCATIONS.md | Current | Current version |
| REGISTRY_CHANGES.md | Current | Current version |
| FILE_BORROWING_GUIDE.md | Current | Current version |
| DIRECTORY_TREE.md | Current | Current version |
| QUICK_LOOKUP_TABLE.md | Current | Current version |

---

**Need help?** Each document includes examples. Start with QUICK_LOOKUP_TABLE.md for the fastest answer.
