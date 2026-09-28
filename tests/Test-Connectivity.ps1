#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'
$vmNames = @('branch1-vm', 'hub1-spoke1-vm', 'hub1-spoke2-vm', 'hub2-spoke1-vm', 'hub2-spoke2-vm')
$startScript = Join-Path $PSScriptRoot 'Start-ConnectivityListener.sh'
$probeScript = Join-Path $PSScriptRoot 'Invoke-ConnectivityChecks.sh'
$stopScript = Join-Path $PSScriptRoot 'Stop-ConnectivityListener.sh'

function Invoke-VmShellScript {
    param(
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$ScriptPath
    )

    $output = az vm run-command invoke `
        --subscription $SubscriptionId `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --command-id RunShellScript `
        --scripts "@$ScriptPath" `
        --query 'value[0].message' `
        --output tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Run Command failed on '$VmName' for '$([IO.Path]::GetFileName($ScriptPath))': $($output -join "`n")"
    }
    return $output -join "`n"
}

az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Unable to select subscription '$SubscriptionId'." }
$account = az account show --subscription $SubscriptionId | ConvertFrom-Json
if (-not $account -or $account.id -ne $SubscriptionId) {
    throw "Azure CLI did not confirm subscription '$SubscriptionId'."
}

$deployedVms = @(az vm list `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --show-details `
    --query '[].{name:name,powerState:powerState}' `
    --output json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw "Unable to list VMs in resource group '$ResourceGroupName'." }

foreach ($vmName in $vmNames) {
    $vm = @($deployedVms | Where-Object name -eq $vmName)
    if ($vm.Count -ne 1 -or $vm[0].powerState -ne 'VM running') {
        throw "Required VM '$vmName' is missing or not running."
    }
}

$probeOutput = [Collections.Generic.List[string]]::new()
try {
    foreach ($vmName in $vmNames) {
        Write-Host "Starting bounded TCP/2222 listener on $vmName..."
        Write-Host (Invoke-VmShellScript -VmName $vmName -ScriptPath $startScript)
    }

    foreach ($vmName in $vmNames) {
        Write-Host "Testing connectivity from $vmName..."
        $result = Invoke-VmShellScript -VmName $vmName -ScriptPath $probeScript
        Write-Host $result
        $probeOutput.Add($result)
    }
}
finally {
    foreach ($vmName in $vmNames) {
        try {
            Write-Host (Invoke-VmShellScript -VmName $vmName -ScriptPath $stopScript)
        }
        catch {
            Write-Warning "Listener cleanup failed on '$vmName': $($_.Exception.Message)"
        }
    }
}

$resultLines = @(($probeOutput -join "`n") -split '\r?\n')
$tcpResults = @($resultLines | Where-Object { $_ -match '^TCP2222 ' })
$sshBlockResults = @($resultLines | Where-Object { $_ -match '^SSH22BLOCK ' })
$httpsResults = @($resultLines | Where-Object { $_ -match '^HTTPS ' })
$failures = @($resultLines | Where-Object { $_ -match '^(TCP2222|SSH22BLOCK|HTTPS) .* FAIL(?: |$)' })

if ($tcpResults.Count -ne 60) { throw "Expected 60 TCP/2222 results, received $($tcpResults.Count)." }
if ($sshBlockResults.Count -ne 20) { throw "Expected 20 SSH-block results, received $($sshBlockResults.Count)." }
if ($httpsResults.Count -ne 4) { throw "Expected 4 HTTPS results, received $($httpsResults.Count)." }
if ($failures.Count -gt 0) { throw "Connectivity validation failed:`n$($failures -join "`n")" }

Write-Host 'PASS: 60/60 private TCP/2222 checks succeeded.' -ForegroundColor Green
Write-Host 'PASS: 20/20 east-west SSH attempts were blocked.' -ForegroundColor Green
Write-Host 'PASS: 4/4 spoke HTTPS egress checks succeeded.' -ForegroundColor Green
