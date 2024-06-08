
<#
# Windows Hyper-V VM and replication health reporter for windows_exporter
# 
# Written by Orsiris de Jong - NetInvent
# 
# Changelog
# 2024-06-08: Initial version
#
# Tested on:
# - Windows Server 2022 with Hyper-V and Hyper-V replication
#
# Usage:
#
# Setup the path to the text collector directory (defaults to what the windows_exporter MSI installer sets
# and create a scheduled task to run this script every 5 minutes
# Run program: powershell.exe
# Arguments: -ExecutionPolicy Bypass "C:\SCRIPTS\hyperv_health.ps1"
#
#>

$TEXT_COLLECTOR_PATH="C:\Program Files\windows_exporter\textfile_inputs"


function GetHyperVVMState {
    # We'll exclude all machines which aren't set for automatic start, since we don't need to get VM state

    $prometheus_status = "# HELP windows_hyperv_vm_status Is the vm in a bad shape
# TYPE windows_hyperv_vm_status gauge
# HELP windows_hyperv_vm_state Is the vm not running
# TYPE windows_hyperv_vm_state gauge`n"

    $vms = Get-VM | Where-Object {$_.AutomaticStartAction -eq 'Start'}

    foreach ($vm in $vms) {    
        if ($vm.State -eq "Running") {
            $running = 0
        } else {
            $running = 1
        }

        # Get list of possible OperationalStatus with
        # [enum]::GetNames([Microsoft.HyperV.Powershell.VMOperationalStatus])

        $good_states = ('Ok', 'InService', 'ApplyingSnapshot', 'CreatingSnapshot', 'DeletingSnapshot', 'MergingDisks', 'ExportingVirtualMachine', 'MigratingVirtualMachine', 'BackingUpVirtualMachine', 'ModifyingUpVirtualMachine', 'StorageMigrationPhaseOne', 'StorageMigrationPhaseTwo', 'MigratingPlannedVm')
        if ($good_states.contains([string]$vm.OperationalStatus)) {
            $healthy = 0
        } else {
            $healthy = 1
        }

        $vmname = $vm.Name
        $vmhost = (Get-VMHost).Name

        $prometheus_status += "windows_hyperv_vm_status{vm=`"" + $vmname + "`",host=`"" + $vmhost + "`"} $running`n"
        $prometheus_status += "windows_hyperv_vm_state{vm=`"" + $vmname + "`",host=`"" + $vmhost + "`"} $healthy`n"

    }
    return $prometheus_status
}

function GetHyperVReplicationState {
    $prometheus_status = "# HELP windows_hyperv_replication_health_status Is the replication in bad health
# TYPE windows_hyperv_replication_health_status gauge
# HELP windows_hyperv_replication_status Is replication not ongoing
# TYPE windows_hyperv_replication_status gauge`n"

    $replications = Get-VMReplication

    foreach ($replication in $replications) {
        if ($replication.ReplicationHealth -eq "Normal") {
            $healthy = 0
        } else {
            $healthy = 1
        }

        if ([String]$replication.ReplicationState -eq "Replicating") {
            $replicating = 0
        } else {
            $replicating = 1
        }

        $vmname = $replication.VMName
        $source = $replication.PrimaryServerName
        $dest = $replication.ReplicaServerName

        $prometheus_status += "windows_hyperv_replication_health_status{vm=`"" + $vmname + "`",source=`"" + $source + "`",destination=`"" + $dest + "`"} $healthy`n"
        $prometheus_status += "windows_hyperv_replication_status{vm=`"" + $vmname + "`",source=`"" + $source + "`",destination=`"" + $dest + "`"} $replicating`n"

    }
    return $prometheus_status
}


$prometheus_status = ""
$prometheus_status += GetHyperVVMState
$prometheus_status += GetHyperVReplicationState

$prom_file = Join-Path -Path $TEXT_COLLECTOR_PATH -ChildPath "hyperv_health.prom"
# The following command forces powershell to create a UTF-8 file without BOM, see https://stackoverflow.com/a/34969243
$null = New-Item -Force $prom_file -Value $prometheus_status
