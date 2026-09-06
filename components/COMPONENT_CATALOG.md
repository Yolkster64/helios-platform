# HELIOS Component Catalog

Complete reference for all components available in the HELIOS Platform. Each component is independently installable and can be borrowed between phases.

---

## AI Dashboard

**Phase:** 3  
**Type:** GUI Dashboard & System Monitoring  
**Independent Use:** ✅ **YES** (Fully Standalone)  
**Version:** 2.1.0  
**Status:** Stable

### What It Does

Web-based GUI dashboard for monitoring HELIOS system performance. Provides real-time metrics, alerts, and system health visualization. Beautiful modern interface with dark mode support.

### Key Features

- Real-time system monitoring (CPU, memory, disk, network)
- Performance metrics dashboard
- Alert management and notifications
- System health scoring
- Historical data trending
- Customizable widgets
- Multi-user support with role-based access

### System Requirements

- **OS:** Windows Server 2019 or later / Windows 10 Pro or later
- **.NET Framework:** 4.8 or later
- **RAM:** Minimum 2 GB, Recommended 4+ GB
- **Disk:** 245 MB installation + 100 MB for data/logs
- **Port:** 8080 (configurable)
- **Browser:** Chrome 90+, Edge 90+, Firefox 88+

### Dependencies

| Dependency | Type | Required? | Can Work Without? |
|-----------|------|-----------|------------------|
| .NET Framework 4.8+ | System | Yes | No |
| Windows Event Log | System | Yes | No |
| IIS (optional) | Application | No | Yes - Uses embedded server |

### Size & Installation Time

- **Download Size:** 156 MB
- **Installed Size:** 245 MB
- **Installation Time:** 5-10 minutes
- **Uninstall Time:** 2 minutes

### Installation Procedure

```powershell
# Method 1: PowerShell (Recommended)
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\install.ps1

# Method 2: With custom port
.\install.ps1 -Port 9000

# Method 3: With SSL/TLS
.\install.ps1 -UseSSL -CertificatePath "C:\certs\dashboard.pfx"

# Method 4: Silent installation
.\install.ps1 -Silent
```

### Configuration

**Config File:** `C:\Program Files\HELIOS\ai-dashboard\config.json`

```json
{
  "server": {
    "port": 8080,
    "host": "localhost",
    "useSSL": false,
    "certificatePath": null
  },
  "display": {
    "theme": "dark",
    "refreshInterval": 5000,
    "chartHistorySize": 100
  },
  "security": {
    "requireAuth": true,
    "sessionTimeout": 3600,
    "allowRemoteAccess": false
  },
  "notifications": {
    "enabled": true,
    "emailAlerts": false,
    "slackWebhook": null
  }
}
```

### Usage

After installation, access at: `http://localhost:8080`

Default credentials:

- **Username:** admin
- **Password:** (Generated during installation, check: `C:\Program Files\HELIOS\ai-dashboard\initial-password.txt`)

Change password immediately:

```
Dashboard → Settings → Security → Change Password
```

### Troubleshooting

- **Can't access dashboard:** Check if port 8080 is open. See component README.
- **High memory usage:** Reduce chart history in config.json
- **Slow performance:** Check system resources and reduce refresh interval

### File Locations

```
C:\Program Files\HELIOS\ai-dashboard\
├── bin\
│   ├── dashboard.exe
│   ├── dashboard.dll
│   └── dependencies\
├── config.json
├── logs\
│   ├── dashboard.log
│   └── errors.log
├── data\
│   └── metrics.db
└── www\
    ├── index.html
    ├── css\
    └── js\
```

### Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\ai-dashboard
.\uninstall.ps1

