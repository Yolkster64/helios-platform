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
param additionalModelDeployments = [
  {
    name: 'text-embedding-3-small'
    version: '1'
    capacity: 120
  }
]

param tags = {
  platform: 'helios'
  workload: 'ai-hub'
}

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
