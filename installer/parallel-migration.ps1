# Parallel Migration Executor for HELIOS
# Distributes migration work across multiple agents/workers

. "$PSScriptRoot\migration-core.ps1"
. "$PSScriptRoot\data-transformer.ps1"

# ============================================================================
# PARALLEL MIGRATION WORKER
# ============================================================================

class ParallelMigrationWorker {
    [int] $WorkerId
    [System.Collections.Generic.Queue[object]] $TaskQueue
    [System.Collections.Generic.List[hashtable]] $CompletedTasks
    [bool] $IsRunning
    [scriptblock] $WorkerScript
    [threading.ManualResetEvent] $ShutdownEvent

    ParallelMigrationWorker([int]$id) {
        $this.WorkerId = $id
        $this.TaskQueue = [System.Collections.Generic.Queue[object]]::new()
        $this.CompletedTasks = [System.Collections.Generic.List[hashtable]]::new()
        $this.IsRunning = $false
        $this.ShutdownEvent = [threading.ManualResetEvent]::new($false)
    }

    [void] QueueTask([object]$task) {
        $this.TaskQueue.Enqueue($task)
    }

    [hashtable] ProcessTask([object]$task) {
        $result = @{
            WorkerId = $this.WorkerId
            TaskId = $task.Id
            Success = $false
            Result = $null
            Error = $null
            Duration = 0
            Timestamp = Get-Date
        }

        $startTime = Get-Date

        try {
            if ($null -ne $this.WorkerScript) {
                $result.Result = & $this.WorkerScript $task
                $result.Success = $true
            }
            else {
                # Default processing
                $result.Result = $task.Data
                $result.Success = $true
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            $result.Success = $false
        }

        $result.Duration = ((Get-Date) - $startTime).TotalMilliseconds
        $this.CompletedTasks.Add($result)

        return $result
    }

    [System.Collections.Generic.List[hashtable]] GetCompletedTasks() {
        return $this.CompletedTasks
    }
}

# ============================================================================
# PARALLEL MIGRATION COORDINATOR
# ============================================================================

class ParallelMigrationCoordinator {
    [int] $MaxWorkers
    [System.Collections.Generic.List[ParallelMigrationWorker]] $Workers
    [System.Collections.Generic.Queue[object]] $GlobalTaskQueue
    [hashtable] $GlobalResults
    $ProgressTracker
    [threading.ManualResetEvent] $AllTasksCompleteEvent

    ParallelMigrationCoordinator([int]$maxWorkers, [string]$logPath) {
        $this.MaxWorkers = $maxWorkers
        $this.Workers = [System.Collections.Generic.List[ParallelMigrationWorker]]::new()
        $this.GlobalTaskQueue = [System.Collections.Generic.Queue[object]]::new()
        $this.GlobalResults = @{}
        $this.ProgressTracker = New-Object MigrationProgressTracker -ArgumentList $logPath
        $this.AllTasksCompleteEvent = [threading.ManualResetEvent]::new($false)
        
        $this.InitializeWorkers()
    }

    [void] InitializeWorkers() {
        for ($i = 0; $i -lt $this.MaxWorkers; $i++) {
            $worker = [ParallelMigrationWorker]::new($i)
            $this.Workers.Add($worker)
        }
    }

    [void] SetWorkerScript([scriptblock]$script) {
        foreach ($worker in $this.Workers) {
            $worker.WorkerScript = $script
        }
    }

    [void] DistributeTasks([System.Collections.Generic.List[object]]$tasks) {
        # Round-robin task distribution
        $workerIndex = 0

        foreach ($task in $tasks) {
            $this.Workers[$workerIndex].QueueTask($task)
            $workerIndex = ($workerIndex + 1) % $this.MaxWorkers
        }

        $this.ProgressTracker.UpdateProgress("parallel-migrate", 0, $tasks.Count)
    }

    [hashtable] ExecuteParallel([System.Collections.Generic.List[object]]$tasks) {
        $executionResult = @{
            TotalTasks = $tasks.Count
            CompletedTasks = 0
            SuccessfulTasks = 0
            FailedTasks = 0
            WorkerResults = @()
            Timestamp = Get-Date
            Duration = 0
        }

        $startTime = Get-Date

        try {
            $this.DistributeTasks($tasks)

            # Process tasks from queue with multiple workers (simulated threading)
            $processedCount = 0
            $tasksRemaining = $tasks.Count

            while ($tasksRemaining -gt 0) {
                foreach ($worker in $this.Workers) {
                    if ($worker.TaskQueue.Count -gt 0) {
                        $task = $worker.TaskQueue.Dequeue()
                        $result = $worker.ProcessTask($task)
                        
                        $this.GlobalResults[$task.Id] = $result

                        if ($result.Success) {
                            $executionResult.SuccessfulTasks++
                        }
                        else {
                            $executionResult.FailedTasks++
                        }

                        $processedCount++
                        $tasksRemaining--
                        
                        $this.ProgressTracker.UpdateProgress("parallel-migrate", $processedCount, $tasks.Count)
                    }
                }

                if ($tasksRemaining -gt 0) {
                    Start-Sleep -Milliseconds 10
                }
            }

            # Aggregate worker results
            foreach ($worker in $this.Workers) {
                $executionResult.WorkerResults += @{
                    WorkerId = $worker.WorkerId
                    TasksCompleted = $worker.CompletedTasks.Count
                    Tasks = $worker.CompletedTasks
                }
            }

            $executionResult.CompletedTasks = $processedCount
        }
        catch {
            $executionResult.Error = $_.Exception.Message
        }

        $executionResult.Duration = ((Get-Date) - $startTime).TotalSeconds
        return $executionResult
    }

