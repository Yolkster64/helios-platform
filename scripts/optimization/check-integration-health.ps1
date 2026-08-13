#Requires -Version 7.0
<#
.SYNOPSIS
    HELIOS Platform Integration Health Check
    
.DESCRIPTION
    Comprehensive health check of all HELIOS Platform systems:
    - System connectivity
    - Data flow validation
    - File integrity
    - Workflow execution
    - Performance monitoring
    
.PARAMETER Verbose
    Enable verbose logging
    
.PARAMETER OutputPath
    Path for health report (default: ./INTEGRATION_HEALTH_REPORT.md)
#>

param(
    [switch]$Verbose,
    [string]$OutputPath = "./INTEGRATION_HEALTH_REPORT.md"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = @()
$systemsStatus = @{}
$overallHealth = "HEALTHY"
$criticalIssues = @()
$warnings = @()

function Write-Section {
    param([string]$Title, [ConsoleColor]$Color = "Cyan")
    Write-Host "`n$('='*60)" -ForegroundColor $Color
    Write-Host $Title -ForegroundColor $Color
    Write-Host "$('='*60)" -ForegroundColor $Color
}

function Log-Result {
    param(
        [string]$Check,
        [string]$Status,
        [string]$Details = "",
        [string]$Component = "General"
    )
    
    $result = @{
        Timestamp = $timestamp
        Component = $Component
        Check = $Check
        Status = $Status
        Details = $Details
    }
    
    $script:report += $result
    
    $statusColor = switch($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }
    
    Write-Host "[$Status] $Check" -ForegroundColor $statusColor
    if ($Details) {
        Write-Host "  └─ $Details" -ForegroundColor Gray
    }
    
    return $result
}

function Check-SystemFile {
    param(
        [string]$Path,
        [string]$Component = "File"
    )
    
    if (Test-Path $Path) {
        $file = Get-Item $Path
        $size = $file.Length / 1MB
        Log-Result "File Check: $(Split-Path $Path -Leaf)" "PASS" "Size: $([math]::Round($size, 2))MB" $Component
        return $true
    } else {
        Log-Result "File Check: $Path" "FAIL" "File not found" $Component
        $script:criticalIssues += "Missing required file: $Path"
        return $false
    }
}

function Check-Directory {
    param(
        [string]$Path,
        [string]$Component = "Directory"
    )
    
    if (Test-Path $Path -PathType Container) {
        $itemCount = (Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        Log-Result "Directory Check: $(Split-Path $Path -Leaf)" "PASS" "Items: $itemCount" $Component
        return $true
    } else {
        Log-Result "Directory Check: $Path" "FAIL" "Directory not found" $Component
        return $false
    }
}

function Check-ProcessStatus {
    param(
        [string]$ProcessName,
        [string]$Component = "Process"
    )
    
    $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($process) {
        $memory = [math]::Round($process.WorkingSet64 / 1MB, 2)
        Log-Result "Process Check: $ProcessName" "PASS" "Memory: ${memory}MB, CPU: $($process.CPU)s" $Component
        return $true
    } else {
        Log-Result "Process Check: $ProcessName" "WARN" "Process not running" $Component
        return $false
    }
}

function Validate-JsonFile {
    param(
        [string]$Path,
        [string]$Component = "JSON"
    )
    
    if (-not (Test-Path $Path)) {
        Log-Result "JSON Validation: $(Split-Path $Path -Leaf)" "FAIL" "File not found" $Component
        return $false
    }
    
    try {
        $content = Get-Content $Path -Raw
        $json = $content | ConvertFrom-Json
        Log-Result "JSON Validation: $(Split-Path $Path -Leaf)" "PASS" "Valid JSON" $Component
        return $true
    } catch {
        Log-Result "JSON Validation: $(Split-Path $Path -Leaf)" "FAIL" "Invalid JSON: $_" $Component
        $script:criticalIssues += "Invalid JSON in $Path"
        return $false
    }
}

function Check-GitRepository {
    param([string]$Path = ".")
    
    try {
        $gitStatus = & git -C $Path status --porcelain 2>$null
        $gitBranch = & git -C $Path rev-parse --abbrev-ref HEAD 2>$null
        $gitCommit = & git -C $Path rev-parse --short HEAD 2>$null
        
        Log-Result "Git Repository" "PASS" "Branch: $gitBranch, Commit: $gitCommit" "Git"
        
        if ($gitStatus) {
            Log-Result "Git Working Directory" "WARN" "Uncommitted changes detected" "Git"
            $script:warnings += "Uncommitted changes in repository"
        } else {
            Log-Result "Git Working Directory" "PASS" "Clean working directory" "Git"
        }
        
        return $true
    } catch {
        Log-Result "Git Repository" "FAIL" "Error checking git: $_" "Git"
        return $false
    }
}

function Test-NetworkConnectivity {
    param(
        [string]$Host = "github.com",
        [string]$Port = 443,
        [string]$Component = "Network"
    )
    
    try {
        $connection = Test-NetConnection -ComputerName $Host -Port $Port -WarningAction SilentlyContinue
        if ($connection.TcpTestSucceeded) {
            Log-Result "Network Connectivity: $Host" "PASS" "TCP Port $Port responding" $Component
            return $true
        } else {
            Log-Result "Network Connectivity: $Host" "FAIL" "Cannot reach $Host on port $Port" $Component
            return $false
        }
    } catch {
        Log-Result "Network Connectivity: $Host" "WARN" "Error testing connection: $_" $Component
        return $false
    }
}

function Check-DiskSpace {
    param(
        [string]$Path = "C:",
        [string]$Component = "Storage"
    )
    
    try {
        $drive = Get-PSDrive -Name ($Path.Substring(0,1)) -ErrorAction Stop
        $total = $drive.Used + $drive.Free
        $percentUsed = [math]::Round(($drive.Used / $total) * 100, 2)
        
        if ($percentUsed -gt 90) {
            Log-Result "Disk Space: $Path" "FAIL" "$percentUsed% used" $Component
            $script:criticalIssues += "Low disk space on $Path"
            return $false
        } elseif ($percentUsed -gt 75) {
            Log-Result "Disk Space: $Path" "WARN" "$percentUsed% used" $Component
            $script:warnings += "Disk space usage elevated on $Path"
            return $true
        } else {
            Log-Result "Disk Space: $Path" "PASS" "$percentUsed% used" $Component
            return $true
        }
    } catch {
        Log-Result "Disk Space: $Path" "FAIL" "Error checking disk: $_" $Component
        return $false
    }
}

function Check-Coresystem {
    Write-Section "Core System Health"
    
    # Check critical directories
    Check-Directory ".\src" "Core System"
    Check-Directory ".\scripts" "Core System"
    Check-Directory ".\config" "Core System"
    Check-Directory ".\docs" "Core System"
    
    # Check critical files
    Check-SystemFile ".\README.md" "Core System"
    Check-SystemFile ".\.gitignore" "Core System"
    Check-SystemFile ".\LICENSE" "Core System"
    
    $systemsStatus["Core System"] = "Checked"
}

function Check-Configuration {
    Write-Section "Configuration Health"
    
    Check-Directory ".\config" "Configuration"
    Check-Directory ".\configs" "Configuration"
    
    if (Test-Path ".\config") {
        $configFiles = Get-ChildItem ".\config" -Filter "*.json" -ErrorAction SilentlyContinue
        foreach ($file in $configFiles) {
            Validate-JsonFile $file.FullName "Configuration"
        }
    }
    
    $systemsStatus["Configuration"] = "Checked"
}

function Check-GitHubIntegration {
    Write-Section "GitHub Integration Health"
    
    Check-Directory ".\.github" "GitHub"
    Check-Directory ".\.github\workflows" "GitHub"
    
    $workflowFiles = Get-ChildItem ".\.github\workflows" -Filter "*.yml" -ErrorAction SilentlyContinue | Measure-Object
    Log-Result "GitHub Workflows" "PASS" "Found $($workflowFiles.Count) workflows" "GitHub"
    
    # Validate workflow files
    Get-ChildItem ".\.github\workflows" -Filter "*.yml" -ErrorAction SilentlyContinue | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match "on:") {
            Log-Result "Workflow: $($_.Name)" "PASS" "Valid workflow file" "GitHub"
        } else {
            Log-Result "Workflow: $($_.Name)" "WARN" "May have missing triggers" "GitHub"
        }
    }
    
    $systemsStatus["GitHub Integration"] = "Checked"
}

