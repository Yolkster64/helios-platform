# Component Borrowing Guide

Learn how to use components from later phases in earlier phases. Borrowing lets you use specific features without installing entire phases.

---

## What is Borrowing?

**Borrowing** is using a component from a later phase in an earlier phase. Instead of installing all of Phase 3 just to use the AI Dashboard, you can "borrow" just the dashboard into Phase 1 or Phase 0.

### Traditional Flow (Non-Borrowing)

```
Want Dashboard (Phase 3)?
→ Install Phase 0 (security-engine)
→ Install Phase 1 (vault, analytics)
→ Install Phase 2 (performance-ai)
→ Install Phase 3 (ai-dashboard, cloud-bridge)
→ 30+ GB, 30+ minutes
```

### Borrowing Flow

```
Want Dashboard (Phase 3)?
→ Borrow just ai-dashboard to current phase
→ 245 MB, 5 minutes
→ Works standalone with minimal dependencies
```

---

## Core Principles

1. **Any component can be borrowed to any earlier phase**
2. **Borrowed components maintain their functionality**
3. **Dependencies are automatically resolved**
4. **Borrowed components work alongside native components**
5. **Easy rollback if needed**

---

## Dependency Resolution in Borrowing

When you borrow a component, the system automatically:

1. Checks what the component needs
2. Ensures all required dependencies are installed
3. Installs hard dependencies automatically (with permission)
4. Notes which components can't work together
5. Creates a dependency map for easy management

### Example: Borrowing AI Dashboard to Phase 0

```
Request: Borrow ai-dashboard to Phase 0

Dependency Check:
├── ai-dashboard needs: .NET 4.8 ✓ (already installed in Phase 0)
├── ai-dashboard needs: Windows Event Log ✓ (system component)
└── No phase dependencies ✓

Result: ✅ Can borrow successfully!
```

### Example: Borrowing Performance AI to Phase 0

```
Request: Borrow performance-ai to Phase 0

Dependency Check:
├── performance-ai needs: security-engine
│   └── security-engine already exists in Phase 0 ✓
├── performance-ai needs: ML models ✓
└── No conflicts detected ✓

Result: ✅ Can borrow successfully!
```

### Example: Borrowing Cloud Bridge to Phase 1

```
Request: Borrow cloud-bridge to Phase 1

Dependency Check:
├── cloud-bridge needs: security-engine ✓ (Phase 0, inherited)
├── cloud-bridge needs: vault-dynamics ✓ (Phase 1, already exists)
└── All dependencies satisfied ✓

Result: ✅ Can borrow successfully!
```

---

## Step-by-Step Borrowing Process

### Step 1: Check Prerequisites

Before borrowing, verify prerequisites are met:

```powershell
# Check if component can be borrowed
.\check-borrowing-prerequisites.ps1 -ComponentName "ai-dashboard" `
                                     -ToPhase "1"

# Output:
# ai-dashboard can be borrowed to Phase 1
# Prerequisites: .NET 4.8 (✓ installed), Windows Event Log (✓ system)
# No conflicts detected
# Estimated space needed: 245 MB (Available: 500 GB)
```

### Step 2: Perform the Borrow

```powershell
# Borrow ai-dashboard to Phase 1
.\borrow-component.ps1 -ComponentName "ai-dashboard" `
                       -FromPhase 3 `
                       -ToPhase 1

# Output:
# Checking dependencies...
# Installing ai-dashboard to Phase 1...
# Installation complete! (5m 32s)
# ai-dashboard is now available in Phase 1
```

### Step 3: Verify Installation

```powershell
# Test the borrowed component
C:\Program Files\HELIOS\Phase-1\ai-dashboard\test-component.ps1

