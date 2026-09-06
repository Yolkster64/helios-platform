# Component Dependencies

Complete dependency mapping showing which components depend on which others, and whether they can work without those dependencies.

---

## Dependency Overview

### Mandatory vs Optional Dependencies

**Mandatory (Hard):** Component cannot function without this
**Optional (Soft):** Component works alone, but features enhance with this
**System:** Built into Windows, no installation needed

---

## Dependency Graph

```
SYSTEM DEPENDENCIES (All Windows)
|- .NET Framework / .NET Core (required by all)
|- Windows Event Log (required by all)
|- Windows CNG Cryptography (required by security and vault)

COMPONENT DEPENDENCIES

|- security-engine (Phase 0) [FOUNDATION]
|  |- .NET Core 3.1 or .NET 6.0 (MANDATORY)
|  |- Windows Event Log (MANDATORY - system)
|  +- SQL Server (OPTIONAL - uses SQLite if not present)
|
|- vault-dynamics (Phase 1)
|  |- .NET Framework 4.6.1+ (MANDATORY)
|  |- Windows CNG (MANDATORY - system cryptography)
|  +- HSM/TPM (OPTIONAL - uses software if not present)
|
|- analytics-core (Phase 1)
|  |- .NET Framework 4.6.1+ (MANDATORY)
|  +- SQL Server Express (OPTIONAL - uses embedded DB if not present)
|
|- performance-ai (Phase 2) [DEPENDS ON PHASE 0!]
|  |- security-engine (MANDATORY)
|  |- .NET Framework 4.8+ (MANDATORY)
|  +- TensorFlow (MANDATORY - bundled)
|
|- ai-dashboard (Phase 3) [NO DEPENDENCIES!]
|  |- .NET Framework 4.8+ (MANDATORY)
|  +- Windows Event Log (MANDATORY - system)
|
+- cloud-bridge (Phase 3) [DEPENDS ON PHASE 0 & 1!]
   |- security-engine (MANDATORY)
   |- vault-dynamics (MANDATORY)
   +- Cloud SDK (bundled)
```

---

## Component Dependency Details

### SECURITY-ENGINE (Phase 0)

**Type:** Foundation - All other components may depend on this

| Dependency | Type | Version | Required | Fallback |
|-----------|------|---------|----------|----------|
| .NET Core | Runtime | 3.1 or 6.0+ | YES | No |
| .NET Framework | Runtime | 4.6.1+ | YES | No |
| Windows Event Log | System | Any | YES | No |
| SQL Server | Database | 2016+ | NO | SQLite (embedded) |
| Azure AD | Optional | Any | NO | Local auth only |

**Can work without dependencies?**

- Without .NET Core 3.1: NO - Will not run
- Without Windows Event Log: NO - Cannot log
- Without SQL Server: YES - Uses SQLite
- Without Azure AD: YES - Uses local auth

**Functions requiring what:**

```
Local Authentication          - Works always
Multi-factor Authentication   - Needs Azure AD or RADIUS provider
LDAP Integration             - Works always  
Audit Logging               - Works always (to Event Log)
Access Control              - Works always
```

---

### VAULT-DYNAMICS (Phase 1)

**Type:** Encryption - No other components depend on this

| Dependency | Type | Version | Required | Fallback |
|-----------|------|---------|----------|----------|
| .NET Framework | Runtime | 4.6.1+ | YES | No |
| Windows CNG | Crypto API | Built-in | YES | No |
| HSM (Hardware Security Module) | Hardware | Optional | NO | Software storage |
| TPM 2.0 | Hardware | Windows 10+ | NO | Software storage |

**Can work without dependencies?**

- Without .NET Framework 4.6.1: NO - Will not run
- Without Windows CNG: NO - Cannot encrypt
- Without HSM: YES - Uses software storage
- Without TPM: YES - Uses software storage

---

### ANALYTICS-CORE (Phase 1)

**Type:** Data Analysis - No other components depend on this

