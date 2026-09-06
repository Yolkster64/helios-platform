# Phase 10: Advanced User & Account Management System

## Overview

The Advanced User & Account Management System for Phase 10 (USB Builder System) provides comprehensive user account provisioning, permission management, security initialization, profile coordination, and activity monitoring. This system integrates with partitioning, vault, sandbox, and quarantine systems to provide a secure, multi-user environment.

## Architecture

### Core Components

#### 1. UserAccountProvisioner.cs

**Purpose**: Creates and manages system user accounts

**Key Features**:

- Create Administrator accounts with strong security
- Create Primary User accounts for gaming/work/dev
- Create Guest accounts with restricted permissions
- Create Service accounts for HELIOS platform
- User profile directory creation
- Environment variable setup
- Account management (enable/disable)

**Public Methods**:

```csharp
Task<bool> CreateAdministratorAsync(string username, string fullName, string password)
Task<bool> CreatePrimaryUserAsync(string username, string fullName, string password)
Task<bool> CreateGuestAccountAsync(string username, string fullName)
Task<bool> CreateServiceAccountAsync(string username, string password)
Task<bool> UserExistsAsync(string username)
Task<List<UserAccountInfo>> GetAllAccountsAsync()
Task<bool> DisableAccountAsync(string username)
```

**Example Usage**:

```csharp
var provisioner = new UserAccountProvisioner();
await provisioner.CreateAdministratorAsync("admin", "Administrator", "P@ssw0rd!");
await provisioner.CreatePrimaryUserAsync("john", "John Doe", "SecurePass123!");
await provisioner.CreateGuestAccountAsync("guest", "Guest User");
await provisioner.CreateServiceAccountAsync("helios-service", "ServiceP@ss123!");
```

#### 2. AccountPermissionManager.cs

**Purpose**: Implements Role-Based Access Control (RBAC)

**Account Roles**:

- **Administrator**: Full system access, can modify all users/groups
- **StandardUser**: Limited access, can't modify system files/registry
- **Guest**: Very limited, sandbox-like restrictions
- **Service**: System service permissions only

**Key Features**:

- Role-based permission assignment
- Local group management
- NTFS file system permissions
- Registry permissions
- UAC level configuration
- Permission revocation

**Public Methods**:

```csharp
Task<bool> ApplyRolePermissionsAsync(string username, AccountRole role)
Task<bool> RevokeAllPermissionsAsync(string username)
Task<bool> IsAdministratorAsync(string username)
Task<UserPermissions> GetUserPermissionsAsync(string username)
```

**Example Usage**:

```csharp
var permManager = new AccountPermissionManager();
await permManager.ApplyRolePermissionsAsync("john", AccountPermissionManager.AccountRole.StandardUser);
await permManager.ApplyRolePermissionsAsync("admin", AccountPermissionManager.AccountRole.Administrator);

var isAdmin = await permManager.IsAdministratorAsync("admin");
var permissions = await permManager.GetUserPermissionsAsync("john");
```

#### 3. UserDataDirectorySetup.cs

**Purpose**: Creates organized user directory structures

**Standard Directories Created**:

- Desktop
- Documents
- Downloads
- Music
- Pictures
- Videos
- Favorites
- AppData (Local, Roaming, LocalLow)
- HELIOS-specific folders (.helios config, data, cache)
- OneDrive sync folders (optional)

**Key Features**:

- Automatic directory structure creation
- Media folder organization (Artists, Albums, etc.)
- Document categorization (Work, Personal, Projects)
- HELIOS-specific configuration directories
- OneDrive integration support
- Directory cleanup and maintenance
- Directory size calculation

**Public Methods**:

```csharp
Task<bool> SetupUserDirectoriesAsync(string username)
Task<bool> CreateDocumentFoldersAsync(string username)
Task<bool> CreateMediaFoldersAsync(string username)
Task<bool> SetupHELIOSFoldersAsync(string username)
Task<bool> SetupOneDriveFoldersAsync(string username, string oneDrivePath = null)
Task<bool> CleanupUserDirectoriesAsync(string username, bool preserveDocuments = true)
Task<long> GetUserDirectorySizeAsync(string username)
string GetUserProfilePath(string username)
```