# Output:
# ai-dashboard test results:
# ✓ Service running on port 8080
# ✓ GUI accessible at http://localhost:8080
# ✓ Database connected
# ✓ All systems operational
```

---

## Common Borrowing Scenarios

### Scenario 1: Use AI Dashboard in Phase 2

**Goal:** You have Phase 2 installed and want the Phase 3 dashboard without installing Phase 3.

```powershell
# Step 1: Verify prerequisites
.\check-borrowing-prerequisites.ps1 -ComponentName "ai-dashboard" -ToPhase "2"
# Output: ✓ Can borrow

# Step 2: Perform borrow
.\borrow-component.ps1 -ComponentName "ai-dashboard" -FromPhase 3 -ToPhase 2

# Step 3: Access dashboard
# Navigate to http://localhost:8080
```

**Result:** Full Phase 3 dashboard working with Phase 2 features. No need to install all of Phase 3.

**Saved Time:** ~15 minutes  
**Saved Space:** ~2 GB (rest of Phase 3)

---

### Scenario 2: Use Vault in Phase 0

**Goal:** You want encryption (Phase 1) in Phase 0 (just foundation security).

```powershell
# Check prerequisites
.\check-borrowing-prerequisites.ps1 -ComponentName "vault-dynamics" -ToPhase "0"
# Output: ✓ Can borrow (no dependencies needed)

# Borrow it
.\borrow-component.ps1 -ComponentName "vault-dynamics" -FromPhase 1 -ToPhase 0

# Now vault-dynamics is available in Phase 0
# You have just security + vault, nothing else
```

**Why?** Maybe you only need encryption and basic security, not analytics or performance optimization.

**Saved Time:** ~20 minutes  
**Saved Space:** ~1.5 GB

---

### Scenario 3: Use Performance AI in Phase 1

**Goal:** You want AI optimization (Phase 2) with Phase 1 components only.

```powershell
# Verify prerequisites
.\check-borrowing-prerequisites.ps1 -ComponentName "performance-ai" -ToPhase "1"
# Output: ⚠️ Missing dependency: security-engine (available in Phase 0)
#         ✓ Can borrow (auto-install security-engine if not present)

# Borrow with auto-dependency installation
.\borrow-component.ps1 -ComponentName "performance-ai" `
                       -FromPhase 2 `
                       -ToPhase 1 `
                       -AutoInstallDependencies

# Now you have: Phase 0 (security-engine) + Phase 1 (vault, analytics)
#                    + Phase 2 (performance-ai borrowed)
# You're missing Phase 2's other components, but have the AI optimizer
```

**Note:** This borrows performance-ai but leaves out advanced-analytics (also in Phase 2) since you didn't request it.

---

### Scenario 4: Use Cloud Bridge in Phase 2

**Goal:** Get cloud integration (Phase 3) with Phase 2 functionality.

```powershell
# Check prerequisites
.\check-borrowing-prerequisites.ps1 -ComponentName "cloud-bridge" -ToPhase "2"
# Output: ✓ All dependencies present (security-engine, vault-dynamics)

# Borrow it
.\borrow-component.ps1 -ComponentName "cloud-bridge" -FromPhase 3 -ToPhase 2

# Now Phase 2 can sync with Azure/AWS/GCP
```

**Why?** Maybe you're scaling to the cloud but don't need Phase 3's dashboard yet.

---

## Advanced Borrowing: Custom Multi-Phase Setup

### Example: "Dashboard + Vault Only"

You want the dashboard and encryption but nothing else.

```powershell
# Step 1: Install security foundation (required by everything)
.\components\security-engine\install.ps1

# Step 2: Install vault encryption
.\components\vault-dynamics\install.ps1

# Step 3: Borrow dashboard from Phase 3
.\borrow-component.ps1 -ComponentName "ai-dashboard" -FromPhase 3 -ToPhase 0

# Result: Lightweight setup with security, encryption, and dashboard
# Total: ~500 MB, ~10 minutes installation
# vs. Full platform: ~3 GB, ~40 minutes
```

### Example: "AI + Dashboard + Analytics"

You want AI optimization, dashboard, and analytics but not cloud features.

