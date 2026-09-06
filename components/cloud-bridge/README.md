# Cloud Bridge Component

Cloud integration enabling hybrid and cloud-native deployments of HELIOS Platform.

---

## Overview

Cloud Bridge seamlessly integrates HELIOS with Azure, AWS, and GCP. Enables hybrid deployments, cloud backup, and disaster recovery.

**Key Facts:**

- **Phase:** 3
- **Standalone:** ⚠️ Partial (needs security-engine + vault-dynamics)
- **Requires:** security-engine, vault-dynamics, cloud SDKs (bundled)
- **Version:** 0.5.0
- **Status:** Alpha
- **Size:** 267 MB
- **Installation Time:** 6-8 minutes

---

## What It Does

### Core Features

1. **Multi-Cloud Support**
   - Azure integration
   - AWS integration
   - GCP integration
   - Hybrid deployments

2. **Data Synchronization**
   - Automatic cloud sync
   - Bidirectional replication
   - Conflict resolution
   - Data consistency

3. **Backup & Recovery**
   - Automated cloud backups
   - Disaster recovery
   - Point-in-time recovery
   - Cross-region failover

4. **Identity Federation**
   - Azure AD integration
   - AWS IAM integration
   - Single sign-on
   - Multi-tenant support

5. **Monitoring**
   - Cloud metrics
   - Hybrid visibility
   - Cloud-to-on-prem sync status

---

## System Requirements

### Minimum

- **Requires:** security-engine (Phase 0) + vault-dynamics (Phase 1)
- **OS:** Windows Server 2019+ or Windows 10+
- **.NET Core:** 3.1 or .NET Framework 4.8+
- **RAM:** 2 GB
- **Disk:** 300 MB available
- **Internet:** Required

### Recommended

- **OS:** Windows Server 2022+
- **RAM:** 4+ GB
- **Disk:** 1 GB available
- **Cloud Account:** Azure/AWS/GCP subscription

---

## Installation Procedure

### Important: Install Dependencies First

Cloud Bridge requires both security-engine AND vault-dynamics:

```powershell
# Step 1: Install security-engine (Phase 0)
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1

# Step 2: Install vault-dynamics (Phase 1)
cd ..\vault-dynamics
.\install.ps1

# Step 3: Install cloud-bridge (Phase 3)
cd ..\cloud-bridge
.\install.ps1
```

### Azure Integration

```powershell
.\install.ps1 -CloudProvider "Azure" `
    -SubscriptionId "your-subscription-id" `
    -TenantId "your-tenant-id" `
    -ClientId "your-client-id"
```

### AWS Integration

```powershell
.\install.ps1 -CloudProvider "AWS" `
    -AwsAccessKey "your-access-key" `
    -AwsSecretKey "your-secret-key" `
    -AwsRegion "us-east-1"
```

### GCP Integration

```powershell
.\install.ps1 -CloudProvider "GCP" `
    -ProjectId "your-project-id" `
    -ServiceAccountPath "C:\certs\service-account.json"
```

---

## Configuration

**Config File:** `C:\Program Files\HELIOS\cloud-bridge\config.json`

```json
{
  "cloud": {
    "provider": "Azure",
    "subscriptionId": "your-subscription-id",
    "region": "eastus",
    "environment": "production"
  },

  "synchronization": {
    "enabled": true,
    "bidirectional": true,
    "interval": 3600,
    "conflictResolution": "cloud-wins"
  },

  "backup": {
    "enabled": true,
    "scheduleDaily": "02:00",
    "retentionDays": 30,
    "encryption": true
  },

  "authentication": {
    "ssoEnabled": true,
    "mfaRequired": true
  }
}
```

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\cloud-bridge\

Application Files:
├── bin\
│   ├── cloud-bridge.exe
│   ├── cloud-bridge.dll
│   └── cloud-sdks\

Configuration:
├── config.json
├── cloud-credentials.encrypted

Logs:
├── logs\
│   ├── sync.log
│   └── errors.log
```

---

## Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\cloud-bridge

# Preserve configuration
.\uninstall.ps1 -PreserveConfig

# Remove everything
.\uninstall.ps1 -CompleteCleanup
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.5.0 | 2023-12-10 | Initial alpha release |

---

## Support

Cloud Bridge is currently in Alpha. For issues, see component logs.
