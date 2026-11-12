<#
.SYNOPSIS
    First-logon configuration of a W11Kit install. Runs once from
    autounattend FirstLogonCommands while the administrator account is
    signed in automatically (elevated). Safe to re-run manually from an
    elevated PowerShell:
      powershell -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\PostInstall.ps1

    1. Microsoft Windows 11 v26H2 and Edge security baselines (data in
       Baselines\, imported from Microsoft's zips), the documented overrides
       and this kit's policies, merged into local Group Policy with built-in
       tools only (Apply-Policy.ps1; docs/reference/SECURITY-BASELINE.md), with ONE
       merged advanced audit policy (the baseline's rows + the DISA STIG
       subcategories; Merge-AuditPolicy.ps1). If an override shows the
       baseline's value afterwards, the automatic restart is cancelled:
       restarting with the bare baseline would UEFI-lock HVCI/LSA and
       auto-deny the standard user's elevation.
    2. Machine registry settings (Set-KitRegistry.ps1 -Mode Online; the home
       location and the options in settings.json, docs/reference/CONFIGURATION.md);
       administrator accounts can't run web browsers (AppLocker,
       New-AdminBrowserPolicy.ps1; DISA STIG); a firewall rule in local Group
       Policy that blocks outbound SMB (TCP 445) to Internet addresses; the
       PowerShell operational log raised to 256 MB; Windows' built-in Sysmon
       enabled with the kit's configuration (Sysmon-Config.xml)
    3. Password expiry off (current Microsoft guidance; complexity stays)
    4. Power: Balanced plan, display off after 15 min. From the hardware profile (profile.json,
       docs/reference/PROFILES.md): power.mode 'hibernate' = hibernate after 30 min idle
       (no sleep), full hibernation file, power button hibernates; 'default' = sleep and
       hibernate left as Windows and the firmware set them. power.wakeOnLan
       = Wake-on-LAN (magic packet) on that adapter from hibernate and shutdown;
       Wi-Fi Direct virtual adapters disabled (DISA STIG)
    5. System Restore on C: + a "clean install" restore point
    6. Windows Time on, Defender signatures, WSL update, Windows Update scan
    7. Public-desktop shortcuts; W11Kit folder locked to administrators
    8. Pre-restart validation snapshot; status file; restart in 2 minutes

    If the overrides fail (critical): no restart. The console says so in red with the
    exact command to run again, a text file on the Public desktop explains it (for
    whoever comes back to the PC later), and the window waits for Enter, at most 15
    minutes. The wait is timed, not open-ended: the answer file's later first-logon
    commands (forced password changes, deleting the cached answer files that hold the
    passwords) run only after this script ends, and a VM test must not hang; the VM
    test reads postinstall-status.json, written before the wait.
#>
[CmdletBinding()]
param(
    [switch]$NoRestart
)

$ErrorActionPreference = 'Continue'
$root = 'C:\ProgramData\W11Kit'
$logDir = Join-Path $root 'Logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$transcriptPath = Join-Path $logDir "postinstall-$(Get-Date -Format yyyyMMdd-HHmmss).txt"
Start-Transcript -Path $transcriptPath | Out-Null
# Left on the Public desktop when the overrides fail (critical); removed by a clean run
$criticalNote = Join-Path $env:PUBLIC 'Desktop\W11Kit setup NOT finished - read me.txt'
$rerunCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $root\PostInstall.ps1"

$failures = New-Object System.Collections.Generic.List[string]
$critical = $false

function Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }
function Fail([string]$What, $Err) {
    $msg = "$What : $Err"
    Write-Warning $msg
    $script:failures.Add($msg)
}
# Runs a native tool and records a (non-critical) failure when its exit code isn't 0.
# Output goes to the console/transcript as before.
function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "$Exe $($Arguments -join ' ')" "exit code $LASTEXITCODE" }
}
# Waits for Enter, at most $Minutes (see .SYNOPSIS: the first-logon commands after this
# script, and a VM test, must not wait forever). No console to read: returns at once.
function Wait-ForEnter([int]$Minutes) {
    try { if ([Console]::IsInputRedirected) { return }; $null = [Console]::KeyAvailable } catch { return }
    Write-Host "Press Enter to close this window (it closes by itself after $Minutes minutes)." -ForegroundColor Yellow
    $until = (Get-Date).AddMinutes($Minutes)
    while ((Get-Date) -lt $until) {
        try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { return } } catch { return }
        Start-Sleep -Milliseconds 250
    }
}
function Invoke-Payload([string]$Name, [hashtable]$Params = @{}) {
    $sb = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $root $Name)))
    & $sb @Params
}
# Runs a step in a child PowerShell with a time limit. A step can hang (System Restore
# has, for 30+ minutes on real hardware), and then PostInstall would never reach its end:
# no status file, no restart, the admin left signed in. A step that overruns is killed
# and recorded as a failure; the script carries on.
function Invoke-Bounded([string]$What, [string]$Script, [int]$Minutes) {
    $out = Join-Path $logDir ("step-{0}.txt" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $wrapped = "`$ErrorActionPreference = 'Stop'`n`$ProgressPreference = 'SilentlyContinue'`ntry {`n$Script`nexit 0`n} catch { Write-Output ('ERROR: ' + `$_); exit 1 }"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapped))
    $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $enc -NoNewWindow -RedirectStandardOutput $out -PassThru
    $null = $p.Handle   # keeps ExitCode readable after the wait
    $done = $p.WaitForExit($Minutes * 60000)
    if (-not $done) { try { $p.Kill(); $p.WaitForExit(10000) | Out-Null } catch { } }
    Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() } | ForEach-Object { Write-Host "    $_" }
    Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
    if (-not $done) { throw "$What did not finish within $Minutes minutes; skipped" }
    if ($p.ExitCode -ne 0) { throw "$What failed (exit code $($p.ExitCode))" }
}

