# Code Checking Policy - HELIOS Platform v2

## Overview

All code committed to HELIOS Platform v2 must pass automated checks before merging. These checks run on every commit and are enforced by GitHub Actions.

## Check Categories

### 1. PowerShell Syntax Validation

**Purpose:** Ensure all PowerShell scripts have valid syntax

**Trigger:** Every `.ps1` file commit

**Check Implementation:**

```powershell
# Basic syntax check
$ErrorActionPreference = 'Stop'
Get-Content -Path $ScriptPath | Invoke-Expression -ErrorAction Stop
```

**What It Checks:**

- ✓ Valid PowerShell syntax
- ✓ Balanced brackets and parentheses
- ✓ Valid variable names
- ✓ Valid function definitions
- ✗ Logic errors (caught by unit tests)

**Example Violations:**

```powershell
# ✗ FAIL: Missing closing bracket
if ($condition {
    Write-Host "test"
}

# ✓ PASS: Valid syntax
if ($condition) {
    Write-Host "test"
}
```

**Command:**

```powershell
.\Check-PowerShellSyntax.ps1 -ScriptPath $FilePath
```

---

### 2. Security Scanning

**Purpose:** Detect hardcoded credentials and suspicious patterns

**Trigger:** Every `.ps1`, `.bat`, `.cmd` commit

**What It Checks:**

| Pattern | Reason | Fix |
|---------|--------|-----|
| `password\s*=\s*['"]` | Hardcoded password | Use secure parameter |
| `apikey\s*=\s*['"]` | Hardcoded API key | Use config/env var |
| `secret\s*=\s*['"]` | Hardcoded secret | Use credential object |
| `token\s*=\s*['"]` | Hardcoded token | Use secure storage |
| `ConvertFrom-SecureString` without key | Unencrypted credential | Use machine key or KMS |

**Example Violations:**

```powershell
# ✗ FAIL: Hardcoded password
$Password = "MySecurePassword123"

# ✗ FAIL: Hardcoded API key
$ApiKey = "sk_live_1234567890abcdef"

# ✓ PASS: Uses parameter
param(
    [securestring]$Password
)

# ✓ PASS: Uses environment variable
$ApiKey = $env:API_KEY
```

**Command:**

```powershell
.\Check-SecurityPatterns.ps1 -ScriptPath $FilePath
```

**Exceptions:**

- Test files can use dummy credentials (prefixed with `test_`, `demo_`, `sandbox_`)
- Example/documentation files must be marked with `# EXAMPLE CODE`

---

### 3. Registry Modification Validation

**Purpose:** Ensure all registry changes are documented and reversible

**Trigger:** Any script containing `New-Item -Path 'HKLM:'` or `Set-ItemProperty`

**What It Checks:**

| Check | Requirement | Reason |
|-------|-------------|--------|
| Is documented | Must include `# Registry: [description]` | Audit trail |
| Has comment | Must explain why change is needed | Maintainability |
| Is reversible | Must backup old value first | Rollback capability |
| Valid path | HKLM, HKCU, HKCR, HKU, HKCC only | Security |
| Correct type | REG_SZ, REG_DWORD, REG_BINARY verified | Data integrity |

**Example - Correct Registry Change:**

```powershell
# Registry: Disable unnecessary service for performance
# This change improves startup time by preventing auto-start of diagnostic service
# Rollback: Restore to original state

$RegistryPath = 'HKLM:\System\CurrentControlSet\Services\DiagTrack'
$OldValue = (Get-ItemProperty -Path $RegistryPath -Name Start).Start

# Backup original value
"Original DiagTrack Start value: $OldValue" | Add-Content -Path $RollbackLog

# Make change
Set-ItemProperty -Path $RegistryPath -Name Start -Value 4 -Type DWord
```

**Example - Invalid Registry Change (Will Fail):**

```powershell
# ✗ FAIL: No documentation
Set-ItemProperty -Path 'HKLM:\Software\Test' -Name Value -Value 1

# ✗ FAIL: Invalid registry hive
Set-ItemProperty -Path 'HKEY_LOCAL_MACHINE:\Software\Test' -Name Value -Value 1
```

**Command:**

```powershell
.\Check-RegistryModifications.ps1 -ScriptPath $FilePath
```

---

### 4. File Path Validation

**Purpose:** Ensure all file paths exist and are correctly formatted

**Trigger:** Any script with hardcoded paths

**What It Checks:**

