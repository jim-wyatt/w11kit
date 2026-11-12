<#
.SYNOPSIS
    Builds the driver inventory report for the running PC (any model).

.DESCRIPTION
    Reads every signed PnP driver bound to a device on the running system and
    produces:
      driver-inventory.csv        every device/driver binding (full detail)
      DRIVER-INVENTORY.md         report by device category (display, audio,
                                  network, Bluetooth, system/chipset, storage,
                                  USB, other third-party) plus all third-party drivers

    Does not require elevation. Each oemNN.inf is resolved to its driver store
    folder through the DRIVERS hive; Export-WindowsDriver uses the same folder
    names, so the report ties directly to the export.

.PARAMETER OutDir
    Folder to write the report into. Default: the driver export in the kit's work
    folder, <KitRoot>\work\DriverExport (the harvest passes its own).
.PARAMETER KitRoot
    The kit folder, for the default -OutDir. Needed only without -OutDir when the
    script is loaded as a scriptblock ($PSScriptRoot empty).
#>
[CmdletBinding()]
param(
    [string]$OutDir,
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) {
    if (-not $KitRoot -and $PSScriptRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
    if (-not $KitRoot) { throw 'Pass -OutDir (or -KitRoot) when loading this script as a scriptblock.' }
    $OutDir = Join-Path "$KitRoot".TrimEnd('\') 'work\DriverExport'
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Index of driver store INFs by file size, used to hash-match oemNN.inf copies
# when the DRIVERS hive key is not readable without elevation. Built once, on first
# use, into the caller's cache (a hashtable passed by reference): this script runs
# as a scriptblock, where $script: would point at the caller's scope.
function Get-StoreIndex([hashtable]$Cache) {
    if ($null -eq $Cache.Index) {
        $index = @{}
        foreach ($inf in @(Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository\*\*.inf" -ErrorAction SilentlyContinue)) {
            if (-not $index.ContainsKey($inf.Length)) { $index[$inf.Length] = @() }
            $index[$inf.Length] += $inf
        }
        $Cache.Index = $index
    }
    $Cache.Index
}

function Get-StoreFolder([string]$InfName, [hashtable]$Cache) {
    if ($InfName -notlike 'oem*.inf') { return $null }
    $key = "HKLM:\DRIVERS\DriverDatabase\DriverInfFiles\$InfName"
    if (Test-Path $key) {
        $k = Get-Item $key
        $active = $k.GetValue('Active')
        if ($active) { return $active }
        $all = @($k.GetValue(''))
        if ($all.Count) { return $all[-1] }
    }
    $oem = Get-Item "$env:SystemRoot\INF\$InfName" -ErrorAction SilentlyContinue
    if (-not $oem) { return $null }
    $hash = (Get-FileHash $oem.FullName -Algorithm SHA256).Hash
    $index = Get-StoreIndex $Cache
    foreach ($candidate in @($index[$oem.Length])) {
        if ($candidate -and (Get-FileHash $candidate.FullName -Algorithm SHA256).Hash -eq $hash) {
            return $candidate.Directory.Name
        }
    }
    return '(unresolved)'
}

function Get-InstalledPackageVersion([string]$Pattern) {
    $roots = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $roots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($_.Publisher -match $Pattern -or $_.DisplayName -match $Pattern) } |
        Sort-Object DisplayName -Unique |
        ForEach-Object { [pscustomobject]@{ Name = $_.DisplayName; Version = $_.DisplayVersion } }
}

$storeCache = @{ Index = $null }
$present = @{}
Get-PnpDevice -PresentOnly | ForEach-Object { $present[$_.InstanceId] = $_ }

$rows = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID } | ForEach-Object {
    $dev = $present[$_.DeviceID]
    $problem = $null
    if ($dev) {
        $p = Get-PnpDeviceProperty -InstanceId $_.DeviceID -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue
        if ($p) { $problem = $p.Data }
    }
    [pscustomobject]@{
        Class          = $_.DeviceClass
        DeviceName     = $_.DeviceName
        PnpDeviceId    = $_.DeviceID
        Provider       = $_.DriverProviderName
        Version        = $_.DriverVersion
        Date           = if ($_.DriverDate) { $_.DriverDate.ToString('yyyy-MM-dd') } else { '' }
        Inf            = $_.InfName
        StoreFolder    = Get-StoreFolder $_.InfName $storeCache
        Present        = [bool]$dev
        Status         = if ($dev) { $dev.Status } else { 'NotPresent' }
        ProblemCode    = $problem
        Inbox          = -not ($_.InfName -like 'oem*.inf')
    }
}

$rows | Sort-Object Class, DeviceName |
    Export-Csv -Path (Join-Path $OutDir 'driver-inventory.csv') -NoTypeInformation -Encoding UTF8

# --- Category rules (by device class; the first matching category wins) ---------
# Hardware buses only for the device categories: ROOT\ / SWD\ devices are virtual
# or software components (they still show under "Other third-party" and below).
$hwBus = '^(PCI|USB|HDAUDIO|ACPI|SD|BTH)\\'
$categories = [ordered]@{
    'Display'               = { $_.Class -eq 'DISPLAY' }
    'Audio'                 = { ($_.Class -in 'MEDIA', 'AUDIOPROCESSINGOBJECT' -or ($_.Class -in 'SYSTEM', 'SOFTWARECOMPONENT' -and $_.DeviceName -match 'Audio')) -and ($_.PnpDeviceId -match $hwBus -or -not $_.Inbox) }
    'Network'               = { $_.Class -eq 'NET' -and $_.PnpDeviceId -match '^(PCI|USB|SD)\\' }
    'Bluetooth'             = { $_.Class -eq 'BLUETOOTH' -and $_.PnpDeviceId -match '^(USB|PCI)\\' }
    'System / chipset'      = { $_.Class -in 'SYSTEM', 'SECURITYDEVICES' -and -not $_.Inbox -and $_.PnpDeviceId -match $hwBus }
    'Storage controller'    = { $_.Class -in 'SCSIADAPTER', 'HDC' -and $_.PnpDeviceId -match '^PCI\\' }
    'USB controller'        = { $_.Class -eq 'USB' -and $_.PnpDeviceId -match '^PCI\\' }
    'Other third-party'     = { -not $_.Inbox -and $_.Class -ne 'FIRMWARE' }
}

$os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Driver Inventory - $("$($cs.Manufacturer) $($cs.Model)".Trim())")
$md.Add('')
$md.Add("Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') on $env:COMPUTERNAME by scripts/New-DriverInventory.ps1.")
$md.Add('')
$md.Add('| Item | Value |')
$md.Add('|---|---|')
$md.Add("| System | $($cs.Manufacturer) $($cs.Model) |")
$md.Add("| BIOS | $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate.ToString('yyyy-MM-dd'))) |")
$md.Add("| Source OS | $((Get-CimInstance Win32_OperatingSystem).Caption) $($os.DisplayVersion) build $($os.CurrentBuild).$($os.UBR) |")
$md.Add("| CPU | $((Get-CimInstance Win32_Processor).Name.Trim()) |")
$md.Add("| RAM | $([math]::Round($cs.TotalPhysicalMemory/1GB)) GB |")
$md.Add('')
$md.Add('## Installed packages from the driver vendors (Programs and Features)')
$md.Add('')
$md.Add('| Package | Version |')
$md.Add('|---|---|')
# Vendors = the first word of every third-party driver provider, plus the PC maker
$vendorWords = @($rows | Where-Object { -not $_.Inbox -and $_.Provider -and $_.Provider -notmatch '^Microsoft' } |
    ForEach-Object { ($_.Provider -split '[\s,]+')[0] }) + @(("$($cs.Manufacturer)" -split '[\s,]+')[0]) |
    Where-Object { $_.Length -ge 3 } | Sort-Object -Unique
$vendorPattern = if ($vendorWords) { '^(' + (($vendorWords | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b' } else { '^$' }
Get-InstalledPackageVersion $vendorPattern |
    ForEach-Object { $md.Add("| $($_.Name) | $($_.Version) |") }
$md.Add('')
$md.Add('## Devices by category')
$md.Add('')
$md.Add('Devices on the running system (present or not), by category; each device is listed once, under the first category that fits.')

$listed = @{}
foreach ($cat in $categories.Keys) {
    $rule = $categories[$cat]
    $hits = @($rows | Where-Object { -not $listed[$_.PnpDeviceId] } | Where-Object $rule | Sort-Object DeviceName, PnpDeviceId)
    foreach ($h in $hits) { $listed[$h.PnpDeviceId] = $true }
    $md.Add('')
    $md.Add("### $cat")
    $md.Add('')
    if (-not $hits.Count) { $md.Add('_No matching device found._'); continue }
    $md.Add('| Device Name | PNP Device ID | Driver Provider | Driver Version | Driver Date | INF File | Driver Store Folder | Status |')
    $md.Add('|---|---|---|---|---|---|---|---|')
    foreach ($h in $hits) {
        $status = $h.Status
        if ($h.ProblemCode) { $status = "$status (code $($h.ProblemCode))" }
        $store = if ($h.StoreFolder) { $h.StoreFolder } else { '(in-box)' }
        $md.Add("| $($h.DeviceName) | ``$($h.PnpDeviceId)`` | $($h.Provider) | $($h.Version) | $($h.Date) | $($h.Inf) | $store | $status |")
    }
}

$md.Add('')
$md.Add('## All third-party drivers bound to devices')
$md.Add('')
$md.Add('| Class | Device Name | Provider | Version | Date | INF File | Driver Store Folder |')
$md.Add('|---|---|---|---|---|---|---|')
$rows | Where-Object { -not $_.Inbox } | Sort-Object Class, DeviceName | ForEach-Object {
    $md.Add("| $($_.Class) | $($_.DeviceName) | $($_.Provider) | $($_.Version) | $($_.Date) | $($_.Inf) | $($_.StoreFolder) |")
}

$problems = @($rows | Where-Object { $_.Present -and $_.Status -ne 'OK' })
$md.Add('')
$md.Add('## Devices not in OK state')
$md.Add('')
if ($problems.Count) {
    $md.Add('| Device Name | PNP Device ID | Status | Problem Code |')
    $md.Add('|---|---|---|---|')
    $problems | ForEach-Object { $md.Add("| $($_.DeviceName) | ``$($_.PnpDeviceId)`` | $($_.Status) | $($_.ProblemCode) |") }
    $md.Add('')
    $md.Add('Problem code 22 = disabled by the user (not a driver fault). Code 28 = no driver installed. Code 10/43 = driver failed to start.')
} else {
    $md.Add('None.')
}

$mdPath = Join-Path $OutDir 'DRIVER-INVENTORY.md'
$md | Set-Content -Path $mdPath -Encoding UTF8
Write-Host "Inventory written to $mdPath"
