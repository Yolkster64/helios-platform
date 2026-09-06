# Code Quality & Linting Workflow - code-checks.yml

## Overview

The `code-checks.yml` workflow performs comprehensive code quality validation for PowerShell scripts, batch files, and shell scripts. It runs on every push and pull request to ensure code meets quality, security, and documentation standards.

**File**: `.github/workflows/code-checks.yml`  
**Trigger**: Push/PR on code files  
**Duration**: 3-5 minutes  
**Runner**: windows-latest  

---

## Table of Contents

1. [Workflow Purpose](#workflow-purpose)
2. [Trigger Conditions](#trigger-conditions)
3. [Checks Performed](#checks-performed)
4. [Job Details](#job-details)
5. [Environment Setup](#environment-setup)
6. [Configuration](#configuration)
7. [Success Criteria](#success-criteria)
8. [Failure Handling](#failure-handling)
9. [Local Testing](#local-testing)
10. [Troubleshooting](#troubleshooting)

---

## Workflow Purpose

**Goals**:

- ✅ Validate PowerShell syntax correctness
- ✅ Detect hardcoded secrets and credentials
- ✅ Validate registry modification documentation
- ✅ Ensure file paths are properly constructed
- ✅ Verify code documentation completeness
- ✅ Run unit tests on Phase scripts
- ✅ Generate quality reports

**Scope**: PowerShell (`.ps1`), Batch (`.bat`, `.cmd`) scripts

---

## Trigger Conditions

```yaml
on:
  push:
    branches: [main, develop]
    paths:
      - '**.ps1'
      - '**.bat'
      - '**.cmd'
      - '.github/workflows/code-checks.yml'
  pull_request:
    branches: [main, develop]
    paths:
      - '**.ps1'
      - '**.bat'
      - '**.cmd'
```

**Triggers when**:

- PowerShell files are modified
- Batch files are modified
- Workflow file itself is modified

**Does not trigger**:

- Documentation-only changes
- Image/binary changes
- Configuration file changes (unrelated)

---

## Checks Performed

### 1. PowerShell Syntax Validation ⚙️

**What it checks**:

- Valid PowerShell syntax for all `.ps1` files
- Proper script structure and formatting
- Valid variable declarations
- Correct function definitions

**How to run locally**:

```powershell
$Files = Get-ChildItem -Recurse -Filter "*.ps1"
foreach ($File in $Files) {
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize(
            (Get-Content $File.FullName), 
            [ref]$null
        )
        Write-Host "✓ $($File.Name)"
    }
    catch {
        Write-Host "✗ $($File.Name): $($_.Exception.Message)"
    }
}
```

**Failure Example**:

```
✗ Deploy-Script.ps1: Unexpected token '"' in expression or statement.
```

**Fix**: Check for unclosed quotes, braces, or parentheses

---

### 2. Security Scanning 🔒

**What it checks**:

- Hardcoded passwords
- Hardcoded API keys
- Hardcoded secrets
- Hardcoded tokens

**Patterns detected**:

```regex
password\s*=\s*['"][^'"]*['"]
apikey\s*=\s*['"][^'"]*['"]
secret\s*=\s*['"][^'"]*['"]
token\s*=\s*['"][^'"]*['"]
```

**Examples of issues**:

```powershell
# ❌ FAIL
$password = "MySecurePass123"
$apiKey = "sk-1234567890"

# ✅ PASS
$password = $env:DB_PASSWORD
$apiKey = $env:NUGET_API_KEY
```

**How to fix**:

1. Use environment variables
2. Use GitHub Secrets
3. Use credential objects
4. Use Azure Key Vault

---

### 3. Registry Modification Validation 📋

**What it checks**:

- All registry modifications are documented
- Registry changes include `# Registry:` comment
- Registry operations are properly commented

**Requirement**:

```powershell
# Registry: Description of what is being changed and why
New-Item -Path "HKCU:\Software\MyApp" -Force | Out-Null
```

**Examples**:

```powershell
# ✅ PASS
# Registry: Creating application configuration key
Set-ItemProperty -Path "HKCU:\Software\HELIOS" -Name "Setting" -Value "Value"

# ❌ FAIL (missing documentation)
Set-ItemProperty -Path "HKCU:\Software\HELIOS" -Name "Setting" -Value "Value"
```

---

### 4. File Path Validation 📁

**What it checks**:

- Hardcoded user paths
- Invalid path characters
- Path consistency

**Examples of issues**:

```powershell
# ⚠️  WARNING
$path = "C:\Users\John\AppData"  # Consider using $env:APPDATA

# ✅ PASS
$path = $env:APPDATA
$path = Join-Path $env:TEMP "myfile.txt"
```

**Valid patterns**:

```powershell
$env:PROGRAMFILES     # System Program Files
$env:APPDATA          # User AppData
$env:TEMP             # Temp directory
$env:USERPROFILE      # User profile
```

---

### 5. Documentation Requirements ✍️

**Applies to**: `Phase-*.ps1` files

**Required elements**:

```powershell
<#
    .SYNOPSIS
    Brief description of what the phase does

    .DESCRIPTION
    Detailed description of the phase functionality,
    what it sets up, and what it configures
#>
param(
    # Parameters
)
```

**Validation**:

- Presence of `<#`
- Presence of `.SYNOPSIS`
- Presence of `.DESCRIPTION`

**Example of compliant script**:

```powershell
<#
    .SYNOPSIS
    Phase 0: Foundation Setup - Initializes platform core

    .DESCRIPTION
    Establishes foundational components for the HELIOS Platform:
    - Creates directory structure
    - Initializes configuration files
    - Sets up logging infrastructure
    - Validates system requirements
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Environment = "development"
)

Write-Host "Setting up Phase 0: Foundation..."
```

---

### 6. Test Coverage Verification 🧪

**What it checks**:

- Discovers test files (`test-*.ps1`)
- Counts number of test files
- Reports coverage

**Expected pattern**:

```
test-phase-0-foundation.ps1
test-phase-1-security.ps1
test-phase-2-optimization.ps1
```

---

### 7. Unit Test Execution 🧬

**What it runs**:

- Executes all `test-*-unit.ps1` files
- Uses Pester for test framework
- Reports pass/fail counts

**Pester test example**:

```powershell
Describe "Phase 0 Foundation Tests" {
    It "Should create required directories" {
        # Arrange
        $testPath = "C:\test"
        
        # Act
        New-Item -ItemType Directory -Path $testPath -Force
        
        # Assert
        Test-Path $testPath | Should -Be $true
        
        # Cleanup
        Remove-Item -Path $testPath -Force
    }
}
```

---

## Job Details

### Job: code-checks

```yaml
jobs:
  code-checks:
    name: Automated Code Quality Checks
    runs-on: windows-latest      # Windows runner required for PowerShell
    steps:
      # Setup steps...
      # Validation steps...
      # Reporting steps...
```

**Runner**: `windows-latest`

- Windows Server 2022
- PowerShell 5.1 (+ PowerShell Core 7 installed)
- Chocolatey package manager

---

## Environment Setup

### PowerShell Setup

```yaml
- name: Setup PowerShell 7
  run: |
    $ProgressPreference = "SilentlyContinue"
    choco install powershell-core -y
  shell: pwsh
```

**Why PowerShell 7?**:

- Modern features
- Better error handling
- Cross-platform compatibility
- Performance improvements

### Pester Installation

```yaml
- name: Install Pester
  run: |
    Install-Module -Name Pester -RequiredVersion 5.4.0 -Force -SkipPublisherCheck
  shell: pwsh
```

**Pester version**: 5.4.0 (latest stable for compatibility)

---

## Configuration

### Excluded Files

Test files are excluded from certain checks:

```powershell
if ($File.Name -notmatch '^test-' -and $Content -notmatch '# EXAMPLE CODE') {
    # Run security checks
}
```

### Security Patterns (Customizable)

```powershell
$PatternMap = @{
    'password\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded password"
    'apikey\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded API key"
    'secret\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded secret"
    'token\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded token"
}
```

**To add custom patterns**:

1. Edit `.github/workflows/code-checks.yml`
2. Add pattern to `$PatternMap`
3. Commit and push

---

## Success Criteria

✅ **All checks must pass**:

- [ ] Syntax validation passes
- [ ] No security issues found
- [ ] Registry modifications documented
- [ ] File paths valid
- [ ] Documentation complete
- [ ] All tests pass (if present)

**Exit code**: `0` (success) or `1` (failure)

---

## Failure Handling

### Step-by-Step Failure Analysis

1. **Check which step failed** (shown in workflow output)
2. **Get detailed error message** (shown in step output)
3. **Run the check locally** (replicate environment)
4. **Fix the issue** (see specific check sections)
5. **Test locally again** (verify fix)
6. **Commit and re-push** (re-trigger workflow)

### Common Failures

| Issue | Cause | Solution |
|-------|-------|----------|
| "Unexpected token" | Syntax error | Check quotes, braces, parentheses |
| "Hardcoded password" | Security issue | Use `$env:VAR` instead |
| "Missing documentation" | Missing comment block | Add `<# .SYNOPSIS ... #>` |
| "Registry changes undocumented" | Missing `# Registry:` | Add comment before registry operation |

---

## Local Testing

### Test Everything Locally

**1. Clone the repository**:

```bash
git clone https://github.com/YOUR_ORG/helios-platform.git
cd helios-platform
```

**2. Run syntax validation**:

```powershell
$Files = Get-ChildItem -Recurse -Filter "*.ps1"
foreach ($File in $Files) {
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize(
            (Get-Content $File.FullName), 
            [ref]$null
        )
        Write-Host "✓ $($File.Name)"
    }
    catch {
        Write-Host "✗ $($File.Name): $($_.Exception.Message)"
        exit 1
    }
}
```

**3. Run security scan**:

```powershell
$Files = Get-ChildItem -Recurse -Filter "*.ps1"
$PatternMap = @{
    'password\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded password"
    'apikey\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded API key"
    'secret\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded secret"
    'token\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded token"
}

foreach ($File in $Files) {
    $Content = Get-Content $File.FullName
    foreach ($Pattern in $PatternMap.Keys) {
        if ($Content -match $Pattern) {
            Write-Host "✗ Security issue: $($PatternMap[$Pattern])"
            exit 1
        }
    }
}
Write-Host "✓ No security issues found"
```

**4. Run tests locally**:

```powershell
Install-Module -Name Pester -RequiredVersion 5.4.0 -Force
Invoke-Pester -Path "tests/" -Verbose
```

---

## Troubleshooting

### PowerShell Not Found

**Error**:

```
PowerShell is not installed
```

**Solution**:

```powershell
# Install PowerShell Core
choco install powershell-core
# Or manually from https://github.com/PowerShell/PowerShell/releases
```

### Pester Module Not Found

**Error**:

```
The specified module 'Pester' was not loaded because no valid module file
```

**Solution**:

```powershell
Install-Module -Name Pester -RequiredVersion 5.4.0 -Force -SkipPublisherCheck
```

### Syntax Check False Positives

**Error**:

```
False positive on valid code
```

**Solution**:

- Mark file as test: `test-*.ps1`
- Add exclusion comment: `# EXAMPLE CODE`

### Tests Timing Out

**Error**:

```
Timeout waiting for test completion
```

**Solution**:

- Run tests locally to check performance
- Reduce test complexity or data size
- Increase workflow timeout

### File Path Issues on Windows

**Error**:

```
Path contains invalid characters
```

**Solutions**:

1. Use absolute paths with proper escaping
2. Use `Join-Path` cmdlet
3. Use environment variables
4. Check for special characters

---

## Performance Tips

⚡ **Optimization**:

- ✅ Cache PSParser results if many files
- ✅ Run checks in parallel when possible
- ✅ Skip non-script file patterns
- ✅ Use native .NET parsing over regex

📊 **Typical Performance**:

- Syntax validation: ~1 min (100 files)
- Security scan: ~1 min
- Registry check: ~30 sec
- Path validation: ~30 sec
- Documentation check: ~30 sec
- **Total: ~4 minutes**

---

## Best Practices

✅ **Do**:

- Write tests for critical scripts
- Document all registry modifications
- Use environment variables for credentials
- Comment complex sections
- Follow PowerShell best practices

❌ **Don't**:

- Hardcode secrets
- Use absolute user paths
- Skip security checks
- Ignore documentation requirements
- Disable workflow checks

---

## Advanced Configuration

### Custom Patterns

To add custom security patterns:

```powershell
$PatternMap = @{
    'password\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded password"
    'connectionstring\s*=\s*[''"][^''\"]*[''"]' = "Hardcoded connection string"
    'YOUR_PATTERN_HERE' = "Your check description"
}
```

### Conditional Checks

```yaml
- name: Run Security Scan
  if: github.event_name == 'pull_request'
  run: |
    # Security scanning logic
```

### Notifications

```yaml
- name: Notify on Failure
  if: failure()
  run: |
    # Send notification to Slack/Teams/Email
```

---

## References

- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Pester Testing Framework](https://pester.dev/)
- [PowerShell Security Best Practices](https://docs.microsoft.com/en-us/powershell/scripting/learn/ps101/09-functions)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
