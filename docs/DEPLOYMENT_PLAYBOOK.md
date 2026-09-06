# HELIOS Platform - Complete Deployment Playbook

## 📋 Executive Summary

This playbook provides step-by-step procedures for deploying the HELIOS Platform v1.0.0 in various scenarios:

- **NuGet Package Installation** (developers)
- **Standalone Executable Deployment** (operations)
- **Windows System Installation** (end users)
- **Enterprise Multi-System Deployment** (IT/DevOps)
- **CI/CD Pipeline Integration** (DevOps)

**Estimated Deployment Time:** 15-30 minutes (varies by tier)
**Success Rate Target:** 99.5%
**Rollback Time:** 5 minutes

---

## 🎯 Pre-Deployment Checklist

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Windows 7 SP1 | Windows 10/11 |
| .NET | 6.0 SDK | 8.0 SDK |
| RAM | 2GB | 8GB |
| Disk Space | 500MB | 2GB |
| Admin Rights | Yes* | Yes |
| Network | Optional | Required (for Azure features) |

### Pre-Deployment Tasks

```powershell
# 1. Verify system requirements
$osVersion = [System.Environment]::OSVersion.VersionString
Write-Host "OS: $osVersion"

# 2. Check disk space
$disk = Get-Volume C
Write-Host "Free Space: $($disk.SizeRemaining / 1GB)GB"

# 3. Verify .NET installation
dotnet --version
dotnet --list-runtimes

# 4. Test network connectivity
Test-NetConnection -ComputerName nuget.org -Port 443

# 5. Backup current system state (optional but recommended)
$backupPath = "C:\backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
mkdir $backupPath
Write-Host "Backup directory: $backupPath"
```

---

## 📦 Deployment Scenario 1: NuGet Package Installation

### Target: Software Developers

### Timeline: 5 minutes

### Step 1: Create Project (if needed)

```powershell
cd C:\projects
dotnet new console -n MyHeliosApp
cd MyHeliosApp
```

### Step 2: Add NuGet Package

**Option A: Command Line**

```powershell
dotnet add package HELIOS.Platform --version 1.0.0
```

**Option B: Package Manager Console**

```powershell
Install-Package HELIOS.Platform -Version 1.0.0
```

**Option C: Visual Studio UI**

1. Right-click Project → Manage NuGet Packages
2. Search for "HELIOS.Platform"
3. Click Install

### Step 3: Verify Installation

```powershell
# Check project file
cat .\MyHeliosApp.csproj | Select-String -Pattern "HELIOS"

# Output should show:
# <PackageReference Include="HELIOS.Platform" Version="1.0.0" />
```

### Step 4: Restore and Build

```powershell
dotnet restore
dotnet build -c Release
```

### Step 5: Create Usage Code

```csharp
using System;
using System.Threading.Tasks;
using HELIOS.Platform;

class Program
{
    static async Task Main()
    {
        // Initialize deployment orchestrator
        var deployment = new HeliosDeployment();

        // Validate platform
        Console.WriteLine("Validating HELIOS Platform...");
        bool isValid = await deployment.ValidateAsync();
        
        if (!isValid)
        {
            Console.WriteLine("Validation failed!");
            return;
        }

        // Deploy platform
        Console.WriteLine("Deploying with Professional tier...");
        var result = await deployment.DeployAsync(DeploymentTier.Professional);

        Console.WriteLine($"Deployment {(result.Success ? "successful" : "failed")}");
        Console.WriteLine($"Current Phase: {result.CurrentPhase}");
        Console.WriteLine($"Current Tier: {result.CurrentTier}");
    }
}
```

### Step 6: Run Application

```powershell
dotnet run --configuration Release
```

### Verification Checklist

- [ ] Package installed without errors
- [ ] No compilation errors
- [ ] Application runs successfully
- [ ] Deployment initialized correctly
- [ ] Status shows as running

---

## 🚀 Deployment Scenario 2: Standalone Executable

### Target: System Administrators / Operations

### Timeline: 10 minutes

