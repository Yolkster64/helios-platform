#Requires -RunAsAdministrator
<#
.SYNOPSIS
    HELIOS Platform Pre-Installation System Check
    
.DESCRIPTION
    Comprehensive system requirements validation before HELIOS Platform installation.
    Checks Windows version, .NET SDK, PowerShell, disk space, and system compatibility.
    
.EXAMPLE
    .\Pre-Install-Check.ps1
    
.AUTHOR
    HELIOS Solutions
    
.VERSION
    1.0.0.0
#>

param(
    [switch]$Verbose,
    [switch]$SkipPrompt
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:Config = @{
    MinWindows           = "11"
    MinDotNetVersion     = "8.0"
    MinPowerShellVersion = "7.0"
    MinDiskSpaceGB       = 2
    MinRAMGB             = 4
    RequiredRegistry     = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        "HKLM:\SYSTEM\CurrentControlSet\Control"
    )
}

$script:Results = @{
    AllChecksPassed = $true
    Checks          = @()
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet("Green", "Red", "Yellow", "Cyan", "White")]
        [string]$Color = "White"
    )
    
    $colors = @{
        "Green"  = 10
        "Red"    = 12
        "Yellow" = 14
        "Cyan"   = 11
        "White"  = 15
    }
    
    $fgColor = $colors[$Color]
    Write-Host $Message -ForegroundColor $Color
}

function Add-CheckResult {
    param(
        [string]$CheckName,
        [bool]$Passed,
        [string]$Message,
        [ValidateSet("Success", "Warning", "Error", "Info")]
        [string]$Status = "Info"
    )
    
    $result = @{
        Name    = $CheckName
        Passed  = $Passed
        Message = $Message
        Status  = $Status
    }
    
    $script:Results.Checks += $result
    
    if (-not $Passed) {
        $script:Results.AllChecksPassed = $false
    }
    
    return $result
}

function Format-CheckOutput {
    param(
        [PSCustomObject]$Check
    )
    
    $icon = if ($Check.Passed) { "✓" } else { "✗" }
    $color = if ($Check.Passed) { "Green" } else { "Red" }
    
    $output = "  [$icon] $($Check.Name)"
    if ($Check.Message) {
        $output += " - $($Check.Message)"
    }
    
    Write-ColorOutput $output $color
}

# ============================================================================
# SYSTEM CHECKS
# ============================================================================

function Test-WindowsVersion {
    Write-Host "`n[1/8] Checking Windows Version..." -ForegroundColor Cyan
    
    $osVersion = [System.Environment]::OSVersion.Version
    $windowsVersion = $osVersion.Major
    
    if ($windowsVersion -ge 11) {
        $versionName = if ($windowsVersion -eq 11) { "Windows 11" } else { "Windows $windowsVersion" }
        Add-CheckResult -CheckName "Windows Version" -Passed $true `
            -Message "$versionName (Build: $($osVersion.Build))" -Status "Success"
        return $true
    }
    else {
        Add-CheckResult -CheckName "Windows Version" -Passed $false `
            -Message "Requires Windows 11 or later. Found: Windows $windowsVersion" -Status "Error"
        return $false
    }
}

function Test-AdminPrivileges {
    Write-Host "`n[2/8] Checking Administrator Privileges..." -ForegroundColor Cyan
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if ($isAdmin) {
        Add-CheckResult -CheckName "Administrator Privileges" -Passed $true `
            -Message "Running with Administrator privileges" -Status "Success"
        return $true
    }
    else {
        Add-CheckResult -CheckName "Administrator Privileges" -Passed $false `
            -Message "This script must run as Administrator" -Status "Error"
        return $false
    }
}