**Example Usage**:

```csharp
var dirSetup = new UserDataDirectorySetup();
await dirSetup.SetupUserDirectoriesAsync("john");
await dirSetup.CreateDocumentFoldersAsync("john");
await dirSetup.CreateMediaFoldersAsync("john");
await dirSetup.SetupHELIOSFoldersAsync("john");
await dirSetup.SetupOneDriveFoldersAsync("john");

long size = await dirSetup.GetUserDirectorySizeAsync("john");
```

#### 4. MultiProfileCoordinator.cs

**Purpose**: Manages user profile switching and multi-user coordination

**Key Features**:

- Switch between user profiles gracefully
- Save/load profile states
- Apply profile-specific settings
- Transition services seamlessly
- Update shortcuts and launchers
- Keep HELIOS services running during switches
- Environment variable management
- Display and accessibility settings

**Profile State Management**:

- Tracks active processes
- Stores user-specific settings
- Manages service continuity
- Logs profile switches

**Public Methods**:

```csharp
Task<bool> SwitchUserProfileAsync(string targetUsername, bool gracefulShutdown = true)
Task<bool> KeepServicesRunningAsync()
string GetCurrentUser()
ProfileState GetProfileState(string username)
List<ProfileState> GetAllProfiles()
```

**Example Usage**:

```csharp
var profileCoord = new MultiProfileCoordinator();

// Switch to different user
await profileCoord.SwitchUserProfileAsync("john", gracefulShutdown: true);

// Keep services running during operations
await profileCoord.KeepServicesRunningAsync();

// Get current state
var currentUser = profileCoord.GetCurrentUser();
var profileState = profileCoord.GetProfileState("john");
```

#### 5. UserSecurityInitializer.cs

**Purpose**: Implements comprehensive security initialization and policies

**Security Configuration**:

- Password requirements and complexity
- Account lockout policies
- Password history tracking
- Login timeout configuration
- Audit logging setup
- 2FA framework initialization
- Recovery codes generation

**Default Password Requirements**:

- Minimum length: 12 characters
- Complexity: Required (upper, lower, numbers, special chars)
- History: 5 passwords
- Maximum age: 90 days
- Account lockout after 5 failed attempts
- 30-minute lockout duration

**Public Methods**:

```csharp
Task<bool> InitializeUserSecurityAsync(string username, PasswordRequirements requirements = null)
Task<bool> SetupPasswordHistoryAsync(string username, int historyCount = 5)
Task<bool> ConfigureLoginTimeoutAsync(string username, int timeoutMinutes = 15)
bool ValidatePassword(string password, PasswordRequirements requirements)
Task<SecurityStatus> GetSecurityStatusAsync(string username)
```

**Example Usage**:

```csharp
var securityInit = new UserSecurityInitializer();

// Initialize security with default requirements
await securityInit.InitializeUserSecurityAsync("john");

// Custom password requirements
var customReqs = new UserSecurityInitializer.PasswordRequirements
{
    MinimumLength = 14,
    HistoryCount = 10,
    RequireComplexity = true
};
await securityInit.InitializeUserSecurityAsync("admin", customReqs);

// Validate password
bool isValid = securityInit.ValidatePassword("SecureP@ss0rd!", customReqs);

// Get security status
var status = await securityInit.GetSecurityStatusAsync("john");
Console.WriteLine($"Security Score: {status.SecurityScore}/100");
```

#### 6. AccountActivityMonitor.cs

**Purpose**: Tracks and audits all user account activity

**Tracked Events**:

- Account creation
- Successful/failed logins
- Logouts
- Privilege escalations
- File access (if enabled)
- Policy changes
- Anomalous activities

**Activity Reports**:

- Login statistics
- Privilege escalation tracking
- Anomalous activity detection
- Risk level calculation
- Activity archiving

**Public Methods**:

