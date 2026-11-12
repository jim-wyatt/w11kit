<#
.SYNOPSIS
    Verifies a mounted W11Kit install image with Microsoft's DISM cmdlets
    before it is committed. Run elevated. Build-Iso.ps1 calls it; it can
    also be run on its own against any mounted image.

    Checks: servicing level (UBR above the source), cumulative/.NET update
    packages installed, every curated driver present, the features in
    config\image.json enabled / not enabled, removed apps gone (and marked
    deprovisioned) and the required apps present, every registry value
    (Set-KitRegistry -Verify, with the staged profile's power mode and the
    staged settings.json), WinRE present,
    and (with -Final) every first-logon payload file, the staged security
    baseline data among them: each file as the importer's index.json in the
    work folder describes it, from the zip config\baselines pins.

    With -BootMedia <media folder>, -MountPath is instead a mounted boot.wim
    image (Windows Setup's) and only the media's boot side is checked: the
    cumulative update is installed in it (-ExpectLcuBuild), every storage driver
    the build added to it is in it (-BootDrivers), and the media's
    sources\setup.exe, sources\setuphost.exe and boot manager
    (efi\boot\bootx64.efi) are byte for byte the files in that image.

    Writes a report and throws if any check fails.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$MountPath,
    [Parameter(Mandatory)] [string]$KitRoot,
    [string]$DriverRoot = (Join-Path $KitRoot 'work\DriverExport\_Curated'),   # the build passes its own
    # The work folder's baselines folder: the data scripts\Import-Baseline.py made, which the
    # build staged as Baselines\ (checked with -Final)
    [string]$BaselineRoot = (Join-Path $KitRoot 'work\baselines'),               # the build passes its own
    # The profile's drivers.skipInf: INFs the build leaves out (regex on the file name)
    [string]$SkipInf,
    # Hardware profile id the build staged as profile.json (checked with -Final)
    [string]$ProfileId,
    [int]$MinUbr = 0,
    [switch]$Final,
    # Package family names the build marked deprovisioned (Build-Iso step 6)
    [string[]]$Deprovisioned,
    # Boot side only: the media folder whose Setup files and boot manager must match the
    # mounted boot.wim image in -MountPath (Build-Iso step 11)
    [string]$BootMedia,
    # With -BootMedia: INF file names of the storage drivers the build added to that image
    [string[]]$BootDrivers,
    # 'build.revision' of the cumulative update that image must hold (e.g. 26100.9550); empty: not checked
    [string]$ExpectLcuBuild,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$imageCfg = Get-Content -Raw (Join-Path $KitRoot 'config\image.json') | ConvertFrom-Json
$checks = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Area, [string]$Check, [bool]$Ok, [string]$Detail) {
    $checks.Add([pscustomobject]@{ Area = $Area; Check = $Check; Result = $(if ($Ok) { 'PASS' } else { 'FAIL' }); Detail = $Detail })
}
function Invoke-Quiet([scriptblock]$Block) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Block } finally { $ErrorActionPreference = $old }
}

