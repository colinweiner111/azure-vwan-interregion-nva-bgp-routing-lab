#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$validationDirectory = Join-Path $root '.azure/local-validation'
New-Item -ItemType Directory -Path $validationDirectory -Force | Out-Null

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    Write-Host "PASS: $Message"
}

function Get-ResourcesByType {
    param([Parameter(Mandatory)][object]$Template, [Parameter(Mandatory)][string]$Type)
    return @($Template.resources.PSObject.Properties.Value | Where-Object { $_.type -eq $Type })
}

$templatePath = Join-Path $validationDirectory 'main.json'
az bicep build --file (Join-Path $root 'main.bicep') --outfile $templatePath
Assert-Condition ($LASTEXITCODE -eq 0) 'Bicep build succeeds'

$template = Get-Content $templatePath -Raw | ConvertFrom-Json -Depth 100
$compiledText = Get-Content $templatePath -Raw
$mainText = Get-Content (Join-Path $root 'main.bicep') -Raw
$frrText = Get-Content (Join-Path $root 'scripts/configure-frr-nva.sh') -Raw
$nvaText = Get-Content (Join-Path $root 'modules/nva.bicep') -Raw
$bgpText = Get-Content (Join-Path $root 'modules/bgp.bicep') -Raw
$wrapperText = Get-Content (Join-Path $root 'deploy-bicep.ps1') -Raw

Assert-Condition ($template.parameters.adminPassword.type -eq 'securestring') 'VM password is a secure parameter'
Assert-Condition ($template.parameters.vpnSharedKey.type -eq 'securestring') 'VPN key is a secure parameter'
Assert-Condition ($compiledText -notmatch 'Microsoft.Network/azureFirewalls|Microsoft.Network/firewallPolicies|routingIntent') 'No Azure Firewall, firewall policy, or Routing Intent resources'

$moduleOrder = @(
    'nva-infrastructure-deployment',
    'network-deployment',
    'vpn-deployment',
    'routing-deployment',
    'bgp-connections-deployment',
    'vms-deployment'
)
$previousIndex = -1
foreach ($moduleName in $moduleOrder) {
    $moduleIndex = $mainText.IndexOf("name: '$moduleName'", [StringComparison]::Ordinal)
    Assert-Condition ($moduleIndex -gt $previousIndex) "Explicit module order includes $moduleName"
    $previousIndex = $moduleIndex
}

$deployments = @{}
foreach ($deployment in @($template.resources.PSObject.Properties.Value | Where-Object { $_.type -eq 'Microsoft.Resources/deployments' })) {
    $deployments[$deployment.name] = $deployment.properties.template
}
foreach ($deploymentName in @($moduleOrder + 'bastion-deployment')) {
    Assert-Condition ($deployments.ContainsKey($deploymentName)) "Deployment module exists: $deploymentName"
}
$network = $deployments['network-deployment']
$nva = $deployments['nva-infrastructure-deployment']
$vpn = $deployments['vpn-deployment']
$routing = $deployments['routing-deployment']
$bgp = $deployments['bgp-connections-deployment']
$vms = $deployments['vms-deployment']

