using 'main.bicep'

// Primary model deployment (legacy quintet preserved).
param aiServicesName = 'helios-ai'
param aiProjectName = 'helios-project'
param modelName = 'gpt-4o-mini'
param modelFormat = 'OpenAI'
param modelVersion = '2024-07-18'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30

// Multi-LLM surface: add or resize deployments here, not in the template.
param additionalModelDeployments = [
  {
    name: 'gpt-4o'
    version: '2024-11-20'
    capacity: 30
  }
  {
    name: 'text-embedding-3-large'
    version: '1'
    capacity: 120
  }
]

param tags = {
  platform: 'helios'
  workload: 'ai-hub'
}
