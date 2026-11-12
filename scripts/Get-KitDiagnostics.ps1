<#
.SYNOPSIS
    Collects what a bug report needs into one zip on your Desktop, with personal data replaced.

.DESCRIPTION
    Started by Collect-Diagnostics.cmd. Needs no administrator rights and changes nothing.

    Collected (text only): the kit's revision and changed files, this PC's Windows version, your
    settings file, the end of the newest build log, the newest image checks (verify-*.txt), the
    VM test's transcript and status, and the FAIL / WARN rows of the validation reports it finds.

    Replaced in every line: the computer name, the names of this PC's accounts and the account
    names in your settings, MAC addresses, account identifiers (SIDs), e-mail addresses, IP
    addresses (IPv4 and IPv6), and the serial numbers of the PC, its board and its disks. In the
    settings file also: the expected apps (reminders.expectedApps, names and paths) and the local
    DNS zones (options.dns.localZones). The home location and the other settings stay: they
    explain most build problems.

    Never read: accounts.txt / test-accounts.txt (any accounts*), any autounattend or unattend
    file, product keys. A line that looks like a password or key line is dropped.

    LOOK INSIDE the zip before you attach it: no filter knows everything that is private to you.

.PARAMETER KitRoot
    The kit folder (default: the parent of this script's folder).

.PARAMETER WorkRoot
    The work folder (default: <KitRoot>\work).

.PARAMETER OutDir
    Where the zip goes (default: your Desktop).
#>
[CmdletBinding()]
param(
    [string]$KitRoot,
    [string]$WorkRoot,
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
if (-not $KitRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
$KitRoot = $KitRoot.TrimEnd('\')
if (-not $WorkRoot) { $WorkRoot = Join-Path $KitRoot 'work' }
if (-not $OutDir) { $OutDir = [Environment]::GetFolderPath('Desktop') }

# --- What to replace -----------------------------------------------------------------
$swap = New-Object System.Collections.Generic.List[object]   # leading comma keeps each pair a pair
function Add-Swap([string]$Text, [string]$With) {
    if ($Text -and $Text.Trim().Length -ge 3) { $swap.Add(@($Text.Trim(), $With)) }
}
Add-Swap $env:COMPUTERNAME '<computer>'
$n = 0
$names = @($env:USERNAME) + @(try { Get-LocalUser -ErrorAction Stop | ForEach-Object Name } catch { }) +
         @(Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
try {
    $own = Get-Content -Raw -LiteralPath (Join-Path $KitRoot 'config\settings.local.json') -ErrorAction Stop | ConvertFrom-Json
    $names += @($own.accounts.adminName, $own.accounts.userName, $own.accounts.builtinAdministratorName, $own.accounts.builtinGuestName, $own.computerName)
} catch { }
# Windows' own names stay: they say nothing about you and the logs are full of them
$keep = 'Public', 'Default', 'Default User', 'All Users', 'Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'LocalAdmin', 'LocalUser'
foreach ($name in ($names | Where-Object { $_ -and $keep -notcontains $_ } | Sort-Object -Unique | Sort-Object Length -Descending)) { $n++; Add-Swap $name "<name$n>" }
$n = 0
try {
    $serials = @((Get-CimInstance Win32_BIOS).SerialNumber, (Get-CimInstance Win32_BaseBoard).SerialNumber, (Get-CimInstance Win32_ComputerSystemProduct).UUID) +
               @(Get-CimInstance Win32_DiskDrive | ForEach-Object SerialNumber)
    foreach ($s in ($serials | Where-Object { $_ -and $_.Trim().Length -ge 6 -and $_ -notmatch '^(0+|Default string|To be filled.*|None|System Serial Number)$' } | Sort-Object -Unique)) { $n++; Add-Swap $s "<serial$n>" }
} catch { }

function Protect-Line([string]$Line) {
    # Dropped whole: anything that reads like a secret
    if ($Line -match '(?i)passw|<Value>|ProductKey|\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b|recovery (key|password)|\b\d{6}(-\d{6}){7}\b') { return '<line removed: it may hold a password or a key>' }
    foreach ($p in $swap) { $Line = [regex]::Replace($Line, '(?i)(?<![A-Za-z0-9])' + [regex]::Escape($p[0]) + '(?![A-Za-z0-9])', $p[1]) }
    $Line = [regex]::Replace($Line, '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', '<mac>')
    $Line = [regex]::Replace($Line, '\bS-1-5-21(-\d+){3,4}\b', '<sid>')
    $Line = [regex]::Replace($Line, '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b', '<e-mail>')
    # IP addresses. IPv4: four parts of 0-255 each, so version numbers (10.0.26100.9711) stay.
    # IPv6: three or more colons or a '::', and one group of 3-4 hex digits, so times stay.
    $Line = [regex]::Replace($Line, '(?<![\d.])(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?![\d.])', '<ip>')
    $Line = [regex]::Replace($Line, '(?i)(?<![0-9a-f:])(?=[0-9a-f:]*[0-9a-f]{3})(?=(?:[0-9a-f]{0,4}:){3}|[0-9a-f]*::)(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(?![0-9a-f:])', '<ip>')
    $Line
}

# --- Collect ---------------------------------------------------------------------------
$stage = Join-Path ([IO.Path]::GetTempPath()) ('w11kit-diag-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $stage
$listed = New-Object System.Collections.Generic.List[string]
function Add-Text([string]$Name, [string[]]$Lines) {
    $out = @($Lines | ForEach-Object { Protect-Line "$_" })
    [IO.File]::WriteAllLines((Join-Path $stage $Name), [string[]]$out, (New-Object Text.UTF8Encoding $false))
    $listed.Add("$Name ($($out.Count) lines)")
}
function Add-File([string]$Path, [string]$Name, [int]$Tail = 0) {
    # The files that hold passwords are never opened, whatever asks for them
    if ((Split-Path $Path -Leaf) -match '(?i)^(test-)?accounts|unattend') { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try {
        $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
        if ($Tail -and $lines.Count -gt $Tail) { $lines = @("(the last $Tail of $($lines.Count) lines)") + @($lines | Select-Object -Last $Tail) }
        Add-Text $Name $lines
    } catch { $listed.Add("$Name NOT collected: $($_.Exception.Message)") }
}
function Get-Newest([string]$Dir, [string]$Filter) {
    Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
}

$sum = New-Object System.Collections.Generic.List[string]
$sum.Add("W11Kit diagnostics, collected $(Get-Date -Format 's')")
$git = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # git writes to stderr
try {
    if ($git -and (Test-Path -LiteralPath (Join-Path $KitRoot '.git'))) {
        $sum.Add('Kit revision: ' + ((& $git -c "safe.directory=$($KitRoot -replace '\\', '/')" -C $KitRoot rev-parse --short HEAD 2>&1 | Out-String).Trim()))
        $sum.Add('Changed kit files (git status --porcelain):')
        @(& $git -c "safe.directory=$($KitRoot -replace '\\', '/')" -C $KitRoot status --porcelain 2>&1) | ForEach-Object { $sum.Add("  $_") }
    } else { $sum.Add('Kit revision: unknown (no Git here, or the kit folder is not a clone)') }
} finally { $ErrorActionPreference = $old }
try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cs = Get-CimInstance Win32_ComputerSystem
    # The registry's ProductName still says "Windows 10" on Windows 11
    $sum.Add("This PC: $((Get-CimInstance Win32_OperatingSystem).Caption) $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR), $($cs.Manufacturer) $($cs.Model), display language $((Get-UICulture).Name), PowerShell $($PSVersionTable.PSVersion)")
} catch { $sum.Add("This PC: $($_.Exception.Message)") }
$sum.Add("Profiles in the kit: $(@(Get-ChildItem (Join-Path $KitRoot 'profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ')")
$sum.Add("Work folder: $(if (Test-Path -LiteralPath $WorkRoot) { 'found' } else { 'not found (nothing built here yet, or this is the installed PC)' })")
Add-Text 'summary.txt' $sum.ToArray()

# Your settings file, with what names your own programs and network replaced: the expected apps
# (names and paths) and the local DNS zones; the rest goes through Protect-Line as every file
$setFile = Join-Path $KitRoot 'config\settings.local.json'
if (Test-Path -LiteralPath $setFile -PathType Leaf) {
    try {
        $sj = Get-Content -Raw -LiteralPath $setFile -ErrorAction Stop | ConvertFrom-Json
        if ($sj.reminders -and $sj.reminders.expectedApps) { $sj.reminders.expectedApps = "(replaced: $(@($sj.reminders.expectedApps).Count) app(s))" }
        if ($sj.options -and $sj.options.dns -and $sj.options.dns.localZones) {
            $z = 0
            foreach ($lz in @($sj.options.dns.localZones)) { $z++; if ($lz.namespace) { $lz.namespace = "(replaced: zone $z)" } }
        }
        Add-Text 'settings.local.json' (($sj | ConvertTo-Json -Depth 8) -split "`r?`n")
    } catch { $listed.Add("settings.local.json NOT collected: $($_.Exception.Message)") }
}
$logs = Join-Path $WorkRoot 'logs'
foreach ($pair in @(@('build-*.txt', 'build-log-end.txt', 400), @('verify-2*.txt', 'verify-image.txt', 0), @('verify-boot-*.txt', 'verify-boot.txt', 0))) {
    $f = Get-Newest $logs $pair[0]
    if ($f) { Add-File $f.FullName $pair[1] $pair[2] }
}
$vm = Join-Path $WorkRoot 'vmtest\results'
Add-File (Join-Path $vm 'vmtest-transcript.txt') 'vmtest-transcript.txt' 400
Add-File (Join-Path $vm 'postinstall-status.json') 'vmtest-postinstall-status.json'
Add-File (Join-Path $vm 'panther-setuperr.log') 'vmtest-setuperr.txt' 200
# Validation reports: the FAIL and WARN rows only (the rest is your PC's inventory)
$reports = @(@((Join-Path $vm 'W11Kit-Validation.json'), 'vmtest-validation-rows.txt'),
             @((Join-Path $env:PUBLIC 'Desktop\W11Kit-Validation.json'), 'this-pc-validation-rows.txt'))
foreach ($r in $reports) {
    if (-not (Test-Path -LiteralPath $r[0])) { continue }
    try {
        $v = Get-Content -Raw -LiteralPath $r[0] | ConvertFrom-Json
        $rows = @($v.rows | Where-Object { $_.result -in 'FAIL', 'WARN' } | ForEach-Object { "$($_.result) $($_.area) | $($_.check): $($_.detail)" })
        Add-Text $r[1] (@("profile $($v.profile), generated $($v.generated), $(@($v.rows).Count) rows, $($rows.Count) FAIL/WARN") + $rows)
    } catch { $listed.Add("$($r[1]) NOT collected: $($_.Exception.Message)") }
}

# --- Zip ---------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $OutDir "W11Kit-diagnostics-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "Collected into $zip" -ForegroundColor Green
$listed | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host "Replaced: the computer name, $(@($swap | Where-Object { $_[1] -like '<name*' }).Count) account name(s), $(@($swap | Where-Object { $_[1] -like '<serial*' }).Count) serial number(s), MAC addresses, SIDs, e-mail addresses, IP addresses; in your settings file also the expected apps and the local DNS zones."
Write-Host 'Never read: the passwords files (accounts*.txt) and any answer file.'
Write-Host 'LOOK INSIDE the zip before you attach it to a bug report: no filter knows everything that is private to you.' -ForegroundColor Yellow
