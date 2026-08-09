# Version Upgrade Handler for HELIOS Migration
# Manages incremental version upgrades (v1->v2->v3, etc)

. "$PSScriptRoot\migration-core.ps1"
. "$PSScriptRoot\data-transformer.ps1"

# ============================================================================
# VERSION UPGRADE MANAGER
# ============================================================================

class VersionUpgradeManager {
    [hashtable] $RegisteredUpgrades
    [hashtable] $VersionGraph
    [object] $ProgressTracker
    [hashtable] $UpgradeHistory

    VersionUpgradeManager([string]$logPath) {
        $this.RegisteredUpgrades = @{}
        $this.VersionGraph = @{}
        $this.ProgressTracker = New-Object MigrationProgressTracker $logPath
        $this.UpgradeHistory = @{}
    }

    [void] RegisterUpgrade([string]$fromVersion, [string]$toVersion, [scriptblock]$upgradeScript, [hashtable]$metadata = @{}) {
        $upgradeKey = "$fromVersion->$toVersion"
        
        $this.RegisteredUpgrades[$upgradeKey] = @{
            FromVersion = $fromVersion
            ToVersion = $toVersion
            Script = $upgradeScript
            Metadata = $metadata
            Registered = Get-Date
        }

        # Build version graph
        if (-not $this.VersionGraph.ContainsKey($fromVersion)) {
            $this.VersionGraph[$fromVersion] = @()
        }
        $this.VersionGraph[$fromVersion] += $toVersion
    }

    [System.Collections.Generic.List[string]] GetUpgradePath([string]$currentVersion, [string]$targetVersion, [bool]$strict = $false) {
        if ($currentVersion -eq $targetVersion) {
            return [System.Collections.Generic.List[string]]::new()
        }

        # BFS to find shortest path
        $queue = [System.Collections.Generic.Queue[object]]::new()
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $parentMap = @{}

        $queue.Enqueue($currentVersion)
        $visited.Add($currentVersion) | Out-Null

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()

            if ($current -eq $targetVersion) {
                # Reconstruct path
                $path = [System.Collections.Generic.List[string]]::new()
                $path.Add($current)
                
                while ($parentMap.ContainsKey($current)) {
                    $current = $parentMap[$current]
                    $path.Insert(0, $current)
                }

                return $path
            }

            if ($this.VersionGraph.ContainsKey($current)) {
                foreach ($nextVersion in $this.VersionGraph[$current]) {
                    if (-not $visited.Contains($nextVersion)) {
                        $visited.Add($nextVersion) | Out-Null
                        $parentMap[$nextVersion] = $current
                        $queue.Enqueue($nextVersion)
                    }
                }
            }
        }

