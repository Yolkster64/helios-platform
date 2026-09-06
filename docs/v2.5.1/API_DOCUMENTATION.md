# API Documentation v2.5.1

Complete reference for core classes and interfaces in Helios Platform v2.5.1.

---

## PathConfiguration Class

Manages configuration for system paths and file locations throughout the platform.

### Description

`PathConfiguration` provides centralized path management, ensuring consistent file operations across the platform. It handles environment-specific paths, cache directories, and temporary storage locations.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `RootPath` | string | Base installation directory |
| `ConfigPath` | string | Configuration files directory |
| `CachePath` | string | Cache storage location |
| `TempPath` | string | Temporary files directory |
| `LogPath` | string | Log files directory |
| `UpdatePath` | string | Update packages directory |
| `ProfilePath` | string | User profiles directory |
| `IsValid` | bool | Validates all paths exist |

### Methods

#### GetFullPath(string relativePath)

Converts relative path to full system path.

**Parameters:**

- `relativePath` (string): Relative path from root

**Returns:** Full system path

**Example:**

```csharp
var config = new PathConfiguration();
string fullPath = config.GetFullPath("config/settings.json");
// Returns: C:\Helios\config\settings.json
```

#### EnsureDirectoryExists(string path)

Creates directory if it doesn't exist.

**Parameters:**

- `path` (string): Directory path to verify/create

**Returns:** bool - True if successful

**Example:**

```csharp
var config = new PathConfiguration();
bool created = config.EnsureDirectoryExists(config.CachePath);
if (created) {
    Console.WriteLine("Cache directory ready");
}
```

#### ValidatePaths()

Validates all configured paths are accessible.

**Parameters:** None

**Returns:** PathValidationResult

**Example:**

```csharp
var config = new PathConfiguration();
var result = config.ValidatePaths();
if (!result.IsValid) {
    foreach (var error in result.Errors) {
        Console.WriteLine($"Path error: {error}");
    }
}
```

---

## ErrorHandler Class

Centralized error handling, logging, and recovery system.

### Description

`ErrorHandler` provides consistent error handling across the platform with automatic recovery suggestions, logging, and error categorization.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `IsLoggingEnabled` | bool | Enable/disable logging |
| `LogLevel` | LogLevel | Current logging level |
| `MaxLogSize` | long | Maximum log file size |
| `ErrorCount` | int | Total errors encountered |
| `LastError` | Exception | Most recent exception |

### Methods

#### Handle(Exception ex, string context = null)

Processes and logs an exception with context.

**Parameters:**

- `ex` (Exception): Exception to handle
- `context` (string, optional): Context description

**Returns:** ErrorResult with recovery suggestions

**Example:**

```csharp
var handler = new ErrorHandler();
try {
    // Some operation
} catch (Exception ex) {
    var result = handler.Handle(ex, "During update download");
    Console.WriteLine($"Error: {result.Message}");
    Console.WriteLine($"Suggestion: {result.RecoverySuggestion}");
}
```

#### Log(string message, LogLevel level = LogLevel.Info)

Logs a message with specified level.

**Parameters:**

- `message` (string): Message to log
- `level` (LogLevel): Severity level (Info, Warning, Error, Critical)

**Returns:** void

**Example:**

```csharp
var handler = new ErrorHandler();
handler.Log("Update started", LogLevel.Info);
handler.Log("Retrying connection", LogLevel.Warning);
```

#### GetErrorHistory(int count = 10)

Retrieves recent error entries.

**Parameters:**

- `count` (int): Number of errors to retrieve

**Returns:** List<ErrorEntry>

**Example:**

```csharp
var handler = new ErrorHandler();
var recent = handler.GetErrorHistory(5);
foreach (var error in recent) {
    Console.WriteLine($"[{error.Timestamp}] {error.Message}");
}
```

---

## ServiceInterfaces

Core service abstractions and contracts.

### IUpdateService Interface

Contract for update checking and installation.

**Methods:**

- `CheckForUpdates()`: Async task returning available updates
- `DownloadUpdate(UpdateInfo info)`: Async task for downloading
- `InstallUpdate(UpdateInfo info)`: Async task for installation
- `RollbackUpdate()`: Rollback to previous version