```csharp
Task<bool> LogAccountCreationAsync(string username, string fullName, string accountType)
Task<bool> LogLoginAttemptAsync(string username, bool successful, string ipAddress = null)
Task<bool> LogLogoutAsync(string username)
Task<bool> LogPrivilegeEscalationAsync(string username, string action, string targetResource)
Task<bool> LogFileAccessAsync(string username, string filePath, string accessType)
Task<bool> LogPolicyChangeAsync(string username, string policyName, string oldValue, string newValue)
Task<ActivityReport> GenerateActivityReportAsync(string username, DateTime startDate, DateTime endDate)
Task<bool> CheckForSuspiciousActivityAsync(string username)
Task<bool> ArchiveOldLogsAsync(int daysToKeep = 90)
```

**Example Usage**:

```csharp
var activityMonitor = new AccountActivityMonitor();

// Log activities
await activityMonitor.LogAccountCreationAsync("john", "John Doe", "PrimaryUser");
await activityMonitor.LogLoginAttemptAsync("john", true, "192.168.1.100");
await activityMonitor.LogPrivilegeEscalationAsync("john", "ModifyRegistry", "HKLM\\Software");

// Generate report
var report = await activityMonitor.GenerateActivityReportAsync(
    "john", 
    DateTime.Now.AddDays(-7), 
    DateTime.Now);

Console.WriteLine($"Risk Level: {report.RiskLevel}");
Console.WriteLine($"Failed Logins: {report.FailedLoginAttempts}");
Console.WriteLine($"Privilege Escalations: {report.PrivilegeEscalationCount}");

// Check for suspicious activity
if (await activityMonitor.CheckForSuspiciousActivityAsync("john"))
{
    Console.WriteLine("Anomalous activity detected!");
}

// Archive old logs
await activityMonitor.ArchiveOldLogsAsync(90);
```

## Integration Interface

The `IUserAccountManagementService` provides a unified interface for orchestrating all services:

```csharp
public interface IUserAccountManagementService
{
    Task InitializeAsync();
    Task<bool> SetupSystemAccountsAsync();
    Task<bool> ProvisionUserAsync(string username, string fullName, string accountType, string password);
    Task<bool> SwitchUserProfileAsync(string username);
    Task<SecurityConfiguration> GetUserSecurityConfigAsync(string username);
    Task<bool> ApplySecurityPoliciesAsync(string username);
    Task<UserActivityReport> GetActivityReportAsync(string username, DateTime startDate, DateTime endDate);
    Task<AccountValidationResult> ValidateAccountAsync(string username);
    Task<bool> RemoveAccountAsync(string username);
    Task<SystemStatus> GetSystemStatusAsync();
}
```

## Setup Guide

### Prerequisites

- .NET 8.0 or higher
- Windows (Server or Desktop)
- Administrator privileges for initial setup
- WMI enabled

### Installation

1. **Add NuGet package** (when published):

   ```bash
   dotnet add package HELIOS.Platform.Phase10.Users
   ```

2. **Initialize services**:

   ```csharp
   var provisioner = new UserAccountProvisioner();
   var permManager = new AccountPermissionManager();
   var dirSetup = new UserDataDirectorySetup();
   var profileCoord = new MultiProfileCoordinator();
   var securityInit = new UserSecurityInitializer();
   var activityMonitor = new AccountActivityMonitor();
   ```

3. **Create system accounts**:

   ```csharp
   // Create administrator account
   await provisioner.CreateAdministratorAsync("admin", "System Administrator", "StrongP@ssw0rd!");
   
   // Create primary user account
   await provisioner.CreatePrimaryUserAsync("user1", "Primary User", "SecurePass123!");
   
   // Create service account
   await provisioner.CreateServiceAccountAsync("helios-service", "ServiceP@ss!");
   
   // Create guest account
   await provisioner.CreateGuestAccountAsync("guest", "Guest User");
   ```

4. **Setup permissions and directories**:

   ```csharp
   // Apply permissions
   await permManager.ApplyRolePermissionsAsync("admin", AccountPermissionManager.AccountRole.Administrator);
   await permManager.ApplyRolePermissionsAsync("user1", AccountPermissionManager.AccountRole.StandardUser);
   
   // Create directories
   await dirSetup.SetupUserDirectoriesAsync("user1");
   await dirSetup.SetupHELIOSFoldersAsync("user1");
   ```

