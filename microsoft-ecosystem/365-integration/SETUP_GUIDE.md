# Microsoft 365 Integration Setup Guide - HELIOS Platform

**Version:** 1.0.0 | **Estimated Setup Time**: 45-60 minutes

## Prerequisites

### Required Modules

```powershell
# Install Microsoft Graph module
Install-Module Microsoft.Graph -Force
Install-Module Microsoft.Graph.Teams -Force
Install-Module Microsoft.Graph.Groups -Force
Install-Module ExchangeOnlineManagement -Force

# Update modules
Update-Module Microsoft.Graph
Update-Module ExchangeOnlineManagement
```

### Required Permissions

- Global Administrator (for initial setup)
- Teams Administrator (for Teams configuration)
- Exchange Administrator (for email setup)
- SharePoint Administrator (for SharePoint configuration)

## Step 1: Connect to Microsoft 365

### 1.1 Authenticate

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Mail.Send"

# Verify connection
Get-MgContext
```

### 1.2 Connect to Exchange Online

```powershell
# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName "admin@company.onmicrosoft.com"

# Verify connection
Get-Mailbox | Select-Object DisplayName, UserPrincipalName | Head -5
```

## Step 2: Configure Teams

### 2.1 Create HELIOS Team

```powershell
# Create Teams team
$team = New-MgTeam `
  -DisplayName "HELIOS Platform" `
  -Description "HELIOS Platform deployment, operations, and coordination" `
  -Visibility "Private" `
  -MemberSettings @{
    AllowCreateUpdateChannels = $true
    AllowDeleteChannels = $false
    AllowAddRemoveApps = $false
    AllowCreateUpdateRemoveTabs = $true
    AllowCreateUpdateRemoveConnectors = $true
  } `
  -GuestSettings @{
    AllowCreateUpdateChannels = $false
    AllowDeleteChannels = $false
  }

# Get team ID
$teamId = $team.Id
Write-Host "Team Created: $teamId"
```

### 2.2 Create Channels

```powershell
# Function to create channel
function New-HeliosChannel {
    param(
        [string]$TeamId,
        [string]$DisplayName,
        [string]$Description
    )
    
    New-MgTeamChannel `
      -TeamId $teamId `
      -DisplayName $displayName `
      -Description $description
}

# Create channels
New-HeliosChannel -TeamId $teamId -DisplayName "announcements" -Description "System updates and notices"
New-HeliosChannel -TeamId $teamId -DisplayName "general" -Description "General discussion"
New-HeliosChannel -TeamId $teamId -DisplayName "deployment" -Description "Deployment status updates"
New-HeliosChannel -TeamId $teamId -DisplayName "incidents" -Description "Security incidents and alerts"
New-HeliosChannel -TeamId $teamId -DisplayName "monitoring" -Description "Performance metrics and monitoring"
New-HeliosChannel -TeamId $teamId -DisplayName "documentation" -Description "Knowledge base and documentation"
New-HeliosChannel -TeamId $teamId -DisplayName "automation-logs" -Description "Automation workflow logs"
New-HeliosChannel -TeamId $teamId -DisplayName "support" -Description "Support requests and issues"
```

### 2.3 Add Team Members

```powershell
# Add users to team
$users = @(
    "admin@company.com",
    "devops-lead@company.com",
    "security-admin@company.com"
)

foreach ($user in $users) {
    $userId = (Get-MgUser -Filter "mail eq '$user'").Id
    
    New-MgTeamMember `
      -TeamId $teamId `
      -DirectoryObjectId $userId `
      -Roles "owner"
}

# Add regular members
$members = @(
    "team-member1@company.com",
    "team-member2@company.com"
)

foreach ($member in $members) {
    $userId = (Get-MgUser -Filter "mail eq '$member'").Id
    
    New-MgTeamMember `
      -TeamId $teamId `
      -DirectoryObjectId $userId `
      -Roles "member"
}
```

### 2.4 Configure Team Settings

```powershell
# Update team settings
Update-MgTeam -TeamId $teamId `
  -MemberSettings @{
    AllowCreateUpdateChannels = $true
    AllowDeleteChannels = $false
    AllowAddRemoveApps = $false
    AllowCreateUpdateRemoveTabs = $true
    AllowCreateUpdateRemoveConnectors = $true
  } `
  -GuestSettings @{
    AllowCreateUpdateChannels = $false
    AllowDeleteChannels = $false
  }
