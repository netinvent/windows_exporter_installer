
<#
# Windows check if a reboot is needeed
# 
# Written by Orsiris de Jong - NetInvent
# 
# Changelog
# 2026-08-21: Initial version
#
# Tested on:
# - Windows Server 2025
#
# Usage:
#
# Setup the path to the text collector directory (defaults to what the windows_exporter MSI installer sets
# and create a scheduled task to run this script every 5 minutes
# Run program: powershell.exe
# Arguments: -ExecutionPolicy Bypass "C:\SCRIPTS\needs_reboot.ps1"
#
#>

$TEXT_COLLECTOR_PATH="C:\Program Files\windows_exporter\textfile_inputs"

function NeedsReboot {

    # Proudly taken from https://stackoverflow.com/a/47869761/2635443
    $prometheus_status = "# HELP windows_needs_reboot '1' if a reboot is required
# TYPE windows_needs_reboot gauge`n"

    #Adapted from https://gist.github.com/altrive/5329377
    #Based on <http://gallery.technet.microsoft.com/scriptcenter/Get-PendingReboot-Query-bdb79542>
    function Test-PendingReboot {
        if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { return $true }
        if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { return $true }
        if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { return $true }
        try { 
            $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
            $status = $util.DetermineIfRebootPending()
            if (($status -ne $null) -and $status.RebootPending) {
                return $true
            }
        }
        catch { }

        return $false
    }
    if (Test-PendingReboot) {
        $needs_reboot = 1
    } else {
        $needs_reboot = 0
    }
    $prometheus_status += "windows_needs_reboot{} $needs_reboot`n"
    return $prometheus_status
}


$prometheus_status = ""
$prometheus_status += NeedsReboot

$prom_file = Join-Path -Path $TEXT_COLLECTOR_PATH -ChildPath "needs_reboot.prom"
# The following command forces powershell to create a UTF-8 file without BOM, see https://stackoverflow.com/a/34969243
$null = New-Item -Force $prom_file -Value $prometheus_status
