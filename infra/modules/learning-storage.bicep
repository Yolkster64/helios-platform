// Azure Table Storage backend for the AIHub learning store — the shared-memory lane of
// the hybrid learning mode (HybridLearningStore), so every fleet worker and developer
// machine learns from one outcome history instead of a private local JSONL file.
// Opt-in from main.bicep (deployLearningStorage); see the "learning" block in
// config/aihub.json.
//
// Design notes:
// - RBAC-only data plane (allowSharedKeyAccess: false): AzureTableLearningStore
//   authenticates with DefaultAzureCredential, so no account keys or SAS tokens exist
//   to custody — matching the platform's no-static-keys chain (OIDC deploys, keyless
//   AI Search). Writers need Storage Table Data Contributor (assigned below when a
//   principal is supplied).
// - The table name is a contract with the C# store:
//   src/ai/HELIOS.AIHub/Learning/AzureTableLearningStore.cs pins
//   `private const string TableName = "aihubOutcomes"` and appends outcomes there.
//   Creating the table here (rather than relying on the store's CreateIfNotExists at
//   runtime) lets a least-privilege data-plane caller skip table-management rights.
//   Change the two together or the hub writes to a table this template never made.
// - publicNetworkAccess stays Enabled: the hub reaches the table over the public
//   endpoint with AAD auth. Private endpoints are a later opt-in (vnet, private DNS,
//   and endpoint wiring), deliberately not part of this module.

@minLength(3)
@maxLength(24)
@description('Storage account name (3-24 lowercase letters and digits, globally unique).')
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('Tags applied to the storage account.')
param tags object = {}

@description('Object ID of the principal granted Storage Table Data Contributor on the account, so the hub identity can write outcomes (shared-key auth is disabled). Empty string skips the role assignment.')
param principalId string = ''

// Storage Table Data Contributor — read/write/delete table data via RBAC.
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

// Pinned to AzureTableLearningStore.TableName (see header note) — not a parameter,
// because the C# constant is the other half of the contract.
var learningTableName = 'aihubOutcomes'

resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // RBAC-only: no shared keys or SAS — the store uses DefaultAzureCredential.
    allowSharedKeyAccess: false
    // Public endpoint + AAD auth; private endpoints are a later opt-in (header note).
    publicNetworkAccess: 'Enabled'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2024-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource outcomesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2024-01-01' = {
  parent: tableService
  name: learningTableName
}

// Data-plane write access for the hub's identity, scoped to this account only. The
// guid() seed is stable across deploys, so re-deployments converge on one assignment.
// principalType is deliberately unpinned (mirroring modules/keyvault.bicep): the
// principal may be a managed identity or an operator's user object ID.
resource tableDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(storageAccount.id, principalId, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: principalId
  }
}

@description('Table service endpoint (https://<account>.table.core.windows.net/) — the AZURE_LEARNING_TABLE_ENDPOINT value. An endpoint URL, not a secret; access is AAD + RBAC only.')
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('Name of the learning storage account.')
output storageAccountName string = storageAccount.name
