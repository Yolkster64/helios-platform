# HELIOS Platform Troubleshooting Guide

**Version:** 1.0.0.0  
**Last Updated:** 2024  
**Status:** Production Ready

---

## Quick Diagnostics

Run this script to automatically diagnose issues:

```powershell
# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Run diagnostic
.\Pre-Install-Check.ps1 -Verbose
.\Post-Install-Verify.ps1 -Verbose
```

---

## Installation Issues

### Issue: "Windows 11 Pro/Enterprise Required"

**Error Message:**

```
This installer requires Windows 11 Pro or Enterprise.
Your system does not meet this requirement.
```

**Causes:**

- Running on Windows 10 or older
- Running on Windows 11 Home Edition
- System version not properly detected

**Solutions:**

1. **Check Windows Version:**

   ```powershell
   [System.Environment]::OSVersion.VersionString
   
   # For more details
   Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
   ```

2. **Upgrade Windows Edition:**
   - Home → Pro: Settings → System → Activation
   - Cost: ~$99 USD
   - Requires internet connection during upgrade

3. **Update Windows:**
   - Settings → Update & Security → Windows Update
   - Install all available updates
   - Restart computer
   - Retry installation

4. **Workaround:**
   - Windows 11 Home can run HELIOS as administrator
   - Not officially supported but may work
   - Full feature set may not be available

---

### Issue: "Administrator Privileges Required"

**Error Message:**

```
This installer requires Administrator privileges.
Please run this installer as Administrator.
```

**Solutions:**

1. **Run as Administrator:**
   - Right-click installer
   - Select "Run as Administrator"
   - Click "Yes" in User Account Control

2. **Enable Admin Execution Policy:**

   ```powershell
   # Open PowerShell as Administrator
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

3. **Disable UAC Temporarily:**

   ```powershell
   # Run as Administrator
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" ^
       /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f
   
   # Restart computer
   # Re-enable after installation
   reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" ^
       /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f
   ```

---

### Issue: ".NET 8 SDK Not Found"

**Error Message:**

```
.NET SDK not found. Please install .NET 8 SDK before proceeding.
Visit: https://dotnet.microsoft.com/download
```

**Verification:**

```powershell
# Check if dotnet is installed
dotnet --version

# List all installed runtimes
dotnet --list-runtimes

# List all installed SDKs
dotnet --list-sdks
```

**Solutions:**

1. **Install .NET 8 SDK:**
   - Visit: https://dotnet.microsoft.com/download
   - Download: .NET 8 SDK (x64 for Windows)
   - Run installer
   - Restart computer
   - Retry HELIOS installation

2. **Update PATH After Installation:**

   ```powershell
   # Refresh environment variables
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
   
   # Verify
   dotnet --version
   ```

3. **Verify Installation:**

   ```powershell
   # Check registry
   Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | 
       Where-Object { $_.PSChildName -like "*dotnet*" }
   
   # Check installation folder
   Test-Path "C:\Program Files\dotnet"
   ```

---

### Issue: "Insufficient Disk Space"

**Error Message:**

```
Insufficient disk space.
Minimum 2 GB free space required.
Available: 500 MB
```

**Solutions:**

1. **Check Available Space:**

   ```powershell
   Get-PSDrive | Where-Object { $_.Name -eq "C" }
   ```

2. **Free Up Disk Space:**

   ```powershell
   # Run Disk Cleanup
   cleanmgr.exe
   
   # Remove temporary files
   Remove-Item -Path "$env:TEMP\*" -Force -Recurse
   Remove-Item -Path "$env:WINDIR\Temp\*" -Force -Recurse
   
   # Clear Windows Update cache
   Dism.exe /online /Cleanup-Image /StartComponentCleanup
   ```

3. **Install to Different Drive:**

   ```powershell
   # During installation, select different drive
   # Or specify custom path
   .\HELIOS-Platform-Setup.exe /D=D:\Applications\HELIOS
   ```

4. **Check Large Files:**

   ```powershell
   # Find large files
   Get-ChildItem -Path "C:\" -Recurse -File -ErrorAction SilentlyContinue | 
       Sort-Object Length -Descending | 
       Select-Object FullName, @{n="Size(MB)";e={[math]::Round($_.Length/1MB,2)}} | 
       Head -20
   ```

---

### Issue: "PowerShell 7+ Not Found"

**Warning Message:**

```
PowerShell version 5.1 detected. 
Recommended: PowerShell 7.0+
```

**Solutions:**

1. **Install PowerShell 7+:**
   - **Option 1:** Microsoft Store
     - Search: "PowerShell"
     - Click "Install"

   - **Option 2:** GitHub Releases
     - Visit: https://github.com/PowerShell/PowerShell/releases
     - Download: `PowerShell-7.4.0-win-x64.msi`
     - Run installer

2. **Verify Installation:**

   ```powershell
   pwsh --version
   ```

3. **Update Scripts to Use PowerShell 7:**
   - Right-click .ps1 file
   - Select "Open with" → "Choose another app"
   - Select "Windows PowerShell (beta)" or latest version

---

## Configuration Issues

### Issue: Registry Entries Not Found

**Symptoms:**

- Shortcuts not working
- Application not found in Add/Remove Programs
- Settings lost after restart

**Diagnosis:**

```powershell
# Check registry entries
Test-Path "HKCU:\Software\HELIOS Platform"
Get-ItemProperty "HKCU:\Software\HELIOS Platform"
Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HELIOS Platform"
```

**Solutions:**

1. **Repair Installation:**

   ```powershell
   .\Post-Install-Verify.ps1 -Repair
   ```

2. **Manual Registry Restore:**

   ```powershell
   $instPath = "C:\Program Files\HELIOS Platform"
   
   # Create registry entries
   New-Item -Path "HKCU:\Software\HELIOS Platform" -Force | Out-Null
   Set-ItemProperty -Path "HKCU:\Software\HELIOS Platform" -Name "InstallPath" -Value $instPath
   Set-ItemProperty -Path "HKCU:\Software\HELIOS Platform" -Name "Version" -Value "1.0.0.0"
   ```

3. **Export/Import Registry:**

   ```powershell
   # Export current settings
   Export-RegistryItem -Path "HKCU:\Software\HELIOS Platform" -FilePath "backup.reg"
   
   # Import backup
   reg import backup.reg
   ```

---

### Issue: Environment PATH Not Updated

**Symptoms:**

- Command `HELIOS.Platform.exe` not found at command prompt
- Application not accessible from PATH

**Verification:**

```powershell
# Check current PATH
$env:Path -split ";" | Where-Object { $_ -like "*HELIOS*" }

