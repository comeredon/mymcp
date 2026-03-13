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

@description('Azure AI Search SKU - use standard (S1) or higher to avoid text extraction truncation (basic limits to 64KB per document)')
@allowed(['free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param searchServiceSku string = 'standard'

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

@description('Azure AI Foundry model deployment configuration')
param aiFoundryConfig object = {
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

@description('Deploy Virtual Network for private networking (recommended for internal-only Container App)')
param deployVNet bool = true

@description('Allow developer IP access to private resources (e.g. AI Search) for local development — false by default')
param allowDeveloperAccess bool = false

@description('Developer IP address to allow through firewalls when allowDeveloperAccess is true (auto-detected by deploy.sh)')
param developerIpAddress string = ''

@description('Blob container names to create in storage account')
param blobContainers array = [
  {
    name: 'pdfs'
  }
  {
    name: 'documents'
  }
  {
    name: 'pdf-images'
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
    disableLocalAuth: true  // MS security baseline: disable API key auth, enforce AAD-only
    // When developer access is enabled, allow the developer IP through the firewall alongside the private endpoint
    publicNetworkAccess: (deployVNet && !allowDeveloperAccess) ? 'disabled' : 'enabled'
    networkRuleSet: allowDeveloperAccess && !empty(developerIpAddress) ? {
      bypass: 'None'
      ipRules: [
        {
          value: developerIpAddress
        }
      ]
    } : {
      bypass: 'None'
      ipRules: []
    }
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
    allowSharedKeyAccess: false  // Security best practice from upstream
    publicNetworkAccess: 'Enabled'
  }
}

// Azure AI Foundry (AIServices) — unified multi-service resource with model deployments
module aiFoundry 'core/ai/cognitiveservices.bicep' = {
  name: 'ai-foundry'
  params: {
    name: 'aifs-${resourceToken}'
    location: location
    tags: tags
    kind: 'AIServices'
    customSubDomainName: 'aifs-${resourceToken}'
    disableLocalAuth: true  // MS security baseline: disable API key auth, enforce AAD-only
    deployments: concat(
      aiFoundryConfig.deployEmbeddings ? [{
        name: 'embeddings'
        model: {
          format: 'OpenAI'
          name: aiFoundryConfig.embeddingsModel
          version: aiFoundryConfig.embeddingsModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: 120
        }
      }] : [],
      aiFoundryConfig.deployGpt ? [{
        name: 'chat'
        model: {
          format: 'OpenAI'
          name: aiFoundryConfig.gptModel
          version: aiFoundryConfig.gptModelVersion
        }
        sku: {
          name: 'Standard'
          capacity: 30
        }
      }] : []
    )
  }
}

// NOTE: Search pipeline (data source, index, skillset, indexer) is deployed via
// setup-search-pipeline.sh after infrastructure deployment. ARM/Bicep cannot reliably
// deploy search data-plane resources (child resources of Microsoft.Search/searchServices).

// NSG for APIM subnet — required for APIM VNet integration
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = if (deployVNet && deployApim) {
  name: '${abbrs.networkNetworkSecurityGroups}apim-${resourceToken}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowClientToApim'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowApimManagement'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowSqlOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowAzureMonitorOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443', '1886']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          access: 'Allow'
          priority: 120
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Virtual Network — provides network isolation so Container App stays internal-only
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
        delegations: [
          {
            name: 'Microsoft.App.environments'
            properties: {
              serviceName: 'Microsoft.App/environments'
            }
          }
        ]
      }
      {
        name: 'apim'
        addressPrefix: '10.0.2.0/24'
        networkSecurityGroupId: (deployApim) ? apimNsg.id : null
      }
      {
        name: 'private-endpoints'
        addressPrefix: '10.0.3.0/24'
      }
      {
        name: 'sn-private-endpoint-ai-search'
        addressPrefix: '10.0.4.0/24'
      }
    ]
  }
}

