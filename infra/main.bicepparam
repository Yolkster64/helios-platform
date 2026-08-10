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
