# Integration Tests Guide - HELIOS Platform v2

## Overview

Integration tests validate interactions between phases and components. They verify that changes in one phase don't break functionality in other phases.

## Integration Testing Philosophy

**Goal:** Ensure phases work together correctly

**Scope:** Test phase interactions, data flow, state transitions

**Execution:** Run after unit tests pass

**Environment:** Controlled test environment with snapshots

## Test Categories

### 1. Phase Transition Tests

**Purpose:** Verify each phase can execute after the previous one

**Pattern:** Phase 0 → Phase 1 → Phase 2 → etc.

#### Phase 0 → Phase 1 Transition

```powershell
Describe "Phase 0 to Phase 1 Transition" {
    
    BeforeAll {
        # Snapshot system before Phase 0
        $Snapshot0 = Capture-SystemSnapshot -Label "Before-Phase-0"
    }
    
    Context "After Phase 0 (Optimization)" {
        
        It "Phase 1 should execute without errors" {
            # Execute Phase 0
            Execute-Phase0
            
            # Verify Phase 0 completed successfully
            $Phase0Result = Get-PhaseExecutionStatus -Phase 0
            $Phase0Result.Status | Should -Be "Success"
            
            # Execute Phase 1
            { Execute-Phase1 } | Should -Not -Throw
        }
        
        It "Phase 1 should not corrupt Phase 0 changes" {
            # Get Phase 0 registry values
            $Phase0Registry = Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase0" -Name "*"
            $Phase0Values = $Phase0Registry | 
                Select-Object -ExpandProperty PSObject.Properties | 
                Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSProvider" }
            
            # Execute Phase 1
            Execute-Phase1
            
            # Verify Phase 0 values unchanged
            $Phase0RegistryAfter = Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase0" -Name "*"
            $Phase0ValuesAfter = $Phase0RegistryAfter | 
                Select-Object -ExpandProperty PSObject.Properties | 
                Where-Object { $_.Name -ne "PSPath" -and $_.Name -ne "PSProvider" }
            
            Compare-Object $Phase0Values $Phase0ValuesAfter | 
                Should -BeNullOrEmpty
        }
        
        It "Phase 1 should have write access to modified files" {
            # Phase 0 may lock files, Phase 1 should still access them
            $Files = Get-ChildItem -Path "C:\Windows\System32" -Filter "HELIOS*"
            
            foreach ($File in $Files) {
                { [IO.File]::Open($File.FullName, 'Open', 'Read') } | 
                    Should -Not -Throw
            }
        }
    }
    
    AfterAll {
        # Restore snapshot if test failed
        if ($LASTEXITCODE -ne 0) {
            Restore-SystemSnapshot -Snapshot $Snapshot0
        }
    }
}
```

#### Phase 1 → Phase 2 Transition

```powershell
Describe "Phase 1 to Phase 2 Transition" {
    
    Context "After Phase 1 (Security)" {
        
        It "Phase 2 should have full monitoring capability" {
            # Verify Phase 1 security settings don't block monitoring
            $MonitoringEnabled = Test-MonitoringAccess
            $MonitoringEnabled | Should -Be $true
        }
        
        It "Phase 2 should not conflict with firewall rules" {
            # Execute Phase 2
            Execute-Phase2
            
            # Verify firewall is functional
            $FirewallStatus = Get-Service -Name MpsSvc
            $FirewallStatus.Status | Should -Be "Running"
        }
        
        It "Phase 2 should respect Phase 1 hardened permissions" {
            # Verify Phase 2 monitoring runs with proper permissions
            $MonitoringService = Get-Service -Name "HELIOS-Monitoring"
            
            # Should run as LocalSystem
            $ProcessUser = Get-ProcessOwner -ProcessName "helios-mon.exe"
            $ProcessUser | Should -Match "SYSTEM|NT AUTHORITY"
        }
    }
}
```

### 2. Component Interaction Tests

**Purpose:** Verify components work together without conflicts

#### Service Interaction Test

```powershell
Describe "Service Interactions" {
    
    Context "When optimization and security services run together" {
        
        It "should not cause service failures" {
            # Start optimization service
            Start-Service -Name "HELIOS-Optimize"
            
            # Start security service
            Start-Service -Name "HELIOS-Security"
            
            # Both should remain running
            $OptiStatus = (Get-Service -Name "HELIOS-Optimize").Status
            $SecStatus = (Get-Service -Name "HELIOS-Security").Status
            
            $OptiStatus | Should -Be "Running"
            $SecStatus | Should -Be "Running"
        }
        
        It "should not consume excessive resources" {
            # Start both services
            Start-Service -Name "HELIOS-Optimize"
            Start-Service -Name "HELIOS-Security"
            
            # Wait for stabilization
            Start-Sleep -Seconds 5
            
            # Check resource usage
            $MemoryUsage = Get-ServiceMemoryUsage -ServiceName "HELIOS-Optimize"
            $MemoryUsage | Should -BeLessThan 500MB  # Limit to 500MB
        }
        
        It "should handle events without deadlock" {
            # Start monitoring
            $MonitoringJob = Start-MonitoringJob
            
            # Trigger optimization event
            Trigger-OptimizationEvent
            
            # Wait for event handling
            Wait-Job -Job $MonitoringJob -Timeout 10
            
            # Should complete within timeout
            $MonitoringJob.State | Should -Be "Completed"
        }
    }
}
```