```powershell
# Phase 0: Foundation
.\components\security-engine\install.ps1

# Phase 1: Analytics
.\components\analytics-core\install.ps1

# Phase 2: AI Optimization (depends on Phase 0, includes Phase 1 elements)
.\components\performance-ai\install.ps1

# Phase 3: Dashboard (borrowed, no need for other Phase 3 components)
.\borrow-component.ps1 -ComponentName "ai-dashboard" -FromPhase 3 -ToPhase 0

# Result: Complete monitoring and optimization without cloud bridge
```

---

## Dependency Resolution Examples

### Example 1: Resolve Conflicting Dependencies

Some components have optional conflicting dependencies. The borrowing system detects these:

```powershell
# Attempt to borrow cloud-bridge with local-only vault
.\borrow-component.ps1 -ComponentName "cloud-bridge" `
                       -FromPhase 3 `
                       -ToPhase 1 `
                       -VaultMode "local-only"

# System recognizes: cloud-bridge needs cloud-capable vault
# Prompts: "cloud-bridge expects cloud-sync-enabled vault. 
#           Your vault is local-only. Proceed anyway? (May cause errors)"
```

### Example 2: Auto-Resolve Version Conflicts

```powershell
# If you have .NET 4.7 but ai-dashboard needs 4.8
.\borrow-component.ps1 -ComponentName "ai-dashboard" `
                       -FromPhase 3 `
                       -ToPhase 1 `
                       -AutoResolveVersions

# System automatically upgrades .NET 4.7 → 4.8
# Completes borrow process
```

---

## Rollback: Removing Borrowed Components

If a borrowed component isn't working or you want to go back:

### Remove Single Borrowed Component

```powershell
# Remove borrowed ai-dashboard
.\unborrow-component.ps1 -ComponentName "ai-dashboard" -FromPhase 1

# Checks: Are any other components using it?
# If safe: Removes component
# If risky: Warns about dependencies
```

### Remove All Borrowed Components from Phase

```powershell
# Restore Phase 1 to original state (remove all borrowings)
.\restore-phase-original.ps1 -Phase 1

# Removes: All components borrowed FROM other phases
# Keeps: All native Phase 1 components
```

### Selective Rollback

```powershell
# Keep ai-dashboard borrowed, remove cloud-bridge borrowed
.\unborrow-component.ps1 -ComponentName "cloud-bridge" -FromPhase 1
```

---

## Checking What's Borrowed

### List All Borrowed Components

```powershell
# Show all borrowed components in current phase
Get-BorrowedComponents

# Output:
# Borrowed Components:
# ├── ai-dashboard (from Phase 3)
# │   └── Depends on: .NET 4.8, Windows Event Log
# ├── vault-dynamics (from Phase 1)
# │   └── Depends on: .NET 4.6.1
# └── performance-ai (from Phase 2)
#     └── Depends on: security-engine
```

### Check Specific Component Borrow Status

```powershell
Get-BorrowedComponents -Filter "ai-dashboard"

# Output:
# Component: ai-dashboard
# Status: Borrowed
# From Phase: 3
# Borrowed To: 1
# Borrow Date: 2024-01-15 10:30:45
# Version: 2.1.0
# Status: ✓ Healthy
```

---

## Troubleshooting Borrowed Components

### Borrowed Component Won't Start

```powershell
# Diagnose borrowed component issues
Test-BorrowedComponent -Name "ai-dashboard" -Verbose

# Output:
# Testing ai-dashboard (borrowed from Phase 3)...
# ✓ Files present
# ✓ .NET 4.8 installed
# ✗ Port 8080 in use by another process
# ✓ Configuration valid
# 
# Issue: Port conflict on 8080
# Solution: Change port in config.json or stop conflicting process
```

### Dependency Lost After System Update

```powershell
# Repair borrowed component dependencies
Repair-BorrowedComponent -Name "ai-dashboard"

# Checks all dependencies
# Reinstalls any missing ones
# Verifies configuration
```

### Performance Issues with Borrowed Component

