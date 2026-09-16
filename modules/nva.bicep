param location1 string
param location2 string
param hub1Name string
param hub2Name string
param adminUsername string
@secure()
param adminPassword string
param vmSize string

var locations = [location1, location2]
var hubNames = [hub1Name, hub2Name]
var vnetPrefixes = ['172.16.10.0/24', '172.16.20.0/24']
var nvaSubnetPrefixes = ['172.16.10.0/26', '172.16.20.0/26']
var nvaIps = [
  ['172.16.10.4', '172.16.10.5']
  ['172.16.20.4', '172.16.20.5']
]
var loadBalancerIps = ['172.16.10.10', '172.16.20.10']
var advertisedPrefixes = ['172.16.1.0/24', '172.16.3.0/24']
var bootstrapSource = loadTextContent('../scripts/configure-frr-nva-bootstrap.sh')
var bootstrap = base64(substring(bootstrapSource, 0, length(bootstrapSource) - 1))
var nvaInstances = [
  { hubIndex: 0, nvaIndex: 0 }
  { hubIndex: 0, nvaIndex: 1 }
  { hubIndex: 1, nvaIndex: 0 }
  { hubIndex: 1, nvaIndex: 1 }
]

resource natGatewayPublicIps 'Microsoft.Network/publicIPAddresses@2024-05-01' = [for hubIndex in range(0, 2): {
  name: '${hubNames[hubIndex]}-nva-nat-pip'
  location: locations[hubIndex]
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}]

resource natGateways 'Microsoft.Network/natGateways@2024-07-01' = [for hubIndex in range(0, 2): {
  name: '${hubNames[hubIndex]}-nva-nat'
  location: locations[hubIndex]
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      {
        id: natGatewayPublicIps[hubIndex].id
      }
    ]
  }
}]

resource nvaVnets 'Microsoft.Network/virtualNetworks@2023-11-01' = [for hubIndex in range(0, 2): {
  name: '${hubNames[hubIndex]}-nva-transit-vnet'
  location: locations[hubIndex]
  properties: {
    addressSpace: {
      addressPrefixes: [vnetPrefixes[hubIndex]]
    }
    subnets: [
      {
        name: 'nva'
        properties: {
          addressPrefix: nvaSubnetPrefixes[hubIndex]
          natGateway: {
            id: natGateways[hubIndex].id
          }
        }
      }
    ]
  }
}]

resource loadBalancers 'Microsoft.Network/loadBalancers@2023-11-01' = [for hubIndex in range(0, 2): {
  name: '${hubNames[hubIndex]}-nva-ilb'
  location: locations[hubIndex]
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAddress: loadBalancerIps[hubIndex]
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: '${nvaVnets[hubIndex].id}/subnets/nva'
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'nva-pool'
      }
    ]
    probes: [
      {
        name: 'nva-health'
        properties: {
          protocol: 'Tcp'
          port: 8080
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'ha-ports'
        properties: {
          protocol: 'All'
          frontendPort: 0
          backendPort: 0
          enableFloatingIP: true
          idleTimeoutInMinutes: 15
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${hubNames[hubIndex]}-nva-ilb', 'internal')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${hubNames[hubIndex]}-nva-ilb', 'nva-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${hubNames[hubIndex]}-nva-ilb', 'nva-health')
          }
        }
      }
    ]
  }
}]

resource nvaNics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for item in nvaInstances: {
  name: '${hubNames[item.hubIndex]}-nva${item.nvaIndex + 1}-nic'
  location: locations[item.hubIndex]
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: nvaIps[item.hubIndex][item.nvaIndex]
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: '${nvaVnets[item.hubIndex].id}/subnets/nva'
          }
          loadBalancerBackendAddressPools: [
            {
              id: loadBalancers[item.hubIndex].properties.backendAddressPools[0].id
            }
          ]
        }
      }
    ]
  }
}]

resource nvaVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for item in nvaInstances: {
  name: '${hubNames[item.hubIndex]}-nva${item.nvaIndex + 1}'
  location: locations[item.hubIndex]
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${hubNames[item.hubIndex]}-nva${item.nvaIndex + 1}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: '${hubNames[item.hubIndex]}-nva${item.nvaIndex + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(format('''#cloud-config
write_files:
  - path: /usr/local/sbin/configure-frr-nva.sh
    permissions: '0755'
    encoding: b64
    content: {0}
runcmd:
  - [/usr/local/sbin/configure-frr-nva.sh, '', '{1}', '65020', '{2}']
''', bootstrap, advertisedPrefixes[item.hubIndex], loadBalancerIps[item.hubIndex]))
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nvaNics[item.hubIndex * 2 + item.nvaIndex].id
        }
      ]
    }
  }
}]

output hub1NvaVnetId string = nvaVnets[0].id
output hub2NvaVnetId string = nvaVnets[1].id
output hub1LoadBalancerIp string = loadBalancerIps[0]
output hub2LoadBalancerIp string = loadBalancerIps[1]
output hub1NvaPeerIps string[] = nvaIps[0]
output hub2NvaPeerIps string[] = nvaIps[1]
output hub1NvaVmNames string[] = [nvaVms[0].name, nvaVms[1].name]
output hub2NvaVmNames string[] = [nvaVms[2].name, nvaVms[3].name]
/* Legacy divergent NVA implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param region1 string
param region2 string
param adminUsername string
@secure()
param adminPassword string
param vmSize string
param hub1RouterIps string[]
param hub2RouterIps string[]
param transit1VnetId string
param transit2VnetId string

var locations = [region1, region2]
var transitVnetIds = [transit1VnetId, transit2VnetId]
var nvaIps = [
  ['10.11.0.4', '10.11.0.5']
  ['10.139.0.4', '10.139.0.5']
]
var loadBalancerIps = ['10.11.0.10', '10.139.0.10']
var regionalPrefixes = ['10.8.0.0/13', '10.136.0.0/13']
var hubRouterIps = [hub1RouterIps, hub2RouterIps]
var bootstrap = base64(loadTextContent('../scripts/configure-frr-nva.sh'))
var nvaInstances = [
  { regionIndex: 0, nvaIndex: 0 }
  { regionIndex: 0, nvaIndex: 1 }
  { regionIndex: 1, nvaIndex: 0 }
  { regionIndex: 1, nvaIndex: 1 }
]

resource loadBalancers 'Microsoft.Network/loadBalancers@2024-05-01' = [for regionIndex in range(0, 2): {
  name: 'nva-ilb-region${regionIndex + 1}'
  location: locations[regionIndex]
  sku: {
    name: 'Standard'
  }
  param location1 string
  param location2 string
  param hub1Name string
  param hub2Name string
  var locations = [location1, location2]
  var transitVnetIds = [transit1VnetId, transit2VnetId]
  var nvaIps = [
    ['172.16.10.4', '172.16.10.5']
    ['172.16.20.4', '172.16.20.5']
  ]
  var loadBalancerIps = ['172.16.10.10', '172.16.20.10']
  var regionalPrefixes = ['172.16.1.0/24', '172.16.3.0/24']
  var bootstrap = base64(loadTextContent('../scripts/configure-frr-nva.sh'))
  var nvaInstances = [
    { hubIndex: 0, nvaIndex: 0 }
    { hubIndex: 0, nvaIndex: 1 }
    { hubIndex: 1, nvaIndex: 0 }
    { hubIndex: 1, nvaIndex: 1 }
  ]
  properties: {
    frontendIPConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAddress: loadBalancerIps[regionIndex]
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: '${transitVnetIds[regionIndex]}/subnets/nva'
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'nva-pool'
      }
    ]
    probes: [
      {
        name: 'nva-health'
        properties: {
          protocol: 'Tcp'
          port: 8080
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'ha-ports'
        properties: {
          protocol: 'All'
          frontendPort: 0
          backendPort: 0
          enableFloatingIP: true
          idleTimeoutInMinutes: 15
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'nva-ilb-region${regionIndex + 1}', 'internal')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'nva-ilb-region${regionIndex + 1}', 'nva-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'nva-ilb-region${regionIndex + 1}', 'nva-health')
          }
        }
      }
    ]
  }
}]

resource nics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for item in nvaInstances: {
  name: 'nva-r${item.regionIndex + 1}-${item.nvaIndex + 1}-nic'
  location: locations[item.regionIndex]
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: nvaIps[item.regionIndex][item.nvaIndex]
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: '${transitVnetIds[item.regionIndex]}/subnets/nva'
          }
          loadBalancerBackendAddressPools: [
            {
              id: loadBalancers[item.regionIndex].properties.backendAddressPools[0].id
            }
          ]
        }
      }
    ]
  }
}]

resource nvaVms 'Microsoft.Compute/virtualMachines@2024-03-01' = [for item in nvaInstances: {
  name: 'nva-r${item.regionIndex + 1}-${item.nvaIndex + 1}'
  location: locations[item.regionIndex]
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'nva-r${item.regionIndex + 1}-${item.nvaIndex + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: base64(format('''#cloud-config
write_files:
  - path: /usr/local/sbin/configure-frr-nva.sh
    permissions: '0755'
    encoding: b64
    content: {0}
runcmd:
  - [/usr/local/sbin/configure-frr-nva.sh, '{1}', '{2}', '65020']
''', bootstrap, join(hubRouterIps[item.regionIndex], ','), regionalPrefixes[item.regionIndex]))
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[item.regionIndex * 2 + item.nvaIndex].id
        }
      ]
    }
  }
}]

output region1LoadBalancerIp string = loadBalancerIps[0]
output region2LoadBalancerIp string = loadBalancerIps[1]
output nvaVmIds string[] = [for index in range(0, 4): nvaVms[index].id]
*/
