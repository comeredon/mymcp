metadata description = 'Creates an Azure Storage Account for blob storage.'

param name string
param location string = resourceGroup().location
param tags object = {}

param kind string = 'StorageV2'
param sku object = {
  name: 'Standard_LRS'
}
param accessTier string = 'Hot'
param allowBlobPublicAccess bool = false
param allowSharedKeyAccess bool = true
param minimumTlsVersion string = 'TLS1_2'
param supportsHttpsTrafficOnly bool = true
param publicNetworkAccess string = 'Disabled'

@description('Virtual Network subnet IDs allowed to access storage')
param allowedSubnetIds array = []

param containers array = []

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: sku
  properties: {
    accessTier: accessTier
    allowBlobPublicAccess: allowBlobPublicAccess
    allowSharedKeyAccess: allowSharedKeyAccess
    minimumTlsVersion: minimumTlsVersion
    supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: !empty(allowedSubnetIds) ? 'Deny' : 'Allow'
      virtualNetworkRules: [for subnetId in allowedSubnetIds: {
        id: subnetId
        action: 'Allow'
      }]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = if (!empty(containers)) {
  parent: storageAccount
  name: 'default'
}

resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in containers: {
  parent: blobService
  name: container.name
  properties: {
    publicAccess: container.?publicAccess ?? 'None'
  }
}]

output id string = storageAccount.id
output name string = storageAccount.name
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
