<#
.SYNOPSIS
    The common part of the kit's .cmd launchers (Run-Build, Run-Harvest, Run-Prepare,
    Run-VmTest, New-Profile): elevation, and the launcher's arguments passed on intact,
    including quoted paths with spaces or apostrophes.

.DESCRIPTION
    A launcher sets three environment variables and loads this file as a scriptblock
    (like every kit script: a policy may block .ps1 files, so $PSScriptRoot is empty):
      W11KIT_ROOT  the kit folder (%~dp0, with its trailing backslash)
      W11KIT_SELF  the launcher itself (%~f0)
      W11KIT_ARGS  its arguments as typed (%*)
    The environment carries them past cmd.exe and powershell.exe unchanged. (Pasted into a
    PowerShell command line, -SourceIso "C:\My ISOs\Win11.iso" would lose its quotes and
    fall apart at the space, and a path with an apostrophe would end the single-quoted
    string.)

    -Elevate     Re-launch the launcher elevated (UAC prompt) with the same arguments:
                 Windows gets the launcher's argument text unchanged, so the elevated
                 cmd.exe sees the same %*. A cancelled or timed-out prompt says so and
                 waits for Enter (a double-clicked window would otherwise just close).
    -Script      Run that kit script (path relative to the kit) with -KitRoot and the
                 launcher's arguments. They are split as cmd.exe shows them (blanks
                 separate, double quotes group and are removed); every value is passed
                 as a literal string, nothing in it is expanded. -Name, -Name:$true and
                 -Name:$false stay parameter names; -Name:value passes value to -Name.
    -ThisPcLocale  Run-Build.cmd only: this PC's keyboard, formats, system locale, time
                 zone and home location are read as the account that runs this file and
                 handed to the script as -ThisPcLocale <text> (Base64 of a small JSON
                 object). With -Elevate that is the account that started the launcher,
                 before the elevation: the elevated build may run as another account (a
                 separate administrator), whose keyboard and formats are not the daily
                 user's. An environment variable would not survive the elevation; the
                 launcher's argument text does. The build uses the values only for
                 settings the user's file leaves out, and checks them like file values.
    -BuildSteps  Run-Build.cmd only: the questions around the build (Build-Iso.ps1
                 itself never asks). Not with -Preflight, which asks and changes nothing.
                 Each question comes only when it applies, at most once, in this order:
                 0. A short notice (what the ISO does, whose licence terms apply).
                 1. "Update the kit to its newest signed release first? [y/N]" when the kit
                    is a Git clone: only to a release signed by a key in the kit's own
                    config\release-signers (scripts\KitUpdate.ps1); after an update the
                    launcher stops, to be started again
                    (the build makes the kit folder writable by administrators only, so
                    a pull needs an administrator: this one is elevated; Git itself
                    refuses a clone that isn't locked yet).
                 2. "Build with these old updates anyway? [y/N]" when the update pins in
                    config\updates.json are more than 70 days old (no: nothing is built).
                 3. The build tools (Prepare-BuildPc.ps1 -ForBuild: "Install them now?
                    [Y/n]" if Git, Python or the ADK is missing).
                 4. The downloads the work folder lacks, in one question: this month's
                    updates (config\updates.json), Microsoft's security baseline zips
                    (config\baselines\<id>\source.json; scripts\Get-Baselines.py also
                    imports them) and, for a build that carries its build inputs (not
                    -TestBuild / -NoBuildInputs), the build-tool installers
                    (config\installers.json). Judged by exit code.
                 5. The hardware profile, when none was given with -Profile and none
                    fits this PC by itself: "Make one now from this PC? [Y/n]"
                    (scripts\New-HardwareProfile.ps1), or, when there are profiles that
                    are only used by choice (no match, or your own for another PC
                    model), a numbered list to pick from. The build then gets
                    -Profile <id>. Not on a virtual machine.
                 6. The drivers, when <work>\DriverExport\_Curated has none: "Collect
                    this PC's drivers now? (Only if this is the PC you will reinstall.)
                    [Y/n]" (scripts\Invoke-DriverHarvest.ps1). Not asked for a profile
                    of another PC model.
                 A "no" or a failed step goes on to the build, whose pre-flight reports
                 what is missing. Questions 5 and 6 are skipped (as "no") when nobody
                 can answer (no interactive console).
                 After a build that succeeded: a line to keep the ISO private, then,
                 when Hyper-V is enabled, "Test this ISO in a virtual machine now (about
                 30 minutes)? [Y/n]" (scripts\Test-IsoInHyperV.ps1 -IsoPath <the ISO>;
                 a failed test makes the exit code 1), else one line on how to get
                 Hyper-V. The ISO is the one the build's log names in its "ISO:" line.
#>
[CmdletBinding()]
param(
    [switch]$Elevate,
    [string]$Script,
    [switch]$BuildSteps,
    [switch]$ThisPcLocale
)

