# HELIOS Platform System Requirements

**Version:** 1.0.0.0  
**Release Date:** 2024  
**Status:** Production Ready

---

## Absolute Minimum Requirements

| Component | Minimum | Why Required |
|-----------|---------|--------------|
| **Operating System** | Windows 11 (Build 22000+) | Modern Windows API features, security patches |
| **.NET SDK** | 8.0 | Platform depends on .NET runtime |
| **RAM** | 4 GB | Minimum for core operations |
| **Disk Space** | 2 GB free | Installation + configuration files |
| **Processor** | 1 GHz, single-core | Basic operations |
| **Administrator** | Yes | Registry modifications, service installation |

---

## Recommended Configuration

| Component | Recommendation | Rationale |
|-----------|-----------------|-----------|
| **Operating System** | Windows 11 Pro, Build 22621+ | Latest security patches, better performance |
| **.NET Version** | .NET 8.0 LTS or .NET 9.0 | Latest features, long-term support |
| **PowerShell** | 7.4 or later | Advanced scripting, better performance |
| **RAM** | 8-16 GB | Smooth multi-component operation |
| **Processor** | Multi-core, 3 GHz+ | Parallel processing, faster operations |
| **Disk** | SSD, 20 GB free | Faster startup, better throughput |
| **Network** | 100 Mbps+ | Faster updates, better telemetry |

---

## Detailed System Requirements

### Operating System

**Supported:**

- Windows 11 Pro (Build 22621+)
- Windows 11 Enterprise (Build 22621+)
- Windows Server 2022 (may work, not officially supported)
- Windows Server 2025 (may work, not officially supported)

**Not Supported:**

- ✗ Windows 10
- ✗ Windows 11 Home Edition
- ✗ Windows 8.1 or earlier
- ✗ Non-Windows platforms

**Verification:**

```powershell
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption)"
Write-Host "Version: $($os.Version)"
Write-Host "Build: $($os.BuildNumber)"
```

### .NET SDK

**Supported Versions:**

- .NET 8.0 (LTS - Long Term Support until November 2026)
- .NET 9.0 (STS - Support until May 2025)

**Installation Methods:**

1. **Official Installer:**
   - Visit: https://dotnet.microsoft.com/download
   - Download: .NET 8 SDK (x64 for Windows)
   - Run MSI installer

2. **Windows Package Manager:**

   ```powershell
   winget install Microsoft.DotNet.SDK.8
   ```

3. **Chocolatey:**

   ```powershell
   choco install dotnet-sdk
   ```

4. **Docker:**

   ```dockerfile
   FROM mcr.microsoft.com/windows/servercore:ltsc2022
   RUN powershell -Command Invoke-WebRequest -Uri https://dot.net/v1/dotnet-install.ps1 -OutFile C:\dotnet-install.ps1
   RUN powershell -Command C:\dotnet-install.ps1 -Channel 8.0
   ```

**Verification:**

```powershell
dotnet --version       # SDK version
dotnet --list-sdks     # All installed SDKs
dotnet --list-runtimes # All installed runtimes
```

### PowerShell

**Supported Versions:**

- PowerShell 7.0 or later (7.4+ recommended)

**Installation:**

1. **Microsoft Store (Easiest):**
   - Search: "PowerShell"
   - Click "Install"

2. **Direct Download:**
   - GitHub: https://github.com/PowerShell/PowerShell/releases
   - Download: `PowerShell-7.4.0-win-x64.msi`
   - Run installer

3. **Windows Package Manager:**

   ```powershell
   winget install Microsoft.PowerShell
   ```

4. **Chocolatey:**

   ```powershell
   choco install pwsh
   ```

**Verification:**

```powershell
pwsh --version              # Modern PowerShell
$PSVersionTable.PSVersion   # Current PowerShell version
```

### Memory (RAM)

**Minimum:** 4 GB

- Core HELIOS Platform
- Basic monitoring
- Standard workloads

**Recommended:** 8-16 GB

- Production deployments
- Multiple concurrent operations
- Advanced monitoring
- Data aggregation

**For Enterprise:** 16 GB+

- Large-scale deployments
- Distributed systems
- High-frequency monitoring
- Historical data analysis

**Verification:**

