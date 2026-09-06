# HELIOS Platform - Examples & Tutorials

Working code examples and tutorials to help you get started with HELIOS Platform.

---

## 🎯 Learning Resources

### Quick Start Examples

- **[Quick Start Guide](./quickstart/README.md)** - Get running in 5 minutes
- **[Basic Deployment](./quickstart/basic-deployment)** - Deploy your first app

### Advanced Examples

- **[Advanced Deployments](./advanced/README.md)** - Complex scenarios
- **[Cloud Integration](./advanced/cloud-integration)** - Multi-cloud setups
- **[Custom Plugins](./advanced/plugins)** - Develop plugins

---

## 📚 Example Categories

### Quick Start (5-15 minutes)

| Example | Description | Files |
|---------|-------------|-------|
| **Basic App** | Deploy a simple application | [View](./quickstart/basic-deployment) |
| **Configuration** | Configure HELIOS settings | [View](./quickstart/configuration) |
| **Monitoring** | Set up monitoring | [View](./quickstart/monitoring) |
| **Dashboard** | Explore the dashboard | [View](./quickstart/dashboard) |

### Intermediate (30-60 minutes)

| Example | Description | Files |
|---------|-------------|-------|
| **Multi-Component** | Deploy multiple components | [View](./advanced/multi-component) |
| **Cloud Integration** | Set up cloud providers | [View](./advanced/cloud-integration) |
| **Custom Plugin** | Build a custom plugin | [View](./advanced/plugins) |
| **API Integration** | Use the REST API | [View](./advanced/api-integration) |

### Advanced (1+ hours)

| Example | Description | Files |
|---------|-------------|-------|
| **Distributed System** | Set up distributed deployment | [View](./advanced/distributed) |
| **High Availability** | Configure HA setup | [View](./advanced/high-availability) |
| **Custom Monitoring** | Build custom monitoring plugin | [View](./advanced/monitoring-plugin) |
| **Complete Platform** | Full platform setup | [View](./advanced/complete-setup) |

---

## 🚀 Quick Start Path

### 1. Basic Deployment (5 min)

```powershell
cd examples/quickstart/basic-deployment
./run.ps1
```

### 2. Explore Configuration (5 min)

```powershell
cd examples/quickstart/configuration
./run.ps1
```

### 3. Set up Monitoring (5 min)

```powershell
cd examples/quickstart/monitoring
./run.ps1
```

### 4. Advanced Deployment (15 min)

```powershell
cd examples/advanced/multi-component
./run.ps1
```

---

## 💡 Example Code

### Example 1: Basic Deployment

```powershell
# Deploy a component
helios deploy \
  --component "WebServer" \
  --target "production" \
  --config @{
    port = 8080
    replicas = 2
  }
```

See [Basic Deployment](./quickstart/basic-deployment) for complete example.

### Example 2: Using the API

```bash
# Get authentication token
TOKEN=$(curl -X POST http://localhost:8080/api/auth/token \
  -d '{"username":"admin","password":"password"}' \
  | jq -r '.access_token')

# List deployments
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/deployments
```

See [API Integration](./advanced/api-integration) for complete example.

### Example 3: Custom Plugin

```csharp
using HELIOS.Platform.Plugins;

public class MyMonitoringPlugin : IPlugin
{
    public string Name => "My Monitoring";
    
    public void Execute(IExecutionContext context)
    {
        var metrics = context.GetMetrics();
        // Process metrics
    }
}
```

See [Custom Plugin](./advanced/plugins) for complete example.

---

## 📋 Example Structure

```
examples/
├── README.md (this file)
├── quickstart/
│   ├── README.md
│   ├── basic-deployment/
│   │   ├── run.ps1
│   │   ├── README.md
│   │   └── ...
│   ├── configuration/
│   ├── monitoring/
│   └── dashboard/
└── advanced/
    ├── README.md
    ├── multi-component/
    ├── cloud-integration/
    ├── plugins/
    ├── api-integration/
    ├── distributed/
    ├── high-availability/
    ├── monitoring-plugin/
    └── complete-setup/
```

---

## 🎓 Learning Paths

### Path 1: New User (30 minutes)

1. [Getting Started](../guides/GETTING_STARTED.md)
2. [Basic Deployment](./quickstart/basic-deployment)
3. [Configuration](./quickstart/configuration)
4. [Monitoring](./quickstart/monitoring)

### Path 2: Developer (1 hour)

1. [API Integration](./advanced/api-integration)
2. [Custom Plugin](./advanced/plugins)
3. [Multi-Component](./advanced/multi-component)

### Path 3: DevOps Engineer (2 hours)

1. [Cloud Integration](./advanced/cloud-integration)
2. [High Availability](./advanced/high-availability)
3. [Distributed Setup](./advanced/distributed)

### Path 4: Architect (3+ hours)

1. [Architecture](../architecture/README.md)
2. [Distributed System](./advanced/distributed)
3. [Complete Setup](./advanced/complete-setup)
4. [Advanced Topics](../architecture/INTEGRATION.md)

---

## ▶️ Running Examples

### Prerequisites

```powershell
# Verify HELIOS is installed
helios --version

# Verify HELIOS is running
helios status
```

### Run an Example

```powershell
# Navigate to example
cd examples/quickstart/basic-deployment

# Read instructions
Get-Content README.md

# Run example
./run.ps1
```

### View Example Results

```powershell
# Check deployment status
helios deployment list

# View logs
helios logs <deployment-name>

# View metrics
helios metrics
```

---

## 🔧 Customizing Examples

Each example can be customized:

1. **Edit configuration** - Modify config.json
2. **Edit parameters** - Change run.ps1 parameters
3. **Edit component** - Modify component files
4. **Run your version** - Deploy your changes

See each example's README for customization options.

---

## 🤝 Contributing Examples

Have a great example? Contribute it:

1. Create a new example directory
2. Add README with instructions
3. Add run.ps1 script
4. Test thoroughly
5. Submit pull request

See [Contributing Guide](../guides/CONTRIBUTING.md) for details.

---

## 📚 Related Documentation

- **[Getting Started](../guides/GETTING_STARTED.md)** - Platform overview
- **[User Guides](../user-guides/README.md)** - How-to guides
- **[API Reference](../api/README.md)** - API documentation
- **[Troubleshooting](../troubleshooting/README.md)** - Problem solving

---

## 💬 Example Discussions

Have questions about examples?

1. **Check README** - Each example has a README
2. **Check FAQ** - See [FAQ](../faq/README.md)
3. **Check Troubleshooting** - See [Troubleshooting](../troubleshooting/README.md)

---

**Last Updated:** 2026-04-16 | [Back to Main Documentation](../README.md)