# Choices made at build time (account names, computer name, kit revision)
$opts = $null
try { $opts = Get-Content -Raw (Join-Path $root 'build-options.json') | ConvertFrom-Json } catch { }
$adminName = if ($opts -and $opts.AdminName) { $opts.AdminName } else { 'your admin account' }
$userName = if ($opts -and $opts.UserName) { $opts.UserName } else { 'your daily account' }
$kitRevision = if ($opts -and $opts.KitRevision) { $opts.KitRevision } else { 'unknown' }

# Hardware profile chosen at build time (docs/reference/PROFILES.md). Not readable: recorded as
# a failure, and the hardware-specific steps fall back to doing nothing (power mode
# 'default', no Wake-on-LAN). ($hw, not $profile: that is PowerShell's own variable.)
$hw = $null
try {
    $hw = Get-Content -Raw -LiteralPath (Join-Path $root 'profile.json') -ErrorAction Stop | ConvertFrom-Json
    if (-not ($hw -and $hw.id -and $hw.power)) { throw 'no id or power section' }
} catch {
    $hw = $null
    Fail 'Hardware profile (profile.json) not readable; power left as Windows set it, no Wake-on-LAN' $_
}
$hwName = if ($hw -and $hw.displayName) { "$($hw.displayName)" } elseif ($hw) { "$($hw.id)" } else { 'unknown hardware profile' }
$powerMode = if ($hw) { "$($hw.power.mode)" } else { 'default' }
if ($powerMode -notin 'hibernate', 'default') {
    Fail 'Hardware profile' "power.mode '$powerMode' is not 'hibernate' or 'default'; using 'default'"
    $powerMode = 'default'
}
$wol = if ($hw -and $hw.power.wakeOnLan -and $hw.power.wakeOnLan.adapter) { $hw.power.wakeOnLan } else { $null }

# The settings as built (settings.json: the kit's defaults with the user's file over them,
# complete; docs/reference/CONFIGURATION.md): Set-KitRegistry takes the home location and
# the options (gaming, Smart App Control, Brave, long paths, Microsoft account) from it.
# Not readable: recorded as a failure, and Set-KitRegistry then sets none of the optional
# values and no home location (it declares no defaults of its own).
$kitSettings = $null
try {
    $kitSettings = Get-Content -Raw -LiteralPath (Join-Path $root 'settings.json') -ErrorAction Stop | ConvertFrom-Json
    if ($kitSettings -isnot [pscustomobject]) { throw 'not a JSON object' }
} catch {
    $kitSettings = $null
    Fail 'Settings (settings.json) not readable; the optional values (gaming, Smart App Control, Brave, long paths) and the home location are not set' $_
}
Write-Host "W11Kit first-boot setup for $hwName (profile $(if ($hw) { $hw.id } else { 'none' })), kit revision: $kitRevision" -ForegroundColor Cyan

