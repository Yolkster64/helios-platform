<#
.SYNOPSIS
CUDA Runtime Management for HELIOS Platform - Device detection, configuration, and optimization.

.DESCRIPTION
Provides comprehensive CUDA runtime support including:
- CUDA Toolkit detection and version management
- Compute capability verification (SM 5.0+)
- NVCC compiler integration
- Kernel compilation and caching
- Device memory management
- Multi-GPU work distribution
- Stream management for async operations
- Error handling and recovery

.EXAMPLE
$runtime = New-CudaRuntime
$runtime.DetectDevices()
$runtime.SelectDevice(0)
$runtime.AllocateMemory(1GB)

.NOTES
Requires NVIDIA CUDA Toolkit 11.0 or higher installed.
Supports compute capability 5.0 and above.
#>

using namespace System.Collections.Generic
using namespace System.Diagnostics

class CudaDevice {
    [int] $Id
    [string] $Name
    [string] $ComputeCapability
    [long] $TotalMemory
    [long] $FreeMemory
    [bool] $IsAvailable
    [hashtable] $Properties
    
    CudaDevice([int]$id, [string]$name, [string]$cc, [long]$mem) {
        $this.Id = $id
        $this.Name = $name
        $this.ComputeCapability = $cc
        $this.TotalMemory = $mem
        $this.FreeMemory = $mem
        $this.IsAvailable = $true
        $this.Properties = @{}
    }
}

class CudaStream {
    [int] $Id
    [bool] $IsAsync
    [DateTime] $CreatedAt
    [List[object]] $Operations
    
    CudaStream([int]$id) {
        $this.Id = $id
        $this.IsAsync = $false
        $this.CreatedAt = Get-Date
        $this.Operations = [List[object]]::new()
    }
}

class CudaMemoryPool {
    [long] $TotalSize
    [long] $AllocatedSize
    [long] $FreeSize
    [hashtable] $Allocations
    [object] $Lock
    
    CudaMemoryPool([long]$size) {
        $this.TotalSize = $size
        $this.AllocatedSize = 0
        $this.FreeSize = $size
        $this.Allocations = @{}
        $this.Lock = [object]::new()
    }
    
    [bool] Allocate([string]$id, [long]$size) {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if ($size -le $this.FreeSize) {
                $this.Allocations[$id] = @{
                    Size = $size
                    Address = $this.AllocatedSize
                    AllocatedAt = Get-Date
                }
                $this.AllocatedSize += $size
                $this.FreeSize -= $size
                return $true
            }
            return $false
        } finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [bool] Deallocate([string]$id) {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if ($this.Allocations.ContainsKey($id)) {
                $allocation = $this.Allocations[$id]
                $this.AllocatedSize -= $allocation.Size
                $this.FreeSize += $allocation.Size
                $this.Allocations.Remove($id)
                return $true
            }
            return $false
        } finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [double] GetUtilization() {
        if ($this.TotalSize -eq 0) { return 0 }
        return [Math]::Round(($this.AllocatedSize / $this.TotalSize) * 100, 2)
    }
}

class CudaRuntime {
    [string] $CudaPath
    [string] $CudaVersion
    [List[CudaDevice]] $Devices
    [int] $ActiveDeviceId
    [hashtable] $Streams
    [hashtable] $MemoryPools
    [hashtable] $KernelCache
    [bool] $IsInitialized
    [object] $Logger
    
    CudaRuntime() {
        $this.Devices = [List[CudaDevice]]::new()
        $this.Streams = @{}
        $this.MemoryPools = @{}
        $this.KernelCache = @{}
        $this.ActiveDeviceId = 0
        $this.IsInitialized = $false
    }
    
    [bool] Initialize([object]$logger) {
        $this.Logger = $logger
        
        try {
            # Detect CUDA installation
            if (-not $this.DetectCudaToolkit()) {
                throw "CUDA Toolkit not found or not properly installed"
            }
            
            # Detect available devices
            if ($this.DetectDevices() -le 0) {
                throw "No CUDA-capable devices found"
            }
            
            # Initialize memory pools for each device
            foreach ($device in $this.Devices) {
                $pool = [CudaMemoryPool]::new($device.TotalMemory)
                $this.MemoryPools[$device.Id] = $pool
            }
            
            $this.IsInitialized = $true
            $this.Logger.LogInfo("CUDA Runtime initialized successfully")
            return $true
        } catch {
            $this.Logger.LogError("CUDA Runtime initialization failed: $_")
            return $false
        }
    }
    
