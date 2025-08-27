metadata description = 'Creates a Log Analytics workspace.'

param name string
param location string = resourceGroup().location
param tags object = {}

param retentionInDays int = 30
param sku object = {
  name: 'PerGB2018'
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    retentionInDays: retentionInDays
    sku: sku
  }
}

output id string = logAnalyticsWorkspace.id
output name string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId