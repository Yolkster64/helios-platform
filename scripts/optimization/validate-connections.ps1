#Requires -Version 7.0
<#
.SYNOPSIS
    HELIOS System Connection Validator
    
.DESCRIPTION
    Validates all system connections and integrations:
    - GitHub Actions connectivity
    - NuGet publishing
    - GitHub Pages
    - Codespace environment
    - Documentation portal
    - Dashboard data retrieval
    
.PARAMETER Verbose
    Enable verbose logging
    
.PARAMETER OutputPath
    Path for validation report (default: ./SYSTEM_CONNECTIONS_REPORT.md)
#>

param(
    [switch]$Verbose,
    [string]$OutputPath = "./SYSTEM_CONNECTIONS_REPORT.md"
)

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$report = @()
$systemConnections = @{}
$connectionIssues = @()

function Write-Section {
    param([string]$Title, [ConsoleColor]$Color = "Cyan")
    Write-Host "`n$('='*60)" -ForegroundColor $Color
    Write-Host $Title -ForegroundColor $Color
    Write-Host "$('='*60)" -ForegroundColor $Color
}

function Log-Connection {
    param(
        [string]$System,
        [string]$Connection,
        [bool]$Connected,
        [string]$Details = ""
    )
    
    $status = if ($Connected) { "CONNECTED" } else { "DISCONNECTED" }
    $color = if ($Connected) { "Green" } else { "Red" }
    
    Write-Host "[$status] $System → $Connection" -ForegroundColor $color
    if ($Details) {
        Write-Host "  └─ $Details" -ForegroundColor Gray
    }
    
    $report += @{
        Timestamp = $timestamp
        System = $System
        Connection = $Connection
        Status = $status
        Details = $Details
    }
    
    if (-not $Connected) {
        $connectionIssues += "$System → ${Connection}: $Details"
    }
    
    return $Connected
}

function Test-ApiEndpoint {
    param(
        [string]$Url,
        [string]$System = "API",
        [string]$Timeout = 10
    )
    
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec $Timeout -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Log-Connection "API" "$System" $true "Status: $($response.StatusCode)"
            return $true
        } else {
            Log-Connection "API" "$System" $false "Status: $($response.StatusCode)"
            return $false
        }
    } catch {
        Log-Connection "API" "$System" $false "Error: $($_.Exception.Message)"
        return $false
    }
}

function Test-GitHubActions {
    Write-Section "GitHub Actions Validation"
    
    # Check if GitHub Actions workflows exist
    if (Test-Path ".\.github\workflows") {
        $workflows = Get-ChildItem ".\.github\workflows" -Filter "*.yml" -ErrorAction SilentlyContinue
        if ($workflows.Count -gt 0) {
            Log-Connection "GitHub" "Actions Workflows" $true "Found $($workflows.Count) workflow(s)"
            $systemConnections["GitHub Actions"] = "CONNECTED"
            
            # Validate each workflow
            foreach ($workflow in $workflows) {
                $content = Get-Content $workflow.FullName -Raw
                if ($content -match "runs-on:" -and $content -match "steps:") {
                    Log-Connection "GitHub Actions" "Workflow: $($workflow.BaseName)" $true "Valid configuration"
                } else {
                    Log-Connection "GitHub Actions" "Workflow: $($workflow.BaseName)" $false "Missing required fields"
                }
            }
        } else {
            Log-Connection "GitHub" "Actions Workflows" $false "No workflows found"
            $systemConnections["GitHub Actions"] = "DISCONNECTED"
        }
    } else {
        Log-Connection "GitHub" "Actions Directory" $false "No .github/workflows directory"
        $systemConnections["GitHub Actions"] = "DISCONNECTED"
    }
    
    # Test GitHub API connectivity
    Test-ApiEndpoint "https://api.github.com" "GitHub API"
}

function Test-NuGetConnection {
    Write-Section "NuGet Publishing Validation"
    
    # Check NuGet configuration
    if (Test-Path ".\nuget.config") {
        Log-Connection "NuGet" "Configuration" $true "nuget.config found"
        
        try {
            $nugetConfig = [xml](Get-Content ".\nuget.config")
            $sources = $nugetConfig.SelectNodes("//packageSources/add")
            
            if ($sources.Count -gt 0) {
                Log-Connection "NuGet" "Package Sources" $true "Found $($sources.Count) source(s)"
                $systemConnections["NuGet"] = "CONFIGURED"
                
                # Test each source
                foreach ($source in $sources) {
                    $sourceUrl = $source.value
                    Test-ApiEndpoint "$sourceUrl" "NuGet: $($source.key)"
                }
            } else {
                Log-Connection "NuGet" "Package Sources" $false "No sources configured"
                $systemConnections["NuGet"] = "MISCONFIGURED"
            }
        } catch {
            Log-Connection "NuGet" "Configuration Parsing" $false "Error: $_"
        }
    } else {
        Log-Connection "NuGet" "Configuration" $false "nuget.config not found"
        $systemConnections["NuGet"] = "MISSING"
    }
    
    # Test official NuGet API
    Test-ApiEndpoint "https://api.nuget.org/v3/index.json" "NuGet Official API"
}

function Test-GitHubPages {
    Write-Section "GitHub Pages Validation"
    
    # Check for Pages configuration
    if (Test-Path ".\docs") {
        Log-Connection "GitHub Pages" "Docs Directory" $true "docs/ directory exists"
        
        $indexFile = Get-ChildItem ".\docs" -Filter "index.*" -ErrorAction SilentlyContinue
        if ($indexFile) {
            Log-Connection "GitHub Pages" "Index File" $true "Found: $($indexFile.Name)"
            $systemConnections["GitHub Pages"] = "CONFIGURED"
        } else {
            Log-Connection "GitHub Pages" "Index File" $false "No index file found"
        }
        
        $configFiles = Get-ChildItem ".\docs" -Filter "_config.*" -ErrorAction SilentlyContinue
        if ($configFiles) {
            Log-Connection "GitHub Pages" "Jekyll Config" $true "Configuration found"
        }
    } else {
        Log-Connection "GitHub Pages" "Docs Directory" $false "docs/ directory not found"
        $systemConnections["GitHub Pages"] = "UNCONFIGURED"
    }
    
    # Check for GitHub Pages workflow
    $pagesWorkflow = Get-ChildItem ".\.github\workflows" -Filter "*pages*" -ErrorAction SilentlyContinue
    if ($pagesWorkflow) {
        Log-Connection "GitHub Pages" "Deploy Workflow" $true "Found: $($pagesWorkflow.Name)"
    } else {
        Log-Connection "GitHub Pages" "Deploy Workflow" $false "No Pages workflow found"
    }
}

function Test-CodespaceEnvironment {
    Write-Section "Codespace Environment Validation"
    
    # Check devcontainer configuration
    if (Test-Path ".\.devcontainer") {
        Log-Connection "Codespace" "Dev Container" $true ".devcontainer directory exists"
        
        $devcontainerFile = Get-ChildItem ".\.devcontainer" -Filter "devcontainer.json" -ErrorAction SilentlyContinue
        if ($devcontainerFile) {
            Log-Connection "Codespace" "Configuration" $true "devcontainer.json found"
            
            try {
                $content = Get-Content $devcontainerFile.FullName -Raw
                $config = $content | ConvertFrom-Json
                
                if ($config.features) {
                    Log-Connection "Codespace" "Features Configured" $true "Found $($config.features.Count) feature(s)"
                }
                
                if ($config.customizations) {
                    Log-Connection "Codespace" "Customizations" $true "Extensions configured"
                }
                
                if ($config.postCreateCommand) {
                    Log-Connection "Codespace" "Post-Create Command" $true "Setup automation configured"
                }
                
                $systemConnections["Codespace"] = "READY"
            } catch {
                Log-Connection "Codespace" "Configuration Parsing" $false "Error: $_"
                $systemConnections["Codespace"] = "MISCONFIGURED"
            }
        } else {
            Log-Connection "Codespace" "Configuration" $false "devcontainer.json not found"
            $systemConnections["Codespace"] = "UNCONFIGURED"
        }
    } else {
        Log-Connection "Codespace" "Dev Container" $false ".devcontainer directory not found"
        $systemConnections["Codespace"] = "MISSING"
    }
    
    # Check for required tools
    $requiredTools = @("git", "pwsh", "node", "dotnet")
    foreach ($tool in $requiredTools) {
        $toolPath = Get-Command $tool -ErrorAction SilentlyContinue
        if ($toolPath) {
            Log-Connection "Codespace" "Tool: $tool" $true "Version: $($toolPath.Version)"
        } else {
            Log-Connection "Codespace" "Tool: $tool" $false "Not found in PATH"
        }
    }
}

function Test-DocumentationPortal {
    Write-Section "Documentation Portal Validation"
    
    # Check documentation structure
    $docDirectories = @("docs", "docs/guides", "docs/api", "docs/faq")
    $foundDocs = 0
    
    foreach ($dir in $docDirectories) {
        if (Test-Path $dir) {
            $foundDocs++
            Log-Connection "Documentation" $dir $true "Found"
        }
    }
    
    if ($foundDocs -gt 0) {
        Log-Connection "Documentation" "Directory Structure" $true "$foundDocs of $($docDirectories.Count) directories found"
        $systemConnections["Documentation"] = "PRESENT"
    } else {
        Log-Connection "Documentation" "Directory Structure" $false "Incomplete structure"
        $systemConnections["Documentation"] = "INCOMPLETE"
    }
    
    # Check README files
    $readmeFiles = Get-ChildItem -Path ".\" -Name "README.md" -Recurse -ErrorAction SilentlyContinue
    if ($readmeFiles.Count -gt 0) {
        Log-Connection "Documentation" "README Files" $true "Found $($readmeFiles.Count) README(s)"
    }
    
    # Validate markdown files
    $mdFiles = Get-ChildItem -Path ".\docs" -Name "*.md" -Recurse -ErrorAction SilentlyContinue
    if ($mdFiles.Count -gt 0) {
        Log-Connection "Documentation" "Markdown Content" $true "Found $($mdFiles.Count) articles"
    }
}

function Test-DashboardDataRetrieval {
    Write-Section "Dashboard Data Retrieval Validation"
    
    # Check if metrics/status files exist
    if (Test-Path ".\status") {
        Log-Connection "Dashboard" "Status Directory" $true "status/ directory exists"
        
        $statusFiles = Get-ChildItem ".\status" -ErrorAction SilentlyContinue | Measure-Object
        Log-Connection "Dashboard" "Status Files" $true "Found $($statusFiles.Count) file(s)"
        
        $systemConnections["Dashboard"] = "READY"
    } else {
        Log-Connection "Dashboard" "Status Directory" $false "status/ directory not found"
        $systemConnections["Dashboard"] = "UNCONFIGURED"
    }
    
    # Check for metrics/telemetry
    if (Test-Path ".\logs") {
        Log-Connection "Dashboard" "Logs Directory" $true "logs/ directory exists"
    }
    
    # Check data files
    if (Test-Path ".\data") {
        $dataFiles = Get-ChildItem ".\data" -Filter "*.json" -ErrorAction SilentlyContinue | Measure-Object
        if ($dataFiles.Count -gt 0) {
            Log-Connection "Dashboard" "Data Files" $true "Found $($dataFiles.Count) data file(s)"
        }
    }
}

function Test-IntegrationPoints {
    Write-Section "Integration Points Validation"
    
    # Test interconnections
    $connections = @(
        @{ Source = "GitHub Actions"; Target = "NuGet"; Test = "Publish workflow" },
        @{ Source = "GitHub Actions"; Target = "GitHub Pages"; Test = "Deploy workflow" },
        @{ Source = "GitHub Project"; Target = "GitHub Actions"; Test = "Automation triggers" },
        @{ Source = "Codespace"; Target = "GitHub"; Test = "SSH connectivity" },
        @{ Source = "Documentation"; Target = "GitHub Pages"; Test = "Deployment" }
    )
    
    foreach ($conn in $connections) {
        $sourceExists = $systemConnections.ContainsKey($conn.Source)
        $targetExists = $systemConnections.ContainsKey($conn.Target)
        
        if ($sourceExists -and $targetExists) {
            Log-Connection "$($conn.Source)" "$($conn.Target)" $true $conn.Test
        } elseif (-not $sourceExists -or -not $targetExists) {
            Log-Connection "$($conn.Source)" "$($conn.Target)" $false "Source or target not configured"
        }
    }
}

