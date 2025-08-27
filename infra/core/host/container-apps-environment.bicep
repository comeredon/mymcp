metadata description = 'Creates an Azure Container Apps environment.'

param name string
param location string = resourceGroup().location
param tags object = {}

param logAnalyticsWorkspaceName string = ''

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {}
}

output name string = containerAppsEnvironment.name
output id string = containerAppsEnvironment.id
output domain string = containerAppsEnvironment.properties.defaultDomain