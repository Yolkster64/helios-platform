# HELIOS Platform - Migration and Upgrade Tools

## Comprehensive Guide

### Overview

The HELIOS Platform Migration Tools provide a complete framework for:

- Migrating from old to new architecture
- Version upgrades (v1→v2→v3, etc)
- Backup creation and rollback
- Data validation and conflict resolution
- Progress tracking and dry-run testing
- Parallel and incremental migration

### Key Components

#### 1. **Migration Core** (`migration-core.ps1`)

Base classes and utilities for all migration operations.

**Classes:**

- `MigrationContext` - Tracks migration state and progress
- `MigrationProgressTracker` - Logs progress and timing
- `BackupManager` - Creates and manages backups
- `ConflictResolver` - Handles data conflicts
- `ValidationEngine` - Pre/post migration validation

#### 2. **Data Transformer** (`data-transformer.ps1`)

Transforms data between different formats and schemas.

**Classes:**

- `DataTransformer` - Field mapping and type conversion
- `SchemaTransformer` - Schema-based transformation
- `VersionMigrationCoordinator` - Finds migration paths
- `BulkTransformer` - Batch processing

#### 3. **Version Upgrade** (`version-upgrade.ps1`)

Manages incremental version upgrades.

**Classes:**

- `VersionUpgradeManager` - Orchestrates version upgrades
- `IncrementalUpgradeOrchestrator` - Phased upgrades
- `UpgradeVerifier` - Pre/post upgrade verification

#### 4. **Parallel Migration** (`parallel-migration.ps1`)

Distributes work across multiple workers.

**Classes:**

- `ParallelMigrationWorker` - Individual worker
- `ParallelMigrationCoordinator` - Manages workers
- `DistributedMigrationExecutor` - Distributed execution
- `WorkDistributionEngine` - Task distribution

#### 5. **Migration Orchestrator** (`migration-orchestrator.ps1`)

Complete migration workflow controller.

**Classes:**

- `MigrationOrchestrator` - Main controller
- `BulkMigrationExecutor` - Bulk operations
- `MigrationReportGenerator` - Report generation

---

## Quick Start Guide

### Basic Migration (Step-by-Step)

```powershell
# Import the orchestrator
. "C:\HELIOS\migration-orchestrator.ps1"

# 1. Create a migration orchestrator
$migration = New-MigrationOrchestrator `
    -Name "MyDataMigration" `
    -FromVersion "v1" `
    -ToVersion "v2"

# 2. Define field mappings
$migration.AddFieldMapping("old_field", "new_field", "string")
$migration.AddFieldMapping("old_count", "new_count", "int")

# 3. Add validation rules
$migration.AddValidationRule("NotEmpty", {
    param($data)
    return @{
        Passed = -not [string]::IsNullOrEmpty($data.new_field)
        Message = "Field must not be empty"
    }
})

# 4. Register version upgrade
$upgrade = {
    param($data)
    $data['Version'] = 'v2'
    $data['MigratedAt'] = Get-Date
    return $data
}
$migration.RegisterUpgrade("v1", "v2", $upgrade)

# 5. Execute migration
$data = @{ old_field = "value"; old_count = 42 }
$result = $migration.ExecuteMigration($data)

# 6. Check results
Write-Host "Success: $($result.Success)"
Write-Host "Duration: $($result.Duration) seconds"
Write-Host "Backup: $($result.BackupPath)"

# 7. Cleanup
$migration.Dispose()
```

### Dry-Run Mode (Test without Making Changes)

```powershell
$migration = New-MigrationOrchestrator -Name "Test" -FromVersion "v1" -ToVersion "v2"

# Enable dry-run mode
$migration.EnableDryRun($true)

# Run migration (no changes persisted)
$result = $migration.ExecuteMigration($data)

Write-Host "Dry-run completed. No changes were made."
$migration.Dispose()
```

### Bulk Migration with Parallel Processing

```powershell
$migration = New-MigrationOrchestrator -Name "BulkMigration" -FromVersion "v1" -ToVersion "v2"

# Add field mappings
$migration.AddFieldMapping("id", "Id", "int")
$migration.AddFieldMapping("name", "Name", "string")

# Create bulk executor with parallel support
$bulk = New-BulkMigrationExecutor -Orchestrator $migration
$bulk.EnableParallelExecution(4)  # Use 4 parallel workers

# Prepare records
$records = [System.Collections.Generic.List[hashtable]]::new()
for ($i = 0; $i -lt 1000; $i++) {
    $records.Add(@{ id = $i; name = "Item_$i" })
}

# Execute bulk migration
$result = $bulk.ExecuteBulkMigration($records)

