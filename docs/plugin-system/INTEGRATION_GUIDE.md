# Plugin System Integration Guide

## Installation

### 1. Copy Plugin System to Your Project

Copy the entire `src/HELIOS.Platform/Core/Plugins/` directory to your project's source structure.

### 2. Add Required References

The plugin system requires only standard .NET libraries:

- System
- System.Collections.Generic
- System.IO
- System.Reflection
- System.Text.Json
- System.Threading.Tasks

### 3. Create Plugin Directory Structure

```
YourProject/
├── plugins/
│   ├── MyPlugin/
│   │   ├── plugin.json
│   │   └── MyPlugin.dll
│   └── AnotherPlugin/
│       ├── plugin.json
│       └── AnotherPlugin.dll
├── plugin-config/
│   ├── com.example.myplugin.json
│   └── com.example.another.json
└── docs/
    └── plugins/
```

## Integration Steps

### Step 1: Initialize the Plugin Manager

```csharp
using HELIOS.Platform.Core.Plugins.Services;

public class PluginServiceBootstrapper
{
    private PluginManager _pluginManager;

    public async Task InitializeAsync()
    {
        // Create plugin manager with paths
        _pluginManager = new PluginManager(
            pluginDirectoryPath: Path.Combine(AppContext.BaseDirectory, "plugins"),
            configDirectoryPath: Path.Combine(AppContext.BaseDirectory, "plugin-config")
        );

        // Subscribe to events
        _pluginManager.PluginLoaded += OnPluginLoaded;
        _pluginManager.PluginUnloaded += OnPluginUnloaded;
        _pluginManager.PluginStateChanged += OnPluginStateChanged;

        // Discover and load plugins
        var result = await _pluginManager.DiscoverAndLoadAllPluginsAsync();

        if (result.IsSuccessful)
        {
            Console.WriteLine($"Loaded {result.SuccessfulLoads.Count} plugins");
        }
        else
        {
            Console.WriteLine("Failed plugins:");
            foreach (var failure in result.FailedLoads)
            {
                Console.WriteLine($"  {failure.Key}: {failure.Value}");
            }
        }

        // Start all plugins
        await _pluginManager.StartAllPluginsAsync();
    }

    private void OnPluginLoaded(object sender, PluginEventArgs e)
    {
        Console.WriteLine($"✓ Plugin loaded: {e.Plugin.Name}");
    }

    private void OnPluginUnloaded(object sender, PluginEventArgs e)
    {
        Console.WriteLine($"✗ Plugin unloaded: {e.Plugin.Name}");
    }

    private void OnPluginStateChanged(object sender, Abstractions.PluginStateChangedEventArgs e)
    {
        Console.WriteLine($"Plugin {e.PluginId}: {e.OldState} → {e.NewState}");
    }
}
```

### Step 2: Configure Plugins

Create plugin configuration files in `plugin-config/` directory:

**com.example.myplugin.json**:

```json
{
  "enabled": true,
  "timeout_ms": 5000,
  "max_threads": 4,
  "database": {
    "host": "localhost",
    "port": 5432
  }
}
```

### Step 3: Use Plugins

```csharp
// Execute plugin commands
var result = await _pluginManager.ExecuteCommandAsync(
    pluginId: "com.example.myplugin",
    commandName: "process",
    parameters: new Dictionary<string, object>
    {
        { "input", "data to process" }
    }
);

if (result.Success)
{
    Console.WriteLine($"Result: {result.Data}");
}

// Subscribe to plugin events
_pluginManager.SubscribeToEvent("com.example.myplugin", "data-processed", async (data) =>
{
    Console.WriteLine($"Data processed: {data}");
    await Task.CompletedTask;
});

// Publish events from your application
await _pluginManager.PublishEventAsync(
    pluginId: "com.example.myplugin",
    eventName: "data-available",
    eventData: new { count = 100, timestamp = DateTime.UtcNow }
);
```

### Step 4: Monitor Plugins

```csharp
// Get platform status
var status = await _pluginManager.GetStatusAsync();
Console.WriteLine($"Total plugins: {status.TotalPluginsLoaded}");
Console.WriteLine($"Running: {status.RunningPlugins}");

foreach (var pluginStatus in status.PluginStates.Values)
{
    Console.WriteLine($"\n{pluginStatus.Name} v{pluginStatus.Version}");
    Console.WriteLine($"  State: {pluginStatus.State}");
    Console.WriteLine($"  Healthy: {pluginStatus.Health.IsHealthy}");
    Console.WriteLine($"  Status: {pluginStatus.Health.Status}");
}

// Monitor specific plugin metrics
var metrics = _pluginManager.GetExecutionMetrics("com.example.myplugin");
Console.WriteLine($"Executions: {metrics.TotalExecutions}");
Console.WriteLine($"Avg time: {metrics.AverageDurationMs}ms");
Console.WriteLine($"Peak memory: {metrics.PeakMemoryMB}MB");
```

### Step 5: Shutdown

```csharp
// Gracefully shutdown
await _pluginManager.StopAllPluginsAsync();
_pluginManager.Dispose();
```

## Complete Integration Example

