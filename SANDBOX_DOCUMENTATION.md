# HELIOS Phase 10: Sandbox Environment - Complete Documentation

## Executive Summary

Phase 10 implements a comprehensive sandbox environment for safely analyzing suspicious files without compromising the main system. This enterprise-grade solution provides:

- **5 Production Services** for complete sandbox lifecycle management
- **25+ Unit Tests** ensuring reliability and correctness
- **Multi-layer Monitoring** for threat detection
- **Snapshot Management** for rapid recovery
- **Network Isolation** for secure analysis
- **GPU Support** for advanced analysis

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│           SandboxOrchestrator (Main Orchestrator)       │
│                                                         │
│  Coordinates all services and manages workflows        │
└─────────────────────────────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌──────────────────┐ ┌────────────────┐ ┌─────────────────┐
│ Environment      │ │ Launcher       │ │ File Transfer   │
│ Setup            │ │                │ │                 │
│ - Initialization │ │ - Launch       │ │ - Transfer      │
│ - Partition      │ │ - Execute      │ │ - Monitor       │
│ - Limits         │ │ - Terminate    │ │ - Archive       │
└──────────────────┘ └────────────────┘ └─────────────────┘
         │                  │                  │
         └──────────────────┼──────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌──────────────────┐ ┌────────────────┐ ┌─────────────────┐
