# HELIOS Migration Framework Core
# Provides base classes and utilities for migration operations

# ============================================================================
# CONFIGURATION AND ENUMS
# ============================================================================

enum MigrationState {
    NotStarted = 0
    InProgress = 1
    Paused = 2
    Completed = 3
    Failed = 4
    RolledBack = 5
}

enum ValidationLevel {
    None = 0
    Basic = 1
    Standard = 2
    Strict = 3
}

# ============================================================================
# MIGRATION CONTEXT CLASS
# ============================================================================

class MigrationContext {
    [string] $Id
    [string] $Name
    [string] $SourceVersion
    [string] $TargetVersion
    [MigrationState] $State
    [hashtable] $Metadata
    [DateTime] $StartTime
    [DateTime] $EndTime
    [string] $BackupPath
    [int] $TotalItems
    [int] $ProcessedItems
    [int] $FailedItems
    [string[]] $ConflictLog
    [hashtable] $ValidationResults
    [bool] $DryRun
    [int] $ParallelWorkers
    [int] $CurrentPhase
    [int] $TotalPhases

    MigrationContext([string]$name, [string]$source, [string]$target) {
        $this.Id = [guid]::NewGuid().ToString()
        $this.Name = $name
        $this.SourceVersion = $source
        $this.TargetVersion = $target
        $this.State = [MigrationState]::NotStarted
        $this.Metadata = @{}
        $this.ConflictLog = @()
        $this.ValidationResults = @{}
        $this.DryRun = $false
        $this.ParallelWorkers = 4
        $this.CurrentPhase = 0
        $this.TotalPhases = 1
    }

    [hashtable] ToHashtable() {
        return @{
            Id = $this.Id
            Name = $this.Name
            SourceVersion = $this.SourceVersion
            TargetVersion = $this.TargetVersion
            State = $this.State.ToString()
            StartTime = $this.StartTime
            EndTime = $this.EndTime
            TotalItems = $this.TotalItems
            ProcessedItems = $this.ProcessedItems
            FailedItems = $this.FailedItems
            Progress = $this.GetProgress()
            DryRun = $this.DryRun
            BackupPath = $this.BackupPath
        }
    }

    [double] GetProgress() {
        if ($this.TotalItems -eq 0) { return 0 }
        return [math]::Round(($this.ProcessedItems / $this.TotalItems) * 100, 2)
    }
}

# ============================================================================
# MIGRATION PROGRESS TRACKER
# ============================================================================

class MigrationProgressTracker {
    [hashtable] $Trackers
    [string] $LogPath
    [System.IO.StreamWriter] $LogWriter

    MigrationProgressTracker([string]$logPath) {
        $this.Trackers = @{}
        $this.LogPath = $logPath
        $this.InitializeLogging()
    }

    [void] InitializeLogging() {
        try {
            $logDir = Split-Path -Parent $this.LogPath
            if (-not (Test-Path $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $this.LogWriter = [System.IO.StreamWriter]::new($this.LogPath, $true)
            $this.LogWriter.AutoFlush = $true
        }
        catch {
            Write-Error "Failed to initialize logging: $_"
        }
    }

    [void] Log([string]$migrationId, [string]$message) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        $logEntry = "[$timestamp] [$migrationId] $message"
        
        try {
            $this.LogWriter.WriteLine($logEntry)
        }
        catch {
            Write-Host $logEntry
        }

        if ($this.Trackers.ContainsKey($migrationId)) {
            $this.Trackers[$migrationId]['LastUpdate'] = Get-Date
        }
    }

    [void] UpdateProgress([string]$migrationId, [int]$processed, [int]$total) {
        if (-not $this.Trackers.ContainsKey($migrationId)) {
            $this.Trackers[$migrationId] = @{
                StartTime = Get-Date
                LastUpdate = Get-Date
                ItemsProcessed = 0
                TotalItems = $total
                ItemsFailed = 0
            }
        }

        $tracker = $this.Trackers[$migrationId]
        $tracker.ItemsProcessed = $processed
        $tracker.TotalItems = $total
        $tracker.LastUpdate = Get-Date

        $progress = [math]::Round(($processed / $total) * 100, 2)
        $elapsed = ((Get-Date) - $tracker.StartTime).TotalSeconds
        
        if ($processed -gt 0) {
            $rate = $processed / $elapsed
            $remaining = [math]::Max(0, ($total - $processed) / $rate)
            $this.Log($migrationId, "Progress: $progress% ($processed/$total) - Rate: $([math]::Round($rate, 2)) items/sec - ETA: $([int]$remaining)s")
        }
    }

    [hashtable] GetTrackerInfo([string]$migrationId) {
        if ($this.Trackers.ContainsKey($migrationId)) {
            return $this.Trackers[$migrationId]
        }
        return $null
    }

    [void] Dispose() {
        if ($this.LogWriter) {
            $this.LogWriter.Dispose()
        }
    }
}

# ============================================================================
# BACKUP MANAGER
# ============================================================================

class BackupManager {
    [string] $BackupBasePath
    [int] $RetentionDays

