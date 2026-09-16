param location1 string
param location2 string
param adminUsername string
@secure()
param adminPassword string
param vmSize string
param branchVnetId string
param spoke1Hub1Id string
param spoke2Hub1Id string
param spoke1Hub2Id string
param spoke2Hub2Id string

var vmNames = ['branch1-vm', 'hub1-spoke1-vm', 'hub1-spoke2-vm', 'hub2-spoke1-vm', 'hub2-spoke2-vm']
var vmLocations = [location1, location1, location1, location2, location2]
var subnetIds = [
  '${branchVnetId}/subnets/main'
  '${spoke1Hub1Id}/subnets/main'
  '${spoke2Hub1Id}/subnets/main'
  '${spoke1Hub2Id}/subnets/main'
  '${spoke2Hub2Id}/subnets/main'
]
var cloudInit = base64('''#cloud-config
package_update: true
/* Legacy divergent workload VM implementation retained as non-deploying reference.
packages:
  - traceroute
  - netcat-openbsd
''')

resource workloadNics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for index in range(0, 5): {
  name: '${vmNames[index]}-nic'
  location: vmLocations[index]
  properties: {
    ipConfigurations: [{ name: 'ipconfig1', properties: { subnet: { id: subnetIds[index] }, privateIPAllocationMethod: 'Dynamic' } }]
  }
}]

resource workloadVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for index in range(0, 5): {
  name: vmNames[index]
  location: vmLocations[index]
  properties: {
    hardwareProfile: { vmSize: vmSize }
    storageProfile: {
      imageReference: { publisher: 'Canonical', offer: '0001-com-ubuntu-server-jammy', sku: '22_04-lts-gen2', version: 'latest' }
      osDisk: { name: '${vmNames[index]}-osdisk', createOption: 'FromImage', managedDisk: { storageAccountType: 'Premium_LRS' } }
    }
    osProfile: {
      computerName: vmNames[index]
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: cloudInit
      linuxConfiguration: { disablePasswordAuthentication: false }
    }
    networkProfile: { networkInterfaces: [{ id: workloadNics[index].id }] }
  }
}]

output workloadVmIds string[] = [for index in range(0, 5): workloadVms[index].id]
/* Legacy divergent workload VM implementation retained as non-deploying reference.
targetScope = 'resourceGroup'

param region1 string
param region2 string
param adminUsername string
@secure()
param adminPassword string
param vmSize string
param workloadSubnetIds string[]

var workloadLocations = [region1, region1, region2, region2, region1, region1, region2, region2]
var cloudInit = base64('''#cloud-config
package_update: true
packages:
  - traceroute
  - netcat-openbsd
''')

resource workloadNics 'Microsoft.Network/networkInterfaces@2024-05-01' = [for (subnetId, index) in workloadSubnetIds: {
  name: 'spoke${index + 1}-vm-nic'
  location: workloadLocations[index]
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}]

resource workloadVms 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (subnetId, index) in workloadSubnetIds: {
  name: 'spoke${index + 1}-vm'
  location: workloadLocations[index]
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
      computerName: 'spoke${index + 1}-vm'
      adminUsername: adminUsername
      adminPassword: adminPassword
      customData: cloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: workloadNics[index].id
        }
      ]
    }
  }
}]

output workloadVmIds string[] = [for index in range(0, length(workloadSubnetIds)): workloadVms[index].id]
*/
