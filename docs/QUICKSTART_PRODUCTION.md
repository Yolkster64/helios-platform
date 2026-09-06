# HELIOS Platform - Quick Start

Get the HELIOS Platform up and running in 5 minutes.

## Prerequisites

- Windows 10/11, Linux, or macOS
- .NET 6.0 SDK or later
- Git
- Visual Studio Code or Visual Studio 2022 (optional)

**Verify Installation**:

```powershell
dotnet --version
git --version
```

## Installation (3 minutes)

### Step 1: Clone Repository

```powershell
git clone https://github.com/M0nado/helios-platform.git
cd helios-platform
```

### Step 2: Restore Dependencies

```powershell
dotnet restore
```

### Step 3: Build

```powershell
dotnet build
```

### Step 4: Run Tests

```powershell
dotnet test
```

Expected: All tests pass with summary showing passed/failed counts.

## First Run (1 minute)

### Start Application

```powershell
cd src/HELIOS.Platform
dotnet run
```

Expected output:

```
info: HELIOS.Platform[0]
      API Gateway listening on http://localhost:5000
```

### Test in Another Terminal

```powershell
curl http://localhost:5000/api/v1/health
```

Expected response:

```json
{
  "success": true,
  "data": { "status": "healthy" }
}
```

## Next Steps

1. **Read [ARCHITECTURE_COMPLETE.md](./ARCHITECTURE_COMPLETE.md)** (10 min) - Understand system design
2. **Read [API_COMPLETE.md](./API_COMPLETE.md)** (10 min) - Learn API endpoints
3. **Read [CONTRIBUTING.md](./CONTRIBUTING.md)** (10 min) - Start developing
4. **Explore code** in `src/HELIOS.Platform/Core/`

## Common Commands

```powershell
dotnet build          # Build solution
dotnet run           # Run application
dotnet test          # Run all tests
dotnet format        # Format code
dotnet clean         # Clean build
```

## Troubleshooting

**Build fails**:

```powershell
dotnet clean
dotnet restore
dotnet build
```

**Port 5000 in use**:

```powershell
dotnet run -- --port 5002
```

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for more solutions.

---

**Last Updated**: Phase 7, Stream 8 - Documentation Expansion