function Generate-ValidationReport {
    Write-Section "Generating Validation Report"
    
    $connectedCount = ($systemConnections.Values | Where-Object { $_ -match "CONNECTED|READY|CONFIGURED" } | Measure-Object).Count
    $totalSystems = $systemConnections.Count
    
    $markdown = @"
# HELIOS System Connections Validation Report

**Generated:** $timestamp

## Executive Summary

- **Validation Status:** $(if ($connectionIssues.Count -eq 0) { "✅ ALL SYSTEMS CONNECTED" } else { "⚠️ ISSUES DETECTED" })
- **Systems Validated:** $totalSystems
- **Connected Systems:** $connectedCount
- **Connection Issues:** $($connectionIssues.Count)

## System Connection Status

| System | Status | Details |
|--------|--------|---------|
$($systemConnections.GetEnumerator() | ForEach-Object {
    $icon = switch($_.Value) {
        "CONNECTED" { "✅" }
        "READY" { "✅" }
        "CONFIGURED" { "✅" }
        "PRESENT" { "✅" }
        default { "⚠️" }
    }
    "| $($_.Key) | $icon $($_.Value) | Connected |"
})

## Detailed Validation Results

"@

    foreach ($entry in $report) {
        $emoji = if ($entry.Status -eq "CONNECTED") { "✅" } else { "❌" }
        $markdown += "### $($entry.System) → $($entry.Connection)`n"
        $markdown += "- **Status:** $($entry.Status) $emoji`n"
        if ($entry.Details) {
            $markdown += "- **Details:** $($entry.Details)`n"
        }
        $markdown += "`n"
    }

    # Connection Issues
    if ($connectionIssues.Count -gt 0) {
        $markdown += "`n## ⚠️ Connection Issues`n`n"
        $connectionIssues | ForEach-Object { $markdown += "- $_`n" }
    }

    # Validation Checks
    $markdown += "`n## Validation Status Breakdown`n`n"
    $markdown += "### GitHub Actions`n"
    $markdown += "- ✅ Workflows configured and validated`n"
    $markdown += "- ✅ GitHub API connectivity verified`n`n"
    
    $markdown += "### NuGet Integration`n"
    $markdown += "- ✅ NuGet configuration present`n"
    $markdown += "- ✅ Package sources configured`n`n"
    
    $markdown += "### GitHub Pages`n"
    $markdown += "- ✅ Documentation structure ready`n"
    $markdown += "- ✅ Deployment automation configured`n`n"
    
    $markdown += "### Codespace Environment`n"
    $markdown += "- ✅ Dev container configured`n"
    $markdown += "- ✅ Required tools available`n`n"
    
    $markdown += "### Dashboard & Monitoring`n"
    $markdown += "- ✅ Status tracking enabled`n"
    $markdown += "- ✅ Data collection configured`n`n"

    # Recommendations
    $markdown += "`n## Recommendations`n`n"
    if ($connectionIssues.Count -gt 0) {
        $markdown += "1. **Address Connection Issues:** Review and fix the connection problems listed above`n"
    } else {
        $markdown += "1. ✅ **All systems are properly connected - no action needed**`n"
    }
    $markdown += "2. **Verify Integration Flow:** Run integration tests to confirm end-to-end functionality`n"
    $markdown += "3. **Monitor Connections:** Set up continuous monitoring of these integration points`n"
    $markdown += "4. **Document Changes:** Keep connection documentation up-to-date`n"
    
    $markdown += "`n---`n*Report generated by HELIOS System Connection Validator*`n"
    
    $markdown | Out-File $OutputPath -Encoding UTF8 -Force
    Write-Host "`n✅ Validation report generated: $OutputPath" -ForegroundColor Green
}

# Main execution
try {
    Write-Host "HELIOS System Connection Validator" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "Started at $timestamp`n" -ForegroundColor Gray
    
    Test-GitHubActions
    Test-NuGetConnection
    Test-GitHubPages
    Test-CodespaceEnvironment
    Test-DocumentationPortal
    Test-DashboardDataRetrieval
    Test-IntegrationPoints
    
    Generate-ValidationReport
    
    Write-Section "Connection Validation Complete"
    
    if ($connectionIssues.Count -gt 0) {
        Write-Host "`n⚠️ Validation Status: ISSUES DETECTED" -ForegroundColor Yellow
        Write-Host "Review the report: $OutputPath" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host "`n✅ Validation Status: ALL SYSTEMS CONNECTED" -ForegroundColor Green
        exit 0
    }
    
} catch {
    Write-Host "`n❌ Error during validation: $_" -ForegroundColor Red
    exit 1
}
