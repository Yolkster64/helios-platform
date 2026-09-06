# Entra ID Integration for HELIOS Platform

**Version:** 1.0.0 | **Status:** Enterprise Ready

## Overview

Entra ID (formerly Azure AD) provides identity and access management for HELIOS Platform:

- **User Authentication**: SSO for all HELIOS services
- **Multi-Factor Authentication**: Enforce 2FA/MFA policies
- **Conditional Access**: Risk-based access policies
- **Device Compliance**: Manage device enrollment and compliance
- **Application Registration**: HELIOS apps in Entra ID
- **Group Management**: Role-based access control

## Architecture

### Authentication Flow

```
User Attempts to Access HELIOS
            ↓
    Entra ID Authentication
            ↓
    MFA Challenge (if configured)
            ↓
    Conditional Access Evaluation
            ├─ Device Compliance Check
            ├─ Location Check
            ├─ Risk Assessment
            └─ Network Check
            ↓
    Issue Authentication Token
            ↓
    HELIOS Application Receives Token
            ↓
    User Granted Access
```

## User Authentication

### Organizational User Types

| User Type | Scope | Authentication | Examples |
|-----------|-------|---|----------|
| **Employees** | Internal | Entra ID + MFA | devops@company.com |
| **Contractors** | External | B2B Guest + MFA | contractor@external.com |
| **Service Accounts** | System | Certificate/Client Secret | helios-automation |
| **Admins** | Super | Entra ID + MFA + Conditional Access | admin@company.com |

### User Profiles

**Admin Profile**:

```
User: admin@company.com
├── Groups: HELIOS-Admins, Global-Admins
├── Roles: Global Administrator, Security Administrator
├── MFA: Enabled (required)
├── Device Compliance: Required
└── Conditional Access: Strict policies
```

**Operator Profile**:

```
User: operator@company.com
├── Groups: HELIOS-Operators
├── Roles: Contributor, Operator
├── MFA: Enabled (required)
├── Device Compliance: Required
└── Conditional Access: Standard policies
```

**Developer Profile**:

```
User: developer@company.com
├── Groups: HELIOS-Developers
├── Roles: Developer, Contributor
├── MFA: Enabled (required)
├── Device Compliance: Recommended
└── Conditional Access: Standard policies
```

## Multi-Factor Authentication (MFA)

### MFA Methods

| Method | Security | Ease of Use | Cost |
|--------|----------|-------------|------|
| **Authenticator App** | High | Medium | Free |
| **Phone Call** | Medium | High | Free |
| **Text Message (SMS)** | Low | High | Low |
| **Hardware Token** | Very High | Low | Medium |
| **Windows Hello** | Very High | Very High | Free |

### MFA Policy Configuration

**Required for All Users**:

```
Users: helios-admins@company.com
├── MFA Status: Required
├── Methods: Authenticator App, Phone Call
├── Remember Days: 30 days
├── Enforce: Always
└── Exception: Service Accounts (certificate-based)
```

**Recommended for Operators**:

```
Users: helios-operators@company.com
├── MFA Status: Recommended
├── Methods: Authenticator App, SMS, Phone Call
├── Remember Days: 7 days
└── Enforce: On risky sign-ins
```

### Setup MFA

```powershell
# Enable MFA for user
$user = Get-MgUser -Filter "mail eq 'admin@company.com'"

# Register device for MFA
# Users must complete via: https://account.activedirectory.windowsazure.com/

# Verify MFA status
Get-MgUserAuthenticationMethod -UserId $user.Id
```

## Conditional Access

### Conditional Access Policies

**Policy 1: Require MFA for High-Risk Sign-Ins**

```
Conditions:
├── Users: All users
├── Cloud Apps: HELIOS Platform, Azure Management
├── Sign-in Risk: High
└── Device Compliance: Not required

Access Control:
├── Grant: Require MFA
└── Session: MFA frequency: Every sign-in
```

**Policy 2: Require Compliant Device**

```
Conditions:
├── Users: HELIOS-Admins
├── Cloud Apps: Azure Portal, Microsoft 365
├── Device Platforms: All
└── Device State: Any

Access Control:
├── Grant: Require device to be marked as compliant
└── Session: Sign-in frequency: Every sign-in
```

**Policy 3: Block Legacy Authentication**

```
Conditions:
├── Users: All users
├── Cloud Apps: All cloud apps
└── Client Apps: Legacy authentication clients

Access Control:
└── Block: Yes
```

**Policy 4: Restrict Access by Location**

```
Conditions:
├── Users: HELIOS-Admins
├── Locations: Not trusted locations
└── Cloud Apps: Azure Management

Access Control:
├── Grant: Require MFA
└── Session: Sign-in frequency: Every sign-in
```

