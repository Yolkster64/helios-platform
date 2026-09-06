# HELIOS Platform Component System

## Overview

The HELIOS Platform is built on a modular component system that allows flexibility in deployment. Components can be used independently, borrowed between phases, or combined into custom configurations. This eliminates the need to install entire phases just to use specific features.

## Quick Start

### Install All Components (Recommended for Full Platform)

```bash
cd components
./install-all.ps1
```

### Install Single Component (Independent Use)

```bash
cd components/ai-dashboard
./install.ps1
```

### Borrow Component from Another Phase

```bash
# Use Phase 3 AI Dashboard in Phase 2
./borrow-component.ps1 -ComponentName "ai-dashboard" -FromPhase 3 -ToPhase 2
```

## Available Components

| Component | Phase | Type | Standalone | Dependencies | Size | Install Time |
|-----------|-------|------|-----------|--------------|------|--------------|
| ai-dashboard | 3 | GUI/Monitoring | ✅ Yes | .NET Framework | 245 MB | 5-10 min |
| vault-dynamics | 1 | Encryption | ✅ Yes | Windows Crypto API | 89 MB | 2-3 min |
| security-engine | 0 | Security | ✅ Yes | .NET Core 3.1+ | 156 MB | 3-5 min |
| performance-ai | 2 | Optimization | ⚠️ Partial | security-engine | 412 MB | 8-12 min |
| analytics-core | 2 | Data Analysis | ✅ Yes | SQL Server Express | 178 MB | 4-6 min |
| cloud-bridge | 3 | Cloud Integration | ⚠️ Partial | security-engine, vault-dynamics | 267 MB | 6-8 min |

## Core Concepts

### Independent Installation

Each component can be installed standalone without requiring its full phase. Components are designed to work with reasonable defaults and only pull in essential dependencies.

**Example:** You can install just the AI Dashboard without installing Phase 3, Phase 2, Phase 1, or Phase 0.

### Phase-Based Installation

Traditional installation follows phases 0→1→2→3, but this is now optional.

```
Phase 0: Foundation → security-engine
Phase 1: Core       → vault-dynamics, analytics-core
Phase 2: Intelligence → performance-ai, advanced-analytics
Phase 3: Integration → ai-dashboard, cloud-bridge
```

### Component Borrowing

"Borrow" a component from a later phase and use it in an earlier phase. The borrowing system handles dependencies automatically.

```
+--------+          +--------+          +--------+          +--------+
| Phase 0|          | Phase 1|          | Phase 2|          | Phase 3|
|        |          |        |          |        |          |        |
|Security├─────────→|Vault   |          |        |          |        |
|Engine  |          |Encrypt |          |        |          |        |
|        |          |        |          |        |          |        |
+────────+          +────────+          +────────+          +────────+
    ↑                   ↑                   ↑          ↑         ↑
    |                   |                   |          |         |
    +───────────────────┴───────────────────┴──────────┴─────────+
              You can borrow any component to any phase!
```

### Component Dependencies

**Hard Dependencies** (must be installed for component to work):

- `security-engine` ← Required by: performance-ai, cloud-bridge, vault-dynamics

**Soft Dependencies** (optional, enhance functionality):

- `vault-dynamics` ← Optional for: security-engine, analytics-core

**No Dependencies**:

- `ai-dashboard` (works standalone with defaults)
- `analytics-core` (only needs SQL Server)

See [COMPONENT_DEPENDENCIES.md](./COMPONENT_DEPENDENCIES.md) for complete dependency graph.

## Usage Patterns

### Pattern 1: Core Security Only

```powershell
# Just the security engine - lightweight foundation
./components/security-engine/install.ps1
```

### Pattern 2: Security + Vault (Two-Phase Combo)

```powershell
# Install Phase 0 and Phase 1 components independently
./components/security-engine/install.ps1
./components/vault-dynamics/install.ps1
```

### Pattern 3: Everything Except Dashboard

```powershell
# All components except Phase 3
./components/security-engine/install.ps1
./components/vault-dynamics/install.ps1
./components/analytics-core/install.ps1
./components/performance-ai/install.ps1
```

### Pattern 4: Dashboard Only (Borrowed)

```powershell
# Just the dashboard from Phase 3, with only essential dependencies
./borrow-component.ps1 -ComponentName "ai-dashboard" -MinimalDeps
```

### Pattern 5: Custom Combination

```powershell
# My specific use case: AI Dashboard + Vault + Security
./components/security-engine/install.ps1
./components/vault-dynamics/install.ps1
./components/ai-dashboard/install.ps1  # No need for entire Phase 3
```

## Installation Methods

### Method 1: PowerShell (Windows Native)

```powershell
cd C:\Users\ADMIN\helios-platform\components\<component-name>
.\install.ps1
```

### Method 2: Package Manager

```powershell
# Using built-in package system
Install-HeliosComponent -Name "ai-dashboard"
```

### Method 3: Manual Installation

