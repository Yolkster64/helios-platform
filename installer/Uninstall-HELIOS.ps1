#!/usr/bin/env pwsh
<#
.SYNOPSIS
    HELIOS Platform Standalone Uninstaller
    
.DESCRIPTION
    Comprehensive uninstallation script for HELIOS Platform.
    Removes all files, registry entries, and configurations.
    
.EXAMPLE
    .\Uninstall-HELIOS.ps1
    .\Uninstall-HELIOS.ps1 -Force
    .\Uninstall-HELIOS.ps1 -KeepConfig
    
.PARAMETER Force
    Skip confirmation prompts and uninstall immediately
    
.PARAMETER KeepConfig
    Keep configuration files and data during uninstall
    
.PARAMETER InstallPath
    Custom installation path (default: Program Files\HELIOS Platform)
    
.AUTHOR
    HELIOS Solutions
    
.VERSION
    1.0.0.0
#>

#Requires -RunAsAdministrator

param(
    [switch]$Force,
    [switch]$KeepConfig,
    [string]$InstallPath = "$env:ProgramFiles\HELIOS Platform"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$UninstallConfig = @{
    RegPaths    = @(
        "HKCU:\Software\HELIOS Platform"
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HELIOS Platform"
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" # Auto-start entry
    )
    Shortcuts   = @(
        "$env:SMPROGRAMS\HELIOS Platform"
        "$env:DESKTOP\HELIOS Platform.lnk"
        "$env:DESKTOP\HELIOS Dashboard.lnk"
    )
    ConfigFiles = @(
        "config"
        "logs"
        "data"
    )
}

$UninstallStatus = @{
    RegistryEntriesRemoved = 0
    FilesRemoved           = 0
    ShortcutsRemoved       = 0
    ErrorsOccurred         = 0
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-UninstallLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "DEBUG"   = "Gray"
    }
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colors[$Level]
}

function Get-UserConfirmation {
    param(
        [string]$Message,
        [string]$Caption = "Confirm Action"
    )
    
    if ($Force) {
        return $true
    }
    
    $choices = @(
        New-Object System.Management.Automation.Host.ChoiceDescription "&Yes"
        New-Object System.Management.Automation.Host.ChoiceDescription "&No"
    )
    
    $decision = $Host.UI.PromptForChoice($Caption, $Message, $choices, 1)
    return $decision -eq 0
}

function Remove-RegistryEntries {
    Write-UninstallLog "`nRemoving registry entries..." "INFO"
    
    foreach ($regPath in $UninstallConfig.RegPaths) {
        try {
            if (Test-Path $regPath) {
                # Handle Run key specially (remove only HELIOS entry)
                if ($regPath -like "*Run") {
                    $value = Get-ItemProperty -Path $regPath -Name "HELIOS Platform" -ErrorAction SilentlyContinue
                    if ($value) {
                        Remove-ItemProperty -Path $regPath -Name "HELIOS Platform" -ErrorAction Stop
                        Write-UninstallLog "✓ Removed: HELIOS Platform (Run key)" "SUCCESS"
                        $script:UninstallStatus.RegistryEntriesRemoved++
                    }
                }
                else {
                    Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                    Write-UninstallLog "✓ Removed: $regPath" "SUCCESS"
                    $script:UninstallStatus.RegistryEntriesRemoved++
                }
            }
        }
        catch {
            Write-UninstallLog "✗ Failed to remove: $regPath - $_" "ERROR"
            $script:UninstallStatus.ErrorsOccurred++
        }
    }
}

function Remove-ShortcutsAndFolders {
    Write-UninstallLog "`nRemoving shortcuts and folders..." "INFO"
    
    foreach ($shortcut in $UninstallConfig.Shortcuts) {
        try {
            if (Test-Path $shortcut) {
                if ((Get-Item $shortcut).PSIsContainer) {
                    Remove-Item -Path $shortcut -Recurse -Force -ErrorAction Stop
                }
                else {
                    Remove-Item -Path $shortcut -Force -ErrorAction Stop
                }
                Write-UninstallLog "✓ Removed: $shortcut" "SUCCESS"
                $script:UninstallStatus.ShortcutsRemoved++
            }
        }
        catch {
            Write-UninstallLog "✗ Failed to remove: $shortcut - $_" "WARNING"
        }
    }
}

function Remove-InstalledFiles {
    Write-UninstallLog "`nRemoving installed files..." "INFO"
    
    if (-not (Test-Path $InstallPath)) {
        Write-UninstallLog "Installation path not found: $InstallPath" "WARNING"
        return
    }
    
    try {
        # Get list of files before deletion
        $files = Get-ChildItem -Path $InstallPath -Recurse -File
        $fileCount = $files.Count
        
        if ($fileCount -gt 0) {
            if ($KeepConfig) {
                # Remove files except config directories
                $filesToRemove = $files | Where-Object {
                    $_.FullName -notmatch "config|logs|data"
                }
            }
            else {
                $filesToRemove = $files
            }
            
            foreach ($file in $filesToRemove) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    $script:UninstallStatus.FilesRemoved++
                }
                catch {
                    Write-UninstallLog "  Warning: Could not remove file: $($file.Name)" "WARNING"
                }
            }
            
            Write-UninstallLog "✓ Removed $($script:UninstallStatus.FilesRemoved) files" "SUCCESS"
        }
        
        # Remove directory if empty
        if ((Get-ChildItem -Path $InstallPath -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
            Remove-Item -Path $InstallPath -Force -ErrorAction Stop
            Write-UninstallLog "✓ Removed installation directory" "SUCCESS"
        }
        else {
            if ($KeepConfig) {
                Write-UninstallLog "⚠ Configuration files retained at: $InstallPath" "INFO"
            }
        }
    }
    catch {
        Write-UninstallLog "✗ Error removing files: $_" "ERROR"
        $script:UninstallStatus.ErrorsOccurred++
    }
}

