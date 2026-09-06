# Security Engine Component

Foundation security system providing authentication, authorization, and access control for HELIOS Platform.

---

## Overview

Security Engine provides the core security foundation for HELIOS. Implements user authentication, role-based access control, intrusion detection, and audit logging. All other HELIOS components build on this foundation.

**Key Facts:**

- **Phase:** 0 (Foundation)
- **Standalone:** ✅ Yes - Fully independent
- **Requires:** .NET Core 3.1+, Windows Event Log
- **Version:** 1.2.0
- **Size:** 156 MB
- **Installation Time:** 3-5 minutes

---

## What It Does

### Core Features

1. **User Authentication**
   - Local user management
   - Password policies and expiration
   - Session management
   - Login attempt tracking

2. **Authorization & Access Control**
   - Role-based access control (RBAC)
   - Permission management
   - Resource-level access control
   - Delegation support

3. **Intrusion Detection**
   - Failed login tracking
   - Brute-force protection
   - Suspicious activity alerts
   - Real-time monitoring

4. **Audit Logging**
   - All access logged
   - Change tracking
   - Compliance reporting
   - History retention

5. **Multi-Factor Authentication** (Optional)
   - MFA provider integration
   - TOTP support
   - SMS/Email codes
   - Hardware tokens

---

## System Requirements

### Minimum

- **OS:** Windows Server 2016+ or Windows 7 SP1+
- **.NET Core:** 3.1 or .NET Framework 4.6.1+
- **RAM:** 1 GB
- **Disk:** 200 MB available
- **Database:** Embedded SQLite or SQL Server

### Recommended

- **OS:** Windows Server 2019+
- **.NET Core:** 6.0 or later
- **RAM:** 2+ GB
- **Disk:** 500 MB available
- **Database:** SQL Server (2016+)

---

## Installation Procedure

### Quick Install

```powershell
cd C:\Users\ADMIN\helios-platform\components\security-engine
.\install.ps1
```

### With SQL Server

```powershell
.\install.ps1 -DatabaseType "SqlServer" `
    -ConnectionString "Server=localhost\SQLEXPRESS;Database=HeliosSecurity;Integrated Security=True"
```

### With Azure AD Integration

```powershell
.\install.ps1 -EnableCloudIdentity -AzureADTenant "your-tenant.onmicrosoft.com"
```

### With MFA Enabled

```powershell
.\install.ps1 -EnableMFA -MFAProvider "Azure"
```

### Silent Installation

```powershell
.\install.ps1 -Silent
# Default admin user created: admin/ChangeMe123!
```

---

## Configuration

**Config File:** `C:\Program Files\HELIOS\security-engine\config.json`

```json
{
  "authentication": {
    "sessionTimeout": 3600,
    "sessionTimeoutWarning": 300,
    "enableMFA": false,
    "mfaProvider": null,
    "rememberMeEnabled": true,
    "rememberMeDays": 30,
    "passwordPolicy": {
      "minLength": 12,
      "requireNumbers": true,
      "requireUpperCase": true,
      "requireLowerCase": true,
      "requireSpecialChars": true,
      "expiryDays": 90,
      "historyCount": 5,
      "lockoutThreshold": 5,
      "lockoutDurationMinutes": 15
    }
  },

  "authorization": {
    "enableRBAC": true,
    "defaultRole": "User",
    "adminRole": "Administrator",
    "delegationAllowed": true
  },

  "intrusion_detection": {
    "enabled": true,
    "sensitivity": "medium",
    "failedLoginThreshold": 5,
    "alertThreshold": 10,
    "lockoutDuration": 15,
    "monitoringEnabled": true
  },

  "audit": {
    "enabled": true,
    "logPath": "C:\\Program Files\\HELIOS\\security-engine\\logs",
    "logLevel": "Information",
    "trackLoginAttempts": true,
    "trackPermissionChanges": true,
    "trackDataAccess": false,
    "retentionDays": 365,
    "uploadToEventLog": true
  },

  "database": {
    "type": "embedded",
    "path": "C:\\Program Files\\HELIOS\\security-engine\\database",
    "connectionString": null,
    "backupEnabled": true,
    "backupPath": "C:\\Backups\\security-engine"
  }
}
```

---

## Usage Examples

### Create User

```powershell
$security = New-Object HeliosPlatform.SecurityEngine.SecurityManager

# Create basic user
$security.CreateUser("john.doe", "john@company.com", "User")

# User must change password on first login
# Send them temporary password via email
```

### Create Administrator

```powershell
$security.CreateUser("admin.user", "admin@company.com", "Administrator")
```

### Authenticate User

```powershell
$auth = $security.AuthenticateUser("john.doe", "password123")