```powershell
# Get system RAM
$ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
Write-Host "Total RAM: $([math]::Round($ram, 1)) GB"

# Get available RAM
$available = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
Write-Host "Available RAM: $([math]::Round($available, 0)) MB"
```

### Disk Space

**Minimum Installation:** 2 GB

- HELIOS Platform core
- Base configuration
- Minimal logging

**With Standard Logging:** 5 GB

- Application files
- Configuration data
- 30 days of logs

**With Full Monitoring:** 20 GB

- All components
- Extended logging
- Historical data
- Performance metrics

**Verification:**

```powershell
# Check C: drive space
$drive = Get-PSDrive C
$freeGB = [math]::Round($drive.Free / 1GB, 2)
$usedGB = [math]::Round($drive.Used / 1GB, 2)
$totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)

Write-Host "Total: $totalGB GB | Used: $usedGB GB | Free: $freeGB GB"
```

### Processor

**Minimum:** 1 GHz single-core processor

- Basic operations
- Development/testing
- Single-system deployment

**Recommended:** Multi-core, 3 GHz+

- Production systems
- Multiple concurrent tasks
- Distributed deployments
- Real-time monitoring

**Recommended by Tier:**

| Tier | CPU | Cores | Frequency |
|------|-----|-------|-----------|
| Professional | Intel i7 / AMD Ryzen 7 | 4+ | 3.0+ GHz |
| Enterprise | Intel Xeon / AMD EPYC | 8+ | 2.5+ GHz |
| Ultimate | High-end Xeon / EPYC | 16+ | 3.0+ GHz |

**Verification:**

```powershell
# Get CPU information
$cpu = Get-CimInstance Win32_Processor
Write-Host "Processor: $($cpu.Name)"
Write-Host "Cores: $($cpu.NumberOfCores)"
Write-Host "Logical Processors: $($cpu.NumberOfLogicalProcessors)"
Write-Host "Max Speed: $($cpu.MaxClockSpeed) MHz"
```

### Network

**Minimum:**

- Internet for installation verification
- Network for deployment targets

**For Cloud Integration:**

- 100 Mbps for standard operations
- 1 Gbps recommended for large deployments
- Low latency (<50ms) for remote monitoring

**Firewall Requirements:**

**Outbound Ports:**

- 443 (HTTPS) - Updates, telemetry
- 80 (HTTP) - Documentation
- 8080-8090 - Custom APIs

**Inbound Ports (if service):**

- 8000-8999 - Application services
- Custom ports for integrations

### Display

**Minimum:**

- 1024x768 resolution
- WDDM 1.0 compatible GPU
- Text mode operation supported

**Recommended:**

- 1920x1080 or higher
- Modern GPU (Intel HD 630+, NVIDIA GTX 1050+, AMD equivalent)
- Multi-monitor support

---

## Tier-Specific Requirements

### Professional Tier

**Typical Use:** Small to medium enterprise

**Minimum:**

- Windows 11 Pro
- .NET 8.0
- 4 GB RAM
- 5 GB disk
- Single processor

**Recommended:**

- Windows 11 Pro
- .NET 8.0 LTS
- 8 GB RAM
- 20 GB disk SSD
- Dual-core 3 GHz+

### Enterprise Tier

**Typical Use:** Medium to large enterprise

**Minimum:**

- Windows 11 Enterprise or Windows Server 2022
- .NET 8.0 LTS
- 8 GB RAM
- 10 GB disk
- Quad-core processor

**Recommended:**

- Windows Server 2022
- .NET 8.0 LTS
- 16 GB RAM
- 50 GB SSD
- 8-core 3 GHz+
- Active Directory integration

### Ultimate Tier

**Typical Use:** Large-scale distributed systems

**Minimum:**

- Windows Server 2022/2025
- .NET 8.0 LTS
- 16 GB RAM
- 50 GB disk
- 8-core processor

**Recommended:**

- Windows Server 2025
- .NET 8.0 LTS or .NET 9.0
- 32 GB RAM
- 100+ GB SSD
- 16-core Xeon/EPYC
- SQL Server backend (optional)
- Load balancer (for HA)

---

## Pre-Installation Checklist

