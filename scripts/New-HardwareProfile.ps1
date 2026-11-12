<#
.SYNOPSIS
    Writes a hardware profile (profiles\<id>\profile.json, docs\reference\PROFILES.md) for
    the PC it runs on, read from the running install. Changes nothing else.

.DESCRIPTION
    Works without elevation (elevation adds nothing it reads). New-Profile.cmd runs
    it elevated anyway: after the first build the kit folder is writable by
    administrators only (scripts\KitAcl.ps1), and the profile is written into it.
    Reads: Win32_ComputerSystem (match, names), the firmware licence (only
    WHETHER an OEM key exists and its edition description: the key itself is
    never read into the output, printed or stored), the drivers bound to present
    devices (drivers.providers), powercfg /a, Kernel DMA Protection, display /
    sound / network / Bluetooth devices (checks), and with -WakeOnLan the wired
    adapter's advanced properties.

    drivers.providers: the vendors of third-party (oemNN.inf) drivers bound to
    present, internal hardware (PCI/ACPI/HDAUDIO/USB/... devices in the PC's own
    device container). Not carried: Microsoft, firmware capsules, providers seen
    only on virtual/software devices (ROOT\, SWD\) or on external devices
    (webcams, receivers, docks: their own container). Review the list.

    Run it on the PC to reinstall, BEFORE reinstalling. Then review the file and
    run Run-Build.cmd: it takes the profile whose match fits the PC by itself
    (-Profile <id> names one). Run-Build.cmd also offers to run this script when
    no profile fits the PC.

.PARAMETER Id
    Profile id / folder name. Default: slug of manufacturer + model.
.PARAMETER OutFile
    Write here instead of <KitRoot>\profiles\<id>\profile.json (e.g. a dry run).
.PARAMETER Force
    Overwrite an existing file.
.PARAMETER Hibernate
    power.mode 'hibernate' (only if powercfg /a lists Hibernate). Default 'default'.
.PARAMETER WakeOnLan
    power.wakeOnLan for the first physical wired adapter that is Up (magic packet).
.PARAMETER NoNextSteps
    Don't print the "Next steps" list (Run-Build.cmd, which goes on by itself).
.PARAMETER KitRoot
    The kit folder. Needed when loaded as a scriptblock ($PSScriptRoot empty).
#>
[CmdletBinding()]
param(
    [string]$Id,
    [string]$OutFile,
    [switch]$Force,
    [switch]$Hibernate,
    [switch]$WakeOnLan,
    [switch]$NoNextSteps,
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
if (-not $KitRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
$KitRoot = $KitRoot.TrimEnd('\')
$PcContainer = '00000000-0000-0000-ffff-ffffffffffff'   # devices built into the PC

# --- helpers -------------------------------------------------------------------------
# Regex for an exact text, readable: spaces stay spaces
function ConvertTo-LiteralRegex([string]$Text) { [regex]::Escape($Text.Trim()) -replace '\\ ', ' ' }

# Vendor part of a driver provider name: 'Realtek Semiconductor Corp.' -> 'Realtek',
# 'MediaTek, Inc.' -> 'MediaTek', 'Advanced Micro Devices, Inc' -> 'Advanced Micro Devices'
function Get-VendorName([string]$Provider) {
    $n = ($Provider -split ',')[0].Trim()
    $n = $n -replace '\s+(Inc|Corp|Corporation|Ltd|Limited|Co|LLC|GmbH|AG|Semiconductor|Technologies|Technology|Electronics)\b.*$', ''
    $n.Trim(' ', '.')
}

# 2-space JSON, UTF-8 without BOM (PS 5.1's ConvertTo-Json indents oddly)
function ConvertTo-KitJson($Value, [int]$Indent = 0) {
    $pad = '  ' * $Indent; $pad2 = '  ' * ($Indent + 1)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string]) {
        $sb = New-Object Text.StringBuilder '"'
        foreach ($ch in $Value.ToCharArray()) {
            switch ($ch) {
                '"' { [void]$sb.Append('\"') }
                '\' { [void]$sb.Append('\\') }
                "`n" { [void]$sb.Append('\n') }
                "`r" { [void]$sb.Append('\r') }
                "`t" { [void]$sb.Append('\t') }
                default { if ([int]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) } else { [void]$sb.Append($ch) } }
            }
        }
        return $sb.Append('"').ToString()
    }
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Count -eq 0) { return '{}' }
        $items = foreach ($k in $Value.Keys) { "$pad2$(ConvertTo-KitJson ([string]$k)): $(ConvertTo-KitJson $Value[$k] ($Indent + 1))" }
        return "{`n$($items -join ",`n")`n$pad}"
    }
    if ($Value -is [Collections.IEnumerable]) {
        $arr = @($Value)
        if ($arr.Count -eq 0) { return '[]' }
        $items = foreach ($e in $arr) { "$pad2$(ConvertTo-KitJson $e ($Indent + 1))" }
        return "[`n$($items -join ",`n")`n$pad]"
    }
    ConvertTo-KitJson ([string]$Value) $Indent
}