# Or preserve configuration
.\uninstall.ps1 -PreserveConfig
```

---

## Vault Dynamics

**Phase:** 1  
**Type:** Advanced Encryption System  
**Independent Use:** ✅ **YES** (Fully Standalone)  
**Version:** 1.5.2  
**Status:** Stable

### What It Does

Enterprise-grade encryption and key management system. Securely encrypts/decrypts sensitive data using AES-256-GCM. Manages encryption keys with optional hardware security module (HSM) support.

### Key Features

- AES-256-GCM encryption standard
- Secure key generation and management
- Key rotation policies (automatic or manual)
- Secure key storage with optional HSM
- Encryption for files, database fields, or custom data
- Audit logging for all cryptographic operations
- Recovery key backup system

### System Requirements

- **OS:** Windows Server 2016 or later / Windows 8.1 or later
- **.NET Framework:** 4.6.1 or later
- **RAM:** Minimum 1 GB, Recommended 2+ GB
- **Disk:** 89 MB installation + 10 MB per 1000 keys
- **Crypto API:** Windows Cryptographic Service Provider (built-in)

### Dependencies

| Dependency | Type | Required? | Can Work Without? |
|-----------|------|-----------|------------------|
| Windows CNG (Cryptography) | System | Yes | No |
| .NET Framework 4.6.1+ | System | Yes | No |
| HSM (optional) | Hardware | No | Yes - Uses TPM fallback |

### Size & Installation Time

- **Download Size:** 67 MB
- **Installed Size:** 89 MB
- **Installation Time:** 2-3 minutes
- **Uninstall Time:** 1 minute

### Installation Procedure

```powershell
# Basic installation
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics
.\install.ps1

# With HSM support
.\install.ps1 -UseHSM -HSMProvider "Thales Luna"

# With TPM (Windows only)
.\install.ps1 -UseTPM

# Silent installation
.\install.ps1 -Silent -MasterPassword "YourSecurePassword123!"
```

### Configuration

**Config File:** `C:\Program Files\HELIOS\vault-dynamics\config.json`

```json
{
  "vault": {
    "masterPasswordHash": "bcrypt_hash_here",
    "keyRotationEnabled": true,
    "rotationIntervalDays": 90,
    "backupPath": "C:\\Backups\\vault-keys"
  },
  "encryption": {
    "algorithm": "AES-256-GCM",
    "keySize": 256,
    "tagSize": 16
  },
  "storage": {
    "type": "filesystem",
    "path": "C:\\Program Files\\HELIOS\\vault-dynamics\\keys",
    "hsmEnabled": false,
    "tpmEnabled": false
  },
  "audit": {
    "enabled": true,
    "logPath": "C:\\Program Files\\HELIOS\\vault-dynamics\\logs",
    "retentionDays": 365
  }
}
```

### Usage Examples

#### Encrypt a File

```powershell
# PowerShell example
$vault = New-Object HeliosPlatform.VaultDynamics.VaultClient
$vault.Initialize("your-master-password")

$encrypted = $vault.EncryptFile("C:\sensitive-data\document.pdf")
# Result saved to: C:\sensitive-data\document.pdf.encrypted
```

#### Decrypt a File

```powershell
$vault.DecryptFile("C:\sensitive-data\document.pdf.encrypted", 
                   "C:\sensitive-data\document.pdf.decrypted")
```

#### Encrypt Database String

```powershell
$connectionString = "Server=localhost;User=admin;Password=secret"
$encrypted = $vault.EncryptString($connectionString)
# Store $encrypted in config file
```

#### List All Keys

```powershell
$keys = $vault.GetAllKeyMetadata()
foreach ($key in $keys) {
    Write-Host "Key: $($key.Id) - Created: $($key.CreatedDate)"
}
```

### Backup Encryption Keys

```powershell
# Backup all keys to encrypted backup
$vault.CreateBackup("C:\Backups\vault-backup-$(Get-Date -Format 'yyyy-MM-dd').bak")

# Restore from backup
$vault.RestoreBackup("C:\Backups\vault-backup-2024-01-15.bak")
```

### File Locations

```
C:\Program Files\HELIOS\vault-dynamics\
├── bin\
│   ├── vault.exe
│   ├── vault.dll
│   └── crypto\
├── config.json
├── keys\
│   ├── master-key.encrypted
│   ├── key-store.db
│   └── backups\
├── logs\
│   └── vault.log
└── certificates\
    └── tpm-cert.pem
