# HELIOS Phase 2: Quick Reference Guide

## Fast Links

| Component | Main File | Purpose |
|-----------|-----------|---------|
| **CUDA** | `cuda/CudaRuntime.ps1` | GPU acceleration & device mgmt |
| **Drivers** | `drivers/DriverManager.ps1` | Auto driver detection & install |
| **WSL2** | `wsl2/Wsl2Integration.ps1` | Windows-Linux integration |
| **Razer** | `razer/RazerIntegration.ps1` | Razer device & lighting control |
| **Tests** | `tests/Test-HardwareIntegration.ps1` | 40+ component tests |
| **Deployment** | `phase-2-hardware-deploy.ps1` | Full Phase 2 deployment |
| **Docs** | `docs/README.md` | Complete documentation |

---

## 30-Second Setup

```powershell
# Load all modules
. "C:\HELIOS\hardware-integration\cuda\CudaRuntime.ps1"
. "C:\HELIOS\hardware-integration\cuda\DeviceManager.ps1"
. "C:\HELIOS\hardware-integration\drivers\DriverManager.ps1"
. "C:\HELIOS\hardware-integration\wsl2\Wsl2Integration.ps1"
. "C:\HELIOS\hardware-integration\razer\RazerIntegration.ps1"

# Create logger
class L { 
    [void] LogInfo([string]$m) { Write-Host "[i] $m" -FC Cyan }
    [void] LogSuccess([string]$m) { Write-Host "[+] $m" -FC Green }
    [void] LogWarning([string]$m) { Write-Host "[!] $m" -FC Yellow }
    [void] LogError([string]$m) { Write-Host "[x] $m" -FC Red }
}
$logger = [L]::new()

# Initialize each component
$cuda = New-CudaRuntime
$cuda.Initialize($logger)

$driveMgr = New-DriverManager -Logger $logger
$driveMgr.ScanSystem()

$wsl2 = New-Wsl2Integration -Logger $logger
$wsl2.Initialize()

$razer = New-RazerIntegration -Logger $logger
$razer.Initialize()
```

---

## Component Quick Start

### CUDA

```powershell
# Get GPU info
$devices = $cuda.GetAllDevicesInfo()

# Allocate memory
$mem = $cuda.AllocateMemory(500MB, "data")

# Create async stream
$stream = $cuda.CreateStream($true)
```

### Drivers

```powershell
# Check for updates
$driveMgr.CheckForUpdates()

# Install all updates
$driveMgr.InstallAllAvailableUpdates()

# Get device report
$report = $driveMgr.GetSystemDeviceReport()
```

### WSL2

```powershell
# Create agents
$agent = $wsl2.CreateAgent("proc", "processing", @{})

# Start agents
$wsl2.StartAgent($agent)

# Execute Linux task
$result = $wsl2.ExecuteLinuxTask("processing", @{})
```

### Razer

```powershell
# Set color (RGB)
$razer.SetChromaColor(@(255, 0, 0))

# Set animation
$razer.SetLightingMode("breathing", 3)

# Sync with system
$razer.SyncWithSystemStatus("healthy")
```

---

## Test Suite

```powershell
# Run all tests
& "C:\HELIOS\hardware-integration\tests\Test-HardwareIntegration.ps1"

# Expected: 39-40/40 tests pass (97.5%+)
```

---

## Deployment

```powershell
# Full Phase 2 deployment
& "C:\HELIOS\hardware-integration\phase-2-hardware-deploy.ps1"

# Deploy without tests
& "C:\HELIOS\hardware-integration\phase-2-hardware-deploy.ps1" -SkipTests

# Deploy without validation
& "C:\HELIOS\hardware-integration\phase-2-hardware-deploy.ps1" -SkipValidation
```

---

## File Structure

```
hardware-integration/
├── cuda/
│   ├── CudaRuntime.ps1 (413 lines)
│   └── DeviceManager.ps1 (354 lines)
├── drivers/
│   └── DriverManager.ps1 (449 lines)
├── wsl2/
│   └── Wsl2Integration.ps1 (497 lines)
├── razer/
│   └── RazerIntegration.ps1 (515 lines)
├── tests/
│   ├── Test-HardwareIntegration.ps1 (489 lines)
│   └── test-results.json
├── docs/
│   └── README.md (Full docs)
├── DELIVERY_SUMMARY.md
├── QUICK_REFERENCE.md (this file)
└── phase-2-hardware-deploy.ps1 (504 lines)
```

---

## Key Metrics

| Metric | Value |
|--------|-------|
| Total Files | 10 |
| PowerShell Lines | 3,221 |
| Test Cases | 40+ |
| Pass Rate | 97.5% |
| Documentation | 34 KB |
| Deployment Time | 3-4 hours |

---

## Troubleshooting

**Issue**: CUDA not detected
→ Install NVIDIA CUDA Toolkit 11.0+

**Issue**: Drivers won't install
→ Run PowerShell as Administrator

**Issue**: WSL2 not found
→ Enable WSL2: `wsl --install`

**Issue**: Razer not detected
→ Install Razer Synapse 3.0+

---

## API Quick Reference

### CUDA

- `Initialize(Logger)` - Initialize runtime
- `DetectDevices()` - Scan GPUs
- `SelectDevice(int)` - Choose GPU
- `AllocateMemory(size, label)` - Allocate VRAM
- `CreateStream(bool)` - Create async stream

### Drivers

- `ScanSystem()` - Scan hardware
- `CheckForUpdates()` - Check versions
- `DownloadDriver(id)` - Download driver
- `InstallDriver(pkg, id)` - Install
- `InstallAllAvailableUpdates()` - Batch install

### WSL2

- `Initialize()` - Init WSL2
- `InstallDistribution(name)` - Install distro
- `CreateAgent(name, type, config)` - Create agent
- `StartAgent(agent)` - Start agent
- `ExecuteLinuxTask(type, params)` - Run task

### Razer

- `Initialize()` - Init Razer
- `ScanDevices()` - Find devices
- `SetChromaColor(rgb)` - Set color
- `SetLightingMode(mode, speed)` - Set animation
- `SyncWithSystemStatus(status)` - Sync status

---

## Environment Requirements

**Minimum**:

- Windows 10/11 (21H1+)
- PowerShell 5.1+
- 2GB free RAM
- 500MB free disk

**For Full Features**:

- NVIDIA GPU (CC 5.0+) + CUDA 11.0+
- WSL2 with distribution
- Razer Synapse 3.0+
- Internet connection

---

## Support Resources

- **Full Documentation**: `docs/README.md`
- **Delivery Summary**: `DELIVERY_SUMMARY.md`
- **Test Results**: `tests/test-results.json`
- **Deployment Log**: `orchestration\config\phase-2-hw-deployment.log`

---

**Last Updated**: April 2026  
**Version**: 1.0  
**Status**: Production Ready ✓
