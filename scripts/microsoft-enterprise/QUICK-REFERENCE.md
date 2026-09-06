# HELIOS Microsoft Enterprise Integration - Quick Reference

## 📁 Directory Structure

```
microsoft-enterprise/
├── azure/                    (7 production scripts)
├── entra/                    (6 production scripts)
├── m365/                     (6 production scripts)
├── copilot/                  (1 production script)
├── purview/                  (1 production script)
├── fabric/                   (1 production script)
├── power/                    (1 production script)
├── [config files]            (5 JSON configuration files)
├── README.md                 (Full documentation)
└── DEPLOYMENT-GUIDE.md       (Step-by-step guide)
```

## 🚀 Quick Start

### 1. Install Dependencies

```powershell
$modules = 'Az.Accounts','Az.Resources','Az.Compute','Az.Network','AzureAD','MicrosoftTeams'
foreach ($m in $modules) { Install-Module $m -Force }
```

### 2. Authenticate

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\azure-auth.ps1"
```

### 3. Deploy Infrastructure

```powershell
# See DEPLOYMENT-GUIDE.md for full examples
```

## 🔐 Scripts by Purpose

### Authentication & Security

- `azure\azure-auth.ps1` - Azure authentication (ServicePrincipal, Interactive, ManagedIdentity, Certificate)
- `entra\mfa-enforcement.ps1` - MFA setup and enforcement
- `entra\conditional-access.ps1` - Conditional Access policies

### Infrastructure

- `azure\resource-manager.ps1` - Resource groups, ARM templates
- `azure\vm-orchestrator.ps1` - VMs, snapshots, extensions
- `azure\network-setup.ps1` - VNet, NSG, subnets, load balancers
- `azure\storage-management.ps1` - Storage accounts, blobs, file shares

### Data & Backup

- `azure\backup-recovery.ps1` - Recovery Services, backup policies
- `azure\cost-analyzer.ps1` - Cost analysis, budgets, optimization

### Identity Management

- `entra\entra-sync.ps1` - Directory synchronization
- `entra\user-management.ps1` - User provisioning and lifecycle
- `entra\group-management.ps1` - Groups and dynamic groups
- `entra\rbac-setup.ps1` - Role-based access control

### Collaboration

- `m365\teams-provisioning.ps1` - Teams, channels, members
- `m365\sharepoint-setup.ps1` - SharePoint sites and lists
- `m365\exchange-config.ps1` - Exchange, distribution groups
- `m365\onedrive-sync.ps1` - OneDrive quotas and sync

### Governance & Compliance

- `m365\license-management.ps1` - License allocation
- `m365\compliance-setup.ps1` - DLP, audit, retention
- `purview\data-governance.ps1` - Data classification
- `copilot\copilot-integration.ps1` - Copilot API

### Analytics & Reporting

- `fabric\workspace-management.ps1` - Fabric workspaces
- `power\power-apps.ps1` - Power Apps management

## ⚙️ Configuration

### Set Environment Variables

```powershell
$env:AZURE_SUBSCRIPTION_ID = "subscription-id"
$env:AZURE_TENANT_ID = "tenant-id"
$env:ENTRA_TENANT_ID = "entra-tenant-id"
$env:NOTIFICATION_EMAIL = "admin@company.com"
```

### Update Configuration Files

- `azure-config.json` - Azure settings (VM size, storage SKU, backup retention)
- `entra-config.json` - Entra settings (sync schedule, password policy)
- `m365-config.json` - Microsoft 365 settings (teams, licenses, policies)
- `fabric-config.json` - Fabric settings (capacity, workspaces)
- `power-config.json` - Power Platform settings (limits, connectors)

## 📊 Common Operations

### Create Resource Group

```powershell
. .\azure\resource-manager.ps1
New-ResourceGroup -ResourceGroupName "mygroup" -Location "eastus"
```

### Provision VM

```powershell
. .\azure\vm-orchestrator.ps1
New-VirtualMachine -ResourceGroupName "mygroup" -VMName "myvm" `
    -ImageType WindowsServer2022 -VMSize Standard_D2s_v3 `
    -VNetName "myvnet" -SubnetName "default"
