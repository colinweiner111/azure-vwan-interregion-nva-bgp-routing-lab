# Azure Virtual WAN Inter-Hub NVA/BGP Routing Lab

This Bicep lab preserves the four-spoke, one-branch topology of the predecessor Virtual WAN routing lab while replacing Azure Firewall with two regional FRR NVA pairs. The NVAs sit in dedicated transit VNets behind Standard internal HA Ports load balancers and peer with their local virtual hub through native `Microsoft.Network/virtualHubs/bgpConnections` resources.

> No Azure Firewall or Routing Intent resource is deployed. The source-equivalent topology was deployed and live-tested in `vwan-interregion-nva-bgp-lab-v3` on September 16, 2026.

## Architecture

![Lab architecture](image/vwan-interhub-spoke-azfw-reference-style.svg)

| Area | Hub 1 | Hub 2 |
|---|---|---|
| Region default | `westus3` | `westus3` |
| Virtual hub | `hub1` / `192.168.0.0/22` | `hub2` / `192.168.4.0/22` |
| Protected spoke | `hub1-spoke1` / `172.16.1.0/24` | `hub2-spoke1` / `172.16.3.0/24` |
| Direct spoke | `hub1-spoke2` / `172.16.2.0/24` | `hub2-spoke2` / `172.16.4.0/24` |
| NVA transit VNet | `hub1-nva-transit-vnet` / `172.16.10.0/24` | `hub2-nva-transit-vnet` / `172.16.20.0/24` |
| NVA peers | `.4`, `.5` | `.4`, `.5` |
| HA Ports ILB | `172.16.10.10` | `172.16.20.10` |
| FRR advertisement | `172.16.1.0/24` | `172.16.3.0/24` |

The shared branch VNet is `branch1` (`10.100.0.0/16`). Its route-based VPN gateway uses ASN `65010` and establishes BGP/IPsec connections to both redundant instances of both virtual hub VPN gateways. The NVA ASN is `65020`; the virtual hub ASN is `65515`. The Bastion VNet is `10.200.0.0/24` and hosts `SharedBastion`.

Protected spoke subnets disable BGP route propagation and send `0.0.0.0/0` to the regional NVA load-balancer frontend. Bidirectional VNet peerings allow forwarded traffic between each protected spoke and its NVA transit VNet. Direct spokes retain their Virtual WAN route-table associations and propagations.

FRR bootstrap enables IPv4 forwarding, disables reverse-path filtering, advertises only the regional protected-spoke prefix, configures eBGP multihop to the local virtual hub routers, enables forwarding/NAT, assigns the ILB frontend `/32` to loopback, and serves the TCP health probe on port `8080`.

## Resources

- One Standard Virtual WAN and two Standard virtual hubs
- Four workload spoke VNets
- Two NVA transit VNets, four Ubuntu 22.04 FRR NVAs, and two Standard HA Ports internal load balancers
- Four native virtual hub BGP connections, each linked to its corresponding NVA transit hub connection
- One branch VNet, one branch VPN gateway, two virtual hub VPN gateways, and four branch-side IPsec connections
- One Standard Azure Bastion host
- Five workload VMs: `branch1-vm`, `hub1-spoke1-vm`, `hub1-spoke2-vm`, `hub2-spoke1-vm`, and `hub2-spoke2-vm`

Including the four NVAs, the deployment creates nine VMs. The default VM size is `Standard_D2ls_v7`, and the default administrator is `azureuser`.

## Prerequisites

- PowerShell 7 or later
- Azure CLI with Bicep support
- An Azure subscription with `Microsoft.Network` and `Microsoft.Compute` registered
- Subscription-scope Contributor or Owner access, because the template creates the resource group
- Sufficient regional quota for nine VMs, two virtual hubs, three VPN gateways, two load balancers, and Standard Bastion

## Validate Locally

Local validation does not deploy or query Azure resources:

```powershell
pwsh -NoProfile -File .\tests\Test-Routing.ps1
```

The suite compiles the Bicep and parameter files, inspects generated nested templates, checks PowerShell syntax, and verifies the topology, names, CIDRs, ASNs, BGP connection ownership, HA Ports behavior, FRR configuration, resource counts, and deployment safeguards.

## Deploy

Use a new, isolated resource group:

```powershell
.\deploy-bicep.ps1 `
  -SubscriptionId 00000000-0000-0000-0000-000000000000 `
  -ResourceGroupName vwan-interregion-nva-bgp-lab
```

Both regions default to `westus3`. Pass `-Location2` to place Hub 2 in another region. The script securely prompts for the VM password and VPN pre-shared key, verifies the exact subscription, and refuses an existing resource group unless `-ResumeExisting` is supplied. `-ResumeExisting` must only target a reviewed resource group created by this lab.

