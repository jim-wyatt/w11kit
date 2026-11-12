<#
.SYNOPSIS
    Applies the Microsoft security baselines, the kit's overrides and the kit's own
    policies to local Group Policy with built-in Windows tools only
    (docs/reference/SECURITY-BASELINE.md, "How the baselines are applied").

.DESCRIPTION
    The baselines are data (staged as Baselines\<id>\; the build imports it from
    Microsoft's official zips with scripts/Import-Baseline.py). Layers, later wins:
      1. what the local GPO already holds (Apply only: e.g. AppLocker rules, an earlier run)
      2. each baseline in Baselines\baselines.json order ('apply'), its GPOs in order
      3. baseline-overrides.txt / .inf / -audit.csv (the documented overrides)
      4. the kit's own policies (Set-KitRegistry.ps1 -PolicyTextPath)

    -Mode Apply (elevated; PostInstall step 1)
      a. Registry: merges the records per key + value name (a later record replaces an
         earlier one; **del.<v> and <v> are the same value; **delvals. drops the key's
         earlier values; CLEAR in the text format drops the key) and writes the local
         GPO's Machine\Registry.pol and User\Registry.pol (PReg, the format gpedit writes).
      b. gpt.ini: Version raised (computer = low 16 bits, user = high 16 bits) and the
         client-side extensions listed (gPCMachineExtensionNames / gPCUserExtensionNames):
         Registry, every one the baseline GPOs' Backup.xml files name (Security, Audit,
         LAPS, mitigation, Device Guard ...) and the ones Microsoft's installer adds
         (source.json 'extensions'); existing entries are kept. Sorted by GUID.
      c. Security template: the baselines' security.inf + baseline-overrides.inf (later
         entry wins) applied with secedit /configure on a temporary database. Not written
         into the local GPO: the local GPO has no security template file (gpedit writes local
         security policy straight into the system, as secedit does); a policy refresh
         doesn't undo it on a standalone PC.
      d. Advanced audit policy: Merge-AuditPolicy.ps1 (the baselines' audit.csv + the
         local GPO's + baseline-overrides-audit.csv: ONE file) written as the local GPO's
         audit.csv (re-applied at every refresh by the audit extension) and applied now
         with auditpol /restore.
      e. The baselines' ADMX templates are not copied: they only label settings in gpedit.
      f. gpupdate /force, then the overrides are read back. An override whose BASELINE
         value is in effect instead makes the result Critical (PostInstall then cancels its
         restart: HVCI/LSA UEFI-locked, standard user denied elevation). Any other problem
         is a Failure. Returns [pscustomobject]@{ Failures; Critical; ... }.
    -Mode ListExpected   The merged records of layers 2-4 (nothing read from or written
                         to the PC): Machine, User, Warnings.
    -Mode Verify         Compares layer 2's computer records that survive the merge with
                         the live registry (the validator's "every policy value" row).
    -Mode Build -OutDir  Writes what Apply would write (Registry.pol x2, gpt.ini,
                         security.inf, audit.csv) into a folder; nothing applied. With
                         -Only '<GPO name>': that GPO's registry records alone, as imported.

    Loaded as a scriptblock by PostInstall and the validator ($PSScriptRoot is empty): the
    paths default to -Root (C:\ProgramData\W11Kit).
#>
[CmdletBinding()]
param(
    [ValidateSet('Apply', 'ListExpected', 'Verify', 'Build')]
    [string]$Mode = 'Apply',
    [string]$Root = 'C:\ProgramData\W11Kit',
    [string]$BaselineRoot,
    [string]$OverridesText,
    [string]$OverridesInf,
    [string]$AuditAdditions,
    [string]$KitRegistryScript,
    [string]$MergeAuditScript,
    # The kit's policies: from Set-KitRegistry.ps1 with these (as PostInstall passes them)
    [ValidateSet('hibernate', 'default')]
    [string]$PowerMode = 'default',
    $Settings,
    [string]$GpRoot = (Join-Path $env:SystemRoot 'System32\GroupPolicy'),
    [string]$LogDir = $env:TEMP,
    [string]$OutDir,
    [string]$Only
)

$ErrorActionPreference = 'Stop'
if (-not $BaselineRoot) { $BaselineRoot = Join-Path $Root 'Baselines' }
if (-not $OverridesText) { $OverridesText = Join-Path $Root 'baseline-overrides.txt' }
if (-not $OverridesInf) { $OverridesInf = Join-Path $Root 'baseline-overrides.inf' }
if (-not $AuditAdditions) { $AuditAdditions = Join-Path $Root 'baseline-overrides-audit.csv' }
if (-not $KitRegistryScript) { $KitRegistryScript = Join-Path $Root 'Set-KitRegistry.ps1' }
if (-not $MergeAuditScript) { $MergeAuditScript = Join-Path $Root 'Merge-AuditPolicy.ps1' }

$U16 = [Text.Encoding]::Unicode
$typeCodes = @{ REG_NONE = 0; REG_SZ = 1; REG_EXPAND_SZ = 2; REG_BINARY = 3; REG_DWORD = 4; REG_MULTI_SZ = 7; REG_QWORD = 11 }
$typeNames = @{ 0 = 'REG_NONE'; 1 = 'REG_SZ'; 2 = 'REG_EXPAND_SZ'; 3 = 'REG_BINARY'; 4 = 'REG_DWORD'; 7 = 'REG_MULTI_SZ'; 11 = 'REG_QWORD' }
$registryCse = '{35378EAC-683F-11D2-A89A-00C04FBBCFA2}'

# --- Records -------------------------------------------------------------------------
# One record = one Registry.pol entry: Key, ValueName, Type (number), Data (bytes), Source.
function New-Rec([string]$Key, [string]$ValueName, [int]$Type, [byte[]]$Data, [string]$Source) {
    [pscustomobject]@{ Key = $Key; ValueName = $ValueName; Type = $Type; Data = $Data; Source = $Source }
}
function ConvertFrom-Hex([string]$Hex) {
    $b = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
    , $b
}
function Get-StringBytes([string]$s) { , $U16.GetBytes($s + [char]0) }
function Get-MultiBytes([string[]]$list) {
    $sb = New-Object Text.StringBuilder
    foreach ($s in $list) { [void]$sb.Append($s).Append([char]0) }
    [void]$sb.Append([char]0)
    , $U16.GetBytes($sb.ToString())
}

# Registry.pol (MS-GPREG): 'PReg' + version 1, then [key;value;type;size;data] records;
# brackets and semicolons are UTF-16LE characters, strings NUL-terminated UTF-16LE.
function Read-Pol([string]$Path, [string]$Source) {
    $out = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path)) { return , $out }
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -eq 0) { return , $out }
    if ($b.Length -lt 8 -or [Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'PReg' -or [BitConverter]::ToUInt32($b, 4) -ne 1) { throw "${Path}: not a Registry.pol file" }
    $i = 8
    while ($i -lt $b.Length) {
        if ($b[$i] -ne 0x5B -or $b[$i + 1] -ne 0) { throw "${Path}: malformed record at byte $i" }
        $i += 2
        $j = $i; while ($b[$j] -ne 0 -or $b[$j + 1] -ne 0) { $j += 2 }
        $key = $U16.GetString($b, $i, $j - $i); $i = $j + 4          # NUL + ';'
        $j = $i; while ($b[$j] -ne 0 -or $b[$j + 1] -ne 0) { $j += 2 }
        $name = $U16.GetString($b, $i, $j - $i); $i = $j + 4
        $type = [BitConverter]::ToUInt32($b, $i); $i += 6
        $size = [BitConverter]::ToUInt32($b, $i); $i += 6
        $data = New-Object byte[] $size
        [Array]::Copy($b, $i, $data, 0, $size); $i += $size
        if ($b[$i] -ne 0x5D -or $b[$i + 1] -ne 0) { throw "${Path}: malformed record end at byte $i" }
        $i += 2
        $out.Add((New-Rec $key $name $type $data $Source))
    }
    , $out
}
function ConvertTo-PolBytes($Records) {
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $ms
    $w.Write([Text.Encoding]::ASCII.GetBytes('PReg')); $w.Write([uint32]1)
    $semi = $U16.GetBytes(';')
    foreach ($r in $Records) {
        $w.Write($U16.GetBytes('[')); $w.Write($U16.GetBytes($r.Key + [char]0)); $w.Write($semi)
        $w.Write($U16.GetBytes($r.ValueName + [char]0)); $w.Write($semi)
        $w.Write([uint32]$r.Type); $w.Write($semi)
        $w.Write([uint32]$r.Data.Length); $w.Write($semi)
        $w.Write([byte[]]$r.Data); $w.Write($U16.GetBytes(']'))
    }
    $w.Flush()
    , $ms.ToArray()
}