### Trusted Locations

```
Trusted Locations:
├── Office HQ (203.0.113.0/24)
├── Data Center (198.51.100.0/24)
├── VPN Gateway (192.0.2.0/24)
└── All Microsoft Cloud IPs (auto-updated)

Untrusted:
├── Public WiFi networks
├── Home networks
└── Mobile networks
```

## Device Compliance

### Compliance Requirements

**Windows Devices**:

```
Device: LAPTOP-ADMIN-001
├── OS: Windows 11 Pro or later
├── BitLocker: Enabled (Full Drive)
├── Antivirus: Windows Defender enabled
├── Firewall: Windows Defender Firewall enabled
├── Security Updates: Current (< 14 days)
├── Password Policy: 14+ characters, complexity
├── Screen Lock: Enabled (< 5 min timeout)
├── Account Control: Standard user (non-admin)
└── Compliance Status: ✓ Compliant
```

**macOS Devices**:

```
Device: MacBook-Pro-Dev
├── OS: macOS 13 or later
├── FileVault: Enabled
├── Firewall: Enabled
├── Antivirus: Third-party required
├── Security Updates: Current
├── Password Policy: 14+ characters
├── Screen Lock: Enabled (< 5 min timeout)
└── Compliance Status: ✓ Compliant
```

**Mobile Devices (iOS/Android)**:

```
Device: iPhone-Admin
├── OS: iOS 16 or later
├── Passcode: 6+ digits
├── Encryption: Enabled
├── Device Lock: 1 minute timeout
├── App Protection: Required
└── Compliance Status: ✓ Compliant
```

### Non-Compliant Device Actions

```
Non-Compliant Device Detected: LAPTOP-USER-001
├── Status: Non-Compliant (BitLocker not enabled)
├── Action: Access Denied
├── Message: "Your device does not meet security requirements"
├── Remediation: Enable BitLocker and wait 24 hours
├── Support: Contact helios-support@company.com
└── Block: Removed from HELIOS access until compliant
```

## Application Registration

### Register HELIOS App in Entra

```powershell
# Create application registration
$app = New-MgApplication `
  -DisplayName "HELIOS Platform" `
  -SignInAudience "AzureADMyOrg" `
  -Web @{
    RedirectUris = @(
      "https://helios-platform.company.com/callback",
      "https://localhost:3000/callback"
    )
    ImplicitGrantSettings = @{
      EnableIdTokenIssuance = $true
      EnableAccessTokenIssuance = $false
    }
  }

# Add API permissions
New-MgApplicationApi `
  -ApplicationId $app.Id `
  -Oauth2PermissionScopes @{
    Id = "user_impersonation"
    AdminConsentDisplayName = "Access HELIOS Platform"
    AdminConsentDescription = "Allows the app to access HELIOS Platform"
    IsEnabled = $true
    Type = "User"
    UserConsentDisplayName = "Access HELIOS Platform"
    UserConsentDescription = "Allows the app to access HELIOS Platform"
  }

Write-Host "App Registration Created: $($app.Id)"
```

## Group Management

### Create Security Groups

```powershell
# Create security groups for RBAC
$groups = @(
    @{ Name = "HELIOS-Global-Admins"; Description = "Global administrators" },
    @{ Name = "HELIOS-Admins"; Description = "HELIOS administrators" },
    @{ Name = "HELIOS-Operators"; Description = "HELIOS operators" },
    @{ Name = "HELIOS-Developers"; Description = "HELIOS developers" },
    @{ Name = "HELIOS-Viewers"; Description = "HELIOS viewers (read-only)" }
)

foreach ($group in $groups) {
    New-MgGroup `
      -DisplayName $group.Name `
      -MailNickname $group.Name.Replace("-", "") `
      -GroupTypes @() `
      -MailEnabled $false `
      -SecurityEnabled $true `
      -Description $group.Description
}
```

### Assign Group Members

```powershell
# Get groups and users
$adminGroup = Get-MgGroup -Filter "displayName eq 'HELIOS-Admins'"
$admin = Get-MgUser -Filter "mail eq 'admin@company.com'"

# Add member to group
New-MgGroupMember `
  -GroupId $adminGroup.Id `
  -DirectoryObjectId $admin.Id

# Verify membership
Get-MgGroupMember -GroupId $adminGroup.Id
```

## Service Principal Setup

### Create Service Principal

```powershell
# Get app registration created above
$app = Get-MgApplication -Filter "displayName eq 'HELIOS Platform'"

