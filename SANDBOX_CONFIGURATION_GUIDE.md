# Sandbox Environment Configuration Guide

## Overview

Phase 10 provides a comprehensive sandbox environment for safely analyzing suspicious files without affecting the main system. This guide covers configuration, deployment, and usage of all sandbox services.

## System Requirements

### Hardware

- **CPU**: Multi-core processor (minimum 4 cores recommended)
- **RAM**: 8 GB minimum (16 GB recommended)
- **Disk**: 50 GB free space (for sandbox partition H:)
- **GPU**: Optional NVIDIA GPU for pass-through support

### Software

- **OS**: Windows 10/11 (Pro, Enterprise, or Education edition)
- **.NET**: .NET 8.0 or later
- **Windows Sandbox**: Enable optional feature (Windows 10 Pro/Enterprise and above)
- **Hyper-V**: Enable for VM-based sandboxes (alternative to Windows Sandbox)

### Permissions

- Administrator privileges required
- UAC (User Account Control) enabled

## Installation

### 1. Enable Windows Sandbox (Optional)

```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All -Online
```

### 2. Enable Hyper-V (Alternative)

```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -FeatureName "Microsoft-Hyper-V-All" -Online
```

### 3. Setup Sandbox Partition (H:)

```powershell
# Create H: partition (if not existing)
# Use Disk Management or:
New-Partition -DiskNumber 1 -Size 50GB -DriveLetter H
Format-Volume -DriveLetter H -FileSystem NTFS -NewFileSystemLabel "Sandbox"
```

### 4. Deploy HELIOS Sandbox Services

```powershell
cd C:\helios-platform\src\HELIOS.Platform\Phase10\Sandbox
dotnet publish -c Release -o "C:\Program Files\HELIOS\Sandbox"
```

## Configuration

### Basic Configuration

Create `sandbox-config.json`:

```json
{
  "Environment": {
    "SandboxType": "WindowsSandbox",
    "StoragePath": "H:\\Sandbox",
    "MaxConcurrentSandboxes": 4
  },
  "ResourceLimits": {
    "CpuCores": 4,
    "RamMb": 4096,
    "DiskGb": 20,
    "NetworkBandwidthMbps": 100
  },
  "Network": {
    "IsolationPolicy": "Restricted",
    "AllowedDomains": [],
    "BlockedDomains": ["malicious.com"]
  },
  "Security": {
    "GpuPassthrough": true,
    "AudioInput": false,
    "VideoInput": false,
    "PrinterRedirection": false,
    "ClipboardRedirection": "Bidirectional"
  },
  "Snapshots": {
    "EnableScheduling": true,
    "ScheduleIntervalSeconds": 300,
    "MaxSnapshotsPerSandbox": 10,
    "CompressionEnabled": true
  },
  "Monitoring": {
    "EnableFileOperationTracking": true,
    "EnableRegistryTracking": true,
    "EnableNetworkTracking": true,
    "EnableProcessTracking": true,
    "ThreatDetectionLevel": "High"
  }
}
```

### Advanced Configuration

#### Network Isolation Policies

```csharp
public enum NetworkIsolationPolicy
{
    Full,              // Complete network isolation
    Restricted,        // Limited to localhost
    LocalhostOnly,     // Only local connections
    CustomRules        // Custom allow/deny rules
}
```

#### Resource Limits

```csharp
var limits = new SandboxResourceLimits
{
    CpuCores = 4,                    // CPU cores allocated
    RamMb = 4096,                    // RAM in MB
    DiskGb = 20,                     // Disk space in GB
    NetworkBandwidthMbps = 1000      // Network bandwidth limit
};
```

## Service Configuration

### 1. SandboxEnvironmentSetup

Initializes and configures sandbox environment:

```csharp
var setup = new SandboxEnvironmentSetup("C:\\sandbox-config");
await setup.InitializeAsync();

// Configure partition
await setup.SetupSandboxPartitionAsync("H:\\Sandbox", 50);

// Configure shared folder
await setup.ConfigureSharedFolderAsync("C:\\Uploads", "C:\\Shared");

// Set resource limits
var limits = new SandboxResourceLimits 
{ 
    CpuCores = 4, 
    RamMb = 4096, 
    DiskGb = 20 
};
await setup.SetResourceLimitsAsync(limits);

// Enable GPU pass-through
await setup.EnableGpuPassThroughAsync();

// Create snapshot capability
await setup.CreateSnapshotCapabilityAsync();

// Get environment info
var info = await setup.GetEnvironmentInfoAsync();
```

### 2. SandboxLauncher

Manages sandbox instance lifecycle:

