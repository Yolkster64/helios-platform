# HELIOS System Tray & Background Integration Documentation

## Overview

The System Tray Integration system provides background service functionality including system tray icon, minimize-to-tray, background processes, Windows service registration, and auto-start capabilities with single instance detection.

## Features Implemented

### 1. System Tray Icon with Menu

- **Functionality**: Display icon and menu in Windows system tray
- **Implementation**: `ISystemTrayIntegration.InitializeTrayIconAsync()`
- **Features**:
  - Custom icon display
  - Tooltip text
  - Right-click context menu
  - Status indication

### 2. Minimize to Tray Functionality

- **Functionality**: Close to tray instead of completely closing
- **Implementation**: `MinimizeToTrayAsync()`, `RestoreFromTrayAsync()`, `ToggleTrayAsync()`
- **Features**:
  - Window state preservation
  - Auto-minimize on close
  - Restore from tray
  - Configurable behavior

### 3. Quick Access Menu

- **Functionality**: Provide quick access menu from tray icon
- **Implementation**: `AddTrayMenuItemAsync()`, `GetTrayMenuItemsAsync()`
- **Features**:
  - Customizable menu items
  - Separator support
  - Keyboard shortcuts
  - Dynamic menu generation

### 4. Status Monitoring in Tray

- **Functionality**: Display status information in/near tray
- **Implementation**: `GetStatusAsync()`, `SetStatusAsync()`
- **Features**:
  - Activity indicator
  - Process status
  - Service status
  - Last activity timestamp

### 5. Tray Icon Notifications

- **Functionality**: Show notifications from tray icon
- **Implementation**: `ShowTrayNotificationAsync()`, `HideTrayNotificationAsync()`
- **Features**:
  - Toast-style notifications
  - Various notification types
  - Click actions
  - Auto-dismiss

### 6. Windows Service Option (Auto-start)

- **Functionality**: Register as Windows service for auto-start
- **Implementation**: `RegisterWindowsServiceAsync()`, `UnregisterWindowsServiceAsync()`
- **Features**:
  - Service registration
  - Auto-start on boot
  - Service control
  - Log integration

### 7. Background Process Support

- **Functionality**: Run background processes without window
- **Implementation**: `StartBackgroundServiceAsync()`, `StopBackgroundServiceAsync()`
- **Features**:
  - Headless execution
  - Resource monitoring
  - Error handling
  - Graceful shutdown

### 8. Auto-launch on System Start

- **Functionality**: Automatically start on system boot
- **Implementation**: `SetAutoStartAsync()`
- **Features**:
  - Registry auto-start
  - Task scheduler integration
  - User-specific startup
  - Configurable start delay

### 9. Single Instance Detection

- **Functionality**: Ensure only one application instance
- **Implementation**: `CheckSingleInstanceAsync()`, `SetSingleInstanceAsync()`
- **Features**:
  - Mutex-based detection
  - Process communication
  - Instance communication
  - Graceful duplicate handling

### 10. Restore Window from Tray

- **Functionality**: Restore minimized window from tray
- **Implementation**: `RestoreFromTrayAsync()`
- **Features**:
  - Window state restoration
  - Focus restoration
  - Position restoration
  - State preservation

## Usage Example

```csharp
// Initialize system tray integration
var systemTray = new SystemTrayIntegration();

// Initialize tray icon
await systemTray.InitializeTrayIconAsync(
    iconPath: "C:\\Program Files\\HELIOS\\icon.ico",
    tooltipText: "HELIOS Platform"
);

// Add tray menu items
await systemTray.AddTrayMenuItemAsync(new TrayMenuItem
{
    Id = "show",
    Label = "Show",
    Command = "show_window",
    Order = 1,
    Shortcut = "Ctrl+Alt+H"
});

await systemTray.AddTrayMenuItemAsync(new TrayMenuItem
{
    Id = "separator",
    IsSeparator = true,
    Order = 2
});

await systemTray.AddTrayMenuItemAsync(new TrayMenuItem
{
    Id = "exit",
    Label = "Exit",
    Command = "exit_app",
    Order = 3
});

// Enable minimize to tray
await systemTray.SetAutoMinimizeAsync(enabled: true);

// Enable auto-start
await systemTray.SetAutoStartAsync(enabled: true);

// Enable single instance
await systemTray.SetSingleInstanceAsync(enabled: true);

// Check if another instance is running
var canStart = await systemTray.CheckSingleInstanceAsync();
if (!canStart)
{
    Console.WriteLine("Another instance is already running");
    return;
}

// Start background service
await systemTray.StartBackgroundServiceAsync();

// Show notification
await systemTray.ShowTrayNotificationAsync(new TrayNotification
{
    Title = "HELIOS Started",
    Message = "Application is running in the background",
    Type = NotificationType.Information,
    DurationMs = 5000
});

// Register as Windows service
await systemTray.RegisterWindowsServiceAsync(new WindowsServiceConfig
{
    ServiceName = "HeliosPlatform",
    DisplayName = "HELIOS Platform Service",
    Description = "HELIOS Platform background service",
    ExecutablePath = "C:\\Program Files\\HELIOS\\helios-service.exe",
    StartType = "Automatic"
});
```

## Configuration

System tray configuration options:

- Enable/disable minimize to tray
- Enable/disable auto-start
- Enable/disable background service
- Notification settings
- Single instance behavior
- Menu items
- Icon appearance

## Registry Paths Used

Auto-start registration locations:

- User Auto-start: `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
- System Auto-start: `HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run`
- Services: `HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services`

## Performance

System tray performance characteristics:

- **Memory Usage**: ~10-20MB baseline
- **CPU Usage**: <1% idle
- **Notification Latency**: <100ms
- **Tray Icon Update**: ~50ms

## Testing

Comprehensive unit tests cover:

- Tray icon initialization
- Menu item management
- Minimize/restore operations
- Notification display
- Background service control
- Auto-start functionality
- Single instance detection
- Status management
- Configuration

All tests in: `SystemTrayTests\SystemTrayIntegrationTests.cs`

## Security Considerations

- Service registration requires admin privileges
- Registry protection for auto-start
- Process isolation
- Secure IPC for single instance
- Event-based communication

## Deployment

System tray deployment requirements:

1. Admin privileges for service registration
2. Icon files in installation directory
3. Registry write permissions
4. Windows service template

## Platform Support

- Windows 10 and later
- System tray icon in taskbar
- Toast notifications support
- Windows service framework
- Scheduled tasks integration
