# HELIOS Microsoft Enterprise Integration - Deployment Guide

## Quick Start

### 1. Prerequisites Setup

```powershell
# Install required modules
$modules = @(
    'Az.Accounts',
    'Az.Resources', 
    'Az.Compute',
    'Az.Network',
    'Az.Storage',
    'Az.RecoveryServices',
    'Az.CostManagement',
    'AzureAD',
    'MicrosoftTeams',
    'ExchangeOnlineManagement',
    'PnP.PowerShell'
)

foreach ($module in $modules) {
    Install-Module -Name $module -Force -Scope CurrentUser -ErrorAction SilentlyContinue
    Write-Host "✓ Installed $module"
}
```

### 2. Environment Configuration

```powershell
# Set environment variables
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"
$env:AZURE_TENANT_ID = "your-tenant-id"
$env:ENTRA_TENANT_ID = "your-entra-tenant-id"
$env:NOTIFICATION_EMAIL = "admin@helios.onmicrosoft.com"

# Verify logs directory
New-Item -ItemType Directory -Path "C:\Logs\HELIOS\Azure" -Force | Out-Null
New-Item -ItemType Directory -Path "C:\Logs\HELIOS\Entra" -Force | Out-Null
New-Item -ItemType Directory -Path "C:\Logs\HELIOS\M365" -Force | Out-Null
```

### 3. Initialize Azure Connection

```powershell
# Import and authenticate
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\azure-auth.ps1"

# Test connection
if (Test-AzureConnection) {
    Write-Host "✓ Azure connection successful"
    Get-AzureConnectionInfo
}
```

## Module-by-Module Deployment

### Azure Infrastructure Setup

```powershell
# Load Azure modules
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\resource-manager.ps1"
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\network-setup.ps1"
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\storage-management.ps1"

# Create resource group
$rg = New-ResourceGroup -ResourceGroupName "helios-prod" -Location "eastus" `
    -Tags @{Environment="Production"; Owner="HELIOS"; CostCenter="IT"}

# Create virtual network
$vnet = New-VirtualNetwork -ResourceGroupName "helios-prod" -VNetName "helios-vnet" `
    -AddressSpace "10.0.0.0/16" -Location "eastus"

# Create subnet
New-Subnet -ResourceGroupName "helios-prod" -VNetName "helios-vnet" `
    -SubnetName "default" -AddressPrefix "10.0.1.0/24"

# Create NSG
$nsg = New-NetworkSecurityGroup -ResourceGroupName "helios-prod" `
    -NSGName "helios-nsg" -Location "eastus"

# Add NSG rules
Add-NSGRule -ResourceGroupName "helios-prod" -NSGName "helios-nsg" `
    -RuleName "AllowHTTPS" -Access Allow -Direction Inbound -Protocol TCP `
    -SourceAddressPrefix "*" -DestinationAddressPrefix "*" -DestinationPortRange 443

# Create storage account
$storage = New-StorageAccount -ResourceGroupName "helios-prod" `
    -StorageAccountName "heliosprod$(Get-Random)" -Location "eastus"

# Create container
New-StorageContainer -ResourceGroupName "helios-prod" `
    -StorageAccountName $storage.StorageAccountName -ContainerName "data"
```

### VM Provisioning

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\vm-orchestrator.ps1"

# Create Windows Server VM
$vm = New-VirtualMachine -ResourceGroupName "helios-prod" -VMName "helios-web01" `
    -ImageType WindowsServer2022 -VMSize Standard_D2s_v3 `
    -VNetName "helios-vnet" -SubnetName "default"

# Add data disk
Add-DataDisk -ResourceGroupName "helios-prod" -VMName "helios-web01" `
    -DiskName "helios-web01-data" -DiskSizeGB 256

# Start VM
Start-VirtualMachine -ResourceGroupName "helios-prod" -VMName "helios-web01"

# Verify status
$status = Get-VMStatus -ResourceGroupName "helios-prod" -VMName "helios-web01"
$status | Format-List
```

