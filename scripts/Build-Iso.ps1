<#
.SYNOPSIS
    Builds the customized Windows 11 Pro ISO for one hardware profile
    (profiles\<id>\profile.json, docs\reference\PROFILES.md). Run elevated (Run-Build.cmd).

.DESCRIPTION
    Everything the build downloads, reads or makes is in ONE folder, the work folder
    (-WorkRoot, default <KitRoot>\work, e.g. C:\W11Kit\work; git ignores it): the
    updates, Microsoft's security baselines, the driver export, the build tools'
    installers, the logs, the passwords file and the finished ISO.

    0.  Import Microsoft's security baselines from their pinned zips in
        <WorkRoot>\baselines (scripts\Import-Baseline.py; needs Python 3)
    1.  Copy the official ISO to the work folder
    2.  Export only the Windows 11 Pro index from install.wim/esd
    3.  Integrate updates: updates\lcu (SSU ships inside the LCU), component
        cleanup without /ResetBase, then updates\dotnet (Microsoft's order)
    4.  Update WinRE (the cumulative update for its servicing stack, then
        updates\safeos) and add network/storage drivers to it
    5.  Integrate the curated drivers harvested from the running system
    6.  Remove provisioned apps listed in config\removal-manifest.json
    7.  Enable / disable the optional features in config\image.json
        (WSL + Virtual Machine Platform, no Hyper-V; Recall off)
    8.  Apply registry customizations offline (Set-KitRegistry.ps1)
    9.  Stage post-install payload (with the imported baseline data) + Start layout
    10. Commit the image (split into <4 GB .swm parts when needed)
    11. Service boot.wim (Windows PE and Windows Setup: every index gets the
        cumulative update and the curated storage drivers, so Setup sees the
        disk), then take setup.exe, setuphost.exe and the boot
        manager for the media from the serviced boot.wim (Microsoft's "Update
        Windows installation media with Dynamic Update" sequence)
    12. Write autounattend.xml, build the ISO with oscdimg, hash it

.PARAMETER Profile
    Hardware profile id (folder under profiles\). Default: the first profile whose
    match fits this PC's manufacturer/model, else 'generic'. It sets the computer
    name, the ISO name, the product key mode and what PostInstall/the validator
    do on that hardware; it is staged as C:\ProgramData\W11Kit\profile.json.
.PARAMETER Settings
    Your settings file, used instead of <KitRoot>\config\settings.local.json
    (untracked: git ignores it, so a git pull never touches it). Either one holds
    only the fields you change (every field: docs\reference\CONFIGURATION.md,
    "Your settings"): language and locales, time zone, home location, computer
    name, account names, options and the validator's reminders. It is laid over
    the kit's defaults, <KitRoot>\config\settings.defaults.json, field by field
    and checked in the pre-flight (an unknown field stops the build). The
    effective settings are staged as C:\ProgramData\W11Kit\settings.json for
    PostInstall and the validator, and the manifest records them and where each
    came from.
.PARAMETER ThisPcLocale
    Set by Run-Build.cmd, not by hand: this PC's keyboard, formats, system
    locale, time zone and home location, read before the elevation as the
    account that started it (scripts\Invoke-KitLauncher.ps1). They fill only
    the fields your settings file leaves out. Without it (Build-Iso.ps1 started
    directly, e.g. by a CI job) nothing is read from the PC: those fields take
    the kit's defaults (UTC, en-US, US keyboard) and the pre-flight notes it.
.PARAMETER ComputerName
    The computer name, instead of computerName in your settings or in the
    profile (in that order). None of them: Windows picks a random name
    (unattend '*').
.PARAMETER SourceIso
    Official ISO. Default: the newest Windows11*.iso / Win11*.iso in <WorkRoot>\source
    (where Restore-BuildInputs puts the one an ISO carries) or in any user's
    Downloads folder (C:\Users\<name>\Downloads, Public included).
.PARAMETER WorkRoot
    The work folder. Default <KitRoot>\work. Everything else follows it: updates\
    (lcu\, dotnet\, safeos\, setup\: scripts\Get-Updates.py), baselines\
    (Microsoft's security baseline zips and the data imported from them:
    scripts\Get-Baselines.py), DriverExport\
    (Run-Harvest.cmd; its _Curated folder holds the drivers the build adds),
    installers\, tools\, logs\, the mount folders, accounts.txt and the ISO.
    Its drive needs the free space.
.PARAMETER Preflight
    Check everything the build needs (ISO, drivers, updates, baseline zips,
    Python, templates, disk space, ISO tool) and stop. No prompts, no changes.
.PARAMETER EncryptAccountsTo
    A certificate file (.cer, "Document Encryption" type) whose private key only
    you hold. The generated passwords are then written encrypted, to
    accounts.txt.cms, and never in plain text; read them with
    Unprotect-CmsMessage -Path <file> as the certificate's owner. For unattended
    (CI) builds. Making the certificate: docs/dev/MAINTAINING.md
    ("Unattended builds and encrypted passwords").
.PARAMETER TestBuild
    Unattended test build for the VM test (Run-VmTest.cmd): same accounts and
    generated passwords, but they go to <WorkRoot>\test-accounts.txt (a real
    build's accounts.txt is never touched), the ISO is named
    Win11Pro-<isoTag>-TEST-*.iso and carries no build inputs. Never install a
    TEST ISO on a real PC.
.PARAMETER NoBuildInputs
    Leave the build inputs out of a real build. By default a real build carries
    its own inputs in the ISO (BuildInputs\, files split into <4 GB parts with
    SHA-256s): the source ISO, the updates, the security baseline zips,
    DriverExport.zip, oscdimg, the
    build-tool installers (Git, Python) in config\installers.json and a git
    bundle of the kit, plus Restore-BuildInputs.cmd, so the reinstalled PC can
    rebuild its ISO without downloads.
.PARAMETER Use2011BootManager
    Keep the media's boot files signed by the Windows Production PCA 2011
    certificate (expires 2026-10-19). By default the ISO boots with the
    "Windows UEFI CA 2023" boot manager from the media's serviced boot.wim
    (Microsoft's Make2023BootableMedia.ps1 procedure, KB5053484); the PC must
    trust that CA. Either way the boot files come from the serviced boot.wim.

.NOTES
    Passwords: each build generates a random 20-character password per account
    (letters and digits without look-alikes and without Y/Z; cryptographic RNG,
    unbiased, about 114 bits) and writes them only to <WorkRoot>\accounts.txt
    (created readable by SYSTEM + Administrators only; never to the console or
    the build log), whose last line names the ISO they belong to. Both must be
    changed at first sign-in.

    Folder lock: before anything else the build makes the kit folder (-KitRoot),
    the work folder (-WorkRoot), the driver export in it and its .zip/.sha256
    writable only by Administrators and SYSTEM (owner Administrators;
    BUILTIN\Users may read), and stops if that fails (scripts\KitAcl.ps1). Without
    the lock a standard user could change what this elevated build runs or puts
    into the image. -Preflight only reports whether they are locked.

    An install.wim over 4 GB is split into <4 GB .swm parts, so the USB stick can
    be FAT32 (the most reliable with Secure Boot).
#>
[CmdletBinding()]
param(
    [string]$SourceIso,
    [string]$KitRoot,
    # -Profile (not $Profile: that is PowerShell's automatic profile-path variable)
    [Alias('Profile')] [string]$HardwareProfile,
    [string]$WorkRoot,      # default: <KitRoot>\work (resolved below)
    [string]$Settings,       # default: <KitRoot>\config\settings.local.json, when it exists
    [string]$ThisPcLocale,   # from Run-Build.cmd (scripts\Invoke-KitLauncher.ps1)
    [string]$EncryptAccountsTo,
    [string]$ComputerName,   # default: your settings' computerName, then the profile's
    [switch]$Use2011BootManager,
    # Pause Defender's Controlled Folder Access and ASR prevalence rule (Defender preferences, as the
    # kit's image sets them) while the build runs; restored at the end. Run-Build.cmd asks first.
    [switch]$PauseDefenderProtection,
    [switch]$TestBuild,
    [switch]$NoBuildInputs,
    [switch]$Preflight
)

$ErrorActionPreference = 'Stop'
# Tools installed by Run-Prepare.cmd in this session: see them without a new console
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$ProgressPreference = 'SilentlyContinue'
$withInputs = -not $TestBuild -and -not $NoBuildInputs
if (-not $KitRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
$KitRoot = $KitRoot.TrimEnd('\')
# One work folder for everything the kit downloads or makes, inside the kit folder
# (git ignores /work/). The other defaults follow it.
if (-not $WorkRoot) { $WorkRoot = Join-Path $KitRoot 'work' }
$WorkRoot = $WorkRoot.TrimEnd('\')
$DriverRoot = Join-Path $WorkRoot 'DriverExport\_Curated'   # Run-Harvest.cmd
$UpdatesRoot = Join-Path $WorkRoot 'updates'                # scripts\Get-Updates.py
# The harvest's archive of the export folder (<work>\DriverExport\_Curated -> <work>\DriverExport.zip)
$driverZip = "$(Split-Path $DriverRoot -Parent).zip"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Preflight) { throw 'Run elevated (use Run-Build.cmd).' }

if ([Environment]::OSVersion.Version.Build -lt 26100) {
    throw "Build host is Windows build $([Environment]::OSVersion.Version.Build); servicing a 26H2 image needs a 24H2+ host (its DISM)."
}
# x64 only: the answer file, the ADK tools and the image are all amd64. Win32_Processor
# reports the real processor (9 = x64, 12 = ARM64) even to an emulated x64 PowerShell.
$hostArch = try { [int](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Architecture } catch { $(if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 9 } else { -1 }) }
if ($hostArch -ne 9) { throw "This PC's processor is not x64 ($(if ($hostArch -eq 12) { 'ARM64' } else { $env:PROCESSOR_ARCHITECTURE })): the kit builds on an x64 PC and makes x64 images only." }

# Leftover state from a failed run: unload offline hives FIRST (a loaded
# hive keeps files in the mount locked), then discard each mount on its own.
function Clear-BuildState([string[]]$Mounts) {
    foreach ($h in 'HKLM\W11K_SOFTWARE', 'HKLM\W11K_SYSTEM', 'HKLM\W11K_DEFAULT', 'HKLM\W11KV_SOFTWARE') {   # W11KV_: Test-OfflineImage
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $null = & reg.exe unload $h 2>&1 } finally { $ErrorActionPreference = $old }
    }
    [gc]::Collect()
    $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })
    foreach ($m in $Mounts) {
        if ($mounted -contains $m) {
            Write-Warning "Discarding mounted image at $m"
            try { Dismount-WindowsImage -Path $m -Discard -ErrorAction Stop | Out-Null } catch { Write-Warning "Could not discard $m : $($_.Exception.Message)" }
        }
    }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $null = & dism.exe /Cleanup-Mountpoints 2>&1 } finally { $ErrorActionPreference = $old }
}

# --- The build's folders: writable by administrators only (scripts\KitAcl.ps1) ----
# Inherited from C:\, the kit, its work folder and the driver export are writable by
# every signed-in user: a standard user (or malware in the daily account) could change
# what this elevated build runs, applies or packs into the image. So, before anything in
# them is used, they are locked: owner Administrators; SYSTEM + Administrators Full,
# Users Read & Execute; no junctions or links inside. -Preflight only reports.
# The work folder is inside the kit folder and the driver export inside the work folder
# (the work folder by default): Get-KitLockPlan gives one walk per path, outer folders
# first, and each walk leaves out the paths that have their own (the kit's walk never
# enters work\, where the mounted images are; nothing is walked twice). A -WorkRoot
# elsewhere simply has nothing to leave out of the kit's walk.
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitAcl.ps1'))))
$driverExport = Split-Path $DriverRoot -Parent
$lockPlan = @(Get-KitLockPlan @($KitRoot, $WorkRoot, $driverExport, $driverZip, "$driverZip.sha256"))
$lockNote = $null      # pre-flight line: $null = locked
$mountDirs = @('mount', 'mount-re', 'mount-boot' | ForEach-Object { Join-Path $WorkRoot $_ })
# Every folder DISM services an image in: excluded from Defender's ASR rules while the build runs
$asrExcl = @($mountDirs) + @(Join-Path $WorkRoot 'scratch')
# The Hyper-V test's copy of an ISO (scripts\Test-IsoInHyperV.ps1): it erases disk 0 without
# asking. The test deletes it when it ends; one left by a test that was killed goes here.
$vmTestIso = Join-Path $WorkRoot 'vmtest\W11Kit-VMTEST-ONLY-wipes-disk.iso'
$staleNotes = New-Object System.Collections.Generic.List[string]   # pre-flight lines (-Preflight changes nothing)
$buildMutex = $null

# Defender ASR-only exclusions for the build's DISM folders, left by a build that was killed
# before its 'finally' could remove them. Removed at the start of the next build; -ReportOnly
# just returns what it can see. Where policy hides exclusions (Get-MpPreference then returns
# 'N/A: ...'), nothing can be seen, so the removal never depends on reading them: removing
# a path that is not excluded changes nothing.
# Defender's ransomware protection, paused by a build (-PauseDefenderProtection) and restored in its
# 'finally'. The state before the pause is kept in <work>\defender-paused.json until then, so a
# build that was killed is repaired by the next build (or Run-Prepare.cmd).
function Get-DefenderProtection {
    $mp = Get-MpPreference -ErrorAction Stop
    $ids = @($mp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() }); $i = [array]::IndexOf($ids, '01443614-cd74-433a-b99e-2ecdc07bfc25')
    [ordered]@{ cfa = [int]$mp.EnableControlledFolderAccess; prevalence = $(if ($i -ge 0) { [int]@($mp.AttackSurfaceReductionRules_Actions)[$i] } else { 0 }) }
}
function Restore-DefenderProtection([string]$Marker) {
    if (-not (Test-Path -LiteralPath $Marker)) { return }
    $st = Get-Content -Raw -LiteralPath $Marker | ConvertFrom-Json
    Set-MpPreference -EnableControlledFolderAccess $(switch ([int]$st.cfa) { 1 { 'Enabled' } 2 { 'AuditMode' } 3 { 'BlockDiskModificationOnly' } default { 'Disabled' } }) -ErrorAction Stop
    $rid = '01443614-cd74-433a-b99e-2ecdc07bfc25'
    if ([int]$st.prevalence -eq 0) { Remove-MpPreference -AttackSurfaceReductionRules_Ids $rid -ErrorAction SilentlyContinue }
    else { Add-MpPreference -AttackSurfaceReductionRules_Ids $rid -AttackSurfaceReductionRules_Actions $(switch ([int]$st.prevalence) { 1 { 'Enabled' } 2 { 'AuditMode' } 6 { 'Warn' } default { 'Disabled' } }) -ErrorAction Stop }
    Remove-Item -LiteralPath $Marker -Force
    Write-Host "Defender protection restored: Controlled Folder Access=$($st.cfa), ASR prevalence rule=$($st.prevalence)" -ForegroundColor Green
}

function Clear-StaleAsrExclusions([string[]]$Paths, [switch]$ReportOnly) {
    $seen = @()
    try { $seen = @((Get-MpPreference -ErrorAction Stop).AttackSurfaceReductionOnlyExclusions | Where-Object { $_ -and $Paths -contains "$_".TrimEnd('\') }) } catch { }
    if ($ReportOnly) { return $seen }
    try { Remove-MpPreference -AttackSurfaceReductionOnlyExclusions $Paths -ErrorAction Stop }
    catch { if ($seen.Count) { Write-Warning "Could not remove the Defender ASR exclusions an interrupted build left ($($seen -join ', ')): $($_.Exception.Message)" }; return }
    if ($seen.Count) { Write-Host "Removed Defender ASR exclusions left by an interrupted build: $($seen -join ', ')" -ForegroundColor Yellow }
}

if ($Preflight) {
    $staleAsr = @(Clear-StaleAsrExclusions $asrExcl -ReportOnly)
    if ($staleAsr.Count) { $staleNotes.Add("Defender ASR exclusions left by an interrupted build: $($staleAsr -join ', '). The next build (or Run-Prepare.cmd) removes them.") }
    if (Test-Path -LiteralPath $vmTestIso) { $staleNotes.Add("A VM-test ISO was left behind: $vmTestIso. It erases disk 0 without asking: never write it to a USB stick. The next build (or Run-Prepare.cmd) deletes it.") }
    $found = New-Object System.Collections.Generic.List[string]
    $mounted = @(try { Get-WindowsImage -Mounted -ErrorAction Stop | ForEach-Object { $_.Path } } catch { })
    foreach ($lp in $lockPlan) {
        if (-not (Test-Path -LiteralPath $lp.Path)) { continue }
        foreach ($x in @(Test-KitPathLocked $lp.Path -RefuseDirs $mounted -SkipDirs $lp.SkipDirs -MaxReport 3)) { $found.Add($x) }
    }
    if ($found.Count) { $lockNote = "not locked yet (the build locks them first): $(@($found | Select-Object -First 3) -join '; ')$(if ($found.Count -gt 3) { '; ...' })" }
} else {
    # An earlier failed run's mounts first: the lock never walks into a mounted image. What is
    # left in the (now unmounted) mount folders is deleted: an image's own junctions would
    # stop the lock, and the build recreates the folders anyway. rmdir /s never follows a
    # junction (it removes the link itself).
    Clear-BuildState $mountDirs
    $mounted = @(Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | ForEach-Object { $_.Path })
    foreach ($d in $mountDirs) {
        if ((Test-Path -LiteralPath $d) -and $mounted -notcontains $d) {
            $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # native stderr under 'Stop' would be terminating
            try { $null = & cmd.exe /d /c "rmdir /s /q `"$d`"" 2>&1 } finally { $ErrorActionPreference = $old }
        }
    }
    # Held while this build runs (Windows releases it when the process ends, however it
    # ends): Run-Prepare.cmd leaves a running build's Defender exclusions alone.
    $buildMutex = New-Object Threading.Mutex($false, 'Global\W11KitBuild')
    # Left by an interrupted build (nothing of this build is mounted yet)
    Clear-StaleAsrExclusions $asrExcl
    # Outer folders first: the kit folder is locked before the work folder in it is created
    # or locked, so nothing can be put in the work folder's place in between.
    foreach ($lp in $lockPlan) {
        if ($lp.Path -ieq [IO.Path]::GetFullPath($WorkRoot).TrimEnd('\')) { New-KitLockedFolder $WorkRoot }
        if (-not (Test-Path -LiteralPath $lp.Path)) { continue }   # no driver export yet: the pre-flight says so
        $bad = @(Lock-KitPath $lp.Path -RefuseDirs $mounted -SkipDirs $lp.SkipDirs)
        if ($bad.Count) { throw "Could not make $($lp.Path) writable by administrators only, so the build stops (nothing else was changed): $($bad -join '; ')" }
    }
    Write-Host "Build folders locked (administrators write, users read): $(@($lockPlan | Where-Object { Test-Path -LiteralPath $_.Path } | ForEach-Object Path) -join ', ')" -ForegroundColor Cyan
    # Left by an interrupted VM test (after the lock: no link can stand in for the folder)
    if (Test-Path -LiteralPath $vmTestIso) {
        Remove-Item -LiteralPath $vmTestIso -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $vmTestIso) { Write-Warning "Could not delete the VM-test ISO $vmTestIso (is a VM test running?). It erases disk 0 without asking: never write it to a USB stick." }
        else { Write-Host "Deleted a VM-test ISO left behind by an interrupted VM test: $vmTestIso" -ForegroundColor Yellow }
    }
}
# The lock ends at each folder's own top: a folder ABOVE it that a standard account may
# change lets that account move the locked folder aside and put another in its place.
# Directly under C:\ (C:\W11Kit) there is none. Told, not refused (kits live in user
# profiles too); paths inside another locked folder have that folder above them.
$above = @(foreach ($lp in $lockPlan) {
    if (@($lockPlan | Where-Object { $_.SkipDirs -contains $lp.Path }).Count) { continue }
    Test-KitPathParents $lp.Path
}) | Sort-Object -Unique
foreach ($a in $above) { Write-Warning "$a, so that account could replace the locked build folder in it as a whole. Keep the kit in a folder of its own directly under the drive, such as C:\W11Kit (docs\dev\BUILD-INTERNALS.md, 'Folder lock')." }
# git as administrator on the kit: only this exact clone is trusted (never a wildcard
# safe.directory, which would also trust a .git planted anywhere). Locked, the kit is owned
# by Administrators, which Git for Windows accepts for an elevated administrator anyway.
$gitSafeDir = 'safe.directory=' + ($KitRoot -replace '\\', '/')


# --- Hardware profile (docs\reference\PROFILES.md) -------------------------------------
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitProfile.ps1'))))
try { $prof = Resolve-KitProfile -KitRoot $KitRoot -Id $HardwareProfile }
catch { throw "Pre-flight failed: $($_.Exception.Message) Nothing was changed." }
$hw = $prof.Profile
Write-Host "Hardware profile: $($hw.id) ($($hw.displayName)): $($prof.Reason)." -ForegroundColor Cyan
if ($prof.FitsPc -eq $false) {
    Write-Host "  [NOTE] Its match does not fit this PC ($($prof.PcManufacturer) $($prof.PcModel)): building for other hardware. The drivers in $DriverRoot must come from a PC of that model." -ForegroundColor Yellow
}
# The generic Windows 11 Pro installation key (selects the edition during Setup; does not
# activate; not a licence). Windows activates with the PC's digital licence if it has one,
# e.g. a Pro licence bought and activated on it. Only for productKey 'generic': 'firmware' (a Pro
# MSDM key) and 'prompt' get no key in the answer file.
$GenericProKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T'
Write-Host "  product key: $($hw.productKey)$(if ($hw.productKey -eq 'generic') { ' (the generic Windows 11 Pro installation key selects the edition; it does not activate and is not a licence)' })"

# --- Your settings (scripts\KitSettings.ps1; docs\reference\CONFIGURATION.md) -----------
# config\settings.defaults.json with your file laid over it, read and checked here; the
# pre-flight below reports any problem and stops the build.
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitSettings.ps1'))))
try { $ks = Get-KitSettings -KitRoot $KitRoot -SettingsFile $Settings -ThisPcLocale $ThisPcLocale }
catch { throw "Pre-flight failed: $($_.Exception.Message) Nothing was changed." }
$kitSettings = $ks.Settings
$settingsProblems = New-Object System.Collections.Generic.List[string]
foreach ($x in $ks.Problems) { $settingsProblems.Add($x) }
$settingsFiles = $ks.Files
$loc = $kitSettings.locale
$geo = $loc.homeLocation
$TimeZone = $loc.timeZone
$AdminName = $kitSettings.accounts.admin
$UserName = $kitSettings.accounts.user
$optGaming = [bool]$kitSettings.options.gamingTweaks
# Computer name: -ComputerName, else your settings, else the profile. None = unattend '*':
# Windows picks a random name and PostInstall renames nothing.
$nameSource = '-ComputerName'
if (-not $PSBoundParameters.ContainsKey('ComputerName')) {
    if ($kitSettings.computerName) { $ComputerName = $kitSettings.computerName; $nameSource = 'your settings' }
    else { $ComputerName = $hw.computerName; $nameSource = "profile $($hw.id)" }
}
if ($ComputerName -and ($ComputerName -notmatch '^[A-Za-z0-9-]{1,15}$' -or $ComputerName -match '^\d+$')) {
    throw "Invalid computer name '$ComputerName' ($nameSource): 1-15 letters, digits or hyphens, not all digits."
}
if ($ComputerName -and ($ComputerName -in $AdminName, $UserName, $kitSettings.accounts.builtinAdministratorName, $kitSettings.accounts.builtinGuestName)) {
    $settingsProblems.Add("computer name '$ComputerName' ($nameSource) is also an account name: Windows does not allow that")
}
# The built-in Administrator and Guest accounts get new names (they stay disabled): the
# ones in your settings, else a new pair for every build, drawn in the build itself (a
# -Preflight draws none). Staged in the security template the first boot applies.
$builtinAdmin = $kitSettings.accounts.builtinAdministratorName
$builtinGuest = $kitSettings.accounts.builtinGuestName
$builtinGenerated = @(if (-not $builtinAdmin) { 'Administrator' }; if (-not $builtinGuest) { 'Guest' })

Write-Host "Settings: $settingsFiles" -ForegroundColor Cyan
if ($ks.OverlayPath -and $ks.FromFile.Count) { Write-Host "  from $($ks.OverlayLabel): $($ks.FromFile -join ', ')" }
elseif (-not $ks.OverlayPath) { Write-Host '  no settings file of your own (config\settings.local.json): the kit''s defaults, and this PC''s values where Run-Build.cmd read them' }
Write-Host "  language $($loc.uiLanguage); accounts $AdminName / $UserName; computer name $(if ($ComputerName) { "$ComputerName ($nameSource)" } else { 'random (Windows picks one)' })"
$settingRows = [ordered]@{ inputLocale = "$($loc.inputLocale)"; userLocale = "$($loc.userLocale)"; systemLocale = "$($loc.systemLocale)"; timeZone = "$($loc.timeZone)"; homeLocation = "$($geo.isoCode) ($($geo.geoId))" }
$settingNames = @{ inputLocale = 'keyboard'; userLocale = 'formats'; systemLocale = 'system locale'; timeZone = 'time zone'; homeLocation = 'home location' }
foreach ($f in $settingRows.Keys) {
    $src = "$($ks.Sources[$f])"
    Write-Host ("  {0,-14} {1,-28} ({2})" -f $settingNames[$f], $settingRows[$f], $(if ($src -eq 'this PC') { 'from this PC' } else { $src })) -ForegroundColor $(if ($src -eq 'kit default') { 'Yellow' } else { 'Gray' })
}
if ($ks.ThisPcAccount -and @($ks.Sources.Values | Where-Object { $_ -eq 'this PC' }).Count) { Write-Host "  (this PC's values were read as $($ks.ThisPcAccount), the account that started Run-Build.cmd)" }
foreach ($n in $ks.Notes) { Write-Host "  [NOTE] $n" -ForegroundColor Yellow }
Write-Host "  built-in Administrator and Guest accounts (disabled) renamed to: $(if ($builtinAdmin) { $builtinAdmin } else { 'a new name' }) / $(if ($builtinGuest) { $builtinGuest } else { 'a new name' })$(if ($builtinGenerated.Count) { ' (drawn for each build; the build prints them)' })"
$optOn = @($kitSettings.options.Keys | Where-Object { $kitSettings.options[$_] -is [bool] -and $kitSettings.options[$_] })
$optOff = @($kitSettings.options.Keys | Where-Object { $kitSettings.options[$_] -is [bool] -and -not $kitSettings.options[$_] })
Write-Host "  options on: $(if ($optOn.Count) { $optOn -join ', ' } else { 'none' }); off: $(if ($optOff.Count) { $optOff -join ', ' } else { 'none' }); Smart App Control: $(if ($kitSettings.options.smartAppControl -eq 'off') { 'off' } else { 'left to Windows' })"
if ($kitSettings.options.allowMicrosoftAccount) { Write-Host '  options.allowMicrosoftAccount: the local accounts may be converted to Microsoft accounts (the policy that prevents it is not set)' -ForegroundColor Yellow }
$remOn = @($kitSettings.reminders.Keys | Where-Object { $kitSettings.reminders[$_] -is [bool] -and $kitSettings.reminders[$_] })
$remOff = @($kitSettings.reminders.Keys | Where-Object { $kitSettings.reminders[$_] -is [bool] -and -not $kitSettings.reminders[$_] })
$expectedApps = @($kitSettings.reminders.expectedApps | ForEach-Object { "$($_.name)" })
Write-Host "  validator reminders on: $(if ($remOn.Count) { $remOn -join ', ' } else { 'none' }); off: $(if ($remOff.Count) { $remOff -join ', ' } else { 'none' }); expected apps: $(if ($expectedApps.Count) { $expectedApps -join ', ' } else { 'none' })"

# Setup's UI language (locale.uiLanguage) must be one the source media has: Setup
# cannot show, and Windows cannot install, a language that isn't on it. The media
# lists its languages in sources\lang.ini ([Available UI Languages]).
# The media must also be x64: its UEFI boot file is efi\boot\bootx64.efi (ARM64 media
# has bootaa64.efi instead). Returns Languages (a list) and Architecture ('x64',
# 'ARM64' or 'unknown').
function Get-IsoFacts([string]$Iso) {
    $img = Get-DiskImage -ImagePath $Iso
    $we = -not $img.Attached
    if ($we) { $null = Mount-DiskImage -ImagePath $Iso -Access ReadOnly -PassThru }
    try {
        $letter = $null
        for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
            $letter = (Get-DiskImage -ImagePath $Iso | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if (-not $letter) { Start-Sleep -Seconds 1 }
        }
        if (-not $letter) { throw 'the ISO mounted but has no drive letter' }
        $ini = "$($letter):\sources\lang.ini"
        if (-not (Test-Path -LiteralPath $ini)) { throw "no sources\lang.ini on the media" }
        $inSection = $false
        $langs = New-Object System.Collections.Generic.List[string]
        foreach ($line in [IO.File]::ReadAllLines($ini)) {
            if ($line -match '^\s*\[(.+)\]') { $inSection = $Matches[1].Trim() -eq 'Available UI Languages'; continue }
            if ($inSection -and $line -match '^\s*([A-Za-z]{2,3}(-[A-Za-z]{4})?-[A-Za-z]{2})\s*=') { $langs.Add($Matches[1]) }
        }
        $arch = if (Test-Path -LiteralPath "$($letter):\efi\boot\bootx64.efi") { 'x64' } elseif (Test-Path -LiteralPath "$($letter):\efi\boot\bootaa64.efi") { 'ARM64' } else { 'unknown' }
        [pscustomobject]@{ Languages = $langs.ToArray(); Architecture = $arch }
    } finally { if ($we) { Dismount-DiskImage -ImagePath $Iso | Out-Null } }
}

# reg.exe with a local 'Continue' (its stderr would be terminating under 'Stop'); returns the exit code
function Invoke-Reg {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $null = & reg.exe @args 2>&1; $LASTEXITCODE } finally { $ErrorActionPreference = $old }
}

function Step([string]$Text) { Write-Host ''; Write-Host "==> [$(Get-Date -Format HH:mm:ss)] $Text" -ForegroundColor Cyan }
function Invoke-KitScript([string]$RelPath, [hashtable]$Params = @{}) {
    $sb = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $KitRoot $RelPath)))
    & $sb @Params
}
function Get-KbNumber([string]$Name) { if ($Name -match 'kb(\d+)') { [int]$Matches[1] } else { 0 } }
function Get-Packages([string]$Sub, [string]$Filter) {
    $d = Join-Path $UpdatesRoot $Sub
    if (Test-Path $d) { @(Get-ChildItem $d -File -Filter $Filter | Where-Object { $_.Extension -eq [IO.Path]::GetExtension($Filter) } | Sort-Object { Get-KbNumber $_.Name }, Name) } else { @() }
}
# An update file, checked right before it is applied: Update Catalog files carry their own
# SHA-1 in the name (<kb>_<sha1>.msu/.cab; scripts\Get-Updates.py checks it at download).
# A file without one, or changed since, stops the build.
function Assert-UpdateFile([IO.FileInfo]$File) {
    if ($File.Name -notmatch '_([0-9a-fA-F]{40})\.(msu|cab)$') { throw "$($File.FullName) is not named like an Update Catalog file (<kb>_<SHA-1>.msu/.cab), so it can't be checked: delete it and fetch the updates again (scripts\Get-Updates.py)." }
    $want = $Matches[1].ToUpperInvariant()
    $got = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA1).Hash
    if ($got -ne $want) { throw "$($File.FullName): SHA-1 $got does not match the one in its name ($want): changed or damaged since the download. Delete it and fetch the updates again (scripts\Get-Updates.py)." }
}
# The cumulative update into a Windows PE image (WinRE, boot.wim), as Microsoft's sample
# does ("Update Windows installation media with Dynamic Update"): there error 0x8007007e
# is "a known issue with combined cumulative update" (the servicing stack went in, the rest
# did not) and is tolerated; anything else stops the build. Returns $true when the package
# applied completely, $false after the tolerated error.
function Add-PeCumulativeUpdate([string]$Path, [IO.FileInfo]$Update, [string]$LogName) {
    Assert-UpdateFile $Update
    try {
        Add-WindowsPackage -Path $Path -PackagePath $Update.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs $LogName) -ErrorAction Stop | Out-Null
        return $true
    } catch {
        if ("$($_.Exception.Message) $($_.Exception)" -notlike '*0x8007007e*') { throw }
        Write-Warning "$($Update.Name): error 0x8007007e, a known issue with a combined cumulative update on Windows PE (Microsoft's sample ignores it)."
        return $false
    }
}
# 'build.revision' (e.g. 26100.9550) of the newest INSTALLED cumulative update in a mounted image, or $null
function Get-InstalledLcuBuild([string]$Path) {
    $best = $null
    foreach ($p in @(Get-WindowsPackage -Path $Path -ScratchDirectory $scratch)) {
        if ("$($p.PackageState)" -eq 'Installed' -and $p.PackageName -match 'RollupFix~.*~~(\d+\.\d+)\.\d+\.\d+$') {
            if (-not $best -or [version]$Matches[1] -gt [version]$best) { $best = $Matches[1] }
        }
    }
    $best
}
# A WIM file's boot index (the image a boot manager starts; 0 = none): the DWORD at offset
# 120 of the WIM header (after the boot-metadata resource entry). DISM's cmdlets don't show it.
function Get-WimBootIndex([string]$Path) {
    $fs = [IO.File]::OpenRead($Path)
    try {
        $b = New-Object byte[] 124
        if ($fs.Read($b, 0, 124) -ne 124 -or [Text.Encoding]::ASCII.GetString($b, 0, 5) -ne 'MSWIM') { throw "$Path is not a WIM file" }
        [int][BitConverter]::ToUInt32($b, 120)
    } finally { $fs.Dispose() }
}
function Get-FileVersionText([string]$Path) {
    $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    '{0}.{1}.{2}.{3}' -f $v.FileMajorPart, $v.FileMinorPart, $v.FileBuildPart, $v.FilePrivatePart
}
# The curated drivers against the harvest's SHA-256 manifest (<export>\_Reports\curated-sha256.txt,
# written by Invoke-DriverHarvest.ps1): every file listed and unchanged, nothing added. Files of
# a package the profile skips (drivers.skipInf) may be missing. Returns the problems.
function Test-CuratedDrivers([string]$Root, [string]$SkipInf) {
    $list = Join-Path (Split-Path $Root -Parent) '_Reports\curated-sha256.txt'
    if (-not (Test-Path -LiteralPath $list)) { return "no SHA-256 manifest ${list}: run Run-Harvest.cmd -CurateOnly (it writes one)" }
    $want = @{}   # relative path -> SHA-256 (PowerShell hashtables ignore case, like Windows paths)
    foreach ($line in [IO.File]::ReadAllLines($list)) { if ($line -match '^([0-9A-Fa-f]{64})  (.+)$') { $want[$Matches[2]] = $Matches[1].ToUpperInvariant() } }
    $skipDirs = @{}
    if ($SkipInf) { foreach ($k in @($want.Keys)) { if ($k -match '\.inf$' -and (Split-Path $k -Leaf) -match $SkipInf) { $skipDirs[($k -split '\\')[0]] = $true } } }
    $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\')
    $seen = @{}
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($rootFull.Length + 1)
        $seen[$rel] = $true
        if (-not $want.ContainsKey($rel)) { $bad.Add("$rel is not from the harvest"); continue }
        if ((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ne $want[$rel]) { $bad.Add("$rel changed since the harvest") }
    }
    foreach ($k in @($want.Keys)) { if (-not $seen.ContainsKey($k) -and -not $skipDirs.ContainsKey(($k -split '\\')[0])) { $bad.Add("$k missing") } }
    if ($bad.Count) { $bad.Add("re-run Run-Harvest.cmd -CurateOnly if you changed _Curated on purpose") }
    $bad.ToArray()
}
# The driver packages (INF files) of the given device setup classes, by the Class line of
# each INF's [Version] section. One selection for WinRE (network and storage: Net,
# SCSIAdapter, HDC) and for boot.wim (storage only), so both get the same storage drivers.
function Select-DriverInfByClass([object[]]$Infs, [string[]]$Classes) {
    $pattern = '^\s*Class\s*=\s*(' + ($Classes -join '|') + ')\s*(;.*)?$'
    @($Infs | Where-Object { $_ -and (Select-String -LiteralPath $_.FullName -Pattern $pattern -Quiet) })
}
# One baseline's imported data in <work>\baselines\<id> (scripts\Import-Baseline.py) against
# its own index.json and the pins: the index names the pinned zip (file and SHA-256) and the
# pinned GPOs in their order, lists only the importer's own file names, and every listed
# file is there with the SHA-256 the index gives. Returns what is wrong, or $null.
function Test-BaselineData($Baseline) {
    try {
        $ixPath = Join-Path $Baseline.Dir 'index.json'
        if (-not (Test-Path -LiteralPath $ixPath)) { return 'not imported yet' }
        $ix = [IO.File]::ReadAllText($ixPath) | ConvertFrom-Json
        if ("$($ix.source.sha256)" -ne $Baseline.Sha256 -or "$($ix.source.file)" -cne $Baseline.File) { return "imported from another file ($($ix.source.file), SHA-256 $($ix.source.sha256)) than the pinned one" }
        if ((@($ix.gpos | ForEach-Object { "$($_.name)" }) -join '|') -cne ($Baseline.Gpos -join '|')) { return 'imported for another list of GPOs than source.json names now' }
        $names = @($ix.files.PSObject.Properties | ForEach-Object Name)
        foreach ($f in 'registry-machine.json', 'registry-user.json') { if ($names -notcontains $f) { return "index.json lists no $f" } }
        foreach ($p in $ix.files.PSObject.Properties) {
            if ($p.Name -notin 'registry-machine.json', 'registry-user.json', 'security.inf', 'audit.csv') { return "index.json lists '$($p.Name)', which is not a file the importer writes" }
            $fp = Join-Path $Baseline.Dir $p.Name
            if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { return "$($p.Name) is missing" }
            if ((Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash -ne "$($p.Value)".ToUpperInvariant()) { return "$($p.Name) is not the file index.json describes (changed since the import)" }
        }
        $null
    } catch { "not readable ($($_.Exception.Message))" }
}
# The staged Baselines folder (C:\ProgramData\W11Kit\Baselines on the installed PC, read by
# Apply-Policy.ps1 and the validator): the list and each baseline's pins from the kit, the
# imported data from the work folder: index.json and exactly the files it lists.
function Copy-BaselineData([object[]]$Baselines, [string]$PinRoot, [string]$Dest) {
    New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PinRoot 'baselines.json') -Destination $Dest -Force
    foreach ($bl in $Baselines) {
        $d = Join-Path $Dest $bl.Id
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PinRoot "$($bl.Id)\source.json") -Destination $d -Force
        $ix = [IO.File]::ReadAllText((Join-Path $bl.Dir 'index.json')) | ConvertFrom-Json
        foreach ($n in @('index.json') + @($ix.files.PSObject.Properties | ForEach-Object Name)) {
            Copy-Item -LiteralPath (Join-Path $bl.Dir $n) -Destination $d -Force
        }
    }
}
# Windows ADK Deployment Tools (oscdimg): pinned in config\installers.json ('adk') and installed
# by the same script as the other build tools (SHA-256 + exact Authenticode signer checked).
function Install-AdkDeploymentTools {
    $r = @(Invoke-KitScript 'scripts\Install-BuildTools.ps1' @{ KitRoot = $KitRoot; WorkRoot = $WorkRoot; Tools = @('adk'); PassThru = $true })
    if (-not $r.Count -or $r[0].State -notin 'OK', 'INSTALLED') { throw "Windows ADK Deployment Tools not installed: $($r[0].Detail) (log in $WorkRoot\logs)" }
}

function Find-Oscdimg {
    # A copy restored from an ISO's BuildInputs (no ADK install), then the ADK, then PATH; each
    # only if validly signed by exactly the ADK's pinned signer (config\installers.json 'adk'),
    # not just any Microsoft-signed program renamed oscdimg.exe.
    $signer = try { "$(([IO.File]::ReadAllText((Join-Path $KitRoot 'config\installers.json')) | ConvertFrom-Json).adk.signer)" } catch { '' }
    if (-not $signer) { $signer = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' }
    $local = Join-Path $WorkRoot 'tools\Oscdimg\oscdimg.exe'
    $c = @($local,
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        (Get-Command oscdimg.exe -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($x in $c) {
        $sig = Get-AuthenticodeSignature -LiteralPath $x
        if ($sig.Status -eq 'Valid' -and "$($sig.SignerCertificate.Subject)" -ceq $signer) { return $x }
        Write-Warning "Ignoring ${x}: not validly signed by '$signer' (status $($sig.Status), signer '$($sig.SignerCertificate.Subject)')."
    }
    return $null
}

# Self-hosting: the build's own inputs go into the ISO so the reinstalled PC can
# rebuild itself (scripts\Restore-BuildInputs.ps1 puts them back). FAT32 can't
# hold a file over 4 GB, so each file is split into parts; one pass both copies
# and hashes. Only the explicit list below goes in: never accounts.txt.
# Every 'dest' is relative to the kit folder the restore makes (default C:\W11Kit) and
# lies in its work folder: work\source, work\updates, work\baselines (Microsoft's zips, not
# the data imported from them: the next build imports them again), work\DriverExport.zip,
# work\tools\Oscdimg, work\installers, work\kit (the bundle and your own files).
function New-BuildInputs([string]$Dir, [long]$PartSize = 3.5GB) {
    $partSize = $PartSize
    $data = Join-Path $Dir 'data'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    $items = New-Object System.Collections.Generic.List[object]
    $add = { param($src, $dest) $items.Add([pscustomobject]@{ Src = $src; Dest = $dest }) }
    & $add $SourceIso ('work\source\' + (Split-Path $SourceIso -Leaf))
    $updRoot = (Resolve-Path $UpdatesRoot).Path.TrimEnd('\')
    Get-ChildItem $updRoot -Recurse -File | Where-Object Extension -ne '.part' | ForEach-Object {
        & $add $_.FullName ('work\updates' + $_.FullName.Substring($updRoot.Length))
    }
    $blZipSha = @{}   # dest -> pinned SHA-256
    foreach ($bl in $blList) { & $add $bl.Zip ('work\baselines\' + $bl.File); $blZipSha['work\baselines\' + $bl.File] = $bl.Sha256 }
    & $add $driverZip 'work\DriverExport.zip'
    & $add "$driverZip.sha256" 'work\DriverExport.zip.sha256'
    # Only the ADK's Oscdimg files (oscdimg could resolve through PATH to a broad folder)
    Get-ChildItem (Split-Path $oscdimg) -File | Where-Object { $_.Name -match '^(oscdimg\.exe|efisys.*\.bin|etfsboot\.com)$' } |
        ForEach-Object { & $add $_.FullName ('work\tools\Oscdimg\' + $_.Name) }
    foreach ($i in @((Get-Content -Raw (Join-Path $KitRoot 'config\installers.json') | ConvertFrom-Json).installers)) {
        & $add (Join-Path $WorkRoot "installers\$($i.file)") ('work\installers\' + $i.file)
    }
    $bundle = Join-Path $WorkRoot 'kit.bundle'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    # safe.directory: this clone only (elevated git refuses a repo owned by someone else,
    # "dubious ownership", e.g. a kit cloned by the daily user and not locked yet)
    try { $null = & $gitExe -c $gitSafeDir -C $KitRoot bundle create $bundle --all 2>&1; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($rc -ne 0) { throw "git bundle failed ($rc)" }
    & $add $bundle 'work\kit\w11kit.bundle'
    # Your own files the bundle (commits only) doesn't hold: config\settings.local.json and
    # config\source-iso.local.json (git-ignored), and profiles\<id>\profile.json files that are untracked or changed (e.g.
    # made with New-Profile.cmd and never committed). Carried under work\kit\local\ with
    # their kit-relative paths; Restore-BuildInputs.ps1 puts them back into the kit clone.
    # (The pathspec keeps git inside profiles\: it never lists the ignored work folder.)
    $localRel = New-Object System.Collections.Generic.List[string]
    foreach ($own in 'config\settings.local.json', 'config\source-iso.local.json') {
        if (Test-Path -LiteralPath (Join-Path $KitRoot $own)) { $localRel.Add($own) }
    }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $st = "$(& $gitExe -c $gitSafeDir -C $KitRoot status --porcelain -z --untracked-files=all -- profiles 2>$null)"; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($rc -ne 0) { throw "git status failed ($rc)" }
    foreach ($e in ($st -split "`0")) {
        # '?? path' (untracked), ' M path' / 'M  path' (changed); -z: no quoting, renames add a second entry
        if ($e.Length -gt 3 -and $e.Substring(0, 2) -match '^(\?\?|.M|M.|A.)$' -and $e.Substring(3) -match '^profiles/[^/]+/profile\.json$') { $localRel.Add(($e.Substring(3) -replace '/', '\')) }
    }
    foreach ($r in $localRel) {
        & $add (Join-Path $KitRoot $r) ('work\kit\local\' + $r)
        Write-Host "  your own file (not in the kit's commits): $r"
    }
    foreach ($it in $items) {
        if ("$($it.Src) $($it.Dest)" -match 'accounts\.txt') { throw "Refusing to put $($it.Src) into the ISO" }
    }

    $files = New-Object System.Collections.Generic.List[object]
    $buf = New-Object byte[] (4MB)
    $n = 0
    foreach ($it in $items) {
        $n++
        $len = (Get-Item -LiteralPath $it.Src).Length
        Write-Host ("  [{0}/{1}] {2} ({3} MB)" -f $n, $items.Count, $it.Dest, [math]::Round($len / 1MB))
        $sha = [Security.Cryptography.SHA256]::Create()
        $parts = New-Object System.Collections.Generic.List[string]
        $in = [IO.File]::OpenRead($it.Src)
        try {
            $p = 0
            do {
                $p++
                $name = 'data\{0:D3}.p{1}' -f $n, $p
                $out = [IO.File]::Create((Join-Path $Dir $name))
                $written = [long]0   # 64-bit: [math]::Min with an int picks the Int32 overload
                try {
                    while ($written -lt $partSize -and ($read = $in.Read($buf, 0, [int][math]::Min([long]$buf.Length, [long]($partSize - $written)))) -gt 0) {
                        $out.Write($buf, 0, $read); [void]$sha.TransformBlock($buf, 0, $read, $null, 0); $written += $read
                    }
                } finally { $out.Dispose() }
                $parts.Add($name)
            } while ($in.Position -lt $len)
        } finally { $in.Dispose() }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
        $hash = -join ($sha.Hash | ForEach-Object { $_.ToString('X2') })
        if ($it.Dest -eq 'work\DriverExport.zip') {
            $want = ((Get-Content "$($it.Src).sha256" -TotalCount 1) -split '\s+')[0].ToUpper()
            if ($hash -ne $want) { throw "DriverExport.zip SHA-256 $hash does not match DriverExport.zip.sha256 ($want)" }
        }
        if ($it.Src -eq $SourceIso -and $hash -ne $sourceSha) { throw "Source ISO changed during the build (SHA-256 $hash)" }
        if ($blZipSha.ContainsKey($it.Dest) -and $hash -ne $blZipSha[$it.Dest].ToUpperInvariant()) { throw "$($it.Src) changed during the build (SHA-256 $hash is not the pinned $($blZipSha[$it.Dest]))" }
        $files.Add([ordered]@{ dest = $it.Dest; size = $len; sha256 = $hash; parts = $parts.ToArray() })
    }
    Remove-Item $bundle -Force
    Copy-Item (Join-Path $KitRoot 'scripts\Restore-BuildInputs.ps1'), (Join-Path $KitRoot 'scripts\Restore-BuildInputs.cmd'), (Join-Path $KitRoot 'scripts\Install-BuildTools.ps1'), (Join-Path $KitRoot 'config\installers.json') $Dir -Force
    # .ToArray(): @(<List>) inside an [ordered] literal throws "Argument types do not match" in PS 5.1
    # layout 2: every dest lies in work\ under the restored kit folder
    [ordered]@{ built = (Get-Date).ToString('s'); kitRevision = $kitRevision; layout = 2; localFiles = $localRel.ToArray(); files = $files.ToArray() } |
        ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Dir 'manifest.json') -Encoding UTF8
    $total = 0; foreach ($f in $files) { $total += $f.size }   # Measure-Object can't read dictionary keys in PS 5.1
    Write-Host ("  {0} files, {1:N1} GB; restore with BuildInputs\Restore-BuildInputs.cmd on the installed PC" -f $files.Count, ($total / 1GB))
    $manifest.buildInputs = @($files.ToArray() | ForEach-Object { [ordered]@{ dest = $_.dest; size = $_.size; sha256 = $_.sha256 } })
}

# --- Pre-flight (before any prompt) ------------------------------------------
if (-not $SourceIso) {
    # <work>\source first (where Restore-BuildInputs puts the ISO an install stick carries),
    # then every profile's Downloads folder, Public included: elevation may run as a
    # different (admin) account than the one that downloaded the ISO. The newest file
    # wins; of two equally new ones, the first found (work\source).
    $isoDirs = @(Join-Path $WorkRoot 'source') + @(Get-ChildItem "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'Downloads' })
    $newestIso = $null
    foreach ($d in $isoDirs) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -Filter '*.iso' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Windows11|Win11).*\.iso$' })) {
            if (-not $newestIso -or $f.LastWriteTime -gt $newestIso.LastWriteTime) { $newestIso = $f }
        }
    }
    if ($newestIso) { $SourceIso = $newestIso.FullName }
}
$problems = New-Object System.Collections.Generic.List[string]
function Check([string]$What, [bool]$Ok, [string]$Detail) {
    $mark = if ($Ok) { 'OK  ' } else { 'FAIL' }
    Write-Host ("  [{0}] {1}  {2}" -f $mark, $What, $Detail) -ForegroundColor $(if ($Ok) { 'Gray' } else { 'Red' })
    if (-not $Ok) { $problems.Add("$What $Detail") }   # parent-scope list (works when run as a scriptblock)
}
Write-Host 'Pre-flight checks:'
Check 'Settings valid' ($settingsProblems.Count -eq 0) "$settingsFiles$(if ($settingsProblems.Count) { ': ' + ($settingsProblems -join '; ') })"
$isoFound = [bool]($SourceIso -and (Test-Path -LiteralPath $SourceIso))
Check 'Source ISO' $isoFound $(if ($isoFound) { "$SourceIso" } elseif ($SourceIso) { "$SourceIso not found: check the path (put it in double quotes if it has spaces)" } else { "none found: the build looks in $WorkRoot\source and in every user's Downloads folder ($env:SystemDrive\Users\<name>\Downloads) for a file named Win11*.iso or Windows11*.iso (the newest wins); or name it: Run-Build.cmd -SourceIso `"<path>`"" })
if ($SourceIso -and (Test-Path $SourceIso)) {
    $isoLangs = $null
    try { $isoFacts = Get-IsoFacts $SourceIso; $isoLangs = @($isoFacts.Languages) } catch { $isoLangErr = $_.Exception.Message }
    if ($null -ne $isoLangs) {
        Check 'Source ISO is x64 media' ($isoFacts.Architecture -eq 'x64') $(if ($isoFacts.Architecture -eq 'x64') { 'efi\boot\bootx64.efi' } else { "$($isoFacts.Architecture) media: the kit builds x64 images only; download the x64 (64-bit) Windows 11 ISO" })
        $langOk = [bool](@($isoLangs | Where-Object { $_ -eq $loc.uiLanguage }).Count)
        Check "Source ISO language matches locale.uiLanguage ($($loc.uiLanguage))" $langOk "media: $(if ($isoLangs.Count) { $isoLangs -join ', ' } else { 'none listed' })$(if (-not $langOk) { " - download the ISO in your language, or set locale.uiLanguage in config\settings.local.json to the media's language" })"
    } elseif ($isAdmin) {
        Check "Source ISO language matches locale.uiLanguage ($($loc.uiLanguage))" $false "could not read the media's languages: $isoLangErr"
    } else {
        Write-Host "  [NOTE] Source ISO language and architecture not checked (mounting needs elevation: $isoLangErr); the build checks them." -ForegroundColor Yellow
    }
}
if ($EncryptAccountsTo) {
    # Protect-CmsMessage needs a Document Encryption certificate (EKU 1.3.6.1.4.1.311.80.1)
    $encCert = try { New-Object Security.Cryptography.X509Certificates.X509Certificate2 (Resolve-Path -LiteralPath $EncryptAccountsTo).Path } catch { $null }
    $encOk = $encCert -and @($encCert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' } | ForEach-Object { $_.EnhancedKeyUsages } | Where-Object Value -eq '1.3.6.1.4.1.311.80.1').Count -gt 0
    Check 'Certificate for encrypted passwords' ([bool]$encOk) $(if ($encCert) { "$($encCert.Subject), expires $($encCert.NotAfter.ToString('yyyy-MM-dd'))$(if (-not $encOk) { ': not a Document Encryption certificate' })" } else { "$EncryptAccountsTo not readable" })
}
# Only ISOs whose SHA-256 is accepted: the kit's list (config\source-iso.json) and your own
# (config\source-iso.local.json, untracked: an ISO in another language or a newer release
# is accepted there, without editing a file git tracks).
$isoCfg = Join-Path $KitRoot 'config\source-iso.json'
$isoLocalCfg = Join-Path $KitRoot 'config\source-iso.local.json'
$isoAccepted = @()
try { $isoAccepted = @((Get-Content -Raw -LiteralPath $isoCfg | ConvertFrom-Json).accepted | Where-Object { $_ -and $_.sha256 }) } catch { }
Check 'Source ISO hash list' ($isoAccepted.Count -gt 0) $isoCfg
if (Test-Path -LiteralPath $isoLocalCfg) {
    $isoLocalErr = $null; $isoLocal = @()
    try {
        $isoLocal = @((Get-Content -Raw -LiteralPath $isoLocalCfg | ConvertFrom-Json).accepted | Where-Object { $_ })
        foreach ($e in $isoLocal) { if ("$($e.sha256)" -notmatch '^[0-9A-Fa-f]{64}$') { throw "an entry's sha256 is not 64 hexadecimal characters: '$($e.sha256)'" } }
    } catch { $isoLocalErr = $_.Exception.Message }
    Check 'Your own source ISO list (config\source-iso.local.json)' (-not $isoLocalErr) $(if ($isoLocalErr) { "$isoLocalErr - expected: { `"accepted`": [ { `"file`": `"<name>.iso`", `"sha256`": `"<SHA-256>`" } ] }" } else { "$($isoLocal.Count) ISO(s)" })
    if (-not $isoLocalErr) { $isoAccepted += $isoLocal }
}
if ($SourceIso -and (Test-Path $SourceIso)) {
    Write-Host '  Hashing the source ISO (SHA-256, about a minute)...'
    $sourceSha = (Get-FileHash $SourceIso -Algorithm SHA256).Hash
    $known = @($isoAccepted | Where-Object { $_.sha256 -eq $sourceSha })
    Check 'Source ISO is an accepted, official release' ($known.Count -gt 0) $(if ($known.Count) { "$($known[0].file)$(if ($known[0].build) { " ($($known[0].build))" })" } else { "SHA-256 $sourceSha is in neither config\source-iso.json nor config\source-iso.local.json" })
    if (-not $known.Count) {
        Write-Host '         To accept this ISO:' -ForegroundColor Yellow
        Write-Host "         1. Compare the SHA-256 above with the one Microsoft lists for your language under 'Verify your download' on" -ForegroundColor Yellow
        Write-Host '            https://www.microsoft.com/software-download/windows11 . Not the same: the file is damaged or not Microsoft''s; download it again.' -ForegroundColor Yellow
        Write-Host "         2. The same: save this as $isoLocalCfg (git ignores that file)$(if (Test-Path -LiteralPath $isoLocalCfg) { '; it exists already: add the { ... } entry to its "accepted" list' }), then run the build again:" -ForegroundColor Yellow
        Write-Host "            { `"accepted`": [ { `"file`": `"$(Split-Path $SourceIso -Leaf)`", `"sha256`": `"$sourceSha`", `"verified`": `"$(Get-Date -Format 'yyyy-MM-dd'), against Microsoft's download page`" } ] }" -ForegroundColor Yellow
    }
}
# -File + exact extension: a '*.inf' filter also matches driver-store FOLDERS
# named 'xyz.inf_amd64_<hash>' (Win32 3-character-extension wildcard quirk).
$infCount = @(Get-ChildItem $DriverRoot -Recurse -File -Filter *.inf -ErrorAction SilentlyContinue | Where-Object Extension -eq '.inf').Count
Check 'Curated drivers' ($infCount -gt 0) "$DriverRoot ($infCount INF files)$(if (-not $infCount) { ': run Run-Harvest.cmd on the PC the image is for.' })"
if ($infCount) {
    # Every file the build would add, unchanged since the harvest (its SHA-256 manifest)
    $drvBad = @(Test-CuratedDrivers $DriverRoot "$($hw.drivers.skipInf)")
    Check 'Curated drivers unchanged since the harvest (SHA-256)' (-not $drvBad.Count) $(if ($drvBad.Count) { "$(@($drvBad | Select-Object -First 5) -join '; ')$(if ($drvBad.Count -gt 5) { "; ... ($($drvBad.Count) problems)" })" } else { "$(Join-Path $driverExport '_Reports\curated-sha256.txt')" })
    # Storage drivers also go into boot.wim (Windows PE and Windows Setup), as into WinRE
    $preSkip = "$($hw.drivers.skipInf)"
    $preStorage = @(Select-DriverInfByClass @(Get-ChildItem $DriverRoot -Recurse -File -Filter *.inf -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.inf' -and (-not $preSkip -or $_.Name -notmatch $preSkip) }) @('SCSIAdapter', 'HDC'))
    if ($preStorage.Count) { Write-Host "  [NOTE] The curated drivers include $($preStorage.Count) storage driver(s) (class SCSIAdapter or HDC: $(@($preStorage | ForEach-Object Name) -join ', ')). The build adds them to boot.wim too, so Setup will have them: needed on PCs whose disk controller has no driver in Windows." -ForegroundColor Yellow }
}
# The harvest records the profile it curated for; a different one here is allowed but noted
$harvestProf = Join-Path (Split-Path $DriverRoot -Parent) '_Reports\harvest-profile.json'
if (Test-Path -LiteralPath $harvestProf) {
    $hp = try { [IO.File]::ReadAllText($harvestProf) | ConvertFrom-Json } catch { $null }
    if ($hp -and $hp.id -ne $hw.id) { Write-Host "  [NOTE] The drivers were curated for profile '$($hp.id)', this build is for '$($hw.id)': re-run Run-Harvest.cmd -CurateOnly -Profile $($hw.id) if that is not intended." -ForegroundColor Yellow }
}
# productKey 'firmware' on the PC it targets: its firmware key must be a Pro key,
# or Setup can't use it for this Pro-only image (a Home OEM key plus a Pro licence
# bought later is the common case: that needs 'generic').
if ($hw.productKey -eq 'firmware' -and $prof.FitsPc -eq $true) {
    $oemDesc = "$((Get-CimInstance SoftwareLicensingService -ErrorAction SilentlyContinue).OA3xOriginalProductKeyDescription)"
    Check "Firmware key is a Pro key (profile productKey 'firmware')" ($oemDesc -match 'Professional') $(if ($oemDesc) { "$oemDesc - use productKey 'generic' (activation from the PC's Pro digital licence)" } else { "no firmware key - use productKey 'generic'" })
}
$lcuFiles = @(Get-Packages 'lcu' '*.msu')
# Missing: Run-Build.cmd offers the download before the build (scripts\Invoke-KitLauncher.ps1)
$getUpdates = "run Run-Build.cmd again (without -Preflight) and answer Y to fetch them, or: py scripts\Get-Updates.py --dest $UpdatesRoot"
Check 'Cumulative update' ($lcuFiles.Count -gt 0) $(if ($lcuFiles.Count) { ($lcuFiles | ForEach-Object Name) -join ', ' } else { "none in $UpdatesRoot\lcu: $getUpdates." })
$pkgCount = @(Get-Packages 'dotnet' '*.msu').Count
Check '.NET update' ($pkgCount -gt 0) $(if ($pkgCount) { "$UpdatesRoot\dotnet" } else { "none in $UpdatesRoot\dotnet: $getUpdates" })
$pkgCount = @(Get-Packages 'safeos' '*.cab').Count
Check 'Safe OS updates' ($pkgCount -gt 0) $(if ($pkgCount) { "$UpdatesRoot\safeos" } else { "none in $UpdatesRoot\safeos: $getUpdates" })
# The build applies only Update Catalog files: their names carry the file's SHA-1, which
# the build checks again right before applying each one
$noSha = @(foreach ($sub in 'lcu', 'dotnet', 'safeos', 'setup') { foreach ($f in @(Get-Packages $sub $(if ($sub -in 'lcu', 'dotnet') { '*.msu' } else { '*.cab' }))) { if ($f.Name -notmatch '_[0-9a-fA-F]{40}\.(msu|cab)$') { "$sub\$($f.Name)" } } })
Check 'Update files named as in the Update Catalog (<kb>_<SHA-1>)' (-not $noSha.Count) $(if ($noSha.Count) { "$($noSha -join ', '): not a catalog file name; delete it and fetch the updates again ($getUpdates)" } else { $UpdatesRoot })
# Present but not the ones config\updates.json pins (e.g. last month's): noted, not refused
try {
    $updCfg = [IO.File]::ReadAllText((Join-Path $KitRoot 'config\updates.json')) | ConvertFrom-Json
    $updOff = @(foreach ($fo in $updCfg.updates.PSObject.Properties) {
        $have = @(Get-ChildItem -LiteralPath (Join-Path $UpdatesRoot $fo.Name) -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.msu', '.cab' } | ForEach-Object Name)
        foreach ($kb in @($fo.Value | Where-Object { $_ })) { if (-not @($have | Where-Object { $_ -match [regex]::Escape($kb) }).Count) { "$($fo.Name)\$kb missing" } }
        foreach ($h in $have) { if (-not @($fo.Value | Where-Object { $_ -and $h -match [regex]::Escape($_) }).Count) { "$($fo.Name)\$h not pinned" } }
    })
    if ($updOff.Count -and $lcuFiles.Count) { Write-Host "  [NOTE] The updates differ from config\updates.json ($($updOff -join ', ')): $getUpdates" -ForegroundColor Yellow }
    # How old the pins are ('pinned': the day they were last moved). Microsoft releases new
    # updates every month; Run-Build.cmd asks before building with pins older than 70 days.
    $pinAge = try { [int]((Get-Date).Date - [datetime]::ParseExact("$($updCfg.pinned)", 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).TotalDays } catch { $null }
    $newPins = "Newer pins: update the kit (Run-Build.cmd, first question), or move them yourself: py scripts\Get-Updates.py --discover --write, then build again (Run-Build.cmd downloads them)."
    if ($null -eq $pinAge) { Write-Host "  [NOTE] config\updates.json has no 'pinned' date (yyyy-MM-dd), so the age of the update pins is not known." -ForegroundColor Yellow }
    elseif ($pinAge -gt 70) { Write-Host "  [WARN] The update pins (config\updates.json) are $pinAge days old (pinned $($updCfg.pinned)): Microsoft has released newer Windows updates since, and this image will start out that far behind. $newPins" -ForegroundColor Yellow }
    elseif ($pinAge -gt 35) { Write-Host "  [NOTE] The update pins (config\updates.json) are $pinAge days old (pinned $($updCfg.pinned)): newer Windows updates are probably out. $newPins" -ForegroundColor Yellow }
} catch { }
# Microsoft's security baselines. The kit holds only the pins (config\baselines\baselines.json
# and one source.json per baseline: the official zip's name, URL and SHA-256, the GPOs to
# apply); the zips are in <work>\baselines (scripts\Get-Baselines.py; Run-Build.cmd offers
# the download), each checked here against its pin. The build then imports every zip
# (scripts\Import-Baseline.py, below) and stages that data, so the data in the image always
# comes from a file with the pinned hash, whatever was in the folder before.
$blPins = Join-Path $KitRoot 'config\baselines'
$blWork = Join-Path $WorkRoot 'baselines'
$blIds = @(try { @(([IO.File]::ReadAllText((Join-Path $blPins 'baselines.json')) | ConvertFrom-Json).apply | Where-Object { $_ }) } catch { })
Check 'Security baselines listed (config\baselines\baselines.json)' ($blIds.Count -gt 0) ($blIds -join ', ')
$getBaselines = "py scripts\Get-Baselines.py --dest $blWork"
$blList = New-Object System.Collections.Generic.List[object]
$blToImport = New-Object System.Collections.Generic.List[string]
foreach ($id in $blIds) {
    $blSrc = $null; $blErr = $null
    try {
        if ("$id" -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw 'an id is lower-case letters, digits, dots and hyphens' }
        $blSrc = [IO.File]::ReadAllText((Join-Path $blPins "$id\source.json")) | ConvertFrom-Json
        if ("$($blSrc.sha256)" -notmatch '^[0-9A-Fa-f]{64}$') { throw "source.json: 'sha256' is not 64 hexadecimal characters" }
        if ("$($blSrc.file)" -notmatch '^[^\\/:*?"<>|]+\.zip$') { throw "source.json: 'file' is not a plain .zip file name" }
        if (-not @($blSrc.gpos | Where-Object { $_ }).Count) { throw "source.json: no 'gpos'" }
    } catch { $blErr = $_.Exception.Message }
    Check "Security baseline pins: config\baselines\$id\source.json" (-not $blErr) $(if ($blErr) { $blErr } else { "$($blSrc.name)" })
    if ($blErr) { continue }
    $bl = [pscustomobject]@{ Id = "$id"; Name = "$($blSrc.name)"; File = "$($blSrc.file)"; Sha256 = "$($blSrc.sha256)".ToLowerInvariant(); Gpos = @($blSrc.gpos | ForEach-Object { "$_" })
                             Zip = (Join-Path $blWork "$($blSrc.file)"); Dir = (Join-Path $blWork "$id") }
    $blPage = if ($blSrc.page) { "$($blSrc.page)" } else { 'https://www.microsoft.com/en-us/download/details.aspx?id=55319' }
    $blHelp = "Run Run-Build.cmd again (without -Preflight) and answer Y to download it, or: $getBaselines . If Microsoft no longer serves this file (it replaces baseline files in place): update the kit (Run-Build.cmd, first question) for newer pins, or use a copy of the pinned zip you already have: $getBaselines --zip `"<path to the zip>`" . Microsoft's download page: $blPage"
    $zipSha = if (Test-Path -LiteralPath $bl.Zip -PathType Leaf) { (Get-FileHash -LiteralPath $bl.Zip -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    $zipOk = $zipSha -eq $bl.Sha256
    Check "Security baseline zip: $($bl.File)" $zipOk $(if ($zipOk) { "$($bl.Zip) (SHA-256 as pinned: $($bl.Sha256.Substring(0, 12))...)" } elseif ($zipSha) { "$($bl.Zip) has SHA-256 $zipSha, not the pinned $($bl.Sha256): not the file this kit pins (damaged, or another release; the download replaces it). $blHelp" } else { "not in ${blWork}. $blHelp" })
    if (-not $zipOk) { continue }
    $blList.Add($bl)
    $blWhy = Test-BaselineData $bl
    if ($blWhy) { $blToImport.Add("$id ($blWhy)") }
}
if ($blIds.Count -and $blList.Count -eq $blIds.Count) {
    if ($blToImport.Count) { Write-Host "  [NOTE] Security baseline data in ${blWork}: $($blToImport -join '; '). The build imports it from the zip$(if ($blList.Count -gt 1) { 's' }) (scripts\Import-Baseline.py)." -ForegroundColor Yellow }
    else { Check 'Security baseline data imported' $true "$(@($blList | ForEach-Object { $_.Dir }) -join ', ') (each matches its index.json and the pinned zip; the build imports it again)" }
}
foreach ($f in 'config\autounattend.xml', 'config\settings.defaults.json', 'scripts\Set-KitRegistry.ps1', 'config\removal-manifest.json', 'config\image.json', 'config\LayoutModification.json',
               'config\wslconfig', 'config\baseline-overrides.txt', 'config\baseline-overrides.inf', 'config\baseline-overrides-audit.csv', 'payload\PostInstall.ps1',
               'payload\Test-InstalledPc.ps1', 'payload\Enable-BitLockerLocal.ps1', 'payload\Enable-BitLocker.cmd', 'payload\Validate-Pc.cmd',
               'payload\Merge-AuditPolicy.ps1', 'payload\New-AdminBrowserPolicy.ps1', 'payload\Apply-Policy.ps1', 'payload\Invoke-ScheduledValidation.ps1') {
    Check $f (Test-Path (Join-Path $KitRoot $f)) ''
}
try { $null = [xml](Get-Content -Raw (Join-Path $KitRoot 'config\autounattend.xml')); $tplOk = $true } catch { $tplOk = $false }
Check 'autounattend template is valid XML' $tplOk ''
# Features and required apps: one list for the build and every checker
try { $imageCfg = Get-Content -Raw (Join-Path $KitRoot 'config\image.json') | ConvertFrom-Json; $imgOk = [bool]@($imageCfg.features.enable).Count } catch { $imgOk = $false }
Check 'config\image.json is valid (features.enable listed)' $imgOk ''
# The files the settings change when they are staged: tried here, so a problem stops the
# build before anything is serviced (placeholder names stand in for a per-build pair)
try {
    $null = ConvertTo-StagedOverridesInf ([IO.File]::ReadAllText((Join-Path $KitRoot 'config\baseline-overrides.inf'))) 'PlaceholderA' 'PlaceholderG' $optGaming
    $null = ConvertTo-StagedStartLayout ([IO.File]::ReadAllText((Join-Path $KitRoot 'config\LayoutModification.json'))) $optGaming @($imageCfg.gamingApps)
    $stageOk = $true; $stageErr = ''
} catch { $stageOk = $false; $stageErr = $_.Exception.Message }
Check 'Security template and Start layout can be staged for these settings' $stageOk $stageErr
foreach ($f in 'scripts\Test-OfflineImage.ps1', 'scripts\Install-BuildTools.ps1', 'scripts\Import-Baseline.py', 'scripts\kitfetch.py') { Check $f (Test-Path (Join-Path $KitRoot $f)) '' }
# Defender Controlled Folder Access blocks DISM's writes to the mounted image
$mpp = try { Get-MpPreference } catch { $null }
$cfa = $mpp.EnableControlledFolderAccess
Check 'Defender Controlled Folder Access off on this build PC' ($cfa -ne 1) "EnableControlledFolderAccess=$cfa (it blocks DISM while servicing)"
# ASR "copied or impersonated system tools" (not in the Microsoft baseline) blocks
# poqexec.exe running from the mounted image: Add-WindowsPackage 0x80070005.
$asrIds = @($mpp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() })
$ci = [array]::IndexOf($asrIds, 'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb')
$copiedAct = if ($ci -ge 0) { @($mpp.AttackSurfaceReductionRules_Actions)[$ci] } else { 0 }
if ($copiedAct -in 1, 6) { Write-Host "  [NOTE] Defender ASR 'copied system tools' rule is on (action $copiedAct): the build excludes its DISM work folders while it runs." -ForegroundColor Yellow }
foreach ($n in $staleNotes) { Write-Host "  [NOTE] $n" -ForegroundColor Yellow }
if ($lockNote) { Write-Host "  [NOTE] Build folders writable by administrators only: $lockNote" -ForegroundColor Yellow }
else { Check 'Build folders writable by administrators only' $true "$KitRoot, $WorkRoot, $driverExport" }
# Will this PC's firmware start the stick? The media's boot manager is signed with Microsoft's
# "Windows UEFI CA 2023" certificate; a firmware whose Secure Boot database (db) lacks it shows
# a Secure Boot violation instead. Told now, while the PC still runs.
if (-not $Use2011BootManager) {
    $otherPc = $(if ($prof.FitsPc -eq $false) { ' (This build is for another PC: check that one, in an administrator PowerShell: [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).Bytes) -match ''Windows UEFI CA 2023''.)' } else { '' })
    try {
        $sbDbText = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db -ErrorAction Stop).Bytes)
        if ($sbDbText -match 'Windows UEFI CA 2023') { Check 'This PC''s firmware trusts the stick''s boot manager (Windows UEFI CA 2023)' $true "in the Secure Boot database$otherPc" }
        else { Write-Host "  [NOTE] This PC's firmware does not trust the 2023 certificate the stick's boot manager is signed with: with Secure Boot on, the stick will not start here (Secure Boot violation). Before reinstalling: update the BIOS from the PC maker's site, or let Windows add the certificate (docs\TROUBLESHOOTING.md, 'Secure Boot violation'), then run the pre-flight again. -Use2011BootManager builds media this firmware starts today; Microsoft's 2011 certificate behind it is valid only until 2026-10-19.$otherPc" -ForegroundColor Yellow }
    } catch { Write-Host "  [NOTE] Could not read this PC's Secure Boot database ($($_.Exception.Message)): whether its firmware starts a stick signed with Windows UEFI CA 2023 is not known. A PC without UEFI Secure Boot (or with it off) starts the stick either way.$otherPc" -ForegroundColor Yellow }
} else { Write-Host '  [NOTE] -Use2011BootManager: the media is signed with Microsoft''s 2011 certificate, which is valid only until 2026-10-19: Microsoft signs no new boot managers with it after that, and a PC that has revoked it will not start this stick.' -ForegroundColor Yellow }
# Free space for the build itself, on top of its inputs already on the PC (source ISO,
# updates, drivers): the copied media (~8 GB), the exported and mounted image with the
# servicing scratch (~25 GB at the peak), and the ISO (~10 GB). A real build also carries
# the build inputs (~15-20 GB, inside the media) and its ISO grows by as much (~28 GB).
$needGb = if ($withInputs) { 80 } else { 40 }
$freeGb = [math]::Round((Get-PSDrive ($WorkRoot.Substring(0, 1))).Free / 1GB)
Check 'Free space' ($freeGb -ge $needGb) "$freeGb GB on $($WorkRoot.Substring(0,2)) (need $needGb$(if ($withInputs) { ' with the build inputs; 40 for a -TestBuild or with -NoBuildInputs' }))"
$oscdimg = Find-Oscdimg
$adkLocal = Join-Path $WorkRoot 'tools\adksetup.exe'
if ($oscdimg) { Check 'ISO tool (oscdimg)' $true $oscdimg }
else { Write-Host "  [NOTE] ISO tool (oscdimg) not installed yet: the build installs Windows ADK Deployment Tools first$(if (Test-Path $adkLocal) { ' from ' + $adkLocal } else { ' (download from Microsoft)' })." -ForegroundColor Yellow }
# The build tools (Git, Python, ADK) are installed on demand (Run-Prepare.cmd), never in the image
$buildTools = @{}
foreach ($t in @(Invoke-KitScript 'scripts\Install-BuildTools.ps1' @{ KitRoot = $KitRoot; WorkRoot = $WorkRoot; Tools = @('git', 'python', 'adk'); Check = $true; PassThru = $true })) { $buildTools[$t.Tool] = $t }
# Python 3 runs the baseline importer in this build (and the download scripts before it)
$pyExe = if ($buildTools.python -and $buildTools.python.State -eq 'OK') { "$($buildTools.python.Path)" } else { '' }
Check 'Python 3 (the build imports the security baselines with it)' ([bool]$pyExe) $(if ($pyExe) { "$pyExe $($buildTools.python.Version)" } else { "not installed$(if ($buildTools.python.Detail) { " ($($buildTools.python.Detail))" }): run Run-Prepare.cmd (it installs Python 3), or Run-Build.cmd without -Preflight (it offers to)" })
if ($withInputs) {
    Check 'Build inputs: DriverExport.zip + .sha256' ((Test-Path $driverZip) -and (Test-Path "$driverZip.sha256")) $driverZip
    $instCfg = Join-Path $KitRoot 'config\installers.json'
    foreach ($i in @((Get-Content -Raw $instCfg | ConvertFrom-Json).installers)) {
        $f = Join-Path $WorkRoot "installers\$($i.file)"
        $ok = (Test-Path $f) -and (Get-FileHash $f -Algorithm SHA256).Hash -eq $i.sha256.ToUpper()
        Check "Build inputs: installer $($i.file)" $ok $(if ($ok) { 'SHA-256 OK' } else { "missing or wrong hash: run Run-Build.cmd again (without -Preflight) and answer Y to fetch it, or: py scripts\Get-Installers.py --dest $WorkRoot\installers" })
    }
    $gitExe = @((Get-Command git.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\Git\cmd\git.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    $gitOk = $false
    if ($gitExe -and (Test-Path (Join-Path $KitRoot '.git'))) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $null = & $gitExe -c $gitSafeDir -C $KitRoot rev-parse HEAD 2>&1; $gitOk = $LASTEXITCODE -eq 0 } finally { $ErrorActionPreference = $old }
    }
    $gitDetail = if (-not $gitExe) { 'Git for Windows is not installed: run Run-Prepare.cmd (it installs the build tools), or build with -NoBuildInputs' }
                 elseif (-not (Test-Path (Join-Path $KitRoot '.git'))) { "$KitRoot is not a Git clone (downloaded as a ZIP?): clone it with git clone <url> C:\W11Kit and build from there, or build with -NoBuildInputs (then the ISO can't rebuild itself after the reinstall)" }
                 elseif (-not $gitOk) { "$gitExe can't read the clone in $KitRoot (git -C $KitRoot status says why), or build with -NoBuildInputs" }
                 else { "$gitExe $KitRoot" }
    Check 'Build inputs: git can read the kit (for the bundle)' $gitOk $gitDetail
    if ($gitOk) {
        # The bundle holds commits only: uncommitted edits to the kit's tracked files would be
        # missing when the reinstalled PC rebuilds itself (changed profile.json files are carried)
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $dirty = @(& $gitExe -c $gitSafeDir -C $KitRoot status --porcelain --untracked-files=no 2>$null | Where-Object { $_ -and $_.Substring(3) -notmatch '^profiles/[^/]+/profile\.json$' } | ForEach-Object { $_.Substring(3) }) } finally { $ErrorActionPreference = $old }
        if ($dirty.Count) { Write-Host "  [NOTE] Not committed, so not in the kit bundle the ISO carries: $($dirty -join ', '). Commit them (from an administrator terminal) if the reinstalled PC should rebuild with them." -ForegroundColor Yellow }
    }
}
if ($problems.Count) { throw "Pre-flight failed: $($problems.Count) problem(s) above. Nothing was changed." }
if ($Preflight) { Write-Host 'Pre-flight passed. Nothing was changed.' -ForegroundColor Green; return }

# --- 0. Security baselines: imported from the pinned zips ----------------------
# Every build imports again (seconds, no download): what is staged below then comes from
# zips whose SHA-256 was checked a moment ago, not from files that were lying in the work
# folder. -I -B: Python ignores the environment and the user's site folder, and writes
# no bytecode into the kit. The importer stops at a zip with another hash.
Write-Host "Importing Microsoft's security baselines from the pinned zips (scripts\Import-Baseline.py):" -ForegroundColor Cyan
foreach ($bl in $blList) {
    $pyArgs = @(if ((Split-Path -Leaf $pyExe) -ieq 'py.exe') { '-3' }) + @('-I', '-B', (Join-Path $KitRoot 'scripts\Import-Baseline.py'), $bl.Id, '--dest', $blWork, '--no-download', '--quiet')
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # native stderr under 'Stop' would be terminating
    try { $pyOut = @(& $pyExe @pyArgs 2>&1 | ForEach-Object { "$_" }); $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    foreach ($line in $pyOut) { Write-Host "  $($line.Trim())" }
    if ($rc -ne 0) { throw "Importing the security baseline $($bl.Id) from $($bl.Zip) failed (exit code $rc, see above). Nothing was built." }
    $blWhy = Test-BaselineData $bl
    if ($blWhy) { throw "The security baseline data in $($bl.Dir) is not right after the import: $blWhy. Nothing was built." }
}

if (-not $oscdimg) {
    Install-AdkDeploymentTools
    $oscdimg = Find-Oscdimg
    if (-not $oscdimg) { throw 'oscdimg.exe still not found after installing the ADK Deployment Tools.' }
    Write-Host "ISO tool installed: $oscdimg"
}

function ConvertTo-UnattendPassword([string]$Name, [string]$pa) {
    if (-not $pa) { throw "An empty password is not allowed for $Name." }
    # Password policy after the overrides (baseline-overrides.inf): minimum 11
    # characters (baseline: 14), complexity (3 of: upper, lower, digit, symbol),
    # and no account name inside it.
    $classes = @('[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]' | Where-Object { $pa -cmatch $_ }).Count
    if ($pa.Length -lt 11 -or $classes -lt 3 -or $pa -match [regex]::Escape($Name)) {
        throw "Password for $Name does not meet the password policy: 11+ characters, 3 of upper/lower/digit/symbol, must not contain the account name."
    }
    # Unattend "PlainText=false" encoding: Base64(UTF-16LE(password + "Password")). Obfuscation only.
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($pa + 'Password'))
}
# Generated account passwords: 20 characters, each drawn uniformly from 52 letters and
# digits (rejection sampling on the OS cryptographic RNG: no modulo bias). Left out: the
# look-alikes 0 O o 1 l I, and Y y Z z, which swap places on a German (QWERTZ) keyboard;
# no symbols, whose keys differ between layouts. 52^20 = about 114 bits. The password
# policy (11+ characters, 3 of upper/lower/digit/symbol, not the account name) is met by
# drawing the WHOLE password again until it has an upper-case letter, a lower-case letter
# and a digit and doesn't contain the account name: that keeps every valid password equally
# likely (uniform over the valid set; about 3.5 % of draws lack a digit, so the valid set
# is 96.5 % of 52^20: 113.95 bits). They only have to survive until first sign-in, where
# both accounts must choose new ones.
function New-AccountPassword([string]$AccountName, [int]$Length = 20) {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWX' + 'abcdefghijkmnpqrstuvwx' + '23456789'   # 22 + 22 + 8 = 52
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] 4
    $n = [uint32]$alphabet.Length
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % $n)   # largest multiple of n: no modulo bias
    try {
        do {
            $c = New-Object char[] $Length
            for ($i = 0; $i -lt $Length; $i++) {
                do { $rng.GetBytes($buf); $v = [BitConverter]::ToUInt32($buf, 0) } while ($v -ge $limit)
                $c[$i] = $alphabet[[int]($v % $n)]
            }
            $pw = -join $c
        } while ($pw -cnotmatch '[A-Z]' -or $pw -cnotmatch '[a-z]' -or $pw -cnotmatch '[0-9]' -or ($AccountName -and $pw -match [regex]::Escape($AccountName)))
        $pw
    } finally { $rng.Dispose() }
}

# The accounts file, readable by SYSTEM and Administrators only FROM ITS CREATION: the
# FileSecurity is part of the create call (no moment with the folder's inherited ACL), and
# CreateNew refuses a file that is already there. Owner Administrators.
function New-AccountsFile([string]$Path, [string]$Text) {
    $sec = New-Object Security.AccessControl.FileSecurity
    $sec.SetSecurityDescriptorSddlForm('O:BAD:PAI(A;;FA;;;SY)(A;;FA;;;BA)')
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::None, $sec)
    try { $b = [Text.Encoding]::ASCII.GetBytes($Text); $fs.Write($b, 0, $b.Length) } finally { $fs.Dispose() }
}

Write-Host "Two local accounts are created: $AdminName (administrator: installs/elevation only) and $UserName (standard, daily)."
# This build's names for the built-in Administrator and Guest accounts: never one of the
# other names in the image. Not secrets (any account on the PC can list them).
$nameAvoid = @((Get-KitReservedAccountNames) + @($AdminName, $UserName, $builtinAdmin, $builtinGuest, $ComputerName) | Where-Object { $_ })
if (-not $builtinAdmin) { $builtinAdmin = New-KitBuiltinAccountName $nameAvoid; $nameAvoid += $builtinAdmin }
if (-not $builtinGuest) { $builtinGuest = New-KitBuiltinAccountName $nameAvoid }
foreach ($bn in $builtinAdmin, $builtinGuest) {
    $bad = Get-KitAccountNameProblem $bn
    if ($bad -or $bn -in $AdminName, $UserName, $ComputerName) { throw "The new name for a built-in account can't be used: $(if ($bad) { $bad } else { "'$bn' is also a kit account or the computer name" })" }
}
if ($builtinAdmin -eq $builtinGuest) { throw 'The new names of the built-in Administrator and Guest accounts must differ.' }
Write-Host "The built-in Administrator account is renamed $builtinAdmin and the built-in Guest account $builtinGuest$(if ($builtinGenerated.Count) { " (drawn for this build: $($builtinGenerated -join ', '))" } else { ' (from your settings)' }); both stay disabled."
# The build's stamp: in the ISO's name and in the accounts file (which ISO they belong to)
$buildStart = Get-Date
$stamp = $buildStart.ToString('yyyyMMdd-HHmmss')
$accountsFile = $null; $accountsPrev = $null; $OutputIso = $null
$adminPw = New-AccountPassword $AdminName; $userPw = New-AccountPassword $UserName
$adminPwB64 = ConvertTo-UnattendPassword $AdminName $adminPw
$userPwB64 = ConvertTo-UnattendPassword $UserName $userPw
if (-not (Test-Path -LiteralPath $WorkRoot)) { New-KitLockedFolder $WorkRoot }
# Test builds never touch a real build's file; a real build keeps the previous one
# (renamed, same ACL) so a rebuild can't lose passwords that weren't copied off yet.
$accountsFile = Join-Path $WorkRoot $(if ($TestBuild) { 'test-accounts.txt' } else { 'accounts.txt' })
if ($EncryptAccountsTo) { $accountsFile += '.cms' }   # encrypted: never a plain-text copy
if (Test-Path -LiteralPath $accountsFile) {
    if ($TestBuild) { Remove-Item -LiteralPath $accountsFile -Force }
    else {
        $accountsPrev = Join-Path $WorkRoot ('accounts-{0:yyyyMMdd-HHmmss}{1}' -f (Get-Item -LiteralPath $accountsFile).LastWriteTime, $(if ($EncryptAccountsTo) { '.txt.cms' } else { '.txt' }))
        Rename-Item -LiteralPath $accountsFile $accountsPrev
    }
}
$lines = @("$($hw.displayName) image accounts (profile $($hw.id)), build $stamp, generated $(Get-Date -Format 's')$(if ($TestBuild) { ' (TEST build: VM only)' })",
  'One-time passwords: both accounts must choose a new one at first sign-in.',
  "They belong ONLY to the ISO named on the last line of this file (Win11Pro-...-$stamp.iso), added when the build finishes. No such line: that build failed and these passwords are in no ISO.",
  'Copy them off this PC (a password manager you can open on another device, or paper) before installing the ISO on it (reinstalling wipes C:), then delete this file.',
  '', "$AdminName  $adminPw", "$UserName  $userPw")
try {
    # CMS (PKCS#7) to the owner's certificate: only its private key decrypts it
    $text = if ($EncryptAccountsTo) { Protect-CmsMessage -Content ($lines -join "`r`n") -To $EncryptAccountsTo } else { $lines -join "`r`n" }
    New-AccountsFile $accountsFile ((@($text) -join "`r`n").TrimEnd() + "`r`n")
} catch {
    if ($accountsPrev) { Rename-Item -LiteralPath $accountsPrev (Split-Path $accountsFile -Leaf) -ErrorAction SilentlyContinue }
    throw "Could not write $accountsFile ($($_.Exception.Message)); no passwords were written."
} finally { $text = $null; $lines = $null }
$adminPw = $null; $userPw = $null
Write-Host "Generated passwords for $AdminName / $UserName are in $accountsFile (admins only$(if ($EncryptAccountsTo) { '; encrypted: Unprotect-CmsMessage -Path <file>' }))." -ForegroundColor Yellow

$media = Join-Path $WorkRoot 'media'
$mount = Join-Path $WorkRoot 'mount'
$reMount = Join-Path $WorkRoot 'mount-re'
$bootMount = Join-Path $WorkRoot 'mount-boot'
$scratch = Join-Path $WorkRoot 'scratch'
$logs = Join-Path $WorkRoot 'logs'
# Work files next to them; a failed build deletes them (the catch below)
$work = Join-Path $WorkRoot 'install.wim'
$reWork = Join-Path $WorkRoot 'winre.wim'
$reOut = Join-Path $WorkRoot 'winre-export.wim'
$bootOut = Join-Path $WorkRoot 'boot-export.wim'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

# Kit revision, recorded in the manifest and shown by PostInstall: the git
# commit when the kit is a checkout, otherwise the build stamp only.
$kitRevision = "build-$stamp"
$gitHead = Join-Path $KitRoot '.git\HEAD'
if (Test-Path -LiteralPath $gitHead) {
    $head = (Get-Content -LiteralPath $gitHead -TotalCount 1).Trim()
    if ($head -match '^ref: (.+)$') {
        $refFile = Join-Path $KitRoot ('.git\' + ($Matches[1] -replace '/', '\'))
        $head = if (Test-Path -LiteralPath $refFile) { (Get-Content -LiteralPath $refFile -TotalCount 1).Trim() } else { '' }
    }
    if ($head -match '^[0-9a-f]{40}$') { $kitRevision += " (git $($head.Substring(0, 7)))" }
}

$manifest = [ordered]@{ built = (Get-Date).ToString('s'); kitRevision = $kitRevision; profile = $hw.id; profileName = $hw.displayName; testBuild = [bool]$TestBuild; sourceIso = $SourceIso; updates = @(); drivers = @(); removed = @(); skipped = @() }
# The effective settings (the files' values + the kit's defaults), as staged in the image
$manifest.settings = $kitSettings
$manifest.settingsSource = [ordered]@{ defaults = $ks.DefaultsPath; file = $ks.OverlayPath; fromFile = $ks.FromFile; localeFrom = $ks.Sources; thisPcReadAs = $ks.ThisPcAccount }
$manifest.computerName = $(if ($ComputerName) { [ordered]@{ name = $ComputerName; from = $nameSource } } else { $null })
$manifest.builtinAccounts = [ordered]@{ administrator = $builtinAdmin; guest = $builtinGuest; drawnForThisBuild = $builtinGenerated }

$asrAdded = $false
$transcribing = $false
try {
    # Inside the try: a failure or Ctrl+C from here on still runs finally
    # (exclusions removed, transcript stopped).
    # Old logs go: DISM's are large (tens of MB a build), and only recent ones get read.
    # 30 days covers the last monthly build; nothing but this folder's own files is touched.
    Get-ChildItem -LiteralPath $logs -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Transcript -Path (Join-Path $logs "build-$stamp.txt") | Out-Null
    $transcribing = $true
    # No sleep while the build runs (this thread's request ends with it; no setting changed)
    if (-not ('W11Kit.Awake' -as [type])) { Add-Type -Namespace W11Kit -Name Awake -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);' }
    $null = [W11Kit.Awake]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED

    # Fresh work folders (inside the try: a failure here still cleans up the accounts file)
    Clear-BuildState @($mount, $reMount, $bootMount)
    foreach ($d in $media, $mount, $reMount, $bootMount, $scratch) {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force }
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    # Defender's ransomware protection (on in the kit's image) blocks DISM: paused only with
    # -PauseDefenderProtection, which Run-Build.cmd passes after the user agreed, and restored in finally
    $defMarker = Join-Path $WorkRoot 'defender-paused.json'
    Restore-DefenderProtection $defMarker   # a killed build's pause
    $defNow = Get-DefenderProtection
    if ($defNow.cfa -eq 1 -or $defNow.prevalence -eq 1) {
        if (-not $PauseDefenderProtection) { throw "Defender's Controlled Folder Access or ASR prevalence rule is on (they block the build's DISM work). Run-Build.cmd asks before pausing them for the build; started directly, pass -PauseDefenderProtection." }
        [IO.File]::WriteAllText($defMarker, ($defNow | ConvertTo-Json -Compress))
        $defPaused = $true   # before the change: finally restores whatever part of it got in
        if ($defNow.cfa -eq 1) { Set-MpPreference -EnableControlledFolderAccess Disabled -ErrorAction Stop }
        if ($defNow.prevalence -eq 1) { Add-MpPreference -AttackSurfaceReductionRules_Ids '01443614-cd74-433a-b99e-2ecdc07bfc25' -AttackSurfaceReductionRules_Actions AuditMode -ErrorAction Stop }
        Write-Host "Defender protection paused for this build (Controlled Folder Access, ASR prevalence rule); restored when the build ends." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }

    # ASR "copied or impersonated system tools" (the image itself turns this rule on)
    # blocks the servicing stack (poqexec.exe) running from the mounted image. The
    # build excludes ONLY its own work folders, only while it runs: added here,
    # removed in finally, so the rule stays on for everything else.
    if ($copiedAct -in 1, 6) {
        $asrAdded = $true   # before the call: finally removes whatever part of it got in
        Add-MpPreference -AttackSurfaceReductionOnlyExclusions $asrExcl
        Start-Sleep -Seconds 15   # exclusions apply a few seconds after Defender logs them (event 5007)
    }

    # --- 1. Media ------------------------------------------------------------
    Step "Copying $SourceIso"
    $manifest.sourceIsoSha256 = $sourceSha
    # Reuse the ISO if it is already mounted (e.g. double-clicked in Explorer)
    $img = Get-DiskImage -ImagePath $SourceIso
    $weMounted = -not $img.Attached
    if ($weMounted) { $img = Mount-DiskImage -ImagePath $SourceIso -PassThru }
    try {
        $letter = $null
        for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
            $letter = (Get-DiskImage -ImagePath $SourceIso | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if (-not $letter) { Start-Sleep -Seconds 1 }
        }
        if (-not $letter) { throw "The ISO mounted but has no drive letter." }
        & robocopy.exe "$($letter):\" $media /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    } finally { if ($weMounted) { Dismount-DiskImage -ImagePath $SourceIso | Out-Null } }
    Get-ChildItem $media -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    # --- 2. Pro index --------------------------------------------------------
    Step 'Selecting Windows 11 Pro'
    $srcWim = @("$media\sources\install.wim", "$media\sources\install.esd") | Where-Object { Test-Path $_ } | Select-Object -First 1
    $pro = Get-WindowsImage -ImagePath $srcWim | ForEach-Object { Get-WindowsImage -ImagePath $srcWim -Index $_.ImageIndex } |
        Where-Object { $_.EditionId -eq 'Professional' } | Select-Object -First 1
    if (-not $pro) { throw 'No Professional edition in this ISO.' }
    # DISM's architecture number: 9 = x64 (12 = ARM64, 0 = x86)
    if ([int]$pro.Architecture -ne 9) { throw "The Windows 11 Pro image in this ISO is not x64 (DISM architecture $($pro.Architecture)$(if ([int]$pro.Architecture -eq 12) { ', ARM64' })): the kit builds x64 images only." }
    # Same check as the pre-flight (media languages), on the image itself
    $proLangs = @($pro.Languages | ForEach-Object { ("$_" -split ' ')[0] })
    if ($proLangs.Count -and $proLangs -notcontains $loc.uiLanguage) {
        throw "The Pro image's language is $($proLangs -join ', '), but settings locale.uiLanguage is $($loc.uiLanguage): use an ISO in that language or change the setting."
    }
    Write-Host "Using index $($pro.ImageIndex): $($pro.ImageName) $($pro.Version)"
    $manifest.baseImage = "$($pro.ImageName) $($pro.Version)"
    foreach ($f in $work, $reWork, $reOut, $bootOut) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }   # an export into an existing file would APPEND
    # -CheckIntegrity: the new file gets an integrity table, which every later save, export and split checks
    Export-WindowsImage -SourceImagePath $srcWim -SourceIndex $pro.ImageIndex -DestinationImagePath $work -CompressionType max -CheckIntegrity | Out-Null
    Remove-Item $srcWim -Force

    Step 'Mounting install image'
    Mount-WindowsImage -ImagePath $work -Index 1 -Path $mount -ScratchDirectory $scratch | Out-Null

    # --- 3. Updates ----------------------------------------------------------
    $lcu = Get-Packages 'lcu' '*.msu'
    $dotnet = Get-Packages 'dotnet' '*.msu'
    if (-not $lcu.Count) { Write-Warning "No cumulative update in $UpdatesRoot\lcu - the image stays at its original build; Windows Update will patch after install." }
    # Every package in updates\lcu must apply. (A 26300.9457+ image is already
    # past the 24H2 checkpoint KB5043080, so only the target LCU belongs there.)
    $target = if ($lcu.Count) { $lcu[-1] } else { $null }
    foreach ($u in $lcu) {
        Step "Adding $($u.Name)"
        Assert-UpdateFile $u
        Add-WindowsPackage -Path $mount -PackagePath $u.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs "dism-$($u.BaseName).log") | Out-Null
        $manifest.updates += $u.Name
    }
    $lcuBuild = $null   # e.g. 26100.9550: what WinRE and boot.wim are serviced to as well
    if ($target) {
        Write-Host "Cumulative update packages in image:"
        Get-WindowsPackage -Path $mount | Where-Object { $_.PackageName -match 'RollupFix' } | Format-Table PackageName, PackageState -AutoSize | Out-String | Write-Host
        $lcuBuild = Get-InstalledLcuBuild $mount
        if (-not $lcuBuild) { throw "No installed cumulative update (Package_for_RollupFix) in the image after adding $($target.Name)." }
    }
    $manifest.lcuBuild = $lcuBuild
    # Microsoft's order: LCU -> component cleanup -> .NET. No /ResetBase, so
    # updates in the installed OS stay uninstallable.
    Step 'Component cleanup (no ResetBase)'
    try { Repair-WindowsImage -Path $mount -StartComponentCleanup -ScratchDirectory $scratch -ErrorAction Stop | Out-Null }
    catch { Write-Warning "Component cleanup skipped: $($_.Exception.Message)"; $manifest.skipped += "StartComponentCleanup ($($_.Exception.Message))" }
    foreach ($u in $dotnet) {
        Step "Adding $($u.Name)"
        Assert-UpdateFile $u
        Add-WindowsPackage -Path $mount -PackagePath $u.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs "dism-$($u.BaseName).log") | Out-Null
        $manifest.updates += $u.Name
    }

    # --- 4. WinRE ------------------------------------------------------------
    Step 'Servicing WinRE'
    $reWim = Join-Path $mount 'Windows\System32\Recovery\Winre.wim'
    # The profile's drivers.skipInf applies here too, so a profile change takes effect without a new harvest
    $skipInf = "$($hw.drivers.skipInf)"
    $allInfs = @(Get-ChildItem $DriverRoot -Recurse -File -Filter *.inf | Where-Object Extension -eq '.inf')
    $driverInfs = @($allInfs | Where-Object { -not $skipInf -or $_.Name -notmatch $skipInf })
    $manifest.driversSkipped = @($allInfs | Where-Object { $skipInf -and $_.Name -match $skipInf } | ForEach-Object Name)
    # WinRE gets the network and storage drivers; boot.wim (step 11) the storage drivers only
    $reInfs = @(Select-DriverInfByClass $driverInfs @('Net', 'SCSIAdapter', 'HDC'))
    $bootInfs = @(Select-DriverInfByClass $driverInfs @('SCSIAdapter', 'HDC'))
    $safeos = Get-Packages 'safeos' '*.cab'
    if (Test-Path $reWim) {
        Copy-Item $reWim $reWork -Force
        (Get-Item $reWork).Attributes = 'Normal'
        Mount-WindowsImage -ImagePath $reWork -Index 1 -Path $reMount -ScratchDirectory $scratch | Out-Null
        # Microsoft's step 1: the cumulative update first, for its servicing stack (the Safe OS
        # updates below are installed by it). WinRE is a Windows PE image: 0x8007007e is tolerated.
        foreach ($u in $lcu) {
            Write-Host "  WinRE: adding $($u.Name) (servicing stack)"
            $full = Add-PeCumulativeUpdate $reMount $u "dism-winre-$($u.BaseName).log"
            $manifest.updates += "WinRE: $($u.Name)$(if (-not $full) { ' (0x8007007e tolerated, as in Microsoft''s sample)' })"
        }
        $safeosApplied = 0
        foreach ($u in $safeos) {
            Assert-UpdateFile $u   # outside the try: a changed file stops the build
            # Several Safe OS DUs can share a release date; one that is older than
            # what is already applied is skipped rather than failing the build.
            try {
                Add-WindowsPackage -Path $reMount -PackagePath $u.FullName -ScratchDirectory $scratch | Out-Null
                $manifest.updates += "WinRE: $($u.Name)"
                $safeosApplied++
            } catch {
                Write-Warning "Safe OS DU $($u.Name) not applied: $($_.Exception.Message)"
                $manifest.skipped += "WinRE: $($u.Name) ($($_.Exception.Message))"
            }
        }
        foreach ($inf in $reInfs) {
            try { Add-WindowsDriver -Path $reMount -Driver $inf.FullName -ScratchDirectory $scratch -ErrorAction Stop | Out-Null }
            catch { Write-Warning "WinRE: driver $($inf.Name) not added: $($_.Exception.Message)"; $manifest.skipped += "WinRE driver $($inf.Name)" }
        }
        # Read back, while WinRE is mounted: the drivers it has, and the level it is really at.
        # The cumulative update leaves only its servicing stack in WinRE (no RollupFix package
        # there): WinRE's level comes from the Safe OS update, so it is its own kernel's version.
        $reHas = @(Get-WindowsDriver -Path $reMount -ScratchDirectory $scratch -ErrorAction SilentlyContinue | ForEach-Object { Split-Path -Leaf "$($_.OriginalFileName)" })
        $reMissing = @($reInfs | Where-Object { $reHas -notcontains $_.Name })
        Write-Host "  WinRE drivers from the curated set: $(@($reInfs | Where-Object { $reHas -contains $_.Name } | ForEach-Object Name) -join ', ')$(if (-not $reInfs.Count) { 'none (the curated set has no network or storage driver)' })"
        $reMissingStorage = @($reMissing | Where-Object { $bootInfs.Name -contains $_.Name })
        if ($reMissingStorage.Count) { throw "WinRE lacks the curated storage driver(s) $(@($reMissingStorage.Name) -join ', '): without them Windows RE cannot see this PC's disk. The warnings above say why each was not added." }
        if ($reMissing.Count) { Write-Warning "WinRE lacks the curated network driver(s) $(@($reMissing.Name) -join ', ') (Windows RE works without a network)" }
        $reKernel = (Get-Item -LiteralPath (Join-Path $reMount 'Windows\System32\ntoskrnl.exe') -ErrorAction SilentlyContinue).VersionInfo
        $reLevel = if ($reKernel) { '{0}.{1}.{2}.{3}' -f $reKernel.FileMajorPart, $reKernel.FileMinorPart, $reKernel.FileBuildPart, $reKernel.FilePrivatePart } else { $null }
        $manifest.winreVersion = $reLevel
        $manifest.winreLcuBuild = Get-InstalledLcuBuild $reMount
        Write-Host "  WinRE level (its kernel): $(if ($reLevel) { $reLevel } else { 'not readable' }); Safe OS updates applied: $safeosApplied of $(@($safeos).Count)"
        # Without a Safe OS update and older than this month's update, WinRE is not serviced
        if ($safeos.Count -and -not $safeosApplied -and $lcuBuild -and $reKernel -and $reKernel.FilePrivatePart -lt ([version]$lcuBuild).Minor) {
            throw "WinRE was not serviced: no Safe OS update applied (warnings above), and its kernel ($reLevel) is older than the cumulative update ($lcuBuild)."
        }
        # WinRE updates are never uninstalled: ResetBase keeps it small enough
        # for future WinRE servicing on the recovery partition. -Defer as in
        # Microsoft's sample (DISM /Cleanup-Image /StartComponentCleanup /ResetBase /Defer).
        Repair-WindowsImage -Path $reMount -StartComponentCleanup -ResetBase -Defer -ScratchDirectory $scratch | Out-Null
        Dismount-WindowsImage -Path $reMount -Save -CheckIntegrity -ScratchDirectory $scratch | Out-Null
        Export-WindowsImage -SourceImagePath $reWork -SourceIndex 1 -DestinationImagePath $reOut -CompressionType max -CheckIntegrity | Out-Null
        Copy-Item $reOut $reWim -Force
        Remove-Item $reWork, $reOut -Force
        Write-Host ("  Winre.wim: {0:N0} MB" -f ((Get-Item -LiteralPath $reWim -Force).Length / 1MB))
    } else {
        Write-Warning 'Winre.wim not found in the image.'
    }

    # --- 5. Drivers ----------------------------------------------------------
    Step "Adding drivers from $DriverRoot ($($driverInfs.Count) packages$(if ($manifest.driversSkipped.Count) { "; profile skips $($manifest.driversSkipped -join ', ')" }))"
    foreach ($inf in $driverInfs) {
        Add-WindowsDriver -Path $mount -Driver $inf.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs 'dism-drivers.log') -ErrorAction Stop | Out-Null
    }
    $added = Get-WindowsDriver -Path $mount
    $manifest.drivers = @($added | ForEach-Object { "$(Split-Path $_.OriginalFileName -Leaf) $($_.Version) [$($_.ProviderName)]" } | Sort-Object -Unique)
    Write-Host "Driver packages in image: $($manifest.drivers.Count)"
    $manifest.drivers | Write-Host

    # --- 6. Apps -------------------------------------------------------------
    Step 'Removing provisioned apps'
    $rm = Get-Content -Raw (Join-Path $KitRoot 'config\removal-manifest.json') | ConvertFrom-Json
    foreach ($r in $rm.remove) {
        foreach ($p in $rm.protect) { if ($r.name -like $p) { throw "Removal entry $($r.name) matches protected pattern $p" } }
    }
    $prov = Get-AppxProvisionedPackage -Path $mount
    foreach ($r in $rm.remove) {
        $hit = @($prov | Where-Object DisplayName -eq $r.name)
        if (-not $hit.Count) { $manifest.skipped += "$($r.name) (not in image)"; Write-Host "  not present: $($r.name)"; continue }
        foreach ($h in $hit) {
            Remove-AppxProvisionedPackage -Path $mount -PackageName $h.PackageName | Out-Null
            $manifest.removed += $h.PackageName
            Write-Host "  removed: $($h.PackageName)"
        }
    }
    $left = Get-AppxProvisionedPackage -Path $mount | Select-Object -ExpandProperty DisplayName
    foreach ($must in (Get-KitRequiredApps $imageCfg $optGaming)) {
        if ($left -notcontains $must) { Write-Warning "Expected provisioned package not present in source image: $must" }
    }
    $manifest.provisionedAfter = @($left | Sort-Object)

    # Mark every removed app deprovisioned (the key Remove-AppxProvisionedPackage
    # -Online writes), so Windows doesn't provision it again: an offline removal
    # doesn't always write it (seen with Dev Home, which Windows then provisioned
    # again minutes after the first sign-in).
    $pfns = @($manifest.removed | ForEach-Object { $p = $_ -split '_'; "$($p[0])_$($p[-1])" } | Sort-Object -Unique)
    # Apps on the list that this source image doesn't carry: mark them too (their family name is
    # in the manifest), or Windows or the Store can provision them later (seen with Dev Home)
    $pfns = @(@($pfns) + @($rm.remove | Where-Object { $_.pfn } | ForEach-Object pfn) | Sort-Object -Unique)
    if ($pfns.Count) {
        $hive = 'HKLM\W11K_SOFTWARE'   # same name Set-KitRegistry uses later; Clear-BuildState unloads it after a failure
        if ((Invoke-Reg load $hive (Join-Path $mount 'Windows\System32\config\SOFTWARE')) -ne 0) { throw 'reg load of the offline SOFTWARE hive failed' }
        try {
            foreach ($pfn in $pfns) {
                if ((Invoke-Reg add "$hive\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn" /f) -ne 0) { throw "Could not mark $pfn deprovisioned" }
                Write-Host "  deprovisioned: $pfn"
            }
        } finally {
            [gc]::Collect()
            if ((Invoke-Reg unload $hive) -ne 0) { Write-Warning "Could not unload $hive" }
        }
    }
    $manifest.deprovisioned = $pfns

    # --- 7. Features ---------------------------------------------------------
    $featOn = @($imageCfg.features.enable); $featOff = @($imageCfg.features.disable)
    Step "Optional features (config\image.json): enable $($featOn -join ', '); disable $($featOff -join ', ')"
    foreach ($f in $featOn) {
        Enable-WindowsOptionalFeature -Path $mount -FeatureName $f -ScratchDirectory $scratch | Out-Null
    }
    foreach ($f in $featOff) {
        # One name per call (-FeatureName takes one); absent from the image = nothing to do
        $cur = Get-WindowsOptionalFeature -Path $mount -FeatureName $f -ErrorAction SilentlyContinue
        if ($cur -and $cur.State -eq 'Enabled') {
            # Disabled, payload kept: feature updates and servicing stay consistent.
            Disable-WindowsOptionalFeature -Path $mount -FeatureName $f -ScratchDirectory $scratch | Out-Null
        }
    }
    $featShow = @($featOn + $featOff + @($imageCfg.features.mustNotBeEnabled))
    Get-WindowsOptionalFeature -Path $mount | Where-Object { $featShow -contains $_.FeatureName } |
        Format-Table FeatureName, State -AutoSize | Out-String | Write-Host

    # --- 8. Registry ---------------------------------------------------------
    Step 'Offline registry customizations'
    Invoke-KitScript 'scripts\Set-KitRegistry.ps1' @{ Mode = 'Offline'; MountPath = $mount; PowerMode = "$($hw.power.mode)"; Settings = $kitSettings }

    # --- 9. Payload ----------------------------------------------------------
    Step 'Staging post-install payload'
    $payload = Join-Path $mount 'ProgramData\W11Kit'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    Copy-Item (Join-Path $KitRoot 'payload\*') $payload -Force
    Copy-Item (Join-Path $KitRoot 'scripts\Set-KitRegistry.ps1') $payload -Force
    Copy-Item (Join-Path $KitRoot 'config\removal-manifest.json') $payload -Force
    Copy-Item (Join-Path $KitRoot 'config\image.json') $payload -Force
    Copy-Item (Join-Path $KitRoot 'config\baseline-overrides.txt') $payload -Force
    # The overrides' security template with this build's names for the built-in accounts,
    # and with the Xbox services' override only for options.gamingTweaks (UTF-16, as secedit reads it)
    $stagedInf = ConvertTo-StagedOverridesInf ([IO.File]::ReadAllText((Join-Path $KitRoot 'config\baseline-overrides.inf'))) $builtinAdmin $builtinGuest $optGaming
    [IO.File]::WriteAllText((Join-Path $payload 'baseline-overrides.inf'), $stagedInf, [Text.Encoding]::Unicode)
    Copy-Item (Join-Path $KitRoot 'config\baseline-overrides-audit.csv') $payload -Force
    # The hardware profile PostInstall and the validator read (C:\ProgramData\W11Kit\profile.json)
    Copy-Item -LiteralPath $prof.Path (Join-Path $payload 'profile.json') -Force
    # The effective settings PostInstall, Set-KitRegistry and the validator follow
    # (C:\ProgramData\W11Kit\settings.json): the files' values and the kit's defaults
    # for fields they leave out.
    $stagedSettings = [ordered]@{ description = "Effective settings of this image (built $($manifest.built) from $settingsFiles$(if (@($ks.Sources.Values | Where-Object { $_ -eq 'this PC' }).Count) { ' and the build PC''s own values' })). docs/reference/CONFIGURATION.md explains every field." }
    foreach ($k in $kitSettings.Keys) { $stagedSettings[$k] = $kitSettings[$k] }
    [IO.File]::WriteAllText((Join-Path $payload 'settings.json'), ($stagedSettings | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
    # Choices PostInstall needs at first logon (no secrets)
    [ordered]@{
        AdminName                       = $AdminName
        UserName                        = $UserName
        ComputerName                    = $(if ($ComputerName) { $ComputerName } else { $null })   # null: random name, nothing to rename
        BuiltinAdministratorName        = $builtinAdmin   # as staged in baseline-overrides.inf
        BuiltinGuestName                = $builtinGuest
        Profile                         = $hw.id
        TestBuild                       = [bool]$TestBuild   # the validator warns about a test build on a real PC
        KitRevision                     = $kitRevision
        TimeZone                        = $TimeZone
        UiLanguage                      = $loc.uiLanguage   # the rest: settings.json next to this file
    } | ConvertTo-Json | Set-Content (Join-Path $payload 'build-options.json') -Encoding ASCII

    # Microsoft's security baselines as data (Apply-Policy.ps1 applies them at first boot):
    # checked once more against the index and the pins, then staged from the work folder
    foreach ($bl in $blList) { $blWhy = Test-BaselineData $bl; if ($blWhy) { throw "The security baseline data in $($bl.Dir) changed during the build: $blWhy." } }
    Copy-BaselineData $blList.ToArray() $blPins (Join-Path $payload 'Baselines')
    $manifest.securityBaselines = @(foreach ($bl in $blList) { "$($bl.File) (SHA-256 $($bl.Sha256))" })
    $manifest.baselineImporter = "scripts\Import-Baseline.py (SHA-256 $((Get-FileHash -LiteralPath (Join-Path $KitRoot 'scripts\Import-Baseline.py') -Algorithm SHA256).Hash.ToLowerInvariant()))"
    $inv = Join-Path (Split-Path $DriverRoot -Parent) 'DRIVER-INVENTORY.md'
    if (Test-Path $inv) { Copy-Item $inv $payload -Force }
    $shell = Join-Path $mount 'Users\Default\AppData\Local\Microsoft\Windows\Shell'
    New-Item -ItemType Directory -Path $shell -Force | Out-Null
    # Start pins: the file as it is, or without the gaming apps' pins (options.gamingTweaks off)
    $layoutSrc = Join-Path $KitRoot 'config\LayoutModification.json'
    if ($optGaming) { Copy-Item $layoutSrc $shell -Force }
    else { [IO.File]::WriteAllText((Join-Path $shell 'LayoutModification.json'), (ConvertTo-StagedStartLayout ([IO.File]::ReadAllText($layoutSrc)) $false @($imageCfg.gamingApps)), (New-Object Text.UTF8Encoding $false)) }
    Copy-Item (Join-Path $KitRoot 'config\wslconfig') (Join-Path $mount 'Users\Default\.wslconfig') -Force

    # --- 9b. Verify the image with DISM before committing ------------------------
    Step 'Verifying the image (DISM read-back of updates, drivers, features, apps, registry, files)'
    $srcUbr = [int](($pro.Version -split '\.')[-1])
    Invoke-KitScript 'scripts\Test-OfflineImage.ps1' @{ MountPath = $mount; KitRoot = $KitRoot; BaselineRoot = $blWork; DriverRoot = $DriverRoot; SkipInf = "$($hw.drivers.skipInf)"; ProfileId = $hw.id; MinUbr = $srcUbr; Final = $true; Deprovisioned = $pfns; ReportPath = (Join-Path $logs "verify-$stamp.txt") }
    $manifest.verification = "passed (logs\verify-$stamp.txt)"

    # --- 10. Commit -------------------------------------------------------------
    Step 'Committing install image'
    Dismount-WindowsImage -Path $mount -Save -CheckIntegrity -ScratchDirectory $scratch | Out-Null
    # Version of the SERVICED image (for the ISO name): WIM metadata is updated on commit
    $builtVersion = try { (Get-WindowsImage -ImagePath $work -Index 1).Version } catch { $null }
    if (-not $builtVersion -or $builtVersion -eq $pro.Version) { $builtVersion = "$($pro.Version) (+ updates)" }
    $manifest.builtVersion = $builtVersion
    $final = "$media\sources\install.wim"
    Export-WindowsImage -SourceImagePath $work -SourceIndex 1 -DestinationImagePath $final -CompressionType max -CheckIntegrity | Out-Null
    Remove-Item $work -Force
    $wimGb = (Get-Item $final).Length / 1GB
    Write-Host ("install.wim: {0:N2} GB" -f $wimGb)
    if ($wimGb -gt 3.9) {
        Step 'Splitting install.wim into <4 GB parts (FAT32-friendly USB)'
        Split-WindowsImage -ImagePath $final -SplitImagePath "$media\sources\install.swm" -FileSize 3800 -CheckIntegrity | Out-Null
        Remove-Item $final -Force
        $final = "$media\sources\install.swm"
    }
    # Read back what Setup will open: the image file (the first part of a split set) must
    # open and hold exactly the one Pro image.
    $finalImages = @(Get-WindowsImage -ImagePath $final)
    if ($finalImages.Count -ne 1) { throw "$final holds $($finalImages.Count) images after the export$(if ($final -like '*.swm') { ' and split' }) (expected 1)." }
    # SHA-256 of every image file on the media, for the manifest: a written stick can be
    # checked against it (Get-FileHash <stick>:\sources\install*.swm).
    $mediaHashes = [ordered]@{}
    foreach ($f in @(Get-ChildItem "$media\sources" -File | Where-Object { $_.Name -match '^install\d*\.(swm|wim)$' } | Sort-Object Name)) {
        $mediaHashes["sources\$($f.Name)"] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    Write-Host "  $($finalImages[0].ImageName): $($mediaHashes.Count) file(s) ($(@($mediaHashes.Keys | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')), SHA-256 in the manifest"

    # --- 11. boot.wim: Windows PE and Windows Setup ------------------------------
    # Microsoft's "Update Windows installation media with Dynamic Update" (steps 17-25):
    # every image in boot.wim (normally 1 = Windows PE, 2 = Windows Setup) gets the
    # cumulative update, a component cleanup and an export into a fresh file. The media
    # then boots a Windows PE with this month's fixes, and its boot manager and Setup
    # binaries (below) carry the current Secure Boot security version.
    # Every image also gets the curated storage drivers (classes SCSIAdapter and HDC, the
    # ones WinRE got): without them Setup shows no disk on a PC whose disk controller has
    # no driver in Windows. Signed drivers only (never -ForceUnsigned).
    $bootWim = "$media\sources\boot.wim"
    $bootImages = @(Get-WindowsImage -ImagePath $bootWim)
    if (-not $bootImages.Count) { throw "$bootWim holds no image." }
    $srcBootIndex = Get-WimBootIndex $bootWim
    $bootInfo = New-Object System.Collections.Generic.List[object]
    $bootAdded = @{}   # image index -> INF names of the storage drivers added to it
    if ($bootInfs.Count) { Write-Host "boot.wim: $($bootInfs.Count) storage driver(s) in the curated set go into every image: $(@($bootInfs | ForEach-Object Name) -join ', ')" }
    else { Write-Host 'boot.wim: no storage drivers in the curated set: nothing to add to boot.wim' }
    if ($lcu.Count) {
        foreach ($bi in $bootImages) {
            Step "Servicing boot.wim image $($bi.ImageIndex) of $($bootImages.Count) ($($bi.ImageName))"
            Mount-WindowsImage -ImagePath $bootWim -Index $bi.ImageIndex -Path $bootMount -ScratchDirectory $scratch | Out-Null
            foreach ($u in $lcu) {
                Write-Host "  adding $($u.Name)"
                $log = "dism-boot$($bi.ImageIndex)-$($u.BaseName).log"
                if (-not (Add-PeCumulativeUpdate $bootMount $u $log)) {
                    # Microsoft's sample adds the update a second time (its step 23), and that one must succeed
                    Write-Host "  adding $($u.Name) again (now with the new servicing stack)"
                    Add-WindowsPackage -Path $bootMount -PackagePath $u.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs $log) -ErrorAction Stop | Out-Null
                }
            }
            # Read back before anything is saved: the same cumulative update level as the installed Windows
            Get-WindowsPackage -Path $bootMount -ScratchDirectory $scratch | Where-Object { $_.PackageName -match 'RollupFix' } | Format-Table PackageName, PackageState -AutoSize | Out-String | Write-Host
            $peBuild = Get-InstalledLcuBuild $bootMount
            if ($peBuild -ne $lcuBuild) { throw "boot.wim image $($bi.ImageIndex) is at cumulative update level '$peBuild' after servicing, the install image at '$lcuBuild' (log: $logs\$log)." }
            $drvAdded = New-Object System.Collections.Generic.List[string]
            foreach ($inf in $bootInfs) {
                try {
                    Add-WindowsDriver -Path $bootMount -Driver $inf.FullName -ScratchDirectory $scratch -LogPath (Join-Path $logs "dism-boot$($bi.ImageIndex)-drivers.log") -ErrorAction Stop | Out-Null
                    $drvAdded.Add($inf.Name)
                } catch {
                    Write-Warning "boot.wim image $($bi.ImageIndex): storage driver $($inf.Name) not added: $($_.Exception.Message)"
                    $manifest.skipped += "boot.wim image $($bi.ImageIndex) driver $($inf.Name)"
                }
            }
            if ($bootInfs.Count) {
                # Read back before anything is saved
                $inImage = @(Get-WindowsDriver -Path $bootMount -ScratchDirectory $scratch | ForEach-Object { (Split-Path $_.OriginalFileName -Leaf).ToLower() })
                $notIn = @($drvAdded.ToArray() | Where-Object { $inImage -notcontains $_.ToLower() })
                if ($notIn.Count) { throw "boot.wim image $($bi.ImageIndex): DISM added $($notIn -join ', ') without an error, but the image does not list $(if ($notIn.Count -gt 1) { 'them' } else { 'it' }) (log: $logs\dism-boot$($bi.ImageIndex)-drivers.log)." }
                Write-Host "  image $($bi.ImageIndex): $($drvAdded.Count) of $($bootInfs.Count) storage driver(s) added$(if ($drvAdded.Count) { " ($($drvAdded.ToArray() -join ', '))" })"
            }
            $bootAdded[[int]$bi.ImageIndex] = $drvAdded.ToArray()
            # Windows PE updates are never uninstalled (flags as in Microsoft's sample)
            Repair-WindowsImage -Path $bootMount -StartComponentCleanup -ResetBase -Defer -ScratchDirectory $scratch | Out-Null
            Dismount-WindowsImage -Path $bootMount -Save -CheckIntegrity -ScratchDirectory $scratch | Out-Null
            # Export into a fresh file (drops the replaced files). The compression is set by the
            # first image; the boot index is kept as in Microsoft's file.
            $exp = @{ SourceImagePath = $bootWim; SourceIndex = $bi.ImageIndex; DestinationImagePath = $bootOut; CheckIntegrity = $true }
            if (-not (Test-Path -LiteralPath $bootOut)) { $exp.CompressionType = 'max' }
            if ($bi.ImageIndex -eq $srcBootIndex) { $exp.Setbootable = $true }
            Export-WindowsImage @exp | Out-Null
            Write-Host "  image $($bi.ImageIndex): cumulative update level $peBuild"
        }
        Move-Item -LiteralPath $bootOut -Destination $bootWim -Force
        $newImages = @(Get-WindowsImage -ImagePath $bootWim)
        $newBootIndex = Get-WimBootIndex $bootWim
        if ($newImages.Count -ne $bootImages.Count -or $newBootIndex -ne $srcBootIndex) {
            throw "The serviced boot.wim has $($newImages.Count) image(s) and boot index $newBootIndex; the source has $($bootImages.Count) and $srcBootIndex."
        }
        $manifest.updates += @($lcu | ForEach-Object { "boot.wim: $($_.Name)" })
    } else {
        Write-Warning "boot.wim is not serviced (no cumulative update in updates\lcu)$(if ($bootInfs.Count) { ', so the storage drivers are not added to it either' })."
    }
    foreach ($bi in $bootImages) {
        $d = Get-WindowsImage -ImagePath $bootWim -Index $bi.ImageIndex
        $biDrivers = @(if ($bootAdded.ContainsKey([int]$bi.ImageIndex)) { $bootAdded[[int]$bi.ImageIndex] })
        $bootInfo.Add([ordered]@{ index = $bi.ImageIndex; name = "$($d.ImageName)"; version = "$($d.Version)"; storageDrivers = $biDrivers })
    }
    $manifest.bootWim = [ordered]@{ serviced = [bool]$lcu.Count; lcuBuild = $(if ($lcu.Count) { $lcuBuild } else { $null }); bootIndex = (Get-WimBootIndex $bootWim); images = $bootInfo.ToArray(); sha256 = (Get-FileHash -LiteralPath $bootWim -Algorithm SHA256).Hash }
    Write-Host ("boot.wim: {0:N0} MB, {1} image(s), boot index {2}" -f ((Get-Item $bootWim).Length / 1MB), $bootImages.Count, $manifest.bootWim.bootIndex)

    # --- Setup Dynamic Update (optional; Microsoft's step 26) ---------------------
    # Before the Setup binaries are taken from boot.wim below: an expanded package
    # may bring its own setup.exe, and the media's must be the one in boot.wim.
    foreach ($c in (Get-Packages 'setup' '*.cab')) {
        Step "Expanding Setup Dynamic Update $($c.Name) into media\sources"
        Assert-UpdateFile $c
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $null = & expand.exe $c.FullName -F:* "$media\sources" 2>&1; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
        if ($rc -ne 0) { throw "expand.exe failed ($rc) for Setup Dynamic Update $($c.Name)" }
        $manifest.updates += "Setup DU: $($c.Name)"
    }

    # --- Setup binaries and boot manager from the serviced boot.wim ---------------
    # Microsoft's last two steps (27, 28). The media's sources\setup.exe and
    # setuphost.exe must be the ones inside boot.wim's Setup image ("If these binaries
    # aren't identical, Windows Setup will fail during installation"), and the media
    # boots with the boot manager of the serviced image.
    # By default that is the one signed by "Windows UEFI CA 2023" (the _EX files, as
    # Microsoft's Make2023BootableMedia.ps1 takes them, KB5053484): the 2011 signing CA
    # expires 2026-10-19, and media signed by it stops booting once a PC revokes it
    # (KB5025885). -Use2011BootManager takes the serviced 2011-signed files instead.
    Step "Setup files and boot manager from the serviced boot.wim ($(if ($Use2011BootManager) { 'Windows Production PCA 2011: -Use2011BootManager' } else { 'Windows UEFI CA 2023' }))"
    $efisys = "$media\efi\microsoft\boot\efisys.bin"
    # The Setup image: the one with sources\setup.exe, normally the last (and the boot index)
    $setupIndex = 0
    foreach ($i in @($srcBootIndex) + @($bootImages.Count..1) | Where-Object { $_ -ge 1 -and $_ -le $bootImages.Count } | Select-Object -Unique) {
        # Not read-only: DISM reads the package list below; nothing is saved (-Discard)
        Mount-WindowsImage -ImagePath $bootWim -Index $i -Path $bootMount -ScratchDirectory $scratch | Out-Null
        if (Test-Path -LiteralPath "$bootMount\sources\setup.exe") { $setupIndex = $i; break }
        Dismount-WindowsImage -Path $bootMount -Discard -ScratchDirectory $scratch | Out-Null
    }
    if (-not $setupIndex) { throw "No image in $bootWim has sources\setup.exe (Windows Setup)." }
    try {
        # Windows Setup's own binaries. Microsoft's steps name setup.exe and setuphost.exe
        # (24H2 and later) and rely on a Setup Dynamic Update of the same level for the rest.
        # There isn't always one (a preview cumulative update can be newer than the newest
        # Setup Dynamic Update), and with only those two files replaced Setup stops at
        # "Determine if the expected version of Setup Platform has been loaded" with
        # 0xC1900100: setuphost.exe from boot.wim, SetupPlatform.dll from the source ISO.
        # So every file of boot.wim's sources\ that the media has too is taken
        # from boot.wim: the whole Setup engine at one level on both sides.
        $setupFiles = [ordered]@{}
        $setupCopied = 0
        $bootSources = (Get-Item -LiteralPath "$bootMount\sources").FullName.TrimEnd('\')
        foreach ($f in @(Get-ChildItem -LiteralPath $bootSources -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($bootSources.Length + 1)
            $dst = Join-Path "$media\sources" $rel
            if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { continue }
            $di = Get-Item -LiteralPath $dst -Force
            if ($di.IsReadOnly) { $di.IsReadOnly = $false }
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            $setupCopied++
        }
        foreach ($n in 'setup.exe', 'setuphost.exe', 'setupplatform.dll', 'setupcore.dll') {
            if (Test-Path -LiteralPath "$media\sources\$n") { $setupFiles[$n] = Get-FileVersionText "$media\sources\$n" }
        }
        $setupFiles['filesFromBootWim'] = $setupCopied
        $manifest.setupFiles = $setupFiles
        $bootDir = "$bootMount\Windows\Boot"
        # Every copy of the boot manager on the media, as Microsoft's sample replaces them
        $bmFiles = @(Get-ChildItem -LiteralPath $media -Recurse -Force -File -Filter 'b*.efi' | Where-Object { $_.Name -in 'bootmgfw.efi', 'bootx64.efi' -and $_.FullName -notmatch '\\BuildInputs\\' })
        if ($bmFiles.FullName -notcontains "$media\efi\boot\bootx64.efi") { throw "The media has no efi\boot\bootx64.efi." }
        if ($Use2011BootManager) {
            Write-Warning 'Keeping 2011-signed boot files (-Use2011BootManager), from the serviced boot.wim.'
            foreach ($f in $bmFiles) { Copy-Item -LiteralPath "$bootDir\EFI\bootmgfw.efi" -Destination $f.FullName -Force }
            if (Test-Path -LiteralPath "$media\bootmgr.efi") { Copy-Item -LiteralPath "$bootDir\EFI\bootmgr.efi" -Destination "$media\bootmgr.efi" -Force }
            # The ISO's UEFI boot image (a small FAT image with the same boot manager inside)
            $efisysNew = @(@("$bootDir\DVD\EFI\en-US\efisys.bin") + @(Get-ChildItem "$bootDir\DVD\EFI\*\efisys.bin" -ErrorAction SilentlyContinue | ForEach-Object FullName) | Where-Object { Test-Path -LiteralPath $_ })
            if ($efisysNew.Count) { Copy-Item -LiteralPath $efisysNew[0] -Destination $efisys -Force }
            else { Write-Warning 'boot.wim has no Windows\Boot\DVD\EFI\<language>\efisys.bin: the ISO keeps the source media''s UEFI boot image.' }
        } else {
            foreach ($d in 'EFI_EX', 'FONTS_EX', 'DVD_EX') {
                if (-not (Test-Path "$bootDir\$d")) { throw "boot.wim has no Windows\Boot\${d}: the source media predates the 2024-04 updates (use -Use2011BootManager to build anyway)" }
            }
            foreach ($f in $bmFiles) { Copy-Item -LiteralPath "$bootDir\EFI_EX\bootmgfw_EX.efi" -Destination $f.FullName -Force }
            if (Test-Path "$bootDir\EFI_EX\bootmgr_EX.efi") { Copy-Item "$bootDir\EFI_EX\bootmgr_EX.efi" "$media\bootmgr.efi" -Force }
            # efisys_EX.bin sits in a language folder (en-US on English media); take any if en-US isn't there
            $efisysEx = @(@("$bootDir\DVD_EX\EFI\en-US\efisys_EX.bin") + @(Get-ChildItem "$bootDir\DVD_EX\EFI\*\efisys_EX.bin" -ErrorAction SilentlyContinue | ForEach-Object FullName) | Where-Object { Test-Path -LiteralPath $_ })
            if (-not $efisysEx.Count) { throw 'boot.wim has no Windows\Boot\DVD_EX\EFI\<language>\efisys_EX.bin (use -Use2011BootManager to build anyway)' }
            $efisys = "$media\efi\microsoft\boot\efisys_ex.bin"
            Copy-Item $efisysEx[0] $efisys -Force
            foreach ($f in Get-ChildItem "$bootDir\FONTS_EX" -File) {
                Copy-Item $f.FullName (Join-Path "$media\efi\microsoft\boot\fonts" ($f.Name -replace '_EX', '')) -Force
            }
        }
        if (Test-Path "$bootDir\EFI\boot.stl") { Copy-Item "$bootDir\EFI\boot.stl" "$media\efi\microsoft\boot\boot.stl" -Force }
        # Read-back (scripts\Test-OfflineImage.ps1 -BootMedia): the Setup image holds the
        # cumulative update and every storage driver that was added to it, and the media's
        # setup.exe, setuphost.exe and boot manager are byte for byte the ones in it. Any
        # mismatch stops the build.
        $setupDrivers = @(if ($bootAdded.ContainsKey([int]$setupIndex)) { $bootAdded[[int]$setupIndex] })
        Invoke-KitScript 'scripts\Test-OfflineImage.ps1' @{ MountPath = $bootMount; KitRoot = $KitRoot; BootMedia = $media; BootDrivers = $setupDrivers; ExpectLcuBuild = "$(if ($lcu.Count) { $lcuBuild })"; ReportPath = (Join-Path $logs "verify-boot-$stamp.txt") }
        $manifest.bootVerification = "passed (logs\verify-boot-$stamp.txt)"
    } finally {
        Dismount-WindowsImage -Path $bootMount -Discard -ScratchDirectory $scratch | Out-Null
    }
    # Read back the EMBEDDED signature (what the firmware checks). Not
    # Get-AuthenticodeSignature: for Windows boot files it returns the
    # catalog signature, whose chain says nothing about the 2011/2023 CA.
    $issuer = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile("$media\efi\boot\bootx64.efi").Issuer
    $manifest.bootManagerVersion = Get-FileVersionText "$media\efi\boot\bootx64.efi"
    if ($Use2011BootManager) {
        $manifest.bootManager = "$(if ($issuer -match 'CN=([^,]+)') { $Matches[1] } else { $issuer }) (-Use2011BootManager)"
    } else {
        if ($issuer -notmatch 'CN=Windows UEFI CA 2023') { throw "efi\boot\bootx64.efi is not signed by Windows UEFI CA 2023 (issuer: $issuer)" }
        $manifest.bootManager = 'Windows UEFI CA 2023'
    }
    Write-Host "  setup.exe $($setupFiles['setup.exe'])$(if ($setupFiles.Contains('setuphost.exe')) { ", setuphost.exe $($setupFiles['setuphost.exe'])" }) and $($setupCopied - 1) more Setup file(s) from boot.wim image $setupIndex"
    Write-Host "  boot manager $($manifest.bootManagerVersion) ($($bmFiles.Count) file(s): bootx64.efi, bootmgfw.efi), bootmgr.efi, $(Split-Path $efisys -Leaf), fonts, boot.stl from the serviced boot.wim; bootx64.efi signed by: $($manifest.bootManager)"

    # --- 10b. Build inputs (self-hosting) --------------------------------------
    if ($withInputs) {
        Step 'Build inputs: source ISO, updates, baseline zips, drivers, oscdimg, installers, kit (split into <4 GB parts)'
        New-BuildInputs (Join-Path $media 'BuildInputs')
    }

    # --- 11. Unattend + ISO -----------------------------------------------------
    Step 'Writing autounattend.xml'
    $xml = Get-Content -Raw (Join-Path $KitRoot 'config\autounattend.xml')
    $xml = $xml.Replace('__ADMINNAME__', $AdminName).Replace('__ADMINPASSWORD_B64__', $adminPwB64)
    $xml = $xml.Replace('__USERNAME__', $UserName).Replace('__USERPASSWORD_B64__', $userPwB64)
    $xml = $xml.Replace('__COMPUTERNAME__', $(if ($ComputerName) { $ComputerName } else { '*' })).Replace('__TIMEZONE__', $TimeZone)
    # Language and locales (settings locale.*): windowsPE (Setup) and oobeSystem (the installed Windows)
    $xml = $xml.Replace('__UILANGUAGE__', $loc.uiLanguage).Replace('__INPUTLOCALE__', $loc.inputLocale)
    $xml = $xml.Replace('__SYSTEMLOCALE__', $loc.systemLocale).Replace('__USERLOCALE__', $loc.userLocale)
    # Product key (windowsPE UserData), the same XML the VM tests add for a VM:
    # 'generic' only. 'firmware' (MSDM key) and 'prompt' (Setup asks) carry none.
    $keyXml = ''
    if ($hw.productKey -eq 'generic') {
        $keyXml = "`n        <ProductKey><Key>$GenericProKey</Key><WillShowUI>OnError</WillShowUI></ProductKey>"
    }
    if (-not $xml.Contains('<!--__PRODUCTKEY__-->')) { throw 'config\autounattend.xml has no <!--__PRODUCTKEY__--> token' }
    $xml = $xml.Replace('<!--__PRODUCTKEY__-->', $keyXml)
    # First-logon commands after PostInstall (Order 1): the forced password
    # changes, then removal of the cached answer files (they hold the passwords).
    $cmds = @()
    # The ISO passwords are only obfuscated: both accounts must pick new ones.
    foreach ($acct in $AdminName, $UserName) {
        $cmds += , @("Require a new password for $acct at next sign-in",
            "powershell.exe -NoProfile -Command `"Set-LocalUser -Name '$acct' -PasswordNeverExpires `$false; net.exe user '$acct' /logonpasswordchg:yes`"")
    }
    # Not cmd's 'del a b': when one path is missing (Panther\Unattend usually is)
    # it deletes nothing at all, and the cached answer files would stay.
    $cmds += , @('Remove the cached answer files (they contain the account passwords)',
        "powershell.exe -NoProfile -Command `"Remove-Item -Force -ErrorAction SilentlyContinue -Path `$env:WINDIR\Panther\unattend*.xml, `$env:WINDIR\Panther\Unattend\unattend*.xml`"")
    $order = 2
    $block = ''
    foreach ($c in $cmds) {
        $block += @"
<SynchronousCommand wcm:action="add">
          <Order>$order</Order>
          <Description>$($c[0])</Description>
          <CommandLine>$($c[1])</CommandLine>
          <RequiresUserInput>false</RequiresUserInput>
        </SynchronousCommand>
        
"@
        $order++
    }
    $xml = $xml.Replace('<!--__FIRSTLOGON_COMMANDS__-->', $block.TrimEnd())
    $null = [xml]$xml   # throws if the result is not well-formed
    [IO.File]::WriteAllText("$media\autounattend.xml", $xml, (New-Object Text.UTF8Encoding $false))
    $adminPwB64 = $null; $userPwB64 = $null

    $manifest.mediaHashes = $mediaHashes
    $manifest | ConvertTo-Json -Depth 6 | Set-Content "$media\W11Kit-build-manifest.json" -Encoding UTF8

    # A test build's ISO says so in its name (the VM test and the CI workflows go by it)
    $ver = (($builtVersion -replace ' \(\+ updates\)$', '') -replace '^10\.0\.', '')
    $OutputIso = Join-Path $WorkRoot "Win11Pro-$($hw.isoTag)-$(if ($TestBuild) { 'TEST-' })$ver-$stamp.iso"
    # Volume label: max 32 characters (UDF); 'WIN11PRO_' + the tag, upper case; a test build's
    # ends in _TEST (the tag gives way), so a stick shows which kind it is in Explorer and Rufus
    $label = ('WIN11PRO_' + $hw.isoTag.ToUpperInvariant())
    $labelEnd = $(if ($TestBuild) { '_TEST' } else { '' })
    if ($label.Length + $labelEnd.Length -gt 32) { $label = $label.Substring(0, 32 - $labelEnd.Length) }
    $label += $labelEnd
    # What this stick is, readable on any PC before booting from it (no secrets)
    $stickLines = @(
        $(if ($TestBuild) { 'W11Kit TEST build: for a virtual machine only. Do NOT install it on a real PC.' } else { 'W11Kit install media (a real build).' }),
        '',
        "ISO:          $(Split-Path $OutputIso -Leaf)",
        "Built:        $($manifest.built) (build $stamp)",
        "Profile:      $($hw.id) ($($hw.displayName))",
        "Kit revision: $kitRevision",
        "Windows:      $builtVersion",
        '',
        'Installing from it ERASES the disk you choose in Windows Setup, completely.',
        "Its two one-time passwords are in $(Split-Path $accountsFile -Leaf) on the build PC, in the build's work folder;",
        'the last line of that file names this ISO. A passwords file that names another ISO does not fit this stick.',
        'Windows gets a security update every month: media more than a few weeks old is better rebuilt (docs\MONTHLY.md).')
    [IO.File]::WriteAllText("$media\W11KIT-THIS-STICK.txt", ($stickLines -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))
    Step "Building $OutputIso"
    $bootData = "2#p0,e,b$media\boot\etfsboot.com#pEF,e,b$efisys"
    # oscdimg prints progress on stderr: run it with 'Continue' so PS 5.1 does not
    # treat that as an error when output is captured; judge it by exit code only.
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $null = & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" "-l$label" $media $OutputIso 2>&1; $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($rc -ne 0) { throw "oscdimg failed ($rc)" }
    $isoHash = (Get-FileHash $OutputIso -Algorithm SHA256).Hash
    "$isoHash  $(Split-Path $OutputIso -Leaf)" | Set-Content "$OutputIso.sha256" -Encoding ASCII
    Copy-Item "$media\W11Kit-build-manifest.json" "$OutputIso.manifest.json" -Force
    # The ISO these passwords belong to (after the CMS block in an encrypted file: not secret;
    # Unprotect-CmsMessage reads the block and ignores text around it)
    if ($accountsFile) { [IO.File]::AppendAllText($accountsFile, "ISO: $(Split-Path $OutputIso -Leaf)  SHA-256 $isoHash`r`n") }

    Write-Host ''
    Write-Host 'BUILD COMPLETE.' -ForegroundColor Green
    Write-Host "ISO:    $OutputIso" -ForegroundColor Green
    Write-Host "SHA256: $isoHash" -ForegroundColor Green
    Write-Host "Built-in accounts (disabled): Administrator is renamed $builtinAdmin, Guest is renamed $builtinGuest$(if ($builtinGenerated.Count) { ' (drawn for this build; also in build-options.json on the installed PC)' })"
    # Never print the passwords: this console is transcribed into logs\build-*.txt.
    if ($accountsFile) {
        Write-Host "Accounts: $AdminName / $UserName, one-time passwords in $accountsFile (admins only$(if ($EncryptAccountsTo) { ', encrypted to your certificate' }); its last line names this ISO). Put them in a password manager you can open on another device (or on paper) BEFORE reinstalling this PC: the reinstall wipes C:, then delete the file" -ForegroundColor Yellow
        if (-not $EncryptAccountsTo) { Write-Host "  To open it: Start > type Notepad > right-click Notepad > Run as administrator > File > Open > $accountsFile" -ForegroundColor Yellow }
    }
    Remove-Item $media, $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "BUILD FAILED: $_" -ForegroundColor Red
    Clear-BuildState @($mount, $reMount, $bootMount)
    # The answer file holds this build's passwords (only obfuscated): never left behind.
    # The half-built media goes with it.
    Remove-Item -LiteralPath (Join-Path $media 'autounattend.xml') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $media, $scratch -Recurse -Force -ErrorAction SilentlyContinue
    # Half-made image files (several GB) go in any case: the next build starts from the source ISO
    foreach ($f in $work, $reWork, $reOut, $bootOut) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    # A half-written ISO (no .sha256 yet) carries the same answer file
    if ($OutputIso -and (Test-Path -LiteralPath $OutputIso) -and -not (Test-Path -LiteralPath "$OutputIso.sha256") -and (Get-Item -LiteralPath $OutputIso).LastWriteTime -ge $buildStart) { Remove-Item -LiteralPath $OutputIso -Force -ErrorAction SilentlyContinue }
    # Passwords that are in no ISO: deleted, and the previous accounts file is accounts.txt again
    if ($accountsFile -and (Test-Path -LiteralPath $accountsFile)) {
        Remove-Item -LiteralPath $accountsFile -Force -ErrorAction SilentlyContinue
        if ($accountsPrev -and (Test-Path -LiteralPath $accountsPrev)) { Rename-Item -LiteralPath $accountsPrev (Split-Path $accountsFile -Leaf) -ErrorAction SilentlyContinue }
        Write-Host "  This build's passwords are in no ISO: $accountsFile $(if ($accountsPrev) { 'is the previous build''s file again' } else { 'was deleted' })." -ForegroundColor Yellow
    }
    throw
}
finally {
    if ('W11Kit.Awake' -as [type]) { $null = [W11Kit.Awake]::SetThreadExecutionState([uint32]2147483648) }   # ES_CONTINUOUS: sleep allowed again
    if ($asrAdded) { Remove-MpPreference -AttackSurfaceReductionOnlyExclusions $asrExcl -ErrorAction SilentlyContinue }
    if ($defPaused) { try { Restore-DefenderProtection $defMarker } catch { Write-Warning "Defender protection NOT restored ($($_.Exception.Message)): the next build or Run-Prepare.cmd restores it from $defMarker" } }
    if ($transcribing) { Stop-Transcript | Out-Null }
    if ($buildMutex) { $buildMutex.Dispose() }
}