#### Registry Configuration Interaction Test

```powershell
Describe "Registry Configuration Interactions" {
    
    Context "When multiple phases modify registry" {
        
        It "should not have conflicting values" {
            # Get all registry values set by Phase 0
            $Phase0Values = Get-RegistryValues -Phase 0
            
            # Get all registry values set by Phase 1
            $Phase1Values = Get-RegistryValues -Phase 1
            
            # Check for conflicts (same key with different values)
            $Conflicts = Find-RegistryConflicts -Phase0 $Phase0Values -Phase1 $Phase1Values
            $Conflicts | Should -BeNullOrEmpty
        }
        
        It "should respect priority ordering" {
            # Phase 1 security settings should override Phase 0 if needed
            $Phase0Value = (Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase0" -Name "SecurityLevel").SecurityLevel
            $Phase1Value = (Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase1" -Name "SecurityLevel").SecurityLevel
            
            # Phase 1 (more restrictive) should be >= Phase 0
            $Phase1Value | Should -BeGreaterThanOrEqual $Phase0Value
        }
    }
}
```

### 3. Data Flow Tests

**Purpose:** Verify data passes correctly between components

```powershell
Describe "Data Flow Validation" {
    
    Context "When Phase 0 processes data" {
        
        It "should pass clean data to Phase 1" {
            # Capture Phase 0 output
            $Phase0Output = Capture-PhaseOutput -Phase 0
            
            # Verify output format
            $Phase0Output | Should -HaveCount 0 | Should -Not -BeNullOrEmpty
            $Phase0Output.Keys | Should -Contain @('Status', 'Duration', 'ChangesApplied')
        }
        
        It "should include required metadata" {
            $Data = Get-PhaseData -Phase 0
            
            # Required fields
            $Data.Timestamp | Should -Not -BeNullOrEmpty
            $Data.Version | Should -Match "^\d+\.\d+\.\d+$"
            $Data.HostName | Should -Not -BeNullOrEmpty
        }
        
        It "should handle data transformation correctly" {
            $SourceData = @{
                OldFormat = "value"
                OldField = 123
            }
            
            $TransformedData = Convert-LegacyData -Data $SourceData
            
            $TransformedData | Should -HaveProperty "NewFormat"
            $TransformedData | Should -HaveProperty "NewField"
        }
    }
    
    Context "When data passes through pipeline" {
        
        It "should not lose data integrity" {
            $OriginalData = Generate-TestData -RecordCount 1000
            
            $ProcessedData = foreach ($Record in $OriginalData) {
                Process-DataRecord -Record $Record
            }
            
            $ProcessedData | Should -HaveCount 1000
            ($ProcessedData | Where-Object { $_ -eq $null } | Measure-Object).Count | 
                Should -Be 0  # No null records
        }
        
        It "should maintain data ordering" {
            $OriginalData = @(1..100)
            
            $ProcessedData = Process-DataPipeline -Data $OriginalData
            
            for ($i = 0; $i -lt 100; $i++) {
                $ProcessedData[$i] | Should -Be $OriginalData[$i]
            }
        }
    }
}
```

### 4. Resource Sharing Tests

**Purpose:** Verify phases don't conflict over shared resources

```powershell
Describe "Resource Sharing" {
    
    Context "When phases access shared resources" {
        
        It "should handle file locks correctly" {
            # Phase 0 accesses shared config file
            $ConfigFile = "C:\HELIOS\config.json"
            
            # Lock file from Phase 0 process
            $Phase0Lock = [System.IO.File]::Open($ConfigFile, 'Open', 'Read', 'None')
            
            # Phase 1 should still be able to read (shared lock)
            { [System.IO.File]::Open($ConfigFile, 'Open', 'Read', 'Read') } | 
                Should -Not -Throw
            
            $Phase0Lock.Close()
        }
        
        It "should wait for resource availability" {
            # Start Phase 0 accessing resource
            $Phase0Job = Start-Job { 
                Lock-Resource -Name "PerformanceMonitor"
                Start-Sleep -Seconds 5
            }
            
            # Phase 1 tries to access same resource
            { 
                Lock-Resource -Name "PerformanceMonitor" -Timeout 10
            } | Should -Not -Throw
            
            Wait-Job -Job $Phase0Job
        }
    }
}
```

