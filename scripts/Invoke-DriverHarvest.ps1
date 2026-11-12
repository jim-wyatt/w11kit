<#
.SYNOPSIS
    Harvests every driver from the running PC and builds the curated set
    for one hardware profile (docs\reference\PROFILES.md). Run elevated.

.DESCRIPTION
    Everything goes into the kit's work folder (-WorkRoot, default <KitRoot>\work,
    e.g. C:\W11Kit\work): the export in <work>\DriverExport, its archive next
    to it.

    1. Export-WindowsDriver -Online -Destination <work>\DriverExport
    2. pnputil / driverquery / Get-ComputerInfo / msinfo32 reports
    3. Driver inventory report (DRIVER-INVENTORY.md + CSV)
    4. Curated set in <work>\DriverExport\_Curated (see docs\reference\DRIVERS.md):
       providers from the profile's drivers.providers, INF names in drivers.skipInf
       never, firmware capsules never
       + _Reports\curated-sha256.txt: the SHA-256 of every file in _Curated (the
       build checks _Curated against it and stops on any change or addition)
    5. Platform/sleep diagnostics (a report: _Reports\platform-diagnostics.txt)
    6. <work>\DriverExport.zip + SHA256
    Nothing on this PC is changed: the harvest only reads and writes its export.
    The export and the .zip/.sha256 are writable by administrators only
    (scripts\KitAcl.ps1: owner Administrators, users may read), like the build's
    other folders: the elevated build adds these drivers to the image.

.PARAMETER Profile
    Hardware profile id (profiles\<id>\profile.json). Default: the profile whose
    match fits this PC, else 'generic'. The drivers always come from the running
    PC: a profile whose match does not fit it gets a loud warning.
.PARAMETER KitRoot
    Folder containing the kit (scripts\, config\...). Needed when the script
    is launched as a scriptblock (Run-Harvest.cmd), where $PSScriptRoot is empty.
.PARAMETER WorkRoot
    The kit's work folder. Default <KitRoot>\work (the same default as the build's
    -WorkRoot: give both the same folder if you change it). The export is
    <WorkRoot>\DriverExport, the archive <WorkRoot>\DriverExport.zip, and the
    build adds the drivers in <WorkRoot>\DriverExport\_Curated.
.PARAMETER SkipArchive
    Don't write DriverExport.zip (a real build needs it for its build inputs).
.PARAMETER CurateOnly
    Rebuild only _Curated, its SHA-256 manifest and the archive from an existing
    export (after a profile change, or after you changed _Curated on purpose).
#>
[CmdletBinding()]
param(
    [string]$WorkRoot,      # default: <KitRoot>\work
    [string]$KitRoot,
    # -Profile (not $Profile: that is PowerShell's automatic profile-path variable)
    [Alias('Profile')] [string]$HardwareProfile,
    [switch]$SkipArchive,
    # Rebuild only _Curated (and the archive) from an existing export
    [switch]$CurateOnly
)

