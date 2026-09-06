// Azure AI Foundry account (AIServices kind with project management enabled)
// plus its model deployments.
//
// Two deployment loops, serialized end to end (@batchSize(1) on each, and the second
// dependsOn the first — parallel creation on one account returns 409):
//   deployments        first-party formats (OpenAI, ...) on the GA 2025-06-01 pin.
//   claudeDeployments  'Anthropic'-format entries (Claude in Foundry). Claude is an Azure
//                      Marketplace offer the Cognitive Services RP accepts on the deployer's
//                      behalf from a modelProviderData attestation block sent with each
//                      deployment; a Claude deployment without it fails with
//                      AnthropicOrganizationCreationException. That block is carried by
//                      accounts/deployments@2025-10-01-preview only (absent from the
//                      2025-06-01 contract, and untyped in Bicep — hence the BCP037
//                      suppression below). Sources:
//                      https://learn.microsoft.com/azure/developer/ai/how-to/deploy-claude-foundry
//                      ("Terms of use") and the starter kit it deploys,
//                      https://github.com/Azure-Samples/claude (infra-bicep/infra/foundry.bicep).

@description('A single model deployment on the Foundry account.')
type modelDeployment = {
  name: string
  modelName: string?
  format: string?
  version: string
  skuName: string?
  capacity: int?
}

@description('Globally unique Foundry account name (also used as the custom subdomain).')
param accountName string

@description('Azure region for the account.')
param location string

@description('Tags applied to the account.')
param tags object = {}

@description('Model deployments to create on the account.')
param modelDeployments modelDeployment[] = []

@description('Object ID of the principal granted Azure AI User on the account. Empty string skips the role assignment.')
param principalId string = ''

@description('Legal entity name sent as modelProviderData.organizationName with every Anthropic-format deployment (Azure Marketplace attestation for Claude). Empty string skips the Anthropic-format entries of modelDeployments entirely.')
param claudeOrganizationName string = ''

@minLength(2)
@maxLength(2)
@description('Two-letter ISO country code sent as modelProviderData.countryCode.')
param claudeCountryCode string = 'US'

@description('Industry sent as modelProviderData.industry — lowercase, one of the Foundry portal dropdown values (validated by main.bicep).')
param claudeIndustry string = 'technology'

// Azure AI User — data-plane access to build/run against the account and its projects.
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

// Anthropic-format entries carry the attestation and ride the preview API; everything
// else keeps the GA pin. Without an organization name the Claude entries are skipped, so
// a redeploy of the live stack with defaults creates nothing new.
var standardDeployments = filter(modelDeployments, d => (d.?format ?? 'OpenAI') != 'Anthropic')
var claudeDeploymentEntries = empty(claudeOrganizationName)
  ? []
  : filter(modelDeployments, d => (d.?format ?? 'OpenAI') == 'Anthropic')

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
  }
}

// Deployments must be created serially — parallel creation races on account quota.
@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = [
  for d in standardDeployments: {
    parent: account
    name: d.name
    sku: {
      name: d.?skuName ?? 'GlobalStandard'
      capacity: d.?capacity ?? 30
    }
    properties: {
      model: {
        format: d.?format ?? 'OpenAI'
        name: d.?modelName ?? d.name
        version: d.version
      }
    }
  }
]

// Claude in Foundry — the same data shape plus the Marketplace attestation, mirroring the
// Learn-cited starter kit: format 'Anthropic', GlobalStandard, model version '1' (Hosted on
// Anthropic infrastructure) or '2' (Hosted on Azure), capacity in K tokens-per-minute.
// dependsOn the first loop so the two loops never create concurrently on the account.
@batchSize(1)
resource claudeDeployments 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = [
  for d in claudeDeploymentEntries: {
    parent: account
    name: d.name
    sku: {
      name: d.?skuName ?? 'GlobalStandard'
      capacity: d.?capacity ?? 30
    }
    properties: {
      model: {
        format: 'Anthropic'
        name: d.?modelName ?? d.name
        version: d.version
      }
      // Not in the published Bicep types for any api-version (BCP037), but required by the
      // RP contract documented in the header; the RP rejects Claude deployments without it.
      #disable-next-line BCP037
      modelProviderData: {
        organizationName: claudeOrganizationName
        countryCode: claudeCountryCode
        industry: claudeIndustry
      }
      versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
      raiPolicyName: 'Microsoft.DefaultV2'
    }
    dependsOn: [
      deployments
    ]
  }
]

resource aiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(account.id, principalId, azureAiUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: principalId
  }
}

var standardDeploymentNames = [for (d, i) in standardDeployments: deployments[i].name]
var claudeDeploymentNames = [for (d, i) in claudeDeploymentEntries: claudeDeployments[i].name]

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.endpoint
output openAiEndpoint string = 'https://${accountName}.openai.azure.com/'
output anthropicBaseUrl string = 'https://${accountName}.services.ai.azure.com/anthropic'
output accountPrincipalId string = account.identity.principalId
output deploymentNames array = concat(standardDeploymentNames, claudeDeploymentNames)
