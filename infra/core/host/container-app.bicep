metadata description = 'Creates an Azure Container App.'

param name string
param location string = resourceGroup().location
param tags object = {}

param containerAppsEnvironmentName string
param containerRegistryName string
param containerName string = 'main'
param env array = []
param external bool = true
param imageName string
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
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
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
          image: '${containerRegistry.properties.loginServer}/${imageName}:latest'
          env: env
          resources: resources
        }
      ]
      scale: scale
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output uri string = containerApp.properties.configuration.ingress.fqdn
output fqdn string = containerApp.properties.configuration.ingress.fqdn