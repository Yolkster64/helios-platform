# Server Management Core - Quick Reference

## 5-Minute Setup

### 1. Initialize Components

```csharp
using HELIOS.Platform.Core.Server;
using HELIOS.Platform.Core.Server.Models;

// Service management
var serviceManager = new ServerServiceManager();

// Process management
var processManager = new ProcessManager();

// Health monitoring
var healthMonitor = new ServiceHealthMonitor(serviceManager, processManager);

// Deployment orchestration
var deploymentService = new DeploymentService();
```

### 2. Register and Start a Service

```csharp
// Create service
var service = new ServiceInfo
{
    ServiceId = "my-app",
    DisplayName = "My Application",
    ServiceType = ServiceType.WindowsService,
    AutoRestartEnabled = true,
    MaxRestartAttempts = 3
};

// Register it
serviceManager.RegisterService(service);

// Start it
await serviceManager.StartServiceAsync("my-app");
```

### 3. Start Health Monitoring

```csharp
// Configure and start
healthMonitor.Start();

// Handle events
healthMonitor.HealthCheckFailed += (s, e) => 
    Console.WriteLine($"Health check failed: {e.ServiceId}");

healthMonitor.ServiceRestarted += (s, e) => 
    Console.WriteLine($"Service restarted: {e.ServiceId} (attempt {e.AttemptNumber})");
```

### 4. Deploy an Application

```csharp
// Start deployment
var deploymentId = await deploymentService.StartDeploymentAsync(
    applicationName: "MyApp",
    version: "2.0.0",
    targetServers: new List<string> { "server1", "server2", "server3" },
    deploymentType: DeploymentType.RollingUpdate
);

// Monitor progress
var deployment = deploymentService.GetDeployment(deploymentId);
Console.WriteLine($"Status: {deployment.Status}, Progress: {deployment.CompletionPercentage}%");
```

## Common Tasks

### Manage Service Lifecycle

```csharp
// Start
await serviceManager.StartServiceAsync("service-id");

// Stop
await serviceManager.StopServiceAsync("service-id");

// Restart
await serviceManager.RestartServiceAsync("service-id");

// Pause (Windows services only)
await serviceManager.PauseServiceAsync("service-id");

// Resume
await serviceManager.ResumeServiceAsync("service-id");
```

### Monitor Processes

```csharp
// Get all processes
var processes = processManager.GetAllProcesses();

// Get process by name
var notepadProcesses = processManager.GetProcessesByName("notepad.exe");

// List with filters
var largeProcesses = processManager.ListProcesses(
    minMemory: 100 * 1024 * 1024  // 100MB+
);

// Set limits
processManager.SetMemoryLimit(pid, 1024 * 1024 * 1024);  // 1GB
processManager.SetCpuLimit(pid, 50.0);                    // 50% CPU
```

### Control Process Priority

```csharp
// Set priority
processManager.SetProcessPriority(pid, ProcessPriority.High);

// Available priorities:
// - ProcessPriority.RealTime (256) - highest
// - ProcessPriority.High (128)
// - ProcessPriority.AboveNormal (32768)
// - ProcessPriority.Normal (32) - default
// - ProcessPriority.BelowNormal (16384)
// - ProcessPriority.Idle (64) - lowest
```

### Set CPU Affinity

```csharp
// Bind to cores 0-3
processManager.SetProcessAffinity(pid, 0x0F);

// Bind to core 0 only
processManager.SetProcessAffinity(pid, 0x01);

// Bind to cores 0,2,4 (0x15 = 0b00010101)
processManager.SetProcessAffinity(pid, 0x15);
```

### Check Service Health

```csharp
// Manual health check
var result = await healthMonitor.CheckServiceHealthAsync("service-id");

// Check status
if (result.Status == HealthStatus.Healthy)
    Console.WriteLine("Service is healthy!");
else if (result.Status == HealthStatus.Warning)
    Console.WriteLine($"Warning: {result.Message}");
else
    Console.WriteLine($"Unhealthy: {result.Message}");

// Get last health check
var lastCheck = healthMonitor.GetLastHealthCheck("service-id");
```

### Deploy Applications

**Standard Deployment** (Fastest)

```csharp
await deploymentService.StartDeploymentAsync(
    "MyApp", "2.0.0", 
    servers,
    DeploymentType.Standard
);
```

**Rolling Update** (Staged)

```csharp
await deploymentService.StartDeploymentAsync(
    "MyApp", "2.0.0",
    servers,
    DeploymentType.RollingUpdate
);
// Deploys in stages: 25%, 50%, 75%, 100%
```

**Blue/Green** (Zero-downtime)

```csharp
await deploymentService.StartDeploymentAsync(
    "MyApp", "2.0.0",
    servers,
    DeploymentType.BlueGreen
);
// Switches traffic after validation
```

**Canary** (Safe rollout)