Write-Host "Processed: $($result.ProcessedRecords)"
Write-Host "Successful: $($result.SuccessfulRecords)"
Write-Host "Failed: $($result.FailedRecords)"
Write-Host "Duration: $($result.Duration) seconds"
Write-Host "Mode: $($result.ExecutionMode)"

$bulk.Dispose()
$migration.Dispose()
```

### Multi-Step Version Upgrade (v1→v2→v3)

```powershell
$migration = New-MigrationOrchestrator -Name "MultiStep" -FromVersion "v1" -ToVersion "v3"

# Register v1 → v2 upgrade
$migration.RegisterUpgrade("v1", "v2", {
    param($data)
    $data['Version'] = 'v2'
    $data['NewField'] = $data['OldField']
    return $data
})

# Register v2 → v3 upgrade
$migration.RegisterUpgrade("v2", "v3", {
    param($data)
    $data['Version'] = 'v3'
    $data['NewField2'] = "upgraded"
    return $data
})

# Execute - will automatically upgrade v1→v2→v3
$data = @{ OldField = "value"; Version = 'v1' }
$result = $migration.ExecuteMigration($data)

$migration.Dispose()
```

### Incremental Phased Migration

```powershell
$migration = New-MigrationOrchestrator -Name "Phased" -FromVersion "v1" -ToVersion "v2"

$upgradeManager = New-VersionUpgradeManager -LogPath "C:\HELIOS\logs\phases.log"
$upgradeManager.RegisterUpgrade("v1", "v2", {
    param($data)
    $data['Phased'] = $true
    return $data
})

$phased = New-IncrementalUpgradeOrchestrator -UpgradeManager $upgradeManager

# Define phases
$phased.DefineMigrationPhase(1, "Phase 1: Users", @("users"), {
    param($result)
    return @{ Valid = $result.Success }
})

$phased.DefineMigrationPhase(2, "Phase 2: Transactions", @("transactions"), {
    param($result)
    return @{ Valid = $result.Success }
})

# Execute phases
$data = @{
    users = @(@{ id = 1; name = "User1" })
    transactions = @(@{ id = 1; amount = 100 })
}

$result = $phased.ExecutePhased("v1", "v2", $data)
Write-Host "Phases: $($result.PhasesCompleted)/$($result.PhasesTotal)"
Write-Host "Success: $($result.Success)"
```

### Rollback on Failure

```powershell
$migration = New-MigrationOrchestrator -Name "Test" -FromVersion "v1" -ToVersion "v2"

# Add a validation rule that will fail
$migration.AddValidationRule("RequireField", {
    param($data)
    return @{
        Passed = $false
        Message = "Intentional failure"
    }
})

# Execute - will fail and trigger automatic rollback
$result = $migration.ExecuteMigration(@{ id = 1 })

if (-not $result.Success) {
    Write-Host "Migration failed and was rolled back: $($result.Error)"
    # Backup can be manually restored from $result.BackupPath
}

$migration.Dispose()
```

---

## Advanced Features

### Custom Data Transformation

```powershell
# Create custom transformer
$transformer = New-DataTransformer -BatchSize 50

# Add field mapping
$transformer.AddFieldMapping("source_field", "target_field", "string")

# Add custom transformation rule
$transformer.AddTransformationRule("CustomLogic", {
    param($source, $target)
    
    # Apply custom logic
    if ($source.ContainsKey("special_field")) {
        $target.processed = $source.special_field.ToUpper()
    }
    
    return $target
})

# Add custom type converter
$transformer.AddCustomConverter("custom", {
    param($value)
    # Custom conversion logic
    return "converted_$value"
})

$result = $transformer.TransformRecord(@{ source_field = "test" })
```

### Conflict Resolution

```powershell
# Create conflict resolver
$resolver = [ConflictResolver]::new("merge")  # Options: "keepOld", "keepNew", "merge", "manual"

# Log conflicts
$resolver.LogConflict("item1", @{value = "old"}, @{value = "new"}, "Data changed during migration")

# Resolve conflicts
$resolved = $resolver.ResolveConflict("item1", 0)

# Get conflict summary
$summary = $resolver.GetConflictSummary()
Write-Host "Total conflicts: $($summary.TotalConflicts)"
Write-Host "Resolved: $($summary.ResolvedConflicts)"
```

### Progress Tracking

```powershell
$tracker = [MigrationProgressTracker]::new("C:\HELIOS\logs\progress.log")

# Log migration events
$tracker.Log("migration-id", "Migration started")
$tracker.UpdateProgress("migration-id", 50, 100)  # 50 of 100 items
$tracker.Log("migration-id", "Migration completed")

