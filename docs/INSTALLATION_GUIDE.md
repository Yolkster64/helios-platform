# HELIOS Platform Installation Guide

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation Methods](#installation-methods)
3. [Verification](#verification)
4. [Troubleshooting](#troubleshooting)
5. [Uninstallation](#uninstallation)

## System Requirements

### Minimum Requirements

- **OS**: Windows 7 SP1, Windows 8.1, Windows 10, Windows 11
- **.NET Framework**: 4.7.2 or .NET 6.0+
- **RAM**: 512 MB minimum
- **Disk Space**: 100 MB for application + dependencies
- **Internet**: Required for online installation methods

### Recommended Requirements

- **OS**: Windows 10 or Windows 11 (latest version)
- **.NET**: .NET 6.0 or .NET 8.0
- **RAM**: 2 GB or more
- **Disk Space**: 500 MB
- **Internet**: Broadband connection for updates

### Hardware Support

- **Processor**: 64-bit Intel or AMD
- **Graphics**: Any DirectX 12 compatible GPU (optional)
- **Storage**: SSD recommended for better performance

## Installation Methods

### Method 1: Graphical Installer (Recommended for Users)

The easiest method for end-users. Downloads from any distribution channel.

#### Steps:

1. **Download** HELIOS-Setup.exe from:
   - GitHub Releases: https://github.com/HELIOS-Platform/helios-platform/releases
   - Direct Download: https://downloads.helios-platform.org/

2. **Run Installer**

   ```
   Double-click HELIOS-Setup.exe
   ```

3. **Welcome Screen**
   - Click "Next" to begin installation
   - Review license agreement

4. **Choose Installation Directory**
   - Default: `C:\Program Files\HELIOS.Platform`
   - Can customize location
   - Requires ~100 MB free space

5. **Select Components**
   - ✓ Main Application (required)
   - ✓ Demo Applications (optional)
   - ✓ Developer Tools (optional)
   - ✓ Documentation (recommended)

6. **Configure Settings**
   - Desktop shortcuts
   - Start menu items
   - File associations
   - Auto-update settings

7. **Install**
   - Click "Install" to proceed
   - Progress bar shows installation status
   - Takes 2-5 minutes depending on components

8. **Complete**
   - Review completion summary
   - Launch application (optional)
   - Click "Finish"

#### Unattended Installation:

```powershell
HELIOS-Setup.exe /S /D=C:\Program Files\HELIOS.Platform
```

### Method 2: NuGet Package Manager

Best for .NET developers and CI/CD pipelines.

#### Prerequisites:

- NuGet CLI installed
- .NET Framework 4.7.2 or higher

#### Installation:

```powershell
# Basic installation
nuget install HELIOS.Platform

# Specific version
nuget install HELIOS.Platform -Version 1.0.0

# With pre-release
nuget install HELIOS.Platform -PreRelease

# To specific output directory
nuget install HELIOS.Platform -OutputDirectory "C:\Packages"
```

#### In Project File (.csproj):

```xml
<ItemGroup>
  <PackageReference Include="HELIOS.Platform" Version="1.0.0" />
</ItemGroup>
```

### Method 3: Chocolatey Package Manager

For systems with Chocolatey installed. Recommended for system administrators.

#### Prerequisites:

- Chocolatey installed: https://chocolatey.org/install
- Administrator privileges

#### Installation:

```powershell
# Install latest version
choco install helios-platform

# Install specific version
choco install helios-platform --version=1.0.0

# Upgrade existing installation
choco upgrade helios-platform

# Install without confirmation
choco install helios-platform -y
```

#### Verification:

```powershell
choco list --local-only | grep helios-platform
```

### Method 4: Windows Package Manager (Winget)

Modern package manager for Windows 10/11.

#### Prerequisites:

- Windows 10 Build 1809 or later
- App Installer from Microsoft Store

#### Installation:

```powershell
# Install latest version
winget install HELIOS.Platform

# Install specific version
winget install HELIOS.Platform --version 1.0.0

# Show available versions
winget show HELIOS.Platform --versions
```

### Method 5: Command-Line Installation

Using command-line parameters for scripting.

```powershell
# Silent installation with defaults
HELIOS-Setup.exe /S

# Silent with custom directory
HELIOS-Setup.exe /S /D=C:\CustomPath\HELIOS

# Silent with specific components
HELIOS-Setup.exe /S /Components=Main,Demos

# Generate log file
HELIOS-Setup.exe /S /LogFile=install.log

# No restart
HELIOS-Setup.exe /S /NoRestart
```

### Method 6: Portable Version

No installation required. Extracted folder can be used directly.

#### Steps:

1. Download `HELIOS.Platform-Portable.zip`
2. Extract to desired location
3. Run `HELIOS.Platform.exe`
4. No admin privileges required

## Post-Installation Setup

### First Launch

```powershell
# Run from Start Menu or:
C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe

# Or use command line:
HELIOS.Platform --launch
```

### Try Demo Applications

```powershell
# Games demo
demo-games.exe

# Developer tools demo
demo-dev.exe

# Security features demo
demo-security.exe
```

### Configure Settings

Launch Settings from:

- Start Menu → HELIOS Platform → Settings
- Or: File → Settings menu
- Or: Run `HELIOS.Platform --settings`

### Register License (if required)

```powershell
HELIOS.Platform.exe --license-key YOUR_LICENSE_KEY
```

## Verification

### Check Installation

```powershell
# Display version
HELIOS.Platform --version

# Check installation path
HELIOS.Platform --info

# Verify components
HELIOS.Platform --list-components

# Run diagnostics
HELIOS.Platform --diagnostics
```

### Verify File Integrity

```powershell
# Check file signatures
HELIOS.Platform --verify-integrity

# Validate checksums
Get-FileHash 'C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe' -Algorithm SHA256
```

### Test Connectivity

```powershell
HELIOS.Platform --test-connection

# Check for updates
HELIOS.Platform --check-updates
```

## Troubleshooting

### Installation Issues

#### "Administrator privileges required"

```powershell
# Run installer as administrator
Start-Process HELIOS-Setup.exe -Verb RunAs
```

#### "Insufficient disk space"

- Free at least 200 MB on target drive
- Install to different drive with more space

#### ".NET Framework not found"

```powershell
# Check installed .NET versions
dotnet --info

# Install required framework
# Download from: https://dotnet.microsoft.com/download
```

#### "File is locked" error

- Close any running HELIOS processes
- Restart Windows in Safe Mode
- Try installation again

### Runtime Issues

#### Application won't start

```powershell
# Try compatibility mode:
# 1. Right-click executable
# 2. Properties → Compatibility
# 3. Select Windows 8 or 7 mode
# 4. Run as administrator

# Or from command line:
HELIOS.Platform.exe --safe-mode
```

#### Permission denied errors

```powershell
# Run as administrator
Start-Process HELIOS.Platform.exe -Verb RunAs

# Check folder permissions
icacls 'C:\Program Files\HELIOS.Platform'
```

#### High CPU or memory usage

```powershell
# Disable auto-update
HELIOS.Platform.exe --disable-auto-update

# Clear cache
Remove-Item $env:APPDATA\HELIOS.Platform\Cache -Recurse

# Reset to defaults
HELIOS.Platform.exe --reset-config
```

### Network Issues

#### Can't access online features

- Check internet connection
- Verify firewall allows HELIOS
- Check proxy settings

```powershell
# Configure proxy
HELIOS.Platform.exe --proxy SERVER:PORT

# Disable proxy
HELIOS.Platform.exe --no-proxy
```

#### Update check fails

```powershell
# Manual update check
HELIOS.Platform.exe --update-force

# Skip update check
HELIOS.Platform.exe --no-check-updates
```

## Uninstallation

### Via Control Panel

1. Open **Control Panel**
2. Go to **Programs** → **Programs and Features**
3. Find **HELIOS Platform**
4. Click **Uninstall**
5. Confirm removal

### Via Command Line

```powershell
# Using Add/Remove Programs
appwiz.cpl

# Or directly:
MsiExec.exe /X{ProductCode} /qb

# From installation directory:
HELIOS-Setup.exe /uninstall
```

### Chocolatey Uninstall

```powershell
choco uninstall helios-platform
```

### Winget Uninstall

```powershell
winget uninstall HELIOS.Platform
```

### Manual Uninstall

```powershell
# Stop running processes
Stop-Process -Name HELIOS.Platform -Force -ErrorAction SilentlyContinue

# Remove files
Remove-Item 'C:\Program Files\HELIOS.Platform' -Recurse -Force

# Remove Start Menu shortcuts
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\HELIOS*" -Force

# Clean registry (if using MSI)
Remove-Item 'HKLM:\Software\HELIOS.Platform' -Force -ErrorAction SilentlyContinue
```

### Remove User Data

```powershell
# Remove application data
Remove-Item "$env:APPDATA\HELIOS.Platform" -Recurse -Force

# Remove local cache
Remove-Item "$env:LOCALAPPDATA\HELIOS.Platform" -Recurse -Force
```

## Repair Installation

If installation is corrupted:

```powershell
# Repair from command line
HELIOS-Setup.exe /Repair

# Or reinstall completely
HELIOS-Setup.exe /uninstall
HELIOS-Setup.exe /S

# Using Add/Remove Programs
# Select HELIOS Platform → Repair
```

## Update Management

### Check for Updates

```powershell
HELIOS.Platform --check-updates
```

### Install Updates

- Automatic (default): Updates install on exit
- Manual: HELIOS → Help → Check for Updates
- Command: `HELIOS.Platform --update`

### Disable Updates

```powershell
HELIOS.Platform --disable-auto-update
```

### Rollback to Previous Version

```powershell
# Via Add/Remove Programs (if update reverted system restore)
# Or reinstall previous version manually
```

## Support & Help

- **Documentation**: https://helios-platform.github.io/
- **Troubleshooting**: https://github.com/HELIOS-Platform/helios-platform/wiki
- **Report Issues**: https://github.com/HELIOS-Platform/helios-platform/issues
- **Chat**: https://github.com/HELIOS-Platform/helios-platform/discussions
- **Email**: support@helios-platform.org

---

**Version**: 1.0.0
**Last Updated**: 2024
**Platform**: Windows 7 SP1+
**License**: MIT