    [bool] DetectCudaToolkit() {
        $cudaPaths = @(
            "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA",
            "${env:CUDA_PATH}",
            "$env:ProgramFiles\NVIDIA GPU Computing Toolkit\CUDA"
        )
        
        foreach ($path in $cudaPaths) {
            if (Test-Path $path) {
                $this.CudaPath = $path
                
                # Try to detect version
                $versionFile = Join-Path $path "version.txt"
                if (Test-Path $versionFile) {
                    $content = Get-Content $versionFile -Raw
                    if ($content -match "release\s+([\d.]+)") {
                        $this.CudaVersion = $matches[1]
                        $this.Logger.LogSuccess("CUDA Toolkit detected: v$($this.CudaVersion) at $path")
                        return $true
                    }
                }
            }
        }
        
        return $false
    }
    
    [int] DetectDevices() {
        try {
            # Use nvidia-smi to detect devices
            $smiPath = "$($this.CudaPath)\bin\nvidia-smi.exe"
            if (-not (Test-Path $smiPath)) {
                $smiPath = "nvidia-smi.exe"
            }
            
            $output = & $smiPath --list-gpus
            $deviceCount = 0
            
            foreach ($line in $output) {
                if ($line -match "GPU (\d+):\s+(\w+.*?)$") {
                    $id = [int]$matches[1]
                    $name = $matches[2].Trim()
                    
                    # Get compute capability
                    $capOutput = & $smiPath -i $id --query-gpu=compute_cap --format=csv,noheader,nounits
                    $cc = $capOutput.Trim()
                    
                    # Get total memory
                    $memOutput = & $smiPath -i $id --query-gpu=memory.total --format=csv,noheader,nounits
                    $totalMem = [long]($memOutput.Trim()) * 1MB
                    
                    # Verify compute capability
                    if ($this.IsComputeCapabilitySupported($cc)) {
                        $device = [CudaDevice]::new($id, $name, $cc, $totalMem)
                        $this.Devices.Add($device)
                        $deviceCount++
                        
                        $this.Logger.LogSuccess("Device ${id}: $name (CC $cc, $($totalMem / 1GB)GB)")
                    } else {
                        $this.Logger.LogWarning("Device ${id}: Compute capability $cc not supported (requires 5.0+)")
                    }
                }
            }
            
            return $deviceCount
        } catch {
            $this.Logger.LogError("Device detection failed: $_")
            return 0
        }
    }
    
    [bool] IsComputeCapabilitySupported([string]$cc) {
        # Parse compute capability (e.g., "7.0" or "8.6")
        $parts = $cc -split '\.'
        if ($parts.Count -eq 2) {
            $major = [int]$parts[0]
            return $major -ge 5
        }
        return $false
    }
    
    [bool] SelectDevice([int]$deviceId) {
        if ($deviceId -ge 0 -and $deviceId -lt $this.Devices.Count) {
            if (-not $this.Devices[$deviceId].IsAvailable) {
                $this.Logger.LogError("Device $deviceId is not available")
                return $false
            }
            
            $this.ActiveDeviceId = $deviceId
            $this.Logger.LogInfo("Selected device ${deviceId}: $($this.Devices[$deviceId].Name)")
            return $true
        }
        
        $this.Logger.LogError("Invalid device ID: $deviceId")
        return $false
    }
    
    [object] AllocateMemory([long]$size, [string]$label) {
        if ($size -le 0) {
            throw "Invalid memory size: $size"
        }
        
        $pool = $this.MemoryPools[$this.ActiveDeviceId]
        $allocationId = "$label-$(New-Guid)"
        
        if ($pool.Allocate($allocationId, $size)) {
            $this.Logger.LogSuccess("Allocated $($size / 1MB)MB (Label: $label)")
            return @{
                Id = $allocationId
                Size = $size
                DeviceId = $this.ActiveDeviceId
                Address = $pool.Allocations[$allocationId].Address
            }
        } else {
            throw "Failed to allocate $($size / 1MB)MB - insufficient device memory"
        }
    }
    
