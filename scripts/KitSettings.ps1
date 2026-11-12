<#
.SYNOPSIS
    The user's settings for Build-Iso.ps1, and what they change in the files the build
    stages. Defines functions only.

    Loaded the scriptblock way (a policy may block .ps1 files):
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitSettings.ps1'))))

    Get-KitSettings -KitRoot <kit> [-SettingsFile <file>] [-ThisPcLocale <text>]
        The effective settings: config\settings.defaults.json (the kit's defaults, the
        only place they are declared) with your file laid over it field by field
        (-SettingsFile, a full path or one relative to the kit folder; else
        config\settings.local.json when it exists). An unknown
        field is a problem (a typo would otherwise be ignored silently); for a field
        this kit renamed, the message gives the new name.
        Keyboard, formats, system locale, time zone and home location that your file
        does not set are taken from -ThisPcLocale (the build PC's own values, read by
        Run-Build.cmd before it elevates: scripts\Invoke-KitLauncher.ps1) when they pass
        the same checks as a value from a file; otherwise the kit's default stays and a
        note says so. Nothing here reads the PC or the signed-in account.
        Returns Settings (ordered), Problems, Notes, Files, DefaultsPath, OverlayPath,
        OverlayLabel, FromFile, Sources (per field: where its value came from),
        ThisPcAccount.

    Get-KitAccountNameProblem, New-KitBuiltinAccountName
        Account-name rules, and the per-build names for the built-in Administrator and
        Guest accounts.

    ConvertTo-StagedOverridesInf, ConvertTo-StagedStartLayout, Get-KitRequiredApps
        config\baseline-overrides.inf, config\LayoutModification.json and the required
        apps of config\image.json as this build stages them.
#>

# Names Windows itself uses for local accounts: never a kit account, never a new name
# for a built-in account.
function Get-KitReservedAccountNames { , @('Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount', 'defaultuser0') }

# $null when the name is fine, else what is wrong with it. -Also: more names it must not be.
function Get-KitAccountNameProblem([string]$Name, [string[]]$Also) {
    if ($Name -notmatch '^[A-Za-z0-9._-]{1,20}$' -or $Name -match '^\.|\.$') { return "'$Name' is not a valid account name (1-20 letters, digits, '.', '_', '-'; no '.' at either end)" }
    if ((Get-KitReservedAccountNames) -contains $Name) { return "'$Name' is a name Windows uses itself" }
    if ($Also -contains $Name) { return "'$Name' is used twice (the two kit accounts, the two built-in accounts and the computer name must all differ)" }
    $null
}

# A new name for a built-in account: four consonant-vowel syllables (8 letters, easy to
# read out, valid as a Windows account name), each letter drawn uniformly with the
# operating system's cryptographic random number generator (rejection sampling: no
# modulo bias), drawn again while it is one of -Avoid. Not a secret: the build prints it.
function New-KitBuiltinAccountName([string[]]$Avoid) {
    $consonants = 'bdfgklmnprstvz'; $vowels = 'aeiou'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] 4
    $pick = {
        param([string]$Set)
        $n = [uint32]$Set.Length
        $limit = [uint32]::MaxValue - ([uint32]::MaxValue % $n)   # largest multiple of n
        do { $rng.GetBytes($buf); $v = [BitConverter]::ToUInt32($buf, 0) } while ($v -ge $limit)
        $Set[[int]($v % $n)]
    }
    try {
        do {
            $s = ''
            for ($i = 0; $i -lt 4; $i++) { $s += (& $pick $consonants); $s += (& $pick $vowels) }
            $name = $s.Substring(0, 1).ToUpperInvariant() + $s.Substring(1)
        } while ($Avoid -contains $name)
        $name
    } finally { $rng.Dispose() }
}

# A parsed JSON object as nested ordered dictionaries (lists and values as they are)
function ConvertTo-KitSettingsTable($Object) {
    $out = [ordered]@{}
    foreach ($p in $Object.PSObject.Properties) {
        if ($p.Value -is [pscustomobject]) { $out[$p.Name] = ConvertTo-KitSettingsTable $p.Value }
        else { $out[$p.Name] = $p.Value }
    }
    $out
}