### Step 1: Acquire Executable

**Option A: Download from Distribution**

```powershell
# Copy from dist folder or download from release
$source = "dist\Release\HELIOS.Platform.exe"
$dest = "C:\HELIOS"
mkdir $dest -Force
Copy-Item $source -Destination $dest
```

**Option B: Build Standalone**

```powershell
# From project directory
.\build.ps1 -CreateExe -Configuration Release

# Result: dist\Release\HELIOS.Platform.exe
```

### Step 2: Verify Executable

```powershell
# Check file exists
Test-Path "C:\HELIOS\HELIOS.Platform.exe"

# Check file size
(Get-Item "C:\HELIOS\HELIOS.Platform.exe").Length / 1MB

# Test execution
& "C:\HELIOS\HELIOS.Platform.exe" --help
```

### Step 3: Interactive Deployment

```powershell
# Run with menu
cd C:\HELIOS
.\HELIOS.Platform.exe

# Select from menu:
# 1. Validate Platform
# 2. Deploy (Standard)
# 3. Deploy (Professional)
# 4. Deploy (Enterprise)
# 5. Get Status
# 6. Rollback
# 7. Undeploy
# 0. Exit
```

### Step 4: Command-Line Deployment (Automated)

```powershell
# Validate
C:\HELIOS\HELIOS.Platform.exe validate

# Deploy (Standard)
C:\HELIOS\HELIOS.Platform.exe deploy standard

# Deploy (Professional)
C:\HELIOS\HELIOS.Platform.exe deploy professional

# Deploy (Enterprise)
C:\HELIOS\HELIOS.Platform.exe deploy enterprise

# Check status
C:\HELIOS\HELIOS.Platform.exe status

# Rollback if needed
C:\HELIOS\HELIOS.Platform.exe rollback 3

# Undeploy
C:\HELIOS\HELIOS.Platform.exe undeploy
```

### Step 5: Monitor Deployment

```powershell
# Watch deployment progress
while ($true) {
    Clear-Host
    C:\HELIOS\HELIOS.Platform.exe status
    Start-Sleep -Seconds 5
}
```

### Verification Checklist

- [ ] Executable found and accessible
- [ ] File integrity verified
- [ ] Validation passes
- [ ] Deployment completes
- [ ] Status shows "Ready"
- [ ] All components initialized

---

## 🔧 Deployment Scenario 3: Windows System Installation

### Target: End Users / System Administrators

### Timeline: 15 minutes

### Step 1: Run Installer

**Option A: Batch Installer (Recommended for simplicity)**

```powershell
# Navigate to setup directory
cd setup

# Right-click and run as Administrator
.\Install.bat

# Or run from PowerShell (as Administrator)
& ".\Install.bat"
```

**Option B: PowerShell Installer**

```powershell
# Run as Administrator (required)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\Install.ps1

# Follow prompts:
# - Confirm installation path
# - Enter custom path if needed
# - Accept installation
```

### Step 2: Verify Installation

```powershell
# Test if executable is in PATH
Get-Command HELIOS.Platform.exe

# Should output:
# CommandType     Name                           ModuleName
# -----------     ----                           ----------
# ExternalScript  HELIOS.Platform.exe

# List installation directory
dir "C:\Program Files\HELIOS.Platform"
```

### Step 3: Run Platform

```powershell
# From any directory, run executable
HELIOS.Platform.exe

# Or with specific command
HELIOS.Platform.exe deploy professional
```

### Step 4: Create Shortcut (Optional)

```powershell
# Create desktop shortcut
$WshShell = New-Object -ComObject WScript.Shell
$shortcutPath = "$env:USERPROFILE\Desktop\HELIOS Platform.lnk"
$targetPath = "C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe"

$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.WorkingDirectory = "C:\Program Files\HELIOS.Platform"
$shortcut.IconLocation = $targetPath
$shortcut.Save()
```

### Verification Checklist

