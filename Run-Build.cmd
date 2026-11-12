@echo off
rem Elevated launcher for scripts\Build-Iso.ps1. Options pass through, e.g. -Profile legion-t5,
rem -Preflight, -SourceIso "D:\My ISOs\Win11_English_x64.iso".
rem Loads the scripts as scriptblocks so they run even where a policy blocks .ps1 files.
rem Around the build (not with -Preflight, which asks and changes nothing), scripts\Invoke-KitLauncher.ps1
rem asks, each question only when it applies:
rem  - "Update the kit to its newest signed release first? [y/N]", and a question when the update pins are very old;
rem  - the build tools (Git, Python, Windows ADK Deployment Tools): "Install them now? [Y/n]";
rem  - the downloads the work folder lacks (this month's updates, Microsoft's security baselines,
rem    the Git/Python installers): "Download ... now? [Y/n]";
rem  - a hardware profile, when none fits this PC: "Make one now from this PC? [Y/n]";
rem  - this PC's drivers, when none are collected: "Collect this PC's drivers now? ... [Y/n]";
rem  - after the build: "Test this ISO in a virtual machine now (about 30 minutes)? [Y/n]".
rem Silent when everything is there. Build-Iso.ps1 itself never asks. The image never has the tools.
rem -ThisPcLocale: this PC's keyboard, formats, time zone and home location are read as the account
rem that started this file (before the elevation) and fill the settings your file leaves out.
setlocal
rem Started from PowerShell 7, PSModulePath lists its modules first, and Windows PowerShell 5.1
rem then can't find Get-FileHash and other cmdlets of its own: 5.1 takes its default path instead
set "PSModulePath="
rem The arguments travel in environment variables (scripts\Invoke-KitLauncher.ps1), so quoted
rem paths with spaces or apostrophes survive the elevation intact.
set "W11KIT_ROOT=%~dp0"
set "W11KIT_SELF=%~f0"
set "W11KIT_ARGS=%*"
rem Elevated? fltmc needs admin rights and no service (net session needs the Server service, which the image disables)
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Elevate -ThisPcLocale"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Script 'scripts\Build-Iso.ps1' -BuildSteps -ThisPcLocale"
set rc=%errorlevel%
pause
exit /b %rc%