$kitRoot = "$env:W11KIT_ROOT"
if (-not $kitRoot) { throw 'W11KIT_ROOT is not set: start the kit through its .cmd launchers (Run-Build.cmd, ...).' }
if (-not $kitRoot.EndsWith('\')) { $kitRoot += '\' }
# -KitRoot for the scripts: no trailing backslash (C:\W11Kit); a drive root stays one (D:\.)
$kitRootArg = if ($kitRoot -match '^[A-Za-z]:\\$') { $kitRoot + '.' } else { $kitRoot.TrimEnd('\') }
$rawArgs = "$env:W11KIT_ARGS"
$self = "$env:W11KIT_SELF"

# Arguments as cmd.exe shows them: blanks separate, double quotes group and are removed.
function Split-LauncherArgs([string]$Line) {
    $out = New-Object System.Collections.Generic.List[string]
    $cur = New-Object System.Text.StringBuilder
    $inQuotes = $false; $has = $false
    foreach ($c in $Line.ToCharArray()) {
        if ($c -eq [char]'"') { $inQuotes = -not $inQuotes; $has = $true; continue }
        if (-not $inQuotes -and ($c -eq [char]' ' -or $c -eq [char]"`t")) {
            if ($has) { $out.Add($cur.ToString()); [void]$cur.Clear(); $has = $false }
            continue
        }
        [void]$cur.Append($c); $has = $true
    }
    if ($has) { $out.Add($cur.ToString()) }
    , $out.ToArray()
}

# One argument as PowerShell source: a parameter name stays one; anything else becomes a
# single-quoted literal. PowerShell also ends single-quoted strings at the typographic
# quotes U+2018-U+201B (e.g. O’Brien), so those are doubled too.
function ConvertTo-PsLiteral([string]$Value) { "'" + ($Value -replace "['\u2018\u2019\u201A\u201B]", '$0$0') + "'" }
# One argument for a native command line (Start-Process): quoted if it has blanks.
# (Backslashes before the closing quote are doubled, so "D:\x\" doesn't escape it.)
function ConvertTo-CmdArg([string]$Value) {
    if ($Value -notmatch '[\s"]' -and $Value) { return $Value }
    '"' + (($Value -replace '"', '\"') -replace '(\\+)$', '$1$1') + '"'
}
function ConvertTo-PsArgument([string]$Token) {
    if ($Token -match '^-[A-Za-z][A-Za-z0-9_]*$') { return $Token }
    if ($Token -match '^(-[A-Za-z][A-Za-z0-9_]*):(.*)$') {
        $name = $Matches[1]; $value = $Matches[2]
        if ($value -match '^\$(true|false)$') { return "${name}:$value" }
        return "${name}:$(ConvertTo-PsLiteral $value)"
    }
    ConvertTo-PsLiteral $Token
}

$tokens = Split-LauncherArgs $rawArgs
# The value of -Name in the arguments ($null if absent); a switch gives $true.
function Get-LauncherArg([string]$Name, [switch]$Switch) {
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -ieq "-$Name") {
            if ($Switch) { return $true }
            if ($i + 1 -lt $tokens.Count) { return $tokens[$i + 1] }
            return $null
        }
        if ($t -like "-${Name}:*") {
            $v = $t.Substring($Name.Length + 2)
            if ($Switch) { return $v -ne '$false' }
            return $v
        }
    }
    $null
}

# --- This PC's keyboard, formats, time zone and home location (-ThisPcLocale) ------------
# Read as the account running this file; what can't be read is left out (the build then
# uses the kit's default for it and says so). Returns Base64 text: no blanks or quotes, so
# it passes through cmd.exe and the elevation unchanged.
function Get-ThisPcLocaleText {
    $o = [ordered]@{}
    try { $o.timeZone = [TimeZoneInfo]::Local.Id } catch { }
    try { $o.systemLocale = (Get-WinSystemLocale -ErrorAction Stop).Name } catch { }
    try { $o.userLocale = (Get-Culture).Name } catch { }
    try {
        # Keyboards and input methods of the account's languages, the default one first
        $tips = New-Object System.Collections.Generic.List[string]
        $first = try { "$((Get-WinDefaultInputMethodOverride -ErrorAction Stop).InputMethodTip)" } catch { '' }
        if ($first) { $tips.Add($first) }
        foreach ($l in @(Get-WinUserLanguageList -ErrorAction Stop)) { foreach ($tip in @($l.InputMethodTips)) { if ($tip -and -not $tips.Contains("$tip")) { $tips.Add("$tip") } } }
        if ($tips.Count) { $o.inputLocale = $tips.ToArray() -join ';' }
    } catch { }
    try {
        # Home location: the GeoId and its two-letter country code, as Windows stores them for the account
        $g = Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\International\Geo' -ErrorAction Stop
        if ("$($g.Nation)" -match '^\d{1,9}$' -and $g.Name) { $o.geoId = [int]$g.Nation; $o.isoCode = "$($g.Name)".ToUpperInvariant() }
    } catch { }
    $o.account = "$env:USERDOMAIN\$env:USERNAME"
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Compress)))
}
$hasThisPc = $null -ne (Get-LauncherArg 'ThisPcLocale')