```

### Create User

```powershell
. .\entra\user-management.ps1
New-EntraUser -UserPrincipalName "user@company.com" `
    -DisplayName "User Name" -FirstName "User" -LastName "Name"
```

### Create Team

```powershell
. .\m365\teams-provisioning.ps1
Connect-MicrosoftTeams
New-Team -TeamName "TeamName" -Visibility Private
```

### Enable Backup

```powershell
. .\azure\backup-recovery.ps1
Enable-VMBackup -ResourceGroupName "mygroup" -VMName "myvm" `
    -VaultName "myvault"
```

## 📋 Logging Locations

- Azure logs: `C:\Logs\HELIOS\Azure\`
- Entra logs: `C:\Logs\HELIOS\Entra\`
- M365 logs: `C:\Logs\HELIOS\M365\`
- Copilot logs: `C:\Logs\HELIOS\Copilot\`
- Purview logs: `C:\Logs\HELIOS\Purview\`
- Fabric logs: `C:\Logs\HELIOS\Fabric\`
- Power logs: `C:\Logs\HELIOS\Power\`

## ✅ Validation Commands

```powershell
# Test Azure connection
Test-AzureConnection

# Get Azure context
Get-AzureConnectionInfo

# List resources
Get-AzResource | Select Name, Type

# List VMs
Get-AzVM | Select Name, ResourceGroupName

# List resource groups
Get-AzResourceGroup | Select ResourceGroupName, Location
```

## 🔧 Troubleshooting

### Clear Cache

```powershell
Remove-Item -Path $env:APPDATA\AzureDataStudio -Recurse -Force
```

### Reconnect

```powershell
Disconnect-AzureAD -ErrorAction SilentlyContinue
Disconnect-AzAccount -ErrorAction SilentlyContinue
. .\azure\azure-auth.ps1 -AuthType Interactive
```

### Check Logs

```powershell
Get-Content "C:\Logs\HELIOS\Azure\*.log" -Tail 30
```

## 📚 Documentation

- **README.md** - Complete module documentation
- **DEPLOYMENT-GUIDE.md** - Step-by-step deployment instructions
- Azure Docs: https://learn.microsoft.com/azure/
- Entra Docs: https://learn.microsoft.com/entra/
- M365 Docs: https://learn.microsoft.com/microsoft-365/

## 🎯 Key Features

✓ Production-ready code with error handling
✓ Comprehensive logging and audit trails
✓ Modular design for easy integration
✓ Security best practices implemented
✓ Disaster recovery capabilities
✓ Cost optimization tools
✓ Automated provisioning
✓ Compliance and governance
✓ Multi-cloud support
✓ Scalable architecture

## 📞 Support Matrix

| Component | Module | Status | Purpose |
|-----------|--------|--------|---------|
| Azure Auth | azure | ✅ | Multi-method authentication |
| Resources | azure | ✅ | RG, ARM deployment, tagging |
| VMs | azure | ✅ | Provisioning, snapshots |
| Network | azure | ✅ | VNet, NSG, LB setup |
| Storage | azure | ✅ | Accounts, blobs, shares |
| Backup | azure | ✅ | Vaults, policies, recovery |
| Costs | azure | ✅ | Analysis, budgets, optimization |
| Sync | entra | ✅ | Directory synchronization |
| Users | entra | ✅ | Provisioning, lifecycle |
| Groups | entra | ✅ | Management, dynamic |
| RBAC | entra | ✅ | Role assignments |
| CA | entra | ✅ | Policies, conditions |
| MFA | entra | ✅ | Setup, enforcement |
| Teams | m365 | ✅ | Provisioning, management |
| SharePoint | m365 | ✅ | Site setup, lists |
| Exchange | m365 | ✅ | Groups, mailboxes |
| OneDrive | m365 | ✅ | Quotas, sync |
| Licenses | m365 | ✅ | Allocation, tracking |
| Compliance | m365 | ✅ | DLP, audit, retention |

---
**Version**: 1.0.0 | **Status**: Production Ready | **Last Updated**: 2024