- [ ] Installation completed without errors
- [ ] Files copied to Program Files
- [ ] PATH environment variable updated
- [ ] Executable accessible from anywhere
- [ ] Start Menu shortcuts created
- [ ] Desktop shortcut working (if created)

---

## 🏢 Deployment Scenario 4: Enterprise Multi-System

### Target: IT/DevOps Teams

### Timeline: 30-60 minutes (depending on system count)

### Step 1: Prepare Distribution Package

```powershell
# Create central distribution point
$distSharePath = "\\fileserver\helios-distribution"
mkdir $distSharePath -Force

# Copy executable
Copy-Item "dist\Release\HELIOS.Platform.exe" -Destination $distSharePath

# Copy installer scripts
Copy-Item "setup\Install.bat" -Destination $distSharePath
Copy-Item "setup\Install.ps1" -Destination $distSharePath

# Create README
"Installation Instructions:
1. Run Install.bat as Administrator
2. Select custom installation path if needed
3. Run HELIOS.Platform.exe to verify

For managed deployment, use Deploy-ToServers.ps1" | 
    Out-File -FilePath "$distSharePath\README.txt"
```

### Step 2: Create Deployment Script

```powershell
# Save as: Deploy-ToServers.ps1
param(
    [string[]]$Servers = @("server1", "server2", "server3"),
    [string]$DeploymentTier = "Professional",
    [string]$Username = $env:USERNAME,
    [string]$Password  # Prompt for password
)

$scriptBlock = {
    param($tier, $distPath)
    
    # Copy files
    $installPath = "C:\Program Files\HELIOS.Platform"
    mkdir $installPath -Force
    Copy-Item "$distPath\HELIOS.Platform.exe" -Destination $installPath -Force
    
    # Deploy
    & "$installPath\HELIOS.Platform.exe" validate
    & "$installPath\HELIOS.Platform.exe" deploy $tier
    
    # Return status
    & "$installPath\HELIOS.Platform.exe" status
}

# Deploy to each server
foreach ($server in $Servers) {
    Write-Host "Deploying to $server..." -ForegroundColor Green
    
    $cred = New-Object System.Management.Automation.PSCredential (
        $Username,
        (ConvertTo-SecureString $Password -AsPlainText -Force)
    )
    
    Invoke-Command -ComputerName $server `
        -Credential $cred `
        -ScriptBlock $scriptBlock `
        -ArgumentList $DeploymentTier, "\\fileserver\helios-distribution"
    
    Write-Host "Deployment to $server completed" -ForegroundColor Green
}
```

### Step 3: Run Enterprise Deployment

```powershell
# Deploy to multiple servers
.\Deploy-ToServers.ps1 -Servers @("srv-prod-01", "srv-prod-02", "srv-prod-03") `
    -DeploymentTier "Enterprise"
```

### Step 4: Verify Enterprise Deployment

```powershell
# Create verification script
$servers = @("srv-prod-01", "srv-prod-02", "srv-prod-03")

foreach ($server in $servers) {
    $status = Invoke-Command -ComputerName $server -ScriptBlock {
        & "C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe" status
    }
    
    Write-Host "Server: $server"
    Write-Host $status
    Write-Host "---"
}
```

### Verification Checklist

- [ ] Distribution share created
- [ ] All files copied to share
- [ ] Deployment script created and tested
- [ ] All target servers accessible
- [ ] Credentials verified
- [ ] Deployment completed on all servers
- [ ] Status verified on all servers

---

## 🔄 Deployment Scenario 5: CI/CD Pipeline Integration

### Target: DevOps / Development Teams

### Timeline: 5-10 minutes setup

### GitHub Actions Workflow

