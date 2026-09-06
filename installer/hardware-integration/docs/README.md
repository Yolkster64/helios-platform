# HELIOS Phase 2: Hardware & Platform Integration

## Overview

This documentation covers the Phase 2 hardware acceleration and integration layer for the HELIOS Platform, consisting of 4 major components:

1. **CUDA Core Implementation** - GPU acceleration and device management
2. **Driver Management & AutoInstall** - Automatic driver detection and installation
3. **WSL2 Integration with Hermes Agents** - Windows-Linux seamless integration
4. **Razer Synapse & Chroma RGB** - Razer device integration and lighting

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Component Documentation](#component-documentation)
3. [Installation & Setup](#installation--setup)
4. [Usage Examples](#usage-examples)
5. [API Reference](#api-reference)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
HELIOS Phase 2 Architecture

┌─────────────────────────────────────────────────────────────────┐
│                     HELIOS Core Platform                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │   CUDA Runtime   │  │ Driver Manager   │  │ Razer Device │  │
│  │                  │  │                  │  │   Manager    │  │
│  │ • Device Mgmt    │  │ • Detection      │  │ • Lighting   │  │
│  │ • Memory Mgmt    │  │ • Download       │  │ • Profiles   │  │
│  │ • Streams        │  │ • Installation   │  │ • Sync       │  │
│  │ • Kernels        │  │ • Rollback       │  │ • Monitoring │  │
│  └──────────────────┘  └──────────────────┘  └──────────────┘  │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              WSL2 Integration Layer                        │ │
│  │  • Distribution Management  • Agent Lifecycle             │ │
│  │  • Environment Provisioning • Cross-Platform Messaging    │ │
│  │  • Hermes Agents (4 types)  • Task Distribution           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Documentation

### 1. CUDA Core Implementation

**Location**: `C:\HELIOS\hardware-integration\cuda\`

#### Overview

Provides complete CUDA runtime management with:

- GPU device detection and management
- Compute capability verification (SM 5.0+)
- Memory management with pooling
- Stream management for async operations
- Kernel compilation and caching
- Multi-GPU workload distribution

#### Key Classes

**CudaRuntime**

- Central CUDA runtime manager
- Device initialization and lifecycle
- Memory pool management
- Stream creation and synchronization

**CudaDevice**

- Represents individual GPU device
- Stores device properties and capabilities
- Memory information tracking

**CudaMemoryPool**

- Thread-safe memory allocation/deallocation
- Device-specific memory management
- Utilization tracking

**CudaStream**

- Async operation management
- Operation queueing
- Stream synchronization

#### Files

- `CudaRuntime.ps1` - Core CUDA runtime class
- `DeviceManager.ps1` - Multi-device management and load balancing

---

### 2. Driver Management & AutoInstall

**Location**: `C:\HELIOS\hardware-integration\drivers\`

#### Overview

Comprehensive driver lifecycle management:

- Automatic hardware detection (WMI-based)
- Latest driver version querying
- Silent driver installation
- Automatic rollback on failure
- Installation history tracking
- Periodic update checks

#### Supported Drivers

- **GPU**: NVIDIA (460+), AMD (Adrenalin), Intel (Arc)
- **Chipset**: Intel, AMD
- **Audio**: Realtek, Creative, ASUS
- **Network**: Intel, Realtek, Qualcomm
- **Peripherals**: USB 3.0, 3.1, Thunderbolt

#### Key Classes

**HardwareDevice**

- Detected hardware representation
- Version tracking (current vs. latest)
- Update availability status

**DriverPackage**

- Downloaded driver bundle
- Checksum verification
- Installation status

**DriverInstallation**

- Installation record
- Rollback point tracking
- Success/failure logging

**DriverManager**

- System scanning and detection
- Update checking
- Download management
- Installation orchestration

#### Files

- `DriverManager.ps1` - Driver detection, download, and installation

---

### 3. WSL2 Integration with Hermes Agents

**Location**: `C:\HELIOS\hardware-integration\wsl2\`

#### Overview

Seamless Windows-Linux integration with distributed agent framework:

- WSL2 distribution management
- Linux environment provisioning
- Hermes agent lifecycle management
- Cross-platform task distribution
- Health monitoring and auto-recovery

#### Supported Distributions

- Ubuntu (18.04, 20.04, 22.04+)
- Debian
- Alpine
- Fedora
- openSUSE

#### Agent Types (Hermes Framework)

1. **Processing Agent** - CPU-intensive tasks
2. **Analytics Agent** - Data analysis and reporting
3. **Background Jobs Agent** - Long-running operations
4. **Data Pipeline Agent** - ETL and data processing

#### Key Classes

**LinuxDistribution**

- WSL2 distribution representation
- Installation and running status
- Environment configuration

**HermesAgent**

- Agent process lifecycle
- Port assignment and communication
- Status tracking and health monitoring

**CrossPlatformMessage**

- Windows↔Linux message passing
- Status tracking (sent/received)
- Payload encapsulation

**Wsl2Integration**

- Distribution management
- Agent orchestration
- Cross-platform communication
- Task routing and execution

#### Files

- `Wsl2Integration.ps1` - WSL2 and Hermes agent management

---

### 4. Razer Synapse & Chroma RGB

**Location**: `C:\HELIOS\hardware-integration\razer\`

#### Overview

Complete Razer device integration:

- Device detection and enumeration
- Battery level monitoring
- DPI profile management
- Chroma RGB lighting control
- System status synchronization
- Game detection and auto-switching

#### Supported Devices

- **Mice**: DeathAdder, Viper, Pro
- **Keyboards**: BlackWidow, Huntsman
- **Headsets**: Kraken, Barracuda
- **Mousepads**: Goliathus

#### Lighting Modes

- Static color
- Breathing (pulse animation)
- Spectrum cycling (rainbow)
- Wave
- Reactive (per-key/on-input)
- Custom profiles

#### System Status Indicators

- **Green** - System healthy (CPU < 70%, Memory < 80%, Temp < 60°C)
- **Orange** - Warning (approaching limits)
- **Red** - Alert (critical thresholds)
- **Blue** - Processing (active operations)

#### Key Classes

**RazerDevice**

- Individual device representation
- Battery, DPI, lighting state
- Device properties and model info

**ChromaProfile**

- Lighting configuration
- Mode, colors, animation speed
- User-definable profiles

**RazerIntegration**

- Device scanning and management
- Lighting orchestration
- Game detection
- System status sync

#### Files

- `RazerIntegration.ps1` - Razer device and lighting management

---

## Installation & Setup

### Prerequisites

- Windows 10/11 (21H1 or later)
- Administrative privileges
- PowerShell 5.1+ or PowerShell Core 7+

### Optional Requirements

- **For CUDA**: NVIDIA CUDA Toolkit 11.0+ and compatible GPU (CC 5.0+)
- **For WSL2**: WSL2 with at least one distribution
- **For Razer**: Razer Synapse 3.0+ and compatible devices
- **For Drivers**: Internet connection for driver downloads

### Installation Steps

1. **Copy hardware integration module to HELIOS**

   ```powershell
   Copy-Item -Path ".\hardware-integration" -Destination "C:\HELIOS\" -Recurse
   ```

2. **Import modules in your scripts**

   ```powershell
   . "C:\HELIOS\hardware-integration\cuda\CudaRuntime.ps1"
   . "C:\HELIOS\hardware-integration\cuda\DeviceManager.ps1"
   . "C:\HELIOS\hardware-integration\drivers\DriverManager.ps1"
   . "C:\HELIOS\hardware-integration\wsl2\Wsl2Integration.ps1"
   . "C:\HELIOS\hardware-integration\razer\RazerIntegration.ps1"
   ```

3. **Create logger instance** (required for all components)

   ```powershell
   class SimpleLogger {
       [void] LogInfo([string]$msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
       [void] LogSuccess([string]$msg) { Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
       [void] LogWarning([string]$msg) { Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
       [void] LogError([string]$msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }
   }
   $logger = [SimpleLogger]::new()
   ```

---

## Usage Examples

### CUDA Runtime

```powershell
# Initialize CUDA runtime
$cuda = New-CudaRuntime
$cuda.Initialize($logger)

# Detect and select device
$devices = $cuda.GetAllDevicesInfo()
$cuda.SelectDevice(0)

# Allocate memory
$memAlloc = $cuda.AllocateMemory(1GB, "training-data")

# Create async stream
$stream = $cuda.CreateStream($true)

# Get memory statistics
$memStats = $cuda.GetMemoryStats()
```

### Driver Management

```powershell
# Initialize driver manager
$driveMgr = New-DriverManager -Logger $logger

# Scan system
$driveMgr.ScanSystem()

# Check for updates
$hasUpdates = $driveMgr.CheckForUpdates()

# Install all available updates
$driveMgr.InstallAllAvailableUpdates()

# Get device report
$report = $driveMgr.GetSystemDeviceReport()
```

### WSL2 Integration

```powershell
# Initialize WSL2 integration
$wsl2 = New-Wsl2Integration -Logger $logger
$wsl2.Initialize()

# Create Hermes agents
$processingAgent = $wsl2.CreateAgent("proc-1", "processing", @{})
$analyticsAgent = $wsl2.CreateAgent("analytics-1", "analytics", @{})

# Start agents
$wsl2.StartAgent($processingAgent)
$wsl2.StartAgent($analyticsAgent)

# Execute Linux task
$result = $wsl2.ExecuteLinuxTask("processing", @{
    DataFile = "/data/input.csv"
    Operation = "transform"
})

# Monitor health
$wsl2.MonitorAgentHealth()
```

### Razer Integration

```powershell
# Initialize Razer integration
$razer = New-RazerIntegration -Logger $logger
$razer.Initialize()

# Scan devices
$razer.ScanDevices()

# Set static color (Red)
$razer.SetChromaColor(@(255, 0, 0))

# Set breathing animation (Blue)
$razer.SetLightingMode("breathing", 3)

# Sync with system status
$razer.SyncWithSystemStatus("healthy")

# Set DPI
$razer.SetDPI(3200, $deviceId)

# Get device status
$status = $razer.GetDeviceStatus()
```

---

## API Reference

### CUDA Runtime

#### Methods

**Initialize(Logger)**

- Initializes CUDA runtime and devices
- Returns: bool

**DetectCudaToolkit()**

- Detects installed CUDA Toolkit
- Returns: bool

**DetectDevices()**

- Scans for CUDA-capable GPUs
- Returns: int (device count)

**SelectDevice(int deviceId)**

- Selects active GPU device
- Returns: bool

**AllocateMemory(long size, string label)**

- Allocates device memory
- Returns: object (allocation info)

**DeallocateMemory(string allocationId)**

- Frees allocated memory
- Returns: bool

**CreateStream(bool async)**

- Creates execution stream
- Returns: CudaStream

**SynchronizeStream(int streamId)**

- Blocks until stream completes
- Returns: bool

**CompileKernel(string sourceCode, string kernelName)**

- Compiles CUDA kernel
- Returns: bool

**GetMemoryStats()**

- Returns memory utilization statistics
- Returns: hashtable

### Device Manager

#### Methods

**DiscoverDevices()**

- Discovers all GPU devices
- Returns: bool

**SetLoadBalancingStrategy(string strategy)**

- Sets workload distribution strategy
- Strategies: round-robin, least-loaded, memory-aware, performance-aware
- Returns: void

**SelectDeviceForWorkload(long memory, int priority)**

- Selects best device for workload
- Returns: int (device ID)

**EnqueueTask(WorkloadTask task)**

- Queues task on appropriate device
- Returns: bool

**DistributeWorkload(array tasks)**

- Distributes multiple tasks
- Returns: array (queued tasks)

**StartMonitoring()**

- Starts device health monitoring
- Returns: bool

**GetDeviceStats()**

- Returns all device statistics
- Returns: hashtable

---

### Driver Manager

#### Methods

**ScanSystem()**

- Detects all hardware devices
- Returns: bool

**CheckForUpdates()**

- Checks for available driver updates
- Returns: bool

**DownloadDriver(string deviceId)**

- Downloads driver for device
- Returns: DriverPackage

**InstallDriver(DriverPackage package, string deviceId)**

- Installs driver silently
- Returns: bool

**VerifyInstallation(DriverPackage package, string deviceId)**

- Verifies successful installation
- Returns: bool

**InstallAllAvailableUpdates()**

- Installs all available driver updates
- Returns: bool

**GetInstallationHistory()**

- Returns installation records
- Returns: hashtable

**GetSystemDeviceReport()**

- Returns full device report
- Returns: array

---

### WSL2 Integration

#### Methods

**Initialize()**

- Initializes WSL2 integration
- Returns: bool

**InstallDistribution(string distroName)**

- Installs WSL2 distribution
- Returns: bool

**ProvisionEnvironment(string distro, hashtable packages)**

- Provisions Linux environment
- Returns: bool

**CreateAgent(string name, string type, hashtable config)**

- Creates Hermes agent instance
- Returns: HermesAgent

**StartAgent(HermesAgent agent)**

- Starts Hermes agent
- Returns: bool

**StartAllAgents()**

- Starts all agents
- Returns: bool

**ExecuteLinuxTask(string taskType, hashtable parameters)**

- Executes task on Linux agent
- Returns: hashtable (result)

**MonitorAgentHealth()**

- Monitors agent health
- Returns: bool

**GetAgentStatus()**

- Returns agent status information
- Returns: hashtable

---

### Razer Integration

#### Methods

**Initialize()**

- Initializes Razer integration
- Returns: bool

**ScanDevices()**

- Scans for connected Razer devices
- Returns: bool

**SetChromaColor(array rgb, string deviceId, int speed)**

- Sets device color
- RGB: [R, G, B] (0-255)
- Returns: bool

**SetLightingMode(string mode, int speed, string deviceId)**

- Sets lighting animation mode
- Modes: static, breathing, spectrum, wave, reactive, sync
- Returns: bool

**SetDPI(int dpi, string deviceId)**

- Sets mouse DPI
- Returns: bool

**SyncWithSystemStatus(string status)**

- Synchronizes lighting with system status
- Status: healthy, warning, alert, processing
- Returns: bool

**CreateCustomProfile(string name, string mode, array color, int speed)**

- Creates custom lighting profile
- Returns: bool

**ApplyProfile(string profileName, string deviceId)**

- Applies lighting profile
- Returns: bool

**DetectGameAndApplyProfile(string gameName)**

- Detects game and applies profile
- Returns: bool

**GetDeviceStatus()**

- Returns all device status information
- Returns: hashtable

---

## Testing

### Running Tests

```powershell
# Run all component tests
& "C:\HELIOS\hardware-integration\tests\Test-HardwareIntegration.ps1"

# Run specific components
& "C:\HELIOS\hardware-integration\tests\Test-HardwareIntegration.ps1" `
    -ComponentsToTest @('CUDA', 'Drivers')

# Save results to custom location
& "C:\HELIOS\hardware-integration\tests\Test-HardwareIntegration.ps1" `
    -OutputFile "C:\Results\hw-tests.json"
```

### Test Coverage

**CUDA Tests (8 tests)**

- Runtime initialization
- Device detection
- Compute capability verification
- Memory allocation
- Stream creation
- Multi-GPU workload distribution
- Device health monitoring
- Error recovery

**Driver Tests (10 tests)**

- System hardware scan
- Device categorization
- Driver version checking
- Update availability detection
- Driver download
- Driver installation
- Installation verification
- Automatic rollback
- Installation history tracking
- Batch driver installation

**WSL2 Tests (10 tests)**

- WSL2 detection
- Distribution discovery
- Environment provisioning
- Linux command execution
- Hermes agent creation
- Agent lifecycle management
- Cross-platform messaging
- Linux task execution
- Agent health monitoring
- Agent auto-recovery

**Razer Tests (12 tests)**

- Razer Synapse detection
- Device scanning
- Device identification
- Battery monitoring
- DPI profile management
- Static color lighting
- Breathing animation
- Spectrum cycling
- System status sync
- Game detection
- Custom profile creation
- Profile application

**Total: 40+ Test Cases**

---

## Troubleshooting

### CUDA Issues

**Problem**: CUDA Toolkit not detected

```powershell
# Solution: Verify installation
$cuda = New-CudaRuntime
if (-not $cuda.DetectCudaToolkit()) {
    Write-Host "Install CUDA from: https://developer.nvidia.com/cuda-toolkit"
}
```

**Problem**: No CUDA devices found

```powershell
# Solution: Check device and compute capability
nvidia-smi -a
# Verify compute capability ≥ 5.0
```

### Driver Issues

**Problem**: Driver installation failed

```powershell
# Solution: Check Windows Update settings
Get-Service wuauserv | Start-Service
# Try manual installation with admin privileges
```

**Problem**: Rollback failed

```powershell
# Solution: Create manual restore point
Checkpoint-Computer -Description "Pre-Driver-Update" -RestorePointType "MODIFY_SETTINGS"
```

### WSL2 Issues

**Problem**: WSL2 not installed

```powershell
# Solution: Enable WSL2
wsl --install
# Or enable manually through Settings > Apps > Optional features
```

**Problem**: Agent communication fails

```powershell
# Solution: Check agent port availability
netstat -ano | findstr :5000
```

### Razer Issues

**Problem**: Razer Synapse not detected

```powershell
# Solution: Reinstall Razer Synapse from official source
# https://www.razerzone.com/synapse-3
```

**Problem**: Devices not responding

```powershell
# Solution: Restart Razer Synapse
Stop-Process -Name "RazerSynapse3" -Force
Start-Sleep -Seconds 2
& "C:\Program Files\Razer\Razer Synapse 3\RazerSynapse3.exe"
```

---

## Performance Considerations

### CUDA Optimization

- Use stream management for concurrent operations
- Monitor memory utilization to avoid allocations
- Profile kernels with device-specific optimizations

### Driver Management

- Schedule driver updates during maintenance windows
- Test updates in staging environment first
- Keep installation history for debugging

### WSL2 Agents

- Distribute workload based on agent type
- Monitor agent memory usage
- Use auto-recovery for reliability

### Razer Lighting

- Use static colors for minimal system impact
- Batch updates to reduce USB traffic
- Disable reactive lighting under high load

---

## Version Information

**Phase 2 Hardware Integration v1.0**

- Release Date: April 2026
- CUDA Support: 11.0+
- Driver Frameworks: Windows 10/11 (21H1+)
- WSL2: Windows 11 Build 22000+
- Razer Synapse: 3.0+

---

## Support & Feedback

For issues, questions, or feature requests:

1. Check troubleshooting section above
2. Review test results for diagnostics
3. Check HELIOS logs in `C:\HELIOS\logs\`
4. Create detailed bug report with logs and system info

---

**End of Documentation**