        if ($strict) {
            throw "No upgrade path found from $currentVersion to $targetVersion"
        }
        else {
            Write-Warning "No direct upgrade path from $currentVersion to $targetVersion"
            return $null
        }
    }

    [hashtable] ExecuteUpgrade([string]$currentVersion, [string]$targetVersion, [hashtable]$data, [bool]$dryRun = $false) {
        $result = @{
            Success = $false
            CurrentVersion = $currentVersion
            TargetVersion = $targetVersion
            ExecutedUpgrades = @()
            FailedAtVersion = $null
            FailedAtStep = $null
            FailureReason = $null
            DryRun = $dryRun
            Timestamp = Get-Date
        }

        try {
            $upgradePath = $this.GetUpgradePath($currentVersion, $targetVersion, $true)
            
            if ($null -eq $upgradePath -or $upgradePath.Count -eq 0) {
                $result.FailureReason = "No upgrade path found"
                return $result
            }

            $currentData = $data

            # Execute each upgrade step
            for ($i = 0; $i -lt $upgradePath.Count - 1; $i++) {
                $from = $upgradePath[$i]
                $to = $upgradePath[$i + 1]
                $upgradeKey = "$from->$to"

                $this.ProgressTracker.Log("", "Starting upgrade: $upgradeKey")

                if (-not $this.RegisteredUpgrades.ContainsKey($upgradeKey)) {
                    $result.FailedAtVersion = $to
                    $result.FailedAtStep = $upgradeKey
                    $result.FailureReason = "Upgrade script not found for $upgradeKey"
                    return $result
                }

                try {
                    $upgrade = $this.RegisteredUpgrades[$upgradeKey]
                    $upgradeScript = $upgrade.Script

                    if ($dryRun) {
                        # Dry-run: validate but don't execute modifications
                        Write-Host "DRY-RUN: Would execute upgrade $upgradeKey" -ForegroundColor Cyan
                    }
                    else {
                        $currentData = & $upgradeScript $currentData
                    }

                    $result.ExecutedUpgrades += @{
                        FromVersion = $from
                        ToVersion = $to
                        Timestamp = Get-Date
                        Success = $true
                    }

                    $this.ProgressTracker.Log("", "Completed upgrade: $upgradeKey")
                }
                catch {
                    $result.FailedAtVersion = $to
                    $result.FailedAtStep = $upgradeKey
                    $result.FailureReason = "Upgrade failed: $_"
                    return $result
                }
            }

            $result.Success = $true
            $this.UpgradeHistory[$targetVersion] = $result

        }
        catch {
            $result.FailureReason = "Exception during upgrade: $_"
        }

        return $result
    }

    [hashtable] ValidateUpgradeCompatibility([string]$fromVersion, [string]$toVersion) {
        $validation = @{
            CanUpgrade = $false
            Gaps = @()
            WarningCount = 0
            Warnings = @()
        }

        $path = $this.GetUpgradePath($fromVersion, $toVersion, $false)

        if ($null -eq $path) {
            $validation.CanUpgrade = $false
            $validation.Gaps = @($fromVersion, $toVersion)
            return $validation
        }

        for ($i = 0; $i -lt $path.Count - 1; $i++) {
            $upgradeKey = "$($path[$i])->$($path[$i+1])"
            if ($this.RegisteredUpgrades.ContainsKey($upgradeKey)) {
                $upgrade = $this.RegisteredUpgrades[$upgradeKey]
                if ($upgrade.Metadata.ContainsKey('Experimental') -and $upgrade.Metadata.Experimental) {
                    $validation.WarningCount++
                    $validation.Warnings += "Experimental upgrade: $upgradeKey"
                }
            }
        }

        $validation.CanUpgrade = $true
        return $validation
    }

    [hashtable] GetUpgradeHistory() {
        return $this.UpgradeHistory
    }

    [void] Dispose() {
        $this.ProgressTracker.Dispose()
    }
}

# ============================================================================
# INCREMENTAL UPGRADE ORCHESTRATOR
# ============================================================================

class IncrementalUpgradeOrchestrator {
    [VersionUpgradeManager] $UpgradeManager
    [hashtable] $PhaseDefinitions
    [int] $CurrentPhase
    [object] $MigrationContext

    IncrementalUpgradeOrchestrator([VersionUpgradeManager]$manager) {
        $this.UpgradeManager = $manager
        $this.PhaseDefinitions = @{}
        $this.CurrentPhase = 0
    }

    [void] DefineMigrationPhase([int]$phaseNumber, [string]$name, [string[]]$dataSubsets, [scriptblock]$validation) {
        $this.PhaseDefinitions[$phaseNumber] = @{
            Number = $phaseNumber
            Name = $name
            DataSubsets = $dataSubsets
            Validation = $validation
            Status = "Pending"
            CompletedAt = $null
        }
    }