foreach ($literal in @(
    'hub1', 'hub2', '192.168.0.0/22', '192.168.4.0/22',
    'branch1', '10.100.0.0/16', 'bastion-vnet', '10.200.0.0/24',
    'hub1-spoke1', '172.16.1.0/24', 'hub1-spoke2', '172.16.2.0/24',
    'hub2-spoke1', '172.16.3.0/24', 'hub2-spoke2', '172.16.4.0/24'
)) {
    Assert-Condition (($network | ConvertTo-Json -Depth 100 -Compress) -match [regex]::Escape($literal)) "Network topology contains $literal"
}
Assert-Condition (@(Get-ResourcesByType $network 'Microsoft.Network/virtualNetworks' | Where-Object { $null -ne $_.properties }).Count -eq 6) 'Network module creates four spokes, one branch, and one Bastion VNet'
Assert-Condition ((Get-ResourcesByType $network 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings').Count -eq 4) 'Protected spokes have four bidirectional NVA peerings'

$nvaJson = $nva | ConvertTo-Json -Depth 100 -Compress
foreach ($literal in @('172.16.10.0/24', '172.16.20.0/24', '172.16.10.4', '172.16.10.5', '172.16.20.4', '172.16.20.5', '172.16.10.10', '172.16.20.10')) {
    Assert-Condition ($nvaJson -match [regex]::Escape($literal)) "NVA topology contains $literal"
}
Assert-Condition ((Get-ResourcesByType $nva 'Microsoft.Network/virtualNetworks')[0].copy.count -eq '[length(range(0, 2))]') 'Two NVA transit VNets are generated'
Assert-Condition ((Get-ResourcesByType $nva 'Microsoft.Network/natGateways')[0].copy.count -eq '[length(range(0, 2))]') 'Two NVA NAT gateways provide bootstrap egress'
Assert-Condition ((Get-ResourcesByType $nva 'Microsoft.Network/publicIPAddresses')[0].copy.count -eq '[length(range(0, 2))]') 'Two NVA NAT public IPs are generated'
Assert-Condition ($nvaJson -match 'natGateway') 'Each NVA subnet references its regional NAT gateway'
Assert-Condition ((Get-ResourcesByType $nva 'Microsoft.Network/loadBalancers')[0].copy.count -eq '[length(range(0, 2))]') 'Two NVA load balancers are generated'
Assert-Condition ((Get-ResourcesByType $nva 'Microsoft.Compute/virtualMachines')[0].copy.count -eq "[length(variables('nvaInstances'))]") 'Four NVA VM instances use the four-element instance array'
Assert-Condition ($nvaJson -match '"protocol":"All"' -and $nvaJson -match '"frontendPort":0' -and $nvaJson -match '"backendPort":0') 'Internal load balancers use HA Ports'
Assert-Condition ($nvaJson -match '"enableIPForwarding":true') 'NVA NIC forwarding is enabled'

$bgpJson = $bgp | ConvertTo-Json -Depth 100 -Compress
$bgpResources = Get-ResourcesByType $bgp 'Microsoft.Network/virtualHubs/bgpConnections'
Assert-Condition ($bgpResources.Count -eq 1 -and $bgpResources[0].copy.count -eq "[length(variables('nvaInstances'))]") 'Four native virtual hub BGP connections are generated'
Assert-Condition ($bgpResources[0].copy.mode -eq 'Serial' -and $bgpResources[0].copy.batchSize -eq 1) 'Virtual hub BGP writes are serialized'
Assert-Condition ($bgpJson -match 'hubVirtualNetworkConnection' -and $bgpJson -match 'nvaConnections') 'Each BGP peer references its regional hub VNet connection'
Assert-Condition ($bgpJson -match '65020') 'NVA BGP peers use ASN 65020'

$routingJson = $routing | ConvertTo-Json -Depth 100 -Compress
Assert-Condition ((Get-ResourcesByType $routing 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections').Count -eq 4) 'Routing module creates two NVA and two direct-spoke hub connections'
Assert-Condition ((Get-ResourcesByType $routing 'Microsoft.Network/virtualHubs/hubRouteTables').Count -eq 5) 'Source-shaped hub route tables are preserved'
Assert-Condition ($routingJson -match 'hub1NvaLoadBalancerIp' -and $routingJson -match 'hub2NvaLoadBalancerIp') 'Protected and internet routes target regional NVA ILB parameters'

$vpnJson = $vpn | ConvertTo-Json -Depth 100 -Compress
Assert-Condition ((Get-ResourcesByType $vpn 'Microsoft.Network/virtualNetworkGateways').Count -eq 1) 'One branch VPN gateway is generated'
Assert-Condition ((Get-ResourcesByType $vpn 'Microsoft.Network/vpnGateways').Count -eq 2) 'Two virtual hub VPN gateways are generated'
Assert-Condition ((Get-ResourcesByType $vpn 'Microsoft.Network/connections')[0].copy.count -eq '[length(range(0, 4))]') 'Branch creates four IPsec connections across both hubs'
Assert-Condition ($vpnJson -match '65010' -and $vpnJson -match '"enableBgp":true') 'Branch VPN uses ASN 65010 with BGP enabled'

$expectedVmNames = @('branch1-vm', 'hub1-spoke1-vm', 'hub1-spoke2-vm', 'hub2-spoke1-vm', 'hub2-spoke2-vm')
Assert-Condition ((Get-ResourcesByType $vms 'Microsoft.Compute/virtualMachines')[0].copy.count -eq '[length(range(0, 5))]') 'Exactly five workload VM instances are generated'
Assert-Condition ((Get-ResourcesByType $vms 'Microsoft.Network/networkInterfaces')[0].copy.count -eq '[length(range(0, 5))]') 'Exactly five workload NIC instances are generated'
Assert-Condition ((@($vms.variables.vmNames) -join ',') -eq ($expectedVmNames -join ',')) 'Workload VM names match the predecessor topology'

Assert-Condition ($frrText -match 'local_asn="\$\{3:-65020\}"') 'FRR defaults to NVA ASN 65020'
Assert-Condition ($frrText -match 'for attempt in 1 2 3 4 5' -and $frrText -match 'Acquire::Retries=3') 'FRR package installation retries transient repository failures'
Assert-Condition ($frrText -match 'systemctl enable frr' -and $frrText -match 'systemctl restart frr') 'FRR restarts after bgpd and integrated configuration are written'
Assert-Condition ($frrText -match 'ip nht resolve-via-default') 'FRR resolves multihop virtual hub next hops through the Azure default route'
Assert-Condition ($nvaText -match 'configure-frr-nva-bootstrap.sh' -and $nvaText -match 'length\(bootstrapSource\) - 1') 'VM custom data remains byte-compatible with the original bootstrap payload'
Assert-Condition ($bgpText -match 'loadTextContent.*configure-frr-nva.sh' -and $bgpText -match 'forceUpdateTag') 'VM extension delivers and reruns the current FRR configuration'
Assert-Condition ($frrText -match 'net.ipv4.ip_forward=1' -and $frrText -match 'rp_filter') 'FRR host enables forwarding and disables reverse-path filtering'
Assert-Condition ($frrText -match 'iptables -P FORWARD ACCEPT' -and $frrText -match 'MASQUERADE') 'FRR host allows forwarding and configures NAT'
Assert-Condition ($frrText -match '10\.0\.0\.0/8 172\.16\.0\.0/12 192\.168\.0\.0/16' -and $frrText -match 'POSTROUTING -d.*RETURN') 'FRR host preserves source addresses for private east-west traffic'
Assert-Condition ($frrText -match '8080' -and $frrText -match 'load_balancer_ip.*/32') 'FRR host serves the probe and owns the ILB frontend address'

Assert-Condition ($wrapperText -match 'account.id -ne \$SubscriptionId') 'Wrapper verifies the exact subscription'
Assert-Condition ($wrapperText -match 'resourceGroupExists -eq ''true'' -and -not \$ResumeExisting') 'Wrapper refuses existing resource groups by default'

foreach ($file in Get-ChildItem $root -Filter '*.ps1' -Recurse) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Condition ($errors.Count -eq 0) "PowerShell syntax: $($file.Name)"
}

$testEnvironment = @{
    VWAN_NVA_BGP_ADMIN_PASSWORD = 'LocalCompilePlaceholderOnly!123'
    VWAN_NVA_BGP_VPN_SHARED_KEY = 'LocalCompilePlaceholderOnly!456'
}
try {
    foreach ($name in $testEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $testEnvironment[$name], 'Process') }
    az bicep build-params --file (Join-Path $root 'main.bicepparam') --outfile (Join-Path $validationDirectory 'parameters.json')
    Assert-Condition ($LASTEXITCODE -eq 0) 'Bicep parameters compile with synthetic local-only secrets'
}
finally {
    foreach ($name in $testEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    Remove-Item (Join-Path $validationDirectory 'parameters.json') -ErrorAction SilentlyContinue
}

Write-Host 'Static checks passed. Azure deployment, route convergence, packet paths, and failover remain unverified.'