<#
.SYNOPSIS
Side-by-side comparison of Helios Platform build variants.

.DESCRIPTION
Compares build variants and displays differences, similarities, overlap, and impacts.
Provides feature-by-feature breakdown, size impact analysis, and time impact analysis.
Can export results to HTML or Markdown reports.

.PARAMETER Variant1
First variant to compare.

.PARAMETER Variant2
Second variant to compare.

.PARAMETER ExportHtml
Export comparison to HTML file.

.PARAMETER ExportMarkdown
Export comparison to Markdown file.

.PARAMETER Verbose
Enables verbose logging output.

.EXAMPLE
.\compare-builds.ps1 -Variant1 developer -Variant2 enterprise
# Compare developer and enterprise builds side-by-side

.EXAMPLE
.\compare-builds.ps1 -Variant1 minimal -Variant2 all-features -ExportHtml
# Compare builds and export to HTML report

.EXAMPLE
.\compare-builds.ps1 -Variant1 gpu-optimized -Variant2 standard -ExportMarkdown
# Compare builds and export to Markdown report

.NOTES
Author: Helios Build System
Version: 1.0
#>

[CmdletBinding()]
param(
    [ValidateSet('minimal', 'standard', 'developer', 'enterprise', 'gpu-optimized', 'edge-deployment', 'all-features')]
    [string]$Variant1,
    
    [ValidateSet('minimal', 'standard', 'developer', 'enterprise', 'gpu-optimized', 'edge-deployment', 'all-features')]
    [string]$Variant2,
    
    [switch]$ExportHtml,
    [switch]$ExportMarkdown,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = if ($Verbose) { 'Continue' } else { 'SilentlyContinue' }

# Define script paths
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$reportsDir = Join-Path $scriptRoot "reports"
$logPath = Join-Path $scriptRoot "logs\compare-builds.log"

# Create directories if needed
@($reportsDir, (Split-Path -Parent $logPath)) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -Path $_ -ItemType Directory -Force | Out-Null
    }
}

<#
.SYNOPSIS
Logs a message to file and console.
#>
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $logPath -Value $logMessage
    
    switch ($Level) {
        'Info' { Write-Host $logMessage -ForegroundColor Gray }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error' { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
}

<#
.SYNOPSIS
Defines all build variants with their configurations.
#>
function Get-BuildVariants {
    return @{
        'minimal' = @{
            Name = 'Minimal Installation'
            Size = 256
            Time = 2
            Components = @('core', 'basic-ui', 'network-stack', 'logging', 'monitoring')
        }
        'standard' = @{
            Name = 'Standard Build'
            Size = 1200
            Time = 8
            Components = @('core', 'basic-ui', 'network-stack', 'logging', 'monitoring', 'database-client')
        }
        'developer' = @{
            Name = 'Developer Build'
            Size = 2400
            Time = 12
            Components = @('core', 'advanced-ui', 'network-stack', 'logging', 'monitoring', 'database-client', 'development-tools', 'debug-utilities', 'testing-framework', 'profiling-tools')
        }
        'enterprise' = @{
            Name = 'Enterprise Build'
            Size = 3800
            Time = 18
            Components = @('core', 'advanced-ui', 'network-stack', 'logging', 'monitoring', 'database-client', 'enterprise-security', 'advanced-analytics', 'clustering', 'backup-recovery')
        }
        'gpu-optimized' = @{
            Name = 'GPU-Optimized Build'
            Size = 2800
            Time = 14
            Components = @('core', 'advanced-ui', 'network-stack', 'gpu-acceleration', 'ml-toolkit', 'compute-libraries', 'monitoring')
        }
        'edge-deployment' = @{
            Name = 'Edge Deployment Build'
            Size = 512
            Time = 4
            Components = @('core', 'lightweight-ui', 'network-stack', 'edge-connector', 'local-cache', 'logging', 'offline-mode')
        }
        'all-features' = @{
            Name = 'All Features Build'
            Size = 5200
            Time = 25
            Components = @('core', 'advanced-ui', 'network-stack', 'logging', 'monitoring', 'database-client', 'development-tools', 'debug-utilities', 'testing-framework', 'enterprise-security', 'advanced-analytics', 'gpu-acceleration', 'ml-toolkit', 'clustering', 'backup-recovery', 'profiling-tools', 'multimedia')
        }
    }
}

