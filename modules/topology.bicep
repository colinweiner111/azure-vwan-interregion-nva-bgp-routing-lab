targetScope = 'resourceGroup'

param region1 string
param region2 string
param hub1Name string
param hub2Name string
param transit1VnetId string
param transit2VnetId string
param region1LoadBalancerIp string
param region2LoadBalancerIp string

var directSpokes = [
  { name: 'spoke1-direct-${region1}', location: region1, prefix: '10.10.0.0/24', hubIndex: 0 }
  { name: 'spoke3-direct-${region2}', location: region2, prefix: '10.138.0.0/24', hubIndex: 1 }
]
var indirectSpokes = [
  { name: 'spoke5-indirect-${region1}', location: region1, prefix: '10.12.0.0/24', regionIndex: 0 }
  { name: 'spoke6-indirect-${region1}', location: region1, prefix: '10.13.0.0/24', regionIndex: 0 }
  { name: 'spoke7-indirect-${region2}', location: region2, prefix: '10.140.0.0/24', regionIndex: 1 }
  { name: 'spoke8-indirect-${region2}', location: region2, prefix: '10.141.0.0/24', regionIndex: 1 }
]
var transitVnetIds = [transit1VnetId, transit2VnetId]
var loadBalancerIps = [region1LoadBalancerIp, region2LoadBalancerIp]

resource indirectRouteTables 'Microsoft.Network/routeTables@2024-05-01' = [for spoke in indirectSpokes: {
  name: '${spoke.name}-udr'
  location: spoke.location
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      {
        name: 'default-via-nva'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: loadBalancerIps[spoke.regionIndex]
        }
      }
    ]
  }
}]

resource directVnets 'Microsoft.Network/virtualNetworks@2024-05-01' = [for spoke in directSpokes: {
  name: spoke.name
  location: spoke.location
  properties: {
    addressSpace: {
      addressPrefixes: [spoke.prefix]
    }
    subnets: [
      {
        name: 'workload'
        properties: {
          addressPrefix: spoke.prefix
          defaultOutboundAccess: false
        }
      }
    ]
  }
}]

resource indirectVnets 'Microsoft.Network/virtualNetworks@2024-05-01' = [for (spoke, index) in indirectSpokes: {
  name: spoke.name
  location: spoke.location
  properties: {
    addressSpace: {
      addressPrefixes: [spoke.prefix]
    }
    subnets: [
      {
        name: 'workload'
        properties: {
          addressPrefix: spoke.prefix
          defaultOutboundAccess: false
          routeTable: {
            id: indirectRouteTables[index].id
          }
        }
      }
    ]
  }
}]

resource hubs 'Microsoft.Network/virtualHubs@2024-05-01' existing = [for hubName in [hub1Name, hub2Name]: {
  name: hubName
}]

resource directHubConnections 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = [for (spoke, index) in directSpokes: {
  parent: hubs[spoke.hubIndex]
  name: '${spoke.name}-connection'
  properties: {
    enableInternetSecurity: false
    remoteVirtualNetwork: {
      id: directVnets[index].id
    }
  }
}]

resource indirectToTransitPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = [for (spoke, index) in indirectSpokes: {
  parent: indirectVnets[index]
  name: 'to-transit'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: transitVnetIds[spoke.regionIndex]
    }
  }
}]

resource transitVnets 'Microsoft.Network/virtualNetworks@2024-05-01' existing = [for transitId in transitVnetIds: {
  name: last(split(transitId, '/'))
}]

resource transitToIndirectPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = [for (spoke, index) in indirectSpokes: {
  parent: transitVnets[spoke.regionIndex]
  name: 'to-${spoke.name}'
  properties: {
    allowForwardedTraffic: true
    allowVirtualNetworkAccess: true
    remoteVirtualNetwork: {
      id: indirectVnets[index].id
    }
  }
}]

output directWorkloadSubnetIds string[] = [for index in range(0, length(directSpokes)): '${directVnets[index].id}/subnets/workload']
output indirectWorkloadSubnetIds string[] = [for index in range(0, length(indirectSpokes)): '${indirectVnets[index].id}/subnets/workload']
