<#
.SYNOPSIS
    Builds ONE advanced audit policy CSV: the Microsoft baseline's audit.csv rows
    plus the kit's additions (config/baseline-overrides-audit.csv, the DISA STIG
    subcategories). Apply-Policy.ps1 applies the result (docs/reference/SECURITY-BASELINE.md, "Advanced audit policy").

.DESCRIPTION
    Why one file: the local Group Policy keeps a single audit.csv (C:\Windows\System32\GroupPolicy\Machine\
    Microsoft\Windows NT\Audit\audit.csv) that the audit client-side extension
    re-applies at every policy refresh. Applying only the additions risks that file
    holding the additions alone, and the baseline's rows would be gone at the next
    refresh. So the rows are merged here, and the merged file is what gets applied.

    Rows are keyed by 'Subcategory GUID' (lower case), or by 'Subcategory' for rows
    without a GUID (global SACL / option rows). Order of precedence, later wins:
      1. -BaselineCsv   the baseline's own audit.csv file(s), as shipped
      2. -LocalCsv      the local GPO's current audit.csv (what the baseline install
                        wrote, plus anything from an earlier run of this script)
      3. -AdditionsCsv  the kit's additions: they win on a conflict
    Missing -BaselineCsv / -LocalCsv files are skipped; at least one baseline row
    must be found, otherwise this throws (applying the additions alone is exactly
    what must never happen).

    The output keeps the baseline's format: the same header, no quoting, ASCII, CRLF.
    Returns a summary object (Rows, BaselineRows, Added, Changed, Out); nothing is
    printed and nothing outside -OutFile is written. Loadable as a scriptblock
    (no $PSScriptRoot needed).
#>
[CmdletBinding()]
param(
    [string[]]$BaselineCsv = @(),
    [string]$LocalCsv,
    [Parameter(Mandatory)][string]$AdditionsCsv,
    [Parameter(Mandatory)][string]$OutFile
)

$ErrorActionPreference = 'Stop'
$header = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'
$columns = $header -split ','

function Read-AuditCsv([string]$Path) {
    $lines = @([IO.File]::ReadAllLines($Path) | Where-Object { "$_".Trim() })
    if (-not $lines.Count) { return }
    $h = ($lines[0] -split ',' | ForEach-Object { $_.Trim() }) -join ','
    if ($h -ne $header) { throw "${Path}: unexpected header '$($lines[0])' (expected '$header')" }
    if ($lines.Count -lt 2) { return }
    foreach ($l in $lines[1..($lines.Count - 1)]) {
        $f = $l -split ','
        # Audit CSVs have exactly seven fields and no quoting (auditpol /backup, the baseline)
        if ($f.Count -ne 7) { throw "${Path}: expected 7 fields, found $($f.Count): '$l'" }
        $row = [ordered]@{}
        for ($i = 0; $i -lt 7; $i++) { $row[$columns[$i]] = $f[$i].Trim() }
        $key = if ($row['Subcategory GUID']) { $row['Subcategory GUID'].ToLowerInvariant() } else { "name:$($row['Subcategory'].ToLowerInvariant())" }
        [pscustomobject]@{ Key = $key; Row = $row; Line = (($columns | ForEach-Object { $row[$_] }) -join ',') }
    }
}

# Ordered by first appearance, so the baseline's order is kept and additions come last
$merged = New-Object System.Collections.Specialized.OrderedDictionary
$baseKeys = New-Object System.Collections.Generic.List[string]
$sources = @()
foreach ($p in @($BaselineCsv | Where-Object { $_ -and (Test-Path -LiteralPath $_) })) { $sources += , @('baseline', $p) }
if ($LocalCsv -and (Test-Path -LiteralPath $LocalCsv)) { $sources += , @('local', $LocalCsv) }
foreach ($s in $sources) {
    foreach ($r in @(Read-AuditCsv $s[1])) {
        if ($merged.Contains($r.Key)) { $merged[$r.Key] = $r } else { $merged.Add($r.Key, $r) }
        if (-not $baseKeys.Contains($r.Key)) { $baseKeys.Add($r.Key) }
    }
}
if (-not $merged.Count) { throw "No baseline audit rows found (looked in: $((@($BaselineCsv) + @($LocalCsv) | Where-Object { $_ }) -join '; ')): refusing to apply the additions alone" }

$added = 0; $changed = 0
foreach ($r in @(Read-AuditCsv $AdditionsCsv)) {
    if ($merged.Contains($r.Key)) {
        if ($merged[$r.Key].Line -ne $r.Line) { $changed++ }
        $merged[$r.Key] = $r
    } else { $merged.Add($r.Key, $r); $added++ }
}

$out = New-Object System.Collections.Generic.List[string]
$out.Add($header)
foreach ($k in $merged.Keys) { $out.Add($merged[$k].Line) }
[IO.File]::WriteAllText($OutFile, (($out -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

[pscustomobject]@{ Rows = $merged.Count; BaselineRows = $baseKeys.Count; Added = $added; Changed = $changed; Out = $OutFile }
