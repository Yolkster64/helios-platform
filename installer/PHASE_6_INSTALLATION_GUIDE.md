# PHASE 6: INSTALLATION & DEPLOYMENT GUIDE

## Quick Start

### For End Users

#### Windows Installation

```powershell
# 1. Download HELIOS-Platform-2.0-Setup.exe
# 2. Right-click and select "Run as administrator"
# 3. Follow the setup wizard
# 4. Application launches automatically at the end
# 5. Access at http://localhost:5000
```

#### USB Installation

```
1. Insert USB drive into computer
2. Restart computer and boot from USB
3. Select "Install HELIOS Platform" from menu
4. Follow installation wizard
5. Remove USB when complete
```

#### Silent Installation (Scripted Deployment)

```powershell
# Minimal installation
.\HELIOS-Platform-2.0-Setup.exe /S /D=C:\Program Files\HELIOS

# With logging
.\HELIOS-Platform-2.0-Setup.exe /S /D=C:\Program Files\HELIOS /LOG=install.log

# Custom port
.\HELIOS-Platform-2.0-Setup.exe /S /D=C:\Program Files\HELIOS PORT=5050
```

#### Uninstall

```powershell
# Standard uninstall
.\HELIOS-Platform-2.0-Setup.exe /uninstall

# Silent uninstall
.\HELIOS-Platform-2.0-Setup.exe /uninstall /S

# Preserve data
.\HELIOS-Platform-2.0-Setup.exe /uninstall /S /PRESERVEDATA=1
```

### For Developers/IT

#### Pre-Installation Checks

```powershell
cd C:\HELIOS\installer\scripts
.\pre-install-checks.ps1 -Verbose
```

**Output**: Installation approved/blocked with detailed reasons

#### Conflict Detection

```powershell
.\conflict-detection.ps1 -PortRangeStart 5000 -PortRangeEnd 6010 -Verbose
```

**Output**: List of conflicts with severity and resolution steps

#### Post-Installation Verification

```powershell
.\post-install-verify.ps1 -InstallPath "C:\Program Files\HELIOS" -Verbose
```

**Output**: Comprehensive verification report with all checks

#### Diagnostic Reporting

```powershell
# Generate complete diagnostics
$reportPath = ".\installation-diagnostics-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
.\diagnostics-report.ps1 -OutputPath $reportPath
```

**Output**: ZIP archive with logs, registry dumps, firewall rules, etc.

## Installation Types

### Minimal (Core Only)

- **Size**: ~500MB
- **Installation Time**: 1-2 minutes
- **Use Case**: Resource-constrained environments
- **Includes**: Core HELIOS Platform only

```powershell
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /INSTALLTYPE=minimal
```

### Standard (Core + Analytics)

- **Size**: ~1.2GB
- **Installation Time**: 2-3 minutes
- **Use Case**: Typical deployment
- **Includes**: Core + Analytics Engine

```powershell
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /INSTALLTYPE=standard
```

### Full (All Features)

- **Size**: ~2GB+
- **Installation Time**: 3-5 minutes
- **Use Case**: Development/Full deployment
- **Includes**: All features + Dev tools

```powershell
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /INSTALLTYPE=full
```

### Custom (User-Selected)

- **Size**: Variable
- **Installation Time**: 2-4 minutes
- **Use Case**: Specific requirements
- **Includes**: User-selected features

```powershell
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /INSTALLTYPE=custom /FEATURES=Core,Analytics
```

## Port Configuration

### Default Ports

| Port | Service | Purpose |
|------|---------|---------|
| 5000 | HTTP | Web UI and API |
| 5001 | HTTPS | Encrypted traffic |
| 6000 | Diagnostics | Health checks |

### Custom Port Configuration

```powershell
# HTTP on port 8080
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /HTTPPORT=8080

# Multiple custom ports
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /HTTPPORT=8080 /HTTPSPORT=8443 /DIAGPORT=8888
```

### Port Conflict Resolution

```powershell
# Detect conflicts
.\conflict-detection.ps1 -PortRangeStart 5000 -PortRangeEnd 6000

# View processes using ports
netstat -ano | findstr "5000\|5001\|6000"

# Stop conflicting service
Stop-Service -Name ConflictingService

# Reinstall with alternate port
.\HELIOS-Platform-2.0-Setup.exe /S /D=path /HTTPPORT=9000
```

## Service Configuration

### Auto-Start (Default)

