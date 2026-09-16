using './main.bicep'

param resourceGroupName = readEnvironmentVariable('VWAN_NVA_BGP_RESOURCE_GROUP', 'vwan-interregion-nva-bgp-lab')
param region1 = readEnvironmentVariable('VWAN_NVA_BGP_REGION_1', 'westus3')
param region2 = readEnvironmentVariable('VWAN_NVA_BGP_REGION_2', 'westus3')
param adminUsername = readEnvironmentVariable('VWAN_NVA_BGP_ADMIN_USERNAME', 'azureuser')
param adminPassword = readEnvironmentVariable('VWAN_NVA_BGP_ADMIN_PASSWORD')
param vmSize = readEnvironmentVariable('VWAN_NVA_BGP_VM_SIZE', 'Standard_D2ls_v7')
param vpnSharedKey = readEnvironmentVariable('VWAN_NVA_BGP_VPN_SHARED_KEY')
