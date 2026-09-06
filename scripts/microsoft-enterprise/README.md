# Microsoft Enterprise Integration Suite for HELIOS Platform

Production-ready Microsoft enterprise integration with comprehensive Azure, Microsoft 365, and enterprise cloud management capabilities.

## Directory Structure

```
microsoft-enterprise/
├── azure/
│   ├── azure-auth.ps1                 (400+ lines - Azure authentication)
│   ├── resource-manager.ps1           (400+ lines - Resource management)
│   ├── vm-orchestrator.ps1            (430+ lines - VM provisioning)
│   ├── network-setup.ps1              (430+ lines - VNet/NSG config)
│   ├── storage-management.ps1         (360+ lines - Storage services)
│   ├── backup-recovery.ps1            (340+ lines - Backup/DR)
│   └── cost-analyzer.ps1              (300+ lines - Cost analysis)
├── entra/
│   ├── entra-sync.ps1                 (240+ lines - Directory sync)
│   ├── user-management.ps1            (270+ lines - User management)
│   ├── group-management.ps1           (260+ lines - Group management)
│   ├── rbac-setup.ps1                 (230+ lines - RBAC setup)
│   ├── conditional-access.ps1         (180+ lines - CA policies)
│   └── mfa-enforcement.ps1            (190+ lines - MFA setup)
├── m365/
│   ├── teams-provisioning.ps1         (280+ lines - Teams management)
│   ├── sharepoint-setup.ps1           (100+ lines - SharePoint config)
│   ├── exchange-config.ps1            (140+ lines - Exchange setup)
│   ├── onedrive-sync.ps1              (90+ lines - OneDrive management)
│   ├── license-management.ps1         (90+ lines - License allocation)
│   └── compliance-setup.ps1           (90+ lines - Compliance policies)
├── copilot/
│   ├── copilot-integration.ps1        (90+ lines - Copilot API)
│   ├── prompt-templates.ps1           (Stub)
│   ├── usage-analytics.ps1            (Stub)
│   └── custom-copilots.ps1            (Stub)
├── purview/
│   ├── data-governance.ps1            (90+ lines - Data classification)
│   ├── compliance-dashboard.ps1       (Stub)
│   ├── risk-management.ps1            (Stub)
│   └── audit-logs.ps1                 (Stub)
├── fabric/
│   ├── workspace-management.ps1       (90+ lines - Workspace setup)
│   ├── lakehouse-setup.ps1            (Stub)
│   ├── data-pipelines.ps1             (Stub)
│   └── reporting.ps1                  (Stub)
├── power/
│   ├── power-apps.ps1                 (90+ lines - Power Apps)
│   ├── power-bi.ps1                   (Stub)
│   ├── power-automate.ps1             (Stub)
│   └── connector-setup.ps1            (Stub)
├── azure-config.json                  (Configuration)
├── entra-config.json                  (Configuration)
├── m365-config.json                   (Configuration)
├── fabric-config.json                 (Configuration)
├── power-config.json                  (Configuration)
└── README.md                          (This file)
```

## Features

### Azure Integration (7 scripts)

- **azure-auth.ps1**: Multi-method authentication (Service Principal, Interactive, Managed Identity, Certificate)
- **resource-manager.ps1**: Resource group management, ARM template deployment, tagging, locks
- **vm-orchestrator.ps1**: VM provisioning, lifecycle management, snapshots, extensions
- **network-setup.ps1**: VNet, subnet, NSG, public IP, load balancer setup
- **storage-management.ps1**: Storage accounts, blobs, file shares, SAS tokens, encryption
- **backup-recovery.ps1**: Recovery vaults, backup policies, disaster recovery, restore operations
- **cost-analyzer.ps1**: Cost analysis, budget management, optimization recommendations

### Azure Entra Integration (6 scripts)

- **entra-sync.ps1**: Directory synchronization, conflict resolution, health monitoring
- **user-management.ps1**: User provisioning, lifecycle, bulk operations, profiles
- **group-management.ps1**: Group creation, dynamic groups, membership management
- **rbac-setup.ps1**: Role assignments, permission management, access control
- **conditional-access.ps1**: CA policies, risk-based conditions, grant controls
- **mfa-enforcement.ps1**: MFA setup, device registration, compliance reporting

### Microsoft 365 Integration (6 scripts)

- **teams-provisioning.ps1**: Team creation, channels, membership, governance
- **sharepoint-setup.ps1**: Site creation, lists, permissions, sharing policies
- **exchange-config.ps1**: Distribution groups, mailbox audit, forwarding rules
- **onedrive-sync.ps1**: Quota management, sync status, security policies
- **license-management.ps1**: License allocation, utilization tracking, SKU management
- **compliance-setup.ps1**: DLP policies, audit logging, retention policies

### Copilot Integration (4 stub scripts)

- **copilot-integration.ps1**: Copilot API management and instance creation
- **prompt-templates.ps1**: Prompt template management and versioning
- **usage-analytics.ps1**: Usage tracking and analytics reporting
- **custom-copilots.ps1**: Custom Copilot creation and configuration

### Purview Integration (4 stub scripts)

- **data-governance.ps1**: Data classification and governance policies
- **compliance-dashboard.ps1**: Compliance monitoring and reporting
- **risk-management.ps1**: Risk assessment and mitigation
- **audit-logs.ps1**: Audit logging and compliance auditing

### Fabric Integration (4 stub scripts)

- **workspace-management.ps1**: Workspace creation and management
- **lakehouse-setup.ps1**: Lakehouse provisioning and configuration
- **data-pipelines.ps1**: Data pipeline creation and orchestration
- **reporting.ps1**: Report generation and distribution

