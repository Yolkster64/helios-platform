// Key Vault for multi-LLM provider API keys. Secrets are only created when a
// non-empty value is supplied; nothing is ever output.

@description('Key Vault name.')
param keyVaultName string

@description('Azure region for the vault.')
param location string

@description('Tags applied to the vault.')
param tags object = {}

@description('Object ID of the principal granted Key Vault Secrets User. Empty string skips the role assignment.')
param principalId string = ''

@secure()
param anthropicApiKey string = ''

@secure()
param openaiApiKey string = ''

@secure()
param githubModelsToken string = ''

// Key Vault Secrets User — read secret contents via RBAC.
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
  }
}

resource anthropicSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(anthropicApiKey)) {
  parent: vault
  name: 'anthropic-api-key'
  properties: {
    value: anthropicApiKey
  }
}

resource openaiSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(openaiApiKey)) {
  parent: vault
  name: 'openai-api-key'
  properties: {
    value: openaiApiKey
  }
}

resource githubModelsSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(githubModelsToken)) {
  parent: vault
  name: 'github-models-token'
  properties: {
    value: githubModelsToken
  }
}

resource secretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(vault.id, principalId, keyVaultSecretsUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
  }
}

output vaultUri string = vault.properties.vaultUri
output vaultName string = vault.name
