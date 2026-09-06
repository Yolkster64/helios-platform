# HELIOS CLI Reference

**Version:** 1.0.0  
**Last Updated:** 2024  
**Target Audience:** Administrators, DevOps engineers, automation specialists

---

## Table of Contents

1. [Overview](#overview)
2. [General Syntax](#general-syntax)
3. [Deployment Commands](#deployment-commands)
4. [AI Service Commands](#ai-service-commands)
5. [Monitoring Commands](#monitoring-commands)
6. [Security Commands](#security-commands)
7. [Agent Commands](#agent-commands)
8. [Configuration Commands](#configuration-commands)
9. [Troubleshooting Commands](#troubleshooting-commands)
10. [Output Formats](#output-formats)

---

## Overview

HELIOS CLI provides comprehensive command-line interface for all platform operations. Commands follow standard PowerShell conventions.

**Installation:**

```powershell
Import-Module HELIOS.CLI
```

**Get Help:**

```powershell
Get-Help Get-HeliosDeployment -Full
```

---

## General Syntax

### Command Structure

```powershell
Verb-HeliosNoun -Parameter1 Value1 -Parameter2 Value2 -Flag
```

### Common Parameters

```powershell
-Verbose          # Show detailed output
-WhatIf           # Simulate operation without executing
-Confirm          # Require confirmation before executing
-OutputFormat     # Format for output (Json, Csv, Table, Xml)
-Wait             # Wait for operation to complete
-Timeout          # Operation timeout in seconds
```

### Examples

```powershell
# Show all deployments in JSON format
Get-HeliosDeployment -OutputFormat Json

# Create deployment with confirmation
New-HeliosDeployment -Name "prod-1" -Tier Enterprise -Confirm

# Simulate security update
Set-HeliosSecurityPolicy -Policy "SOC2" -WhatIf

# Stream logs in real-time
Get-HeliosLogStream -Component "AI-Service" -Follow
```

---

## Deployment Commands

### Get-HeliosDeployment

**Description:** List all deployments or get specific deployment details

**Syntax:**

```powershell
Get-HeliosDeployment [-Name <String>] [-Status <String>] [-Region <String>] 
                     [-OutputFormat <String>] [-Verbose]
```

**Parameters:**

- `-Name`: Filter by deployment name
- `-Status`: Filter by status (Running, Completed, Failed, Rollback)
- `-Region`: Filter by region
- `-OutputFormat`: Output format (Json, Csv, Table, Xml)

**Examples:**

```powershell
# List all deployments
Get-HeliosDeployment

# Get specific deployment
Get-HeliosDeployment -Name "prod-1"

# Get failed deployments
Get-HeliosDeployment -Status Failed

# Output as JSON
Get-HeliosDeployment -OutputFormat Json | ConvertTo-Json

# Filter by region
Get-HeliosDeployment -Region "eastus"
```

**Output Example:**

```
Name           Status     Tier        Region   CreatedAt            Progress
----           ------     ----        ------   ---------            --------
prod-1         Running    Enterprise  eastus   2024-01-15 10:30:00  75%
dev-1          Completed  Standard    westus   2024-01-14 09:15:00  100%
test-1         Failed     Lite        eastus   2024-01-13 14:22:00  40%
```

---

### New-HeliosDeployment

**Description:** Create new deployment

**Syntax:**

```powershell
New-HeliosDeployment -Name <String> -Tier <String> [-Region <String>] 
                     [-Environment <String>] [-Config <Object>] 
                     [-Wait] [-Timeout <Int32>] [-WhatIf] [-Confirm]
```

**Parameters:**

- `-Name`: Deployment name (required)
- `-Tier`: Deployment tier (Lite, Standard, Enterprise) (required)
- `-Region`: Azure region (default: eastus)
- `-Environment`: Environment name (Production, Staging, Development)
- `-Config`: Configuration object or JSON path
- `-Wait`: Wait for completion
- `-Timeout`: Timeout in seconds

**Examples:**

```powershell
# Create enterprise deployment
New-HeliosDeployment -Name "prod-1" -Tier Enterprise -Region "eastus" -Wait

# Create with custom configuration
$config = @{
    autoScaling = $true
    maxInstances = 10
    minInstances = 2
}
New-HeliosDeployment -Name "prod-2" -Tier Standard -Config $config

# Simulate deployment
New-HeliosDeployment -Name "test-1" -Tier Lite -WhatIf

# Create with confirmation
New-HeliosDeployment -Name "prod-3" -Tier Enterprise -Confirm
```

**Output Example:**

```
DeploymentId : 550e8400-e29b-41d4-a716-446655440000
Name         : prod-1
Status       : Running
Tier         : Enterprise
Region       : eastus
CreatedAt    : 2024-01-15 10:30:00
EstimatedTime: 35 minutes
```

---

### Set-HeliosDeployment

**Description:** Update deployment configuration

**Syntax:**

```powershell
Set-HeliosDeployment -Name <String> -Config <Object> 
                     [-Wait] [-WhatIf] [-Confirm]
```

**Examples:**

```powershell
# Update scaling configuration
$config = @{ maxInstances = 20; minInstances = 5 }
Set-HeliosDeployment -Name "prod-1" -Config $config -Wait

# Disable auto-scaling
Set-HeliosDeployment -Name "prod-1" -Config @{ autoScaling = $false }
```

---

### Remove-HeliosDeployment

**Description:** Delete deployment

**Syntax:**

```powershell
Remove-HeliosDeployment -Name <String> [-Force] [-WhatIf] [-Confirm]
```

**Parameters:**

- `-Force`: Skip confirmation
- `-WhatIf`: Show what would be deleted

**Examples:**

```powershell
# Delete deployment with confirmation
Remove-HeliosDeployment -Name "test-1"

# Force delete without confirmation
Remove-HeliosDeployment -Name "test-1" -Force

# Show what would be deleted
Remove-HeliosDeployment -Name "test-1" -WhatIf
```

---

### Start-HeliosDeployment

**Description:** Start deployment phase

**Syntax:**

```powershell
Start-HeliosDeployment -Name <String> -Phase <Int32> [-Wait] [-Timeout <Int32>]
```

**Parameters:**

- `-Name`: Deployment name (required)
- `-Phase`: Phase number (0-6) (required)
- `-Wait`: Wait for completion
- `-Timeout`: Timeout in seconds

**Phases:**

- Phase 0: Pre-flight checks
- Phase 1: Infrastructure
- Phase 2: Agent Fleet
- Phase 3: AI Services
- Phase 4: Security
- Phase 5: Monitoring
- Phase 6: Verification

**Examples:**

```powershell
# Start phase 1
Start-HeliosDeployment -Name "prod-1" -Phase 1 -Wait

# Start phase 2 with 30-minute timeout
Start-HeliosDeployment -Name "prod-1" -Phase 2 -Wait -Timeout 1800
```

---

### Get-HeliosDeploymentStatus

**Description:** Get detailed deployment status

**Syntax:**

```powershell
Get-HeliosDeploymentStatus -Name <String> [-Verbose]
```

**Examples:**

```powershell
# Get deployment status
Get-HeliosDeploymentStatus -Name "prod-1"

# Get verbose status with details
Get-HeliosDeploymentStatus -Name "prod-1" -Verbose
```

**Output Example:**

```
Deployment     : prod-1
Status         : Running
Phase          : 3
PhaseProgress  : 60%
OverallProgress: 42%
CurrentTask    : Registering AI Services
EstimatedTime  : 20 minutes remaining
Phase0-Checks  : ✅ Passed (10/10)
Phase1-Infra   : ✅ Completed
Phase2-Agents  : ✅ Completed
Phase3-AI      : 🔄 In Progress (6/10 services)
Phase4-Security: ⏳ Pending
Phase5-Monitor : ⏳ Pending
Phase6-Verify  : ⏳ Pending
```

---

## AI Service Commands

### Get-HeliosAIService

**Description:** List AI services or get service details

**Syntax:**

```powershell
Get-HeliosAIService [-Name <String>] [-Status <String>] 
                    [-Tier <String>] [-OutputFormat <String>]
```

**Parameters:**

- `-Name`: Service name filter
- `-Status`: Service status (Active, Inactive, Error)
- `-Tier`: Service tier (Tier1-Free, Tier2-Standard, Tier3-Specialist)

**Examples:**

```powershell
# List all services
Get-HeliosAIService

# Get specific service
Get-HeliosAIService -Name "azure-openai"

# Get active tier 2 services
Get-HeliosAIService -Status Active -Tier "Tier2-Standard"

# Output as JSON
Get-HeliosAIService -OutputFormat Json
```

**Output Example:**

```
Name            Status  Tier               Requests  AvgLatency  CacheHit
----            ------  ----               --------  ----------  --------
azure-openai    Active  Tier2-Standard     15,234    245ms       72%
claude          Active  Tier2-Standard     8,945     380ms       61%
ollama          Active  Tier1-Free         12,456    156ms       85%
gemini          Active  Tier1-Free         4,321     523ms       45%
```

---

### Set-HeliosAIModel

**Description:** Configure primary AI model

**Syntax:**

```powershell
Set-HeliosAIModel -Model <String> [-RoutingStrategy <String>] 
                  [-Fallbacks <String[]>] [-CachingEnabled <Boolean>]
```

**Parameters:**

- `-Model`: Primary model name (required)
- `-RoutingStrategy`: CostOptimized, PerformanceOptimized, BalancedOptimized
- `-Fallbacks`: Array of fallback model names
- `-CachingEnabled`: Enable request caching

**Examples:**

```powershell
# Set primary model to Azure OpenAI
Set-HeliosAIModel -Model "azure-openai"

# Set cost-optimized routing with fallbacks
Set-HeliosAIModel -Model "ollama" -RoutingStrategy CostOptimized `
                  -Fallbacks @("gemini", "azure-openai")

# Enable caching
Set-HeliosAIModel -CachingEnabled $true
```

---

### Get-HeliosAIMetrics

**Description:** Get AI service performance metrics

**Syntax:**

```powershell
Get-HeliosAIMetrics [-Service <String>] [-Period <String>] 
                    [-OutputFormat <String>]
```

**Parameters:**

- `-Service`: Service name
- `-Period`: Time period (Hour, Day, Week, Month)

**Examples:**

```powershell
# Get metrics for all services
Get-HeliosAIMetrics -Period Day

# Get Azure OpenAI metrics for this month
Get-HeliosAIMetrics -Service "azure-openai" -Period Month

# Output as JSON
Get-HeliosAIMetrics -OutputFormat Json
```

**Output Example:**

```
Service         Requests  AvgLatency  P95Latency  CacheHit  Cost
-------         --------  ----------  ----------  --------  ----
azure-openai    15,234    245ms       1200ms      72%       $248
claude          8,945     380ms       1500ms      61%       $195
ollama          12,456    156ms       800ms       85%       $0
gemini          4,321     523ms       2100ms      45%       $47
```

---

## Monitoring Commands

### Get-HeliosDashboard

**Description:** Retrieve dashboard data

**Syntax:**

```powershell
Get-HeliosDashboard -Name <String> [-Period <String>] 
                    [-OutputFormat <String>]
```

**Dashboard Names:**

- Cost
- Performance
- Security
- Compliance
- AI
- Agents
- System

**Examples:**

```powershell
# Get cost dashboard
Get-HeliosDashboard -Name "Cost"

# Get performance dashboard for this week
Get-HeliosDashboard -Name "Performance" -Period Week

# Get security dashboard as JSON
Get-HeliosDashboard -Name "Security" -OutputFormat Json
```

---

### Get-HeliosMetrics

**Description:** Get system metrics

**Syntax:**

```powershell
Get-HeliosMetrics [-Metric <String>] [-Period <String>] 
                  [-Interval <String>]
```

**Available Metrics:**

- CPU
- Memory
- Disk
- Network
- Latency
- Throughput
- ErrorRate

**Examples:**

```powershell
# Get CPU metrics
Get-HeliosMetrics -Metric "CPU"

# Get memory metrics for the day
Get-HeliosMetrics -Metric "Memory" -Period Day -Interval "5m"

# Get all metrics
Get-HeliosMetrics
```

---

### Get-HeliosAlert

**Description:** Get active alerts

**Syntax:**

```powershell
Get-HeliosAlert [-Severity <String>] [-Status <String>] 
                [-OutputFormat <String>]
```

**Examples:**

```powershell
# Get all active alerts
Get-HeliosAlert

# Get critical alerts
Get-HeliosAlert -Severity Critical

# Get resolved alerts
Get-HeliosAlert -Status Resolved
```

---

### Get-HeliosAuditLog

**Description:** Retrieve audit logs

**Syntax:**

```powershell
Get-HeliosAuditLog [-Last <Int32>] [-Since <DateTime>] 
                   [-Filter <String>] [-OutputFormat <String>]
```

**Examples:**

```powershell
# Get last 100 audit entries
Get-HeliosAuditLog -Last 100

# Get logs from last 24 hours
Get-HeliosAuditLog -Since (Get-Date).AddHours(-24)

# Get security-related logs
Get-HeliosAuditLog -Filter "security" -OutputFormat Json
```

---

## Security Commands

### Get-HeliosSecurityStatus

**Description:** Get security status

**Syntax:**

```powershell
Get-HeliosSecurityStatus [-Verbose]
```

**Examples:**

```powershell
# Get security status
Get-HeliosSecurityStatus

# Get verbose security details
Get-HeliosSecurityStatus -Verbose
```

**Output Example:**

```
Physical        : ✅ Enabled (TPM 2.0, USB Token)
Authentication  : ✅ Enabled (MFA, Entra ID)
Secrets         : ✅ Enabled (Dual Vault)
CodeSigning     : ✅ Enabled (RSA 2048)
Execution       : ✅ Enabled (Docker Quarantine)
Changes         : ✅ Enabled (7-Stage Workflow)
Audit           : ✅ Enabled (WORM Storage)
AI              : ✅ Enabled (Multi-Model Consensus)
ComplianceScore : 98%
```

---

### Set-HeliosSecurityPolicy

**Description:** Update security policy

**Syntax:**

```powershell
Set-HeliosSecurityPolicy -Policy <String> [-Strict <Boolean>] 
                         [-MfaEnabled <Boolean>]
```

**Policy Options:**

- SOC2
- ISO27001
- HIPAA
- PCIDSS
- FedRAMP

**Examples:**

```powershell
# Set SOC2 compliance
Set-HeliosSecurityPolicy -Policy "SOC2"

# Enable strict mode
Set-HeliosSecurityPolicy -Policy "ISO27001" -Strict $true

# Enable MFA
Set-HeliosSecurityPolicy -MfaEnabled $true
```

---

## Agent Commands

### Get-HeliosAgent

**Description:** List deployment agents

**Syntax:**

```powershell
Get-HeliosAgent [-Name <String>] [-Status <String>] 
                [-OutputFormat <String>]
```

**Agent Types:**

- Storage
- Security
- Software
- GUI
- Optimization
- Testing

**Examples:**

```powershell
# List all agents
Get-HeliosAgent

# Get specific agent
Get-HeliosAgent -Name "Storage"

# Get running agents
Get-HeliosAgent -Status Running

# Output as JSON
Get-HeliosAgent -OutputFormat Json
```

**Output Example:**

```
Name           Type        Status    CPU    Memory  Uptime
----           ----        ------    ---    ------  ------
Storage-01     Storage     Running   15%    45%     42 days
Security-01    Security    Running   8%     32%     42 days
Software-01    Software    Running   12%    38%     42 days
GUI-01         GUI         Running   25%    52%     42 days
Optimization   Optimization Running  6%     28%     42 days
Testing-01     Testing     Running   10%    35%     42 days
```

---

### Restart-HeliosAgent

**Description:** Restart agent

**Syntax:**

```powershell
Restart-HeliosAgent -Name <String> [-Wait] [-Timeout <Int32>]
```

**Examples:**

```powershell
# Restart storage agent
Restart-HeliosAgent -Name "Storage-01" -Wait

# Restart with 5-minute timeout
Restart-HeliosAgent -Name "Security-01" -Wait -Timeout 300
```

---

## Configuration Commands

### Get-HeliosConfig

**Description:** Get configuration

**Syntax:**

```powershell
Get-HeliosConfig [-Section <String>] [-OutputFormat <String>]
```

**Sections:**

- Deployment
- Security
- AI
- Monitoring
- Performance

**Examples:**

```powershell
# Get all configuration
Get-HeliosConfig

# Get deployment config
Get-HeliosConfig -Section Deployment

# Get security config as JSON
Get-HeliosConfig -Section Security -OutputFormat Json
```

---

### Set-HeliosConfig

**Description:** Update configuration

**Syntax:**

```powershell
Set-HeliosConfig -Section <String> -Setting <String> -Value <Object> 
                 [-WhatIf]
```

**Examples:**

```powershell
# Set deployment tier
Set-HeliosConfig -Section Deployment -Setting "Tier" -Value "Enterprise"

# Set monitoring interval
Set-HeliosConfig -Section Monitoring -Setting "MetricsInterval" -Value 30

# Simulate change
Set-HeliosConfig -Section AI -Setting "CachingEnabled" -Value $true -WhatIf
```

---

## Troubleshooting Commands

### Get-HeliosLogStream

**Description:** Stream logs in real-time

**Syntax:**

```powershell
Get-HeliosLogStream [-Component <String>] [-Level <String>] 
                    [-Follow] [-Tail <Int32>]
```

**Log Levels:**

- Debug
- Information
- Warning
- Error
- Critical

**Examples:**

```powershell
# Stream all logs
Get-HeliosLogStream -Follow

# Stream error logs from AI service
Get-HeliosLogStream -Component "AI-Service" -Level Error -Follow

# Get last 50 lines from deployment
Get-HeliosLogStream -Component "Deployment" -Tail 50
```

---

### Get-HeliosHealth

**Description:** Check system health

**Syntax:**

```powershell
Get-HeliosHealth [-Verbose]
```

**Examples:**

```powershell
# Quick health check
Get-HeliosHealth

# Detailed health report
Get-HeliosHealth -Verbose
```

**Output Example:**

```
Status            : Healthy
Score             : 95/100
UpSinceLast       : 42 days
Deployments       : 3 (All Running)
Agents            : 6 (All Running)
AIServices        : 12 (All Active)
DiskUsage         : 62%
MemoryUsage       : 48%
CPUUsage          : 18%
AverageLatency    : 245ms
ErrorRate         : 0.02%
```

---

## Output Formats

### JSON Format

```powershell
Get-HeliosDeployment | ConvertTo-Json -Depth 3
```

### CSV Format

```powershell
Get-HeliosDeployment -OutputFormat Csv | Out-File deployments.csv
```

### Table Format (Default)

```powershell
Get-HeliosDeployment -OutputFormat Table | Format-Table
```

### XML Format

```powershell
Get-HeliosDeployment -OutputFormat Xml | Out-File deployments.xml
```

---

## Error Handling

### Common Errors

**Error:** Unauthorized access

```powershell
# Solution: Re-authenticate
Add-HeliosCredential -Interactive
```

**Error:** Deployment not found

```powershell
# Solution: List all deployments
Get-HeliosDeployment -Verbose
```

**Error:** Operation timeout

```powershell
# Solution: Increase timeout
Start-HeliosDeployment -Name "prod-1" -Phase 2 -Timeout 3600
```

---

## Additional Resources

- **User Guide:** [USER_GUIDE_COMPLETE.md](USER_GUIDE_COMPLETE.md)
- **Feature Guide:** [FEATURE_GUIDE.md](FEATURE_GUIDE.md)
- **API Reference:** [API_REFERENCE.md](../API_REFERENCE.md)
- **PowerShell Docs:** https://docs.microsoft.com/en-us/powershell/

---

**Last Updated:** 2024  
**Version:** 1.0.0