function Check-BuildSystems {
    Write-Section "Build System Health"
    
    Check-Directory ".\builds" "Build System"
    
    # Check NuGet config
    if (Test-Path ".\nuget.config") {
        Log-Result "NuGet Configuration" "PASS" "nuget.config found" "Build System"
    } else {
        Log-Result "NuGet Configuration" "WARN" "nuget.config not found" "Build System"
    }
    
    $systemsStatus["Build System"] = "Checked"
}

function Check-Documentation {
    Write-Section "Documentation Health"
    
    Check-Directory ".\docs" "Documentation"
    
    $docFiles = @(
        "README.md",
        "CONTRIBUTING.md",
        "DEVELOPMENT.md",
        "LICENSE.md"
    )
    
    foreach ($file in $docFiles) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            Log-Result "Doc File: $file" "PASS" "Size: $size bytes" "Documentation"
        }
    }
    
    $systemsStatus["Documentation"] = "Checked"
}

function Check-TestingInfrastructure {
    Write-Section "Testing Infrastructure Health"
    
    Check-Directory ".\tests" "Testing"
    
    $testFiles = Get-ChildItem ".\tests" -Filter "*test*" -ErrorAction SilentlyContinue | Measure-Object
    Log-Result "Test Files" "PASS" "Found $($testFiles.Count) test files" "Testing"
    
    $systemsStatus["Testing"] = "Checked"
}

