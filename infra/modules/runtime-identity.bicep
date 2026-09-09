// Identity for AIHub/worker runtime credentials; separate from the deploy identity.
// Bicep owns creation; attaching it to a host is that host template's responsibility.
@minLength(3)
@maxLength(128)
param identityName string

param location string
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output id string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
