using 'main.bicep'

// Primary model deployment (legacy param names preserved; model must be GA —
// Azure rejects new deployments of 'Deprecating' models like gpt-4o-mini/2024-07-18).
param aiServicesName = 'helios-ai'
param aiProjectName = 'helios-project'
param modelName = 'gpt-5-mini'
param modelFormat = 'OpenAI'
param modelVersion = '2025-08-07'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30

// Multi-LLM surface: add or resize deployments here, not in the template.
// Check regional quota first: `az cognitiveservices usage list -l <region>` —
// GlobalStandard quota for gpt-4o and text-embedding-3-large is 0 in some
// subscriptions, which fails preflight with InsufficientQuota.
//
// Claude in Foundry (format 'Anthropic'): the deployment names double as the model IDs
// scripts/ai-integration/Connect-ClaudeFoundry.ps1 (ANTHROPIC_DEFAULT_{SONNET,HAIKU,OPUS}_MODEL)
// and the hub's anthropic-foundry provider send as `model`. version '1' = Hosted on
// Anthropic infrastructure — the only version of Sonnet 4.6 and Opus 4.6; Haiku 4.5 also
// ships '2' = Hosted on Azure. All three families are GlobalStandard in eastus2 and
// swedencentral (westus2: Sonnet and Opus only). capacity is K tokens-per-minute;
// pay-as-you-go default quota is 80 for Sonnet 4.6 / Haiku 4.5 and 40 for Opus 4.6.
// These entries deploy only once claudeOrganizationName (below) is set.
//   https://learn.microsoft.com/azure/foundry/foundry-models/concepts/claude-models
//   https://learn.microsoft.com/azure/foundry/foundry-models/concepts/models-from-partners#region-availability-by-deployment-type
param additionalModelDeployments = [
  {
    name: 'text-embedding-3-small'
    version: '1'
    capacity: 120
  }
  {
    name: 'claude-sonnet-4-6'
    format: 'Anthropic'
    version: '1'
    capacity: 25
  }
  {
    name: 'claude-haiku-4-5'
    format: 'Anthropic'
    version: '1'
    capacity: 25
  }
  {
    name: 'claude-opus-4-6'
    format: 'Anthropic'
    version: '1'
    capacity: 25
  }
]

// Claude Marketplace attestation (modelProviderData) — deliberately EMPTY so the live
// rg-helios-ai stack redeploys unchanged: the Anthropic-format entries above are skipped
// until the owner attests at deploy time. The legal entity name is not a secret, but it
// is the owner's statement (review https://www.anthropic.com/legal/commercial-terms):
//   az deployment group what-if -g rg-helios-ai --template-file infra/main.bicep \
//     --parameters infra/main.bicepparam --parameters claudeOrganizationName="<legal entity name>"
param claudeOrganizationName = ''
// param claudeCountryCode = 'US'
// param claudeIndustry = 'technology'  // lowercase: technology|finance|healthcare|education|retail|manufacturing|government|media|other

param tags = {
  platform: 'helios'
  workload: 'ai-hub'
}

// AI Search connection + agent capability host — deliberately OFF so the live
// rg-helios-ai stack redeploys unchanged. Enabling deploys an Azure AI Search service
// (keyless: local auth disabled), an AAD project connection, RBAC for the project's
// managed identity, and the account+project capability hosts agents read their vector
// store from. One capability host per scope; if one already exists this 409s.
param deployAiSearchConnection = false
// param aiSearchServiceName = ''                       // '' = srch-helios-<suffix>
// param aiSearchSkuName = 'basic'
// param aiSearchConnectionName = 'ai-search-connection'

// Fleet burst VMSS (infra/README.md, "Fleet burst capacity (VMSS)") — deliberately
// OFF so the live rg-helios-ai stack redeploys unchanged. To enable, set
// deployFleetVmss = true AND pass an SSH public key (both gates must open; a public
// key is not a secret, but it is operator-specific, so pass it at deploy time:
//   az deployment group create ... --parameters deployFleetVmss=true \
//     vmssAdminPublicKey="$(cat ~/.ssh/id_ed25519.pub)"
// ). Sizing knobs, uncommented here only when they need to differ from the defaults:
param deployFleetVmss = false
// param vmssAdminUsername = 'heliosadmin'
// param fleetVmSku = 'Standard_B2s'
// param fleetBurstMinInstances = 0      // autoscale floor; 0 = scale-to-zero
// param fleetBurstMaxInstances = 5      // topology maxBurstLanes
// param fleetScaleDownIdleSeconds = 300 // topology scaleDownIdleSeconds (>= 300)
// param fleetWorkersPerInstance = 2
// param fleetPool = 'cloud-burst'       // exported as HELIOS_FLEET_POOL on cloud lanes
// param fleetRepoUrl = 'https://github.com/Yolkster64/helios-platform'
// param fleetRepoRef = 'main'

// Learning-store Azure backend — deliberately OFF: local JSONL stays the learning lane; enabling creates the storage account + aihubOutcomes table whose endpoint backs AZURE_LEARNING_TABLE_ENDPOINT.
param deployLearningStorage = false