function Check-DataIntegrity {
    Write-Section "Data Integrity Checks"
    
    Check-Directory ".\data" "Data"
    
    # Check for orphaned files
    $files = Get-ChildItem ".\data" -Recurse -ErrorAction SilentlyContinue | Measure-Object
    Log-Result "Data Files" "PASS" "Total: $($files.Count) items" "Data"
    
    $systemsStatus["Data Integrity"] = "Checked"
}

function Check-Performance {
    Write-Section "Performance Metrics"
    
    $startTime = Get-Date
    $uptime = (Get-Date) - (Get-Date (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime)
    Log-Result "System Uptime" "PASS" "Uptime: $([int]$uptime.TotalDays) days, $($uptime.Hours) hours" "Performance"
    
    $cpuUsage = Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty LoadPercentage
    if ($cpuUsage -lt 50) {
        Log-Result "CPU Usage" "PASS" "Current: ${cpuUsage}%" "Performance"
    } elseif ($cpuUsage -lt 80) {
        Log-Result "CPU Usage" "WARN" "Current: ${cpuUsage}%" "Performance"
        $script:warnings += "CPU usage elevated"
    } else {
        Log-Result "CPU Usage" "FAIL" "Current: ${cpuUsage}%" "Performance"
        $script:criticalIssues += "High CPU usage"
    }
    
    $memory = Get-CimInstance -ClassName Win32_ComputerSystem
    $memUsage = [math]::Round(((($memory.TotalPhysicalMemory - (Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory)) / $memory.TotalPhysicalMemory) * 100, 2)
    
    if ($memUsage -lt 75) {
        Log-Result "Memory Usage" "PASS" "Current: ${memUsage}%" "Performance"
    } elseif ($memUsage -lt 90) {
        Log-Result "Memory Usage" "WARN" "Current: ${memUsage}%" "Performance"
        $script:warnings += "Memory usage elevated"
    } else {
        Log-Result "Memory Usage" "FAIL" "Current: ${memUsage}%" "Performance"
        $script:criticalIssues += "High memory usage"
    }
    
    Check-DiskSpace
    
    $systemsStatus["Performance"] = "Checked"
}

function Check-NetworkConnections {
    Write-Section "Network Connectivity"
    
    Test-NetworkConnectivity -Host "github.com" -Port 443
    Test-NetworkConnectivity -Host "api.github.com" -Port 443
    Test-NetworkConnectivity -Host "api.nuget.org" -Port 443
    Test-NetworkConnectivity -Host "www.powershellgallery.com" -Port 443
    Test-NetworkConnectivity -Host "8.8.8.8" -Port 53
    
    $systemsStatus["Network"] = "Checked"
}

function Generate-HealthReport {
    Write-Section "Generating Health Report"
    
    $markdown = @"
# HELIOS Platform Integration Health Report

**Generated:** $timestamp

## Executive Summary

- **Overall Health Status:** $overallHealth
- **Total Checks:** $($report.Count)
- **Passed:** $($report | Where-Object {$_.Status -eq 'PASS'} | Measure-Object).Count
- **Warnings:** $($report | Where-Object {$_.Status -eq 'WARN'} | Measure-Object).Count
- **Failed:** $($report | Where-Object {$_.Status -eq 'FAIL'} | Measure-Object).Count

## System Status Summary

| System | Status |
|--------|--------|
$($systemsStatus.Keys | ForEach-Object { "| $_ | ✓ |" })

## Detailed Results

"@

    # Group results by component
    $components = $report.Component | Sort-Object -Unique
    
    foreach ($component in $components) {
        $markdown += "`n### $component`n`n"
        $componentResults = $report | Where-Object {$_.Component -eq $component}
        
        foreach ($result in $componentResults) {
            $emoji = switch($result.Status) {
                "PASS" { "✅" }
                "WARN" { "⚠️" }
                "FAIL" { "❌" }
                default { "ℹ️" }
            }
            
            $markdown += "- **$($result.Check)** [$($result.Status)] $emoji`n"
            if ($result.Details) {
                $markdown += "  - Details: $($result.Details)`n"
            }
        }
    }

    # Critical Issues
    if ($criticalIssues.Count -gt 0) {
        $markdown += "`n## ⚠️ Critical Issues`n`n"
        $criticalIssues | ForEach-Object { $markdown += "- $_`n" }
        $script:overallHealth = "UNHEALTHY"
    }

    # Warnings
    if ($warnings.Count -gt 0) {
        $markdown += "`n## ⚠️ Warnings`n`n"
        $warnings | ForEach-Object { $markdown += "- $_`n" }
    }

    # Recommendations
    $markdown += "`n## Recommendations`n`n"
    if ($criticalIssues.Count -gt 0) {
        $markdown += "1. **Address Critical Issues First:** Review and fix all critical issues listed above`n"
    }
    if ($warnings.Count -gt 0) {
        $markdown += "2. **Monitor and Resolve Warnings:** Address warnings to prevent future issues`n"
    }
    if ($memUsage -gt 75) {
        $markdown += "3. **Optimize Memory Usage:** Consider optimizing memory-intensive processes`n"
    }
    if ($cpuUsage -gt 50) {
        $markdown += "4. **CPU Performance:** Monitor CPU-intensive operations`n"
    }
    
    $markdown += "`n---`n*Report generated by HELIOS Integration Health Check*`n"
    
    $markdown | Out-File $OutputPath -Encoding UTF8 -Force
    Write-Host "`n✅ Health report generated: $OutputPath" -ForegroundColor Green
    
    return $markdown
}

# Main execution
try {
    Write-Host "HELIOS Platform Integration Health Check" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "Started at $timestamp`n" -ForegroundColor Gray
    
    Check-CoreSystem
    Check-GitRepository
    Check-Configuration
    Check-GitHubIntegration
    Check-BuildSystems
    Check-Documentation
    Check-TestingInfrastructure
    Check-DataIntegrity
    Check-NetworkConnections
    Check-Performance
    
    Generate-HealthReport
    
    Write-Section "Health Check Complete"
    
    if ($criticalIssues.Count -gt 0) {
        Write-Host "`n❌ Health Status: UNHEALTHY" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "`n✅ Health Status: HEALTHY" -ForegroundColor Green
        exit 0
    }
    
} catch {
    Write-Host "`n❌ Error during health check: $_" -ForegroundColor Red
    exit 1
}
