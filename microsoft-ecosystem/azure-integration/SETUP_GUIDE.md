# Azure Integration Setup Guide - HELIOS Platform

**Version:** 1.0.0 | **Estimated Setup Time**: 30-45 minutes

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Azure Account Setup](#step-1-azure-account-setup)
3. [Step 2: Service Principal Creation](#step-2-service-principal-creation)
4. [Step 3: IAM Roles and Permissions](#step-3-iam-roles-and-permissions)
5. [Step 4: Resource Group Organization](#step-4-resource-group-organization)
6. [Step 5: Virtual Network Configuration](#step-5-virtual-network-configuration)
7. [Step 6: Storage and Key Vault](#step-6-storage-and-key-vault)
8. [Step 7: Database Setup](#step-7-database-setup)
9. [Step 8: Backup Configuration](#step-8-backup-configuration)
10. [Step 9: Monitoring Setup](#step-9-monitoring-setup)
11. [Verification Checklist](#verification-checklist)

## Prerequisites

### Required Software

```powershell
# Check PowerShell version (must be 7.0+)
$PSVersionTable.PSVersion

# Install required modules
Install-Module -Name Az -Force -AllowClobber
Install-Module -Name Az.Accounts -Force -AllowClobber
Install-Module -Name Az.Compute -Force -AllowClobber
Install-Module -Name Az.Storage -Force -AllowClobber
Install-Module -Name Az.Sql -Force -AllowClobber
```

### Required Information (Gather Before Starting)

```
Subscription Information:
- Azure Subscription ID: __________________________
- Subscription Type: [ ] Pay-As-You-Go [ ] Enterprise Agreement
- Region: [ ] eastus2 [ ] westus2 [ ] other: ___________

Organizational Information:
- Company Name: __________________________
- Department: __________________________
- Cost Center: __________________________
- Environment: [ ] Development [ ] Staging [ ] Production

Contact Information:
- Azure Subscription Admin: __________________________
- Email: __________________________
- Phone: __________________________
```

## Step 1: Azure Account Setup

### 1.1 Sign Up for Azure

**Option A: New Account**

1. Visit https://azure.microsoft.com/en-us/free/
2. Click "Start Free"
3. Sign in with Microsoft account or create new one
4. Verify identity with credit card
5. Receive $200 free credits (valid 30 days)

**Option B: Enterprise Agreement**

1. Contact Microsoft Enterprise Sales
2. Set up agreement terms
3. Create accounts for team members

### 1.2 Verify Subscription

```powershell
# Connect to Azure
Connect-AzAccount

# List subscriptions
Get-AzSubscription | Format-Table Name, Id, State

# Set current subscription
$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
Set-AzContext -SubscriptionId $subscriptionId

# Verify connection
Get-AzContext
```

### 1.3 Set Subscription Variables

```powershell
# Create script to set environment variables
$env:HELIOS_AZURE_SUBSCRIPTION_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$env:HELIOS_AZURE_TENANT_ID = (Get-AzContext).Tenant.Id
$env:HELIOS_ENVIRONMENT = "production"
$env:HELIOS_LOCATION = "eastus2"
$env:HELIOS_LOCATION_SECONDARY = "westus2"

# Save to profile for persistence
@"
`$env:HELIOS_AZURE_SUBSCRIPTION_ID = "$($env:HELIOS_AZURE_SUBSCRIPTION_ID)"
`$env:HELIOS_AZURE_TENANT_ID = "$($env:HELIOS_AZURE_TENANT_ID)"
`$env:HELIOS_ENVIRONMENT = "production"
`$env:HELIOS_LOCATION = "eastus2"
`$env:HELIOS_LOCATION_SECONDARY = "westus2"
"@ | Add-Content -Path $PROFILE
```

## Step 2: Service Principal Creation

Service principals enable HELIOS automation without user credentials.

### 2.1 Create Service Principal

```powershell
# Create service principal for HELIOS Platform
$spName = "HELIOS-Platform-Automation"
$sp = New-AzADServicePrincipal -DisplayName $spName `
  -Role "Contributor" `
  -Scope "/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)"

# Save credentials securely
$spId = $sp.AppId
$spSecret = $sp.PasswordCredentials.SecretText

Write-Host "Service Principal Created:"
Write-Host "  AppId: $spId"
Write-Host "  TenantId: $($env:HELIOS_AZURE_TENANT_ID)"
Write-Host ""
Write-Host "IMPORTANT: Save the secret securely. You cannot retrieve it again:"
Write-Host "  Secret: $spSecret"
```

### 2.2 Store Credentials Securely

```powershell
# Option 1: Store in Windows Credential Manager
$credential = New-Object System.Management.Automation.PSCredential(
  $spId,
  (ConvertTo-SecureString $spSecret -AsPlainText -Force)
)
$credential | Export-Clixml -Path "$env:USERPROFILE\.helios\sp-credentials.xml"

# Option 2: Store in Azure Key Vault
$keyVaultName = "helios-vault-prod"
New-AzKeyVault -Name $keyVaultName `
  -ResourceGroupName "helios-platform-prod" `
  -Location $env:HELIOS_LOCATION

Set-AzKeyVaultSecret -VaultName $keyVaultName `
  -Name "sp-client-id" `
  -SecretValue (ConvertTo-SecureString $spId -AsPlainText -Force)

Set-AzKeyVaultSecret -VaultName $keyVaultName `
  -Name "sp-client-secret" `
  -SecretValue (ConvertTo-SecureString $spSecret -AsPlainText -Force)
```

### 2.3 Test Service Principal

```powershell
# Test authentication with service principal
$spCredential = New-Object System.Management.Automation.PSCredential(
  $spId,
  (ConvertTo-SecureString $spSecret -AsPlainText -Force)
)

Connect-AzAccount -ServicePrincipal `
  -Credential $spCredential `
  -Tenant $env:HELIOS_AZURE_TENANT_ID

# Verify access
Get-AzSubscription | Select-Object Id, Name, State
```

## Step 3: IAM Roles and Permissions

### 3.1 Understand Azure Roles

| Role | Permissions | Use Case |
|------|-----------|----------|
| **Owner** | Full access | Subscription owner only |
| **Contributor** | All actions except access | HELIOS automation |
| **Reader** | View-only access | Monitoring, audits |
| **Security Admin** | Security-specific permissions | Security team |
| **Cost Management Contributor** | Budget and cost management | Finance team |

### 3.2 Assign Custom Roles

```powershell
# Create custom role for HELIOS operators
$roleDefinition = @{
  Name = "HELIOS Platform Operator"
  IsCustom = $true
  Description = "Operators can manage HELIOS Platform infrastructure"
  Actions = @(
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/write",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/powerOff/action",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Sql/servers/databases/read",
    "Microsoft.Insights/metrics/read"
  )
  NotActions = @(
    "Microsoft.Authorization/*/Delete",
    "Microsoft.Authorization/*/write"
  )
  AssignableScopes = @("/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)")
}

# Create the role
New-AzRoleDefinition -InputObject $roleDefinition

# Assign role to user/group
New-AzRoleAssignment `
  -ObjectId "<user-or-group-id>" `
  -RoleDefinitionName "HELIOS Platform Operator" `
  -Scope "/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)"
```

### 3.3 Recommended Role Assignments

```
HELIOS Platform Owner:
  - Owner (on subscription)
  - Global Administrator (in Entra ID)

HELIOS Platform Admins:
  - Contributor (on subscription)
  - Application Administrator (in Entra ID)
  - Security Administrator
  - Backup Operator

HELIOS Platform Operators:
  - HELIOS Platform Operator (custom role)
  - Reader (on resource groups)
  - Virtual Machine User Login

HELIOS Platform Developers:
  - Contributor (on dev resource group)
  - Application Developer
  - Storage Account Contributor

HELIOS Platform Auditors:
  - Reader (on subscription)
  - Security Reader
  - Compliance Reader
```

### 3.4 View Current Assignments

```powershell
# List role assignments for subscription
Get-AzRoleAssignment -Scope "/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)" | 
  Select-Object DisplayName, RoleDefinitionName, Scope | Format-Table -AutoSize

# List role assignments for resource group
Get-AzRoleAssignment -ResourceGroupName "helios-platform-prod" | 
  Select-Object DisplayName, RoleDefinitionName | Format-Table -AutoSize
```

## Step 4: Resource Group Organization

### 4.1 Create Resource Groups

```powershell
# Production resource group
New-AzResourceGroup `
  -Name "helios-platform-prod" `
  -Location $env:HELIOS_LOCATION `
  -Tag @{
    Environment = "Production"
    CostCenter = "IT-001"
    ManagedBy = "HELIOS-Automation"
  }

# Staging resource group
New-AzResourceGroup `
  -Name "helios-platform-staging" `
  -Location $env:HELIOS_LOCATION `
  -Tag @{
    Environment = "Staging"
    CostCenter = "IT-001"
    ManagedBy = "HELIOS-Automation"
  }

# Development resource group
New-AzResourceGroup `
  -Name "helios-platform-dev" `
  -Location $env:HELIOS_LOCATION `
  -Tag @{
    Environment = "Development"
    CostCenter = "IT-001"
    ManagedBy = "HELIOS-Automation"
  }

# Shared services resource group
New-AzResourceGroup `
  -Name "helios-platform-shared" `
  -Location $env:HELIOS_LOCATION `
  -Tag @{
    Environment = "Shared"
    CostCenter = "IT-001"
    ManagedBy = "HELIOS-Automation"
  }
```

### 4.2 Resource Naming Convention

```
Pattern: [service]-[component]-[environment]-[instance]

Examples:
- helios-vm-prod-01          (Virtual Machine)
- helios-sqldb-prod          (SQL Database)
- helios-storage-prod        (Storage Account)
- helios-vault-prod          (Key Vault)
- helios-appinsights-prod    (Application Insights)
- helios-vnet-prod           (Virtual Network)
- helios-nsg-prod-web        (Network Security Group)
```

### 4.3 Apply Tags for Organization

```powershell
# Create standardized tags
$commonTags = @{
  Project = "HELIOS"
  Environment = "Production"
  CostCenter = "IT-001"
  Owner = "helios-admins@company.com"
  ManagedBy = "HELIOS-Automation"
  CreatedDate = (Get-Date -Format "yyyy-MM-dd")
  Compliance = "SOC2"
}

# Apply tags to resource group
Update-AzTag -ResourceId "/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)/resourceGroups/helios-platform-prod" `
  -Tag $commonTags `
  -Operation Merge
```

## Step 5: Virtual Network Configuration

### 5.1 Create Virtual Network

```powershell
# Create VNet
$vnet = New-AzVirtualNetwork `
  -ResourceGroupName "helios-platform-prod" `
  -Name "helios-vnet-prod" `
  -AddressPrefix "10.0.0.0/16" `
  -Location $env:HELIOS_LOCATION

# Create subnets
$subnet1 = Add-AzVirtualNetworkSubnetConfig `
  -Name "frontend-subnet" `
  -AddressPrefix "10.0.1.0/24" `
  -VirtualNetwork $vnet

$subnet2 = Add-AzVirtualNetworkSubnetConfig `
  -Name "backend-subnet" `
  -AddressPrefix "10.0.2.0/24" `
  -VirtualNetwork $vnet

$subnet3 = Add-AzVirtualNetworkSubnetConfig `
  -Name "database-subnet" `
  -AddressPrefix "10.0.3.0/24" `
  -VirtualNetwork $vnet

# Save VNet
$vnet | Set-AzVirtualNetwork
```

### 5.2 Create Network Security Groups

```powershell
# Frontend NSG
$fwdNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName "helios-platform-prod" `
  -Name "helios-nsg-prod-frontend" `
  -Location $env:HELIOS_LOCATION

# Add rules: Allow HTTPS, SSH from admin IPs
$fwdNsg | Add-AzNetworkSecurityRuleConfig `
  -Name "AllowHTTPS" `
  -Priority 100 `
  -Direction Inbound `
  -SourceAddressPrefix "*" `
  -SourcePortRange "*" `
  -DestinationAddressPrefix "*" `
  -DestinationPortRange "443" `
  -Access Allow `
  -Protocol Tcp | Set-AzNetworkSecurityGroup

# Backend NSG
$backendNsg = New-AzNetworkSecurityGroup `
  -ResourceGroupName "helios-platform-prod" `
  -Name "helios-nsg-prod-backend" `
  -Location $env:HELIOS_LOCATION

# Add rules: Only from frontend subnet
$backendNsg | Add-AzNetworkSecurityRuleConfig `
  -Name "AllowFromFrontend" `
  -Priority 100 `
  -Direction Inbound `
  -SourceAddressPrefix "10.0.1.0/24" `
  -SourcePortRange "*" `
  -DestinationAddressPrefix "10.0.2.0/24" `
  -DestinationPortRange "22,443,3306" `
  -Access Allow `
  -Protocol Tcp | Set-AzNetworkSecurityGroup
```

### 5.3 Associate NSGs with Subnets

```powershell
$vnet = Get-AzVirtualNetwork -ResourceGroupName "helios-platform-prod" -Name "helios-vnet-prod"
$subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "frontend-subnet"

$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName "helios-platform-prod" -Name "helios-nsg-prod-frontend"
Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name "frontend-subnet" -AddressPrefix "10.0.1.0/24" -NetworkSecurityGroup $nsg
$vnet | Set-AzVirtualNetwork
```

## Step 6: Storage and Key Vault

### 6.1 Create Storage Account

```powershell
# Create storage account for HELIOS data and backups
$storageAccount = New-AzStorageAccount `
  -ResourceGroupName "helios-platform-prod" `
  -Name "heliosplatformstorage" `
  -SkuName "Standard_GRS" `
  -Location $env:HELIOS_LOCATION `
  -Kind "StorageV2" `
  -AccessTier "Hot"

# Create containers
New-AzStorageContainer -Name "backups" -Context $storageAccount.Context
New-AzStorageContainer -Name "logs" -Context $storageAccount.Context
New-AzStorageContainer -Name "data" -Context $storageAccount.Context
```

### 6.2 Create Key Vault

```powershell
# Create Key Vault
$vault = New-AzKeyVault `
  -VaultName "helios-vault-prod" `
  -ResourceGroupName "helios-platform-prod" `
  -Location $env:HELIOS_LOCATION `
  -EnabledForDeployment `
  -EnabledForDiskEncryption `
  -EnabledForTemplateDeployment

# Store secrets
Set-AzKeyVaultSecret -VaultName "helios-vault-prod" `
  -Name "db-password" `
  -SecretValue (ConvertTo-SecureString "ComplexPassword123!@#" -AsPlainText -Force)

Set-AzKeyVaultSecret -VaultName "helios-vault-prod" `
  -Name "storage-connection-string" `
  -SecretValue (ConvertTo-SecureString $storageAccount.Context.ConnectionString -AsPlainText -Force)

Set-AzKeyVaultSecret -VaultName "helios-vault-prod" `
  -Name "api-key" `
  -SecretValue (ConvertTo-SecureString "$(New-Guid)" -AsPlainText -Force)
```

### 6.3 Configure Access Policies

```powershell
# Grant service principal access to Key Vault
Set-AzKeyVaultAccessPolicy `
  -VaultName "helios-vault-prod" `
  -ObjectId $sp.ObjectId `
  -PermissionsToSecrets Get, List `
  -PermissionsToKeys Get, List, Unwrap, Wrap, Decrypt, Encrypt

# Grant current user access
Set-AzKeyVaultAccessPolicy `
  -VaultName "helios-vault-prod" `
  -UserPrincipalName (Get-AzContext).Account `
  -PermissionsToSecrets Get, List, Set, Delete `
  -PermissionsToKeys Get, List, Create, Delete
```

## Step 7: Database Setup

### 7.1 Create SQL Server

```powershell
# Create SQL Server
$sqlServer = New-AzSqlServer `
  -ResourceGroupName "helios-platform-prod" `
  -ServerName "helios-sqlserver-prod" `
  -Location $env:HELIOS_LOCATION `
  -SqlAdministratorCredentials (Get-Credential -Message "SQL Admin Credentials") `
  -AssignIdentity

# Add firewall rule for Azure services
New-AzSqlServerFirewallRule `
  -ResourceGroupName "helios-platform-prod" `
  -ServerName "helios-sqlserver-prod" `
  -FirewallRuleName "AllowAzureServices" `
  -StartIpAddress "0.0.0.0" `
  -EndIpAddress "0.0.0.0"

# Add firewall rule for admin IP
New-AzSqlServerFirewallRule `
  -ResourceGroupName "helios-platform-prod" `
  -ServerName "helios-sqlserver-prod" `
  -FirewallRuleName "AdminIP" `
  -StartIpAddress "203.0.113.0" `
  -EndIpAddress "203.0.113.255"
```

### 7.2 Create SQL Database

```powershell
# Create SQL Database
$database = New-AzSqlDatabase `
  -ResourceGroupName "helios-platform-prod" `
  -ServerName "helios-sqlserver-prod" `
  -DatabaseName "helios-db-prod" `
  -Edition "Standard" `
  -Collation "SQL_Latin1_General_CP1_CI_AS" `
  -MaxSizeBytes 268435456000

# Configure backup retention
Set-AzSqlDatabase `
  -ResourceGroupName "helios-platform-prod" `
  -ServerName "helios-sqlserver-prod" `
  -DatabaseName "helios-db-prod" `
  -BackupStorageRedundancy "Geo"
```

### 7.3 Create Database User

```powershell
# Connect to database and create user
$query = @"
CREATE USER [helios-app-user] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [helios-app-user];
ALTER ROLE db_datawriter ADD MEMBER [helios-app-user];
"@

# Execute using Azure Data Studio or SQL Server Management Studio
# Or use Invoke-SqlCmd if SQLPS module is available
```

## Step 8: Backup Configuration

### 8.1 Create Recovery Services Vault

```powershell
# Create vault
$vault = New-AzRecoveryServicesVault `
  -Name "helios-recovery-vault-prod" `
  -ResourceGroupName "helios-platform-prod" `
  -Location $env:HELIOS_LOCATION

# Set vault context
Set-AzRecoveryServicesVaultContext -Vault $vault

# Set backup properties
$backupProperties = Get-AzRecoveryServicesBackupProperties -Vault $vault
$backupProperties.StorageModelType = "GeoRedundant"
$backupProperties | Set-AzRecoveryServicesBackupProperties
```

### 8.2 Configure VM Backup

```powershell
# Create backup policy
$schedulePolicy = Get-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType "AzureVM"
$schedulePolicy.ScheduleRunFrequency = "Daily"
$schedulePolicy.ScheduleRunTimes[0] = "2024-01-01T02:00:00Z"

$retentionPolicy = Get-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType "AzureVM"
$retentionPolicy.IsMonthlyBackupEnabled = $true
$retentionPolicy.IsDailyBackupEnabled = $true
$retentionPolicy.DailyRetentionDuration.Count = 7

# Create policy
$backupPolicy = New-AzRecoveryServicesBackupProtectionPolicy `
  -Name "HELIOS-VM-Backup-Policy" `
  -WorkloadType "AzureVM" `
  -BackupManagementType "AzureVM" `
  -SchedulePolicy $schedulePolicy `
  -RetentionPolicy $retentionPolicy

# Enable backup
$vm = Get-AzVM -ResourceGroupName "helios-platform-prod" -Name "helios-vm-01-prod"
Enable-AzRecoveryServicesBackupProtection `
  -ResourceGroupName "helios-platform-prod" `
  -Name "helios-vm-01-prod" `
  -Policy $backupPolicy
```

## Step 9: Monitoring Setup

### 9.1 Create Application Insights

```powershell
# Create Application Insights
$appInsights = New-AzApplicationInsights `
  -ResourceGroupName "helios-platform-prod" `
  -Name "helios-appinsights-prod" `
  -Location $env:HELIOS_LOCATION `
  -Kind "web" `
  -RetentionInDays 30

# Get instrumentation key
$instrumentationKey = $appInsights.InstrumentationKey
Write-Host "Instrumentation Key: $instrumentationKey"
```

### 9.2 Create Action Group

```powershell
# Create action group for alerts
$actionGroup = New-AzActionGroup `
  -Name "helios-alerts-prod" `
  -ResourceGroupName "helios-platform-prod" `
  -ShortName "HELIOS" `
  -Location "eastus2"

# Add email action
Add-AzActionGroupEmailReceiver `
  -ActionGroupId $actionGroup.Id `
  -Name "helios-admins" `
  -EmailAddress "helios-admins@company.com"

# Add webhook action for Teams/Slack
Add-AzActionGroupWebhookReceiver `
  -ActionGroupId $actionGroup.Id `
  -Name "teams-webhook" `
  -ServiceUri "https://outlook.webhook.office.com/webhookb2/xxxxx"
```

### 9.3 Create Alert Rules

```powershell
# Alert: High CPU utilization
$alertRule = New-AzMetricAlertRuleV2 `
  -Name "HELIOS-High-CPU-Alert" `
  -ResourceGroupName "helios-platform-prod" `
  -Scopes "/subscriptions/$($env:HELIOS_AZURE_SUBSCRIPTION_ID)/resourceGroups/helios-platform-prod" `
  -Condition $(
    New-AzMetricAlertRuleV2Criteria `
      -MetricName "Percentage CPU" `
      -MetricNamespace "Microsoft.Compute/virtualMachines" `
      -Operator "GreaterThan" `
      -Threshold 80 `
      -AggregationFunction "Average" `
      -TimeAggregation "Avg"
  ) `
  -WindowSize "00:05:00" `
  -Frequency "00:01:00" `
  -ActionGroupId $actionGroup.Id `
  -Severity 2
```

## Verification Checklist

Before completing setup, verify all components:

### Azure Subscription

- [ ] Subscription created and active
- [ ] Payment method verified
- [ ] Subscription ID saved: ___________________

### Service Principal

- [ ] Service principal created
- [ ] Credentials saved securely
- [ ] Tested successful authentication

### Resource Groups

- [ ] Production RG created: `helios-platform-prod`
- [ ] Staging RG created: `helios-platform-staging`
- [ ] Development RG created: `helios-platform-dev`
- [ ] Shared RG created: `helios-platform-shared`

### Networking

- [ ] VNet created: `helios-vnet-prod` (10.0.0.0/16)
- [ ] Frontend subnet created: 10.0.1.0/24
- [ ] Backend subnet created: 10.0.2.0/24
- [ ] Database subnet created: 10.0.3.0/24
- [ ] NSGs created and associated

### Storage & Secrets

- [ ] Storage account created
- [ ] Key Vault created
- [ ] Secrets stored in Key Vault
- [ ] Access policies configured

### Database

- [ ] SQL Server created
- [ ] SQL Database created
- [ ] Firewall rules configured
- [ ] Backup configured

### Monitoring

- [ ] Application Insights created
- [ ] Action group created
- [ ] Alert rules created
- [ ] Recovery Services Vault created

### IAM & Security

- [ ] Service principal assigned Contributor role
- [ ] Custom roles created
- [ ] Role assignments documented
- [ ] Key Vault access policies configured

## Next Steps

1. **Deploy VMs**: Use `../scripts/deploy-to-azure.ps1`
2. **Configure Monitoring**: Set up dashboards
3. **Test Connectivity**: Verify all services are accessible
4. **Document Configuration**: Record all resource names and IDs
5. **Setup Backup**: Configure backup policies
6. **Proceed to Entra ID Setup**: See `../entra-id/SETUP_GUIDE.md`

## Troubleshooting

### Issue: "Insufficient privileges to complete operation"

- Verify service principal has Contributor role
- Check role assignment: `Get-AzRoleAssignment -ObjectId $sp.ObjectId`

### Issue: "Firewall rule blocks database connection"

- Add your IP address to SQL Server firewall
- Or add specific VNet service endpoints

### Issue: "Key Vault access denied"

- Verify access policy is set: `Get-AzKeyVaultAccessPolicy -VaultName "helios-vault-prod"`
- Re-run: `Set-AzKeyVaultAccessPolicy` command

## Support

For issues, contact:

- **Azure Support**: https://azure.microsoft.com/support
- **HELIOS Platform Team**: See parent directory README

---

**Version 1.0.0** | **Last Updated**: 2024