# A baseline's registry-*.json (scripts/Import-Baseline.py): exact data, or 'hex'
function Read-BaselineRecords([string]$Path, [string]$Id) {
    $out = New-Object System.Collections.Generic.List[object]
    # Assigned first: Windows PowerShell 5.1 passes a JSON array down the pipeline as ONE object
    $all = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
    foreach ($r in $all) {
        if ($null -eq $r) { continue }
        $type = if ("$($r.type)" -match '^\d+$') { [int]$r.type } elseif ($typeCodes.ContainsKey("$($r.type)")) { $typeCodes["$($r.type)"] } else { throw "${Path}: unknown type '$($r.type)'" }
        $data = if ($r.PSObject.Properties['hex']) { ConvertFrom-Hex $r.hex } else {
            switch ($type) {
                { $_ -in 1, 2 } { Get-StringBytes "$($r.data)"; break }
                7 { Get-MultiBytes @($r.data); break }
                4 { , [BitConverter]::GetBytes([uint32]$r.data); break }
                11 { , [BitConverter]::GetBytes([uint64]$r.data); break }
                default { throw "${Path}: type $type needs 'hex' data" }
            }
        }
        $out.Add((New-Rec $r.key $r.valueName $type $data "baseline:${Id}:$($r.gpo)"))
    }
    , $out
}

