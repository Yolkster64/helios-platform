# Entra ID Integration Setup Guide - HELIOS Platform

**Version:** 1.0.0 | **Estimated Setup Time**: 60-90 minutes

## Prerequisites

### Required Modules

```powershell
# Install Microsoft Graph modules
Install-Module Microsoft.Graph.Identity -Force
Install-Module Microsoft.Graph.Users -Force
Install-Module Microsoft.Graph.Groups -Force
Install-Module Microsoft.Graph.Applications -Force
Install-Module Microsoft.Graph.Devices.CloudPC -Force

# Update modules
Update-Module Microsoft.Graph -Force
```

### Required Permissions

- Global Administrator (for initial setup)
- Authentication Policy Administrator
- Security Administrator
- Conditional Access Administrator

## Step 1: Connect to Entra ID

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Directory.ReadWrite.All", "Application.ReadWrite.All", "Policy.ReadWrite.ConditionalAccess"

# Verify connection
Get-MgContext
```

## Step 2: Create User Groups

### 2.1 Create Security Groups

```powershell
# Function to create groups
function New-HeliosSecurityGroup {
    param(
        [string]$DisplayName,
        [string]$MailNickname,
        [string]$Description
    )
    
    New-MgGroup `
      -DisplayName $DisplayName `
      -MailNickname $MailNickname `
      -GroupTypes @() `
      -MailEnabled $false `
      -SecurityEnabled $true `
      -Description $Description
}

# Create groups
New-HeliosSecurityGroup -DisplayName "HELIOS-Global-Admins" `
  -MailNickname "helioscglobaladmins" `
  -Description "Global administrators with full HELIOS access"

New-HeliosSecurityGroup -DisplayName "HELIOS-Admins" `
  -MailNickname "heliosadmins" `
  -Description "HELIOS platform administrators"

New-HeliosSecurityGroup -DisplayName "HELIOS-Operators" `
  -MailNickname "heliosoperators" `
  -Description "HELIOS platform operators"

New-HeliosSecurityGroup -DisplayName "HELIOS-Developers" `
  -MailNickname "heliosdevelopers" `
  -Description "HELIOS platform developers"

New-HeliosSecurityGroup -DisplayName "HELIOS-Viewers" `
  -MailNickname "heliosviewers" `
  -Description "HELIOS platform viewers (read-only access)"

New-HeliosSecurityGroup -DisplayName "HELIOS-Compliance-Team" `
  -MailNickname "helioscompliance" `
  -Description "HELIOS compliance and audit team"
```

### 2.2 Add Members to Groups

```powershell
# Function to add member to group
function Add-HeliosGroupMember {
    param(
        [string]$GroupDisplayName,
        [string]$UserEmail
    )
    
    $group = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'"
    $user = Get-MgUser -Filter "mail eq '$UserEmail'"
    
    New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
}

# Add members to groups
Add-HeliosGroupMember -GroupDisplayName "HELIOS-Global-Admins" -UserEmail "admin@company.com"
Add-HeliosGroupMember -GroupDisplayName "HELIOS-Admins" -UserEmail "devops-admin@company.com"
Add-HeliosGroupMember -GroupDisplayName "HELIOS-Operators" -UserEmail "operator@company.com"
Add-HeliosGroupMember -GroupDisplayName "HELIOS-Developers" -UserEmail "developer@company.com"
```

## Step 3: Configure Multi-Factor Authentication

### 3.1 Enable MFA Policy

```powershell
# Create authentication policy requiring MFA for admins
$policy = New-MgPoliciesAuthenticationMethodPolicy `
  -Description "HELIOS MFA Policy" `
  -IsSystemDefault $false

# Register authenticator app
$methods = @(
    @{
        Id = "MicrosoftAuthenticator"
        IsEnabled = $true
        IncludeTargets = @{
            TargetType = "group"
            Id = "All"
        }
    },
    @{
        Id = "PhoneAuthentication"
        IsEnabled = $true
        IncludeTargets = @{
            TargetType = "group"
            Id = "All"
        }
    }
)
```

### 3.2 Enforce MFA for Admins

```powershell
# Get admin group
$adminGroup = Get-MgGroup -Filter "displayName eq 'HELIOS-Admins'"

