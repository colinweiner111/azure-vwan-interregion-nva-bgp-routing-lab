param location1 string
param location2 string
param vwanName string
param hub1Name string
param hub2Name string
param branchVnetId string
param hub1Id string
param hub2Id string
param hub1DefaultRouteTableId string
param hub2DefaultRouteTableId string
@secure()
param vpnSharedKey string

resource branchPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'branch1-vpngw-pip-az'
  location: location1
  zones: ['1', '2', '3']
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource branchVpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-11-01' = {
  name: 'branch1-vpngw'
  location: location1
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    enableBgp: true
    bgpSettings: { asn: 65010 }
    ipConfigurations: [{
      name: 'default'
      properties: {
        privateIPAllocationMethod: 'Dynamic'
        subnet: { id: '${branchVnetId}/subnets/GatewaySubnet' }
        publicIPAddress: { id: branchPublicIp.id }
      }
    }]
  }
}

resource hub1VpnGw 'Microsoft.Network/vpnGateways@2023-11-01' = {
  name: '${hub1Name}-vpngw'
  location: location1
  properties: { virtualHub: { id: hub1Id }, bgpSettings: { asn: 65515 } }
}
resource hub2VpnGw 'Microsoft.Network/vpnGateways@2023-11-01' = {
  name: '${hub2Name}-vpngw'
  location: location2
  properties: { virtualHub: { id: hub2Id }, bgpSettings: { asn: 65515 } }
}

resource vpnSite 'Microsoft.Network/vpnSites@2023-11-01' = {
  name: 'site-branch1'
  location: location1
  properties: {
    virtualWan: { id: resourceId('Microsoft.Network/virtualWans', vwanName) }
    deviceProperties: { deviceVendor: 'Microsoft', deviceModel: 'Azure', linkSpeedInMbps: 50 }
    vpnSiteLinks: [{
      name: 'link1'
      properties: {
        ipAddress: branchPublicIp.properties.ipAddress
        bgpProperties: { asn: 65010, bgpPeeringAddress: branchVpnGateway.properties.bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0] }
        linkProperties: { linkSpeedInMbps: 50 }
      }
    }]
  }
}

resource hub1BranchConn 'Microsoft.Network/vpnGateways/vpnConnections@2023-11-01' = {
  parent: hub1VpnGw
  name: 'site-branch1-conn'
  properties: {
    remoteVpnSite: { id: vpnSite.id }
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: { id: hub1DefaultRouteTableId }
      propagatedRouteTables: { labels: ['Default', 'internet-only', 'private-only'], ids: [{ id: hub1DefaultRouteTableId }] }
    }
    vpnLinkConnections: [{ name: 'link1', properties: { vpnSiteLink: { id: '${vpnSite.id}/vpnSiteLinks/link1' }, sharedKey: vpnSharedKey, enableBgp: true } }]
  }
}
resource hub2BranchConn 'Microsoft.Network/vpnGateways/vpnConnections@2023-11-01' = {
  parent: hub2VpnGw
  name: 'site-branch1-conn'
  properties: {
    remoteVpnSite: { id: vpnSite.id }
    enableInternetSecurity: true
    routingConfiguration: {
      associatedRouteTable: { id: hub2DefaultRouteTableId }
      propagatedRouteTables: { labels: ['Default', 'internet-only', 'private-only'], ids: [{ id: hub2DefaultRouteTableId }] }
    }
    vpnLinkConnections: [{ name: 'link1', properties: { vpnSiteLink: { id: '${vpnSite.id}/vpnSiteLinks/link1' }, sharedKey: vpnSharedKey, enableBgp: true } }]
  }
}

var hubVpnGateways = [hub1VpnGw, hub2VpnGw]
var hubNames = [hub1Name, hub2Name]
resource localHubGateways 'Microsoft.Network/localNetworkGateways@2023-11-01' = [for item in [
  { hubIndex: 0, gatewayIndex: 0 }
  { hubIndex: 0, gatewayIndex: 1 }
  { hubIndex: 1, gatewayIndex: 0 }
  { hubIndex: 1, gatewayIndex: 1 }
]: {
  name: 'lng-${hubNames[item.hubIndex]}-gw${item.gatewayIndex + 1}'
  location: location1
  properties: {
    gatewayIpAddress: hubVpnGateways[item.hubIndex].properties.bgpSettings.bgpPeeringAddresses[item.gatewayIndex].tunnelIpAddresses[0]
    bgpSettings: { asn: 65515, bgpPeeringAddress: hubVpnGateways[item.hubIndex].properties.bgpSettings.bgpPeeringAddresses[item.gatewayIndex].defaultBgpIpAddresses[0] }
  }
}]

