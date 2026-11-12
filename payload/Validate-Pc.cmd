@echo off
rem Self-elevating launcher for Test-InstalledPc.ps1 (writes W11Kit-Validation.md + .json to the Public desktop and C:\ProgramData\W11Kit)
rem Options pass through: -All prints every row as one table (default: what needs attention, then counts per group).
rem Not elevated: re-launch elevated
setlocal
set "W11KIT_SELF=%~f0"
set "W11KIT_ARGS=%*"
rem Elevated? fltmc needs admin rights and no service (net session needs the Server service, which the image disables)
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "if ($env:W11KIT_ARGS) { Start-Process -Verb RunAs -FilePath $env:W11KIT_SELF -ArgumentList $env:W11KIT_ARGS } else { Start-Process -Verb RunAs -FilePath $env:W11KIT_SELF }"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-InstalledPc.ps1" %*
pause
