param location1 string
param location2 string
param vwanName string
param hub1Name string
param hub2Name string
param hub1NvaVnetId string
param hub2NvaVnetId string
param hub1NvaLoadBalancerIp string
param hub2NvaLoadBalancerIp string

resource hub1NvaVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = { name: last(split(hub1NvaVnetId, '/')) }
resource hub2NvaVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = { name: last(split(hub2NvaVnetId, '/')) }

resource hub1Spoke1Routes 'Microsoft.Network/routeTables@2023-11-01' = {
  name: '${hub1Name}-spoke1-to-nva'
  location: location1
  properties: {
    disableBgpRoutePropagation: true
    routes: [{ name: 'DefaultToNva', properties: { addressPrefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIpAddress: hub1NvaLoadBalancerIp } }]
  }
}

resource hub2Spoke1Routes 'Microsoft.Network/routeTables@2023-11-01' = {
  name: '${hub2Name}-spoke1-to-nva'
  location: location2
  properties: {
    disableBgpRoutePropagation: true
    routes: [{ name: 'DefaultToNva', properties: { addressPrefix: '0.0.0.0/0', nextHopType: 'VirtualAppliance', nextHopIpAddress: hub2NvaLoadBalancerIp } }]
  }
}

resource vwan 'Microsoft.Network/virtualWans@2023-11-01' = {
  name: vwanName
  location: location1
  properties: { type: 'Standard', allowBranchToBranchTraffic: true }
}

resource hub1 'Microsoft.Network/virtualHubs@2023-11-01' = {
  name: hub1Name
  location: location1
  properties: { addressPrefix: '192.168.0.0/22', virtualWan: { id: vwan.id }, sku: 'Standard', hubRoutingPreference: 'ASPath' }
}

resource hub2 'Microsoft.Network/virtualHubs@2023-11-01' = {
  name: hub2Name
  location: location2
  properties: { addressPrefix: '192.168.4.0/22', virtualWan: { id: vwan.id }, sku: 'Standard', hubRoutingPreference: 'ASPath' }
}

resource branchVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'branch1'
  location: location1
  properties: { addressSpace: { addressPrefixes: ['10.100.0.0/16'] } }
}

resource bastionVnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'bastion-vnet'
  location: location1
  properties: { addressSpace: { addressPrefixes: ['10.200.0.0/24'] } }
}

resource spoke1Hub1 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'hub1-spoke1'
  location: location1
  properties: { addressSpace: { addressPrefixes: ['172.16.1.0/24'] } }
}

resource spoke2Hub1 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'hub1-spoke2'
  location: location1
  properties: { addressSpace: { addressPrefixes: ['172.16.2.0/24'] } }
}

resource spoke1Hub2 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'hub2-spoke1'
  location: location2
  properties: { addressSpace: { addressPrefixes: ['172.16.3.0/24'] } }
}

resource spoke2Hub2 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'hub2-spoke2'
  location: location2
  properties: { addressSpace: { addressPrefixes: ['172.16.4.0/24'] } }
}

resource nsgHub1 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'default-nsg-${hub1Name}-${location1}'
  location: location1
  properties: {
    securityRules: [
      { name: 'allow-bastion-ssh', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: '10.200.0.0/26', sourcePortRange: '*', destinationAddressPrefix: '*', destinationPortRange: '22' } }
      { name: 'allow-lab-ssh-tests', properties: { priority: 110, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefixes: ['10.100.0.0/24', '172.16.1.0/27', '172.16.2.0/27', '172.16.3.0/27', '172.16.4.0/27'], sourcePortRange: '*', destinationAddressPrefixes: ['10.100.0.0/24', '172.16.1.0/27', '172.16.2.0/27'], destinationPortRange: '22' } }
    ]
  }
}

resource nsgHub2 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'default-nsg-${hub2Name}-${location2}'
  location: location2
  properties: {
    securityRules: [
      { name: 'allow-bastion-ssh', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: '10.200.0.0/26', sourcePortRange: '*', destinationAddressPrefix: '*', destinationPortRange: '22' } }
      { name: 'allow-lab-ssh-tests', properties: { priority: 110, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefixes: ['10.100.0.0/24', '172.16.1.0/27', '172.16.2.0/27', '172.16.3.0/27', '172.16.4.0/27'], sourcePortRange: '*', destinationAddressPrefixes: ['172.16.3.0/27', '172.16.4.0/27'], destinationPortRange: '22' } }
    ]
  }
}

resource spoke1Hub1Subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: spoke1Hub1
  name: 'main'
  properties: { addressPrefix: '172.16.1.0/27', defaultOutboundAccess: false, routeTable: { id: hub1Spoke1Routes.id }, networkSecurityGroup: { id: nsgHub1.id } }
}
resource spoke2Hub1Subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: spoke2Hub1
  name: 'main'
  properties: { addressPrefix: '172.16.2.0/27', networkSecurityGroup: { id: nsgHub1.id } }
}
resource spoke1Hub2Subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: spoke1Hub2
  name: 'main'
  properties: { addressPrefix: '172.16.3.0/27', defaultOutboundAccess: false, routeTable: { id: hub2Spoke1Routes.id }, networkSecurityGroup: { id: nsgHub2.id } }
}
resource spoke2Hub2Subnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: spoke2Hub2
  name: 'main'
  properties: { addressPrefix: '172.16.4.0/27', networkSecurityGroup: { id: nsgHub2.id } }
}
resource branchSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: branchVnet
  name: 'main'
  properties: { addressPrefix: '10.100.0.0/24', networkSecurityGroup: { id: nsgHub1.id } }
}
resource branchGatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: branchVnet
  name: 'GatewaySubnet'
  properties: { addressPrefix: '10.100.255.0/27' }
  dependsOn: [branchSubnet]
}

