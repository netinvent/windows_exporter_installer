# windows_exporter installer script
# (C) 2023 Orsiris de Jong - NetInvent
# Script ver 2023110201


$script_path = Split-Path $MyInvocation.MyCommand.Path -Parent
$LISTEN_PORT=9182
$BASIC_PROFILE="[defaults],cpu_info,logon,memory,tcp,textfile,service"
$AD_COLLECTORS=",ad,dns"
$IIS_COLLECTOR=",iis"
$MSSQL_COLLECTOR=",mssql"

# TODO: Get Windows server version, if newer than 2016, add this
# Also check Win10 / 11 compat
$2016_AND_NEWER_COLLECTORS=",time"

# textfile collector dir is created by MSI, defaults to C:\Program Files\windows_exporter\textfile_inputs

function IsDomainController {
    
    $Role = Get-Wmiobject -Class ‘Win32_computersystem’ -ErrorAction Stop
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
    if (Test-Path “HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL”) {
    return $true
    } Else {
    return $false
    }
}

# Script entry point

try {
    $MSI_FILE=(Get-ChildItem $script_path -filter "windows_exporter*.msi")[0].FullName
} catch {
    Write-Output "No windows_exporter msi file found. Please place the file in the same dir as the script."
    exit 1
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

Write-Output "Installing $MSI_FILE with collectors: $COLLECTORS"
msiexec.exe /i $MSI_FILE ENABLED_COLLECTORS="$COLLECTORS" LISTEN_PORT=$LISTEN_PORT
