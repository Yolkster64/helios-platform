# HELIOS Platform Installation Guide

## Professional Windows Installer

**Version:** 1.0.0.0  
**Release Date:** 2024  
**Platform:** Windows 11 Pro/Enterprise  
**Status:** Production Ready

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Pre-Installation](#pre-installation)
3. [Installation Process](#installation-process)
4. [Post-Installation](#post-installation)
5. [Configuration](#configuration)
6. [Deployment Tiers](#deployment-tiers)
7. [Advanced Options](#advanced-options)
8. [Troubleshooting](#troubleshooting)
9. [Uninstallation](#uninstallation)

---

## System Requirements

### Minimum Requirements

| Component | Requirement | Notes |
|-----------|-------------|-------|
| **Operating System** | Windows 11 Pro or Enterprise | Windows Server 2022+ also supported |
| **.NET SDK** | .NET 8.0 or later | Required for platform functionality |
| **PowerShell** | PowerShell 7.0+ | Modern PowerShell with advanced features |
| **RAM** | 4 GB minimum | 8 GB recommended for optimal performance |
| **Disk Space** | 2 GB free | Additional 5 GB for logs and data |
| **Administrator Rights** | Required | Installation requires admin privileges |

### Recommended Configuration

| Component | Recommendation |
|-----------|-----------------|
| **Operating System** | Windows 11 Pro, Build 22621+ |
| **.NET SDK** | .NET 8.0 LTS or .NET 9.0 |
| **PowerShell** | PowerShell 7.4 or later |
| **RAM** | 8 GB or more |
| **Processor** | Multi-core processor, 3 GHz+ |
| **Disk** | SSD with 20 GB free space |

### Network Requirements

- Internet connectivity (optional, for updates)
- Windows Update connectivity (for security patches)
- NuGet package repository access (for package updates)

---

## Pre-Installation

### Step 1: Download Installer

1. Download `HELIOS-Platform-Setup.exe` from the official source
2. Verify file integrity:
   - **SHA256:** Available in release notes
   - Right-click → Properties → Digital Signatures (if signed)

### Step 2: Run Pre-Installation Check

Before installing, run the system check script:

```powershell
# Open PowerShell as Administrator
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Pre-Install-Check.ps1
```

This script verifies:

- ✓ Windows version (11+)
- ✓ Administrator privileges
- ✓ .NET 8 SDK installation
- ✓ PowerShell 7+ availability
- ✓ Disk space (minimum 2 GB)
- ✓ System RAM (minimum 4 GB)
- ✓ Registry access
- ✓ Internet connectivity

### Step 3: Address Any Issues

If the pre-installation check reports errors:

1. **Windows Version:** Upgrade to Windows 11 Pro
2. **.NET SDK:** Download from https://dotnet.microsoft.com/download
3. **PowerShell:** Install from Microsoft Store or https://github.com/PowerShell/PowerShell
4. **Disk Space:** Free up at least 2 GB of space
5. **Administrator:** Right-click installer → Run as Administrator

---

## Installation Process

### Method 1: GUI Installation (Recommended)

1. **Run Installer**

   ```
   Double-click HELIOS-Platform-Setup.exe
   ```

2. **Welcome Screen**
   - Review license agreement
   - Click "Next"

3. **License Agreement**
   - Read the LICENSE.txt file
   - Check "I Agree" checkbox
   - Click "Next"

4. **Component Selection**
   - ☑ HELIOS Platform Core (required)
   - ☑ Start Menu Shortcuts
   - ☑ Desktop Shortcut
   - ☑ Add to PATH
   - Click "Next"

5. **Installation Options**
   - [ ] Enable Auto-Start on Boot (optional)
   - [ ] Enable Telemetry (optional)
   - Choose Installation Drive: C: (recommended)
   - Click "Next"

6. **Installation Directory**
   - Default: `C:\Program Files\HELIOS Platform`
   - Modify if needed
   - Click "Install"

7. **Installation Progress**
   - Monitor installation progress
   - Wait for completion message
   - Click "Finish"

### Method 2: Silent Installation (Automation)

For automated deployments without user interaction:

```powershell
# Silent installation with default settings
.\HELIOS-Platform-Setup.exe /S

# Silent installation with custom path
.\HELIOS-Platform-Setup.exe /S /D=C:\CustomPath\HELIOS

# Silent with auto-start enabled
.\HELIOS-Platform-Setup.exe /S /AUTOSTART=1
```

### Method 3: Command Line with Options

```powershell
# Log installation to file
.\HELIOS-Platform-Setup.exe /LOG="install.log"

# Show installation progress but no UI dialogs
.\HELIOS-Platform-Setup.exe /NC

# Extract installer files without installing
.\HELIOS-Platform-Setup.exe /EXTRACTTO="C:\Extract"
```

---

## Post-Installation

### Step 1: Verify Installation

Run the post-installation verification script:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Post-Install-Verify.ps1
```

This checks:

- ✓ Installation path and files
- ✓ Registry entries
- ✓ System PATH registration
- ✓ Shortcuts creation
- ✓ Application startup

### Step 2: Initial Configuration

1. **Launch HELIOS Platform**
   - From Start Menu: `HELIOS Platform` → `HELIOS Platform`
   - From Desktop shortcut
   - From command line: `HELIOS.Platform.exe`

2. **Configuration Wizard**
   - Select deployment tier
   - Configure deployment options
   - Set monitoring preferences
   - Accept default or customize

3. **First Run Setup**
   - HELIOS Platform initializes components
   - System registry entries are created
   - Baseline configuration is established

### Step 3: Test Installation

```powershell
# Verify executable is accessible
HELIOS.Platform.exe --version

# Run platform health check
HELIOS.Platform.exe --health-check

# Display help information
HELIOS.Platform.exe --help
```

### Step 4: Create Backup

Back up the configuration after initial setup:

```powershell
# Backup configuration
$source = "$env:ProgramFiles\HELIOS Platform\config"
$destination = "$env:USERPROFILE\HELIOS-Backup-$(Get-Date -f 'yyyyMMdd')"
Copy-Item $source $destination -Recurse
```

---

## Configuration

### Configuration File

**Location:** `C:\Program Files\HELIOS Platform\config\helios.config`

```ini
[HELIOS Platform Configuration]
Version=1.0.0.0
InstallDate=2024-01-15
DeploymentTier=Professional
EnableTelemetry=0
EnableAutoStart=0
SystemMonitoring=1
LogLevel=Information
```

### Registry Configuration

**User Settings (Current User):**

```
HKEY_CURRENT_USER\Software\HELIOS Platform
```

**System Settings (All Users):**

```
HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Uninstall\HELIOS Platform
```

### Environment Variables

After installation, the following environment variables are available:

```powershell
# HELIOS installation directory
$env:HELIOS_HOME = "C:\Program Files\HELIOS Platform"

# Application version
$env:HELIOS_VERSION = "1.0.0.0"

# Configuration path
$env:HELIOS_CONFIG = "$env:HELIOS_HOME\config"
```

---

## Deployment Tiers

### Professional Tier

**For:** Standard enterprise deployments

- Core HELIOS Platform components
- Basic automation and deployment
- Standard monitoring
- 8 GB log storage
- Email support

**Installation Size:** ~500 MB

### Enterprise Tier

**For:** Advanced enterprise environments

- All Professional features
- Advanced automation workflows
- Enhanced monitoring and analytics
- 50 GB log storage
- Priority email support

**Installation Size:** ~2 GB

### Ultimate Tier

**For:** Large-scale distributed systems

- All Enterprise features
- Complete component suite
- Distributed deployment support
- Unlimited log storage
- 24/7 phone support
- Custom integrations

**Installation Size:** ~5 GB

---

## Advanced Options

### Enabling Auto-Start

To enable automatic startup on system boot:

**Method 1: During Installation**

- Check "Enable Auto-Start on Boot" in options

**Method 2: After Installation**

```powershell
# Add to startup registry
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$exePath = "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe"
Set-ItemProperty -Path $regPath -Name "HELIOS Platform" -Value "$exePath --silent --auto-start"
```

### Enabling Telemetry

To help improve HELIOS Platform:

```powershell
# Enable telemetry
Set-ItemProperty -Path "HKCU:\Software\HELIOS Platform" -Name "EnableTelemetry" -Value 1

# View telemetry settings
Get-ItemProperty -Path "HKCU:\Software\HELIOS Platform" -Name "EnableTelemetry"
```

### Customizing Installation Path

```powershell
# During installation
.\HELIOS-Platform-Setup.exe /D=D:\Applications\HELIOS

# Update PATH after custom installation
$customPath = "D:\Applications\HELIOS"
$envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$newPath = "$envPath;$customPath"
[System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
```

### Portable/Standalone Mode

```powershell
# Extract files without installing
.\HELIOS-Platform-Setup.exe /EXTRACTTO="C:\HELIOS-Portable"

# Run from extracted location
C:\HELIOS-Portable\HELIOS.Platform.exe
```

---

## Troubleshooting

### Installation Fails with "Access Denied"

**Cause:** Insufficient permissions
**Solution:**

1. Right-click installer
2. Select "Run as Administrator"
3. Click "Yes" in UAC prompt
4. Retry installation

### Pre-Installation Check Shows "Administrator Privileges Required"

**Solution:**

```powershell
# Run PowerShell as Administrator
# Right-click PowerShell → Run as Administrator

# Then run check
.\Pre-Install-Check.ps1
```

### ".NET 8 SDK not found" Error

**Solution:**

1. Download .NET 8 SDK: https://dotnet.microsoft.com/download
2. Run the installer
3. Restart your computer
4. Retry HELIOS installation

### "Insufficient Disk Space" Error

**Solution:**

1. Free up at least 2 GB of disk space
2. Run Disk Cleanup: `cleanmgr.exe`
3. Remove temporary files
4. Retry installation

### Installation Appears to Hang

**Solution:**

1. Wait 5 minutes (initial setup can be slow)
2. If still unresponsive, press Ctrl+C to cancel
3. Uninstall: `Control Panel` → `Programs` → `Uninstall a Program`
4. Restart computer
5. Retry installation

### Post-Installation Verification Fails

**Repair Installation:**

```powershell
.\Post-Install-Verify.ps1 -Repair
```

This automatically restores:

- Registry entries
- Start Menu shortcuts
- Configuration files
- Environment PATH

### Application Won't Start

**Troubleshooting:**

```powershell
# Check if installed correctly
Test-Path "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe"

# Run with debug output
"C:\Program Files\HELIOS Platform\HELIOS.Platform.exe" --debug --verbose

# Check event viewer for errors
Get-EventLog -LogName Application -Source "HELIOS" -Newest 10
```

---

## Uninstallation

### Method 1: GUI Uninstallation

1. Open `Settings`
2. Navigate to `System` → `Apps` → `Installed apps`
3. Search for "HELIOS Platform"
4. Click on "HELIOS Platform"
5. Click "Uninstall"
6. Confirm when prompted
7. Wait for uninstallation to complete

### Method 2: Control Panel

1. Open `Control Panel`
2. Click `Programs` → `Programs and Features`
3. Locate "HELIOS Platform"
4. Right-click → "Uninstall"
5. Follow prompts to complete uninstallation

### Method 3: Command Line

```powershell
# Silently uninstall
"C:\Program Files\HELIOS Platform\Uninstall.exe" /S

# Uninstall and keep configuration
.\Uninstall-HELIOS.ps1 -KeepConfig

# Force uninstall without prompts
.\Uninstall-HELIOS.ps1 -Force
```

### Step 4: Verify Uninstallation

```powershell
# Check if files removed
Test-Path "C:\Program Files\HELIOS Platform"

# Check registry entries removed
Test-Path "HKCU:\Software\HELIOS Platform"

# Check Start Menu
Test-Path "$env:SMPROGRAMS\HELIOS Platform"
```

### Clean Uninstallation (Remove All Data)

```powershell
# Remove all HELIOS data
Remove-Item -Path "$env:ProgramFiles\HELIOS Platform" -Recurse -Force
Remove-Item -Path "$env:APPDATA\HELIOS" -Recurse -Force -ErrorAction SilentlyContinue
```

---

## Support & Resources

### Documentation

- **Official Docs:** https://docs.helios.solutions
- **GitHub Repository:** https://github.com/helios-solutions/platform
- **NuGet Package:** https://www.nuget.org/packages/HELIOS.Platform/

### Support Channels

- **Email:** support@helios.solutions
- **Community Forum:** https://community.helios.solutions
- **GitHub Issues:** https://github.com/helios-solutions/platform/issues
- **Professional Support:** https://helios.solutions/support

### Getting Help

1. Check the troubleshooting guide
2. Review installation logs
3. Search community forum
4. Open GitHub issue
5. Contact professional support

---

## License

HELIOS Platform is provided under the terms specified in LICENSE.txt.
Installation and use implies acceptance of the license agreement.

---

**Last Updated:** 2024  
**Support & Updates:** https://helios.solutions
