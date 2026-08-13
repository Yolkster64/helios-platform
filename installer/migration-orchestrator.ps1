# Main Migration Orchestrator and Execution Engine
# Comprehensive migration workflow with all features

. "$PSScriptRoot\migration-core.ps1"
. "$PSScriptRoot\data-transformer.ps1"
. "$PSScriptRoot\version-upgrade.ps1"
. "$PSScriptRoot\parallel-migration.ps1"

# ============================================================================
# MIGRATION ORCHESTRATOR
# ============================================================================

class MigrationOrchestrator {
    $Context
    $BackupManager
    $ConflictResolver
    $Validator
    $UpgradeManager
    $Transformer
    $ProgressTracker
    [bool] $DryRun
    [string] $BackupPath

    MigrationOrchestrator([string]$name, [string]$from, [string]$to) {
        $this.Context = New-Object MigrationContext -ArgumentList $name, $from, $to
        $logPath = "C:\HELIOS\logs\migration_$($this.Context.Id).log"
        $this.ProgressTracker = New-Object MigrationProgressTracker -ArgumentList $logPath
        $this.BackupManager = New-Object BackupManager -ArgumentList "C:\HELIOS\backups", 30
        $this.ConflictResolver = New-Object ConflictResolver -ArgumentList "merge"
        $this.Validator = New-Object ValidationEngine -ArgumentList 'Standard'
        $this.UpgradeManager = New-Object VersionUpgradeManager -ArgumentList $logPath
        $this.Transformer = New-Object DataTransformer -ArgumentList 100
        $this.DryRun = $false
    }

    [void] EnableDryRun([bool]$enable) {
        $this.DryRun = $enable
        $this.Context.DryRun = $enable
    }

    [void] SetParallelWorkers([int]$count) {
        $this.Context.ParallelWorkers = $count
    }

    [void] RegisterUpgrade([string]$from, [string]$to, [scriptblock]$script) {
        $this.UpgradeManager.RegisterUpgrade($from, $to, $script)
    }

    [void] AddFieldMapping([string]$source, [string]$target, [string]$type = "string") {
        $this.Transformer.AddFieldMapping($source, $target, $type)
    }

    [void] AddValidationRule([string]$ruleName, [scriptblock]$rule) {
        $this.Validator.AddRule($ruleName, $rule)
    }

    [void] AddTransformationRule([string]$ruleName, [scriptblock]$rule) {
        $this.Transformer.AddTransformRule($ruleName, $rule)
    }

