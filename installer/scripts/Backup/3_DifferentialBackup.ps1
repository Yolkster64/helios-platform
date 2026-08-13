#################################################################################
# HELIOS Platform - Differential Backup
# Purpose: Backs up only changes since last full backup
# Version: 1.0.0
#################################################################################

param(
    [string]$BackupName = "DifferentialBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [bool]$CompressBackup = $true,
    [bool]$UploadToCloud = $true,
    [bool]$VerifyAfterBackup = $true
)

. "C:\HELIOS\Scripts\Backup\0_BackupCore.ps1"

$logFile = Initialize-BackupLogging -LogType "DifferentialBackup"
Write-BackupLog -Message "Differential Backup Started: $BackupName" -Level "INFO" -LogFile $logFile

try {
    $null = Initialize-BackupDirectories
    
    $lastFullBackupPath = Get-ChildItem -Path $Script:BackupLocations.SystemPath -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending | Select-Object -First 1
    
    if (-not $lastFullBackupPath) {
        Write-BackupLog -Message "No full backup found. Running full backup first..." -Level "WARN" -LogFile $logFile
        $result = & "C:\HELIOS\Scripts\Backup\1_FullBackup.ps1"
        return $result
    }
    
    $lastFullBackupTime = $lastFullBackupPath.CreationTime
    Write-BackupLog -Message "Last full backup: $($lastFullBackupPath.Name) at $lastFullBackupTime" -LogFile $logFile
    
    $metadata = New-BackupMetadata -BackupName $BackupName -BackupType "Differential" `
        -Description "Differential backup of changes since $lastFullBackupTime"
    
    $backupRootPath = Join-Path $Script:BackupLocations.SystemPath $BackupName
    New-Item -ItemType Directory -Path $backupRootPath -Force | Out-Null
    
    # Differential Database Backups
    Write-BackupLog -Message "Phase 1: Differential database backups..." -Level "INFO" -LogFile $logFile
    
    $dbBackupPath = Join-Path $backupRootPath "Databases"
    New-Item -ItemType Directory -Path $dbBackupPath -Force | Out-Null
    
    foreach ($database in $Script:Databases) {
        try {
            $dbName = $database.Name
            $dbServer = $database.Server
            $backupFile = Join-Path $dbBackupPath "$dbName.dif"
            
            $backupQuery = "BACKUP DATABASE [$dbName] TO DISK = N'$backupFile' WITH DIFFERENTIAL, NOFORMAT, NOINIT, NAME = N'$dbName-DifferentialBackup', SKIP, REWIND, NOUNLOAD, STATS = 10;"
            
            Invoke-Sqlcmd -ServerInstance $dbServer -Query $backupQuery -QueryTimeout 3600
            
            $backupSize = (Get-Item $backupFile).Length
            Write-BackupLog -Message "Differential database backup: $dbName ($(($backupSize/1MB).ToString('F2')) MB)" -Level "SUCCESS" -LogFile $logFile
        }
        catch {
            Write-BackupLog -Message "Failed differential backup for $($database.Name): $_" -Level "ERROR" -LogFile $logFile
        }
    }
    
    # File System Differential
    Write-BackupLog -Message "Phase 2: File system differential backup..." -Level "INFO" -LogFile $logFile
    
    $fsBackupPath = Join-Path $backupRootPath "FileSystem"
    New-Item -ItemType Directory -Path $fsBackupPath -Force | Out-Null
    
    $dirsToBackup = @(
        @{ Source = "D:\HELIOS\Data"; Exclude = @("*.tmp", "*.log") }
        @{ Source = "D:\HELIOS\Documents"; Exclude = @() }
    )
    
    $totalChangedFiles = 0
    
    foreach ($dir in $dirsToBackup) {
        if (Test-Path $dir.Source) {
            $dirName = Split-Path -Leaf $dir.Source
            $destPath = Join-Path $fsBackupPath $dirName
            
            $changedFiles = Get-ChildItem -Path $dir.Source -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $lastFullBackupTime }
            
            $totalChangedFiles += $changedFiles.Count
            
            if ($changedFiles.Count -gt 0) {
                New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                
                foreach ($file in $changedFiles) {
                    $relPath = $file.FullName.Substring($dir.Source.Length)
                    $destFile = Join-Path $destPath $relPath
                    $destDir = Split-Path $destFile
                    
                    New-Item -ItemType Directory -Path $destDir -Force -ErrorAction SilentlyContinue | Out-Null
                    Copy-Item -Path $file.FullName -Destination $destFile -Force -ErrorAction SilentlyContinue
                }
                
                Write-BackupLog -Message "Differential backup for ${dirName}: $($changedFiles.Count) files" -Level "INFO" -LogFile $logFile
            }
        }
    }
    
    # Metadata and checksums
    Write-BackupLog -Message "Phase 3: Generating metadata..." -Level "INFO" -LogFile $logFile
    
    $metadata.Status = "Generating Checksums"
    Generate-BackupChecksum -BackupPath $backupRootPath -Metadata $metadata
    
    $metadata.Status = "Completed"
    $metadata.CompletedAt = Get-Date -Format "o"
    $metadata.BasedOnFullBackup = $lastFullBackupPath.Name
    $metadata.ChangedFilesCount = $totalChangedFiles
    
    $totalSize = (Get-ChildItem -Path $backupRootPath -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $metadata.Size = $totalSize
    
    Save-BackupMetadata -Metadata $metadata
    
    Write-BackupLog -Message "Differential Backup Completed! ($($totalChangedFiles) changed files)" -Level "SUCCESS" -LogFile $logFile
    
    return @{
        Success = $true
        BackupId = $metadata.BackupId
        BackupPath = $backupRootPath
        TotalSize = $metadata.Size
        ChangedFilesCount = $totalChangedFiles
    }
}
catch {
    Write-BackupLog -Message "Differential Backup FAILED: $_" -Level "ERROR" -LogFile $logFile
    return @{ Success = $false; Error = $_ }
}
