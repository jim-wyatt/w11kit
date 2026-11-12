@echo off
rem Writes a hardware profile for THIS PC (profiles\<model>\profile.json) from its
rem running Windows: scripts\New-HardwareProfile.ps1. Runs elevated (UAC prompt): after the
rem first build the kit folder is writable by administrators only (scripts\KitAcl.ps1).
rem Options pass through, e.g.: New-Profile.cmd -Hibernate -WakeOnLan
setlocal
rem Started from PowerShell 7, PSModulePath lists its modules first, and Windows PowerShell 5.1
rem then can't find Get-FileHash and other cmdlets of its own: 5.1 takes its default path instead
set "PSModulePath="
set "W11KIT_ROOT=%~dp0"
set "W11KIT_SELF=%~f0"
set "W11KIT_ARGS=%*"
rem Elevated? fltmc needs admin rights and no service (net session needs the Server service, which the image disables)
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Elevate"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Script 'scripts\New-HardwareProfile.ps1'"
set rc=%errorlevel%
pause
exit /b %rc%
