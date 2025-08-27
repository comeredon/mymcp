metadata description = 'Creates an Azure Container Apps environment.'

param name string
param location string = resourceGroup().location
param tags object = {}

param logAnalyticsWorkspaceName string = ''
param logAnalyticsWorkspaceRG string = ''

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = if (!empty(logAnalyticsWorkspaceName)) {
  name: logAnalyticsWorkspaceName
  scope: !empty(logAnalyticsWorkspaceRG) ? resourceGroup(logAnalyticsWorkspaceRG) : resourceGroup()
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: !empty(logAnalyticsWorkspaceName) ? {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    } : {
      destination: 'azure-monitor'
    }
    zoneRedundant: false
  }
}

output name string = containerAppsEnvironment.name
output id string = containerAppsEnvironment.id
output domain string = containerAppsEnvironment.properties.defaultDomain