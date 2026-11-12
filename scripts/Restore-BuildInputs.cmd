@echo off
rem Restores the build inputs from this USB stick onto the PC (elevated): the kit as a Git
rem clone in C:\W11Kit, everything else in C:\W11Kit\work.
rem Another folder: give it as the one argument, e.g.  Restore-BuildInputs.cmd D:\W11Kit
rem Loads the script as a scriptblock so it runs even where a policy blocks .ps1 files.
setlocal
rem The paths travel in environment variables, never pasted into a PowerShell command line
rem (a blank or an apostrophe in one would break it).
set "W11KIT_SELF=%~f0"
set "W11KIT_BI=%~dp0."
set "W11KIT_RESTORE_TO=%~1"
rem Elevated? fltmc needs admin rights and no service (net session needs the Server service, which the image disables)
fltmc >nul 2>&1
if errorlevel 1 goto elevate
powershell -NoProfile -ExecutionPolicy Bypass -Command "$a = @{ Root = $env:W11KIT_BI }; if ($env:W11KIT_RESTORE_TO) { $a.KitRoot = $env:W11KIT_RESTORE_TO }; & ([scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $env:W11KIT_BI 'Restore-BuildInputs.ps1')))) @a"
pause
exit /b
:elevate
powershell -NoProfile -Command "$a = @{ FilePath = $env:W11KIT_SELF; Verb = 'RunAs' }; if ($env:W11KIT_RESTORE_TO) { $a.ArgumentList = [char]34 + $env:W11KIT_RESTORE_TO + [char]34 }; Start-Process @a"
exit /b
