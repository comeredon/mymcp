targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string = 'swedencentral'

@description('Azure AI Search service name')
param searchServiceName string

@description('Name of the search index containing your PDF documents')
param searchIndexName string

@description('Search service endpoint')
param searchEndpoint string

@description('Search service admin key')
@secure()
param searchKey string

@description('Server API key for authentication')
@secure()
param serverApiKey string

// Generate unique resource names
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

// Reference existing resources from phase 1
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: '${abbrs.appManagedEnvironments}${resourceToken}'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: '${abbrs.containerRegistryRegistries}${resourceToken}'
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
}

// Reference existing search service
resource existingSearchService 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: searchServiceName
}

// MCP server container app
module mcpServer 'core/host/container-app.bicep' = {
  name: 'mcp-server'
  params: {
    name: '${abbrs.appContainerApps}mcp-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    containerAppsEnvironmentName: containerAppsEnvironment.name
    containerRegistryName: containerRegistry.name
    containerName: 'mcp-azure-pdf'
    imageName: 'mcp-azure-pdf'
    managedIdentityName: managedIdentity.name
    secrets: [
      {
        name: 'search-endpoint'
        value: searchEndpoint
      }
      {
        name: 'search-key'
        value: searchKey
      }
      {
        name: 'server-api-key'
        value: serverApiKey
      }
    ]
    env: [
      {
        name: 'SEARCH_ENDPOINT'
        secretRef: 'search-endpoint'
      }
      {
        name: 'SEARCH_KEY'
        secretRef: 'search-key'
      }
      {
        name: 'SEARCH_INDEX'
        value: searchIndexName
      }
      {
        name: 'SERVER_API_KEY'
        secretRef: 'server-api-key'
      }
      {
        name: 'PORT'
        value: '8080'
      }
    ]
    targetPort: 8080
    resources: {
      cpu: '0.25'
      memory: '0.5Gi'
    }
    scale: {
      minReplicas: 1
      maxReplicas: 10
    }
  }
}

// Grant ACR pull permissions to the container app managed identity
module acrPullRole 'core/security/role.bicep' = {
  name: 'acr-pull-role'
  params: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output containerAppUrl string = mcpServer.outputs.uri
output containerAppName string = mcpServer.outputs.name