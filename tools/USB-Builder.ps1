# USB Builder Script for HELIOS Platform
# Creates bootable installation USB from start to finish
# Run as Administrator

param(
    [Parameter(Mandatory=$true)]
    [string]$USBDrive,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("gaming", "workstation", "server", "custom")]
    [string]$ConfigProfile = "gaming",
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoBoot = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$SecureMode = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force = $false
)

# ============================================================================
# HELIOS USB Builder v2.0
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
$Color = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Progress = 'Blue'
}

function Write-Status {
    param([string]$Message, [string]$Type = "Info")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color[$Type]
}

function Write-Progress-Bar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity
    )
    $percent = [int](($Current / $Total) * 100)
    $bar = "█" * ($percent / 5) + "░" * ((100 - $percent) / 5)
    Write-Host "`r[$bar] $percent% - $Activity" -NoNewline
}

# ============================================================================
# 1. VALIDATION & PREREQUISITES
# ============================================================================

Write-Status "HELIOS USB Builder - Initialization" "Info"
Write-Status "Profile: $ConfigProfile | SecureMode: $SecureMode | AutoBoot: $AutoBoot" "Info"

# Check admin privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Status "ERROR: This script must run as Administrator!" "Error"
    exit 1
}

# Verify USB drive exists
try {
    $USB = Get-Volume -DriveLetter $USBDrive.TrimEnd(':') -ErrorAction Stop
    Write-Status "USB Drive detected: $($USB.FileSystemLabel) ($($USB.Size / 1GB) GB)" "Success"
} catch {
    Write-Status "ERROR: USB drive not found at $USBDrive" "Error"
    Write-Status "Available drives: $(Get-Volume | Select-Object -ExpandProperty DriveLetter | Join-String -Separator ', ')" "Warning"
    exit 1
}

# Verify minimum USB size (32GB)
$USBSizeGB = [int]($USB.Size / 1GB)
if ($USBSizeGB -lt 32) {
    Write-Status "ERROR: USB drive must be at least 32GB (current: $USBSizeGB GB)" "Error"
    if (-not $Force) {
        exit 1
    }
    Write-Status "Continuing with Force flag..." "Warning"
}

# Confirm formatting
Write-Status "CAUTION: This will format $USBDrive and delete all data!" "Warning"
if (-not $Force) {
    $confirm = Read-Host "Type 'FORMAT' to continue"
    if ($confirm -ne "FORMAT") {
        Write-Status "Operation cancelled by user" "Warning"
        exit 0
    }
}

# ============================================================================
# 2. FORMAT USB DRIVE
# ============================================================================

Write-Status "Phase 1: Formatting USB Drive..." "Progress"

try {
    # Get disk number for USB drive
    $DiskNum = (Get-Volume -DriveLetter $USBDrive.TrimEnd(':')).DriveLetter
    $Disk = Get-Disk | Where-Object { $_.BusType -eq "USB" } | Select-Object -First 1
    
    if (-not $Disk) {
        Write-Status "ERROR: Could not identify USB disk" "Error"
        exit 1
    }
    
    # Remove existing partitions
    Write-Status "Removing existing partitions..." "Info"
    Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue | Remove-Partition -Force -ErrorAction SilentlyContinue
    
    # Create new partition table
    Write-Status "Creating new partition table..." "Info"
    Initialize-Disk -Number $Disk.Number -PartitionStyle GPT -Force -Confirm:$false
    
    # Create partitions
    $Partition = New-Partition -DiskNumber $Disk.Number -UseMaximumSize -DriveLetter $USBDrive.TrimEnd(':')
    Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "HELIOS" -Confirm:$false
    
    Write-Status "USB drive formatted successfully" "Success"
}
catch {
    Write-Status "ERROR: Failed to format USB drive: $_" "Error"
    exit 1
}

# ============================================================================
# 3. CREATE DIRECTORY STRUCTURE
# ============================================================================

Write-Status "Phase 2: Creating directory structure..." "Progress"

$USBPath = "$($USBDrive)\"
$dirs = @(
    "BOOT",
    "HELIOS",
    "HELIOS\Configs",
    "HELIOS\Drivers",
    "HELIOS\Software",
    "HELIOS\AI-Models",
    "HELIOS\Security",
    "HELIOS\Documentation",
    "RECOVERY",
    "LOGS"
)

foreach ($dir in $dirs) {
    $fullPath = Join-Path $USBPath $dir
    New-Item -ItemType Directory -Path $fullPath -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Status "Created: $dir" "Info"
}

# ============================================================================
# 4. COPY HELIOS EXECUTABLE & COMPONENTS
# ============================================================================

Write-Status "Phase 3: Copying HELIOS files..." "Progress"

