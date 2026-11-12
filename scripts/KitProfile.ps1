<#
.SYNOPSIS
    Hardware-profile helpers shared by Build-Iso.ps1 and Invoke-DriverHarvest.ps1
    (the contract is docs\reference\PROFILES.md). Defines functions only.

    Loaded the scriptblock way (a policy may block .ps1 files):
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitProfile.ps1'))))

    Resolve-KitProfile -KitRoot <kit> [-Id <id>]
        -Id given: profiles\<id>\profile.json. Otherwise the first profile (by folder
        name) whose match.manufacturer / match.model regexes fit this PC's
        Win32_ComputerSystem Manufacturer / Model, else 'generic'. Validates the
        profile and throws one message listing every problem. Returns
        Profile, Path, Reason, FitsPc ($true / $false / $null = no match in the profile),
        PcManufacturer, PcModel.
#>

function Test-KitRegex([string]$Pattern) {
    try { $null = New-Object regex $Pattern; $true } catch { $false }
}

function Test-KitProfile($P, [string]$FolderId) {
    $bad = New-Object System.Collections.Generic.List[string]
    $has = { param($o, $n) $null -ne $o -and @($o.PSObject.Properties.Name) -contains $n }
    $str = { param($v) $v -is [string] -and $v.Trim() }
    foreach ($f in 'id', 'displayName', 'isoTag', 'productKey', 'drivers', 'power', 'security', 'checks') {
        if (-not (& $has $P $f)) { $bad.Add("missing field '$f'") }
    }
    # The profile format's version: this kit reads version 1
    if (-not (& $has $P 'schemaVersion')) { $bad.Add("missing field 'schemaVersion' (add `"schemaVersion`": 1 as the first field)") }
    elseif ($P.schemaVersion -isnot [int] -or $P.schemaVersion -lt 1) { $bad.Add("schemaVersion '$($P.schemaVersion)': a whole number (this kit reads 1)") }
    elseif ($P.schemaVersion -gt 1) { $bad.Add("schemaVersion $($P.schemaVersion) is newer than this kit reads (1): update the kit (Run-Build.cmd, first question)") }
    if ($bad.Count) { return $bad.ToArray() }
    if ($P.id -isnot [string] -or $P.id -notmatch '^[a-z0-9][a-z0-9-]*$') { $bad.Add("id '$($P.id)': lower-case letters, digits and hyphens") }
    elseif ($FolderId -and $P.id -ne $FolderId) { $bad.Add("id '$($P.id)' differs from its folder name '$FolderId'") }
    if (-not (& $str $P.displayName)) { $bad.Add('displayName must be a non-empty string') }
    if ((& $has $P 'match') -and $null -ne $P.match) {
        foreach ($k in 'manufacturer', 'model') {
            $v = if (& $has $P.match $k) { $P.match.$k } else { $null }
            if (-not (& $str $v) -or -not (Test-KitRegex $v)) { $bad.Add("match.$k must be a valid regex (or set match to null)") }
        }
    }
    $cn = if (& $has $P 'computerName') { $P.computerName } else { $null }
    if ($null -ne $cn -and ($cn -isnot [string] -or $cn -notmatch '^[A-Za-z0-9-]{1,15}$' -or $cn -match '^\d+$')) {
        $bad.Add("computerName '$cn': 1-15 letters, digits or hyphens, not all digits (or null for a random name)")
    }
    if ($P.isoTag -isnot [string] -or $P.isoTag -notmatch '^[A-Za-z0-9]{1,23}$') { $bad.Add("isoTag '$($P.isoTag)': 1-23 letters and digits") }
    if ($P.productKey -notin 'firmware', 'generic', 'prompt') { $bad.Add("productKey '$($P.productKey)': firmware, generic or prompt") }
    $prov = if (& $has $P.drivers 'providers') { $P.drivers.providers } else { $null }
    if (-not (& $str $prov) -or -not (Test-KitRegex $prov)) { $bad.Add('drivers.providers must be a valid regex (. = every third-party provider)') }
    $skip = if (& $has $P.drivers 'skipInf') { $P.drivers.skipInf } else { $null }
    if ($null -ne $skip -and (-not (& $str $skip) -or -not (Test-KitRegex $skip))) { $bad.Add('drivers.skipInf must be a valid regex or null') }
    $mode = if (& $has $P.power 'mode') { $P.power.mode } else { $null }
    if ($mode -notin 'hibernate', 'default') { $bad.Add("power.mode '$mode': hibernate or default") }
    $wol = if (& $has $P.power 'wakeOnLan') { $P.power.wakeOnLan } else { $null }
    if ($null -ne $wol) {
        if (-not (& $str $wol.adapter) -or -not (Test-KitRegex $wol.adapter)) { $bad.Add('power.wakeOnLan.adapter must be a valid regex') }
        if (-not (& $str $wol.label)) { $bad.Add('power.wakeOnLan.label must be a non-empty string') }
        if ((& $has $wol 'advanced') -and $null -ne $wol.advanced -and $wol.advanced -isnot [System.Management.Automation.PSCustomObject]) { $bad.Add('power.wakeOnLan.advanced must be an object') }
    }
    $dma = if (& $has $P.security 'kernelDmaProtection') { $P.security.kernelDmaProtection } else { $null }
    if ($dma -notin 'required', 'recommended') { $bad.Add("security.kernelDmaProtection '$dma': required or recommended") }
    if ($null -ne $P.checks -and $P.checks -isnot [array]) { $bad.Add('checks must be an array') }
    $i = 0
    foreach ($c in @($P.checks | Where-Object { $null -ne $_ })) {
        $i++
        $n = "checks[$i]"
        foreach ($k in 'area', 'name') { if (-not (& $str $c.$k)) { $bad.Add("$n.$k must be a non-empty string") } }
        if ($c.type -notin 'video', 'sound', 'netadapter', 'pnp') { $bad.Add("$n.type '$($c.type)': video, sound, netadapter or pnp") }
        if (-not (& $str $c.match) -or -not (Test-KitRegex $c.match)) { $bad.Add("$n.match must be a valid regex") }
        if ((& $has $c 'vendor') -and $null -ne $c.vendor -and -not (Test-KitRegex $c.vendor)) { $bad.Add("$n.vendor must be a valid regex") }
    }
    $bad.ToArray()
}

# $true / $false: whether the profile's match fits the PC; $null: the profile has no match
function Test-KitProfileFits($P, [string]$Manufacturer, [string]$Model) {
    if ($null -eq $P.match) { return $null }
    ($Manufacturer -match $P.match.manufacturer) -and ($Model -match $P.match.model)
}

function Resolve-KitProfile([string]$KitRoot, [string]$Id) {
    $cs = Get-CimInstance Win32_ComputerSystem
    $mfr = "$($cs.Manufacturer)".Trim(); $model = "$($cs.Model)".Trim()
    $root = Join-Path $KitRoot 'profiles'
    if ($Id) {
        $path = Join-Path $root "$Id\profile.json"
        if (-not (Test-Path -LiteralPath $path)) {
            $known = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'profile.json') } | ForEach-Object Name)
            throw "Profile '$Id' not found ($path). Known profiles: $($known -join ', '). Make one for this PC with New-Profile.cmd (docs\reference\PROFILES.md), or check the spelling (the folder name under profiles\)."
        }
        $reason = 'given with -Profile'
    } else {
        $path = $null
        foreach ($d in @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $f = Join-Path $d.FullName 'profile.json'
            if (-not (Test-Path -LiteralPath $f)) { continue }
            try { $cand = [IO.File]::ReadAllText($f) | ConvertFrom-Json } catch { Write-Warning "Skipping $f (not valid JSON): $($_.Exception.Message)"; continue }
            if ($null -eq $cand.match) { continue }
            $fits = $false
            try { $fits = Test-KitProfileFits $cand $mfr $model } catch { Write-Warning "Skipping $f (bad match regex): $($_.Exception.Message)"; continue }
            if ($fits) { $path = $f; $reason = "its match fits this PC ($mfr $model)"; break }
        }
        if (-not $path) {
            $path = Join-Path $root 'generic\profile.json'
            $reason = "no profile's match fits this PC ($mfr $model)"
        }
    }
    try { $p = [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { throw "Profile $path is not valid JSON: $($_.Exception.Message)" }
    $problems = @(Test-KitProfile $p (Split-Path (Split-Path $path -Parent) -Leaf))
    if ($problems.Count) {
        throw "Profile $path is invalid (see docs\reference\PROFILES.md):`n  - $($problems -join "`n  - ")"
    }
    [pscustomobject]@{
        Profile        = $p
        Path           = $path
        Reason         = $reason
        FitsPc         = Test-KitProfileFits $p $mfr $model
        PcManufacturer = $mfr
        PcModel        = $model
    }
}