```csharp
await deploymentService.StartDeploymentAsync(
    "MyApp", "2.0.0",
    servers,
    DeploymentType.Canary
);
// Tests on 1 server first, then full rollout
```

### Rollback Deployment

```csharp
// Rollback failed deployment
await deploymentService.RollbackDeployment(deploymentId);

// Check if rollback succeeded
var deployment = deploymentService.GetDeployment(deploymentId);
if (deployment.Status == DeploymentStatus.RolledBack)
    Console.WriteLine("Rollback successful");
```

## Performance Tips

### Service Management

```csharp
// Optimize for 100+ services
// - Use unique ServiceIds
// - Set dependencies correctly
// - Keep auto-restart disabled for non-critical services
// - Use clustering for redundancy
```

### Process Management

```csharp
// Optimize for 1000+ processes
// - Register only critical processes
// - Use process names for bulk operations
// - Set memory limits to prevent bloat
// - Use affinity to isolate workloads
```

### Health Monitoring

```csharp
// Optimize health checks
var monitor = new ServiceHealthMonitor(
    serviceManager,
    processManager,
    healthCheckIntervalSeconds: 60  // Increase for large systems
);
```

## Configuration Presets

### High Availability

```csharp
var service = new ServiceInfo
{
    ServiceId = "critical-app",
    AutoRestartEnabled = true,
    MaxRestartAttempts = 5,
    StartupType = ServiceStartupType.Automatic,
    ClusterMembers = new() { "node1", "node2", "node3" }
};
```

### Resource Constrained

```csharp
var service = new ServiceInfo
{
    ServiceId = "light-app",
    AutoRestartEnabled = false,
    MaxRestartAttempts = 1
};

processManager.SetMemoryLimit(pid, 512 * 1024 * 1024);  // 512MB
processManager.SetCpuLimit(pid, 25.0);                  // 25% CPU
```

### Development

```csharp
var monitor = new ServiceHealthMonitor(
    serviceManager,
    processManager,
    healthCheckIntervalSeconds: 5  // Frequent checks
);
```

## Event Handling

```csharp
// Service events
serviceManager.ServiceStatusChanged += (s, e) =>
    Console.WriteLine($"Service {e.ServiceId} is now {e.NewStatus}");

serviceManager.ServiceError += (s, e) =>
    Console.WriteLine($"Error in {e.ServiceId}: {e.ErrorMessage}");

// Process events
processManager.ProcessStateChanged += (s, e) =>
    Console.WriteLine($"Process {e.ProcessId} is now {e.NewState}");

processManager.ProcessError += (s, e) =>
    Console.WriteLine($"Error in process {e.ProcessId}: {e.ErrorMessage}");

// Health events
healthMonitor.HealthCheckFailed += (s, e) =>
    Console.WriteLine($"Health check failed: {e.Message}");

healthMonitor.HealthAlert += (s, e) =>
    Console.WriteLine($"Health alert: {e.AlertMessage}");

// Deployment events
deploymentService.DeploymentStatusChanged += (s, e) =>
    Console.WriteLine($"Deployment {e.DeploymentId} is now {e.NewStatus}");

deploymentService.DeploymentError += (s, e) =>
    Console.WriteLine($"Deployment error: {e.ErrorMessage}");
```

## Status Values

### Service Status

```
Stopped = 0      - Service is not running
Running = 1      - Service is running
Paused = 2       - Service is paused
Unknown = 3      - Unknown status
```

### Health Status

```
Healthy = 0      - All checks passed
Unhealthy = 1    - Critical issues
Warning = 2      - Warning conditions
Unknown = 3      - Unable to check
```

### Deployment Status

```
Pending = 0      - Waiting to start
InProgress = 1   - Currently deploying
Verifying = 2    - Verifying deployment
Completed = 3    - Successfully deployed
RolledBack = 4   - Deployment rolled back
Failed = 5       - Deployment failed
Cancelled = 6    - Deployment cancelled
```

## Troubleshooting Checklist

- [ ] Is the service registered?
- [ ] Are dependencies running?
- [ ] Does the process exist?
- [ ] Are resource limits sufficient?
- [ ] Is health monitoring enabled?
- [ ] Are deployment targets accessible?
- [ ] Check deployment logs
- [ ] Consider rollback if deployment failed

## Best Practices

1. **Always set dependencies correctly** - Prevents start-up failures
2. **Enable auto-restart for critical services** - Improves availability
3. **Set resource limits** - Prevents resource exhaustion
4. **Monitor health regularly** - Catch issues early
5. **Use rolling updates** - Minimize deployment risk
6. **Test deployments** - Canary before full rollout
7. **Implement logging** - Trace issues to root cause
8. **Plan for rollback** - Always have exit strategy

## Resources

- Full documentation: `docs/SERVER_MANAGEMENT_CORE.md`
- Source code: `src/HELIOS.Platform/Core/Server/`
- Tests: `tests/HELIOS.Platform.Tests/Server/`