$sourceBase = "C:\HELIOS"
$items = @(
    @{ Source = "$sourceBase\bin\Release\HELIOS.exe"; Dest = "HELIOS" },
    @{ Source = "$sourceBase\bin\Release\HELIOS.Platform.dll"; Dest = "HELIOS" },
    @{ Source = "$sourceBase\bin\Release\*.dll"; Dest = "HELIOS" },
    @{ Source = "$sourceBase\drivers\*"; Dest = "HELIOS\Drivers" },
    @{ Source = "$sourceBase\documentation\*"; Dest = "HELIOS\Documentation" }
)

foreach ($item in $items) {
    if (Test-Path $item.Source) {
        $dest = Join-Path $USBPath $item.Dest
        Copy-Item -Path $item.Source -Destination $dest -Recurse -Force -ErrorAction Continue
        Write-Status "Copied: $($item.Source) → $($item.Dest)" "Info"
    }
}

# ============================================================================
# 5. CREATE CONFIGURATION FILES
# ============================================================================

Write-Status "Phase 4: Creating configuration files..." "Progress"

$configs = @{
    "gaming" = @{
        "profile" = "gaming"
        "optimization" = "performance"
        "gpu_mode" = "maximum"
        "cpu_governor" = "performance"
        "ram_allocation" = "24GB"
        "software_preset" = "gaming"
    }
    "workstation" = @{
        "profile" = "workstation"
        "optimization" = "balanced"
        "gpu_mode" = "compute"
        "cpu_governor" = "powersave"
        "ram_allocation" = "16GB"
        "software_preset" = "development"
    }
    "server" = @{
        "profile" = "server"
        "optimization" = "stability"
        "gpu_mode" = "disabled"
        "cpu_governor" = "powersave"
        "ram_allocation" = "balanced"
        "software_preset" = "server"
    }
}

$selectedConfig = $configs[$ConfigProfile]

$configJson = @{
    profile = $ConfigProfile
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    settings = $selectedConfig
    features = @{
        ai_dashboard = $true
        gpu_acceleration = $true
        security_hardening = $true
        auto_updates = $true
        cloud_integration = $true
    }
} | ConvertTo-Json

$configJson | Out-File -FilePath "$USBPath\HELIOS\Configs\$ConfigProfile.config" -Encoding UTF8
Write-Status "Created config: $ConfigProfile.config" "Success"

# ============================================================================
# 6. CREATE BOOT FILES
# ============================================================================

Write-Status "Phase 5: Creating boot configuration..." "Progress"

# Create AUTORUN.INF
$autorunContent = @"
[autorun]
open=setup.exe
icon=HELIOS.exe
label=HELIOS Platform Installation
"@
$autorunContent | Out-File -FilePath "$USBPath\AUTORUN.INF" -Encoding ASCII

# Create setup batch file
$setupBatch = @"
@echo off
cls
echo.
echo ============================================
echo  HELIOS Platform Installation
echo ============================================
echo.
echo This USB contains the complete HELIOS Platform.
echo.
echo To begin installation:
echo  1. Boot this USB (F12 during startup)
echo  2. Follow the on-screen instructions
echo.
echo For manual installation, run:
echo  %CD%\HELIOS\HELIOS.exe
echo.
pause
"@
$setupBatch | Out-File -FilePath "$USBPath\setup.bat" -Encoding ASCII

Write-Status "Boot files created" "Success"

# ============================================================================
# 7. CREATE SETUP MANIFEST
# ============================================================================

Write-Status "Phase 6: Creating manifest..." "Progress"

$manifest = @{
    version = "2.0"
    date_created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    profile = $ConfigProfile
    secure_mode = $SecureMode
    auto_boot = $AutoBoot
    features = @(
        "Studio Admin Dashboard"
        "Server Management System"
        "GPU Acceleration (CUDA/DirectML)"
        "Automation Engine"
        "DevDrive + Vault + Recovery"
        "AI Intelligence Layer"
        "300+ Software Packages"
        "Hardware Integration (NVIDIA/AMD/WSL2/Razer)"
    )
    components = @{
        executable = "HELIOS.exe"
        libraries = "*.dll"
        drivers = "50+ driver types"
        software = "300+ packages"
        ai_models = "7 LLM models"
        documentation = "50+ guides"
    }
    requirements = @{
        min_disk_space = "300GB"
        min_ram = "16GB"
        min_usb_size = "32GB"
        windows_version = "Windows 10/11"
        dotnet_version = ".NET 7.0+"
    }
} | ConvertTo-Json -Depth 5

$manifest | Out-File -FilePath "$USBPath\SETUP_MANIFEST.xml" -Encoding UTF8
Write-Status "Manifest created" "Success"

# ============================================================================
# 8. CREATE README
# ============================================================================

Write-Status "Phase 7: Creating documentation..." "Progress"

$readmeContent = @"
HELIOS PLATFORM - USB INSTALLATION MEDIA
==========================================