```powershell
# Service starts automatically on boot
# Service Name: HELIOSService
# Startup Type: Automatic
# Account: LocalSystem

# Verify service running
Get-Service -Name HELIOSService

# Restart service
Restart-Service -Name HELIOSService
```

### Manual Start

```powershell
# Disable auto-start
.\HELIOS-Platform-2.0-Setup.exe /SERVICESTART=manual

# Start service manually
Start-Service -Name HELIOSService

# Stop service
Stop-Service -Name HELIOSService
```

## Firewall Configuration

### Automatic Configuration

Installer automatically creates three rules:

```
Rule 1: HELIOS Platform HTTP (TCP 5000)
Rule 2: HELIOS Platform HTTPS (TCP 5001)
Rule 3: HELIOS Platform Diagnostics (TCP 6000)
```

### Manual Configuration

```powershell
# Create HTTP rule
New-NetFirewallRule -DisplayName "HELIOS HTTP" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5000

# Create HTTPS rule
New-NetFirewallRule -DisplayName "HELIOS HTTPS" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5001

# List HELIOS rules
Get-NetFirewallRule -DisplayName "HELIOS*"

# Remove HELIOS rules
Get-NetFirewallRule -DisplayName "HELIOS*" | Remove-NetFirewallRule
```

### Third-Party Firewall Configuration

#### Cisco ASA

```
access-list HTTP permit tcp any any eq 5000
access-list HTTPS permit tcp any any eq 5001
access-list DIAG permit tcp any any eq 6000
```

#### Palo Alto Networks

```
Admin → Network → Network Profiles → Service Objects
Create: HELIOS_HTTP (TCP 5000)
Create: HELIOS_HTTPS (TCP 5001)
Create: HELIOS_DIAG (TCP 6000)
```

## Environment Variables

After installation, the following environment variables are set:

```powershell
# HELIOS installation root
$env:HELIOS_HOME

# Installation directory
$env:HELIOS_INSTALL

# Data directory
$env:HELIOS_DATA

# Version number
$env:HELIOS_VERSION

# HTTP port in use
$env:HELIOS_PORT

# View all HELIOS environment variables
Get-ChildItem env:HELIOS*
```

## Registry Entries

Location: `HKLM:\SOFTWARE\HELIOS\`

```
InstallPath: C:\Program Files\HELIOS\
Version: 2.0.0.0
BuildDate: YYYY-MM-DD
Manufacturer: HELIOS Corporation
DisplayName: HELIOS Platform 2.0

Features\
  Core: 1 (always installed)
  Analytics: 0 or 1
  DevTools: 0 or 1

Configuration\
  HttpPort: 5000 (or custom)
  HttpsPort: 5001
  DiagnosticPort: 6000
  AutoUpdate: 1
```

## Troubleshooting

### Installation Fails

**Symptom**: Installation terminates with error

```powershell
# Run pre-installation checks
.\pre-install-checks.ps1 -Verbose

# Check installation logs
Get-Content $env:TEMP\HELIOS-Setup-*.log -Tail 50

# Run conflict detection
.\conflict-detection.ps1 -Verbose

# View Windows Event Log
Get-EventLog -LogName Application -Source HELIOS* -Newest 10
```

### Port Already in Use

**Symptom**: Installation succeeds but cannot access http://localhost:5000

```powershell
# Find process using port
netstat -ano | findstr "5000"

# Stop the process
Stop-Process -Id <PID> -Force

# Reinstall with alternate port
.\HELIOS-Platform-2.0-Setup.exe /S /HTTPPORT=5050

# Verify new port
curl http://localhost:5050/health
```

### Service Won't Start

**Symptom**: Windows Service exists but won't start

```powershell
# Check service status
Get-Service HELIOSService

# View service logs
Get-EventLog -LogName Application -Source HELIOSService -Newest 20

# Restart service
Restart-Service -Name HELIOSService -Force

# If still failing, check prerequisites
.\verification\service-verification.ps1
```

### Antivirus Quarantine

**Symptom**: Installer or application files are quarantined

```powershell
# Add exclusion to antivirus
# Windows Defender example:
Add-MpPreference -ExclusionPath "C:\Program Files\HELIOS"

# Restore quarantined files
# Usually through antivirus GUI

# Reinstall
.\HELIOS-Platform-2.0-Setup.exe /S
```

### Uninstall Leaves Traces

**Symptom**: Files or registry entries remain after uninstall

```powershell
# Manual cleanup of files
Remove-Item -Path "C:\Program Files\HELIOS" -Recurse -Force

