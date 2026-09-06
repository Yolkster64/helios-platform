# HELIOS Platform Professional Windows Installer

**Version:** 1.0.0.0  
**Status:** Production Ready  
**Release Date:** 2024  
**Platform:** Windows 11 Pro/Enterprise  
**Type:** Enterprise-grade Installation Package

---

## 📦 Package Contents

```
installer/
├── setup.nsi                          # NSIS installer script (source)
├── Build-Installer.ps1                # Build automation script
├── Pre-Install-Check.ps1              # System requirements validator
├── Post-Install-Verify.ps1            # Installation verification tool
├── Uninstall-HELIOS.ps1               # Standalone uninstaller
├── INSTALLATION_GUIDE.md              # Step-by-step installation guide
├── TROUBLESHOOTING_GUIDE.md           # Common issues and solutions
├── SYSTEM_REQUIREMENTS.md             # Detailed system requirements
├── LICENSE.txt                        # Software license agreement
├── README.md                          # This file
├── BUILD_MANIFEST.json                # Build metadata (generated)
└── HELIOS-Platform-Setup.exe          # Final installer executable (built)
```

---

## 🚀 Quick Start

### For End Users

```powershell
# 1. Check system requirements
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Pre-Install-Check.ps1

# 2. Run installer
.\HELIOS-Platform-Setup.exe

# 3. Verify installation
.\Post-Install-Verify.ps1
```

### For IT Administrators

```powershell
# Silent installation
.\HELIOS-Platform-Setup.exe /S /D=C:\Program Files\HELIOS

# With custom options
.\HELIOS-Platform-Setup.exe /S /AUTOSTART=1 /TELEMETRY=0

# Uninstall
.\HELIOS-Platform-Setup.exe /UNINSTALL /S
```

### For Developers

```powershell
# Build installer from source
.\Build-Installer.ps1 -OutputPath ".\build"

# Build with code signing
.\Build-Installer.ps1 -SignCertificate "cert.pfx" -CertPassword "password"
```

---

## 📋 System Requirements

### Minimum

- **Windows:** 11 Pro or Enterprise
- **.NET:** 8.0 SDK or later
- **PowerShell:** 7.0 or later
- **RAM:** 4 GB
- **Disk:** 2 GB free space
- **Admin:** Required

### Recommended

- **Windows:** 11 Pro, Build 22621+
- **.NET:** 8.0 LTS or 9.0
- **PowerShell:** 7.4 or later
- **RAM:** 8 GB or more
- **Disk:** 20 GB SSD
- **Processor:** Multi-core, 3 GHz+

**Full Details:** See [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md)

---

## 🔧 Installation Methods

### Method 1: GUI Installation (Recommended)

Easiest for end users - provides wizard-based installation interface.

```
1. Double-click HELIOS-Platform-Setup.exe
2. Follow on-screen prompts
3. Select components and options
4. Click "Install"
5. Wait for completion
```

**Time:** ~5-10 minutes

### Method 2: Silent Installation (Automation)

For automated enterprise deployments without user interaction.

```powershell
.\HELIOS-Platform-Setup.exe /S /D="C:\Program Files\HELIOS"
```

**Options:**

- `/S` - Silent mode (no UI)
- `/D=path` - Installation directory
- `/AUTOSTART=1` - Enable auto-start
- `/TELEMETRY=0` - Disable telemetry
- `/LANGUAGE=English` - Set language

**Time:** ~2-3 minutes

### Method 3: Command Line (Scripted)

For integration with deployment automation systems.

```powershell
$installer = "HELIOS-Platform-Setup.exe"
$args = @(
    "/S",
    "/D=C:\Program Files\HELIOS",
    "/AUTOSTART=1",
    "/LOG=install.log"
)
Start-Process -FilePath $installer -ArgumentList $args -Wait
```

### Method 4: Network/GPO Deployment

For enterprise Active Directory environments:

```powershell
# Copy to network share
Copy-Item "HELIOS-Platform-Setup.exe" "\\server\software\"

# Deploy via Group Policy
# Create GPO with logon script containing silent install command
```

---

## ✅ Pre-Installation Checklist