    [hashtable] ExecuteMigration([hashtable]$data) {
        $migrationResult = @{
            MigrationId = $this.Context.Id
            Name = $this.Context.Name
            SourceVersion = $this.Context.SourceVersion
            TargetVersion = $this.Context.TargetVersion
            DryRun = $this.DryRun
            Success = $false
            Timestamp = Get-Date
            Steps = @()
            BackupPath = $null
            Conflicts = @()
            ValidationResults = @()
            Duration = 0
        }

        $startTime = Get-Date
        $this.Context.State = 'InProgress'
        $this.Context.StartTime = $startTime

        try {
            # STEP 1: Pre-migration validation
            Write-Host "Step 1: Pre-migration validation..." -ForegroundColor Cyan
            $preValidation = $this.Validator.Validate($data)
            $migrationResult.Steps += @{
                Step = "PreValidation"
                Success = $preValidation.Valid
                Details = $preValidation
                Timestamp = Get-Date
            }

            if (-not $preValidation.Valid) {
                throw "Pre-migration validation failed"
            }

            # STEP 2: Create backup
            Write-Host "Step 2: Creating backup..." -ForegroundColor Cyan
            if (-not $this.DryRun) {
                $createdBackupPath = $this.CreateBackup($data)
                $this.BackupPath = $createdBackupPath
                $migrationResult.BackupPath = $createdBackupPath
            }

            $migrationResult.Steps += @{
                Step = "Backup"
                Success = $true
                BackupPath = $this.BackupPath
                Timestamp = Get-Date
            }

            # STEP 3: Execute version upgrade
            Write-Host "Step 3: Executing version upgrade..." -ForegroundColor Cyan
            $upgradeResult = $this.UpgradeManager.ExecuteUpgrade(
                $this.Context.SourceVersion,
                $this.Context.TargetVersion,
                $data,
                $this.DryRun
            )

            if (-not $upgradeResult.Success) {
                throw $upgradeResult.FailureReason
            }

            $migratedData = $data
            $migrationResult.Steps += @{
                Step = "VersionUpgrade"
                Success = $upgradeResult.Success
                Details = $upgradeResult
                Timestamp = Get-Date
            }

            # STEP 4: Data transformation
            Write-Host "Step 4: Transforming data..." -ForegroundColor Cyan
            $transformedData = $this.Transformer.TransformRecord($migratedData)

            $migrationResult.Steps += @{
                Step = "DataTransformation"
                Success = $true
                RecordsProcessed = 1
                Timestamp = Get-Date
            }

            # STEP 5: Conflict detection and resolution
            Write-Host "Step 5: Detecting and resolving conflicts..." -ForegroundColor Cyan
            $conflictSummary = $this.ConflictResolver.GetConflictSummary()

            if ($conflictSummary.UnresolvedConflicts -gt 0) {
                Write-Host "Found $($conflictSummary.UnresolvedConflicts) unresolved conflicts" -ForegroundColor Yellow
                $migrationResult.Conflicts = $conflictSummary
            }

            $migrationResult.Steps += @{
                Step = "ConflictResolution"
                Success = $true
                ConflictSummary = $conflictSummary
                Timestamp = Get-Date
            }

            # STEP 6: Post-migration validation
            Write-Host "Step 6: Post-migration validation..." -ForegroundColor Cyan
            $postValidation = $this.Validator.Validate($transformedData)
            $migrationResult.ValidationResults = $postValidation

            if (-not $postValidation.Valid) {
                throw "Post-migration validation failed"
            }

            $migrationResult.Steps += @{
                Step = "PostValidation"
                Success = $postValidation.Valid
                Details = $postValidation
                Timestamp = Get-Date
            }

            # STEP 7: Finalize migration
            Write-Host "Step 7: Finalizing migration..." -ForegroundColor Cyan
            $this.Context.State = 'Completed'
            $this.Context.ProcessedItems = 1
            $this.Context.FailedItems = 0
            $migrationResult.Success = $true

            Write-Host "Migration completed successfully!" -ForegroundColor Green

        }
        catch {
            Write-Error "Migration failed: $_"
            $this.Context.State = 'Failed'
            $migrationResult.Success = $false
            $migrationResult.Error = $_.Exception.Message

            # Attempt rollback on failure
            if (-not $this.DryRun -and $null -ne $this.BackupPath) {
                Write-Host "Attempting rollback..." -ForegroundColor Yellow
                $this.RollbackMigration()
            }
        }

        $this.Context.EndTime = Get-Date
        $migrationResult.Duration = ($this.Context.EndTime - $startTime).TotalSeconds
        $migrationResult.MigrationContextId = $this.Context.Id

        return $migrationResult
    }

    [string] CreateBackup([hashtable]$data) {
        $backupName = "$($this.Context.Name)_$($this.Context.SourceVersion)_$($this.Context.TargetVersion)"
        
        # Serialize data to temporary file for backup
        $tempDataPath = [System.IO.Path]::GetTempFileName()
        $data | ConvertTo-Json | Set-Content -Path $tempDataPath -Force

        $createdBackupPath = $this.BackupManager.CreateBackup($tempDataPath, $backupName)
        Remove-Item $tempDataPath -Force

        $this.ProgressTracker.Log($this.Context.Id, "Backup created at: $createdBackupPath")
        return $createdBackupPath
    }

    [void] RollbackMigration() {
        try {
            if ($null -eq $this.BackupPath) {
                throw "No backup available for rollback"
            }

            $this.BackupManager.RestoreBackup($this.BackupPath, "C:\HELIOS\rollback")
            $this.Context.State = 'RolledBack'

            Write-Host "Migration rolled back successfully" -ForegroundColor Green
            $this.ProgressTracker.Log($this.Context.Id, "Rollback completed")
        }
        catch {
            Write-Error "Rollback failed: $_"
        }
    }

    [hashtable] GetMigrationStatus() {
        return @{
            MigrationId = $this.Context.Id
            Name = $this.Context.Name
            State = $this.Context.State.ToString()
            Progress = $this.Context.GetProgress()
            StartTime = $this.Context.StartTime
            EndTime = $this.Context.EndTime
            TotalItems = $this.Context.TotalItems
            ProcessedItems = $this.Context.ProcessedItems
            FailedItems = $this.Context.FailedItems
        }
    }

    [void] Dispose() {
        $this.ProgressTracker.Dispose()
    }
}

# ============================================================================
# BULK MIGRATION EXECUTOR
# ============================================================================

class BulkMigrationExecutor {
    [MigrationOrchestrator] $Orchestrator
    $DistributedExecutor
    [bool] $UseParallelExecution
    $ProgressTracker

    BulkMigrationExecutor([MigrationOrchestrator]$orchestrator) {
        $this.Orchestrator = $orchestrator
        $logPath = "C:\HELIOS\logs\bulk_migration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $this.ProgressTracker = New-Object MigrationProgressTracker -ArgumentList $logPath
        $this.UseParallelExecution = $false
    }

