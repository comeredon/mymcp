targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string = 'swedencentral'

@description('Name of the search index containing your PDF documents')
param searchIndexName string = 'pdf-index'

@description('Azure AI Search SKU')
@allowed(['free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param searchServiceSku string = 'basic'

@description('Custom API key for the MCP server (optional - will generate if not provided)')
@secure()
param serverApiKey string = ''

@description('Container app CPU and memory configuration')
param containerAppConfig object = {
  cpu: '0.25'
  memory: '0.5Gi'
  minReplicas: 1
  maxReplicas: 10
}

// Generate unique resource names
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(resourceGroup().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var generatedApiKey = !empty(serverApiKey) ? serverApiKey : 'mcp-${uniqueString(resourceToken, environmentName)}'

// Log Analytics workspace
module logAnalytics 'core/monitor/loganalytics.bicep' = {
  name: 'loganalytics'
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

// Azure AI Search service - CREATE NEW
module searchService 'core/search/search-services.bicep' = {
  name: 'search-service'
  params: {
    name: '${abbrs.searchSearchServices}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: searchServiceSku
    }
    semanticSearch: 'free'
  }
}

// Container apps environment
module containerAppsEnvironment 'core/host/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
  }
}

// Container registry
module containerRegistry 'core/host/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
  }
}

// User assigned managed identity for container app
module managedIdentity 'core/security/managed-identity.bicep' = {
  name: 'managed-identity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

// MCP server container app
module mcpServer 'core/host/container-app.bicep' = {
  name: 'mcp-server'
  params: {
    name: '${abbrs.appContainerApps}mcp-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    containerName: 'mcp-azure-pdf'
    imageName: 'mcp-azure-pdf'
    managedIdentityName: managedIdentity.outputs.name
    secrets: [
      {
        name: 'search-endpoint'
        value: searchService.outputs.endpoint
      }
      {
        name: 'search-key'
        value: searchService.outputs.adminKey
      }
      {
        name: 'server-api-key'
        value: generatedApiKey
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
      cpu: containerAppConfig.cpu
      memory: containerAppConfig.memory
    }
    scale: {
      minReplicas: containerAppConfig.minReplicas
      maxReplicas: containerAppConfig.maxReplicas
    }
  }
}

// Role assignments for the managed identity
module searchContributorRole 'core/security/role.bicep' = {
  name: 'search-contributor-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '8ebe5a00-799e-43f5-93ac-243d3dce84a7' // Search Index Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant ACR pull permissions to the container app managed identity
module acrPullRole 'core/security/role.bicep' = {
  name: 'acr-pull-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP_NAME string = resourceGroup().name
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

output AZURE_CONTAINER_APPS_ENVIRONMENT_NAME string = containerAppsEnvironment.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name

output SEARCH_SERVICE_NAME string = searchService.outputs.name
output SEARCH_ENDPOINT string = searchService.outputs.endpoint
output SEARCH_INDEX_NAME string = searchIndexName

output MCP_SERVER_URI string = mcpServer.outputs.uri
output MCP_SERVER_API_KEY string = generatedApiKey

output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.name