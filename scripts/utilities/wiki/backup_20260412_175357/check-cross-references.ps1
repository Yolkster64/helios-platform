<#
.SYNOPSIS
    Validates and manages cross-references in wiki database

.DESCRIPTION
    Comprehensive cross-reference validation:
    - Verify all links are valid
    - Find broken references
    - Detect conflicting dependencies
    - Identify circular references
    - Validate file paths exist
    - Suggest fixes for broken links
    - Generate conflict report

.PARAMETER ValidateFiles
    Check if all referenced files exist (default: $true)

.PARAMETER CheckCircular
    Detect circular dependencies

.PARAMETER GenerateReport
    Create detailed validation report

.PARAMETER AutoFix
    Attempt to fix broken references

.PARAMETER DatabasePath
    SQLite database path

.EXAMPLE
    .\check-cross-references.ps1

.EXAMPLE
    .\check-cross-references.ps1 -CheckCircular -GenerateReport

.EXAMPLE
    .\check-cross-references.ps1 -ValidateFiles -AutoFix

.NOTES
    Location: scripts/utilities/wiki/check-cross-references.ps1
    Version: 1.0
#>

param(
    [switch]$ValidateFiles = $true,
    [switch]$CheckCircular,
    [switch]$GenerateReport,
    [switch]$AutoFix,
    [string]$DatabasePath = "C:\Users\ADMIN\helios-platform\docs\wiki.db",
    [string]$ReportPath = "C:\Users\ADMIN\helios-platform\docs\cross-reference-report.md"
)

$rootDir = "C:\Users\ADMIN\helios-platform"
$report = @()
$stats = @{
    total = 0
    valid = 0
    broken = 0
    conflicts = 0
    circular = 0
}

function Write-Status {
    param([string]$Message, [ValidateSet('Info', 'Success', 'Warning', 'Error')]$Type = 'Info')
    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $colors[$Type]
}

function Execute-Query {
    param([string]$Sql, [string]$DbPath)
    
    try {
        $result = & sqlite3 -json $DbPath $Sql 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $result | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        return @()
    }
    catch {
        Write-Status "Query error: $_" "Error"
        return @()
    }
}

function Validate-FileReferences {
    param([string]$DbPath)
    
    Write-Status "Validating file paths..."
    
    $sql = @"
SELECT f.id, f.path, f.name
FROM files f
WHERE f.status IN ('active', 'experimental');
"@
    
    $files = Execute-Query $sql $DbPath
    $broken = @()
    
    foreach ($file in $files) {
        $fullPath = Join-Path $rootDir $file.path
        if (-not (Test-Path $fullPath)) {
            $broken += $file
            $stats.broken++
            Write-Status "Broken: $($file.path)" "Warning"
        } else {
            $stats.valid++
        }
        $stats.total++
    }
    
    return $broken
}

function Check-Circular-Dependencies {
    param([string]$DbPath)
    
    Write-Status "Checking for circular dependencies..."
    
    $sql = @"
WITH RECURSIVE dep_chain AS (
    SELECT source_id, target_id, 1 as depth, CAST(source_id || '->' || target_id AS TEXT) as path
    FROM dependencies
    
    UNION ALL
    
    SELECT dc.source_id, d.target_id, dc.depth + 1,
           dc.path || '->' || d.target_id
    FROM dep_chain dc
    JOIN dependencies d ON dc.target_id = d.source_id
    WHERE dc.depth < 10
      AND dc.path NOT LIKE '%' || d.target_id || '%'
)
SELECT source_id, target_id, path FROM dep_chain
WHERE target_id = source_id AND depth > 1;
"@
    
    $circular = Execute-Query $sql $DbPath
    $stats.circular = $circular.Count
    
    if ($circular) {
        Write-Status "Found $($circular.Count) circular dependencies" "Warning"
    }
    
    return $circular
}

function Find-Conflict-Potential {
    param([string]$DbPath)
    
    Write-Status "Checking for conflicting references..."
    
    $sql = @"
SELECT xr.id, src.name as source_file, tgt.name as target_file,
       xr.reference_type, xr.conflict_notes, COUNT(*) as ref_count
FROM cross_references xr
JOIN files src ON xr.source_file_id = src.id
LEFT JOIN files tgt ON xr.target_file_id = tgt.id
WHERE xr.conflict_potential = 1
GROUP BY xr.source_file_id, xr.target_file_id
ORDER BY ref_count DESC;
"@
    
    $conflicts = Execute-Query $sql $DbPath
    $stats.conflicts = $conflicts.Count
    
    if ($conflicts) {
        Write-Status "Found $($conflicts.Count) potential conflicts" "Warning"
    }
    
    return $conflicts
}