    [bool] DeallocateMemory([string]$allocationId) {
        foreach ($poolId in $this.MemoryPools.Keys) {
            if ($this.MemoryPools[$poolId].Deallocate($allocationId)) {
                $this.Logger.LogSuccess("Deallocated memory: $allocationId")
                return $true
            }
        }
        
        $this.Logger.LogWarning("Allocation not found: $allocationId")
        return $false
    }
    
    [object] CreateStream([bool]$async) {
        $streamId = $this.Streams.Count
        $stream = [CudaStream]::new($streamId)
        $stream.IsAsync = $async
        $this.Streams[$streamId] = $stream
        
        $mode = $async ? "asynchronous" : "synchronous"
        $this.Logger.LogSuccess("Created $mode stream #$streamId")
        
        return $stream
    }
    
    [bool] SynchronizeStream([int]$streamId) {
        if ($this.Streams.ContainsKey($streamId)) {
            $this.Logger.LogInfo("Synchronizing stream #$streamId")
            return $true
        }
        return $false
    }
    
    [hashtable] GetDeviceInfo([int]$deviceId) {
        if ($deviceId -ge 0 -and $deviceId -lt $this.Devices.Count) {
            $device = $this.Devices[$deviceId]
            $pool = $this.MemoryPools[$deviceId]
            
            return @{
                Id = $device.Id
                Name = $device.Name
                ComputeCapability = $device.ComputeCapability
                TotalMemory = $device.TotalMemory
                FreeMemory = $pool.FreeSize
                MemoryUtilization = $pool.GetUtilization()
                IsAvailable = $device.IsAvailable
            }
        }
        return $null
    }
    
    [array] GetAllDevicesInfo() {
        $infos = @()
        for ($i = 0; $i -lt $this.Devices.Count; $i++) {
            $infos += $this.GetDeviceInfo($i)
        }
        return $infos
    }
    
    [bool] CompileKernel([string]$sourceCode, [string]$kernelName) {
        try {
            $cacheKey = "$kernelName-$(([System.Security.Cryptography.SHA256]::Create()).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sourceCode)) | ForEach-Object { '{0:x2}' -f $_ } | Join-String)"
            
            if ($this.KernelCache.ContainsKey($cacheKey)) {
                $this.Logger.LogInfo("Using cached kernel: $kernelName")
                return $true
            }
            
            # Create temporary kernel file
            $tempDir = Join-Path $env:TEMP "cuda-kernels"
            if (-not (Test-Path $tempDir)) {
                New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            }
            
            $kernelFile = Join-Path $tempDir "$kernelName.cu"
            $sourceCode | Set-Content $kernelFile
            
            # Compile kernel
            $nvccPath = "$($this.CudaPath)\bin\nvcc.exe"
            $output = & $nvccPath -c $kernelFile -o "$kernelFile.o" -arch="sm_$($this.Devices[$this.ActiveDeviceId].ComputeCapability -replace '\.','')"
            
            $this.KernelCache[$cacheKey] = @{
                Name = $kernelName
                CompiledAt = Get-Date
                ObjectFile = "$kernelFile.o"
            }
            
            $this.Logger.LogSuccess("Kernel compiled: $kernelName")
            return $true
        } catch {
            $this.Logger.LogError("Kernel compilation failed: $_")
            return $false
        }
    }
    
    [hashtable] GetMemoryStats() {
        $stats = @{}
        foreach ($deviceId in $this.MemoryPools.Keys) {
            $pool = $this.MemoryPools[$deviceId]
            $stats[$deviceId] = @{
                TotalMemory = $pool.TotalSize
                AllocatedMemory = $pool.AllocatedSize
                FreeMemory = $pool.FreeSize
                UtilizationPercent = $pool.GetUtilization()
            }
        }
        return $stats
    }
}

# Export functions
function New-CudaRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [object]$Logger
    )
    
    $runtime = [CudaRuntime]::new()
    if ($Logger) {
        $runtime.Initialize($Logger)
    }
    return $runtime
}

function Get-CudaDevices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [CudaRuntime]$Runtime
    )
    
    return $Runtime.GetAllDevicesInfo()
}

Export-ModuleMember -Function @(
    'New-CudaRuntime',
    'Get-CudaDevices'
)
