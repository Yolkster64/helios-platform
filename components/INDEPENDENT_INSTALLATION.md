# Independent Installation Guide

Learn how to install and use HELIOS components completely standalone, without needing entire phases or other components.

---

## Standalone Installation Overview

Any component marked **Fully Standalone** in the COMPONENT_CATALOG.md can be installed without:

- Other phases
- Other components
- Full platform

**Fully Standalone Components:**

- ✅ security-engine
- ✅ vault-dynamics
- ✅ analytics-core
- ✅ ai-dashboard

**Partially Standalone** (needs one or more specific components):

- ⚠️ performance-ai (needs security-engine)
- ⚠️ cloud-bridge (needs security-engine + vault-dynamics)

---

## Scenario 1: Just AI Dashboard

**Question:** "Can I install just the dashboard without all phases?"

**Answer:** ✅ **YES** - Fully standalone, zero dependencies on other HELIOS components

### Installation

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\install.ps1

# That's it! Dashboard is ready in 5 minutes
# Access: http://localhost:8080
```

### Configuration for Standalone

**Default single-user mode:**

```json
{
  "security": {
    "requireAuth": false,
    "defaultUser": "admin",
    "sessionTimeout": 0
  },
  "features": {
    "multiuser": false,
    "roleBasedAccess": false
  }
}
```

### What You Get

```
✅ Real-time system monitoring
✅ Performance metrics dashboard
✅ System health visualization
✅ Modern web interface
✅ Alert management
✅ No user authentication (single user)
✅ No access control
```

### What You Don't Get

```
❌ Multi-user support
❌ Role-based access control
❌ Audit logging
❌ User authentication
```

### Add Security Later

If you later want multi-user access, just install security-engine:

```powershell
# Later, when you want users and auth
.\components\security-engine\install.ps1

# Dashboard automatically uses it after restart
# Now supports multi-user, RBAC, audit logging
```

---

## Scenario 2: Just Vault Encryption

**Question:** "Can I use encryption (Phase 1) without all the other stuff?"

**Answer:** ✅ **YES** - Fully standalone, works without security-engine or anything else

### Installation

```powershell
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics
.\install.ps1

# Standalone vault is ready!
```

### Usage

Encrypt files or data with just vault:

```powershell
# PowerShell example
$vault = New-Object HeliosPlatform.VaultDynamics.VaultClient
$vault.Initialize("master-password-123")

# Encrypt a file
$vault.EncryptFile("C:\MyData\Document.pdf")
# Result: C:\MyData\Document.pdf.encrypted

# Encrypt a database connection string
$connStr = "Server=localhost;Database=MyDB;Password=secret"
$encrypted = $vault.EncryptString($connStr)
```

### Configuration for Standalone

```json
{
  "vault": {
    "masterPasswordHash": "bcrypt_hash_here",
    "keyRotationEnabled": true,
    "rotationIntervalDays": 90
  },
  "storage": {
    "type": "filesystem",
    "hsmEnabled": false,
    "tpmEnabled": false
  },
  "audit": {
    "enabled": false
  }
}
```

### What You Get

```
✅ File encryption/decryption
✅ String encryption
✅ Secure key management
✅ Key rotation policies
✅ Standalone operation
```

### What You Don't Get

```
❌ User access control (anyone with master password can decrypt)
❌ Audit logging of operations
❌ Multi-user scenarios
❌ HSM support required (uses software keys)
```

### Add Security Later

```powershell
# If you want access control and audit logging
.\components\security-engine\install.ps1

# Vault now integrates with security system
```

---

## Scenario 3: Just Security (Foundation Only)

**Question:** "Can I install just the security system without optimization?"

**Answer:** ✅ **YES** - Fully standalone

### Installation

```powershell
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# Foundation security is ready
```

### Usage

Create users, authenticate, control access:

```powershell
$security = New-Object HeliosPlatform.SecurityEngine.SecurityManager

# Create users
$security.CreateUser("john.doe", "email@company.com")
$security.CreateUser("jane.smith", "jane@company.com")

# Assign roles
$security.AssignRole("john.doe", "Administrator")
$security.AssignRole("jane.smith", "Operator")

# Authenticate user
$auth = $security.AuthenticateUser("john.doe", "password")
if ($auth.Success) {
    Write-Host "User logged in. Session: $($auth.SessionToken)"
}
```

### Configuration for Standalone

```json
{
  "authentication": {
    "sessionTimeout": 3600,
    "enableMFA": false,
    "passwordPolicy": {
      "minLength": 8,
      "requireNumbers": true,
      "expiryDays": 90
    }
  },
  "database": {
    "type": "embedded",
    "path": "C:\\Program Files\\HELIOS\\security-engine\\data"
  },
  "audit": {
    "enabled": false
  }
}
```

### What You Get

```
✅ User authentication
✅ Role-based access control
✅ Local user management
✅ Password policies
✅ Session management
```

### What You Don't Get

```
❌ Cloud directory (Azure AD, LDAP)
❌ Multi-factor authentication (no provider)
❌ Audit logging
❌ Compliance reporting
```

---

## Scenario 4: Just Analytics

**Question:** "Can I collect and analyze data without all the other components?"

**Answer:** ✅ **YES** - Fully standalone

### Installation

```powershell
cd C:\Users\ADMIN\helios-platform\components\analytics-core
.\install.ps1