# The policy text format of config/baseline-overrides.txt (four lines per entry: Computer|User, key, value name, action;
# blank and ';' lines separate entries). Actions: DWORD:n, QWORD:n, SZ:, EXSZ:, MULTISZ:
# (\0 separates strings), BINARY:hex,hex,..., DELETE, DELETEALLVALUES, DELETEKEYS, CLEAR.
# SZ/EXSZ/MULTISZ text takes the escapes \r, \n and \\. Returns @{ Computer; User } lists.
function Read-PolicyText([string]$Path, [string]$Source) {
    $res = @{ Computer = (New-Object System.Collections.Generic.List[object]); User = (New-Object System.Collections.Generic.List[object]) }
    $lines = @([IO.File]::ReadAllLines($Path))
    $unescape = {
        param([string]$s, [bool]$multi)
        $sb = New-Object Text.StringBuilder
        for ($k = 0; $k -lt $s.Length; $k++) {
            $c = $s[$k]
            if ($c -eq '\' -and $k + 1 -lt $s.Length) {
                $n = $s[$k + 1]
                if ($n -ceq 'r') { [void]$sb.Append("`r"); $k++; continue }
                if ($n -ceq 'n') { [void]$sb.Append("`n"); $k++; continue }
                if ($n -eq '\') { [void]$sb.Append('\'); $k++; continue }
                if ($multi -and $n -eq '0') { [void]$sb.Append([char]0); $k++; continue }
            }
            [void]$sb.Append($c)
        }
        $sb.ToString()
    }
    $i = 0
    while ($i -lt $lines.Count) {
        $l = $lines[$i]
        if ($l -eq '' -or $l.StartsWith(';')) { $i++; continue }
        if ($i + 3 -ge $lines.Count) { throw "${Path}:$($i + 1): incomplete entry (four lines: configuration, key, value name, action)" }
        $cfg = $l; $key = $lines[$i + 1]; $name = $lines[$i + 2]; $act = $lines[$i + 3]
        $where = "${Path}:$($i + 1)"
        $side = if ($cfg -eq 'Computer') { 'Computer' } elseif ($cfg -eq 'User') { 'User' } else { throw "${where}: configuration '$cfg' is not supported (Computer or User)" }
        if (-not $key -or $key.StartsWith(';')) { throw "${where}: missing registry key" }
        $op = 'set'; $type = 0; $data = $null
        if ($act -match '^(?i)DWORD:(.+)$') {
            $v = $Matches[1].Trim(); $n = if ($v -match '^(?i)0x([0-9a-f]+)$') { [Convert]::ToUInt32($Matches[1], 16) } else { [uint32]$v }
            $type = 4; $data = [BitConverter]::GetBytes([uint32]$n)
        } elseif ($act -match '^(?i)QWORD:(.+)$') {
            $v = $Matches[1].Trim(); $n = if ($v -match '^(?i)0x([0-9a-f]+)$') { [Convert]::ToUInt64($Matches[1], 16) } else { [uint64]$v }
            $type = 11; $data = [BitConverter]::GetBytes([uint64]$n)
        } elseif ($act -match '^(?i)SZ:(.*)$') { $type = 1; $data = Get-StringBytes (& $unescape $Matches[1] $false) }
        elseif ($act -match '^(?i)EXSZ:(.*)$') { $type = 2; $data = Get-StringBytes (& $unescape $Matches[1] $false) }
        elseif ($act -match '^(?i)MULTISZ:(.*)$') { $type = 7; $data = Get-MultiBytes @((& $unescape $Matches[1] $true) -split [char]0) }
        elseif ($act -match '^(?i)BINARY:(.*)$') { $type = 3; $data = ConvertFrom-Hex (($Matches[1] -replace '[\s,]', '')) }
        elseif ($act -ceq 'DELETE') { $type = 1; $name = "**del.$name"; $data = Get-StringBytes ' ' }
        elseif ($act -ceq 'DELETEALLVALUES') { $type = 1; $name = '**delvals.'; $data = Get-StringBytes ' ' }
        elseif ($act -ceq 'DELETEKEYS') { $type = 1; $data = Get-StringBytes $name; $name = '**DeleteKeys' }
        elseif ($act -ceq 'CLEAR') { $op = 'clear' }
        else { throw "${where}: action '$act' is not supported" }
        $res[$side].Add([pscustomobject]@{ Op = $op; Rec = (New-Rec $key $name $type $data $Source) })
        $i += 4
    }
    $res
}

# The value a record writes or deletes ('' for key-level commands like **delvals.)
function Get-Target([string]$Name) {
    $n = $Name.ToLowerInvariant()
    if ($n.StartsWith('**del.')) { return $n.Substring(6) }
    if ($n.StartsWith('**soft.')) { return $n.Substring(7) }
    if ($n.StartsWith('**')) { return $null }
    $n
}
# Later wins, as local Group Policy keeps one entry per key + value
function Remove-Where([System.Collections.Generic.List[object]]$Set, [scriptblock]$Test) {
    for ($x = $Set.Count - 1; $x -ge 0; $x--) { if (& $Test $Set[$x]) { $Set.RemoveAt($x) } }
}
function Add-Merged([System.Collections.Generic.List[object]]$Set, $Rec, [string]$Op = 'set') {
    $k = $Rec.Key.ToLowerInvariant()
    if ($Op -eq 'clear') {
        Remove-Where $Set { param($o) $ok = $o.Key.ToLowerInvariant(); $ok -eq $k -or $ok.StartsWith("$k\") }
        return
    }
    $n = $Rec.ValueName.ToLowerInvariant()
    $t = Get-Target $Rec.ValueName
    if ($n -eq '**delvals.') {
        # Deletes every value of the key when applied: the key's earlier values are moot
        Remove-Where $Set { param($o) $o.Key.ToLowerInvariant() -eq $k -and ($null -ne (Get-Target $o.ValueName) -or $o.ValueName.ToLowerInvariant() -eq '**delvals.') }
    } elseif ($null -ne $t) {
        Remove-Where $Set { param($o) $o.Key.ToLowerInvariant() -eq $k -and (Get-Target $o.ValueName) -eq $t }
    } else {
        Remove-Where $Set { param($o) $o.Key.ToLowerInvariant() -eq $k -and $o.ValueName.ToLowerInvariant() -eq $n }
    }
    $Set.Add($Rec)
}

# --- Security templates --------------------------------------------------------------
function Read-Inf([string]$Path) {
    $secs = [ordered]@{}; $cur = $null
    foreach ($raw in [IO.File]::ReadAllLines($Path)) {   # BOM-detected (UTF-16LE)
        $line = $raw.TrimEnd()
        if (-not $line -or $line.TrimStart().StartsWith(';')) { continue }
        if ($line.Trim() -match '^\[(.+)\]$') { $cur = $Matches[1]; if (-not $secs.Contains($cur)) { $secs[$cur] = [ordered]@{} }; continue }
        if ($null -eq $cur) { throw "${Path}: entry outside a section: $line" }
        $id = if ($cur -in 'Service General Setting', 'Registry Keys', 'File Security') { ($line -split ',', 2)[0].Trim().Trim('"').ToLowerInvariant() } else { ($line -split '=', 2)[0].Trim().ToLowerInvariant() }
        $secs[$cur][$id] = $line
    }
    $secs
}
# Same rules as Import-Baseline.py's merge_inf: sections and entries in order of first
# appearance, a later template's entry replaces the earlier one. Returns the text and,
# per section + entry, the template it came from.
function Merge-Inf([object[]]$Templates) {
    $merged = [ordered]@{}; $from = @{}
    foreach ($t in $Templates) {
        foreach ($sec in $t.Sections.Keys) {
            if ($sec -in 'Unicode', 'Version') { continue }
            $tgt = @($merged.Keys | Where-Object { $_ -eq $sec }) | Select-Object -First 1
            if (-not $tgt) { $tgt = $sec; $merged[$tgt] = [ordered]@{} }
            foreach ($id in $t.Sections[$sec].Keys) { $merged[$tgt][$id] = $t.Sections[$sec][$id]; $from["$($tgt.ToLowerInvariant())|$id"] = $t.Name }
        }
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in '[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1') { $lines.Add($l) }
    foreach ($sec in $merged.Keys) { $lines.Add("[$sec]"); foreach ($id in $merged[$sec].Keys) { $lines.Add($merged[$sec][$id]) } }
    [pscustomobject]@{ Text = (($lines.ToArray() -join "`r`n") + "`r`n"); Sections = $merged; From = $from }
}

# --- Live registry -------------------------------------------------------------------
function Format-RecValue($Rec) {
    $d = [byte[]]$Rec.Data
    switch ($Rec.Type) {
        { $_ -in 1, 2 } { $s = $U16.GetString($d); $z = $s.IndexOf([char]0); if ($z -ge 0) { $s = $s.Substring(0, $z) }; return $s }
        7 { return (($U16.GetString($d).TrimEnd([char]0)) -split [char]0) -join '\0' }
        4 { if ($d.Length -eq 4) { return "$([BitConverter]::ToUInt32($d, 0))" } }
        11 { if ($d.Length -eq 8) { return "$([BitConverter]::ToUInt64($d, 0))" } }
    }
    'hex:' + (($d | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Format-LiveValue($Value, [int]$Kind) {
    switch ($Kind) {
        { $_ -in 1, 2 } { return "$Value" }
        7 { return (@($Value) -join '\0') }
        4 { return "$([uint32]([int64]$Value -band 0xFFFFFFFFL))" }
        11 { return "$([BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$Value), 0))" }
    }
    'hex:' + ((@([byte[]]$Value) | ForEach-Object { $_.ToString('x2') }) -join '')
}
# A computer record against HKLM. State: ok / wrong / skipped; Live = what is there.
function Test-LiveRecord($Rec, $AllRecords) {
    $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $key = $null
    try {
        $key = $hklm.OpenSubKey($Rec.Key)
        $n = $Rec.ValueName.ToLowerInvariant()
        $t = Get-Target $Rec.ValueName
        if ($n -eq '**delvals.') {
            # Only the values policy sets in that key may be there
            $allowed = @($AllRecords | Where-Object { $_.Key -eq $Rec.Key -and -not $_.ValueName.StartsWith('**') } | ForEach-Object { $_.ValueName.ToLowerInvariant() })
            $extra = @(if ($key) { $key.GetValueNames() | Where-Object { $allowed -notcontains $_.ToLowerInvariant() } })
            return [pscustomobject]@{ State = $(if ($extra.Count) { 'wrong' } else { 'ok' }); Live = $(if ($extra.Count) { "also holds $($extra -join ', ')" } else { 'only policy values' }) }
        }
        if ($null -eq $t) { return [pscustomobject]@{ State = 'skipped'; Live = '' } }
        $real = if ($key) { @($key.GetValueNames() | Where-Object { $_.ToLowerInvariant() -eq $t }) | Select-Object -First 1 } else { $null }
        if ($n.StartsWith('**del.')) { return [pscustomobject]@{ State = $(if ($null -eq $real) { 'ok' } else { 'wrong' }); Live = $(if ($null -eq $real) { '<absent>' } else { 'present' }) } }
        if ($n.StartsWith('**')) { return [pscustomobject]@{ State = 'skipped'; Live = '' } }
        if ($null -eq $real) { return [pscustomobject]@{ State = 'wrong'; Live = '<absent>' } }
        $kind = [int]$key.GetValueKind($real)
        $live = Format-LiveValue $key.GetValue($real, $null, 'DoNotExpandEnvironmentNames') $kind
        $want = Format-RecValue $Rec
        $ok = ($kind -eq $Rec.Type) -and ($live -ceq $want)
        [pscustomobject]@{ State = $(if ($ok) { 'ok' } else { 'wrong' }); Live = $(if ($kind -ne $Rec.Type) { "$live ($($typeNames[$kind]))" } else { $live }) }
    } catch [System.Security.SecurityException], [System.UnauthorizedAccessException] {
        [pscustomobject]@{ State = 'skipped'; Live = 'not readable (run elevated)' }
    } finally { if ($key) { $key.Close() }; $hklm.Close() }
}

# --- Inputs --------------------------------------------------------------------------
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$listPath = Join-Path $BaselineRoot 'baselines.json'
$ids = @(([IO.File]::ReadAllText($listPath) | ConvertFrom-Json).apply | Where-Object { $_ })
if (-not $ids.Count) { throw "${listPath}: no baselines listed in 'apply'" }
$baselines = foreach ($id in $ids) {
    $dir = Join-Path $BaselineRoot $id
    $index = [IO.File]::ReadAllText((Join-Path $dir 'index.json')) | ConvertFrom-Json
    # The data must be what Import-Baseline.py wrote (index.json holds each file's SHA-256)
    foreach ($p in $index.files.PSObject.Properties) {
        $h = (Get-FileHash -LiteralPath (Join-Path $dir $p.Name) -Algorithm SHA256).Hash
        if ($h -ne "$($p.Value)".ToUpperInvariant()) { throw "Baseline ${id}: $($p.Name) differs from what Import-Baseline.py imported (SHA-256 $h): re-import it" }
    }
    [pscustomobject]@{
        Id = $id; Dir = $dir; Index = $index
        Machine = (Read-BaselineRecords (Join-Path $dir 'registry-machine.json') $id)
        User = (Read-BaselineRecords (Join-Path $dir 'registry-user.json') $id)
        Inf = $(if (Test-Path -LiteralPath (Join-Path $dir 'security.inf')) { Join-Path $dir 'security.inf' })
        Audit = $(if (Test-Path -LiteralPath (Join-Path $dir 'audit.csv')) { Join-Path $dir 'audit.csv' })
    }
}

if ($Mode -eq 'Build' -and $Only) {
    if (-not $OutDir) { throw '-Mode Build needs -OutDir' }
    $sel = foreach ($b in $baselines) { foreach ($side in 'Machine', 'User') { foreach ($r in $b.$side) { if ($r.Source -eq "baseline:$($b.Id):$Only") { [pscustomobject]@{ Side = $side; Rec = $r } } } } }
    if (-not @($sel).Count) { throw "No registry records from a GPO named '$Only'" }
    foreach ($side in 'Machine', 'User') {
        $recs = @($sel | Where-Object Side -eq $side | ForEach-Object Rec)
        if (-not $recs.Count) { continue }
        New-Item -ItemType Directory -Path (Join-Path $OutDir $side) -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $OutDir "$side\Registry.pol"), (ConvertTo-PolBytes $recs))
    }
    return [pscustomobject]@{ Gpo = $Only; Machine = @($sel | Where-Object Side -eq 'Machine').Count; User = @($sel | Where-Object Side -eq 'User').Count }
}

# Overrides (a parse error here means nothing is written at all)
$ovr = Read-PolicyText $OverridesText 'override'

# The kit's own policies, generated by Set-KitRegistry.ps1 as PostInstall always did
$kit = $null
$kitText = Join-Path $LogDir "w11kit-policies-$PID.txt"
try {
    $sb = [scriptblock]::Create([IO.File]::ReadAllText($KitRegistryScript))
    $kitArgs = @{ PolicyTextPath = $kitText; PowerMode = $PowerMode }
    if ($null -ne $Settings) { $kitArgs.Settings = $Settings }
    & $sb @kitArgs 6>$null | Out-Null
    $kit = Read-PolicyText $kitText 'kit'
} catch {
    $failures.Add("Kit policies (Set-KitRegistry.ps1 -PolicyTextPath): $($_.Exception.Message); the baselines and overrides are applied without them")
    $warnings.Add($failures[$failures.Count - 1])
} finally { Remove-Item -LiteralPath $kitText -ErrorAction SilentlyContinue }

function Get-Merged([string]$Side, $Start) {
    $set = New-Object System.Collections.Generic.List[object]
    # (no @() around a generic List: Windows PowerShell 5.1 throws 'Argument types do not match' on an empty one)
    if ($null -ne $Start) { foreach ($r in $Start) { if ($r) { $set.Add($r) } } }
    foreach ($b in $baselines) { foreach ($r in $b.$Side) { Add-Merged $set $r } }
    $cfg = if ($Side -eq 'Machine') { 'Computer' } else { 'User' }
    foreach ($e in $ovr[$cfg]) { Add-Merged $set $e.Rec $e.Op }
    if ($kit) { foreach ($e in $kit[$cfg]) { Add-Merged $set $e.Rec $e.Op } }
    , $set
}

if ($Mode -in 'ListExpected', 'Verify') {
    $m = Get-Merged 'Machine' $null
    if ($Mode -eq 'ListExpected') {
        $u = Get-Merged 'User' $null
        $view = { param($r, $hive) [pscustomobject]@{ Hive = $hive; Key = $r.Key; ValueName = $r.ValueName; Type = $(if ($typeNames.ContainsKey([int]$r.Type)) { $typeNames[[int]$r.Type] } else { "$($r.Type)" }); Value = (Format-RecValue $r); Source = $r.Source } }
        return [pscustomobject]@{
            Machine  = @($m | ForEach-Object { & $view $_ 'HKLM' })
            User     = @($u | ForEach-Object { & $view $_ 'HKCU' })
            Warnings = $warnings.ToArray()
        }
    }
    # Verify: every baseline computer record still in the merged set, against the registry
    $total = 0; foreach ($b in $baselines) { $total += $b.Machine.Count }
    $ok = 0; $wrong = New-Object System.Collections.Generic.List[string]; $skipped = 0; $per = [ordered]@{}
    foreach ($r in $m) {
        if (-not $r.Source.StartsWith('baseline:')) { continue }
        $id = $r.Source.Split(':')[1]
        if (-not $per.Contains($id)) { $per[$id] = 0 }
        $res = Test-LiveRecord $r $m
        switch ($res.State) {
            'ok' { $ok++; $per[$id]++ }
            'skipped' { $skipped++ }
            default { $wrong.Add("HKLM\$($r.Key)\$($r.ValueName): want $(Format-RecValue $r), found $($res.Live)") }
        }
    }
    $checked = $ok + $wrong.Count
    return [pscustomobject]@{
        Records = $total; Checked = $checked; Ok = $ok; PerBaseline = $per; Replaced = ($total - $checked - $skipped)
        Skipped = $skipped; Wrong = $wrong.ToArray(); Warnings = $warnings.ToArray()
    }
}

# --- Apply / Build -----------------------------------------------------------------------
if ($Mode -eq 'Build') { if (-not $OutDir) { throw '-Mode Build needs -OutDir' }; $target = $OutDir } else { $target = $GpRoot }
$machinePol = Join-Path $target 'Machine\Registry.pol'
$userPol = Join-Path $target 'User\Registry.pol'
$existingM = if ($Mode -eq 'Apply') { Read-Pol $machinePol 'local' } else { $null }
$existingU = if ($Mode -eq 'Apply') { Read-Pol $userPol 'local' } else { $null }
$machine = Get-Merged 'Machine' $existingM
$user = Get-Merged 'User' $existingU

# Security template: the baselines' merged templates, then the overrides
$tmpls = @(foreach ($b in $baselines) { if ($b.Inf) { [pscustomobject]@{ Name = "baseline:$($b.Id)"; Sections = (Read-Inf $b.Inf) } } })
$tmpls += [pscustomobject]@{ Name = 'override'; Sections = (Read-Inf $OverridesInf) }
$inf = Merge-Inf $tmpls
$baseInf = Merge-Inf @($tmpls | Where-Object Name -ne 'override')

# Client-side extensions for gpt.ini: CSE GUID -> tool GUIDs
function Get-CseMap([string]$Side) {
    $map = @{}
    $add = { param($cse, $tools) $c = $cse.ToUpperInvariant(); if (-not $map.ContainsKey($c)) { $map[$c] = New-Object System.Collections.Generic.HashSet[string] }; foreach ($t in @($tools)) { if ($t) { [void]$map[$c].Add($t.ToUpperInvariant()) } } }
    & $add $registryCse @($(if ($Side -eq 'machine') { '{D02B1F72-3407-48AE-BA88-E8213C6761F1}' } else { '{D02B1F73-3407-48AE-BA88-E8213C6761F1}' }))
    foreach ($b in $baselines) { foreach ($blk in @($b.Index.extensions.$Side)) { $l = @($blk); if ($l.Count) { & $add $l[0] @($l | Select-Object -Skip 1) } } }
    # A CSE listed without a tool gets the Administrative Templates tool of its side
    foreach ($c in @($map.Keys)) { if (-not $map[$c].Count) { [void]$map[$c].Add($(if ($Side -eq 'machine') { '{D02B1F72-3407-48AE-BA88-E8213C6761F1}' } else { '{D02B1F73-3407-48AE-BA88-E8213C6761F1}' })) } }
    $map
}
function Merge-CseList([string]$Existing, [hashtable]$Map) {
    $all = @{}
    foreach ($blk in [regex]::Matches("$Existing", '\[([^\[\]]*)\]')) {
        $g = @([regex]::Matches($blk.Groups[1].Value, '\{[0-9A-Fa-f-]{36}\}') | ForEach-Object { $_.Value.ToUpperInvariant() })
        if (-not $g.Count) { continue }
        if (-not $all.ContainsKey($g[0])) { $all[$g[0]] = New-Object System.Collections.Generic.HashSet[string] }
        foreach ($t in @($g | Select-Object -Skip 1)) { [void]$all[$g[0]].Add($t) }
    }
    foreach ($c in $Map.Keys) {
        if (-not $all.ContainsKey($c)) { $all[$c] = New-Object System.Collections.Generic.HashSet[string] }
        foreach ($t in $Map[$c]) { [void]$all[$c].Add($t) }
    }
    $sorted = [string[]]@($all.Keys); [Array]::Sort($sorted, [StringComparer]::OrdinalIgnoreCase)
    ($sorted | ForEach-Object { $tools = [string[]]@($all[$_]); [Array]::Sort($tools, [StringComparer]::OrdinalIgnoreCase); "[$_$($tools -join '')]" }) -join ''
}
function Get-GptIni([string]$Path, [bool]$Bump) {
    $lines = if (Test-Path -LiteralPath $Path) { @([IO.File]::ReadAllLines($Path)) } else { @('[General]') }
    $vals = [ordered]@{}; $other = New-Object System.Collections.Generic.List[string]; $inGeneral = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $inGeneral = ($Matches[1] -eq 'General'); if (-not $inGeneral) { $other.Add($l) }; continue }
        if ($inGeneral -and $l -match '^\s*([^=]+?)\s*=(.*)$') { $vals[$Matches[1]] = $Matches[2]; continue }
        if (-not $inGeneral -and $l.Trim()) { $other.Add($l) }
    }
    $ver = 0L; [void][int64]::TryParse("$($vals['Version'])", [ref]$ver)
    $mv = $ver -band 0xFFFF; $uv = ($ver -shr 16) -band 0xFFFF
    if ($Bump) { $mv = ($mv % 0xFFFF) + 1; $uv = ($uv % 0xFFFF) + 1 }
    $vals['gPCMachineExtensionNames'] = Merge-CseList $vals['gPCMachineExtensionNames'] (Get-CseMap 'machine')
    $vals['Version'] = "$(($uv -shl 16) -bor $mv)"
    $vals['gPCUserExtensionNames'] = Merge-CseList $vals['gPCUserExtensionNames'] (Get-CseMap 'user')
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('[General]')
    foreach ($k in $vals.Keys) { $out.Add("$k=$($vals[$k])") }
    foreach ($l in $other) { $out.Add($l) }
    ($out.ToArray() -join "`r`n") + "`r`n"
}

$counts = "computer: $($machine.Count) registry entries, user: $($user.Count)"
if ($Mode -eq 'Build') {
    foreach ($d in 'Machine', 'User') { New-Item -ItemType Directory -Path (Join-Path $OutDir $d) -Force | Out-Null }
    [IO.File]::WriteAllBytes($machinePol, (ConvertTo-PolBytes $machine))
    [IO.File]::WriteAllBytes($userPol, (ConvertTo-PolBytes $user))
    [IO.File]::WriteAllText((Join-Path $OutDir 'gpt.ini'), (Get-GptIni (Join-Path $OutDir 'gpt.ini') $true), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $OutDir 'security.inf'), $inf.Text, $U16)
    $auditOut = $null
    try {
        $sbA = [scriptblock]::Create([IO.File]::ReadAllText($MergeAuditScript))
        $auditOut = & $sbA -BaselineCsv @($baselines | Where-Object Audit | ForEach-Object Audit) -AdditionsCsv $AuditAdditions -OutFile (Join-Path $OutDir 'audit.csv')
    } catch { $failures.Add("Audit merge: $($_.Exception.Message)") }
    return [pscustomobject]@{ Out = $OutDir; Machine = $machine; User = $user; Inf = $inf; Audit = $auditOut; Failures = $failures.ToArray(); Summary = $counts }
}

# --- Apply (elevated) ----------------------------------------------------------------
$critical = $false
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $o = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Where-Object { $_.Trim() -and $_ -ne 'System.Management.Automation.RemoteException' }
        [pscustomobject]@{ Code = $LASTEXITCODE; Out = (@($o) -join ' ') }
    } finally { $ErrorActionPreference = $old }
}