**Example:**

```csharp
public class CustomUpdateImplementation : IUpdateService {
    public async Task<UpdateInfo[]> CheckForUpdates() {
        // Implementation
    }
    
    public async Task DownloadUpdate(UpdateInfo info) {
        // Download logic with 4-concurrent batching
    }
    
    public async Task InstallUpdate(UpdateInfo info) {
        // Installation logic
    }
    
    public void RollbackUpdate() {
        // Rollback logic
    }
}
```

### IConfigurationService Interface

Contract for configuration management.

**Methods:**

- `LoadConfiguration(string path)`: Load config from file
- `SaveConfiguration(string path)`: Persist config to file
- `GetSetting(string key)`: Retrieve setting value
- `SetSetting(string key, object value)`: Update setting

### ILoggingService Interface

Contract for logging operations.

**Methods:**

- `Log(string message, LogLevel level)`: Log message
- `LogException(Exception ex, string context)`: Log exception
- `GetLogs(DateTime from, DateTime to)`: Retrieve logs in range

---

## UpdateService Class

Manages software updates with parallel downloading and installation.

### Description

`UpdateService` handles checking, downloading, and installing updates with built-in parallelization (4 concurrent downloads), error recovery, and rollback capabilities.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `MaxConcurrentDownloads` | int | Concurrent batch size (default: 4) |
| `RetryAttempts` | int | Download retry count |
| `IsUpdateAvailable` | bool | Cached availability status |
| `CurrentVersion` | Version | Currently installed version |
| `AvailableVersions` | Version[] | Available update versions |

### Methods

#### CheckForUpdates()

Checks for available updates from server.

**Parameters:** None

**Returns:** Async Task<UpdateInfo[]>

**Example:**

```csharp
var service = new UpdateService();
var updates = await service.CheckForUpdates();
foreach (var update in updates) {
    Console.WriteLine($"Update available: v{update.Version}");
    Console.WriteLine($"Size: {update.SizeMB} MB");
}
```

#### DownloadUpdate(UpdateInfo info, IProgress<ProgressReport> progress)

Downloads update with progress reporting and parallelization.

**Parameters:**

- `info` (UpdateInfo): Update to download
- `progress` (IProgress<ProgressReport>): Progress callback

**Returns:** Async Task<bool>

**Example:**

```csharp
var service = new UpdateService();
var progress = new Progress<ProgressReport>(report => {
    Console.WriteLine($"Download: {report.Percentage}% ({report.BytesReceived}/{report.TotalBytes})");
});

var update = new UpdateInfo { Version = "2.5.1", Size = 500 };
bool success = await service.DownloadUpdate(update, progress);
if (success) {
    Console.WriteLine("Download complete");
}
```

#### InstallUpdate(UpdateInfo info)

Installs downloaded update with automatic recovery on failure.

**Parameters:**

- `info` (UpdateInfo): Update to install

**Returns:** Async Task<InstallResult>

**Example:**

```csharp
var service = new UpdateService();
var result = await service.InstallUpdate(update);
if (result.Success) {
    Console.WriteLine("Update installed successfully");
    Console.WriteLine($"New version: {result.NewVersion}");
} else {
    Console.WriteLine($"Installation failed: {result.ErrorMessage}");
}
```

#### RollbackUpdate()

Rolls back to previous version if update failed.

**Parameters:** None

**Returns:** Async Task<RollbackResult>

**Example:**

```csharp
var service = new UpdateService();
var result = await service.RollbackUpdate();
if (result.Success) {
    Console.WriteLine("Rolled back to previous version");
}
```

---

## USBManagementGUI Class

User interface for USB creation, profile management, and deployment.

### Description

`USBManagementGUI` provides comprehensive UI for USB wizard, profile switching, boot phases, and system configuration with 4 main tabs.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `ActiveTab` | TabType | Currently active tab |
| `SelectedProfile` | Profile | Currently selected profile |
| `AvailableProfiles` | Profile[] | Available profiles (max 5) |
| `USBDevices` | USBDevice[] | Connected USB devices |
| `IsProcessing` | bool | Operation in progress |

### Methods

#### InitializeGUI()

Initializes UI components and detects USB devices.

