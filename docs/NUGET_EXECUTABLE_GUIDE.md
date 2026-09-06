# HELIOS Platform - Complete NuGet & Executable Distribution Guide

## 📦 Quick Start - 3 Minutes to Deployment

### For NuGet Package Consumption (Easiest)

```bash
# Install into your project
dotnet add package HELIOS.Platform

# Or install via Package Manager
Install-Package HELIOS.Platform
```

### For Standalone Executable

```bash
# Download and extract HELIOS.Platform.exe
cd C:\your-installation-path

# Run with menu
HELIOS.Platform.exe

# Or run commands directly
HELIOS.Platform.exe validate
HELIOS.Platform.exe deploy professional
HELIOS.Platform.exe status
```

### For Windows Installation

```bash
# Run as Administrator
setup\Install.bat

# Or using PowerShell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\setup\Install.ps1
```

---

## 🏗️ Building from Source

### Prerequisites

- .NET 6.0 or later SDK
- Windows 10/11
- Administrator privileges (for installer creation)

### Build Complete Distribution

```powershell
# Navigate to project directory
cd C:\Users\ADMIN\helios-platform

# Build everything
.\build.ps1 -All

# Or build specific components
.\build.ps1 -Configuration Release -CreateExe -CreateInstaller -CreateDemo
```

### Build Options

```powershell
# Build only specific framework
.\build.ps1 -Framework net8.0

# Build without tests
.\build.ps1 -SkipTests

# Build without NuGet package
.\build.ps1 -SkipPack

# Create standalone executable only
.\build.ps1 -CreateExe

# Create installer only
.\build.ps1 -CreateInstaller

# Create demo apps only
.\build.ps1 -CreateDemo
```

---

## 📋 Distribution Package Contents

### 1. NuGet Package (`HELIOS.Platform.1.0.0.nupkg`)

**What's Inside:**

- Multi-framework support (.NET 6.0, 7.0, 8.0)
- Main assembly: `HELIOS.Platform.dll`
- Symbol files for debugging: `HELIOS.Platform.pdb`
- All 7 components pre-compiled
- Complete API documentation

**Published To:**

- https://www.nuget.org/packages/HELIOS.Platform/
- https://www.nuget.org/api/v2/package/HELIOS.Platform

**Dependencies:**

- Azure.Identity (1.10.0+)
- Azure.ResourceManager.Storage (1.6.0+)
- Microsoft.Extensions.Logging (8.0.0+)
- System.Diagnostics.EventLog (4.7.0+)

### 2. Standalone Executable (`HELIOS.Platform.exe`)

**What's Inside:**

- Self-contained console application
- No .NET runtime required
- All components bundled
- ~50MB total size (single-file deployment)

**Features:**

- Interactive menu system
- Command-line interface
- Real-time progress tracking
- Rollback capability
- Status monitoring

### 3. Windows Installer (`setup/Install.bat` or `Install.ps1`)

**What's Inside:**

- Batch installer for Windows
- PowerShell installer for Windows
- Creates installation directory
- Updates PATH environment variable
- Registers shortcuts

**Installation Path:**

- Default: `C:\Program Files\HELIOS.Platform`
- Customizable during installation

### 4. Demo Applications

**Included Demos:**

1. **Demo1_BasicUsage.cs** - Simple deployment and monitoring
2. **Demo2_ComponentIntegration.cs** - Access all 7 components
3. **Demo3_MultiTierDeployment.cs** - Multi-tier deployment scenarios

---

## 🚀 Deployment Scenarios

### Scenario 1: Development Integration

```csharp
using HELIOS.Platform;

// Add to your project.csproj
<PackageReference Include="HELIOS.Platform" Version="1.0.0" />

// Use in your code
var deployment = new HeliosDeployment();

// Validate platform
bool isValid = await deployment.ValidateAsync();

// Deploy with specific tier
var result = await deployment.DeployAsync(DeploymentTier.Professional);

// Monitor status
var status = await deployment.GetStatusAsync();
```