# One locale value against what Windows Setup accepts: $null, or what is wrong
function Get-KitLocaleProblem([string]$Field, $Value) {
    if ($Field -in 'uiLanguage', 'systemLocale', 'userLocale') {
        # Language tags as Windows Setup takes them: ll-CC or ll-Script-CC (en-US, de-DE, sr-Latn-RS)
        if ($Value -isnot [string] -or $Value -cnotmatch '^[a-z]{2,3}(-[A-Z][a-z]{3})?-[A-Z]{2}$') { return "'$Value' is not a language tag like en-US or de-DE" }
    } elseif ($Field -eq 'inputLocale') {
        # Keyboards: <language id>:<layout id> (0407:00000407), or an IME's {GUID}{GUID}; several separated by ';'
        $kbd = '[0-9A-Fa-f]{4}:([0-9A-Fa-f]{8}|\{[0-9A-Fa-f-]{36}\}\{[0-9A-Fa-f-]{36}\})'
        if ($Value -isnot [string] -or $Value -notmatch "^$kbd(;$kbd)*$") { return "'$Value' is not like 0409:00000409 (several: separated by ';')" }
    } elseif ($Field -eq 'timeZone') {
        if ($Value -isnot [string] -or -not $Value.Trim()) { return "'$Value' is not a Windows time zone ID (tzutil /l lists them)" }
        try { $null = [TimeZoneInfo]::FindSystemTimeZoneById($Value) } catch { return "'$Value' is not a Windows time zone ID (tzutil /l lists them)" }
    } elseif ($Field -eq 'homeLocation') {
        # The GeoId and the ISO code must name the same country (Windows' own table)
        $iso = "$($Value.isoCode)"; $id = $Value.geoId
        if ($iso -cnotmatch '^[A-Z]{2}$') { return "isoCode '$iso' is not an upper-case two-letter country code" }
        try {
            $region = New-Object Globalization.RegionInfo $iso
            if ("$($region.GeoId)" -ne "$id") { return "isoCode '$iso' is GeoId $($region.GeoId) ($($region.EnglishName)), not $id; use the two-letter code and its GeoId" }
        } catch { return "isoCode '$iso' is not a country code Windows knows" }
    }
    $null
}

# The defaults with the file's values, each checked against the default's kind: an
# object, true/false, a whole number, text, text or null (default null), a list (default
# []). $State: Problems, FromFile, Defaulted (lists), Label (the file's name), Enums.
function Merge-KitSettings($Defaults, $User, [string]$Prefix, $State) {
    # Fields this kit renamed: the message says what they are called now
    $renamed = @{
        'checks'                     = "it is now called 'reminders' (the same fields inside)"
        'options.smartAppControlOff' = "it is now 'options.smartAppControl': `"off`" (was true) or `"leave`" (was false)"
        'options.developerTweaks'    = "it is now called 'options.longPaths'"
    }
    $out = [ordered]@{}
    $userNames = @(if ($null -ne $User) { $User.PSObject.Properties | ForEach-Object Name })
    foreach ($n in $userNames) {
        if ($n -eq 'description' -or $Defaults.Contains($n)) { continue }
        $path = "$Prefix$n"
        if ($renamed.ContainsKey($path)) { $State.Problems.Add("$($State.Label): '$path' is not a field any more: $($renamed[$path])") }
        else { $State.Problems.Add("$($State.Label): unknown field '$path' (the fields are in config\settings.defaults.json)") }
    }
    foreach ($k in @($Defaults.Keys)) {
        $d = $Defaults[$k]
        $path = "$Prefix$k"
        $u = $null
        if ($userNames -contains $k) { $u = $User.$k }
        if ($d -is [Collections.Specialized.OrderedDictionary]) {
            if ($null -ne $u -and $u -isnot [pscustomobject]) { $State.Problems.Add("$($State.Label): '$path' must be an object ({ ... })"); $u = $null }
            $out[$k] = Merge-KitSettings $d $u "$path." $State
            continue
        }
        if ($null -eq $u) { $State.Defaulted.Add($path); $out[$k] = $d; continue }
        $want = $null
        if ($null -eq $d) { if ($u -isnot [string] -or -not $u.Trim()) { $want = 'text or null' } }
        elseif ($d -is [array]) { if ($u -isnot [array]) { $want = 'a list ([ ... ])' } }
        elseif ($d -is [bool]) { if ($u -isnot [bool]) { $want = 'true or false' } }
        elseif ($d -is [int]) { if (($u -isnot [int] -and $u -isnot [long]) -or $u -le 0) { $want = 'a positive whole number' } }
        elseif ($u -isnot [string] -or -not $u.Trim()) { $want = 'non-empty text' }
        elseif ($State.Enums.ContainsKey($path) -and $State.Enums[$path] -cnotcontains $u) { $want = 'one of: "' + ($State.Enums[$path] -join '", "') + '"' }
        if ($want) {
            $State.Problems.Add("$($State.Label): '$path' must be $want, not '$(if ($u -is [bool]) { "$u".ToLowerInvariant() } else { $u })'")
            $State.Defaulted.Add($path); $out[$k] = $d
            continue
        }
        $State.FromFile.Add($path)
        if ($u -is [long]) { $out[$k] = [int]$u } else { $out[$k] = $u }
    }
    $out
}