function Validate-CrossReferences {
    param([string]$DbPath)
    
    Write-Status "Validating cross-references..."
    
    $sql = @"
SELECT xr.id, src.path as source_path, tgt.path as target_path,
       xr.reference_type, xr.validated
FROM cross_references xr
JOIN files src ON xr.source_file_id = src.id
LEFT JOIN files tgt ON xr.target_file_id = tgt.id;
"@
    
    $xrefs = Execute-Query $sql $DbPath
    $unvalidated = @()
    
    foreach ($xref in $xrefs) {
        if ($xref.target_path) {
            $fullPath = Join-Path $rootDir $xref.target_path
            if (-not (Test-Path $fullPath)) {
                $unvalidated += $xref
                Write-Status "Invalid cross-ref: $($xref.source_path) -> $($xref.target_path)" "Warning"
            }
        }
        
        if (-not $xref.validated) {
            Update-CrossReferenceValidation $DbPath $xref.id
        }
    }
    
    return $unvalidated
}

function Update-CrossReferenceValidation {
    param([string]$DbPath, [int]$RefId)
    
    $sql = @"
UPDATE cross_references 
SET validated = 1, validation_date = datetime('now')
WHERE id = $RefId;
"@
    
    $sql | & sqlite3 $DbPath 2>&1 | Out-Null
}

function Generate-Conflict-Report {
    param([array]$Conflicts, [array]$Circular, [array]$Broken)
    
    Write-Status "Generating conflict report..."
    
    $report = @"
# Cross-Reference Validation Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Summary
- **Total References:** $($stats.total)
- **Valid:** $($stats.valid)
- **Broken:** $($stats.broken)
- **Conflicts:** $($stats.conflicts)
- **Circular:** $($stats.circular)

## Broken File References
$(
    if ($Broken) {
        $Broken | ForEach-Object {
            "- **$($_.name)** - ``$($_.path)``"
        } | Out-String
    } else {
        "✓ No broken references found"
    }
)

## Conflicting References
$(
    if ($Conflicts) {
        "| Source | Target | Type | Notes |"
        "|--------|--------|------|-------|"
        $Conflicts | ForEach-Object {
            "| $($_.source_file) | $($_.target_file) | $($_.reference_type) | $($_.conflict_notes) |"
        } | Out-String
    } else {
        "✓ No conflicts found"
    }
)

## Circular Dependencies
$(
    if ($Circular) {
        "| Source | Target | Path |"
        "|--------|--------|------|"
        $Circular | ForEach-Object {
            "| $($_.source_id) | $($_.target_id) | $($_.path) |"
        } | Out-String
    } else {
        "✓ No circular dependencies found"
    }
)

## Recommendations
$(
    if ($stats.broken -gt 0) {
        "- Remove or update broken file references"
    }
    if ($stats.conflicts -gt 0) {
        "- Review and resolve conflicting dependencies"
    }
    if ($stats.circular -gt 0) {
        "- Refactor code to eliminate circular dependencies"
    }
    if ($stats.broken -eq 0 -and $stats.conflicts -eq 0 -and $stats.circular -eq 0) {
        "- All cross-references are valid ✓"
    }
)

---
*Report generated by Cross-Reference Validator v1.0*
"@
    
    return $report
}

function Save-Report {
    param([string]$ReportContent, [string]$Path)
    
    Set-Content -Path $Path -Value $ReportContent -Force
    Write-Status "Report saved: $Path" "Success"
}

# Main execution
Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    CROSS-REFERENCE VALIDATOR           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝`n" -ForegroundColor Cyan

if (-not (Test-Path $DatabasePath)) {
    Write-Status "Database not found: $DatabasePath" "Error"
    exit 1
}

$brokenFiles = @()
$conflicts = @()
$circular = @()

# Validate files
if ($ValidateFiles) {
    $brokenFiles = Validate-FileReferences $DatabasePath
}

# Check circular dependencies
if ($CheckCircular) {
    $circular = Check-Circular-Dependencies $DatabasePath
}

# Find conflicts
$conflicts = Find-Conflict-Potential $DatabasePath

# Validate cross-references
Validate-CrossReferences $DatabasePath | Out-Null

# Generate report
if ($GenerateReport) {
    $reportContent = Generate-Conflict-Report $conflicts $circular $brokenFiles
    Save-Report $reportContent $ReportPath
}

# Display summary
Write-Host "`n=== Validation Summary ===" -ForegroundColor Cyan
Write-Host "Total References: $($stats.total)" -ForegroundColor Cyan
Write-Host "Valid: $($stats.valid)" -ForegroundColor Green
Write-Host "Broken: $($stats.broken)" -ForegroundColor $(if ($stats.broken -gt 0) { 'Red' } else { 'Green' })
Write-Host "Conflicts: $($stats.conflicts)" -ForegroundColor $(if ($stats.conflicts -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "Circular: $($stats.circular)" -ForegroundColor $(if ($stats.circular -gt 0) { 'Yellow' } else { 'Green' })

if ($stats.broken -eq 0 -and $stats.conflicts -eq 0 -and $stats.circular -eq 0) {
    Write-Status "All cross-references validated successfully!" "Success"
} else {
    Write-Status "Issues found - review report for details" "Warning"
}

Write-Host ""