**Parameters:** None

**Returns:** void

**Example:**

```csharp
var gui = new USBManagementGUI();
gui.InitializeGUI();
Console.WriteLine($"Detected {gui.USBDevices.Length} USB devices");
```

#### CreateUSBMedia(USBDevice device, Profile profile, IProgress<ProgressReport> progress)

Creates bootable USB with selected profile using optimized StringBuilder rendering.

**Parameters:**

- `device` (USBDevice): USB device to write to
- `profile` (Profile): Profile to deploy
- `progress` (IProgress<ProgressReport>): Progress updates

**Returns:** Async Task<USBCreationResult>

**Example:**

```csharp
var gui = new USBManagementGUI();
var usb = gui.USBDevices[0];
var profile = gui.AvailableProfiles[0];

var progress = new Progress<ProgressReport>(report => {
    Console.WriteLine($"USB Creation: {report.Percentage}%");
});

var result = await gui.CreateUSBMedia(usb, profile, progress);
if (result.Success) {
    Console.WriteLine("USB ready for deployment");
}
```

#### SwitchProfile(Profile profile)

Switches active profile for next deployment.

**Parameters:**

- `profile` (Profile): Profile to activate

**Returns:** bool - Success status

**Example:**

```csharp
var gui = new USBManagementGUI();
var profile = gui.AvailableProfiles.FirstOrDefault(p => p.Name == "Enterprise");
if (gui.SwitchProfile(profile)) {
    Console.WriteLine($"Profile switched to: {profile.Name}");
}
```

#### SetActiveTab(TabType tab)

Switches between 4 main tabs (Wizard, Profiles, Boot, Configuration).

**Parameters:**

- `tab` (TabType): Tab to activate

**Returns:** void

**Example:**

```csharp
var gui = new USBManagementGUI();
gui.SetActiveTab(TabType.Profiles);
// Displays profiles management interface
```

#### ValidateUSB(USBDevice device)

Validates USB device is suitable for media creation.

**Parameters:**

- `device` (USBDevice): USB device to validate

**Returns:** ValidationResult

**Example:**

```csharp
var gui = new USBManagementGUI();
var device = gui.USBDevices[0];
var validation = gui.ValidateUSB(device);
if (!validation.IsValid) {
    foreach (var issue in validation.Issues) {
        Console.WriteLine($"Issue: {issue}");
    }
}
```

---

## Data Models

### UpdateInfo

Represents an available update.

```csharp
public class UpdateInfo {
    public string Version { get; set; }
    public long SizeMB { get; set; }
    public string ChangelogUrl { get; set; }
    public DateTime ReleaseDate { get; set; }
    public bool IsCritical { get; set; }
    public string[] Dependencies { get; set; }
}
```

### Profile

Represents a deployment profile.

```csharp
public class Profile {
    public string Name { get; set; }
    public string Description { get; set; }
    public Dictionary<string, string> Settings { get; set; }
    public string[] BootScripts { get; set; }
    public int Priority { get; set; }
}
```

### ProgressReport

Progress information for long-running operations.

```csharp
public class ProgressReport {
    public int Percentage { get; set; }
    public long BytesReceived { get; set; }
    public long TotalBytes { get; set; }
    public TimeSpan ElapsedTime { get; set; }
    public TimeSpan EstimatedRemainingTime { get; set; }
    public string CurrentOperation { get; set; }
}
```

---

## Code Quality & Performance Notes

### Optimization Features in v2.5.1

1. **Download Parallelization**: UpdateService uses 4-concurrent batch downloads for 3-4x faster update deployment
2. **GUI Optimization**: USBManagementGUI uses StringBuilder for rendering, reducing UI lag by ~60%
3. **Error Recovery**: ErrorHandler includes automatic recovery suggestions
4. **Async/Await**: All long-running operations are non-blocking

### Best Practices

- Always check `IsValid` on PathConfiguration before operations
- Use IProgress for UI updates during long operations
- Implement retry logic with exponential backoff
- Log important events for troubleshooting

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.5.1 | 2024 Q1 | Added parallelization, GUI optimization |
| 2.5.0 | 2023 Q4 | Initial release |

---

Last Updated: 2024  
API Version: 2.5.1