# Create conditional access policy for MFA
$params = @{
    DisplayName = "MFA for HELIOS Admins"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeGroups = @($adminGroup.Id)
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("mfa")
    }
    SessionControls = @{
        SignInFrequency = @{
            Value = 1
            Type = "hours"
            IsEnabled = $true
        }
    }
}

# Note: Use Microsoft Graph beta endpoint
# This typically requires PowerShell or Azure Portal UI
```

### 3.3 Configure MFA Methods

```powershell
# Enable multiple MFA methods
# Via Azure Portal: Azure AD → Security → MFA Server

# Recommended configuration:
# - Authenticator App: Primary (required for admins)
# - Phone Call: Secondary
# - SMS: Tertiary (less secure)
# - OATH Hardware Token: For critical admins

# Users can register methods at: https://myaccount.microsoft.com
```

## Step 4: Create Conditional Access Policies

### 4.1 Policy 1: Require MFA for High-Risk Sign-Ins

```powershell
# Create policy (via Azure Portal is recommended)
# Conditions:
#   - Users: All users
#   - Cloud Apps: HELIOS Platform, Azure Management
#   - Sign-in Risk: High
# Grant:
#   - Require MFA

# PowerShell template (note: conditional access requires beta endpoint)
$policy = @{
    DisplayName = "Require MFA for High Risk"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeUsers = @("All")
        }
        Applications = @{
            IncludeApplications = @("00000002-0000-0000-c000-000000000000") # Azure Service Management
        }
        SignInRiskLevels = @("high", "medium")
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("mfa")
    }
}
```

### 4.2 Policy 2: Require Compliant Device

```powershell
# Conditions:
#   - Users: HELIOS-Admins
#   - Cloud Apps: Azure Portal, Microsoft 365 apps
#   - Device state: Any
# Grant:
#   - Mark device as compliant

$policy = @{
    DisplayName = "Require Compliant Device for Admins"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeGroups = @("<admin-group-id>")
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("compliantDevice")
    }
}
```

### 4.3 Policy 3: Block Legacy Authentication

```powershell
# Block users from using less secure protocols
# Conditions:
#   - Users: All users
#   - Cloud Apps: All cloud apps
#   - Client apps: Legacy authentication clients
# Access: Block

$policy = @{
    DisplayName = "Block Legacy Authentication"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeUsers = @("All")
        }
        Applications = @{
            IncludeApplications = @("All")
        }
        ClientAppTypes = @("exchangeActiveSync", "other")
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("block")
    }
}
```

### 4.4 Policy 4: Restrict Access by Location

```powershell
# Restrict high-privilege access to trusted locations
# Conditions:
#   - Users: HELIOS-Global-Admins
#   - Locations: Not from trusted locations
#   - Cloud Apps: Azure Management
# Grant:
#   - Require MFA

$policy = @{
    DisplayName = "Restrict Admin Access by Location"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeGroups = @("<global-admin-group-id>")
        }
        Locations = @{
            ExcludeLocations = @("<trusted-location-id>")
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("mfa")
    }
}
```

## Step 5: Register HELIOS Application

### 5.1 Create App Registration

```powershell
# Create application registration
$params = @{
    DisplayName = "HELIOS Platform"
    SignInAudience = "AzureADMyOrg"
    Web = @{
        RedirectUris = @(
            "https://helios-platform.company.com/auth/callback",
            "https://localhost:3000/auth/callback"
        )
        ImplicitGrantSettings = @{
            EnableIdTokenIssuance = $true
            EnableAccessTokenIssuance = $false
        }
        HomePageUrl = "https://helios-platform.company.com"
    }
}

$app = New-MgApplication @params

Write-Host "Application Created: $($app.Id)"
Write-Host "Application ID (Client ID): $($app.AppId)"
```

### 5.2 Add API Permissions

```powershell
# Get Microsoft Graph service principal
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Add delegated permissions
$requiredResourceAccessParams = @(
    @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
        ResourceAccess = @(
            @{
                Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
                Type = "Scope"
            },
            @{
                Id = "5b567255-7703-4780-807c-7be8301ae99e" # Group.Read.All
                Type = "Scope"
            }
        )
    }
)

Update-MgApplication -ApplicationId $app.Id `
  -RequiredResourceAccess $requiredResourceAccessParams
```

### 5.3 Create Client Secret

