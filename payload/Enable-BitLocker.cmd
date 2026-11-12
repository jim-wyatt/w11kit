@echo off
rem Self-elevating launcher for Enable-BitLockerLocal.ps1
rem Not elevated: re-launch elevated, passing any options through, e.g. -ExportOnly or
rem -BackupPath "\\nas\my share\keys". The arguments travel in environment variables, so quoted
rem paths with spaces or apostrophes survive the elevation intact.
setlocal
set "W11KIT_SELF=%~f0"
set "W11KIT_ARGS=%*"
rem Elevated? fltmc needs admin rights and no service (net session needs the Server service, which the image disables)
fltmc >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "if ($env:W11KIT_ARGS) { Start-Process -Verb RunAs -FilePath $env:W11KIT_SELF -ArgumentList $env:W11KIT_ARGS } else { Start-Process -Verb RunAs -FilePath $env:W11KIT_SELF }"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enable-BitLockerLocal.ps1" %*
pause