function Remove-EnvironmentPath {
    Write-UninstallLog "`nRemoving from system PATH..." "INFO"
    
    try {
        # Get current PATH
        $envPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        
        if ($envPath -contains $InstallPath) {
            # Remove from PATH
            $newPath = ($envPath -split ";" | Where-Object { $_ -ne $InstallPath }) -join ";"
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            
            Write-UninstallLog "✓ Removed from system PATH" "SUCCESS"
        }
        else {
            Write-UninstallLog "  Not found in system PATH (skipped)" "INFO"
        }
    }
    catch {
        Write-UninstallLog "✗ Failed to modify PATH: $_" "WARNING"
    }
}

function Backup-Configuration {
    Write-UninstallLog "`nBacking up configuration..." "INFO"
    
    try {
        $backupDir = "$env:USERPROFILE\HELIOS-Platform-Backup"
        $backupTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$backupDir\config-$backupTimestamp"
        
        if (Test-Path "$InstallPath\config") {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Copy-Item -Path "$InstallPath\config\*" -Destination $backupPath -Recurse -Force
            
            Write-UninstallLog "✓ Configuration backed up to: $backupPath" "SUCCESS"
        }
    }
    catch {
        Write-UninstallLog "⚠ Failed to backup configuration: $_" "WARNING"
    }
}

function Generate-UninstallReport {
    $reportPath = "$env:USERPROFILE\HELIOS-Uninstall-Report.txt"
    
    $report = @"
╔════════════════════════════════════════════════════════════════════╗
║          HELIOS PLATFORM UNINSTALLATION REPORT                   ║
╚════════════════════════════════════════════════════════════════════╝

Uninstall Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Installation Path: $InstallPath

═══════════════════════════════════════════════════════════════════════

UNINSTALLATION SUMMARY

Registry Entries Removed:    $($UninstallStatus.RegistryEntriesRemoved)
Files Removed:               $($UninstallStatus.FilesRemoved)
Shortcuts Removed:           $($UninstallStatus.ShortcutsRemoved)
Errors Occurred:             $($UninstallStatus.ErrorsOccurred)

═══════════════════════════════════════════════════════════════════════

ACTIONS PERFORMED

✓ Removed registry entries
✓ Removed shortcuts and start menu items
✓ Removed installed files
✓ Removed from system PATH

$(if ($KeepConfig) { "`n⚠ Configuration files retained for future reinstallation`n" } else { "" })

═══════════════════════════════════════════════════════════════════════

If you want to completely remove all HELIOS Platform data, delete:
$InstallPath

Support: https://docs.helios.solutions
"@
    
    $report | Set-Content $reportPath -Encoding UTF8
    Write-UninstallLog "`nUninstall report saved: $reportPath" "INFO"
}

# ============================================================================
# MAIN UNINSTALLATION PROCESS
# ============================================================================

function Invoke-Uninstallation {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           HELIOS PLATFORM UNINSTALLER                             ║" -ForegroundColor Cyan
    Write-Host "║                    Version 1.0.0.0                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-UninstallLog "Uninstallation Configuration:" "INFO"
    Write-UninstallLog "  Installation Path: $InstallPath" "INFO"
    Write-UninstallLog "  Keep Configuration: $KeepConfig" "INFO"
    Write-UninstallLog "  Force Mode: $Force" "INFO"
    
    # Confirmation
    if (-not $Force) {
        $message = "This will uninstall HELIOS Platform and remove all files from:`n`n  $InstallPath"
        if (-not $KeepConfig) {
            $message += "`n`nConfiguration files will also be deleted."
        }
        
        if (-not (Get-UserConfirmation -Message $message)) {
            Write-UninstallLog "Uninstallation cancelled by user" "WARNING"
            exit 0
        }
    }
    
    # Verify admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-UninstallLog "This script requires Administrator privileges" "ERROR"
        exit 1
    }
    
    Write-UninstallLog "`nStarting uninstallation..." "INFO"
    Write-UninstallLog "═" * 70 "DEBUG"
    
    try {
        # Backup config if keeping
        if ($KeepConfig) {
            Backup-Configuration
        }
        
        # Remove components
        Remove-RegistryEntries
        Remove-ShortcutsAndFolders
        Remove-EnvironmentPath
        Remove-InstalledFiles
        
        # Generate report
        Generate-UninstallReport
        
        # Final status
        Write-UninstallLog "═" * 70 "DEBUG"
        Write-UninstallLog "`n✓ UNINSTALLATION COMPLETED" "SUCCESS"
        
        if ($UninstallStatus.ErrorsOccurred -gt 0) {
            Write-UninstallLog "⚠ Some errors occurred during uninstallation (see above)" "WARNING"
            exit 1
        }
        
        Write-UninstallLog "`nSummary:" "INFO"
        Write-UninstallLog "  Registry entries removed: $($UninstallStatus.RegistryEntriesRemoved)" "INFO"
        Write-UninstallLog "  Files removed: $($UninstallStatus.FilesRemoved)" "INFO"
        Write-UninstallLog "  Shortcuts removed: $($UninstallStatus.ShortcutsRemoved)" "INFO"
        
        Write-UninstallLog "`nThank you for using HELIOS Platform!" "INFO"
        Write-UninstallLog "Report saved to: $env:USERPROFILE\HELIOS-Uninstall-Report.txt" "INFO"
        
        exit 0
    }
    catch {
        Write-UninstallLog "✗ UNINSTALLATION FAILED: $_" "ERROR"
        Write-UninstallLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        exit 1
    }
}

# Execute
Invoke-Uninstallation