# Get tracker info
$info = $tracker.GetTrackerInfo("migration-id")
Write-Host "Items processed: $($info.ItemsProcessed) / $($info.TotalItems)"

$tracker.Dispose()
```

### Pre/Post Migration Validation

```powershell
$verifier = New-UpgradeVerifier

# Add pre-upgrade checks
$verifier.AddPreCheck("DataIntegrity", {
    param($data)
    return @{
        Passed = -not [string]::IsNullOrEmpty($data.id)
        Message = "ID field required"
    }
})

# Add post-upgrade checks
$verifier.AddPostCheck("VersionCheck", {
    param($data)
    return @{
        Passed = $data.Upgraded.Version -eq 'v2'
        Message = "Version should be v2 after upgrade"
    }
})

# Run verification
$preResults = $verifier.VerifyPreUpgrade($originalData)
$postResults = $verifier.VerifyPostUpgrade($originalData, $upgradedData)

Write-Host "All checks passed: $($preResults.AllPassed)"
```

---

## Error Handling

All scripts include comprehensive error handling:

```powershell
try {
    $migration = New-MigrationOrchestrator -Name "Test" -FromVersion "v1" -ToVersion "v2"
    
    $result = $migration.ExecuteMigration($data)
    
    if ($result.Success) {
        Write-Host "Migration successful"
    }
    else {
        Write-Host "Migration failed: $($result.Error)"
        if ($null -ne $result.BackupPath) {
            Write-Host "Backup available at: $($result.BackupPath)"
        }
    }
}
catch {
    Write-Error "Unexpected error: $_"
}
finally {
    $migration.Dispose()
}
```

---

## Logging

All operations are logged to:

- **Migration logs**: `C:\HELIOS\logs\migration_<id>.log`
- **Bulk migration**: `C:\HELIOS\logs\bulk_migration_<timestamp>.log`
- **Distributed migration**: `C:\HELIOS\logs\distributed_migration.log`
- **Backups**: `C:\HELIOS\backups\`

View logs:

```powershell
Get-Content "C:\HELIOS\logs\migration_*.log" -Tail 50
```

---

## Performance Considerations

### Parallel Processing

- Use 4-8 workers for optimal performance
- More workers = higher CPU usage but faster processing
- Adjust based on system resources

### Batch Size

- Default: 100 records per batch
- Increase for large simple transformations
- Decrease for complex transformations

### Incremental Migration

- Split large migrations into phases
- Test each phase before proceeding
- Allows for rollback at phase boundaries

---

## Troubleshooting

### Migration Fails

1. Check logs: `Get-Content C:\HELIOS\logs\migration_<id>.log`
2. Run dry-run: `$migration.EnableDryRun($true)`
3. Verify backup exists: Check `C:\HELIOS\backups\`
4. Manual rollback if needed

### Slow Performance

1. Enable parallel execution: `$bulk.EnableParallelExecution(8)`
2. Increase batch size: `$executor.SetChunkSize(500)`
3. Check system resources (CPU, Memory)

### Data Conflicts

1. Review conflict log: `$resolver.GetConflictSummary()`
2. Change resolution strategy: "keepNew", "merge", etc
3. Implement custom conflict resolution

---

## Examples

See `migration-examples.ps1` for working examples:

```powershell
. "C:\HELIOS\migration-examples.ps1"

# Run examples
Invoke-SimpleMigration
Invoke-DryRunMigration
Invoke-ParallelBulkMigration
Invoke-MultiStepUpgrade
Invoke-IncrementalPhasedMigration
Invoke-RollbackScenario
Invoke-GenerateReport
```

---

## Best Practices

1. **Always use dry-run first** - Test before production
2. **Create backups** - Automatic but verify they exist
3. **Validate data** - Add pre/post migration validation
4. **Monitor progress** - Use progress tracking for large migrations
5. **Phase large migrations** - Don't migrate everything at once
6. **Document transformations** - Include comments in upgrade scripts
7. **Test rollback** - Verify rollback process works before production
8. **Use version graphs** - Define clear upgrade paths
9. **Handle conflicts** - Plan conflict resolution strategy
10. **Log everything** - Review logs for issues

---

## Summary

The HELIOS Migration Tools provide a complete, production-ready solution for:
✓ Data migrations between architectures
✓ Version upgrades with automatic path finding
✓ Backup and rollback
✓ Conflict detection and resolution
✓ Data validation
✓ Progress tracking
✓ Parallel execution
✓ Incremental phased migration
✓ Comprehensive error handling
✓ Detailed logging and reporting

All scripts use PowerShell best practices with proper error handling, resource cleanup, and logging.