# a + b. Registry.pol (computer, user) and gpt.ini
Write-Host "  Registry policy: $counts (baselines $($ids -join ', '), $($ovr.Computer.Count + $ovr.User.Count) override entries, $(if ($kit) { $kit.Computer.Count + $kit.User.Count } else { 0 }) kit entries)"
foreach ($d in 'Machine', 'User') { New-Item -ItemType Directory -Path (Join-Path $GpRoot $d) -Force | Out-Null }
[IO.File]::WriteAllBytes($machinePol, (ConvertTo-PolBytes $machine))
[IO.File]::WriteAllBytes($userPol, (ConvertTo-PolBytes $user))
$gpt = @(Get-ChildItem -LiteralPath $GpRoot -File -Filter 'gpt.ini' -ErrorAction SilentlyContinue | Select-Object -First 1)
$gptPath = if ($gpt.Count) { $gpt[0].FullName } else { Join-Path $GpRoot 'gpt.ini' }
[IO.File]::WriteAllText($gptPath, (Get-GptIni $gptPath $true), [Text.Encoding]::ASCII)
Write-Host "  gpt.ini: $((Get-Content -LiteralPath $gptPath | Where-Object { $_ -like 'Version=*' }) -join '')"

# c. Security template (secedit on a temporary database)
$infPath = Join-Path $LogDir 'w11kit-security.inf'
[IO.File]::WriteAllText($infPath, $inf.Text, $U16)
$db = Join-Path $env:TEMP "w11kit-secedit-$PID.sdb"
$sLog = Join-Path $LogDir 'w11kit-secedit.log'
$r = Invoke-Native secedit.exe @('/configure', '/db', $db, '/cfg', $infPath, '/overwrite', '/quiet', '/log', $sLog)
Remove-Item -LiteralPath $db, "$db.jfm" -ErrorAction SilentlyContinue
Write-Host "  Security template: secedit /configure exit code $($r.Code) ($(($inf.Sections.Keys | ForEach-Object { $_ }) -join ', '); log $sLog)"
$seceditCode = $r.Code