### Backup & Recovery Setup

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\backup-recovery.ps1"

# Create Recovery Services vault
$vault = New-RecoveryServicesVault -ResourceGroupName "helios-prod" `
    -VaultName "helios-backup" -Location "eastus"

# Create backup policy
$policy = Create-BackupPolicy -VaultName "helios-backup" `
    -ResourceGroupName "helios-prod" -PolicyName "DailyBackup" `
    -SchedulePolicy "Daily" -RetentionDays 30

# Enable VM backup
Enable-VMBackup -ResourceGroupName "helios-prod" -VMName "helios-web01" `
    -VaultName "helios-backup" -PolicyName "DailyBackup"

# Trigger initial backup
Trigger-VMBackup -ResourceGroupName "helios-prod" -VMName "helios-web01" `
    -VaultName "helios-backup"
```

### Entra ID Setup

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\entra\user-management.ps1"
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\entra\group-management.ps1"
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\entra\rbac-setup.ps1"

# Import CSV with user data
$users = Import-Csv "C:\Users\ADMIN\helios-platform\users.csv"
Bulk-ImportEntraUsers -CsvPath "C:\Users\ADMIN\helios-platform\users.csv"

# Create security groups
$engGroup = New-EntraGroup -DisplayName "Engineering" `
    -Description "Engineering team members"
$adminGroup = New-EntraGroup -DisplayName "Administrators" `
    -Description "System administrators"

# Create dynamic group for all users
$dynamicGroup = New-DynamicGroup -DisplayName "AllUsers" `
    -MembershipRule '(user.accountEnabled -eq true)'

# Assign roles
foreach ($user in $users) {
    $entraUser = Get-EntraUser -UserPrincipalName $user.UserPrincipalName
    if ($user.Role -eq "Admin") {
        Assign-EntraRoleToUser -UserObjectId $entraUser.ObjectId -RoleName "Global Administrator"
    }
}
```

### Microsoft 365 Setup

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\m365\teams-provisioning.ps1"
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\m365\license-management.ps1"

# Connect to Teams
Connect-MicrosoftTeams

# Create teams
$engTeam = New-Team -TeamName "Engineering" `
    -TeamDescription "Engineering and Development" -Visibility Private
$opsTeam = New-Team -TeamName "Operations" `
    -TeamDescription "Operations and Support" -Visibility Private

# Create channels
New-TeamChannel -GroupId $engTeam.GroupId -ChannelName "General"
New-TeamChannel -GroupId $engTeam.GroupId -ChannelName "Development" `
    -ChannelDescription "Development discussions"
New-TeamChannel -GroupId $engTeam.GroupId -ChannelName "Deployments" `
    -ChannelDescription "Deployment notifications and approvals"

# Add members
foreach ($user in $users) {
    if ($user.Department -eq "Engineering") {
        Add-TeamMember -GroupId $engTeam.GroupId -User $user.UserPrincipalName -Role Member
    }
}

# Assign licenses
$users | Where-Object Role -eq "Admin" | ForEach-Object {
    Assign-License -UserObjectId $_.ObjectId -SKU "M365E5"
}
```

### Cost Monitoring Setup

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\cost-analyzer.ps1"

# Get cost analysis
$costs = Get-ResourceCostAnalysis -TimeFrame MonthToDate

# Get top cost resources
$topResources = Get-TopCostResources -TopCount 10

# Create budget
New-CostBudget -BudgetName "Production" -Amount 10000 `
    -NotificationEmails @("admin@helios.onmicrosoft.com") -ThresholdPercent 80

