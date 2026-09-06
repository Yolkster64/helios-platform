# HELIOS Platform - Guide for DevOps

**Document Version:** 1.0  
**Date:** April 13, 2026  
**Audience:** DevOps Engineers, Infrastructure Teams

## Overview

DevOps manages the complete pipeline from code to production, including CI/CD, deployment, monitoring, and infrastructure.

## Core Infrastructure

### Architecture

```
GitHub (Source) → GitHub Actions (CI/CD) → Artifacts → Deploy
                                            ↓
                                        NuGet.org
                                            ↓
                                    Production Systems
                                            ↓
                                        Dashboard (Monitor)
```

### Deployment Targets

**Supported:**

- Windows 11 Pro/Enterprise
- Windows Server 2022+
- Azure VMs
- Hybrid environments
- Air-gapped systems

**Requirements:**

- .NET 6.0+
- PowerShell 7.0+
- 4GB RAM minimum
- 2GB disk space
- Internet connectivity (optional)

## CI/CD Pipeline

### Build Pipeline

**Trigger Events:**

- Push to main branch
- Pull request creation
- Manual dispatch

**Pipeline Stages:**

```
1. Checkout Code (1 min)
   └─ Fetch source from GitHub

2. Setup Environment (2 min)
   └─ Install .NET SDK
   └─ Restore NuGet packages

3. Build Code (2 min)
   └─ dotnet build -c Release

4. Run Tests (10 min)
   └─ dotnet test with coverage
   └─ Generate coverage reports

5. Create Package (2 min)
   └─ dotnet pack

6. Upload Artifacts (1 min)
   └─ Store in GitHub Actions

Total Time: ~18 minutes
```

### Deployment Pipeline

**Trigger Events:**

- Release tag created
- Manual trigger
- Scheduled (optional)

**Pipeline Stages:**

```
1. Get Artifacts (2 min)
   └─ Download from storage

2. Deploy to Staging (5 min)
   └─ Deploy Phase 0-3
   └─ Run health checks

3. Run Integration Tests (5 min)
   └─ Full end-to-end testing

4. Deploy to Production (5 min)
   └─ Rolling deployment
   └─ Health checks

5. Verify & Report (3 min)
   └─ Confirmation checks
   └─ Metrics collection

Total Time: ~20 minutes
```

## Deployment Commands

### Deploy to Single System

```powershell
# Deploy latest release
.\scripts\deploy.ps1 -Environment Production

# Deploy specific version
.\scripts\deploy.ps1 -Environment Production -Version 2.0.1

# Deploy to specific system
.\scripts\deploy.ps1 -Environment Production -TargetSystem "SERVER01"

# Dry run (validation only)
.\scripts\deploy.ps1 -Environment Production -WhatIf
```

### Deploy to Multiple Systems

```powershell
# Deploy to all prod systems
.\scripts\deploy.ps1 -Environment Production -TargetAll

# Deploy to specific group
.\scripts\deploy.ps1 -Environment Production -TargetGroup "East-Coast"

# Deploy in waves (5% at a time)
.\scripts\deploy.ps1 -Environment Production -Canary $true -CanaryPercentage 5
```

### Rollback Command

```powershell
# Rollback on single system
.\scripts\rollback.ps1 -TargetSystem "SERVER01"

# Rollback on all systems
.\scripts\rollback.ps1 -TargetAll

# Rollback to specific version
.\scripts\rollback.ps1 -Version 2.0.0
```

## Monitoring & Operations

### Health Checks

```powershell
# Daily health check
.\scripts\health-check.ps1

# Detailed diagnostics
.\scripts\health-check.ps1 -Verbose -FullDiagnostics

# Performance analysis
.\scripts\performance-check.ps1

# Security audit
.\scripts\security-audit.ps1
```

### Key Metrics to Monitor

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| CPU Usage | <40% | 60% | >80% |
| Memory | <70% | 85% | >95% |
| Disk Free | >30% | 20% | <10% |
| Service Uptime | 99.9%+ | 99% | <99% |
| Deployment Success | 98%+ | 95% | <95% |

### Alert Thresholds

```powershell
# CPU Alert (trigger if >80% for 5 min)
New-Alert -Name "HighCPU" -Threshold 80 -Duration 5

# Memory Alert (trigger if >95%)
New-Alert -Name "HighMemory" -Threshold 95

# Deployment Failure Alert
New-Alert -Name "DeployFail" -Condition "Status == Failed"

# Service Down Alert
New-Alert -Name "ServiceDown" -Condition "HealthStatus == Down"
```

## GitHub Secrets Configuration

**Required Secrets for CI/CD:**

```
NUGET_API_KEY          # For NuGet.org publishing
AZURE_CREDENTIALS      # For Azure deployments (if used)
DEPLOY_TOKEN           # For deployment authentication
SLACK_WEBHOOK          # For Slack notifications
PAGERDUTY_KEY          # For PagerDuty alerts
```

**Set Secrets in GitHub:**

1. Go to Settings → Secrets
2. Click "New repository secret"
3. Name: [SECRET_NAME]
4. Value: [secret_value]
5. Save

## Performance Tuning

### Build Optimization