```csharp
var launcher = new SandboxLauncher();
await launcher.InitializeAsync();

// Launch sandbox
var options = new SandboxLaunchOptions
{
    SandboxName = "Analysis_001",
    ResourceLimits = new SandboxResourceLimits { CpuCores = 2, RamMb = 2048 },
    NetworkPolicy = NetworkIsolationPolicy.Restricted,
    TimeoutSeconds = 300
};

var sandbox = await launcher.LaunchSandboxAsync(options);

// Mount shared folder
await launcher.MountSharedFolderAsync(sandbox, "C:\\Uploads", "C:\\Shared");

// Execute command
var result = await launcher.ExecuteInSandboxAsync(sandbox, "cmd.exe /c analysis.exe", 30);

// Terminate sandbox
await launcher.TerminateSandboxAsync(sandbox);
```

### 3. SandboxFileTransfer

Manages file operations:

```csharp
var fileTransfer = new SandboxFileTransfer();
await fileTransfer.InitializeAsync();

// Transfer file to sandbox
await fileTransfer.TransferFileToSandboxAsync(
    sandbox, 
    "C:\\Uploads\\suspect.exe", 
    "C:\\Analysis\\file.exe");

// Monitor file activity
var activity = await fileTransfer.MonitorFileInSandboxAsync(
    sandbox, 
    "C:\\Analysis\\file.exe");

// Capture all activity
var report = await fileTransfer.CaptureActivityAsync(sandbox);

// Verify no contamination
var contamination = await fileTransfer.VerifyNoContaminationAsync(sandbox);

// Transfer results back
await fileTransfer.TransferFileFromSandboxAsync(
    sandbox, 
    "C:\\Analysis\\Results\\report.txt", 
    "C:\\Results\\report.txt");

// Archive analysis
await fileTransfer.ArchiveAnalysisResultsAsync(sandbox, "C:\\Archives\\analysis_001.zip");
```

### 4. SandboxMonitor

Monitors sandbox activity:

```csharp
var monitor = new SandboxMonitor();
await monitor.InitializeAsync();

// Start monitoring
await monitor.StartMonitoringAsync(sandbox);

// Get monitored activities
var fileOps = await monitor.GetFileOperationsAsync(sandbox);
var regOps = await monitor.GetRegistryAccessAsync(sandbox);
var netOps = await monitor.GetNetworkAccessAsync(sandbox);
var procOps = await monitor.GetProcessActivityAsync(sandbox);

// Generate activity report
var report = await monitor.GenerateActivityReportAsync(sandbox);

// Detect malware behavior
var threatResult = await monitor.DetectMalwareBehaviorAsync(sandbox);
if (threatResult.ThreatDetected)
{
    Console.WriteLine($"Threat Level: {threatResult.ThreatLevel}");
    Console.WriteLine($"Indicators: {string.Join(", ", threatResult.ThreatIndicators)}");
}

// Auto-terminate on danger
var autoTerminated = await monitor.AutoTerminateOnDangerAsync(sandbox);

// Stop monitoring
await monitor.StopMonitoringAsync(sandbox);
```

### 5. SandboxSnapshotManager

Manages snapshots:

```csharp
var snapshotManager = new SandboxSnapshotManager("H:\\Snapshots");
await snapshotManager.InitializeAsync();

// Create snapshot
var snapshot = await snapshotManager.CreateSnapshotAsync(sandbox, "clean-state");

// Get all snapshots
var snapshots = await snapshotManager.GetSnapshotsAsync(sandbox);

// Restore from snapshot
await snapshotManager.RestoreFromSnapshotAsync(sandbox, snapshot);

// Compress snapshot
await snapshotManager.CompressSnapshotAsync(snapshot);

// Schedule automatic snapshots
await snapshotManager.ScheduleSnapshotAsync(sandbox, TimeSpan.FromMinutes(5));

// Rapid rollback
await snapshotManager.RapidRollbackAsync(sandbox);

// Get management report
var mgmtReport = await snapshotManager.GetManagementReportAsync(sandbox);
Console.WriteLine($"Total Snapshots: {mgmtReport.TotalSnapshots}");
Console.WriteLine($"Storage Used: {mgmtReport.TotalStorageMb} MB");

// Delete snapshot
await snapshotManager.DeleteSnapshotAsync(snapshot);
```

## Integration with Orchestrator

The `SandboxOrchestrator` coordinates all services:

```csharp
var setup = new SandboxEnvironmentSetup();
var launcher = new SandboxLauncher();
var fileTransfer = new SandboxFileTransfer();
var monitor = new SandboxMonitor();
var snapshotManager = new SandboxSnapshotManager();

var orchestrator = new SandboxOrchestrator(
    setup, launcher, fileTransfer, monitor, snapshotManager);

// Initialize all services
await orchestrator.InitializeAsync();

// Analyze single file
var options = new SandboxAnalysisOptions
{
    TimeoutSeconds = 300,
    ArchiveResults = true,
    EnableMonitoring = true
};

var result = await orchestrator.AnalyzeSuspiciousFileAsync(
    "C:\\Uploads\\suspect.exe", 
    options);

Console.WriteLine($"Is Safe: {result.IsSafe}");
Console.WriteLine($"Threat Level: {result.ThreatLevel}");
Console.WriteLine($"Behaviors: {string.Join(", ", result.SuspiciousBehaviors)}");

// Analyze multiple files
var files = new[] { "file1.exe", "file2.dll" };
var batchResult = await orchestrator.AnalyzeSuspiciousFilesAsync(files, options);

// Shutdown
await orchestrator.ShutdownAsync();
```