if ($auth.Success) {
    Write-Host "Authentication successful"
    Write-Host "Session Token: $($auth.SessionToken)"
    Write-Host "User ID: $($auth.UserId)"
    Write-Host "Role: $($auth.Role)"
} else {
    Write-Host "Authentication failed: $($auth.ErrorMessage)"
    Write-Host "Reason: $($auth.FailureReason)"
}
```

### Check Permissions

```powershell
$hasPermission = $security.HasPermission(
    $sessionToken,
    "Deploy.Application"
)

if ($hasPermission) {
    # Allow deployment
} else {
    # Deny access
}
```

### List All Users

```powershell
$users = $security.GetAllUsers()

foreach ($user in $users) {
    Write-Host "$($user.Username) - Role: $($user.Role) - Last Login: $($user.LastLoginDate)"
}
```

### View Audit Log

```powershell
$events = $security.GetAuditLog(
    -StartDate (Get-Date).AddDays(-7),
    -EndDate (Get-Date)
)

foreach ($event in $events) {
    Write-Host "$($event.Timestamp): $($event.Action) by $($event.User) - $($event.Details)"
}
```

---

## User Management

### Assign Role

```powershell
$security.AssignRole("john.doe", "Administrator")

# Available roles: Administrator, Operator, User, Viewer
```

### Reset Password

```powershell
# By admin
$security.ResetPassword("john.doe")
# Returns temporary password to send to user

# Self-service
$security.ChangePassword("john.doe", "oldPassword", "newPassword")
```

### Disable/Enable User

```powershell
# Disable user (account locked)
$security.DisableUser("john.doe")

# Enable user
$security.EnableUser("john.doe")
```

### Delete User

```powershell
# Remove user completely
$security.DeleteUser("john.doe")
# WARNING: Irreversible
```

---

## Troubleshooting

### User Locked Out

```powershell
# Check lockout status
$user = $security.GetUser("john.doe")
Write-Host "Locked: $($user.IsLocked)"
Write-Host "Lockout Expires: $($user.LockoutExpiresDate)"

# Unlock immediately (if admin)
$security.UnlockUser("john.doe")
```

### Password Expiration Issues

```powershell
# Check password age
$user = $security.GetUser("john.doe")
Write-Host "Password Changed: $($user.PasswordChangedDate)"

# Force password change on next login
$security.ExpirePassword("john.doe")
```

### Failed Authentication Tracking

```powershell
# Check failed login attempts
$events = $security.GetAuditLog() | Where-Object {$_.Action -eq "LOGIN_FAILED"}

foreach ($event in $events) {
    Write-Host "$($event.Timestamp): $($event.User) - Reason: $($event.Details)"
}
```

### Database Issues

```powershell
# Backup security database
Copy-Item "C:\Program Files\HELIOS\security-engine\database" `
    -Destination "C:\Backup\security-db" -Recurse

# Rebuild indexes if corrupted
.\rebuild-database.ps1
```

---

## File Locations

```
Installation:
C:\Program Files\HELIOS\security-engine\

Application Files:
├── bin\
│   ├── security.exe
│   ├── security.dll
│   └── plugins\

Configuration:
├── config.json

Database:
├── database\
│   ├── users.db
│   ├── permissions.db
│   └── audit.db

Logs:
├── logs\
│   ├── security.log
│   ├── audit.log
│   └── errors.log

Policies:
├── policies\
│   ├── default-policies.json
│   └── custom-policies.json
```

---

## Security Best Practices

1. **Strong Passwords**
   - Enforce: 12+ characters, mixed case, numbers, symbols
   - Update policy in config.json

2. **Regular Audits**
   - Review audit logs weekly
   - Monitor failed login attempts
   - Check for unauthorized access

3. **MFA for Admins**
   - Enable MFA for all administrators
   - Require MFA for sensitive operations

4. **Session Management**
   - Set appropriate session timeout (3600s = 1 hour)
   - Enable session warning alerts

5. **Backup Regularly**
   - Backup security database daily
   - Store backups securely

---

## Uninstall

```powershell
cd C:\Users\ADMIN\helios-platform\components\security-engine

# Remove with data preservation
.\uninstall.ps1 -PreserveData

# Remove completely
.\uninstall.ps1 -CompleteCleanup
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.0 | 2024-01-05 | Enhanced intrusion detection |
| 1.1.0 | 2023-11-01 | MFA improvements |
| 1.0.0 | 2023-09-01 | Initial release |

---

## Support

- **Configuration:** Review config.json settings
- **User Issues:** See User Management section
- **Troubleshooting:** Check Troubleshooting section
- **Standalone Usage:** See INDEPENDENT_INSTALLATION.md
