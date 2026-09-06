# HELIOS Plugin Development Template

Use this template to quickly create new plugins for the HELIOS platform.

## Project Structure

```
MyPlugin/
├── src/
│   └── MyPlugin.cs
├── tests/
│   └── MyPluginTests.cs
├── plugin.json
├── README.md
└── LICENSE
```

## Plugin Template

```csharp
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using HELIOS.Platform.Core.Plugins.Abstractions;

namespace MyCompany.Plugins
{
    /// <summary>
    /// [DESCRIBE YOUR PLUGIN HERE]
    /// 
    /// Features:
    /// - Feature 1
    /// - Feature 2
    /// - Feature 3
    /// 
    /// Configuration:
    /// See plugin.json for configuration options
    /// 
    /// Usage:
    /// // Example of using this plugin
    /// var result = await pluginManager.ExecuteCommandAsync("com.mycompany.myplugin", "command_name", params);
    /// </summary>
    public class MyPlugin : PluginBase
    {
        // ==================== Configuration ====================

        private const string PLUGIN_ID = "com.mycompany.myplugin";
        private const string PLUGIN_NAME = "My Plugin";
        private const string PLUGIN_VERSION = "1.0.0";
        private const string PLUGIN_AUTHOR = "My Company";
        private const string PLUGIN_DESCRIPTION = "Description of what my plugin does";

        // ==================== Properties ====================

        public override string Id => PLUGIN_ID;
        public override string Name => PLUGIN_NAME;
        public override string Version => PLUGIN_VERSION;
        public override string Author => PLUGIN_AUTHOR;
        public override string Description => PLUGIN_DESCRIPTION;

        // ==================== State ====================

        private bool _isRunning = false;
        private IPluginConfiguration _config;

        // ==================== Lifecycle ====================

        /// <summary>
        /// Called when plugin is first loaded
        /// </summary>
        public override async Task InitializeAsync(IPluginContext context)
        {
            await base.InitializeAsync(context);
            _config = context.Configuration;

            try
            {
                LogInfo($"Initializing {Name} v{Version}");

                // Load configuration
                var setting1 = _config.Get("setting1", "default_value");
                LogInfo($"Loaded configuration: setting1={setting1}");

                // Initialize resources
                // TODO: Initialize your plugin here

                LogInfo($"{Name} initialized successfully");
            }
            catch (Exception ex)
            {
                LogError($"Failed to initialize {Name}", ex);
                throw;
            }
        }

        /// <summary>
        /// Called when plugin should start operations
        /// </summary>
        public override async Task StartAsync()
        {
            await base.StartAsync();
            _isRunning = true;

            try
            {
                LogInfo($"Starting {Name}");

                // Subscribe to events
                _context.SubscribeToEvent("plugin.event.name", OnEventReceived);

                // Start background operations
                _ = Task.Run(BackgroundOperationLoop);

                LogInfo($"{Name} started successfully");
            }
            catch (Exception ex)
            {
                LogError($"Failed to start {Name}", ex);
                _isRunning = false;
                throw;
            }
        }

        /// <summary>
        /// Called when plugin should stop operations
        /// </summary>
        public override async Task StopAsync()
        {
            await base.StopAsync();
            _isRunning = false;

            try
            {
                LogInfo($"Stopping {Name}");

                // Stop background operations
                // Cancel any pending tasks
                // Clean up resources

                LogInfo($"{Name} stopped successfully");
            }
            catch (Exception ex)
            {
                LogError($"Error stopping {Name}", ex);
                throw;
            }
        }

        /// <summary>
        /// Called when plugin is unloaded
        /// </summary>
        public override void Dispose()
        {
            try
            {
                LogInfo($"Disposing {Name}");

                _isRunning = false;

                // Dispose resources
                // Close connections
                // Release file handles

                base.Dispose();
            }
            catch (Exception ex)
            {
                LogError($"Error disposing {Name}", ex);
            }
        }

        // ==================== Commands ====================

        /// <summary>
        /// Execute plugin commands
        /// </summary>
        public override async Task<PluginCommandResult> ExecuteCommandAsync(
            string commandName,
            Dictionary<string, object> parameters)
        {
            return commandName switch
            {
                "command1" => ExecuteCommand1(parameters),
                "command2" => await ExecuteCommand2(parameters),
                "status" => GetStatus(),
                _ => await base.ExecuteCommandAsync(commandName, parameters)
            };
        }

        private PluginCommandResult ExecuteCommand1(Dictionary<string, object> parameters)
        {
            try
            {
                // Validate parameters
                if (!parameters.TryGetValue("param1", out var param1))
                    return PluginCommandResult.Error("'param1' parameter is required");

                // Execute command
                var result = DoSomething(param1);

                // Return result
                return PluginCommandResult.Ok(result);
            }
            catch (Exception ex)
            {
                LogError("Error in command1", ex);
                return PluginCommandResult.Error($"Command failed: {ex.Message}");
            }
        }

        private async Task<PluginCommandResult> ExecuteCommand2(Dictionary<string, object> parameters)
        {
            try
            {
                // Async command execution
                var result = await DoSomethingAsync();
                return PluginCommandResult.Ok(result);
            }
            catch (Exception ex)
            {
                LogError("Error in command2", ex);
                return PluginCommandResult.Error($"Command failed: {ex.Message}");
            }
        }

        private PluginCommandResult GetStatus()
        {
            return PluginCommandResult.Ok(new
            {
                name = Name,
                version = Version,
                state = State.ToString(),
                running = _isRunning,
                uptime = DateTime.UtcNow
            });
        }

        // ==================== Capabilities ====================

        public override IReadOnlyList<string> GetCapabilities()
        {
            return new[]
            {
                "capability1",
                "capability2",
                "capability3"
            };
        }

        // ==================== Health ====================

        public override async Task<PluginHealth> GetHealthAsync()
        {
            var health = await base.GetHealthAsync();

            health.Metrics["running"] = _isRunning;
            health.Metrics["state"] = State.ToString();
            // TODO: Add more metrics

            return health;
        }

        // ==================== Events ====================

        private async Task OnEventReceived(object eventData)
        {
            try
            {
                LogInfo($"Event received: {eventData}");
                // Handle event
                await Task.CompletedTask;
            }
            catch (Exception ex)
            {
                LogError("Error handling event", ex);
            }
        }

        // ==================== Background Operations ====================

        private async Task BackgroundOperationLoop()
        {
            while (_isRunning)
            {
                try
                {
                    // Perform background work
                    LogDebug("Performing background operation");

                    // TODO: Implement your background logic

                    await Task.Delay(5000); // Wait 5 seconds before next iteration
                }
                catch (Exception ex)
                {
                    LogError("Error in background operation", ex);
                }
            }
        }

        // ==================== Implementation Methods ====================

        private object DoSomething(object param)
        {
            // TODO: Implement your logic
            LogInfo("Doing something...");
            return "Result";
        }

        private async Task<object> DoSomethingAsync()
        {
            // TODO: Implement your async logic
            LogInfo("Doing something async...");
            await Task.Delay(100);
            return "Result";
        }
    }
}
```