```powershell
# Check resource usage of borrowed component
Get-ComponentResourceUsage -Name "ai-dashboard"

# Optimize: Reduce refresh interval, disable unused features
# Edit: C:\Program Files\HELIOS\ai-dashboard\config.json
```

---

## Best Practices for Borrowing

1. **Always check prerequisites first**

   ```powershell
   .\check-borrowing-prerequisites.ps1 -ComponentName "name" -ToPhase "phase"
   ```

2. **Test borrowed component immediately after installation**

   ```powershell
   .\components\<component-name>\test-component.ps1
   ```

3. **Keep a record of borrowed components**

   ```powershell
   Get-BorrowedComponents | Export-Csv "borrowed-components.csv"
   ```

4. **Don't borrow too many components** (increases complexity and conflicts)
   - Safe: 2-3 borrowed components
   - Risky: 5+ borrowed components

5. **Document your custom setup**

   ```
   # My HELIOS Setup
   Phase 0: security-engine (native)
   Phase 1: vault-dynamics (native), analytics-core (native)
   Phase 2: performance-ai (native)
   Borrowed: ai-dashboard from Phase 3
   
   Notes: This setup provides monitoring without cloud features
   ```

6. **Test after system updates**

   ```powershell
   Test-AllBorrowedComponents -Verbose
   ```

7. **Backup before major borrows**

   ```powershell
   .\backup-components.ps1 -BackupPath "C:\Backups\pre-borrow-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
   ```

---

## Advanced: Creating Custom Borrow Profiles

### Create and Save Borrow Profile

```powershell
# Create a profile for your specific setup
New-BorrowProfile -Name "LightweightMonitoring" `
                  -Components @("security-engine", "vault-dynamics", "ai-dashboard") `
                  -Description "Minimal setup with monitoring"

# This can be applied to any system later:
Apply-BorrowProfile -ProfileName "LightweightMonitoring"
```

### Save Your Custom Configuration

```powershell
# Export your current component setup
Export-ComponentConfiguration -Path "C:\MySetups\my-config.json"

# Contents:
# {
#   "nativeComponents": ["security-engine", "vault-dynamics", "analytics-core"],
#   "borrowedComponents": [
#     {
#       "name": "ai-dashboard",
#       "fromPhase": 3,
#       "toPhase": 1,
#       "borrowDate": "2024-01-15T10:30:45Z"
#     }
#   ],
#   "totalSize": "1.2 GB",
#   "installationTime": "18 minutes"
# }

# Re-apply this setup to another system:
Import-ComponentConfiguration -Path "C:\MySetups\my-config.json" -AutoInstall
```

---

## Quick Reference: Borrowing Command Syntax

```powershell
# Basic borrow
.\borrow-component.ps1 -ComponentName "component-name" `
                       -FromPhase <number> `
                       -ToPhase <number>

# Borrow with auto-dependencies
.\borrow-component.ps1 -ComponentName "component-name" `
                       -FromPhase 3 `
                       -ToPhase 1 `
                       -AutoInstallDependencies

# Borrow with minimal dependencies (skip optional deps)
.\borrow-component.ps1 -ComponentName "component-name" `
                       -FromPhase 3 `
                       -ToPhase 1 `
                       -MinimalDependencies

# Check if can borrow
.\check-borrowing-prerequisites.ps1 -ComponentName "component-name" `
                                     -ToPhase <number>

# Remove borrowed component
.\unborrow-component.ps1 -ComponentName "component-name" `
                         -FromPhase <number>

# List borrowed components
Get-BorrowedComponents

# Test borrowed component
Test-BorrowedComponent -Name "component-name"

# Get borrow history
Get-BorrowHistory
```

---

## Summary

Borrowing allows you to:

- ✅ Use specific components without full phases
- ✅ Build custom lightweight configurations
- ✅ Save installation time and disk space
- ✅ Maintain full functionality of borrowed components
- ✅ Easily rollback changes

See **ADVANCED_BORROWING_SCENARIOS.md** for complex real-world examples.