| Check | Requirement | Reason |
|-------|-------------|--------|
| Valid format | Use backslashes or `$PSScriptRoot` | Windows standard |
| No UNC abuse | UNC paths require network verification | Security |
| Parent exists | Parent directory must exist | Avoid failures |
| Valid chars | No invalid path characters | Compatibility |
| Expandable | Environment variables are valid | Dynamic paths |

**Example - Correct Path Usage:**

```powershell
# ✓ PASS: Use $PSScriptRoot for relative paths
$ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'config.json'

# ✓ PASS: Use System32 environment variable
$SystemPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32'

# ✓ PASS: Create directory before using
$LogDir = 'C:\Logs\HELIOS'
if (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# ✗ FAIL: Hardcoded path without validation
$ConfigPath = 'C:\Users\Admin\Desktop\config.json'

# ✗ FAIL: Invalid characters
$LogPath = 'C:\Logs\<invalid>\log.txt'
```

**Command:**

```powershell
.\Check-FilePaths.ps1 -ScriptPath $FilePath
```

---

### 5. Documentation Requirements

**Purpose:** Ensure code is documented for maintainability

**Trigger:** Every `.ps1` file (phase scripts, utilities)

**What It Checks:**

| Element | Requirement | Example |
|---------|-------------|---------|
| File header | Minimum 5 lines | Phase, purpose, author, date |
| Function help | `<#.SYNOPSIS#>` block | Parameter descriptions |
| Parameters | Doc for each param | Type, purpose, examples |
| Error handling | Comment for try/catch | What error is handled |
| Complex logic | Inline comments | Why, not what |

**Required File Header:**

```powershell
<#
.SYNOPSIS
    Brief one-line description

.DESCRIPTION
    Detailed description of what this script does,
    why it's needed, and what it modifies.

.PARAMETER Phase
    Which HELIOS phase this applies to (0, 1, 2, etc.)

.AUTHOR
    Your Name

.DATE
    2024-MM-DD

.NOTES
    Any special requirements or dependencies
#>
```

**Required Function Documentation:**

```powershell
function Optimize-StartupServices {
    <#
    .SYNOPSIS
    Disables non-essential services to improve startup time

    .DESCRIPTION
    This function safely disables services that are not critical
    for system functionality but can impact startup performance.

    .PARAMETER ServiceNames
    Array of service names to disable. Must be valid service names.

    .EXAMPLE
    Optimize-StartupServices -ServiceNames @('DiagTrack', 'dmwappushservice')
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ServiceNames
    )
    # Implementation...
}
```

**Command:**

```powershell
.\Check-Documentation.ps1 -ScriptPath $FilePath
```

---

### 6. Test Coverage Requirements

**Purpose:** Ensure code changes have accompanying tests

**Trigger:** Any phase script or utility modification

**What It Checks:**

| Item | Requirement | Consequence |
|------|-------------|-------------|
| Unit tests exist | One per function | Test fails on commit |
| Coverage % | Minimum 80% | Test fails on commit |
| Test names | `test-[script-name].ps1` | Can't find tests |
| Assertions pass | All tests must pass | Can't merge code |

**Coverage Calculation:**

```
Coverage % = (Lines executed in tests / Total non-comment lines) * 100
```

**Example - Acceptable Coverage:**

```
Phase-0-Optimize.ps1: 1,245 lines
- Comments/blanks: 245 lines
- Code: 1,000 lines
- Tested: 820 lines

Coverage = (820 / 1000) * 100 = 82% ✓ PASS
```

**Example - Insufficient Coverage:**

```
Phase-1-Security.ps1: 2,150 lines
- Comments/blanks: 150 lines
- Code: 2,000 lines
- Tested: 1,200 lines

Coverage = (1200 / 2000) * 100 = 60% ✗ FAIL (< 80%)
```

**Command:**

```powershell
.\Check-TestCoverage.ps1 -ScriptPath $FilePath -MinimumCoverage 80
```

---

## Check Execution Order

Checks run in sequence; failure stops the pipeline:

```
1. PowerShell Syntax Validation
   ↓ (all files must have valid syntax)
2. Security Scanning
   ↓ (no hardcoded credentials)
3. Registry Modification Validation
   ↓ (all registry changes documented)
4. File Path Validation
   ↓ (all paths valid)
5. Documentation Requirements
   ↓ (all code documented)
6. Test Coverage Requirements
   ↓ (minimum 80% coverage)
```