    BackupManager([string]$basePath, [int]$retentionDays = 30) {
        $this.BackupBasePath = $basePath
        $this.RetentionDays = $retentionDays
        $this.EnsureBackupDirectory()
    }

    [void] EnsureBackupDirectory() {
        if (-not (Test-Path $this.BackupBasePath)) {
            New-Item -ItemType Directory -Path $this.BackupBasePath -Force | Out-Null
        }
    }

    [string] CreateBackup([string]$sourceData, [string]$backupName) {
        try {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupDir = Join-Path $this.BackupBasePath "backup_${backupName}_${timestamp}"
            
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

            # Create manifest
            $manifest = @{
                BackupName = $backupName
                Timestamp = Get-Date
                SourcePath = $sourceData
                DataHash = (Get-FileHash $sourceData -Algorithm SHA256).Hash
                ItemCount = 0
            }

            # Copy data with structure preservation
            if (Test-Path $sourceData -PathType Container) {
                Copy-Item -Path $sourceData -Destination $backupDir -Recurse -Force
                $manifest.ItemCount = @(Get-ChildItem -Path $backupDir -Recurse).Count
            }
            else {
                Copy-Item -Path $sourceData -Destination $backupDir -Force
                $manifest.ItemCount = 1
            }

            # Save manifest
            $manifest | ConvertTo-Json | Set-Content -Path (Join-Path $backupDir "manifest.json") -Force
            
            Write-Host "Backup created: $backupDir" -ForegroundColor Green
            return $backupDir
        }
        catch {
            Write-Error "Backup creation failed: $_"
            throw
        }
    }

    [void] RestoreBackup([string]$backupPath, [string]$restoreTarget) {
        try {
            if (-not (Test-Path $backupPath)) {
                throw "Backup not found: $backupPath"
            }

            $manifest = Get-Content (Join-Path $backupPath "manifest.json") | ConvertFrom-Json
            
            # Clear target
            if (Test-Path $restoreTarget) {
                Remove-Item -Path $restoreTarget -Recurse -Force
            }

            # Restore data
            New-Item -ItemType Directory -Path (Split-Path -Parent $restoreTarget) -Force | Out-Null
            Copy-Item -Path $backupPath\* -Destination $restoreTarget -Recurse -Force -Exclude "manifest.json"
            
            Write-Host "Restored from backup: $backupPath to $restoreTarget" -ForegroundColor Green
        }
        catch {
            Write-Error "Restore failed: $_"
            throw
        }
    }

    [void] CleanupOldBackups() {
        try {
            $cutoffDate = (Get-Date).AddDays(-$this.RetentionDays)
            $oldBackups = Get-ChildItem -Path $this.BackupBasePath -Directory | 
                Where-Object { $_.CreationTime -lt $cutoffDate }

            foreach ($backup in $oldBackups) {
                Remove-Item -Path $backup.FullName -Recurse -Force
                Write-Host "Removed old backup: $($backup.Name)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error "Cleanup failed: $_"
        }
    }

    [hashtable] GetBackupInfo([string]$backupPath) {
        $manifest = Get-Content (Join-Path $backupPath "manifest.json") | ConvertFrom-Json
        return @{
            Name = $manifest.BackupName
            Timestamp = $manifest.Timestamp
            ItemCount = $manifest.ItemCount
            Size = (Get-ChildItem -Path $backupPath -Recurse | Measure-Object -Property Length -Sum).Sum
            Path = $backupPath
        }
    }
}

# ============================================================================
# CONFLICT RESOLVER
# ============================================================================

class ConflictResolver {
    [hashtable] $ConflictLog
    [string] $ResolutionStrategy

    ConflictResolver([string]$strategy = "manual") {
        $this.ConflictLog = @{}
        $this.ResolutionStrategy = $strategy
    }

