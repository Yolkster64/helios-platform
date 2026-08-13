// HELIOS Platform — Azure AI Foundry infrastructure.
//
// Re-expresses the legacy hub-based "standard agent setup" parameter surface on the
// modern Foundry account + project model (Microsoft.CognitiveServices/accounts@2025-06-01).
// The hub/project (MachineLearningServices) model is deprecated ("Foundry classic");
// see infra/README.md for the legacy-parameter → modern-resource mapping table.
targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

@description('A single model deployment on the Foundry account.')
type modelDeployment = {
  @description('Deployment name (also the default model name).')
  name: string

  @description('Model name if it differs from the deployment name.')
  modelName: string?

  @description('Model format. Defaults to OpenAI.')
  format: string?

  @description('Model version.')
  version: string

  @description('Deployment SKU. Defaults to GlobalStandard.')
  skuName: string?

  @description('Deployment capacity in thousands of tokens-per-minute. Defaults to 30.')
  capacity: int?
}

// ---------------------------------------------------------------------------
// Parameters — names preserved from the legacy hub template where applicable
// ---------------------------------------------------------------------------

@minLength(2)
@maxLength(12)
@description('Base name for the Azure AI Services (Foundry) account; a unique suffix is appended.')
param aiServicesName string = 'helios-ai'

@description('Name for the Foundry project.')
param aiProjectName string = 'helios-project'

@description('Friendly name for the Foundry project, shown in the Foundry portal.')
param aiProjectFriendlyName string = 'HELIOS AI Project'

@description('Description of the Foundry project, shown in the Foundry portal.')
param aiProjectDescription string = 'Multi-LLM hub project for the HELIOS platform.'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Region for the Foundry account when model availability requires a different region. Empty string means use location.')
param modelLocation string = ''

@description('Set of tags to apply to all resources.')
param tags object = {}

// Primary model deployment — param names preserved verbatim from the legacy template.
// Defaults must point at a GA model: Azure rejects new deployments of models in
// 'Deprecating' state (which is what killed gpt-4o-mini/2024-07-18 here).
@description('Model name for the primary deployment.')
param modelName string = 'gpt-5-mini'

@description('Model format for the primary deployment.')
param modelFormat string = 'OpenAI'

@description('Model version for the primary deployment.')
param modelVersion string = '2025-08-07'

@description('SKU name for the primary model deployment.')
param modelSkuName string = 'GlobalStandard'

@description('Capacity for the primary model deployment, in thousands of tokens-per-minute.')
param modelCapacity int = 30

@description('Additional model deployments beyond the primary one (multi-LLM surface).')
param additionalModelDeployments modelDeployment[] = [
  {
    name: 'text-embedding-3-small'
    version: '1'
    capacity: 120
  }
]

@description('Full ARM resource ID of an existing Foundry/AI Services account. Empty string means create a new account (and project) here; when set, no account, deployments, or project are created — see infra/README.md.')
param aiServiceAccountResourceId string = ''

@description('Key Vault name for provider API keys. Empty string means a name is generated.')
param keyVaultName string = ''

@secure()
@description('Anthropic API key to store in Key Vault. Empty string means the secret is not created.')
param anthropicApiKey string = ''

@secure()
@description('OpenAI API key to store in Key Vault. Empty string means the secret is not created.')
param openaiApiKey string = ''

@secure()
@description('GitHub token for GitHub Models to store in Key Vault. Empty string means the secret is not created.')
param githubModelsToken string = ''

@description('Object ID of the principal granted Azure AI User and Key Vault Secrets User. Empty string means no role assignments are created.')
param principalId string = ''

// --- AI Search connection + agent capability host (opt-in) ------------------------
// OFF by default so existing deployments are unchanged. Requires the account/project
// created by this template (not aiServiceAccountResourceId): the module wires the
// connection and capability hosts onto that project. Identity-based auth only — the
// search service disables API keys entirely.

@description('Deploy an Azure AI Search service, a CognitiveSearch project connection, and the account+project capability hosts that let Foundry agents use it as their vector store. OFF by default; ignored when aiServiceAccountResourceId is set.')
param deployAiSearchConnection bool = false

@description('Name for the Azure AI Search service (lowercase letters, digits, dashes; 2-60 chars). Empty string means a name is generated.')
param aiSearchServiceName string = ''

@description('SKU (pricing tier) for the Azure AI Search service.')
param aiSearchSkuName string = 'basic'