# Analytics engine is ready
```

### Usage

Collect and query data:

```powershell
$analytics = New-Object HeliosPlatform.AnalyticsCore.AnalyticsEngine

# Collect metrics
$metrics = @{
    Timestamp = Get-Date
    CPU = 45.2
    Memory = 62.8
    Disk = 78.1
}
$analytics.RecordMetrics($metrics)

# Query data
$report = $analytics.CreateReport(
    "Select * from metrics where Timestamp > @Start",
    @{ Start = (Get-Date).AddDays(-7) }
)

# Export
$report.ExportToExcel("C:\Reports\metrics.xlsx")
```

### Configuration for Standalone

```json
{
  "database": {
    "type": "embedded",
    "path": "C:\\Program Files\\HELIOS\\analytics-core\\data"
  },
  "collection": {
    "interval": 60,
    "retention": 365
  },
  "reporting": {
    "formats": ["CSV", "Excel", "JSON"]
  }
}
```

### What You Get

```
✅ Data collection
✅ SQL query builder
✅ Report generation
✅ Export to Excel/CSV
✅ Embedded database
```

### What You Don't Get

```
❌ User authentication
❌ Audit logging
❌ Enterprise SQL Server
❌ Advanced visualization
```

---

## Scenario 5: Just Performance Optimization

**Question:** "Can I use AI performance tuning without everything else?"

**Answer:** ⚠️ **PARTIAL** - Needs security-engine

### Why Needs security-engine

The performance AI system records all optimization changes for audit and compliance. Even in standalone mode, it needs security-engine for:

- Access control (who can enable/disable optimizations)
- Change tracking (what was changed and why)
- Session management (multi-user scenarios)

### Installation

```powershell
# Step 1: Install security foundation first
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# Step 2: Install performance AI
cd ..\performance-ai
.\install.ps1

# Performance AI is now ready
```

### Configuration for Standalone

```json
{
  "learningPhase": {
    "enabled": true,
    "durationHours": 72
  },
  "optimization": {
    "level": "balanced",
    "autoTuning": true,
    "maxChangePercent": 20,
    "backupBeforeTuning": true
  },
  "security": {
    "auditEnabled": false,
    "multiUserMode": false
  }
}
```

### Usage

```powershell
$perf = New-Object HeliosPlatform.PerformanceAI.PerformanceOptimizer

# Get recommendations
$recs = $perf.GetOptimizationRecommendations()

# Apply optimization
$result = $perf.ApplyOptimization($recs[0].Id)

# Check results
Write-Host "New performance score: $($result.NewScore)"
```

### What You Get

```
✅ AI-powered optimization
✅ Performance monitoring
✅ Automatic tuning
✅ Bottleneck detection
✅ Anomaly detection
```

### What You Don't Get

```
❌ Multi-user role management (security-engine provides single user)
❌ Complex audit trails
❌ Enterprise compliance features
```

---

## Standalone Installation Checklist

For any component you want to install standalone:

### Before Installation

```
[ ] Component marked "Fully Standalone" or accept "Partial" dependency
[ ] Check minimum .NET Framework version (see COMPONENT_CATALOG.md)
[ ] Verify disk space available
[ ] Verify ports not in use (dashboard needs 8080, etc.)
[ ] Administrator privileges available
[ ] No conflicting applications running
```

### During Installation

```
.\install.ps1

# Options for standalone:
.\install.ps1 -MinimalDeps         # Skip optional dependencies
.\install.ps1 -Silent              # No prompts
.\install.ps1 -NoStartService      # Don't auto-start
```

### After Installation

```powershell
# Test the component
.\test-component.ps1

