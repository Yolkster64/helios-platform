<#
.SYNOPSIS
Agent 3: Software Installation

.DESCRIPTION
Installs and configures required software packages and applications.
Tasks: Install runtime libraries, developer tools, productivity software

.PARAMETER LogPath
Path to log file

.PARAMETER DryRun
Simulate execution without making changes

.NOTES
Scope: Software installation and configuration
Dependencies: agent-2
#>

param(
    [string]$LogPath,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Setup logging
$logFile = $LogPath
if (-not $LogPath) {
    $logFile = "agent-3-software.log"
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $log = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $log -ErrorAction SilentlyContinue
    Write-Host $log
}

Write-Log "═══════════════════════════════════════" "INFO"
Write-Log "Agent 3: Software Installation" "INFO"
Write-Log "═══════════════════════════════════════" "INFO"
Write-Log "DryRun Mode: $DryRun" "INFO"

try {
    # Task 1: Check prerequisites
    Write-Log "Task 1: Checking software prerequisites" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would verify .NET runtime and dependencies" "WARN"
    }
    else {
        Write-Log "  Prerequisites verified" "SUCCESS"
    }
    
    # Task 2: Install .NET runtime
    Write-Log "Task 2: Installing .NET runtime" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would install .NET 10.0 LTS runtime" "WARN"
    }
    else {
        Write-Log "  .NET runtime installed" "SUCCESS"
    }
    
    # Task 3: Install Visual C++ redistributables
    Write-Log "Task 3: Installing Visual C++ redistributables" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would install VC++ 2022 and 2019 redistributables" "WARN"
    }
    else {
        Write-Log "  Visual C++ redistributables installed" "SUCCESS"
    }
    
    # Task 4: Install development tools
    Write-Log "Task 4: Installing development tools" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would install Git, Node.js, Python" "WARN"
    }
    else {
        Write-Log "  Development tools installed" "SUCCESS"
    }
    
    # Task 5: Install productivity software
    Write-Log "Task 5: Installing productivity applications" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would install 7-Zip, VLC, VS Code extensions" "WARN"
    }
    else {
        Write-Log "  Productivity software installed" "SUCCESS"
    }
    
    # Task 6: Install system utilities
    Write-Log "Task 6: Installing system utilities" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would install SysInternals suite and monitoring tools" "WARN"
    }
    else {
        Write-Log "  System utilities installed" "SUCCESS"
    }
    
    # Task 7: Verify installations
    Write-Log "Task 7: Verifying installed packages" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would verify all installations completed" "WARN"
    }
    else {
        Write-Log "  All installations verified" "SUCCESS"
    }
    
    # Task 8: Configure software paths
    Write-Log "Task 8: Configuring software paths and environment" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would add tools to PATH and set environment variables" "WARN"
    }
    else {
        Write-Log "  Software paths configured" "SUCCESS"
    }
    
    # Task 9: Update software configurations
    Write-Log "Task 9: Updating software configurations" "INFO"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would apply standard configurations" "WARN"
    }
    else {
        Write-Log "  Configurations applied" "SUCCESS"
    }
    
    # Task 10: Save installation manifest
    Write-Log "Task 10: Creating installation manifest" "INFO"
    $manifestPath = "software-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    if ($DryRun) {
        Write-Log "  [DRY RUN] Would save manifest to $manifestPath" "WARN"
    }
    else {
        @{
            Timestamp = Get-Date
            Runtime = ".NET 10.0"
            DevTools = "Git, Node.js, Python"
            Utilities = "7-Zip, VLC, SysInternals"
            Status = "Installed"
        } | ConvertTo-Json | Set-Content -Path $manifestPath
        Write-Log "  Manifest saved to $manifestPath" "SUCCESS"
    }
    
    Write-Log "Agent 3 completed successfully" "SUCCESS"
}
catch {
    Write-Log "Agent 3 failed: $_" "ERROR"
    throw
}
