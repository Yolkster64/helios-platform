# Quick Start Guide - HELIOS Logging & Diagnostics System

## 5-Minute Setup

### Step 1: Initialize Logging (Program.cs)

```csharp
using HELIOS.Platform.Core.Logging;
using HELIOS.Platform.Core.Diagnostics;
using Serilog;

public static void Main()
{
    // Initialize logging (FIRST!)
    LoggerConfiguration.ConfigureGlobalLogger(Serilog.Events.LogEventLevel.Information);
    
    // Register crash handlers
    CrashReporter.RegisterGlobalHandlers();
    
    // Initialize Windows Event Log
    WindowsEventLogIntegration.Initialize();
    
    // Your application code here
    RunApplication();
    
    // Cleanup on exit
    LoggerConfiguration.CloseLogger();
    WindowsEventLogIntegration.Cleanup();
}

private static void RunApplication()
{
    var logger = Log.ForContext<Program>();
    logger.Information("HELIOS Platform started");
    
    // Your business logic here
}
```

### Step 2: Use Structured Logging

```csharp
var logger = Log.ForContext<MyService>();

// Simple logging
logger.Information("Process started");

// With structured data
using (var context = LogContext.CreateScope()
    .WithUserId("user123")
    .WithRequestId("req-456"))
{
    logger.Information("Processing order {OrderId}", orderId);
    logger.Warning("High amount detected: {Amount}", amount);
}
```

### Step 3: Add Health Checks

```csharp
var healthEngine = new HealthDiagnosticsEngine();

// Register health checks
healthEngine.RegisterHealthCheck("Database", new DatabaseHealthCheck());
healthEngine.RegisterHealthCheck("DiskSpace", new DiskSpaceHealthCheck());

// Run checks periodically
var timer = new System.Timers.Timer(60000); // Every minute
timer.Elapsed += async (s, e) =>
{
    var status = await healthEngine.RunAllHealthChecksAsync();
    if (status.Status != HealthStatusCode.Healthy)
    {
        logger.Warning("Health check failed: {Status}", status.Status);
    }
};
timer.Start();
```

### Step 4: Monitor Performance

```csharp
var performanceMonitor = new PerformanceMonitor();

// Register counters
performanceMonitor.RegisterCounter("RequestCount", "API requests", CounterType.Counter);
performanceMonitor.RegisterCounter("ResponseTime", "Response time", CounterType.Timing);

// Measure operations
using (performanceMonitor.MeasurePerformance("ProcessRequest"))
{
    // Your code here
}

performanceMonitor.IncrementCounter("RequestCount");
```

### Step 5: Track Resources

```csharp
var resourceTracker = new ResourceUsageTracker();

// Capture periodic snapshots
var timer = new System.Timers.Timer(10000); // Every 10 seconds
timer.Elapsed += (s, e) =>
{
    var snapshot = resourceTracker.CaptureSnapshot();
    logger.Debug("Memory: {Memory}MB, CPU: {CPU}%", 
        snapshot.ProcessMemoryMB, 
        snapshot.CpuUsagePercent);
};
timer.Start();

// Check for anomalies
var anomalies = resourceTracker.DetectAnomalies();
if (anomalies.HasAnomalies)
{
    foreach (var anomaly in anomalies.Anomalies)
        logger.Warning("Anomaly: {Anomaly}", anomaly);
}
```

### Step 6: Setup Alerts

```csharp
var alertSystem = new HealthAlertSystem();

// Register alert handler
alertSystem.RegisterHandler(new ConsoleAlertHandler());

// Add alert rules
alertSystem.AddAlertRule(new AlertRule
{
    Name = "CriticalFailure",
    Title = "Critical System Failure",
    Severity = AlertSeverity.Critical,
    Condition = (status) => status.Status == HealthStatusCode.Critical
});

// Check and trigger alerts
await healthEngine.RunAllHealthChecksAsync();
// (Alerts are checked in your health check loop)
```

### Step 7: View Dashboard

```csharp
var dashboard = new HealthDashboardProvider(
    healthEngine,
    resourceTracker,
    performanceMonitor,
    alertSystem,
    counterManager);

// Generate dashboard data
var data = dashboard.GenerateDashboardData();
Console.WriteLine($"Health: {data.HealthStatus.Status}");
Console.WriteLine($"Memory: {data.ResourceUsage?.ProcessMemoryMB}MB");
Console.WriteLine($"Active Alerts: {data.ActiveAlerts.Count}");

// Generate summary
var summary = dashboard.GenerateSummary();
Console.WriteLine($"Overall Status: {summary.HealthStatus}");
Console.WriteLine($"Critical Alerts: {summary.CriticalAlertCount}");
```