## Plugin Manifest Template (plugin.json)

```json
{
  "id": "com.mycompany.myplugin",
  "version": "1.0.0",
  "name": "My Plugin",
  "description": "Description of what my plugin does",
  "author": "My Company",
  "license": "MIT",
  "homepage": "https://example.com/plugins/myplugin",
  "repository": "https://github.com/mycompany/myplugin",
  "main": "MyPlugin.dll",
  "entryPoint": "MyCompany.Plugins.MyPlugin",
  "dependencies": [
    {
      "id": "com.helios.plugins.log",
      "version": "^1.0.0",
      "optional": false
    }
  ],
  "capabilities": [
    "capability1",
    "capability2"
  ],
  "priority": 10,
  "autoStart": true,
  "metadata": {
    "category": "data",
    "tags": ["tag1", "tag2"],
    "config_key": "config_value"
  }
}
```

## Test Template

```csharp
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using HELIOS.Platform.Core.Plugins.Testing;
using HELIOS.Platform.Core.Plugins.Abstractions;

namespace MyCompany.Plugins.Tests
{
    public class MyPluginTests
    {
        private PluginTestFramework _testFramework;
        private PluginIntegrationTestHelper _testHelper;

        public async Task RunAllTests()
        {
            _testFramework = new PluginTestFramework();
            _testHelper = new PluginIntegrationTestHelper();

            // Register test cases
            RegisterTestCases();

            // Run tests
            var result = await _testFramework.RunAllTestsAsync();

            // Print results
            PrintResults(result);

            // Cleanup
            await _testHelper.CleanupAsync();
        }

        private void RegisterTestCases()
        {
            _testFramework.RegisterTestCase(new PluginTestCase
            {
                Name = "Test Plugin Initialization",
                Description = "Verify plugin initializes correctly",
                Setup = async () =>
                {
                    await Task.CompletedTask;
                },
                Execute = async () =>
                {
                    // Execute test
                    await Task.CompletedTask;
                },
                Assert = () =>
                {
                    Assert.IsTrue(true, "Plugin initialized");
                },
                Cleanup = async () =>
                {
                    await Task.CompletedTask;
                }
            });

            _testFramework.RegisterTestCase(new PluginTestCase
            {
                Name = "Test Plugin Command",
                Description = "Verify plugin command execution",
                Setup = async () =>
                {
                    await Task.CompletedTask;
                },
                Execute = async () =>
                {
                    // Execute test
                    await Task.CompletedTask;
                },
                Assert = () =>
                {
                    Assert.IsTrue(true, "Command executed");
                },
                Cleanup = async () =>
                {
                    await Task.CompletedTask;
                }
            });
        }

        private void PrintResults(TestRunResult result)
        {
            Console.WriteLine($"\nTest Results:");
            Console.WriteLine($"Total: {result.TotalTests}");
            Console.WriteLine($"Passed: {result.PassedTests}");
            Console.WriteLine($"Failed: {result.FailedTests}");
            Console.WriteLine($"Errors: {result.ErrorTests}");
            Console.WriteLine($"Success Rate: {result.SuccessRate:F2}%");

            if (result.FailedTests > 0)
            {
                Console.WriteLine("\nFailed Tests:");
                foreach (var testResult in result.Results)
                {
                    if (!testResult.IsSuccess)
                    {
                        Console.WriteLine($"  ✗ {testResult.TestName}");
                        if (!string.IsNullOrEmpty(testResult.ErrorMessage))
                        {
                            Console.WriteLine($"    {testResult.ErrorMessage}");
                        }
                    }
                }
            }
        }
    }
}
```

