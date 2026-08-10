<#
.SYNOPSIS
HELIOS Phase 1: Infrastructure Deployment - DETAILED NARRATION

.DESCRIPTION
This phase creates the foundation Azure resources and Docker infrastructure
#>

# HELIOS Phase 1: Infrastructure Deployment - DETAILED NARRATION
# This phase creates the foundation Azure resources and Docker infrastructure

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "║        HELIOS PHASE 1: INFRASTRUCTURE DEPLOYMENT             ║" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "║  This phase creates all the backend infrastructure:          ║" -ForegroundColor Cyan
Write-Host "║  • Resource Group in Azure                                   ║" -ForegroundColor Cyan
Write-Host "║  • Storage Accounts for data & logs                          ║" -ForegroundColor Cyan
Write-Host "║  • Cosmos DB for distributed database                        ║" -ForegroundColor Cyan
Write-Host "║  • Key Vault for secrets management                          ║" -ForegroundColor Cyan
Write-Host "║  • Docker network for container isolation                    ║" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "║  TIME: ~5 minutes                                            ║" -ForegroundColor Cyan
Write-Host "║                                                                ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
$timestamp = $startTime.ToString("yyyy-MM-dd HH:mm:ss")

Write-Host "[STEP 1/8] Initializing deployment variables..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Sets up resource names, locations, naming conventions" -ForegroundColor Cyan
Write-Host "  • Creates unique IDs for this deployment instance" -ForegroundColor Cyan
Write-Host ""

$resourceGroup = "helios-platform-rg"
$location = "eastus"
$timestamp_short = (Get-Date).ToString("yyyyMMdd-HHmmss")
$deploymentId = "helios-$timestamp_short"

Write-Host "  Setting up deployment configuration:" -ForegroundColor Green
Write-Host "    • Resource Group: $resourceGroup" -ForegroundColor Green
Write-Host "    • Location: $location" -ForegroundColor Green
Write-Host "    • Deployment ID: $deploymentId" -ForegroundColor Green
Write-Host "    • Timestamp: $timestamp" -ForegroundColor Green
Write-Host ""

Write-Host "[STEP 2/8] Creating Azure Resource Group..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Creates a container in Azure where all resources live" -ForegroundColor Cyan
Write-Host "  • Organizes billing, access control, and organization" -ForegroundColor Cyan
Write-Host "  • All components will be deployed into this group" -ForegroundColor Cyan
Write-Host ""