# Output should be:
# ✓ All systems operational
# ✓ Service running
# ✓ Configuration valid
# ✓ Port available
```

---

## Standalone Prerequisites

### For All Components

**Required:**

- Windows Server 2016 or later / Windows 8.1 or later
- Administrator privileges
- 500 MB free disk space (varies by component)
- Internet connectivity (for downloading bundled dependencies)

**Minimum .NET:**

```
security-engine:    .NET Core 3.1 or .NET Framework 4.6.1
vault-dynamics:     .NET Framework 4.6.1
analytics-core:     .NET Framework 4.6.1
performance-ai:     .NET Framework 4.8
ai-dashboard:       .NET Framework 4.8
```

### Component-Specific Prerequisites

**ai-dashboard:**

- Windows Event Log (system component)
- Open port 8080 (configurable)

**vault-dynamics:**

- Windows CNG (built-in crypto)
- Access to file system for key storage

**analytics-core:**

- SQL Server Express (free) OR embedded database
- Disk space for collected data

**performance-ai:**

- Requires security-engine (see dependencies)
- Multi-core processor recommended
- 4 GB RAM recommended

**security-engine:**

- Windows Event Log
- SQL Server Express (optional) OR embedded database

---

## Standalone Configuration Templates

### Minimal Configuration (Smallest Footprint)

Use this for space-constrained environments:

```json
{
  "features": {
    "advancedFeatures": false,
    "analyticsEnabled": false,
    "auditingEnabled": false
  },
  "performance": {
    "maxMemoryUsage": "256MB",
    "compressionEnabled": true
  },
  "security": {
    "requireAuth": false
  }
}
```

### Standard Configuration (Balanced)

Use this for typical deployments:

```json
{
  "features": {
    "advancedFeatures": true,
    "analyticsEnabled": true,
    "auditingEnabled": false
  },
  "performance": {
    "maxMemoryUsage": "1GB",
    "compressionEnabled": true
  }
}
```

### Enterprise Configuration (Full Features)

Use this when adding more components later:

```json
{
  "features": {
    "advancedFeatures": true,
    "analyticsEnabled": true,
    "auditingEnabled": true
  },
  "performance": {
    "maxMemoryUsage": "2GB",
    "compressionEnabled": true
  },
  "integrations": {
    "enableAllInterfaces": true
  }
}
```

---

## Standalone vs Full Platform

| Aspect | Standalone | Full Platform |
|--------|-----------|--------------|
| Installation Time | 5-10 minutes | 30+ minutes |
| Disk Space | 150-400 MB | 1.5 GB |
| Performance Impact | Minimal | Moderate |
| Features Available | Component only | All |
| Complexity | Low | High |
| Adding to full later | ✅ Easy | N/A |

---

## Upgrading from Standalone to Full

If you start with just a dashboard and later want the full platform:

```powershell
# Current: Just ai-dashboard installed

# Step 1: Add security
.\components\security-engine\install.ps1

# Step 2: Add vault
.\components\vault-dynamics\install.ps1

# Step 3: Add analytics
.\components\analytics-core\install.ps1

# Step 4: Add performance AI
.\components\performance-ai\install.ps1

# Step 5: Add cloud bridge
.\components\cloud-bridge\install.ps1

# Dashboard automatically integrates with all new components!
```

---

## File Locations for Standalone

### ai-dashboard Standalone

```
C:\Program Files\HELIOS\ai-dashboard\
├── bin\ (executable and DLLs)
├── config.json
├── logs\
├── data\ (metrics database)
└── www\ (web files)
```

### vault-dynamics Standalone

```
C:\Program Files\HELIOS\vault-dynamics\
├── bin\
├── config.json
├── keys\ (encrypted keys)
├── logs\
└── backups\
```

### security-engine Standalone

```
C:\Program Files\HELIOS\security-engine\
├── bin\
├── config.json
├── database\ (user database)
├── logs\
└── policies\
```

### analytics-core Standalone

```
C:\Program Files\HELIOS\analytics-core\
├── bin\
├── config.json
├── data\ (analytics database)
├── logs\
└── reports\
```

### performance-ai Standalone

```
C:\Program Files\HELIOS\performance-ai\
├── bin\
├── config.json
├── ml-models\
├── logs\
└── data\
```

---

## Quick Start Templates

### Template 1: Dashboard Only

```powershell
# Install dashboard, nothing else
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\install.ps1 -Silent

# Access at http://localhost:8080
```

### Template 2: Encryption Only

```powershell
# Install vault encryption standalone
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics
.\install.ps1 -Silent -MasterPassword "YourPassword123"

# Start using for encryption
```

### Template 3: Analytics Only

```powershell
# Install analytics for data collection
cd C:\Users\ADMIN\helios-platform\components\analytics-core
.\install.ps1 -Silent

# Start collecting metrics
```

### Template 4: Security + Dashboard

```powershell
# Foundation security + GUI dashboard
.\components\security-engine\install.ps1 -Silent
.\components\ai-dashboard\install.ps1 -Silent

# Multi-user dashboard with authentication
```

---

## Uninstalling Standalone

Uninstall is clean and complete:

```powershell
cd C:\Users\ADMIN\helios-platform\components\<component-name>
.\uninstall.ps1

# All files and registry entries removed
# Database can be preserved with -PreserveData flag
.\uninstall.ps1 -PreserveData
```

---

## See Also

- **BORROWING_GUIDE.md** - Add components from other phases
- **COMPONENT_CATALOG.md** - Detailed component info
- **COMPONENT_DEPENDENCIES.md** - What each component needs
