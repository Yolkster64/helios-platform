# Phase 10 Quarantine System - Quick Start Guide

## 5-Minute Setup

### Step 1: Prerequisites Check

```bash
# Verify .NET 8.0 is installed
dotnet --version

# Should show version 8.0 or higher
```

### Step 2: Install VeraCrypt

```bash
# Download from https://www.veracrypt.fr/
# Or install via chocolatey
choco install veracrypt -y

# Verify installation
"C:\Program Files\VeraCrypt\veracrypt.exe" /?
```

### Step 3: Initialize Quarantine System

```csharp
using HELIOS.Platform.Phase10.Quarantine;

// Create logger
var logger = new ConsoleLogger();

// Initialize service
var service = new QuarantineService(logger);
bool initialized = await service.InitializeAsync();

Console.WriteLine($"System initialized: {initialized}");
```

### Step 4: Capture Your First Threat

```csharp
// Capture a suspicious file
var result = await service.CaptureThreatAsync("C:\\Downloads\\suspicious.exe", "Generic.Malware");

if (result.IsSuccessful)
{
    Console.WriteLine($"✓ Captured: {result.QuarantinePath}");
    Console.WriteLine($"✓ Hash: {result.FileHash}");
    Console.WriteLine($"✓ Backup: {result.BackupPath}");
}
```

### Step 5: Analyze the Threat

```csharp
// Analyze captured threat
var report = await service.AnalyzeThreatAsync(result.QuarantinePath);

Console.WriteLine($"Threat Level: {report.ThreatLevel}");
Console.WriteLine($"Family: {report.ThreatFamily}");
Console.WriteLine("Recommendations:");
foreach (var suggestion in report.RemediationSuggestions)
{
    Console.WriteLine($"  - {suggestion}");
}
```

## Common Tasks

### View Quarantine Status

```csharp
var stats = await service.GetQuarantineStatsAsync();
Console.WriteLine($"Total Threats: {stats.TotalThreatCount}");
Console.WriteLine($"Space Used: {stats.TotalUsedSpace / (1024 * 1024)} MB");
Console.WriteLine($"Active: {stats.ActiveThreatCount}");
Console.WriteLine($"Archived: {stats.ArchivedThreatCount}");
```

### List All Quarantined Files

```csharp
var files = await service.ListQuarantinedFilesAsync();
foreach (var file in files)
{
    Console.WriteLine($"{file.FileName} - {file.FileSize:N0} bytes");
}
```

### Delete a Threat

```csharp
// Permanently delete threat and backup
bool deleted = await service.DeleteThreatAsync("20240120_malware_abcd1234.quarantine", deleteBackup: true);
Console.WriteLine($"Deleted: {deleted}");
```

### Update Threat Intelligence

```csharp
var result = await service.UpdateThreatIntelligenceAsync();
Console.WriteLine($"Signatures: {result.SignaturesUpdated}");
Console.WriteLine($"Definitions: {result.DefinitionsDownloaded}");
Console.WriteLine($"Heuristics: {result.HeuristicsUpdated}");
```

## Configuration Guide

### Adjust Partition Size

Edit `config/Phase10/quarantine-config.json`:

```json
{
  "quarantineConfig": {
    "partitionSizeGB": 30  // Change from 20 to 30 GB
  }
}
```

### Change Archive Threshold

```json
{
  "quarantineConfig": {
    "archiveThresholdDays": 60  // Archive after 60 days instead of 90
  }
}
```

### Disable Auto Update

```json
{
  "quarantineConfig": {
    "threatIntelligence": {
      "autoUpdate": false
    }
  }
}
```

## Running Tests

```bash
# Run all quarantine tests
dotnet test --filter "Phase10.Quarantine"

# Run specific test class
dotnet test --filter "QuarantineSystemSetupTests"

# Run with verbose output
dotnet test --verbosity detailed
```

## Monitoring

### Check System Logs

```bash
# View recent logs
Get-Content "$env:APPDATA\HELIOS\quarantine-logs\system.log" -Tail 50
```

### Monitor Active Threats

```csharp
// Every 5 minutes
while (true)
{
    var stats = await service.GetQuarantineStatsAsync();
    Console.WriteLine($"[{DateTime.Now:HH:mm:ss}] Active: {stats.ActiveThreatCount}, Space: {stats.TotalUsedSpace / (1024*1024)} MB");
    await Task.Delay(TimeSpan.FromMinutes(5));
}
```

## Troubleshooting

### Issue: "VeraCrypt not found"

```bash
# Add to PATH
$env:Path += ";C:\Program Files\VeraCrypt"
```

### Issue: Permission Denied

```bash
# Run as Administrator
Start-Process powershell -ArgumentList "-Command `"$YOUR_COMMAND`"" -Verb RunAs
```

### Issue: Partition Already Exists

```bash
# Check drive I: is mounted
Get-Volume -DriveLetter I
```

## Architecture Overview

```
User Request
    ↓
QuarantineService (Main Interface)
    ├─→ ThreatCapture (Isolate files)
    ├─→ ThreatAnalyzer (Analyze threats)
    ├─→ QuarantineManager (Manage storage)
    └─→ ThreatIntelligenceUpdater (Update rules)
    ↓
Encrypted I: Partition (VeraCrypt)
    ├─ active-threats/
    ├─ threat-database/
    ├─ analysis-logs/
    ├─ backup-quarantined/
    └─ archive/
```

## Performance Tips

1. **Batch Processing**: Process multiple files together

   ```csharp
   var results = await service.CaptureThreatsBatchAsync(fileList);
   ```

2. **Archive Regularly**: Keep active threats minimal

   ```csharp
   await QuarantineManager.ArchiveOldThreatsAsync(90);
   ```

3. **Update Intelligence**: Keep threat database current

   ```csharp
   await service.UpdateThreatIntelligenceAsync();
   ```

## Integration Example

```csharp
// Complete threat handling workflow
var orchestrator = new QuarantineOrchestrator(service, logger);

var threatsToHandle = new List<string>
{
    "C:\\Downloads\\file1.exe",
    "C:\\Downloads\\file2.dll",
    "C:\\Downloads\\file3.scr"
};

var results = await orchestrator.HandleMultipleThreatsAsync(threatsToHandle);

foreach (var result in results)
{
    Console.WriteLine($"File: {Path.GetFileName(result.FilePath)}");
    Console.WriteLine($"Level: {result.ThreatLevel}");
    foreach (var suggestion in result.RemediationSuggestions)
    {
        Console.WriteLine($"  ✓ {suggestion}");
    }
}
```

## Next Steps

1. ✓ System initialized
2. ✓ First threat captured
3. ✓ Threat analyzed
4. → Set up monitoring
5. → Configure alerts
6. → Integrate with antivirus
7. → Schedule regular updates

## Support

- **Documentation**: See `PHASE10_QUARANTINE_README.md`
- **Tests**: Run `dotnet test` for validation
- **Logs**: Check `%APPDATA%\HELIOS\quarantine-logs\`
- **Config**: Edit `config\Phase10\quarantine-config.json`

## Key Files

- **Services**: `src/HELIOS.Platform/Phase10/Quarantine/*.cs`
- **Tests**: `tests/HELIOS.Platform.Tests/Phase10/Quarantine/`
- **Config**: `config/Phase10/quarantine-config.json`
- **Intel**: `config/Phase10/threat-intelligence.json`

---

**Status**: Production Ready
**Version**: 1.0.0
**Last Updated**: January 2024
