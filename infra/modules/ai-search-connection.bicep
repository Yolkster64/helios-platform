// Azure AI Search for Foundry agents — an AI Search service, a CognitiveSearch-category
// connection on the existing Foundry project, RBAC for the project's managed identity,
// and the account+project capability hosts that let the Agent Service use the connection
// as its vector store.
//
// Identity-based auth throughout: the search service disables local (API-key) auth, the
// connection authenticates as AAD, and the project's system-assigned identity gets the
// two data-plane roles the Foundry AI Search integration requires. No keys exist,
// so none can leak into outputs.
//
// Capability-host constraints (docs: /azure/foundry/agents/concepts/capability-hosts):
//   - one capability host per scope; a pre-existing one with a different name 409s
//   - updates are not supported — delete and recreate to change configuration
//   - the account-level host must exist before the project-level host
// This module wires the vector-store (AI Search) connection only; full BYO "standard
// agent setup" additionally references Cosmos DB (threadStorageConnections) and Storage
// (storageConnections) connections on the same project capability host.

@description('Name of the existing Foundry account.')
param accountName string

@description('Name of the existing Foundry project under the account.')
param projectName string

@description('Globally unique Azure AI Search service name (lowercase letters, digits, dashes; 2-60 chars).')
param searchServiceName string

@description('Azure region for the search service.')
param location string

@description('Tags applied to the search service.')
param tags object = {}

@description('Search service SKU (pricing tier). basic is the cheapest dedicated tier; free does not support managed-identity scenarios reliably.')
param searchSkuName string = 'basic'

@description('Name of the project connection that agents reference (3-33 chars: letter/digit then letters, digits, _ or -).')
param connectionName string = 'ai-search-connection'

// Azure AI Search data-plane roles the Foundry project identity needs for the
// AI Search tool / vector store (learn.microsoft.com/azure/foundry/agents/how-to/tools/ai-search):
// query + write index data, and manage search objects.
var searchIndexDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'

resource account 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: account
  name: projectName
}

resource search 'Microsoft.Search/searchServices@2025-05-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchSkuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Keyless on purpose: callers (the Foundry project identity, operators) come in
    // through Entra ID + the role assignments below. authOptions must be absent when
    // disableLocalAuth is true.
    disableLocalAuth: true
    partitionCount: 1
    replicaCount: 1
    publicNetworkAccess: 'Enabled'
  }
}

// Data-plane access for the project's system-assigned identity, scoped to the search
// service. principalType pinned so a freshly minted identity doesn't intermittently
// fail the assignment with PrincipalNotFound during replication.
resource projectSearchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, project.id, searchIndexDataContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchIndexDataContributorRoleId)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectSearchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, project.id, searchServiceContributorRoleId)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: project.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Project connection the agents reference by name. The Agent Service requires
// authType/category/target plus metadata.ResourceId to resolve the resource at runtime.
resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: project
  name: connectionName
  properties: {
    category: 'CognitiveSearch'
    target: 'https://${search.name}.search.windows.net'
    authType: 'AAD'
    isSharedToAll: false
    metadata: {
      ApiType: 'Azure'
      ResourceId: search.id
      location: search.location
    }
  }
}

// Account-level capability host enables the Agent Service at the account scope and is a
// hard prerequisite of the project-level host.
resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-06-01' = {
  parent: account
  name: '${accountName}-caphost'
  properties: {
    capabilityHostKind: 'Agents'
  }
}

// Project-level capability host: what the Agent Service actually reads to decide which
// bring-your-own resources this project's agents use. Vector store only here (see the
// header note about full standard setup). Role assignments are explicit dependencies so
// the host never activates before the identity can reach the search service.
resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-06-01' = {
  parent: project
  name: '${projectName}-caphost'
  properties: {
    vectorStoreConnections: [
      searchConnection.name
    ]
  }
  dependsOn: [
    accountCapabilityHost
    projectSearchIndexDataContributor
    projectSearchServiceContributor
  ]
}

output searchServiceId string = search.id
output searchServiceName string = search.name
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchPrincipalId string = search.identity.principalId
output connectionId string = searchConnection.id
output connectionName string = searchConnection.name
output projectCapabilityHostId string = projectCapabilityHost.id