## Configuration File Template

**plugin.json** (in config directory):

```json
{
  "enabled": true,
  "debug": false,
  "timeout_ms": 5000,
  "max_retries": 3,
  "batch_size": 100,
  "database": {
    "host": "localhost",
    "port": 5432,
    "name": "mydb"
  },
  "features": {
    "feature1": true,
    "feature2": false
  }
}
```

## README Template

```markdown
# My Plugin

Description of what this plugin does.

## Installation

1. Build the plugin
2. Copy `MyPlugin.dll` to plugins directory
3. Copy `plugin.json` to plugins directory
4. Restart HELIOS platform

## Configuration

Configure in `plugin-config/com.mycompany.myplugin.json`:

```json
{
  "setting1": "value1",
  "setting2": 12345
}
```

## Usage

```csharp
var result = await pluginManager.ExecuteCommandAsync(
    "com.mycompany.myplugin",
    "command_name",
    new Dictionary<string, object> { /* params */ }
);
```

## Commands

- `command1` - Does something
- `command2` - Does something else
- `status` - Get plugin status

## Dependencies

- `com.helios.plugins.log` (^1.0.0)

## License

MIT

## Author

My Company

```

## Building Your Plugin

### Step 1: Create Project

```bash
dotnet new classlib -n MyPlugin
cd MyPlugin
```

### Step 2: Add Plugin References

```bash
dotnet add reference ../path/to/HELIOS.Platform.Core.Plugins.csproj
```

### Step 3: Implement Plugin

Use the plugin template above.

### Step 4: Build

```bash
dotnet build --configuration Release
```

### Step 5: Deploy

1. Copy `bin/Release/net6.0/MyPlugin.dll` to plugins directory
2. Copy `plugin.json` to plugins directory

## Quick Checklist

- [ ] Plugin extends PluginBase or implements IPlugin
- [ ] Plugin has unique ID in format `com.company.name`
- [ ] Plugin implements required methods
- [ ] plugin.json is valid JSON
- [ ] Dependencies are correctly specified
- [ ] Configuration file is created
- [ ] Tests are written and passing
- [ ] Documentation is updated
- [ ] License file is included

## Support

For help creating plugins, refer to the main Plugin System Guide.
