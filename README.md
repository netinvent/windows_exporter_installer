## Prometheus windows_exporter installer script

This is a quick cmd/powershell install script for windows_exporter that does the following:

- Detect Active Directory
- Detect Microsoft SQL Server
- Detect Remote Desktop Server
- Detect IIS Server
- Detect Hyper-V
- Detect OS version
- Activate collectors corresponding to detection

It will also install a copy of `storage_health.ps1` and `hyperv_health.ps1` into `C:\NPF\SCRIPTS` and setup a scheduled task to be executed every 5 minutes.
This will allow `windows_exporter` to pickup additional storage health metrics and Hyper-V VM and replication metrics.

Firewall port 9182 is opened by the MSI installer.

## Setup

Download the script directory and execute `windows_exporter_installer.cmd` or `windows_exporter_installer.ps1`
If the current directory contains a copy of windows_exporter msi file, it will run this one.
Else, the script will try to download a copy from Github

## Misc

An example Grafana Dashboard for storage health can be found in the examples directory