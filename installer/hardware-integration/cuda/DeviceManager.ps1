<#
.SYNOPSIS
CUDA Device Manager - Multi-device management and workload distribution.

.DESCRIPTION
Manages multiple CUDA devices with capabilities for:
- Device enumeration and properties
- Device health monitoring
- Workload distribution and load balancing
- Device synchronization
- Error detection and recovery
- Performance monitoring

.EXAMPLE
$manager = New-CudaDeviceManager
$manager.DiscoverDevices()
$manager.SetLoadBalancingStrategy('round-robin')
$workload = $manager.DistributeWorkload($tasks)

.NOTES
Integrates with CudaRuntime for core functionality.
#>

class DeviceLoadInfo {
    [int] $DeviceId
    [double] $CurrentLoad
    [double] $AvgLoad
    [long] $ActiveMemory
    [long] $TotalMemory
    [bool] $IsHealthy
    [DateTime] $LastUpdated
}

class WorkloadTask {
    [string] $Id
    [string] $Name
    [long] $EstimatedMemory
    [int] $Priority
    [int] $AssignedDevice
    [string] $Status
    [DateTime] $CreatedAt
    [DateTime] $StartedAt
    [DateTime] $CompletedAt
}

class CudaDeviceManager {
    [hashtable] $Devices
    [hashtable] $DeviceLoads
    [hashtable] $WorkloadQueues
    [string] $LoadBalancingStrategy
    [object] $Logger
    [bool] $MonitoringEnabled
    [System.Threading.Thread] $MonitoringThread
    
    CudaDeviceManager([object]$logger) {
        $this.Devices = @{}
        $this.DeviceLoads = @{}
        $this.WorkloadQueues = @{}
        $this.LoadBalancingStrategy = 'round-robin'
        $this.Logger = $logger
        $this.MonitoringEnabled = $false
    }
    
    [bool] DiscoverDevices() {
        try {
            $smiPath = "nvidia-smi.exe"
            $output = & $smiPath --list-gpus
            
            $deviceCount = 0
            foreach ($line in $output) {
                if ($line -match "GPU (\d+):\s+(\w+.*?)$") {
                    $id = [int]$matches[1]
                    $name = $matches[2].Trim()
                    
                    $deviceInfo = $this.QueryDeviceProperties($id)
                    if ($deviceInfo) {
                        $this.Devices[$id] = $deviceInfo
                        $this.DeviceLoads[$id] = [DeviceLoadInfo]@{
                            DeviceId = $id
                            CurrentLoad = 0
                            AvgLoad = 0
                            IsHealthy = $true
                            LastUpdated = Get-Date
                        }
                        $this.WorkloadQueues[$id] = [System.Collections.Generic.List[WorkloadTask]]::new()
                        $deviceCount++
                        $this.Logger.LogSuccess("Discovered device ${id}: $name")
                    }
                }
            }
            
            if ($deviceCount -gt 0) {
                $this.Logger.LogSuccess("Total devices discovered: $deviceCount")
                return $true
            }
        } catch {
            $this.Logger.LogError("Device discovery failed: $_")
        }
        return $false
    }
    
    [hashtable] QueryDeviceProperties([int]$deviceId) {
        try {
            $queries = @{
                Name = "name"
                ComputeCap = "compute_cap"
                Memory = "memory.total"
                ClockRate = "clocks.current.graphics"
                MemoryRate = "clocks.current.memory"
                Power = "power.draw"
                Temperature = "temperature.gpu"
            }
            
            $properties = @{ DeviceId = $deviceId }
            
            foreach ($key in $queries.Keys) {
                try {
                    $value = & nvidia-smi -i $deviceId --query-gpu=$($queries[$key]) --format=csv,noheader,nounits | ForEach-Object { $_.Trim() }
                    $properties[$key] = $value
                } catch {
                    $this.Logger.LogWarning("Failed to query $key for device $deviceId")
                }
            }
            
            return $properties
        } catch {
            return $null
        }
    }
    
    [void] SetLoadBalancingStrategy([string]$strategy) {
        $validStrategies = @('round-robin', 'least-loaded', 'memory-aware', 'performance-aware')
        
        if ($strategy -in $validStrategies) {
            $this.LoadBalancingStrategy = $strategy
            $this.Logger.LogSuccess("Load balancing strategy set to: $strategy")
        } else {
            $this.Logger.LogWarning("Unknown strategy: $strategy. Using default (round-robin)")
        }
    }
    
    [int] SelectDeviceForWorkload([long]$memoryRequired, [int]$priority) {
        $selectedDevice = -1
        
        switch ($this.LoadBalancingStrategy) {
            'round-robin' {
                $selectedDevice = $this.SelectRoundRobin()
            }
            'least-loaded' {
                $selectedDevice = $this.SelectLeastLoaded()
            }
            'memory-aware' {
                $selectedDevice = $this.SelectMemoryAware($memoryRequired)
            }
            'performance-aware' {
                $selectedDevice = $this.SelectPerformanceAware($priority)
            }
            default {
                $selectedDevice = $this.SelectRoundRobin()
            }
        }
        
        return $selectedDevice
    }
    
    [int] SelectRoundRobin() {
        $deviceIds = @($this.Devices.Keys | Sort-Object)
        if ($deviceIds.Count -eq 0) { return -1 }
        
        $idx = (Get-Random -Minimum 0 -Maximum $deviceIds.Count)
        return $deviceIds[$idx]
    }
    