1. Download component from `./releases/`
2. Extract to `C:\Program Files\HELIOS\components\<name>\`
3. Run configuration wizard
4. Test installation with `test-component.ps1`

### Method 4: Docker (If Available)

```bash
docker pull helios/ai-dashboard:latest
docker run -d -p 8080:8080 helios/ai-dashboard:latest
```

## File Structure

```
components/
├── README.md (this file)
├── COMPONENT_CATALOG.md
├── COMPONENT_DEPENDENCIES.md
├── COMPONENT_COMPATIBILITY_MATRIX.md
├── BORROWING_GUIDE.md
├── INDEPENDENT_INSTALLATION.md
├── UNINSTALL_GUIDE.md
├── ADVANCED_BORROWING_SCENARIOS.md
├── borrow-component.ps1
├── install-all.ps1
├── uninstall-all.ps1
│
├── ai-dashboard/
│   ├── README.md
│   ├── install.ps1
│   ├── uninstall.ps1
│   ├── config.json
│   └── test-component.ps1
│
├── vault-dynamics/
│   ├── README.md
│   ├── install.ps1
│   ├── uninstall.ps1
│   ├── config.json
│   └── test-component.ps1
│
├── security-engine/
│   ├── README.md
│   ├── install.ps1
│   ├── uninstall.ps1
│   ├── config.json
│   └── test-component.ps1
│
├── performance-ai/
│   ├── README.md
│   ├── install.ps1
│   ├── uninstall.ps1
│   ├── config.json
│   └── test-component.ps1
│
└── analytics-core/
    ├── README.md
    ├── install.ps1
    ├── uninstall.ps1
    ├── config.json
    └── test-component.ps1
```

## Checking What's Installed

```powershell
# List all installed components
Get-HeliosComponents

# Check specific component
Test-HeliosComponent -Name "ai-dashboard"

# View component dependencies
Get-ComponentDependencies -Name "ai-dashboard" -Recursive
```

## Common Tasks

### Check Installation Status

```powershell
./components/ai-dashboard/test-component.ps1
# Output: ai-dashboard is installed (v2.1.0)
```

### Verify Component Health

```powershell
Get-HeliosComponent -Name "vault-dynamics" -Verbose
```

### Remove Single Component (Keep Others)

```powershell
./components/ai-dashboard/uninstall.ps1 -KeepDependencies
```

### Upgrade Single Component

```powershell
./components/ai-dashboard/install.ps1 -Upgrade -NoRestart
```

### List All Available Components

```powershell
Get-HeliosComponentCatalog
```

## Troubleshooting

### Component Won't Install

1. Check prerequisites: See component's README.md
2. Verify disk space: Need ~2 GB free
3. Run as Administrator
4. Check component logs: `$HELIOS\logs\component-install.log`

### Borrowed Component Has Issues

1. Verify all dependencies are installed: `Get-ComponentDependencies -Name "component-name"`
2. Check compatibility: See COMPONENT_COMPATIBILITY_MATRIX.md
3. Reinstall component: `./install.ps1 -Reinstall`
4. See troubleshooting section in component's specific README

### Dependency Conflicts

If borrowing causes conflicts:

1. Review COMPONENT_DEPENDENCIES.md
2. Check ADVANCED_BORROWING_SCENARIOS.md for your use case
3. Consider using Minimal Dependencies mode: `./install.ps1 -MinimalDeps`

## Documentation Index

- **COMPONENT_CATALOG.md** - Detailed info on each component
- **COMPONENT_DEPENDENCIES.md** - Which components depend on what
- **COMPONENT_COMPATIBILITY_MATRIX.md** - Compatibility between components
- **BORROWING_GUIDE.md** - How to borrow components between phases
- **INDEPENDENT_INSTALLATION.md** - Using components standalone
- **UNINSTALL_GUIDE.md** - Removing components cleanly
- **ADVANCED_BORROWING_SCENARIOS.md** - Complex borrowing examples

## Best Practices

1. **Always check dependencies** before installing: `Get-ComponentDependencies -Name "component-name"`

2. **Use version pinning** for production: `Install-HeliosComponent -Name "component" -Version "2.1.0"`

3. **Test in isolated environment** before production: Use Docker containers

4. **Document custom builds**: Keep a config file showing which components you borrowed

5. **Backup before major changes**: `.\backup-components.ps1`

6. **Use minimal dependencies** when possible to reduce attack surface

7. **Regularly check for updates**: `Get-HeliosComponentUpdates`

## Uninstalling Components

Individual components can be uninstalled without affecting others:

```powershell
# Uninstall one component
./components/ai-dashboard/uninstall.ps1

# Uninstall all components
./uninstall-all.ps1

# Uninstall with config preservation
./components/vault-dynamics/uninstall.ps1 -PreserveConfig
```

## Support & Documentation

- **Component Issues**: See individual component README.md files
- **Borrowing Questions**: See BORROWING_GUIDE.md
- **Dependencies**: See COMPONENT_DEPENDENCIES.md
- **Compatibility**: See COMPONENT_COMPATIBILITY_MATRIX.md

## Version Information

| Component | Current Version | Release Date | Status |
|-----------|----------------|--------------|--------|
| ai-dashboard | 2.1.0 | 2024-01-15 | Stable |
| vault-dynamics | 1.5.2 | 2024-01-10 | Stable |
| security-engine | 1.2.0 | 2024-01-05 | Stable |
| performance-ai | 0.8.1 | 2023-12-20 | Beta |
| analytics-core | 1.0.3 | 2023-12-15 | Stable |
| cloud-bridge | 0.5.0 | 2023-12-10 | Alpha |

---

**For detailed component information, see COMPONENT_CATALOG.md**