resource branchToHubConnections 'Microsoft.Network/connections@2023-11-01' = [for index in range(0, 4): {
  name: 'branch1-to-${hubNames[index < 2 ? 0 : 1]}-gw${(index % 2) + 1}'
  location: location1
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: any({ id: branchVpnGateway.id })
    localNetworkGateway2: any({ id: localHubGateways[index].id })
    sharedKey: vpnSharedKey
    enableBgp: true
  }
}]

output branchVpnGatewayId string = branchVpnGateway.id
output hub1VpnGwId string = hub1VpnGw.id
output hub2VpnGwId string = hub2VpnGw.id
output vpnSiteId string = vpnSite.id
/* Legacy divergent branch implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param location string
param branchNumber int
param branchPrefix string
param branchAsn int
param virtualWanId string
param hubId string
param hubName string
@secure()
param vpnSharedKey string

var branchName = 'branch${branchNumber}'

resource branchVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${branchName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [branchPrefix]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: cidrSubnet(branchPrefix, 27, 0)
        }
      }
      {
        name: 'workload'
        properties: {
          addressPrefix: cidrSubnet(branchPrefix, 26, 1)
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource branchPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${branchName}-vpngw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource branchGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: '${branchName}-vpngw'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enableBgp: true
    bgpSettings: {
      asn: branchAsn
    }
    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: branchPublicIp.id
          }
          subnet: {
            id: '${branchVnet.id}/subnets/GatewaySubnet'
          }
        }
      }
    ]
  }
}

resource hubVpnGateway 'Microsoft.Network/vpnGateways@2024-05-01' = {
  name: '${hubName}-vpngw'
  location: location
  properties: {
    virtualHub: {
      id: hubId
    }
    bgpSettings: {
      asn: 65515
    }
  }
}

resource vpnSite 'Microsoft.Network/vpnSites@2024-05-01' = {
  name: '${branchName}-site'
  location: location
  properties: {
    virtualWan: {
      id: virtualWanId
    }
    deviceProperties: {
      deviceModel: 'Azure VPN Gateway'
      deviceVendor: 'Microsoft'
      linkSpeedInMbps: 50
    }
    vpnSiteLinks: [
      {
        name: 'link1'
        properties: {
          ipAddress: branchPublicIp.properties.ipAddress
          bgpProperties: {
            asn: branchAsn
            bgpPeeringAddress: branchGateway.properties.bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]
          }
          linkProperties: {
            linkSpeedInMbps: 50
          }
        }
      }
    ]
  }
}

resource hubToBranch 'Microsoft.Network/vpnGateways/vpnConnections@2024-05-01' = {
  parent: hubVpnGateway
  name: '${branchName}-connection'
  properties: {
    remoteVpnSite: {
      id: vpnSite.id
    }
    enableInternetSecurity: false
    vpnLinkConnections: [
      {
        name: 'link1'
        properties: {
          enableBgp: true
          sharedKey: vpnSharedKey
          vpnSiteLink: {
            id: '${vpnSite.id}/vpnSiteLinks/link1'
          }
        }
      }
    ]
  }
}

resource hubTunnelPeers 'Microsoft.Network/localNetworkGateways@2024-05-01' = [for tunnelIndex in range(0, 2): {
  name: '${branchName}-${hubName}-tunnel${tunnelIndex + 1}'
  location: location
  properties: {
    gatewayIpAddress: hubVpnGateway.properties.bgpSettings.bgpPeeringAddresses[tunnelIndex].tunnelIpAddresses[0]
    bgpSettings: {
      asn: 65515
      bgpPeeringAddress: hubVpnGateway.properties.bgpSettings.bgpPeeringAddresses[tunnelIndex].defaultBgpIpAddresses[0]
    }
  }
}]

resource branchToHubTunnels 'Microsoft.Network/connections@2024-05-01' = [for tunnelIndex in range(0, 2): {
  name: '${branchName}-to-${hubName}-tunnel${tunnelIndex + 1}'
  location: location
  properties: {
    connectionType: 'IPsec'
    enableBgp: true
    sharedKey: vpnSharedKey
    virtualNetworkGateway1: any({
      id: branchGateway.id
    })
    localNetworkGateway2: any({
      id: hubTunnelPeers[tunnelIndex].id
    })
  }
}]

output branchWorkloadSubnetId string = '${branchVnet.id}/subnets/workload'
output hubVpnGatewayId string = hubVpnGateway.id
*/
