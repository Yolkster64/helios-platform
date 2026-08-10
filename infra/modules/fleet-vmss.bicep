// Hermes/Xcore fleet burst capacity — a Linux VM scale set that runs stub fleet-worker
// lanes in cloud mode, plus its CPU-driven autoscale policy. Opt-in from main.bicep
// (deployFleetVmss); see docs/architecture/HERMES_FLEET_AND_XCORE.md,
// "Autoscaling (local / hybrid)" and config/fleet/fleet-topology.json.
//
// Design notes:
// - Flexible orchestration, Ubuntu 24.04 LTS Gen2, SSH-key-only auth (password auth
//   disabled). The NSG ships with NO inbound allow rules by default, so instances are
//   unreachable from the internet even though each carries a Standard public IP: the
//   IP exists for OUTBOUND access only (default outbound access for new VMs retired
//   September 2025). Per-instance IPs — unlike a NAT gateway — bill only while
//   instances exist, preserving scale-to-zero economics.
// - cloud-init (customData) installs the lane toolchain (dotnet-runtime-8.0 and
//   python3 from the Ubuntu archive, pwsh via snap), clones the public repo, and runs
//   workersPerInstance stub fleet workers (python3 -m helios_agents.fleet_worker) as
//   systemd template units honoring the HERMES_KANBAN_* worker-lane contract against
//   a local seed board, with HELIOS_FLEET_POOL set so outcome analytics attribute
//   cloud lanes to their pool. NO secrets appear in cloud-init (it is readable by any
//   process on the instance and via the instance metadata service).
// - Autoscale here is CPU-driven only: queue-depth-driven scaling (scaleUpQueueDepth
//   in config/fleet/fleet-topology.json) arrives via scripts/fleet/scale-fleet.ps1
//   calling `az vmss scale` — Azure autoscale cannot see board queue depth unless the
//   fleet publishes custom metrics to Application Insights, which is out of scope
//   here. CPU >70%/<25% is the platform-metric proxy for busy/idle lanes.

@description('Name of the VM scale set. Derived names (vnet, NSG, autoscale) hang off it.')
param vmssName string

@description('Azure region for all fleet resources.')
param location string

@description('Tags applied to all fleet resources.')
param tags object = {}

@description('VM size for burst instances. B2s (2 vCPU / 4 GiB) fits two stub lanes.')
param vmSku string = 'Standard_B2s'

@description('Admin username on the instances. SSH-key-only; password auth is disabled.')
param adminUsername string

@minLength(1)
@description('SSH public key for adminUsername (e.g. contents of ~/.ssh/id_ed25519.pub). Deliberately NOT @secure(): public keys are not secrets, and keeping the param plain lets main.bicep gate the module on its emptiness.')
param adminPublicKey string

@minValue(1)
@description('Stub fleet worker lanes started per instance (systemd template units).')
param workersPerInstance int = 2

@description('Pool name exported as HELIOS_FLEET_POOL so fleet outcomes carry the cloud pool.')
param fleetPool string = 'cloud-burst'

@description('Git repository cloned onto each instance. Must be public — cloud-init clones anonymously and must never carry credentials.')
param repoUrl string = 'https://github.com/Yolkster64/helios-platform'

@description('Git ref (branch or tag) checked out on each instance.')
param repoRef string = 'main'

@minValue(0)
@description('Autoscale floor and default instance count. 0 = scale-to-zero when idle.')
param burstMinInstances int = 0

@minValue(1)
@description('Autoscale ceiling — the topology default maxBurstLanes (config/fleet/fleet-topology.json).')
param burstMaxInstances int = 5

@minValue(300)
@maxValue(43200)
@description('Idle window in seconds before scale-in — the topology default scaleDownIdleSeconds. Azure autoscale requires windows of at least 300 seconds.')
param scaleDownIdleSeconds int = 300

@description('Address space of the fleet virtual network.')
param vnetAddressPrefix string = '10.44.0.0/24'

@description('Address prefix of the fleet subnet (may equal the vnet space).')
param subnetAddressPrefix string = '10.44.0.0/24'

@description('CIDR allowed to SSH to instances (e.g. an operator IP). Empty string (the default) adds no inbound rule, leaving the NSG default DenyAllInbound in force.')
param sshSourceAddressPrefix string = ''

@description('Managed disk SKU for the OS disk.')
param osDiskStorageAccountType string = 'StandardSSD_LRS'

// ---------------------------------------------------------------------------
// cloud-init — worker lanes as systemd template units. Interpolation is not
// available inside Bicep multi-line strings, so __TOKENS__ are substituted via
// replace() below. HERMES_KANBAN_MAX_IDLE_POLLS=0 makes cloud lanes poll
// forever: scale-in is autoscale's job, not the worker's idle exit.
// ---------------------------------------------------------------------------

