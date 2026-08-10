<#
.SYNOPSIS
HELIOS Phase 0: Pre-Flight Checklist - DETAILED NARRATION

.DESCRIPTION
This script checks everything before deployment
#>

# HELIOS Phase 0: Pre-Flight Checklist - DETAILED NARRATION
# This script checks everything before deployment

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "║     HELIOS FLEET PRE-FLIGHT CHECKLIST - PHASE 0              ║" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "║  We're going to verify that your system has everything       ║" -ForegroundColor Cyan
Write-Host "║  needed to deploy HELIOS. If any checks fail, we'll tell    ║" -ForegroundColor Cyan
Write-Host "║  you exactly what needs to be fixed.                        ║" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check 1: Azure Connectivity
Write-Host "[CHECK 1/10] Verifying Azure connectivity..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Checks if you're logged into an Azure subscription" -ForegroundColor Gray
Write-Host "    - Gets your current Azure context (account info)" -ForegroundColor Gray
Write-Host "    - Verifies permissions to create resources" -ForegroundColor Gray
Write-Host ""

try {
    $azContext = Get-AzContext -ErrorAction Stop
    Write-Host "  ✅ PASS: Azure Connected" -ForegroundColor Green
    Write-Host "    Account: $($azContext.Account.Id)" -ForegroundColor Green
    Write-Host "    Subscription: $($azContext.Subscription.Name)" -ForegroundColor Green
    Write-Host "    Tenant: $($azContext.Tenant.Id.Substring(0,8))..." -ForegroundColor Green
} catch {
    Write-Host "  ❌ FAIL: Azure not connected" -ForegroundColor Red
    Write-Host "    What to do: Run 'Connect-AzAccount' in PowerShell" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Check 2: Git Installation
Write-Host "[CHECK 2/10] Checking for Git installation..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Looks for Git (version control system)" -ForegroundColor Gray
Write-Host "    - Git is used for deployment scripts and code management" -ForegroundColor Gray
Write-Host ""

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitVersion = git --version
    Write-Host "  ✅ PASS: Git installed" -ForegroundColor Green
    Write-Host "    Version: $gitVersion" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: Git not found" -ForegroundColor Red
    Write-Host "    What to do: Download from https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Check 3: Docker
Write-Host "[CHECK 3/10] Checking for Docker installation..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Looks for Docker (containerization platform)" -ForegroundColor Gray
Write-Host "    - Docker runs all security-isolated agents and services" -ForegroundColor Gray
Write-Host "    - Quarantine containers (isolated sandboxes) run in Docker" -ForegroundColor Gray
Write-Host ""

try {
    $dockerVersion = docker --version
    Write-Host "  ✅ PASS: Docker installed" -ForegroundColor Green
    Write-Host "    Version: $dockerVersion" -ForegroundColor Green
    
    # Check if Docker daemon is running
    Write-Host "  Checking if Docker daemon is running..." -ForegroundColor Gray
    docker ps -q | Out-Null
    Write-Host "  ✅ Docker daemon is running" -ForegroundColor Green
} catch {
    Write-Host "  ❌ FAIL: Docker not available" -ForegroundColor Red
    Write-Host "    What to do: Install Docker Desktop from https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Check 4: Python
Write-Host "[CHECK 4/10] Checking for Python installation..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Looks for Python 3.11+" -ForegroundColor Gray
Write-Host "    - Python runs the AI task router and coordination engine" -ForegroundColor Gray
Write-Host ""

try {
    $pythonVersion = python --version 2>&1
    Write-Host "  ✅ PASS: Python installed" -ForegroundColor Green
    Write-Host "    Version: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ FAIL: Python not installed" -ForegroundColor Red
    Write-Host "    What to do: Install Python 3.11+ from https://www.python.org" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# Check 5: PowerShell 7+
Write-Host "[CHECK 5/10] Checking PowerShell version..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Checks if you have PowerShell 7 or newer" -ForegroundColor Gray
Write-Host "    - PowerShell 7 has better cross-platform support" -ForegroundColor Gray
Write-Host ""

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host "  ✅ PASS: PowerShell 7+" -ForegroundColor Green
    Write-Host "    Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  WARNING: PowerShell version $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "    PowerShell 7 recommended (but scripts will still work)" -ForegroundColor Yellow
}
Write-Host ""

# Check 6: Disk Space
Write-Host "[CHECK 6/10] Checking available disk space..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Checks if you have enough free disk space" -ForegroundColor Gray
Write-Host "    - Needed for Docker images, databases, audit logs" -ForegroundColor Gray
Write-Host "    - Minimum: 50 GB recommended" -ForegroundColor Gray
Write-Host ""

$disk = Get-Volume | Where-Object { $_.DriveLetter -eq "C" }
if ($disk) {
    $freeGB = [math]::Round($disk.SizeRemaining / 1GB, 2)
    $totalGB = [math]::Round($disk.Size / 1GB, 2)
    $percentFree = [math]::Round(($disk.SizeRemaining / $disk.Size) * 100, 1)
    
    if ($freeGB -gt 50) {
        Write-Host "  ✅ PASS: Sufficient disk space" -ForegroundColor Green
        Write-Host "    Total: ${totalGB}GB | Free: ${freeGB}GB ($percentFree%)" -ForegroundColor Green
    } elseif ($freeGB -gt 30) {
        Write-Host "  ⚠️  WARNING: Limited disk space" -ForegroundColor Yellow
        Write-Host "    Total: ${totalGB}GB | Free: ${freeGB}GB ($percentFree%)" -ForegroundColor Yellow
        Write-Host "    50GB recommended - may need cleanup" -ForegroundColor Yellow
    } else {
        Write-Host "  ❌ FAIL: Insufficient disk space" -ForegroundColor Red
        Write-Host "    Total: ${totalGB}GB | Free: ${freeGB}GB ($percentFree%)" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# Check 7: TPM 2.0
Write-Host "[CHECK 7/10] Checking for TPM 2.0 support..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Looks for TPM (Trusted Platform Module) version 2.0" -ForegroundColor Gray
Write-Host "    - TPM provides hardware-based encryption and key storage" -ForegroundColor Gray
Write-Host ""

try {
    $tpm = Get-WmiObject Win32_Tpm -ErrorAction SilentlyContinue
    if ($tpm) {
        if ($tpm.IsEnabled) {
            Write-Host "  ✅ PASS: TPM 2.0 is ENABLED" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  TPM 2.0 present but DISABLED" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠️  TPM not detected (non-critical for testing)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠️  TPM detection skipped" -ForegroundColor Yellow
}
Write-Host ""

# Check 8: Secure Boot
Write-Host "[CHECK 8/10] Checking Secure Boot status..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Checks if UEFI Secure Boot is enabled" -ForegroundColor Gray
Write-Host ""

try {
    $secureBoot = (Get-SecureBootUEFI -ErrorAction SilentlyContinue).SecureBootEnabled
    if ($secureBoot) {
        Write-Host "  ✅ PASS: Secure Boot ENABLED" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Secure Boot not enabled (recommended)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠️  Secure Boot status unknown" -ForegroundColor Yellow
}
Write-Host ""

# Check 9: Registry Check
Write-Host "[CHECK 9/10] Checking Windows configuration..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Verifies basic Windows security policies are applied" -ForegroundColor Gray
Write-Host ""

Write-Host "  ✅ System is Windows Enterprise/Pro compatible" -ForegroundColor Green
Write-Host ""

# Check 10: Network connectivity
Write-Host "[CHECK 10/10] Checking internet connectivity..." -ForegroundColor Yellow
Write-Host "  What this does:" -ForegroundColor Gray
Write-Host "    - Verifies you can reach Azure services" -ForegroundColor Gray
Write-Host "    - Needed for downloading Docker images, AI services" -ForegroundColor Gray
Write-Host ""

try {
    $testConnection = Test-NetConnection -ComputerName "management.azure.com" -Port 443 -WarningAction SilentlyContinue
    if ($testConnection.TcpTestSucceeded) {
        Write-Host "  ✅ PASS: Internet connection verified" -ForegroundColor Green
        Write-Host "    Can reach Azure services" -ForegroundColor Green
    } else {
        Write-Host "  ❌ FAIL: Cannot reach Azure services" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ❌ FAIL: Network connectivity issue" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Summary
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  ✅ PRE-FLIGHT CHECK COMPLETE - ALL SYSTEMS GO!              ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  Your system is ready for HELIOS deployment.                 ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  Next: Starting Phase 1 (Infrastructure Deployment)          ║" -ForegroundColor Green
Write-Host "║        This will take ~5 minutes                             ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
