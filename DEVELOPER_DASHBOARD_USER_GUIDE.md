# Developer Dashboard v3.6.0 - User Guide

## Overview

The Developer Dashboard is a comprehensive tool for monitoring, analyzing, and optimizing the Helios Platform. It provides real-time metrics, performance analysis, and advanced debugging capabilities in an intuitive, responsive interface.

### Key Features

- **Real-time Performance Monitoring**: CPU, memory, disk, and network metrics
- **Process Management**: Monitor and manage system processes
- **Performance Analytics**: Historical data and trend analysis
- **Developer Tools**: API Explorer, Theme Builder, Plugin Generator
- **Advanced Debugging**: Crash dump analysis, bottleneck detection, memory profiling
- **Event Tracing**: System event recording and analysis

---

## Dashboard Tabs

### 1. Overview Tab

The Overview tab provides a quick snapshot of system health and key metrics.

**Features:**

- Real-time CPU, Memory, Disk, and Network metrics
- Health status summary
- Quick access to common operations
- Auto-refreshing indicators

**How to Use:**

1. Open the Dashboard
2. The Overview tab is selected by default
3. View current system metrics in the upper section
4. Click "Refresh" to update all metrics
5. Click on any metric to view historical data

### 2. Performance Tab

Detailed performance metrics with historical trends and visualization.

**Features:**

- CPU and Memory usage graphs (60-minute history)
- Peak usage tracking
- Trend analysis with color indicators
- Comparative analysis tools

**How to Use:**

1. Navigate to the Performance tab
2. View the metric timeline graph
3. Hover over graph points to see exact values
4. Use the time range selector to adjust the view
5. Toggle metrics on/off using the legend

### 3. Processes Tab

Monitor and manage system processes with detailed metrics.

**Features:**

- List of top 20 processes by memory usage
- CPU percentage per process
- Thread count tracking
- Process status (Running/Not Responding)
- Terminate process capability

**How to Use:**

1. Go to the Processes tab
2. View the process list sorted by memory usage
3. Click "Refresh" to update the list
4. To terminate a process: select it and click "Terminate"
5. Red indicator means process is not responding

**⚠️ Warning:** Only terminate processes you're certain about. System processes termination can cause instability.

### 4. Logs & Events Tab

View and filter system logs and events with search capability.

**Features:**

- Real-time log entries with timestamps
- Severity filtering (ERROR, WARNING, INFO)
- Full-text search capability
- Source filtering
- Export logs to file
- Auto-scroll to latest entry

**How to Use:**

1. Navigate to Logs & Events tab
2. Use the Filter dropdown to select log level
3. Use the Search box for keyword search
4. Click "Clear All" to reset the log view
5. Right-click entries for additional options (copy, export)

### 5. Developer Tools Tab

Suite of tools for API testing, theme customization, and plugin development.

#### API Explorer

Interactive REST/GraphQL API testing tool.

**Features:**

- Request builder (GET, POST, PUT, DELETE, PATCH)
- JSON payload editor with syntax highlighting
- Response viewer with formatting
- Request history with timing
- Export requests as cURL commands

**How to Use:**

1. Select "API Explorer" from the Tools tab
2. Enter API endpoint URL
3. Choose HTTP method from dropdown
4. Enter request payload (if applicable)
5. Click "Execute"
6. View response in the Response panel

#### Theme Builder

Visual theme customization and export.

**Features:**

- Live color picker for theme colors
- Real-time preview of color changes
- Pre-built theme templates
- Export theme as JSON
- Import custom themes

**How to Use:**

1. Click on "Theme Builder"
2. Click on color swatches to change colors
3. See the preview update in real-time
4. Click "Export" to save as JSON
5. Click "Apply" to use as current theme

#### Plugin Generator

Scaffolding tool for new plugin development.

**Features:**

- Multiple plugin templates (Basic, UI Widget, Service)
- Automatic file generation
- Dependency resolution
- Ready-to-use project structure

**How to Use:**

1. Select "Plugin Generator"
2. Enter your plugin name
3. Choose a template
4. Click "Generate"
5. Navigate to the output directory to view generated files

#### Performance Profiler

Built-in performance profiling for optimization.

**Features:**

- Function call timing
- Memory allocation tracking
- Hot spot detection
- Comparative analysis
- Export profiling data

**How to Use:**

1. Click "Start Profiling"
2. Perform the operation you want to profile
3. Click "Stop Profiling"
4. Review the results showing function timings
5. Focus optimization on high-impact functions

### 6. Advanced Tab

Advanced debugging and analysis tools.

#### Crash Dump Analyzer

Analyze crash dumps from system processes.

**Features:**

- Automatic crash detection
- Stack trace extraction
- Exception type identification
- Dump file management
- Multi-crash comparison

**How to Use:**

1. Go to Advanced tab
2. Click "Analyze Crashes"
3. View detected crash dumps
4. Click on a crash to view details
5. Review stack traces and exception info

#### Performance Bottleneck Detector

Identify performance issues and optimization opportunities.

**Features:**

- Memory allocation analysis
- Garbage collection impact assessment
- Thread contention detection
- I/O bottleneck identification
- Severity scoring

**How to Use:**

1. Click "Detect Bottlenecks"
2. Review detected issues with severity
3. Read recommendations for each issue
4. Implement suggested optimizations
5. Re-run detection to measure improvements

#### Dependency Visualizer

Visual representation of module and package dependencies.

**Features:**

- Dependency graph generation
- Circular dependency detection
- Version compatibility checking
- Dependency health scoring

**How to Use:**

