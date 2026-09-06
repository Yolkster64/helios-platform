# Developer Dashboard - Technical API Documentation

## Architecture Overview

The Developer Dashboard follows the MVVM (Model-View-ViewModel) pattern for clean separation of concerns and testability.

---

## Core ViewModels

### DeveloperDashboardViewModel

Main dashboard controller managing tab navigation and overall metrics.

**Key Properties:**

```csharp
ObservableCollection<DashboardTab> Tabs { get; set; }
DashboardTab SelectedTab { get; set; }
ObservableCollection<PerformanceMetric> Metrics { get; set; }
double CpuUsage { get; set; }
double MemoryUsage { get; set; }
double DiskUsage { get; set; }
double NetworkLatency { get; set; }
int ActiveProcesses { get; set; }
bool IsRefreshing { get; set; }
DateTime LastUpdate { get; set; }
```

**Key Commands:**

```csharp
ICommand SelectTabCommand        // Switch between dashboard tabs
ICommand RefreshCommand          // Update all metrics
ICommand SettingsCommand         // Open settings dialog
```

### AnalyticsViewModel

Provides performance analytics, process management, and system health.

**Key Classes:**

- PerformanceMetric
- ProcessInfo
- SystemHealthStatus
- LogEntry

**Key Properties:**

```csharp
ObservableCollection<MetricDataPoint> MetricsHistory { get; set; }
ObservableCollection<ProcessInfo> ProcessList { get; set; }
ObservableCollection<SystemHealthStatus> HealthStatuses { get; set; }
ObservableCollection<LogEntry> LogEntries { get; set; }
double AverageCpu { get; set; }
double AverageMemory { get; set; }
double PeakCpu { get; set; }
double PeakMemory { get; set; }
```

**Key Commands:**

```csharp
ICommand RefreshCommand              // Load latest process list
ICommand TerminateProcessCommand     // Kill a process
ICommand ClearLogsCommand            // Clear log entries
ICommand FilterLogsCommand           // Filter by level
```

### DeveloperToolsViewModel

API testing, theme building, and plugin generation tools.

**Key Classes:**

- ApiRequest
- ThemeColor
- PluginTemplate
- PerformanceProfile

**Key Commands:**

```csharp
ICommand ExecuteApiCommand          // Execute API request
ICommand ClearApiCommand            // Clear request history
ICommand GeneratePluginCommand      // Create plugin scaffold
ICommand ExportThemeCommand         // Export theme as JSON
ICommand StartProfilingCommand      // Start performance profiling
ICommand StopProfilingCommand       // Stop profiling
```

### AdvancedFeaturesViewModel

Crash analysis, bottleneck detection, and memory profiling.

**Key Classes:**

- CrashDump
- BottleneckDetection
- DependencyNode
- MemoryAllocation
- TraceEvent

**Key Commands:**

```csharp
ICommand AnalyzeCrashCommand           // Scan for crash dumps
ICommand DetectBottlenecksCommand      // Find performance issues
ICommand VisualizeDependenciesCommand  // Generate dependency graph
ICommand StartMemoryProfilingCommand   // Start memory analysis
ICommand StopMemoryProfilingCommand    // Stop memory analysis
ICommand ViewCrashDetailsCommand       // View crash info
ICommand StartTraceCommand             // Start event tracing
ICommand StopTraceCommand              // Stop tracing
```

---

## Data Binding Patterns

### Observable Collections

All view models use `ObservableCollection<T>` for automatic UI updates:

```csharp
public ObservableCollection<ProcessInfo> ProcessList { get; set; }

// Changes automatically update the UI
ProcessList.Add(newProcess);
ProcessList.Remove(oldProcess);
ProcessList[0] = updatedProcess;
```

### Property Change Notifications

Implement property changes for metrics and state:

```csharp
private double _cpuUsage;
public double CpuUsage
{
    get => _cpuUsage;
    set => SetProperty(ref _cpuUsage, value);
}
```

---

## Real-Time Updates

### Auto-Refresh Pattern

```csharp
private async void RefreshMetrics()
{
    IsRefreshing = true;
    try
    {
        await Task.Run(() => UpdateSystemMetrics());
        LastUpdate = DateTime.Now;
    }
    finally
    {
        IsRefreshing = false;
    }
}
```

---

## Performance Considerations

### Metric Collection (<16ms frame time)

- Use async operations for I/O
- Cache metric calculations
- Throttle refresh operations
- Limit history retention

### Process List Management

- Load in background thread
- Cache process handles
- Limit to top N processes
- Update incrementally

---

## Testing

### Unit Test Example

```csharp
[Fact]
public void DashboardViewModel_RefreshMetrics_UpdatesCpuUsage()
{
    var vm = new DeveloperDashboardViewModel();
    var initialCpu = vm.CpuUsage;
    
    vm.RefreshCommand.Execute(null);
    System.Threading.Thread.Sleep(500);

    Assert.NotEqual(initialCpu, vm.CpuUsage);
}
```

---

## Performance Benchmarks

- Dashboard initialization: < 100ms
- Metric refresh: < 500ms
- Tab switching: < 50ms
- API request execution: < 500ms
- Process list update: < 1000ms
- Crash analysis: < 500ms
- Memory profiling startup: < 100ms

---

## Best Practices

1. **Thread Safety**: Always use ObservableCollection on UI thread
2. **Async Operations**: Use async/await for I/O operations
3. **Resource Management**: Dispose of resources properly
4. **Error Handling**: Wrap commands in try-catch blocks
5. **Logging**: Log all operations for debugging
6. **Testing**: Aim for 80%+ code coverage
7. **Documentation**: Update docs when API changes

---

## Version

- **Version**: 3.6.0
- **Updated**: 2026-04-24
- **Status**: Stable