resource hub1NvaToSpoke1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hub1NvaVnet
  name: 'nva-transit-to-spoke1'
  properties: { remoteVirtualNetwork: { id: spoke1Hub1.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, allowGatewayTransit: false, useRemoteGateways: false }
  dependsOn: [spoke1Hub1Subnet]
}
resource hub1Spoke1ToNva 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spoke1Hub1
  name: 'spoke1-to-nva-transit'
  properties: { remoteVirtualNetwork: { id: hub1NvaVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, allowGatewayTransit: false, useRemoteGateways: false }
  dependsOn: [spoke1Hub1Subnet]
}
resource hub2NvaToSpoke1 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: hub2NvaVnet
  name: 'nva-transit-to-spoke1'
  properties: { remoteVirtualNetwork: { id: spoke1Hub2.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, allowGatewayTransit: false, useRemoteGateways: false }
  dependsOn: [spoke1Hub2Subnet]
}
resource hub2Spoke1ToNva 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spoke1Hub2
  name: 'spoke1-to-nva-transit'
  properties: { remoteVirtualNetwork: { id: hub2NvaVnet.id }, allowVirtualNetworkAccess: true, allowForwardedTraffic: true, allowGatewayTransit: false, useRemoteGateways: false }
  dependsOn: [spoke1Hub2Subnet]
}

output vwanId string = vwan.id
output hub1Id string = hub1.id
output hub2Id string = hub2.id
output hub1RouterIps string[] = hub1.properties.virtualRouterIps
output hub2RouterIps string[] = hub2.properties.virtualRouterIps
output branchVnetId string = branchVnet.id
output bastionVnetId string = bastionVnet.id
output spoke1Hub1Id string = spoke1Hub1.id
output spoke2Hub1Id string = spoke2Hub1.id
output spoke1Hub2Id string = spoke1Hub2.id
output spoke2Hub2Id string = spoke2Hub2.id
output spoke1Hub1Prefixes string[] = spoke1Hub1.properties.addressSpace.addressPrefixes
output spoke1Hub2Prefixes string[] = spoke1Hub2.properties.addressSpace.addressPrefixes
/* Legacy divergent network implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param region1 string
param region2 string
param virtualWanName string

resource virtualWan 'Microsoft.Network/virtualWans@2024-05-01' = {
  name: virtualWanName
  location: region1
  properties: {
    allowBranchToBranchTraffic: true
    disableVpnEncryption: false
    type: 'Standard'
  }
}

resource hub1 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: 'hub1-${region1}'
  location: region1
  properties: {
    addressPrefix: '10.0.0.0/24'
    sku: 'Standard'
    virtualWan: {
      id: virtualWan.id
    }
  }
}

resource hub2 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: 'hub2-${region2}'
  location: region2
  properties: {
    addressPrefix: '10.128.0.0/24'
    sku: 'Standard'
    virtualWan: {
      id: virtualWan.id
    }
  }
}

resource transit1 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'spoke2-transit-${region1}'
  location: region1
  properties: {
    addressSpace: {
      addressPrefixes: ['10.11.0.0/24']
    }
    subnets: [
      {
        name: 'nva'
        properties: {
          addressPrefix: '10.11.0.0/27'
        }
      }
      {
        name: 'workload'
        properties: {
          addressPrefix: '10.11.0.64/26'
        }
      }
    ]
  }
}

resource transit2 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'spoke4-transit-${region2}'
  location: region2
  properties: {
    addressSpace: {
      addressPrefixes: ['10.139.0.0/24']
    }
    subnets: [
      {
        name: 'nva'
        properties: {
          addressPrefix: '10.139.0.0/27'
        }
      }
      {
        name: 'workload'
        properties: {
          addressPrefix: '10.139.0.64/26'
        }
      }
    ]
  }
}

resource hub1TransitConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: hub1
  name: 'spoke2-transit-connection'
  properties: {
    enableInternetSecurity: false
    remoteVirtualNetwork: {
      id: transit1.id
    }
  }
}

resource hub2TransitConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: hub2
  name: 'spoke4-transit-connection'
  properties: {
    enableInternetSecurity: false
    remoteVirtualNetwork: {
      id: transit2.id
    }
  }
}

output virtualWanId string = virtualWan.id
output hub1Id string = hub1.id
output hub2Id string = hub2.id
output hub1Name string = hub1.name
output hub2Name string = hub2.name
output hub1TransitConnectionName string = hub1TransitConnection.name
output hub2TransitConnectionName string = hub2TransitConnection.name
output hub1RouterIps string[] = hub1.properties.virtualRouterIps
output hub2RouterIps string[] = hub2.properties.virtualRouterIps
output transit1VnetId string = transit1.id
output transit2VnetId string = transit2.id
*/
