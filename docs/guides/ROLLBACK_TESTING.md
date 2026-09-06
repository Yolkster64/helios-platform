# Rollback Testing - HELIOS Platform v2

## Overview

Rollback testing ensures every HELIOS phase can be safely reversed if needed. All phase deployments must have tested rollback capability.

## Rollback Testing Philosophy

**Goal:** Ensure safe recovery from any phase execution

**Coverage:** Test rollback of each phase independently

**Automation:** All rollback procedures must be automated and regularly tested

**Verification:** Rollback success must be measurable

## Rollback Point Strategy

### Pre-Execution Snapshots

Before executing any phase:

1. Export all relevant registry hives
2. Backup critical files
3. Document service configuration
4. Capture system performance metrics

### Rollback Snapshot Contents

```
rollback-phase-0/
├── registry-phase0.reg       # Registry backup
├── registry-phase1.reg       # Other phase registries
├── registry-phase2.reg
├── critical-files.zip        # Backup of C:\HELIOS, C:\ProgramData\HELIOS
├── services-config.json      # Service states and startup types
└── snapshot-manifest.json    # Complete snapshot metadata
```

## Creating Rollback Snapshots

```powershell
function Create-RollbackSnapshot {
    param([int]$Phase, [string]$Label = "Rollback")
    
    $SnapshotPath = "C:\HELIOS\rollback\Phase-$Phase-$Label"
    New-Item -Path $SnapshotPath -ItemType Directory -Force | Out-Null
    
    Write-Host "Creating rollback snapshot for Phase $Phase..."
    
    # Export registry hives
    foreach ($Hive in @("Phase0", "Phase1", "Phase2")) {
        $RegPath = "HKLM:\Software\HELIOS\$Hive"
        if (Test-Path $RegPath) {
            reg export "$RegPath" "$SnapshotPath\registry-$Hive.reg" /y | Out-Null
        }
    }
    
    # Backup critical directories
    @("C:\HELIOS", "C:\ProgramData\HELIOS") | 
        Where-Object { Test-Path $_ } |
        ForEach-Object {
            $DirName = (Split-Path $_ -Leaf)
            Compress-Archive -Path $_ -DestinationPath "$SnapshotPath\$DirName.zip" -Force
        }
    
    # Save service configuration
    Get-Service -Name "HELIOS*" -ErrorAction SilentlyContinue | 
        Select-Object Name, Status, StartType, DisplayName |
        ConvertTo-Json | Set-Content "$SnapshotPath\services.json"
    
    # Save manifest
    @{
        Timestamp = Get-Date
        Phase = $Phase
        Label = $Label
        Hostname = $env:COMPUTERNAME
    } | ConvertTo-Json | Set-Content "$SnapshotPath\manifest.json"
    
    Write-Host "✓ Snapshot created: $SnapshotPath"
    return $SnapshotPath
}
```

## Executing Rollback

```powershell
function Restore-Phase {
    param([int]$Phase, [string]$SnapshotPath)
    
    Write-Host "Rolling back Phase $Phase..."
    
    $Manifest = Get-Content "$SnapshotPath\manifest.json" | ConvertFrom-Json
    
    # Restore registry
    Write-Host "Restoring registry..."
    Get-ChildItem "$SnapshotPath\registry-*.reg" | ForEach-Object {
        reg import $_.FullName 2>&1 | Out-Null
    }
    
    # Restore files
    Write-Host "Restoring files..."
    Get-ChildItem "$SnapshotPath\*.zip" | ForEach-Object {
        $Parent = Split-Path ($_.BaseName) -Parent
        Expand-Archive -Path $_.FullName -DestinationPath "C:\" -Force
    }
    
    # Restore services
    Write-Host "Restoring services..."
    if (Test-Path "$SnapshotPath\services.json") {
        $Services = Get-Content "$SnapshotPath\services.json" | ConvertFrom-Json
        foreach ($Svc in $Services) {
            Set-Service -Name $Svc.Name -StartupType $Svc.StartType -ErrorAction SilentlyContinue
            if ($Svc.Status -eq "Running") {
                Start-Service -Name $Svc.Name -ErrorAction SilentlyContinue
            }
        }
    }
    
    Write-Host "✓ Rollback complete for Phase $Phase"
}
```

## Rollback Testing

### Unit Rollback Test Template

```powershell
Describe "Phase X Rollback" {
    
    BeforeAll {
        $Snapshot = Create-RollbackSnapshot -Phase X -Label "Test"
    }
    
    Context "When rolling back changes" {
        
        It "should restore registry values" {
            $OriginalValue = (Get-ItemProperty "HKLM:\Software\HELIOS\PhaseX" -Name "TestKey").TestKey
            
            Set-ItemProperty "HKLM:\Software\HELIOS\PhaseX" -Name "TestKey" -Value "Modified"
            Restore-Phase -Phase X -SnapshotPath $Snapshot
            
            $RestoredValue = (Get-ItemProperty "HKLM:\Software\HELIOS\PhaseX" -Name "TestKey").TestKey
            $RestoredValue | Should -Be $OriginalValue
        }
        
        It "should restore service states" {
            $Original = Get-Service -Name "HELIOS-Service"
            $OriginalState = @{
                Status = $Original.Status
                StartType = $Original.StartType
            }
            
            Stop-Service -Name "HELIOS-Service" -Force
            Set-Service -Name "HELIOS-Service" -StartupType Disabled
            
            Restore-Phase -Phase X -SnapshotPath $Snapshot
            
            $Restored = Get-Service -Name "HELIOS-Service"
            $Restored.StartType | Should -Be $OriginalState.StartType
        }
        
        It "should have no errors after rollback" {
            Restore-Phase -Phase X -SnapshotPath $Snapshot
            
            $RecentErrors = Get-EventLog -LogName System -Newest 50 | 
                Where-Object { $_.EntryType -eq "Error" -and 
                             $_.TimeGenerated -gt (Get-Date).AddMinutes(-5) }
            
            $RecentErrors | Should -BeNullOrEmpty
        }
    }
    
    AfterAll {
        Remove-Item -Path $Snapshot -Recurse -Force
    }
}
```