| Dependency | Type | Version | Required | Fallback |
|-----------|------|---------|----------|----------|
| .NET Framework | Runtime | 4.6.1+ | YES | No |
| SQL Server Express | Database | Free tier | NO | Embedded SQLite |
| Reporting Services | Optional | Any | NO | Manual export |

**Can work without dependencies?**

- Without .NET Framework 4.6.1: NO - Will not run
- Without SQL Server Express: YES - Uses embedded SQLite
- Without Reporting Services: YES - Export as CSV

---

### PERFORMANCE-AI (Phase 2)

**Type:** AI Optimization - DEPENDS ON security-engine

| Dependency | Type | Version | Required | Auto-Install |
|-----------|------|---------|----------|--------------|
| **security-engine** | **Component** | **1.2.0+** | **YES** | **Auto (if missing)** |
| .NET Framework | Runtime | 4.8+ | YES | No - May need manual |
| TensorFlow | ML Framework | 2.10+ | YES | Auto (bundled) |
| NumPy/SciPy | Python libs | Latest | YES | Auto (bundled) |
| GPU Support (NVIDIA/AMD) | Hardware | Optional | NO | Works on CPU |

**Hard dependency on security-engine because:**

- User authentication and authorization
- Audit logging of all optimization changes
- Session management for multiple users
- Secure encrypted configuration storage

**Can work without security-engine?** NO - Installation fails

**Error if not present:**

```
Error: security-engine (v1.2.0+) is a mandatory dependency for performance-ai
Solution: Install security-engine first
```

**Installation order:**

```
1. Install security-engine (Phase 0) first
   |
2. Install performance-ai (Phase 2)
   |
3. TensorFlow and models auto-install
   |
4. AI optimizer is ready
```

---

### AI-DASHBOARD (Phase 3)

**Type:** GUI Dashboard - NO dependencies on other HELIOS components!

| Dependency | Type | Version | Required | Fallback |
|-----------|------|---------|----------|----------|
| .NET Framework | Runtime | 4.8+ | YES | No |
| Windows Event Log | System | Any | YES | No |

**Can it be installed standalone?** YES - Completely independent

**Works without .NET 4.8?** NO - Will not run
**Works without Windows Event Log?** NO - Cannot display events

**Limitations when standalone (without security-engine):**

```
Feature                | With security-engine | Standalone |
User authentication    | Multi-user, RBAC    | Single user |
Access control        | Enforced             | None        |
Audit logging         | Complete             | Basic       |
MFA support           | Yes                  | No          |
Role-based features   | Yes                  | No          |
```

---

### CLOUD-BRIDGE (Phase 3)

**Type:** Cloud Integration - DEPENDS ON security-engine AND vault-dynamics

| Dependency | Type | Version | Required | Auto-Install |
|-----------|------|---------|----------|--------------|
| **security-engine** | **Component** | **1.2.0+** | **YES** | Warn (may fail) |
| **vault-dynamics** | **Component** | **1.5.0+** | **YES** | Warn (may fail) |
| Azure SDK / AWS SDK | Software | Latest | YES | Auto (bundled) |
| Internet Connection | Network | Any | YES | Required |

**Why needs security-engine:**

- Identity federation with Azure AD / AWS IAM
- Access control to cloud resources
- Audit logging of cloud operations

**Why needs vault-dynamics:**

- Encrypting credentials before cloud upload
- Secure key exchange with cloud
- Encrypted backup storage

**Can work without both?** NO - Installation fails

**Installation order:**

```
1. Install security-engine (Phase 0)
   |
2. Install vault-dynamics (Phase 1)
   |
3. Install cloud-bridge (Phase 3)
   |
4. Cloud SDKs auto-install
   |
5. Connect to Azure/AWS/GCP
```

---

## Dependency Conflict Matrix

**Which components conflict with each other:**