@description('Name of the Foundry project connection agents reference for AI Search.')
param aiSearchConnectionName string = 'ai-search-connection'

// --- Fleet burst VMSS (opt-in; docs/architecture/HERMES_FLEET_AND_XCORE.md) -------
// OFF by default and doubly gated (deployFleetVmss AND a non-empty SSH key), so the
// live rg-helios-ai stack redeploys unchanged until an operator opts in. See
// infra/README.md, "Fleet burst capacity (VMSS)".

@description('Deploy the Hermes/Xcore fleet burst VM scale set (cloud fleet-worker lanes). OFF by default; also requires vmssAdminPublicKey.')
param deployFleetVmss bool = false

@description('Admin username on fleet VMSS instances. SSH-key-only; password auth is disabled.')
param vmssAdminUsername string = 'heliosadmin'

@description('SSH public key for vmssAdminUsername (e.g. contents of ~/.ssh/id_ed25519.pub). Not @secure() on purpose — public keys are not secrets, and the module is gated on this being non-empty. Empty string (the default) keeps the VMSS off even when deployFleetVmss is true.')
param vmssAdminPublicKey string = ''

@description('VM size for fleet burst instances.')
param fleetVmSku string = 'Standard_B2s'

@minValue(0)
@description('Autoscale floor and default instance count for the fleet VMSS. 0 = scale-to-zero when idle.')
param fleetBurstMinInstances int = 0

@minValue(1)
@description('Autoscale ceiling for the fleet VMSS — the topology default maxBurstLanes (config/fleet/fleet-topology.json).')
param fleetBurstMaxInstances int = 5

@minValue(300)
@maxValue(43200)
@description('Idle window in seconds before the fleet VMSS scales in — the topology default scaleDownIdleSeconds. Azure autoscale requires windows of at least 300 seconds.')
param fleetScaleDownIdleSeconds int = 300

@minValue(1)
@description('Stub fleet worker lanes started per VMSS instance.')
param fleetWorkersPerInstance int = 2

@description('Pool name exported as HELIOS_FLEET_POOL on cloud lanes, so fleet outcomes attribute to the burst pool.')
param fleetPool string = 'cloud-burst'

@description('Git repository cloned onto each VMSS instance. Must be public — cloud-init clones anonymously and never carries credentials.')
param fleetRepoUrl string = 'https://github.com/Yolkster64/helios-platform'

@description('Git ref (branch or tag) checked out on each VMSS instance.')
param fleetRepoRef string = 'main'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

// Stable suffix: idempotent re-deployments update resources in place. (The legacy
// quickstart mixed in utcNow(), which mints brand-new resources on every deploy.)
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)
var accountName = toLower('${aiServicesName}${uniqueSuffix}')
var projectName = toLower(aiProjectName)
var effectiveModelLocation = empty(modelLocation) ? location : modelLocation
var effectiveKeyVaultName = empty(keyVaultName) ? 'kv-helios-${uniqueSuffix}' : keyVaultName
var aiServiceExists = !empty(aiServiceAccountResourceId)

// Both gates must open: the flag, and an SSH key (SSH-key-only auth means a VMSS
// without a key would be undeployable anyway).
var fleetVmssEnabled = deployFleetVmss && vmssAdminPublicKey != ''

// AI Search wiring needs the account+project deployed HERE — with an existing account
// supplied, this template creates no project to attach the connection to.
var aiSearchEnabled = deployAiSearchConnection && !aiServiceExists
var effectiveAiSearchName = empty(aiSearchServiceName) ? 'srch-helios-${uniqueSuffix}' : aiSearchServiceName

var allModelDeployments = concat(
  [
    {
      name: modelName
      modelName: modelName
      format: modelFormat
      version: modelVersion
      skuName: modelSkuName
      capacity: modelCapacity
    }
  ],
  additionalModelDeployments
)

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module foundryAccount 'modules/ai-foundry-account.bicep' = if (!aiServiceExists) {
  name: 'foundry-account-${uniqueSuffix}'
  params: {
    accountName: accountName
    location: effectiveModelLocation
    tags: tags
    modelDeployments: allModelDeployments
    principalId: principalId
  }
}