## Rollback Verification

```powershell
function Verify-RollbackSuccess {
    param([string]$SnapshotPath)
    
    Write-Host "Verifying rollback success..."
    
    $Checks = @()
    
    # Check registry
    $Checks += @{
        Check = "Registry restored"
        Pass = (Get-ItemProperty "HKLM:\Software\HELIOS\Phase0" -Name "*" -ErrorAction SilentlyContinue) -ne $null
    }
    
    # Check services
    $Checks += @{
        Check = "Services running"
        Pass = (Get-Service -Name "HELIOS-*" -ErrorAction SilentlyContinue | 
               Where-Object Status -eq "Running" | Measure-Object).Count -gt 0
    }
    
    # Check critical files
    $Checks += @{
        Check = "Critical files present"
        Pass = (Test-Path "C:\HELIOS") -and (Test-Path "C:\ProgramData\HELIOS")
    }
    
    # Check system health
    $Checks += @{
        Check = "No recent errors"
        Pass = (Get-EventLog -LogName System -Newest 50 | 
               Where-Object { $_.EntryType -eq "Error" -and 
                            $_.TimeGenerated -gt (Get-Date).AddMinutes(-5) } |
               Measure-Object).Count -eq 0
    }
    
    Write-Host ""
    Write-Host "Verification Results:"
    $Checks | ForEach-Object {
        $Status = if ($_.Pass) { "✓" } else { "✗" }
        Write-Host "  $Status $($_.Check)"
    }
    
    $AllPass = $Checks | Where-Object Pass -eq $false
    if ($AllPass) {
        Write-Host "✗ Rollback verification FAILED"
        return $false
    }
    else {
        Write-Host "✓ Rollback verification PASSED"
        return $true
    }
}
```

## Continuous Rollback Testing

```powershell
function Test-RollbackProcedure {
    param(
        [int]$Iterations = 3,
        [int]$Phase = 0
    )
    
    Write-Host "Testing rollback procedure ($Iterations iterations)..."
    
    $Results = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        Write-Host ""
        Write-Host "Iteration $i/$Iterations"
        
        # Create snapshot
        $Snapshot = Create-RollbackSnapshot -Phase $Phase -Label "Test-$i"
        
        # Perform rollback
        Restore-Phase -Phase $Phase -SnapshotPath $Snapshot
        
        # Verify
        $Success = Verify-RollbackSuccess -SnapshotPath $Snapshot
        
        $Results += @{
            Iteration = $i
            Success = $Success
            Timestamp = Get-Date
        }
        
        Remove-Item -Path $Snapshot -Recurse -Force
        
        Write-Host "Result: $(if ($Success) { '✓ PASS' } else { '✗ FAIL' })"
        
        Start-Sleep -Seconds 30
    }
    
    $PassCount = ($Results | Where-Object Success).Count
    Write-Host ""
    Write-Host "Summary: $PassCount/$Iterations rollback tests passed"
    
    return $Results
}
```

## Rollback Procedures by Phase

### Phase 0 Rollback (Optimization)

Disables optimizations applied in Phase 0:

- Re-enables diagnostic services
- Restores service startup types
- Removes performance registry settings
- Time: 2-3 minutes

### Phase 1 Rollback (Security)

Reverses security hardening:

- Disables firewall rules added by Phase 1
- Restores UAC settings
- Re-enables previously disabled security policies
- Time: 2-3 minutes

### Phase 2 Rollback (Monitoring)

Removes monitoring infrastructure:

- Stops monitoring service
- Removes monitoring registry entries
- Deletes log collection schedules
- Time: 1-2 minutes

## Rollback Decision Tree

```
Phase Execution Failed
        ↓
YES → Automatic Rollback Triggered
        ↓
Create Snapshot (if not auto-backed)
        ↓
Restore Registry
        ↓
Restore Files
        ↓
Restore Services
        ↓
Verify Success
        ↓
LOG ALL ACTIONS
        ↓
ALERT ADMIN
```

## Best Practices

✓ **Do:**

- Create snapshot BEFORE executing phase
- Test rollback procedures regularly
- Verify all snapshots have integrity checks
- Log all rollback actions
- Notify administrators of rollbacks
- Document rollback reasons

✗ **Don't:**

- Skip snapshot creation
- Assume rollback will work without testing
- Delete old snapshots without archiving
- Rollback without verification
- Execute phase without rollback plan

---

**Version:** 2.0  
**Last Updated:** 2024  
**Maintained By:** HELIOS Development Team