$ErrorActionPreference = 'Stop'
if (-not $KitRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
$KitRoot = $KitRoot.TrimEnd('\')
if (-not $WorkRoot) { $WorkRoot = Join-Path $KitRoot 'work' }
$Destination = Join-Path $WorkRoot.TrimEnd('\') 'DriverExport'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run elevated (use Run-Harvest.cmd).' }

# Hardware profile: which driver providers to carry (docs\reference\PROFILES.md)
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitProfile.ps1'))))
$prof = Resolve-KitProfile -KitRoot $KitRoot -Id $HardwareProfile
$hw = $prof.Profile
# '.' = every third-party provider; Microsoft-provided packages (in-box class
# drivers republished as third-party, e.g. Voice Clarity) are left to Windows.
$providers = $hw.drivers.providers
$skipInf = $hw.drivers.skipInf
function Test-CarriedProvider([string]$Name) {
    ($Name -match $providers) -and -not ($providers -eq '.' -and $Name -match '^Microsoft')
}

function Invoke-KitScript([string]$RelPath, [hashtable]$Params = @{}) {
    $p = Join-Path $KitRoot $RelPath
    $sb = [scriptblock]::Create((Get-Content -Raw -LiteralPath $p))
    & $sb @Params
}

function Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }

# The export: writable by administrators only (the elevated build puts these drivers into the image)
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitAcl.ps1'))))
function Lock-Export([string]$Path) {
    $bad = @(Lock-KitPath $Path)
    if ($bad.Count) { throw "Could not make $Path writable by administrators only: $($bad -join '; ')" }
}

if ($CurateOnly) {
    if (-not (Test-Path (Join-Path $Destination '_Reports\export-index.csv'))) { throw "No existing export at $Destination (-CurateOnly re-curates an earlier export): run Run-Harvest.cmd without -CurateOnly first." }
    Lock-Export $Destination   # before anything in it is read
} elseif ((Test-Path $Destination) -and (Get-ChildItem $Destination -Force | Select-Object -First 1)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Write-Warning "$Destination is not empty; moving it to $Destination.$stamp"
    Move-Item $Destination "$Destination.$stamp"
}
# A work folder this creates is writable by administrators only from the start, like the build makes it
$destParent = Split-Path $Destination -Parent
if ($destParent -and -not (Test-Path -LiteralPath $destParent)) { New-KitLockedFolder $destParent }
if (Test-Path -LiteralPath $Destination) { Lock-Export $Destination } else { New-KitLockedFolder $Destination }
$reports = Join-Path $Destination '_Reports'
New-Item -ItemType Directory -Path $reports -Force | Out-Null
$transcriptName = if ($CurateOnly) { 'curate-transcript.txt' } else { 'harvest-transcript.txt' }
Start-Transcript -Path (Join-Path $reports $transcriptName) | Out-Null
# After the transcript starts, so the choice (and a mismatch) is on record
Write-Host "Hardware profile: $($hw.id) ($($hw.displayName)): $($prof.Reason)." -ForegroundColor Cyan
Write-Host "  drivers.providers: $($hw.drivers.providers)   drivers.skipInf: $(if ($hw.drivers.skipInf) { $hw.drivers.skipInf } else { '(none)' })"
if ($prof.FitsPc -eq $false) {
    $warn = "PROFILE MISMATCH: profile '$($hw.id)' is for $($hw.match.manufacturer) / $($hw.match.model), but this PC is $($prof.PcManufacturer) $($prof.PcModel). " +
            "The harvest exports the drivers of THIS PC: an image built from them will lack the drivers of the profile's hardware."
    1..3 | ForEach-Object { Write-Warning $warn }
}

try {
  if ($CurateOnly) {
    $exportIndex = Import-Csv (Join-Path $reports 'export-index.csv')
  } else {
    # --- 1. Export ---------------------------------------------------------
    Step 'Export-WindowsDriver -Online'
    $exported = @(Export-WindowsDriver -Online -Destination $Destination)
    $exportIndex = $exported | ForEach-Object {
        [pscustomobject]@{
            Driver           = $_.Driver
            OriginalFileName = $_.OriginalFileName
            InfName          = Split-Path $_.OriginalFileName -Leaf
            Folder           = Split-Path (Split-Path $_.OriginalFileName -Parent) -Leaf
            ClassName        = $_.ClassName
            ProviderName     = $_.ProviderName
            Version          = $_.Version
            Date             = $_.Date.ToString('yyyy-MM-dd')
            BootCritical     = $_.BootCritical
        }
    }
    $exportIndex | Export-Csv (Join-Path $reports 'export-index.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($exported.Count) driver packages."

    # --- 2. Requested collection ------------------------------------------
    Step 'pnputil / driverquery / Get-ComputerInfo / msinfo32'
    & pnputil.exe /enum-drivers | Out-File (Join-Path $Destination 'pnputil-drivers.txt') -Encoding UTF8
    & pnputil.exe /enum-devices /drivers | Out-File (Join-Path $reports 'pnputil-devices-drivers.txt') -Encoding UTF8
    & driverquery.exe /v /fo csv | Out-File (Join-Path $Destination 'driverquery.csv') -Encoding UTF8
    Get-ComputerInfo | Out-File (Join-Path $Destination 'computerinfo.txt') -Encoding UTF8 -Width 300
    # msinfo32 can hang: give it 3 minutes, then carry on without its report.
    $msinfoReport = Join-Path $Destination 'msinfo32.txt'
    $mi = Start-Process msinfo32.exe -ArgumentList '/report', $msinfoReport -PassThru
    if (-not $mi.WaitForExit(180000)) {
        try { $mi.Kill() } catch { }
        Remove-Item -LiteralPath $msinfoReport -ErrorAction SilentlyContinue   # partial report
        Write-Warning 'msinfo32 /report did not finish within 3 minutes: stopped; the harvest continues without msinfo32.txt.'
    }

    # --- 3. Inventory -----------------------------------------------------
    Step 'Driver inventory report'
    Invoke-KitScript 'scripts\New-DriverInventory.ps1' @{ OutDir = $Destination }
  }

    # --- 4. Curated set ---------------------------------------------------
    Step 'Building curated driver set'
    # The profile this set is curated for (Build-Iso notes a build for another profile)
    Copy-Item -LiteralPath $prof.Path (Join-Path $reports 'harvest-profile.json') -Force
    $bound = @{}
    Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.InfName -like 'oem*.inf' } | ForEach-Object { $bound[$_.InfName.ToLower()] = $true }

    # Firmware capsules (Lenovo system/EC/device firmware) never go into the image:
    # staged in a fresh install they could reflash the firmware. BIOS updates stay manual.
    $candidates = $exportIndex | Where-Object {
        (Test-CarriedProvider $_.ProviderName) -and $_.ClassName -ne 'Firmware'
    }

    $curated = New-Object System.Collections.Generic.List[object]
    $excluded = New-Object System.Collections.Generic.List[object]
    foreach ($group in ($candidates | Group-Object InfName)) {
        $boundInGroup = @($group.Group | Where-Object { $bound[$_.Driver.ToLower()] })
        if ($boundInGroup.Count) {
            # Preference 1: the package the running system actually uses
            $pick = $boundInGroup
            $reason = 'bound to a device on the running system'
        } elseif ($skipInf -and $group.Name -match $skipInf) {
            # The profile's drivers.skipInf (e.g. superseded AMD Adrenalin display
            # packages, which use per-release INF names)
            $pick = @()
            $reason = ''
        } elseif (@($group.Group | Where-Object { $_.ClassName -in 'Extension', 'SoftwareComponent', 'AudioProcessingObject' }).Count) {
            # Extension / component INFs attach to a base device and never show
            # as its main driver; they only apply where the hardware ID matches.
            $pick = @($group.Group | Sort-Object { [version]$_.Version }, Date -Descending | Select-Object -First 1)
            $reason = 'newest extension/component package for this INF'
        } else {
            # Device drivers for hardware this machine does not have
            $pick = @()
            $reason = ''
        }
        foreach ($d in $group.Group) {
            if ($pick -contains $d) { $curated.Add(($d | Select-Object *, @{ n = 'Reason'; e = { $reason } })) }
            else { $excluded.Add(($d | Select-Object *, @{ n = 'Reason'; e = { 'superseded version, or a device driver for hardware not in this machine' } })) }
        }
    }
    $exportIndex | Where-Object { $candidates -notcontains $_ } | ForEach-Object {
        $why = if ($_.ClassName -eq 'Firmware') { 'firmware capsule (BIOS/EC updates stay manual)' } else { 'provider not in the profile''s drivers.providers (installed later by its app or Windows Update)' }
        $excluded.Add(($_ | Select-Object *, @{ n = 'Reason'; e = { $why } }))
    }

    $curatedRoot = Join-Path $Destination '_Curated'
    if (Test-Path $curatedRoot) { Remove-Item $curatedRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $curatedRoot -Force | Out-Null
    foreach ($d in $curated) {
        Copy-Item -LiteralPath (Join-Path $Destination $d.Folder) -Destination $curatedRoot -Recurse -Force
    }
    # SHA-256 of every curated file: the build checks _Curated against it (nothing changed or added)
    $curRoot = (Resolve-Path -LiteralPath $curatedRoot).ProviderPath.TrimEnd('\')
    $shaLines = @(Get-ChildItem -LiteralPath $curRoot -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)  $($_.FullName.Substring($curRoot.Length + 1))"
    })
    [IO.File]::WriteAllLines((Join-Path $reports 'curated-sha256.txt'), [string[]]$shaLines)
    Write-Host "SHA-256 manifest: $(Join-Path $reports 'curated-sha256.txt') ($($shaLines.Count) files)"
    $curated | Sort-Object ClassName, InfName | Export-Csv (Join-Path $reports 'curated-drivers.csv') -NoTypeInformation -Encoding UTF8
    $excluded | Sort-Object Reason, InfName | Export-Csv (Join-Path $reports 'excluded-drivers.csv') -NoTypeInformation -Encoding UTF8
    Write-Host "Curated: $($curated.Count) packages. Excluded: $($excluded.Count)."
    $curated | Sort-Object ClassName, InfName | Format-Table ClassName, InfName, Version, ProviderName -AutoSize | Out-String -Width 200 | Write-Host

    # Every third-party INF bound to present hardware from a carried provider must be curated
    $missing = Get-CimInstance Win32_PnPSignedDriver | Where-Object {
        $_.InfName -like 'oem*.inf' -and (Test-CarriedProvider $_.DriverProviderName) -and $_.DeviceClass -ne 'FIRMWARE' -and
        -not ($curated | Where-Object Driver -eq $_.InfName)
    }
    if ($missing) {
        $missing | Format-Table DeviceName, InfName, DriverProviderName -AutoSize | Out-String | Write-Warning
        throw 'Some bound platform drivers are missing from the curated set.'
    }

  if (-not $CurateOnly) {
    # --- 5. Platform diagnostics (read-only) -----------------------------
    Step 'Platform and sleep diagnostics'
    $diag = New-Object System.Collections.Generic.List[string]
    $diag.Add("Secure Boot enabled: $(try { Confirm-SecureBootUEFI } catch { $_.Exception.Message })")
    try {
        $db = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI -Name db).Bytes)
        $diag.Add("Secure Boot DB has 'Windows UEFI CA 2023': $($db -match 'Windows UEFI CA 2023')")
        $diag.Add("Secure Boot DB has 'Windows Production PCA 2011': $($db -match 'Windows Production PCA 2011')")
    } catch { $diag.Add("Secure Boot DB read failed: $($_.Exception.Message)") }
    $tpm = Get-Tpm
    $diag.Add("TPM present/ready: $($tpm.TpmPresent)/$($tpm.TpmReady); version: $((Get-CimInstance -Namespace root/cimv2/security/microsofttpm -ClassName Win32_Tpm).SpecVersion)")
    $diag.Add('')
    $diag.Add('--- powercfg /a ---')
    $diag.AddRange([string[]](& powercfg.exe /a))
    $diag | Set-Content (Join-Path $reports 'platform-diagnostics.txt') -Encoding UTF8
    $diag | Write-Host

    # Devices Windows can't run today: the image carries what works NOW, and Windows Update
    # delivers no drivers afterwards, so these stay broken unless fixed before the build.
    # [int]: once the PnpDevice module is loaded (the inventory above uses it), PowerShell shows
    # this property as a name (CM_PROB_FAILED_INSTALL), not as the number the hint below explains
    $broken = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { [int]$_.ConfigManagerErrorCode -and [int]$_.ConfigManagerErrorCode -notin 22, 45 })
    $brokenLines = @($broken | Sort-Object Name | ForEach-Object { "code $([int]$_.ConfigManagerErrorCode): $(if ($_.Name) { $_.Name } else { '(no name)' })  [$($_.PNPDeviceID)]" })
    $brokenLines | Set-Content (Join-Path $reports 'devices-not-working.txt') -Encoding UTF8
    if ($broken.Count) {
        Write-Host ''
        Write-Warning "$($broken.Count) device(s) are not working on this PC now (code 28 = no driver installed):"
        $brokenLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        Write-Host '  They will not work after the reinstall either. If you need one: install its driver from the PC or' -ForegroundColor Yellow
        Write-Host '  device maker now, then run Run-Harvest.cmd again. (docs\AFTER-INSTALL.md, "A device without a driver")' -ForegroundColor Yellow
    } else { Write-Host 'Devices: none in an error state (disabled or unplugged devices are not counted).' }
  }

    # --- 6. Archive -------------------------------------------------------
    if (-not $SkipArchive) {
        Step 'Archiving'
        Stop-Transcript | Out-Null
        $zip = "$Destination.zip"
        # Old copies: taken over first (a file another user planted there may deny admins)
        foreach ($f in $zip, "$zip.sha256") { if (Test-Path -LiteralPath $f) { Lock-Export $f; Remove-Item -LiteralPath $f -Force } }
        & tar.exe -a -c -f $zip -C (Split-Path $Destination -Parent) (Split-Path $Destination -Leaf)
        if ($LASTEXITCODE -ne 0) { throw 'tar failed to create the archive' }
        Lock-Export $zip   # before it is hashed
        $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
        "$hash  $(Split-Path $zip -Leaf)" | Set-Content "$zip.sha256" -Encoding ASCII
        Lock-Export "$zip.sha256"
        Write-Host "Archive: $zip ($([math]::Round((Get-Item $zip).Length/1MB)) MB) SHA256 $hash"
    }
    Write-Host ''
    Write-Host 'Harvest complete.' -ForegroundColor Green
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