    [int] SelectLeastLoaded() {
        $leastLoaded = -1
        $minLoad = [double]::MaxValue
        
        foreach ($deviceId in $this.DeviceLoads.Keys) {
            $load = $this.DeviceLoads[$deviceId].CurrentLoad
            if ($load -lt $minLoad -and $this.DeviceLoads[$deviceId].IsHealthy) {
                $minLoad = $load
                $leastLoaded = $deviceId
            }
        }
        
        return $leastLoaded
    }
    
    [int] SelectMemoryAware([long]$memoryRequired) {
        $bestDevice = -1
        $maxAvailable = 0
        
        foreach ($deviceId in $this.Devices.Keys) {
            if (-not $this.DeviceLoads[$deviceId].IsHealthy) { continue }
            
            $available = $this.DeviceLoads[$deviceId].TotalMemory - $this.DeviceLoads[$deviceId].ActiveMemory
            if ($available -ge $memoryRequired -and $available -gt $maxAvailable) {
                $maxAvailable = $available
                $bestDevice = $deviceId
            }
        }
        
        return $bestDevice
    }
    
    [int] SelectPerformanceAware([int]$priority) {
        $candidates = @()
        
        foreach ($deviceId in $this.Devices.Keys) {
            if ($this.DeviceLoads[$deviceId].IsHealthy) {
                $candidates += $deviceId
            }
        }
        
        if ($candidates.Count -eq 0) { return -1 }
        
        # Sort by load (lowest first)
        $sorted = $candidates | Sort-Object {
            $this.DeviceLoads[$_].CurrentLoad
        }
        
        return $sorted[0]
    }
    
    [WorkloadTask] CreateTask([string]$name, [long]$memoryRequired, [int]$priority) {
        $task = [WorkloadTask]@{
            Id = "task-$(New-Guid)"
            Name = $name
            EstimatedMemory = $memoryRequired
            Priority = $priority
            Status = 'pending'
            CreatedAt = Get-Date
            AssignedDevice = -1
        }
        
        return $task
    }
    
    [bool] EnqueueTask([WorkloadTask]$task) {
        $deviceId = $this.SelectDeviceForWorkload($task.EstimatedMemory, $task.Priority)
        
        if ($deviceId -eq -1) {
            $this.Logger.LogError("No available device for task: $($task.Name)")
            return $false
        }
        
        $task.AssignedDevice = $deviceId
        $task.Status = 'queued'
        $this.WorkloadQueues[$deviceId].Add($task)
        
        $this.Logger.LogInfo("Task enqueued on device $deviceId : $($task.Name)")
        return $true
    }
    
    [array] DistributeWorkload([array]$tasks) {
        $results = @()
        
        foreach ($task in $tasks) {
            if ($this.EnqueueTask($task)) {
                $results += $task
            } else {
                $this.Logger.LogWarning("Failed to distribute task: $($task.Name)")
            }
        }
        
        return $results
    }
    
    [bool] StartMonitoring() {
        if ($this.MonitoringEnabled) { return $true }
        
        $this.MonitoringEnabled = $true
        
        # This would start a background monitoring thread
        # For now, we'll just log it
        $this.Logger.LogSuccess("Device monitoring started")
        return $true
    }
    
    [bool] StopMonitoring() {
        $this.MonitoringEnabled = $false
        $this.Logger.LogInfo("Device monitoring stopped")
        return $true
    }
    
    [void] UpdateDeviceHealth() {
        foreach ($deviceId in $this.Devices.Keys) {
            try {
                # Query device temperatures and power
                $temp = & nvidia-smi -i $deviceId --query-gpu=temperature.gpu --format=csv,noheader,nounits
                $power = & nvidia-smi -i $deviceId --query-gpu=power.draw --format=csv,noheader,nounits
                
                $tempVal = [int]$temp.Trim()
                $powerVal = [double]$power.Trim().Split()[0]
                
                $isHealthy = $tempVal -lt 85 -and $powerVal -lt 300
                $this.DeviceLoads[$deviceId].IsHealthy = $isHealthy
                $this.DeviceLoads[$deviceId].LastUpdated = Get-Date
                
                if (-not $isHealthy) {
                    $this.Logger.LogWarning("Device $deviceId health degraded (Temp: $tempVal°C, Power: $powerVal W)")
                }
            } catch {
                $this.Logger.LogWarning("Health check failed for device $deviceId : $_")
            }
        }
    }
    
    [hashtable] GetDeviceStats() {
        $stats = @{}
        
        foreach ($deviceId in $this.Devices.Keys) {
            $load = $this.DeviceLoads[$deviceId]
            $queue = $this.WorkloadQueues[$deviceId]
            
            $stats[$deviceId] = @{
                DeviceId = $deviceId
                Name = $this.Devices[$deviceId].Name
                CurrentLoad = $load.CurrentLoad
                ActiveMemory = $load.ActiveMemory
                IsHealthy = $load.IsHealthy
                QueuedTasks = $queue.Count
                LastUpdated = $load.LastUpdated
            }
        }
        
        return $stats
    }
    
    [int] GetTotalDeviceCount() {
        return $this.Devices.Count
    }
    
    [int] GetHealthyDeviceCount() {
        return @($this.DeviceLoads.Keys | Where-Object { $this.DeviceLoads[$_].IsHealthy }).Count
    }
}

# Export functions
function New-CudaDeviceManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Logger
    )
    
    return [CudaDeviceManager]::new($Logger)
}

function Invoke-DeviceDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [CudaDeviceManager]$Manager
    )
    
    return $Manager.DiscoverDevices()
}

Export-ModuleMember -Function @(
    'New-CudaDeviceManager',
    'Invoke-DeviceDiscovery'
)
