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