```

## Step 3: Configure OneDrive

### 3.1 Create Folder Structure

```powershell
# Set up OneDrive folder structure for HELIOS
# This is typically done through the UI, but can be automated

# Create a script to sync OneDrive to local storage
$oneDrivePath = "$env:USERPROFILE\OneDrive - Company\HELIOS-Platform"

# Create folder structure
@(
    "$oneDrivePath\Configurations\Phase-Discovery",
    "$oneDrivePath\Configurations\Phase-Assessment",
    "$oneDrivePath\Configurations\Phase-Planning",
    "$oneDrivePath\Configurations\Phase-Execution",
    "$oneDrivePath\Configurations\Phase-Monitoring",
    "$oneDrivePath\Backups\Daily",
    "$oneDrivePath\Backups\Weekly",
    "$oneDrivePath\Backups\Monthly",
    "$oneDrivePath\Documentation",
    "$oneDrivePath\Reports",
    "$oneDrivePath\Templates"
) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Host "Created: $_"
    }
}
```

### 3.2 Configure OneDrive Sync

```powershell
# Create sync configuration
# Note: This typically requires user action in OneDrive client

# Enable Files On-Demand (if using Windows)
# Settings → Sync and backup → Files On-Demand
```

### 3.3 Set Sharing Policies

```powershell
# Allow sharing with external users (controlled)
Set-SPOSite -Identity "https://company-my.sharepoint.com/personal/admin_company_com" `
  -SharingCapability "ExternalUserAndGuestSharing"

# Require external sharing approval
Set-SPOSite -Identity "https://company-my.sharepoint.com/personal/admin_company_com" `
  -SharingCapability "Disabled" `
  # Then re-enable with restrictions
```

## Step 4: Configure SharePoint

### 4.1 Create Communication Site

```powershell
# Create SharePoint communication site
# Note: Requires SPO management shell

Install-Module Microsoft.Online.SharePoint.PowerShell -Force

# Connect to SharePoint
Connect-SPOService -Url "https://company-admin.sharepoint.com"

# Create site
New-SPOSite -Url "https://company.sharepoint.com/sites/helios-platform" `
  -Title "HELIOS Platform" `
  -Owner "admin@company.com" `
  -StorageQuota 1048576 `
  -Template "COMMUNICATIONSITE#0"
```

### 4.2 Create Site Structure

```powershell
# Create document libraries
# This is typically done through SharePoint UI

# Libraries to create:
# - Documentation
# - Compliance Reports
# - Deployment Logs
# - Configuration Templates
```

### 4.3 Configure Site Permissions

```powershell
# Get site
$site = Get-SPOSite -Identity "https://company.sharepoint.com/sites/helios-platform"

# Grant permissions
Grant-SPOSiteAccess -Site $site `
  -User "helios-admins@company.com" `
  -PermissionLevel "Full Control"

Grant-SPOSiteAccess -Site $site `
  -User "helios-team@company.com" `
  -PermissionLevel "Edit"

Grant-SPOSiteAccess -Site $site `
  -User "helios-viewers@company.com" `
  -PermissionLevel "Read"
```

## Step 5: Configure Exchange (Email)

### 5.1 Create Distribution Groups

```powershell
# Create distribution groups
New-DistributionGroup -Name "HELIOS Admins" `
  -DisplayName "HELIOS Admins" `
  -ManagedBy "admin@company.com" `
  -Members @("admin@company.com", "devops@company.com")