| Component A | Component B | Conflict | Why | Solution |
|-----------|-----------|---------|-----|----------|
| vault-local-mode | vault-cloud-mode | CONFLICT | Both control key storage differently | Choose one mode: local OR cloud |
| performance-ai | custom-scheduler | WARNING | Both try to manage CPU scheduling | Disable custom scheduler |
| analytics-core | custom-reporter | WARNING | Both log same events | Configure separate event types |

**Other combinations:** All compatible - no issues

---

## Version Compatibility

| Component | Min Version | Recommended | Status |
|-----------|------------|------------|--------|
| security-engine | 1.0.0 | 1.2.0+ | Stable |
| vault-dynamics | 1.3.0 | 1.5.2+ | Stable |
| performance-ai needs | 1.2.0+ | 1.2.0+ | Beta |
| cloud-bridge needs | 1.2.0+ & 1.5.0+ | Latest | Alpha |
| ai-dashboard | No deps | 2.1.0 | Stable |
| analytics-core | No deps | 1.0.3 | Stable |

**.NET Framework Requirements:**

```
All components: Minimum 4.6.1, Recommended 4.8+
```

---

## Checking Dependencies

### Check Before Installing

```powershell
# Verify all dependencies
.\check-dependencies.ps1 -ComponentName "performance-ai"

# Output:
# Checking performance-ai dependencies...
# [OK] .NET Framework 4.8
# [OK] security-engine 1.2.0 
# [OK] TensorFlow (bundled)
# Status: Ready to install
```

### Get Dependency Tree

```powershell
Get-DependencyTree -ComponentName "performance-ai" -Recursive

# Output:
# performance-ai
# |- [REQUIRED] security-engine >= 1.2.0
# |  |- [REQUIRED] .NET Core 3.1
# |  +- [OPTIONAL] Azure AD
# |- [REQUIRED] .NET Framework 4.8
# +- [REQUIRED] TensorFlow (bundled)
```

---

## Quick Lookup: Can I Install X Without Y?

| Component X | Without Component Y | Answer | Notes |
|-----------|-------------------|--------|-------|
| vault-dynamics | security-engine | YES | Independent |
| performance-ai | security-engine | NO | Hard dependency |
| ai-dashboard | security-engine | YES | Works alone |
| cloud-bridge | security-engine | NO | Hard dependency |
| cloud-bridge | vault-dynamics | NO | Hard dependency |
| analytics-core | SQL Server | YES | Uses embedded DB |
| performance-ai | vault-dynamics | YES | Not required |
| All | .NET 4.8 | NO | Runtime needed |

---

## Dependency Troubleshooting

### Component Won't Install - Missing Dependency

```powershell
# Find what's missing
Get-MissingDependencies -ComponentName "performance-ai"

# Install the missing component
.\components\security-engine\install.ps1

# Then try again
.\components\performance-ai\install.ps1
```

### Component Crashes on Startup

```powershell
# Verify all dependencies are correct version
Test-ComponentDependencies -ComponentName "performance-ai" -Verbose

# May need to upgrade
.\components\security-engine\install.ps1 -Upgrade
```

### Dependency Version Conflict

```powershell
# Show installed vs required
Get-DependencyMismatch -ComponentName "cloud-bridge"

# Auto-fix with upgrades
.\install.ps1 -ComponentName "cloud-bridge" -UpgradeDependencies
```

---

## Summary Table

| Component | Depends On | Can Install Solo | Min Deps |
|-----------|-----------|-----------------|----------|
| security-engine | Nothing | YES | .NET Core 3.1 |
| vault-dynamics | Nothing | YES | .NET 4.6.1 |
| analytics-core | Nothing | YES | .NET 4.6.1 |
| performance-ai | security-engine | NO* | Phase 0 |
| ai-dashboard | Nothing | YES | .NET 4.8 |
| cloud-bridge | sec-engine, vault | NO* | Phase 0+1 |

*Can install to system, but won't work without dependencies

---

See **COMPONENT_COMPATIBILITY_MATRIX.md** for which components work together best.