```yaml
# In .github/workflows/build.yml
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dotnet-version: ['6.0', '7.0', '8.0']
    steps:
      - uses: actions/cache@v2  # Cache dependencies
        with:
          path: ~/.nuget/packages
          key: ${{ runner.os }}-nuget-${{ hashFiles('**/packages.lock.json') }}
```

### Artifact Caching

```powershell
# Cache build artifacts (save bandwidth)
New-ArtifactCache -Name "Release-Build" -MaxAge 30 -Size 5GB
```

### Pipeline Parallelization

```yaml
# Run tests in parallel on 4 runners
strategy:
  matrix:
    test-platform: [win2022, ubuntu-latest, macos-latest]
  max-parallel: 4
```

## Disaster Recovery

### Backup Strategy

**Automated Backups:**

- Frequency: Daily (incremental) + Weekly (full)
- Retention: 30 days daily, 90 days weekly
- Location: On-site + Cloud (geo-redundant)
- Testing: Weekly restore tests

### Restore Procedures

**Full System Restore:**

```powershell
# List available backups
Get-BackupList | Sort-Object Date -Descending

# Restore from latest backup
Restore-SystemBackup -Backup "Full-2026-04-13"

# Verify restoration
Test-SystemIntegrity -Verbose
```

**Partial Recovery:**

```powershell
# Restore specific application
Restore-AppBackup -Backup "Full-2026-04-13" -App "HELIOS"

# Restore user data
Restore-DataBackup -Backup "Full-2026-04-13" -Path "D:\Data"
```

## Infrastructure Scaling

### Auto-scaling Rules

```powershell
# Enable auto-scaling for deployments
Enable-AutoScaling -MinInstances 1 -MaxInstances 10 -TargetCPU 70

# Scale by custom metric
New-ScalingRule -Metric "DeploymentQueue" -TargetValue 5 -ScaleUpBy 2
```

### Load Balancing

```powershell
# Setup load balancer
New-LoadBalancer -Name "HELIOS-LB" -Algorithm "RoundRobin"

# Add targets to balancer
Add-LBTarget -LoadBalancer "HELIOS-LB" -Targets @("SERVER01", "SERVER02", "SERVER03")
```

## Security & Compliance

### Vulnerability Scanning

```powershell
# Scan for known vulnerabilities
Scan-Vulnerabilities -PackageFile "packages.lock.json"

# Generate compliance report
New-ComplianceReport -Format "PDF" -OutputPath "compliance.pdf"
```

### Access Control

**CI/CD Permissions:**

- [ ] Limited service account access
- [ ] Multi-factor authentication enabled
- [ ] Audit logging active
- [ ] Least privilege principle

### Secret Management

```powershell
# Rotate secrets monthly
Set-GitHubSecret -Name "NUGET_API_KEY" -Value $newSecret

# Audit secret access
Get-AuditLog -EventType "SecretAccess" -Days 30
```

## Troubleshooting

### Build Failure Debugging

```powershell
# Check build logs
Get-BuildLog -RunID 12345

# Retry failed build
Retry-Build -RunID 12345

# Clear cache and rebuild
Clear-BuildCache -Repository "helios-platform"
Invoke-Build -Repository "helios-platform" -FreshCache
```

### Deployment Issues

```powershell
# Check deployment status
Get-DeploymentStatus -TargetSystem "SERVER01"

# Review deployment logs
Get-DeploymentLog -TargetSystem "SERVER01" -LastHours 24

# Attempt automatic recovery
Invoke-AutoRecovery -TargetSystem "SERVER01"
```

### Network Connectivity

```powershell
# Test GitHub connectivity
Test-Connection github.com

# Test NuGet connectivity
Test-Connection nuget.org -Port 443

# Test Azure connectivity
Test-AzureConnection
```

## Operational Procedures

### Weekly Maintenance

```powershell
# 1. Backup verification (30 min)
Test-BackupRestoration -BackupName "Full-Weekly"

# 2. Security review (30 min)
Review-SecurityLogs -Days 7

# 3. Performance analysis (30 min)
Analyze-Performance -Period "Week"

# 4. Capacity planning (30 min)
Review-Capacity -Projection "Month"
```

### Monthly Operations Review

```powershell
# Generate monthly report
New-OperationsReport -Period "Month" -OutputFormat "HTML"

# Includes:
# - Uptime metrics
# - Performance trends
# - Deployment statistics
# - Security status
# - Cost analysis
```

## Quick Reference

### Critical Commands

```
Build:    dotnet build -c Release
Test:     dotnet test /p:CollectCoverage=true
Package:  dotnet pack
Deploy:   .\scripts\deploy.ps1 -Environment Production
Rollback: .\scripts\rollback.ps1
Monitor:  Start-DashboardMonitoring
Health:   .\scripts\health-check.ps1
```

### Important URLs

- GitHub Actions: https://github.com/your-org/helios-platform/actions
- NuGet Package: https://www.nuget.org/packages/HELIOS.Platform/
- Dashboard: https://dashboard.helios-platform.org
- Documentation: https://your-org.github.io/helios-platform

### Escalation Contacts

- **Build Issues:** DevOps Team Slack
- **Deployment Issues:** On-call DevOps Engineer
- **Infrastructure:** Infrastructure Team
- **Security:** Security Officer

---

**Status: ✅ READY FOR DEVOPS OPERATIONS**