    [void] EnableParallelExecution([int]$workers = 4) {
        $logPath = "C:\HELIOS\logs\distributed_migration.log"
        $this.DistributedExecutor = New-Object DistributedMigrationExecutor -ArgumentList @(
            $workers,
            $logPath,
            $this.Orchestrator.Transformer
        )
        $this.UseParallelExecution = $true
    }

    [hashtable] ExecuteBulkMigration([System.Collections.Generic.List[hashtable]]$records) {
        $bulkResult = @{
            TotalRecords = $records.Count
            ProcessedRecords = 0
            SuccessfulRecords = 0
            FailedRecords = 0
            StartTime = Get-Date
            EndTime = $null
            Duration = 0
            ExecutionMode = "Sequential"
            Details = @()
        }

        try {
            if ($this.UseParallelExecution -and $null -ne $this.DistributedExecutor) {
                $bulkResult.ExecutionMode = "Parallel"
                Write-Host "Executing bulk migration in parallel mode..." -ForegroundColor Cyan
                $executionResult = $this.DistributedExecutor.ExecuteDistributedMigration($records)
                $bulkResult.ProcessedRecords = $executionResult.ProcessedRecords
                $bulkResult.SuccessfulRecords = $executionResult.SuccessfulRecords
                $bulkResult.FailedRecords = $executionResult.FailedRecords
            }
            else {
                Write-Host "Executing bulk migration in sequential mode..." -ForegroundColor Cyan
                
                for ($i = 0; $i -lt $records.Count; $i++) {
                    try {
                        $transformed = $this.Orchestrator.Transformer.TransformRecord($records[$i])
                        $bulkResult.SuccessfulRecords++
                        $bulkResult.ProcessedRecords++
                    }
                    catch {
                        $bulkResult.FailedRecords++
                        $bulkResult.ProcessedRecords++
                    }

                    if (($i + 1) % 100 -eq 0) {
                        $this.ProgressTracker.UpdateProgress("bulk-migrate", $i + 1, $records.Count)
                    }
                }
            }
        }
        catch {
            $bulkResult.Error = $_.Exception.Message
        }

        $bulkResult.EndTime = Get-Date
        $bulkResult.Duration = ($bulkResult.EndTime - $bulkResult.StartTime).TotalSeconds

        return $bulkResult
    }

    [void] Dispose() {
        $this.ProgressTracker.Dispose()
        if ($null -ne $this.DistributedExecutor) {
            $this.DistributedExecutor.Dispose()
        }
    }
}

# ============================================================================
# MIGRATION REPORT GENERATOR
# ============================================================================

class MigrationReportGenerator {
    [hashtable] $MigrationResults

    MigrationReportGenerator() {
        $this.MigrationResults = @{}
    }

    [void] AddMigrationResult([string]$migrationId, [hashtable]$result) {
        $this.MigrationResults[$migrationId] = $result
    }

    [string] GenerateHTMLReport() {
        $html = "<html><head><title>HELIOS Migration Report</title></head><body>"
        $html += "<h1>HELIOS Migration Report</h1>"
        $html += "<p>Generated: $(Get-Date)</p>"

        foreach ($migId in $this.MigrationResults.Keys) {
            $result = $this.MigrationResults[$migId]
            $html += "<h2>Migration: $($result.Name)</h2>"
            $html += "<p>Status: $(if ($result.Success) { '<span style="color:green">SUCCESS</span>' } else { '<span style="color:red">FAILED</span>' })</p>"
            $html += "<p>Duration: $($result.Duration) seconds</p>"
            $html += "<p>Source: $($result.SourceVersion) → Target: $($result.TargetVersion)</p>"
        }

        $html += "</body></html>"
        return $html
    }

    [string] GenerateJSONReport() {
        return ConvertTo-Json $this.MigrationResults -Depth 10
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function New-MigrationOrchestrator {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,
        
        [Parameter(Mandatory=$true)]
        [string]$FromVersion,
        
        [Parameter(Mandatory=$true)]
        [string]$ToVersion
    )
    return [MigrationOrchestrator]::new($Name, $FromVersion, $ToVersion)
}

function New-BulkMigrationExecutor {
    param(
        [Parameter(Mandatory=$true)]
        [MigrationOrchestrator]$Orchestrator
    )
    return [BulkMigrationExecutor]::new($Orchestrator)
}

function New-MigrationReportGenerator {
    return [MigrationReportGenerator]::new()
}

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

Export-ModuleMember -Class MigrationOrchestrator, BulkMigrationExecutor, MigrationReportGenerator
Export-ModuleMember -Function New-MigrationOrchestrator, New-BulkMigrationExecutor, New-MigrationReportGenerator
