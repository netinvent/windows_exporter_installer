
<#
# Windows physical disk / storage pool / virtual disk health reporter for windows_exporter
# 
# Written by Orsiris de Jong - NetInvent
# 
# Changelog
# 2026-01-13: Add HP Smart Array Event Service error detection
# 2024-10-28: Add uniqueid to disks since disk serial numbers might not exist in virtual machines
# 2024-04-05: Initial version
#
# Tested on:
# - Windows Server 2022 with Intel VROC and Storage Space Direct RAID
#
# Usage:
#
# Setup the path to the text collector directory (defaults to what the windows_exporter MSI installer sets
# and create a scheduled task to run this script every 5 minutes
# Run program: powershell.exe
# Arguments: -ExecutionPolicy Bypass "C:\SCRIPTS\storage_health.ps1"
#
#>

$TEXT_COLLECTOR_PATH="C:\Program Files\windows_exporter\textfile_inputs"

function GetPhysicalDiskState {

    $prometheus_status = "# HELP windows_physical_disk_health_status '1' if disk status is bad
# TYPE windows_physical_disk_health_status gauge
# HELP windows_physical_disk_operational_status '1' if disk operational status is bad
# TYPE windows_physical_disk_operational_status gauge`n"

    $physical_disks = Get-PhysicalDisk

    foreach ($physical_disk in $physical_disks) {
        if ($physical_disk.HealthStatus -eq "Healthy") {
            $healthy = 0
        } else {
            $healthy = 1
        }
        if ($physical_disk.OperationalStatus -eq "OK") {
            $op = 0
        } else {
            $op = 1
        }

        # Don't know why they put dots at the end of a serial number, but here we are
        $serial = $physical_disk.SerialNumber -replace(".", "")
        $uniqueid = $physical_disk.UniqueId
        $name = $physical_disk.FriendlyName

        $prometheus_status += "windows_physical_disk_health_status{name=`"" + $name + "`",serialnumber=`"" + $serial + "`",uniqueid=`"" + $uniqueid + "`"} $healthy`n"
        $prometheus_status += "windows_physical_disk_operational_status{name=`"" + $name + "`",serialnumber=`"" + $serial + "`",uniqueid=`"" + $uniqueid + "`"} $op`n"

    }
    return $prometheus_status
}

function GetStoragePoolStatus {

    $prometheus_status = "# HELP windows_storage_pool_health_status '1' if the storage pool health failed
# TYPE windows_storage_pool_health_status gauge
# HELP windows_storage_pool_operational_status '1' if  the storage pool operational status failed
# TYPE windows_storage_pool_operational_status gauge
# HELP windows_storage_pool_is_readonly '1' if the storage pool in degraded readnoly status
# TYPE windows_storage_pool_is_readonly gauge`n"
    $storage_pools = Get-StoragePool

    foreach ($storage_pool in $storage_pools) {
        if ($storage_pool.HealthStatus -eq "Healthy") {
            $healthy = 0
        } else {
            $healthy = 1
        }
        if ($storage_pool.OperationalStatus -eq "OK") {
            $op = 0
        } else {
            $op = 1
        }

        if ($storage_pool.IsReadonly -eq $false) {
            $readonly = 0
        } else {
            $readonly = 1
        }

        $name = $storage_pool.FriendlyName
        $primordial = $storage_pool.IsPrimordial

        $prometheus_status += "windows_storage_pool_health_status{name=`"" + $name + "`",primordial=`"" + $primordial + "`"} $healthy`n"
        $prometheus_status += "windows_storage_pool_operational_status{name=`"" + $name + "`",primordial=`"" + $primordial + "`"} $op`n"
        $prometheus_status += "windows_storage_pool_is_readonly{name=`"" + $name + "`",primordial=`"" + $primordial + "`"} $readonly`n"

    }
    return $prometheus_status
}


function GetVirtualDiskStatus {

    $prometheus_status = "# HELP windows_virtual_disk_health_status '1' if the virtual disk health failed
# TYPE windows_virtual_disk_health_status gauge
# HELP windows_virtual_disk_operational_status '1' if the virtual disk operational status failed
# TYPE windows_virtual_disk_operational_status gauge`n"
    $virtual_disks = Get-VirtualDisk

    foreach ($virtual_disk in $virtual_disks) {
        if ($virtual_disk.HealthStatus -eq "Healthy") {
            $healthy = 0
        } else {
            $healthy = 1
        }
        if ($virtual_disk.OperationalStatus -eq "OK") {
            $op = 0
        } else {
            $op = 1
        }


        $name = $virtual_disk.FriendlyName

        $prometheus_status += "windows_virtual_disk_health_status{name=`"" + $name + "`"} $healthy`n"
        $prometheus_status += "windows_virtual_disk_operational_status{name=`"" + $name + "`"} $op`n"

    }
    return $prometheus_status
}

function GetHPSmartArrayStatus {
    # We need to check whether Cissesrv exists
    if (Get-Service "cissesrv" -ErrorAction SilentlyContinue) {
        # If an error is found, we'll keep the textcollector file around until it is manually deleted by a sysadmin
        $prometheus_status = "#HELP windows_hpe_smart_array_health_status '1' if array has errors`n"
        
        # Check for CISSESRV (hp smart array event service) errors in system event log for the last 24h
        $events = Get-EventLog System -After (Get-Date).AddDays(-1) -Source Cissesrv -EntryType Error
        if ($events) {
            $prometheus_status += "windows_hpe_smart_array_health_status{} 1`n"
        } else {
            $prometheus_status += "windows_hpe_smart_array_health_status{} 0`n"
        }
        return $prometheus_status 
    } else {
        return ""
    }
}


$prometheus_status = ""
$prometheus_status += GetPhysicalDiskState
$prometheus_status += GetStoragePoolStatus
$prometheus_status += GetVirtualDiskStatus
$prometheus_status += GetHPSmartArrayStatus

$prom_file = Join-Path -Path $TEXT_COLLECTOR_PATH -ChildPath "windows_storage_health.prom"

# The following command forces powershell to create a UTF-8 file without BOM, see https://stackoverflow.com/a/34969243
$null = New-Item -Force $prom_file -Value $prometheus_status