# Create service principal
$sp = New-MgServicePrincipal `
  -AppId $app.AppId `
  -DisplayName "HELIOS Platform Service"

# Create client secret
$credential = Add-MgApplicationPassword -ApplicationId $app.Id

Write-Host "Service Principal: $($sp.Id)"
Write-Host "Client Secret: $($credential.SecretText)"
```

### Grant Service Principal Permissions

```powershell
# Get Microsoft Graph service principal
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Create delegated permission grant
New-MgOAuth2PermissionGrant `
  -ClientId $sp.Id `
  -ConsentType "AllPrincipals" `
  -ResourceId $graphSp.Id `
  -Scopes @("User.Read", "Group.Read.All", "Mail.Send")
```

## Sync with On-Premises AD

### Azure AD Connect (Hybrid Identity)

If your organization has on-premises Active Directory:

**Synchronization Method**:

```
On-Premises AD
        ↓
Azure AD Connect (Sync Service)
        ↓
Entra ID Cloud
        ↓
HELIOS Platform + Microsoft 365
```

**Configuration**:

```powershell
# Install Azure AD Connect
# Download from: https://www.microsoft.com/download/details.aspx?id=47594

# Configure synchronization:
# 1. User Synchronization: Bi-directional
# 2. Group Synchronization: Bi-directional
# 3. Sync Frequency: 30 minutes (default)
# 4. Password Hash Sync: Enabled
# 5. Device Sync: Enabled

# Verify sync status
$syncStatus = Get-ADSyncConnectorRunStatus -ConnectorName "aadconnector"
$syncStatus | Select-Object ConnectorName, RunStartTime, RunProfileName, RunStatus
```

## Audit and Compliance

### Enable Sign-In Logs

```powershell
# Sign-in logs track all authentication attempts
# Access via: https://portal.azure.com → Entra ID → Sign-in logs

# Query recent sign-ins
Get-MgAuditLogSignIn -Top 10 | 
  Select-Object UserDisplayName, CreatedDateTime, SignInStatus |
  Format-Table -AutoSize
```

### Enable Audit Logs

```powershell
# Enable unified audit logging
Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true -AdminAuditLogAgeLimit 365

# Query audit logs
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-90) `
  -EndDate (Get-Date) `
  -UserIds "admin@company.com" |
  Select-Object Operation, ObjectModified, CreationTime |
  Format-Table -AutoSize
```

### Risky User Detection

```powershell
# Get risky users
Get-MgRiskyUser | 
  Select-Object UserDisplayName, RiskLevel, RiskLastUpdatedDateTime |
  Format-Table -AutoSize

# Dismiss risk
Dismiss-MgRiskyUser -UserId "<user-id>"
```

## Migration from Azure AD to Entra

### Timeline

- **Current**: Azure AD continues to function
- **Q2 2024**: Entra ID becomes primary namespace
- **Gradual Migration**: Existing tenants migrate automatically
- **Refresh Tokens**: Will continue to work during transition

### What Changes

```
Azure AD Portal: https://portal.azure.com
        ↓ (Redirects to)
Entra ID Admin Center: https://entra.microsoft.com
        ↓
Same functionality, new UI and branding
```

### No Action Required For

- Most configurations automatically migrate
- Groups, users, and apps continue to work
- Security policies automatically migrate
- Conditional access policies preserved

## Troubleshooting

### Issue: MFA Not Enforcing

```powershell
# Check conditional access policies
Get-MgIdentityConditionalAccessPolicy | 
  Select-Object Id, DisplayName, State |
  Format-Table -AutoSize

# Verify MFA requirement
$policy = Get-MgIdentityConditionalAccessPolicy -Identity "<policy-id>"
$policy.GrantControls | Select-Object BuiltInControls
```

### Issue: Device Not Compliant

```powershell
# Check device compliance status
Get-MgDeviceManagementDeviceCompliancePolicy |
  Select-Object Id, DisplayName, CreatedDateTime |
  Format-Table -AutoSize

# Review non-compliant devices
Get-MgDeviceManagementDeviceCompliancePolicyDeviceStateSummary |
  Select-Object NonCompliantDeviceCount, CompliantDeviceCount
```

## Best Practices

1. **MFA Always**: Enable for all users, especially admins
2. **Conditional Access**: Use risk-based policies
3. **Device Compliance**: Enforce for sensitive operations
4. **Group Management**: Use groups for RBAC
5. **Audit Logging**: Enable and review regularly
6. **Password Policy**: Enforce strong passwords
7. **Review Permissions**: Quarterly access reviews
8. **Incident Response**: Have playbooks for compromised accounts

---

**Version 1.0.0** | **Last Updated**: 2024