    [hashtable] ExecutePhased([string]$currentVersion, [string]$targetVersion, [hashtable]$fullData, [bool]$dryRun = $false) {
        $orchestrationResult = @{
            Success = $false
            PhasesCompleted = 0
            PhasesTotal = $this.PhaseDefinitions.Count
            PhaseResults = @()
            Timestamp = Get-Date
            Duration = $null
        }

        $startTime = Get-Date
        $sortedPhases = $this.PhaseDefinitions.Keys | Sort-Object

        foreach ($phaseNum in $sortedPhases) {
            $phase = $this.PhaseDefinitions[$phaseNum]
            $phaseResult = @{
                Phase = $phaseNum
                Name = $phase.Name
                Success = $false
                ItemsProcessed = 0
                ItemsFailed = 0
                Duration = $null
                StartTime = Get-Date
            }

            try {
                Write-Host "Executing phase ${phaseNum}: $($phase.Name)" -ForegroundColor Cyan

                # Process data subsets
                $phasedData = $this.ExtractDataSubsets($fullData, $phase.DataSubsets)

                # Execute upgrade for this phase
                $upgradeResult = $this.UpgradeManager.ExecuteUpgrade($currentVersion, $targetVersion, $phasedData, $dryRun)

                if ($upgradeResult.Success) {
                    # Validate phase results
                    $validation = & $phase.Validation $upgradeResult
                    if ($validation.Valid) {
                        $phaseResult.Success = $true
                        $phaseResult.ItemsProcessed = $phase.DataSubsets.Count
                        $orchestrationResult.PhasesCompleted++
                    }
                    else {
                        throw "Phase validation failed: $($validation.Message)"
                    }
                }
                else {
                    throw "Upgrade failed: $($upgradeResult.FailureReason)"
                }
            }
            catch {
                $phaseResult.Success = $false
                Write-Error "Phase $phaseNum failed: $_"
                $phaseResult.Error = $_
            }

            $phaseResult.Duration = ((Get-Date) - $phaseResult.StartTime).TotalSeconds
            $orchestrationResult.PhaseResults += $phaseResult

            if (-not $phaseResult.Success) {
                break
            }
        }

        $orchestrationResult.Success = ($orchestrationResult.PhasesCompleted -eq $orchestrationResult.PhasesTotal)
        $orchestrationResult.Duration = ((Get-Date) - $startTime).TotalSeconds

        return $orchestrationResult
    }

    [hashtable] ExtractDataSubsets([hashtable]$data, [string[]]$subsets) {
        $extracted = @{}
        foreach ($subset in $subsets) {
            if ($data.ContainsKey($subset)) {
                $extracted[$subset] = $data[$subset]
            }
        }
        return $extracted
    }

    [void] SetMigrationContext([object]$context) {
        $this.MigrationContext = $context
    }
}

# ============================================================================
# UPGRADE VERIFICATION
# ============================================================================

class UpgradeVerifier {
    [hashtable] $PreUpgradeChecks
    [hashtable] $PostUpgradeChecks

    UpgradeVerifier() {
        $this.PreUpgradeChecks = @{}
        $this.PostUpgradeChecks = @{}
    }

    [void] AddPreCheck([string]$checkName, [scriptblock]$check) {
        $this.PreUpgradeChecks[$checkName] = $check
    }

    [void] AddPostCheck([string]$checkName, [scriptblock]$check) {
        $this.PostUpgradeChecks[$checkName] = $check
    }

    [hashtable] VerifyPreUpgrade([hashtable]$data) {
        return $this.ExecuteChecks($this.PreUpgradeChecks, $data)
    }

    [hashtable] VerifyPostUpgrade([hashtable]$originalData, [hashtable]$upgradedData) {
        return $this.ExecuteChecks($this.PostUpgradeChecks, @{
            Original = $originalData
            Upgraded = $upgradedData
        })
    }

    [hashtable] ExecuteChecks([hashtable]$checks, [hashtable]$data) {
        $results = @{
            AllPassed = $true
            CheckResults = @()
        }

        foreach ($checkName in $checks.Keys) {
            $check = $checks[$checkName]
            $checkResult = @{
                Name = $checkName
                Passed = $false
                Message = ""
            }

            try {
                $checkReturn = & $check $data
                $checkResult.Passed = $checkReturn.Passed
                $checkResult.Message = $checkReturn.Message
            }
            catch {
                $checkResult.Passed = $false
                $checkResult.Message = "Check failed with exception: $_"
            }

            if (-not $checkResult.Passed) {
                $results.AllPassed = $false
            }

            $results.CheckResults += $checkResult
        }

        return $results
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function New-VersionUpgradeManager {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    return [VersionUpgradeManager]::new($LogPath)
}

function New-IncrementalUpgradeOrchestrator {
    param(
        [Parameter(Mandatory=$true)]
        [VersionUpgradeManager]$UpgradeManager
    )
    return [IncrementalUpgradeOrchestrator]::new($UpgradeManager)
}

function New-UpgradeVerifier {
    return [UpgradeVerifier]::new()
}

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

Export-ModuleMember -Class VersionUpgradeManager, IncrementalUpgradeOrchestrator, UpgradeVerifier
Export-ModuleMember -Function New-VersionUpgradeManager, New-IncrementalUpgradeOrchestrator, New-UpgradeVerifier