### Power Platform (4 stub scripts)

- **power-apps.ps1**: Power Apps management and creation
- **power-bi.ps1**: Power BI workspace and report management
- **power-automate.ps1**: Flow creation and management
- **connector-setup.ps1**: Custom connector configuration

## Prerequisites

### Required PowerShell Modules

```powershell
# Azure
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.Resources -Force
Install-Module -Name Az.Compute -Force
Install-Module -Name Az.Network -Force
Install-Module -Name Az.Storage -Force
Install-Module -Name Az.RecoveryServices -Force
Install-Module -Name Az.CostManagement -Force

# Azure Entra
Install-Module -Name AzureAD -Force

# Microsoft 365
Install-Module -Name MicrosoftTeams -Force
Install-Module -Name ExchangeOnlineManagement -Force
Install-Module -Name PnP.PowerShell -Force

# Fabric
Install-Module -Name MicrosoftFabric -Force  # When available
```

### Required Permissions

- Azure: Subscription Reader, Contributor roles
- Entra: Global Administrator or appropriate role
- Microsoft 365: Global Administrator or delegated role
- Fabric: Fabric Admin
- Power Platform: Power Platform Admin

## Configuration

### Environment Variables

Set these before running scripts:

```powershell
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"
$env:AZURE_TENANT_ID = "your-tenant-id"
$env:AZURE_CLIENT_ID = "your-client-id"
$env:AZURE_CLIENT_SECRET = "your-client-secret"
$env:ENTRA_TENANT_ID = "your-entra-tenant-id"
$env:M365_TENANT_ID = "your-m365-tenant-id"
$env:NOTIFICATION_EMAIL = "admin@helios.onmicrosoft.com"
```

### Configuration Files

- **azure-config.json**: Azure service configuration
- **entra-config.json**: Entra ID configuration
- **m365-config.json**: Microsoft 365 configuration
- **fabric-config.json**: Fabric configuration
- **power-config.json**: Power Platform configuration

## Usage Examples

### Azure Authentication

```powershell
# Service Principal
. .\azure\azure-auth.ps1 -AuthType ServicePrincipal -TenantId $tenantId -ClientId $clientId -ClientSecret $secret

# Interactive
. .\azure\azure-auth.ps1 -AuthType Interactive

# Managed Identity
. .\azure\azure-auth.ps1 -AuthType ManagedIdentity
```

### Resource Management

```powershell
. .\azure\resource-manager.ps1
$rg = New-ResourceGroup -ResourceGroupName "helios-rg" -Location "eastus"
$templates = Get-DeploymentHistory -ResourceGroupName "helios-rg"
```

### VM Orchestration

```powershell
. .\azure\vm-orchestrator.ps1
$vm = New-VirtualMachine -ResourceGroupName "helios-rg" -VMName "helios-vm01" `
    -ImageType WindowsServer2022 -VMSize Standard_D2s_v3 `
    -VNetName "helios-vnet" -SubnetName "default"
```

### Entra User Management

```powershell
. .\entra\user-management.ps1
$user = New-EntraUser -UserPrincipalName "john.doe@helios.onmicrosoft.com" `
    -DisplayName "John Doe" -FirstName "John" -LastName "Doe"
```

### Teams Provisioning

```powershell
. .\m365\teams-provisioning.ps1
$team = New-Team -TeamName "Engineering" -TeamDescription "Engineering Team" -Visibility Private
```

## Error Handling & Logging

All scripts include comprehensive:

- **Structured Logging**: Timestamped logs with severity levels
- **Error Handling**: Try-catch blocks with detailed error messages
- **Validation**: Input parameter validation
- **Retry Logic**: Automatic retry for transient failures

Logs are written to: `C:\Logs\HELIOS\{Component}\`

## Security Best Practices

1. **Credentials**: Use service principals or managed identities, never hardcode credentials
2. **Audit Logging**: Enable audit logging for all critical operations
3. **MFA**: Enforce MFA for all user accounts
4. **RBAC**: Follow principle of least privilege
5. **Secrets**: Use Azure Key Vault for storing secrets
6. **Compliance**: Regular compliance audits and reviews

## Troubleshooting

### Connection Issues

```powershell
# Test Azure connection
Test-AzureConnection

# Get current context
Get-AzureConnectionInfo

# Verify Entra connection
Get-AzureADCurrentSessionInfo
```

### Module Issues

```powershell
# Update modules
Update-Module -Name Az.Accounts -Force
Update-Module -Name AzureAD -Force

# Verify module versions
Get-Module -Name Az.* -ListAvailable
```

## Performance Optimization

- Use batch operations for bulk user/group management
- Implement parallel processing for large resource sets
- Cache frequently accessed data
- Use appropriate pagination for list operations
- Enable diagnostic logging for troubleshooting

## Maintenance

- Review and update configurations quarterly
- Monitor for deprecated APIs and cmdlets
- Test disaster recovery procedures monthly
- Update scripts when API versions change
- Rotate credentials regularly

## Support & Documentation

- Azure: https://learn.microsoft.com/azure/
- Entra: https://learn.microsoft.com/entra/
- Microsoft 365: https://learn.microsoft.com/microsoft-365/
- Fabric: https://learn.microsoft.com/fabric/
- Power Platform: https://learn.microsoft.com/power-platform/

## Version Information

- Platform Version: 1.0.0
- PowerShell Version: 7.0+
- .NET Framework: 4.7.2+
- Update Date: 2024

## License

Internal use only - HELIOS Platform

## Contributors

- HELIOS Platform Team
- Microsoft Enterprise Integration Team
