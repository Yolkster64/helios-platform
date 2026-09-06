# HELIOS Plugin System - Complete Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Quick Start](#quick-start)
4. [Creating Plugins](#creating-plugins)
5. [Plugin Lifecycle](#plugin-lifecycle)
6. [Configuration](#configuration)
7. [Versioning & Dependencies](#versioning--dependencies)
8. [Security](#security)
9. [Testing](#testing)
10. [Marketplace](#marketplace)
11. [API Reference](#api-reference)
12. [Best Practices](#best-practices)

## Overview

The HELIOS Plugin System is a comprehensive, production-ready framework for building, discovering, loading, and managing plugins. It provides:

- **Extensibility**: Build plugins that extend HELIOS platform capabilities
- **Lifecycle Management**: Complete plugin lifecycle from load to unload
- **Dependency Resolution**: Automatic semver-based dependency resolution
- **Security**: Sandboxed plugin execution with configurable security policies
- **Discovery**: Plugin discovery and loading mechanisms
- **Testing**: Built-in testing framework for plugin development
- **Marketplace**: Plugin marketplace for distribution and discovery
- **Versioning**: Full semantic versioning support
- **Configuration**: Flexible configuration management per plugin

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                    PluginManager                        │
│                 (Central Orchestrator)                  │
├─────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐ │
│ │ PluginLoader │ │ PluginConfig │ │ PluginSecurity   │ │
│ │            │ │   Manager    │ │    Sandbox       │ │
│ └──────────────┘ └──────────────┘ └──────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ ┌──────────────────────────────────────────────────────┐ │
│ │          PluginContext (IPluginContext)              │ │
│ │  (Provides access to services and configuration)    │ │
│ └──────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐ │
│ │DependencyRes.│ │Marketplace   │ │  TestFramework   │ │
│ └──────────────┘ └──────────────┘ └──────────────────┘ │
└─────────────────────────────────────────────────────────┘
           │
           ├─► IPlugin (Plugin Interface)
           │
           └─► PluginBase (Base Implementation)
```

### Key Classes

- **PluginManager**: Central orchestrator for all plugin operations
- **PluginLoader**: Discovers and loads plugins from disk
- **IPlugin**: Interface all plugins must implement
- **PluginBase**: Base class for simplified plugin development
- **IPluginContext**: Provides plugins access to platform services
- **DependencyResolver**: Resolves plugin dependencies using semver
- **PluginMarketplace**: Manages plugin discovery and distribution
- **PluginTestFramework**: Framework for testing plugins

## Quick Start

### 1. Initialize the Plugin System

```csharp
var pluginManager = new PluginManager(
    pluginDirectoryPath: "C:\\Plugins",
    configDirectoryPath: "C:\\PluginConfigs"
);

// Discover and load all plugins
var loadResult = await pluginManager.DiscoverAndLoadAllPluginsAsync();
if (!loadResult.IsSuccessful)
{
    Console.WriteLine("Failed plugins:");
    foreach (var failure in loadResult.FailedLoads)
    {
        Console.WriteLine($"  {failure.Key}: {failure.Value}");
    }
}

// Start all loaded plugins
await pluginManager.StartAllPluginsAsync();
```

### 2. Basic Plugin Example

```csharp
public class MyPlugin : PluginBase
{
    public override string Id => "com.company.myplugin";
    public override string Name => "My Plugin";
    public override string Version => "1.0.0";
    public override string Author => "Company";
    public override string Description => "My custom plugin";

    public override async Task InitializeAsync(IPluginContext context)
    {
        await base.InitializeAsync(context);
        LogInfo("Plugin initialized");
    }

    public override async Task StartAsync()
    {
        await base.StartAsync();
        LogInfo("Plugin started");
    }

    public override async Task<PluginCommandResult> ExecuteCommandAsync(
        string commandName, 
        Dictionary<string, object> parameters)
    {
        if (commandName == "hello")
        {
            return PluginCommandResult.Ok("Hello from my plugin!");
        }
        
        return await base.ExecuteCommandAsync(commandName, parameters);
    }
}
```

### 3. Execute Plugin Commands

```csharp
var result = await pluginManager.ExecuteCommandAsync(
    pluginId: "com.company.myplugin",
    commandName: "hello",
    parameters: new Dictionary<string, object>()
);

if (result.Success)
{
    Console.WriteLine($"Result: {result.Data}");
}
else
{
    Console.WriteLine($"Error: {result.ErrorMessage}");
}
```

## Creating Plugins

### Plugin Structure

A plugin requires:

1. **Plugin Class**: Implement `IPlugin` or extend `PluginBase`
2. **Manifest File** (`plugin.json`): Define plugin metadata and dependencies
3. **Assembly**: Compiled DLL with plugin class

### Plugin Manifest (plugin.json)

```json
{
  "id": "com.example.myplugin",
  "version": "1.0.0",
  "name": "My Example Plugin",
  "description": "A sample plugin demonstrating all features",
  "author": "Example Corp",
  "license": "MIT",
  "homepage": "https://example.com",
  "repository": "https://github.com/example/myplugin",
  "main": "MyPlugin.dll",
  "entryPoint": "Example.Plugins.MyPlugin",
  "dependencies": [
    {
      "id": "com.helios.plugins.log",
      "version": "^1.0.0",
      "optional": false
    }
  ],
  "capabilities": [
    "data-processing",
    "caching",
    "notifications"
  ],
  "priority": 10,
  "autoStart": true,
  "metadata": {
    "category": "data",
    "tags": ["processing", "caching"]
  }
}
```

### Complete Plugin Implementation

```csharp
using HELIOS.Platform.Core.Plugins.Abstractions;

public class AdvancedPlugin : PluginBase
{
    private IPluginConfiguration _config;
    private bool _running = false;

    public override string Id => "com.example.advanced";
    public override string Name => "Advanced Plugin";
    public override string Version => "2.0.0";
    public override string Author => "Example Corp";
    public override string Description => "Advanced plugin example";

    public override IReadOnlyList<PluginDependency> Dependencies => 
        new List<PluginDependency>
        {
            new PluginDependency("com.helios.plugins.log", "^1.0.0")
        };

    public override IReadOnlyList<string> GetCapabilities()
    {
        return new[] { "advanced-processing", "data-export" };
    }

    public override async Task InitializeAsync(IPluginContext context)
    {
        await base.InitializeAsync(context);
        _config = context.Configuration;
        
        // Load configuration defaults
        var batchSize = _config.Get("batch_size", 100);
        var timeout = _config.Get("timeout_ms", 5000);
        
        LogInfo($"Configured with batch_size={batchSize}, timeout={timeout}ms");
    }

    public override async Task StartAsync()
    {
        await base.StartAsync();
        _running = true;
        
        // Subscribe to events
        _context.SubscribeToEvent("data.received", OnDataReceived);
        
        // Start background processing
        _ = BackgroundProcessingLoop();
    }

    public override async Task StopAsync()
    {
        await base.StopAsync();
        _running = false;
    }

    public override async Task<PluginCommandResult> ExecuteCommandAsync(
        string commandName,
        Dictionary<string, object> parameters)
    {
        return commandName switch
        {
            "process" => ExecuteProcess(parameters),
            "export" => ExecuteExport(parameters),
            "status" => ExecuteStatus(),
            _ => await base.ExecuteCommandAsync(commandName, parameters)
        };
    }

    private PluginCommandResult ExecuteProcess(Dictionary<string, object> parameters)
    {
        if (!parameters.TryGetValue("data", out var data))
            return PluginCommandResult.Error("'data' parameter required");
        
        try
        {
            // Process the data
            var result = ProcessData(data.ToString());
            return PluginCommandResult.Ok(result);
        }
        catch (Exception ex)
        {
            return PluginCommandResult.Error(ex.Message);
        }
    }

    private PluginCommandResult ExecuteExport(Dictionary<string, object> parameters)
    {
        if (!parameters.TryGetValue("format", out var format))
            return PluginCommandResult.Error("'format' parameter required");
        
        var exported = ExportData(format.ToString());
        return PluginCommandResult.Ok(exported);
    }

    private PluginCommandResult ExecuteStatus()
    {
        return PluginCommandResult.Ok(new
        {
            running = _running,
            state = State.ToString()
        });
    }

    private async Task OnDataReceived(object eventData)
    {
        LogInfo($"Received data event: {eventData}");
        await Task.CompletedTask;
    }

    private async Task BackgroundProcessingLoop()
    {
        while (_running)
        {
            try
            {
                await Task.Delay(1000);
                // Perform background work
            }
            catch (Exception ex)
            {
                LogError("Background processing error", ex);
            }
        }
    }

    private object ProcessData(string data) => $"Processed: {data}";
    private object ExportData(string format) => $"Exported as {format}";
}
```

## Plugin Lifecycle

### States

```
Created → Initialized → Running → Stopped → Unloaded
                          ↓
                        Failed
```

### Lifecycle Events

1. **Creation**: Plugin instance created
2. **Initialization**: `InitializeAsync()` called - configure plugin
3. **Starting**: `StartAsync()` called - start operations
4. **Running**: Plugin actively processing
5. **Stopping**: `StopAsync()` called - graceful shutdown
6. **Stopped**: Plugin halted
7. **Unloading**: `Dispose()` called - cleanup resources

### Handling State Changes

```csharp
pluginManager.PluginStateChanged += (sender, e) =>
{
    Console.WriteLine($"Plugin {e.PluginId}: {e.OldState} → {e.NewState}");
    Console.WriteLine($"Reason: {e.Reason}");
    Console.WriteLine($"Time: {e.Timestamp}");
};
```

## Configuration

### Loading Configuration

```csharp
// In InitializeAsync
public override async Task InitializeAsync(IPluginContext context)
{
    await base.InitializeAsync(context);
    
    // Get configuration values
    var maxConnections = context.Configuration.Get("max_connections", 100);
    var timeout = context.Configuration.Get("timeout_ms", 30000);
    var enabled = context.Configuration.Get("enabled", true);
    
    LogInfo($"Max connections: {maxConnections}");
    LogInfo($"Timeout: {timeout}ms");
    LogInfo($"Enabled: {enabled}");
}
```

### Configuration File (plugin.json settings)

```json
{
  "id": "com.example.myplugin",
  "version": "1.0.0",
  ...
  "metadata": {
    "max_connections": 100,
    "timeout_ms": 30000,
    "enabled": true,
    "database": {
      "host": "localhost",
      "port": 5432
    }
  }
}
```

### Saving Configuration

```csharp
// Modify and save configuration
_context.Configuration.Set("last_run", DateTime.UtcNow);
await _context.Configuration.ReloadAsync();
```

### Configuration Validation

```csharp
var validator = new ConfigurationSchemaValidator();

var schema = new ConfigurationSchema
{
    PluginId = "com.example.plugin",
    Properties = new Dictionary<string, ConfigurationProperty>
    {
        ["max_threads"] = new ConfigurationProperty
        {
            Type = typeof(int),
            Required = true,
            MinValue = 1,
            MaxValue = 100
        },
        ["mode"] = new ConfigurationProperty
        {
            Type = typeof(string),
            AllowedValues = new List<object> { "fast", "balanced", "thorough" }
        }
    }
};

validator.RegisterSchema("com.example.plugin", schema);

var result = validator.Validate("com.example.plugin", configuration);
if (!result.IsValid)
{
    foreach (var error in result.Errors)
        Console.WriteLine($"Validation error: {error}");
}
```

## Versioning & Dependencies

### Semantic Versioning

Plugins use semantic versioning: `MAJOR.MINOR.PATCH[-PRERELEASE][+METADATA]`

```csharp
var version = SemanticVersion.Parse("1.2.3-beta+build123");
Console.WriteLine($"Major: {version.Major}"); // 1
Console.WriteLine($"Minor: {version.Minor}"); // 2
Console.WriteLine($"Patch: {version.Patch}"); // 3
```

### Version Constraints

Supported constraint formats:

```
*              // Any version
1.2.3          // Exact version
^1.2.3         // Compatible with version (allows minor/patch changes)
~1.2.3         // Approximately (allows patch changes only)
>=1.0.0        // Greater than or equal
>1.0.0         // Greater than
<=2.0.0        // Less than or equal
<2.0.0         // Less than
1.0.0 - 2.0.0  // Range
```

### Dependency Resolution

```csharp
var resolver = new DependencyResolver();

// Register available versions
resolver.RegisterVersions("com.helios.plugins.log", 
    "1.0.0", "1.1.0", "1.2.0", "2.0.0");

resolver.RegisterVersions("com.helios.plugins.metrics",
    "1.0.0", "1.0.1");

// Create manifests with dependencies
var manifest = new PluginManifest
{
    Id = "com.example.plugin",
    Version = "1.0.0",
    Dependencies = new List<PluginDependencyManifest>
    {
        new PluginDependencyManifest 
        { 
            PluginId = "com.helios.plugins.log", 
            VersionConstraint = "^1.0.0" 
        }
    }
};

resolver.RegisterManifest("com.example.plugin", "1.0.0", manifest);

// Resolve dependencies
var resolution = resolver.ResolveDependencies("com.example.plugin", "1.0.0");

if (resolution.IsSuccessful)
{
    foreach (var resolved in resolution.Resolved)
    {
        Console.WriteLine($"{resolved.Key}@{resolved.Value}");
    }
}
else
{
    foreach (var error in resolution.Errors)
    {
        Console.WriteLine($"Resolution error: {error}");
    }
}
```

## Security

### Security Levels

```csharp
public enum SecurityLevel
{
    Minimal,      // Execution only
    Low,          // Read-only file access
    Medium,       // File I/O + environment (default)
    High,         // Most operations except unmanaged code
    Full          // Full trust (use with caution)
}
```

### Setting Security Policy

```csharp
// Use predefined policy
var policy = PluginSecurityPolicy.CreateDefault("com.example.plugin");
pluginManager.SetSecurityPolicy("com.example.plugin", policy);

// Or create custom policy
var customPolicy = new PluginSecurityPolicy
{
    PluginId = "com.untrusted.plugin",
    DefaultLevel = SecurityLevel.Low,
    AllowNetworkAccess = false,
    AllowFileSystem = false,
    AllowReflection = false,
    AllowUnmanagedCode = false,
    MaxMemoryMB = 256,
    MaxExecutionTimeMs = 10000
};

pluginManager.SetSecurityPolicy("com.untrusted.plugin", customPolicy);
```

### Monitoring Plugin Execution

```csharp
var metrics = pluginManager.GetExecutionMetrics("com.example.plugin");

Console.WriteLine($"Total executions: {metrics.TotalExecutions}");
Console.WriteLine($"Average duration: {metrics.AverageDurationMs}ms");
Console.WriteLine($"Peak memory: {metrics.PeakMemoryMB}MB");
Console.WriteLine($"Timeout violations: {metrics.TimeoutViolations}");
Console.WriteLine($"Memory violations: {metrics.MemoryViolations}");
```

## Testing

### Creating Test Cases

```csharp
var framework = new PluginTestFramework();

framework.RegisterTestCase(new PluginTestCase
{
    Name = "Test plugin initialization",
    Description = "Verify plugin initializes correctly",
    Setup = async () => 
    {
        // Setup test environment
        await Task.CompletedTask;
    },
    Execute = async () => 
    {
        // Execute plugin operation
        await Task.CompletedTask;
    },
    Assert = () => 
    {
        // Assert expected results
        Assert.IsTrue(true, "Plugin initialized");
    },
    Cleanup = async () => 
    {
        // Cleanup resources
        await Task.CompletedTask;
    }
});

var result = await framework.RunAllTestsAsync();
Console.WriteLine(result.ToString());
```

### Plugin Integration Testing

```csharp
var testHelper = new PluginIntegrationTestHelper();

var plugin = await testHelper.CreateTestPluginAsync<MyPlugin>();

// Test plugin functionality
await plugin.InitializeAsync(new MockPluginContext());
await plugin.StartAsync();

var cmdResult = await plugin.ExecuteCommandAsync("hello", new Dictionary<string, object>());
Assert.IsTrue(cmdResult.Success, "Command execution failed");

await testHelper.CleanupAsync();
```

### Mock Objects

```csharp
// Create mock context
var context = new MockPluginContext
{
    Configuration = new PluginConfiguration(new Dictionary<string, object>
    {
        ["test_value"] = "hello"
    })
};

// Access mock logger
var logger = (MockPluginLogger)context.Logger;
foreach (var message in logger.LogMessages)
{
    Console.WriteLine(message);
}
```

## Marketplace

### Submitting a Plugin

```csharp
var marketplace = new PluginMarketplace();

var submission = new PluginSubmission
{
    PluginId = "com.example.plugin",
    Name = "Example Plugin",
    Description = "A useful plugin for HELIOS",
    Version = "1.0.0",
    Author = "Example Corp",
    License = "MIT",
    Homepage = "https://example.com",
    RepositoryUrl = "https://github.com/example/plugin",
    IconUrl = "https://example.com/icon.png",
    DownloadUrl = "https://example.com/download/plugin-1.0.0.zip",
    Categories = new List<string> { "data-processing", "utilities" },
    Tags = new List<string> { "fast", "reliable" }
};

var result = await marketplace.SubmitPluginAsync(submission);
if (result.IsSuccess)
{
    Console.WriteLine($"Plugin submitted: {result.Data.PluginId}");
}
```

### Searching Plugins

```csharp
// Search by query
var results = await marketplace.SearchAsync("logging", category: "utilities", limit: 10);

foreach (var plugin in results)
{
    Console.WriteLine($"{plugin.Name} ({plugin.Version}) by {plugin.Author}");
    Console.WriteLine($"  Rating: {plugin.Rating}/5.0");
    Console.WriteLine($"  Downloads: {plugin.Downloads}");
}
```

### Discovering Plugins

```csharp
// Get trending plugins
var trending = await marketplace.GetTrendingAsync(limit: 5);

// Get top-rated plugins
var topRated = await marketplace.GetTopRatedAsync(limit: 5);

// Get categories
var categories = await marketplace.GetCategoriesAsync();
```

### Submitting Reviews

```csharp
var review = new PluginReview
{
    PluginId = "com.example.plugin",
    Author = "user@example.com",
    Rating = 5,
    Title = "Excellent plugin!",
    Comment = "Works perfectly and has great documentation."
};

var reviewResult = await marketplace.SubmitReviewAsync(review);

// Get reviews
var reviews = await marketplace.GetReviewsAsync("com.example.plugin");
foreach (var rev in reviews)
{
    Console.WriteLine($"{rev.Title} - {rev.Author} ({rev.Rating}/5)");
    Console.WriteLine($"  {rev.Comment}");
}
```

## API Reference

### IPlugin Interface

```csharp
public interface IPlugin : IDisposable
{
    string Id { get; }
    string Name { get; }
    string Version { get; }
    string Author { get; }
    string Description { get; }
    PluginState State { get; }
    IReadOnlyList<PluginDependency> Dependencies { get; }
    
    event EventHandler<PluginStateChangedEventArgs> StateChanged;
    
    Task InitializeAsync(IPluginContext context);
    Task StartAsync();
    Task StopAsync();
    Task ReloadConfigAsync();
    IPluginMetadata GetMetadata();
    Task<PluginCommandResult> ExecuteCommandAsync(string commandName, Dictionary<string, object> parameters);
    IReadOnlyList<string> GetCapabilities();
    Task<PluginHealth> GetHealthAsync();
}
```

### IPluginContext Interface

```csharp
public interface IPluginContext
{
    IPluginConfiguration Configuration { get; }
    IServiceProvider ServiceProvider { get; }
    IPluginLogger Logger { get; }
    
    IPlugin GetPlugin(string pluginId);
    void RegisterService(string serviceName, object serviceInstance);
    object GetService(string serviceName);
    Task PublishEventAsync(string eventName, object eventData);
    void SubscribeToEvent(string eventName, Func<object, Task> handler);
}
```

### PluginManager Methods

```csharp
// Discovery and Loading
Task<LoadResult> DiscoverAndLoadAllPluginsAsync();
Task<LoadedPlugin> LoadPluginAsync(Type pluginType, string pluginId, PluginManifestData manifest = null);

// Lifecycle Management
Task StartPluginAsync(string pluginId);
Task StopPluginAsync(string pluginId);
Task UnloadPluginAsync(string pluginId);
Task StartAllPluginsAsync();
Task StopAllPluginsAsync();

// Plugin Access
IPlugin GetPlugin(string pluginId);
IReadOnlyList<IPlugin> GetAllPlugins();

// Health and Monitoring
Task<PluginHealth> GetPluginHealthAsync(string pluginId);
Task<Dictionary<string, PluginHealth>> GetAllPluginsHealthAsync();
ExecutionMetrics GetExecutionMetrics(string pluginId);

// Commands and Events
Task<PluginCommandResult> ExecuteCommandAsync(string pluginId, string commandName, Dictionary<string, object> parameters = null);
Task PublishEventAsync(string pluginId, string eventName, object eventData);
void SubscribeToEvent(string pluginId, string eventName, Func<object, Task> handler);

// Status
Task<PlatformStatus> GetStatusAsync();

// Security
void SetSecurityPolicy(string pluginId, PluginSecurityPolicy policy);

// Configuration
Task ReloadPluginConfigAsync(string pluginId);
```

## Best Practices

### 1. Error Handling

- Always implement try-catch in lifecycle methods
- Return meaningful error messages
- Log errors with context

```csharp
public override async Task StartAsync()
{
    try
    {
        await base.StartAsync();
        // Your code
    }
    catch (Exception ex)
    {
        LogError("Failed to start plugin", ex);
        throw;
    }
}
```

### 2. Resource Management

- Implement `Dispose()` properly
- Clean up connections and file handles
- Cancel background tasks on stop

```csharp
public override void Dispose()
{
    _running = false;
    _cancellationTokenSource?.Cancel();
    _connection?.Close();
    base.Dispose();
}
```

### 3. Configuration Handling

- Provide sensible defaults
- Validate configuration values
- Log configuration issues

```csharp
public override async Task InitializeAsync(IPluginContext context)
{
    await base.InitializeAsync(context);
    
    var timeout = context.Configuration.Get("timeout_ms", 5000);
    if (timeout < 100 || timeout > 300000)
    {
        LogWarning("Invalid timeout configured, using default");
        timeout = 5000;
    }
}
```

### 4. Performance Optimization

- Use async/await properly
- Implement caching where appropriate
- Monitor resource usage

```csharp
public override async Task<PluginHealth> GetHealthAsync()
{
    var health = await base.GetHealthAsync();
    health.Metrics["cache_hit_rate"] = _cacheHitRate;
    health.Metrics["memory_usage"] = GC.GetTotalMemory(false) / (1024 * 1024);
    return health;
}
```

### 5. Documentation

- Document all public methods
- Provide example usage
- Keep plugin.json updated

```csharp
/// <summary>
/// Process data asynchronously
/// </summary>
/// <param name="data">Data to process</param>
/// <returns>Processed result or error</returns>
public async Task<PluginCommandResult> ProcessAsync(string data)
{
    // Implementation
}
```

### 6. Testing

- Write comprehensive tests
- Test error paths
- Mock external dependencies

```csharp
[Test]
public async Task TestCommandExecution()
{
    var plugin = await testHelper.CreateTestPluginAsync<MyPlugin>();
    var result = await plugin.ExecuteCommandAsync("process", new Dictionary<string, object>());
    Assert.IsTrue(result.Success);
}
```

### 7. Security

- Request only necessary permissions
- Validate all inputs
- Handle sensitive data securely

```csharp
if (!parameters.TryGetValue("apiKey", out var key))
    return PluginCommandResult.Error("API key required");

// Never log sensitive data
LogInfo("API request initiated");
```

---

## Sample Plugins

See the `samples/plugins` directory for complete working examples:

- **LogPlugin**: Centralized logging
- **MetricsPlugin**: System monitoring
- **AlertPlugin**: Alert management

## Support

For issues or questions about the plugin system, contact the HELIOS team.

Last updated: 2024