Run the automatic pre-installation checker:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Pre-Install-Check.ps1
```

**Manual checklist:**

- [ ] Windows 11 Pro or Enterprise
- [ ] Administrator privileges available
- [ ] .NET 8 SDK installed (`dotnet --version`)
- [ ] PowerShell 7+ installed (`pwsh --version`)
- [ ] At least 2 GB free disk space
- [ ] 4 GB RAM minimum available
- [ ] Internet connectivity (for initial setup)
- [ ] No antivirus blocking installation
- [ ] UAC (User Account Control) enabled
- [ ] System fully patched and updated

---

## 📥 Installation Process

### Step 1: Pre-Installation Checks

- System requirements validated
- Administrator privileges verified
- .NET SDK availability confirmed
- Disk space confirmed
- Registry access verified

### Step 2: File Extraction

- Application files copied
- Configuration directories created
- Support files placed
- Default configuration initialized

### Step 3: System Integration

- Registry entries created
- Start Menu shortcuts added
- Desktop shortcuts created
- PATH environment variable updated
- Auto-start configured (if selected)

### Step 4: Initialization

- Platform components loaded
- Configuration validated
- System baseline established
- Installation logged

### Step 5: Completion

- Summary displayed
- Registry entries confirmed
- Shortcuts verified
- Help available

---

## ✔️ Post-Installation Verification

Automatically verify installation success:

```powershell
.\Post-Install-Verify.ps1
```

**Verification checks:**

- Installation path exists
- Required files present
- Registry entries created
- System PATH updated
- Shortcuts functional
- Application startup

**If issues found:**

```powershell
# Automatic repair
.\Post-Install-Verify.ps1 -Repair
```

**Manual verification:**

```powershell
# Check installation path
Test-Path "C:\Program Files\HELIOS Platform"

# Run application
"C:\Program Files\HELIOS Platform\HELIOS.Platform.exe" --version

# Check shortcuts
Test-Path "$env:SMPROGRAMS\HELIOS Platform"
Test-Path "$env:DESKTOP\HELIOS Platform.lnk"
```

---

## 🔄 Silent Installation Example

### Basic Automation Script

```powershell
# deploy-helios.ps1
param([string]$ComputerName = "localhost")

# Configuration
$installer = "HELIOS-Platform-Setup.exe"
$installPath = "C:\Program Files\HELIOS"
$logFile = "helios-install.log"

# Run pre-check
Write-Host "Checking system requirements..."
if (-not (.\Pre-Install-Check.ps1)) {
    throw "System requirements not met"
}

# Silent installation
Write-Host "Installing HELIOS Platform..."
$process = Start-Process -FilePath $installer `
    -ArgumentList "/S", "/D=$installPath", "/LOG=$logFile" `
    -NoNewWindow -PassThru -Wait

if ($process.ExitCode -ne 0) {
    throw "Installation failed with code $($process.ExitCode)"
}

# Post-installation verification
Write-Host "Verifying installation..."
if (-not (.\Post-Install-Verify.ps1)) {
    Write-Warning "Verification found issues, attempting repair..."
    .\Post-Install-Verify.ps1 -Repair
}

Write-Host "✓ Installation completed successfully"
```

### Batch Deployment Script

```powershell
# deploy-to-computers.ps1
$computers = @("PC001", "PC002", "PC003")
$installerPath = "\\server\software\HELIOS-Platform-Setup.exe"

foreach ($computer in $computers) {
    Write-Host "Installing on $computer..."
    
    Invoke-Command -ComputerName $computer -ScriptBlock {
        & $installerPath /S /D="C:\Program Files\HELIOS"
    }
    
    Write-Host "  ✓ Installation started on $computer"
}
```

---

## 🛠️ Building the Installer

### Requirements

1. **NSIS (3.0+)**
   - Download: https://nsis.sourceforge.io/Download
   - Install location: `C:\Program Files (x86)\NSIS`

2. **NSIS Plugins**
   - Modern UI plugin (included with NSIS)
   - LogicLib plugin (included with NSIS)

3. **PowerShell 5+**
   - Already on Windows 11

### Building

```powershell
# Build installer in current directory
.\Build-Installer.ps1

# Build to specific output path
.\Build-Installer.ps1 -OutputPath "C:\Releases"

# Build with code signing
.\Build-Installer.ps1 -SignCertificate "mycert.pfx" -CertPassword "password"
```

### Output

```
Output Directory/
├── HELIOS-Platform-Setup.exe      # Main installer executable
├── BUILD_MANIFEST.json            # Build metadata and hashes
└── HELIOS-Platform-Release/       # Release package
    ├── HELIOS-Platform-Setup.exe
    ├── Pre-Install-Check.ps1
    ├── Post-Install-Verify.ps1
    ├── INSTALLATION_GUIDE.md
    ├── TROUBLESHOOTING_GUIDE.md
    └── README.txt
```

---

## 🗑️ Uninstallation

### Method 1: Settings App (Windows 11)

1. Open Settings
2. System → Apps → Installed apps
3. Search "HELIOS"
4. Click "Uninstall"
5. Confirm

### Method 2: Control Panel

1. Control Panel → Programs → Programs and Features
2. Find "HELIOS Platform"
3. Right-click → Uninstall
4. Confirm

### Method 3: Command Line

```powershell
# Silent uninstall
"C:\Program Files\HELIOS Platform\Uninstall.exe" /S

