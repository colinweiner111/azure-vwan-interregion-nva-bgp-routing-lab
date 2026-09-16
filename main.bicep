targetScope = 'subscription'

@description('Primary region for deployment')
param region1 string = 'westus3'

@description('Region for Hub 2 resources')
param region2 string = 'westus3'

@description('Resource group name')
param resourceGroupName string = 'vwan-interregion-nva-bgp-lab'

@description('Virtual WAN name')
param vwanName string = 'vwan-spoke-nva-demo'

@description('Hub 1 name')
param hub1Name string = 'hub1'

@description('Hub 2 name')
param hub2Name string = 'hub2'

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('Admin password for VMs')
@secure()
param adminPassword string

@description('Pre-shared key for the site-to-site VPN connections')
@secure()
param vpnSharedKey string

@description('VM size')
param vmSize string = 'Standard_D2ls_v7'

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: region1
}

module nva 'modules/nva.bicep' = {
  scope: rg
  name: 'nva-infrastructure-deployment'
  params: {
    location1: region1
    location2: region2
    hub1Name: hub1Name
    hub2Name: hub2Name
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
}

module network 'modules/network.bicep' = {
  scope: rg
  name: 'network-deployment'
  params: {
    location1: region1
    location2: region2
    vwanName: vwanName
    hub1Name: hub1Name
    hub2Name: hub2Name
    hub1NvaVnetId: nva.outputs.hub1NvaVnetId
    hub2NvaVnetId: nva.outputs.hub2NvaVnetId
    hub1NvaLoadBalancerIp: nva.outputs.hub1LoadBalancerIp
    hub2NvaLoadBalancerIp: nva.outputs.hub2LoadBalancerIp
  }
}

module vpn 'modules/vpn.bicep' = {
  scope: rg
  name: 'vpn-deployment'
  params: {
    location1: region1
    location2: region2
    vwanName: vwanName
    hub1Name: hub1Name
    hub2Name: hub2Name
    branchVnetId: network.outputs.branchVnetId
    hub1Id: network.outputs.hub1Id
    hub2Id: network.outputs.hub2Id
    hub1DefaultRouteTableId: '${network.outputs.hub1Id}/hubRouteTables/defaultRouteTable'
    hub2DefaultRouteTableId: '${network.outputs.hub2Id}/hubRouteTables/defaultRouteTable'
    vpnSharedKey: vpnSharedKey
  }
}

module routing 'modules/routing.bicep' = {
  scope: rg
  name: 'routing-deployment'
  params: {
    hub1Name: hub1Name
    hub2Name: hub2Name
    hub1NvaVnetId: nva.outputs.hub1NvaVnetId
    hub2NvaVnetId: nva.outputs.hub2NvaVnetId
    hub1NvaLoadBalancerIp: nva.outputs.hub1LoadBalancerIp
    hub2NvaLoadBalancerIp: nva.outputs.hub2LoadBalancerIp
    spoke1Hub1Prefixes: network.outputs.spoke1Hub1Prefixes
    spoke1Hub2Prefixes: network.outputs.spoke1Hub2Prefixes
    spoke2Hub1Id: network.outputs.spoke2Hub1Id
    spoke2Hub2Id: network.outputs.spoke2Hub2Id
  }
  dependsOn: [vpn]
}

module bgp 'modules/bgp.bicep' = {
  scope: rg
  name: 'bgp-connections-deployment'
  params: {
    location1: region1
    location2: region2
    hub1Name: hub1Name
    hub2Name: hub2Name
    hub1NvaConnectionName: routing.outputs.hub1NvaConnectionName
    hub2NvaConnectionName: routing.outputs.hub2NvaConnectionName
    hub1RouterIps: network.outputs.hub1RouterIps
    hub2RouterIps: network.outputs.hub2RouterIps
    hub1NvaVmNames: nva.outputs.hub1NvaVmNames
    hub2NvaVmNames: nva.outputs.hub2NvaVmNames
    hub1NvaPeerIps: nva.outputs.hub1NvaPeerIps
    hub2NvaPeerIps: nva.outputs.hub2NvaPeerIps
  }
}

module vms 'modules/vms.bicep' = {
  scope: rg
  name: 'vms-deployment'
  params: {
    location1: region1
    location2: region2
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    branchVnetId: network.outputs.branchVnetId
    spoke1Hub1Id: network.outputs.spoke1Hub1Id
    spoke2Hub1Id: network.outputs.spoke2Hub1Id
    spoke1Hub2Id: network.outputs.spoke1Hub2Id
    spoke2Hub2Id: network.outputs.spoke2Hub2Id
  }
  dependsOn: [bgp]
}

module bastion 'modules/bastion.bicep' = {
  scope: rg
  name: 'bastion-deployment'
  params: {
    location: region1
    hub1Id: network.outputs.hub1Id
    bastionVnetId: network.outputs.bastionVnetId
    hub1PrivateRouteTableId: routing.outputs.hub1PrivateRouteTableId
    hub1DefaultRouteTableId: routing.outputs.hub1DefaultRouteTableId
  }
  dependsOn: [vpn]
}

output vwanId string = network.outputs.vwanId
output hub1Id string = network.outputs.hub1Id
output hub2Id string = network.outputs.hub2Id
output bastionName string = bastion.outputs.bastionName
output hub1NvaLoadBalancerIp string = nva.outputs.hub1LoadBalancerIp
output hub2NvaLoadBalancerIp string = nva.outputs.hub2LoadBalancerIp
output bgpConnectionIds string[] = concat(bgp.outputs.hub1BgpConnectionIds, bgp.outputs.hub2BgpConnectionIds)
/* Legacy divergent orchestration retained as non-deploying reference.
targetScope = 'subscription'

@description('Primary Azure region.')
param region1 string = 'westus3'

@description('Secondary Azure region.')
param region2 string = 'westus3'

@description('Isolated resource group for this lab.')
param resourceGroupName string = 'vwan-interregion-nva-bgp-lab'

@description('Virtual WAN name.')
param virtualWanName string = 'vwan-nva-bgp-lab'

@description('Administrator username for Linux virtual machines.')
param adminUsername string = 'azureuser'

@description('Administrator password for Linux virtual machines.')
@secure()
param adminPassword string

@description('Virtual machine size used by the lab.')
param vmSize string = 'Standard_D2ls_v7'

@description('Pre-shared key used by the two lab branch VPN connections.')
@secure()
param vpnSharedKey string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: region1
}

module network 'modules/network.bicep' = {
  scope: resourceGroup
  params: {
    region1: region1
    region2: region2
    virtualWanName: virtualWanName
  }
}

module nva 'modules/nva.bicep' = {
  scope: resourceGroup
  params: {
    region1: region1
    region2: region2
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    hub1RouterIps: network.outputs.hub1RouterIps
    hub2RouterIps: network.outputs.hub2RouterIps
    transit1VnetId: network.outputs.transit1VnetId
    transit2VnetId: network.outputs.transit2VnetId
  }
}

module topology 'modules/topology.bicep' = {
  scope: resourceGroup
  params: {
    region1: region1
    region2: region2
    hub1Name: network.outputs.hub1Name
    hub2Name: network.outputs.hub2Name
    transit1VnetId: network.outputs.transit1VnetId
    transit2VnetId: network.outputs.transit2VnetId
    region1LoadBalancerIp: nva.outputs.region1LoadBalancerIp
    region2LoadBalancerIp: nva.outputs.region2LoadBalancerIp
  }
}

module vms 'modules/vms.bicep' = {
  scope: resourceGroup
  params: {
    region1: region1
    region2: region2
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    workloadSubnetIds: concat(
      [
        topology.outputs.directWorkloadSubnetIds[0]
        '${network.outputs.transit1VnetId}/subnets/workload'
        topology.outputs.directWorkloadSubnetIds[1]
        '${network.outputs.transit2VnetId}/subnets/workload'
      ],
      topology.outputs.indirectWorkloadSubnetIds
    )
  }
  dependsOn: [bgp]
}

module branch1Vpn 'modules/vpn.bicep' = {
  scope: resourceGroup
  params: {
    @description('Primary region for deployment')
    branchNumber: 1
    branchPrefix: '10.200.0.0/24'
    @description('Region for Hub 2 resources')
    virtualWanId: network.outputs.virtualWanId
    hubId: network.outputs.hub1Id
    @description('Resource group name')
    vpnSharedKey: vpnSharedKey
  }
    @description('Virtual WAN name')

module branch2Vpn 'modules/vpn.bicep' = {
    @description('Hub 1 name')
  params: {
    location: region2
    @description('Hub 2 name')
    branchPrefix: '10.201.0.0/24'
    branchAsn: 65102
    @description('Admin username for VMs')
    hubId: network.outputs.hub2Id
    hubName: network.outputs.hub2Name
    @description('Admin password for VMs')
    @secure()
  }
}
    @description('Pre-shared key for the site-to-site VPN connections')
    @secure()
module branch1Vm 'modules/test-vm.bicep' = {
  scope: resourceGroup
    @description('VM size')
    name: 'branch1-vm'
    location: region1
    subnetId: branch1Vpn.outputs.branchWorkloadSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
}

module branch2Vm 'modules/test-vm.bicep' = {
  scope: resourceGroup
  params: {
    name: 'branch2-vm'
    location: region2
    subnetId: branch2Vpn.outputs.branchWorkloadSubnetId
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
  }
}

module bastion 'modules/bastion.bicep' = {
  scope: resourceGroup
  params: {
    location: region1
    hubName: network.outputs.hub1Name
  }
}

module bgp 'modules/bgp.bicep' = {
  scope: resourceGroup
  params: {
    hub1Name: network.outputs.hub1Name
    hub2Name: network.outputs.hub2Name
    hub1TransitConnectionName: network.outputs.hub1TransitConnectionName
    hub2TransitConnectionName: network.outputs.hub2TransitConnectionName
    hub1NvaPeerIps: [
      '10.11.0.4'
      '10.11.0.5'
    ]
    hub2NvaPeerIps: [
      '10.139.0.4'
      '10.139.0.5'
    ]
  }
  dependsOn: [nva]
}

output virtualWanId string = network.outputs.virtualWanId
output hub1Id string = network.outputs.hub1Id
output hub2Id string = network.outputs.hub2Id
output bgpConnectionIds string[] = concat(bgp.outputs.hub1BgpConnectionIds, bgp.outputs.hub2BgpConnectionIds)
output bastionName string = bastion.outputs.bastionName
*/