│ Monitor          │ │ Snapshot       │ │ Sandbox Instance│
│                  │ │ Manager        │ │                 │
│ - Activity       │ │ - Create       │ │ - ID            │
│ - Threats        │ │ - Restore      │ │ - Status        │
│ - Auto-terminate │ │ - Compress     │ │ - Metadata      │
└──────────────────┘ └────────────────┘ └─────────────────┘
```

## Service Architecture

### 1. SandboxEnvironmentSetup

Initializes and configures the sandbox environment.

**Responsibilities:**

- Detect Windows Sandbox or Hyper-V availability
- Setup sandbox partition (H:)
- Configure shared folders
- Set resource limits
- Enable GPU pass-through
- Create snapshot capability

**Key Methods:**

```csharp
Task<bool> InitializeAsync()
Task<bool> IsAvailableAsync()
Task<SandboxConfiguration> GetCurrentConfigurationAsync()
Task<bool> SetupSandboxPartitionAsync(string path, long sizeGb)
Task<bool> ConfigureSharedFolderAsync(string hostPath, string sandboxPath)
Task<bool> SetResourceLimitsAsync(SandboxResourceLimits limits)
Task<bool> ConfigureNetworkIsolationAsync(NetworkIsolationPolicy policy)
Task<bool> EnableGpuPassThroughAsync()
Task<SandboxEnvironmentInfo> GetEnvironmentInfoAsync()
```

**Usage:**

```csharp
var setup = new SandboxEnvironmentSetup();
await setup.InitializeAsync();
var config = await setup.GetCurrentConfigurationAsync();
```

### 2. SandboxLauncher

Manages sandbox instance lifecycle and execution.

**Responsibilities:**

- Launch sandbox instances
- Mount shared folders
- Pass files for testing
- Execute commands in sandbox
- Verify isolation
- Retrieve logs
- Terminate sandboxes

**Key Methods:**

```csharp
Task<SandboxInstance> LaunchSandboxAsync(SandboxLaunchOptions options)
Task<bool> MountSharedFolderAsync(SandboxInstance sandbox, string hostPath, string sandboxPath)
Task<bool> PassFileForTestingAsync(SandboxInstance sandbox, string filePath)
Task<SandboxExecutionResult> ExecuteInSandboxAsync(SandboxInstance sandbox, string command, int timeout)
Task<bool> VerifyIsolationAsync(SandboxInstance sandbox)
Task<SandboxLogs> GetSandboxLogsAsync(SandboxInstance sandbox)
Task<bool> TerminateSandboxAsync(SandboxInstance sandbox)
```

**Usage:**

```csharp
var launcher = new SandboxLauncher();
var options = new SandboxLaunchOptions { SandboxName = "Analysis_001" };
var sandbox = await launcher.LaunchSandboxAsync(options);
await launcher.TerminateSandboxAsync(sandbox);
```

### 3. SandboxFileTransfer

Manages file operations and activity monitoring within sandbox.

**Responsibilities:**

- Transfer files to/from sandbox
- Monitor file activity
- Capture all sandbox activity
- Verify no contamination
- Log transfers
- Archive analysis results

**Key Methods:**

```csharp
Task<bool> TransferFileToSandboxAsync(SandboxInstance sandbox, string source, string dest)
Task<bool> TransferFileFromSandboxAsync(SandboxInstance sandbox, string sandboxPath, string dest)
Task<SandboxFileActivity> MonitorFileInSandboxAsync(SandboxInstance sandbox, string filePath)
Task<SandboxActivityReport> CaptureActivityAsync(SandboxInstance sandbox)
Task<ContaminationCheckResult> VerifyNoContaminationAsync(SandboxInstance sandbox)
Task<FileTransferLog> GetTransferLogAsync(SandboxInstance sandbox)
Task<bool> ArchiveAnalysisResultsAsync(SandboxInstance sandbox, string archivePath)
```

**Usage:**

```csharp
var fileTransfer = new SandboxFileTransfer();
await fileTransfer.TransferFileToSandboxAsync(sandbox, "C:\\file.exe", "C:\\Analysis\\file.exe");
var activity = await fileTransfer.CaptureActivityAsync(sandbox);
```

### 4. SandboxMonitor

Monitors sandbox activity and detects threats.

**Responsibilities:**

- Monitor file operations
- Track registry access
- Monitor network access
- Track process activity
- Generate activity reports
- Detect malware behavior
- Auto-terminate on critical threats

**Key Methods:**

```csharp
Task StartMonitoringAsync(SandboxInstance sandbox)
Task<IEnumerable<FileOperation>> GetFileOperationsAsync(SandboxInstance sandbox)
Task<IEnumerable<RegistryOperation>> GetRegistryAccessAsync(SandboxInstance sandbox)
Task<IEnumerable<NetworkOperation>> GetNetworkAccessAsync(SandboxInstance sandbox)
Task<IEnumerable<ProcessOperation>> GetProcessActivityAsync(SandboxInstance sandbox)
Task<ActivityReport> GenerateActivityReportAsync(SandboxInstance sandbox)
Task<ThreatDetectionResult> DetectMalwareBehaviorAsync(SandboxInstance sandbox)
Task<bool> AutoTerminateOnDangerAsync(SandboxInstance sandbox)
Task StopMonitoringAsync(SandboxInstance sandbox)
```

**Usage:**

```csharp
var monitor = new SandboxMonitor();
await monitor.StartMonitoringAsync(sandbox);
var threatResult = await monitor.DetectMalwareBehaviorAsync(sandbox);
if (threatResult.ThreatDetected) { /* handle threat */ }
```

### 5. SandboxSnapshotManager

Manages sandbox snapshots for rapid recovery.

**Responsibilities:**

- Create snapshots
- Restore from snapshots
- Manage multiple snapshots
- Schedule automatic snapshots
- Compress snapshots
- Perform rapid rollback
- Manage snapshot storage

**Key Methods:**

```csharp
Task<SandboxSnapshot> CreateSnapshotAsync(SandboxInstance sandbox, string name)
Task<bool> RestoreFromSnapshotAsync(SandboxInstance sandbox, SandboxSnapshot snapshot)
Task<IEnumerable<SandboxSnapshot>> GetSnapshotsAsync(SandboxInstance sandbox)
Task<bool> CompressSnapshotAsync(SandboxSnapshot snapshot)
Task<bool> ScheduleSnapshotAsync(SandboxInstance sandbox, TimeSpan interval)
Task<bool> RapidRollbackAsync(SandboxInstance sandbox)
Task<bool> DeleteSnapshotAsync(SandboxSnapshot snapshot)
Task<SnapshotManagementReport> GetManagementReportAsync(SandboxInstance sandbox)
```

**Usage:**

```csharp
var snapshotManager = new SandboxSnapshotManager();
var snapshot = await snapshotManager.CreateSnapshotAsync(sandbox, "clean");
await snapshotManager.RestoreFromSnapshotAsync(sandbox, snapshot);
```

## Data Models

### SandboxInstance

Represents an active sandbox environment.

```csharp
public class SandboxInstance
{
    public string Id { get; set; }
    public string Name { get; set; }
    public DateTime CreatedAt { get; set; }
    public int? ProcessId { get; set; }
    public SandboxStatus Status { get; set; }
    public Dictionary<string, object> Metadata { get; set; }
}

