<#
.SYNOPSIS
Azure VM Orchestration and Management for HELIOS Platform

.DESCRIPTION
Manages Azure Virtual Machines including:
- VM provisioning and deployment
- VM lifecycle management
- VM extensions and agents
- VM performance monitoring
- Disk management
- Network interface management

.NOTES
Author: HELIOS Platform
Version: 1.0.0
Requires: Az.Compute module
#>

#Requires -Modules Az.Compute, Az.Storage, Az.Network

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\azure-config.json"
)

$LogDirectory = "C:\Logs\HELIOS\Azure"
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "vm-orchestrator-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Warning', 'Error', 'Success')]$Level = 'Info')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logMessage -Force
    
    $color = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
    }
    Write-Host $logMessage -ForegroundColor $color[$Level]
}

function Get-ConfigValue {
    param([string]$Key, [string]$DefaultValue = $null)
    
    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        return $config.$Key ?? $DefaultValue
    }
    return $DefaultValue
}

function New-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [string]$ImageName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('UbuntuLTS', 'WindowsServer2022', 'CentOS8', 'RHEL8')]
        [string]$ImageType,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Standard_B1s', 'Standard_B2s', 'Standard_D2s_v3', 'Standard_D4s_v3')]
        [string]$VMSize,
        
        [Parameter(Mandatory = $true)]
        [string]$VNetName,
        
        [Parameter(Mandatory = $true)]
        [string]$SubnetName,
        
        [Parameter(Mandatory = $false)]
        [string]$AdminUsername = 'azureuser',
        
        [Parameter(Mandatory = $false)]
        [securestring]$AdminPassword,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags
    )
    
    try {
        Write-Log "Creating Virtual Machine: $VMName"
        
        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $VNetName -ErrorAction Stop
        $subnet = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName -ErrorAction Stop
        
        $nic = New-AzNetworkInterface -Name "$VMName-nic" -ResourceGroupName $ResourceGroupName `
            -Location $vnet.Location -Subnet $subnet -ErrorAction Stop
        
        $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize
        
        switch ($ImageType) {
            'UbuntuLTS' {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VMName `
                    -Credential (New-Object PSCredential($AdminUsername, (ConvertTo-SecureString -AsPlainText -Force 'TempPassword123!')))
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'Canonical' -Offer '0001-com-ubuntu-server-focal' `
                    -Skus '20_04-lts-gen2' -Version 'Latest'
            }
            'WindowsServer2022' {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VMName `
                    -Credential (New-Object PSCredential($AdminUsername, $AdminPassword ?? (ConvertTo-SecureString -AsPlainText -Force 'Helios@123')))
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'MicrosoftWindowsServer' `
                    -Offer 'WindowsServer' -Skus '2022-datacenter-g2' -Version 'Latest'
            }
            'CentOS8' {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VMName `
                    -Credential (New-Object PSCredential($AdminUsername, (ConvertTo-SecureString -AsPlainText -Force 'TempPassword123!')))
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'OpenLogic' -Offer 'CentOS' `
                    -Skus '8_5-gen2' -Version 'Latest'
            }
            'RHEL8' {
                $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $VMName `
                    -Credential (New-Object PSCredential($AdminUsername, (ConvertTo-SecureString -AsPlainText -Force 'TempPassword123!')))
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName 'RedHat' -Offer 'RHEL' `
                    -Skus '8' -Version 'Latest'
            }
        }
        
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id
        
        $vm = New-AzVM -ResourceGroupName $ResourceGroupName -VM $vmConfig -ErrorAction Stop
        
        if ($Tags) {
            Update-AzTag -ResourceId $vm.Id -Tag $Tags -Operation Merge | Out-Null
        }
        
        Write-Log "Virtual Machine created successfully: $VMName" -Level Success
        return $vm
    }
    catch {
        Write-Log "Failed to create VM: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Start-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )
    
    try {
        Write-Log "Starting Virtual Machine: $VMName"
        
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait -ErrorAction Stop
        
        Write-Log "VM start command issued successfully: $VMName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to start VM: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Stop-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $false)]
        [switch]$SkipShutdown
    )
    
    try {
        Write-Log "Stopping Virtual Machine: $VMName"
        
        if ($SkipShutdown) {
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait -Force -ErrorAction Stop
        }
        else {
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -NoWait -ErrorAction Stop
        }
        
        Write-Log "VM stop command issued successfully: $VMName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to stop VM: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Remove-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    try {
        Write-Log "Removing Virtual Machine: $VMName"
        
        Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force:$Force `
            -ErrorAction Stop
        
        Write-Log "Virtual Machine removed successfully: $VMName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to remove VM: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-VMStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )
    
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status -ErrorAction Stop
        
        return @{
            Name            = $vm.Name
            ResourceGroup   = $ResourceGroupName
            Location        = $vm.Location
            PowerState      = $vm.Statuses | Where-Object { $_.Code -match 'PowerState' } | Select-Object -ExpandProperty DisplayStatus
            ProvisioningState = $vm.Statuses | Where-Object { $_.Code -match 'ProvisioningState' } | Select-Object -ExpandProperty DisplayStatus
            Statuses        = $vm.Statuses
        }
    }
    catch {
        Write-Log "Failed to get VM status: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Resize-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Standard_B1s', 'Standard_B2s', 'Standard_D2s_v3', 'Standard_D4s_v3')]
        [string]$NewVMSize
    )
    
    try {
        Write-Log "Resizing Virtual Machine: $VMName to $NewVMSize"
        
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        $vm.HardwareProfile.VmSize = $NewVMSize
        Update-AzVM -VM $vm -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        Write-Log "Virtual Machine resized successfully: $VMName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to resize VM: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Add-DataDisk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [string]$DiskName,
        
        [Parameter(Mandatory = $true)]
        [int]$DiskSizeGB,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Premium_LRS', 'Standard_LRS', 'StandardSSD_LRS')]
        [string]$StorageType = 'StandardSSD_LRS'
    )
    
    try {
        Write-Log "Adding data disk to VM: $VMName (Size: $DiskSizeGB GB)"
        
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        $disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DiskName `
            -Disk (New-AzDiskConfig -SkuName $StorageType -Location $vm.Location -CreateOption Empty -DiskSizeGB $DiskSizeGB) `
            -ErrorAction Stop
        
        Add-AzVMDataDisk -VM $vm -Name $DiskName -ManagedDiskId $disk.Id -Lun 0 -ErrorAction Stop
        Update-AzVM -VM $vm -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        
        Write-Log "Data disk added successfully to VM: $VMName" -Level Success
        return $disk
    }
    catch {
        Write-Log "Failed to add data disk: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Add-VMExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('CustomScriptExtension', 'WindowsAgent', 'LinuxAgent', 'AzureMonitor')]
        [string]$ExtensionType,
        
        [Parameter(Mandatory = $false)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory = $false)]
        [string]$ExtensionName
    )
    
    try {
        Write-Log "Adding VM Extension to ${VMName}: $ExtensionType"
        
        if (-not $ExtensionName) {
            $ExtensionName = "$VMName-$ExtensionType-$(Get-Date -Format 'yyyyMMddHHmmss')"
        }
        
        switch ($ExtensionType) {
            'CustomScriptExtension' {
                if (-not $ScriptPath) {
                    throw "ScriptPath parameter required for CustomScriptExtension"
                }
                Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -VMName $VMName `
                    -Name $ExtensionName -FileUri $ScriptPath -Run "powershell.exe -File *.ps1" -ErrorAction Stop
            }
            'WindowsAgent' {
                Set-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName `
                    -Name $ExtensionName -Publisher 'Microsoft.Compute' -ExtensionType 'BGInfo' `
                    -TypeHandlerVersion '2.1' -ErrorAction Stop
            }
            'LinuxAgent' {
                Set-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName `
                    -Name $ExtensionName -Publisher 'Microsoft.OSTCExtensions' -ExtensionType 'OSPatchingForLinux' `
                    -TypeHandlerVersion '2.3' -ErrorAction Stop
            }
            'AzureMonitor' {
                Set-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName `
                    -Name $ExtensionName -Publisher 'Microsoft.EnterpriseCloud.Monitoring' `
                    -ExtensionType 'MicrosoftMonitoringAgent' -TypeHandlerVersion '1.0' -ErrorAction Stop
            }
        }
        
        Write-Log "VM Extension added successfully: $ExtensionName" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to add VM extension: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-VMPerformanceMetrics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )
    
    try {
        Write-Log "Retrieving performance metrics for VM: $VMName"
        
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        
        $metrics = @{
            VMName          = $VMName
            Location        = $vm.Location
            VMSize          = $vm.HardwareProfile.VmSize
            ResourceId      = $vm.Id
            Tags            = $vm.Tags
        }
        
        Write-Log "Performance metrics retrieved successfully" -Level Success
        return $metrics
    }
    catch {
        Write-Log "Failed to retrieve metrics: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Backup-VirtualMachine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$VMName,
        
        [Parameter(Mandatory = $false)]
        [string]$SnapshotName
    )
    
    try {
        if (-not $SnapshotName) {
            $SnapshotName = "$VMName-snapshot-$(Get-Date -Format 'yyyyMMddHHmmss')"
        }
        
        Write-Log "Creating snapshot backup for VM: $VMName"
        
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop
        $osDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $vm.StorageProfile.OsDisk.Name -ErrorAction Stop
        
        $snapshotConfig = New-AzSnapshotConfig -SourceUri $osDisk.Id -Location $vm.Location -CreateOption Copy
        $snapshot = New-AzSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $SnapshotName `
            -Snapshot $snapshotConfig -ErrorAction Stop
        
        Write-Log "Snapshot created successfully: $SnapshotName" -Level Success
        return $snapshot
    }
    catch {
        Write-Log "Failed to create snapshot: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-ListAllVMs {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName
    )
    
    try {
        Write-Log "Listing all Virtual Machines"
        
        $getParams = @{
            ErrorAction = 'Stop'
        }
        
        if ($ResourceGroupName) {
            $getParams['ResourceGroupName'] = $ResourceGroupName
        }
        
        $vms = Get-AzVM @getParams
        
        Write-Log "Retrieved $($vms.Count) Virtual Machine(s)" -Level Success
        return $vms
    }
    catch {
        Write-Log "Failed to list VMs: $($_.Exception.Message)" -Level Error
        throw
    }
}

Export-ModuleMember -Function @(
    'New-VirtualMachine',
    'Start-VirtualMachine',
    'Stop-VirtualMachine',
    'Remove-VirtualMachine',
    'Get-VMStatus',
    'Resize-VirtualMachine',
    'Add-DataDisk',
    'Add-VMExtension',
    'Get-VMPerformanceMetrics',
    'Backup-VirtualMachine',
    'Get-ListAllVMs'
)
