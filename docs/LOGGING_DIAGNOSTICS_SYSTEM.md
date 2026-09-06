# HELIOS Platform Logging & Diagnostics System

## Overview

The HELIOS Platform Logging & Diagnostics System provides a comprehensive, production-ready solution for:

- **Multi-level structured logging** with Serilog
- **Log rotation, archival, and aggregation**
- **Crash reporting and analysis**
- **Health diagnostics and monitoring**
- **Performance tracking and metrics**
- **Resource usage monitoring**
- **Windows Event Log integration**
- **Custom performance counters**
- **Health alerts and notifications**
- **System health dashboard**

## Architecture

### 14 Core Components

1. **Logger Configuration** (`LoggerConfiguration.cs`)
   - Configures Serilog with multiple sinks
   - Console, file, JSON, and error-specific outputs
   - Automatic log rotation and archival

2. **Structured Logging Context** (`LogContext.cs`)
   - Adds contextual information to logs
   - User ID, Request ID, Correlation ID tracking
   - Automatic timing measurements
   - Scoped context management

3. **Crash Reporting** (`CrashReporter.cs`)
   - Global exception handlers
   - Detailed crash dumps
   - Exception hierarchy formatting
   - Automatic cleanup of old dumps

4. **Log Rotation Manager** (`LogRotationManager.cs`)
   - Automatic log file rotation
   - Size and date-based rollover
   - Archive management
   - Log statistics and reporting

5. **Log Aggregation** (`LogAggregation.cs`)
   - Support for external log aggregators
   - Elasticsearch, Splunk, and other services
   - Batch processing and buffering
   - Connection management

6. **Health Diagnostics Engine** (`HealthDiagnosticsEngine.cs`)
   - Custom health check framework
   - Overall health status calculation
   - Health check caching
   - Status severity levels

7. **Performance Monitor** (`PerformanceMonitor.cs`)
   - Counter, timing, gauge, and histogram types
   - Automatic statistics calculation
   - Performance measurement scopes
   - Thread-safe operations

8. **Resource Usage Tracker** (`ResourceUsageTracker.cs`)
   - CPU, memory, thread monitoring
   - Garbage collection tracking
   - Anomaly detection
   - Historical snapshots

9. **Windows Event Log Integration** (`WindowsEventLogIntegration.cs`)
   - Event source creation
   - Multiple event types (Information, Warning, Error, etc.)
   - Health status events
   - Performance event logging

10. **Custom Performance Counters** (`CustomPerformanceCounters.cs`)
    - Custom counter management
    - Category-based organization
    - Alert and warning thresholds
    - Counter snapshots and reporting

11. **Health Alert System** (`HealthAlertSystem.cs`)
    - Alert rule engine
    - Multiple alert handlers
    - Alert lifecycle management (Active, Acknowledged, Resolved)
    - Alert statistics and reporting

12. **Health Dashboard Provider** (`HealthDashboardProvider.cs`)
    - Comprehensive dashboard data generation
    - Dashboard summaries
    - Health trend analysis
    - Multi-source data aggregation

13. **Implementation Examples** (`LoggingAndDiagnosticsExamples.cs`)
    - 10 complete examples
    - Best practices
    - Common use cases

14. **Complete Documentation** (this file)
    - Architecture overview
    - Usage guide
    - API reference
    - Configuration guide

## Installation & Setup

### NuGet Dependencies

Add these packages to your project:

```xml
<ItemGroup>
    <PackageReference Include="Serilog" Version="3.0.0" />
    <PackageReference Include="Serilog.Sinks.Console" Version="5.0.0" />
    <PackageReference Include="Serilog.Sinks.File" Version="5.0.0" />
    <PackageReference Include="Serilog.Formatting.Compact" Version="2.0.0" />
</ItemGroup>
```

### Initialize the System

```csharp
// In your Program.cs or startup code
public static void Main()
{
    // Configure logging
    LoggerConfiguration.ConfigureGlobalLogger(LogEventLevel.Information);
    
    // Register global crash handlers
    CrashReporter.RegisterGlobalHandlers();
    
    // Initialize Event Log
    WindowsEventLogIntegration.Initialize();
    
    // Setup your application...
    
    // On shutdown
    LoggerConfiguration.CloseLogger();
    WindowsEventLogIntegration.Cleanup();
}
```

## Usage Guide

### 1. Basic Logging

```csharp
using Serilog;

var logger = Log.ForContext<MyClass>();
logger.Information("Application started");
logger.Warning("Unusual condition detected");
logger.Error(ex, "Error processing request");
```

### 2. Structured Logging with Context

```csharp
using (var context = LogContext.CreateScope()
    .WithUserId("user123")
    .WithRequestId("req-456")
    .WithOperation("ProcessOrder"))
{
    logger.Information("Processing order");
}
```

### 3. Performance Measurement

```csharp
var monitor = new PerformanceMonitor();
monitor.RegisterCounter("MyOperation", "Operation duration", CounterType.Timing);

using (monitor.MeasurePerformance("MyOperation"))
{
    // Do work
}
```