# One entry of options.asrExclusions: the full path of a folder or a program, on a drive (not a
# whole drive), without the characters a policy value or Windows paths can't hold. Returns the
# problem, or nothing.
function Get-KitAsrExclusionProblem([string]$Path) {
    if ($Path -notmatch '^[A-Za-z]:\\') { return 'must be a full path, like C:\Tools\runner' }
    if ($Path -match '["<>|\x00-\x1F]') { return 'must not contain " < > | or control characters' }
    if ($Path -match '^[A-Za-z]:\\[\\*?.]*$') { return 'must name a folder or a program, not a whole drive' }
}

function Get-KitSettings([string]$KitRoot, [string]$SettingsFile, [string]$ThisPcLocale) {
    $problems = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]
    $defaultsPath = Join-Path $KitRoot 'config\settings.defaults.json'
    try {
        $raw = [IO.File]::ReadAllText($defaultsPath) | ConvertFrom-Json
        if ($raw -isnot [pscustomobject]) { throw 'not a JSON object' }
        $defaults = ConvertTo-KitSettingsTable $raw
        $defaults.Remove('description')
        if ($defaults['schemaVersion'] -isnot [int]) { throw 'no schemaVersion' }
    } catch { throw "The kit's settings defaults ($defaultsPath) are not readable: $($_.Exception.Message)" }

    # Your file: -Settings <file>, else config\settings.local.json (untracked: a git pull never touches it)
    $overlayPath = $null; $overlayLabel = $null; $user = $null
    if ($SettingsFile) {
        $overlayLabel = Split-Path -Leaf $SettingsFile
        # As typed, else relative to the kit folder (an elevated console starts in System32)
        $typed = $SettingsFile
        if (-not (Test-Path -LiteralPath $typed) -and -not [IO.Path]::IsPathRooted($typed) -and (Test-Path -LiteralPath (Join-Path $KitRoot $typed))) { $typed = Join-Path $KitRoot $typed }
        try { $overlayPath = (Resolve-Path -LiteralPath $typed -ErrorAction Stop).ProviderPath }
        catch { $problems.Add("-Settings ${SettingsFile}: file not found (give the full path, or one relative to the kit folder)") }
    } else {
        $local = Join-Path $KitRoot 'config\settings.local.json'
        if (Test-Path -LiteralPath $local) { $overlayPath = $local; $overlayLabel = 'settings.local.json' }
    }
    if ($overlayPath) {
        try {
            $user = [IO.File]::ReadAllText($overlayPath) | ConvertFrom-Json
            if ($user -isnot [pscustomobject]) { $user = $null; throw 'not a JSON object ({ ... })' }
        } catch { $problems.Add("${overlayLabel} is not readable: $($_.Exception.Message)") }
    }
    $state = @{
        Problems = $problems; Label = "$overlayLabel"
        FromFile = (New-Object System.Collections.Generic.List[string]); Defaulted = (New-Object System.Collections.Generic.List[string])
        Enums = @{ 'options.smartAppControl' = @('leave', 'off'); 'options.optionalUpdates' = @('off', 'auto', 'userChoice'); 'options.asrPrevalenceRule' = @('block', 'audit', 'off'); 'options.netbios' = @('off', 'leave'); 'options.firstNetworkCategory' = @('public', 'private'); 'options.dns.overHttps' = @('leave', 'require') }
    }
    $s = Merge-KitSettings $defaults $user '' $state
    # The file's own schemaVersion only says which kit it was written for
    $fileVersion = $s.schemaVersion
    $s.schemaVersion = $defaults.schemaVersion
    [void]$state.FromFile.Remove('schemaVersion')
    if ($fileVersion -gt $defaults.schemaVersion) { $problems.Add("${overlayLabel}: schemaVersion $fileVersion is newer than this kit reads ($($defaults.schemaVersion)): update the kit (Run-Build.cmd, first question) and build again") }

    # --- This PC's values (Run-Build.cmd read them as the account that started it) -------
    $pc = $null; $pcAccount = $null
    if ($ThisPcLocale) {
        try {
            $pc = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ThisPcLocale)) | ConvertFrom-Json
            if ($pc -isnot [pscustomobject]) { $pc = $null; throw 'not a JSON object' }
            if ($pc.account -is [string] -and $pc.account -match '^[^\x00-\x1F"]{1,200}$') { $pcAccount = $pc.account }
        } catch { $pc = $null; $notes.Add("-ThisPcLocale is not the text Run-Build.cmd makes (Base64 of a JSON object): this PC's keyboard, formats, time zone and home location are not used.") }
    }
    $labels = [ordered]@{ inputLocale = 'keyboard'; userLocale = 'formats'; systemLocale = 'system locale'; timeZone = 'time zone'; homeLocation = 'home location' }
    $sources = [ordered]@{}
    $defaultUsed = New-Object System.Collections.Generic.List[string]
    foreach ($f in $labels.Keys) {
        $isSet = if ($f -eq 'homeLocation') { $state.FromFile -contains 'locale.homeLocation.geoId' -or $state.FromFile -contains 'locale.homeLocation.isoCode' } else { $state.FromFile -contains "locale.$f" }
        if ($isSet) { $sources[$f] = $overlayLabel; continue }
        $sources[$f] = 'kit default'
        $shown = if ($f -eq 'homeLocation') { "$($s.locale.homeLocation.isoCode) ($($s.locale.homeLocation.geoId))" } else { "$($s.locale[$f])" }
        if ($pc) {
            $v = if ($f -eq 'homeLocation') { [pscustomobject]@{ geoId = $pc.geoId; isoCode = "$($pc.isoCode)" } } else { $pc.$f }
            $has = if ($f -eq 'homeLocation') { $null -ne $pc.geoId -and $pc.isoCode } else { $null -ne $v }
            $bad = if ($has) { Get-KitLocaleProblem $f $v } else { 'not found' }
            if ($f -eq 'homeLocation' -and -not $bad -and "$($pc.geoId)" -notmatch '^\d{1,9}$') { $bad = "GeoId '$($pc.geoId)' is not a number" }
            if (-not $bad) {
                if ($f -eq 'homeLocation') { $s.locale.homeLocation = [ordered]@{ geoId = [int]$pc.geoId; isoCode = "$($pc.isoCode)" } } else { $s.locale[$f] = $v }
                $sources[$f] = 'this PC'
                continue
            }
            $notes.Add("This PC's $($labels[$f]) can't be used ($bad): the kit's default $shown is used. Set locale.$f in config\settings.local.json for another.")
            continue
        }
        $defaultUsed.Add("$($labels[$f]) $shown")
    }
    if ($defaultUsed.Count) {
        $notes.Add("Not in your settings, and not read from this PC (Run-Build.cmd does that; Build-Iso.ps1 was started directly): the kit's default is used for $($defaultUsed -join ', '). Set them under locale in config\settings.local.json.")
    }

    # --- The effective values, checked -------------------------------------------------
    $loc = $s.locale
    foreach ($f in 'uiLanguage', 'inputLocale', 'systemLocale', 'userLocale', 'timeZone', 'homeLocation') {
        $bad = Get-KitLocaleProblem $f $loc[$f]
        if ($bad) { $problems.Add("locale.${f}: $bad") }
    }
    # Windows' display language: English only for now. The answer file adds the accounts to the
    # groups by their English names (Administrators, Users), and no other language has had a VM test.
    if (-not (Get-KitLocaleProblem 'uiLanguage' $loc.uiLanguage) -and $loc.uiLanguage -cnotin 'en-US', 'en-GB') {
        $problems.Add("locale.uiLanguage '$($loc.uiLanguage)': the kit builds English Windows only (en-US or en-GB) for now: its answer file names the account groups in English, and no other display language has been tested. Use the English Windows 11 ISO; your keyboard, formats, time zone and country can stay yours (docs\reference\CONFIGURATION.md, 'Another language').")
    }
    $acc = $s.accounts
    $taken = New-Object System.Collections.Generic.List[string]
    foreach ($a in 'admin', 'user', 'builtinAdministratorName', 'builtinGuestName') {
        if ($null -eq $acc[$a]) { continue }   # the two built-in names: null = a new name per build
        $bad = Get-KitAccountNameProblem "$($acc[$a])" $taken.ToArray()
        if ($bad) { $problems.Add("accounts.${a}: $bad") }
        $taken.Add("$($acc[$a])")
    }
    if ($null -ne $s.computerName) {
        if ($s.computerName -notmatch '^[A-Za-z0-9-]{1,15}$' -or $s.computerName -match '^\d+$') { $problems.Add("computerName '$($s.computerName)': 1-15 letters, digits or hyphens, not all digits (or null)") }
        elseif ($taken -contains $s.computerName) { $problems.Add("computerName '$($s.computerName)' is also an account name: Windows does not allow that") }
    }
    # reminders.expectedApps: { "name": ..., "wingetId": ... (optional), "path": ... (optional) }
    $i = 0
    foreach ($app in @($s.reminders.expectedApps)) {
        $i++
        $n = "reminders.expectedApps[$i]"
        if ($app -isnot [pscustomobject]) { $problems.Add("$n must be an object: { `"name`": `"...`", `"wingetId`": `"...`" }"); continue }
        foreach ($p in $app.PSObject.Properties) { if ($p.Name -notin 'name', 'wingetId', 'path') { $problems.Add("$n has an unknown field '$($p.Name)' (name, wingetId, path)") } }
        if ($app.name -isnot [string] -or $app.name -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._+&()-]{0,59}$') { $problems.Add("$n.name must be 1-60 letters, digits, spaces or . _ + & ( ) -") }
        if ($null -ne $app.wingetId -and ($app.wingetId -isnot [string] -or $app.wingetId -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$')) { $problems.Add("$n.wingetId '$($app.wingetId)' is not a winget package id (like Publisher.Product)") }
        if ($null -ne $app.path -and ($app.path -isnot [string] -or -not $app.path.Trim() -or $app.path -match '["<>|*?\x00-\x1F]')) { $problems.Add("$n.path must be the full path of the app's program file (environment variables like %ProgramFiles% are allowed)") }
    }

    # options.asrExclusions: full paths; '>' separates them in the policy value
    $i = 0
    foreach ($x in @($s.options.asrExclusions)) {
        $i++
        if ($x -isnot [string] -or (Get-KitAsrExclusionProblem $x)) { $problems.Add("options.asrExclusions[$i] '$x': $(if ($x -is [string]) { Get-KitAsrExclusionProblem $x } else { 'must be text' })") }
    }

    [pscustomobject]@{
        Settings      = $s
        Problems      = $problems.ToArray()
        Notes         = $notes.ToArray()
        Files         = $defaultsPath + $(if ($overlayPath) { " + $overlayPath" })
        DefaultsPath  = $defaultsPath
        OverlayPath   = $overlayPath
        OverlayLabel  = $overlayLabel
        FromFile      = $state.FromFile.ToArray()
        Sources       = $sources
        ThisPcAccount = $pcAccount
    }
}

# --- What the settings change in the staged files ---------------------------------------

# The four Xbox services the Microsoft baseline disables; the kit's override sets them
# back to Manual only with options.gamingTweaks.
function Get-KitXboxServices { , @('XboxGipSvc', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc') }

# config\baseline-overrides.inf as this build stages it (the copy Apply-Policy.ps1 applies
# and reads back, and the validator reads): the new names of the built-in Administrator
# and Guest accounts added at the end of [System Access]; without -GamingTweaks the Xbox
# service lines left out (the baseline's value, Disabled, then stands); with it, Secondary
# Logon set to Manual instead of Disabled (some game launchers need it).
# Comment lines are dropped. Returns the text (CRLF line ends).
function ConvertTo-StagedOverridesInf([string]$Text, [string]$AdministratorName, [string]$GuestName, [bool]$GamingTweaks) {
    $xbox = Get-KitXboxServices
    $names = @("NewAdministratorName = `"$AdministratorName`"", "NewGuestName = `"$GuestName`"")
    $out = New-Object System.Collections.Generic.List[string]
    $section = $null; $added = $false
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if (-not $line -or $line.TrimStart().StartsWith(';')) { continue }
        if ($line -match '^\[(.+)\]$') {
            if ($section -eq 'System Access' -and -not $added) { foreach ($n in $names) { $out.Add($n) }; $added = $true }
            $section = $Matches[1]
            $out.Add($line)
            continue
        }
        if ($section -eq 'System Access' -and $line -match '^\s*New(Administrator|Guest)Name\s*=') { continue }
        if ($section -eq 'Service General Setting' -and -not $GamingTweaks -and $xbox -contains ($line -split ',', 2)[0].Trim().Trim('"')) { continue }
        if ($section -eq 'Service General Setting' -and $GamingTweaks -and ($line -split ',', 2)[0].Trim().Trim('"') -eq 'seclogon') { $out.Add('"seclogon",3,""'); continue }
        $out.Add($line)
    }
    if ($section -eq 'System Access' -and -not $added) { foreach ($n in $names) { $out.Add($n) }; $added = $true }
    if (-not $added) { throw 'config\baseline-overrides.inf has no [System Access] section for the built-in accounts'' new names' }
    ($out.ToArray() -join "`r`n") + "`r`n"
}

# The apps of config\image.json that must be in the image: 'requiredApps', without the
# 'gamingApps' among them unless options.gamingTweaks is on.
function Get-KitRequiredApps($ImageCfg, [bool]$GamingTweaks) {
    $gaming = @($ImageCfg.gamingApps | Where-Object { $_ })
    , @($ImageCfg.requiredApps | Where-Object { $_ -and ($GamingTweaks -or $gaming -notcontains $_) })
}

# config\LayoutModification.json as staged: unchanged with -GamingTweaks; otherwise without
# the Start pins of the image's gaming apps (image.json 'gamingApps').
function ConvertTo-StagedStartLayout([string]$Json, [bool]$GamingTweaks, [string[]]$GamingApps) {
    if ($GamingTweaks) { return $Json }
    $layout = $Json | ConvertFrom-Json
    $kept = @(foreach ($pin in @($layout.pinnedList)) {
        $id = "$($pin.packagedAppId)"
        if ($id -and @($GamingApps | Where-Object { $_ -and $id.StartsWith("${_}_", [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
        $pin
    })
    $text = [ordered]@{ pinnedList = $kept } | ConvertTo-Json -Depth 5
    $null = $text | ConvertFrom-Json   # must parse
    $text + "`r`n"
}
