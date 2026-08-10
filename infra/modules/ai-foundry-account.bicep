// Azure AI Foundry account (AIServices kind with project management enabled)
// plus its model deployments.

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

// Azure AI User — data-plane access to build/run against the account and its projects.
var azureAiUserRoleId = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

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
  for d in modelDeployments: {
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

resource aiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(account.id, principalId, azureAiUserRoleId)
  scope: account
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAiUserRoleId)
    principalId: principalId
  }
}

output accountId string = account.id
output accountName string = account.name
output endpoint string = account.properties.endpoint
output openAiEndpoint string = 'https://${accountName}.openai.azure.com/'
output accountPrincipalId string = account.identity.principalId
output deploymentNames array = [for (d, i) in modelDeployments: deployments[i].name]