### 5. State Consistency Tests

**Purpose:** Verify system state remains consistent

```powershell
Describe "State Consistency" {
    
    Context "After all phases complete" {
        
        It "should have consistent registry state" {
            # Collect all registry values
            $AllRegistryValues = @()
            $AllRegistryValues += Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase0" -Name "*"
            $AllRegistryValues += Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase1" -Name "*"
            $AllRegistryValues += Get-ItemProperty -Path "HKLM:\Software\HELIOS\Phase2" -Name "*"
            
            # Check for orphaned references (value points to deleted entry)
            foreach ($Value in $AllRegistryValues) {
                if ($Value -match 'Reference|Ref|Link') {
                    $ReferencedPath = $Value
                    Test-Path -Path $ReferencedPath | Should -Be $true
                }
            }
        }
        
        It "should have consistent service state" {
            $Services = Get-Service -Name "HELIOS-*"
            
            foreach ($Service in $Services) {
                # If service is set to start automatically, it should exist
                if ($Service.StartType -eq "Automatic") {
                    $Service.Status | Should -Be "Running"
                }
            }
        }
        
        It "should have no orphaned processes" {
            $HeliosProcesses = Get-Process -Name "helios*" -ErrorAction SilentlyContinue
            
            foreach ($Process in $HeliosProcesses) {
                # Process should have valid command line
                $Process.CommandLine | Should -Not -BeNullOrEmpty
                
                # Process should have valid parent
                $Process.Parent | Should -Not -BeNullOrEmpty
            }
        }
    }
}
```

## Integration Test Execution

### Running Integration Tests

```powershell
# Run all integration tests
Invoke-Pester -Path ".\tests\*-integration.ps1" -Output Detailed

# Run specific integration test
Invoke-Pester -Path ".\tests\test-phase-transitions-integration.ps1"

# Run with verbose output
Invoke-Pester -Path ".\tests\*-integration.ps1" -Output Verbose
```

### Integration Test Sequence

```
Clean Environment
       ↓
Execute Phase 0
       ↓
Verify Phase 0 Success
       ↓
Execute Phase 1
       ↓
Verify Phase 0 Still OK ✓
       ↓
Verify Phase 1 Success
       ↓
Execute Phase 2
       ↓
Verify Phases 0 & 1 Still OK ✓
       ↓
Verify Phase 2 Success
       ↓
Verify All Data Integrity ✓
       ↓
Verify No Resource Conflicts ✓
```

## Integration Test Templates

### Basic Phase Transition Template

```powershell
Describe "Phase X to Phase Y Transition" {
    
    BeforeAll {
        $Snapshot = Capture-SystemSnapshot -Label "Before-Phase-X-Y"
        Execute-PhaseX
    }
    
    Context "After Phase X execution" {
        
        It "Phase Y should execute without errors" {
            { Execute-PhaseY } | Should -Not -Throw
        }
        
        It "Phase X changes should be preserved" {
            # Verify Phase X registry values
            # Verify Phase X file modifications
            # Verify Phase X service state
        }
    }
    
    AfterAll {
        if ($LASTEXITCODE -ne 0) {
            Restore-SystemSnapshot -Snapshot $Snapshot
        }
    }
}
```

### Cross-Component Interaction Template

```powershell
Describe "Component A and Component B Interaction" {
    
    Context "When Component A and B run simultaneously" {
        
        It "should not cause conflicts" {
            $JobA = Start-Job { Invoke-ComponentA }
            $JobB = Start-Job { Invoke-ComponentB }
            
            $Results = Wait-Job -Job @($JobA, $JobB) -Timeout 30
            $Results.Count | Should -Be 2
        }
        
        It "should have correct state after execution" {
            # Verify Component A state
            # Verify Component B state
            # Verify interaction outcomes
        }
    }
}
```

## Integration Test Best Practices

✓ **Do:**

- Test complete phase sequences
- Verify data persistence across phases
- Check resource availability
- Validate error handling in phase chains
- Use system snapshots for cleanup
- Run integration tests after unit tests pass

✗ **Don't:**

- Mix phases in wrong order
- Skip phase setup/verification
- Assume unit test success means integration success
- Use hardcoded paths for test data
- Leave test artifacts on system

## Success Criteria

Integration tests pass when:

- ✅ All phases execute in sequence without errors
- ✅ Phase changes are preserved after subsequent phases
- ✅ No resource conflicts between phases
- ✅ Data passes correctly between components
- ✅ System state remains consistent
- ✅ All rollback procedures work correctly

---

**Version:** 2.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Development Team
