# HELIOS Platform Installation & Integration Guide

## Table of Contents

1. [Installation Guide](#installation-guide)
2. [Shell Extension Integration](#shell-extension-integration)
3. [System Tray Application](#system-tray-application)
4. [Windows Service Setup](#windows-service-setup)
5. [Partition Management](#partition-management)
6. [System Requirements Detection](#system-requirements-detection)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Configuration](#advanced-configuration)

---

## Installation Guide

### Quick Installation

For a fast, automatic installation with sensible defaults:

```powershell
cd $InstallPath\scripts
.\Install-HELIOS.ps1 -InstallMode Quick
```

### Advanced Installation

For detailed component selection and configuration:

```powershell
.\Install-HELIOS.ps1 -InstallMode Advanced `
    -EnableShellExtension `
    -EnableSystemService `
    -EnableAutoStart
```

### Silent Installation

For automated/scripted deployment without UI:

```powershell
.\Install-HELIOS.ps1 -InstallMode Silent `
    -InstallPath "D:\HELIOS Platform" `
    -EnableShellExtension `
    -EnableSystemService
```

### Portable Installation

For USB or portable media deployment:

```powershell
.\Install-HELIOS.ps1 -InstallMode Portable `
    -InstallPath "E:\HELIOS Platform"
```

### Installation Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| InstallPath | String | $ProgramFiles\HELIOS Platform | Installation directory |
| InstallMode | Enum | Quick | Installation mode (Quick/Advanced/Silent/Portable) |
| EnableShellExtension | Switch | False | Register context menu items |
| EnableSystemService | Switch | False | Install Windows Service |
| EnableAutoStart | Switch | False | Start with Windows |

---

## Shell Extension Integration

### Context Menu Registration

The shell extension adds "Open with HELIOS Platform" to file context menus.

#### Automatic Registration

The Install-HELIOS.ps1 script handles registration automatically when `-EnableShellExtension` is used.

#### Manual Registration

```csharp
// In C# code
ShellExtension.ContextMenuRegistration.Register();
```

### File Associations

Associate custom file types with HELIOS:

```powershell
[HELIOS.Platform.ShellExtension.FileAssociationManager]::AssociateExtension(".helios", "HELIOS Project File")
```

### Protocol Handlers

Register custom protocols (e.g., helios://):

```powershell
[HELIOS.Platform.ShellExtension.FileAssociationManager]::RegisterProtocol("helios")
```

### Unregistering Extensions

```csharp
ShellExtension.ContextMenuRegistration.Unregister();
```

---

## System Tray Application

### Starting the Tray Application

```powershell
& "$env:ProgramFiles\HELIOS Platform\HELIOS.Platform.Tray.exe"
```

### Tray Features

1. **Minimize to Tray**: Click the tray icon to minimize/restore
2. **Status Indicators**: Real-time system status display
3. **Quick Menu**: Right-click menu with common actions
4. **Notifications**: System notifications for important events

### Tray Menu Options

| Option | Description |
|--------|-------------|
| Dashboard | Open main HELIOS dashboard |
| Status Monitor | View system status and metrics |
| Settings | Configure HELIOS preferences |
| About HELIOS | Version and license information |
| Exit | Close HELIOS Platform |

### Configuration

To enable auto-start of the tray application:

```powershell
# Via installer
.\Install-HELIOS.ps1 -EnableAutoStart

# Or manually in registry
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $regPath -Name "HELIOS Platform" `
    -Value "$env:ProgramFiles\HELIOS Platform\HELIOS.Platform.Tray.exe"
```

---

## Windows Service Setup

### Service Installation

Install the HELIOS background service:

```powershell
.\Manage-Service.ps1 -Install `
    -ServicePath "C:\Program Files\HELIOS Platform\HELIOS.Platform.Service.exe"
```

### Service Management

#### Start Service

```powershell
.\Manage-Service.ps1 -Start
```

#### Stop Service

```powershell
.\Manage-Service.ps1 -Stop
```

#### Check Status

```powershell
.\Manage-Service.ps1 -Status
```

#### Enable Auto-Start

```powershell
.\Manage-Service.ps1 -AutoStart
```

#### Uninstall Service

```powershell
.\Manage-Service.ps1 -Uninstall
```

### Service Recovery

The installer automatically configures service recovery:

- **Restart on failure**: After 60 seconds
- **Max restarts**: 3 attempts within 24 hours

### Service Logs

Check service logs in Event Viewer:

- **Log**: System
- **Source**: HeliosPlatformService

---

## Partition Management

### Analyze Current Partitions

```powershell
.\Manage-Partitions.ps1 -Analyze
```

Displays:

- Drive letters and labels
- File systems
- Total/Used/Free space
- Usage percentage and visualization

### View Storage Recommendations

```powershell
.\Manage-Partitions.ps1 -ShowRecommendations
```

Shows:

- Low disk space warnings
- System drive optimization suggestions
- Partition defragmentation status

### DevDrive Creation

```powershell
.\Manage-Partitions.ps1 -CreateDevDrive -DriveLetter E
```

**Note**: Requires Windows 11 24H2 or later

### Optimize Partitions

```powershell
.\Manage-Partitions.ps1 -Optimize
```

Performs:

- NTFS defragmentation
- SSD TRIM operations
- Volume optimization

---

## System Requirements Detection

### Programmatic Access

```csharp
using HELIOS.Platform.SystemIntegration;

// Check system requirements
var requirements = SystemDetector.CheckSystemRequirements();
if (requirements.IsPassed)
{
    // Installation can proceed
}

// Get partition info
var partitions = SystemDetector.GetPartitionInfo();
foreach (var partition in partitions.Partitions)
{
    Console.WriteLine($"Drive: {partition.DriveLetter}");
    Console.WriteLine($"Free Space: {partition.AvailableSpace / (1024*1024*1024)} GB");
}

// Get license info
var license = SystemDetector.GetLicenseInfo();
Console.WriteLine($"OS: {license.ProductName}");
Console.WriteLine($"License: {license.LicenseStatus}");

// Get devices
var network = SystemDetector.GetNetworkDevices();
var storage = SystemDetector.GetStorageDevices();
var printers = SystemDetector.GetPrinters();
```

### System Requirements Check

HELIOS requires:

- ✓ Windows 11 Professional or Enterprise
- ✓ 5 GB free disk space
- ✓ 4 GB RAM
- ✓ Administrator privileges

---

## Uninstallation

### Standard Uninstall

```powershell
.\Uninstall-HELIOS.ps1
```

Interactive uninstaller with options:

- [C]ontinue - Proceed immediately
- [B]ackup first - Create backup before removing
- [E]xit - Cancel

### Silent Uninstall

```powershell
.\Uninstall-HELIOS.ps1 -Force
```

### Remove User Data

```powershell
.\Uninstall-HELIOS.ps1 -RemoveUserData -Force
```

### What Gets Removed

1. Installation files
2. Registry entries
3. Shell extensions
4. Windows Service
5. Start menu shortcuts
6. Auto-start configurations

### Backup Preservation

By default, a backup is created:

```
C:\Program Files\HELIOS Platform.backup.20240115_143022
```

---

## Advanced Configuration

### Custom Installation Path

```powershell
.\Install-HELIOS.ps1 -InstallPath "D:\CustomPath\HELIOS"
```

### Enable All Features

```powershell
.\Install-HELIOS.ps1 `
    -InstallMode Advanced `
    -EnableShellExtension `
    -EnableSystemService `
    -EnableAutoStart
```

### Component-Specific Installation

The HELIOS installer supports installing individual components:

```powershell
# Core only
.\Install-HELIOS.ps1 -InstallMode Advanced  # Then deselect optional components

# With all services
.\Install-HELIOS.ps1 `
    -EnableSystemService `
    -EnableAutoStart
```

### Registry Customization

Key registry locations:

```
HKLM:\SOFTWARE\HELIOS Platform
HKCU:\Software\Classes\*\shell\HELIOS
HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
```

---

## Troubleshooting

### Installation Fails

1. **Check Administrator Rights**

   ```powershell
   [Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'
   ```

2. **Check Disk Space**

   ```powershell
   Get-Volume | Where-Object { $_.DriveLetter -eq 'C' }
   ```

3. **Check Installation Log**

   ```powershell
   Get-Content "$env:TEMP\HELIOS_Install_*.log" -Tail 50
   ```

### Service Won't Start

1. **Check Service Status**

   ```powershell
   Get-Service HeliosPlatformService
   ```

2. **View Event Logs**

   ```powershell
   Get-EventLog System | Where-Object { $_.Source -eq 'HeliosPlatformService' }
   ```

3. **Check Service Executable**

   ```powershell
   Test-Path "C:\Program Files\HELIOS Platform\HELIOS.Platform.Service.exe"
   ```

### Context Menu Not Appearing

1. **Verify Registration**

   ```powershell
   Test-Path 'HKCU:\Software\Classes\*\shell\HELIOS'
   ```

2. **Re-register Extensions**

   ```powershell
   .\Install-HELIOS.ps1 -EnableShellExtension
   ```

3. **Explorer Restart**

   ```powershell
   Stop-Process -Name explorer -Force
   Start-Process explorer
   ```

### Tray Application Crashes

1. **Check Application Log**

   ```powershell
   Get-EventLog Application | Where-Object { $_.Source -match 'HELIOS' }
   ```

2. **Try Standalone**

   ```powershell
   & "C:\Program Files\HELIOS Platform\HELIOS.Platform.Tray.exe" -debug
   ```

---

## Support & Documentation

For additional help:

- Check log files in `%TEMP%\HELIOS_*.log`
- Review Event Viewer for system events
- Consult SYSTEM_REQUIREMENTS.md for detailed requirements
- See INSTALLATION_GUIDE.md for detailed procedures

---

**Version**: 1.0.0  
**Last Updated**: 2024  
**License**: MIT  
© 2024 HELIOS Solutions. All rights reserved.