    [void] LogConflict([string]$itemId, [hashtable]$oldValue, [hashtable]$newValue, [string]$reason) {
        if (-not $this.ConflictLog.ContainsKey($itemId)) {
            $this.ConflictLog[$itemId] = @()
        }

        $conflict = @{
            Timestamp = Get-Date
            OldValue = $oldValue
            NewValue = $newValue
            Reason = $reason
            Resolved = $false
            Resolution = $null
        }

        $this.ConflictLog[$itemId] += $conflict
    }

    [hashtable] ResolveConflict([string]$itemId, [int]$conflictIndex = 0) {
        if (-not $this.ConflictLog.ContainsKey($itemId)) {
            return $null
        }

        $conflicts = $this.ConflictLog[$itemId]
        if ($conflictIndex -ge $conflicts.Count) {
            return $null
        }

        $conflict = $conflicts[$conflictIndex]

        switch ($this.ResolutionStrategy) {
            "keepOld" {
                $conflict.Resolution = "Kept old value"
                $conflict.Resolved = $true
                return $conflict.OldValue
            }
            "keepNew" {
                $conflict.Resolution = "Kept new value"
                $conflict.Resolved = $true
                return $conflict.NewValue
            }
            "merge" {
                $merged = $this.MergeValues($conflict.OldValue, $conflict.NewValue)
                $conflict.Resolution = "Merged values"
                $conflict.Resolved = $true
                return $merged
            }
            "manual" {
                # Return conflict for manual resolution
                return $conflict
            }
        }
        return $conflict
    }

    [hashtable] MergeValues([hashtable]$old, [hashtable]$new) {
        $merged = $old.Clone()
        foreach ($key in $new.Keys) {
            if ($merged.ContainsKey($key)) {
                if ($merged[$key] -is [hashtable] -and $new[$key] -is [hashtable]) {
                    $merged[$key] = $this.MergeValues($merged[$key], $new[$key])
                }
                else {
                    $merged[$key] = $new[$key]
                }
            }
            else {
                $merged[$key] = $new[$key]
            }
        }
        return $merged
    }

    [hashtable] GetConflictSummary() {
        $summary = @{
            TotalConflicts = 0
            ResolvedConflicts = 0
            UnresolvedConflicts = 0
            ConflictsByItem = @{}
        }

        foreach ($itemId in $this.ConflictLog.Keys) {
            $conflicts = $this.ConflictLog[$itemId]
            $summary.TotalConflicts += $conflicts.Count
            $resolved = @($conflicts | Where-Object { $_.Resolved }).Count
            $summary.ResolvedConflicts += $resolved
            $summary.UnresolvedConflicts += ($conflicts.Count - $resolved)
            $summary.ConflictsByItem[$itemId] = @{
                Total = $conflicts.Count
                Resolved = $resolved
            }
        }

        return $summary
    }
}

# ============================================================================
# VALIDATION ENGINE
# ============================================================================

class ValidationEngine {
    [ValidationLevel] $ValidationLevel
    [hashtable] $ValidationRules
    [System.Collections.Generic.List[string]] $ValidationErrors

    ValidationEngine([ValidationLevel]$level = [ValidationLevel]::Standard) {
        $this.ValidationLevel = $level
        $this.ValidationRules = @{}
        $this.ValidationErrors = [System.Collections.Generic.List[string]]::new()
    }

    [void] AddRule([string]$ruleName, [scriptblock]$rule) {
        $this.ValidationRules[$ruleName] = $rule
    }

    [hashtable] Validate([hashtable]$data) {
        $results = @{
            Valid = $true
            Level = $this.ValidationLevel.ToString()
            RuleResults = @{}
            ErrorCount = 0
            WarningCount = 0
        }

        foreach ($ruleName in $this.ValidationRules.Keys) {
            try {
                $rule = $this.ValidationRules[$ruleName]
                $ruleResult = & $rule $data
                
                $results.RuleResults[$ruleName] = @{
                    Passed = $ruleResult.Passed
                    Message = $ruleResult.Message
                }

                if (-not $ruleResult.Passed) {
                    $results.Valid = $false
                    $results.ErrorCount++
                    $this.ValidationErrors.Add("Rule '$ruleName' failed: $($ruleResult.Message)")
                }
            }
            catch {
                $results.Valid = $false
                $results.ErrorCount++
                $this.ValidationErrors.Add("Error executing rule '$ruleName': $_")
            }
        }

        return $results
    }

    [System.Collections.Generic.List[string]] GetErrors() {
        return $this.ValidationErrors
    }

    [void] ClearErrors() {
        $this.ValidationErrors.Clear()
    }
}

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

Export-ModuleMember -Class MigrationContext, MigrationProgressTracker, BackupManager, ConflictResolver, ValidationEngine
