param location string
param hub1Id string
param bastionVnetId string
param hub1PrivateRouteTableId string
param hub1DefaultRouteTableId string

resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'bastion-nsg'
  location: location
  properties: {
    securityRules: [
      { name: 'AllowHttpsInbound', properties: { priority: 100, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: 'Internet', sourcePortRange: '*', destinationAddressPrefix: '*', destinationPortRange: '443' } }
      { name: 'AllowGatewayManagerInbound', properties: { priority: 110, direction: 'Inbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: 'GatewayManager', sourcePortRange: '*', destinationAddressPrefix: '*', destinationPortRange: '443' } }
      { name: 'AllowBastionHostCommunication', properties: { priority: 120, direction: 'Inbound', access: 'Allow', protocol: '*', sourceAddressPrefix: 'VirtualNetwork', sourcePortRange: '*', destinationAddressPrefix: 'VirtualNetwork', destinationPortRanges: ['8080', '5701'] } }
      { name: 'AllowSshRdpOutbound', properties: { priority: 100, direction: 'Outbound', access: 'Allow', protocol: '*', sourceAddressPrefix: '*', sourcePortRange: '*', destinationAddressPrefix: 'VirtualNetwork', destinationPortRanges: ['22', '3389'] } }
      { name: 'AllowAzureCloudOutbound', properties: { priority: 110, direction: 'Outbound', access: 'Allow', protocol: 'Tcp', sourceAddressPrefix: '*', sourcePortRange: '*', destinationAddressPrefix: 'AzureCloud', destinationPortRange: '443' } }
      { name: 'AllowBastionCommunication', properties: { priority: 120, direction: 'Outbound', access: 'Allow', protocol: '*', sourceAddressPrefix: 'VirtualNetwork', sourcePortRange: '*', destinationAddressPrefix: 'VirtualNetwork', destinationPortRanges: ['8080', '5701'] } }
      { name: 'AllowGetSessionInformation', properties: { priority: 130, direction: 'Outbound', access: 'Allow', protocol: '*', sourceAddressPrefix: '*', sourcePortRange: '*', destinationAddressPrefix: 'Internet', destinationPortRange: '80' } }
    ]
  }
}

resource bastionVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = { name: last(split(bastionVnetId, '/')) }
resource hub1 'Microsoft.Network/virtualHubs@2023-11-01' existing = { name: last(split(hub1Id, '/')) }

resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: bastionVnet
  name: 'AzureBastionSubnet'
  properties: { addressPrefix: '10.200.0.0/26', networkSecurityGroup: { id: bastionNsg.id } }
}
resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'Bastion-PIP'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}
resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'SharedBastion'
  location: location
  sku: { name: 'Standard' }
  properties: {
    enableIpConnect: true
    ipConfigurations: [{ name: 'IpConf', properties: { subnet: { id: bastionSubnet.id }, publicIPAddress: { id: bastionPip.id } } }]
  }
}
resource bastionHubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2023-11-01' = {
  parent: hub1
  name: 'bastion-vnet-conn'
  properties: {
    remoteVirtualNetwork: { id: bastionVnetId }
    enableInternetSecurity: false
    routingConfiguration: {
      associatedRouteTable: { id: hub1PrivateRouteTableId }
      propagatedRouteTables: { labels: ['Default', 'internet-only', 'private-only'], ids: [{ id: hub1DefaultRouteTableId }] }
    }
  }
  dependsOn: [bastion]
}

output bastionId string = bastion.id
output bastionName string = bastion.name
output bastionNsgId string = bastionNsg.id
/* Legacy divergent Bastion implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param location string
param hubName string

resource bastionVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'bastion-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.250.0.0/24']
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.250.0.0/26'
        }
      }
    ]
  }
}

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'shared-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableIpConnect: true
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: '${bastionVnet.id}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
  }
}

resource hub 'Microsoft.Network/virtualHubs@2024-05-01' existing = {
  name: hubName
}

resource bastionHubConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: hub
  name: 'bastion-connection'
  properties: {
    enableInternetSecurity: false
    remoteVirtualNetwork: {
      id: bastionVnet.id
    }
  }
}

output bastionName string = bastion.name
*/
