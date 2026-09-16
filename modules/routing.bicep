param hub1Name string
param hub2Name string
param hub1NvaVnetId string
param hub2NvaVnetId string
param hub1NvaLoadBalancerIp string
param hub2NvaLoadBalancerIp string
param spoke2Hub1Id string
param spoke2Hub2Id string
param spoke1Hub1Prefixes string[]
param spoke1Hub2Prefixes string[]

resource hub1 'Microsoft.Network/virtualHubs@2023-11-01' existing = { name: hub1Name }
resource hub2 'Microsoft.Network/virtualHubs@2023-11-01' existing = { name: hub2Name }

var hub1NvaConnectionId = resourceId('Microsoft.Network/virtualHubs/hubVirtualNetworkConnections', hub1Name, 'hub1-nva-transit-conn')
var hub2NvaConnectionId = resourceId('Microsoft.Network/virtualHubs/hubVirtualNetworkConnections', hub2Name, 'hub2-nva-transit-conn')
var protectedRoutes = [
  { name: 'Hub1Spoke1ViaNvaConnection', destinationType: 'CIDR', destinations: spoke1Hub1Prefixes, nextHopType: 'ResourceId', nextHop: hub1NvaConnectionId }
  { name: 'Hub2Spoke1ViaNvaConnection', destinationType: 'CIDR', destinations: spoke1Hub2Prefixes, nextHopType: 'ResourceId', nextHop: hub2NvaConnectionId }
]

resource hub1DefaultRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: hub1
  name: 'defaultRouteTable'
  properties: { labels: ['default'], routes: protectedRoutes }
  dependsOn: [hub1NvaConnection, hub2NvaConnection]
}
resource hub2DefaultRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: hub2
  name: 'defaultRouteTable'
  properties: { labels: ['default'], routes: protectedRoutes }
  dependsOn: [hub1DefaultRouteTable]
}
resource hub1InternetOnlyRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: hub1
  name: 'internetOnlyRouteTable'
  properties: { labels: ['internet-only'], routes: concat(protectedRoutes, [{ name: 'InternetViaLocalNvaConnection', destinationType: 'CIDR', destinations: ['0.0.0.0/0'], nextHopType: 'ResourceId', nextHop: hub1NvaConnectionId }]) }
  dependsOn: [hub2DefaultRouteTable]
}
resource hub2InternetOnlyRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: hub2
  name: 'internetOnlyRouteTable'
  properties: { labels: ['internet-only'], routes: concat(protectedRoutes, [{ name: 'InternetViaLocalNvaConnection', destinationType: 'CIDR', destinations: ['0.0.0.0/0'], nextHopType: 'ResourceId', nextHop: hub2NvaConnectionId }]) }
  dependsOn: [hub1InternetOnlyRouteTable]
}
resource hub1PrivateRouteTable 'Microsoft.Network/virtualHubs/hubRouteTables@2023-11-01' = {
  parent: hub1
  name: 'privateOnlyRouteTable'
  properties: { labels: ['private-only'], routes: protectedRoutes }
  dependsOn: [hub2InternetOnlyRouteTable]
}

resource hub1NvaConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: hub1
  name: 'hub1-nva-transit-conn'
  properties: {
    remoteVirtualNetwork: { id: hub1NvaVnetId }
    enableInternetSecurity: false
    routingConfiguration: {
      associatedRouteTable: { id: resourceId('Microsoft.Network/virtualHubs/hubRouteTables', hub1Name, 'defaultRouteTable') }
      propagatedRouteTables: { labels: ['none'], ids: [{ id: resourceId('Microsoft.Network/virtualHubs/hubRouteTables', hub1Name, 'noneRouteTable') }] }
      vnetRoutes: {
        staticRoutes: [
          { name: 'ProtectedSpokeToNva', addressPrefixes: spoke1Hub1Prefixes, nextHopIpAddress: hub1NvaLoadBalancerIp }
          { name: 'InternetToNva', addressPrefixes: ['0.0.0.0/0'], nextHopIpAddress: hub1NvaLoadBalancerIp }
        ]
        staticRoutesConfig: { vnetLocalRouteOverrideCriteria: 'Equal' }
      }
    }
  }
}
resource hub2NvaConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: hub2
  name: 'hub2-nva-transit-conn'
  properties: {
    remoteVirtualNetwork: { id: hub2NvaVnetId }
    enableInternetSecurity: false
    routingConfiguration: {
      associatedRouteTable: { id: resourceId('Microsoft.Network/virtualHubs/hubRouteTables', hub2Name, 'defaultRouteTable') }
      propagatedRouteTables: { labels: ['none'], ids: [{ id: resourceId('Microsoft.Network/virtualHubs/hubRouteTables', hub2Name, 'noneRouteTable') }] }
      vnetRoutes: {
        staticRoutes: [
          { name: 'ProtectedSpokeToNva', addressPrefixes: spoke1Hub2Prefixes, nextHopIpAddress: hub2NvaLoadBalancerIp }
          { name: 'InternetToNva', addressPrefixes: ['0.0.0.0/0'], nextHopIpAddress: hub2NvaLoadBalancerIp }
        ]
        staticRoutesConfig: { vnetLocalRouteOverrideCriteria: 'Equal' }
      }
    }
  }
}

resource hub1Spoke2Connection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: hub1
  name: 'hub1-spoke2-conn'
  properties: {
    remoteVirtualNetwork: { id: spoke2Hub1Id }
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: { id: hub1InternetOnlyRouteTable.id }
      propagatedRouteTables: { labels: ['Default', 'internet-only', 'private-only'], ids: [{ id: hub1DefaultRouteTable.id }] }
    }
  }
  dependsOn: [hub1PrivateRouteTable]
}
resource hub2Spoke2Connection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: hub2
  name: 'hub2-spoke2-conn'
  properties: {
    remoteVirtualNetwork: { id: spoke2Hub2Id }
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: { id: hub2InternetOnlyRouteTable.id }
      propagatedRouteTables: { labels: ['Default', 'internet-only', 'private-only'], ids: [{ id: hub2DefaultRouteTable.id }] }
    }
  }
  dependsOn: [hub1Spoke2Connection]
}

output hub1NvaConnectionName string = hub1NvaConnection.name
output hub2NvaConnectionName string = hub2NvaConnection.name
output hub1InternetOnlyRouteTableId string = hub1InternetOnlyRouteTable.id
output hub2InternetOnlyRouteTableId string = hub2InternetOnlyRouteTable.id
output hub1PrivateRouteTableId string = hub1PrivateRouteTable.id
output hub1DefaultRouteTableId string = hub1DefaultRouteTable.id
output hub2DefaultRouteTableId string = hub2DefaultRouteTable.id