<#
.SYNOPSIS
Displays comparison in console.
#>
function Show-ConsoleComparison {
    param(
        [object]$Var1,
        [object]$Var2,
        [string]$V1Name,
        [string]$V2Name
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Build Variant Comparison Report" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Header
    $headerFormat = "{0,-30} | {1,25} | {2,25}"
    Write-Host ($headerFormat -f "Metric", $V1Name, $V2Name) -ForegroundColor Yellow
    Write-Host ("-" * 82) -ForegroundColor Gray
    
    # Size comparison
    $sizeDiff = $Var2.Size - $Var1.Size
    $sizeDiffPct = if ($Var1.Size -gt 0) { [math]::Round(($sizeDiff / $Var1.Size) * 100, 1) } else { 0 }
    $sizeIndicator = if ($sizeDiff -gt 0) { "▲" } else { "▼" }
    
    Write-Host ($headerFormat -f "Size (MB)", "$($Var1.Size) MB", "$($Var2.Size) MB")
    Write-Host ($headerFormat -f "Size Difference", "-", "$sizeIndicator $sizeDiff MB ($sizeDiffPct%)")
    Write-Host ""
    
    # Time comparison
    $timeDiff = $Var2.Time - $Var1.Time
    $timeDiffPct = if ($Var1.Time -gt 0) { [math]::Round(($timeDiff / $Var1.Time) * 100, 1) } else { 0 }
    $timeIndicator = if ($timeDiff -gt 0) { "▲" } else { "▼" }
    
    Write-Host ($headerFormat -f "Install Time (min)", "$($Var1.Time) min", "$($Var2.Time) min")
    Write-Host ($headerFormat -f "Time Difference", "-", "$timeIndicator $timeDiff min ($timeDiffPct%)")
    Write-Host ""
    
    # Component counts
    $v1CompCount = @($Var1.Components).Count
    $v2CompCount = @($Var2.Components).Count
    
    Write-Host ($headerFormat -f "Total Components", "$v1CompCount", "$v2CompCount")
    Write-Host ""
    
    # Shared components
    $shared = @($Var1.Components | Where-Object { $_ -in $Var2.Components })
    Write-Host "Shared Components ($($shared.Count)): " -ForegroundColor Green
    foreach ($comp in $shared) {
        Write-Host "  ✓ $comp" -ForegroundColor Green
    }
    Write-Host ""
    
    # Unique to Variant 1
    $unique1 = @($Var1.Components | Where-Object { $_ -notin $Var2.Components })
    Write-Host "Unique to $V1Name ($($unique1.Count)): " -ForegroundColor Cyan
    foreach ($comp in $unique1) {
        Write-Host "  ◆ $comp" -ForegroundColor Cyan
    }
    Write-Host ""
    
    # Unique to Variant 2
    $unique2 = @($Var2.Components | Where-Object { $_ -notin $Var1.Components })
    Write-Host "Unique to $V2Name ($($unique2.Count)): " -ForegroundColor Magenta
    foreach ($comp in $unique2) {
        Write-Host "  ◆ $comp" -ForegroundColor Magenta
    }
    Write-Host ""
    
    # Component matrix
    Write-Host "Component Matrix:" -ForegroundColor Yellow
    Write-Host ""
    $allComponents = @(($Var1.Components + $Var2.Components) | Sort-Object -Unique)
    
    $matrixFormat = "{0,-35} | {1,20} | {2,20}"
    Write-Host ($matrixFormat -f "Component", "In $V1Name", "In $V2Name") -ForegroundColor Gray
    Write-Host ("-" * 78) -ForegroundColor Gray
    
    foreach ($comp in $allComponents) {
        $in1 = if ($comp -in $Var1.Components) { "✓" } else { "✗" }
        $in2 = if ($comp -in $Var2.Components) { "✓" } else { "✗" }
        Write-Host ($matrixFormat -f $comp, $in1, $in2)
    }
    Write-Host ""
}

<#
.SYNOPSIS
Exports comparison to HTML file.
#>
function Export-ComparisonHtml {
    param(
        [object]$Var1,
        [object]$Var2,
        [string]$V1Name,
        [string]$V2Name
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fileName = "comparison-$V1Name-vs-$V2Name-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $filePath = Join-Path $reportsDir $fileName
    
    $allComponents = @(($Var1.Components + $Var2.Components) | Sort-Object -Unique)
    $shared = @($Var1.Components | Where-Object { $_ -in $Var2.Components })
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Build Comparison: $V1Name vs $V2Name</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Segoe UI, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-bottom: 10px; text-align: center; }
        .timestamp { text-align: center; color: #999; font-size: 12px; margin-bottom: 30px; }
        .comparison-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .variant-card { border: 1px solid #ddd; padding: 20px; border-radius: 6px; }
        .variant-card h2 { color: #0066cc; margin-bottom: 15px; font-size: 18px; }
        .metric { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #eee; }
        .metric-label { color: #666; font-weight: 500; }
        .metric-value { color: #333; font-weight: 600; }
        .size-impact { background: #f0f8ff; padding: 15px; border-radius: 4px; margin: 20px 0; }
        .time-impact { background: #fffacd; padding: 15px; border-radius: 4px; margin: 20px 0; }
        .component-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .component-table th { background: #f0f0f0; padding: 12px; text-align: left; font-weight: 600; border-bottom: 2px solid #ddd; }
        .component-table td { padding: 10px 12px; border-bottom: 1px solid #eee; }
        .component-table tr:hover { background: #f9f9f9; }
        .checkmark { color: green; font-weight: bold; }
        .cross { color: red; font-weight: bold; }
        .summary { background: #f0f0f0; padding: 20px; border-radius: 6px; margin: 20px 0; }
        .summary-item { display: flex; justify-content: space-between; padding: 8px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Build Variant Comparison Report</h1>
        <div class="timestamp">Generated: $timestamp</div>
        
        <div class="comparison-grid">
            <div class="variant-card">
                <h2>$V1Name</h2>
                <div class="metric">
                    <span class="metric-label">Size:</span>
                    <span class="metric-value">${($Var1.Size)} MB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Install Time:</span>
                    <span class="metric-value">${($Var1.Time)} minutes</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Components:</span>
                    <span class="metric-value">${@($Var1.Components).Count}</span>
                </div>
            </div>
            
            <div class="variant-card">
                <h2>$V2Name</h2>
                <div class="metric">
                    <span class="metric-label">Size:</span>
                    <span class="metric-value">${($Var2.Size)} MB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Install Time:</span>
                    <span class="metric-value">${($Var2.Time)} minutes</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Components:</span>
                    <span class="metric-value">${@($Var2.Components).Count}</span>
                </div>
            </div>
        </div>
        
        <div class="size-impact">
            <strong>Size Impact Analysis</strong><br>
            Difference: <strong>${$($Var2.Size - $Var1.Size)} MB</strong> 
            ($(if ($Var2.Size -gt $Var1.Size) { "+" } else { "" })$([math]::Round((($Var2.Size - $Var1.Size) / $Var1.Size) * 100, 1))%)
        </div>
        
        <div class="time-impact">
            <strong>Time Impact Analysis</strong><br>
            Difference: <strong>${$($Var2.Time - $Var1.Time)} minutes</strong> 
            ($(if ($Var2.Time -gt $Var1.Time) { "+" } else { "" })$([math]::Round((($Var2.Time - $Var1.Time) / $Var1.Time) * 100, 1))%)
        </div>
        
        <div class="summary">
            <div class="summary-item">
                <span>Shared Components:</span>
                <strong>$($shared.Count)</strong>
            </div>
            <div class="summary-item">
                <span>Unique to ${V1Name}:</span>
                <strong>$(@($Var1.Components | Where-Object { $_ -notin $Var2.Components }).Count)</strong>
            </div>
            <div class="summary-item">
                <span>Unique to ${V2Name}:</span>
                <strong>$(@($Var2.Components | Where-Object { $_ -notin $Var1.Components }).Count)</strong>
            </div>
        </div>
        
        <h3>Component Matrix</h3>
        <table class="component-table">
            <thead>
                <tr>
                    <th>Component</th>
                    <th>In $V1Name</th>
                    <th>In $V2Name</th>
                </tr>
            </thead>
            <tbody>
"@
    
    foreach ($comp in $allComponents) {
        $in1 = if ($comp -in $Var1.Components) { '<span class="checkmark">✓</span>' } else { '<span class="cross">✗</span>' }
        $in2 = if ($comp -in $Var2.Components) { '<span class="checkmark">✓</span>' } else { '<span class="cross">✗</span>' }
        $html += "                <tr><td>$comp</td><td>$in1</td><td>$in2</td></tr>`n"
    }
    
    $html += @"
            </tbody>
        </table>
    </div>
</body>
</html>
"@
    
    try {
        $html | Set-Content -Path $filePath -Encoding UTF8
        Write-Log -Message "HTML report exported to $filePath" -Level Success
        Write-Host "HTML report: $filePath" -ForegroundColor Green
        return $filePath
    }
    catch {
        Write-Log -Message "Failed to export HTML: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
Exports comparison to Markdown file.
#>
function Export-ComparisonMarkdown {
    param(
        [object]$Var1,
        [object]$Var2,
        [string]$V1Name,
        [string]$V2Name
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $fileName = "comparison-$V1Name-vs-$V2Name-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
    $filePath = Join-Path $reportsDir $fileName
    
    $allComponents = @(($Var1.Components + $Var2.Components) | Sort-Object -Unique)
    $shared = @($Var1.Components | Where-Object { $_ -in $Var2.Components })
    $unique1 = @($Var1.Components | Where-Object { $_ -notin $Var2.Components })
    $unique2 = @($Var2.Components | Where-Object { $_ -notin $Var1.Components })
    
    $markdown = @"
# Build Variant Comparison Report

**Generated:** $timestamp

## Comparison: $V1Name vs $V2Name

### Overview

| Metric | $V1Name | $V2Name |
|--------|$(if ($V1Name.Length -lt 15) { "-" * (15 - $V1Name.Length) }else { "" })-|$(if ($V2Name.Length -lt 15) { "-" * (15 - $V2Name.Length) }else { "" })-|
| Size | $($Var1.Size) MB | $($Var2.Size) MB |
| Install Time | $($Var1.Time) minutes | $($Var2.Time) minutes |
| Total Components | $(@($Var1.Components).Count) | $(@($Var2.Components).Count) |

### Impact Analysis

#### Size Impact
- **Difference:** $($Var2.Size - $Var1.Size) MB
- **Percentage Change:** $(if ($Var1.Size -gt 0) { [math]::Round((($Var2.Size - $Var1.Size) / $Var1.Size) * 100, 1) }else { "N/A" })%

#### Time Impact
- **Difference:** $($Var2.Time - $Var1.Time) minutes
- **Percentage Change:** $(if ($Var1.Time -gt 0) { [math]::Round((($Var2.Time - $Var1.Time) / $Var1.Time) * 100, 1) }else { "N/A" })%

### Component Breakdown

#### Shared Components ($($shared.Count))

$($shared | ForEach-Object { "- $_ ✓" } | Out-String)

#### Unique to $V1Name ($($unique1.Count))

$($unique1 | ForEach-Object { "- $_ ◆" } | Out-String)

#### Unique to $V2Name ($($unique2.Count))

$($unique2 | ForEach-Object { "- $_ ◆" } | Out-String)

### Component Matrix

| Component | $V1Name | $V2Name |
|-----------|:-------:|:-------:|
$($allComponents | ForEach-Object { 
    $in1 = if ($_ -in $Var1.Components) { "✓" } else { "✗" }
    $in2 = if ($_ -in $Var2.Components) { "✓" } else { "✗" }
    "| $_ | $in1 | $in2 |"
} | Out-String)

### Summary

- **Shared Components:** $($shared.Count)
- **Unique to ${V1Name}:** $(@($Var1.Components | Where-Object { $_ -notin $Var2.Components }).Count)
- **Unique to ${V2Name}:** $(@($Var2.Components | Where-Object { $_ -notin $Var1.Components }).Count)
- **Total Unique:** $($unique1.Count + $unique2.Count)

---
*Generated by Helios Build Manager*
"@
    
    try {
        $markdown | Set-Content -Path $filePath -Encoding UTF8
        Write-Log -Message "Markdown report exported to $filePath" -Level Success
        Write-Host "Markdown report: $filePath" -ForegroundColor Green
        return $filePath
    }
    catch {
        Write-Log -Message "Failed to export Markdown: $_" -Level Error
        return $null
    }
}

<#
.SYNOPSIS
Main comparison function.
#>
function Invoke-BuildComparison {
    Write-Log -Message "Build comparison started: $Variant1 vs $Variant2" -Level Info
    
    $variants = Get-BuildVariants
    
    if (-not $variants.ContainsKey($Variant1) -or -not $variants.ContainsKey($Variant2)) {
        Write-Log -Message "Invalid variant specified" -Level Error
        return $false
    }
    
    if ($Variant1 -eq $Variant2) {
        Write-Log -Message "Cannot compare identical variants" -Level Warning
        Write-Host "Cannot compare identical variants. Please select different variants." -ForegroundColor Yellow
        return $false
    }
    
    $var1Data = $variants[$Variant1]
    $var2Data = $variants[$Variant2]
    
    Show-ConsoleComparison -Var1 $var1Data -Var2 $var2Data -V1Name $Variant1 -V2Name $Variant2
    
    if ($ExportHtml) {
        Export-ComparisonHtml -Var1 $var1Data -Var2 $var2Data -V1Name $Variant1 -V2Name $Variant2
    }
    
    if ($ExportMarkdown) {
        Export-ComparisonMarkdown -Var1 $var1Data -Var2 $var2Data -V1Name $Variant1 -V2Name $Variant2
    }
    
    Write-Log -Message "Build comparison completed successfully" -Level Success
    return $true
}

# Main execution
try {
    $result = Invoke-BuildComparison
    exit if ($result) { 0 } else { 1 }
}
catch {
    Write-Log -Message "Unhandled error: $_" -Level Error
    Write-Log -Message $_.ScriptStackTrace -Level Error
    exit 1
}