# --- Elevation -------------------------------------------------------------------------
if ($Elevate) {
    # Before the elevation: the values of the account that started the launcher
    if ($ThisPcLocale -and -not $hasThisPc) { $rawArgs = ("$rawArgs".TrimEnd() + ' -ThisPcLocale ' + (Get-ThisPcLocaleText)).Trim() }
    $p = @{ FilePath = $self; Verb = 'RunAs'; ErrorAction = 'Stop' }
    if ($rawArgs.Trim()) { $p.ArgumentList = $rawArgs }
    try { Start-Process @p }
    catch {
        Write-Host "$(Split-Path -Leaf $self) did not start: the Windows UAC prompt was cancelled or timed out (it closes itself after about 2 minutes)." -ForegroundColor Yellow
        Write-Host 'Run it again and click Yes on the prompt (with your administrator password if it asks).' -ForegroundColor Yellow
        Write-Host "($($_.Exception.Message))"
        $null = Read-Host 'Press Enter to close'
        exit 1
    }
    return
}

if (-not $Script) { throw 'Invoke-KitLauncher: give -Elevate or -Script <kit-relative path>.' }
# Started from a console that is already elevated: there was no "before the elevation", so
# the values are this account's.
if ($ThisPcLocale -and -not $hasThisPc) { $tokens = @($tokens) + @('-ThisPcLocale', (Get-ThisPcLocaleText)) }

# Run a kit script in a child Windows PowerShell on this console (it may 'exit', which here
# would end this process too). Returns its exit code.
function Invoke-KitChild([string]$RelPath, [string]$ArgText) {
    $code = "& ([scriptblock]::Create([IO.File]::ReadAllText($(ConvertTo-PsLiteral (Join-Path $kitRoot $RelPath))))) -KitRoot $(ConvertTo-PsLiteral $kitRootArg) $ArgText"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $proc = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc -NoNewWindow -Wait -PassThru
    $null = $proc.Handle
    $proc.ExitCode
}

