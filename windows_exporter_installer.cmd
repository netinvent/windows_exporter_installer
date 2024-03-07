@echo off

set curdir=%~dp0
set curdir=%curdir:~0,-1%
set curdrive=%~d0

FOR /F "tokens=* USEBACKQ" %%F IN (`dir windows_exporter*.msi /b/s`) DO (
SET msi_file=%%F
)

powershell -ExecutionPolicy Bypass -NonInteractive -NoLogo -File %curdir%\windows_exporter_installer.ps1
