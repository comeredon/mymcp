metadata description = 'Creates an Azure Container App.'

param name string
param location string = resourceGroup().location
param tags object = {}

param containerAppsEnvironmentName string
param containerRegistryName string
param containerName string = 'main'
param env array = []
param external bool = true
param imageName string = ''
param managedIdentityName string = ''
param resources object = {
  cpu: '0.25'
  memory: '0.5Gi'
}
param scale object = {
  minReplicas: 1
  maxReplicas: 10
}
param secrets array = []
param targetPort int = 80

@description('Workload profile name to use. Set to Consumption for VNet-integrated environments.')
param workloadProfileName string = ''

// Use ACR image when imageName is provided, otherwise fallback to a public placeholder
// This avoids MANIFEST_UNKNOWN errors on first deployment when the image hasn't been pushed yet
var containerImage = !empty(imageName) ? '${containerRegistry.properties.loginServer}/${imageName}:latest' : 'mcr.microsoft.com/k8se/quickstart:latest'

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppsEnvironmentName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: containerRegistryName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!empty(managedIdentityName)) {
  name: managedIdentityName
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: !empty(managedIdentityName) ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  } : {
    type: 'None'
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: external
        targetPort: targetPort
        transport: 'http'
        corsPolicy: {
          allowedOrigins: ['https://*.azure-api.net']
          allowedMethods: ['GET', 'POST', 'OPTIONS']
          allowedHeaders: ['Content-Type', 'x-api-key']
          allowCredentials: false
        }
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: !empty(managedIdentityName) ? managedIdentity.id : null
        }
      ]
      secrets: secrets
    }
    template: {
      containers: [
        {
          name: containerName
          image: containerImage
          env: env
          resources: resources
        }
      ]
      scale: scale
    }
    workloadProfileName: !empty(workloadProfileName) ? workloadProfileName : null
  }
}

output id string = containerApp.id
output name string = containerApp.name
output uri string = containerApp.properties.configuration.ingress.fqdn
output fqdn string = containerApp.properties.configuration.ingress.fqdn