# --- Run-Build.cmd: the questions before the build (kit update, tools, downloads, profile,
# drivers). Variables stay inside this function: the kit script runs in a child scope of
# this file and would otherwise see them.
function Invoke-BuildSteps {
    Write-Host ''
    Write-Host 'W11Kit - builds a Windows 11 Pro install ISO for YOUR OWN PC.          (beta, MIT License, NO WARRANTY)' -ForegroundColor Cyan
    Write-Host '  * Installing the ISO ERASES the disk you choose and applies a strict security configuration.'
    Write-Host '  * You need your own Windows 11 Pro licence. The install is unattended: by building and installing'
    Write-Host '    you accept Microsoft''s licence terms for Windows and for the tools this build installs.'
    Write-Host '  * The ISO holds Windows, your drivers and your one-time passwords: never share or upload it.'
    Write-Host '  * Independent project: not affiliated with or endorsed by Microsoft or DISA; not a compliance product.'
    Write-Host ''
    # Questions that start something on this PC (a profile, the harvest, the VM test) are
    # asked only when somebody can answer; otherwise they count as "no".
    $canAsk = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    $workRoot = Get-LauncherArg 'WorkRoot'
    if (-not $workRoot) { $workRoot = Join-Path $kitRootArg 'work' }   # the same default as Build-Iso.ps1
    $updatesRoot = Join-Path $workRoot 'updates'
    $installersDir = Join-Path $workRoot 'installers'
    $baselinesDir = Join-Path $workRoot 'baselines'
    # The work folder, if this creates it: writable by administrators only from the start
    # (the build locks it anyway; scripts\KitAcl.ps1)
    if (-not (Test-Path -LiteralPath $workRoot)) {
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot 'scripts\KitAcl.ps1'))))
        New-KitLockedFolder $workRoot
    }

    # 0. The kit: after the first build only administrators can change it, so offer the update
    #    here (elevated): to the newest release signed by a key this kit already trusts
    #    (scripts\KitUpdate.ps1). No safe.directory: Git refuses a clone another user owns,
    #    which is what a kit not locked yet is.
    $gitExe = @((Get-Command git.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\Git\cmd\git.exe") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($gitExe -and (Test-Path -LiteralPath (Join-Path $kitRoot '.git'))) {
        if ((Read-Host 'Update the kit to its newest signed release first? [y/N]') -match '^\s*y') {
            . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot 'scripts\KitUpdate.ps1'))))
            $u = Update-KitToSignedRelease -KitRoot $kitRootArg -GitExe $gitExe
            Write-Host $u.Message -ForegroundColor $(if ($u.Result -in 'Updated', 'Current') { 'Green' } else { 'Yellow' })
            if ($u.Result -eq 'Updated') {
                Write-Host 'The new release takes effect when this launcher starts again: run Run-Build.cmd once more.' -ForegroundColor Yellow
                $launch.Stop = $true
                return
            } elseif ($u.Result -ne 'Current') { Write-Host 'Continuing with the kit as it is.' -ForegroundColor Yellow }
        }
    }
    # 0b. Update pins that are more than 70 days old ('pinned' in config\updates.json, the
    #     day they were last moved): ask before building an image that starts out that far
    #     behind. (From 35 days the build's pre-flight notes it; Build-Iso.ps1 never asks.)
    try {
        $pinned = "$(([IO.File]::ReadAllText((Join-Path $kitRoot 'config\updates.json')) | ConvertFrom-Json).pinned)"
        $pinAge = [int]((Get-Date).Date - [datetime]::ParseExact($pinned, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).TotalDays
        if ($pinAge -gt 70) {
            Write-Host ''
            Write-Host "The update pins of this kit (config\updates.json) are $pinAge days old (pinned $pinned)." -ForegroundColor Yellow
            Write-Host 'Microsoft has released newer Windows updates since: an image built now starts out that far behind.' -ForegroundColor Yellow
            Write-Host 'Newer pins: update the kit (run Run-Build.cmd again and answer y to the first question), or move' -ForegroundColor Yellow
            Write-Host 'them yourself in an administrator terminal:  py scripts\Get-Updates.py --discover --write' -ForegroundColor Yellow
            if ((Read-Host 'Build with these old updates anyway? [y/N]') -notmatch '^\s*y') {
                Write-Host 'Stopped: nothing was built.' -ForegroundColor Yellow
                $launch.Stop = $true
                return
            }
        }
    } catch { }   # no readable 'pinned' date: the build's pre-flight says so
    $withInputs = -not (Get-LauncherArg 'TestBuild' -Switch) -and -not (Get-LauncherArg 'NoBuildInputs' -Switch)

    # 1. Build tools (asks "Install them now? [Y/n]" only when one is missing; silent otherwise)
    $null = Invoke-KitChild 'scripts\Prepare-BuildPc.ps1' "-ForBuild -WorkRoot $(ConvertTo-PsLiteral $workRoot)"
    # Tools installed just now: this process still has the PATH from before
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

    # 2. Updates: every KB in config\updates.json has its file, and nothing else is in those
    #    folders (the build applies every package there). Installers: present with their SHA-256.
    $missing = New-Object System.Collections.Generic.List[string]
    try {
        $ucfg = [IO.File]::ReadAllText((Join-Path $kitRoot 'config\updates.json')) | ConvertFrom-Json
        foreach ($folder in $ucfg.updates.PSObject.Properties) {
            $kbs = @($folder.Value | Where-Object { $_ })
            $files = @(Get-ChildItem -LiteralPath (Join-Path $updatesRoot $folder.Name) -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.msu', '.cab' })
            foreach ($kb in $kbs) {
                if (-not @($files | Where-Object { $_.Name -match [regex]::Escape($kb) }).Count) { $missing.Add("$($folder.Name)\$kb") }
            }
            foreach ($f in $files) {
                if (-not @($kbs | Where-Object { $f.Name -match [regex]::Escape($_) }).Count) { $missing.Add("$($folder.Name)\$($f.Name) (not a configured KB: the download removes it)") }
            }
        }
    } catch { Write-Host "  [NOTE] config\updates.json not readable ($($_.Exception.Message)): the updates are not checked here." -ForegroundColor Yellow }
    $missingInst = New-Object System.Collections.Generic.List[string]
    if ($withInputs) {
        try {
            foreach ($i in @(([IO.File]::ReadAllText((Join-Path $kitRoot 'config\installers.json')) | ConvertFrom-Json).installers)) {
                $f = Join-Path $installersDir $i.file
                if (-not (Test-Path -LiteralPath $f) -or (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne "$($i.sha256)".ToUpperInvariant()) { $missingInst.Add($i.file) }
            }
        } catch { Write-Host "  [NOTE] config\installers.json not readable ($($_.Exception.Message)): the installers are not checked here." -ForegroundColor Yellow }
    }
    # Microsoft's security baselines: each zip config\baselines pins is in the work folder
    # with the pinned SHA-256 (the build imports them itself; the download script does too)
    $missingBl = New-Object System.Collections.Generic.List[string]
    try {
        $blPins = Join-Path $kitRoot 'config\baselines'
        foreach ($id in @(([IO.File]::ReadAllText((Join-Path $blPins 'baselines.json')) | ConvertFrom-Json).apply | Where-Object { $_ })) {
            $pin = [IO.File]::ReadAllText((Join-Path $blPins "$id\source.json")) | ConvertFrom-Json
            $f = Join-Path $baselinesDir "$($pin.file)"
            if (-not (Test-Path -LiteralPath $f -PathType Leaf) -or (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne "$($pin.sha256)".ToUpperInvariant()) { $missingBl.Add("$($pin.file)") }
        }
    } catch { Write-Host "  [NOTE] config\baselines not readable ($($_.Exception.Message)): the security baselines are not checked here." -ForegroundColor Yellow }
    if ($missing.Count -or $missingBl.Count -or $missingInst.Count) {
        Write-Host ''
        if ($missing.Count) { Write-Host "This month's Windows updates are not (all) in ${updatesRoot}: $($missing -join ', ')." -ForegroundColor Yellow }
        if ($missingBl.Count) { Write-Host "Microsoft's security baselines are not (all) in ${baselinesDir}: $($missingBl -join ', ')." -ForegroundColor Yellow }
        if ($missingInst.Count) { Write-Host "The build-tool installers the ISO carries are not (all) in ${installersDir}: $($missingInst -join ', ')." -ForegroundColor Yellow }
        # One question for everything that is missing
        $wanted = @(if ($missing.Count) { , @("this month's Windows updates", '~5 GB') }
                    if ($missingBl.Count) { , @("Microsoft's security baselines", '~2 MB') }
                    if ($missingInst.Count) { , @('the Git and Python installers', '~100 MB') })
        $question = if ($wanted.Count -eq 1) { "Download $($wanted[0][0]) now ($($wanted[0][1]))? [Y/n]" }
                    else {
                        $items = @($wanted | ForEach-Object { "$($_[0]) ($($_[1]))" })
                        "Download $(($items[0..($items.Count - 2)]) -join ', ') and $($items[-1]) now? [Y/n]"
                    }
        $answer = Read-Host $question
        if ($answer -match '^\s*n') {
            Write-Host 'Not downloaded. Continuing: the build''s pre-flight says what it still needs.' -ForegroundColor Yellow
        } else {
            $pyTool = $null
            try {
                $its = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot 'scripts\Install-BuildTools.ps1')))
                $pyTool = @(& $its -KitRoot $kitRootArg -WorkRoot $workRoot -Tools python -Check -PassThru) | Where-Object { $_.State -eq 'OK' } | Select-Object -First 1
            } catch { }
            if (-not $pyTool -or -not $pyTool.Path) {
                Write-Host 'Python 3 is not installed, so nothing can be downloaded: run Run-Prepare.cmd (it installs it), then Run-Build.cmd again. Continuing: the build''s pre-flight says what is missing.' -ForegroundColor Yellow
            } else {
                $pyArgs = @(if ((Split-Path -Leaf $pyTool.Path) -ieq 'py.exe') { '-3' })
                $jobs = @()
                if ($missing.Count) { $jobs += , @('Get-Updates.py', $updatesRoot) }
                if ($missingBl.Count) { $jobs += , @('Get-Baselines.py', $baselinesDir) }
                if ($missingInst.Count) { $jobs += , @('Get-Installers.py', $installersDir) }
                foreach ($j in $jobs) {
                    Write-Host ''
                    Write-Host "==> scripts\$($j[0]) --dest $($j[1])" -ForegroundColor Cyan
                    # On this console (Python's progress unbuffered), judged by its exit code
                    $py = Start-Process -FilePath $pyTool.Path -ArgumentList ($pyArgs + @((ConvertTo-CmdArg (Join-Path $kitRoot "scripts\$($j[0])")), '--dest', (ConvertTo-CmdArg $j[1]))) -NoNewWindow -Wait -PassThru
                    $null = $py.Handle
                    if ($py.ExitCode -ne 0) {
                        Write-Host "scripts\$($j[0]) failed (exit code $($py.ExitCode)). Microsoft's servers sometimes don't answer: run Run-Build.cmd again in a few minutes (files already downloaded are kept). Continuing: the pre-flight says what is missing." -ForegroundColor Yellow
                    }
                }
            }
        }
        Write-Host ''
    }

    # 3. Hardware profile. Given with -Profile: nothing to ask. Otherwise the build takes the
    #    profile whose match fits this PC, else 'generic' (scripts\KitProfile.ps1). When it
    #    would be 'generic': offer to make a profile from this PC, or to pick one of the
    #    profiles that are never taken by themselves. The choice goes to the build (and the
    #    harvest) as -Profile <id>.
    $profileId = Get-LauncherArg 'Profile'
    if (-not $profileId) { $profileId = Get-LauncherArg 'HardwareProfile' }
    $resolved = $null
    try {
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot 'scripts\KitProfile.ps1'))))
        $resolved = Resolve-KitProfile -KitRoot $kitRootArg -Id $profileId
    } catch { }   # unknown or invalid profile: the build's pre-flight says so
    $useId = if ($resolved) { "$($resolved.Profile.id)" } else { '' }
    $fitsPc = if ($resolved) { $resolved.FitsPc } else { $null }   # $false: made for another PC model
    $thisPc = if ($resolved) { "$($resolved.PcManufacturer) $($resolved.PcModel)".Trim() } else { '' }
    # A virtual machine gets no profile of its own
    $isVm = $thisPc -match 'Virtual Machine|VMware|VirtualBox|KVM|QEMU|Standard PC|HVM domU|Parallels|Bochs'
    if ($resolved -and -not $profileId -and $useId -eq 'generic' -and $canAsk) {
        $profilesDir = Join-Path $kitRootArg 'profiles'
        $listIds = { @(Get-ChildItem -LiteralPath $profilesDir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'profile.json') } | ForEach-Object Name) }
        # Runs New-HardwareProfile.ps1 (it only reads this PC and writes the one file);
        # returns the new profile's id, or nothing when none was written.
        $makeProfile = {
            $before = @(& $listIds)
            Write-Host ''
            Write-Host '==> scripts\New-HardwareProfile.ps1' -ForegroundColor Cyan
            $rc = Invoke-KitChild 'scripts\New-HardwareProfile.ps1' '-NoNextSteps'
            $new = @(& $listIds | Where-Object { $before -notcontains $_ })
            if ($rc -eq 0 -and $new.Count -eq 1) {
                Write-Host "Building with the new profile '$($new[0])'. To review it later: $(Join-Path $profilesDir "$($new[0])\profile.json") (docs\reference\PROFILES.md)." -ForegroundColor Green
                $new[0]
            } else {
                Write-Host "No profile was made (see above). Continuing with the 'generic' profile." -ForegroundColor Yellow
            }
        }
        # Profiles of your own in a Git clone: untracked or changed ones. (No safe.directory:
        # Git refuses a clone another account owns, as for the pull above; then only the
        # profiles without a match are listed.)
        $own = @{}
        if ($gitExe -and (Test-Path -LiteralPath (Join-Path $kitRoot '.git'))) {
            $st = ''
            try { $st = "$(& $gitExe -C $kitRootArg status --porcelain -z --untracked-files=all -- profiles 2>$null)" } catch { }
            foreach ($e in ($st -split "`0")) { if ($e.Length -gt 3 -and $e.Substring(3) -match '^profiles/([^/]+)/profile\.json$') { $own[$Matches[1]] = $true } }
        }
        # Never taken by themselves: a profile without a match (a PC whose maker left the
        # model name empty gets one), and your own profile for another PC model.
        $cands = New-Object System.Collections.Generic.List[object]
        foreach ($id in @(& $listIds | Sort-Object)) {
            if ($id -eq 'generic') { continue }
            try { $cand = [IO.File]::ReadAllText((Join-Path $profilesDir "$id\profile.json")) | ConvertFrom-Json } catch { continue }
            $hasMatch = $null -ne $cand.match
            if ($hasMatch -and -not $own.ContainsKey($id)) { continue }   # a profile the kit ships, for another PC model
            $problems = @(Test-KitProfile $cand $id)
            if ($problems.Count) { Write-Host "  [NOTE] profiles\$id\profile.json is not valid and is not offered: $($problems[0])" -ForegroundColor Yellow; continue }
            $cands.Add([pscustomobject]@{ Id = $id; Name = "$($cand.displayName)"; HasMatch = $hasMatch })
        }
        Write-Host ''
        if ($cands.Count) {
            Write-Host "No hardware profile fits this PC by itself ($thisPc). These are used only when you choose them:" -ForegroundColor Yellow
            $n = 0
            foreach ($c in $cands) { $n++; Write-Host ("  {0}. {1}  ({2}; {3})" -f $n, $c.Id, $c.Name, $(if ($c.HasMatch) { 'your own, made for another PC model' } else { 'no match: never picked by itself' })) }
            Write-Host "  G. generic  (any PC: every third-party driver, no device checks)"
            if (-not $isVm) { Write-Host '  N. make a new profile from this PC now' }
            $default = if ($cands.Count -eq 1) { '1' } else { 'G' }
            $question = "Build with which profile? Type its number, G$(if (-not $isVm) { ' or N' }) [$default]"
            $choice = $null
            while ($null -eq $choice) {
                $a = "$(Read-Host $question)".Trim()
                if (-not $a) { $a = $default }
                if ($a -match '^\d+$' -and [int]$a -ge 1 -and [int]$a -le $cands.Count) { $choice = $cands[[int]$a - 1] }
                elseif ($a -match '^g') { $choice = 'generic' }
                elseif ($a -match '^n' -and -not $isVm) { $choice = 'new' }
                else { Write-Host "  '$a' is not one of the choices." -ForegroundColor Yellow }
            }
            if ($choice -is [string]) {
                if ($choice -eq 'new') { $made = & $makeProfile; if ($made) { $useId = "$made"; $fitsPc = $true; $launch.ProfileId = $useId } }
            } else {
                $useId = $choice.Id; $launch.ProfileId = $useId
                if ($choice.HasMatch) { $fitsPc = $false }
            }
        } elseif (-not $isVm) {
            Write-Host "This kit has no hardware profile that fits this PC ($thisPc)." -ForegroundColor Yellow
            Write-Host 'A profile says which makers'' drivers the image carries and which devices are checked after the install.'
            Write-Host 'Answer n if you build for another PC, or want the ''generic'' profile (any PC: every third-party driver,'
            Write-Host 'no device checks). A profile made on another PC is used with -Profile <id>.'
            if ((Read-Host 'No hardware profile for this PC yet. Make one now from this PC? [Y/n]') -notmatch '^\s*n') {
                $made = & $makeProfile
                if ($made) { $useId = "$made"; $fitsPc = $true; $launch.ProfileId = $useId }
            } else {
                Write-Host "No profile made. Continuing with the 'generic' profile." -ForegroundColor Yellow
            }
        }
    }

    # 4. Drivers: the build adds the ones in <work>\DriverExport\_Curated (the harvest of the
    #    PC the image is for). None there: offer the harvest of this PC, for the profile above.
    $curated = Join-Path $workRoot 'DriverExport\_Curated'
    $hasDrivers = [bool]@(Get-ChildItem -LiteralPath $curated -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.inf' } | Select-Object -First 1).Count
    if (-not $hasDrivers -and $resolved -and $canAsk) {
        Write-Host ''
        if ($fitsPc -eq $false) {
            Write-Host "No drivers are collected yet (nothing in $curated), and profile '$useId' is for another PC model than this one ($thisPc)." -ForegroundColor Yellow
            Write-Host "Collect them on that PC (Run-Harvest.cmd -Profile $useId there) and copy its work\DriverExport folder and work\DriverExport.zip"
            Write-Host "to $workRoot (docs\reference\BUILD-OPTIONS.md, ""Building on another PC""). Continuing: the build's pre-flight will stop at ""Curated drivers""."
        } else {
            Write-Host "This PC's drivers are not collected yet (nothing in $curated)." -ForegroundColor Yellow
            Write-Host "The image carries the drivers this PC uses now, chosen by the profile '$useId'. Collecting them takes"
            Write-Host '5-15 minutes and changes nothing on this PC.'
            if ((Read-Host 'Collect this PC''s drivers now? (Only if this is the PC you will reinstall.) [Y/n]') -notmatch '^\s*n') {
                Write-Host ''
                Write-Host '==> scripts\Invoke-DriverHarvest.ps1' -ForegroundColor Cyan
                $rc = Invoke-KitChild 'scripts\Invoke-DriverHarvest.ps1' "-WorkRoot $(ConvertTo-PsLiteral $workRoot) -Profile $(ConvertTo-PsLiteral $useId)"
                if ($rc -ne 0) { Write-Host "The driver harvest failed (exit code $rc, see above). Continuing: the build's pre-flight says what is missing." -ForegroundColor Yellow }
            } else {
                Write-Host "Not collected. The build needs the drivers of the PC you will reinstall: run Run-Harvest.cmd on that PC and copy its" -ForegroundColor Yellow
                Write-Host "work\DriverExport folder and work\DriverExport.zip to $workRoot (docs\reference\BUILD-OPTIONS.md, ""Building on another PC"")." -ForegroundColor Yellow
                Write-Host 'Continuing: the build''s pre-flight will stop at "Curated drivers".' -ForegroundColor Yellow
            }
        }
        Write-Host ''
    }
    # 6. Defender's ransomware protection: the kit's image turns it on, and it blocks the build's
    #    DISM work. Paused for the build only with a deliberate yes; the build restores it.
    $def = $null
    try {
        $mp = Get-MpPreference -ErrorAction Stop
        $ids = @($mp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() }); $pi = [array]::IndexOf($ids, '01443614-cd74-433a-b99e-2ecdc07bfc25')
        $def = @{ Cfa = [int]$mp.EnableControlledFolderAccess -eq 1; Prev = $pi -ge 0 -and [int]@($mp.AttackSurfaceReductionRules_Actions)[$pi] -eq 1 }
    } catch { }
    if ($def -and ($def.Cfa -or $def.Prev)) {
        Write-Host ''
        Write-Host "This PC runs with Defender's ransomware protection on: $((@($(if ($def.Cfa) { 'Controlled Folder Access' }), $(if ($def.Prev) { 'the ASR rule that blocks rarely seen programs' }) | Where-Object { $_ }) -join ' and '))." -ForegroundColor Yellow
        Write-Host 'Both block the tools the build uses to change the Windows image, so they must be paused while it runs'
        Write-Host '(about an hour) and are turned back on when it ends, also after an error.'
        Write-Host 'This PC is not a throwaway build machine: during that hour, a malicious program you start could change'
        Write-Host 'your documents unhindered. Close what you don''t need, start nothing new from the internet, and stay nearby.' -ForegroundColor Yellow
        if ((Read-Host 'Pause the protection for this build? [y/N]') -notmatch '^\s*y') {
            Write-Host 'Stopped: nothing was built, and the protection stays on.' -ForegroundColor Yellow
            $launch.Stop = $true
            return
        }
        $launch.PauseDefender = $true
    }

    # For the questions after the build
    $launch.WorkRoot = $workRoot
    $launch.CanAsk = $canAsk
}

