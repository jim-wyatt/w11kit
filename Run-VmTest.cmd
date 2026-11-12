@echo off
rem Elevated launcher for scripts\Test-IsoInHyperV.ps1 (Hyper-V test install of the built ISO;
rem needs Hyper-V on this PC: Run-Prepare.cmd). Ends with RESULT: PASS / FAIL (exit code 0 / 1).
rem Options pass through, e.g. -KeepVm or -IsoPath "D:\My ISOs\Win11Pro-....iso".
rem Loads the script as a scriptblock so it runs even where a policy blocks .ps1 files
rem (so $PSScriptRoot is empty: the kit folder is passed as -KitRoot).
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Invoke-KitLauncher.ps1'))) -Script 'scripts\Test-IsoInHyperV.ps1'"
set RC=%errorlevel%
pause
exit /b %RC%