### Scenario 2: Standalone Server Deployment

```bash
# Copy executable to server
copy HELIOS.Platform.exe \\server\deployment\

# Connect and run
\\server\deployment\HELIOS.Platform.exe deploy enterprise

# Check status
\\server\deployment\HELIOS.Platform.exe status

# Rollback if needed
\\server\deployment\HELIOS.Platform.exe rollback 3
```

### Scenario 3: CI/CD Pipeline Integration

```yaml
# GitHub Actions Example
- name: Deploy HELIOS Platform
  run: |
    dotnet add package HELIOS.Platform
    dotnet build -c Release
    ./bin/Release/net8.0/YourApp.exe
```

### Scenario 4: Enterprise Distribution

```powershell
# Create corporate installation package
$nugetPath = "C:\dist\HELIOS.Platform.1.0.0.nupkg"

# Publish to internal NuGet feed
nuget push $nugetPath -Source "https://your-internal-feed/nuget"

# Deploy to multiple servers
$servers = @("server1", "server2", "server3")
foreach ($server in $servers) {
    Invoke-Command -ComputerName $server -ScriptBlock {
        dotnet package add HELIOS.Platform
    }
}
```

---

## 📊 Component Overview - 7 Integrated Components

### 1. **Monado Engine**

- Core performance optimization
- System resource management
- Performance metrics collection

### 2. **Security System**

- Windows security hardening
- Threat landscape analysis
- Security policy application
- Event log integration

### 3. **AI Orchestrator**

- Intelligent automation
- Deployment orchestration
- Query processing
- Model management

### 4. **GUI Dashboard**

- Real-time monitoring
- Metrics visualization
- Status updates
- Interactive controls

### 5. **Build Agents**

- CI/CD pipeline management
- Build execution
- Agent deployment
- Build result tracking

### 6. **DevAI Hub**

- AI-assisted development
- Code recommendations
- Collaboration features
- Development insights

### 7. **Software Stack**

- Dependency management
- Software provisioning
- Stack configuration
- Version management

---

## 🔧 Advanced Configuration

### Custom Deployment Configuration

```csharp
var config = new PhaseConfig
{
    EnableMonadoEngine = true,
    EnableSecuritySystem = true,
    EnableAIOrchestrator = true,
    // ... other options
};

var result = await deployment.DeployAsync(config);
```

### Environment Variables

```bash
# Logging configuration
set HELIOS_LOG_LEVEL=Debug

# Azure authentication
set AZURE_TENANT_ID=your-tenant-id
set AZURE_CLIENT_ID=your-client-id
set AZURE_CLIENT_SECRET=your-secret

# Deployment options
set HELIOS_DEPLOYMENT_TIER=Enterprise
set HELIOS_AUTO_UPDATE=true
```

### Configuration File

```json
{
  "HELIOS": {
    "Version": "1.0.0",
    "LogLevel": "Information",
    "DeploymentTier": "Professional",
    "EnableComponents": {
      "MonadoEngine": true,
      "SecuritySystem": true,
      "AIOrchestrator": true,
      "GUIDashboard": true,
      "BuildAgents": true,
      "DevAIHub": true,
      "SoftwareStack": true
    },
    "Azure": {
      "Enabled": true,
      "TenantId": "your-tenant-id",
      "SubscriptionId": "your-subscription-id"
    }
  }
}
```

---

## 📈 Deployment Tiers

### Standard Tier

- Basic component initialization
- Standard security policies
- Essential monitoring
- Ideal for: Development environments

### Professional Tier

- All components fully initialized
- Advanced security hardening
- Comprehensive monitoring
- Performance optimization enabled
- Ideal for: Production environments

### Enterprise Tier

- Full feature set
- Enterprise security policies
- Advanced AI orchestration
- Multi-region deployment
- SLA compliance
- Ideal for: Enterprise deployments