New-DistributionGroup -Name "HELIOS Team" `
  -DisplayName "HELIOS Team" `
  -ManagedBy "admin@company.com"

New-DistributionGroup -Name "HELIOS Alerts" `
  -DisplayName "HELIOS Alerts" `
  -ManagedBy "admin@company.com"
```

### 5.2 Configure Email Notifications

```powershell
# Create transport rule for HELIOS alerts
New-TransportRule -Name "HELIOS Alert Routing" `
  -FromAddress "noreply@helios-platform.onmicrosoft.com" `
  -SentToScope "Internal" `
  -RecipientDomainIs @("company.com") `
  -RouteMessageOutboundConnector "HELIOS-Connector"

# Create another rule for external alerts
New-TransportRule -Name "HELIOS External Alert Routing" `
  -Subject "*HELIOS*" `
  -SentToScope "NotInOrganization" `
  -RouteMessageOutboundConnector "External-Connector"
```

### 5.3 Configure Email Forwarding

```powershell
# Set up forwarding for HELIOS alerts
Set-Mailbox -Identity "helios-alerts@company.com" `
  -ForwardingAddress "helios-admins@company.com" `
  -DeliverToMailboxAndForward $true
```

## Step 6: Configure Microsoft Defender

### 6.1 Enable Threat Protection

```powershell
# Enable Microsoft Defender for Office 365
# Set up policies for protection

# Create Safe Links policy
New-SafeLinksPolicy -Name "HELIOS Safe Links" `
  -AdminDisplayName "HELIOS Safe Links Policy" `
  -IsEnabled $true `
  -ScanUrls $true `
  -DeliverMessageAfterScan $true

# Create Safe Attachments policy
New-SafeAttachmentPolicy -Name "HELIOS Safe Attachments" `
  -Enable $true `
  -Action "Block"

# Create Anti-malware policy
New-MalwareFilterPolicy -Name "HELIOS Anti-Malware" `
  -Action "Quarantine" `
  -EnableInternalSenderAdminNotifications $true
```

### 6.2 Configure Threat Dashboard

```powershell
# Enable threat tracking
# Access via Security & Compliance Center: https://security.microsoft.com

# View threat data
Get-MailDetailTransportRuleReport -EventType Malware |
  Select-Object Date, EventType, DetectionType, Count |
  Format-Table -AutoSize
```

## Step 7: Configure Data Loss Prevention (DLP)

### 7.1 Create DLP Policy

```powershell
# Create DLP compliance policy
$policy = New-DlpCompliancePolicy -Name "HELIOS-Data-Protection" `
  -Comment "Protect HELIOS configurations and sensitive data" `
  -Enabled $true

# Create rule to detect HELIOS API keys
New-DlpComplianceRule -Policy $policy `
  -Name "Detect-HELIOS-API-Keys" `
  -ContentContainsSensitiveInformation @{
    Regex = "HELIOS-[A-Z0-9]{32}"
  } `
  -NotifyUser "All" `
  -BlockAccess $true `
  -BlockAccessScope "All"
```

### 7.2 Configure DLP Exceptions

```powershell
# Add exception for authorized users
$rule = Get-DlpComplianceRule -Identity "Detect-HELIOS-API-Keys"

# Create exception
$rule | Set-DlpComplianceRule `
  -ExceptIfFrom @("admin@company.com", "devops@company.com")
```

## Step 8: User Provisioning

### 8.1 Bulk Import Users

