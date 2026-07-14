targetScope = 'resourceGroup'

@minLength(2)
param environmentName string
param location string = resourceGroup().location
param deployControl bool = false
param externalIngress bool = false
param image string = 'invalid.example/helios-control:deployment-disabled'

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)
var prefix = toLower('helios-${environmentName}')

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs-${suffix}'
  location: location
  properties: { retentionInDays: 30 }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-ai-${suffix}'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web', WorkspaceResourceId: logs.id }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-identity-${suffix}'
  location: location
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take(replace('${prefix}-kv-${suffix}', '-', ''), 24)
  location: location
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 30
    publicNetworkAccess: 'Disabled'
    sku: { family: 'A', name: 'standard' }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'heliosacr${suffix}'
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${prefix}-env-${suffix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource control 'Microsoft.App/containerApps@2024-03-01' = if (deployControl) {
  name: '${prefix}-control'
  location: location
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: externalIngress, targetPort: 8080, transport: 'auto', allowInsecure: false }
      registries: [{ server: registry.properties.loginServer, identity: identity.id }]
    }
    template: {
      containers: [{
        name: 'control'
        image: image
        env: [
          { name: 'HELIOS_ENVIRONMENT', value: environmentName }
          { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
          { name: 'KEY_VAULT_URI', value: vault.properties.vaultUri }
          { name: 'XCORE_TRAINING_ENABLED', value: 'false' }
        ]
        resources: { cpu: json('0.5'), memory: '1Gi' }
        probes: [
          {
            type: 'Liveness'
            httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' }
            initialDelaySeconds: 5
            periodSeconds: 30
            timeoutSeconds: 3
            failureThreshold: 3
          }
          {
            type: 'Readiness'
            httpGet: { path: '/health/ready', port: 8080, scheme: 'HTTP' }
            initialDelaySeconds: 2
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          }
        ]
      }]
      scale: { minReplicas: 0, maxReplicas: 3, rules: [{ name: 'http', http: { metadata: { concurrentRequests: '50' } } }] }
    }
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'acrpull')
  scope: registry
  properties: { principalId: identity.properties.principalId, roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d'), principalType: 'ServicePrincipal' }
}

output registryName string = registry.name
output registryServer string = registry.properties.loginServer