var cloudInitTemplate = '''
#cloud-config
package_update: true
packages:
  - git
  - python3
  - dotnet-runtime-8.0
write_files:
  - path: /etc/systemd/system/helios-fleet-worker@.service
    permissions: '0644'
    content: |
      [Unit]
      Description=HELIOS fleet worker lane %i (cloud-burst stub)
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      User=heliosfleet
      WorkingDirectory=/opt/helios/src/ai/python
      Environment=HELIOS_FLEET_POOL=__FLEET_POOL__
      Environment=HERMES_KANBAN_DB=/var/lib/helios-fleet/boards/__FLEET_POOL__.json
      Environment=HERMES_KANBAN_CLAIM_LOCK=/var/lib/helios-fleet/boards/__FLEET_POOL__.json.lock
      Environment=HERMES_KANBAN_TASK=*
      Environment=HERMES_KANBAN_RUN_ID=__FLEET_POOL__-%H
      Environment=HERMES_KANBAN_ASSIGNEE=%H-lane-%i
      Environment=HERMES_KANBAN_MAX_IDLE_POLLS=0
      ExecStart=/usr/bin/python3 -m helios_agents.fleet_worker
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
  - path: /var/lib/helios-fleet/boards/__FLEET_POOL__.json
    permissions: '0664'
    content: |
      { "tasks": [] }
runcmd:
  - snap install powershell --classic
  - useradd --system --create-home --shell /usr/sbin/nologin heliosfleet
  - git clone --depth 1 --branch __REPO_REF__ __REPO_URL__ /opt/helios
  - chown -R heliosfleet:heliosfleet /var/lib/helios-fleet
  - systemctl daemon-reload
  - for i in $(seq 1 __WORKERS_PER_INSTANCE__); do systemctl enable --now helios-fleet-worker@$i.service; done
'''

var cloudInit = replace(
  replace(
    replace(
      replace(cloudInitTemplate, '__FLEET_POOL__', fleetPool),
      '__REPO_URL__',
      repoUrl
    ),
    '__REPO_REF__',
    repoRef
  ),
  '__WORKERS_PER_INSTANCE__',
  string(workersPerInstance)
)

// ---------------------------------------------------------------------------
// Network — NSG default rules deny all inbound from the internet; the optional
// operator rule is the only way in (SSH, key-only).
// ---------------------------------------------------------------------------

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${vmssName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: empty(sshSourceAddressPrefix)
      ? []
      : [
          {
            name: 'allow-ssh-from-operator'
            properties: {
              priority: 1000
              direction: 'Inbound'
              access: 'Allow'
              protocol: 'Tcp'
              sourceAddressPrefix: sshSourceAddressPrefix
              sourcePortRange: '*'
              destinationAddressPrefix: '*'
              destinationPortRange: '22'
            }
          }
        ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${vmssName}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'fleet'
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// VM scale set — Flexible orchestration, system-assigned identity. No
// upgradePolicy: instances are cattle; replacements pick up the latest model.
// Note the sku.capacity here only seeds initial capacity — once the autoscale
// setting below exists, IT owns the instance count (a redeploy that appears as
// a capacity Modify in what-if is normal and is reconciled by autoscale).
// ---------------------------------------------------------------------------

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: vmssName
  location: location
  tags: tags
  sku: {
    name: vmSku
    tier: 'Standard'
    capacity: burstMinInstances
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    orchestrationMode: 'Flexible'
    platformFaultDomainCount: 1
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'hfleet'
        adminUsername: adminUsername
        customData: base64(cloudInit)
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          // Ubuntu 24.04 LTS (noble); the 'server' SKU of this offer is Gen2 x64.
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: osDiskStorageAccountType
          }
        }
      }
      networkProfile: {
        // Required for Flexible orchestration.
        networkApiVersion: '2020-11-01'
        networkInterfaceConfigurations: [
          {
            name: '${vmssName}-nic'
            properties: {
              primary: true
              networkSecurityGroup: {
                id: nsg.id
              }
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: {
                      id: vnet.properties.subnets[0].id
                    }
                    // Outbound-only in practice (NSG blocks inbound): apt, snap,
                    // and the git clone need internet; default outbound access is
                    // retired for new deployments, and this — unlike a NAT
                    // gateway — costs nothing while the set is scaled to zero.
                    publicIPAddressConfiguration: {
                      name: '${vmssName}-pip'
                      sku: {
                        name: 'Standard'
                      }
                      properties: {
                        idleTimeoutInMinutes: 15
                      }
                    }
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Autoscale — CPU proxy for lane pressure. Queue-depth-driven scaling
// (scaleUpQueueDepth in config/fleet/fleet-topology.json) arrives via
// scripts/fleet/scale-fleet.ps1 calling `az vmss scale`; wiring board depth
// into Azure autoscale needs custom metrics in Application Insights, which is
// out of scope for this module.
// ---------------------------------------------------------------------------

resource autoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: '${vmssName}-autoscale'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'fleet-burst'
        capacity: {
          minimum: string(burstMinInstances)
          maximum: string(burstMaxInstances)
          default: string(burstMinInstances)
        }
        rules: [
          {
            // Scale out: average CPU above 70% for 5 minutes -> +1 instance.
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            // Scale in: average CPU below 25% for scaleDownIdleSeconds -> -1 instance.
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'microsoft.compute/virtualmachinescalesets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT${scaleDownIdleSeconds}S'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT${scaleDownIdleSeconds}S'
            }
          }
        ]
      }
    ]
  }
}

@description('Name of the VM scale set.')
output vmssName string = vmss.name

@description('Resource ID of the VM scale set (the az vmss scale target for scale-fleet.ps1).')
output vmssId string = vmss.id

@description('Principal ID of the system-assigned managed identity — grant it roles (e.g. Key Vault Secrets User) if cloud lanes must read provider keys.')
output principalId string = vmss.identity.principalId

@description('Name of the autoscale setting.')
output autoscaleName string = autoscale.name