## Performance Tuning

### CPU Optimization

- Allocate 2-4 cores for analysis tasks
- Monitor CPU usage: `Get-Process | Sort-Object CPU -Descending`

### Memory Optimization

- Base allocation: 2-4 GB RAM per sandbox
- Monitor: `Get-Process | Sort-Object WorkingSet -Descending`

### Disk Optimization

- Use SSD for snapshots
- Enable compression for long-term storage
- Periodic cleanup: `Get-ChildItem H:\Sandbox -Recurse | Where {$_.LastAccessTime -lt (Get-Date).AddDays(-30)} | Remove-Item`

### Network Optimization

- Use local analysis when possible
- Restrict network bandwidth for suspected malware
- Enable DNS-over-HTTPS for safety

## Monitoring and Logging

### Enable Detailed Logging

```csharp
// Configure logging
var logger = LoggerFactory.Create(builder =>
{
    builder.AddConsole()
           .AddDebug()
           .SetMinimumLevel(LogLevel.Debug);
});
```

### Monitor Key Metrics

```csharp
// Get environment info
var info = await orchestrator.GetEnvironmentInfoAsync();
Console.WriteLine($"Sandbox Available: {info.IsAvailable}");
Console.WriteLine($"Type: {info.SandboxType}");
Console.WriteLine($"Max Concurrent: {info.MaxConcurrentSandboxes}");
```

### Health Checks

```powershell
# Check Windows Sandbox
Get-Process | Where-Object {$_.ProcessName -eq "WindowsSandbox"}

# Check Hyper-V VMs
Get-VM | Where-Object {$_.State -eq "Running"}

# Check disk usage
Get-Volume -DriveLetter H | Select-Object SizeRemaining, Size

# Check network isolation
Get-NetFirewallRule -Direction Inbound -Action Block
```

## Troubleshooting

### Windows Sandbox Not Available

```powershell
# Verify feature is installed
Get-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM"

# Enable if needed
Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All
```

### Hyper-V Issues

```powershell
# Check Hyper-V status
Get-VMHost

# Verify virtualization support
Get-ComputerInfo | Select-Object HyperVRequirementVirtualizationCapable
```

### Disk Space Issues

```powershell
# Clean old snapshots
Remove-Item "H:\Snapshots\*" -Recurse -Force

# Compact snapshots
Compact-Volume -DriveLetter H -UsageType Default
```

### Network Isolation Problems

```powershell
# Check firewall rules
Get-NetFirewallProfile

# Reset network settings
ipconfig /all
```

## Security Best Practices

1. **Isolation**
   - Always use Full network isolation for untrusted files
   - Enable all monitoring features
   - Use snapshots for clean state verification

2. **File Handling**
   - Never execute analysis files on the host
   - Always verify contamination
   - Archive results for future analysis

3. **Monitoring**
   - Enable all monitoring features by default
   - Review threat detection results
   - Auto-terminate on critical threats

4. **Snapshots**
   - Create snapshots before analysis
   - Enable compression for storage
   - Implement retention policies

5. **Resource Limits**
   - Set appropriate limits per sandbox
   - Monitor resource usage
   - Terminate runaway processes

## Advanced Usage

### Custom Threat Detection

Extend `SandboxMonitor` for custom detection:

```csharp
public class CustomThreatDetector : SandboxMonitor
{
    public async Task<bool> DetectCustomThreat(SandboxInstance sandbox)
    {
        var operations = await GetFileOperationsAsync(sandbox);
        // Implement custom detection logic
        return false;
    }
}
```

### Batch Analysis

```csharp
var files = Directory.GetFiles("C:\\Quarantine", "*.exe");
var tasks = files.Select(f => orchestrator.AnalyzeSuspiciousFileAsync(f, options));
var results = await Task.WhenAll(tasks);

var threats = results.Where(r => !r.IsSafe).ToList();
Console.WriteLine($"Threats detected: {threats.Count}");
```

### Automated Reporting

```csharp
foreach (var result in results)
{
    Console.WriteLine($"File: {result.FilePath}");
    Console.WriteLine($"Safe: {result.IsSafe}");
    Console.WriteLine($"Threat Level: {result.ThreatLevel}");
    Console.WriteLine($"Archive: {result.ArchivePath}");
}
```

## Support and Documentation

For issues and additional information:

- Review log files in `%APPDATA%\HELIOS\Logs\`
- Check system events in Event Viewer
- Contact HELIOS support team

## Version History

- **1.0.0** - Initial release with 5 core services
  - SandboxEnvironmentSetup
  - SandboxLauncher
  - SandboxFileTransfer
  - SandboxMonitor
  - SandboxSnapshotManager