---

## ✅ Verification Checklist

### Pre-Deployment

- [ ] .NET 6.0 or later installed
- [ ] Administrator privileges available
- [ ] Network connectivity verified
- [ ] Azure credentials configured (if using cloud features)
- [ ] Sufficient disk space available (~500MB)

### Post-Deployment

- [ ] All 7 components initialized successfully
- [ ] No error messages in logs
- [ ] Platform validation passing
- [ ] Status showing "Ready"
- [ ] All metrics displaying correctly

### Post-Installation

- [ ] Executable in PATH
- [ ] Start Menu shortcuts working
- [ ] Environment variables set
- [ ] First deployment successful
- [ ] Rollback capability verified

---

## 🐛 Troubleshooting

### Issue: "Platform validation failed"

```powershell
# Check system requirements
Get-ComputerInfo | Select-Object -Property OSName, OSVersion

# Check .NET installation
dotnet --version

# Check for missing dependencies
dotnet package list HELIOS.Platform
```

### Issue: "Cannot find HELIOS.Platform.exe"

```powershell
# Verify PATH is set correctly
$env:PATH -split ';' | Select-String 'HELIOS'

# Manual path addition
$path = [Environment]::GetEnvironmentVariable("PATH")
[Environment]::SetEnvironmentVariable("PATH", "$path;C:\Program Files\HELIOS.Platform", "User")
```

### Issue: "Deployment stuck"

```powershell
# Check deployment status
HELIOS.Platform.exe status

# Rollback to previous state
HELIOS.Platform.exe rollback 2

# Full reset
HELIOS.Platform.exe undeploy
```

### Issue: "Azure authentication failed"

```powershell
# Verify Azure credentials
az login

# Check Azure subscription
az account show

# Configure Azure credentials
az account set --subscription "your-subscription-id"
```

---

## 🔐 Security Best Practices

1. **Administrator Privileges**
   - Always run installer with admin rights
   - Deployment requires admin context

2. **Network Security**
   - Use HTTPS for NuGet feeds
   - Verify package signatures
   - Check hash values

3. **Access Control**
   - Restrict installation to authorized users
   - Use Azure RBAC for cloud operations
   - Enable audit logging

4. **Updates & Patches**
   - Check for updates regularly
   - Test in staging before production
   - Keep dependencies current

---

## 📞 Support & Resources

### Documentation

- **API Reference:** `HELIOS.Platform\API_REFERENCE.md`
- **Deployment Guide:** `docs\DEPLOYMENT_GUIDE.md`
- **Contributing:** `CONTRIBUTION_GUIDE.md`

### Reporting Issues

- **GitHub Issues:** https://github.com/M0nado/helios-platform/issues
- **NuGet Page:** https://www.nuget.org/packages/HELIOS.Platform/

### Community

- **GitHub Discussions:** https://github.com/M0nado/helios-platform/discussions
- **Project Board:** https://github.com/orgs/M0nado/projects/

---

## 📝 Version History

### v1.0.0 (Current - 2024)

- ✓ Complete 7-component ecosystem
- ✓ Multi-framework support (.NET 6.0, 7.0, 8.0)
- ✓ Standalone executable deployment
- ✓ Windows installer
- ✓ NuGet package publishing
- ✓ Comprehensive documentation
- ✓ Demo applications

### Planned Features

- [ ] Web dashboard UI
- [ ] Docker container support
- [ ] Kubernetes orchestration
- [ ] Linux/macOS support
- [ ] Advanced metrics dashboard

---

## 📄 License

This project is licensed under the MIT License - see LICENSE.md for details.

**Quick License Summary:**

- ✓ Commercial use allowed
- ✓ Modification allowed
- ✓ Distribution allowed
- ✓ Private use allowed
- ✗ No warranty provided
- ✗ No liability

---

**Last Updated:** 2024
**Maintained By:** HELIOS Team (M0nado Organization)