function Test-DotNetSDK {
    Write-Host "`n[3/8] Checking .NET SDK..." -ForegroundColor Cyan
    
    try {
        # Check for .NET 10 SDK
        $dotnetPath = Get-Command dotnet -ErrorAction Stop | Select-Object -ExpandProperty Source
        $output = & $dotnetPath --version

        $version = $output.Split(' ')[0]
        $majorVersion = [int]$version.Split('.')[0]

        if ($majorVersion -ge 10) {
            Add-CheckResult -CheckName ".NET SDK" -Passed $true `
                -Message ".NET SDK $version installed" -Status "Success"
            return $true
        }
        else {
            Add-CheckResult -CheckName ".NET SDK" -Passed $false `
                -Message "Requires .NET 10 SDK or later. Found: $version" -Status "Error"
            return $false
        }
    }
    catch {
        Add-CheckResult -CheckName ".NET SDK" -Passed $false `
            -Message ".NET SDK not found. Download from: https://dotnet.microsoft.com/download" -Status "Error"
        return $false
    }
}

function Test-PowerShellVersion {
    Write-Host "`n[4/8] Checking PowerShell Version..." -ForegroundColor Cyan
    
    $psVersion = $PSVersionTable.PSVersion.Major
    
    if ($psVersion -ge 7) {
        Add-CheckResult -CheckName "PowerShell Version" -Passed $true `
            -Message "PowerShell $psVersion.$($PSVersionTable.PSVersion.Minor)" -Status "Success"
        return $true
    }
    else {
        Add-CheckResult -CheckName "PowerShell Version" -Passed $false `
            -Message "Requires PowerShell 7.0+. Found: $psVersion.$($PSVersionTable.PSVersion.Minor)" -Status "Error"
        return $false
    }
}

function Test-DiskSpace {
    Write-Host "`n[5/8] Checking Disk Space..." -ForegroundColor Cyan
    
    try {
        $programFilesDrive = (Get-Item $env:ProgramFiles).PSDrive.Name + ":"
        $driveInfo = Get-PSDrive -Name $programFilesDrive[0] -ErrorAction Stop
        $freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
        
        if ($freeSpaceGB -ge $script:Config.MinDiskSpaceGB) {
            Add-CheckResult -CheckName "Disk Space" -Passed $true `
                -Message "$freeSpaceGB GB free space available (requires: $($script:Config.MinDiskSpaceGB) GB)" -Status "Success"
            return $true
        }
        else {
            Add-CheckResult -CheckName "Disk Space" -Passed $false `
                -Message "Insufficient disk space. Available: $freeSpaceGB GB, Required: $($script:Config.MinDiskSpaceGB) GB" -Status "Error"
            return $false
        }
    }
    catch {
        Add-CheckResult -CheckName "Disk Space" -Passed $false `
            -Message "Could not determine available disk space" -Status "Warning"
        return $false
    }
}

function Test-RAMCapacity {
    Write-Host "`n[6/8] Checking RAM Capacity..." -ForegroundColor Cyan
    
    try {
        $totalMemory = (Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory) / 1GB
        $ramGB = [math]::Round($totalMemory, 2)
        
        if ($ramGB -ge $script:Config.MinRAMGB) {
            Add-CheckResult -CheckName "System RAM" -Passed $true `
                -Message "$ramGB GB available (requires: $($script:Config.MinRAMGB) GB)" -Status "Success"
            return $true
        }
        else {
            Add-CheckResult -CheckName "System RAM" -Passed $false `
                -Message "Low RAM detected. Available: $ramGB GB, Recommended: $($script:Config.MinRAMGB) GB" -Status "Warning"
            return $true  # Warning only, not a blocker
        }
    }
    catch {
        Add-CheckResult -CheckName "System RAM" -Passed $true `
            -Message "Could not verify RAM (non-critical)" -Status "Warning"
        return $true
    }
}

function Test-RegistryAccess {
    Write-Host "`n[7/8] Checking Registry Access..." -ForegroundColor Cyan
    
    try {
        foreach ($regPath in $script:Config.RequiredRegistry) {
            $testPath = Test-Path $regPath -ErrorAction Stop
            if (-not $testPath) {
                Add-CheckResult -CheckName "Registry Access" -Passed $false `
                    -Message "Cannot access required registry key: $regPath" -Status "Error"
                return $false
            }
        }
        
        Add-CheckResult -CheckName "Registry Access" -Passed $true `
            -Message "Registry access verified" -Status "Success"
        return $true
    }
    catch {
        Add-CheckResult -CheckName "Registry Access" -Passed $false `
            -Message "Registry access check failed: $_" -Status "Error"
        return $false
    }
}

function Test-InternetConnectivity {
    Write-Host "`n[8/8] Checking Internet Connectivity..." -ForegroundColor Cyan
    
    try {
        $testConnection = Test-NetConnection -ComputerName "www.google.com" -Port 443 -ErrorAction SilentlyContinue
        
        if ($testConnection.TcpTestSucceeded) {
            Add-CheckResult -CheckName "Internet Connectivity" -Passed $true `
                -Message "Internet connection available" -Status "Success"
            return $true
        }
        else {
            Add-CheckResult -CheckName "Internet Connectivity" -Passed $false `
                -Message "No internet connection detected (optional)" -Status "Warning"
            return $true  # Warning only
        }
    }
    catch {
        Add-CheckResult -CheckName "Internet Connectivity" -Passed $true `
            -Message "Could not verify internet connectivity (non-critical)" -Status "Warning"
        return $true
    }
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

function New-CheckReport {
    Write-Host "`n" + ("="*70)
    Write-ColorOutput "HELIOS PLATFORM PRE-INSTALLATION CHECK REPORT" "Cyan"
    Write-Host "="*70
    
    Write-Host "`nCheck Results:" -ForegroundColor White
    Write-Host "-"*70
    
    foreach ($check in $script:Results.Checks) {
        Format-CheckOutput $check
    }
    
    Write-Host "`n" + "-"*70
    
    if ($script:Results.AllChecksPassed) {
        Write-ColorOutput "✓ All checks passed! Your system is ready for HELIOS Platform installation." "Green"
        Write-Host "`nYou can now proceed with running the HELIOS-Platform-Setup.exe installer.`n"
        return 0
    }
    else {
        Write-ColorOutput "✗ Some checks failed. Please resolve the issues before proceeding." "Red"
        Write-Host "`nRequired Actions:`n"
        
        foreach ($check in $script:Results.Checks | Where-Object { -not $_.Passed -and $_.Status -eq "Error" }) {
            Write-Host "  • $($check.Name): $($check.Message)" -ForegroundColor Yellow
        }
        
        Write-Host "`nFor more information, visit: https://docs.helios.solutions`n"
        return 1
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Invoke-PreInstallationCheck {
    Write-ColorOutput "`n╔════════════════════════════════════════════════════════════════════╗" "Cyan"
    Write-ColorOutput "║         HELIOS PLATFORM PRE-INSTALLATION CHECK                   ║" "Cyan"
    Write-ColorOutput "║                    Version 1.0.0.0                                ║" "Cyan"
    Write-ColorOutput "╚════════════════════════════════════════════════════════════════════╝" "Cyan"
    
    # Run all checks
    $checks = @(
        $(Test-WindowsVersion),
        $(Test-AdminPrivileges),
        $(Test-DotNetSDK),
        $(Test-PowerShellVersion),
        $(Test-DiskSpace),
        $(Test-RAMCapacity),
        $(Test-RegistryAccess),
        $(Test-InternetConnectivity)
    )
    
    # Generate report
    $exitCode = New-CheckReport
    
    # Prompt for action
    if (-not $SkipPrompt) {
        if ($script:Results.AllChecksPassed) {
            $response = Read-Host "`nWould you like to launch the installer now? (Y/N)"
            if ($response -eq "Y" -or $response -eq "y") {
                if (Test-Path ".\HELIOS-Platform-Setup.exe") {
                    Write-Host "`nLaunching installer..."
                    & ".\HELIOS-Platform-Setup.exe"
                }
                else {
                    Write-ColorOutput "Installer not found in current directory." "Yellow"
                }
            }
        }
    }
    
    Write-Host "`nPress any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    exit $exitCode
}

# Execute
Invoke-PreInstallationCheck
