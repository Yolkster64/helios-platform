# Unit Tests Guide - HELIOS Platform v2

## Overview

Unit tests validate individual functions and components in isolation. They are fast, focused, and run frequently during development.

## Unit Testing Philosophy

**Goal:** Catch bugs early before integration

**Speed:** Each test should run in <1 second

**Scope:** Test one function at a time

**Independence:** Tests don't depend on each other

**Clarity:** Test name describes what it validates

## Unit Test Framework

HELIOS Platform v2 uses **Pester**, PowerShell's native testing framework.

### Installation

```powershell
# Install Pester (if needed)
Install-Module -Name Pester -RequiredVersion 5.4.0 -Force -SkipPublisherCheck
```

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path '.\tests' -Output Detailed

# Run specific test file
Invoke-Pester -Path '.\tests\test-phase-0.ps1' -Output Detailed

# Run with coverage
Invoke-Pester -Path '.\tests' -CodeCoverage '.\Phase-0-Optimize.ps1'

# Run with output to file
Invoke-Pester -Path '.\tests' -OutputFile '.\test-results.xml' -OutputFormat JUnitXml
```

## Unit Test Structure

### Test File Organization

```
tests/
├── test-phase-0-unit.ps1        # Phase 0 unit tests
├── test-phase-1-unit.ps1        # Phase 1 unit tests
├── test-utilities-unit.ps1      # Shared utility tests
└── test-helpers.ps1             # Test helper functions
```

### Naming Convention

| What | Pattern | Example |
|------|---------|---------|
| Test files | `test-[module]-unit.ps1` | `test-phase-0-unit.ps1` |
| Describe blocks | `Describe "[Function Name]"` | `Describe "Optimize-StartupServices"` |
| Test cases | `It "should [do something]"` | `It "should disable DiagTrack service"` |

### Basic Test Structure

```powershell
# test-phase-0-unit.ps1

BeforeAll {
    # Load the script being tested
    . $PSScriptRoot\..\Phase-0-Optimize.ps1
    
    # Import test helpers
    . $PSScriptRoot\test-helpers.ps1
}

Describe "Optimize-StartupServices" {
    Context "When called with valid service names" {
        It "should disable specified services" {
            # Arrange
            $ServiceNames = @("TestService1", "TestService2")
            
            # Act
            Optimize-StartupServices -ServiceNames $ServiceNames
            
            # Assert
            # (Verify expected result)
        }
    }
    
    Context "When called with invalid service name" {
        It "should throw an error" {
            # Arrange
            $InvalidService = "NonExistentService12345"
            
            # Act & Assert
            { Optimize-StartupServices -ServiceNames $InvalidService } | 
                Should -Throw
        }
    }
}
```

## Test Template

Use this template for new unit tests:

```powershell
<#
.SYNOPSIS
    Unit tests for [FunctionName]

.DESCRIPTION
    Tests the [FunctionName] function to ensure it:
    - Validates input parameters
    - Performs expected operations
    - Handles errors gracefully
    - Returns expected output

.NOTES
    Run with: Invoke-Pester -Path '.\tests\test-[module]-unit.ps1'
#>

BeforeAll {
    # Load script being tested
    . $PSScriptRoot\..\Phase-X-[FunctionModule].ps1
    
    # Load helpers
    . $PSScriptRoot\test-helpers.ps1
}

Describe "[FunctionName]" {
    
    Context "When called with valid parameters" {
        It "should [expected behavior]" {
            # Arrange
            $InputParam = "value"
            
            # Act
            $Result = [FunctionName] -Parameter $InputParam
            
            # Assert
            $Result | Should -Be "expected"
        }
    }
    
    Context "When called with invalid parameters" {
        It "should throw [ErrorType]" {
            # Arrange
            $InvalidParam = $null
            
            # Act & Assert
            { [FunctionName] -Parameter $InvalidParam } | 
                Should -Throw -ExceptionType "ErrorMessage"
        }
    }
    
    Context "When called with edge case" {
        It "should handle [edge case]" {
            # Arrange
            $EdgeCaseParam = "special_value"
            
            # Act
            $Result = [FunctionName] -Parameter $EdgeCaseParam
            
            # Assert
            $Result | Should -Not -BeNullOrEmpty
        }
    }
}
```

## Assertion Examples

### String Assertions

```powershell
# Exact match
$Result | Should -Be "Expected Value"

# Contains
$Result | Should -Match "pattern"
$Result | Should -Contain "substring"

# Length
$Result | Should -HaveCount 5
$Result.Length | Should -Be 10

# Null/Empty
$Result | Should -BeNullOrEmpty
$Result | Should -Not -BeNullOrEmpty
```

### Numeric Assertions

```powershell
# Equality
$Count | Should -Be 42
$Count | Should -Not -Be 0

