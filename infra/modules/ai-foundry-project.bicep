// Foundry project — child of the Foundry account. The project endpoint replaces the
// legacy hub model's "project connection string".

@description('Name of the parent Foundry account.')
param accountName string

@description('Name for the Foundry project.')
param projectName string

@description('Friendly display name for the project.')
param projectFriendlyName string

@description('Description shown in the Foundry portal.')
param projectDescription string

@description('Azure region for the project (must match the account region).')
param location string

@description('Tags applied to the project.')
param tags object = {}

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectFriendlyName
    description: projectDescription
  }
}

output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output projectEndpoint string = 'https://${accountName}.services.ai.azure.com/api/projects/${projectName}'