```

### Troubleshooting

- **Master password required but none set:** Run `.\configure-master-password.ps1`
- **Key rotation failed:** Check permissions on key storage directory
- **HSM not connecting:** Verify HSM drivers and network connectivity

### Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\vault-dynamics
.\uninstall.ps1

# Preserve encrypted keys (for recovery later)
.\uninstall.ps1 -PreserveKeys -BackupPath "C:\Vault-Backup"
```

---

## Security Engine

**Phase:** 0  
**Type:** Foundation Security System  
**Independent Use:** ✅ **YES** (Fully Standalone)  
**Version:** 1.2.0  
**Status:** Stable

### What It Does

Core security foundation for the HELIOS Platform. Provides authentication, authorization, intrusion detection, and security policy enforcement. All other components depend on this for security operations.

### Key Features

- User authentication and session management
- Role-based access control (RBAC)
- Multi-factor authentication (MFA) support
- Intrusion detection system (IDS)
- Security policy enforcement
- Audit logging and compliance tracking
- Rate limiting and brute-force protection
- Security event monitoring

### System Requirements

- **OS:** Windows Server 2016 or later / Windows 7 SP1 or later
- **.NET Core:** 3.1 or .NET 6.0+
- **RAM:** Minimum 1 GB, Recommended 2+ GB
- **Disk:** 156 MB installation + logs
- **Dependencies:** Windows Security essentials

### Dependencies

| Dependency | Type | Required? | Can Work Without? |
|-----------|------|-----------|------------------|
| .NET Core 3.1 or .NET 6 | Framework | Yes | No |
| Windows Event Log | System | Yes | No |
| SQL Server Express (optional) | Database | No | Yes - Uses embedded SQLite |

### Size & Installation Time

- **Download Size:** 94 MB
- **Installed Size:** 156 MB
- **Installation Time:** 3-5 minutes
- **Uninstall Time:** 1-2 minutes

### Installation Procedure

```powershell
# Basic installation
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# With SQL Server backend
.\install.ps1 -UseDatabase -DatabaseType "SqlServer" `
    -ConnectionString "Server=localhost;Database=HeliosSecurity"

# With MFA enabled
.\install.ps1 -EnableMFA -MFAProvider "Azure"

# Silent installation
.\install.ps1 -Silent
```

### Configuration

**Config File:** `C:\Program Files\HELIOS\security-engine\config.json`

```json
{
  "authentication": {
    "sessionTimeout": 3600,
    "enableMFA": false,
    "mfaProvider": null,
    "passwordPolicy": {
      "minLength": 12,
      "requireNumbers": true,
      "requireSpecialChars": true,
      "expiryDays": 90
    }
  },
  "authorization": {
    "enableRBAC": true,
    "defaultRole": "User"
  },
  "ids": {
    "enabled": true,
    "sensitivity": "medium",
    "alertThreshold": 5
  },
  "audit": {
    "enabled": true,
    "logPath": "C:\\Program Files\\HELIOS\\security-engine\\logs",
    "retentionDays": 365
  }
}
```

### Usage Examples

#### Create User Account

```powershell
$security = New-Object HeliosPlatform.SecurityEngine.SecurityManager
$security.CreateUser("john.doe", "john@company.com", "Role:Admin")
```

#### Authenticate User

```powershell
$authenticated = $security.AuthenticateUser("john.doe", "password123")
if ($authenticated.Success) {
    Write-Host "Login successful. Session: $($authenticated.SessionToken)"
} else {
    Write-Host "Login failed: $($authenticated.ErrorMessage)"
}
```

#### Check Permissions

```powershell
$hasPermission = $security.HasPermission($sessionToken, "Deploy.Application")
```

### File Locations

```
C:\Program Files\HELIOS\security-engine\
├── bin\
│   ├── security.exe
│   ├── security.dll
│   └── plugins\
├── config.json
├── policies\
│   ├── default-policies.json
│   └── custom-policies.json
├── logs\
│   ├── security.log
│   └── audit.log
└── database\
    └── security.db
```

### Troubleshooting

- **User lockout:** Check audit logs for failed attempts
- **Authorization denied:** Verify user roles and permissions
- **Performance issues:** Monitor IDS rules, reduce sensitivity if needed

### Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\uninstall.ps1

# Preserve user accounts and audit logs
.\uninstall.ps1 -PreserveData
```

