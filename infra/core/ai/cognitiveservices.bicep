metadata description = 'Creates an Azure Cognitive Services account (Azure AI Foundry / AIServices).'

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

@description('IP addresses to allow through the firewall (e.g. developer IP for local access)')
param ipRules array = []

param deployments array = []

resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
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
      defaultAction: !empty(ipRules) ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
      ipRules: [for ipRule in ipRules: {
        value: ipRule
      }]
    }
  }
}

@batchSize(1)
resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for deployment in deployments: {
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
output aiServicesEndpoint string = 'https://${customSubDomainName}.services.ai.azure.com'
