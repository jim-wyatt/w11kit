<#
.SYNOPSIS
    The scheduled run of the validator (settings options.scheduledValidation; PostInstall
    registers the task "W11Kit Validate PC" as SYSTEM: weekly, and at every start).
.DESCRIPTION
    Runs Test-InstalledPc.ps1 when Windows' build changed since the last report (a Windows
    Update restart) or the last report is 6 days old or older, else does nothing. The
    validator writes its report as always (C:\ProgramData\W11Kit and the Public desktop).
    A row that is FAIL now and wasn't FAIL in the report before is shown to everyone signed
    in (msg.exe): a FAIL that stays is not shown again. Log: Logs\scheduled-validation.txt.
    Exits with the validator's -ExitCode (0 no FAIL or WARN, 1 WARN only, 2 a FAIL), or 0
    when nothing was due.
#>
[CmdletBinding()]
param(
    # For tests only: another folder, another validator script, and no message
    [string]$Root = 'C:\ProgramData\W11Kit',
    [string]$Validator,
    [switch]$NoMessage
)
$ErrorActionPreference = 'Continue'
$root = $Root
if (-not $Validator) { $Validator = Join-Path $root 'Test-InstalledPc.ps1' }
$report = Join-Path $root 'W11Kit-Validation.json'
$logDir = Join-Path $root 'Logs'
$log = Join-Path $logDir 'scheduled-validation.txt'
$lines = New-Object System.Collections.Generic.List[string]
function L([string]$m) { $lines.Add("$(Get-Date -Format s) $m") }
function Save-Log { try { $null = New-Item -ItemType Directory -Force $logDir; [IO.File]::WriteAllLines($log, $lines.ToArray()) } catch { } }

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
$build = "$($cv.CurrentBuild).$($cv.UBR)"
$prev = try { [IO.File]::ReadAllText($report) | ConvertFrom-Json } catch { $null }
$age = if ($prev -and $prev.generated) { try { ((Get-Date) - [datetime]$prev.generated).TotalDays } catch { $null } } else { $null }
$why = $null
if (-not $prev) { $why = 'no earlier report' }
elseif ("$($prev.osBuild)" -ne $build) { $why = "Windows build $build (the last report saw $(if ($prev.osBuild) { $prev.osBuild } else { 'none' }))" }
elseif ($null -eq $age -or $age -ge 6) { $why = "the last report is $(if ($null -ne $age) { [int]$age } else { '?' }) days old" }
if (-not $why) { L "Not due: build $build unchanged, last report $([int]$age) day(s) old."; Save-Log; exit 0 }
L "Running the validator: $why."

$prevFail = @(if ($prev) { @($prev.rows) | Where-Object { "$($_.result)" -eq 'FAIL' } | ForEach-Object { "$($_.area): $($_.check)" } })
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Validator -ExitCode *> $null
$rc = $LASTEXITCODE
$now = try { [IO.File]::ReadAllText($report) | ConvertFrom-Json } catch { $null }
if (-not $now -or "$($now.generated)" -eq "$($prev.generated)") { L "The validator wrote no new report (exit code $rc)."; Save-Log; exit $(if ($rc) { $rc } else { 2 }) }
L "FAIL $($now.summary.fail), WARN $($now.summary.warn) (exit code $rc)."

$newFail = @(@($now.rows) | Where-Object { "$($_.result)" -eq 'FAIL' -and $prevFail -notcontains "$($_.area): $($_.check)" } | ForEach-Object { "$($_.area): $($_.check)" })
if ($newFail.Count) {
    $text = "W11Kit Validate PC: $($newFail.Count) new FAIL row(s) since the last report: $(($newFail | Select-Object -First 5) -join '; ')$(if ($newFail.Count -gt 5) { '; ...' }). The report: W11Kit-Validation.md on the desktop."
    L "New FAIL rows: $($newFail -join '; ')"
    $msg = Join-Path $env:SystemRoot 'System32\msg.exe'
    if ($NoMessage) { L 'Not shown (-NoMessage).' }
    elseif (Test-Path -LiteralPath $msg) {
        & $msg '*' '/TIME:0' $text 2>&1 | Out-Null
        L "Shown with msg.exe (exit code $LASTEXITCODE)."
    } else { L 'msg.exe is not on this PC: the new FAIL rows are only in the report.' }
}
Save-Log
exit $rc
