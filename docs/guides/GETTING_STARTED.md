# Getting Started with HELIOS Platform

**Estimated time:** 5-10 minutes  
**Level:** Beginner  
**Prerequisites:** Windows 10+ or Windows Server 2016+

---

## 🎯 What You'll Learn

By the end of this guide, you will:

- ✅ Understand what HELIOS Platform is and its key features
- ✅ Install HELIOS Platform on your system
- ✅ Perform your first deployment
- ✅ Access the web dashboard
- ✅ Know where to find additional help

---

## 📦 Prerequisites

Before getting started, ensure you have:

- **Windows OS**: Windows 10 (version 1909+) or Windows Server 2016+
- **.NET Runtime**: .NET 6.0 or higher
- **Disk Space**: Minimum 500 MB
- **Administrative Access**: Required for installation
- **Internet Connection**: For downloading components

---

## 🚀 Step 1: Installation (2 minutes)

### Option A: Using NuGet Package (Recommended)

```powershell
# Install via NuGet
nuget install HELIOS.Platform -OutputDirectory C:\HELIOS

# Navigate to installation
cd C:\HELIOS\HELIOS.Platform*
```

### Option B: Download from Repository

```powershell
# Clone the repository
git clone https://github.com/helios-platform/helios-platform.git
cd helios-platform

# Install dependencies
.\setup.ps1
```

### Verify Installation

```powershell
# Check installation
helios --version
# Expected output: HELIOS Platform v1.0.0
```

---

## ⚙️ Step 2: Initial Configuration (3 minutes)

### Create Configuration File

```powershell
# Generate default configuration
helios config init

# This creates: ~/.helios/config.json
```

### View Configuration

```powershell
# View configuration
notepad "$env:USERPROFILE\.helios\config.json"
```

### Default Settings

```json
{
  "platform": {
    "name": "HELIOS Platform",
    "port": 8080,
    "environment": "development"
  },
  "logging": {
    "level": "info",
    "output": "console"
  }
}
```

---

## ▶️ Step 3: Start the Platform (2 minutes)

### Start HELIOS Service

```powershell
# Start the platform
helios start

# Expected output:
# ✓ HELIOS Platform started successfully
# ✓ Web dashboard: http://localhost:8080
# ✓ API endpoint: http://localhost:8080/api
```

### Access the Dashboard

Open your browser and navigate to:

```
http://localhost:8080
```

You should see the HELIOS Platform dashboard.

### Verify Service is Running

```powershell
# Check service status
helios status

# Expected output: RUNNING
```

---

## 🎮 Step 4: Your First Deployment

### Create a Simple Deployment

```powershell
# Deploy a basic component
helios deploy --component="SystemMonitor" --target="local"

# Expected output:
# ✓ Deployment started
# ✓ Component: SystemMonitor
# ✓ Status: Running
```

### Check Deployment Status

```powershell
# List active deployments
helios deployment list

# View detailed status
helios deployment status SystemMonitor
```

---

## 📊 Step 5: Monitor Your Deployment

### Via Web Dashboard

1. Open http://localhost:8080
2. Click on "Deployments" tab
3. View real-time metrics and logs

### Via Command Line

```powershell
# View live logs
helios logs SystemMonitor --follow

# View metrics
helios metrics SystemMonitor

# View health status
helios health
```

---

## 🛠️ Common First Steps

### Enable Additional Features

```powershell
# Enable cloud integration
helios config set cloud.enabled true

# Enable monitoring
helios config set monitoring.enabled true

# Restart to apply changes
helios restart
```

### Create Your First Plugin

See [Plugin Development Guide](../guides/PLUGIN_DEVELOPMENT.md) for details.

### Connect to Cloud Services

See [Cloud Integration Guide](../architecture/INTEGRATION.md) for details.

---

## ✅ Verification Checklist

Before proceeding, verify:

- [ ] HELIOS Platform installed successfully
- [ ] `helios --version` shows version 1.0.0+
- [ ] Configuration file exists at ~/.helios/config.json
- [ ] HELIOS service is running (`helios status` shows RUNNING)
- [ ] Web dashboard is accessible at http://localhost:8080
- [ ] First deployment completed successfully

---

## 🎓 Next Steps

### Learn More

- **Configuration**: [Configuration Guide](../user-guides/CONFIGURATION.md)
- **Deployments**: [Deployment Guide](../user-guides/DEPLOYMENT.md)
- **Plugins**: [Plugin Development](PLUGIN_DEVELOPMENT.md)
- **Architecture**: [System Architecture](../architecture/README.md)

### Explore Examples

```powershell
# Run example deployments
cd examples/quickstart
.\run-example.ps1
```

See [Examples](../../examples/README.md) for more.

### Get Help

- 📖 [User Guides](../user-guides/README.md)
- ❓ [FAQ](../faq/README.md)
- 🐛 [Troubleshooting](../troubleshooting/README.md)
- 💻 [API Reference](../api/README.md)

---

## ⚠️ Troubleshooting

### Issue: Cannot start HELIOS service

```powershell
# Check if port is in use
netstat -ano | findstr :8080

# Try alternative port
helios config set platform.port 8081
helios start
```

### Issue: Dashboard not loading

```powershell
# Check service logs
helios logs --service=platform

# Restart service
helios restart
```

### Issue: Deployment failed

```powershell
# View detailed error
helios deployment status SystemMonitor --verbose

# Check logs
helios logs SystemMonitor --error-only
```

**For more issues**, see [Troubleshooting Guide](../troubleshooting/README.md)

---

## 🔗 Related Documentation

- [Installation Guide](../user-guides/INSTALLATION.md) - Detailed installation steps
- [Quick Start Tutorial](QUICK_START.md) - More advanced tutorial
- [Configuration Guide](../user-guides/CONFIGURATION.md) - Configuration options
- [FAQ](../faq/README.md) - Common questions

---

**Congratulations!** 🎉 You've successfully set up HELIOS Platform.

**Next:** Explore the [User Guides](../user-guides/README.md) or continue learning with the [Architecture Guide](../architecture/README.md).

---

**Questions?** Check the [FAQ](../faq/README.md) or [Troubleshooting Guide](../troubleshooting/README.md)  
**Last Updated:** 2026-04-16 | [Back to Documentation](../README.md)
