metadata description = 'Creates a private endpoint with a private DNS zone group.'

param name string
param location string = resourceGroup().location
param tags object = {}

@description('Resource ID of the target service to connect to via private endpoint.')
param serviceId string

@description('The group ID (sub-resource) for the private endpoint connection (e.g. searchService, blob, vault).')
param groupId string

@description('Resource ID of the subnet to place the private endpoint in.')
param subnetId string

@description('Resource IDs of the private DNS zones to register the endpoint in (supports multiple zones, e.g. AI Foundry needs two).')
param privateDnsZoneIds array

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: serviceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in privateDnsZoneIds: {
      name: '${groupId}-config-${i}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output id string = privateEndpoint.id
output name string = privateEndpoint.name
output networkInterfaceIds array = privateEndpoint.properties.networkInterfaces