```yaml
name: HELIOS Platform Build & Deploy

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup .NET
      uses: actions/setup-dotnet@v3
      with:
        dotnet-version: '8.0.x'
    
    - name: Restore dependencies
      run: dotnet restore
    
    - name: Build
      run: dotnet build -c Release --no-restore
    
    - name: Run tests
      run: dotnet test -c Release --no-build --verbosity normal
    
    - name: Create NuGet package
      run: dotnet pack src/HELIOS.Platform/HELIOS.Platform.csproj -c Release -o ./dist
    
    - name: Create executable
      run: |
        mkdir -p dist/Release
        dotnet publish dist/HELIOS.Platform.Exe/HELIOS.Platform.Exe.csproj `
          -c Release -f net8.0 -r win-x64 `
          --self-contained -p:PublishSingleFile=true `
          -o dist/Release
    
    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: helios-distribution
        path: dist/
    
    - name: Publish to NuGet.org
      if: startsWith(github.ref, 'refs/tags/')
      run: |
        dotnet nuget push dist/*.nupkg `
          -s https://api.nuget.org/v3/index.json `
          -k ${{ secrets.NUGET_API_KEY }} `
          --skip-duplicate
```

### Azure Pipelines Workflow

```yaml
trigger:
  - main

pr:
  - main

pool:
  vmImage: 'windows-latest'

variables:
  buildConfiguration: 'Release'
  buildPlatform: 'x64'

stages:
  - stage: Build
    jobs:
    - job: BuildAndTest
      displayName: 'Build and Test'
      steps:
      - task: UseDotNet@2
        inputs:
          version: '8.0.x'
      
      - task: DotNetCoreCLI@2
        displayName: 'Restore'
        inputs:
          command: 'restore'
      
      - task: DotNetCoreCLI@2
        displayName: 'Build'
        inputs:
          command: 'build'
          arguments: '-c Release'
      
      - task: DotNetCoreCLI@2
        displayName: 'Test'
        inputs:
          command: 'test'
          arguments: '-c Release --no-build'
      
      - task: DotNetCoreCLI@2
        displayName: 'Pack'
        inputs:
          command: 'pack'
          packagesToPack: '**/HELIOS.Platform.csproj'
          configuration: '$(buildConfiguration)'
          outputDir: '$(Build.ArtifactStagingDirectory)'
      
      - task: PublishBuildArtifacts@1
        displayName: 'Publish Artifacts'
        inputs:
          PathtoPublish: '$(Build.ArtifactStagingDirectory)'
          ArtifactName: 'helios-distribution'
  
  - stage: Publish
    condition: succeeded()
    jobs:
    - job: PublishNuGet
      displayName: 'Publish to NuGet.org'
      steps:
      - task: DownloadBuildArtifacts@0
        inputs:
          artifactName: 'helios-distribution'
      
      - task: NuGetCommand@2
        inputs:
          command: 'push'
          packagesToPush: '$(Pipeline.Workspace)/**/*.nupkg;!$(Pipeline.Workspace)/**/*.symbols.nupkg'
          nuGetFeedType: 'external'
          publishFeedCredentials: 'NuGet.org'
```

### Verification Checklist

- [ ] Workflow file created and syntax valid
- [ ] Build succeeds in CI/CD
- [ ] Tests pass in CI/CD
- [ ] Package created successfully
- [ ] Executable builds successfully
- [ ] Artifacts published
- [ ] NuGet package available after publish

---

## ⚠️ Rollback Procedures

### Quick Rollback

```powershell
# If deployment fails or encounters issues
HELIOS.Platform.exe rollback <phase>

# Example - rollback to phase 2
HELIOS.Platform.exe rollback 2

# Verify rollback completed
HELIOS.Platform.exe status
```

### Complete Undeployment

```powershell
# Complete removal
HELIOS.Platform.exe undeploy

# Wait for completion
Start-Sleep -Seconds 10

# Verify undeploy
HELIOS.Platform.exe status
```

### Manual Rollback (if automated fails)

```powershell
# 1. Stop any running deployments
Get-Process HELIOS.Platform* | Stop-Process -Force

# 2. Restore from backup (if available)
Copy-Item "C:\backup-20240101-120000\*" -Destination "C:\Program Files\HELIOS.Platform" -Recurse -Force

# 3. Verify system state
C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe status