# d. Advanced audit policy: ONE merged file (never the additions alone)
try {
    $gpAudit = Join-Path $GpRoot 'Machine\Microsoft\Windows NT\Audit\audit.csv'
    $merged = Join-Path $LogDir 'w11kit-audit.csv'
    $sbA = [scriptblock]::Create([IO.File]::ReadAllText($MergeAuditScript))
    $m = & $sbA -BaselineCsv @($baselines | Where-Object Audit | ForEach-Object Audit) -LocalCsv $gpAudit -AdditionsCsv $AuditAdditions -OutFile $merged
    New-Item -ItemType Directory -Path (Split-Path $gpAudit) -Force | Out-Null
    Copy-Item -LiteralPath $merged -Destination $gpAudit -Force
    $r = Invoke-Native auditpol.exe @('/restore', "/file:$merged")
    if ($r.Code -ne 0) { throw "auditpol /restore exit code $($r.Code): $($r.Out)" }
    Write-Host "  Audit policy: $($m.Rows) subcategories ($($m.BaselineRows) from the baselines + local policy, $($m.Added) added, $($m.Changed) raised)"
} catch { $failures.Add("Advanced audit policy: $($_.Exception.Message)") }

# f. Refresh, then read the overrides back
$r = Invoke-Native gpupdate.exe @('/force', '/wait:120')
if ($r.Code -ne 0) { $failures.Add("gpupdate /force: exit code $($r.Code)") }