```powershell
# Create CSV with user data
# Format: FirstName,LastName,Email,JobTitle,Department,Manager

$csvFile = "C:\Users\ADMIN\users.csv"

# Import and create users
$users = Import-Csv -Path $csvFile

foreach ($user in $users) {
    # Create user
    $passwordProfile = @{
        ForceChangePasswordNextSignIn = $true
        Password = "TempPassword123!@#"
    }
    
    $newUser = New-MgUser `
      -DisplayName "$($user.FirstName) $($user.LastName)" `
      -MailNickname $user.Email.Split('@')[0] `
      -UserPrincipalName $user.Email `
      -PasswordProfile $passwordProfile `
      -AccountEnabled $true `
      -Department $user.Department `
      -JobTitle $user.JobTitle
    
    # Assign license
    $license = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "SPE_E3" }
    Set-MgUserLicense -UserId $newUser.Id `
      -AddLicenses @{skuId = $license.SkuId} `
      -RemoveLicenses @()
    
    Write-Host "Created user: $($user.Email)"
}
```

### 8.2 Create Groups

```powershell
# Create security groups
New-MgGroup -DisplayName "HELIOS Admins" `
  -MailNickname "helios-admins" `
  -GroupTypes @() `
  -MailEnabled $false `
  -SecurityEnabled $true `
  -Description "HELIOS Platform administrators"

New-MgGroup -DisplayName "HELIOS Team" `
  -MailNickname "helios-team" `
  -GroupTypes @() `
  -MailEnabled $false `
  -SecurityEnabled $true `
  -Description "HELIOS Platform team members"

# Create Office 365 group
New-MgGroup -DisplayName "HELIOS Core Team" `
  -MailNickname "helios-core-team" `
  -GroupTypes @("Unified") `
  -MailEnabled $true `
  -SecurityEnabled $false `
  -Description "HELIOS core team collaboration"
```

### 8.3 Assign Group Memberships

```powershell
# Get group and add members
$adminGroup = Get-MgGroup -Filter "displayName eq 'HELIOS Admins'"
$admin = Get-MgUser -Filter "mail eq 'admin@company.com'"

New-MgGroupMember -GroupId $adminGroup.Id -DirectoryObjectId $admin.Id
```

## Step 9: Configure Compliance

### 9.1 Enable Audit Logging

```powershell
# Enable unified audit log
Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true

# Set retention to 1 year (365 days)
Set-AdminAuditLogConfig -UnifiedAuditLogAgeLimit 365
```

### 9.2 Configure Data Retention

```powershell
# Create retention policy
New-RetentionCompliancePolicy -Name "HELIOS-Retention" `
  -Enabled $true `
  -RetentionDays 2555 `
  -RetentionComplianceRule "HELIOS-Retention-Rule"

# Add rule
New-RetentionComplianceRule -Policy "HELIOS-Retention" `
  -Name "HELIOS-Retention-Rule" `
  -RetentionDuration 2555 `
  -RetentionComplianceAction Delete `
  -RetentionTrigger Created
```

### 9.3 Enable eDiscovery

```powershell
# Create eDiscovery case
$case = New-ComplianceCase -Name "HELIOS eDiscovery Case" `
  -Description "eDiscovery case for HELIOS Platform data"

# Add custodians
Add-ComplianceCaseMember -Case $case.Identity `
  -Member "admin@company.com"
```

## Verification Checklist

- [ ] Connected to Microsoft 365
- [ ] Created HELIOS team
- [ ] Created all channels
- [ ] Added team members
- [ ] Configured OneDrive folder structure
- [ ] Created SharePoint site
- [ ] Created distribution groups
- [ ] Configured email notification rules
- [ ] Set up Microsoft Defender policies
- [ ] Created DLP policies
- [ ] Provisioned users
- [ ] Created security groups
- [ ] Enabled audit logging
- [ ] Configured data retention
- [ ] Tested email delivery
- [ ] Verified team access

## Next Steps

1. **Teams Integration**: Set up Power Automate workflows for notifications
2. **Document Repository**: Populate SharePoint with documentation
3. **User Training**: Train team on Microsoft 365 features
4. **Monitor Usage**: Track adoption and usage patterns
5. **Proceed to Entra ID**: See `../entra-id/README.md`

---

**Version 1.0.0** | **Last Updated**: 2024
