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

@description('Azure OpenAI deployment configuration')
param openAiConfig object = {
  deployEmbeddings: true
  embeddingsModel: 'text-embedding-3-large'  // Modern, cost-effective, 3072 dimensions
  embeddingsModelVersion: '1'
  deployGpt: true
  gptModel: 'gpt-4o'  // Supports vision for image analysis
  gptModelVersion: '2024-08-06'  // Latest version with enhanced vision capabilities
}

@description('Deploy API Management (APIM) - Required for secure access')
param deployApim bool = true

@description('Publisher email for APIM - REQUIRED if deployApim is true')
param apimPublisherEmail string = 'admin@contoso.com'

@description('Publisher name for APIM - REQUIRED if deployApim is true')
param apimPublisherName string = 'Contoso'

@description('Deploy Virtual Network for private networking')
param deployVNet bool = false

@description('Blob container names to create in storage account')
param blobContainers array = [
  {
    name: 'pdfs'
  }
  {
    name: 'documents'
  }
]

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

// Storage Account for PDF documents
module storageAccount 'core/storage/storage-account.bicep' = {
  name: 'storage-account'
  params: {
    name: '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    containers: blobContainers
  }
}

// Azure OpenAI / Cognitive Services
module openAi 'core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'OpenAI'
    customSubDomainName: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    deployments: concat(
      openAiConfig.deployEmbeddings ? [{
        name: 'embeddings'
        model: {
          format: 'OpenAI'
          name: openAiConfig.embeddingsModel
          version: openAiConfig.embeddingsModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: 120
        }
      }] : [],
      openAiConfig.deployGpt ? [{
        name: 'chat'
        model: {
          format: 'OpenAI'
          name: openAiConfig.gptModel
          version: openAiConfig.gptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: 30
        }
      }] : []
    )
  }
}

// Virtual Network (optional)
module vnet 'core/network/vnet.bicep' = if (deployVNet) {
  name: 'vnet'
  params: {
    name: '${abbrs.networkVirtualNetworks}${resourceToken}'
    location: location
    tags: tags
    addressPrefix: '10.0.0.0/16'
    subnets: [
      {
        name: 'container-apps'
        addressPrefix: '10.0.0.0/23'
      }
      {
        name: 'apim'
        addressPrefix: '10.0.2.0/24'
      }
      {
        name: 'private-endpoints'
        addressPrefix: '10.0.3.0/24'
      }
    ]
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

// MCP server container app (INTERNAL ONLY - accessed via APIM)
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
    external: false  // INTERNAL ONLY - no direct external access
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
        name: 'storage-connection-string'
        value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.outputs.name};AccountKey=${storageAccount.outputs.primaryKey};EndpointSuffix=${environment().suffixes.storage}'
      }
      {
        name: 'openai-endpoint'
        value: openAi.outputs.endpoint
      }
      {
        name: 'openai-key'
        value: openAi.outputs.key
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
        name: 'STORAGE_CONNECTION_STRING'
        secretRef: 'storage-connection-string'
      }
      {
        name: 'AZURE_STORAGE_ACCOUNT_NAME'
        value: storageAccount.outputs.name
      }
      {
        name: 'AZURE_STORAGE_CONTAINER_NAME'
        value: 'pdfs'
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        secretRef: 'openai-endpoint'
      }
      {
        name: 'AZURE_OPENAI_KEY'
        secretRef: 'openai-key'
      }
      {
        name: 'AZURE_OPENAI_EMBEDDING_DEPLOYMENT'
        value: 'embeddings'
      }
      {
        name: 'AZURE_OPENAI_CHAT_DEPLOYMENT'
        value: 'chat'
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

// API Management - Gateway for secure access to MCP server
module apim 'core/gateway/apim.bicep' = if (deployApim) {
  name: 'apim'
  params: {
    name: '${abbrs.apiManagementService}${resourceToken}'
    location: location
    tags: tags
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    backendUrl: 'https://${mcpServer.outputs.uri}'
    apiKey: generatedApiKey
  }
  dependsOn: [
    mcpServer
  ]
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

// Grant Storage Blob Data Contributor role for managed identity
module storageBlobContributorRole 'core/security/role.bicep' = {
  name: 'storage-blob-contributor-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Grant Cognitive Services OpenAI User role for managed identity
module openAiUserRole 'core/security/role.bicep' = {
  name: 'openai-user-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
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

output STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output STORAGE_BLOB_ENDPOINT string = storageAccount.outputs.blobEndpoint

output AZURE_OPENAI_NAME string = openAi.outputs.name
output AZURE_OPENAI_ENDPOINT string = openAi.outputs.endpoint
output AZURE_OPENAI_EMBEDDING_DEPLOYMENT string = 'embeddings'
output AZURE_OPENAI_CHAT_DEPLOYMENT string = 'chat'

output APIM_NAME string = deployApim ? apim.outputs.name : ''
output APIM_GATEWAY_URL string = deployApim ? apim.outputs.gatewayUrl : ''
output APIM_MCP_API_URL string = deployApim ? apim.outputs.mcpApiUrl : ''

output MCP_SERVER_INTERNAL_URI string = mcpServer.outputs.uri
output MCP_SERVER_API_KEY string = generatedApiKey
output MCP_PUBLIC_ENDPOINT string = deployApim ? '${apim.outputs.mcpApiUrl}/api/tools' : mcpServer.outputs.uri

output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.name
output MANAGED_IDENTITY_NAME string = managedIdentity.outputs.name
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.outputs.clientId