# Generate report
Generate-CostOptimizationReport -OutputPath "C:\Reports\cost-analysis-$(Get-Date -Format 'yyyyMMdd').json"
```

## Validation Checklist

```powershell
# Create validation script
$validations = @(
    @{Name="Azure Connection"; Test={ Test-AzureConnection }},
    @{Name="Resource Group"; Test={ Get-AzResourceGroup -Name "helios-prod" -EA SilentlyContinue }},
    @{Name="VNet"; Test={ Get-AzVirtualNetwork -Name "helios-vnet" -EA SilentlyContinue }},
    @{Name="Storage"; Test={ Get-AzStorageAccount -Name "heliosprod*" -EA SilentlyContinue }},
    @{Name="VMs"; Test={ Get-AzVM -ResourceGroupName "helios-prod" -EA SilentlyContinue }},
    @{Name="Backup Vault"; Test={ Get-AzRecoveryServicesVault -Name "helios-backup" -EA SilentlyContinue }}
)

foreach ($validation in $validations) {
    $result = & $validation.Test
    $status = if ($result) { "✓ PASS" } else { "✗ FAIL" }
    Write-Host "$status - $($validation.Name)"
}
```

## Common Operations

### Adding a New User

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\entra\user-management.ps1"

$user = New-EntraUser -UserPrincipalName "jane.smith@helios.onmicrosoft.com" `
    -DisplayName "Jane Smith" -FirstName "Jane" -LastName "Smith" `
    -Department "Engineering" -JobTitle "Software Engineer"

# Assign license
Assign-License -UserObjectId $user.ObjectId -SKU "M365E3"

# Add to group
Add-EntraGroupMember -GroupObjectId $engGroup.ObjectId -UserObjectId $user.ObjectId

Write-Host "User created and configured: $($user.UserPrincipalName)"
```

### Provisioning New Team

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\m365\teams-provisioning.ps1"

$team = New-Team -TeamName "ProjectAlpha" `
    -TeamDescription "Project Alpha Team" -Visibility Private

New-TeamChannel -GroupId $team.GroupId -ChannelName "Planning"
New-TeamChannel -GroupId $team.GroupId -ChannelName "Development"
New-TeamChannel -GroupId $team.GroupId -ChannelName "Testing"

Write-Host "Team provisioned: $($team.DisplayName)"
```

### Emergency VM Snapshot

```powershell
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\vm-orchestrator.ps1"

$snapshot = Backup-VirtualMachine -ResourceGroupName "helios-prod" `
    -VMName "helios-web01" -SnapshotName "emergency-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-Host "Snapshot created: $($snapshot.Name)"
```

## Troubleshooting

### Check Logs

```powershell
# View recent Azure logs
Get-Content "C:\Logs\HELIOS\Azure\resource-mgmt-$(Get-Date -Format 'yyyyMMdd').log" -Tail 20

# View Entra logs
Get-Content "C:\Logs\HELIOS\Entra\user-mgmt-$(Get-Date -Format 'yyyyMMdd').log" -Tail 20
```

### Connection Issues

```powershell
# Clear cached credentials
Remove-Item -Path "$env:APPDATA\AzureDataStudio" -Recurse -Force -ErrorAction SilentlyContinue

# Reconnect
. "C:\Users\ADMIN\helios-platform\scripts\microsoft-enterprise\azure\azure-auth.ps1" -AuthType Interactive
```

## Support Resources

- Azure Documentation: https://learn.microsoft.com/en-us/azure/
- Entra Documentation: https://learn.microsoft.com/en-us/entra/
- Microsoft 365 Docs: https://learn.microsoft.com/en-us/microsoft-365/
- PowerShell Docs: https://learn.microsoft.com/en-us/powershell/

## Next Steps

1. ✓ Deploy Azure infrastructure
2. ✓ Configure Entra ID
3. ✓ Provision Microsoft 365 services
4. ✓ Set up Copilot integration
5. ✓ Configure Purview governance
6. ✓ Deploy Fabric workspaces
7. ✓ Set up Power Platform
8. ✓ Configure monitoring and alerting
9. ✓ Implement disaster recovery
10. ✓ Regular maintenance and optimization
