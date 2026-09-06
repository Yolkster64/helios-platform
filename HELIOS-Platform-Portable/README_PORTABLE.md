# HELIOS Platform - Portable Version Setup Guide

## Quick Start

1. **Extract** HELIOS-Platform-Portable.zip to your desired location
2. **Verify** you have .NET 8.0 Runtime installed:

   ```powershell
   dotnet --version
   ```

3. **Run** the executable:

   ```powershell
   .\HELIOS.Platform.exe
   ```

## System Requirements

### Minimum

- Windows 10 (Build 1909+) or Windows Server 2019+
- .NET 8.0 Runtime
- 256 MB RAM
- 200 MB disk space

### Recommended

- Windows 11 or Windows Server 2022+
- .NET 8.0 Runtime + Latest patches
- 2 GB+ RAM
- 500 MB+ disk space for operation

## Installation

### Option 1: Portable (No Installation)

- Extract ZIP file anywhere
- Run HELIOS.Platform.exe directly
- No registry modifications
- Can move/delete directory anytime

### Option 2: System Path (Optional)

```powershell
# Add to system PATH for command-line access from anywhere
$env:Path += ";C:\path\to\HELIOS-Platform"
```

## Configuration

### Environment Variables

Set environment variables before running to customize behavior:

```powershell
# Set custom log level
$env:HELIOS_LOG_LEVEL = "Debug"

# Set working directory
$env:HELIOS_WORK_DIR = "C:\HELIOS-Data"

# Enable cloud features
$env:HELIOS_ENABLE_CLOUD = "true"
```

### Configuration Files

Place YAML or JSON config files in the `config/` folder:

- `config/security.yaml` - Security settings
- `config/optimization.yaml` - Optimization parameters
- `config/cloud.yaml` - Azure/Cloud settings
- `config/monitoring.yaml` - Log and metrics settings

Example `config/security.yaml`:

```yaml
security:
  mfa_enabled: true
  min_password_length: 12
  session_timeout_minutes: 30
```

## Features

### Core Capabilities

- ✓ **Security Management** - Credential management, authentication, authorization
- ✓ **System Optimization** - Profile-based system tuning, performance management
- ✓ **Cloud Integration** - Azure services, cloud storage, cloud compute
- ✓ **Monitoring & Logging** - Prometheus metrics, structured logging with Serilog
- ✓ **AI/ML Integration** - ML.NET models, AI predictions, machine learning
- ✓ **Container Support** - Docker integration, orchestration support

### Advanced Features

- Extensible plugin architecture
- Comprehensive API for integration
- Multi-tenancy support
- Enterprise audit logging
- Role-based access control (RBAC)
- Automated backup and recovery
- Health monitoring and alerts

## Running the Application

### Basic Execution

```powershell
.\HELIOS.Platform.exe
```

### With Output Logging

```powershell
.\HELIOS.Platform.exe > app.log 2>&1
```

### With Custom Working Directory

```powershell
cd C:\HELIOS-Data
...\HELIOS.Platform.exe
```

### Running as a Service (Windows)

Create a batch file `run-helios.bat`:

```batch
@echo off
cd /d %~dp0
start /b .\HELIOS.Platform.exe
```

Then use Task Scheduler or NSSM to manage as service.

## Troubleshooting

### ".NET 8.0 not found" Error

**Solution:** Install .NET 8.0 Runtime from https://dotnet.microsoft.com/download/dotnet/8.0

### "Port already in use" Error

**Solution:** Change port in `config/network.yaml` or kill existing process:

```powershell
taskkill /IM HELIOS.Platform.exe /F
```

### "Permission denied" Error

**Solution:** Run PowerShell as Administrator or modify file permissions:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Application Crashes on Startup

**Solution:** Enable debug logging:

```powershell
$env:HELIOS_LOG_LEVEL = "Debug"
.\HELIOS.Platform.exe
```

## Performance Optimization

### Memory Usage

- Default: ~50-80 MB at startup
- Optimize: Set `HELIOS_GC_MODE = "Workstation"` for lower memory systems

### CPU Usage

- Default: <1% idle
- Scale: Add worker threads in config for multi-core systems

### Disk I/O

- Cache location: `config/cache/`
- Increase cache size in config for frequently used operations

## Security Considerations

### Best Practices

1. **Run as Limited User** - Don't run as Administrator unless necessary
2. **Enable MFA** - Use multi-factor authentication when available
3. **Secure Config Files** - Protect config/ folder with restricted ACLs
4. **Update Regularly** - Download latest version periodically
5. **Monitor Logs** - Review security logs for suspicious activity

### Credential Storage

- Sensitive data is encrypted in transit
- Credentials stored in Windows Credential Manager when available
- Never commit credentials to version control

## Updating

### Check for Updates

```powershell
.\HELIOS.Platform.exe --version
```

### Update Procedure

1. Download latest HELIOS-Platform-Portable.zip
2. Backup current config/ folder
3. Extract new version to new location or update existing
4. Restore config/ folder if needed
5. Restart application

## Uninstallation

Since this is portable (no installation), simply:

1. Stop any running instances
2. Delete the HELIOS-Platform directory
3. Remove any shortcuts or PATH entries

Configuration data is only in the `config/` folder, so back that up if needed before deletion.

## Support & Documentation

- **Version:** 1.0.0
- **Released:** 2026-04-16
- **Platform:** Windows (x64)
- **Runtime:** .NET 8.0+

For additional help:

- Check application log files in working directory
- Review config examples in config/ folder
- Enable debug logging for detailed troubleshooting

## Legal

HELIOS Platform is provided as-is. Refer to LICENSE file for full terms and conditions.

---

**Status:** Production Ready  
**Last Updated:** 2026-04-16 17:21 UTC