## Common Tasks

### View Logs

Logs are stored in `Logs/` directory:

- `application-*.txt` - All logs
- `application-structured-*.json` - Structured logs
- `errors-*.txt` - Error only
- `critical-*.txt` - Critical only

### Check Crash Dumps

```csharp
var crashes = CrashReporter.GetCrashDumps();
foreach (var crash in crashes)
{
    Console.WriteLine($"Crash: {crash}");
    var content = File.ReadAllText(crash);
    // Analyze...
}
```

### Rotate Logs Manually

```csharp
LogRotationManager.RotateLogs();
var stats = LogRotationManager.GetLogStatistics();
Console.WriteLine($"Log files: {stats.LogFileCount}");
Console.WriteLine($"Total size: {stats.TotalLogSizeMB}MB");
```

### Custom Performance Counter

```csharp
var counterMgr = new CustomPerformanceCounterManager();
var counter = counterMgr.GetOrCreateCounter(
    "API", "RequestLatency",
    new CounterDefinition 
    { 
        WarningThreshold = 500,
        AlertThreshold = 1000 
    });

counter.RecordSample(123); // Record value
var status = counter.GetStatus();
```

### Get Resource Statistics

```csharp
var stats = resourceTracker.GetStatistics(TimeSpan.FromHours(1));
Console.WriteLine($"Avg Memory: {stats.AverageProcessMemoryMB:F2}MB");
Console.WriteLine($"Peak Memory: {stats.MaxProcessMemoryMB}MB");
Console.WriteLine($"Avg CPU: {stats.AverageCpuUsagePercent:F2}%");
```

## File Structure

```
C:\Users\ADMIN\helios-platform\src\HELIOS.Platform\Core\
├── Logging/
│   ├── LoggerConfiguration.cs          # Main logger setup
│   ├── LogContext.cs                   # Structured context
│   ├── CrashReporter.cs                # Crash handling
│   ├── LogRotationManager.cs           # Log rotation
│   └── LogAggregation.cs               # External aggregation
├── Diagnostics/
│   ├── HealthDiagnosticsEngine.cs      # Health checks
│   ├── PerformanceMonitor.cs           # Performance tracking
│   ├── ResourceUsageTracker.cs         # Resource monitoring
│   ├── WindowsEventLogIntegration.cs   # Event log
│   ├── CustomPerformanceCounters.cs    # Custom counters
│   ├── HealthAlertSystem.cs            # Alerting
│   └── HealthDashboardProvider.cs      # Dashboard
└── Examples/
    └── LoggingAndDiagnosticsExamples.cs  # Usage examples
```

## Troubleshooting

### "Event Log Source Not Found"

- Run as Administrator
- Manually create: `EventLog.CreateEventSource("HELIOS Platform", "Application")`

### "Cannot write to log directory"

- Check folder permissions
- Ensure `Logs/` directory exists and is writable

### High CPU Usage

- Reduce health check frequency
- Increase batch sizes for aggregation
- Disable detailed performance tracking if not needed

### Disk Growing Fast

- Reduce `MaxRetainedFiles` in rotation config
- Decrease `DaysToKeepArchived`
- Reduce log file size limit

## Next Steps

1. Review `LoggingAndDiagnosticsExamples.cs` for complete examples
2. Read full documentation: `LOGGING_DIAGNOSTICS_SYSTEM.md`
3. Implement custom health checks for your system
4. Setup alert handlers for your notification system
5. Configure log aggregation for centralized monitoring

## Example Output

```
[2026-04-16 14:30:45.123 +00:00] [INF] [HELIOS.Platform.Core.Examples] Application started with comprehensive logging

Health Check Results:
  DatabaseConnection: Healthy (45ms)
  DiskSpace: Healthy (23ms)
  Overall: Healthy

Performance Metrics:
  RequestCount: 1,234 requests
  ResponseTime: Avg 125ms, Min 45ms, Max 890ms

Resource Usage:
  Memory: 256MB / 512MB
  CPU: 15%
  Threads: 42

Active Alerts: 0
Dashboard Status: ✓ All Systems Operational
```

---

**Ready to go!** Start logging and monitoring your HELIOS Platform now.