    [hashtable] GetResult([string]$taskId) {
        if ($this.GlobalResults.ContainsKey($taskId)) {
            return $this.GlobalResults[$taskId]
        }
        return $null
    }

    [hashtable] GetSummary() {
        $summary = @{
            TotalResults = $this.GlobalResults.Count
            SuccessfulResults = @($this.GlobalResults.Values | Where-Object { $_.Success }).Count
            FailedResults = @($this.GlobalResults.Values | Where-Object { -not $_.Success }).Count
            AverageDuration = 0
            WorkerLoad = @{}
        }

        if ($this.GlobalResults.Count -gt 0) {
            $summary.AverageDuration = ($this.GlobalResults.Values | Measure-Object -Property Duration -Average).Average
        }

        foreach ($worker in $this.Workers) {
            $summary.WorkerLoad[$worker.WorkerId] = $worker.CompletedTasks.Count
        }

        return $summary
    }

    [void] Dispose() {
        $this.ProgressTracker.Dispose()
    }
}

# ============================================================================
# DISTRIBUTED MIGRATION EXECUTOR
# ============================================================================

class DistributedMigrationExecutor {
    [ParallelMigrationCoordinator] $Coordinator
    $Transformer
    [int] $ChunkSize
    [hashtable] $ExecutionLog

    DistributedMigrationExecutor([int]$maxWorkers, [string]$logPath, $transformer) {
        $this.Coordinator = [ParallelMigrationCoordinator]::new($maxWorkers, $logPath)
        $this.Transformer = $transformer
        $this.ChunkSize = 100
        $this.ExecutionLog = @{}
    }

    [void] SetChunkSize([int]$size) {
        $this.ChunkSize = $size
    }

    [hashtable] ExecuteDistributedMigration([System.Collections.Generic.List[hashtable]]$records) {
        $executionResult = @{
            TotalRecords = $records.Count
            ProcessedRecords = 0
            SuccessfulRecords = 0
            FailedRecords = 0
            ChunksProcessed = 0
            StartTime = Get-Date
            EndTime = $null
            Duration = 0
            ChunkResults = @()
        }

        try {
            # Split records into chunks
            $chunks = $this.CreateChunks($records)
            $executionResult.ChunksProcessed = 0

            # Create tasks for parallel execution
            $tasks = [System.Collections.Generic.List[object]]::new()

            for ($i = 0; $i -lt $chunks.Count; $i++) {
                $task = @{
                    Id = "chunk_$i"
                    ChunkIndex = $i
                    Data = $chunks[$i]
                }
                $tasks.Add($task)
            }

            # Set worker script for transformation
            $transformScript = {
                param($task)
                $chunk = $task.Data
                $results = $this.Transformer.TransformBatch([System.Collections.Generic.List[hashtable]]$chunk)
                return $results
            }.GetNewClosure()

            $this.Coordinator.SetWorkerScript($transformScript)

            # Execute parallel migration
            $parallelResult = $this.Coordinator.ExecuteParallel($tasks)

            # Aggregate results
            foreach ($workerResult in $parallelResult.WorkerResults) {
                foreach ($taskResult in $workerResult.Tasks) {
                    if ($taskResult.Success) {
                        $executionResult.SuccessfulRecords += ($taskResult.Result | Measure-Object).Count
                    }
                    else {
                        $executionResult.FailedRecords++
                    }
                    $executionResult.ChunkResults += $taskResult
                }
            }

            $executionResult.ProcessedRecords = $executionResult.SuccessfulRecords + $executionResult.FailedRecords
        }
        catch {
            $executionResult.Error = $_.Exception.Message
        }

        $executionResult.EndTime = Get-Date
        $executionResult.Duration = ($executionResult.EndTime - $executionResult.StartTime).TotalSeconds

        return $executionResult
    }