```powershell
# Create secret
$secret = Add-MgApplicationPassword -ApplicationId $app.Id

Write-Host "Client Secret: $($secret.SecretText)"
Write-Host "SECRET EXPIRES: $($secret.EndDateTime)"
Write-Host ""
Write-Host "⚠️  SAVE THIS SECRET SECURELY - You cannot retrieve it again"
```

### 5.4 Create Service Principal

```powershell
# Create service principal
$sp = New-MgServicePrincipal -AppId $app.AppId

Write-Host "Service Principal Created: $($sp.Id)"
```

## Step 6: Configure Device Compliance

### 6.1 Create Compliance Policy

```powershell
# Define compliance requirements for Windows devices
# Recommended via Microsoft Intune admin center

# Key compliance settings:
# - Operating System: Windows 10 version 21H2 or later
# - Bitlocker: Enabled
# - Antivirus: Active and up-to-date
# - Firewall: Enabled
# - Security Updates: Current (within 30 days)
# - Password: Enabled, 14+ characters, complexity
```

### 6.2 Create Conditional Access for Compliance

```powershell
# Require compliant devices for sensitive operations
$policy = @{
    DisplayName = "Require Device Compliance for Sensitive Apps"
    State = "enabled"
    Conditions = @{
        Users = @{
            IncludeUsers = @("All")
        }
        Applications = @{
            IncludeApplications = @("All")
        }
    }
    GrantControls = @{
        Operator = "OR"
        BuiltInControls = @("compliantDevice")
    }
}
```

## Step 7: Create Application Roles

### 7.1 Define App Roles

```powershell
# Define roles for HELIOS application
$appRoles = @(
    @{
        AllowedMemberTypes = @("User")
        Description = "HELIOS Global Administrator"
        DisplayName = "HELIOS Global Admin"
        Id = "admin"
        IsEnabled = $true
        Value = "admin"
    },
    @{
        AllowedMemberTypes = @("User")
        Description = "HELIOS Administrator"
        DisplayName = "HELIOS Admin"
        Id = "operator"
        IsEnabled = $true
        Value = "operator"
    },
    @{
        AllowedMemberTypes = @("User")
        Description = "HELIOS Developer"
        DisplayName = "HELIOS Developer"
        Id = "developer"
        IsEnabled = $true
        Value = "developer"
    },
    @{
        AllowedMemberTypes = @("User")
        Description = "HELIOS Viewer"
        DisplayName = "HELIOS Viewer"
        Id = "viewer"
        IsEnabled = $true
        Value = "viewer"
    }
)

# Update application with roles
Update-MgApplication -ApplicationId $app.Id -AppRoles $appRoles
```

### 7.2 Assign Roles to Users

```powershell
# Assign app role to user
# This is typically done through Azure Portal UI or with additional Graph calls

# Example: Assign admin role to user
# Navigate to: Azure Portal → Enterprise Applications → HELIOS Platform → Users and Groups
```

## Step 8: Configure SSO

### 8.1 Enable Single Sign-On

```powershell
# Configure SAML SSO (if using SAML-based apps)
# Configure OAuth 2.0 / OpenID Connect (recommended)

# Redirect URIs configured above will handle callback
# Set in app: https://helios-platform.company.com/auth/callback
```

### 8.2 Configure Token Lifetime

```powershell
# Create token lifetime policy
$tokenLifetimePolicy = @{
    Definition = @(
        '{"TokenLifetimePolicy":{"Version":1,"AccessTokenLifetime":"1:00:00","RefreshTokenLifetime":"7.00:00:00","RefreshTokenAbsoluteLifetime":"90.00:00:00"}}'
    )
    DisplayName = "HELIOS Token Lifetime Policy"
    IsOrganizationDefault = $false
}

# Apply policy to application
$policy = New-MgPoliciesTokenLifetimePolicy @tokenLifetimePolicy
# Then assign: New-MgApplicationTokenLifetimePolicy ...
```

## Step 9: Set Up Synchronization (If Hybrid)

### 9.1 Install Azure AD Connect

```powershell
# Download Azure AD Connect from Microsoft
# https://www.microsoft.com/download/details.aspx?id=47594

# Run installer
# Follow wizard to configure synchronization
```

### 9.2 Configure Sync Options

```
Sync Configuration:
├── Password Hash Sync: Enabled
├── Pass-through Auth: Disabled (unless required)
├── Federation: Disabled (unless required)
├── Sync Scope: All users and groups
├── Sync Frequency: 30 minutes
└── Attribute Sync:
    ├── displayName
    ├── mail
    ├── proxyAddresses
    ├── userPrincipalName
    └── employeeId
```