# Registry overrides (text file, computer side): in effect, or the baseline's value instead?
$baseOnly = New-Object System.Collections.Generic.List[object]
foreach ($b in $baselines) { foreach ($x in $b.Machine) { Add-Merged $baseOnly $x } }
$ovrBad = 0
foreach ($e in $ovr.Computer) {
    if ($e.Op -ne 'set') { continue }
    $res = Test-LiveRecord $e.Rec $machine
    if ($res.State -ne 'wrong') { continue }
    $ovrBad++
    $t = Get-Target $e.Rec.ValueName
    $base = $baseOnly | Where-Object { $_.Key -eq $e.Rec.Key -and (Get-Target $_.ValueName) -eq $t } | Select-Object -First 1
    $isBase = $base -and (Test-LiveRecord $base $baseOnly).State -eq 'ok'
    if ($isBase) { $critical = $true }
    $failures.Add("Override not in effect: HKLM\$($e.Rec.Key)\$($e.Rec.ValueName) = $($res.Live), want $(Format-RecValue $e.Rec)$(if ($isBase) { " (the baseline's value: CRITICAL)" })")
}
# Security template: registry values read directly; overrides that show the baseline's value are critical
$regVals = $inf.Sections.Keys | Where-Object { $_ -eq 'Registry Values' } | Select-Object -First 1
if ($regVals) {
    foreach ($id in $inf.Sections[$regVals].Keys) {
        $lhs, $rhs = $inf.Sections[$regVals][$id] -split '=', 2
        if ($lhs -notmatch '^MACHINE\\(.+)\\([^\\]+)$' -or $rhs -notmatch '^(\d+),(.*)$') { continue }
        $k = ($lhs -replace '^MACHINE\\(.+)\\[^\\]+$', '$1'); $n = ($lhs -replace '^.*\\', ''); $ty = [int]$Matches[1]; $v = $Matches[2]
        if ($ty -notin 1, 2, 4, 7) { continue }
        $want = if ($ty -eq 4) { "$([uint32]$v)" } elseif ($ty -eq 7) { (@($v -split ',' | ForEach-Object { $_.Trim('"') })) -join '\0' } else { $v.Trim('"') }
        $rec = New-Rec $k $n $ty $(if ($ty -eq 4) { [BitConverter]::GetBytes([uint32]$v) } elseif ($ty -eq 7) { Get-MultiBytes @($v -split ',' | ForEach-Object { $_.Trim('"') }) } else { Get-StringBytes $want }) 'template'
        $res = Test-LiveRecord $rec @()
        if ($res.State -ne 'wrong') { continue }
        $src = $inf.From["registry values|$id"]
        $isBase = $false
        if ($src -eq 'override') {
            $bl = if ($baseInf.Sections.Contains('Registry Values')) { $baseInf.Sections['Registry Values'][$id] }
            if ($bl -and $bl -match '=\d+,(.*)$') { $isBase = ($res.Live -ceq $Matches[1].Trim('"')) }
            if ($isBase) { $critical = $true }
        }
        $failures.Add("Security template value not in effect ($src): HKLM\$k\$n = $($res.Live), want $want$(if ($isBase) { " (the baseline's value: CRITICAL)" })")
    }
}
# Security template: account policies and user rights, read back with secedit /export
$exp = Join-Path $env:TEMP "w11kit-secexport-$PID.inf"
$r = Invoke-Native secedit.exe @('/export', '/cfg', $exp, '/areas', 'SECURITYPOLICY', 'USER_RIGHTS', '/quiet')
if (Test-Path -LiteralPath $exp) {
    $live = Read-Inf $exp
    Remove-Item -LiteralPath $exp -ErrorAction SilentlyContinue
    $notExported = New-Object System.Collections.Generic.List[string]
    foreach ($sec in 'System Access', 'Privilege Rights') {
        $want = $inf.Sections.Keys | Where-Object { $_ -eq $sec } | Select-Object -First 1
        if (-not $want) { continue }
        $have = $live.Keys | Where-Object { $_ -eq $sec } | Select-Object -First 1
        foreach ($id in $inf.Sections[$want].Keys) {
            $wName, $wv = $inf.Sections[$want][$id] -split '=', 2
            $wName = $wName.Trim(); $wv = $wv.Trim()
            $hl = if ($have -and $live[$have].Contains($id)) { $live[$have][$id] } else { $null }
            if ($sec -eq 'Privilege Rights') {
                # Order-free SID lists; a right granted to no one isn't exported at all
                $ws = @($wv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
                $hs = @(if ($hl) { ($hl -split '=', 2)[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object })
                if (($ws -join ',') -ne ($hs -join ',')) { $failures.Add("User right not in effect ($($inf.From["privilege rights|$id"])): $wName = $($hs -join ','), want $($ws -join ',')") }
            } elseif ($null -eq $hl) {
                $notExported.Add($wName)
            } elseif ((($hl -split '=', 2)[1].Trim()) -ne $wv) {
                $failures.Add("Account policy not in effect ($($inf.From["system access|$id"])): $(($hl -split '=', 2)[0].Trim()) = $((($hl -split '=', 2)[1]).Trim()), want $wv")
            }
        }
    }
    if ($notExported.Count) { Write-Host "  (not in secedit /export, not checked: $($notExported -join ', '))" }
} else { $failures.Add("secedit /export (read-back of the security template) failed: exit code $($r.Code)") }
# Services from the template: start type in the registry (2 automatic, 3 manual, 4 disabled)
$svcSec = $inf.Sections.Keys | Where-Object { $_ -eq 'Service General Setting' } | Select-Object -First 1
if ($svcSec) {
    foreach ($id in $inf.Sections[$svcSec].Keys) {
        $f = $inf.Sections[$svcSec][$id] -split ','
        $start = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$($f[0].Trim('"'))" -Name Start -ErrorAction SilentlyContinue).Start
        if ($null -ne $start -and "$start" -ne $f[1].Trim()) { $failures.Add("Service start type not in effect ($($inf.From["service general setting|$id"])): $($f[0].Trim('"')) = $start, want $($f[1].Trim())") }
    }
}
if ($seceditCode -ne 0) {
    # secedit also exits non-zero for mere warnings (e.g. an account it couldn't map): the
    # read-back above decides. A failure only if something didn't read back.
    $tmplBad = @($failures | Where-Object { $_ -match '^(Security template value|Account policy|User right|Service start type) not in effect' }).Count
    if ($tmplBad) { $failures.Add("secedit /configure exit code $seceditCode (see $sLog)") }
    else { Write-Host "  secedit /configure exit code $seceditCode, but every value read back as set (see $sLog)" }
}
Write-Host "  Read-back: $($ovr.Computer.Count) registry overrides ($ovrBad not in effect), security template, user rights, services: $($failures.Count) problem(s)$(if ($critical) { ', CRITICAL' })"

[pscustomobject]@{ Failures = $failures.ToArray(); Critical = $critical; Summary = $counts }