public enum SandboxStatus
{
    Created,
    Running,
    Suspended,
    Stopped,
    Error
}
```

### SandboxConfiguration

Stores sandbox configuration settings.

```csharp
public class SandboxConfiguration
{
    public string SandboxType { get; set; }
    public string StoragePath { get; set; }
    public SandboxResourceLimits ResourceLimits { get; set; }
    public NetworkIsolationPolicy NetworkPolicy { get; set; }
    public bool GpuEnabled { get; set; }
    public bool SnapshotCapable { get; set; }
    public DateTime CreatedAt { get; set; }
    public Dictionary<string, string> CustomSettings { get; set; }
}
```

### ResourceLimits

Defines resource constraints.

```csharp
public class SandboxResourceLimits
{
    public int CpuCores { get; set; }
    public long RamMb { get; set; }
    public long DiskGb { get; set; }
    public long NetworkBandwidthMbps { get; set; }
}
```

### ActivityReport

Aggregates monitoring data.

```csharp
public class ActivityReport
{
    public int TotalOperations { get; set; }
    public int FileOperations { get; set; }
    public int RegistryOperations { get; set; }
    public int NetworkOperations { get; set; }
    public int ProcessOperations { get; set; }
    public DateTime GeneratedAt { get; set; }
}
```

### ThreatDetectionResult

Reports threat analysis findings.

```csharp
public class ThreatDetectionResult
{
    public bool ThreatDetected { get; set; }
    public string ThreatLevel { get; set; }
    public List<string> ThreatIndicators { get; set; }
    public List<string> SuspiciousBehaviors { get; set; }
    public DateTime AnalyzedAt { get; set; }
}
```

## Threat Detection

### Threat Levels

1. **Critical**
   - Known C2 communication
   - Direct system compromise
   - Auto-termination triggered

2. **High**
   - System file modification
   - Registry persistence attempts
   - Privilege escalation

3. **Medium**
   - Risky registry access
   - Suspicious behavior patterns
   - Unusual network activity

4. **Low**
   - Benign suspicious patterns
   - Policy violations
   - Unusual file operations

### Detection Mechanisms

**Network Analysis:**

- Known C2 address detection
- DNS exfiltration attempts
- Unusual port usage
- Protocol anomalies

**Registry Analysis:**

- Run key modifications
- Service installation
- Driver loading
- Configuration changes

**File Operations:**

- System file modifications
- Temp file creation patterns
- Startup folder access
- DLL injection targets

**Process Activity:**

- Process creation patterns
- Privilege escalation attempts
- Code injection detection
- Hollowing detection

## Test Coverage

### Unit Tests (25+)

**SandboxEnvironmentSetup (9 tests)**

- Initialization
- Availability detection
- Configuration retrieval
- Partition setup
- Shared folder configuration
- Resource limits validation
- Network isolation
- GPU pass-through
- Snapshot capability

**SandboxLauncher (7 tests)**

- Initialization
- Sandbox launch
- Shared folder mounting
- File transfer
- Command execution
- Isolation verification
- Sandbox termination

**SandboxFileTransfer (8 tests)**

- File transfer to sandbox
- File transfer from sandbox
- File activity monitoring
- Activity capture
- Contamination verification
- Transfer logging
- Result archival
- Shutdown

**SandboxMonitor (8 tests)**

- Monitoring initialization
- Monitoring start/stop
- File operations tracking
- Registry access tracking
- Network access tracking
- Process activity tracking
- Activity report generation
- Threat detection

**SandboxSnapshotManager (8 tests)**

- Snapshot creation
- Snapshot retrieval
- Snapshot restoration
- Snapshot compression
- Rapid rollback
- Snapshot scheduling
- Snapshot deletion
- Management reporting

**SandboxOrchestrator (3 tests)**

- Initialization
- Environment info retrieval
- Shutdown

## Integration Workflow

### Complete Analysis Workflow

```csharp
// 1. Initialize
var orchestrator = new SandboxOrchestrator(
    new SandboxEnvironmentSetup(),
    new SandboxLauncher(),
    new SandboxFileTransfer(),
    new SandboxMonitor(),
    new SandboxSnapshotManager());

await orchestrator.InitializeAsync();

