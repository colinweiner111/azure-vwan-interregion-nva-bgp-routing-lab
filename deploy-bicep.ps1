#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,
    [string]$ResourceGroupName = 'vwan-interregion-nva-bgp-lab',
    [string]$Location = 'westus3',
    [string]$Location2 = 'westus3',
    [string]$AdminUsername = 'azureuser',
    [string]$VmSize = 'Standard_D2ls_v7',
    [System.Security.SecureString]$AdminPassword,
    [System.Security.SecureString]$VpnSharedKey,
    [switch]$ResumeExisting
)

$ErrorActionPreference = 'Stop'

function ConvertTo-PlainText {
    param([Parameter(Mandatory)][System.Security.SecureString]$SecureValue)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    az login
    if ($LASTEXITCODE -ne 0) { throw 'Azure login failed.' }
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select subscription '$SubscriptionId'." }
$account = az account show --subscription $SubscriptionId 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $account -or $account.id -ne $SubscriptionId) {
    throw "Azure CLI did not confirm subscription '$SubscriptionId'."
}

$resourceGroupExists = az group exists --name $ResourceGroupName --subscription $SubscriptionId 2>$null
if ($LASTEXITCODE -ne 0 -or $resourceGroupExists -notin @('true', 'false')) {
    throw "Unable to check whether resource group '$ResourceGroupName' exists."
}
if ($resourceGroupExists -eq 'true' -and -not $ResumeExisting) {
    throw "Deployment refused: resource group '$ResourceGroupName' already exists. Use a new group or explicitly pass -ResumeExisting."
}
if ($resourceGroupExists -eq 'false' -and $ResumeExisting) {
    throw "Resume refused: resource group '$ResourceGroupName' does not exist."
}

if (-not $AdminPassword) { $AdminPassword = Read-Host 'Enter VM admin password' -AsSecureString }
if (-not $VpnSharedKey) { $VpnSharedKey = Read-Host 'Enter VPN pre-shared key' -AsSecureString }

Write-Host "Subscription: $($account.name) ($SubscriptionId)" -ForegroundColor Green
Write-Host "Resource group: $ResourceGroupName"
Write-Host "Regions: $Location, $Location2"
Write-Host 'Deploying two vHubs, four workload spokes, four FRR NVAs, one dual-connected BGP branch, five workload VMs, and Bastion.'

$environment = @{
    VWAN_NVA_BGP_RESOURCE_GROUP = $ResourceGroupName
    VWAN_NVA_BGP_REGION_1 = $Location
    VWAN_NVA_BGP_REGION_2 = $Location2
    VWAN_NVA_BGP_ADMIN_USERNAME = $AdminUsername
    VWAN_NVA_BGP_ADMIN_PASSWORD = ConvertTo-PlainText $AdminPassword
    VWAN_NVA_BGP_VM_SIZE = $VmSize
    VWAN_NVA_BGP_VPN_SHARED_KEY = ConvertTo-PlainText $VpnSharedKey
}
$previous = @{}
try {
    foreach ($name in $environment.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process')
    }
    az deployment sub create `
        --subscription $SubscriptionId `
        --name "vwan-nva-bgp-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
        --location $Location `
        --template-file "$PSScriptRoot\main.bicep" `
        --parameters "$PSScriptRoot\main.bicepparam"
    if ($LASTEXITCODE -ne 0) { throw 'Azure deployment failed.' }
}
finally {
    foreach ($name in $environment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
    $environment.Clear()
    $previous.Clear()
    $AdminPassword = $null
    $VpnSharedKey = $null
}

Write-Host 'Deployment completed. Validate BGP state, effective routes, symmetry, and failover before drawing conclusions.' -ForegroundColor Green