# Comparison
$Duration | Should -BeLessThan 1000
$UsedMemory | Should -BeLessThan 1048576  # 1 MB
$Value | Should -BeGreaterThan 0
```

### File Assertions

```powershell
# File/Directory existence
$Path | Should -Exist
$Path | Should -Not -Exist

# File content
Get-Content $Path | Should -Match "expected"
Get-Content $Path | Should -Contain "value"
```

### Exception Assertions

```powershell
# Should throw
{ Get-Command -Name "NonExistent" } | Should -Throw

# Specific exception type
{ [IO.File]::Delete("C:\nonexistent\file.txt") } | 
    Should -Throw -ExceptionType "System.IO.DirectoryNotFoundException"

# Exception message
{ Write-Error "Custom error" } | Should -Throw -ExpectedMessage "*Custom*"
```

### Registry Assertions

```powershell
# Registry key exists
"HKLM:\Software\Test" | Should -Exist

# Registry value
(Get-ItemProperty -Path "HKLM:\Software\Test" -Name Value).Value | 
    Should -Be 1
```

## Real-World Test Examples

### Example 1: Testing Service Optimization

```powershell
Describe "Optimize-StartupServices" {
    
    BeforeEach {
        # Mock Get-Service to avoid needing real services
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{
                Name = "DiagTrack"
                Status = "Running"
                StartType = "Automatic"
            }
        }
        
        Mock -CommandName Set-Service -MockWith {}
    }
    
    Context "When optimizing startup services" {
        
        It "should disable DiagTrack service" {
            Optimize-StartupServices
            
            Assert-MockCalled -CommandName Set-Service -Times 1 -Scope It
        }
        
        It "should handle already disabled services" {
            Mock -CommandName Get-Service -MockWith {
                [PSCustomObject]@{
                    Name = "DiagTrack"
                    StartType = "Disabled"
                }
            }
            
            { Optimize-StartupServices } | Should -Not -Throw
        }
    }
}
```

### Example 2: Testing Registry Changes

```powershell
Describe "Configure-PerformanceRegistry" {
    
    BeforeEach {
        # Create test registry path
        $TestPath = "HKCU:\Software\HELIOS-Test"
        if (Test-Path $TestPath) { Remove-Item $TestPath -Force }
        New-Item -Path $TestPath -Force | Out-Null
    }
    
    AfterEach {
        # Clean up
        if (Test-Path $TestPath) { Remove-Item $TestPath -Force }
    }
    
    Context "When setting performance registry values" {
        
        It "should create required registry keys" {
            Configure-PerformanceRegistry -RegistryPath $TestPath
            
            Test-Path "$TestPath" | Should -Be $true
        }
        
        It "should set correct DWord values" {
            Configure-PerformanceRegistry -RegistryPath $TestPath
            
            $Value = (Get-ItemProperty -Path $TestPath -Name "TestValue").TestValue
            $Value | Should -Be 1
        }
        
        It "should not modify other registry keys" {
            $OtherPath = "HKCU:\Software\HELIOS-Other"
            New-Item -Path $OtherPath -Force | Out-Null
            Set-ItemProperty -Path $OtherPath -Name "PreExisting" -Value "keep"
            
            Configure-PerformanceRegistry -RegistryPath $TestPath
            
            (Get-ItemProperty -Path $OtherPath -Name "PreExisting").PreExisting | 
                Should -Be "keep"
            
            Remove-Item $OtherPath -Force
        }
    }
}
```

### Example 3: Testing Error Handling

```powershell
Describe "Get-SystemMetrics" {
    
    Context "When system access is denied" {
        
        It "should throw access denied error" {
            Mock -CommandName Get-WmiObject -MockWith {
                throw "Access is denied"
            }
            
            { Get-SystemMetrics } | Should -Throw -ExpectedMessage "*Access*"
        }
    }
    
    Context "When called without parameters" {
        
        It "should return all available metrics" {
            $Metrics = Get-SystemMetrics
            
            $Metrics | Should -Not -BeNullOrEmpty
            $Metrics | Should -HaveCount 4
        }
    }
    
    Context "When called with specific metric name" {
        
        It "should return only requested metric" {
            $Result = Get-SystemMetrics -MetricName "CPU"
            
            $Result.Name | Should -Be "CPU"
        }
        
        It "should throw if metric not found" {
            { Get-SystemMetrics -MetricName "NonExistent" } | 
                Should -Throw
        }
    }
}
```

## Mocking & Stubbing

Use mocks to isolate code being tested:

```powershell
# Mock a command that makes changes
Mock -CommandName Set-Service -MockWith {
    Write-Host "Mock: Set-Service called"
}

# Mock with parameter matching
Mock -CommandName Get-Service -MockWith {
    param($Name)
    if ($Name -eq "DiagTrack") {
        return [PSCustomObject]@{ Name = "DiagTrack"; Status = "Running" }
    }
} -ParameterFilter { $Name -eq "DiagTrack" }

# Assert mock was called
Assert-MockCalled -CommandName Set-Service -Times 1

