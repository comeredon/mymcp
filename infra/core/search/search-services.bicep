metadata description = 'Creates an Azure AI Search service.'

param name string
param location string = resourceGroup().location
param tags object = {}

param authOptions object = {}
param disableLocalAuth bool = false
param disabledDataExfiltrationOptions array = []
param encryptionWithCmk object = {
  enforcement: 'Unspecified'
}
param hostingMode string = 'default'
param networkRuleSet object = {
  bypass: 'None'
  ipRules: []
}
param partitionCount int = 1
param publicNetworkAccess string = 'enabled'
param replicaCount int = 1
param semanticSearch string = 'disabled'
param sku object = {
  name: 'standard'
}

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: sku
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // authOptions must be null when disableLocalAuth=true (Azure REST API requirement)
    authOptions: disableLocalAuth ? null : authOptions
    disableLocalAuth: disableLocalAuth
    encryptionWithCmk: encryptionWithCmk
    hostingMode: hostingMode
    networkRuleSet: networkRuleSet
    partitionCount: partitionCount
    publicNetworkAccess: publicNetworkAccess
    replicaCount: replicaCount
    semanticSearch: semanticSearch
  }
}

output id string = searchService.id
output name string = searchService.name
output endpoint string = 'https://${searchService.name}.search.windows.net/'
output principalId string = searchService.identity.principalId
