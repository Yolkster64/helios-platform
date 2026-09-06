# HELIOS NuGet Package

`HELIOS.Platform` is a complete enterprise automation system with:

- ✅ 6-phase automated deployment
- ✅ 6 coordinated build agents
- ✅ 12+ AI services integration
- ✅ 8-layer military-grade security
- ✅ Real-time monitoring dashboards
- ✅ Production-ready in 30 minutes

## Installation

```bash
dotnet add package HELIOS.Platform
```

or

```bash
nuget install HELIOS.Platform
```

or via Package Manager:

```
Install-Package HELIOS.Platform
```

## Quick Start

```csharp
using HELIOS.Platform;
using HELIOS.Deployment;

// Initialize deployment
var deployer = new HeliosDeployer();
deployer.RunPhase(DeploymentPhase.Preflight);
deployer.RunPhase(DeploymentPhase.Infrastructure);
deployer.RunPhase(DeploymentPhase.AgentFleet);
deployer.RunPhase(DeploymentPhase.AiServices);
deployer.RunPhase(DeploymentPhase.Security);
deployer.RunPhase(DeploymentPhase.Monitoring);
deployer.RunPhase(DeploymentPhase.Verification);

// Or run all phases
await deployer.RunAllPhasesAsync();

// Get deployment status
var status = deployer.GetStatus();
Console.WriteLine($"Status: {status.Phase}/{status.TotalPhases}");
Console.WriteLine($"Progress: {status.Progress:P}");
```

## Configuration

```csharp
var config = new HeliosConfiguration
{
    Environment = "production",
    AzureSubscription = "your-subscription-id",
    Region = "eastus",
    SecurityLevel = SecurityLevel.Maximum,
    EnableMonitoring = true,
    EnableCostOptimization = true
};

var deployer = new HeliosDeployer(config);
```

## Features

### Deployment Phases

- **Phase 0**: Pre-flight validation
- **Phase 1**: Infrastructure deployment
- **Phase 2**: Agent fleet launch
- **Phase 3**: AI services initialization
- **Phase 4**: Security framework deployment
- **Phase 5**: Monitoring dashboard setup
- **Phase 6**: Verification & go-live

### Security

- 8-layer protection framework
- USB token + TPM 2.0 authentication
- Dual vault secrets management
- 100% code signing coverage
- Immutable audit logging
- Consensus-based AI security

### Monitoring

- 7 real-time dashboards
- Cost tracking & optimization
- Performance analytics
- Security compliance reporting
- Integration with Power BI
- Teams alerts integration

## Documentation

- [Deployment Guide](../docs/DEPLOYMENT_COMPLETE_GUIDE.md)
- [Component Catalog](../docs/COMPONENT_CATALOG/)
- [Phase Planner](../docs/PHASE_PLANNER/)
- [Security Architecture](../docs/SECURITY_ARCHITECTURE.md)

## License

MIT License - See LICENSE file for details

## Support

- 📧 Email: support@helios-platform.dev
- 💬 Discussions: GitHub Discussions
- 🐛 Issues: GitHub Issues
- 📖 Docs: https://helios-platform.dev

---

**Made with ❤️ by the HELIOS team**