# Check mock call parameters
Assert-MockCalled -CommandName Set-Service -ParameterFilter {
    $Name -eq "DiagTrack" -and $StartupType -eq "Disabled"
} -Times 1
```

## Test Coverage

### Measuring Coverage

```powershell
# Generate coverage report
$Coverage = @(".\Phase-0-Optimize.ps1")
$Results = Invoke-Pester -Path ".\tests\test-phase-0-unit.ps1" `
    -CodeCoverage $Coverage `
    -PassThru

# Display coverage summary
$Results.CodeCoverage | 
    Select-Object Path, @{N="Lines";E={$_.NumberOfLines}}, `
    @{N="Covered";E={$_.NumberOfCommandsExecuted}}, `
    @{N="Coverage%";E={
        if ($_.NumberOfLines -gt 0) {
            [math]::Round(($_.NumberOfCommandsExecuted / $_.NumberOfLines) * 100)
        } else { 0 }
    }}
```

### Coverage Requirements

- **Minimum:** 80% of code must be covered by unit tests
- **Target:** 90%+ coverage for critical paths
- **Excluded:** Comments, blank lines, not counted

### Coverage Report Example

```
Path                Coverage  Lines  Executed  Missing
────────────────────────────────────────────────────────
Phase-0-Optimize    85%       1200   1020      180
  ├─ Optimize-...   92%       120    110       10
  ├─ Disable-...    78%       450    351       99
  └─ Enable-...     88%       630    559       71

OVERALL:            85%       (Meets 80% minimum ✓)
```

## Running Tests Locally

### Before Committing

```powershell
# Run tests with coverage report
Invoke-Pester -Path ".\tests\test-phase-0-unit.ps1" `
    -CodeCoverage ".\Phase-0-Optimize.ps1" `
    -Output Detailed

# If all pass, safe to commit
```

### CI/CD Integration

Tests automatically run on every commit:

- GitHub Actions triggers on push
- Tests run in parallel
- Results posted to pull request
- Blocks merge if any test fails

## Test Organization by Phase

```
Phase 0 (Optimize)
├── test-phase-0-unit.ps1
│   ├─ Optimize-StartupServices
│   ├─ Disable-TelemetryServices
│   └─ Enable-PerformanceFeatures
└── Coverage: 87%

Phase 1 (Security)
├── test-phase-1-unit.ps1
│   ├─ Enable-DefenderScanning
│   ├─ Configure-WindowsFirewall
│   └─ Harden-SecuritySettings
└── Coverage: 92%

Phase 2 (Monitoring)
├── test-phase-2-unit.ps1
│   ├─ Start-SystemMonitoring
│   ├─ Configure-LogCollection
│   └─ Setup-Alerts
└── Coverage: 88%

OVERALL: 89% (Target met ✓)
```

## Troubleshooting

### Test Fails with "Command Not Found"

```powershell
# Verify the script is being loaded
BeforeAll {
    . $PSScriptRoot\..\Phase-0-Optimize.ps1  # Check path is correct
}
```

### Test Fails Intermittently

```powershell
# May need cleanup or state reset
AfterEach {
    # Reset system state
    # Clean up test data
    # Restore original values
}
```

### Mock Not Being Called

```powershell
# Verify mock is created BEFORE function call
Mock -CommandName SomeCommand -MockWith { ... }

# Then call function
Function-Under-Test

# Then assert
Assert-MockCalled -CommandName SomeCommand
```

### Coverage Shows 0%

```powershell
# Ensure code coverage path is correct
$Coverage = @(".\Phase-0-Optimize.ps1")  # Full path from test directory

# Or use relative to test script
$Coverage = @("$PSScriptRoot\..\Phase-0-Optimize.ps1")
```

## Best Practices

✓ **Do:**

- Test one thing per test
- Use descriptive test names
- Keep tests fast (<100ms each)
- Mock external dependencies
- Verify both success and failure paths
- Clean up test data in AfterEach
- Use BeforeAll for one-time setup

✗ **Don't:**

- Make tests depend on each other
- Test multiple functions in one test
- Use real files/registry in tests
- Create tight coupling to implementation
- Skip error path testing
- Commit with failing tests

## Quick Reference

```powershell
# Template structure
Describe "FunctionName" { }          # Test suite
Context "Scenario" { }               # Test scenario
It "should do X" { }                 # Individual test

# Assertion patterns
Should -Be                           # Equality
Should -Match                        # Regex
Should -Contain                      # In collection
Should -Exist                        # File/registry
Should -Throw                        # Exception
Should -HaveCount                    # Collection size

# Mocking
Mock -CommandName Cmd                # Create mock
Assert-MockCalled -CommandName Cmd   # Verify called

# Running
Invoke-Pester -Path .\tests          # Run all
Invoke-Pester -Path .\test-file.ps1  # Run one
```

---

**Version:** 2.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Development Team
