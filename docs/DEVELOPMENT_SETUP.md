# HELIOS Platform - Development Setup Guide

**Version:** 1.0.0  
**Last Updated:** 2024  
**Target Audience:** Developers, contributors, platform engineers

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Project Structure](#project-structure)
4. [Building from Source](#building-from-source)
5. [Running Tests](#running-tests)
6. [Debugging](#debugging)
7. [Development Workflow](#development-workflow)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### System Requirements

**Operating System:**

- Windows 11 Pro or Enterprise
- Windows Server 2022+
- macOS 12.0+ (limited support)
- Ubuntu 20.04+ (limited support)

**Hardware:**

- CPU: 4 cores minimum (8 recommended)
- RAM: 8GB minimum (16GB recommended)
- Disk: 100GB SSD (50GB for base, 50GB for development)

### Required Software

**1. PowerShell 7.4+**

```powershell
# Check version
$PSVersionTable.PSVersion

# Install or upgrade
# https://github.com/PowerShell/PowerShell/releases
```

**2. .NET 8.0 SDK**

```powershell
# Download and install
# https://dotnet.microsoft.com/download/dotnet/8.0

# Verify installation
dotnet --version
```

**3. Git**

```powershell
# Install from https://git-scm.com/download/win
# Verify
git --version
```

**4. Docker Desktop**

```powershell
# Install from https://www.docker.com/products/docker-desktop
# Enable WSL 2 backend
# Verify
docker --version
docker run hello-world
```

**5. Azure CLI**

```powershell
# Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-windows
# Verify
az --version
```

**6. Code Editor** (choose one)

```powershell
# Visual Studio Code
# Download from https://code.visualstudio.com/

# Visual Studio 2022 Community
# Download from https://visualstudio.microsoft.com/
```

### Recommended VSCode Extensions

```json
{
  "extensions": [
    "ms-dotnettools.csharp",
    "ms-vscode.PowerShell",
    "ms-azure-tools.vscode-azuretools",
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "RedHat.vscode-yaml",
    "GitHub.Copilot"
  ]
}
```

---

## Environment Setup

### Step 1: Clone Repository

```powershell
# Clone main repository
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform

# Initialize submodules
git submodule update --init --recursive
```

### Step 2: Verify Prerequisites

```powershell
# Run verification script
.\verify-setup.sh

# Expected output:
# ✅ PowerShell 7.4+
# ✅ .NET 8.0 SDK
# ✅ Docker Desktop
# ✅ Git
# ✅ Azure CLI
# ✅ All prerequisites satisfied
```

### Step 3: Configure Development Environment

```powershell
# Copy environment template
Copy-Item .env.template -Destination .env

# Edit configuration
notepad .env

# Required settings:
# AZURE_SUBSCRIPTION_ID=your-subscription-id
# AZURE_RESOURCE_GROUP=helios-dev
# DOCKER_REGISTRY=your-registry
```

### Step 4: Install Dependencies

```powershell
# Restore NuGet packages
dotnet restore

# Install development tools
dotnet tool install -g dotnet-format
dotnet tool install -g dotnet-ef

# Verify
dotnet tool list -g
```

### Step 5: Set Up Local Database

```powershell
# Create local SQL database
# Option 1: Use Docker SQL Server
docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=Password123!" `
  -p 1433:1433 `
  -d mcr.microsoft.com/mssql/server:2022-latest

# Option 2: Use LocalDB (Windows)
sqllocaldb create MSSQLLocalDB
sqllocaldb start MSSQLLocalDB

# Apply migrations
dotnet ef database update
```

### Step 6: Configure Local Services

```powershell
# Start Redis cache
docker run -d -p 6379:6379 redis:latest

# Start Elasticsearch
docker run -d -p 9200:9200 -p 9300:9300 `
  -e "discovery.type=single-node" `
  docker.elastic.co/elasticsearch/elasticsearch:8.0.0

# Verify services
docker ps
```

---

## Project Structure

```
helios-platform/
├── src/
│   ├── HELIOS.Platform/
│   │   ├── Core/                 # Core abstractions
│   │   ├── Services/             # Business services
│   │   │   ├── DeploymentService
│   │   │   ├── SecurityService
│   │   │   ├── AiService
│   │   │   ├── AgentService
│   │   │   ├── MonitoringService
│   │   │   └── StorageService
│   │   ├── Agents/               # Build agents
│   │   │   ├── StorageAgent
│   │   │   ├── SecurityAgent
│   │   │   ├── SoftwareAgent
│   │   │   ├── GuiAgent
│   │   │   ├── OptimizationAgent
│   │   │   └── TestingAgent
│   │   ├── Models/               # Data models
│   │   ├── Repositories/         # Data access
│   │   ├── Middleware/           # HTTP middleware
│   │   ├── Extensions/           # Extension methods
│   │   └── Program.cs            # Entry point
│   ├── HELIOS.Platform.CLI/      # CLI tool
│   └── HELIOS.Platform.UI/       # Web UI (React)
├── tests/
│   ├── HELIOS.Platform.Tests/    # Unit tests
│   ├── HELIOS.Platform.Integration.Tests/
│   └── HELIOS.Platform.E2E.Tests/
├── docs/                          # Documentation
├── scripts/
│   ├── phase-0-preflight.ps1
│   ├── phase-1-infrastructure.ps1
│   ├── phase-2-agents.ps1
│   ├── phase-3-ai-services.ps1
│   ├── phase-4-security.ps1
│   ├── phase-5-monitoring.ps1
│   ├── phase-6-verification.ps1
│   └── deploy.ps1
├── config/                        # Configuration files
├── .devcontainer/                # Codespace configuration
├── .github/                       # GitHub workflows
├── helios-platform.sln           # Solution file
└── nuget.config                  # NuGet configuration
```

### Key Files

| File | Purpose |
|------|---------|
| `helios-platform.sln` | Visual Studio solution |
| `src/HELIOS.Platform/Program.cs` | API entry point |
| `src/HELIOS.Platform.CLI/Program.cs` | CLI entry point |
| `tests/` | Test projects |
| `.github/workflows/` | CI/CD pipelines |
| `config/` | Configuration files |

---

## Building from Source

### Build Solutions

```powershell
# Build all solutions
dotnet build

# Build with verbose output
dotnet build --verbose

# Build specific project
dotnet build src/HELIOS.Platform/HELIOS.Platform.csproj

# Release build
dotnet build --configuration Release
```

### Build Output

```
Build directory structure:
bin/
├── Debug/
│   └── net8.0/
│       ├── HELIOS.Platform.dll
│       ├── HELIOS.Platform.pdb
│       ├── HELIOS.Platform.CLI.exe
│       └── ...
└── Release/
    └── net8.0/
        ├── HELIOS.Platform.dll
        └── ...
```

### NuGet Package

```powershell
# Create NuGet package
dotnet pack src/HELIOS.Platform/HELIOS.Platform.csproj

# Output: bin/Release/HELIOS.Platform.1.0.0.nupkg

# Publish to NuGet
dotnet nuget push bin/Release/HELIOS.Platform.1.0.0.nupkg `
  -s https://api.nuget.org/v3/index.json `
  -k <api-key>
```

### Docker Image

```powershell
# Build Docker image
docker build -t helios-platform:latest .

# Build multi-stage image
docker build -f Dockerfile.prod -t helios-platform:1.0.0 .

# Run container
docker run -p 8080:8080 helios-platform:latest

# Push to registry
docker tag helios-platform:latest myregistry.azurecr.io/helios-platform:latest
docker push myregistry.azurecr.io/helios-platform:latest
```

---

## Running Tests

### Unit Tests

```powershell
# Run all unit tests
dotnet test

# Run specific test project
dotnet test tests/HELIOS.Platform.Tests/

# Run with code coverage
dotnet test /p:CollectCoverage=true /p:CoverageFormat=opencover

# View coverage report
# Open ./coverage/index.html
```

### Integration Tests

```powershell
# Run integration tests
dotnet test tests/HELIOS.Platform.Integration.Tests/ `
  --configuration Debug `
  --no-build

# With database
# Ensure SQL Server running: docker ps
dotnet test tests/HELIOS.Platform.Integration.Tests/
```

### End-to-End Tests

```powershell
# Run E2E tests
dotnet test tests/HELIOS.Platform.E2E.Tests/ `
  --configuration Release `
  --verbosity detailed

# These deploy actual infrastructure
# Set environment variables:
$env:AZURE_SUBSCRIPTION_ID="..."
$env:AZURE_RESOURCE_GROUP="helios-e2e-test"
$env:DEPLOY_TIMEOUT=3600
```

### Test Coverage

```powershell
# Generate coverage report
dotnet test /p:CollectCoverage=true `
  /p:CoverageFormat=cobertura `
  /p:Exclude="\"[HELIOS.Platform.Tests]*\""

# View HTML report
Start-Process "./coverage/index.html"
```

---

## Debugging

### Visual Studio Code

**Debug Configuration** (.vscode/launch.json):

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": ".NET Core Launch (web)",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "build",
      "program": "${workspaceFolder}/src/HELIOS.Platform/bin/Debug/net8.0/HELIOS.Platform.dll",
      "args": [],
      "cwd": "${workspaceFolder}",
      "stopAtEntry": false,
      "serverReadyAction": {
        "pattern": "\\bNow listening on:\\s+(https?://\\S+)",
        "uriFormat": "{0}",
        "action": "openExternalUrl"
      }
    }
  ]
}
```

**Start Debugging:**

1. Press F5
2. Set breakpoints (click left margin)
3. Inspect variables in debug panel

### Command Line Debugging

```powershell
# Run with debug symbols
dotnet run --configuration Debug

# Attach debugger to running process
dotnet attach -p <process-id>

# Debug tests
dotnet test --configuration Debug --diagnostics
```

### Logging

**Configure logging level:**

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft": "Information",
      "HELIOS": "Debug"
    }
  }
}
```

**View logs:**

```powershell
# Real-time log streaming
Get-HeliosLogStream -Follow

# Export logs
Export-HeliosLogs -OutputPath ./logs.zip
```

---

## Development Workflow

### 1. Feature Development

```powershell
# Create feature branch
git checkout -b feature/my-feature

# Make changes and commit
git add .
git commit -m "feat: Add new feature"

# Push to remote
git push origin feature/my-feature

# Create pull request on GitHub
```

### 2. Code Style

**HELIOS uses:**

- C# Coding Conventions
- StyleCop analyzers
- EditorConfig rules

**Format code:**

```powershell
# Auto-format all files
dotnet format

# Format specific file
dotnet format src/HELIOS.Platform/MyFile.cs

# Check without formatting
dotnet format --verify-no-changes
```

### 3. Commit Messages

**Format:** `<type>(<scope>): <description>`

**Types:**

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation
- `style` - Code style
- `refactor` - Refactoring
- `test` - Test additions
- `chore` - Build/tooling

**Examples:**

```
feat(ai): Add Claude model routing
fix(security): Fix MFA token validation
docs(setup): Add development guide
test(deployment): Add phase 2 tests
```

### 4. Pull Request Process

1. Push to feature branch
2. Create PR with description
3. Link related issues
4. Request reviewers
5. Address feedback
6. Merge to main

---

## Troubleshooting

### Build Issues

**Error:** "Project file not found"

```powershell
# Solution: Verify solution path
ls helios-platform.sln
dotnet sln list
```

**Error:** ".NET 8.0 not found"

```powershell
# Solution: Install .NET 8.0 SDK
dotnet --list-sdks
# Download from https://dotnet.microsoft.com/download/dotnet/8.0
```

### Database Issues

**Error:** "Connection timeout"

```powershell
# Solution: Verify database running
docker ps | Select-String sql

# Start if not running
docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=Password123!" `
  -p 1433:1433 `
  -d mcr.microsoft.com/mssql/server:2022-latest

# Update connection string in appsettings.json
```

### Docker Issues

**Error:** "Docker daemon not running"

```powershell
# Solution: Start Docker Desktop
Start-Service Docker

# Or start Docker Desktop application
```

**Error:** "Port already in use"

```powershell
# Find process using port
netstat -ano | findstr :8080

# Kill process
Stop-Process -Id <PID> -Force
```

### Test Issues

**Error:** "Tests fail locally but pass in CI"

```powershell
# Solution: Ensure same environment
docker ps  # Check if services running
dotnet test --configuration Debug
```

---

## Additional Resources

- **Contributing Guide:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **CLI Reference:** [../CLI_REFERENCE.md](../CLI_REFERENCE.md)
- **Official Docs:** https://docs.helios-platform.dev

---

**Last Updated:** 2024  
**Version:** 1.0.0