# --- Run-Build.cmd: after a build that succeeded -----------------------------------------
# $After: what Invoke-BuildSteps left (work folder, when the build started).
function Invoke-AfterBuild($After) {
    $workRoot = $After.WorkRoot
    # The ISO, as the build's own log names it ("ISO:    <path>", the line the CI workflows
    # read too); it must be a finished one of this run (its .sha256 is written last).
    $iso = $null
    $log = Get-ChildItem -LiteralPath (Join-Path $workRoot 'logs') -Filter 'build-*.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $After.Started } | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($log) {
        $m = Select-String -LiteralPath $log.FullName -Pattern '^ISO:\s+(.+?)\s*$' | Select-Object -Last 1
        if ($m) { $iso = $m.Matches[0].Groups[1].Value }
    }
    if (-not $iso -or -not (Test-Path -LiteralPath $iso -PathType Leaf) -or -not (Test-Path -LiteralPath "$iso.sha256") -or (Get-Item -LiteralPath $iso).LastWriteTime -lt $After.Started) { return }
    Write-Host 'Keep this ISO private: it contains Microsoft Windows, your drivers and your one-time passwords. Do not share, upload or sell it.' -ForegroundColor Yellow
    Write-Host ''
    # Hyper-V: enabled (and Windows restarted since) = the VM test can run now
    $hv = $null
    try {
        $its = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot 'scripts\Install-BuildTools.ps1')))
        $hv = @(& $its -KitRoot $kitRootArg -WorkRoot $workRoot -Tools hyperv -Check -PassThru) | Select-Object -First 1
    } catch { }
    if ($hv -and $hv.State -eq 'OK' -and -not $hv.Restart) {
        if (-not $After.CanAsk) { return }
        Write-Host 'Before you erase a PC with it: a test installs this ISO in a virtual machine on this PC (Hyper-V), hands-off,'
        Write-Host 'and checks the result. Your ISO is not changed. Keep the PC awake while it runs.'
        if ((Read-Host 'Test this ISO in a virtual machine now (about 30 minutes)? [Y/n]') -match '^\s*n') {
            Write-Host "Not tested. To test it later: Run-VmTest.cmd (it tests the newest ISO in $workRoot)." -ForegroundColor Yellow
            return
        }
        Write-Host ''
        Write-Host '==> scripts\Test-IsoInHyperV.ps1' -ForegroundColor Cyan
        $rc = Invoke-KitChild 'scripts\Test-IsoInHyperV.ps1' "-IsoPath $(ConvertTo-PsLiteral $iso) -WorkRoot $(ConvertTo-PsLiteral $workRoot)"
        if ($rc -ne 0) { $After.ExitCode = 1 }
    } elseif ($hv -and $hv.State -eq 'OK') {
        Write-Host 'Not tested in a virtual machine yet: Hyper-V is enabled, but Windows has not been restarted since. Restart, then run Run-VmTest.cmd.' -ForegroundColor Yellow
    } elseif ($hv -and $hv.State -eq 'N/A') {
        Write-Host "Not tested in a virtual machine: Hyper-V can't run on this PC ($($hv.Detail))." -ForegroundColor Yellow
    } else {
        Write-Host 'Not tested in a virtual machine: Hyper-V is not enabled on this PC. Run-Prepare.cmd enables it (one restart); then Run-VmTest.cmd tests this ISO.' -ForegroundColor Yellow
    }
}
$launch = @{ Stop = $false }   # filled by Invoke-BuildSteps: Stop (the user stopped the build), ProfileId, WorkRoot, CanAsk
if ($BuildSteps -and -not (Get-LauncherArg 'Preflight' -Switch)) { Invoke-BuildSteps }
if ($launch.Stop) { exit 1 }
# The profile made or picked above goes to the build
if ($launch.ProfileId) { $tokens = @($tokens) + @('-Profile', "$($launch.ProfileId)") }
if ($launch.PauseDefender) { $tokens = @($tokens) + @('-PauseDefenderProtection') }