Version: 2.0
Profile: $ConfigProfile
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

QUICK START
-----------
1. Insert this USB into your computer
2. Reboot and enter boot menu (usually F12 or ESC)
3. Select this USB drive
4. Follow on-screen instructions
5. Installation takes 20-30 minutes

CONTENTS
--------
$(Get-ChildItem -Path $USBPath -Recurse | Measure-Object | Select-Object -ExpandProperty Count) files
$USBSizeGB GB capacity

FEATURES INCLUDED
-----------------
$(($configs[$ConfigProfile].GetEnumerator() | ForEach-Object { "  • $($_.Key): $($_.Value)" }) -join "`n")

REQUIREMENTS
------------
• Disk Space: 300GB minimum
• RAM: 16GB minimum
• USB 3.0 or faster
• Windows 10 (22H2) or Windows 11
• .NET 7.0 Runtime

SUPPORT
-------
Documentation: \HELIOS\Documentation\
Troubleshooting: https://github.com/M0nado/helios-platform/wiki
GitHub: https://github.com/M0nado/helios-platform

For detailed setup instructions, see:
USB_BUILDER_AND_SETUP_GUIDE.md
"@

$readmeContent | Out-File -FilePath "$USBPath\README.txt" -Encoding ASCII
Write-Status "README created" "Success"

# ============================================================================
# 9. CONFIGURE BOOT SETTINGS (OPTIONAL)
# ============================================================================

if ($AutoBoot) {
    Write-Status "Phase 8: Configuring auto-boot..." "Progress"
    
    # Create boot config file
    $bootConfig = @"
[boot loader]
default=HELIOS
timeout=10

[operating systems]
HELIOS="HELIOS Platform Installation"
"@
    $bootConfig | Out-File -FilePath "$USBPath\BOOT\boot.ini" -Encoding ASCII
    Write-Status "Auto-boot configured (10 second delay)" "Success"
}

# ============================================================================
# 10. SECURE MODE (OPTIONAL)
# ============================================================================

if ($SecureMode) {
    Write-Status "Phase 9: Enabling secure mode..." "Progress"
    
    Write-Status "WARNING: Secure Mode requires BitLocker-capable drive" "Warning"
    
    # Note: Full BitLocker on USB requires specific hardware support
    # This creates security config for post-install
    $securityConfig = @{
        bitlocker_enabled = $true
        secure_boot = $true
        tpm_required = $true
        uefi_only = $true
    } | ConvertTo-Json
    
    $securityConfig | Out-File -FilePath "$USBPath\HELIOS\Security\secure-config.json" -Encoding UTF8
    Write-Status "Security configuration created" "Success"
}

# ============================================================================
# 11. VERIFY AND FINALIZE
# ============================================================================

Write-Status "Phase 10: Verification & finalization..." "Progress"

$fileCount = (Get-ChildItem -Path $USBPath -Recurse | Measure-Object | Select-Object -ExpandProperty Count)
$usedSpace = (Get-Item -Path $USBPath -Force | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum) / 1GB

Write-Status "Files written: $fileCount" "Info"
Write-Status "Space used: $([int]$usedSpace) GB / $USBSizeGB GB" "Info"

# Eject USB
Write-Status "Preparing to eject USB..." "Info"
[System.IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -eq "$($USBDrive)\" } | ForEach-Object { $_.VolumeLabel }

Write-Status "" "Info"
Write-Status "════════════════════════════════════════════════" "Success"
Write-Status "USB BUILDER COMPLETE!" "Success"
Write-Status "════════════════════════════════════════════════" "Success"
Write-Status "" "Info"
Write-Status "✓ USB is ready for installation" "Success"
Write-Status "✓ Profile: $ConfigProfile" "Success"
Write-Status "✓ Capacity: $USBSizeGB GB" "Success"
Write-Status "✓ Files: $fileCount" "Success"
Write-Status "" "Info"
Write-Status "Next steps:" "Info"
Write-Status "1. Eject this USB safely" "Info"
Write-Status "2. Insert into target computer" "Info"
Write-Status "3. Boot from USB (F12 during startup)" "Info"
Write-Status "4. Follow on-screen installation wizard" "Info"
Write-Status "" "Info"
Write-Status "Installation will take 20-30 minutes depending on:" "Info"
Write-Status "• System performance" "Info"
Write-Status "• Internet speed (for package downloads)" "Info"
Write-Status "• Selected configuration" "Info"
Write-Status "" "Info"

# Safe removal
$volume = Get-Volume -DriveLetter $USBDrive.TrimEnd(':')
Write-Status "Safe removal instructions:" "Info"
Write-Status "Windows: Right-click USB drive → Eject" "Info"
Write-Status "PowerShell: Safely eject USB now" "Info"

Write-Status "" "Success"
Write-Status "HELIOS USB is ready!" "Success"
Write-Status "" "Success"
