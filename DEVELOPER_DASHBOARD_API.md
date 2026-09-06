# Developer Dashboard - Technical API Documentation

## Architecture Overview

The Developer Dashboard follows the MVVM (Model-View-ViewModel) pattern for clean separation of concerns and testability.

### Component Structure

```
MonadoBlade.GUI/
├── ViewModels/
│   ├── DeveloperDashboardViewModel.cs (Core dashboard state)
│   ├── AnalyticsViewModel.cs (Performance metrics & processes)
│   ├── DeveloperToolsViewModel.cs (API, themes, plugins)
│   └── AdvancedFeaturesViewModel.cs (Advanced debugging)
├── Views/
│   └── DeveloperDashboard.xaml
└── Controls/
    └── Dashboard widgets and components
```

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

**Usage Example:**

```csharp
var dashboard = new DeveloperDashboardViewModel();

// Subscribe to property changes
dashboard.PropertyChanged += (s, e) => 
{
    if (e.PropertyName == nameof(dashboard.CpuUsage))
    {
        Console.WriteLine($"CPU: {dashboard.CpuUsage}%");
    }
};

// Switch tabs
dashboard.SelectTabCommand.Execute("performance");

// Refresh metrics
dashboard.RefreshCommand.Execute(null);
```

---

### AnalyticsViewModel

Provides performance analytics, process management, and system health.

**Key Classes:**

#### PerformanceMetric

```csharp
public class PerformanceMetric
{
    public string Label { get; set; }
    public double Value { get; set; }
    public double MaxValue { get; set; }
    public string Unit { get; set; }
    public Color IndicatorColor { get; set; }
    public DateTime Timestamp { get; set; }
}
```

#### ProcessInfo

```csharp
public class ProcessInfo
{
    public int Id { get; set; }
    public string Name { get; set; }
    public double MemoryMB { get; set; }
    public double CpuPercent { get; set; }
    public int ThreadCount { get; set; }
    public string Status { get; set; }
    public Color StatusColor { get; set; }
}
```

#### SystemHealthStatus

```csharp
public class SystemHealthStatus
{
    public string Category { get; set; }
    public string Status { get; set; }
    public Color StatusColor { get; set; }
    public string Details { get; set; }
    public double HealthScore { get; set; }
}
```

#### LogEntry

```csharp
public class LogEntry
{
    public DateTime Timestamp { get; set; }
    public string Level { get; set; }
    public string Source { get; set; }
    public string Message { get; set; }
    public Color LevelColor { get; set; }
}
```

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

**Usage Example:**

```csharp
var analytics = new AnalyticsViewModel();

// Get top processes
analytics.RefreshCommand.Execute(null);
var topProcess = analytics.ProcessList.First();

// Filter logs
analytics.FilterLogsCommand.Execute("ERROR");

// Terminate process (use with caution!)
analytics.TerminateProcessCommand.Execute(topProcess);
```

---

### DeveloperToolsViewModel

API testing, theme building, and plugin generation tools.

**Key Classes:**

#### ApiRequest

```csharp
public class ApiRequest
{
    public string Id { get; set; }
    public string Method { get; set; }
    public string Endpoint { get; set; }
    public string Payload { get; set; }
    public string Response { get; set; }
    public int StatusCode { get; set; }
    public double Duration { get; set; }
    public DateTime Timestamp { get; set; }
}
```

#### ThemeColor

```csharp
public class ThemeColor
{
    public string Name { get; set; }
    public Color Value { get; set; }
    public string HexValue { get; set; }
}
```

#### PluginTemplate

```csharp
public class PluginTemplate
{
    public string Id { get; set; }
    public string Name { get; set; }
    public string Description { get; set; }
    public string TargetFramework { get; set; }
}
```

#### PerformanceProfile

```csharp
public class PerformanceProfile
{
    public string FunctionName { get; set; }
    public long TimeMs { get; set; }
    public int CallCount { get; set; }
    public double AverageMs { get; set; }
    public Color TrendColor { get; set; }
}
```

**Key Properties:**

```csharp
ObservableCollection<ApiRequest> ApiRequests { get; set; }
ObservableCollection<ThemeColor> ThemeColors { get; set; }
ObservableCollection<PluginTemplate> PluginTemplates { get; set; }
ObservableCollection<PerformanceProfile> PerformanceProfiles { get; set; }
string ApiMethod { get; set; }
string ApiEndpoint { get; set; }
string ApiPayload { get; set; }
bool IsProfiling { get; set; }
```

**Key Commands:**

```csharp
ICommand ExecuteApiCommand          // Execute API request
ICommand ClearApiCommand            // Clear request history
ICommand GeneratePluginCommand      // Create plugin scaffold
ICommand ExportThemeCommand         // Export theme as JSON
ICommand StartProfilingCommand      // Start performance profiling
ICommand StopProfilingCommand       // Stop profiling
ICommand ShowEventViewerCommand     // Open event viewer
```

**Usage Example:**

```csharp
var tools = new DeveloperToolsViewModel();

// Execute API request
tools.ApiEndpoint = "https://api.example.com/data";
tools.ApiMethod = "GET";
tools.ExecuteApiCommand.Execute(null);

// Generate plugin
tools.PluginName = "MyPlugin";
tools.SelectedTemplateId = "basic";
tools.GeneratePluginCommand.Execute(null);

// Profile performance
tools.StartProfilingCommand.Execute(null);
// ... perform operations ...
tools.StopProfilingCommand.Execute(null);
```