// Container apps environment — deployed into VNet subnet when VNet is enabled
module containerAppsEnvironment 'core/host/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceName: logAnalytics.outputs.name
    infrastructureSubnetId: deployVNet ? vnet!.outputs.subnets[0].id : ''
  }
}

// Private DNS zone for internal Container Apps Environment
// Required so APIM (in the same VNet) can resolve internal Container App FQDNs
module privateDnsZone 'core/network/private-dns-zone.bicep' = if (deployVNet) {
  name: 'private-dns-zone'
  params: {
    zoneName: containerAppsEnvironment.outputs.domain
    vnetId: vnet!.outputs.id
    staticIp: containerAppsEnvironment.outputs.staticIp
    resourceToken: resourceToken
    tags: tags
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
  dependsOn: [
    acrPullRole   // Ensure AcrPull role is assigned before the container app registers the ACR identity
  ]
  params: {
    name: '${abbrs.appContainerApps}mcp-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    containerAppsEnvironmentName: containerAppsEnvironment.outputs.name
    containerRegistryName: containerRegistry.outputs.name
    containerName: 'mcp-azure-pdf'
    // imageName intentionally omitted — defaults to MCR placeholder on first deploy.
    // deploy.sh updates the container with the real ACR image after pushing it.
    managedIdentityName: managedIdentity.outputs.name
    external: true   // Accessible within the VNet. The Container Apps Environment is internal (internal: true),
                      // so the FQDN is only resolvable inside the VNet. APIM (in the same VNet) routes traffic here.
    workloadProfileName: 'Consumption'
    secrets: [
      {
        name: 'server-api-key'
        value: generatedApiKey
      }
    ]
    env: [
      {
        name: 'SEARCH_ENDPOINT'
        value: searchService.outputs.endpoint
      }
      {
        name: 'SEARCH_INDEX'
        value: searchIndexName
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
        name: 'AI_FOUNDRY_ENDPOINT'
        value: aiFoundry.outputs.endpoint
      }
      {
        name: 'AI_FOUNDRY_EMBEDDING_DEPLOYMENT'
        value: 'embeddings'
      }
      {
        name: 'AI_FOUNDRY_CHAT_DEPLOYMENT'
        value: 'chat'
      }
      {
        name: 'AZURE_CLIENT_ID'  // User-assigned MI client ID - used by DefaultAzureCredential for deterministic MI auth
        value: managedIdentity.outputs.clientId
      }
      {
        name: 'SERVER_API_KEY'
        secretRef: 'server-api-key'
      }
      {
        name: 'ALLOWED_ORIGINS'
        // Allow requests originating from APIM (for any browser clients proxied through APIM)
        value: deployApim ? 'https://${abbrs.apiManagementService}${resourceToken}.azure-api.net' : ''
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
    sku: {
      name: 'Developer'
      capacity: 1
    }
    backendUrl: 'https://${mcpServer.outputs.uri}'
    apiKey: generatedApiKey
    virtualNetworkType: deployVNet ? 'External' : 'None'
    subnetResourceId: deployVNet ? vnet!.outputs.subnets[1].id : ''
  }
}

// Private DNS zone for Azure AI Search
resource searchPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployVNet) {
  name: 'privatelink.search.windows.net'
  location: 'global'
  tags: tags
}

resource searchPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployVNet) {
  parent: searchPrivateDnsZone
  name: 'search-vnet-link-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnet!.outputs.id
    }
    registrationEnabled: false
  }
}