5. **Initialize security**:

   ```csharp
   await securityInit.InitializeUserSecurityAsync("admin");
   await securityInit.InitializeUserSecurityAsync("user1");
   ```

## Security Considerations

### Password Policy

- Minimum 12 characters (configurable)
- Require uppercase letters
- Require lowercase letters
- Require numbers
- Require special characters (!@#$%^&*)
- Password history: 5 previous passwords (configurable)
- Maximum age: 90 days

### Account Lockout

- Failed attempt threshold: 5
- Lockout duration: 30 minutes
- Reset counter: 30 minutes of inactivity

### Audit Logging

- All account operations logged
- Daily log rotation
- 90-day retention (configurable)
- Archive of old logs
- Anomaly detection enabled

### Two-Factor Authentication

- TOTP support
- Recovery codes (10 per account)
- Backup methods configurable

## Testing

The system includes 30+ comprehensive unit tests:

```bash
dotnet test Phase10.Users.Tests --verbosity detailed
```

### Test Coverage

- **UserAccountProvisioner**: 5 tests
  - User existence checks
  - Account listing
  - Account information validation

- **AccountPermissionManager**: 5 tests
  - Administrator role detection
  - Permission retrieval
  - Permission revocation

- **UserDataDirectorySetup**: 6 tests
  - Path validation
  - Directory creation
  - Directory size calculation
  - Cleanup operations

- **MultiProfileCoordinator**: 6 tests
  - Current user tracking
  - Profile state management
  - Service continuity

- **UserSecurityInitializer**: 8 tests
  - Password validation
  - Complexity requirements
  - Security score calculation
  - Policy configuration

- **AccountActivityMonitor**: 10 tests
  - Event logging
  - Activity report generation
  - Risk level calculation
  - Suspicious activity detection

- **Integration Tests**: 2 tests
  - Service integration
  - Async workflow chaining

## Logging

All services implement comprehensive logging to:

- `%APPDATA%\HELIOS\Logs\UserProvisioning.log`
- `%APPDATA%\HELIOS\Logs\Permissions.log`
- `%APPDATA%\HELIOS\Logs\DirectorySetup.log`
- `%APPDATA%\HELIOS\Logs\ProfileCoordinator.log`
- `%APPDATA%\HELIOS\Logs\SecurityInitializer.log`
- `%APPDATA%\HELIOS\Logs\ActivityMonitor.log`

Logs include timestamps, severity levels, and detailed messages for troubleshooting.

## Integration Points

### With Other Phase 10 Systems

- **Partitioning System**: Coordinates user-specific partitions
- **Vault System**: Secures user credentials and recovery codes
- **Sandbox System**: Manages guest/restricted user environments
- **Quarantine System**: Tracks suspicious user activities

### Event Publishing

Services publish events for integration with central audit system:

- User creation events
- Permission changes
- Security policy updates
- Suspicious activity alerts

## Performance Considerations

- All operations are async/await based
- Thread-safe using lock objects
- Minimal resource footprint
- Batch operations supported
- Directory operations optimized for large user base

## Error Handling

All services implement robust error handling:

- Exceptions logged but don't crash services
- Graceful fallbacks
- Detailed error messages
- Recovery procedures

## Future Enhancements

- [ ] LDAP/Active Directory integration
- [ ] Biometric authentication support
- [ ] Advanced anomaly detection (ML-based)
- [ ] Account usage analytics
- [ ] Automated password rotation
- [ ] SSO integration
- [ ] WebAuthn support
- [ ] Geo-location tracking

## Troubleshooting

### Common Issues

**WMI Errors**

- Ensure WMI service is running
- Check user has administrator privileges
- Verify Windows security policies allow WMI access

**Permission Denied**

- Run with administrator privileges
- Check file system ACLs
- Verify registry access permissions

**User Creation Fails**

- Username already exists
- Invalid username format
- Username length exceeds limits

**Security Policy Application**

- Group policy conflicts
- Missing registry paths
- Insufficient permissions

## License

Copyright © 2024 HELIOS Platform. All rights reserved.

## Support

For issues, questions, or contributions, please contact the HELIOS Platform team.