# --- Boot side only (-BootMedia): the serviced boot.wim against the media -------------
if ($BootMedia) {
    $rollups = @(Get-WindowsPackage -Path $MountPath | Where-Object { $_.PackageName -match 'RollupFix~.*~~(\d+\.\d+)\.\d+\.\d+$' -and "$($_.PackageState)" -eq 'Installed' } |
        ForEach-Object { [regex]::Match($_.PackageName, '~~(\d+\.\d+)\.\d+\.\d+$').Groups[1].Value })
    if ($ExpectLcuBuild) {
        Add-Result 'boot.wim' "Cumulative update $ExpectLcuBuild installed in the Setup image" ($rollups -contains $ExpectLcuBuild) "installed: $(if ($rollups.Count) { $rollups -join ', ' } else { 'none' })"
    }
    # The curated storage drivers (classes SCSIAdapter, HDC) the build added: Setup needs
    # them to see the disk on a PC whose disk controller has no driver in Windows
    $wantDrv = @($BootDrivers | Where-Object { $_ } | ForEach-Object { "$_".ToLower() } | Sort-Object -Unique)
    if ($wantDrv.Count) {
        $haveDrv = @(Get-WindowsDriver -Path $MountPath | ForEach-Object { (Split-Path $_.OriginalFileName -Leaf).ToLower() } | Sort-Object -Unique)
        $missDrv = @($wantDrv | Where-Object { $haveDrv -notcontains $_ })
        Add-Result 'boot.wim' "Storage drivers in the Setup image ($($wantDrv.Count))" (-not $missDrv.Count) $(if ($missDrv.Count) { 'missing: ' + ($missDrv -join ', ') } else { $wantDrv -join ', ' })
    } else {
        Add-Result 'boot.wim' 'Storage drivers in the Setup image' $true 'none added (no storage drivers in the curated set)'
    }
    # The media's Setup binaries must be the ones inside boot.wim, or Windows Setup fails
    foreach ($n in 'setup.exe', 'setuphost.exe') {
        $inWim = Join-Path $MountPath "sources\$n"
        $onMedia = Join-Path $BootMedia "sources\$n"
        if (-not (Test-Path -LiteralPath $inWim)) {
            # setuphost.exe exists from Windows 11 24H2 on; setup.exe always
            if ($n -eq 'setup.exe') { Add-Result 'boot.wim' "sources\$n in the Setup image" $false 'missing' }
            continue
        }
        $same = (Test-Path -LiteralPath $onMedia) -and (Get-FileHash -LiteralPath $onMedia -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $inWim -Algorithm SHA256).Hash
        Add-Result 'Media' "sources\$n identical to the one in boot.wim" $same $(if (Test-Path -LiteralPath $onMedia) { [Diagnostics.FileVersionInfo]::GetVersionInfo($onMedia).FileVersion } else { 'missing on the media' })
    }
    # The same for every other file of boot.wim's sources\ that the media has too: one level
    # for the whole Setup engine (a setuphost.exe newer than SetupPlatform.dll stops Setup
    # with 0xC1900100)
    $wimSources = Join-Path $MountPath 'sources'
    if (Test-Path -LiteralPath $wimSources) {
        $wimSources = (Get-Item -LiteralPath $wimSources).FullName.TrimEnd('\')
        $shared = 0
        $differ = New-Object System.Collections.Generic.List[string]
        foreach ($f in @(Get-ChildItem -LiteralPath $wimSources -Recurse -File -Force)) {
            $rel = $f.FullName.Substring($wimSources.Length + 1)
            $onMedia = Join-Path (Join-Path $BootMedia 'sources') $rel
            if (-not (Test-Path -LiteralPath $onMedia -PathType Leaf)) { continue }
            $shared++
            if ((Get-FileHash -LiteralPath $onMedia -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash) { $differ.Add($rel) }
        }
        Add-Result 'Media' "Every Setup file shared with boot.wim is identical ($shared)" (-not $differ.Count) $(if ($differ.Count) { "$(@($differ | Select-Object -First 5) -join ', ')$(if ($differ.Count -gt 5) { ", ... ($($differ.Count))" })" } else { 'sources\ of the Setup image' })
    }
    # The media's boot manager: the serviced image's 2023-signed (_EX) or 2011-signed one
    $bm = Join-Path $BootMedia 'efi\boot\bootx64.efi'
    $bmHash = if (Test-Path -LiteralPath $bm) { (Get-FileHash -LiteralPath $bm -Algorithm SHA256).Hash } else { '' }
    $from = @('Windows\Boot\EFI_EX\bootmgfw_EX.efi', 'Windows\Boot\EFI\bootmgfw.efi' | Where-Object {
        $f = Join-Path $MountPath $_
        $bmHash -and (Test-Path -LiteralPath $f) -and (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -eq $bmHash
    })
    Add-Result 'Media' 'efi\boot\bootx64.efi is the boot manager of the serviced boot.wim' ([bool]$from.Count) $(if ($from.Count) { "$($from[0]), $([Diagnostics.FileVersionInfo]::GetVersionInfo($bm).FileVersion)" } elseif ($bmHash) { 'differs from both bootmgfw_EX.efi and bootmgfw.efi in the image' } else { 'missing on the media' })

    $fails = @($checks | Where-Object Result -eq 'FAIL')
    $text = $checks | Format-Table Area, Check, Result, Detail -AutoSize -Wrap | Out-String -Width 220
    Write-Host $text
    if ($ReportPath) { $text | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
    if ($fails.Count) { throw "Boot media verification failed: $($fails.Count) check(s). See the table above." }
    Write-Host 'Boot media verification passed.' -ForegroundColor Green
    return
}

# --- Servicing level ------------------------------------------------------------
$hive = Join-Path $MountPath 'Windows\System32\config\SOFTWARE'
$rc = Invoke-Quiet { $null = & reg.exe load 'HKLM\W11KV_SOFTWARE' $hive 2>&1; $LASTEXITCODE }
if ($rc -eq 0) {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('W11KV_SOFTWARE\Microsoft\Windows NT\CurrentVersion')
        $build = $k.GetValue('CurrentBuild'); $ubr = [int]$k.GetValue('UBR'); $edition = $k.GetValue('EditionID'); $disp = $k.GetValue('DisplayVersion')
        $k.Close()
    } finally {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        $null = Invoke-Quiet { & reg.exe unload 'HKLM\W11KV_SOFTWARE' 2>&1 }
    }
    Add-Result 'Servicing' 'Edition is Professional' ($edition -eq 'Professional') "$edition $disp"
    Add-Result 'Servicing' "Build updated past source (UBR > $MinUbr)" ($ubr -gt $MinUbr) "$build.$ubr"
} else {
    Add-Result 'Servicing' 'Read image version' $false 'could not load SOFTWARE hive'
}

# --- Update packages -------------------------------------------------------------
$pkgs = @(Get-WindowsPackage -Path $MountPath)
# The newest installed cumulative update must be newer than the source image.
# (Microsoft's stock image already lists older RollupFix packages as Staged or
# Superseded; that is normal and not checked.)
$rollup = @($pkgs | Where-Object { $_.PackageName -match 'RollupFix~.*~~\d+\.(\d+)\.' -and $_.PackageState -eq 'Installed' } |
    ForEach-Object { [pscustomobject]@{ Name = $_.PackageName; Ubr = [int]([regex]::Match($_.PackageName, '~~\d+\.(\d+)\.').Groups[1].Value) } })
$newest = $rollup | Sort-Object Ubr -Descending | Select-Object -First 1
Add-Result 'Updates' "Cumulative update newer than source ($MinUbr) installed" ([bool]$newest -and $newest.Ubr -gt $MinUbr) "$($newest.Name)"
$pending = @($pkgs | Where-Object { $_.PackageState -match 'Pending' })
Add-Result 'Updates' 'No package operation left pending' ($pending.Count -eq 0) (($pending | ForEach-Object { "$($_.PackageName)=$($_.PackageState)" }) -join '; ')

# --- Drivers ---------------------------------------------------------------------
$wantInf = @(Get-ChildItem $DriverRoot -Recurse -File -Filter *.inf | Where-Object Extension -eq '.inf' | Where-Object { -not $SkipInf -or $_.Name -notmatch $SkipInf } | ForEach-Object { $_.Name.ToLower() } | Sort-Object -Unique)
$haveInf = @(Get-WindowsDriver -Path $MountPath | ForEach-Object { (Split-Path $_.OriginalFileName -Leaf).ToLower() } | Sort-Object -Unique)
$missing = @($wantInf | Where-Object { $haveInf -notcontains $_ })
Add-Result 'Drivers' "All $($wantInf.Count) curated drivers in the image" ($missing.Count -eq 0) $(if ($missing.Count) { 'missing: ' + ($missing -join ', ') } else { "$($haveInf.Count) third-party driver packages" })

# --- Optional features -----------------------------------------------------------
$feat = @{}
Get-WindowsOptionalFeature -Path $MountPath | ForEach-Object { $feat[$_.FeatureName] = "$($_.State)" }
foreach ($f in @($imageCfg.features.enable)) {
    Add-Result 'Features' "$f enabled" ($feat[$f] -match '^Enable') "$($feat[$f])"
}
foreach ($f in @(@($imageCfg.features.mustNotBeEnabled) + @($imageCfg.features.disable) | Sort-Object -Unique)) {
    if ($feat.ContainsKey($f)) { Add-Result 'Features' "$f not enabled" ($feat[$f] -notmatch '^Enable') "$($feat[$f])" }
}

# --- Provisioned apps --------------------------------------------------------------
$prov = @(Get-AppxProvisionedPackage -Path $MountPath | ForEach-Object DisplayName)
$rm = Get-Content -Raw (Join-Path $KitRoot 'config\removal-manifest.json') | ConvertFrom-Json
$still = @($rm.remove | ForEach-Object name | Where-Object { $prov -contains $_ })
Add-Result 'Apps' 'Removed apps are gone' ($still.Count -eq 0) $(if ($still.Count) { 'still present: ' + ($still -join ', ') } else { "$($prov.Count) provisioned apps remain" })
# image.json 'gamingApps' are required only with options.gamingTweaks in the staged settings
# (not staged yet, or not readable: every app in the list is required)
$stagedSet = try { [IO.File]::ReadAllText((Join-Path $MountPath 'ProgramData\W11Kit\settings.json')) | ConvertFrom-Json } catch { $null }
$gamingOn = -not $stagedSet -or $stagedSet.options.gamingTweaks -eq $true
$gamingApps = @($imageCfg.gamingApps | Where-Object { $_ })
$lost = @(@($imageCfg.requiredApps) | Where-Object { $_ -and ($gamingOn -or $gamingApps -notcontains $_) -and $prov -notcontains $_ })
Add-Result 'Apps' 'Required apps (config\image.json) present' ($lost.Count -eq 0) $(if ($lost.Count) { 'missing: ' + ($lost -join ', ') } else { "all present$(if (-not $gamingOn) { ' (the gaming apps are not required: options.gamingTweaks is off)' })" })
if ($Deprovisioned) {
    # reg.exe (not the registry provider) so no handle keeps the hive loaded
    $depHive = 'HKLM\W11KV_SOFTWARE'
    Invoke-Quiet { $null = & reg.exe load $depHive (Join-Path $MountPath 'Windows\System32\config\SOFTWARE') 2>&1 }
    if ($LASTEXITCODE -ne 0) {
        Add-Result 'Apps' 'Removed apps marked deprovisioned' $false 'could not load the offline SOFTWARE hive'
    } else {
        try {
            $missing = @($Deprovisioned | Where-Object {
                Invoke-Quiet { $null = & reg.exe query "$depHive\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$_" 2>&1 }
                $LASTEXITCODE -ne 0
            })
        } finally { Invoke-Quiet { $null = & reg.exe unload $depHive 2>&1 } }
        Add-Result 'Apps' 'Removed apps marked deprovisioned' ($missing.Count -eq 0) $(if ($missing.Count) { 'missing: ' + ($missing -join ', ') } else { "$($Deprovisioned.Count) package families" })
    }
}

# --- Registry (every value the kit sets) --------------------------------------------
try {
    $sb = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $KitRoot 'scripts\Set-KitRegistry.ps1')))
    # The staged hardware profile decides the power values (hibernate or Windows' default)
    $staged = try { [IO.File]::ReadAllText((Join-Path $MountPath 'ProgramData\W11Kit\profile.json')) | ConvertFrom-Json } catch { $null }
    $pm = if ($staged -and "$($staged.power.mode)" -in 'hibernate', 'default') { "$($staged.power.mode)" } else { 'hibernate' }
    # ...and the staged settings the home location and the options (gaming, Smart App
    # Control, Brave, long paths, Microsoft account). Not staged: every option off (the Payload row fails).
    $stagedSettings = Join-Path $MountPath 'ProgramData\W11Kit\settings.json'
    $setArg = @{}
    if (Test-Path -LiteralPath $stagedSettings) { $setArg.Settings = $stagedSettings }
    $regOut = & $sb -Mode Offline -MountPath $MountPath -Verify -PowerMode $pm @setArg 6>&1 | Out-String
    Add-Result 'Registry' 'All kit registry values correct' $true (($regOut -split "`n" | Where-Object { $_ -match 'Registry verify' }) -join ' ').Trim()
} catch {
    Add-Result 'Registry' 'All kit registry values correct' $false $_.Exception.Message
}

