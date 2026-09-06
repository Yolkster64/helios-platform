# HELIOS Platform - Plugins

Complete information about the plugin system, development, and ecosystem.

## Claude Code operator plugin

The implemented, validated plugin in this repository is
[`plugins/helios-operator`](helios-operator/README.md). It packages the `operate-helios`
skill and the `fabric-operator` agent for Claude Code — deliberately no MCP server: the
HELIOS MCP tools come from the repo-level `.mcp.json` (`helios` server), which every
HELIOS checkout already registers, so the tools are available only when Claude Code runs
inside a HELIOS checkout. Its catalog is `.claude-plugin/marketplace.json`; its design
and safety boundary are documented in
`docs/architecture/CLAUDE_CODE_OPERATOR_PLUGIN.md`.

The material below describes the legacy in-process plugin concept and is not evidence that
those runtime classes, commands, or registry endpoints currently exist.

---

## 🔌 Plugin Overview

HELIOS Platform provides a comprehensive plugin system that allows you to extend functionality without modifying core code.

### What are Plugins?

Plugins are modular components that:

- ✅ Extend HELIOS functionality
- ✅ Integrate with external systems
- ✅ Add custom features
- ✅ Hook into deployment lifecycle
- ✅ Provide custom monitoring

### Plugin Types

- **Deployment Plugins**: Execute during deployments
- **Monitoring Plugins**: Collect metrics and health data
- **Integration Plugins**: Connect external systems
- **Custom Plugins**: Your own functionality

---

## 📚 Plugin Documentation

### Getting Started

- **[Plugin Development Guide](../guides/PLUGIN_DEVELOPMENT.md)** - Build your first plugin
- **[Plugin API Reference](../api/PLUGIN_API.md)** - Complete API documentation

### Advanced Topics

- **[Plugin Architecture](./ARCHITECTURE.md)** - Plugin system internals
- **[Plugin Lifecycle](./LIFECYCLE.md)** - Plugin initialization and shutdown
- **[Plugin Configuration](./CONFIGURATION.md)** - Plugin settings and options

### Plugin Examples

- **[Hello World Plugin](./examples/HelloWorld)** - Minimal example
- **[Monitoring Plugin](./examples/Monitoring)** - Collect metrics
- **[Integration Plugin](./examples/Integration)** - Integrate external API

---

## 🎯 Plugin Development Quick Start

### 1. Create Plugin Class

```csharp
using HELIOS.Platform.Plugins;

[PluginMetadata(
    Name = "My Plugin",
    Version = "1.0.0",
    Author = "Your Name"
)]
public class MyPlugin : IPlugin
{
    public void Initialize(IPluginContext context)
    {
        // Initialize plugin
    }
    
    public void Execute(IExecutionContext context)
    {
        // Execute plugin logic
    }
    
    public void Dispose()
    {
        // Cleanup
    }
}
```

### 2. Build Plugin

```powershell
dotnet build -c Release
```

### 3. Package Plugin

```powershell
# Copy DLL to plugins folder
Copy-Item bin/Release/net6.0/MyPlugin.dll plugins/
```

### 4. Load Plugin

```powershell
# Restart HELIOS to load plugin
helios restart

# Or reload plugins dynamically
helios plugin reload
```

### 5. Verify Plugin

```powershell
# List loaded plugins
helios plugin list

# Check plugin status
helios plugin status MyPlugin
```

---

## 📦 Available Plugins

### Official Plugins

| Plugin | Purpose | Status |
|--------|---------|--------|
| SystemMonitor | System monitoring | ✅ Available |
| CloudSync | Cloud integration | ✅ Available |
| LogAggregator | Log aggregation | ✅ Available |
| MetricsExporter | Metrics export | ✅ Available |

### Community Plugins

- Browse community plugins at [Plugin Registry](https://plugins.helios-platform.com)
- Submit your plugin to the registry

---

## 🔗 Plugin Folder Structure

```
plugins/
├── README.md (this file)
├── templates/
│   ├── BasicPlugin.csproj
│   ├── DeploymentPlugin.csproj
│   └── IntegrationPlugin.csproj
├── examples/
│   ├── HelloWorld/
│   ├── Monitoring/
│   └── Integration/
└── [Your Plugins]/
    ├── bin/
    ├── obj/
    └── MyPlugin.dll
```

---

## 🚀 Plugin Lifecycle

1. **Discovery**: HELIOS discovers plugins in the plugins folder
2. **Loading**: Plugins are loaded into memory
3. **Initialization**: `Initialize()` is called
4. **Execution**: `Execute()` is called when needed
5. **Disposal**: `Dispose()` is called on shutdown

---

## 🔗 Related Documentation

- **[Plugin Development Guide](../guides/PLUGIN_DEVELOPMENT.md)** - Build plugins
- **[Plugin API Reference](../api/PLUGIN_API.md)** - API documentation
- **[Architecture](../architecture/README.md)** - System architecture
- **[Getting Started](../guides/GETTING_STARTED.md)** - Platform overview

---

**Last Updated:** 2026-04-16 | [Back to Main Documentation](../README.md)
