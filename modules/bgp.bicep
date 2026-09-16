param location1 string
param location2 string
param hub1Name string
param hub2Name string
param hub1NvaConnectionName string
param hub2NvaConnectionName string
param hub1RouterIps string[]
param hub2RouterIps string[]
param hub1NvaVmNames string[]
param hub2NvaVmNames string[]
param hub1NvaPeerIps string[]
param hub2NvaPeerIps string[]

var nvaAsn = 65020
var locations = [location1, location2]
var hubNames = [hub1Name, hub2Name]
var connectionNames = [hub1NvaConnectionName, hub2NvaConnectionName]
var hubRouterIps = [hub1RouterIps, hub2RouterIps]
var nvaVmNames = [hub1NvaVmNames, hub2NvaVmNames]
var nvaPeerIps = [hub1NvaPeerIps, hub2NvaPeerIps]
var advertisedPrefixes = ['172.16.1.0/24', '172.16.3.0/24']
var loadBalancerIps = ['172.16.10.10', '172.16.20.10']
var configureFrrScript = base64(loadTextContent('../scripts/configure-frr-nva.sh'))
var nvaInstances = [
  { hubIndex: 0, nvaIndex: 0 }
  { hubIndex: 0, nvaIndex: 1 }
  { hubIndex: 1, nvaIndex: 0 }
  { hubIndex: 1, nvaIndex: 1 }
]

resource hubs 'Microsoft.Network/virtualHubs@2023-11-01' existing = [for hubName in hubNames: {
  name: hubName
}]

resource nvaConnections 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' existing = [for hubIndex in range(0, 2): {
  parent: hubs[hubIndex]
  name: connectionNames[hubIndex]
}]

@batchSize(1)
resource bgpConnections 'Microsoft.Network/virtualHubs/bgpConnections@2023-11-01' = [for item in nvaInstances: {
  parent: hubs[item.hubIndex]
  name: '${hubNames[item.hubIndex]}-nva${item.nvaIndex + 1}-bgp'
  properties: {
    hubVirtualNetworkConnection: {
      id: nvaConnections[item.hubIndex].id
    }
    peerAsn: nvaAsn
    peerIp: nvaPeerIps[item.hubIndex][item.nvaIndex]
  }
}]

resource nvaVms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for item in nvaInstances: {
  name: nvaVmNames[item.hubIndex][item.nvaIndex]
}]

resource configureFrr 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for item in nvaInstances: {
  parent: nvaVms[item.hubIndex * 2 + item.nvaIndex]
  name: 'configure-frr-bgp'
  location: locations[item.hubIndex]
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    forceUpdateTag: 'private-nat-exclusions-v4'
    settings: {
      commandToExecute: 'echo "${configureFrrScript}" | base64 --decode > /usr/local/sbin/configure-frr-nva.sh && chmod 0755 /usr/local/sbin/configure-frr-nva.sh && /usr/local/sbin/configure-frr-nva.sh "${join(hubRouterIps[item.hubIndex], ',')}" "${advertisedPrefixes[item.hubIndex]}" "${nvaAsn}" "${loadBalancerIps[item.hubIndex]}"'
    }
  }
}]

output hub1BgpConnectionIds string[] = [bgpConnections[0].id, bgpConnections[1].id]
output hub2BgpConnectionIds string[] = [bgpConnections[2].id, bgpConnections[3].id]
/* Legacy divergent BGP implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param hub1Name string
param hub2Name string
param hub1TransitConnectionName string
param hub2TransitConnectionName string
param hub1NvaPeerIps string[]
param hub2NvaPeerIps string[]

var nvaAsn = 65020

resource hub1 'Microsoft.Network/virtualHubs@2024-05-01' existing = {
  name: hub1Name
}

resource hub2 'Microsoft.Network/virtualHubs@2024-05-01' existing = {
  name: hub2Name
}

resource hub1TransitConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' existing = {
  parent: hub1
  name: hub1TransitConnectionName
}

resource hub2TransitConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' existing = {
  parent: hub2
  name: hub2TransitConnectionName
}

resource hub1BgpConnections 'Microsoft.Network/virtualHubs/bgpConnections@2024-05-01' = [for (peerIp, index) in hub1NvaPeerIps: {
  parent: hub1
  param hub1NvaConnectionName string
  param hub2NvaConnectionName string
  param hub1RouterIps string[]
  param hub2RouterIps string[]
  var nvaAsn = 65020
  var locations = [location1, location2]
  var hubNames = [hub1Name, hub2Name]
  var connectionNames = [hub1NvaConnectionName, hub2NvaConnectionName]
  var hubRouterIps = [hub1RouterIps, hub2RouterIps]
  var nvaPeerIps = [hub1NvaPeerIps, hub2NvaPeerIps]
  var advertisedPrefixes = ['172.16.1.0/24', '172.16.3.0/24']
  var nvaInstances = [
    { hubIndex: 0, nvaIndex: 0 }
    { hubIndex: 0, nvaIndex: 1 }
    { hubIndex: 1, nvaIndex: 0 }
    { hubIndex: 1, nvaIndex: 1 }
  ]
  name: 'nva${index + 1}-bgp'
  properties: {
    hubVirtualNetworkConnection: {
      id: hub1TransitConnection.id
    }
    peerAsn: nvaAsn
    peerIp: peerIp
  }
}]

resource hub2BgpConnections 'Microsoft.Network/virtualHubs/bgpConnections@2024-05-01' = [for (peerIp, index) in hub2NvaPeerIps: {
  parent: hub2
  name: 'nva${index + 1}-bgp'
  properties: {
    hubVirtualNetworkConnection: {
      id: hub2TransitConnection.id
    }
    peerAsn: nvaAsn
    peerIp: peerIp
  }
}]

output hub1BgpConnectionIds string[] = [for index in range(0, length(hub1NvaPeerIps)): hub1BgpConnections[index].id]
output hub2BgpConnectionIds string[] = [for index in range(0, length(hub2NvaPeerIps)): hub2BgpConnections[index].id]
*/