// 2. Configure analysis
var options = new SandboxAnalysisOptions
{
    TimeoutSeconds = 300,
    ArchiveResults = true,
    EnableMonitoring = true,
    NetworkPolicy = NetworkIsolationPolicy.Full
};

// 3. Analyze file
var result = await orchestrator.AnalyzeSuspiciousFileAsync(
    "C:\\suspect.exe", 
    options);

// 4. Review results
if (result.IsSafe)
{
    Console.WriteLine("File is safe to use");
}
else
{
    Console.WriteLine($"Threat detected: {result.ThreatLevel}");
    Console.WriteLine($"Behaviors: {string.Join(", ", result.SuspiciousBehaviors)}");
}

// 5. Shutdown
await orchestrator.ShutdownAsync();
```

## Performance Characteristics

### Startup Time

- Environment setup: ~500ms
- Sandbox launch: 2-5 seconds
- Initial snapshot: 3-10 seconds

### Analysis Time

- Small files (< 1MB): 10-30 seconds
- Medium files (1-10MB): 30-60 seconds
- Large files (> 10MB): 60-300 seconds

### Resource Usage

- Base memory: ~100MB
- Per sandbox: 2-4GB RAM
- Snapshot storage: 1-5GB per snapshot

## Security Considerations

### Isolation Guarantees

- Complete file system isolation
- Registry isolation
- Network isolation (configurable)
- Process isolation

### Contamination Prevention

- Verification of clean state
- Host file integrity checking
- Registry protection
- Network monitoring

### Monitoring

- Comprehensive activity tracking
- Real-time threat detection
- Automated threat response
- Audit logging

## API Reference

### SandboxOrchestrator.AnalyzeSuspiciousFileAsync

Analyzes a single suspicious file.

```csharp
Task<SandboxAnalysisResult> AnalyzeSuspiciousFileAsync(
    string filePath,
    SandboxAnalysisOptions options,
    CancellationToken cancellationToken = default)
```

**Parameters:**

- `filePath`: Path to the file to analyze
- `options`: Analysis options
- `cancellationToken`: Cancellation token

**Returns:**

- `SandboxAnalysisResult` containing analysis findings

**Exceptions:**

- `ArgumentNullException`: If filePath is null
- `FileNotFoundException`: If file doesn't exist
- `InvalidOperationException`: If not initialized

### SandboxOrchestrator.AnalyzeSuspiciousFilesAsync

Analyzes multiple suspicious files.

```csharp
Task<SandboxAnalysisResult> AnalyzeSuspiciousFilesAsync(
    IEnumerable<string> filePaths,
    SandboxAnalysisOptions options,
    CancellationToken cancellationToken = default)
```

**Parameters:**

- `filePaths`: Collection of file paths to analyze
- `options`: Analysis options
- `cancellationToken`: Cancellation token

**Returns:**

- Aggregate `SandboxAnalysisResult` for all files

## Troubleshooting

### Common Issues

**Issue: Windows Sandbox not found**

- Solution: Enable Windows Sandbox optional feature
- Command: `Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All`

**Issue: Insufficient disk space**

- Solution: Increase partition or clean old snapshots
- Check: `Get-Volume -DriveLetter H | Select-Object SizeRemaining`

**Issue: GPU pass-through failing**

- Solution: Verify GPU driver support
- Check: `Get-PnpDevice -Class Display`

**Issue: Network isolation blocking legitimate traffic**

- Solution: Adjust isolation policy or add allow rules
- Policy: Change to `NetworkIsolationPolicy.Restricted`

## Future Enhancements

### Planned Features

- Machine learning-based threat detection
- Behavioral analysis improvements
- Performance optimization
- Multi-language support
- Advanced reporting
- Integration with threat intelligence feeds

### Extensibility Points

- Custom threat detectors
- Custom analysis engines
- Custom monitoring providers
- Custom snapshot backends

## License

HELIOS Phase 10 Sandbox Environment is part of the HELIOS Platform.

## Support

For support and issues:

- Email: support@helios.example.com
- Documentation: https://docs.helios.example.com/phase10
- Issue Tracker: https://github.com/helios/issues

## Changelog

### Version 1.0.0 (Initial Release)

- 5 production-ready services
- 25+ comprehensive unit tests
- Complete configuration guide
- Threat detection capabilities
- Snapshot management
- File transfer capabilities
- Activity monitoring
- Network isolation
- GPU support

---

**Last Updated:** 2024
**Version:** 1.0.0