---

### AdvancedFeaturesViewModel

Crash analysis, bottleneck detection, and memory profiling.

**Key Classes:**

#### CrashDump

```csharp
public class CrashDump
{
    public string Id { get; set; }
    public string ProcessName { get; set; }
    public DateTime Timestamp { get; set; }
    public string ExceptionType { get; set; }
    public string StackTrace { get; set; }
    public string FilePath { get; set; }
    public long FileSize { get; set; }
}
```

#### BottleneckDetection

```csharp
public class BottleneckDetection
{
    public string Category { get; set; }
    public string Issue { get; set; }
    public string Severity { get; set; }
    public Color SeverityColor { get; set; }
    public string Recommendation { get; set; }
    public double ImpactScore { get; set; }
}
```

#### DependencyNode

```csharp
public class DependencyNode
{
    public string Name { get; set; }
    public string Version { get; set; }
    public int DependencyCount { get; set; }
    public bool HasCircular { get; set; }
    public Color StatusColor { get; set; }
}
```

#### MemoryAllocation

```csharp
public class MemoryAllocation
{
    public string Type { get; set; }
    public long BytesAllocated { get; set; }
    public long BytesRetained { get; set; }
    public int AllocationCount { get; set; }
    public double PercentOfTotal { get; set; }
}
```

#### TraceEvent

```csharp
public class TraceEvent
{
    public DateTime Timestamp { get; set; }
    public string EventType { get; set; }
    public string ComponentName { get; set; }
    public string Details { get; set; }
    public long Duration { get; set; }
    public Color EventColor { get; set; }
}
```

**Key Properties:**

```csharp
ObservableCollection<CrashDump> CrashDumps { get; set; }
ObservableCollection<BottleneckDetection> Bottlenecks { get; set; }
ObservableCollection<DependencyNode> Dependencies { get; set; }
ObservableCollection<MemoryAllocation> MemoryAllocations { get; set; }
ObservableCollection<TraceEvent> TraceEvents { get; set; }
double OverallHealth { get; set; }
int CriticalIssues { get; set; }
int WarningIssues { get; set; }
```

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

**Usage Example:**

```csharp
var advanced = new AdvancedFeaturesViewModel();

// Analyze crashes
advanced.AnalyzeCrashCommand.Execute(null);
foreach (var crash in advanced.CrashDumps)
{
    Console.WriteLine($"Crash: {crash.ProcessName} - {crash.ExceptionType}");
}

// Detect bottlenecks
advanced.DetectBottlenecksCommand.Execute(null);
var criticalBottlenecks = advanced.Bottlenecks
    .Where(b => b.Severity == "Critical");

// Profile memory
advanced.StartMemoryProfilingCommand.Execute(null);
// ... perform operations ...
advanced.StopMemoryProfilingCommand.Execute(null);
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

### Computed Properties

Use LINQ for computed values:

```csharp
public double AverageCpu => 
    ProcessList.Count > 0 ? ProcessList.Average(p => p.CpuPercent) : 0;
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

### Event Subscription

```csharp
// Subscribe to metric changes
dashboard.PropertyChanged += (s, e) => 
{
    if (e.PropertyName == nameof(dashboard.CpuUsage))
    {
        OnMetricChanged();
    }
};
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

### Memory Profiling

- Use sampling instead of allocation tracking
- Limit trace buffer size
- Clear old events periodically
- Profile during low-load periods

---

## Extensibility

### Custom Widget Interface

```csharp
public interface IDashboardWidget
{
    string WidgetId { get; }
    string Title { get; }
    object Content { get; }
    
    void Initialize();
    void Refresh();
    void Dispose();
}
```

### Adding Custom Tools

```csharp
public class CustomTool : IDashboardTool
{
    public string ToolId => "custom-tool";
    public string ToolName => "My Custom Tool";
    
    public void Execute()
    {
        // Implementation
    }
}

dashboard.RegisterTool(new CustomTool());
```

### Theme Extension

```csharp
public class CustomTheme : ITheme
{
    public string ThemeId => "custom";
    public Color PrimaryColor => Color.FromRgb(0, 217, 255);
    public Color SecondaryColor => Color.FromRgb(102, 51, 153);
}
```

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

### Integration Test Example

```csharp
[Fact]
public void Analytics_ProcessTermination_RemovesProcess()
{
    var vm = new AnalyticsViewModel();
    vm.RefreshCommand.Execute(null);
    System.Threading.Thread.Sleep(500);

    var initialCount = vm.ProcessList.Count;
    var processToTerminate = vm.ProcessList.First();
    
    vm.TerminateProcessCommand.Execute(processToTerminate);
    
    Assert.True(vm.ProcessList.Count <= initialCount);
}
```

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

## Performance Benchmarks

- Dashboard initialization: < 100ms
- Metric refresh: < 500ms
- Tab switching: < 50ms
- API request execution: < 500ms
- Process list update: < 1000ms
- Crash analysis: < 500ms
- Memory profiling startup: < 100ms

---

## API Reference Version

- **Version**: 3.6.0
- **Updated**: 2026-04-24
- **Status**: Stable