// Private endpoint for Azure AI Search — placed in dedicated search-pe subnet
module searchPrivateEndpoint 'core/network/private-endpoint.bicep' = if (deployVNet) {
  name: 'search-private-endpoint'
  params: {
    name: '${abbrs.networkPrivateEndpoints}srch-${resourceToken}'
    location: location
    tags: tags
    serviceId: searchService.outputs.id
    groupId: 'searchService'
    subnetId: vnet!.outputs.subnets[3].id  // search-pe subnet
    privateDnsZoneId: searchPrivateDnsZone.id
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

// Grant Search Index Data Reader role - required for read/query operations (separate from Contributor)
module searchReaderRole 'core/security/role.bicep' = {
  name: 'search-reader-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f' // Search Index Data Reader
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

// Grant Cognitive Services OpenAI User role for managed identity (AI Foundry)
module aiFoundryUserRole 'core/security/role.bicep' = {
  name: 'ai-foundry-user-role'
  params: {
    principalId: managedIdentity.outputs.principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
    principalType: 'ServicePrincipal'
  }
}

// Role assignments for search service system-assigned MI (indexer pipeline)
module searchStorageReaderRole 'core/security/role.bicep' = {
  name: 'search-storage-reader-role'
  params: {
    principalId: searchService.outputs.principalId
    roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' // Storage Blob Data Reader
    principalType: 'ServicePrincipal'
  }
}

module searchStorageContributorRole 'core/security/role.bicep' = {
  name: 'search-storage-contributor-role'
  params: {
    principalId: searchService.outputs.principalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor (knowledge store)
    principalType: 'ServicePrincipal'
  }
}

module searchAiFoundryUserRole 'core/security/role.bicep' = {
  name: 'search-ai-foundry-user-role'
  params: {
    principalId: searchService.outputs.principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User (AI Foundry)
    principalType: 'ServicePrincipal'
  }
}

module searchAiFoundryServicesUserRole 'core/security/role.bicep' = {
  name: 'search-ai-foundry-services-user-role'
  params: {
    principalId: searchService.outputs.principalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User (AI Foundry billing)
    principalType: 'ServicePrincipal'
  }
}

// Grant Search Service Contributor role to search service system-assigned managed identity
// Required when disableLocalAuth=true for indexer data-plane management (data sources, skillsets, indexers)
module searchServiceContributorRole 'core/security/role.bicep' = {
  name: 'search-service-contributor-role'
  params: {
    principalId: searchService.outputs.principalId
    roleDefinitionId: '7ca78c08-252a-4471-8644-bb5ff32d4ba0' // Search Service Contributor
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
output STORAGE_ACCOUNT_ID string = storageAccount.outputs.id
output STORAGE_BLOB_ENDPOINT string = storageAccount.outputs.blobEndpoint

output AI_FOUNDRY_NAME string = aiFoundry.outputs.name
output AI_FOUNDRY_ENDPOINT string = aiFoundry.outputs.endpoint
output AI_FOUNDRY_EMBEDDING_DEPLOYMENT string = 'embeddings'
output AI_FOUNDRY_CHAT_DEPLOYMENT string = 'chat'

output APIM_NAME string = deployApim ? apim!.outputs.name : ''
output APIM_GATEWAY_URL string = deployApim ? apim!.outputs.gatewayUrl : ''
output APIM_MCP_API_URL string = deployApim ? apim!.outputs.mcpApiUrl : ''
// APIM subscription key is NOT output here (security best practice — retrieve at runtime via az rest)

output CONTAINER_APP_NAME string = mcpServer.outputs.name
output MCP_SERVER_INTERNAL_URI string = mcpServer.outputs.uri
// MCP server API key is NOT output here (security best practice — retrieve at runtime via az containerapp secret show)
output MCP_PUBLIC_ENDPOINT string = deployApim ? '${apim!.outputs.mcpApiUrl}/api/tools' : mcpServer.outputs.uri

output AZURE_LOG_ANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.name  
output MANAGED_IDENTITY_NAME string = managedIdentity.outputs.name
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.outputs.clientId
output MANAGED_IDENTITY_ID string = managedIdentity.outputs.id
output AI_FOUNDRY_SUBDOMAIN_URL string = 'https://aifs-${resourceToken}.services.ai.azure.com'
output SEARCH_SERVICE_PRINCIPAL_ID string = searchService.outputs.principalId