function Test-InternalDevice([string]$InstanceId) {
    $c = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName DEVPKEY_Device_ContainerId -ErrorAction SilentlyContinue
    "$($c.Data)".Trim('{', '}') -eq $PcContainer
}

$notes = New-Object System.Collections.Generic.List[string]

# --- identity ------------------------------------------------------------------------
Write-Host 'Reading this PC...'
$cs = Get-CimInstance Win32_ComputerSystem
$csp = Get-CimInstance Win32_ComputerSystemProduct
$mfr = "$($cs.Manufacturer)".Trim()
$model = "$($cs.Model)".Trim()
$placeholder = '^(System Product Name|System manufacturer|To be filled.*|Default string|O\.E\.M\.|Not Applicable|)$'
$mfrNice = if ($mfr -cmatch '^[A-Z0-9 ]+$' -and $mfr.Length -gt 3) { (Get-Culture).TextInfo.ToTitleCase($mfr.ToLower()) } else { $mfr }
# Lenovo: Model is the machine type/model (90YJ001KUS); the product name is in Version
$friendly = $model
if ($mfr -match '^Lenovo$' -and "$($csp.Version)".Trim()) { $friendly = "$($csp.Version)".Trim() }
$generic = ($model -match $placeholder) -or ($mfr -match $placeholder)
if ($generic) {
    $bb = Get-CimInstance Win32_BaseBoard
    $friendly = "$($bb.Manufacturer) $($bb.Product)".Trim()
    $notes.Add("Manufacturer/model are placeholders ('$mfr' / '$model'): match is null, so the build never takes this profile by itself. Run-Build.cmd lists it and asks; -Profile <id> names it.")
}
$displayName = if ($generic) { $friendly } else { "$mfrNice $friendly".Trim() }
if (-not $Id) {
    $Id = (("$mfr $model".ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
    if ($generic -or -not $Id) { $Id = (($friendly.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')) }
}
if ($Id -notmatch '^[a-z0-9][a-z0-9-]*$') { throw "Invalid -Id '$Id': lower-case letters, digits and hyphens." }
$match = $null
if (-not $generic) {
    # Lenovo machine type = the first 4 characters of the 10-character MTM
    $modelRx = if ($mfr -match '^Lenovo$' -and $model -match '^[0-9A-Z]{10}$') { '^' + $model.Substring(0, 4) } else { '^' + (ConvertTo-LiteralRegex $model) }
    $match = [ordered]@{ manufacturer = '^' + (ConvertTo-LiteralRegex $mfr) + '$'; model = $modelRx }
}
$isoTag = ($friendly -replace '[^A-Za-z0-9]', '')
if (-not $isoTag) { $isoTag = 'Custom' }
if ($isoTag.Length -gt 23) { $isoTag = $isoTag.Substring(0, 23) }

# --- licence: only whether a firmware key exists, and its edition ------------------------
$sls = Get-CimInstance SoftwareLicensingService
$hasOemKey = [bool]"$($sls.OA3xOriginalProductKey)"   # the key itself is not kept or shown
$oemKeyDesc = "$($sls.OA3xOriginalProductKeyDescription)"
$sls = $null
if ($hasOemKey -and $oemKeyDesc -match 'Professional') {
    $productKey = 'firmware'
    $licence = "firmware (MSDM) key for Pro ($oemKeyDesc): no key in the answer file"
} elseif ($hasOemKey) {
    $productKey = 'generic'
    $licence = "firmware (MSDM) key is not a Pro key ($oemKeyDesc): 'generic' so Setup selects Pro; Windows activates Pro only with a Pro digital licence for this PC"
    $notes.Add("The firmware key is '$oemKeyDesc', not Pro. The image holds only Pro: with no key Setup could not use the firmware key. productKey 'generic' selects Pro; activation needs this PC's Pro digital licence (e.g. a past Home-to-Pro upgrade).")
} else {
    $productKey = 'generic'
    $licence = 'no firmware key: the generic Windows 11 Pro installation key selects the edition (it does not activate and is not a licence); activation via digital licence or a key entered later'
}

# --- drivers.providers ----------------------------------------------------------------
$present = @{}
Get-PnpDevice -PresentOnly | ForEach-Object { $present[$_.InstanceId] = $_ }
$signed = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -and $present.ContainsKey($_.DeviceID) })
$keep = [ordered]@{}; $dropped = [ordered]@{}
foreach ($d in ($signed | Where-Object { $_.InfName -like 'oem*.inf' -and $_.DriverProviderName })) {
    $vendor = Get-VendorName $d.DriverProviderName
    if (-not $vendor) { continue }
    $key = $vendor.ToLowerInvariant()
    $why = if ($d.DriverProviderName -match '^Microsoft') { 'Microsoft' }
           elseif ($d.DeviceClass -eq 'FIRMWARE') { 'firmware capsule' }
           elseif ($d.DeviceID -match '^(ROOT|SWD|SW)\\') { 'virtual/software device' }
           elseif (-not (Test-InternalDevice $d.DeviceID)) { 'external device' }
           else { $null }
    if ($why) {
        if (-not $dropped.Contains($key)) { $dropped[$key] = [ordered]@{ Name = $vendor; Why = New-Object System.Collections.Generic.List[string] } }
        if (-not $dropped[$key].Why.Contains("$why ($($d.DeviceName))")) { $dropped[$key].Why.Add("$why ($($d.DeviceName))") }
    } else {
        if (-not $keep.Contains($key)) { $keep[$key] = [ordered]@{ Name = $vendor; Devices = New-Object System.Collections.Generic.List[string] } }
        $keep[$key].Devices.Add($d.DeviceName)
    }
}
foreach ($k in @($dropped.Keys)) { if ($keep.Contains($k)) { $dropped.Remove($k) } }
$providers = if ($keep.Count) { '^(' + ((@($keep.Values) | ForEach-Object { ConvertTo-LiteralRegex $_.Name } | Sort-Object) -join '|') + ')' } else { '.' }
if (-not $keep.Count) { $notes.Add("No third-party driver bound to internal hardware: drivers.providers is '.' (every third-party provider).") }

# --- power ----------------------------------------------------------------------------
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try { $pc = @(& powercfg.exe /a 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $old }
$avail = New-Object System.Collections.Generic.List[string]
foreach ($l in $pc) { if ($l -match 'not available') { break }; if ($l -match '^\s+\S') { $avail.Add($l.Trim()) } }
$canHibernate = $avail -contains 'Hibernate'
$powerMode = 'default'
if ($Hibernate -and $canHibernate) { $powerMode = 'hibernate' }
elseif ($Hibernate) { $notes.Add("-Hibernate: powercfg /a does not list Hibernate as available ($($avail -join ', ')): power.mode stays 'default'.") }

$wol = $null
$netAll = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
$wired = @($netAll | Where-Object { $_.PhysicalMediaType -eq '802.3' -and (Test-InternalDevice $_.PnPDeviceID) } | Sort-Object ifIndex)
$wifi = @($netAll | Where-Object { $_.PhysicalMediaType -eq 'Native 802.11' -and (Test-InternalDevice $_.PnPDeviceID) } | Sort-Object ifIndex)
if ($WakeOnLan) {
    $a = $wired | Where-Object Status -eq 'Up' | Select-Object -First 1
    if (-not $a) {
        $notes.Add('-WakeOnLan: no built-in wired adapter is connected (Up): power.wakeOnLan stays null.')
    } else {
        $desc = $a.InterfaceDescription -replace '\s+#\d+$', ''
        $adv = [ordered]@{ '*WakeOnMagicPacket' = '1'; '*WakeOnPattern' = '0' }
        $props = @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties -ErrorAction SilentlyContinue)
        $s5 = $props | Where-Object RegistryKeyword -eq 'S5WakeOnLan' | Select-Object -First 1
        if ($s5) { $adv['S5WakeOnLan'] = '1' }
        $ls = $props | Where-Object RegistryKeyword -eq 'WolShutdownLinkSpeed' | Select-Object -First 1
        # Realtek: 2 = "Not Speed Down" (wake from S5 at full link speed)
        if ($ls -and @($ls.ValidRegistryValues) -contains '2') { $adv['WolShutdownLinkSpeed'] = '2' }
        $wol = [ordered]@{ adapter = ConvertTo-LiteralRegex $desc; label = $desc; advanced = $adv }
    }
}

# --- Kernel DMA Protection (NtQuerySystemInformation SystemDmaGuardPolicyInformation) ------
$dmaOn = $null
try {
    if (-not ('W11KitDmaGuard' -as [type])) {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class W11KitDmaGuard {
    [DllImport("ntdll.dll")] public static extern int NtQuerySystemInformation(int infoClass, ref byte info, int length, out int returned);
}
'@
    }
    $b = [byte]0; $ret = 0
    if ([W11KitDmaGuard]::NtQuerySystemInformation(202, [ref]$b, 1, [ref]$ret) -eq 0) { $dmaOn = $b -ne 0 }
} catch { }
$dmaSetting = if ($dmaOn) { 'required' } else { 'recommended' }

# --- checks ---------------------------------------------------------------------------
$drvByDevice = @{}
foreach ($d in $signed) { $drvByDevice[$d.DeviceID] = $d }
$checks = New-Object System.Collections.Generic.List[object]
foreach ($v in @(Get-CimInstance Win32_VideoController | Where-Object { $_.PNPDeviceID -match '^PCI\\' -and $_.AdapterCompatibility -and $_.AdapterCompatibility -notmatch '^Microsoft' } | Sort-Object Name)) {
    $checks.Add([ordered]@{ area = 'GPU'; name = "$($v.Name.Trim()) on $($v.AdapterCompatibility.Trim()) driver"; type = 'video'; match = ConvertTo-LiteralRegex $v.Name; vendor = ConvertTo-LiteralRegex $v.AdapterCompatibility })
}
foreach ($s in @(Get-CimInstance Win32_SoundDevice | Where-Object { $_.PNPDeviceID -and $_.PNPDeviceID -notmatch '^(ROOT|SWD|SW)\\' } | Sort-Object Name)) {
    $d = $drvByDevice[$s.PNPDeviceID]
    if (-not $d -or $d.InfName -notlike 'oem*.inf' -or $d.DriverProviderName -match '^Microsoft') { continue }
    if (-not (Test-InternalDevice $s.PNPDeviceID)) { continue }
    $checks.Add([ordered]@{ area = 'Audio'; name = $s.Name.Trim(); type = 'sound'; match = ConvertTo-LiteralRegex $s.Name })
}
foreach ($n in $wired) {
    $desc = $n.InterfaceDescription -replace '\s+#\d+$', ''
    $checks.Add([ordered]@{ area = 'Network'; name = "$desc"; type = 'netadapter'; match = ConvertTo-LiteralRegex $desc })
}
foreach ($n in $wifi) {
    $pnp = Get-PnpDevice -InstanceId $n.PnPDeviceID -ErrorAction SilentlyContinue
    $name = if ($pnp -and $pnp.FriendlyName) { $pnp.FriendlyName } else { $n.InterfaceDescription -replace '\s+#\d+$', '' }
    $checks.Add([ordered]@{ area = 'Network'; name = "$name"; type = 'pnp'; match = ConvertTo-LiteralRegex $name })
}
foreach ($bt in @(Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^(USB|PCI)\\' -and $_.FriendlyName } | Sort-Object FriendlyName)) {
    $checks.Add([ordered]@{ area = 'Bluetooth'; name = $bt.FriendlyName.Trim(); type = 'pnp'; class = 'Bluetooth'; match = ConvertTo-LiteralRegex $bt.FriendlyName })
}

# --- write ----------------------------------------------------------------------------
$cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
$parts = @($cpu) + @($checks | Where-Object { $_.type -ne 'sound' } | ForEach-Object { $_.match -replace '\\', '' })
$profileObj = [ordered]@{
    schemaVersion = 1
    id            = $Id
    displayName   = $displayName
    description   = "$($parts -join ', '). Generated by scripts\New-HardwareProfile.ps1 on $(Get-Date -Format 'yyyy-MM-dd'); review before use."
    match         = $match
    computerName  = $null
    isoTag        = $isoTag
    productKey    = $productKey
    drivers       = [ordered]@{ providers = $providers; skipInf = $null }
    power         = [ordered]@{ mode = $powerMode; wakeOnLan = $wol }
    security      = [ordered]@{ kernelDmaProtection = $dmaSetting }
    checks        = $checks.ToArray()
    firmwareHints = [ordered]@{}
}
$json = (ConvertTo-KitJson $profileObj) + "`n"
$null = $json | ConvertFrom-Json   # must parse

if (-not $OutFile) { $OutFile = Join-Path $KitRoot "profiles\$Id\profile.json" }
if ((Test-Path -LiteralPath $OutFile) -and -not $Force) { throw "$OutFile exists: use -Force to overwrite it, or -Id for another name." }
$dir = Split-Path -Parent $OutFile
try {
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($OutFile, $json, (New-Object Text.UTF8Encoding $false))
} catch {
    if ($_.Exception -is [UnauthorizedAccessException] -or $_.Exception.InnerException -is [UnauthorizedAccessException]) {
        throw "Can't write ${OutFile}: the kit folder is writable by administrators only once a build has run. Use New-Profile.cmd (it asks for elevation), or -OutFile <a path of yours>."
    }
    throw
}

# --- summary --------------------------------------------------------------------------
Write-Host ''
Write-Host "Profile '$Id' written to $OutFile" -ForegroundColor Green
Write-Host "  PC:             $mfr $model ($displayName)"
Write-Host "  match:          $(if ($match) { "manufacturer $($match.manufacturer), model $($match.model)" } else { 'null (never taken by itself: Run-Build.cmd asks, or -Profile names it)' })"
Write-Host "  ISO name:       Win11Pro-$isoTag-<build>-<time>.iso; computer name: random (set computerName in your settings, or here, to fix one)"
Write-Host "  licence:        $licence"
Write-Host "  drivers:        $providers"
foreach ($k in $keep.Values) { Write-Host ("                  {0}: {1}" -f $k.Name, ((@($k.Devices) | Sort-Object -Unique) -join '; ')) }
foreach ($k in $dropped.Values) { Write-Host ("    not carried:  {0}: {1}" -f $k.Name, ((@($k.Why) | Select-Object -First 3) -join '; ')) -ForegroundColor DarkGray }
Write-Host "  power:          $powerMode (powercfg /a available: $($avail -join ', '))$(if ($wol) { "; Wake-on-LAN on $($wol.label)" })"
Write-Host "  Kernel DMA:     $(if ($null -eq $dmaOn) { 'unknown' } elseif ($dmaOn) { 'On' } else { 'Off' }) -> $dmaSetting"
Write-Host "  checks:         $($checks.Count)"
foreach ($c in $checks) { Write-Host "                  [$($c.area)] $($c.name) ($($c.type))" }
foreach ($n in $notes) { Write-Host "  NOTE: $n" -ForegroundColor Yellow }
if ($NoNextSteps) { return }
Write-Host ''
Write-Host 'Next steps:'
Write-Host "  1. Review $OutFile (docs\reference\PROFILES.md): drop peripheral vendors from drivers.providers, set firmwareHints."
if ($match) {
    Write-Host '  2. On this PC, before reinstalling: Run-Build.cmd. It takes this profile by itself (its match fits this PC),'
    Write-Host '     offers to collect this PC''s drivers, and builds.'
} else {
    Write-Host "  2. On this PC, before reinstalling: Run-Build.cmd. It lists this profile and asks (or name it: Run-Build.cmd -Profile $Id),"
    Write-Host '     offers to collect this PC''s drivers, and builds.'
}
Write-Host "     Building on another PC: Run-Harvest.cmd -Profile $Id here, then docs\reference\BUILD-OPTIONS.md, ""Building on another PC""."
Write-Host '  3. Keep it: git pull leaves it alone, and the ISO carries it for a rebuild after the reinstall. Commit it only to share it.'