# --- The script itself ------------------------------------------------------------------
# It runs in a child scope of this file: only these two variables (unlikely names) are left
# for it to see.
$__w11kitScript = [scriptblock]::Create([IO.File]::ReadAllText((Join-Path $kitRoot $Script)))
$__w11kitRoot = $kitRootArg
$__w11kitCall = '& $__w11kitScript -KitRoot $__w11kitRoot ' + (@($tokens | ForEach-Object { ConvertTo-PsArgument $_ }) -join ' ')
# Run-Build.cmd, a real build: what the questions after it need (one more unlikely name)
$__w11kitAfter = if ($launch.WorkRoot) { @{ KitRoot = $kitRoot; WorkRoot = $launch.WorkRoot; CanAsk = [bool]$launch.CanAsk; Started = (Get-Date).AddSeconds(-2); ExitCode = 0 } } else { $null }
Remove-Variable kitRoot, kitRootArg, rawArgs, self, tokens, Elevate, Script, BuildSteps, ThisPcLocale, hasThisPc, launch -ErrorAction SilentlyContinue
& ([scriptblock]::Create($__w11kitCall))
# Reached only when the script ended without an error (a failed build throws; this file
# then ends with it)
if ($__w11kitAfter) {
    $kitRoot = $__w11kitAfter.KitRoot
    $kitRootArg = $__w11kitRoot
    Invoke-AfterBuild $__w11kitAfter
    if ($__w11kitAfter.ExitCode) { exit $__w11kitAfter.ExitCode }
}
