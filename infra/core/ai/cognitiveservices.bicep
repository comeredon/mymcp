metadata description = 'Creates an Azure Cognitive Services account (Azure OpenAI).'

param name string
param location string = resourceGroup().location
param tags object = {}

param kind string = 'OpenAI'
param sku object = {
  name: 'S0'
}
param customSubDomainName string = name
param publicNetworkAccess string = 'Enabled'
param disableLocalAuth bool = false

param deployments array = []

resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: kind
  sku: sku
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: publicNetworkAccess
    disableLocalAuth: disableLocalAuth
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = [for deployment in deployments: {
  parent: cognitiveServices
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: deployment.?raiPolicyName ?? null
  }
  sku: deployment.?sku ?? {
    name: 'Standard'
    capacity: 20
  }
}]

output id string = cognitiveServices.id
output name string = cognitiveServices.name
output endpoint string = cognitiveServices.properties.endpoint
output host string = split(cognitiveServices.properties.endpoint, '/')[2]
output key string = cognitiveServices.listKeys().key1