After deployment, validate effective routes, FRR neighbors and advertised routes, VPN tunnel state, ILB probe health, bidirectional workload connectivity, path symmetry, and single-NVA failover before drawing conclusions.

## Live Validation

All seven deployments succeeded, all nine VMs were healthy, and all eight FRR sessions to the two virtual hubs reached `Established`. Each NVA advertised its regional protected prefix and installed learned routes from the virtual hub.

The source-equivalent TCP/22 matrix passed 16 of 20 directions. The same four protected-Spoke1-to-remote-Spoke2 directions that fail in the predecessor lab also failed here; all other branch, same-hub, protected-to-protected, and direct-Spoke2 paths passed. HTTPS passed from all four spokes, with both Hub 1 spokes sharing one regional egress IP and both Hub 2 spokes sharing another.

Stopping `hub1-nva1` left both BGP sessions on `hub1-nva2` established. Hub 1 protected-spoke traffic to the branch, the local direct spoke, and the internet continued successfully. The stopped NVA was restored and both of its BGP sessions returned to `Established`.

## Cleanup

```powershell
az group delete --subscription <subscription-id> --name <resource-group> --yes --no-wait
```

## Credits

- Daniel Mauser's [inter-region NVA/BGP example](https://github.com/dmauser/azure-virtualwan/tree/main/inter-region-nvabgp)
- [BGP peering with an Azure Virtual WAN hub](https://learn.microsoft.com/azure/virtual-wan/scenario-bgp-peering-hub)

MIT licensed. See [LICENSE](LICENSE).# Azure Virtual WAN NVA/BGP: Inter-Region Spoke Routing

> This lab script is based on work by Daniel Mauser (see *Credits & Source* below).

This repo contains a **Bicep-based deployment** for a two-region **Azure Virtual WAN** lab with eight spokes, two BGP branches, four Ubuntu/FRR NVAs, internal HA Ports load balancers, VPN gateways, test VMs, and Azure Bastion. Traffic is configured with native vHub BGP connections, VNet peering, subnet UDRs, and dynamically exchanged routes.

> **No Routing Intent resources are deployed.** This lab tests inter-region routing through BGP-capable NVAs outside the managed virtual hubs.

> **Validation status:** The templates and parameters pass local compilation and static architecture checks. This repository has not been deployed, and no live Azure route convergence, packet path, symmetry, or failover result is claimed.

## Routing Design

Each region contains one direct spoke, one transit spoke, and two indirect spokes. The transit spoke contains two NVAs behind an internal Standard load balancer.

| Region | Transit spoke | NVA peer IPs | NVA ASN | Advertised aggregate | ILB frontend |
|---|---|---|---|---|---|
| Region 1 | `spoke2-transit-westus3` | `10.11.0.4`, `10.11.0.5` | `65010` | `10.8.0.0/13` | `10.11.0.10` |
| Region 2 | `spoke4-transit-centralus` | `10.139.0.4`, `10.139.0.5` | `65010` | `10.136.0.0/13` | `10.139.0.10` |

The deployment creates four native `Microsoft.Network/virtualHubs/bgpConnections` resources. Each vHub peers with both NVAs in its local transit spoke. FRR receives the vHub router IPs at deployment time and advertises the local regional aggregate.

| Connection | vHub connected | Routing behavior |
|---|---|---|
| Spoke 1 | Hub 1 | Direct vHub connection |
| Spoke 2 | Hub 1 | Transit connection containing Region 1 NVAs |
| Spoke 3 | Hub 2 | Direct vHub connection |
| Spoke 4 | Hub 2 | Transit connection containing Region 2 NVAs |
| Spokes 5 and 6 | No | Peered to Spoke 2; default UDR targets `10.11.0.10` |
| Spokes 7 and 8 | No | Peered to Spoke 4; default UDR targets `10.139.0.10` |
| Branch 1 | Hub 1 VPN | BGP ASN `65101`, dual IPsec tunnels |
| Branch 2 | Hub 2 VPN | BGP ASN `65102`, dual IPsec tunnels |
| Bastion VNet | Hub 1 | Direct vHub connection with internet security disabled |

The indirect-spoke peerings enable virtual network access and forwarded traffic in both directions. Their workload subnets disable BGP route propagation and use `0.0.0.0/0` with next-hop type `VirtualAppliance` to reach the local HA Ports load balancer.

The NVA bootstrap enables Linux IP forwarding, disables reverse-path filtering, installs FRR, configures BGP against both local vHub routers, enables NAT, and starts a TCP health-probe listener on port `8080`.

## Architecture

The diagram uses the requested reference-style architecture asset from the source lab.

![Lab Architecture](image/vwan-interhub-spoke-azfw-reference-style.svg)

## Prerequisites

### Requirements

- **PowerShell 7+** - Run the deployment script with `pwsh`. Windows PowerShell 5.1 is not supported.
- **Azure Subscription** - An active subscription with sufficient regional quota for the resources deployed.
- **RBAC role at subscription scope** - **Contributor** is sufficient; **Owner** also works. Resource-group-only access is insufficient because the subscription-scoped template creates the resource group.
- **Azure CLI with Bicep support** - The deployment script invokes `az deployment sub create`.
- Logged in to Azure CLI. When deploying to another tenant, specify its tenant ID or verified domain:

  ```powershell
  az login --tenant "<TENANT_ID_OR_DOMAIN>"
  ```

### Required Resource Providers

The subscription must have these resource providers registered:

- `Microsoft.Network`
- `Microsoft.Compute`

The default deployment includes 14 Linux VMs, two vHubs, two vHub VPN gateways, two branch VPN gateways, two internal load balancers, and one Standard Bastion host. Check regional VM and networking quotas before deployment.

## Getting Started

### Clone the Repository

```powershell
git clone https://github.com/colinweiner111/azure-vwan-interregion-nva-bgp-routing-lab.git
cd azure-vwan-interregion-nva-bgp-routing-lab
```

## Deployment

Use the PowerShell deployment script:

```powershell
.\deploy-bicep.ps1 -SubscriptionId <subscription-id> -ResourceGroupName <your-rg-name> -Location westus3 -Location2 centralus
```

Example:
```powershell
.\deploy-bicep.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName vwan-interregion-nva-bgp-test01 -Location westus3 -Location2 centralus
```

The script will:
1. Select and verify the exact subscription supplied with `-SubscriptionId`
2. Refuse an existing resource group unless `-ResumeExisting` is explicitly supplied
3. Deploy the subscription-scoped Bicep template, which creates the resource group
4. Prompt securely for the VM admin password and VPN pre-shared key if not provided

> **Use a fresh resource group.** `-ResumeExisting` is only for a deliberately reviewed, isolated deployment created from this lab. Never target an unrelated resource group.

### Required Parameter

- `-SubscriptionId`: Azure subscription GUID to select, verify, and use for all resource checks and deployment operations

### Optional Parameters

- `-ResourceGroupName`: Resource group name (default: `vwan-interregion-nva-bgp-lab`)
- `-Location`: Hub 1, Branch 1, and Bastion region (default: `westus3`)
- `-Location2`: Hub 2 and Branch 2 region (default: `westus3`)
- `-AdminUsername`: Linux VM administrator username (default: `azureuser`)
- `-VmSize`: VM SKU for NVA and test VMs (default: `Standard_D2ls_v7`)
- `-AdminPassword`: Linux VM administrator password as a `SecureString`
- `-VpnSharedKey`: Branch VPN pre-shared key as a `SecureString`
- `-ResumeExisting`: Resume a reviewed existing resource group created from this lab

For non-interactive use, construct the secure parameters before invoking the script:

```powershell
$adminPassword = ConvertTo-SecureString $env:AZURE_VM_ADMIN_PASSWORD -AsPlainText -Force
$vpnSharedKey = ConvertTo-SecureString $env:AZURE_VPN_SHARED_KEY -AsPlainText -Force
./deploy-bicep.ps1 -SubscriptionId <subscription-id> -AdminPassword $adminPassword -VpnSharedKey $vpnSharedKey
```

## What Gets Deployed

- One Standard Virtual WAN and two Standard vHubs
- Eight spoke VNets across two regions
- Four native vHub BGP connections
- Four Ubuntu/FRR NVAs with static private IPs and NIC IP forwarding
- Two internal Standard HA Ports load balancers
- Four indirect-spoke UDRs and eight bidirectional peering links
- Two BGP branch VNets with route-based VPN gateways and dual IPsec tunnels
- **Azure Bastion - provides browser-based SSH access to all VMs**
- **14 Ubuntu VMs:**
  - nva-r1-1, nva-r1-2 (in Region 1 transit spoke)
  - nva-r2-1, nva-r2-2 (in Region 2 transit spoke)
  - spoke1-vm through spoke8-vm (in direct, transit, and indirect spokes)
  - branch1-vm, branch2-vm (in branch VNets)

## Default Configuration

- **Username**: `azureuser`
- **Password**: Prompted during deployment
- **Regions**: Both hubs in `westus3` by default; pass `-Location2 centralus` for the interregion topology
- **VM Size**: `Standard_D2ls_v7`
- **NVA ASN**: `65010`
- **Branch ASNs**: `65101` and `65102`
- **vHub ASN**: `65515`
- **VPN pre-shared key**: Prompted during deployment

## VM Network Information

| VM Name | Network | Subnet or address |
|---------|------|-------------------|
| `spoke1-vm` | Spoke 1 direct | `10.10.0.0/24` |
| `spoke2-vm` | Spoke 2 transit workload | `10.11.0.64/26` |
| `spoke3-vm` | Spoke 3 direct | `10.138.0.0/24` |
| `spoke4-vm` | Spoke 4 transit workload | `10.139.0.64/26` |
| `spoke5-vm` | Spoke 5 indirect | `10.12.0.0/24` |
| `spoke6-vm` | Spoke 6 indirect | `10.13.0.0/24` |
| `spoke7-vm` | Spoke 7 indirect | `10.140.0.0/24` |
| `spoke8-vm` | Spoke 8 indirect | `10.141.0.0/24` |
| `branch1-vm` | Branch 1 workload | `10.200.0.64/26` |
| `branch2-vm` | Branch 2 workload | `10.201.0.64/26` |
| `nva-r1-1`, `nva-r1-2` | Region 1 NVA subnet | `10.11.0.4`, `10.11.0.5` |
| `nva-r2-1`, `nva-r2-2` | Region 2 NVA subnet | `10.139.0.4`, `10.139.0.5` |

Workload VMs receive dynamic private IPs. Retrieve current addresses before testing:

```powershell
az vm list-ip-addresses --resource-group <your-rg> --query "[].{vm:virtualMachine.name,privateIp:virtualMachine.network.privateIpAddresses[0]}" -o table
```

## Cleanup

When finished, delete the isolated resource group:
```powershell
az group delete --subscription <subscription-id> --name <your-rg> --yes --no-wait
```

## Validation

Run the local checks before deployment:

```powershell
pwsh ./tests/Test-Routing.ps1
```

The local suite verifies Bicep compilation, secure parameter types, four NVA peer definitions, HA Ports configuration, NVA IP forwarding, FRR bootstrap inclusion, regional aggregate advertisements, indirect-spoke UDRs, forwarded-traffic peerings, two BGP branches, and PowerShell syntax.

### Intra-region paths

| Path | Result | Required evidence |
|---|---|---|
| Spoke 5 -> Region 1 ILB -> NVA -> Hub 1 -> Spoke 1 | NOT TESTED | TCP result, effective routes, NVA flow evidence |
| Spoke 1 -> Hub 1 -> NVA -> Spoke 5 | NOT TESTED | Return-path symmetry and NVA flow evidence |
| Spoke 7 -> Region 2 ILB -> NVA -> Hub 2 -> Spoke 3 | NOT TESTED | TCP result, effective routes, NVA flow evidence |
| Spoke 3 -> Hub 2 -> NVA -> Spoke 7 | NOT TESTED | Return-path symmetry and NVA flow evidence |

### Branch paths

| Path | Result | Required evidence |
|---|---|---|
| Branch 1 -> VPN/BGP -> Hub 1 -> regional spokes | NOT TESTED | Tunnel state, learned routes, bidirectional TCP |
| Branch 2 -> VPN/BGP -> Hub 2 -> regional spokes | NOT TESTED | Tunnel state, learned routes, bidirectional TCP |
| Branch 1 -> Virtual WAN -> Branch 2 | NOT TESTED | Both branch route tables and bidirectional TCP |

### Inter-region paths

| Path | Result | Required evidence |
|---|---|---|
| Region 1 indirect spoke -> NVA -> Hub 1 -> Hub 2 -> Region 2 direct spoke | NOT TESTED | Aggregate route propagation and symmetric TCP |
| Region 2 indirect spoke -> NVA -> Hub 2 -> Hub 1 -> Region 1 direct spoke | NOT TESTED | Aggregate route propagation and symmetric TCP |
| Spoke 5 -> both regional NVA paths -> Spoke 7 | NOT TESTED | Forward and return NVA selection, packet capture |

### NVA failover

| Test | Result | Required evidence |
|---|---|---|
| Remove one Region 1 NVA from the ILB backend | NOT TESTED | Probe state, convergence time, uninterrupted or recovered flow |
| Stop FRR on one Region 2 NVA | NOT TESTED | BGP withdrawal, effective routes, recovered flow |

Successful connectivity alone does not prove the intended NVA path. Correlate effective routes, BGP learned/advertised routes, ILB health, FRR state, and packet or flow evidence before claiming inspection, symmetry, or failover.

## Credits & Source

- Daniel Mauser, [`inter-region-nvabgp`](https://github.com/dmauser/azure-virtualwan/tree/main/inter-region-nvabgp) - architecture inspiration.
- The predecessor Virtual WAN lab - repository structure, deployment safeguards, README format, and source diagram style.
- [BGP peering with a Virtual WAN hub](https://learn.microsoft.com/azure/virtual-wan/scenario-bgp-peering-hub) - Microsoft documentation.

---

MIT licensed. See [LICENSE](LICENSE).