### 4. Health Checks

```csharp
var engine = new HealthDiagnosticsEngine();
engine.RegisterHealthCheck("Database", new DatabaseHealthCheck());

var status = await engine.RunAllHealthChecksAsync();
if (status.Status == HealthStatusCode.Healthy)
{
    logger.Information("System health is good");
}
```

### 5. Resource Monitoring

```csharp
var tracker = new ResourceUsageTracker();
var snapshot = tracker.CaptureSnapshot();
logger.Information("Memory: {Memory}MB, CPU: {CPU}%", 
    snapshot.ProcessMemoryMB, 
    snapshot.CpuUsagePercent);
```

### 6. Custom Counters

```csharp
var counterMgr = new CustomPerformanceCounterManager();
var counter = counterMgr.GetOrCreateCounter(
    "API", "RequestCount",
    new CounterDefinition { AlertThreshold = 1000 });

counter.RecordSample(42);
```

### 7. Alert Rules

```csharp
var alertSystem = new HealthAlertSystem();
alertSystem.RegisterHandler(new ConsoleAlertHandler());

alertSystem.AddAlertRule(new AlertRule
{
    Name = "HighMemory",
    Title = "High Memory Usage",
    Severity = AlertSeverity.Warning,
    Condition = (status) => status.CriticalCount > 0
});
```

### 8. Dashboard Generation

```csharp
var dashboard = new HealthDashboardProvider(
    diagnosticsEngine,
    resourceTracker,
    performanceMonitor,
    alertSystem,
    counterManager);

var data = dashboard.GenerateDashboardData();
var summary = dashboard.GenerateSummary();
var trends = dashboard.GenerateHealthTrend(TimeSpan.FromHours(1));
```

## Log File Structure

Logs are stored in the `Logs/` directory:

```
Logs/
├── application-2026-04-16.txt           # Daily text logs
├── application-structured-2026-04-16.json  # Structured JSON logs
├── errors-2026-04-16.txt               # Error-only logs
├── critical-2026-04-16.txt             # Critical/Fatal logs
├── Archive/                            # Archived old logs
│   └── 2026-04-09_application-*.txt
└── CrashDumps/                         # Crash dump files
    └── crash_UnhandledException_*.txt
```

## Configuration

### Logger Levels

- **Debug**: Detailed diagnostic information
- **Information**: General informational messages
- **Warning**: Warning messages
- **Error**: Error messages
- **Fatal**: Critical/fatal errors

### Rotation Configuration

```csharp
var config = new LogRotationManager.RotationConfig
{
    MaxFileSizeBytes = 100 * 1024 * 1024,  // 100 MB per file
    MaxRetainedFiles = 30,                  // Keep 30 recent files
    DaysBeforeArchival = 7,                // Archive after 7 days
    DaysToKeepArchived = 90,               // Keep archives for 90 days
    CompressArchivedLogs = true            // Compress old logs
};

LogRotationManager.RotateLogs(config);
```

### Event Log Configuration

```csharp
// Event ID ranges
EventLogEventIds.Information = 1000
EventLogEventIds.Warning = 2000
EventLogEventIds.Error = 3000
EventLogEventIds.FailureAudit = 4000
EventLogEventIds.SuccessAudit = 5000
EventLogEventIds.HealthStatus = 6000
EventLogEventIds.Performance = 7000
EventLogEventIds.Crash = 8000
```

## API Reference

### LoggerConfiguration

```csharp
// Configure global logger
LoggerConfiguration.ConfigureGlobalLogger(minimumLevel);

// Get directory paths
string logDir = LoggerConfiguration.GetLogDirectory();
string archiveDir = LoggerConfiguration.GetArchiveDirectory();
string crashDir = LoggerConfiguration.GetCrashDumpDirectory();

// Cleanup
LoggerConfiguration.CloseLogger();
```

### CrashReporter

```csharp
// Register global handlers
CrashReporter.RegisterGlobalHandlers();

// Create a crash dump
string dumpPath = CrashReporter.CreateCrashDump(type, exception);

// Get all crash dumps
string[] dumps = CrashReporter.GetCrashDumps();

// Clean old dumps
CrashReporter.CleanOldCrashDumps(daysToKeep);
```

### HealthDiagnosticsEngine

```csharp
var engine = new HealthDiagnosticsEngine();

// Register health check
engine.RegisterHealthCheck(name, check);

// Run checks
var status = await engine.RunHealthCheckAsync(name);
var overall = await engine.RunAllHealthChecksAsync();

// Get cached status
var cached = engine.GetCachedStatus(name);
```

### PerformanceMonitor

```csharp
var monitor = new PerformanceMonitor();

// Register counter
monitor.RegisterCounter(name, description, type);

// Record values
monitor.IncrementCounter(name);
monitor.RecordTiming(name, durationMs);

// Get statistics
var summary = monitor.GetSummary();
```

### ResourceUsageTracker

