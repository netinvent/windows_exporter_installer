# windows_exporter installer script
# Written in 2023-2025 by Orsiris de Jong - NetInvent
# Script ver 2025071001

# Changelog
# 2025-07-10: - Add error message on MSI install failure
# 2025-07-07: - Update default collectors for windows_exporter 0.31+
# 2025-03-24: - Re-enable firewall exception, disabled by upstream
# 2025-03-20: - Add automatic best git version download
# 2024-10-28: - Add installation log
# 2024-06-08: - Add Hyper-V health script and task setup
# 2024-04-09: - Add optional Hyper-V collector
#             - Uninstall previous windows_exporter versions
#             - Add storage_health script and task setup
#             - Auto download windows_exporter last version if not present in directory
#             - Check if the script is run as administrator


$git_org = "prometheus-community"
$git_repo = "windows_exporter"
$filenamePattern = "windows_exporter*-amd64.msi"

$dest_script_path = "C:\NPF\SCRIPTS"

$LISTEN_PORT=9182
# Remove FirewallException if you don't want to add a firewall exception
$ADD_LOCAL="FirewallException"

# collector logon has been replaced with terminal_servies in windows_exporter 0.31+
$BASIC_PROFILE="[defaults],cpu_info,terminal_services,memory,tcp,textfile,service"
$AD_COLLECTORS=",ad,dns"
$IIS_COLLECTOR=",iis"
$MSSQL_COLLECTOR=",mssql"
$HYPERV_COLLECTOR=",hyperv"

try {
    $script_path = Split-Path $MyInvocation.MyCommand.Path -Parent
} catch {
    Write-Output "Please run this script from command line (or from batch file)"
    exit 1
}
$ScriptFullPath = $MyInvocation.MyCommand.Path
# Start logging stdout and stderr to file
Start-Transcript -Path "$ScriptFullPath.log" -Append

# TODO: Get Windows server version, if newer than 2016, add this
# Also check Win10 / 11 compat
$2016_AND_NEWER_COLLECTORS=",time"

# textfile collector dir is created by MSI, defaults to C:\Program Files\windows_exporter\textfile_inputs

function DownloadGitRelease {
    # Download current release from github

    $releasesUri = "https://api.github.com/repos/$git_org/$git_repo/releases/latest"
    $downloadUri = ((Invoke-RestMethod -Method GET -Uri $releasesUri).assets | Where-Object name -like $filenamePattern ).browser_download_url
    $MSI_FILE = Join-Path -Path $script_path -ChildPath $(Split-Path -Path $downloadUri -Leaf)
    Write-Output "Downloading github release to $MSI_FILE"
    Invoke-WebRequest -Uri $downloadUri -Out $MSI_FILE
}


function IsDomainController {
    
    $Role = Get-Wmiobject -Class "Win32_computersystem" -ErrorAction Stop
    If ($Role) {
        #Switch ($Role.pcsystemtype) {
        #    "1"     {} # "Desktop"
        #    "2"     {} # "Mobile / Laptop"
        #    "3"     {} # "Workstation"
        #    "4"     {} # "Enterprise Server"
        #    "5"     {} # "Small Office and Home Office (SOHO) Server"
        #    "6"     {} # "Appliance PC"
        #    "7"     {} # "Performance Server"
        #    "8"     {} # "Maximum"
        #    default {} # "Not a known Product Type"
        #}
        Switch ($Role.domainrole) {
            "0" { return $false }    # "Stand-alone workstation"
            "1" { return $false }    # "Member workstation"
            "2" { return $false }    # "Stand-alone server"
            "3" { return $false }    # "Member server"
            "4" { return $true }     # "Domain controller"
            "5" { return $true }     # "Pdc emulator domain controller"
        }
   
    }
    Return $false
}


function IsIISInstalled {
    try {
        if ((Get-WindowsFeature WebServer).InstallState -eq "Installed") {
            return $true
        } 
        else {
            return $false
        }
    } catch {
        return $false
    }
}

function IsMSSQLInstalled {
    $SQLPath = "HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL"
    return Test-Path $SQLPath
}

function IsHyperVInstalled {
    try {
        if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled") {
            return $true
        } else {
            return $false
        }
    } catch {
        Write-Output "Cannot determine if Hyper-V is installed, do you have admin super powers ?"
        exit 1
    }
}