module foundryProject 'modules/ai-foundry-project.bicep' = if (!aiServiceExists) {
  name: 'foundry-project-${uniqueSuffix}'
  params: {
    accountName: aiServiceExists ? '' : foundryAccount!.outputs.accountName
    projectName: projectName
    projectFriendlyName: aiProjectFriendlyName
    projectDescription: aiProjectDescription
    location: effectiveModelLocation
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-${uniqueSuffix}'
  params: {
    keyVaultName: effectiveKeyVaultName
    location: location
    tags: tags
    principalId: principalId
    anthropicApiKey: anthropicApiKey
    openaiApiKey: openaiApiKey
    githubModelsToken: githubModelsToken
  }
}

// AI Search vector store for Foundry agents — search service + AAD project connection
// + capability hosts. Opt-in (deployAiSearchConnection); a redeploy of the live stack
// with defaults creates nothing new. NOTE: each account/project allows exactly ONE
// capability host and updates are unsupported — if one already exists (e.g. created in
// the portal) this module 409s; delete it first or leave this flag off.
module aiSearch 'modules/ai-search-connection.bicep' = if (aiSearchEnabled) {
  name: 'ai-search-${uniqueSuffix}'
  params: {
    accountName: foundryAccount!.outputs.accountName
    projectName: foundryProject!.outputs.projectName
    searchServiceName: effectiveAiSearchName
    location: location
    tags: tags
    searchSkuName: aiSearchSkuName
    connectionName: aiSearchConnectionName
  }
}

// Hermes/Xcore fleet burst capacity — VMSS + autoscale for cloud fleet-worker
// lanes. Conditional on BOTH deployFleetVmss and a supplied SSH public key, so a
// redeploy of the live stack with defaults creates nothing new.
module fleetVmss 'modules/fleet-vmss.bicep' = if (fleetVmssEnabled) {
  name: 'fleet-vmss-${uniqueSuffix}'
  params: {
    vmssName: 'vmss-helios-${uniqueSuffix}'
    location: location
    tags: tags
    vmSku: fleetVmSku
    adminUsername: vmssAdminUsername
    adminPublicKey: vmssAdminPublicKey
    workersPerInstance: fleetWorkersPerInstance
    fleetPool: fleetPool
    repoUrl: fleetRepoUrl
    repoRef: fleetRepoRef
    burstMinInstances: fleetBurstMinInstances
    burstMaxInstances: fleetBurstMaxInstances
    scaleDownIdleSeconds: fleetScaleDownIdleSeconds
  }
}

// ---------------------------------------------------------------------------
// Outputs — never output secrets
// ---------------------------------------------------------------------------

@description('Foundry account endpoint (empty when an existing account was supplied).')
output aiServicesEndpoint string = aiServiceExists ? '' : foundryAccount!.outputs.endpoint

@description('Azure OpenAI-compatible endpoint on the Foundry account (empty when an existing account was supplied).')
output openAiEndpoint string = aiServiceExists ? '' : foundryAccount!.outputs.openAiEndpoint

@description('Foundry project endpoint — the modern replacement for the legacy "project connection string".')
output projectEndpoint string = aiServiceExists ? '' : foundryProject!.outputs.projectEndpoint

@description('Foundry project resource ID (empty when an existing account was supplied).')
output projectId string = aiServiceExists ? '' : foundryProject!.outputs.projectId

@description('Key Vault URI for provider API keys.')
output keyVaultUri string = keyVault.outputs.vaultUri

@description('Names of all model deployments created on the account.')
output modelDeploymentNames array = aiServiceExists ? [] : foundryAccount!.outputs.deploymentNames

@description('Azure AI Search endpoint wired to the Foundry project for agent vector storage (empty string when the AI Search connection is disabled).')
output aiSearchEndpoint string = aiSearchEnabled ? aiSearch!.outputs.searchEndpoint : ''

@description('Name of the Foundry project connection agents reference for AI Search (empty string when disabled).')
output aiSearchConnectionName string = aiSearchEnabled ? aiSearch!.outputs.connectionName : ''

@description('Resource ID of the Azure AI Search service (empty string when disabled).')
output aiSearchServiceId string = aiSearchEnabled ? aiSearch!.outputs.searchServiceId : ''

@description('Name of the fleet burst VM scale set — the az vmss scale target for scripts/fleet/scale-fleet.ps1 (empty string when the VMSS is disabled).')
output fleetVmssName string = fleetVmssEnabled ? fleetVmss!.outputs.vmssName : ''

@description('Principal ID of the fleet VMSS system-assigned identity — grant it roles (e.g. Key Vault Secrets User) if cloud lanes must read provider keys (empty string when the VMSS is disabled).')
output fleetVmssPrincipalId string = fleetVmssEnabled ? fleetVmss!.outputs.principalId : ''