# --- WinRE ----------------------------------------------------------------------------
$re = Get-Item (Join-Path $MountPath 'Windows\System32\Recovery\Winre.wim') -Force -ErrorAction SilentlyContinue
Add-Result 'WinRE' 'Winre.wim present' ([bool]$re -and $re.Length -gt 300MB) $(if ($re) { '{0:N0} MB' -f ($re.Length / 1MB) } else { 'missing' })

# --- First-logon payload ------------------------------------------------------------------
if ($Final) {
    # Everything Build-Iso stages: the kit's payload folder (by name), the files
    # it adds next to it, the baselines' data and the Default profile's files.
    $staged = @(Get-ChildItem (Join-Path $KitRoot 'payload') -File | ForEach-Object Name) +
              'Set-KitRegistry.ps1', 'removal-manifest.json', 'image.json', 'baseline-overrides.txt', 'baseline-overrides.inf', 'baseline-overrides-audit.csv', 'build-options.json', 'profile.json', 'settings.json'
    # The security baselines: the list and each baseline's pins from config\baselines, and
    # the imported data from the work folder (index.json and the files it lists). Every
    # staged data file must be the one that index describes, from the pinned zip.
    $blPins = Join-Path $KitRoot 'config\baselines'
    $staged += 'Baselines\baselines.json'
    $blBad = New-Object System.Collections.Generic.List[string]
    $blFiles = 0
    $blIds = @(try { @(([IO.File]::ReadAllText((Join-Path $blPins 'baselines.json')) | ConvertFrom-Json).apply | Where-Object { $_ }) } catch { $blBad.Add("config\baselines\baselines.json: $($_.Exception.Message)") })
    foreach ($id in $blIds) {
        $staged += "Baselines\$id\source.json", "Baselines\$id\index.json"
        try {
            $pin = [IO.File]::ReadAllText((Join-Path $blPins "$id\source.json")) | ConvertFrom-Json
            $ix = [IO.File]::ReadAllText((Join-Path $BaselineRoot "$id\index.json")) | ConvertFrom-Json
            if ("$($ix.source.sha256)" -ne "$($pin.sha256)") { $blBad.Add("${id}: imported from a zip with SHA-256 $($ix.source.sha256), not the pinned $($pin.sha256)") }
            $stagedDir = Join-Path $MountPath "ProgramData\W11Kit\Baselines\$id"
            foreach ($n in 'source.json', 'index.json') {
                $src = if ($n -eq 'source.json') { Join-Path $blPins "$id\$n" } else { Join-Path $BaselineRoot "$id\$n" }
                $dst = Join-Path $stagedDir $n
                if ((Test-Path -LiteralPath $dst) -and (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash) { $blBad.Add("$id\$n differs from $src") }
            }
            foreach ($p in $ix.files.PSObject.Properties) {
                $staged += "Baselines\$id\$($p.Name)"
                $blFiles++
                $dst = Join-Path $stagedDir $p.Name
                if ((Test-Path -LiteralPath $dst) -and (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ne "$($p.Value)".ToUpperInvariant()) { $blBad.Add("$id\$($p.Name) is not the file index.json describes") }
            }
        } catch { $blBad.Add("${id}: $($_.Exception.Message)") }
    }
    Add-Result 'Payload' "Security baseline data staged as imported from the pinned zips ($($blIds -join ', '))" (-not $blBad.Count) $(if ($blBad.Count) { $blBad -join '; ' } else { "$blFiles data files, SHA-256 as in each index.json" })
    # The build stages the driver inventory only when the harvest left one next to the drivers
    if (Test-Path (Join-Path (Split-Path $DriverRoot -Parent) 'DRIVER-INVENTORY.md')) { $staged += 'DRIVER-INVENTORY.md' }
    $files = @($staged | ForEach-Object { "ProgramData\W11Kit\$_" }) +
             'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json', 'Users\Default\.wslconfig'
    $absent = @($files | Where-Object { -not (Test-Path (Join-Path $MountPath $_)) })
    Add-Result 'Payload' "All $($files.Count) first-logon files staged" ($absent.Count -eq 0) $(if ($absent.Count) { 'missing: ' + ($absent -join ', ') } else { 'all present' })
    try {
        $opts = Get-Content -Raw (Join-Path $MountPath 'ProgramData\W11Kit\build-options.json') | ConvertFrom-Json
        Add-Result 'Payload' 'build-options.json readable' ([bool]$opts.AdminName -and [bool]$opts.UserName) "admin=$($opts.AdminName) daily=$($opts.UserName)"
    } catch { Add-Result 'Payload' 'build-options.json readable' $false $_.Exception.Message }
    # The staged security template renames the built-in Administrator and Guest accounts to
    # the names build-options.json records (per build, or from the settings), and carries the
    # Xbox services' override only with options.gamingTweaks.
    try {
        $infText = [IO.File]::ReadAllText((Join-Path $MountPath 'ProgramData\W11Kit\baseline-overrides.inf'))
        $infAdm = if ($infText -match '(?m)^\s*NewAdministratorName\s*=\s*"([^"\r\n]+)"\s*$') { $Matches[1] } else { '' }
        $infGst = if ($infText -match '(?m)^\s*NewGuestName\s*=\s*"([^"\r\n]+)"\s*$') { $Matches[1] } else { '' }
        $namesOk = $infAdm -match '^[A-Za-z0-9._-]{1,20}$' -and $infGst -match '^[A-Za-z0-9._-]{1,20}$' -and $infAdm -ne $infGst -and
                   $infAdm -notin 'Administrator', 'Guest', $opts.AdminName, $opts.UserName -and $infGst -notin 'Administrator', 'Guest', $opts.AdminName, $opts.UserName -and
                   $infAdm -ceq "$($opts.BuiltinAdministratorName)" -and $infGst -ceq "$($opts.BuiltinGuestName)"
        Add-Result 'Payload' 'Built-in Administrator and Guest: new names staged (baseline-overrides.inf = build-options.json)' $namesOk "template: $infAdm / $infGst; build-options: $($opts.BuiltinAdministratorName) / $($opts.BuiltinGuestName)"
        $xboxLines = @([regex]::Matches($infText, '(?m)^\s*"(Xbox|Xbl)[A-Za-z]+"\s*,\s*3\s*,')).Count
        Add-Result 'Payload' 'Xbox services override follows options.gamingTweaks' ($(if ($gamingOn) { $xboxLines -eq 4 } else { $xboxLines -eq 0 })) "gamingTweaks $(if ($gamingOn) { 'on' } else { 'off' }): $xboxLines Xbox service line(s) in the staged template"
        $secStart = if ($infText -match '(?m)^\s*"seclogon"\s*,\s*(\d)\s*,') { $Matches[1] } else { 'none' }
        Add-Result 'Payload' 'Secondary Logon follows options.gamingTweaks (Manual with it, else Disabled)' ($secStart -eq $(if ($gamingOn) { '3' } else { '4' })) "gamingTweaks $(if ($gamingOn) { 'on' } else { 'off' }): seclogon start type $secStart in the staged template"
    } catch { Add-Result 'Payload' 'Built-in Administrator and Guest: new names staged (baseline-overrides.inf = build-options.json)' $false $_.Exception.Message }
    # The Start layout: valid JSON with pins; the gaming apps' pins only with options.gamingTweaks
    try {
        $pins = @(([IO.File]::ReadAllText((Join-Path $MountPath 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json')) | ConvertFrom-Json).pinnedList)
        $gamePins = @($pins | Where-Object { $id = "$($_.packagedAppId)"; @($gamingApps | Where-Object { $id.StartsWith("${_}_", [StringComparison]::OrdinalIgnoreCase) }).Count })
        Add-Result 'Payload' 'Start layout readable; gaming pins follow options.gamingTweaks' ($pins.Count -gt 0 -and ($gamingOn -or -not $gamePins.Count)) "$($pins.Count) pins, $($gamePins.Count) for gaming apps (gamingTweaks $(if ($gamingOn) { 'on' } else { 'off' }))"
    } catch { Add-Result 'Payload' 'Start layout readable; gaming pins follow options.gamingTweaks' $false $_.Exception.Message }
    try {
        $hp = [IO.File]::ReadAllText((Join-Path $MountPath 'ProgramData\W11Kit\profile.json')) | ConvertFrom-Json
        $ok = [bool]$hp.id -and (-not $ProfileId -or $hp.id -eq $ProfileId) -and $hp.id -eq $opts.Profile
        Add-Result 'Payload' 'profile.json readable, same profile as build-options.json' $ok "profile.json=$($hp.id) build-options=$($opts.Profile)$(if ($ProfileId) { " build=$ProfileId" })"
    } catch { Add-Result 'Payload' 'profile.json readable, same profile as build-options.json' $false $_.Exception.Message }
}

# --- Report -------------------------------------------------------------------------------
$fails = @($checks | Where-Object Result -eq 'FAIL')
$text = $checks | Format-Table Area, Check, Result, Detail -AutoSize -Wrap | Out-String -Width 220
Write-Host $text
if ($ReportPath) { $text | Set-Content -LiteralPath $ReportPath -Encoding UTF8 }
if ($fails.Count) { throw "Image verification failed: $($fails.Count) check(s). See the table above." }
Write-Host 'Image verification passed.' -ForegroundColor Green
