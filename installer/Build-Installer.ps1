#!/usr/bin/env pwsh
<#
.SYNOPSIS
    HELIOS Platform Installer Build Script
    
.DESCRIPTION
    Builds the NSIS installer executable and creates distribution package.
    Requires NSIS to be installed on the system.
    
.EXAMPLE
    .\Build-Installer.ps1
    .\Build-Installer.ps1 -OutputPath "C:\Releases"
    .\Build-Installer.ps1 -SignCertificate "cert.pfx" -CertPassword "password"
    
.PARAMETER OutputPath
    Directory where the installer will be created (default: current directory)
    
.PARAMETER SignCertificate
    Path to code signing certificate (.pfx file)
    
.PARAMETER CertPassword
    Password for the code signing certificate
    
.PARAMETER SkipNSIS
    Skip NSIS compilation step
    
.AUTHOR
    HELIOS Solutions
    
.VERSION
    1.0.0.0
#>

param(
    [string]$OutputPath = ".",
    [string]$SignCertificate = "",
    [string]$CertPassword = "",
    [switch]$SkipNSIS
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$BuildConfig = @{
    NSISVersion      = "3.08"
    InstallerName    = "HELIOS-Platform-Setup.exe"
    Version          = "1.0.0.0"
    Company          = "HELIOS Solutions"
    ProductName      = "HELIOS Platform"
    NSISScript       = "setup.nsi"
    SourceDir        = ".."  # Parent of installer directory
}

# ============================================================================
; UTILITY FUNCTIONS
# ============================================================================

function Write-BuildLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Test-NSISInstalled {
    Write-BuildLog "Checking for NSIS installation..." "INFO"
    
    $nsisExePath = "C:\Program Files (x86)\NSIS\makensis.exe"
    $nsisExePath64 = "C:\Program Files\NSIS\makensis.exe"
    
    if (Test-Path $nsisExePath) {
        Write-BuildLog "NSIS found at: $nsisExePath" "SUCCESS"
        return $nsisExePath
    }
    elseif (Test-Path $nsisExePath64) {
        Write-BuildLog "NSIS found at: $nsisExePath64" "SUCCESS"
        return $nsisExePath64
    }
    else {
        Write-BuildLog "NSIS not found. Please install NSIS from: https://nsis.sourceforge.io/Download" "ERROR"
        Write-BuildLog "Attempted paths:" "WARNING"
        Write-BuildLog "  - $nsisExePath" "WARNING"
        Write-BuildLog "  - $nsisExePath64" "WARNING"
        throw "NSIS installation not found"
    }
}

function Test-BuildPrerequisites {
    Write-BuildLog "`nVerifying build prerequisites..." "INFO"
    
    # Check script location
    if (-not (Test-Path $BuildConfig.NSISScript)) {
        throw "NSIS script not found: $($BuildConfig.NSISScript)"
    }
    Write-BuildLog "✓ NSIS script found" "SUCCESS"
    
    # Check output path
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    Write-BuildLog "✓ Output directory ready: $OutputPath" "SUCCESS"
}

function Get-BuildInfo {
    Write-BuildLog "`nBuild Information:" "INFO"
    Write-BuildLog "  Product: $($BuildConfig.ProductName)" "INFO"
    Write-BuildLog "  Version: $($BuildConfig.Version)" "INFO"
    Write-BuildLog "  Company: $($BuildConfig.Company)" "INFO"
    Write-BuildLog "  Output: $OutputPath\$($BuildConfig.InstallerName)" "INFO"
}

function Invoke-NSISCompilation {
    param(
        [string]$NSISPath
    )
    
    Write-BuildLog "`nStarting NSIS compilation..." "INFO"
    
    $outputFile = Join-Path $OutputPath $BuildConfig.InstallerName
    
    # Build NSIS command
    $nsisArgs = @(
        "/V4"  # Verbosity level
        "/O`"$outputFile`""  # Output file
        "`"$($BuildConfig.NSISScript)`""  # Script file
    )
    
    Write-BuildLog "Executing: $NSISPath $($nsisArgs -join ' ')" "INFO"
    
    # Execute NSIS
    $process = Start-Process -FilePath $NSISPath -ArgumentList $nsisArgs -NoNewWindow -PassThru -ErrorAction Stop
    $process.WaitForExit()
    
    if ($process.ExitCode -eq 0) {
        Write-BuildLog "NSIS compilation completed successfully" "SUCCESS"
        return $true
    }
    else {
        Write-BuildLog "NSIS compilation failed with exit code: $($process.ExitCode)" "ERROR"
        throw "NSIS compilation failed"
    }
}

function Invoke-CodeSigning {
    param(
        [string]$ExecutablePath
    )
    
    if ([string]::IsNullOrEmpty($SignCertificate)) {
        Write-BuildLog "Skipping code signing (no certificate provided)" "WARNING"
        return
    }
    
    if (-not (Test-Path $SignCertificate)) {
        Write-BuildLog "Certificate file not found: $SignCertificate" "ERROR"
        return
    }
    
    Write-BuildLog "`nSigning executable..." "INFO"
    
    try {
        # Import certificate
        $cert = Get-PfxCertificate -FilePath $SignCertificate -ErrorAction Stop
        
        # Sign file
        Set-AuthenticodeSignature -FilePath $ExecutablePath -Certificate $cert -ErrorAction Stop
        
        Write-BuildLog "✓ Executable signed successfully" "SUCCESS"
    }
    catch {
        Write-BuildLog "Code signing failed: $_" "WARNING"
    }
}

function Test-InstallerIntegrity {
    param(
        [string]$InstallerPath
    )
    
    Write-BuildLog "`nVerifying installer integrity..." "INFO"
    
    if (-not (Test-Path $InstallerPath)) {
        throw "Installer file not found: $InstallerPath"
    }
    
    $fileInfo = Get-Item $InstallerPath
    $fileSize = [math]::Round($fileInfo.Length / 1MB, 2)
    
    Write-BuildLog "✓ Installer file: $InstallerPath" "SUCCESS"
    Write-BuildLog "✓ File size: $fileSize MB" "SUCCESS"
    
    # Calculate checksum
    $sha256 = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash
    Write-BuildLog "✓ SHA256: $sha256" "SUCCESS"
    
    return $true
}

function Create-BuildManifest {
    param(
        [string]$InstallerPath
    )
    
    $manifestPath = Join-Path $OutputPath "BUILD_MANIFEST.json"
    
    $manifest = @{
        BuildDate       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ProductName     = $BuildConfig.ProductName
        Version         = $BuildConfig.Version
        Company         = $BuildConfig.Company
        InstallerFile   = [System.IO.Path]::GetFileName($InstallerPath)
        InstallerPath   = $InstallerPath
        FileSize        = (Get-Item $InstallerPath).Length
        SHA256          = (Get-FileHash -Path $InstallerPath -Algorithm SHA256).Hash
        BuildEnvironment = @{
            OS              = [System.Environment]::OSVersion.VersionString
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            UserName        = [System.Environment]::UserName
        }
    } | ConvertTo-Json -Depth 5
    
    $manifest | Set-Content $manifestPath -Encoding UTF8
    Write-BuildLog "Build manifest created: $manifestPath" "SUCCESS"
}

function Create-ReleasePackage {
    param(
        [string]$InstallerPath
    )
    
    Write-BuildLog "`nPreparing release package..." "INFO"
    
    $packageDir = Join-Path $OutputPath "HELIOS-Platform-Release"
    
    if (Test-Path $packageDir) {
        Remove-Item $packageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    
    # Copy installer
    Copy-Item $InstallerPath $packageDir
    
    # Copy documentation
    $docsToInclude = @(
        "Pre-Install-Check.ps1"
        "Post-Install-Verify.ps1"
        "INSTALLATION_GUIDE.md"
        "TROUBLESHOOTING_GUIDE.md"
    )
    
    foreach ($doc in $docsToInclude) {
        if (Test-Path $doc) {
            Copy-Item $doc $packageDir
        }
    }
    
    # Create README
    $readmeContent = @"
# HELIOS Platform Installation Package

## Contents
- HELIOS-Platform-Setup.exe - Main installer
- Pre-Install-Check.ps1 - System requirements checker
- Post-Install-Verify.ps1 - Installation verification
- INSTALLATION_GUIDE.md - Detailed installation guide
- TROUBLESHOOTING_GUIDE.md - Common issues and solutions

## Quick Start

### 1. Pre-Installation Check
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Pre-Install-Check.ps1
```

### 2. Install HELIOS Platform
Run the installer:
```
HELIOS-Platform-Setup.exe
```

### 3. Post-Installation Verification
```powershell
.\Post-Install-Verify.ps1
```

## System Requirements
- Windows 11 Pro or Enterprise
- .NET 8 SDK
- PowerShell 7.0+
- Administrator privileges
- 2 GB free disk space

## Support
For issues and support, visit: https://docs.helios.solutions

---
Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
    
    $readmeContent | Set-Content "$packageDir\README.txt" -Encoding UTF8
    
    Write-BuildLog "✓ Release package created: $packageDir" "SUCCESS"
    
    return $packageDir
}

# ============================================================================
; MAIN BUILD PROCESS
# ============================================================================

function Invoke-BuildProcess {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           HELIOS PLATFORM INSTALLER BUILD SCRIPT                  ║" -ForegroundColor Cyan
    Write-Host "║                    Version 1.0.0.0                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    try {
        # Verify prerequisites
        Get-BuildInfo
        Test-BuildPrerequisites
        
        # Check for NSIS
        if (-not $SkipNSIS) {
            $nsisPath = Test-NSISInstalled
        }
        
        # Compile installer
        if (-not $SkipNSIS) {
            Invoke-NSISCompilation -NSISPath $nsisPath
        }
        
        # Sign executable
        $installerPath = Join-Path $OutputPath $BuildConfig.InstallerName
        if (Test-Path $installerPath) {
            Invoke-CodeSigning -ExecutablePath $installerPath
        }
        
        # Verify integrity
        Test-InstallerIntegrity -InstallerPath $installerPath
        
        # Create manifest
        Create-BuildManifest -InstallerPath $installerPath
        
        # Package for release
        $packagePath = Create-ReleasePackage -InstallerPath $installerPath
        
        # Build complete
        Write-BuildLog "`n✓ BUILD COMPLETED SUCCESSFULLY" "SUCCESS"
        Write-BuildLog "Output: $OutputPath" "SUCCESS"
        Write-BuildLog "Release Package: $packagePath" "SUCCESS"
        
        return 0
    }
    catch {
        Write-BuildLog "✗ BUILD FAILED: $_" "ERROR"
        Write-BuildLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        return 1
    }
}

# Execute
exit (Invoke-BuildProcess)
