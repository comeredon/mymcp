metadata description = 'Creates a private DNS zone with a VNet link and wildcard A record for internal Container Apps.'

@description('The DNS zone name (e.g. the Container Apps Environment default domain)')
param zoneName string

@description('Resource ID of the VNet to link')
param vnetId string

@description('Static IP address for the wildcard A record')
param staticIp string

@description('Resource token for naming')
param resourceToken string

param tags object = {}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-link-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource privateDnsWildcard 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: '*'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}

output id string = privateDnsZone.id
output name string = privateDnsZone.name
