metadata description = 'Creates a Virtual Network with subnets.'

param name string
param location string = resourceGroup().location
param tags object = {}

param addressPrefix string = '10.0.0.0/16'
param subnets array = []

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        delegations: subnet.?delegations ?? []
        serviceEndpoints: subnet.?serviceEndpoints ?? []
        privateEndpointNetworkPolicies: subnet.?privateEndpointNetworkPolicies ?? 'Disabled'
        privateLinkServiceNetworkPolicies: subnet.?privateLinkServiceNetworkPolicies ?? 'Disabled'
        networkSecurityGroup: subnet.?networkSecurityGroupId != null ? {
          id: subnet.networkSecurityGroupId
        } : null
      }
    }]
  }
}

output id string = vnet.id
output name string = vnet.name
output subnets array = [for (subnet, i) in subnets: {
  name: vnet.properties.subnets[i].name
  id: vnet.properties.subnets[i].id
}]
