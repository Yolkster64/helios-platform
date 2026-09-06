# HELIOS Platform Installer - Quick Reference Card

**Version:** 1.0.0.0 | **Status:** Production Ready | **Platform:** Windows 11 Pro/Enterprise

---

## 📋 QUICK START

### For End Users

```powershell
1. Run: .\Pre-Install-Check.ps1
2. Run: HELIOS-Platform-Setup.exe
3. Follow on-screen wizard
4. Run: .\Post-Install-Verify.ps1
```

### For IT Administrators

```powershell
# Silent install
.\HELIOS-Platform-Setup.exe /S /D=C:\Program Files\HELIOS

# Verify
.\Post-Install-Verify.ps1

# Uninstall
.\HELIOS-Platform-Setup.exe /UNINSTALL /S
```

### For Developers

```powershell
# Build installer
.\Build-Installer.ps1 -OutputPath ".\build"

# Build with signing
.\Build-Installer.ps1 -SignCertificate "cert.pfx" -CertPassword "pwd"
```

---

## ✅ SYSTEM REQUIREMENTS

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Windows 11 Pro | Windows 11 Pro Build 22621+ |
| **.NET** | .NET 8.0 | .NET 8.0 LTS |
| **PowerShell** | 7.0+ | 7.4+ |
| **RAM** | 4 GB | 8 GB+ |
| **Disk** | 2 GB free | 20 GB SSD |
| **CPU** | 1 GHz | Multi-core 3 GHz+ |

---

## 📦 FILES PROVIDED

| File | Size | Purpose |
|------|------|---------|
| `setup.nsi` | 8 KB | Installer script |
| `Build-Installer.ps1` | 12 KB | Build automation |
| `Pre-Install-Check.ps1` | 13 KB | System validation |
| `Post-Install-Verify.ps1` | 13 KB | Installation check |
| `Uninstall-HELIOS.ps1` | 14 KB | Uninstaller tool |
| `INSTALLATION_GUIDE.md` | 13 KB | Installation docs |
| `TROUBLESHOOTING_GUIDE.md` | 14 KB | Issue solutions |
| `SYSTEM_REQUIREMENTS.md` | 12 KB | Tech specs |
| `LICENSE.txt` | 10 KB | License agreement |
| `README.md` | 13 KB | Project overview |

---

## 🔧 COMMON COMMANDS

### Pre-Installation

```powershell
# Check requirements
.\Pre-Install-Check.ps1

# Verbose output
.\Pre-Install-Check.ps1 -Verbose

# Skip confirmation prompt
.\Pre-Install-Check.ps1 -SkipPrompt
```

### Installation

```powershell
# GUI installation
HELIOS-Platform-Setup.exe

# Silent mode
HELIOS-Platform-Setup.exe /S

# Custom path
HELIOS-Platform-Setup.exe /D=D:\HELIOS

# With logging
HELIOS-Platform-Setup.exe /LOG=install.log

# Extract only
HELIOS-Platform-Setup.exe /EXTRACTTO=C:\Extract
```

### Post-Installation

```powershell
# Verify installation
.\Post-Install-Verify.ps1

# Verbose verification
.\Post-Install-Verify.ps1 -Verbose

# Auto-repair issues
.\Post-Install-Verify.ps1 -Repair

# Custom path
.\Post-Install-Verify.ps1 -InstallPath "D:\HELIOS"
```

### Uninstallation

```powershell
# Interactive uninstall
.\Uninstall-HELIOS.ps1

# Silent uninstall
.\Uninstall-HELIOS.ps1 -Force

# Keep configuration
.\Uninstall-HELIOS.ps1 -KeepConfig

# Custom path
.\Uninstall-HELIOS.ps1 -InstallPath "D:\HELIOS"
```

### Building

```powershell
# Build in current directory
.\Build-Installer.ps1

# Output to specific path
.\Build-Installer.ps1 -OutputPath "C:\Releases"

# With code signing
.\Build-Installer.ps1 -SignCertificate "cert.pfx" -CertPassword "password"

# Skip NSIS build
.\Build-Installer.ps1 -SkipNSIS
```

---

## 🔍 VERIFICATION STEPS

### After Installation

```powershell
# Check installation path
Test-Path "C:\Program Files\HELIOS Platform"

# Test application
"C:\Program Files\HELIOS Platform\HELIOS.Platform.exe" --version

# Check registry
Get-ItemProperty "HKCU:\Software\HELIOS Platform"

# Check shortcuts
Test-Path "$env:SMPROGRAMS\HELIOS Platform"
Test-Path "$env:DESKTOP\HELIOS Platform.lnk"

# Check PATH
$env:Path -split ";" | Where-Object { $_ -like "*HELIOS*" }
```

### After Uninstallation

```powershell
# Verify removal
Test-Path "C:\Program Files\HELIOS Platform"     # Should be False
Test-Path "HKCU:\Software\HELIOS Platform"       # Should be False
Test-Path "$env:SMPROGRAMS\HELIOS Platform"      # Should be False
```

---

## 🆘 TROUBLESHOOTING