# 4. Investigate logs
Get-EventLog -LogName Application | Where-Object {$_.Source -like "*HELIOS*"} | Format-List
```

---

## 🔍 Troubleshooting Guide

### Issue: "Access Denied" during installation

**Cause:** Not running as administrator
**Solution:**

```powershell
# Run PowerShell as Administrator
# Or run batch file with right-click → "Run as administrator"
```

### Issue: Deployment stuck on phase 3

**Cause:** AI Orchestrator initialization timeout
**Solution:**

```powershell
# Rollback to phase 2
HELIOS.Platform.exe rollback 2

# Retry with Standard tier (fewer components)
HELIOS.Platform.exe deploy standard

# Check logs for details
Get-EventLog -LogName Application -Newest 20 | Format-List
```

### Issue: "Cannot find HELIOS.Platform.exe"

**Cause:** Installation path not in PATH environment variable
**Solution:**

```powershell
# Add to PATH manually
$installPath = "C:\Program Files\HELIOS.Platform"
$envPath = [Environment]::GetEnvironmentVariable("PATH")
[Environment]::SetEnvironmentVariable("PATH", "$envPath;$installPath", "User")

# Verify
$env:PATH -split ';' | Select-String -Pattern "HELIOS"
```

---

## 📊 Monitoring After Deployment

### Real-Time Status

```powershell
# One-time status check
HELIOS.Platform.exe status

# Continuous monitoring (every 5 seconds)
while ($true) {
    Clear-Host
    Write-Host "HELIOS Platform Status - $(Get-Date)" -ForegroundColor Green
    HELIOS.Platform.exe status
    Write-Host "---"
    Start-Sleep -Seconds 5
}
```

### Event Log Monitoring

```powershell
# View HELIOS-related events
Get-EventLog -LogName Application -Source "*HELIOS*" -Newest 10 | Format-List

# Filter by severity
Get-EventLog -LogName Application -Source "*HELIOS*" -EntryType Error | Format-List
```

### Windows Task Scheduler (Optional)

```powershell
# Create scheduled task for periodic status checks
$action = New-ScheduledTaskAction -Execute "HELIOS.Platform.exe" -Argument "status"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserID "NT AUTHORITY\SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName "HELIOS Platform Monitor" `
    -Action $action -Trigger $trigger -Principal $principal
```

---

## ✅ Post-Deployment Validation

### Checklist

- [ ] All 7 components initialized
- [ ] Deployment status shows "Ready"
- [ ] No error events in Windows Event Log
- [ ] Performance metrics within normal range
- [ ] Security policies applied successfully
- [ ] All features accessible
- [ ] Rollback capability verified
- [ ] Documentation reviewed by team

### Acceptance Criteria

| Criterion | Expected Result |
|-----------|-----------------|
| Validation | ✓ Pass |
| Deployment Time | < 30 seconds (Standard), < 60 seconds (Professional), < 120 seconds (Enterprise) |
| Error Count | 0 |
| Component Status | All Healthy |
| System Stability | Stable (no crashes after 24 hours) |
| Rollback Time | < 5 minutes |

---

## 📞 Support & Escalation

### Support Levels

| Level | Contact | Response Time |
|-------|---------|----------------|
| L1 | Documentation | Immediate |
| L2 | GitHub Issues | 24 hours |
| L3 | Community Forum | 48 hours |
| L4 | Enterprise Support | 4 hours |

### Collecting Debug Information

```powershell
# Generate diagnostic report
$report = @{
    "Timestamp" = Get-Date
    "OS" = [System.Environment]::OSVersion
    "DotNet" = dotnet --version
    "InstallPath" = "C:\Program Files\HELIOS.Platform"
    "Files" = Get-ChildItem "C:\Program Files\HELIOS.Platform"
    "RecentEvents" = Get-EventLog -LogName Application -Source "*HELIOS*" -Newest 20
    "Status" = & "C:\Program Files\HELIOS.Platform\HELIOS.Platform.exe" status
}

# Save report
$report | Out-File -FilePath "helios-diagnostic-report.txt"
```

---

**Document Version:** 1.0
**Last Updated:** 2024
**Next Review:** Q2 2024