```csharp
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using HELIOS.Platform.Core.Plugins.Services;
using HELIOS.Platform.Core.Plugins.Security;

public class Application
{
    private PluginManager _pluginManager;

    public async Task RunAsync()
    {
        try
        {
            // Initialize
            await InitializePluginSystem();

            // Use plugins
            await UsePluginsAsync();

            // Monitor
            await MonitorPluginsAsync();
        }
        finally
        {
            // Cleanup
            await ShutdownPluginSystem();
        }
    }

    private async Task InitializePluginSystem()
    {
        Console.WriteLine("Initializing plugin system...");

        _pluginManager = new PluginManager(
            pluginDirectoryPath: "./plugins",
            configDirectoryPath: "./plugin-config"
        );

        // Configure security policies
        var policy = PluginSecurityPolicy.CreateDefault("com.example.plugin");
        _pluginManager.SetSecurityPolicy("com.example.plugin", policy);

        // Subscribe to events
        _pluginManager.PluginLoaded += (s, e) =>
            Console.WriteLine($"✓ {e.Plugin.Name} loaded");

        _pluginManager.PluginStateChanged += (s, e) =>
            Console.WriteLine($"  {e.PluginId}: {e.OldState} → {e.NewState}");

        // Discover and load
        var result = await _pluginManager.DiscoverAndLoadAllPluginsAsync();
        Console.WriteLine($"Loaded {result.SuccessfulLoads.Count} plugins");

        // Start
        await _pluginManager.StartAllPluginsAsync();
        Console.WriteLine("All plugins started");
    }

    private async Task UsePluginsAsync()
    {
        Console.WriteLine("\nUsing plugins...");

        // Example: Use logging plugin
        var logResult = await _pluginManager.ExecuteCommandAsync(
            "com.helios.plugins.log",
            "write_log",
            new Dictionary<string, object>
            {
                { "message", "Application started" },
                { "level", "INFO" }
            }
        );

        // Example: Use metrics plugin
        var metricsResult = await _pluginManager.ExecuteCommandAsync(
            "com.helios.plugins.metrics",
            "record_metric",
            new Dictionary<string, object>
            {
                { "name", "app.startup_time" },
                { "value", 1234.5 }
            }
        );

        // Example: Use alerts plugin
        var alertResult = await _pluginManager.ExecuteCommandAsync(
            "com.helios.plugins.alerts",
            "create_alert",
            new Dictionary<string, object>
            {
                { "title", "Application Started" },
                { "message", "Application has started successfully" },
                { "severity", "INFO" }
            }
        );

        await Task.CompletedTask;
    }

    private async Task MonitorPluginsAsync()
    {
        Console.WriteLine("\nMonitoring plugins...");

        while (true)
        {
            var status = await _pluginManager.GetStatusAsync();

            Console.WriteLine($"\n[{DateTime.Now:HH:mm:ss}] Platform Status");
            Console.WriteLine($"  Total: {status.TotalPluginsLoaded}");
            Console.WriteLine($"  Running: {status.RunningPlugins}");

            foreach (var ps in status.PluginStates.Values)
            {
                var healthIcon = ps.Health.IsHealthy ? "✓" : "✗";
                Console.WriteLine($"  {healthIcon} {ps.Name}: {ps.State}");
            }

            await Task.Delay(5000);
        }
    }

    private async Task ShutdownPluginSystem()
    {
        Console.WriteLine("\nShutting down plugin system...");

        await _pluginManager.StopAllPluginsAsync();
        _pluginManager.Dispose();

        Console.WriteLine("Plugin system shut down");
    }
}

// Usage
var app = new Application();
await app.RunAsync();
```

## Deployment Checklist

- [ ] Plugin system libraries are included in deployment
- [ ] Plugin directory exists and is accessible
- [ ] Plugin configuration files are created
- [ ] All plugin DLLs and manifests are in plugins directory
- [ ] Plugin security policies are configured appropriately
- [ ] Plugin startup order is correct (based on dependencies)
- [ ] Error handling is in place for plugin failures
- [ ] Monitoring and logging are configured
- [ ] Performance baseline is established
- [ ] Backup strategy includes plugin configurations

## Troubleshooting

### Plugins Not Loading

**Issue**: Plugins not discovered or loaded

**Solutions**:

1. Check plugin directory path is correct
2. Verify manifest file names are `plugin.json`
3. Ensure assembly files exist with correct names
4. Check assembly is not locked by another process
5. Review error messages in logs

### Plugin Initialization Failures

**Issue**: Plugin fails during initialization

**Solutions**:

1. Check plugin configuration file exists and is valid
2. Verify plugin dependencies are loaded first
3. Review plugin logs for specific errors
4. Ensure plugin has necessary permissions
5. Check IPlugin implementation is correct

### Dependency Resolution Issues

**Issue**: Dependency conflicts or missing dependencies

**Solutions**:

1. Verify version constraints in manifest
2. Check all dependency plugins are present
3. Review dependency resolution output
4. Ensure version format matches semver
5. Check for circular dependencies

### Security Policy Issues

**Issue**: Plugin fails due to security restrictions

**Solutions**:

1. Review security policy configuration
2. Check if less restrictive policy is needed
3. Verify plugin doesn't require blocked operations
4. Review execution metrics for violations
5. Consider plugin trustworthiness

---

## Additional Resources

- **Plugin Development Guide**: `PLUGIN_DEVELOPMENT_GUIDE.md`
- **API Reference**: `API_REFERENCE.md`
- **Sample Plugins**: `samples/plugins/`
- **Troubleshooting**: `TROUBLESHOOTING.md`

For support, contact the HELIOS development team.