    [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]] CreateChunks([System.Collections.Generic.List[hashtable]]$records) {
        $chunks = [System.Collections.Generic.List[System.Collections.Generic.List[hashtable]]]::new()
        
        for ($i = 0; $i -lt $records.Count; $i += $this.ChunkSize) {
            $currentChunkSize = [math]::Min($this.ChunkSize, $records.Count - $i)
            $chunk = [System.Collections.Generic.List[hashtable]]::new()

            for ($j = 0; $j -lt $currentChunkSize; $j++) {
                $chunk.Add($records[$i + $j])
            }
            
            $chunks.Add($chunk)
        }

        return $chunks
    }

    [hashtable] GetCoordinatorSummary() {
        return $this.Coordinator.GetSummary()
    }

    [void] Dispose() {
        $this.Coordinator.Dispose()
    }
}

# ============================================================================
# WORK DISTRIBUTION ENGINE
# ============================================================================

class WorkDistributionEngine {
    [hashtable] $WorkQueues
    [hashtable] $WorkerCapacity
    [hashtable] $CompletedWork
    [int] $MaxQueueSize

    WorkDistributionEngine([int]$workers = 4, [int]$maxQueueSize = 1000) {
        $this.WorkQueues = @{}
        $this.WorkerCapacity = @{}
        $this.CompletedWork = @{}
        $this.MaxQueueSize = $maxQueueSize

        for ($i = 0; $i -lt $workers; $i++) {
            $this.WorkQueues[$i] = [System.Collections.Generic.Queue[object]]::new()
            $this.WorkerCapacity[$i] = $maxQueueSize
            $this.CompletedWork[$i] = @()
        }
    }

    [int] DistributeWork([object]$workItem, [string]$strategy = "leastLoaded") {
        $targetWorker = $this.SelectWorker($strategy)
        
        if ($this.WorkQueues[$targetWorker].Count -lt $this.WorkerCapacity[$targetWorker]) {
            $this.WorkQueues[$targetWorker].Enqueue($workItem)
            return $targetWorker
        }

        return -1 # Failed to distribute
    }

    [int] SelectWorker([string]$strategy) {
        switch ($strategy) {
            "leastLoaded" {
                $leastLoaded = 0
                $minLoad = $this.WorkQueues[0].Count
                
                for ($i = 1; $i -lt $this.WorkQueues.Count; $i++) {
                    if ($this.WorkQueues[$i].Count -lt $minLoad) {
                        $minLoad = $this.WorkQueues[$i].Count
                        $leastLoaded = $i
                    }
                }
                return $leastLoaded
            }
            "roundRobin" {
                return Get-Random -Minimum 0 -Maximum $this.WorkQueues.Count
            }
            "random" {
                return Get-Random -Minimum 0 -Maximum $this.WorkQueues.Count
            }
            default {
                return 0
            }
        }
        return 0
    }

    [object] GetNextWork([int]$workerId) {
        if ($this.WorkQueues[$workerId].Count -gt 0) {
            return $this.WorkQueues[$workerId].Dequeue()
        }
        return $null
    }

    [void] MarkWorkComplete([int]$workerId, [object]$work) {
        $this.CompletedWork[$workerId] += $work
    }

    [hashtable] GetDistributionStats() {
        $stats = @{
            TotalWorkers = $this.WorkQueues.Count
            PendingWorkByWorker = @{}
            CompletedWorkByWorker = @{}
            TotalPendingWork = 0
            TotalCompletedWork = 0
        }

        for ($i = 0; $i -lt $this.WorkQueues.Count; $i++) {
            $pendingCount = $this.WorkQueues[$i].Count
            $completedCount = $this.CompletedWork[$i].Count

            $stats.PendingWorkByWorker[$i] = $pendingCount
            $stats.CompletedWorkByWorker[$i] = $completedCount
            $stats.TotalPendingWork += $pendingCount
            $stats.TotalCompletedWork += $completedCount
        }

        return $stats
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function New-ParallelMigrationCoordinator {
    param(
        [int]$MaxWorkers = 4,
        [Parameter(Mandatory=$true)]
        [string]$LogPath
    )
    return [ParallelMigrationCoordinator]::new($MaxWorkers, $LogPath)
}

function New-DistributedMigrationExecutor {
    param(
        [int]$MaxWorkers = 4,
        [Parameter(Mandatory=$true)]
        [string]$LogPath,
        [Parameter(Mandatory=$true)]
        [DataTransformer]$Transformer
    )
    return [DistributedMigrationExecutor]::new($MaxWorkers, $LogPath, $Transformer)
}

function New-WorkDistributionEngine {
    param(
        [int]$Workers = 4,
        [int]$MaxQueueSize = 1000
    )
    return [WorkDistributionEngine]::new($Workers, $MaxQueueSize)
}

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

Export-ModuleMember -Class ParallelMigrationWorker, ParallelMigrationCoordinator, DistributedMigrationExecutor, WorkDistributionEngine
Export-ModuleMember -Function New-ParallelMigrationCoordinator, New-DistributedMigrationExecutor, New-WorkDistributionEngine
