@echo off
rem Collects what a bug report needs into one zip on your Desktop, with the computer name,
rem account names, serial numbers, MAC, e-mail and IP addresses and SIDs replaced. No administrator rights,
rem no changes. It never reads the passwords files or an answer file. Look inside the zip
rem before you attach it. What it collects: the comment at the top of
rem scripts\Get-KitDiagnostics.ps1.
setlocal
rem Started from PowerShell 7, PSModulePath lists its modules first, and Windows PowerShell 5.1
rem then can't find Get-FileHash and other cmdlets of its own: 5.1 takes its default path instead
set "PSModulePath="
set "W11KIT_ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText($env:W11KIT_ROOT + 'scripts\Get-KitDiagnostics.ps1'))) -KitRoot $env:W11KIT_ROOT"
set RC=%errorlevel%
pause
exit /b %RC%