```csharp
var tracker = new ResourceUsageTracker();

// Capture snapshot
var snapshot = tracker.CaptureSnapshot();

// Get statistics
var stats = tracker.GetStatistics(timeRange);

// Detect anomalies
var anomalies = tracker.DetectAnomalies();
```

### HealthAlertSystem

```csharp
var alertSystem = new HealthAlertSystem();

// Register handler
alertSystem.RegisterHandler(handler);

// Add rule
alertSystem.AddAlertRule(rule);

// Check and trigger alerts
alertSystem.CheckHealthStatus(healthStatus);

// Manage alerts
alertSystem.AcknowledgeAlert(alertId);
alertSystem.ResolveAlert(alertId);
```

## Best Practices

### 1. Initialize Early

Initialize logging and crash handlers at application startup before any business logic.

### 2. Use Structured Logging

Always use structured logging with context for better analysis:

```csharp
logger.Information("Order processed: {OrderId} for {CustomerId}", orderId, customerId);
```

### 3. Performance Measurements

Use measurement scopes for automatic timing:

```csharp
using (monitor.MeasurePerformance("OrderProcessing"))
{
    // Work here is automatically timed
}
```

### 4. Resource Monitoring

Capture snapshots periodically:

```csharp
var timer = new System.Timers.Timer(60000); // Every minute
timer.Elapsed += (s, e) => tracker.CaptureSnapshot();
timer.Start();
```

### 5. Alert Thresholds

Set appropriate alert thresholds based on your system:

```csharp
alertRule.Condition = (status) => 
    status.FailedCount > 0 || 
    status.CriticalCount > 0;
```

### 6. Regular Maintenance

Schedule regular log cleanup:

```csharp
// Daily: archive and cleanup
await Task.Delay(TimeSpan.FromHours(24));
LogRotationManager.RotateLogs(config);
CrashReporter.CleanOldCrashDumps(30);
```

## Troubleshooting

### Issue: Event Log Source Not Found

**Solution**: Run as Administrator to create the event log source:

```csharp
// Administrator required for EventLog.CreateEventSource
try
{
    WindowsEventLogIntegration.Initialize();
}
catch (UnauthorizedAccessException)
{
    // Run application as Administrator
}
```

### Issue: High CPU from Performance Counters

**Solution**: Reduce sampling frequency or increase batch intervals:

```csharp
var config = new LogAggregationConfig
{
    BatchSize = 500,      // Larger batches
    FlushIntervalMs = 10000  // Flush every 10 seconds instead of 5
};
```

### Issue: Disk Space Growing

**Solution**: Adjust rotation and retention:

```csharp
var config = new LogRotationManager.RotationConfig
{
    MaxRetainedFiles = 10,        // Keep fewer files
    DaysToKeepArchived = 30,      // Shorter retention
    MaxFileSizeBytes = 50 * 1024 * 1024  // Smaller files
};
```

## Performance Considerations

- **Logging overhead**: ~1-5ms per log entry
- **Memory tracking**: Snapshots stored in-memory, ~1KB per snapshot
- **CPU usage**: Negligible when properly configured

## Security Considerations

- **Sensitive Data**: Don't log passwords or API keys
- **Event Log Access**: Windows Event Log requires appropriate permissions
- **File Permissions**: Ensure log directories have proper access controls
- **Crash Dumps**: May contain sensitive information; store securely

## Extensions

### Custom Health Checks

```csharp
public class MyCustomCheck : IHealthCheck
{
    public async Task<HealthStatus> CheckAsync()
    {
        var result = await MyCustomCheckLogic();
        return new HealthStatus
        {
            Status = result ? HealthStatusCode.Healthy : HealthStatusCode.Failed,
            Message = result ? "OK" : "Failed"
        };
    }
}
```

### Custom Alert Handlers

```csharp
public class EmailAlertHandler : IAlertHandler
{
    public void HandleAlert(Alert alert)
    {
        // Send email notification
    }
}
```

### Custom Log Aggregator

```csharp
public class MyAggregator : ILogAggregator
{
    public async Task SendLogsAsync(IEnumerable<AggregatedLogEntry> logs)
    {
        // Send to external service
    }
}
```

## Examples

See `LoggingAndDiagnosticsExamples.cs` for 10 complete working examples covering:

1. Logger initialization
2. Structured logging with context
3. Log rotation and archival
4. Crash reporting
5. Health diagnostics
6. Performance monitoring
7. Resource usage tracking
8. Alert system
9. Custom performance counters
10. Dashboard generation

## Support & Documentation

- **API Documentation**: See XML comments in source files
- **Examples**: See `LoggingAndDiagnosticsExamples.cs`
- **Configuration**: See configuration classes and comments
- **Troubleshooting**: See "Troubleshooting" section above

## License

Part of the HELIOS Platform. See main repository for license details.

## Version

Version 1.0.0 - Production Ready

## Changelog

### v1.0.0

- Initial release
- 14 core components
- Complete documentation
- Example implementations
- Production-ready logging system