# With PowerShell script
.\Uninstall-HELIOS.ps1

# Force uninstall without prompts
.\Uninstall-HELIOS.ps1 -Force

# Keep configuration during uninstall
.\Uninstall-HELIOS.ps1 -KeepConfig
```

### Verify Uninstallation

```powershell
# Check path removed
Test-Path "C:\Program Files\HELIOS Platform"

# Check registry cleaned
Test-Path "HKCU:\Software\HELIOS Platform"

# Check shortcuts removed
Test-Path "$env:SMPROGRAMS\HELIOS Platform"
```

---

## 📖 Documentation

| Document | Purpose |
|----------|---------|
| [INSTALLATION_GUIDE.md](INSTALLATION_GUIDE.md) | Complete step-by-step installation instructions |
| [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md) | Solutions for common installation/configuration issues |
| [SYSTEM_REQUIREMENTS.md](SYSTEM_REQUIREMENTS.md) | Detailed system requirement specifications |
| [LICENSE.txt](LICENSE.txt) | Software license agreement and terms |

---

## 🔍 Troubleshooting

### "Access Denied" During Installation

```powershell
# Run as Administrator
# Right-click installer → Run as Administrator
```

### Pre-Check Fails

```powershell
# Run detailed check
.\Pre-Install-Check.ps1 -Verbose
```

### Installation Hangs

```powershell
# Check installation progress
Get-Process NSIS* -ErrorAction SilentlyContinue

# View install log
Get-Content "install.log" -Tail 50
```

### Post-Install Verification Fails

```powershell
# Attempt automatic repair
.\Post-Install-Verify.ps1 -Repair

# Manual registry restore
.\Post-Install-Verify.ps1 -Verbose
```

**Full Troubleshooting Guide:** See [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md)

---

## 🔐 Security

### Code Signing

The installer can be digitally signed for enterprise security:

```powershell
.\Build-Installer.ps1 `
    -SignCertificate "mycert.pfx" `
    -CertPassword "mypassword"
```

### File Verification

Check installer integrity:

```powershell
$hash = (Get-FileHash "HELIOS-Platform-Setup.exe" -Algorithm SHA256).Hash
Write-Host "SHA256: $hash"

# Compare with published hash from release notes
```

### Data Protection

- Configuration files with sensitive data encrypted
- Logs kept in secure location
- Uninstaller removes all data
- Keep-config option preserves data for recovery

---

## 📊 Installation Logging

Logs are created in the installation directory:

```
C:\Program Files\HELIOS Platform\logs\
├── install.log           # Installation log
├── error.log             # Error log
└── app.log               # Application log
```

**View logs:**

```powershell
# Recent installation log
Get-Content "$env:ProgramFiles\HELIOS Platform\logs\install.log" -Tail 100

# Errors only
Select-String -Path "$env:ProgramFiles\HELIOS Platform\logs\*.log" -Pattern "error"
```

---

## 🎯 Deployment Tiers

### Professional Tier

- Standard enterprise deployment
- Email support (business hours)
- Security updates only
- $0 (included)

### Enterprise Tier

- Advanced features enabled
- Email support (24/5)
- All updates included
- Priority response

### Ultimate Tier

- Complete feature set
- 24/7 phone support
- Premium features
- Custom integrations

---

## 📞 Support

- **Documentation:** https://docs.helios.solutions
- **Community:** https://community.helios.solutions
- **Email:** support@helios.solutions
- **GitHub:** https://github.com/helios-solutions/platform
- **Issues:** https://github.com/helios-solutions/platform/issues

---

## 📝 License

HELIOS Platform is provided under the terms specified in [LICENSE.txt](LICENSE.txt).
Installation constitutes acceptance of the license agreement.

---

## 🔄 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0.0 | 2024 | Initial production release |

---

## 🏆 Production Readiness Checklist

- ✅ NSIS installer script (setup.nsi)
- ✅ Pre-installation checker script
- ✅ Post-installation verifier script
- ✅ Build automation script
- ✅ Standalone uninstaller
- ✅ Complete documentation
- ✅ Troubleshooting guide
- ✅ System requirements document
- ✅ License agreement
- ✅ Error handling and recovery
- ✅ Silent installation support
- ✅ Registry management
- ✅ Shortcut creation
- ✅ PATH registration
- ✅ Uninstall support

---

**Package Version:** 1.0.0.0  
**Last Updated:** 2024  
**Status:** ✅ Production Ready