# Manual cleanup of registry
Remove-Item -Path "HKLM:\SOFTWARE\HELIOS" -Recurse -Force

# Manual cleanup of shortcuts
Remove-Item -Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\HELIOS Platform" -Recurse -Force

# Manual cleanup of environment variables
[System.Environment]::SetEnvironmentVariable("HELIOS_HOME", "", "Machine")
[System.Environment]::SetEnvironmentVariable("HELIOS_INSTALL", "", "Machine")
```

### USB Image Not Booting

**Symptom**: USB drive doesn't boot

```
1. Verify USB is bootable
   - Insert USB, restart computer
   - Enter BIOS (usually F2, F12, or Del)
   - Set USB as first boot device
   - Save and exit

2. Check boot mode
   - UEFI: Modern systems (Windows 10/11)
   - BIOS: Legacy systems (Windows 7)

3. Recreate USB image
   - Run USB-Creator-Tool.exe
   - Verify checksum before writing
   - Use different USB drive

4. Check BIOS compatibility
   - Enable legacy USB support if needed
   - Disable Secure Boot if issues persist
```

## Enterprise Deployment

### Group Policy Deployment

```batch
# Create deployment share
net use Z: \\deploymentserver\share

# Deploy via Group Policy
psexec -s \\workstation.domain.com "\\deploymentserver\share\HELIOS-Platform-2.0-Setup.exe /S"
```

### SCCM/ConfigMgr Deployment

```
1. Create new Application
2. Name: HELIOS Platform 2.0
3. Deployment Type: Windows Installer (MSI)
4. Source: HELIOS-Platform-2.0-Setup.exe /S /D=%ProgramFiles%\HELIOS
5. Detection Rule: Registry HKLM\SOFTWARE\HELIOS\Version
6. Requirements: Windows 7 SP1+, 4GB RAM, 2GB Disk
7. Deploy to collections
```

### Automated Deployment Script

```powershell
# Deploy HELIOS to multiple computers
$computers = @("PC1", "PC2", "PC3")
$installerPath = "\\deploymentserver\share\HELIOS-Platform-2.0-Setup.exe"

foreach ($computer in $computers) {
    Write-Host "Deploying to $computer..."
    
    # Copy installer
    Copy-Item $installerPath -Destination "\\$computer\c$\temp\" -Force
    
    # Execute installer remotely
    Invoke-Command -ComputerName $computer -ScriptBlock {
        & C:\temp\HELIOS-Platform-2.0-Setup.exe /S /D=C:\Program Files\HELIOS
    }
    
    # Verify installation
    Invoke-Command -ComputerName $computer -ScriptBlock {
        & C:\HELIOS\installer\scripts\post-install-verify.ps1
    }
}
```

## Rollback Procedures

### Automatic Rollback

```powershell
# System automatically rolls back on installation failure
# Snapshot created before installation
# Automatic restoration on critical error
```

### Manual Rollback

```powershell
# List available snapshots
.\deployment\rollback.ps1

# Rollback to specific snapshot
.\deployment\rollback.ps1 -ToSnapshot "pre-helios-install"

# Rollback with confirmation
.\deployment\rollback.ps1 -ToSnapshot "snapshot-name" -Confirm:$true

# Full rollback (to initial state)
.\deployment\rollback.ps1 -Full -Confirm:$false
```

## Performance Tuning

### Optimize Port Configuration

```powershell
# Move to higher performance port range
.\HELIOS-Platform-2.0-Setup.exe /S /HTTPPORT=8080 /HTTPSPORT=8443

# Verify with load test
Invoke-WebRequest -Uri "http://localhost:8080/health" -Verbose
```

### Service Optimization

```powershell
# Set service priority to high
$service = Get-WmiObject Win32_Service -Filter "Name='HELIOSService'"
$service.Change($null, $null, $null, $null, $null, $null, $null, $null, $null, $null, "High") | Out-Null

# Enable service dependency (if needed)
Set-Service -Name HELIOSService -Depends @("RpcSs")
```

## Support & Documentation

- **Installation Help**: https://helios-corp.com/docs/installation
- **Troubleshooting Guide**: https://helios-corp.com/docs/troubleshooting
- **Community Forum**: https://forum.helios-corp.com
- **Enterprise Support**: support@helios-corp.com

---

**Version**: 2.0
**Last Updated**: 2024-04-15
**Status**: Production Ready
