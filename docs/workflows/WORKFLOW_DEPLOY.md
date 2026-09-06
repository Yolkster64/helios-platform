# Deployment Workflow - deploy.yml

## Overview

The `deploy.yml` workflow manages phase-based deployments to Azure environments. It supports multiple environments (development, staging, production) and deployment phases with validation and testing.

**File**: `.github/workflows/deploy.yml`  
**Trigger**: Manual workflow dispatch only  
**Duration**: 15-30 minutes  
**Runner**: ubuntu-latest  
**Environments**: development, staging, production

---

## Table of Contents

1. [Workflow Purpose](#workflow-purpose)
2. [Deployment Architecture](#deployment-architecture)
3. [Workflow Dispatch Inputs](#workflow-dispatch-inputs)
4. [Phase Management](#phase-management)
5. [Job Workflow](#job-workflow)
6. [Deployment Steps](#deployment-steps)
7. [Environment Configuration](#environment-configuration)
8. [Testing & Validation](#testing--validation)
9. [Rollback Procedures](#rollback-procedures)
10. [Troubleshooting](#troubleshooting)

---

## Workflow Purpose

**Goals**:

- ✅ Deploy phases to target environments
- ✅ Validate deployment configuration
- ✅ Execute post-deployment tests
- ✅ Track deployment status
- ✅ Enable rollback capability
- ✅ Notify deployment completion
- ✅ Maintain deployment history

**Scope**: Azure infrastructure deployment for HELIOS Platform

---

## Deployment Architecture

### Phase Structure

```
Phases/
├── 0-foundation/          # Core infrastructure
│   ├── README.md
│   ├── build.ps1
│   ├── MANIFEST.json
│   └── resources/
├── 1-security/            # Security configuration
│   ├── README.md
│   ├── build.ps1
│   ├── MANIFEST.json
│   └── resources/
├── 2-optimization/        # Performance tuning
│   ├── README.md
│   ├── build.ps1
│   ├── MANIFEST.json
│   └── resources/
└── 3-capability/          # Feature deployment
    ├── README.md
    ├── build.ps1
    ├── MANIFEST.json
    └── resources/
```

### Environment Structure

```
Environments:
├── Development (dev)      # Testing environment
│   ├── Resource Group: helios-development
│   ├── Region: eastus
│   └── Tier: Standard
├── Staging (staging)      # Pre-production
│   ├── Resource Group: helios-staging
│   ├── Region: eastus2
│   └── Tier: Standard
└── Production (prod)      # Production
    ├── Resource Group: helios-production
    ├── Region: westus
    └── Tier: Premium
```

---

## Workflow Dispatch Inputs

### Manual Trigger Configuration

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        type: choice
        options:
          - 'development'
          - 'staging'
          - 'production'
      phase:
        description: 'Phase to deploy'
        required: true
        type: choice
        options:
          - '0-foundation'
          - '1-security'
          - '2-optimization'
          - '3-capability'
```

### Deployment Matrix

| Environment | Phase | Approval Required | Duration |
|---|---|---|---|
| development | Any | ❌ No | 5-10 min |
| staging | 0-foundation, 1-security | ✅ Yes | 10-15 min |
| staging | 2-optimization, 3-capability | ✅ Yes | 15-20 min |
| production | 0-foundation | ✅✅ Yes | 20-30 min |
| production | 1-3 | ✅✅ Yes | 25-35 min |

---

## Phase Management

### Phase 0: Foundation

```powershell
# Purpose: Core infrastructure setup
# Creates:
# - Resource groups
# - Storage accounts
# - Networking
# - Basic compute resources

phases/0-foundation/build.ps1
```

**Manifest** (`MANIFEST.json`):

```json
{
  "phase": "0-foundation",
  "version": "1.0.0",
  "requires": [],
  "resources": [
    "resourceGroup",
    "storageAccount",
    "virtualNetwork",
    "subnet"
  ],
  "estimatedTime": 600,
  "costEstimate": "$50/month"
}
```

### Phase 1: Security

```powershell
# Purpose: Security configuration
# Configures:
# - Key Vault
# - Identity providers
# - Network security
# - Secrets management

phases/1-security/build.ps1
```

**Prerequisite**: Phase 0 must be deployed

### Phase 2: Optimization

```powershell
# Purpose: Performance and reliability
# Sets up:
# - Caching
# - CDN
# - Load balancing
# - Auto-scaling

phases/2-optimization/build.ps1
```

**Prerequisite**: Phases 0 and 1 must be deployed

### Phase 3: Capability

```powershell
# Purpose: Feature deployment
# Deploys:
# - Application code
# - Service configurations
# - Monitoring
# - Logging

phases/3-capability/build.ps1
```

**Prerequisite**: Phases 0, 1, and 2 must be deployed

---

## Job Workflow

### Job 1: Deploy

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    name: Deploy Phase ${{ inputs.phase }} to ${{ inputs.environment }}
    steps:
      - Checkout
      - Setup Azure CLI
      - Setup PowerShell
      - Azure Login
      - Prepare Deployment
      - Validate Configuration
      - Deploy to Azure
```

**Execution**:

```
1. Checkout Repository
   └─ Get current code and phase scripts

2. Setup Azure CLI
   └─ Install Azure command-line tools

3. Setup PowerShell
   └─ Install PowerShell environment

4. Azure Login
   └─ Authenticate with Azure using credentials

5. Prepare Deployment
   └─ Check phase directory exists
   └─ Verify required files present

6. Validate Configuration
   └─ Check required files:
      - phases/<phase>/README.md
      - phases/<phase>/build.ps1
      - phases/<phase>/MANIFEST.json

7. Deploy to Azure
   └─ Execute phase build script
   └─ Deploy resources to environment
```

### Job 2: Test Deployment

```yaml
jobs:
  test-deployment:
    runs-on: ubuntu-latest
    needs: deploy
    name: Test Deployment
    steps:
      - Checkout
      - Run Deployment Tests
```

**Tests**:

- Verify resources created
- Check resource health
- Validate connectivity
- Confirm configuration

### Job 3: Notify Status

```yaml
jobs:
  notify-completion:
    runs-on: ubuntu-latest
    if: always()
    needs: [deploy, test-deployment]
    name: Notify Deployment Status
    steps:
      - Success Notification (if success)
      - Failure Notification (if failure)
```

---

## Deployment Steps

### Azure Login

```yaml
- name: Azure Login
  uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}
```

**Setup AZURE_CREDENTIALS**:

```bash
# Create service principal
az ad sp create-for-rbac --name "helios-deploy" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}

# Output JSON (save as secret):
{
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "...",
  "tenantId": "..."
}
```

### Prepare Deployment

```powershell
$phaseDir = "phases/${{ inputs.phase }}"
if (-not (Test-Path $phaseDir)) {
    throw "Phase directory not found: $phaseDir"
}
Write-Host "✅ Phase directory verified"
```

### Validate Configuration

```powershell
$requiredFiles = @(
    "phases/${{ inputs.phase }}/README.md",
    "phases/${{ inputs.phase }}/build.ps1",
    "phases/${{ inputs.phase }}/MANIFEST.json"
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        Write-Host "⚠️  Missing: $file"
    }
}
```

### Execute Deployment

```powershell
# Deploy ARM template
az deployment group create `
  --resource-group "helios-${{ inputs.environment }}" `
  --template-file "phases/${{ inputs.phase }}/template.json" `
  --parameters "phases/${{ inputs.phase }}/parameters.json"

# Or execute build script
& "phases/${{ inputs.phase }}/build.ps1" `
  -Environment "${{ inputs.environment }}" `
  -Verbose
```

---

## Environment Configuration

### Azure Environment Setup

```powershell
# Development
New-AzResourceGroup `
  -Name "helios-development" `
  -Location "eastus"

# Staging
New-AzResourceGroup `
  -Name "helios-staging" `
  -Location "eastus2"

# Production
New-AzResourceGroup `
  -Name "helios-production" `
  -Location "westus"
```

### Required Secrets

```
AZURE_CREDENTIALS    # Service principal credentials
AZURE_SUBSCRIPTION   # Subscription ID
AZURE_TENANT_ID      # Tenant ID
```

### Environment Protection Rules

(In GitHub repository settings)

```yaml
Development:
  - Required status checks: None
  - Require approval: No
  - Restrict who can deploy: All users

Staging:
  - Required status checks: All
  - Require approval: Yes
  - Restrict who can deploy: Team leads

Production:
  - Required status checks: All
  - Require approval: Yes (2 reviewers)
  - Restrict who can deploy: Release manager
  - Require up-to-date branches: Yes
```

---

## Testing & Validation

### Post-Deployment Tests

```powershell
# tests/deployment-tests.ps1
if (Test-Path "tests/deployment-tests.ps1") {
    & "tests/deployment-tests.ps1" `
        -Environment "${{ inputs.environment }}" `
        -Phase "${{ inputs.phase }}"
}
```

### Test Examples

```powershell
# Check resource exists
$resource = Get-AzResource -Name "myapp" -ResourceType "Microsoft.Compute/virtualMachines"
if ($resource) {
    Write-Host "✓ VM deployed"
} else {
    Write-Host "✗ VM deployment failed"
    exit 1
}

# Check connectivity
$test = Test-NetConnection -ComputerName "myapp.azurewebsites.net" -Port 443
if ($test.TcpTestSucceeded) {
    Write-Host "✓ HTTPS accessible"
} else {
    Write-Host "✗ HTTPS not accessible"
    exit 1
}

# Check health endpoint
$health = Invoke-WebRequest "https://myapp/health"
if ($health.StatusCode -eq 200) {
    Write-Host "✓ Application healthy"
} else {
    Write-Host "✗ Application unhealthy"
    exit 1
}
```

---

## Rollback Procedures

### Automatic Rollback

```yaml
- name: Rollback on Failure
  if: failure()
  run: |
    Write-Host "Rolling back deployment..."
    # Execute rollback logic
    az deployment group create \
      --resource-group "helios-${{ inputs.environment }}" \
      --template-file "phases/${{ inputs.phase }}/rollback.json"
```

### Manual Rollback

```bash
# List previous deployments
az deployment group list \
  --resource-group "helios-staging" \
  --query "[].{name:name, state:properties.provisioningState}" \
  --output table

# Redeploy previous version
az deployment group create \
  --resource-group "helios-staging" \
  --template-file "phases/0-foundation/template.json" \
  --parameters "version=1.0.0"
```

### Rollback Strategy

1. **Within 5 minutes**: Automatic rollback via workflow
2. **5-30 minutes**: Manual rollback via Azure CLI
3. **30+ minutes**: Contact infrastructure team

---

## Troubleshooting

### Authentication Failures

| Error | Cause | Solution |
|---|---|---|
| `401 Unauthorized` | Invalid credentials | Update AZURE_CREDENTIALS |
| `403 Forbidden` | Insufficient permissions | Grant contributor role |
| `Subscription not found` | Wrong subscription ID | Verify AZURE_SUBSCRIPTION |

### Deployment Failures

| Error | Cause | Solution |
|---|---|---|
| `Phase directory not found` | Wrong phase name | Check phase directory |
| `Resource already exists` | Name conflict | Use unique naming |
| `Quota exceeded` | Resource limit | Increase quota or delete |
| `Deployment timeout` | Long-running operation | Increase timeout |

### Validation Failures

| Error | Cause | Solution |
|---|---|---|
| `Schema validation error` | Invalid ARM template | Validate template JSON |
| `Parameter not provided` | Missing required parameter | Check parameters file |
| `Resource type not supported` | Unsupported resource | Use supported type |

---

## Best Practices

✅ **Do**:

- Test in development first
- Use staging for pre-prod validation
- Document all deployments
- Keep rollback scripts updated
- Monitor post-deployment
- Version your phases
- Use approval gates

❌ **Don't**:

- Deploy directly to production without testing
- Skip validation steps
- Hardcode environment-specific values
- Deploy during peak hours
- Ignore deployment warnings
- Disable automatic rollback

---

## References

- [Azure Deployments](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/)
- [Azure CLI Reference](https://docs.microsoft.com/en-us/cli/azure/)
- [GitHub Actions Azure Login](https://github.com/Azure/login)
- [ARM Template Reference](https://docs.microsoft.com/en-us/azure/templates/)

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Status**: Active ✅