1. Click "Visualize Dependencies"
2. View the interactive dependency graph
3. Zoom and pan to explore relationships
4. Click nodes to view details
5. Identify problematic dependencies

#### Memory Profiler

Detailed memory allocation and garbage collection analysis.

**Features:**

- Memory snapshot comparison
- Allocation tracking by type
- GC pause time analysis
- Memory leak detection
- Historical comparison

**How to Use:**

1. Click "Start Memory Profiling"
2. Perform operations to profile
3. Click "Stop Memory Profiling"
4. View memory allocation breakdown
5. Analyze trends and patterns

#### Trace Viewer

System event and execution trace analysis.

**Features:**

- Real-time event capture
- Timeline visualization
- Event filtering and search
- Duration analysis
- Component interaction mapping

**How to Use:**

1. Click "Start Trace"
2. Perform operations to trace
3. Click "Stop Trace"
4. Review event timeline
5. Analyze component interactions

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Next Tab | Ctrl + Tab |
| Previous Tab | Ctrl + Shift + Tab |
| Refresh Metrics | F5 |
| Clear History | Ctrl + L |
| Export Data | Ctrl + E |
| Search | Ctrl + F |
| Settings | Ctrl + , |

---

## Settings and Preferences

### Dashboard Preferences

1. **Auto-Refresh**
   - Enable automatic metric updates
   - Set refresh interval (1-60 seconds)
   - Default: 5 seconds

2. **Data Retention**
   - Metrics history duration (1 hour - 7 days)
   - Log entry limit (100 - 10,000)
   - Default: 24 hours / 1,000 entries

3. **Display Options**
   - Theme: Light / Dark / Custom
   - Graph update speed
   - Chart types (Line / Area / Bar)

4. **Alerts**
   - CPU threshold (50-95%)
   - Memory threshold (60-95%)
   - Enable/disable notifications
   - Alert sound toggle

### Exporting Data

1. **CSV Export**
   - Click "Export" button
   - Select date range
   - Choose metrics to include
   - File saved to Downloads

2. **JSON Export**
   - Click "Export as JSON"
   - All data with timestamps
   - Structured format for analysis

3. **PDF Reports**
   - Click "Generate Report"
   - Select timeframe
   - Choose analysis type
   - Email option available

---

## Troubleshooting

### Dashboard Won't Load

- Restart the application
- Check system permissions
- Verify .NET 6.0+ is installed

### Metrics Not Updating

- Check "Auto-Refresh" is enabled
- Click "Refresh" button manually
- Check system resource availability

### Performance Tools Not Responding

- Close and reopen the dashboard
- Check for sufficient disk space
- Verify administrative privileges

### Logs Not Showing

- Click "Clear Filters"
- Ensure log level is not set to highest
- Check event log service is running

---

## Developer API for Custom Widgets

### Creating a Custom Widget

```csharp
public class CustomMetricWidget : IDashboardWidget
{
    public string Title { get; set; }
    public string WidgetId { get; set; }
    public object Content { get; set; }
    
    public void Refresh()
    {
        // Update widget data
    }
    
    public void Initialize()
    {
        // Setup widget
    }
}
```

### Registering a Widget

```csharp
dashboard.RegisterWidget(
    new CustomMetricWidget 
    { 
        WidgetId = "custom-metric",
        Title = "Custom Metric"
    }
);
```

### Widget Lifecycle

1. **Initialize** - Called when dashboard loads
2. **Refresh** - Called when data updates
3. **Dispose** - Called when dashboard closes

---

## Extension Guide

### Creating Dashboard Extensions

Extensions can add new tabs, tools, or features.

**Extension Structure:**

```
MyExtension/
├── MyExtensionViewModel.cs
├── MyExtensionView.xaml
├── MyExtensionView.xaml.cs
├── Resources/
│   └── Icons/
└── manifest.json
```

**manifest.json:**

```json
{
  "id": "my-extension",
  "name": "My Extension",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Extension description",
  "targetVersion": "3.6.0",
  "entry": "MyExtension.MyExtensionView"
}
```

### Loading Extensions

1. Place extension folder in `%AppData%/Helios/Extensions`
2. Restart Dashboard
3. New tab appears automatically

---

## Performance Optimization Tips

1. **Reduce History Retention** - Keep only recent data
2. **Enable Selective Logging** - Only log necessary events
3. **Use Sampling** - Sample metrics instead of capturing all
4. **Close Unused Tabs** - Reduces background processing
5. **Adjust Refresh Rate** - Lower refresh interval for faster data
6. **Monitor Process List** - Terminate unnecessary processes
7. **Optimize Memory** - Use Memory Profiler to find leaks

---

## Best Practices

1. **Regular Monitoring** - Check dashboard daily for anomalies
2. **Baseline Metrics** - Record normal operating metrics
3. **Alert Configuration** - Set appropriate thresholds
4. **Log Retention** - Balance detail vs. storage
5. **Backup Data** - Export critical metrics regularly
6. **Theme Consistency** - Maintain visual coherence
7. **Documentation** - Document custom extensions

---

## Support and Resources

- **Documentation**: https://docs.helios.local/dashboard
- **Bug Reports**: https://github.com/helios/issues
- **Community**: https://community.helios.local
- **API Docs**: https://api.helios.local/docs

---

## Version History

### v3.6.0 (Current)

- Initial release
- 6 main tabs with 15+ sub-features
- 35+ test coverage
- Real-time metric updates
- Advanced debugging tools

---

## License

Developer Dashboard is part of the Helios Platform and is subject to the same license terms.