---

## Performance AI

**Phase:** 2  
**Type:** AI-Powered Performance Optimization  
**Independent Use:** ⚠️ **PARTIAL** (Needs security-engine)  
**Version:** 0.8.1  
**Status:** Beta

### What It Does

Machine learning-based performance optimization. Learns system behavior, predicts bottlenecks, and provides automatic tuning recommendations. Continuously adapts to workload patterns.

### Key Features

- Real-time workload analysis
- Predictive performance modeling
- Automatic parameter tuning
- Anomaly detection
- Performance bottleneck identification
- Resource allocation optimization
- Historical trend analysis

### System Requirements

- **OS:** Windows Server 2019 or later / Windows 10 or later
- **.NET Framework:** 4.8+ or .NET 6.0+
- **RAM:** Minimum 4 GB, Recommended 8+ GB
- **Disk:** 412 MB installation + 50+ MB for ML models
- **CPU:** Multi-core recommended

### Dependencies

| Dependency | Type | Required? | Why? |
|-----------|------|-----------|------|
| security-engine | Component | **YES** | For access control and audit logging |
| .NET Framework 4.8+ | Framework | Yes | Runtime |
| TensorFlow (bundled) | ML Framework | Yes | Model inference |

### Size & Installation Time

- **Download Size:** 267 MB
- **Installed Size:** 412 MB
- **Installation Time:** 8-12 minutes (includes ML model download)
- **Uninstall Time:** 2 minutes

### Installation Procedure

```powershell
# Requires security-engine first
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# Then install performance-ai
cd ..\performance-ai
.\install.ps1

# With learning mode (trains on current workload)
.\install.ps1 -LearningMode -LearningDurationHours 24

# With aggressive tuning (risky, not recommended for production initially)
.\install.ps1 -AggressiveTuning -WarningLevel high
```

### Configuration

**Config File:** `C:\Program Files\HELIOS\performance-ai\config.json`

```json
{
  "learningPhase": {
    "enabled": true,
    "durationHours": 72,
    "collectInterval": 60
  },
  "optimization": {
    "level": "balanced",
    "autoTuning": true,
    "maxChangePercent": 20,
    "backupBeforeTuning": true
  },
  "models": {
    "cpuOptimization": true,
    "memoryOptimization": true,
    "diskOptimization": true,
    "networkOptimization": true
  },
  "alerts": {
    "anomalyDetection": true,
    "anomalySensitivity": 0.8
  }
}
```

### Usage

#### Get Performance Recommendations

```powershell
$perf = New-Object HeliosPlatform.PerformanceAI.PerformanceOptimizer
$recommendations = $perf.GetOptimizationRecommendations()

foreach ($rec in $recommendations) {
    Write-Host "Priority: $($rec.Priority)"
    Write-Host "Recommendation: $($rec.Description)"
    Write-Host "Expected Improvement: $($rec.ExpectedImprovementPercent)%"
}
```

#### Apply Recommended Optimization

```powershell
$result = $perf.ApplyOptimization($recommendations[0].Id)
if ($result.Success) {
    Write-Host "Applied optimization. New performance score: $($result.NewScore)"
}
```

### File Locations

```
C:\Program Files\HELIOS\performance-ai\
├── bin\
│   ├── optimizer.exe
│   ├── optimizer.dll
│   └── models\
├── config.json
├── ml-models\
│   ├── cpu-optimizer.model
│   ├── memory-optimizer.model
│   ├── disk-optimizer.model
│   └── network-optimizer.model
├── logs\
│   └── optimization.log
└── data\
    └── training-data.db
```

### Troubleshooting

- **Models not loading:** Check `$HELIOS\logs\performance-ai.log`
- **Optimization too aggressive:** Reduce `maxChangePercent` in config
- **Learning phase stuck:** Set `learningPhase.enabled` to false and restart

### Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\performance-ai
.\uninstall.ps1
```

---

## Analytics Core

**Phase:** 1  
**Type:** Data Analysis & Reporting  
**Independent Use:** ✅ **YES** (Fully Standalone)  
**Version:** 1.0.3  
**Status:** Stable

### What It Does

Comprehensive data collection, analysis, and reporting. Works with any data source - system metrics, application logs, custom data. Generates reports and dashboards.

### Key Features

- Real-time data collection
- SQL query builder
- Custom report generation
- Data visualization
- Export to Excel/PDF/CSV
- Scheduled reports
- Data aggregation and transformation

### System Requirements

- **OS:** Windows Server 2016 or later / Windows 8.1 or later
- **.NET Framework:** 4.6.1 or later
- **RAM:** Minimum 2 GB, Recommended 4+ GB
- **Disk:** 178 MB installation + data
- **Database:** SQL Server Express (free)

### Dependencies

| Dependency | Type | Required? | Can Work Without? |
|-----------|------|-----------|------------------|
| SQL Server Express | Database | No | Yes - Uses embedded DB |
| .NET Framework 4.6.1+ | Framework | Yes | No |

### Size & Installation Time

- **Download Size:** 134 MB
- **Installed Size:** 178 MB
- **Installation Time:** 4-6 minutes
- **Uninstall Time:** 1 minute

### Installation Procedure

```powershell
cd C:\Users\ADMIN\helios-platform\components\analytics-core
.\install.ps1

# Or with SQL Server
.\install.ps1 -DatabaseType "SqlServer" `
    -ConnectionString "Server=localhost\SQLEXPRESS;Database=HeliosAnalytics"
```

### File Locations

```
C:\Program Files\HELIOS\analytics-core\
├── bin\
├── config.json
├── data\
├── logs\
└── templates\
```

---

## Cloud Bridge

**Phase:** 3  
**Type:** Cloud Integration  
**Independent Use:** ⚠️ **PARTIAL** (Needs security-engine, vault-dynamics)  
**Version:** 0.5.0  
**Status:** Alpha

### What It Does

Integrates HELIOS with cloud platforms (Azure, AWS, GCP). Enables hybrid and cloud-native deployments with seamless data synchronization.

### Key Features

- Multi-cloud support (Azure, AWS, GCP)
- Automatic data synchronization
- Hybrid deployment support
- Cloud backup and disaster recovery
- Identity federation

### System Requirements

- **OS:** Windows Server 2019 or later / Windows 10 or later
- **RAM:** Minimum 2 GB, Recommended 4+ GB
- **Internet:** Required
- **.NET:** .NET 6.0+

### Dependencies

| Dependency | Type | Required? |
|-----------|------|-----------|
| security-engine | Component | **YES** |
| vault-dynamics | Component | **YES** |

### Size & Installation Time

- **Download Size:** 178 MB
- **Installed Size:** 267 MB
- **Installation Time:** 6-8 minutes
- **Uninstall Time:** 2 minutes

### Installation Procedure

```powershell
# Must install dependencies first
.\components\security-engine\install.ps1
.\components\vault-dynamics\install.ps1

# Then install cloud-bridge
.\components\cloud-bridge\install.ps1 -CloudProvider "Azure" `
    -SubscriptionId "your-subscription-id"
```

---

## Summary Table

| Component | Phase | Standalone | Dependencies | Size | Install Time |
|-----------|-------|-----------|--------------|------|--------------|
| **ai-dashboard** | 3 | ✅ Yes | .NET 4.8 | 245 MB | 5-10 min |
| **vault-dynamics** | 1 | ✅ Yes | .NET 4.6.1 | 89 MB | 2-3 min |
| **security-engine** | 0 | ✅ Yes | .NET Core 3.1 | 156 MB | 3-5 min |
| **performance-ai** | 2 | ⚠️ Partial | security-engine | 412 MB | 8-12 min |
| **analytics-core** | 1 | ✅ Yes | SQL Express | 178 MB | 4-6 min |
| **cloud-bridge** | 3 | ⚠️ Partial | security-engine, vault | 267 MB | 6-8 min |

---

**For dependency details, see: COMPONENT_DEPENDENCIES.md**  
**For compatibility info, see: COMPONENT_COMPATIBILITY_MATRIX.md**