# Check if HELIOS is in PATH
"C:\Program Files\HELIOS Platform" -in ($env:Path -split ";")
```

**Solutions:**

1. **Add to PATH Manually:**

   ```powershell
   # For current user
   $heliosPath = "C:\Program Files\HELIOS Platform"
   $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
   
   if ($userPath -notlike "*HELIOS*") {
       $newPath = "$userPath;$heliosPath"
       [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
   }
   ```

2. **Add to System PATH:**

   ```powershell
   # Run as Administrator
   $heliosPath = "C:\Program Files\HELIOS Platform"
   $sysPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
   
   if ($sysPath -notlike "*HELIOS*") {
       $newPath = "$sysPath;$heliosPath"
       [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
   }
   
   # Refresh session
   $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
   ```

3. **Verify:**

   ```powershell
   # Restart PowerShell and test
   HELIOS.Platform.exe --version
   ```

---

## Application Issues

### Issue: Application Fails to Start

**Symptoms:**

- Double-click does nothing
- Error window appears briefly
- Task Manager shows exit code 1

**Troubleshooting:**

1. **Check File Exists:**

   ```powershell
   Test-Path "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe"
   ```

2. **Run with Debug Output:**

   ```powershell
   & "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe" --debug --verbose 2>&1
   ```

3. **Check Event Viewer:**

   ```powershell
   # View recent errors
   Get-EventLog -LogName Application -Newest 20 | 
       Where-Object { $_.Source -like "*HELIOS*" }
   ```

4. **Verify .NET Availability:**

   ```powershell
   dotnet --version
   dotnet --list-runtimes
   ```

5. **Run as Administrator:**
   - Right-click application
   - Select "Run as Administrator"
   - Click "Yes"

---

### Issue: Application Crashes on Startup

**Log Location:**

```
C:\Program Files\HELIOS Platform\logs\
```

**Viewing Logs:**

```powershell
# Get recent errors
Get-Content "C:\Program Files\HELIOS Platform\logs\error.log" -Tail 50

# Search for specific errors
Select-String -Path "C:\Program Files\HELIOS Platform\logs\*" -Pattern "error|exception"
```

**Solutions:**

1. **Clear Cache and Logs:**

   ```powershell
   Remove-Item "C:\Program Files\HELIOS Platform\logs\*" -Force
   Remove-Item "C:\Program Files\HELIOS Platform\cache\*" -Force -ErrorAction SilentlyContinue
   ```

2. **Reset Configuration:**

   ```powershell
   # Backup current config
   Copy-Item "C:\Program Files\HELIOS Platform\config\helios.config" `
       "C:\Program Files\HELIOS Platform\config\helios.config.backup"
   
   # Delete config to reset
   Remove-Item "C:\Program Files\HELIOS Platform\config\helios.config"
   
   # Restart application to recreate default config
   ```

3. **Repair Installation:**

   ```powershell
   .\Post-Install-Verify.ps1 -Repair
   ```

---

## Network & Connectivity Issues

### Issue: Cannot Reach Update Server

**Error Message:**

```
Unable to connect to update server.
Check your internet connection.
```

**Solutions:**

1. **Check Internet Connection:**

   ```powershell
   Test-NetConnection -ComputerName "www.google.com" -Port 443
   Test-NetConnection -ComputerName "api.helios.solutions" -Port 443
   ```

2. **Check Firewall Rules:**

   ```powershell
   # View Windows Firewall status
   Get-NetFirewallProfile | Select-Object Name, Enabled
   
   # Check rules for HELIOS
   Get-NetFirewallRule | Where-Object { $_.DisplayName -like "*HELIOS*" }
   ```

3. **Configure Firewall Exception:**

   ```powershell
   # Add firewall rule
   New-NetFirewallRule -DisplayName "HELIOS Platform" `
       -Direction Outbound `
       -Program "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe" `
       -Action Allow
   ```

4. **Disable Proxy Issues:**

   ```powershell
   # Check proxy settings
   netsh winhttp show proxy
   
   # Reset to direct connection
   netsh winhttp reset proxy
   ```

---

## Uninstallation Issues

### Issue: "Failed to Uninstall" Error

**Solutions:**

1. **Force Uninstall:**

   ```powershell
   # Run uninstaller with force flag
   .\Uninstall-HELIOS.ps1 -Force
   ```

2. **Manual Cleanup:**

   ```powershell
   # As Administrator
   
   # Remove files
   Remove-Item "C:\Program Files\HELIOS Platform" -Recurse -Force -ErrorAction SilentlyContinue
   
   # Remove registry
   Remove-Item "HKCU:\Software\HELIOS Platform" -Recurse -Force
   Remove-Item "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HELIOS Platform" -Recurse -Force
   
   # Remove shortcuts
   Remove-Item "$env:SMPROGRAMS\HELIOS Platform" -Recurse -Force
   Remove-Item "$env:DESKTOP\HELIOS*.lnk" -Force
   ```

3. **Check Task Manager:**

   ```powershell
   # End any running HELIOS processes
   Get-Process HELIOS* -ErrorAction SilentlyContinue | Stop-Process -Force
   ```

---

## System Performance Issues

### Issue: High CPU Usage After Installation

**Symptoms:**

- CPU constantly at 50%+
- Fans spinning loudly
- System runs slowly

**Diagnosis:**

```powershell
# Check HELIOS process usage
Get-Process HELIOS* -ErrorAction SilentlyContinue | 
    Select-Object ProcessName, CPU, Memory
```

**Solutions:**

1. **Disable Auto-Start:**

   ```powershell
   # Remove from startup
   Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
       -Name "HELIOS Platform" -ErrorAction SilentlyContinue
   ```

2. **Reduce Monitoring:**

   ```powershell
   # Edit config file
   $configPath = "C:\Program Files\HELIOS Platform\config\helios.config"
   
   # Change LogLevel to Error
   # Disable unnecessary monitoring
   ```

3. **Limit Resource Usage:**

   ```powershell
   # Open Task Scheduler
   # Find HELIOS tasks
   # Right-click → Properties → Resources
   # Set CPU/Memory limits
   ```

---

## Getting Additional Help

### Diagnostic Reports

Generate a comprehensive diagnostic report:

```powershell
# Create diagnostic package
$diagPath = "$env:USERPROFILE\HELIOS-Diagnostics-$(Get-Date -f 'yyyyMMdd')"
New-Item -ItemType Directory -Path $diagPath -Force | Out-Null

# Collect system info
systeminfo > "$diagPath\systeminfo.txt"
Get-EventLog -LogName Application -Newest 100 > "$diagPath\application.log"
Get-Process HELIOS* -ErrorAction SilentlyContinue | Out-File "$diagPath\processes.txt"

# Copy logs
Copy-Item "C:\Program Files\HELIOS Platform\logs\*" "$diagPath\logs\" -Recurse -ErrorAction SilentlyContinue

# Compress
Compress-Archive -Path $diagPath -DestinationPath "$diagPath.zip"

Write-Host "Diagnostic package ready: $diagPath.zip"
```

### Support Contact

- **Email:** support@helios.solutions
- **Forum:** https://community.helios.solutions
- **GitHub:** https://github.com/helios-solutions/platform/issues
- **Docs:** https://docs.helios.solutions

---

**Document Version:** 1.0.0.0  
**Last Updated:** 2024
