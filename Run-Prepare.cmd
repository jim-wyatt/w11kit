@echo off
rem Elevated launcher for scripts\Prepare-BuildPc.ps1: readies this PC to build the ISO (checks,
rem then offers to install the build tools and Hyper-V; the image itself never has them).
rem Everything the kit downloads or makes is in ONE folder, work\ next to this file.
rem Options pass through, e.g. -Check, -Yes or -SkipHyperV.
rem Loads the script as a scriptblock so it runs even where a policy blocks .ps1 files.
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
    powershell -NoProfile -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Elevate"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Script 'scripts\Prepare-BuildPc.ps1'"
set rc=%errorlevel%
pause
exit /b %rc%