| Issue | Solution |
|-------|----------|
| **"Access Denied"** | Right-click installer → Run as Administrator |
| **".NET SDK Not Found"** | Download from https://dotnet.microsoft.com/download |
| **"Admin Privileges Required"** | Open PowerShell as Administrator |
| **"Insufficient Disk Space"** | Free up 2+ GB of disk space |
| **"Can't Find HELIOS"** | Add to PATH: `$env:Path + ";C:\Program Files\HELIOS"` |
| **Installation Hangs** | Wait 5 minutes, then Ctrl+C and retry |
| **Post-Check Fails** | Run: `.\Post-Install-Verify.ps1 -Repair` |

---

## 📊 DEPLOYMENT TIERS

| Tier | Size | Features | Support |
|------|------|----------|---------|
| **Professional** | 500 MB | Core + Standard | Email (business hours) |
| **Enterprise** | 2 GB | Advanced + Analytics | Email (24/5) |
| **Ultimate** | 5 GB | All features + 24/7 | Phone + Email (24/7) |

---

## 🔒 SECURITY CHECKLIST

- ✓ Admin privileges enforced
- ✓ UAC integration active
- ✓ Registry verified
- ✓ File permissions secured
- ✓ Code signing supported
- ✓ Telemetry opt-in (disabled by default)
- ✓ Secure uninstall

---

## 📞 SUPPORT

| Channel | Contact |
|---------|---------|
| **Email** | support@helios.solutions |
| **Docs** | https://docs.helios.solutions |
| **Forum** | https://community.helios.solutions |
| **GitHub** | https://github.com/helios-solutions/platform |
| **Issues** | https://github.com/helios-solutions/platform/issues |

---

## 💡 PRO TIPS

### Silent Deployment to Multiple Computers

```powershell
$computers = @("PC001", "PC002", "PC003")
foreach ($pc in $computers) {
    Invoke-Command -ComputerName $pc -ScriptBlock {
        & "\\server\share\HELIOS-Platform-Setup.exe" /S /D="C:\Program Files\HELIOS"
    }
}
```

### Verify Installation Across Fleet

```powershell
$computers = @("PC001", "PC002")
foreach ($pc in $computers) {
    $result = Invoke-Command -ComputerName $pc -ScriptBlock {
        Test-Path "C:\Program Files\HELIOS Platform\HELIOS.Platform.exe"
    }
    Write-Host "$pc : $(if($result) {'✓ Installed'} else {'✗ Not Found'})"
}
```

### Automate with Task Scheduler

```powershell
# Create scheduled task for installation
$action = New-ScheduledTaskAction -Execute "C:\installer\HELIOS-Platform-Setup.exe" -Argument "/S"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "HELIOS Install"
```

### Create Installation Report

```powershell
# Generate installation summary
$report = @{
    Date = Get-Date
    Computer = $env:COMPUTERNAME
    User = $env:USERNAME
    Path = if(Test-Path "C:\Program Files\HELIOS Platform") {"✓ Installed"} else {"✗ Not Installed"}
    Shortcuts = if(Test-Path "$env:SMPROGRAMS\HELIOS Platform") {"✓ Created"} else {"✗ Missing"}
} | ConvertTo-Json
$report | Out-File "installation-report.json"
```

---

## 📖 DOCUMENTATION MAP

| Need | Document | Location |
|------|----------|----------|
| **Step-by-step Install** | INSTALLATION_GUIDE.md | installer/ |
| **Fix Problems** | TROUBLESHOOTING_GUIDE.md | installer/ |
| **System Specs** | SYSTEM_REQUIREMENTS.md | installer/ |
| **Legal Terms** | LICENSE.txt | installer/ |
| **Quick Overview** | README.md | installer/ |
| **All Features** | DELIVERABLES.md | installer/ |

---

## ✨ KEY FEATURES

- ✅ Professional GUI wizard
- ✅ Silent installation mode
- ✅ Automatic system checks
- ✅ Installation verification
- ✅ Auto-repair capability
- ✅ Registry management
- ✅ Shortcut creation
- ✅ PATH registration
- ✅ Clean uninstall
- ✅ Comprehensive docs
- ✅ 20+ troubleshooting solutions
- ✅ 3 deployment tiers
- ✅ Enterprise-ready
- ✅ Production-ready

---

## 📈 INSTALLATION TIME

| Method | Time | For |
|--------|------|-----|
| **GUI** | 5-10 min | Users, manual |
| **Silent** | 2-3 min | Automation |
| **Network** | 3-5 min | Enterprise |

---

## 🚀 QUICK COMMANDS

```powershell
# Everything in one go
.\Pre-Install-Check.ps1 -SkipPrompt && .\HELIOS-Platform-Setup.exe && .\Post-Install-Verify.ps1

# Silent deployment
.\HELIOS-Platform-Setup.exe /S /D="C:\Program Files\HELIOS"

# Repair installation
.\Post-Install-Verify.ps1 -Repair

# Complete uninstall
.\Uninstall-HELIOS.ps1 -Force

# Build new installer
.\Build-Installer.ps1 -OutputPath ".\release"
```

---

## ✅ PRODUCTION READY

- ✅ Tested and verified
- ✅ Fully documented
- ✅ Enterprise-grade
- ✅ Security validated
- ✅ Ready for distribution
- ✅ Support included
- ✅ Troubleshooting guides
- ✅ Deployment ready

---

**Last Updated:** 2024  
**Version:** 1.0.0.0  
**Status:** ✅ PRODUCTION READY

---

**Need Help?** See full documentation in installer/ directory or visit https://docs.helios.solutions