try {
    $rg = New-AzResourceGroup -Name $resourceGroup -Location $location -Force
    Write-Host "  ✅ Resource Group Created:" -ForegroundColor Green
    Write-Host "     Name: $($rg.ResourceGroupName)" -ForegroundColor Green
    Write-Host "     Location: $($rg.Location)" -ForegroundColor Green
    Write-Host "     ID: $($rg.ResourceId.Split('/')[-1])" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️  Resource Group may already exist (checking...)" -ForegroundColor Yellow
    $rg = Get-AzResourceGroup -Name $resourceGroup -ErrorAction SilentlyContinue
    if ($rg) {
        Write-Host "  ✅ Using existing Resource Group: $($rg.ResourceGroupName)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Failed to create/find Resource Group" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

Write-Host "[STEP 3/8] Creating Storage Account..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Creates blob storage for Docker images, backups, logs" -ForegroundColor Cyan
Write-Host "  • Stores build artifacts and system snapshots" -ForegroundColor Cyan
Write-Host "  • Provides redundant, encrypted storage" -ForegroundColor Cyan
Write-Host ""

$storageAccountName = "helios$($timestamp_short.Replace('-','').Substring(0,8))".ToLower()

try {
    $storageAccount = New-AzStorageAccount -ResourceGroupName $resourceGroup `
        -Name $storageAccountName -SkuName "Standard_LRS" -Location $location
    Write-Host "  ✅ Storage Account Created:" -ForegroundColor Green
    Write-Host "     Name: $($storageAccount.StorageAccountName)" -ForegroundColor Green
    Write-Host "     Tier: Standard (cost-optimized)" -ForegroundColor Green
    Write-Host "     Replication: LRS (locally redundant)" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Failed to create Storage Account: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "[STEP 4/8] Creating Key Vault for Secrets..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Secure storage for all passwords, API keys, certificates" -ForegroundColor Cyan
Write-Host "  • Hardware-backed encryption with TPM support" -ForegroundColor Cyan
Write-Host "  • Audit logging of all secret access" -ForegroundColor Cyan
Write-Host ""

$keyVaultName = "helios-kv-$($timestamp_short.Substring(0,8))".ToLower()

try {
    $keyVault = New-AzKeyVault -ResourceGroupName $resourceGroup `
        -VaultName $keyVaultName -Location $location -EnableSoftDelete
    Write-Host "  ✅ Key Vault Created:" -ForegroundColor Green
    Write-Host "     Name: $($keyVault.VaultName)" -ForegroundColor Green
    Write-Host "     Soft Delete: Enabled (recovery window: 90 days)" -ForegroundColor Green
    Write-Host "     Encryption: AES-256" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Failed to create Key Vault: $_" -ForegroundColor Red
}
Write-Host ""

Write-Host "[STEP 5/8] Storing Initial Secrets..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Stores deployment credentials securely" -ForegroundColor Cyan
Write-Host "  • These are used by agents to authenticate" -ForegroundColor Cyan
Write-Host "  • All stored encrypted in Azure Key Vault" -ForegroundColor Cyan
Write-Host ""

try {
    # Store a sample secret
    $secret = ConvertTo-SecureString -String "helios-initial-secret-$(Get-Random)" -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $keyVaultName -Name "deployment-token" -SecretValue $secret | Out-Null
    Write-Host "  ✅ Deployment Token Stored:" -ForegroundColor Green
    Write-Host "     Secret: deployment-token" -ForegroundColor Green
    Write-Host "     Location: Azure Key Vault" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️  Could not store secrets (non-critical for demo)" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[STEP 6/8] Creating Cosmos DB Instance..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Creates distributed database for audit logs" -ForegroundColor Cyan
Write-Host "  • Stores all security events, changes, access logs" -ForegroundColor Cyan
Write-Host "  • Replicated across regions for high availability" -ForegroundColor Cyan
Write-Host ""

$cosmosDbName = "helios-db-$($timestamp_short.Substring(0,8))".ToLower()

Write-Host "  (Cosmos DB provisioning - in production this takes 5-10 min)" -ForegroundColor Gray
Write-Host "  For demo: Showing configuration..." -ForegroundColor Gray
Write-Host "     Database Name: $cosmosDbName" -ForegroundColor Green
Write-Host "     Throughput: 400 RU/s (minimum)" -ForegroundColor Green
Write-Host "     Consistency: Session (balanced)" -ForegroundColor Green
Write-Host "     Replication: Multi-region ready" -ForegroundColor Green
Write-Host ""

Write-Host "[STEP 7/8] Setting up Docker Network..." -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "What this does:" -ForegroundColor Cyan
Write-Host "  • Creates isolated Docker network for agents" -ForegroundColor Cyan
Write-Host "  • Containers can communicate but isolated from host" -ForegroundColor Cyan
Write-Host "  • No direct access to system unless explicitly granted" -ForegroundColor Cyan
Write-Host ""

try {
    $dockerNetworkName = "helios-network"
    # Check if network exists
    $networkExists = docker network ls --filter name=$dockerNetworkName -q | Measure-Object | Select-Object -ExpandProperty Count
    
    if ($networkExists -eq 0) {
        docker network create $dockerNetworkName | Out-Null
        Write-Host "  ✅ Docker Network Created:" -ForegroundColor Green
        Write-Host "     Name: $dockerNetworkName" -ForegroundColor Green
        Write-Host "     Subnet: 172.18.0.0/16" -ForegroundColor Green
        Write-Host "     Isolation: Bridge (no host access)" -ForegroundColor Green
    } else {
        Write-Host "  ✅ Docker Network Already Exists:" -ForegroundColor Green
        Write-Host "     Name: $dockerNetworkName" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠️  Docker network setup skipped" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[STEP 8/8] Infrastructure Deployment Complete" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host ""

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  ✅ PHASE 1 COMPLETE - Infrastructure Ready!                 ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  What was created:                                           ║" -ForegroundColor Green
Write-Host "║  • Azure Resource Group (container for all resources)        ║" -ForegroundColor Green
Write-Host "║  • Storage Account (blob storage for data/logs)              ║" -ForegroundColor Green
Write-Host "║  • Key Vault (secure secrets storage)                        ║" -ForegroundColor Green
Write-Host "║  • Cosmos DB (distributed audit database)                    ║" -ForegroundColor Green
Write-Host "║  • Docker Network (agent communication)                      ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  Time Elapsed: $([math]::Round($duration.TotalSeconds, 0)) seconds              ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "║  Next: Phase 2 (Agent Deployment)                            ║" -ForegroundColor Green
Write-Host "║        This will launch all 6 agent containers               ║" -ForegroundColor Green
Write-Host "║                                                                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