### 9.3 Verify Sync Status

```powershell
# Check sync status
$syncStatus = Get-ADSyncConnectorRunStatus -ConnectorName "aadconnector"

Write-Host "Sync Status:"
Write-Host "  Last Run: $($syncStatus.RunStartTime)"
Write-Host "  Status: $($syncStatus.RunStatus)"
Write-Host "  Profile: $($syncStatus.RunProfileName)"
```

## Step 10: Enable Audit Logging

### 10.1 Enable Audit Logs

```powershell
# Enable directory audit logging
Update-MgDirectoryAuditLog -Enabled $true

# Configure retention (default 30 days, max 90 days)
```

### 10.2 Query Audit Logs

```powershell
# Get recent directory changes
Get-MgAuditLogDirectoryAudit -Top 10 |
  Select-Object ActivityDisplayName, InitiatedBy, Result, ActivityDateTime |
  Format-Table -AutoSize

# Search for specific activity
Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Add member to group'" |
  Select-Object InitiatedBy, TargetResources, ActivityDateTime |
  Format-Table -AutoSize
```

### 10.3 Enable Sign-In Logs

```powershell
# Sign-in logs are automatically enabled
# Review via Azure Portal or PowerShell

Get-MgAuditLogSignIn -Top 10 |
  Select-Object UserDisplayName, AppDisplayName, Status, CreatedDateTime |
  Format-Table -AutoSize

# Check for failed sign-ins
Get-MgAuditLogSignIn -Filter "status/errorCode ne 0" -Top 10 |
  Select-Object UserDisplayName, Status, CreatedDateTime |
  Format-Table -AutoSize
```

## Step 11: Configure Password Policy

### 11.1 Set Password Requirements

```powershell
# Configure password policy
# Note: This requires Azure AD Premium P1

# Set via Azure Portal:
# Azure AD → Security → Authentication Methods → Password Protection

# Recommended settings:
# - Minimum length: 14 characters
# - Require: Uppercase, Lowercase, Numbers, Special characters
# - Lockout duration: 15 minutes after 5 failed attempts
# - Password expiration: Disabled (not recommended by Microsoft)
# - Remember history: 24 previous passwords
```

### 11.2 Ban Weak Passwords

```powershell
# Configure custom banned password list
# Upload list via Azure Portal:
# Azure AD → Security → Authentication Methods → Password Protection → Custom banned passwords

# Example banned passwords:
# - company name variations
# - common patterns
# - seasonal variations
```

## Step 12: Risky User Detection

### 12.1 Configure Risk Policies

```powershell
# Enable risk-based conditional access
# Azure AD → Security → Identity Protection → Risk policies

# Configure:
# - User Risk Policy: Block high-risk users
# - Sign-in Risk Policy: Require MFA for medium/high risk
```

### 12.2 Review Risky Users

```powershell
# Get users flagged as risky
Get-MgRiskyUser |
  Select-Object UserDisplayName, RiskLevel, RiskLastUpdatedDateTime |
  Format-Table -AutoSize

# Review risky sign-ins
Get-MgAuditLogSignIn -Filter "riskDetail ne 'none'" -Top 20 |
  Select-Object UserDisplayName, RiskDetail, RiskLevelDuringSignIn, CreatedDateTime |
  Format-Table -AutoSize
```

## Verification Checklist

- [ ] Connected to Entra ID
- [ ] Created all security groups
- [ ] Added members to groups
- [ ] Configured MFA policy
- [ ] Created conditional access policies
- [ ] Registered HELIOS application
- [ ] Added API permissions
- [ ] Created service principal
- [ ] Created client secret
- [ ] Configured device compliance
- [ ] Created app roles
- [ ] Configured SSO
- [ ] Enabled audit logging
- [ ] Configured password policy
- [ ] Tested MFA enforcement
- [ ] Verified group membership
- [ ] Tested conditional access

## Next Steps

1. **Test Authentication**: Verify MFA and conditional access
2. **Configure Applications**: Update HELIOS app with credentials
3. **User Training**: Train users on MFA setup
4. **Monitor Logins**: Review sign-in logs
5. **Proceed to Copilot**: See `../copilot/README.md`

---

**Version 1.0.0** | **Last Updated**: 2024