---

## Running Checks Locally

### Before Committing

```powershell
# Run all checks on your files
.\Run-CodeChecks.ps1 -FilePath .\Phase-0-Optimize.ps1

# Output:
# [✓] Syntax validation passed
# [✓] Security scan passed
# [✓] Registry modifications validated
# [✓] File paths validated
# [✓] Documentation complete
# [✓] Test coverage 85%
# Result: PASS - Safe to commit
```

### Individual Checks

```powershell
# Syntax only
.\Check-PowerShellSyntax.ps1 -ScriptPath .\Phase-0-Optimize.ps1

# Security only
.\Check-SecurityPatterns.ps1 -ScriptPath .\Phase-0-Optimize.ps1

# Registry only
.\Check-RegistryModifications.ps1 -ScriptPath .\Phase-0-Optimize.ps1

# Paths only
.\Check-FilePaths.ps1 -ScriptPath .\Phase-0-Optimize.ps1

# Documentation only
.\Check-Documentation.ps1 -ScriptPath .\Phase-0-Optimize.ps1

# Coverage only
.\Check-TestCoverage.ps1 -ScriptPath .\Phase-0-Optimize.ps1 -MinimumCoverage 80
```

---

## GitHub Actions Workflow

All checks run automatically on every commit via `.github/workflows/code-checks.yml`:

```
Commit Push
    ↓
GitHub Actions Triggered
    ↓
Checkout Code
    ↓
Install PowerShell 7
    ↓
Run Code Checks
    ├─ Syntax ✓
    ├─ Security ✓
    ├─ Registry ✓
    ├─ Paths ✓
    ├─ Documentation ✓
    └─ Coverage ✓
    ↓
✓ PASS: Can merge to main
OR
✗ FAIL: Block merge, fix required
```

---

## Exemptions

Limited exemptions are available for specific cases:

### Test Code Exemption

```powershell
# TEST CODE EXEMPTION
# This file contains dummy credentials for testing only
# Not used in production

$TestPassword = "TestPassword123"  # Exempted for unit testing
```

### Legacy Code Exemption

```powershell
<#
.LEGACY_CODE_EXEMPTION
Reason: Service discovery requires legacy COM objects
Expiration: 2024-12-31
#>
```

Request exemptions by commenting in pull request with justification.

---

## Troubleshooting Failed Checks

### Syntax Validation Failed

```
ERROR: Unexpected token '[' in type name.

Fix: Check for mismatched brackets
```

### Security Scan Failed

```
ERROR: Hardcoded password detected at line 42
Pattern: password = "..."

Fix: Use secure parameters or environment variables
```

### Registry Validation Failed

```
ERROR: Registry modification not documented at line 55
Required: Add comment explaining the change

Fix: Add # Registry: [description] comment
```

### Path Validation Failed

```
ERROR: Path contains invalid characters at line 12
Path: C:\Invalid<Path>\file.txt

Fix: Remove or escape invalid characters
```

### Documentation Failed

```
ERROR: Function missing <#.SYNOPSIS#> block at line 25
Function: Get-SystemMetrics

Fix: Add documentation block above function
```

### Coverage Failed

```
ERROR: Test coverage 65% below minimum 80%
Scripts tested: 650 / 1000 lines

Fix: Add more unit tests to increase coverage
```

---

## Metrics & Reporting

Check results are tracked in `.github/workflows/check-results.csv`:

```
Date,Script,Syntax,Security,Registry,Paths,Docs,Coverage,Overall
2024-01-15,Phase-0-Optimize.ps1,PASS,PASS,PASS,PASS,PASS,85%,PASS
2024-01-15,test-phase-0.ps1,PASS,PASS,PASS,PASS,PASS,92%,PASS
2024-01-16,Phase-1-Security.ps1,PASS,FAIL,PASS,PASS,PASS,78%,FAIL
```

---

## Summary

| Check | Frequency | Impact | Time |
|-------|-----------|--------|------|
| Syntax Validation | Every commit | Blocking | <1s |
| Security Scanning | Every commit | Blocking | <2s |
| Registry Validation | Every commit | Blocking | <1s |
| File Path Validation | Every commit | Blocking | <1s |
| Documentation | Every commit | Blocking | <2s |
| Test Coverage | Every commit | Blocking | ~30s |
| **Total** | Every commit | Blocking | **~40s** |

---

**Version:** 2.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Development Team