function IsNT10OrBetter {
    if (([System.Environment]::OSVersion.Version).Major -ge 10) {
        return $true
    } else {
        return $false
    }
}

function SetupScript([string]$setup_type) {
    if ($setup_type -eq "storage") {
        $script = "storage_health.ps1"
        $taskname = "Windows_exporter Storage Health"
    } elseif ($setup_type -eq "hyperv") {
        $script = "hyperv_health.ps1"
        $taskname = "Windows_exporter Hyper-V Health"
    } else {
        Write-Output "Unknown script type $setup_type"
        exit 1
    }

    $result = New-Item -ItemType Directory -Force -Path $dest_script_path
    if ($null -ne $result) {
        Write-Output "Directory $dest_script_path created"
    } else {
        Write-Output "Directory $dest_script_path creation failed"
        exit 1
    }
    $current_script_path = Join-Path -Path $script_path -ChildPath $script
    $dest_script_path = Join-Path -Path $dest_script_path -ChildPath $script
    try {
        Copy-Item $current_script_path -Destination $dest_script_path -Force | Out-Null
    } catch {
        Write-Output "File $script copy failed"
        exit 1
    }
    $taskdescription = "Collects $setup_type health information and sends info to textcollector directory for windows_exporter to pickup"
    $arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest_script_path`""
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument $arguments
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $task = Get-ScheduledTask -TaskName $taskname -ErrorAction SilentlyContinue
    if ($null -ne $task) {
        Write-Output "Task $taskname already exists. Deleting it."
        Unregister-ScheduledTask -TaskName $taskname -Confirm:$false | Out-Null
    }

    $result = Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskname -Description $taskdescription -Runlevel Highest -Settings $settings -User "System" | Out-Null
    if ($null -eq $result) {
        Write-Output "Task $taskname created"
    } else {
        Write-Output "Task $taskname creation failed"
        exit 1
    }
    Get-ScheduledTask -TaskName $taskname | Start-ScheduledTask
}

# Script entry point

$principal = new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator) -eq $false) {
    Write-Output "You need to run this script as an administrator"
    exit 1
}

try {
    $MSI_FILE=(Get-ChildItem $script_path -filter "windows_exporter*.msi")[0].FullName
    Write-Output "Found windows_exporter in $MSI_FILE"
} catch {
    Write-Output "No windows_exporter msi file found. Trying to download a copy from github"
    DownLoadGitRelease
}


$COLLECTORS = $BASIC_PROFILE
if (IsDomainController) {
    $COLLECTORS = $COLLECTORS + $AD_COLLECTORS
}
if (IsIISInstalled) {
    $COLLECTORS = $COLLECTORS + $IIS_COLLECTOR
}
if (IsMSSQLInstalled) {
    $COLLECTORS = $COLLECTORS + $MSSQL_COLLECTOR
}
if (IsHyperVInstalled) {
    $COLLECTORS = $COLLECTORS + $HYPERV_COLLECTOR
}
if (IsNT10OrBetter) {
    $COLLECTORS = $COLLECTORS + $2016_AND_NEWER_COLLECTORS
}

# Uninstall any previous versions
$app = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -match "windows_exporter" }
if ($null -ne $app) {
    Write-Output "Uninstalling previous windows_exporter"
	$app.Uninstall() | Out-Null
}

Write-Output "Installing windows exporter with following command line:"
Write-Output "msiexec.exe /passive /i $MSI_FILE ENABLED_COLLECTORS=$COLLECTORS LISTEN_PORT=$LISTEN_PORT ADDLOCAL=$ADD_LOCAL"
msiexec.exe /passive /i $MSI_FILE ENABLED_COLLECTORS="$COLLECTORS" LISTEN_PORT=$LISTEN_PORT ADDLOCAL=$ADD_LOCAL
if ($LASTEXITCODE -ne 0) {
    Write-Output "Failed to install $MSI_FILE - See event logs"
    Start-Sleep -s 15
    exit 1
}

Write-Output "Setup storage health task"
SetupScript "storage"
if (IsHyperVInstalled) {
    Write-Output "Setup Hyper-V health task"
    SetupScript "hyperv"
}

Write-Output "Finished setup windows_exporter. Please check by running"
Write-Output "curl http://localhost:9182/metrics"

Stop-Transcript