try {
    # --- 1. Security baseline + overrides + kit policies -------------------
    # Apply-Policy.ps1: the baselines (data in Baselines\, imported from Microsoft's
    # zips), the overrides and the kit's policies merged into local Group Policy
    # (Registry.pol, gpt.ini, secedit, ONE merged audit policy), gpupdate, then the
    # overrides read back. An override that shows the BASELINE's value instead makes the
    # result critical: restarting then would UEFI-lock HVCI/LSA and auto-deny the
    # standard user's elevation, so the restart is cancelled.
    Step 'Microsoft security baselines (Windows 11 v26H2, Edge v151) + overrides + kit policies (local Group Policy)'
    try {
        $ap = Invoke-Payload 'Apply-Policy.ps1' @{ LogDir = $logDir; PowerMode = $powerMode; Settings = $kitSettings }
        foreach ($f in @($ap.Failures)) { Fail 'Security baseline' $f }
        if ($ap.Critical) { $critical = $true }
        Write-Host "Baselines, overrides and kit policies applied ($($ap.Summary)). Full effect after the restart."
    } catch { Fail 'Security baseline' $_ }

    # --- 2. Machine registry -------------------------------------------------
    Step 'Registry customizations (machine + this account + Default profile)'
    try { Invoke-Payload 'Set-KitRegistry.ps1' @{ Mode = 'Online'; PowerMode = $powerMode; Settings = $kitSettings } } catch { Fail 'Registry' $_ }

    # --- 2a. Administrator accounts: no web browsers (DISA STIG V-253294, CAT I) ----
    # AppLocker (enforced on every edition since Windows 10 2004 + KB5024351), deny-list
    # mode; Exe rules plus an "all signed packaged apps" Appx rule (Exe rules alone would
    # deny every packaged app to every user): everyone may run everything except msedge/brave/chrome/
    # firefox.exe for the Administrators group (elevated tokens) and the admin account
    # itself (also non-elevated). WebView2, installers, PowerShell, DISM, git, python and
    # oscdimg are untouched (docs/reference/SECURITY-BASELINE.md, DISA STIG additions).
    Step 'Administrator accounts: no web browsers (AppLocker)'
    try {
        $adminSid = $null
        if ($opts -and $opts.AdminName) { $adminSid = (Get-LocalUser -Name $opts.AdminName -ErrorAction Stop).SID.Value }
        else { Fail 'Browser block for administrators' 'build-options.json names no admin account: only elevated admin tokens are covered' }
        $alXml = Join-Path $logDir 'w11kit-applocker.xml'
        [IO.File]::WriteAllText($alXml, (Invoke-Payload 'New-AdminBrowserPolicy.ps1' @{ AdminSid = $adminSid }), (New-Object Text.UTF8Encoding $false))
        Set-AppLockerPolicy -XmlPolicy $alXml -ErrorAction Stop
        # Set in local Group Policy; if it isn't effective yet (the validator reads the effective policy), refresh
        if ("$(Get-AppLockerPolicy -Effective -Xml -ErrorAction SilentlyContinue)" -notmatch 'W11Kit: no ') {
            & gpupdate.exe /target:computer /force /wait:120 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail 'gpupdate /target:computer (AppLocker)' "exit code $LASTEXITCODE" }
        }
        if ("$(Get-AppLockerPolicy -Effective -Xml -ErrorAction SilentlyContinue)" -notmatch 'W11Kit: no ') { throw 'policy set, but not in the effective AppLocker policy' }
        # Enforcement needs the Application Identity service. It is a protected service:
        # elevated sc.exe can set its start type (Set-Service and services.msc can't).
        & sc.exe config AppIDSvc start= auto | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'sc.exe config AppIDSvc start= auto' "exit code $LASTEXITCODE" }
        Start-Service AppIDSvc -ErrorAction Stop
        Write-Host "  AppLocker executable rules enforced; browsers denied to Administrators$(if ($adminSid) { " and $($opts.AdminName)" }); AppIDSvc $((Get-Service AppIDSvc).Status)"
    } catch { Fail 'Browser block for administrators (AppLocker)' $_ }

    # --- 2b. Computer name -------------------------------------------------------
    # Windows 11 26H2 Setup can ignore the answer file's specialize ComputerName
    # (the PC then has a random WIN-xxxxxxxx name). Rename here if needed; it
    # takes effect at this script's restart.
    if ($opts -and $opts.ComputerName -and $env:COMPUTERNAME -ne $opts.ComputerName) {
        Step "Computer name: $env:COMPUTERNAME -> $($opts.ComputerName)"
        try { Rename-Computer -NewName $opts.ComputerName -Force -ErrorAction Stop -WarningAction SilentlyContinue }
        catch { Fail 'Rename-Computer' $_ }
    }

    # --- 2c. Firewall: no SMB to the Internet ------------------------------------
    # A link or document that points at \\<internet host>\share makes Windows offer the
    # signed-in user's NTLM credentials to that host. Outbound TCP 445 to public
    # addresses is blocked; private ranges are not listed, so a NAS or another PC on the
    # LAN works as before. The rule is a kit policy value (Set-KitRegistry.ps1:
    # ...\WindowsFirewall\FirewallRules, so it is in local Group Policy, where the Public
    # profile's "apply local firewall rules: No" doesn't ignore it); step 1 applied it.
    # Not New-NetFirewallRule -PolicyStore localhost: that reaches the local GPO over a
    # network path to this PC and fails with "The specified network name is no longer
    # available" (this image disables the Server service). Here: is the firewall enforcing it?
    Step 'Firewall: outbound SMB (TCP 445) to Internet addresses blocked'
    try {
        $fwName = 'W11Kit-Block-SMB-Out-Internet'
        $fw = Get-NetFirewallRule -PolicyStore ActiveStore -Name $fwName -ErrorAction SilentlyContinue
        if (-not $fw) {
            & gpupdate.exe /target:computer /force /wait:120 | Out-Null
            $fw = Get-NetFirewallRule -PolicyStore ActiveStore -Name $fwName -ErrorAction SilentlyContinue
        }
        if (-not $fw) { throw "the firewall has not loaded the policy rule $fwName (HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules)" }
        if ("$($fw.Enabled)" -ne 'True' -or "$($fw.Action)" -ne 'Block' -or "$($fw.Direction)" -ne 'Outbound') {
            throw "rule read back as Enabled=$($fw.Enabled) Action=$($fw.Action) Direction=$($fw.Direction)"
        }
        $fwAddr = @(try { ($fw | Get-NetFirewallAddressFilter -ErrorAction Stop).RemoteAddress } catch { })
        Write-Host "  $fwName active: Block, Outbound, TCP 445, $(if ($fwAddr.Count) { "$($fwAddr.Count) public address ranges" } else { 'address ranges not read back' })"
    } catch { Fail 'Firewall rule (outbound SMB to the Internet)' $_ }

    # --- 2d. PowerShell operational log: 256 MB ------------------------------------
    # Script block logging (kit policy) writes every script PowerShell runs to this log;
    # at Windows' 15 MB one build pushes a week of history out. Costs disk space only.
    Step 'PowerShell operational event log: 256 MB'
    try {
        $psLog = 'Microsoft-Windows-PowerShell/Operational'; $psLogBytes = 256MB
        & wevtutil.exe sl $psLog "/ms:$psLogBytes" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "wevtutil sl $psLog /ms:$psLogBytes : exit code $LASTEXITCODE" }
        $psLogNow = (Get-WinEvent -ListLog $psLog -ErrorAction Stop).MaximumSizeInBytes
        if ($psLogNow -ne $psLogBytes) { throw "maximum size reads back as $psLogNow bytes, want $psLogBytes" }
        Write-Host "  $psLog : $($psLogNow / 1MB) MB"
    } catch { Fail 'PowerShell event log size' $_ }

    # --- 2e. Sysmon (built into Windows 11) ------------------------------------------
    # Microsoft's System Monitor ships in Windows as an optional feature, off by default
    # (KB5077241): "Dism /Online /Enable-Feature /FeatureName:Sysmon", then "sysmon -i".
    # The kit's own configuration (Sysmon-Config.xml) records process starts with their
    # SHA-256, non-Windows driver loads, network connections of script hosts and of
    # programs in temp/download folders, changed file creation times, process tampering
    # and WMI persistence, into Microsoft-Windows-Sysmon/Operational (256 MB).
    # Tolerant: an image without the feature, or anything else going wrong, is a recorded
    # (non-critical) failure and the PC is otherwise complete. If Windows wants a restart
    # before sysmon.exe is usable, a one-time startup task finishes the job after this
    # script's restart and deletes itself.
    Step 'Sysmon (built into Windows): enable and configure'
    try {
        $smCfg = Join-Path $root 'Sysmon-Config.xml'
        $smLog = 'Microsoft-Windows-Sysmon/Operational'; $smLogBytes = 256MB
        if (-not (Test-Path -LiteralPath $smCfg)) { throw "$smCfg is missing from the payload" }
        # -FeatureName takes ONE name; an unknown name is an error (or nothing)
        $smFeat = $null
        try { $smFeat = Get-WindowsOptionalFeature -Online -FeatureName Sysmon -ErrorAction Stop } catch { }
        if (-not $smFeat) { throw 'this Windows image has no optional feature named Sysmon (it arrived with the 2026 updates): not installed' }
        if ("$($smFeat.State)" -notmatch '^Enable') {
            Invoke-Bounded 'Enabling the Sysmon feature' @'
$ErrorActionPreference = 'Continue'
& dism.exe /Online /Enable-Feature /FeatureName:Sysmon /NoRestart /Quiet | Out-Null
if ($LASTEXITCODE -notin 0, 3010) { throw "dism /Online /Enable-Feature /FeatureName:Sysmon : exit code $LASTEXITCODE" }
"Sysmon feature enabled (dism exit code $LASTEXITCODE; 3010 = restart needed)."
'@ 10
            $smFeat = Get-WindowsOptionalFeature -Online -FeatureName Sysmon -ErrorAction Stop
        }
        $smExe = @((Join-Path $env:SystemRoot 'System32\Sysmon.exe'), (Join-Path $env:SystemRoot 'Sysmon.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $smExe) { $smExe = (Get-Command sysmon.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
        $smDone = $false
        if ($smExe -and "$($smFeat.State)" -eq 'Enabled') {
            # First run: -i installs the service and driver with the configuration (no restart
            # needed). A re-run: -i says it is installed already, and -c loads the configuration.
            # Then the running service must report its configuration (sysmon -c). In a child
            # PowerShell with a time limit, so a prompt or a hang can't stop PostInstall.
            $env:W11KIT_SYSMON_EXE = $smExe; $env:W11KIT_SYSMON_CFG = $smCfg
            try {
                Invoke-Bounded 'Sysmon install (sysmon -i / -c)' @'
$ErrorActionPreference = 'Continue'
$exe = $env:W11KIT_SYSMON_EXE; $cfg = $env:W11KIT_SYSMON_CFG
function Run { $o = & $exe @args 2>&1 | ForEach-Object { ("$_" -replace "`0", '').Trim() } | Where-Object { $_ }; $t = @($o) -join ' '; if ($t.Length -gt 300) { $t = $t.Substring(0, 300) + ' ...' }; [pscustomobject]@{ Code = $LASTEXITCODE; Out = $t } }
$i = Run -accepteula -nologo -i $cfg
if ($i.Code -ne 0) {
    $c = Run -nologo -c $cfg
    if ($c.Code -ne 0) { throw "sysmon -i: exit code $($i.Code) ($($i.Out)); sysmon -c: exit code $($c.Code) ($($c.Out))" }
}
$s = Run -nologo -c
if ($s.Code -ne 0) { throw "installed, but 'sysmon -c' (show the running configuration) fails: exit code $($s.Code) ($($s.Out))" }
'Sysmon installed; the running service reports its configuration.'
'@ 5
            } finally { Remove-Item Env:\W11KIT_SYSMON_EXE, Env:\W11KIT_SYSMON_CFG -ErrorAction SilentlyContinue }
            & wevtutil.exe sl $smLog "/ms:$smLogBytes" | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "wevtutil sl $smLog /ms:$smLogBytes : exit code $LASTEXITCODE" }
            $smSvc = @(Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1)
            Write-Host "  Sysmon running with $smCfg; service $(if ($smSvc.Count) { "$($smSvc[0].Name) $($smSvc[0].Status)" } else { 'name not found' }); log $smLog $((Get-WinEvent -ListLog $smLog -ErrorAction Stop).MaximumSizeInBytes / 1MB) MB"
            $smDone = $true
        }
        if (-not $smDone) {
            # Feature state "$($smFeat.State)" (restart pending) or sysmon.exe not there yet:
            # finish at the next start, as SYSTEM, once.
            $smTask = 'W11Kit Sysmon setup'
            $smCmd = "`$ErrorActionPreference = 'Continue'; & sysmon.exe -accepteula -nologo -i '$smCfg' *> '$logDir\sysmon-setup.txt'; & wevtutil.exe sl $smLog /ms:$smLogBytes; Unregister-ScheduledTask -TaskName '$smTask' -Confirm:`$false"
            $smEnc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($smCmd))
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -EncodedCommand $smEnc"
            $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $smTask -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $prn -Force -ErrorAction Stop | Out-Null
            Write-Host "  Sysmon feature state $($smFeat.State), sysmon.exe $(if ($smExe) { $smExe } else { 'not present yet' }): the one-time startup task '$smTask' installs it after the restart (log: $logDir\sysmon-setup.txt)"
        }
    } catch { Fail 'Sysmon' $_ }

    # --- 3. Password expiry --------------------------------------------------
    Step 'Password expiry off (length/complexity/lockout from the baseline stay)'
    & net.exe accounts /maxpwage:unlimited | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'net accounts /maxpwage' $LASTEXITCODE }

    # --- 4. Power ------------------------------------------------------------
    # Every profile: the plan (Balanced, or Ultimate Performance on request) and the
    # display-off timeout. power.mode 'hibernate' only: hibernation file, no sleep,
    # hibernate on idle and on the power/sleep buttons, no hybrid sleep, important
    # wake timers only. 'default' leaves those as Windows and the firmware set them.
    Step $(if ($powerMode -eq 'hibernate') { 'Power: hibernate (no sleep), Fast Startup off' } else { 'Power: plan and display timeout (sleep left as Windows sets it)' })
    try {
        if ($powerMode -eq 'hibernate') {
            # Full hibernation file (the reduced type only serves Fast Startup).
            Invoke-Checked powercfg.exe '/hibernate', 'on'
            Invoke-Checked powercfg.exe '/hibernate', '/type', 'full'
        }
        # The Balanced plan: hibernate after 30 minutes idle, display off after 15.
        # settings options.idleHibernate false: the PC never hibernates or sleeps by itself
        $idleOff = $kitSettings -and $kitSettings.options.idleHibernate -eq $false
        if ($idleOff) {
            foreach ($m in '/setacvalueindex', '/setdcvalueindex') {
                Invoke-Checked powercfg.exe $m, '381b4222-f694-41f0-9685-ff5bb260df2e', 'SUB_SLEEP', 'STANDBYIDLE', '0'
                Invoke-Checked powercfg.exe $m, '381b4222-f694-41f0-9685-ff5bb260df2e', 'SUB_SLEEP', 'HIBERNATEIDLE', '0'
            }
        }
        $g = '381b4222-f694-41f0-9685-ff5bb260df2e'
        foreach ($mode in '/setacvalueindex', '/setdcvalueindex') {
            if ($powerMode -eq 'hibernate') {
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_SLEEP', 'STANDBYIDLE', '0'      # never sleep (the baseline disallows S1-S3 anyway)
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_SLEEP', 'HIBERNATEIDLE', $(if ($idleOff) { '0' } else { '1800' })
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_SLEEP', 'HYBRIDSLEEP', '0'
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_SLEEP', 'RTCWAKE', '2'   # important wake timers only (fewer spurious wakes)
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_BUTTONS', 'PBUTTONACTION', '2'   # 2 = hibernate
                Invoke-Checked powercfg.exe $mode, $g, 'SUB_BUTTONS', 'SBUTTONACTION', '2'
            }
            Invoke-Checked powercfg.exe $mode, $g, 'SUB_VIDEO', 'VIDEOIDLE', '900'
        }
        Invoke-Checked powercfg.exe '/setactive', $g
        & powercfg.exe /getactivescheme
        & powercfg.exe /a
    } catch { Fail 'Power' $_ }

    # --- 4b. Wake-on-LAN ---------------------------------------------------------
    # Only with power.wakeOnLan in the profile. Magic packet only (no pattern/link-change
    # wakes), from hibernate (S4) and, where the driver offers it, from shutdown (S5;
    # the profile's advanced properties). The BIOS must have Wake on LAN on and
    # ErP/deep power saving off (docs/reference/CONFIGURATION.md, "Power: hibernate and Wake-on-LAN").
    if ($wol) {
        $wolLabel = if ($wol.label) { "$($wol.label)" } else { "$($wol.adapter)" }
        Step "Wake-on-LAN: $wolLabel, magic packet"
        try {
            $nic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -match $wol.adapter | Select-Object -First 1
            if (-not $nic) {
                Write-Warning "No $wolLabel adapter (expected in a VM): Wake-on-LAN not configured."
            } else {
                $adv = @(Get-NetAdapterAdvancedProperty -Name $nic.Name -AllProperties -ErrorAction SilentlyContinue)
                if ($wol.advanced) {
                    foreach ($p in $wol.advanced.PSObject.Properties) {
                        if ($adv | Where-Object RegistryKeyword -eq $p.Name) {
                            Set-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword $p.Name -RegistryValue "$($p.Value)" -NoRestart -ErrorAction Stop
                        }
                    }
                }
                Set-NetAdapterPowerManagement -Name $nic.Name -WakeOnMagicPacket Enabled -WakeOnPattern Disabled -NoRestart -ErrorAction Stop
                & powercfg.exe /deviceenablewake $nic.InterfaceDescription
                if ($LASTEXITCODE -ne 0) { Fail 'powercfg /deviceenablewake' $LASTEXITCODE }
                Write-Host "  $($nic.InterfaceDescription) ($($nic.MacAddress)): magic packet wake on"
            }
        } catch { Fail 'Wake-on-LAN' $_ }
    }

    # --- 4b2. Wi-Fi Direct virtual adapters (DISA STIG V-288475) -----------------
    # Costs Mobile hotspot, Miracast casting and Wi-Fi Direct printers; ordinary Wi-Fi
    # is unaffected. A Wi-Fi driver update may re-create the adapter: the validator WARNs.
    Step 'Wi-Fi Direct virtual adapters off'
    try {
        $wfd = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -like 'Microsoft Wi-Fi Direct Virtual Adapter*')
        if (-not $wfd.Count) { Write-Host '  none on this PC (no Wi-Fi hardware, e.g. a VM)' }
        foreach ($a in $wfd) {
            if ("$($a.Status)" -ne 'Disabled') { $a | Disable-NetAdapter -Confirm:$false -ErrorAction Stop }
            Write-Host "  $($a.InterfaceDescription): disabled"
        }
    } catch { Fail 'Wi-Fi Direct adapters' $_ }

    # --- 4c. Secure Boot certificates (2023) ---------------------------------
    # Microsoft's 2011 Secure Boot certificates expire in 2026. If the firmware
    # doesn't have the 2023 ones yet, queue Microsoft's own servicing task to add
    # the 2023 DB/KEK certificates and the 2023-signed boot manager (0x5944,
    # KB5062713). No revocations: old 2011-signed media keeps booting.
    Step 'Secure Boot: 2023 certificates'
    try {
        $sbStatus = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue).UEFICA2023Status
        # Check the firmware's lists themselves: UEFICA2023Status=Updated alone doesn't prove the 2023 KEK.
        $sbDb = try { [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).Bytes) } catch { '' }
        $sbKek = try { [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI KEK).Bytes) } catch { '' }
        if (-not (Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
            Write-Warning 'Secure Boot is off: certificate update skipped.'
        } elseif ($sbDb -match 'Windows UEFI CA 2023' -and $sbKek -match 'KEK 2K CA 2023') {
            Write-Host "  DB and KEK already hold the 2023 certificates (UEFICA2023Status=$sbStatus): nothing to do"
        } else {
            Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot' -Name AvailableUpdates -Value 0x5944 -Type DWord
            Start-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update'
            Write-Host "  UEFICA2023Status=${sbStatus}: queued the 2023 certificate + boot manager update (finishes over the next restarts)"
        }
    } catch { Fail 'Secure Boot certificates' $_ }

    # --- 5. System Restore ---------------------------------------------------
    Step 'System Restore'
    try {
        # Bypasses the 24-hour restore point frequency limit for this one checkpoint
        Invoke-Bounded 'System Restore' @'
Enable-ComputerRestore -Drive "$env:SystemDrive\"
& vssadmin.exe resize shadowstorage /for=$env:SystemDrive /on=$env:SystemDrive /maxsize=5% | Out-Null
$sr = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
Set-ItemProperty $sr -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
try { Checkpoint-Computer -Description 'W11Kit clean install' -RestorePointType MODIFY_SETTINGS }
finally { Remove-ItemProperty $sr -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
'System Restore on; restore point created.'
'@ 10
    } catch { Fail 'System Restore' $_ }

    # --- 6. Updates (need the network cable plugged in) -----------------------
    Step 'Windows Time'
    # Was left Manual and stopped on the live PC (w32tm failed with 0x80070426).
    try {
        Set-Service W32Time -StartupType Automatic -ErrorAction Stop
        Start-Service W32Time -ErrorAction Stop
        & w32tm.exe /config /update | Out-Null
        & w32tm.exe /resync /force | Out-Null
        Write-Host "  W32Time running (Automatic); resync exit code $LASTEXITCODE"
    } catch { Fail 'Windows Time' $_ }

    Step 'Defender signatures'
    try { Invoke-Bounded 'Defender signatures' "Update-MpSignature; 'Signatures updated.'" 5 } catch { Write-Warning "Update-MpSignature: $_ (Windows Update will retry)" }

    Step 'WSL'
    try {
        # The features the image enables (config/image.json, staged next to this script).
        # Not readable: recorded, and nothing is checked here (the validator FAILs on it too).
        $wantFeatures = @()
        try {
            $image = Get-Content -Raw -LiteralPath (Join-Path $root 'image.json') -ErrorAction Stop | ConvertFrom-Json
            $wantFeatures = @($image.features.enable | Where-Object { $_ })
            if (-not $wantFeatures.Count) { Fail 'WSL features' 'image.json lists no features.enable' }
        } catch { Fail 'WSL features: image.json not readable' $_ }
        # -FeatureName takes ONE name: query each feature separately
        foreach ($f in $wantFeatures) {
            $st = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State
            Write-Host "  $f : $st"
            if ("$st" -notmatch '^Enable') { Fail "WSL feature $f" "state $st" }
        }
    } catch { Fail 'WSL features' $_ }
    try {
        # Native stderr + 'Stop' is a terminating error in PS 5.1: 'Continue' here.
        # wsl.exe writes UTF-16 to pipes unless WSL_UTF8 is set.
        Invoke-Bounded 'wsl --update' @'
$ErrorActionPreference = 'Continue'
$env:WSL_UTF8 = '1'
& wsl.exe --update 2>&1 | ForEach-Object { "$_" }
'@ 10
    } catch { Write-Warning "wsl --update: $_ (run it later once online)" }

    Step 'Windows Update scan'
    try { (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow(); Write-Host 'Scan requested.' } catch { Write-Warning $_ }

    # --- 7. Shortcuts + folder permissions -----------------------------------
    Step 'Shortcuts on the Public desktop'
    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($sc in @(@('Validate PC', 'Validate-Pc.cmd'), @('Enable BitLocker (local key)', 'Enable-BitLocker.cmd'))) {
            $lnk = $wsh.CreateShortcut("$env:PUBLIC\Desktop\$($sc[0]).lnk")
            $lnk.TargetPath = Join-Path $root $sc[1]
            $lnk.WorkingDirectory = $root
            $lnk.Save()
        }
    } catch { Fail 'Shortcuts' $_ }

    # The validator by itself (settings options.scheduledValidation): weekly, and at every start,
    # where Invoke-ScheduledValidation.ps1 runs it only after a Windows build change (an update
    # restart) or when the last report is 6 days old. As SYSTEM; it changes no setting.
    if (-not ($kitSettings -and $kitSettings.options -and $kitSettings.options.scheduledValidation -eq $false)) {
        Step 'Scheduled validation (weekly and after Windows Update restarts)'
        try {
            $svAct = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$root\Invoke-ScheduledValidation.ps1`"" -WorkingDirectory $root
            $svBoot = New-ScheduledTaskTrigger -AtStartup
            $svBoot.Delay = 'PT10M'
            $svTrig = @((New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '12:00'), $svBoot)
            $svPrn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
            $svSet = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
            Register-ScheduledTask -TaskName 'W11Kit Validate PC' -Description 'W11Kit: runs Validate PC weekly and after a Windows Update restart (settings options.scheduledValidation). Changes no setting.' -Action $svAct -Trigger $svTrig -Principal $svPrn -Settings $svSet -Force -ErrorAction Stop | Out-Null
            Write-Host "  Task 'W11Kit Validate PC': Sundays 12:00 (or at the next start), and 10 minutes after each start when Windows' build changed. Log: $logDir\scheduled-validation.txt"
        } catch { Fail 'Scheduled validation' $_ }
    }

    Step 'Locking C:\ProgramData\W11Kit to administrators (its tools run elevated)'
    # SIDs: Administrators full, SYSTEM full, Users read/execute only. Set the
    # FOLDER's ACL (no /T: /T would strip each file's inherited ACEs and leave
    # files readable by nobody), then make everything inside inherit from it.
    try {
        & icacls.exe $root /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls folder ACL failed ($LASTEXITCODE)" }
        & icacls.exe "$root\*" /reset /T /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls /reset failed ($LASTEXITCODE)" }
        # Read-back: the tools in this folder must still be readable.
        foreach ($f in 'Test-InstalledPc.ps1', 'Enable-BitLockerLocal.ps1', 'Apply-Policy.ps1', 'Baselines\baselines.json') {
            $null = Get-Content -LiteralPath (Join-Path $root $f) -TotalCount 1 -ErrorAction Stop
        }
        Write-Host 'Locked: Administrators/SYSTEM full control, standard users read-only; tools still readable.'
    } catch { Fail 'W11Kit folder lockdown' $_ }

    $o = if ($kitSettings) { $kitSettings.options } else { $null }

    # Defender's ransomware protection as preferences, not policy: Run-Build.cmd can then pause
    # them for a build (with the user's consent) and restore them (settings
    # options.controlledFolderAccess, options.asrPrevalenceRule)
    Step 'Defender: Controlled Folder Access and the ASR prevalence rule'
    try {
        $cfaOn = -not ($o -and $o.controlledFolderAccess -eq $false)
        Set-MpPreference -EnableControlledFolderAccess $(if ($cfaOn) { 'Enabled' } else { 'Disabled' }) -ErrorAction Stop
        $prev = if ($o -and $o.asrPrevalenceRule) { "$($o.asrPrevalenceRule)" } else { 'block' }
        $prevId = '01443614-cd74-433a-b99e-2ecdc07bfc25'   # executables need prevalence, age or trusted-list status
        if ($prev -eq 'off') { Remove-MpPreference -AttackSurfaceReductionRules_Ids $prevId -ErrorAction SilentlyContinue }
        else { Add-MpPreference -AttackSurfaceReductionRules_Ids $prevId -AttackSurfaceReductionRules_Actions $(if ($prev -eq 'block') { 'Enabled' } else { 'AuditMode' }) -ErrorAction Stop }
        Write-Host "Controlled Folder Access: $(if ($cfaOn) { 'on' } else { 'off' }); ASR prevalence rule: $prev"
    } catch { Fail 'Defender ransomware protection' $_ }

    # NetBIOS over TCP/IP off on every present adapter (settings options.netbios)
    if ($o -and "$($o.netbios)" -eq 'off') {
        Step 'NetBIOS over TCP/IP off'
        try {
            foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction Stop)) {
                Set-ItemProperty -LiteralPath $k.PSPath -Name NetbiosOptions -Value 2 -Type DWord -ErrorAction Stop
            }
            Write-Host 'NetbiosOptions = 2 on every interface (adapters added later need it again: the validator says so).'
        } catch { Fail 'NetBIOS over TCP/IP off' $_ }
    }

    # The network Setup used: Private (settings options.firstNetworkCategory). Windows puts a new
    # network on Public, where the baseline ignores firewall rules that apps add themselves
    # (AllowLocalPolicyMerge = 0); Private applies them. Networks met later stay Public.
    if ($o -and "$($o.firstNetworkCategory)" -eq 'private') {
        Step 'First network: Private'
        try {
            $ncp = @(Get-NetConnectionProfile -ErrorAction Stop | Where-Object { "$($_.NetworkCategory)" -ne 'DomainAuthenticated' })
            if (-not $ncp.Count) { Write-Warning 'No network connection yet: none set to Private (Settings > Network & internet > the connection > Network profile type)' }
            foreach ($n in $ncp) {
                Set-NetConnectionProfile -InterfaceIndex $n.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                Write-Host "  $($n.Name) on $($n.InterfaceAlias): Private"
            }
        } catch { Fail 'First network: Private' $_ }
    }

    # DNS over HTTPS (settings options.dns): each server DoH-only (no fallback to plain DNS), set
    # on every physical adapter; names of the local zones go to their own servers (NRPT)
    if ($o -and $o.dns -and "$($o.dns.overHttps)" -eq 'require') {
        Step 'DNS over HTTPS'
        try {
            $addrs = @()
            foreach ($ds in @($o.dns.servers)) {
                $a = "$($ds.address)"; $t = "$($ds.template)"
                if (Get-DnsClientDohServerAddress -ServerAddress $a -ErrorAction SilentlyContinue) { Set-DnsClientDohServerAddress -ServerAddress $a -DohTemplate $t -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop }
                else { Add-DnsClientDohServerAddress -ServerAddress $a -DohTemplate $t -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop }
                $addrs += $a
            }
            foreach ($nic in @(Get-NetAdapter -Physical -ErrorAction Stop)) { Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $addrs -ErrorAction Stop }
            foreach ($z in @($o.dns.localZones)) {
                Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object { @($_.Namespace) -contains "$($z.namespace)" } | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force -ErrorAction SilentlyContinue }
                Add-DnsClientNrptRule -Namespace "$($z.namespace)" -NameServers @($z.servers) -Comment 'W11Kit local zone (settings options.dns.localZones)' -ErrorAction Stop
            }
            Clear-DnsClientCache
            Write-Host "DNS servers $($addrs -join ', ') (DoH only) on every physical adapter; local zones: $((@($o.dns.localZones) | ForEach-Object { $_.namespace }) -join ', ')"
        } catch { Fail 'DNS over HTTPS' $_ }
    }

    # Setup's temporary account (OOBE): disabled, but its profile and account stay behind
    Step 'Removing Setup''s temporary account (defaultuser0)'
    try {
        $tmpProf = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq "$env:SystemDrive\Users\defaultuser0" -and -not $_.Loaded }
        if ($tmpProf) { $tmpProf | Remove-CimInstance -ErrorAction Stop; Write-Host 'Profile removed.' }
        if (Get-LocalUser -Name defaultuser0 -ErrorAction SilentlyContinue) { Remove-LocalUser -Name defaultuser0 -ErrorAction Stop; Write-Host 'Account removed.' }
    } catch { Write-Warning "defaultuser0: $_ (harmless: the account is disabled)" }

    # --- 8. Validation snapshot ------------------------------------------------
    Step 'Validation (pre-restart snapshot)'
    try { Invoke-Payload 'Test-InstalledPc.ps1' @{ PreRestart = $true } } catch { Fail 'Validation' $_ }
}
catch {
    # Anything a step's own handler missed: record it so the status file can
    # never claim a clean run (the remaining steps are skipped).
    Fail 'Unexpected error (later steps skipped)' $_
}
finally {
    Step 'Clearing one-time autologon'
    # Setup's AutoLogon (LogonCount=1) is spent; make sure no password stays in Winlogon.
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $wl -Name AutoAdminLogon -Value '0' -ErrorAction SilentlyContinue
    Remove-ItemProperty $wl -Name DefaultPassword, AutoLogonCount -ErrorAction SilentlyContinue

    [ordered]@{
        finished = (Get-Date).ToString('s')
        kitRevision = $kitRevision
        critical = $critical
        failures = @($failures)
    } | ConvertTo-Json | Set-Content (Join-Path $root 'postinstall-status.json') -Encoding ASCII

    # Inside a Hyper-V test VM only: publish the outcome to the host through the
    # Key-Value Pair Exchange integration service (scripts\Test-IsoInHyperV.ps1).
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs.Manufacturer -eq 'Microsoft Corporation' -and $cs.Model -eq 'Virtual Machine') {
        # Guest-to-host Key-Value Pair items live under ...\Virtual Machine\Guest
        # (the host reads them as GuestExchangeItems); ...\Auto is Windows' own intrinsic set
        $kvp = 'HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest'
        New-Item -Path $kvp -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty $kvp -Name 'W11KitPostInstall' -Value "done;critical=$critical;failures=$($failures.Count)" -ErrorAction SilentlyContinue
    }

    Write-Host ''
    if ($critical) {
        # Same text on screen and in a file on the Public desktop (the window may be gone
        # by the time someone comes back to the PC).
        $note = @(
            'SECURITY BASELINE OVERRIDES FAILED - DO NOT RESTART YET.'
            ''
            "What happened: the W11Kit first-boot setup ($(Get-Date -Format 'yyyy-MM-dd HH:mm')) could not apply some of its changes"
            "to Microsoft's security baseline, so it cancelled its automatic restart on purpose. Restarting now"
            'would lock Memory Integrity and LSA protection into the firmware (UEFI lock) and stop your daily'
            "account ($userName) from approving administrator prompts."
            ''
            'What to do:'
            '  1. Do not restart or shut down the PC.'
            "  2. Open PowerShell as administrator: Start, type powershell, right-click Windows PowerShell,"
            "     Run as administrator (approve as $adminName)."
            '  3. Run the first-boot setup again (safe to repeat):'
            "       $rerunCmd"
            '     If it ends with "Setup complete" or "Finished with N warning(s)", the PC restarts by itself'
            '     in 2 minutes and this file is deleted.'
            '  4. If it says SECURITY BASELINE OVERRIDES FAILED again: still do not restart. Report it with'
            "     the log $transcriptPath"
            "     and $root\postinstall-status.json."
            ''
            'Only the security policies (baselines, overrides, kit policies; no restart), from the same'
            'administrator PowerShell (docs/reference/SECURITY-BASELINE.md, "Changing a setting later"):'
            "  cd $root"
            '  $p = (Get-Content -Raw profile.json | ConvertFrom-Json).power.mode'
            '  & ([scriptblock]::Create((Get-Content -Raw .\Apply-Policy.ps1))) -PowerMode $p -Settings (Get-Content -Raw settings.json | ConvertFrom-Json) -LogDir .\Logs'
            ''
            "What failed ($($failures.Count)):"
        ) + @($failures | ForEach-Object { "  - $_" })
        try { [IO.File]::WriteAllLines($criticalNote, [string[]]$note) } catch { Write-Warning "Could not write ${criticalNote}: $_" }
        foreach ($l in $note) { Write-Host $l -ForegroundColor Red }
        Write-Host ''
        Write-Host "This text is also on the desktop: $criticalNote" -ForegroundColor Yellow
        Wait-ForEnter 15
    } else {
        Remove-Item -LiteralPath $criticalNote -Force -ErrorAction SilentlyContinue   # from an earlier, critical run
        if ($failures.Count) {
            Write-Host "Finished with $($failures.Count) warning(s) - see $logDir and $root\postinstall-status.json." -ForegroundColor Yellow
        } else {
            Write-Host 'Setup complete.' -ForegroundColor Green
        }
        Write-Host 'The PC restarts in 2 minutes. Afterwards:' -ForegroundColor Green
        Write-Host "  1. Sign in as $adminName, set its new password, sign out." -ForegroundColor Green
        Write-Host "  2. Sign in as $userName and set its new password. Use $userName from then on." -ForegroundColor Green
        if (-not $NoRestart) {
            & shutdown.exe /r /t 120 /c "Windows setup complete. After the restart: sign in as $adminName first to change its password, then use $userName."
        }
    }
    Stop-Transcript | Out-Null
}