- [ ] Windows 11 Pro or Enterprise installed
- [ ] Administrator account available
- [ ] .NET 8 SDK installed and verified
- [ ] PowerShell 7+ installed
- [ ] At least 2 GB free disk space
- [ ] 4 GB RAM minimum available
- [ ] Internet connection for installation
- [ ] No antivirus blocking installation
- [ ] UAC (User Account Control) accessible
- [ ] System is fully patched and updated

---

## Virtualization Support

### Hyper-V (Recommended)

```powershell
# Hyper-V VM Configuration for HELIOS
# CPU: 4 cores
# RAM: 8 GB
# Storage: 50 GB VHDX
# Network: Bridged to host

New-VM -Name HELIOS-VM `
    -MemoryStartupBytes 8GB `
    -NewVHDPath "C:\VMs\HELIOS.vhdx" `
    -NewVHDSizeBytes 50GB `
    -Generation 2
```

### VMware ESXi

- vSAN/NVMe storage recommended
- Minimum 4 vCPU, 8 GB vRAM
- VM network in production VLAN
- Latest VMware Tools

### VirtualBox

- Minimum 6.1
- 4 CPU cores allocated
- 8 GB RAM minimum
- VirtualBox Additions installed

### Azure

- VM Size: Standard_D4s_v3 or larger
- OS: Windows 11 Pro or Windows Server 2022
- Network: Virtual network with NSG

### AWS

- Instance Type: t3.xlarge or larger
- AMI: Windows Server 2022 or Windows 11 Pro
- Security Group: Allow required ports

---

## Performance Tuning

### For Optimal Performance

```powershell
# Disable visual effects
$path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty -Path $path -Name "ListviewAlphaSelect" -Value 0
Set-ItemProperty -Path $path -Name "ListviewShadow" -Value 0

# Increase max file handles
reg add "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" ^
    /v FastSendDatagramThreshold /t REG_DWORD /d 1024 /f

# Optimize network performance
netsh int tcp set global autotuninglevel=normal
netsh int tcp set global congestionprovider=bbr
```

### Disable Unnecessary Services

```powershell
# Disable services that may interfere
$servicesToDisable = @(
    "DiagTrack",           # Connected User Experiences and Telemetry
    "dmwappushservice",    # dmwappushservice
    "MapsBroker",          # Maps
    "TrkWks"               # Distributed Link Tracking
)

foreach ($service in $servicesToDisable) {
    Stop-Service -Name $service -ErrorAction SilentlyContinue
    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
}
```

---

## Security Recommendations

- Keep Windows fully patched
- Keep .NET SDK updated
- Use Windows Defender or enterprise antivirus
- Enable Windows Firewall
- Restrict local administrator access
- Use strong passwords for admin accounts
- Enable auditing for security events
- Use full disk encryption (BitLocker)
- Keep PowerShell execution policy restricted
- Regular security backups

---

## Troubleshooting System Requirements Issues

### "Insufficient Resources" Error

1. Check current resource usage
2. Close unnecessary applications
3. Increase virtual memory
4. Upgrade RAM
5. Use SSD for better performance

### Performance Degradation

1. Monitor system resources
2. Check for malware
3. Review event logs
4. Disable unnecessary services
5. Optimize disk space

### Installation Fails on Virtual Machine

1. Ensure VM has sufficient resources
2. Update VM tools
3. Enable VM acceleration features
4. Check VM network connectivity
5. Try different storage backend

---

## Compatibility Matrix

| Feature | Windows 11 Pro | Windows 11 Enterprise | Windows Server 2022 | Windows Server 2025 |
|---------|---|---|---|---|
| Full Installation | ✓ | ✓ | ✓* | ✓* |
| All Components | ✓ | ✓ | ~* | ~* |
| Domain Integration | ✓ | ✓ | ✓ | ✓ |
| Group Policy | ✓ | ✓ | ✓ | ✓ |
| Active Directory | ✓ | ✓ | ✓ | ✓ |

*: Server editions not officially supported but likely compatible

---

## Support Contact

- **For compatibility questions:** support@helios.solutions
- **For installation issues:** https://docs.helios.solutions
- **For performance tuning:** https://community.helios.solutions

---

**Document Version:** 1.0.0.0  
**Last Updated:** 2024  
**Next Review:** 2025
