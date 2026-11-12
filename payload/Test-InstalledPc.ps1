<#
.SYNOPSIS
    Checks the installed system against the kit's success criteria and the
    hardware profile's device checks (C:\ProgramData\W11Kit\profile.json,
    docs/reference/PROFILES.md), following the settings as built (settings.json next to it:
    home location, options and reminders; docs/reference/CONFIGURATION.md). Writes W11Kit-Validation.md and W11Kit-Validation.json
    (machine-readable; 'hardware' marks the profile's device, Wake-on-LAN and
    disk rows) to the Public desktop and C:\ProgramData\W11Kit.
    The window shows the FAIL and WARN rows first (what to look at), then one line
    per group with its counts, then the totals and where the report is; -All
    prints every row as one table instead. W11Kit-Validation.md starts with
    "Needs attention", then has a section per group.
    Run elevated for the TPM / Secure Boot / BitLocker checks and for the
    "Since last report" rows (event counts since the previous report's time).
#>
[CmdletBinding()]
param(
    # Set by PostInstall.ps1: the snapshot is taken before the first restart,
    # so VBS/HVCI, the UAC settings and some policies show their
    # pre-restart state. Re-run (desktop shortcut) after the restart.
    [switch]$PreRestart,
    # Print every row as one wide table (the default prints what needs attention, then
    # counts per group; the report files always hold every row).
    [switch]$All,
    # Exit with 0 (no FAIL or WARN), 1 (WARN only) or 2 (a FAIL), for a scheduled task or a CI job.
    # Only for a run as a script file (powershell -File): in a scriptblock, exit would end its caller.
    [switch]$ExitCode
)

$ErrorActionPreference = 'Continue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$results = New-Object System.Collections.Generic.List[object]
# -Hardware: a row about physical hardware (the profile's checks[], Wake-on-LAN, the
# disks, firmware and driver age); a VM test treats those as expected to fail.
# What to do about a WARN or FAIL row whose own text doesn't say: rows backed by the kit's local
# Group Policy are fixed by applying it again; device rows by a driver. 'Area: Check' patterns
# (-like); a row's own -Fix comes first. Shown under the row, and in the .json (fix).
$fixPolicy = "put the kit's policies back: in PowerShell as administrator, Apply-Policy.ps1 as in docs/reference/SECURITY-BASELINE.md, 'Changing a setting later'"
$fixDevice = "Device Manager shows the device and its problem; a missing driver: docs/AFTER-INSTALL.md, 'A device without a driver'"
$fixVbs = "restart once (the first restart after setup turns it on); still off: the CPU's virtualization in the BIOS (AMD: SVM Mode, Intel: VT-x) - read docs/GUIDE.md, 'Before any BIOS change' first"
$fixRepair = "repair Windows' own files, in PowerShell as administrator: DISM /Online /Cleanup-Image /RestoreHealth, then sfc /scannow"
$fixSb = "restart twice: Windows installs Microsoft's new Secure Boot certificates over restarts; still missing: the newest BIOS from the PC maker (docs/TROUBLESHOOTING.md, 'Secure Boot and BitLocker')"
$fixFor = [ordered]@{
    'Security: SmartScreen not disabled by policy' = $fixPolicy; 'Security: Defender PUA blocking' = $fixPolicy
    'Security: ASR rules' = $fixPolicy; 'Security: ASR [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-*' = $fixPolicy
    'Security: BitLocker policy allows TPM-only unlock' = $fixPolicy
    'Baseline: Microsoft Security Baseline applied' = $fixPolicy; 'Baseline: Account lockout *' = $fixPolicy
    'Baseline: SmartScreen for apps*' = $fixPolicy; 'Baseline: Defender network protection*' = $fixPolicy
    'Baseline: Edge security baseline applied' = $fixPolicy; 'Baseline: Baseline: every policy value in effect' = $fixPolicy
    'Override: Overrides and kit policies*' = $fixPolicy; 'Override: Edge *' = $fixPolicy
    'Override: Administrator protection off*' = $fixPolicy; 'Override: Minimum password length*' = $fixPolicy
    'Override: UAC prompt lists the admin account' = $fixPolicy; 'Override: Standard user gets an admin credential prompt' = $fixPolicy
    'Override: USB drives writable' = $fixPolicy; 'Override: HVCI policy without UEFI lock' = $fixPolicy
    'Override: LSA protection without UEFI lock' = $fixPolicy; 'Override: ASR rule:*' = $fixPolicy
    'Override: Defender sends safe samples only' = $fixPolicy; 'Override: Xbox service *' = $fixPolicy
    'Override: Services the kit disables*' = $fixPolicy; 'Override: Security options the kit sets*' = $fixPolicy
    'STIG: Minimum password age 1 day' = $fixPolicy; 'STIG: Built-in Administrator and Guest renamed and disabled' = $fixPolicy
    'STIG: Audit policy*' = $fixPolicy; 'STIG: Deny logon rights*' = $fixPolicy
    'Updates: New devices*' = $fixPolicy
    'Account: Windows sign-in cannot be converted to a Microsoft account' = $fixPolicy
    'Privacy: Diagnostic data = Required' = $fixPolicy; 'Privacy: Recall disabled' = $fixPolicy; 'Privacy: Widgets disabled' = $fixPolicy
    'Devices: No unknown devices (code 28)' = $fixDevice; 'Devices: No failed devices' = $fixDevice
    'Security: Windows RE enabled' = 'in PowerShell as administrator: reagentc /enable (reagentc /info then shows where Windows RE is)'
    'Security: VBS running' = $fixVbs; 'Security: Memory integrity (HVCI)' = $fixVbs
    'Security: LSA protection' = 'Windows Security > Device security > Core isolation details > Local Security Authority protection: on, then restart'
    'Security: Defender real-time protection' = 'Windows Security > Virus & threat protection > Manage settings > Real-time protection: on (another antivirus program turns it off)'
    'Services: Windows Time automatic' = 'in PowerShell as administrator: Set-Service W32Time -StartupType Automatic; Start-Service W32Time'
    'Runtimes: WebView2 Runtime' = 'install the Evergreen WebView2 Runtime from Microsoft: https://developer.microsoft.com/microsoft-edge/webview2/'
    'Runtimes: DirectX 12' = $fixRepair; 'Runtimes: .NET Framework 4.8+' = $fixRepair
    'OS: Edition' = 'the kit''s image is Pro: Settings > System > Activation > Change product key, with a Windows 11 Pro key'
    'Security: Secure Boot DB has Windows UEFI CA 2023' = $fixSb; 'Security: Secure Boot KEK has Microsoft KEK 2K CA 2023' = $fixSb
    'Account: Local accounts only (no Microsoft account)' = 'on the account that was converted: Settings > Accounts > Your info > Sign in with a local account instead'
    'Account: Separate standard daily account' = "in PowerShell as administrator: Remove-LocalGroupMember -SID S-1-5-32-544 -Member '<the daily account>' (S-1-5-32-544 is the Administrators group)"
    'Baseline: PostInstall finished cleanly' = 'run the first-boot setup again (safe to repeat; it restarts the PC 2 minutes after it ends), in PowerShell as administrator: powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\PostInstall.ps1'
    'Power: Wake-on-LAN: magic packet on the *' = $fixDevice
    'Power: Wake-on-LAN: NIC armed to wake the PC' = "in PowerShell as administrator: powercfg /deviceenableawake '<the adapter's name, as powercfg /devicequery wake_programmable lists it>'"
    'Power: Fast Startup off*' = 'Control Panel > Power Options > Choose what the power buttons do > Change settings that are currently unavailable > Turn on fast start-up: off'
    'Conflicts: Smart multi-homed name resolution not disabled' = $fixPolicy
    'GPU: Hardware-accelerated GPU scheduling' = 'Settings > System > Display > Graphics: Hardware-accelerated GPU scheduling on, then restart'
    'GPU: Variable refresh rate' = 'as the account that plays: Settings > System > Display > Graphics: Variable refresh rate and Optimizations for windowed games on'
    'GPU: Game Mode' = 'as the account that plays: Settings > Gaming > Game Mode: on'
    'Store/Gaming: *' = 'as the daily account: install it from the Microsoft Store'
    'WSL: Optional features' = 'run Validate PC as administrator'
    'Services: *' = "in PowerShell as administrator: Set-Service -Name '<the service in this row>' -StartupType Manual (Automatic if it should always run)"
    'WSL: *' = 'in PowerShell as administrator: Enable-WindowsOptionalFeature -Online -FeatureName <the feature in this row> (Disable-WindowsOptionalFeature when it should be off), then restart'
}
function Add-Check([string]$Area, [string]$Check, [ValidateSet('PASS', 'WARN', 'FAIL', 'INFO')][string]$State, [string]$Detail, [switch]$Hardware, [string]$Fix) {
    if (-not $Fix -and $State -in 'WARN', 'FAIL') { foreach ($k in $fixFor.Keys) { if ("${Area}: $Check" -like $k) { $Fix = $fixFor[$k]; break } } }
    $results.Add([pscustomobject]@{ Area = $Area; Check = $Check; State = $State; Detail = $Detail; Hardware = [bool]$Hardware; Fix = $(if ($State -in 'WARN', 'FAIL') { $Fix } else { '' }) })
}
function Reg($Path, $Name) { try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null } }

# --- OS ----------------------------------------------------------------------
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$os = Get-CimInstance Win32_OperatingSystem
# How old this install is (days; $null when not readable): rows about things that need
# time (a first scan, a month of updates, a week of logs) don't WARN on a new PC.
$pcAgeDays = try { [int]((Get-Date) - $os.InstallDate).TotalDays } catch { $null }
$pcIsNew = { param([int]$Days) $PreRestart -or $null -eq $pcAgeDays -or $pcAgeDays -lt $Days }
# The report before this one (read now, overwritten at the end): the "Since last report"
# rows count events from its time. $null: no earlier report, or its time isn't usable.
$prevTime = $null; $prevJson = $null
foreach ($p in 'C:\ProgramData\W11Kit\W11Kit-Validation.json', "$env:PUBLIC\Desktop\W11Kit-Validation.json") {
    try {
        $pj = Get-Content -Raw -LiteralPath $p -ErrorAction Stop | ConvertFrom-Json
        $g = "$($pj.generated)"
        $t = [datetime]::Parse($g, [Globalization.CultureInfo]::InvariantCulture)
        if ($t -lt (Get-Date)) { $prevTime = $t; $prevJson = $pj; break }
    } catch { }
}
Add-Check 'OS' 'Edition' $(if ($cv.EditionID -eq 'Professional') { 'PASS' } else { 'FAIL' }) "$($os.Caption) $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR)"
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select-Object -First 1
# A 'generic' profile activates from the PC's digital licence (e.g. a Pro licence
# bought and activated on it before the reinstall) once Windows is online.
Add-Check 'OS' 'Activation' $(if ($lic.LicenseStatus -eq 1) { 'PASS' } else { 'WARN' }) "LicenseStatus=$($lic.LicenseStatus) ($($lic.Description))$(if ($lic.LicenseStatus -ne 1) { ' - connect to the internet and wait, or Settings > System > Activation > Troubleshoot; enter your Pro key there if this PC never had Pro activated' })"

$bo = try { Get-Content -Raw 'C:\ProgramData\W11Kit\build-options.json' -ErrorAction Stop | ConvertFrom-Json } catch { $null }
# Whose settings the per-user rows read: the daily account's (build-options.json UserName)
# when this run is another account (elevated, or SYSTEM for the scheduled run) and the daily
# account is signed in (its hive is loaded under HKEY_USERS), else this account's, and the
# row says so
$userRoot = 'HKCU:'; $userWho = "$env:USERDOMAIN\$env:USERNAME"; $userNote = ''
if ($bo -and $bo.UserName -and $env:USERNAME -ne $bo.UserName) {
    $uSid = try { (Get-LocalUser -Name $bo.UserName -ErrorAction Stop).SID.Value } catch { $null }
    if ($uSid -and (Test-Path -LiteralPath "Registry::HKEY_USERS\$uSid")) { $userRoot = "Registry::HKEY_USERS\$uSid"; $userWho = "$($bo.UserName) (the daily account)" }
    else { $userNote = " - $($bo.UserName), the daily account, isn't signed in: sign in as it and run Validate PC for its own settings" }
}
if ($bo -and $bo.ComputerName) {
    # Setup can ignore the answer file's name; PostInstall renames (effective after its restart).
    $pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    $nameState = if ($env:COMPUTERNAME -eq $bo.ComputerName) { 'PASS' } elseif ($PreRestart -and $pendingName -eq $bo.ComputerName) { 'PASS' } else { 'FAIL' }
    Add-Check 'OS' 'Computer name' $nameState "running as $env:COMPUTERNAME, pending $pendingName, image $($bo.ComputerName)"
} else {
    Add-Check 'OS' 'Computer name' 'INFO' $(if ($bo) { "$env:COMPUTERNAME (no name in the settings or the profile: Windows chose it)" } else { "$env:COMPUTERNAME (build-options.json not readable: run elevated)" })
}
# A test build (Run-Build.cmd -TestBuild) is for a virtual machine: its passwords are in
# test-accounts.txt, and its ISO carries no build inputs for a rebuild.
if ($bo -and $bo.TestBuild) {
    $csModel = try { $c = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; "$($c.Manufacturer) $($c.Model)" } catch { '' }
    if ($csModel -match 'Virtual|VMware|KVM|QEMU|Xen|Bochs') { Add-Check 'OS' 'Image kind' 'INFO' "test build, in a virtual machine ($csModel)" }
    else { Add-Check 'OS' 'Image kind' 'WARN' "this PC was installed from a TEST build ($csModel): a test build is for a virtual machine only, and its ISO holds no build inputs. Build a real ISO (Run-Build.cmd without -TestBuild) and reinstall from that" }
}
# The image's feature and app lists (config/image.json, staged by the build): the
# single source of truth for the WSL and Store/Gaming checks below.
$image = $null; $imageErr = 'empty, or no features/requiredApps'
try { $image = Get-Content -Raw -LiteralPath 'C:\ProgramData\W11Kit\image.json' -ErrorAction Stop | ConvertFrom-Json } catch { $imageErr = $_.Exception.Message }
if (-not ($image -and $image.features -and $image.requiredApps)) {
    $image = $null
    Add-Check 'OS' 'Image facts (image.json) readable' 'FAIL' "C:\ProgramData\W11Kit\image.json: $imageErr - the WSL feature and Store/Gaming app checks are skipped"
}

# The hardware profile chosen at build time (docs/reference/PROFILES.md). Not readable: one FAIL
# row, the hardware checks are skipped, power is checked as mode 'default'.
$hw = $null; $hwErr = 'no id or power section'
try { $hw = Get-Content -Raw -LiteralPath 'C:\ProgramData\W11Kit\profile.json' -ErrorAction Stop | ConvertFrom-Json } catch { $hwErr = $_.Exception.Message }
if (-not ($hw -and $hw.id -and $hw.power)) {
    $hw = $null
    Add-Check 'OS' 'Hardware profile (profile.json) readable' 'FAIL' "C:\ProgramData\W11Kit\profile.json: $hwErr - the hardware checks (devices, Wake-on-LAN, hibernate) are skipped"
}
$hwName = if ($hw -and $hw.displayName) { "$($hw.displayName)" } elseif ($hw) { "$($hw.id)" } else { 'Windows 11 (no hardware profile)' }
$powerMode = if ($hw -and "$($hw.power.mode)" -eq 'hibernate') { 'hibernate' } else { 'default' }
$wol = if ($hw -and $hw.power.wakeOnLan -and $hw.power.wakeOnLan.adapter) { $hw.power.wakeOnLan } else { $null }
$hwChecks = @(if ($hw) { @($hw.checks) | Where-Object { $_ -and $_.name -and $_.type } })

# The settings as built (docs/reference/CONFIGURATION.md, "Your settings"): the kit's
# defaults with the user's file over them, complete. No defaults are declared here: a
# field that is missing, or a file that can't be read (one FAIL row), means the option
# or reminder is off, so its rows only report.
$kitSettings = $null; $setErr = 'not a JSON object'
try { $kitSettings = Get-Content -Raw -LiteralPath 'C:\ProgramData\W11Kit\settings.json' -ErrorAction Stop | ConvertFrom-Json } catch { $setErr = $_.Exception.Message }
if ($kitSettings -isnot [pscustomobject]) {
    $kitSettings = $null
    Add-Check 'OS' 'Settings (settings.json) readable' 'FAIL' "C:\ProgramData\W11Kit\settings.json: $setErr - the rows that follow the settings (options, reminders, home location) only report"
}
function Get-Setting([string]$Path) {
    $v = $kitSettings
    foreach ($part in $Path -split '\.') { if ($null -eq $v) { break }; $v = $v.$part }
    $v
}
$optGaming = (Get-Setting 'options.gamingTweaks') -eq $true
$expectedExtra = @(Get-Setting 'accounts.expectedExtra' | Where-Object { $_ } | ForEach-Object { "$_" })
$optSacOff = "$(Get-Setting 'options.smartAppControl')" -eq 'off'
$optBrave = (Get-Setting 'options.bravePolicies') -eq $true
$optLongPaths = (Get-Setting 'options.longPaths') -eq $true
$remOneDrive = (Get-Setting 'reminders.oneDriveBackup') -eq $true
$remRemote = (Get-Setting 'reminders.remoteAccessOnDemand') -eq $true
$remNvidia = (Get-Setting 'reminders.nvidiaApp') -eq $true
$remOffline = (Get-Setting 'reminders.offlineBackup') -eq $true
$expectedApps = @(Get-Setting 'reminders.expectedApps' | Where-Object { $_ -and $_.name })
$homeGeoId = "$(Get-Setting 'locale.homeLocation.geoId')"
$homeIso = "$(Get-Setting 'locale.homeLocation.isoCode')"
$homeName = if ($homeIso) { try { (New-Object Globalization.RegionInfo $homeIso).EnglishName } catch { $homeIso } } else { '' }

# One row per profile check (checks[]: video / sound / netadapter / pnp).
function Test-ProfileCheck($c) {
    try {
        switch ("$($c.type)") {
            'video' {
                $all = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object Name -match $c.match)
                $ok = @($all | Where-Object { $_.Status -eq 'OK' -and (-not $c.vendor -or $_.AdapterCompatibility -match $c.vendor) })
                $d = @($ok + $all) | Select-Object -First 1
                Add-Check $c.area $c.name $(if ($ok.Count) { 'PASS' } else { 'FAIL' }) "$($d.Name) driver $($d.DriverVersion) status $($d.Status)" -Hardware -Fix $fixDevice
            }
            'sound' {
                $audio = @(Get-CimInstance Win32_SoundDevice -ErrorAction Stop)
                $ok = @($audio | Where-Object { $_.Name -match $c.match -and $_.Status -eq 'OK' })
                Add-Check $c.area $c.name $(if ($ok.Count) { 'PASS' } else { 'FAIL' }) (($audio | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join '; ') -Hardware -Fix $fixDevice
            }
            'netadapter' {
                $all = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -match $c.match)
                $up = @($all | Where-Object Status -eq 'Up')
                $d = @($up + $all) | Select-Object -First 1
                Add-Check $c.area $c.name $(if ($up.Count) { 'PASS' } elseif ($all.Count) { 'WARN' } else { 'FAIL' }) "$($d.InterfaceDescription) $($d.Status) $($d.LinkSpeed) driver $($d.DriverVersion)" -Hardware -Fix $fixDevice
            }
            'pnp' {
                $all = @(if ($c.class) { Get-PnpDevice -Class $c.class -PresentOnly -ErrorAction SilentlyContinue } else { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue }) |
                    Where-Object FriendlyName -match $c.match
                $all = @($all)
                $ok = @($all | Where-Object Status -eq 'OK')
                $d = @($ok + $all) | Select-Object -First 1
                # A network device also shows its adapter (Wi-Fi: connected or not, driver version)
                $ad = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -match $c.match | Select-Object -First 1
                Add-Check $c.area $c.name $(if ($ok.Count) { 'PASS' } elseif ($all.Count) { 'WARN' } else { 'FAIL' }) "$(if ($d) { "$($d.FriendlyName) $($d.Status)" } else { 'not found' })$(if ($ad) { "; adapter $($ad.Status) driver $($ad.DriverVersion)" })" -Hardware -Fix $fixDevice
            }
            default { Add-Check $c.area $c.name 'FAIL' "profile check type '$($c.type)' unknown (video, sound, netadapter, pnp)" -Hardware }
        }
    } catch { Add-Check $c.area $c.name 'FAIL' "check failed: $($_.Exception.Message)" -Hardware }
}

# --- Devices -----------------------------------------------------------------
$bad = Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' } | ForEach-Object {
    $code = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
    [pscustomobject]@{ Name = $_.FriendlyName; Id = $_.InstanceId; Code = $code }
}
$unknown = @($bad | Where-Object { $_.Code -eq 28 -or -not $_.Name })
$faulted = @($bad | Where-Object { $_.Code -ne 22 -and $_.Code -ne 28 -and $_.Name })
$disabled = @($bad | Where-Object { $_.Code -eq 22 })
Add-Check 'Devices' 'No unknown devices (code 28)' $(if ($unknown.Count) { 'FAIL' } else { 'PASS' }) (($unknown | ForEach-Object { "$($_.Name) [$($_.Id)]" }) -join '; ')
Add-Check 'Devices' 'No failed devices' $(if ($faulted.Count) { 'FAIL' } else { 'PASS' }) (($faulted | ForEach-Object { "$($_.Name) code $($_.Code)" }) -join '; ')
if ($disabled.Count) { Add-Check 'Devices' 'Disabled by user (code 22)' 'INFO' (($disabled | ForEach-Object { $_.Name }) -join '; ') }

# The profile's GPU-area checks first, then the generic GPU rows, then its other checks.
foreach ($c in @($hwChecks | Where-Object { "$($_.area)" -eq 'GPU' })) { Test-ProfileCheck $c }
$hags = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
# settings options.gamingTweaks false: the kit doesn't set these, so they are only reported (INFO)
$gamingOff = if ($optGaming) { '' } else { ' (not set by the kit: settings options.gamingTweaks is false)' }
Add-Check 'GPU' 'Hardware-accelerated GPU scheduling' $(if (-not $optGaming) { 'INFO' } elseif ($hags -eq 2) { 'PASS' } else { 'WARN' }) "HwSchMode=$hags$gamingOff"
$dx = Reg "$userRoot\Software\Microsoft\DirectX\UserGpuPreferences" 'DirectXUserGlobalSettings'
$who = "$userWho$userNote"
Add-Check 'GPU' 'Variable refresh rate' $(if (-not $optGaming) { 'INFO' } elseif ($dx -match 'VRROptimizeEnable=1') { 'PASS' } else { 'WARN' }) "$dx (checked for $who; also enable G-SYNC / FreeSync in the GPU's control panel if the display supports it)$gamingOff"
$gm = Reg "$userRoot\Software\Microsoft\GameBar" 'AutoGameModeEnabled'
Add-Check 'GPU' 'Game Mode' $(if (-not $optGaming) { 'INFO' } elseif ($gm -ne 0) { 'PASS' } else { 'WARN' }) "AutoGameModeEnabled=$gm (checked for $who)$gamingOff"

foreach ($c in @($hwChecks | Where-Object { "$($_.area)" -ne 'GPU' })) { Test-ProfileCheck $c }

# --- Power: the profile's power.mode and Wake-on-LAN (docs/reference/PROFILES.md) -----
# Windows' own numbers, not the text of powercfg / net accounts / msinfo32: that text is
# translated, so a check that reads it fails on a PC with another display language.
if (-not ('W11KitNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class W11KitNative {
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int infoClass, ref byte info, int length, out int returned);
    [DllImport("powrprof.dll")] static extern byte GetPwrCapabilities(IntPtr caps);
    [DllImport("powrprof.dll")] static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
    [DllImport("powrprof.dll")] static extern uint PowerReadACValueIndex(IntPtr root, IntPtr scheme, ref Guid sub, ref Guid setting, out uint value);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
    [DllImport("netapi32.dll", CharSet = CharSet.Unicode)] static extern int NetUserModalsGet(string server, int level, out IntPtr buf);
    [DllImport("netapi32.dll")] static extern int NetApiBufferFree(IntPtr buf);
    // Kernel DMA Protection (SystemDmaGuardPolicyInformation): 1 on, 0 off, -1 unknown
    public static int DmaGuard() { byte b = 0; int r; return NtQuerySystemInformation(202, ref b, 1, out r) == 0 ? (b != 0 ? 1 : 0) : -1; }
    // SYSTEM_POWER_CAPABILITIES as bytes: [3] S1, [4] S2, [5] S3, [6] S4, [8] hibernation file, [20] Modern Standby
    public static byte[] PowerCaps() {
        IntPtr p = Marshal.AllocHGlobal(256);
        try { for (int i = 0; i < 256; i++) Marshal.WriteByte(p, i, 0); if (GetPwrCapabilities(p) == 0) return null; byte[] b = new byte[32]; Marshal.Copy(p, b, 0, 32); return b; }
        finally { Marshal.FreeHGlobal(p); }
    }
    // The active plan's value on mains power; -1 if it can't be read
    public static long PowerAc(Guid sub, Guid setting) {
        IntPtr s; if (PowerGetActiveScheme(IntPtr.Zero, out s) != 0) return -1;
        try { uint v; return PowerReadACValueIndex(IntPtr.Zero, s, ref sub, ref setting, out v) == 0 ? (long)v : -1L; } finally { LocalFree(s); }
    }
    // Account policy: level 0 = { minimum length, maximum age s, minimum age s, force logoff, history },
    // level 3 = { lockout duration s, observation window s, threshold }
    public static uint[] Modals(int level) {
        IntPtr p; if (NetUserModalsGet(null, level, out p) != 0) return null;
        try { int n = level == 0 ? 5 : 3; uint[] r = new uint[n]; for (int i = 0; i < n; i++) r[i] = (uint)Marshal.ReadInt32(p, i * 4); return r; } finally { NetApiBufferFree(p); }
    }
}
'@
}
$caps = try { [W11KitNative]::PowerCaps() } catch { $null }
$canHibernate = [bool]($caps -and $caps[6] -and $caps[8])   # S4 and a hibernation file
# The setting GUIDs behind powercfg's aliases (the power button one is hidden on a desktop).
$powerGuid = @{ SUB_SLEEP = '238c9fa8-0aad-41ed-83f4-97be242c8f20'; HIBERNATEIDLE = '9d7815a6-7ee4-497e-8888-515a05f02364'
                SUB_BUTTONS = '4f971e89-eebd-4455-a8de-9e59040e7347'; PBUTTONACTION = '7648efa3-dd9c-4e3e-b566-50f929386280' }
function Get-PowerAc([string]$Sub, [string]$Setting) {
    $v = try { [W11KitNative]::PowerAc([guid]$powerGuid[$Sub], [guid]$powerGuid[$Setting]) } catch { -1 }
    if ($v -ge 0) { [int]$v } else { $null }
}
if ($powerMode -eq 'hibernate') {
    Add-Check 'Power' 'Hibernate available' $(if ($canHibernate) { 'PASS' } else { 'FAIL' }) $(if ($canHibernate) { 'the firmware offers S4 and the hibernation file exists' } elseif (-not $caps) { 'the power capabilities could not be read' } else { "S4 offered by the firmware: $([bool]$caps[6]); hibernation file: $([bool]$caps[8]) - powercfg /a says why" })
    $hb = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
    Add-Check 'Power' 'Fast Startup off (clean cold boot; Wake-on-LAN from shutdown)' $(if ($hb -eq 0) { 'PASS' } else { 'WARN' }) "HiberbootEnabled=$hb"
    $hibIdle = Get-PowerAc SUB_SLEEP HIBERNATEIDLE
    $btn = Get-PowerAc SUB_BUTTONS PBUTTONACTION
    # settings options.idleHibernate false: no idle hibernate is the chosen state
    $idleWanted = (Get-Setting 'options.idleHibernate') -ne $false
    Add-Check 'Power' $(if ($idleWanted) { 'Idle and power button hibernate' } else { 'Power button hibernates; never idle (settings options.idleHibernate false)' }) $(if ($btn -eq 2 -and (($idleWanted -and $hibIdle -gt 0) -or (-not $idleWanted -and $hibIdle -eq 0))) { 'PASS' } else { 'WARN' }) "hibernate after $hibIdle s idle, power button action=$btn (2 = hibernate)"
} else {
    # Mode 'default': sleep is left as Windows and the firmware set it; just show it.
    $states = @(if ($caps) { if ($caps[20]) { 'Modern Standby (S0 low power idle)' }; if ($caps[3]) { 'S1' }; if ($caps[4]) { 'S2' }; if ($caps[5]) { 'S3' }; if ($canHibernate) { 'Hibernate (S4)' } })
    Add-Check 'Power' 'Sleep states (profile power mode: default)' 'INFO' "offered by the firmware: $(if ($states.Count) { $states -join ', ' } else { 'none' }) (powercfg /a shows what policy leaves available)"
}
if ($wol) {
    $wolLabel = if ($wol.label) { "$($wol.label)" } else { "$($wol.adapter)" }
    $wolNic = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -match $wol.adapter | Select-Object -First 1
    if ($wolNic) {
        $pm = Get-NetAdapterPowerManagement -Name $wolNic.Name -ErrorAction SilentlyContinue
        $s5 = (Get-NetAdapterAdvancedProperty -Name $wolNic.Name -RegistryKeyword 'S5WakeOnLan' -ErrorAction SilentlyContinue).RegistryValue
        Add-Check 'Power' "Wake-on-LAN: magic packet on the $wolLabel" $(if ("$($pm.WakeOnMagicPacket)" -eq 'Enabled') { 'PASS' } elseif (-not $pm) { 'WARN' } else { 'FAIL' }) "WakeOnMagicPacket=$($pm.WakeOnMagicPacket) WakeOnPattern=$($pm.WakeOnPattern) S5WakeOnLan=$s5 MAC $($wolNic.MacAddress) (BIOS: Wake on LAN on, ErP off)$(if (-not $pm) { ' - run elevated to read the NIC power settings' })" -Hardware
        $armed = @(& powercfg.exe /devicequery wake_armed) -contains $wolNic.InterfaceDescription
        Add-Check 'Power' 'Wake-on-LAN: NIC armed to wake the PC' $(if ($armed) { 'PASS' } else { 'FAIL' }) "powercfg /devicequery wake_armed $(if ($armed) { 'lists' } else { 'does not list' }) $($wolNic.InterfaceDescription)" -Hardware
    } else {
        Add-Check 'Power' "Wake-on-LAN: magic packet on the $wolLabel" 'FAIL' "$wolLabel adapter not found" -Hardware
    }
}
Add-Check 'Power' 'Active power plan (Balanced)' 'INFO' ((& powercfg.exe /getactivescheme) -join ' ')
Add-Check 'Power' 'Devices allowed to wake' 'INFO' (((& powercfg.exe /devicequery wake_armed) | Where-Object { $_ }) -join '; ')
Add-Check 'Power' 'Last wake source' 'INFO' (((& powercfg.exe /lastwake) | Where-Object { $_ -match 'Instance|Friendly|Description' }) -join '; ')

# --- Platform services -------------------------------------------------------
foreach ($svc in 'wuauserv', 'UsoSvc', 'BITS', 'CryptSvc', 'TrustedInstaller', 'VSS', 'WinDefend', 'ClipSVC', 'InstallService') {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    Add-Check 'Services' $svc $(if ($s -and $s.StartType -ne 'Disabled') { 'PASS' } else { 'FAIL' }) $(if ($s) { "$($s.Status), $($s.StartType)" } else { 'missing' })
}
# image.json: 'gamingApps' (the Xbox app and its sign-in component) are required only with options.gamingTweaks
$gamingApps = @($image.gamingApps | Where-Object { $_ })
# Has the daily account signed in yet? Before that (the first-boot snapshot) Windows has only
# provisioned the apps: it installs them for each account at that account's first sign-in.
$dailySid = if ($bo.UserName) { try { (Get-LocalUser -Name $bo.UserName -ErrorAction Stop).SID.Value } catch { $null } }
$dailySignedIn = [bool]($dailySid -and (Get-CimInstance Win32_UserProfile -Filter "SID='$dailySid'" -ErrorAction SilentlyContinue))
foreach ($pkg in @($image.requiredApps | Where-Object { $_ -and ($optGaming -or $gamingApps -notcontains $_) })) {
    # Elevated, the validator may run as another administrator: check the daily account's packages
    $for = if ($isAdmin -and $bo.UserName) { $bo.UserName } else { $env:USERNAME }
    $p = if ($isAdmin -and $bo.UserName) {
        Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue | Where-Object { @($_.PackageUserInformation | Where-Object { ("$($_.UserSecurityId.Username)" -eq $for -or "$($_.UserSecurityId.Username)" -like "*\$for") -and "$($_.InstallState)" -eq 'Installed' }).Count } | Select-Object -First 1
    } else { Get-AppxPackage -Name $pkg -ErrorAction SilentlyContinue }
    $prov = if (-not $p -and $isAdmin -and $bo.UserName -and -not $dailySignedIn) {
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $pkg | Select-Object -First 1
    }
    Add-Check 'Store/Gaming' $pkg $(if ($p -or $prov) { 'PASS' } else { 'FAIL' }) $(if ($p) { "$($p.Version) (checked for $for)" } elseif ($prov) { "$($prov.Version) provisioned: installed at $for's first sign-in" } else { "(checked for $for)" })
}
$gs = Get-AppxPackage -Name Microsoft.GamingServices -ErrorAction SilentlyContinue
Add-Check 'Store/Gaming' 'Gaming Services' $(if ($gs) { 'PASS' } else { 'INFO' }) $(if ($gs) { $gs.Version } else { 'Installed on demand by the Xbox app or the Store when a game needs it' })
$wv = Reg 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' 'pv'
Add-Check 'Runtimes' 'WebView2 Runtime' $(if ($wv) { 'PASS' } else { 'FAIL' }) "$wv"
Add-Check 'Runtimes' 'DirectX 12' $(if (Test-Path "$env:SystemRoot\System32\d3d12.dll") { 'PASS' } else { 'FAIL' }) 'd3d12.dll present (DirectStorage ships with each game)'
$net = Reg 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' 'Release'
Add-Check 'Runtimes' '.NET Framework 4.8+' $(if ($net -ge 528040) { 'PASS' } else { 'FAIL' }) "Release=$net"
$vc = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName -match 'Visual C\+\+ 20(15|17|19|22)'
Add-Check 'Runtimes' 'Visual C++ redistributables' 'INFO' $(if ($vc) { ($vc.DisplayName | Sort-Object -Unique) -join '; ' } else { 'None yet - the apps that need them install them' })

# --- Security ----------------------------------------------------------------
try { $mp = Get-MpComputerStatus; Add-Check 'Security' 'Defender real-time protection' $(if ($mp.RealTimeProtectionEnabled) { 'PASS' } else { 'FAIL' }) "AM $($mp.AMProductVersion)" } catch { Add-Check 'Security' 'Defender' 'FAIL' $_.Exception.Message }
# Defender's health beyond "real-time protection is on". In the first-logon snapshot
# these are INFO: tamper protection and fresh signatures arrive with Defender's first
# update, and no scan has run yet.
if ($mp -and $null -ne $mp.AMRunningMode) {
    $soft = if ($PreRestart) { 'INFO' } else { 'WARN' }
    Add-Check 'Security' 'Defender tamper protection' $(if ($mp.IsTamperProtected) { 'PASS' } else { $soft }) "IsTamperProtected=$($mp.IsTamperProtected)$(if (-not $mp.IsTamperProtected) { if ($PreRestart) { ' - Windows turns it on after Defender''s first update; check again after the restart' } else { ' - malware with admin rights could switch Defender off. Turn it on: Windows Security > Virus & threat protection > Manage settings > Tamper Protection (it can only be switched there, on purpose)' } })"
    Add-Check 'Security' 'Defender running in normal mode' $(if ("$($mp.AMRunningMode)" -eq 'Normal') { 'PASS' } else { 'WARN' }) "AMRunningMode=$($mp.AMRunningMode)$(if ("$($mp.AMRunningMode)" -ne 'Normal') { ' - another antivirus has taken over or Defender is not running: uninstall the other antivirus, then check Windows Security > Virus & threat protection' })"
    $sigAge = $mp.AntivirusSignatureAge
    Add-Check 'Security' 'Defender signatures current (3 days)' $(if ($null -ne $sigAge -and $sigAge -le 3) { 'PASS' } else { $soft }) "$sigAge day(s) old, version $($mp.AntivirusSignatureVersion)$(if ($null -eq $sigAge -or $sigAge -gt 3) { if ($PreRestart) { ' - as shipped in the image; Windows Update refreshes them once online' } else { ' - connect to the internet, then Windows Security > Virus & threat protection > Protection updates > Check for updates' } })"
    $scanAge = $mp.QuickScanAge; $neverScanned = ($null -eq $scanAge -or $scanAge -gt 100000)   # 4294967295 = never
    $scanState = if (-not $neverScanned -and $scanAge -le 14) { 'PASS' } elseif (& $pcIsNew 14) { 'INFO' } else { 'WARN' }
    Add-Check 'Security' 'Defender quick scan in the last 14 days' $scanState "$(if ($neverScanned) { 'no quick scan yet' } else { "last quick scan $scanAge day(s) ago" })$(if ($scanState -eq 'INFO') { ' (new install: Windows runs one by itself within days)' } elseif ($scanState -eq 'WARN') { ' - Windows normally scans by itself while the PC is idle. Run one: Windows Security > Virus & threat protection > Quick scan' })"
}
$ss = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen'
Add-Check 'Security' 'SmartScreen not disabled by policy' $(if ($ss -ne 0) { 'PASS' } else { 'FAIL' }) "EnableSmartScreen=$ss"
if (-not $isAdmin) {
    Add-Check 'Security' 'TPM / Secure Boot / WinRE / BitLocker' 'WARN' 'Not elevated - re-run as administrator for these checks'
} else {
try { $tpm = Get-Tpm -ErrorAction Stop; Add-Check 'Security' 'TPM ready' $(if ($tpm.TpmReady) { 'PASS' } else { 'FAIL' }) "present=$($tpm.TpmPresent) ready=$($tpm.TpmReady)" } catch { Add-Check 'Security' 'TPM' 'WARN' 'Run elevated' }
try { Add-Check 'Security' 'Secure Boot' $(if (Confirm-SecureBootUEFI) { 'PASS' } else { 'FAIL' }) '' } catch { Add-Check 'Security' 'Secure Boot' 'WARN' 'Run elevated' }
# The 2011 Secure Boot certificates expire in 2026: the firmware must trust the 2023 ones.
try {
    $sbDb = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db -ErrorAction Stop).Bytes)
    $sbKek = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI KEK -ErrorAction Stop).Bytes)
    $sbStatus = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue).UEFICA2023Status
    Add-Check 'Security' 'Secure Boot DB has Windows UEFI CA 2023' $(if ($sbDb -match 'Windows UEFI CA 2023') { 'PASS' } else { 'WARN' }) "UEFICA2023Status=$sbStatus (PostInstall queues Microsoft's update when missing; it completes over restarts)"
    Add-Check 'Security' 'Secure Boot KEK has Microsoft KEK 2K CA 2023' $(if ($sbKek -match 'KEK 2K CA 2023') { 'PASS' } else { 'WARN' }) "UEFICA2023Status=$sbStatus"
} catch { Add-Check 'Security' 'Secure Boot 2023 certificates' 'WARN' "Could not read db/KEK: $($_.Exception.Message)" }
# The boot manager this PC really starts from (on the EFI system partition), by its
# EMBEDDED signature (what the firmware checks; Get-AuthenticodeSignature would show the
# catalog signature). Read through the partition's volume path, so no drive letter is
# needed; if that fails, the partition is mounted for a moment (mountvol /S) and always
# unmounted again. Pre-restart it is INFO: Windows swaps the boot manager over restarts.
$sbCapable = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue).WindowsUEFICA2023Capable
$bmIssuer = $null; $bmErr = ''
$readIssuer = { param([string]$EspRoot) [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile(($EspRoot.TrimEnd('\') + '\EFI\Microsoft\Boot\bootmgfw.efi')).Issuer }
try {
    $sysDisk = (Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop).DiskNumber
    $esp = Get-Partition -DiskNumber $sysDisk -ErrorAction Stop | Where-Object { "$($_.GptType)" -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } | Select-Object -First 1
    $espPath = @($esp.AccessPaths | Where-Object { "$_" -like '\\?\Volume{*' }) | Select-Object -First 1
    if (-not $espPath) { throw 'no EFI system partition found on the Windows disk' }
    $bmIssuer = & $readIssuer "$espPath"
} catch { $bmErr = "$($_.Exception.Message)" }
if (-not $bmIssuer) {
    $espLetter = @('S', 'T', 'U', 'V', 'W', 'R', 'Q', 'P') | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
    if ($espLetter) {
        & mountvol.exe "${espLetter}:" /S 2>&1 | Out-Null
        try { if ($LASTEXITCODE -eq 0) { $bmIssuer = & $readIssuer "${espLetter}:\" } }
        catch { $bmErr = "$($_.Exception.Message)" }
        finally { & mountvol.exe "${espLetter}:" /D 2>&1 | Out-Null }
    }
}
$bmName = 'Installed boot manager signed with Windows UEFI CA 2023'
if ("$bmIssuer" -match 'Windows UEFI CA 2023') {
    Add-Check 'Security' $bmName 'PASS' "bootmgfw.efi on the EFI system partition: $bmIssuer"
} elseif ($bmIssuer) {
    Add-Check 'Security' $bmName $(if ($PreRestart) { 'INFO' } else { 'WARN' }) "bootmgfw.efi on the EFI system partition: $bmIssuer (WindowsUEFICA2023Capable=$sbCapable)$(if ($PreRestart) { ' - Windows replaces it over the next restarts once the firmware has the 2023 certificates; check again later' } else { ' - still the 2011 boot manager, whose certificate expires in October 2026. Ask Windows to switch (Microsoft''s own update, nothing is revoked): in an administrator PowerShell run  Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot -Name AvailableUpdates -Value 0x5944 -Type DWord; Start-ScheduledTask -TaskPath ''\Microsoft\Windows\PI\'' -TaskName Secure-Boot-Update  then restart twice and validate again' })"
} else {
    Add-Check 'Security' $bmName 'INFO' "could not read bootmgfw.efi on the EFI system partition ($bmErr); WindowsUEFICA2023Capable=$sbCapable (2 = Windows reports it starts from the 2023 boot manager)"
}
# Whether the firmware already refuses 2011-signed boot managers (DBX). The kit never
# revokes (irreversible; older boot media would stop starting): information only.
try {
    $sbDbx = [Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI dbx -ErrorAction Stop).Bytes)
    $revoked = $sbDbx -match 'Microsoft Windows Production PCA 2011'
    Add-Check 'Security' 'Secure Boot DBX: 2011 boot managers revoked' 'INFO' $(if ($revoked) { 'yes: this PC no longer starts boot media signed with the 2011 certificate (use a stick from a current build)' } else { 'no: boot media signed with the 2011 certificate still starts here (the kit does not revoke it: that step cannot be undone)' })
} catch { }
$re = (& reagentc.exe /info) -join ' '
# Enabled = reagentc names where Windows RE is (the status word itself is translated)
Add-Check 'Security' 'Windows RE enabled' $(if ($re -match '(?i)harddisk\d+\\partition\d+\\Recovery\\WindowsRE') { 'PASS' } else { 'FAIL' }) (($re -replace '\s+', ' ').Trim())
# Where Windows RE lives. Setup puts it on a recovery partition of its own (after
# Windows) when it creates the layout; left on C: it can't start once C: is encrypted.
if ($re -match '(?i)harddisk(\d+)\\partition(\d+)') {
    $reDisk = [int]$Matches[1]; $rePartNo = [int]$Matches[2]
    try {
        $rePart = Get-Partition -DiskNumber $reDisk -PartitionNumber $rePartNo -ErrorAction Stop
        $reVol = $rePart | Get-Volume -ErrorAction SilentlyContinue
        $reWhere = "disk $reDisk partition $rePartNo, $([math]::Round($rePart.Size / 1MB)) MB$(if ($reVol) { ", $([math]::Round($reVol.SizeRemaining / 1MB)) MB free" })"
        $reName = 'Windows RE on its own recovery partition'
        if ("$($rePart.DriveLetter)" -eq $env:SystemDrive.Substring(0, 1)) {
            Add-Check 'Security' $reName 'WARN' "Windows RE is on the Windows partition ($reWhere), not on a recovery partition: BitLocker can't keep the recovery tools on an encrypted drive, so they stop working once C: is encrypted. A reinstall onto unallocated space creates the partition (docs/GUIDE.md, step 12); to add one by hand see Microsoft's KB5028997"
        } elseif ("$($rePart.GptType)" -eq '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}') {
            Add-Check 'Security' $reName 'PASS' "$reWhere$(if ($reVol -and $reVol.SizeRemaining -lt 250MB) { ' (Microsoft asks for 250 MB free for recovery updates: if a Windows Update for the recovery environment fails with 0x80070643, enlarge the partition as KB5028997 describes)' })"
        } else {
            Add-Check 'Security' $reName 'INFO' "$reWhere, partition type $($rePart.GptType) (not the usual recovery type)"
        }
    } catch { Add-Check 'Security' 'Windows RE on its own recovery partition' 'INFO' "disk $reDisk partition $rePartNo could not be read: $($_.Exception.Message)" }
}
# Quick Machine Recovery (Windows RE fetching fixes from Windows Update after repeated
# start-up failures): only its two switches are shown. The full output can hold a
# Wi-Fi password, so it is never printed.
$qmr = (& reagentc.exe /getrecoverysettings 2>&1 | ForEach-Object { "$_" }) -join ' '
if ($qmr -match '(?i)<CloudRemediation\s+state="(\d+)"') {
    $qmrCloud = $Matches[1]
    $qmrAuto = if ($qmr -match '(?i)<AutoRemediation\s+state="(\d+)"') { $Matches[1] } else { 'not set' }
    Add-Check 'Recovery' 'Quick Machine Recovery' 'INFO' "cloud remediation state=$qmrCloud, auto remediation state=$qmrAuto (as reagentc /getrecoverysettings reports them; the switches are in Settings > System > Recovery > Quick machine recovery)"
}
}
# Microsoft's Secure Boot certificate update, as Windows records it (readable without
# elevation). An error is INFO in the first-logon snapshot: the update was queued minutes ago.
$sbServ = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing' -ErrorAction SilentlyContinue
$sbErr = $sbServ.UEFICA2023Error
$sbState = if ($sbErr) { if ($PreRestart) { 'INFO' } else { 'WARN' } } elseif ("$($sbServ.UEFICA2023Status)" -eq 'Updated' -or $sbServ.WindowsUEFICA2023Capable -eq 2) { 'PASS' } else { 'INFO' }
Add-Check 'Security' 'Secure Boot 2023 update: no error recorded' $sbState "UEFICA2023Status=$($sbServ.UEFICA2023Status) WindowsUEFICA2023Capable=$($sbServ.WindowsUEFICA2023Capable) (2 = 2023 certificate trusted and 2023 boot manager in use)$(if ($sbErr) { " UEFICA2023Error=0x$('{0:x}' -f [int64]$sbErr) - the firmware refused part of the update: install the newest BIOS from the PC maker's support site, restart twice and validate again; details are in Event Viewer > System, source TPM-WMI" } elseif ($sbState -eq 'INFO') { ' - not finished yet: it completes over restarts' })"
$dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$running = @($dg.SecurityServicesRunning)
Add-Check 'Security' 'VBS running' $(if ($dg.VirtualizationBasedSecurityStatus -eq 2) { 'PASS' } else { 'FAIL' }) "status=$($dg.VirtualizationBasedSecurityStatus)"
Add-Check 'Security' 'Memory integrity (HVCI)' $(if ($running -contains 2) { 'PASS' } else { 'FAIL' }) "running services: $($running -join ',')"
Add-Check 'Security' 'Secure Launch (baseline: configured)' 'INFO' "configured services: $(@($dg.SecurityServicesConfigured) -join ','), running: $($running -join ',') (3 = Secure Launch: configured by the baseline, runs only with firmware DRTM support; while configured Windows turns S3 sleep off$(if ($powerMode -eq 'hibernate') { ', which is fine because this image hibernates' } else { ' (the baseline disallows standby anyway)' }))"
Add-Check 'Security' 'Kernel-mode stack protection' $(if ($running -contains 5) { 'PASS' } else { 'WARN' }) 'enforced by the baseline (ConfigureKernelShadowStacksLaunch); to turn off for an incompatible game, change that policy - see docs/reference/SECURITY-BASELINE.md, "Baseline settings kept on purpose"'
$ppl = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL'
$pplBoot = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPLBoot'
Add-Check 'Security' 'LSA protection' $(if ($ppl -in 1, 2 -or $pplBoot -in 1, 2) { 'PASS' } else { 'WARN' }) "RunAsPPL=$ppl RunAsPPLBoot=$pplBoot (Windows enables it by default on clean installs)"
# Kernel DMA Protection needs the firmware to opt in (many desktops do). The accepted
# fallback for firmware that doesn't: IOMMU active (VBS lists DMA Protection) and no Thunderbolt/USB4
# controller, i.e. no external port with direct memory access. A DMA attack on the running PC would
# need the case opened.
function Get-DmaExposure {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $iommu = @($dg.AvailableSecurityProperties) -contains 3
    $ext = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -match 'Thunderbolt|USB4' -or @($_.CompatibleID) -match '^PCI\\CC_0C0340'
    } | ForEach-Object FriendlyName | Sort-Object -Unique)
    [pscustomobject]@{ Iommu = $iommu; External = $ext; Ok = ($iommu -and -not $ext.Count) }
}
$dmaGuard = try { [W11KitNative]::DmaGuard() } catch { -1 }
$dmaLine = "Kernel DMA Protection: $(if ($dmaGuard -eq 1) { 'On' } elseif ($dmaGuard -eq 0) { 'Off' } else { 'not readable' })"
if ($dmaGuard -eq 1) {
    Add-Check 'Security' 'DMA protection (BitLocker, running PC)' 'PASS' "$dmaLine"
} else {
    $x = Get-DmaExposure
    $detail = "$dmaLine (firmware doesn't opt in); IOMMU active=$($x.Iommu); Thunderbolt/USB4: $(if ($x.External.Count) { $x.External -join ', ' } else { 'none' })"
    # security.kernelDmaProtection 'recommended' (or no profile: 'required') makes a gap a WARN.
    $dmaGap = if ($hw -and "$($hw.security.kernelDmaProtection)" -eq 'recommended') { 'WARN' } else { 'FAIL' }
    $iommuHint = if ($hw -and $hw.firmwareHints -and $hw.firmwareHints.iommu) { " ($($hw.firmwareHints.iommu))" } else { '' }
    Add-Check 'Security' 'DMA protection (BitLocker, running PC)' $(if ($x.Ok) { 'PASS' } else { $dmaGap }) $(if ($x.Ok) { "$detail - no external DMA port" } else { "$detail - enable Kernel DMA Protection / IOMMU$iommuHint in the BIOS before BitLocker (the key is in RAM while the PC runs)" })
}
$pua = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'PUAProtection'
Add-Check 'Security' 'Defender PUA blocking' $(if ($pua -eq 1) { 'PASS' } else { 'WARN' }) "PUAProtection=$pua"
try {
    $mp = Get-MpPreference
    $asr = @{}; for ($i = 0; $i -lt @($mp.AttackSurfaceReductionRules_Ids).Count; $i++) { $asr[$mp.AttackSurfaceReductionRules_Ids[$i].ToLower()] = $mp.AttackSurfaceReductionRules_Actions[$i] }
    foreach ($rule in '56a863a9-875e-4185-98a7-b882c64b5ce5', '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2') {
        Add-Check 'Security' "ASR $rule" $(if ($asr[$rule] -eq 1) { 'PASS' } else { 'WARN' }) "action=$($asr[$rule]) (1=block)"
    }
} catch { Add-Check 'Security' 'ASR rules' 'WARN' 'Run elevated' }
# --- Microsoft Security Baseline + overrides ---------------------------------
# Applied = values that only the baseline sets are present (a log alone proves nothing)
$asrCount = @(Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules' -ErrorAction SilentlyContinue | ForEach-Object { $_.GetValueNames() }).Count
$minLen = $null; $lockN = $null; $lockMin = $null; $lockWin = $null; $minAge = $null
try {
    # The account policy as numbers (NetUserModalsGet; ages and lockout times are in seconds)
    $m0 = [W11KitNative]::Modals(0); $m3 = [W11KitNative]::Modals(3)
    if ($m0) { $minLen = "$($m0[0])"; $minAge = "$([int][math]::Floor($m0[2] / 86400))" }
    if ($m3) { $lockN = "$($m3[2])"; $lockMin = "$([int][math]::Floor($m3[0] / 60))"; $lockWin = "$([int][math]::Floor($m3[1] / 60))" }
} catch { }
$ssl0 = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'ShellSmartScreenLevel'
$sbOk = ($asrCount -ge 10) -and ($ssl0 -eq 'Block')
Add-Check 'Baseline' 'Microsoft Security Baseline applied' $(if ($sbOk) { 'PASS' } else { 'FAIL' }) "ASR rules=$asrCount, ShellSmartScreenLevel=$ssl0"
# Row name kept from before 2026-10-08: the threshold is still the baseline's 10, the duration
# and the counter reset are now 15 minutes (override, DISA STIG V-253297 / V-253299).
Add-Check 'Baseline' 'Account lockout 10 attempts / 15 minutes (baseline + STIG)' $(if ($lockN -eq '10' -and $lockMin -eq '15' -and $lockWin -eq '15') { 'PASS' } else { 'WARN' }) "threshold=$lockN duration=$lockMin min reset after $lockWin min (kit: 10 attempts / 15 / 15 min, DISA STIG; baseline 10 / 10 / 10. A second hardening tool that sets a shorter lockout can lock the only admin account out)"
$st = $null
try { $st = Get-Content -Raw 'C:\ProgramData\W11Kit\postinstall-status.json' -ErrorAction Stop | ConvertFrom-Json } catch { }
if ($st) {
    Add-Check 'Baseline' 'PostInstall finished cleanly' $(if ($st.critical) { 'FAIL' } elseif (@($st.failures).Count) { 'WARN' } else { 'PASS' }) $(if (@($st.failures).Count) { (@($st.failures) -join ' | ') } else { "finished $($st.finished)" })
} elseif (-not $PreRestart) {
    Add-Check 'Baseline' 'PostInstall finished cleanly' 'WARN' 'No postinstall-status.json'
}
$ssl = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'ShellSmartScreenLevel'
Add-Check 'Baseline' 'SmartScreen for apps = Block (baseline)' $(if ($ssl -eq 'Block') { 'PASS' } else { 'WARN' }) "ShellSmartScreenLevel=$ssl (unblock a trusted download with Unblock-File)"
$np = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection' 'EnableNetworkProtection'
Add-Check 'Baseline' 'Defender network protection (baseline)' $(if ($np -eq 1) { 'PASS' } else { 'WARN' }) "EnableNetworkProtection=$np"
$edgeSs = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SmartScreenEnabled'
$edgeIso = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SitePerProcess'
Add-Check 'Baseline' 'Edge security baseline applied' $(if ($edgeSs -eq 1 -and $edgeIso -eq 1) { 'PASS' } else { 'FAIL' }) "SmartScreenEnabled=$edgeSs SitePerProcess=$edgeIso"
# Every computer registry value of both baselines (the data in Baselines\), except those a
# later GPO, an override or a kit policy replaces: the merge Apply-Policy.ps1 applies (its
# -Mode Verify), read against the live registry.
try {
    $bv = & ([scriptblock]::Create([IO.File]::ReadAllText('C:\ProgramData\W11Kit\Apply-Policy.ps1'))) -Mode Verify -PowerMode $powerMode -Settings $kitSettings
    $perBl = (@($bv.PerBaseline.Keys) | ForEach-Object { "$_ $($bv.PerBaseline[$_])" }) -join ', '
    $bvDetail = "$($bv.Ok) of $($bv.Checked) values in effect ($perBl); $($bv.Replaced) replaced by a later GPO, an override or a kit policy$(if ($bv.Skipped) { "; $($bv.Skipped) not checkable" })"
    if (@($bv.Wrong).Count) { $bvDetail += "; $(@($bv.Wrong).Count) not in effect, e.g. " + ((@($bv.Wrong) | Select-Object -First 5) -join '; ') }
    if (@($bv.Warnings).Count) { $bvDetail += "; $(@($bv.Warnings) -join '; ')" }
    Add-Check 'Baseline' 'Baseline: every policy value in effect' $(if (@($bv.Wrong).Count -or -not $bv.Checked) { 'FAIL' } else { 'PASS' }) $bvDetail
} catch { Add-Check 'Baseline' 'Baseline: every policy value in effect' 'FAIL' "C:\ProgramData\W11Kit\Apply-Policy.ps1 -Mode Verify: $($_.Exception.Message)" }
# The same for the kit's own layers: every computer value the overrides and the kit's
# policies put into local Group Policy (Apply-Policy.ps1 -Mode ListExpected: the merged
# set, nothing read or written), against the live registry. Plain numbers and text are
# compared; delete markers and other types are counted as not compared.
try {
    $le = & ([scriptblock]::Create([IO.File]::ReadAllText('C:\ProgramData\W11Kit\Apply-Policy.ps1'))) -Mode ListExpected -PowerMode $powerMode -Settings $kitSettings
    $kitRecs = @($le.Machine | Where-Object { "$($_.Source)" -notlike 'baseline:*' })
    $kpOk = 0; $kpSkip = 0; $kpWrong = New-Object System.Collections.Generic.List[string]
    $hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    try {
        foreach ($r in $kitRecs) {
            if ("$($r.ValueName)".StartsWith('**') -or "$($r.Type)" -notin 'REG_DWORD', 'REG_SZ') { $kpSkip++; continue }
            $live = $null
            try { $k = $hklm64.OpenSubKey("$($r.Key)"); if ($k) { try { $live = $k.GetValue("$($r.ValueName)", $null, 'DoNotExpandEnvironmentNames') } finally { $k.Close() } } } catch { $kpSkip++; continue }
            $liveText = if ($null -eq $live) { $null } elseif ("$($r.Type)" -eq 'REG_DWORD') { try { "$([uint32]([int64]$live -band 0xFFFFFFFFL))" } catch { "$live" } } else { "$live" }
            if ($null -ne $liveText -and $liveText -ceq "$($r.Value)") { $kpOk++ } else { $kpWrong.Add("HKLM\$($r.Key)\$($r.ValueName): want $($r.Value), found $(if ($null -eq $liveText) { '<absent>' } else { $liveText })") }
        }
    } finally { $hklm64.Close() }
    # User-side policies (a handful) apply per account at its sign-in: counted, not compared
    $kpUser = @($le.User | Where-Object { "$($_.Source)" -notlike 'baseline:*' }).Count
    $kpDetail = "$kpOk of $($kpOk + $kpWrong.Count) computer values in effect$(if ($kpSkip) { "; $kpSkip not compared (delete markers, other types)" })$(if ($kpUser) { "; $kpUser per-user policy value(s) not compared (they apply to each account at sign-in)" })"
    if ($kpWrong.Count) { $kpDetail += "; $($kpWrong.Count) not in effect, e.g. " + ((@($kpWrong) | Select-Object -First 5) -join '; ') + ' - something changed them (another tool, a manual edit). Re-apply the kit''s policies: docs/reference/SECURITY-BASELINE.md, "Changing a setting later"' }
    Add-Check 'Override' 'Overrides and kit policies: every value in effect' $(if ($kpWrong.Count -or -not $kitRecs.Count) { 'WARN' } else { 'PASS' }) $kpDetail
} catch { Add-Check 'Override' 'Overrides and kit policies: every value in effect' 'WARN' "C:\ProgramData\W11Kit\Apply-Policy.ps1 -Mode ListExpected: $($_.Exception.Message)" }
$extBlock = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist' '1'
$nmh = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'NativeMessagingUserLevelHosts'
Add-Check 'Override' 'Edge extensions allowed (store + desktop-app integration)' $(if ($extBlock -ne '*' -and $nmh -ne 0) { 'PASS' } else { 'FAIL' }) "ExtensionInstallBlocklist[1]=$extBlock NativeMessagingUserLevelHosts=$nmh"
$aam = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'TypeOfAdminApprovalMode'
Add-Check 'Override' 'Administrator protection off (legacy Admin Approval Mode)' $(if ($aam -eq 1) { 'PASS' } else { 'FAIL' }) "TypeOfAdminApprovalMode=$aam (baseline 2 = Administrator protection: elevation then runs as a separate hidden account)"
$shadow = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { (Split-Path $_.LocalPath -Leaf) -like 'ADMIN_*' })
Add-Check 'Override' 'No Administrator-protection shadow accounts' $(if (-not $shadow.Count) { 'PASS' } else { 'WARN' }) (($shadow | ForEach-Object LocalPath) -join '; ')
Add-Check 'Override' 'Minimum password length 11' $(if ($minLen -eq '11') { 'PASS' } else { 'FAIL' }) "account policy: $minLen (baseline 14)"
$enumAdm = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\CredUI' 'EnumerateAdministrators'
Add-Check 'Override' 'UAC prompt lists the admin account' $(if ($enumAdm -eq 1) { 'PASS' } else { 'FAIL' }) "EnumerateAdministrators=$enumAdm (baseline 0)"
$sslOv = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SSLErrorOverrideAllowed'
Add-Check 'Override' 'Edge allows proceeding past certificate errors' $(if ($sslOv -eq 1) { 'PASS' } else { 'FAIL' }) "SSLErrorOverrideAllowed=$sslOv (baseline 0; self-signed LAN services)"
$cpu = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorUser'
Add-Check 'Override' 'Standard user gets an admin credential prompt' $(if ($cpu -eq 1) { 'PASS' } else { 'FAIL' }) "ConsentPromptBehaviorUser=$cpu (baseline 0 = auto-deny)"
$rdv = Reg 'HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE' 'RDVDenyWriteAccess'
Add-Check 'Override' 'USB drives writable' $(if ($rdv -ne 1) { 'PASS' } else { 'FAIL' }) "RDVDenyWriteAccess=$rdv"
$hv = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard' 'HypervisorEnforcedCodeIntegrity'
Add-Check 'Override' 'HVCI policy without UEFI lock' $(if ($hv -eq 2) { 'PASS' } else { 'FAIL' }) "HypervisorEnforcedCodeIntegrity=$hv"
$hvLocked = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Locked'
Add-Check 'Override' 'HVCI not UEFI-locked' $(if ($hvLocked -ne 1) { 'PASS' } else { 'WARN' }) "Locked=$hvLocked (1 = locked in firmware, e.g. left by an earlier Windows install)"
$pplPol = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'RunAsPPL'
Add-Check 'Override' 'LSA protection without UEFI lock' $(if ($pplPol -eq 2) { 'PASS' } else { 'WARN' }) "policy RunAsPPL=$pplPol"
$asrPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules'
foreach ($r in @(@('33ddedf1-c6e0-47cb-833e-de6133960387', 'Block rebooting in Safe Mode'), @('c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb', 'Block copied or impersonated system tools'))) {
    $v = Reg $asrPol $r[0]
    Add-Check 'Override' "ASR rule: $($r[1])" $(if ("$v" -eq '1') { 'PASS' } else { 'FAIL' }) "policy $($r[0])=$v (1 = Block; added to the baseline's 15)"
}
$ssc = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' 'SubmitSamplesConsent'
Add-Check 'Override' 'Defender sends safe samples only' $(if ($ssc -eq 1) { 'PASS' } else { 'WARN' }) "SubmitSamplesConsent=$ssc"
# The Xbox services: the baseline disables them; the kit's override (Manual) is staged only
# with options.gamingTweaks. Without it the baseline's value stands and the rows only report.
foreach ($svc in 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') {
    $x = Get-Service $svc -ErrorAction SilentlyContinue
    if ($optGaming) { Add-Check 'Override' "Xbox service $svc usable" $(if ($x -and $x.StartType -ne 'Disabled') { 'PASS' } else { 'FAIL' }) "$($x.StartType)" }
    else { Add-Check 'Override' "Xbox service $svc" 'INFO' "$($x.StartType) (the baseline's value is Disabled; the kit makes it usable only with options.gamingTweaks in the settings)" }
}
# --- DISA Windows 11 STIG V2R11 additions (docs/reference/SECURITY-BASELINE.md, "DISA STIG additions") -----
Add-Check 'STIG' 'Minimum password age 1 day' $(if ($minAge -eq '1') { 'PASS' } else { 'WARN' }) "account policy: $minAge day(s) (V-253302; an admin can still reset a password at any time)"
$stigReg = @(
    @('HKLM:\SOFTWARE\Policies\Microsoft\FVE', 'MinimumPIN', 6),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}', 'NoGPOListChanges', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers', 'DisableHTTPPrinting', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'DontDisplayNetworkSelectionUI', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat', 'DisableInventory', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode', 0),
    @('HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork', 'RequireSecurityDevice', 1),
    @('HKLM:\SOFTWARE\Policies\Microsoft\PassportForWork\PINComplexity', 'MinimumPINLength', 6),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy', 'LetAppsActivateWithVoice', 2),
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters', 'SupportedEncryptionTypes', 2147483640),
    @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\EventLog\Security', 'MaxSize', 1048576),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest', 'UseLogonCredential', 0),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\pku2u', 'AllowOnlineID', 0),
    @('HKLM:\SOFTWARE\Classes\batfile\shell\runasuser', 'SuppressionPolicy', 4096),
    @('HKLM:\SOFTWARE\Classes\cmdfile\shell\runasuser', 'SuppressionPolicy', 4096),
    @('HKLM:\SOFTWARE\Classes\exefile\shell\runasuser', 'SuppressionPolicy', 4096),
    @('HKLM:\SOFTWARE\Classes\mscfile\shell\runasuser', 'SuppressionPolicy', 4096))
$stigBad = @(foreach ($r in $stigReg) { $v = Reg $r[0] $r[1]; if ("$v" -ne "$($r[2])") { "$(Split-Path $r[0] -Leaf)\$($r[1])=$v (want $($r[2]))" } })
Add-Check 'STIG' "Registry values ($($stigReg.Count): Kerberos AES, WDigest, PKU2U, Hello PIN, Delivery Optimization, log size, ...)" $(if ($stigBad.Count) { 'WARN' } else { 'PASS' }) $(if ($stigBad.Count) { $stigBad -join '; ' } else { 'all as set by Set-KitRegistry.ps1 (Security log 1 GB, Delivery Optimization HTTP only, no Run as different user)' })
$seclogon = Get-Service seclogon -ErrorAction SilentlyContinue
if ($optGaming) { Add-Check 'STIG' 'Secondary Logon service' 'INFO' "$(if ($seclogon) { "$($seclogon.StartType), $($seclogon.Status)" } else { 'not present' }) (V-253289 wants Disabled; the kit leaves it Manual with options.gamingTweaks: some game launchers need it)" }
else { Add-Check 'STIG' 'Secondary Logon service disabled' $(if (-not $seclogon -or "$($seclogon.StartType)" -eq 'Disabled') { 'PASS' } else { 'WARN' }) "$(if ($seclogon) { "$($seclogon.StartType), $($seclogon.Status)" } else { 'not present' }) (V-253289: Run as different user / runas off; UAC elevation is unaffected)" }
# Built-in Administrator (RID 500) and Guest (RID 501): renamed (names from the staged .inf) and disabled
$infText = try { [IO.File]::ReadAllText('C:\ProgramData\W11Kit\baseline-overrides.inf') } catch { '' }
# Every service the staged overrides disable ([Service General Setting], start type 4),
# so a service added there is checked without a row of its own. Not on this PC = fine.
$infSvcOff = @(if ($infText -match '(?ms)^\[Service General Setting\]\s*$(.*?)(?=^\[|\z)') { [regex]::Matches($Matches[1], '(?m)^\s*"?([^",\r\n]+)"?\s*,\s*4\s*,') | ForEach-Object { $_.Groups[1].Value.Trim() } })
if ($infSvcOff.Count) {
    $svcOn = @(foreach ($n in $infSvcOff) { $x = Get-Service -Name $n -ErrorAction SilentlyContinue; if ($x -and "$($x.StartType)" -ne 'Disabled') { "$n is $($x.StartType) ($($x.Status))" } })
    Add-Check 'Override' "Services the kit disables ($($infSvcOff.Count))" $(if ($svcOn.Count) { 'WARN' } else { 'PASS' }) $(if ($svcOn.Count) { "$($svcOn -join '; ') - something turned it back on. Disable it again in an administrator PowerShell: Set-Service <name> -StartupType Disabled; Stop-Service <name> (why each is off: docs/reference/SECURITY-BASELINE.md, 'Network exposure, sign-in and monitoring')" } else { "disabled or not present: $($infSvcOff -join ', ')" })
}
$wantAdm = if ($infText -match '(?m)^\s*NewAdministratorName\s*=\s*"?([^"\r\n]+)"?') { $Matches[1].Trim() } else { $null }
$wantGst = if ($infText -match '(?m)^\s*NewGuestName\s*=\s*"?([^"\r\n]+)"?') { $Matches[1].Trim() } else { $null }
$builtin = @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { "$($_.SID)" -match '-50[01]$' })
$b500 = $builtin | Where-Object { "$($_.SID)" -match '-500$' }; $b501 = $builtin | Where-Object { "$($_.SID)" -match '-501$' }
$renOk = $b500 -and $b501 -and $b500.Name -ne 'Administrator' -and $b501.Name -ne 'Guest' -and (-not $wantAdm -or $b500.Name -eq $wantAdm) -and (-not $wantGst -or $b501.Name -eq $wantGst) -and -not $b500.Enabled -and -not $b501.Enabled
Add-Check 'STIG' 'Built-in Administrator and Guest renamed and disabled' $(if ($renOk) { 'PASS' } else { 'WARN' }) "RID 500: $($b500.Name) enabled=$($b500.Enabled); RID 501: $($b501.Name) enabled=$($b501.Enabled) (expected $wantAdm / $wantGst, disabled; V-253435 / V-253436)"
# Every security option the staged overrides set ([Registry Values], MACHINE\<key>\<value>=4,<number>),
# e.g. the UAC values and NTLM auditing: checked from the data, like the services above.
$infReg = @(if ($infText -match '(?ms)^\[Registry Values\]\s*$(.*?)(?=^\[|\z)') { [regex]::Matches($Matches[1], '(?m)^\s*MACHINE\\(.+)\\([^\\=]+?)\s*=\s*4\s*,\s*(\d+)\s*$') | ForEach-Object { [pscustomobject]@{ Key = $_.Groups[1].Value; Name = $_.Groups[2].Value; Want = $_.Groups[3].Value } } })
if ($infReg.Count) {
    $infRegBad = @(foreach ($r in $infReg) { $v = Reg "HKLM:\$($r.Key)" $r.Name; if ("$v" -ne $r.Want) { "$(Split-Path $r.Key -Leaf)\$($r.Name)=$v (want $($r.Want))" } })
    Add-Check 'Override' "Security options the kit sets ($($infReg.Count))" $(if ($infRegBad.Count) { 'WARN' } else { 'PASS' }) $(if ($infRegBad.Count) { "$($infRegBad -join '; ') - something changed them. Re-apply the kit's policies: docs/reference/SECURITY-BASELINE.md, ""Changing a setting later""" } else { "as set: $(($infReg | ForEach-Object { "$($_.Name)=$($_.Want)" }) -join ', ') (NTLM is audited, not blocked)" })
}
# Two hardening values outside the policy keys (set in the image by Set-KitRegistry.ps1):
# no automatic proxy discovery (WPAD), and the strict Authenticode signature check
# (CVE-2013-3900) for 64-bit and 32-bit programs (any non-zero value counts).
$wpad = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' 'DisableWpad'
$pad64 = Reg 'HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config' 'EnableCertPaddingCheck'
$pad32 = Reg 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config' 'EnableCertPaddingCheck'
$hardOk = ("$wpad" -eq '1') -and ("$pad64" -match '^[1-9]') -and ("$pad32" -match '^[1-9]')
Add-Check 'Override' 'WPAD off and strict signature check on' $(if ($hardOk) { 'PASS' } else { 'WARN' }) "DisableWpad=$wpad; EnableCertPaddingCheck=$pad64 (64-bit) / $pad32 (32-bit)$(if (-not $hardOk) { ' - set them again in an administrator PowerShell: powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\PostInstall.ps1 -NoRestart (the first-boot setup; safe to repeat)' })"
# Wi-Fi Direct virtual adapters (V-288475): none at all = INFO (no Wi-Fi hardware, e.g. a VM)
$wfd = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object InterfaceDescription -like 'Microsoft Wi-Fi Direct Virtual Adapter*')
# 'Not Present': the adapter's Wi-Fi device is gone or off, so it can't host anything either
$wfdOn = @($wfd | Where-Object { "$($_.Status)" -notin 'Disabled', 'Not Present' })
Add-Check 'STIG' 'Wi-Fi Direct adapters disabled (no hotspot / casting)' $(if (-not $wfd.Count) { 'INFO' } elseif ($wfdOn.Count) { 'WARN' } else { 'PASS' }) $(if (-not $wfd.Count) { 'no Wi-Fi Direct adapter on this PC (no Wi-Fi hardware, e.g. a VM)' } else { "$(($wfd | ForEach-Object { "$($_.InterfaceDescription): $($_.Status)" }) -join '; ')$(if ($wfdOn.Count) { ' - a Wi-Fi driver update can re-create it: Get-NetAdapter -IncludeHidden ''Microsoft Wi-Fi Direct*'' | Disable-NetAdapter (elevated)' })" })
if (-not $isAdmin) {
    Add-Check 'STIG' 'Audit policy / logon rights / browser block for administrators' 'WARN' 'Not elevated - re-run as administrator for these checks'
} else {
    # Advanced audit policy, read back by GUID and numeric value (auditpol /backup; the
    # /get text is localized): the DISA STIG additions, and the baseline's own rows kept.
    $live = @{}; $auditTmp = Join-Path $env:TEMP "w11kit-auditpol-$PID.csv"
    & auditpol.exe /backup "/file:$auditTmp" 2>&1 | Out-Null
    foreach ($l in @(Get-Content -LiteralPath $auditTmp -ErrorAction SilentlyContinue | Select-Object -Skip 1)) {
        $f = "$l" -split ','
        if ($f.Count -ge 7 -and $f[3] -match '^\{[0-9a-fA-F-]+\}$' -and $f[6] -match '^\d+$') { $live[$f[3].ToLowerInvariant()] = [int]$f[6] }
    }
    Remove-Item -LiteralPath $auditTmp -ErrorAction SilentlyContinue
    function Compare-AuditRows([string[]]$Files) {
        foreach ($p in $Files) {
            foreach ($r in @(Import-Csv -LiteralPath $p -ErrorAction Stop)) {
                $g = "$($r.'Subcategory GUID')".ToLowerInvariant(); $want = [int]$r.'Setting Value'
                if (-not $g) { continue }
                $have = if ($live.ContainsKey($g)) { $live[$g] } else { 0 }
                [pscustomobject]@{ Name = $r.Subcategory; Want = $want; Have = $have; Ok = (($have -band $want) -eq $want) }
            }
        }
    }
    $auditVal = { param($v) switch ($v) { 0 { 'none' } 1 { 'S' } 2 { 'F' } 3 { 'S+F' } default { "$v" } } }
    if (-not $live.Count) {
        Add-Check 'STIG' 'Audit policy: DISA STIG subcategories' 'WARN' "auditpol /backup returned nothing (exit code $LASTEXITCODE)"
    } else {
        try {
            $add = @(Compare-AuditRows @('C:\ProgramData\W11Kit\baseline-overrides-audit.csv'))
            $miss = @($add | Where-Object { -not $_.Ok })
            Add-Check 'STIG' 'Audit policy: DISA STIG subcategories' $(if (-not $add.Count -or $miss.Count) { 'WARN' } else { 'PASS' }) $(if ($miss.Count) { 'missing: ' + (($miss | ForEach-Object { "$($_.Name) has $(& $auditVal $_.Have), want $(& $auditVal $_.Want)" }) -join '; ') } else { "$($add.Count) subcategories ($(($add | ForEach-Object { "$($_.Name -replace '^Audit ', '') $(& $auditVal $_.Want)" }) -join ', '))" })
        } catch { Add-Check 'STIG' 'Audit policy: DISA STIG subcategories' 'WARN' "baseline-overrides-audit.csv not readable: $($_.Exception.Message)" }
        $baseCsv = @(Get-ChildItem 'C:\ProgramData\W11Kit\Baselines' -Recurse -File -Filter 'audit.csv' -ErrorAction SilentlyContinue | ForEach-Object FullName)
        try {
            $base = @(if ($baseCsv.Count) { Compare-AuditRows $baseCsv })
            $miss = @($base | Where-Object { -not $_.Ok })
            Add-Check 'STIG' "Audit policy: the baseline's subcategories kept" $(if (-not $base.Count -or $miss.Count) { 'WARN' } else { 'PASS' }) $(if (-not $base.Count) { 'baseline audit.csv not found under C:\ProgramData\W11Kit\Baselines' } elseif ($miss.Count) { 'lost: ' + (($miss | ForEach-Object { "$($_.Name) has $(& $auditVal $_.Have), want $(& $auditVal $_.Want)" }) -join '; ') } else { "all $($base.Count) baseline rows in effect (merged with the additions, not replaced)" })
        } catch { Add-Check 'STIG' "Audit policy: the baseline's subcategories kept" 'WARN' $_.Exception.Message }
    }
    # Deny-logon rights: the baseline's entries + Guests (secedit export, by SID)
    $seTmp = Join-Path $env:TEMP "w11kit-rights-$PID.inf"
    & secedit.exe /export /areas USER_RIGHTS /cfg $seTmp /quiet 2>&1 | Out-Null
    $rights = @{}
    foreach ($l in @(Get-Content -LiteralPath $seTmp -ErrorAction SilentlyContinue)) { if ("$l" -match '^\s*(Se\w+)\s*=\s*(.*)$') { $rights[$Matches[1]] = @($Matches[2] -split ',' | ForEach-Object { $_.Trim() }) } }
    Remove-Item -LiteralPath $seTmp -ErrorAction SilentlyContinue
    $wantRights = [ordered]@{ SeDenyNetworkLogonRight = @('*S-1-5-113', '*S-1-5-32-546'); SeDenyInteractiveLogonRight = @('*S-1-5-32-546'); SeDenyRemoteInteractiveLogonRight = @('*S-1-5-113', '*S-1-5-32-546') }
    $rightsBad = @(foreach ($k in $wantRights.Keys) { $missing = @($wantRights[$k] | Where-Object { @($rights[$k]) -notcontains $_ }); if ($missing.Count) { "$k lacks $($missing -join ',')" } })
    Add-Check 'STIG' 'Deny logon rights: local accounts (network, RDP) and Guests' $(if (-not $rights.Count -or $rightsBad.Count) { 'WARN' } else { 'PASS' }) $(if (-not $rights.Count) { "secedit /export returned nothing (exit code $LASTEXITCODE)" } elseif ($rightsBad.Count) { $rightsBad -join '; ' } else { (($wantRights.Keys | ForEach-Object { "$_=$(@($rights[$_]) -join ',')" }) -join '; ') + ' (S-1-5-113 = local account, S-1-5-32-546 = Guests)' })
    # Administrators can't run web browsers (AppLocker; V-253294, CAT I): the effective
    # policy, its decision for the admin and the daily account, and the AppID service.
    try {
        $eff = [xml](Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop)
        $exe = @($eff.AppLockerPolicy.RuleCollection | Where-Object { $_.Type -eq 'Exe' }) | Select-Object -First 1
        $denies = @(if ($exe) { $exe.ChildNodes | Where-Object { $_.Action -eq 'Deny' -and "$($_.Name)" -like 'W11Kit: no *' } })
        $edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        $wv2 = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\EdgeWebView\Application\*\msedgewebview2.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        $pol = Get-AppLockerPolicy -Effective -ErrorAction Stop
        $dec = { param($path, $user) if ($path -and $user -and (Test-Path -LiteralPath $path)) { try { "$((Test-AppLockerPolicy -PolicyObject $pol -Path $path -User $user -ErrorAction Stop).PolicyDecision)" } catch { "error: $($_.Exception.Message)" } } else { 'n/a' } }
        $admEdge = & $dec $edge $bo.AdminName; $usrEdge = & $dec $edge $bo.UserName; $admWv = & $dec $wv2.FullName $bo.AdminName
        # Packaged apps must stay allowed: enforced Exe rules without an Appx rule deny every
        # packaged app (Start, Settings, Store, Terminal, WSL) to every user
        $calc = Get-AppxPackage -AllUsers -Name Microsoft.WindowsCalculator -ErrorAction SilentlyContinue | Select-Object -First 1
        # -Packages works only with -XmlPolicy (not -PolicyObject): test against the effective policy as a file
        $usrAppx = if ($calc -and $bo.UserName) {
            $alXml = Join-Path $env:TEMP "w11kit-applocker-$PID.xml"
            try { $eff.Save($alXml); "$((Test-AppLockerPolicy -XmlPolicy $alXml -Packages $calc -User $bo.UserName -ErrorAction Stop).PolicyDecision)" }
            catch { "error: $($_.Exception.Message)" }
            finally { Remove-Item -LiteralPath $alXml -ErrorAction SilentlyContinue }
        } else { 'n/a' }
        $appId = Get-Service AppIDSvc -ErrorAction SilentlyContinue
        $lang = "$($ExecutionContext.SessionState.LanguageMode)"
        $policyOk = $exe -and "$($exe.EnforcementMode)" -eq 'Enabled' -and $denies.Count -ge 4 -and $admEdge -like 'Denied*' -and $usrEdge -notlike 'Denied*' -and $admWv -notlike 'Denied*' -and $usrAppx -notlike 'Denied*' -and $usrAppx -notlike 'error*' -and $lang -eq 'FullLanguage'
        $alState = if (-not $policyOk) { 'FAIL' } elseif ("$($appId.Status)" -ne 'Running') { 'WARN' } else { 'PASS' }
        Add-Check 'STIG' 'Administrators cannot run web browsers (AppLocker)' $alState "Exe rules $(if ($exe) { $exe.EnforcementMode } else { 'absent' }), $($denies.Count) kit deny rules; msedge.exe for $($bo.AdminName): $admEdge, for $($bo.UserName): $usrEdge; msedgewebview2.exe for $($bo.AdminName): $admWv; packaged apps (Calculator) for $($bo.UserName): $usrAppx; AppIDSvc $($appId.Status) $($appId.StartType) (must run for enforcement); PowerShell $lang (V-253294)"
    } catch { Add-Check 'STIG' 'Administrators cannot run web browsers (AppLocker)' 'FAIL' "AppLocker policy not readable: $($_.Exception.Message)" }
}
$wuPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$trv = Reg $wuPol 'TargetReleaseVersionInfo'
Add-Check 'Updates' 'Feature version pinned to the image (rebuild to move)' $(if ((Reg $wuPol 'TargetReleaseVersion') -eq 1 -and $trv -eq $cv.DisplayVersion) { 'PASS' } else { 'WARN' }) "TargetReleaseVersionInfo=$trv, running $($cv.DisplayVersion)"
# The pin keeps this PC on the image's feature version: say so before Microsoft stops
# updating that version (image.json featureVersion; Home and Pro dates).
$fv = if ($image) { $image.featureVersion } else { $null }
if ($fv -and $fv.endOfServicing -and $cv.DisplayVersion -eq $fv.version) {
    $fvEnd = [datetime]::ParseExact($fv.endOfServicing, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $fvDays = [int][math]::Floor(($fvEnd - (Get-Date).Date).TotalDays)
    $fvHow = 'build an ISO from a newer kit and reinstall, or lift the pin (docs/MONTHLY.md, "When this Windows version nears its end")'
    if ($fvDays -lt 0) { Add-Check 'Updates' 'Feature version still gets security updates' 'FAIL' "Windows 11 $($fv.version) Pro got its last update on $($fv.endOfServicing): $fvHow" }
    elseif ($fvDays -le 90) { Add-Check 'Updates' 'Feature version still gets security updates' 'WARN' "Windows 11 $($fv.version) Pro gets updates until $($fv.endOfServicing), $fvDays days from now: $fvHow" }
    else { Add-Check 'Updates' 'Feature version still gets security updates' 'PASS' "Windows 11 $($fv.version) Pro, until $($fv.endOfServicing)" }
} else {
    Add-Check 'Updates' 'Feature version still gets security updates' 'INFO' "running $($cv.DisplayVersion); the image's facts name $(if ($fv) { $fv.version } else { 'no version' }): see Microsoft's Windows 11 release information for its end date"
}
$wuDrv = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate'
# settings options.windowsUpdateDrivers: either value is a choice; the row checks the chosen one
$wuDrvWanted = if ((Get-Setting 'options.windowsUpdateDrivers') -eq $true) { 0 } else { 1 }
Add-Check 'Updates' $(if ($wuDrvWanted -eq 1) { 'Drivers not delivered by Windows Update' } else { 'Drivers and firmware from Windows Update (settings options.windowsUpdateDrivers)' }) $(if ($wuDrv -eq $wuDrvWanted) { 'PASS' } else { 'FAIL' }) "ExcludeWUDriversInQualityUpdate=$wuDrv (wanted $wuDrvWanted)"
$optUpdWanted = "$(Get-Setting 'options.optionalUpdates')"; if (-not $optUpdWanted) { $optUpdWanted = 'off' }
$aoc = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'AllowOptionalContent'
$aocWanted = @{ off = $null; auto = 1; userChoice = 3 }[$optUpdWanted]
Add-Check 'Updates' "Optional updates: $optUpdWanted (settings options.optionalUpdates)" $(if ("$aoc" -eq "$aocWanted") { 'PASS' } else { 'WARN' }) "AllowOptionalContent=$aoc"
# Defender's ransomware protection (settings options.controlledFolderAccess / asrPrevalenceRule).
# Off while a build paused it: the build restores it, or the next build or Run-Prepare.cmd does.
try {
    $mp = Get-MpPreference -ErrorAction Stop
    $cfaWanted = (Get-Setting 'options.controlledFolderAccess') -ne $false
    $cfaNow = [int]$mp.EnableControlledFolderAccess
    Add-Check 'Security' "Controlled Folder Access $(if ($cfaWanted) { 'on' } else { 'off' }) (settings options.controlledFolderAccess)" $(if (($cfaWanted -and $cfaNow -eq 1) -or (-not $cfaWanted -and $cfaNow -ne 1)) { 'PASS' } else { 'WARN' }) "EnableControlledFolderAccess=$cfaNow (1 = on)$(if ($cfaWanted -and $cfaNow -ne 1) { ' - turn it on again: Set-MpPreference -EnableControlledFolderAccess Enabled (as administrator); a build that was stopped may have left it paused' })"
    $prevWanted = "$(Get-Setting 'options.asrPrevalenceRule')"; if (-not $prevWanted) { $prevWanted = 'block' }
    $pIds = @($mp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() }); $pi = [array]::IndexOf($pIds, '01443614-cd74-433a-b99e-2ecdc07bfc25')
    $prevNow = if ($pi -ge 0) { [int]@($mp.AttackSurfaceReductionRules_Actions)[$pi] } else { 0 }
    $prevOk = @{ block = 1; audit = 2; off = 0 }[$prevWanted] -eq $prevNow
    Add-Check 'Security' "ASR prevalence rule: $prevWanted (settings options.asrPrevalenceRule)" $(if ($prevOk) { 'PASS' } else { 'WARN' }) "action=$prevNow (1 = block, 2 = audit, 0 = off)"
} catch { Add-Check 'Security' 'Controlled Folder Access / ASR prevalence rule' 'WARN' 'Not readable - run elevated' }
# Paths the two ASR reputation rules let run (settings options.asrExclusions; Set-KitRegistry.ps1)
$asrExWanted = (@(Get-Setting 'options.asrExclusions' | Where-Object { $_ } | ForEach-Object { "$_" })) -join '>'
if (-not $isAdmin) { Add-Check 'Security' 'ASR exceptions (settings options.asrExclusions)' 'INFO' "Not checked: Defender's policy keys are readable by administrators only (run elevated). Wanted: $(if ($asrExWanted) { $asrExWanted.Replace('>', '; ') } else { 'none' })" }
else {
    $asrExKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\ASROnlyPerRuleExclusions'
    # The baseline's HideExclusionsFromLocalAdmins makes the key unreadable even to administrators
    $asrExHidden = $false
    try { $null = (Get-Item -LiteralPath $asrExKey -ErrorAction Stop).GetValueNames() } catch { $asrExHidden = Test-Path -LiteralPath $asrExKey }
    $asrExNow = @(foreach ($g in '01443614-cd74-433a-b99e-2ecdc07bfc25', 'c1db55ab-c21a-4637-bb3f-a12568109d35') { "$(Reg $asrExKey $g)" })
    $asrExOk = -not @($asrExNow | Where-Object { $_ -ne $asrExWanted }).Count
    if ($asrExHidden) { Add-Check 'Security' 'ASR exceptions (settings options.asrExclusions)' 'INFO' "Not checked: Defender hides its exclusions here even from administrators (the baseline's HideExclusionsFromLocalAdmins). Wanted: $(if ($asrExWanted) { $asrExWanted.Replace('>', '; ') } else { 'none' })" }
    else { Add-Check 'Security' 'ASR exceptions (settings options.asrExclusions)' $(if ($asrExOk) { 'PASS' } else { 'WARN' }) $(if ($asrExOk -and $asrExWanted) { "the prevalence and ransomware rules let these run: $($asrExWanted.Replace('>', '; ')) (every other ASR rule still covers them)" } elseif ($asrExOk) { 'none' } else { "prevalence rule: '$($asrExNow[0])', ransomware rule: '$($asrExNow[1])' (wanted '$asrExWanted'; '>' separates paths)" }) }
}
# Network categories (settings options.firstNetworkCategory): on Public the baseline ignores the
# firewall rules that apps add themselves (AllowLocalPolicyMerge = 0); a network met later is Public
$ncWanted = "$(Get-Setting 'options.firstNetworkCategory')"; if (-not $ncWanted) { $ncWanted = 'public' }
$ncp = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
Add-Check 'Network' "Network categories (settings options.firstNetworkCategory: $ncWanted)" 'INFO' $(if ($ncp.Count) { "$(($ncp | ForEach-Object { "$($_.Name) on $($_.InterfaceAlias): $($_.NetworkCategory)" }) -join '; ')$(if (@($ncp | Where-Object { "$($_.NetworkCategory)" -eq 'Public' }).Count) { ' - on Public, firewall rules that apps add themselves have no effect: for a network you trust, Settings > Network & internet > the connection > Network profile type: Private' })" } else { 'no network connection' })
if ("$(Get-Setting 'options.netbios')" -eq 'off') {
    $nbOn = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue | Where-Object { $_.GetValue('NetbiosOptions') -ne 2 } | ForEach-Object PSChildName)
    Add-Check 'Network' 'NetBIOS over TCP/IP off (settings options.netbios)' $(if ($nbOn.Count) { 'WARN' } else { 'PASS' }) $(if ($nbOn.Count) { "still on for: $($nbOn -join ', ') (an adapter added after setup) - in an administrator PowerShell: Get-ChildItem HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces | ForEach-Object { Set-ItemProperty `$_.PSPath NetbiosOptions 2 }" } else { 'NetbiosOptions=2 on every interface' })
}
if ("$(Get-Setting 'options.dns.overHttps')" -eq 'require') {
    $want = @(Get-Setting 'options.dns.servers' | ForEach-Object { "$($_.address)" })
    $dohBad = @($want | Where-Object { $d = Get-DnsClientDohServerAddress -ServerAddress $_ -ErrorAction SilentlyContinue; -not $d -or $d.AllowFallbackToUdp })
    $nicBad = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $cur = @((Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue).ServerAddresses); @($cur | Where-Object { $want -notcontains $_ }).Count -or -not $cur.Count } | ForEach-Object Name)
    $zones = @(Get-Setting 'options.dns.localZones' | ForEach-Object { "$($_.namespace)" })
    $nrpt = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | ForEach-Object { @($_.Namespace) })
    $zoneBad = @($zones | Where-Object { $nrpt -notcontains $_ })
    Add-Check 'Network' 'DNS over HTTPS only, local zones by their own servers (settings options.dns)' $(if ($dohBad.Count -or $nicBad.Count -or $zoneBad.Count) { 'WARN' } else { 'PASS' }) $(if ($dohBad.Count -or $nicBad.Count -or $zoneBad.Count) { "not DoH-only: $($dohBad -join ', '); adapters with other DNS servers: $($nicBad -join ', '); zones without a rule: $($zoneBad -join ', ') (an adapter added after setup gets its router's DNS: set the servers again)" } else { "servers $($want -join ', ') DoH-only on every physical adapter; local zones: $($zones -join ', ')" })
}
$drvSearch = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'SearchOrderConfig'
$devMeta = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork'
$dontSearch = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'DontSearchWindowsUpdate'
$dontPrompt = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'DontPromptForWindowsUpdate'
$werSoft = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings' 'DisableSendRequestAdditionalSoftwareToWER'
$werGen = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings' 'DisableSendGenericDriverNotFoundToWER'
Add-Check 'Updates' 'New devices: no drivers or apps from Windows Update' $(if ($drvSearch -eq 0 -and $devMeta -eq 1 -and $dontSearch -eq 1 -and $dontPrompt -eq 1 -and $werSoft -eq 1 -and $werGen -eq 1) { 'PASS' } else { 'FAIL' }) "SearchOrderConfig=$drvSearch PreventDeviceMetadataFromNetwork=$devMeta DontSearchWindowsUpdate=$dontSearch DontPromptForWindowsUpdate=$dontPrompt DisableSendRequestAdditionalSoftwareToWER=$werSoft DisableSendGenericDriverNotFoundToWER=$werGen (plugged-in devices get in-box and curated drivers only)"
# Update currency. The newest installed update (Get-HotFix) should be under 40 days old:
# Microsoft ships every month. A new install is INFO (the image's updates carry no usable
# date, and Windows Update needs a few days).
$hfNew = $null
try { $hfNew = @(Get-HotFix -ErrorAction Stop | Where-Object { $_.InstalledOn }) | Sort-Object InstalledOn | Select-Object -Last 1 } catch { }
$hfAge = if ($hfNew) { [int]((Get-Date) - $hfNew.InstalledOn).TotalDays } else { $null }
$updState = if ($null -ne $hfAge -and $hfAge -le 40) { 'PASS' } elseif (& $pcIsNew 14) { 'INFO' } else { 'WARN' }
Add-Check 'Updates' 'An update installed in the last 40 days' $updState "$(if ($hfNew) { "newest: $($hfNew.HotFixID), $($hfNew.InstalledOn.ToString('yyyy-MM-dd')) ($hfAge days ago)" } else { 'no dated update found' }); running build $($cv.CurrentBuild).$($cv.UBR)$(if ($updState -eq 'INFO') { ' (new install: Windows Update catches up over the next days)' } elseif ($updState -eq 'WARN') { ' - Settings > Windows Update > Check for updates, install what it offers and restart. If it shows an error, note the code and search Microsoft''s support site for it' })"
# A restart Windows is waiting for (servicing or Windows Update). Pending file renames
# alone are not counted: they are almost always there.
$rbCbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$rbWu = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
Add-Check 'Updates' 'No restart pending for updates' $(if (-not ($rbCbs -or $rbWu)) { 'PASS' } elseif ($PreRestart) { 'INFO' } else { 'WARN' }) $(if ($rbCbs -or $rbWu) { "pending: $(@($(if ($rbCbs) { 'component servicing' }), $(if ($rbWu) { 'Windows Update' }) | Where-Object { $_ }) -join ', ')$(if ($PreRestart) { ' (setup restarts the PC in a moment)' } else { ' - restart the PC (Start > Power > Restart, not Shut down): updates are not in effect until then' })" } else { '' })
$lp = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled'
Add-Check 'Dev' 'Long paths' $(if (-not $optLongPaths) { 'INFO' } elseif ($lp -eq 1) { 'PASS' } else { 'WARN' }) "LongPathsEnabled=$lp$(if (-not $optLongPaths) { ' (not set by the kit: settings options.longPaths is false)' })"
$rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
# Get-ComputerRestorePoint returns nothing without elevation: no count then
Add-Check 'Recovery' 'System Restore point exists' $(if ($rp) { 'PASS' } else { 'WARN' }) $(if ($rp -or $isAdmin) { "$(@($rp).Count) restore point(s)" } else { 'Not elevated - re-run as administrator to count the restore points' })
if ($isAdmin) {
    try {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
        $prot = @($bl.KeyProtector | ForEach-Object { "$($_.KeyProtectorType)" })
        # TPM-only (2026-10-07): a startup PIN would stop every Wake-on-LAN at the pre-boot prompt.
        # Off is a WARN (DISA STIG V-253259, CAT I: encrypt all disks): BitLocker is a manual step.
        $blOff = "$($bl.ProtectionStatus)" -ne 'On'
        $blState = if ($blOff) { 'WARN' } elseif ($prot -contains 'Tpm') { 'PASS' } else { 'WARN' }
        # Protection off has three meanings: nothing encrypted yet; encrypted but SUSPENDED
        # (the key lies unprotected on the disk until protection is resumed); or still encrypting.
        $blVs = "$($bl.VolumeStatus)"
        $blHint = if ($blOff -and $blVs -eq 'FullyEncrypted') { ' - SUSPENDED: the disk is encrypted, but its key is stored on it unprotected, so anyone with the disk can read it. Turn protection back on in an administrator PowerShell: Resume-BitLocker -MountPoint C: (after Suspend-BitLocker -RebootCount 1 it comes back by itself at the next restart)' }
                  elseif ($blOff -and $blVs -match 'InProgress|Paused') { " - $blVs ($($bl.EncryptionPercentage) %): protection turns on by itself when encryption has finished; validate again then" }
                  elseif ($blOff -and $prot.Count) { ' - not encrypted yet, but BitLocker is prepared: restart the PC (Windows tests the TPM at the next start, then encrypts)' }
                  elseif ($blOff) { ' - not encrypted yet: run C:\ProgramData\W11Kit\Enable-BitLocker.cmd (DISA STIG V-253259)' }
                  elseif ($blState -eq 'WARN') { ' - not TPM-only: a startup PIN blocks unattended Wake-on-LAN boots' } else { '' }
        Add-Check 'Security' 'BitLocker on, TPM-only' $blState "$blVs, protection $($bl.ProtectionStatus), protectors: $($prot -join ', ')$blHint"
        # What the TPM protector is bound to (Win32_EncryptableVolume.GetKeyProtectorPlatformValidationProfile).
        # With PCR 7 (Secure Boot state) a BIOS update normally doesn't ask for the recovery
        # key; without it BitLocker measures the firmware itself, and every BIOS change does.
        $tpmProt = @($bl.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -like 'Tpm*' }) | Select-Object -First 1
        if ($tpmProt) {
            try {
                $ev = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$env:SystemDrive'" -ErrorAction Stop
                $pv = Invoke-CimMethod -InputObject $ev -MethodName GetKeyProtectorPlatformValidationProfile -Arguments @{ VolumeKeyProtectorID = "$($tpmProt.KeyProtectorId)" } -ErrorAction Stop
                if ($pv.ReturnValue -ne 0) { throw "GetKeyProtectorPlatformValidationProfile returned 0x$('{0:x}' -f [int64]$pv.ReturnValue)" }
                $pcrs = @($pv.PlatformValidationProfile | ForEach-Object { [int]$_ })
                Add-Check 'Security' 'BitLocker bound to Secure Boot (PCR 7)' $(if ($pcrs -contains 7) { 'PASS' } else { 'WARN' }) "TPM protector validates PCR $($pcrs -join ', ')$(if ($pcrs -notcontains 7) { ' - without PCR 7 every BIOS update or BIOS setting change asks for the 48-digit recovery key: always run Suspend-BitLocker -MountPoint C: -RebootCount 1 first. Usual cause: Secure Boot was off when BitLocker was turned on. To bind it to Secure Boot (recovery key at hand, Secure Boot on; msinfo32 as administrator must show PCR7 Configuration: Binding Possible): manage-bde -protectors -delete C: -type TPM  then  manage-bde -protectors -add C: -tpm' })"
            } catch { Add-Check 'Security' 'BitLocker bound to Secure Boot (PCR 7)' 'INFO' "could not read the TPM protector's validation profile: $($_.Exception.Message)" }
        }
        # Is the recovery key you saved still the one on the disk? Enable-BitLocker records
        # the recovery protector's ID (never the key) each time it saves the key.
        $recIds = @($bl.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' } | ForEach-Object { "$($_.KeyProtectorId)".ToUpperInvariant() })
        if ($recIds.Count) {
            $recFile = $null
            try { $recFile = (Get-Content -Raw -LiteralPath 'C:\ProgramData\W11Kit\bitlocker-recovery-id.json' -ErrorAction Stop | ConvertFrom-Json).volumes | Where-Object { "$($_.volume)" -eq $env:SystemDrive } | Select-Object -First 1 } catch { }
            $savedIds = @($recFile.ids | Where-Object { $_ } | ForEach-Object { "$_".ToUpperInvariant() })
            $short = { param($ids) (@($ids) | ForEach-Object { $_.Trim('{}').Substring(0, [Math]::Min(8, $_.Trim('{}').Length)) }) -join ', ' }
            $recName = 'BitLocker recovery key on file is the current one'
            if (-not $savedIds.Count) {
                Add-Check 'Security' $recName 'INFO' "no record for $env:SystemDrive (BitLocker was turned on before the kit recorded this, or not with the kit's script); recovery key ID on the disk: $(& $short $recIds). To save the key again and record it: C:\ProgramData\W11Kit\Enable-BitLocker.cmd -ExportOnly"
            } elseif (@($recIds | Where-Object { $savedIds -notcontains $_ }).Count) {
                Add-Check 'Security' $recName 'WARN' "the recovery key on the disk has ID $(& $short $recIds), but the key the kit last saved ($($recFile.saved)) had ID $(& $short $savedIds): the copy you keep may no longer unlock this disk. Save the current key now: C:\ProgramData\W11Kit\Enable-BitLocker.cmd -ExportOnly, and replace your old copies"
            } else {
                Add-Check 'Security' $recName 'PASS' "ID $(& $short $recIds), saved $($recFile.saved) (the first 8 characters are in the key file's name)"
            }
        }
        # Fixed data drives with a letter (the STIG wants every disk encrypted); no row without any
        $dataVols = @(Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { "$($_.VolumeType)" -eq 'FixedData' -and "$($_.MountPoint)" -match '^[A-Za-z]:' })
        if ($dataVols.Count) {
            $openVols = @($dataVols | Where-Object { "$($_.ProtectionStatus)" -ne 'On' })
            Add-Check 'STIG' 'BitLocker on fixed data drives' $(if ($openVols.Count) { 'WARN' } else { 'PASS' }) "$(($dataVols | ForEach-Object { "$($_.MountPoint) $($_.ProtectionStatus)" }) -join ', ')$(if ($openVols.Count) { ' - encrypt them (Enable-BitLocker -MountPoint <X:> -EncryptionMethod XtsAes256 -RecoveryPasswordProtector, then -AutoUnlockEnabled); DISA STIG V-253259' })"
        }
    } catch { Add-Check 'Security' 'BitLocker' 'WARN' 'Run elevated' }
}

$fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
$useTpm = Reg $fve 'UseTPM'; $usePin = Reg $fve 'UseTPMPIN'; $osEnc = Reg $fve 'OSEncryptionType'
$tpmOnlyOk = ($useTpm -ne 0) -and ($usePin -ne 1) -and ((Reg $fve 'UseTPMKey') -ne 1) -and ((Reg $fve 'UseTPMKeyPIN') -ne 1)
Add-Check 'Security' 'BitLocker policy allows TPM-only unlock' $(if ($tpmOnlyOk) { 'PASS' } else { 'FAIL' }) "UseTPM=$useTpm UseTPMPIN=$usePin OSEncryptionType=$osEnc (1 = require, 2 = allow, 0 = not allowed)"
$wlKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$autoLogon = Reg $wlKey 'AutoAdminLogon'; $hasDefPw = $null -ne (Reg $wlKey 'DefaultPassword')
Add-Check 'Security' 'Setup auto-logon removed (no stored password)' $(if ($autoLogon -ne '1' -and -not $hasDefPw) { 'PASS' } elseif ($PreRestart) { 'INFO' } else { 'FAIL' }) "AutoAdminLogon=$autoLogon DefaultPassword $(if ($hasDefPw) { 'PRESENT' } else { 'absent' }) (PostInstall clears both after this snapshot)"
$panther = @(Get-ChildItem "$env:SystemRoot\Panther\unattend*.xml", "$env:SystemRoot\Panther\Unattend\unattend*.xml" -ErrorAction SilentlyContinue)
Add-Check 'Security' 'No cached answer files with passwords' $(if (-not $panther.Count) { 'PASS' } elseif ($PreRestart) { 'INFO' } else { 'FAIL' }) $(if ($panther.Count) { "$(($panther | ForEach-Object Name) -join ', ') (the last first-logon command deletes them)" } else { 'Panther clean' })
$w32 = Get-Service W32Time -ErrorAction SilentlyContinue
Add-Check 'Services' 'Windows Time automatic' $(if ($w32.StartType -eq 'Automatic') { 'PASS' } else { 'WARN' }) "$($w32.Status), $($w32.StartType)"
$geo = try { (Get-WinHomeLocation).GeoId } catch { $null }
Add-Check 'Store/Gaming' "Home location$(if ($homeName) { " $homeName" })" $(if (-not $homeGeoId) { 'INFO' } elseif ("$geo" -eq $homeGeoId) { 'PASS' } else { 'WARN' }) "GeoId=$geo for $who (settings: $(if ($homeGeoId) { $homeGeoId } else { 'not readable' }); 39070 = World: the Store catalog 404s)"

# --- Other hardening tools ------------------------------------------------------
# A second hardening tool can undo the kit's decisions (power policy, a TPM+PIN
# requirement, a stricter lockout, .ps1 blocked, slow DNS behind a VPN). One such tool
# is recognised by its service and package name.
$hss = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'HardenSystemSecurity' -or $_.DisplayName -match 'Harden System Security' })
if ($isAdmin) { $hss += @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object Name -match 'HardenSystemSecurity') }
Add-Check 'Conflicts' 'No second hardening tool' $(if (-not $hss.Count) { 'PASS' } else { 'WARN' }) $(if ($hss.Count) { 'another hardening tool is installed; its settings may conflict with this image (docs/reference/SECURITY-BASELINE.md, "Other hardening tools"): uninstall it' } else { '' })
$mpol = try { Get-ExecutionPolicy -Scope MachinePolicy } catch { $null }
Add-Check 'Conflicts' 'PowerShell scripts not blocked by machine policy' $(if ("$mpol" -notin 'Restricted', 'AllSigned') { 'PASS' } else { 'FAIL' }) "MachinePolicy=$mpol (Restricted blocks this validator and Enable-BitLocker)"
$smart = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DisableSmartNameResolution'
Add-Check 'Conflicts' 'Smart multi-homed name resolution not disabled' $(if ($smart -ne 1) { 'PASS' } else { 'WARN' }) "DisableSmartNameResolution=$smart (1 = ~10 s DNS stalls behind a full-tunnel VPN)"

# --- Self-hosting: this PC must rebuild its own ISO (docs/dev/BUILD-INTERNALS.md, "Self-hosting") ---
# Local policy (a second hardening tool sets both) can turn these on: Controlled Folder
# Access stops the build at preflight, the ASR rule blocks self-built tools. Neither is
# in the Microsoft baseline.
$mpp = try { Get-MpPreference -ErrorAction Stop } catch { $null }
$cfa = $mpp.EnableControlledFolderAccess
# A build pauses Defender's protection (Run-Build.cmd asks; -PauseDefenderProtection): only a policy-set value can't be paused
$egPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard'
$cfaPol = (Get-ItemProperty "$egPol\Controlled Folder Access" -ErrorAction SilentlyContinue).EnableControlledFolderAccess
Add-Check 'Self-hosting' 'Controlled Folder Access can be paused for a build (not set by policy)' $(if ($cfaPol -ne 1) { 'PASS' } else { 'FAIL' }) "policy EnableControlledFolderAccess=$cfaPol, preference=$cfa (a policy value blocks every build: set it to Not configured, or build on another PC)"
# Defender exclusions. The build excludes its own work folders while it runs and removes
# them at the end; a build that crashed can leave them behind, and an excluded folder is
# a place malware is never scanned in. While DISM or oscdimg runs they are expected.
# The baseline hides exclusions from Get-MpPreference even for administrators
# (HideExclusionsFromLocalAdmins: the values read 'N/A: ...'), so Defender's own registry
# keys are read instead (administrators only).
$exclAll = New-Object System.Collections.Generic.List[string]; $exclSeen = $false
$exclNames = [ordered]@{ ExclusionPath = 'Path'; ExclusionProcess = 'Process'; ExclusionExtension = 'Extension'; AttackSurfaceReductionOnlyExclusions = 'ASR-only exclusion' }
if ($mpp -and -not @($exclNames.Keys | Where-Object { "$(@($mpp.$_) -join ' ')" -like 'N/A:*' }).Count) {
    $exclSeen = $true
    foreach ($n in $exclNames.Keys) { foreach ($v in @($mpp.$n)) { if ("$v".Trim()) { $exclAll.Add("$($exclNames[$n]): $v") } } }
} elseif ($isAdmin) {
    $wdKey = 'HKLM:\SOFTWARE\Microsoft\Windows Defender'
    $exclKeys = [ordered]@{ "$wdKey\Exclusions\Paths" = 'Path'; "$wdKey\Exclusions\Processes" = 'Process'; "$wdKey\Exclusions\Extensions" = 'Extension'; "$wdKey\Windows Defender Exploit Guard\ASR\ASROnlyExclusions" = 'ASR-only exclusion' }
    try {
        foreach ($k in $exclKeys.Keys) {
            if (-not (Test-Path -LiteralPath $k)) { continue }
            foreach ($v in @((Get-Item -LiteralPath $k -ErrorAction Stop).GetValueNames())) { if ("$v".Trim()) { $exclAll.Add("$($exclKeys[$k]): $v") } }
        }
        $exclSeen = $true
    } catch { }
}
if (-not $exclSeen) {
    Add-Check 'Security' 'No Defender exclusions left behind' 'INFO' "Not checked: Windows shows Defender's exclusions to administrators only$(if ($isAdmin) { ', and here not even to them (the baseline hides them)' } else { ' (run elevated)' })"
} else {
    $building = @(Get-Process -Name Dism, DismHost, oscdimg -ErrorAction SilentlyContinue).Count -gt 0
    $exclText = $exclAll.ToArray() -join '; '
    Add-Check 'Security' 'No Defender exclusions left behind' $(if (-not $exclAll.Count) { 'PASS' } elseif ($building) { 'INFO' } else { 'WARN' }) $(if (-not $exclAll.Count) { 'none' } elseif ($building) { "$exclText (a build is running: its exclusions are expected until it ends)" } else { "$exclText - Defender does not scan these. If a build left them (C:\W11Kit\work\...), or you don't know them, remove each in an administrator PowerShell: Remove-MpPreference -AttackSurfaceReductionOnlyExclusions '<path>' (or -ExclusionPath, -ExclusionProcess, -ExclusionExtension)" })
}
# ASR rules beyond the Microsoft baseline that break a self-hosted build. Block (1)
# and Warn (6) both stop background tools: nobody is there to click "allow".
$asrIds = @($mpp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() })
$asrAct = @($mpp.AttackSurfaceReductionRules_Actions)
# ('copied or impersonated system tools' is ON in the image: Build-Iso excludes its
# own DISM work folders while it runs, so it no longer blocks a self-hosted build.)
foreach ($rule in @(   # leading comma below: a one-item list of lists would unroll into strings
        ,@('01443614-cd74-433a-b99e-2ecdc07bfc25', 'prevalence, age or trusted list', 'WARN', 'blocks self-built tools, including the ones the build runs'))) {
    $i = [array]::IndexOf($asrIds, $rule[0])
    $act = if ($i -ge 0) { $asrAct[$i] } else { 0 }
    # Block as a Defender preference (the image's default) is paused by a build; only a policy value isn't
    $actPol = (Get-ItemProperty "$egPol\ASR\Rules" -ErrorAction SilentlyContinue).($rule[0])
    Add-Check 'Self-hosting' "ASR rule '$($rule[1])' can be paused for a build (not blocking by policy)" $(if ("$actPol" -notin '1', '6') { 'PASS' } else { $rule[2] }) "policy action=$actPol; rule $($rule[0]) action=$act (1 Block / 6 Warn: $($rule[3]); not in the Microsoft baseline)"
}

# --- Privacy / account -------------------------------------------------------
$tel = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
Add-Check 'Privacy' 'Diagnostic data = Required' $(if ($tel -eq 1) { 'PASS' } else { 'WARN' }) "AllowTelemetry=$tel"
$rc = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement'
Add-Check 'Privacy' 'Recall disabled' $(if ($rc -eq 0) { 'PASS' } else { 'WARN' }) "AllowRecallEnablement=$rc"
$wd = Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests'
Add-Check 'Privacy' 'Widgets disabled' $(if ($wd -eq 0) { 'PASS' } else { 'WARN' }) "AllowNewsAndInterests=$wd"
$admins = @(Get-LocalGroupMember -Group Administrators -ErrorAction SilentlyContinue | Where-Object { $_.ObjectClass -eq 'User' } | ForEach-Object { $_.Name.Split('\')[-1] })
$locals = @(Get-LocalUser | Where-Object Enabled)
$standard = @($locals | Where-Object { $admins -notcontains $_.Name })
# settings options.allowMicrosoftAccount true: a Microsoft account for Windows sign-in is a choice, not drift
$msaAllowed = (Get-Setting 'options.allowMicrosoftAccount') -eq $true
$msaAcc = @($locals | Where-Object PrincipalSource -eq 'MicrosoftAccount')
Add-Check 'Account' $(if ($msaAllowed) { 'Microsoft accounts allowed (settings options.allowMicrosoftAccount)' } else { 'Local accounts only (no Microsoft account)' }) $(if ($msaAllowed) { 'INFO' } elseif (-not $msaAcc.Count) { 'PASS' } else { 'WARN' }) (($locals | ForEach-Object { "$($_.Name) ($($_.PrincipalSource))" }) -join '; ')
Add-Check 'Account' 'Separate standard daily account' $(if ($standard.Count) { 'PASS' } else { 'WARN' }) "admins: $($admins -join ', '); standard: $(($standard | ForEach-Object Name) -join ', ')"
$mac = Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser'
if ($msaAllowed) { Add-Check 'Account' 'Windows sign-in may be converted to a Microsoft account (settings options.allowMicrosoftAccount)' $(if ($mac -ge 1) { 'INFO' } else { 'PASS' }) "NoConnectedUser=$mac$(if ($mac -ge 1) { ' (a policy prevents it all the same: not one of the kit''s with this setting)' })" }
else { Add-Check 'Account' 'Windows sign-in cannot be converted to a Microsoft account' $(if ($mac -ge 1) { 'PASS' } else { 'WARN' }) "NoConnectedUser=$mac (the kit sets 1: users can't add Microsoft accounts)" }
# Drift: the image has exactly one administrator (plus the built-in one, renamed and
# disabled) and one daily account. Anything more was added later: by you, or not.
if ($bo -and $bo.AdminName -and $bo.UserName) {
    try {
        $admAll = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
        $admExtra = @($admAll | Where-Object { "$($_.SID)" -notmatch '^S-1-5-21-.*-500$' -and "$($_.Name)".Split('\')[-1] -ne $bo.AdminName } | ForEach-Object { "$($_.Name)".Split('\')[-1] } | Where-Object { $expectedExtra -notcontains $_ })
        Add-Check 'Account' "Administrators group: only $($bo.AdminName)" $(if ($admExtra.Count) { 'WARN' } else { 'PASS' }) $(if ($admExtra.Count) { "also in the group: $($admExtra -join ', ') - every member has full control of this PC. If you didn't add it on purpose, remove it in an administrator PowerShell: Remove-LocalGroupMember -Group Administrators -Member '<name>'" } else { "members: $(($admAll | ForEach-Object { "$($_.Name)".Split('\')[-1] }) -join ', ') (the built-in Administrator is renamed and disabled)" })
    } catch { Add-Check 'Account' "Administrators group: only $($bo.AdminName)" 'INFO' "members not readable: $($_.Exception.Message)" }
    # settings accounts.expectedExtra: accounts the owner adds on purpose are not findings
    $extraUsers = @($locals | Where-Object { $_.Name -notin $bo.AdminName, $bo.UserName -and $expectedExtra -notcontains $_.Name } | ForEach-Object Name)
    Add-Check 'Account' "Enabled accounts: only $($bo.AdminName) and $($bo.UserName)" $(if ($extraUsers.Count) { 'WARN' } else { 'PASS' }) $(if ($extraUsers.Count) { "also enabled: $($extraUsers -join ', ') - fine if you created it (a family member, a service account); if not, disable it in an administrator PowerShell: Disable-LocalUser -Name '<name>'" } else { "enabled: $(($locals | ForEach-Object Name) -join ', ')" })
    # A reminder only: passwords never expire on this image.
    $admUser = $locals | Where-Object Name -eq $bo.AdminName | Select-Object -First 1
    if ($admUser -and $admUser.PasswordLastSet) {
        $pwAge = [int]((Get-Date) - $admUser.PasswordLastSet).TotalDays
        Add-Check 'Account' "Password age of $($bo.AdminName)" 'INFO' "set $pwAge day(s) ago$(if ($pwAge -gt 180) { ' - consider a new one (a reminder: passwords do not expire on this image). Sign in as that account, Ctrl+Alt+Del > Change a password' })"
    }
} else {
    Add-Check 'Account' 'Administrators group and enabled accounts' 'INFO' 'Not checked: C:\ProgramData\W11Kit\build-options.json does not name the two kit accounts'
}

# --- WSL ---------------------------------------------------------------------
try {
    # image.json: features.enable must be Enabled (missing = WARN); features.mustNotBeEnabled
    # must not be (one this Windows doesn't offer at all can't be enabled: no row).
    $enable = @($image.features.enable | Where-Object { $_ })
    $mustNot = @($image.features.mustNotBeEnabled | Where-Object { $_ })
    if ($image) {
        $feat = @(Get-WindowsOptionalFeature -Online -ErrorAction Stop | Where-Object { $_.FeatureName -in ($enable + $mustNot) })
        foreach ($f in $feat) {
            $want = $f.FeatureName -in $enable
            $okState = if ($want) { $f.State -eq 'Enabled' } else { $f.State -ne 'Enabled' }
            Add-Check 'WSL' $f.FeatureName $(if ($okState) { 'PASS' } else { 'WARN' }) "$($f.State) (expected $(if ($want) { 'Enabled' } else { 'Disabled' }))"
        }
        foreach ($name in @($enable | Where-Object { @($feat.FeatureName) -notcontains $_ })) {
            Add-Check 'WSL' $name 'WARN' 'not offered by this Windows (expected Enabled)'
        }
    }
} catch { Add-Check 'WSL' 'Optional features' 'WARN' 'Run elevated' }

# --- Apps --------------------------------------------------------------------
# Apps you expect on this PC (settings reminders.expectedApps: name, and optionally the
# winget id and the program file's path): a reminder until each is installed. Installed =
# its program file exists (path), else a program of that name is registered for uninstall.
if ($expectedApps.Count) {
    $installedNames = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', "$userRoot\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object DisplayName | ForEach-Object { "$($_.DisplayName)" })
    foreach ($app in $expectedApps) {
        $there = if ($app.path) { Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables("$($app.path)")) } else { [bool]@($installedNames | Where-Object { $_ -eq "$($app.name)" -or $_.StartsWith("$($app.name) ", [StringComparison]::OrdinalIgnoreCase) }).Count }
        Add-Check 'Apps' "$($app.name) installed" $(if ($there) { 'PASS' } else { 'INFO' }) $(if ($there) { '' } elseif ($app.wingetId) { "Not installed yet: winget install -e --id $($app.wingetId)" } else { 'Not installed yet' })
    }
}
# Removed apps that came back: Windows or the Store can provision or install them again
# (seen with Dev Home, minutes after a first sign-in).
try {
    $rmNames = @((Get-Content -Raw 'C:\ProgramData\W11Kit\removal-manifest.json' -ErrorAction Stop | ConvertFrom-Json).remove.name)
    $back = @(@(if ($isAdmin) { Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue } else { Get-AppxPackage -ErrorAction SilentlyContinue }) |
        Where-Object { $rmNames -contains $_.Name } | ForEach-Object Name)
    if ($isAdmin) { $back += @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $rmNames -contains $_.DisplayName } | ForEach-Object { "$($_.DisplayName) (provisioned)" }) }
    $back = @($back | Sort-Object -Unique)
    Add-Check 'Apps' "Removed apps not reinstalled ($(if ($isAdmin) { 'all users' } else { $who }))" $(if ($back.Count) { 'WARN' } else { 'PASS' }) $(if ($back.Count) { ($back -join ', ') + ' - remove: docs/reference/REMOVED-APPS.md, "If a removed app comes back"' } else { '' })
} catch { Add-Check 'Apps' 'Removed apps not reinstalled' 'WARN' "removal-manifest.json not readable: $_" }
# Smart App Control (settings options.smartAppControl): "off" for a PC that runs its own
# unsigned builds; "leave": the kit sets nothing, and from evaluation mode Windows switches
# it on or off by itself. Reported only.
$sac = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' 'VerifiedAndReputablePolicyState'
if ($optSacOff) {
    Add-Check 'Security' 'Smart App Control off (decision)' $(if ($sac -eq 0) { 'PASS' } else { 'WARN' }) "VerifiedAndReputablePolicyState=$sac (0 off, 1 on, 2 evaluation) - Windows Security > App & browser control > Smart App Control"
} else {
    Add-Check 'Security' 'Smart App Control' 'INFO' "VerifiedAndReputablePolicyState=$sac (0 off, 1 on, 2 evaluation; left to Windows: settings options.smartAppControl is leave)"
}
# Backup of the daily user's files: OneDrive folder backup (settings reminders.oneDriveBackup).
# Read from the daily account's own hive (loaded while it is signed in), since
# this report usually runs elevated as the admin.
$daily = try { (Get-Content -Raw 'C:\ProgramData\W11Kit\build-options.json' -ErrorAction Stop | ConvertFrom-Json).UserName } catch { $null }
$dailySid = if ($daily) { try { (Get-LocalUser -Name $daily -ErrorAction Stop).SID.Value } catch { $null } }
$usf = if ($dailySid) { "Registry::HKEY_USERS\$dailySid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" }
if ($usf -and (Test-Path $usf)) {
    # Raw values: they're REG_EXPAND_SZ (%USERPROFILE%\...), and expanding them here
    # would use the profile of whoever runs this report (usually the admin).
    $k = Get-Item $usf
    $docs = $k.GetValue('Personal', $null, 'DoNotExpandEnvironmentNames'); $desk = $k.GetValue('Desktop', $null, 'DoNotExpandEnvironmentNames'); $pics = $k.GetValue('My Pictures', $null, 'DoNotExpandEnvironmentNames')
    $kfm = ("$docs" -match 'OneDrive') -and ("$desk" -match 'OneDrive') -and ("$pics" -match 'OneDrive')
    # settings reminders.oneDriveBackup false: you back up another way; reported only
    Add-Check 'Backup' "OneDrive folder backup ($daily)" $(if (-not $remOneDrive) { 'INFO' } elseif ($kfm) { 'PASS' } else { 'WARN' }) "Documents: $docs; Desktop: $desk; Pictures: $pics$(if (-not $remOneDrive) { ' (not required: settings reminders.oneDriveBackup is false)' } elseif (-not $kfm) { ' - as the daily user: Settings > Accounts > Windows backup > OneDrive folder syncing, and switch on Documents, Desktop and Pictures' })"
} else {
    Add-Check 'Backup' "OneDrive folder backup ($daily)" 'INFO' 'Not checked: the daily account is not signed in'
}
# What OneDrive folder backup does NOT hold on this PC: things that are lost with the
# disk unless they are copied somewhere else (docs/MONTHLY.md, 'Offline backup').
$dailyHome = if ($dailySid) { Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$dailySid" 'ProfileImagePath' }
if ($dailyHome -and (Test-Path -LiteralPath $dailyHome)) {
    $gaps = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-Path $dailyHome '.ssh')) { $gaps.Add("$dailyHome\.ssh (SSH keys)") }
    foreach ($v in @(Get-ChildItem -Path (Join-Path $dailyHome 'AppData\Local\Packages\*\LocalState\ext4.vhdx'), (Join-Path $dailyHome 'AppData\Local\wsl\*\ext4.vhdx') -Force -ErrorAction SilentlyContinue)) {
        $gaps.Add("WSL disk $($v.FullName -replace '^.*\\(Packages|wsl)\\([^\\]+)\\.*$', '$2') ($([math]::Round($v.Length / 1GB)) GB)")
    }
    # Git working folders: the profile's own folders and one level below (not AppData, not OneDrive)
    $repos = New-Object System.Collections.Generic.List[string]
    foreach ($d in @(Get-ChildItem -LiteralPath $dailyHome -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(AppData|OneDrive.*|\..*)$' })) {
        if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $repos.Add($d.FullName); continue }
        foreach ($d2 in @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue | Select-Object -First 200)) {
            if (Test-Path -LiteralPath (Join-Path $d2.FullName '.git')) { $repos.Add($d2.FullName) }
        }
    }
    if ($repos.Count) { $gaps.Add("$($repos.Count) Git folder(s): $((@($repos) | Select-Object -First 6) -join ', ')$(if ($repos.Count -gt 6) { ', ...' })") }
    Add-Check 'Backup' "$(if ($remOneDrive) { 'Not covered by OneDrive' } else { 'Only on this disk' }) ($daily)" 'INFO' $(if ($gaps.Count) { "$($gaps -join '; ') - these live only on this disk: push code to a remote, and copy the rest in your offline backup" } else { 'no SSH keys, WSL disks or Git folders found in the profile' })
}
# Offline backup reminder (settings reminders.offlineBackup): a copy on a drive that is
# unplugged afterwards is the one ransomware and a cloud account problem can't reach. After each backup, the stamp file's date is renewed by hand.
$stamp = Join-Path $env:PUBLIC 'Documents\W11Kit-offline-backup.txt'
$stampCmd = 'copy /y nul "%PUBLIC%\Documents\W11Kit-offline-backup.txt"'
$stampItem = Get-Item -LiteralPath $stamp -ErrorAction SilentlyContinue
$stampAge = if ($stampItem) { [int]((Get-Date) - $stampItem.LastWriteTime).TotalDays } else { $null }
$offName = 'Offline backup in the last 35 days'
if (-not $remOffline) {
    Add-Check 'Backup' $offName 'INFO' "$(if ($stampItem) { "last recorded $($stampItem.LastWriteTime.ToString('yyyy-MM-dd'))" } else { 'none recorded' }) (not required: settings reminders.offlineBackup is false)"
} elseif ($null -ne $stampAge -and $stampAge -le 35) {
    Add-Check 'Backup' $offName 'PASS' "last recorded $($stampItem.LastWriteTime.ToString('yyyy-MM-dd')) ($stampAge days ago)"
} elseif ($null -eq $stampAge -and (& $pcIsNew 35)) {
    Add-Check 'Backup' $offName 'INFO' "none recorded yet (new install). After your first backup to an external drive (docs/MONTHLY.md, 'Offline backup'), record it in a Command Prompt: $stampCmd"
} else {
    Add-Check 'Backup' $offName 'WARN' "$(if ($stampItem) { "last recorded $($stampItem.LastWriteTime.ToString('yyyy-MM-dd')) ($stampAge days ago)" } else { 'none recorded' }) - copy your files to an external drive, unplug it, then record it in a Command Prompt: $stampCmd (what to copy: docs/MONTHLY.md, 'Offline backup'; to switch this reminder off: reminders.offlineBackup false in your settings)"
}

# Remote-access tools and driver/software auto-updaters: allowed, but visible in
# every report (a remote-access tool runs on demand, not as a service that starts
# with Windows; vendor updaters notify only).
$uninst = @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', "$userRoot\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object DisplayName)
$remote = @($uninst | Where-Object DisplayName -match 'RustDesk|AnyDesk|TeamViewer|Chrome Remote Desktop|Splashtop|Parsec|RealVNC|TightVNC|UltraVNC' | ForEach-Object DisplayName | Sort-Object -Unique)
$autoSvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'RustDesk|AnyDesk|TeamViewer|Splashtop|Parsec|VNC' -and $_.StartType -eq 'Automatic' } | ForEach-Object Name)
$rdpOn = (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0
# settings reminders.remoteAccessOnDemand false: listed, never a WARN
Add-Check 'Remote' 'Remote-access tools' $(if ($remRemote -and ($autoSvc.Count -or $rdpOn)) { 'WARN' } else { 'INFO' }) "$(if (-not $remote.Count -and -not $rdpOn) { 'none' } else { "installed: $($remote -join ', ')$(if ($rdpOn) { '; Remote Desktop ON' })$(if ($autoSvc.Count) { "; service starts automatically: $($autoSvc -join ', ')$(if ($remRemote) { ' (decision: on demand = Manual)' })" } else { '; services manual / not running at boot' })" })$(if (-not $remRemote) { ' (on-demand not required: settings reminders.remoteAccessOnDemand is false)' })"
# Remote shells: an OpenSSH server or Windows Remote Management that runs, or starts with
# Windows, is a standing way in like a remote-access tool (same setting: on demand).
$shellSvc = @(foreach ($n in 'sshd', 'WinRM') { $x = Get-Service -Name $n -ErrorAction SilentlyContinue; if ($x -and ("$($x.Status)" -eq 'Running' -or "$($x.StartType)" -eq 'Automatic')) { "$n ($($x.Status), $($x.StartType))" } })
Add-Check 'Remote' 'No remote shell service (OpenSSH server, WinRM)' $(if (-not $shellSvc.Count) { 'PASS' } elseif ($remRemote) { 'WARN' } else { 'INFO' }) $(if ($shellSvc.Count) { "$($shellSvc -join '; ')$(if ($remRemote) { ' - if you don''t need it all the time, in an administrator PowerShell: Stop-Service <name>; Set-Service <name> -StartupType Manual (start it when you need it)' } else { ' (on-demand not required: settings reminders.remoteAccessOnDemand is false)' })" } else { 'sshd and WinRM are not running and do not start with Windows' })
$updaters = @($uninst | Where-Object DisplayName -match 'AMD Install Manager|Logi(tech)? Download Assistant|Logi Options|Armoury|MyASUS|Dragon Center|Driver Booster|Driver Easy|Intel.*Driver.*Support' | ForEach-Object DisplayName | Sort-Object -Unique)
Add-Check 'Drivers' 'Driver/software auto-updaters' 'INFO' $(if ($updaters.Count) { ($updaters -join ', ') + ' - keep them on notify-only (Windows Update does not deliver drivers on purpose)' } else { 'none' })
# Brave installs per user (the daily account's profile); this report usually runs as the admin
$braveExe = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe") + @(Get-ChildItem "$env:SystemDrive\Users\*\AppData\Local\BraveSoftware\Brave-Browser\Application\brave.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($braveExe) {
    $bp = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    $braveOk = ((Reg $bp 'DownloadRestrictions') -eq 1) -and ((Reg $bp 'SafeBrowsingProtectionLevel') -eq 1)
    # settings options.bravePolicies false: the kit sets none; reported only
    Add-Check 'Browser' 'Brave security policies' $(if (-not $optBrave) { 'INFO' } elseif ($braveOk) { 'PASS' } else { 'WARN' }) "DownloadRestrictions=$(Reg $bp 'DownloadRestrictions') SafeBrowsingProtectionLevel=$(Reg $bp 'SafeBrowsingProtectionLevel') $(if ($optBrave) { '(kit: 1 / 1)' } else { '(not set by the kit: settings options.bravePolicies is false)' })"
}
$nvApp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object DisplayName -match '^NVIDIA App' | Select-Object -First 1
# settings reminders.nvidiaApp (for a PC with an NVIDIA GPU, when you want the app): false = no row
if ($remNvidia) {
    Add-Check 'Apps' 'NVIDIA App' $(if ($nvApp) { 'PASS' } else { 'INFO' }) $(if ($nvApp) { $nvApp.DisplayVersion } else { 'Driver is integrated; install the NVIDIA App (same or newer driver) for G-SYNC/settings (docs/reference/DRIVERS.md, section Notes per device class)' })
}

# --- Network exposure --------------------------------------------------------
try {
    $netProf = @(Get-NetConnectionProfile -ErrorAction Stop)
    Add-Check 'Network' 'Network type per connection' 'INFO' $(if ($netProf.Count) { ($netProf | ForEach-Object { "$($_.InterfaceAlias): $($_.NetworkCategory) ($($_.Name))" }) -join '; ' } else { 'not connected' })
} catch { $netProf = @() }
try {
    $fwProf = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop)
    $fwOff = @($fwProf | Where-Object { "$($_.Enabled)" -ne 'True' } | ForEach-Object Name)
    Add-Check 'Network' 'Firewall on for every network type' $(if ($fwProf.Count -and -not $fwOff.Count) { 'PASS' } else { 'WARN' }) "$(($fwProf | ForEach-Object { "$($_.Name): $(if ("$($_.Enabled)" -eq 'True') { 'on' } else { 'OFF' }), inbound $($_.DefaultInboundAction)" }) -join '; ')$(if ($fwOff.Count) { ' - turn it on: Windows Security > Firewall & network protection (the baseline sets it on by policy: if it is off, re-apply the kit''s policies, docs/reference/SECURITY-BASELINE.md, "Changing a setting later")' })"
    # How many doors are open: enabled inbound Allow rules that apply to the connected
    # network type(s). A number to compare between reports, not a verdict.
    $cats = @($netProf | ForEach-Object { "$($_.NetworkCategory)" -replace '^DomainAuthenticated$', 'Domain' } | Sort-Object -Unique)
    if ($cats.Count) {
        $inAllow = @(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop | Where-Object { $p = "$($_.Profile)"; $p -eq 'Any' -or @($cats | Where-Object { $p -match "\b$_\b" }).Count })
        Add-Check 'Network' 'Inbound firewall allow rules in use' 'INFO' "$($inAllow.Count) enabled inbound Allow rule(s) apply to the $($cats -join ' + ') network (compare with your last report; list them: Windows Defender Firewall with Advanced Security > Monitoring > Firewall)"
    }
} catch { Add-Check 'Network' 'Firewall on for every network type' 'INFO' "firewall settings not readable: $($_.Exception.Message)" }
# Folders or printers this PC shares (administrative shares such as C$ and IPC$ don't
# count). The image disables the file-sharing service (Server, LanmanServer): once it has
# stopped, nothing can be shared and the share list itself can't be read. That is a PASS.
$srv = Get-Service LanmanServer -ErrorAction SilentlyContinue
$srvText = if ($srv) { "$($srv.Status), $($srv.StartType)" } else { 'not present' }
if (-not $srv -or "$($srv.Status)" -ne 'Running') {
    Add-Check 'Network' 'No shared folders or printers' 'PASS' "the file-sharing service is off ($srvText): this PC shares nothing"
} else {
    try {
        $shares = @(Get-CimInstance Win32_Share -ErrorAction Stop | Where-Object { -not ([int64]$_.Type -band 0x80000000L) })
        Add-Check 'Network' 'No shared folders or printers' $(if ($shares.Count) { 'WARN' } else { 'PASS' }) $(if ($shares.Count) { "$(($shares | ForEach-Object { "$($_.Name) = $($_.Path)" }) -join '; ') - reachable from the network. If you don't need a share: File Explorer > the folder's Properties > Sharing > Advanced Sharing, untick Share this folder (or, elevated: Remove-SmbShare -Name '<name>')" } else { "none (file-sharing service: $srvText$(if ("$($srv.StartType)" -eq 'Disabled') { '; it stops for good at the next restart' }))" })
    } catch { Add-Check 'Network' 'No shared folders or printers' 'INFO' "shares not readable (file-sharing service: $srvText): $($_.Exception.Message)" }
}
# The kit's own firewall rule (PostInstall, in local Group Policy): no SMB (TCP 445) to
# Internet addresses, so a link to \\<internet host>\share can't draw out the account's
# credentials. Read from the active store (what the firewall enforces now). Missing in the
# first-logon snapshot is INFO: the firewall loads it at the restart at the latest.
$fwName = 'W11Kit-Block-SMB-Out-Internet'
$fwRerun = 'run the first-boot setup again in an administrator PowerShell (safe to repeat): powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\PostInstall.ps1 -NoRestart'
try {
    $fwRule = Get-NetFirewallRule -PolicyStore ActiveStore -Name $fwName -ErrorAction Stop | Select-Object -First 1
    $fwGood = "$($fwRule.Enabled)" -eq 'True' -and "$($fwRule.Action)" -eq 'Block' -and "$($fwRule.Direction)" -eq 'Outbound'
    Add-Check 'Network' 'Outbound SMB to the Internet blocked (firewall rule)' $(if ($fwGood) { 'PASS' } else { 'WARN' }) "$fwName active: Enabled=$($fwRule.Enabled) Action=$($fwRule.Action) Direction=$($fwRule.Direction)$(if (-not $fwGood) { " - the rule was changed: $fwRerun" })"
} catch {
    $fwMissing = "$($_.FullyQualifiedErrorId)" -like 'CmdletizationQuery_NotFound*'
    Add-Check 'Network' 'Outbound SMB to the Internet blocked (firewall rule)' $(if (-not $fwMissing -or $PreRestart) { 'INFO' } else { 'WARN' }) $(if (-not $fwMissing) { "firewall rules not readable: $($_.Exception.Message)" } elseif ($PreRestart) { "$fwName is not in the active firewall rules yet: the firewall loads it from local Group Policy at the restart; validate again afterwards" } else { "$fwName is not among the active firewall rules: Windows would offer your sign-in to any Internet file server a link points at. To put it back, $fwRerun" })
}
# WSL's own firewall (Hyper-V firewall, VM creator ID of WSL): on and inbound blocked by
# default. A WARN only when it was explicitly switched off or opened.
if (Get-Command Get-NetFirewallHyperVVMSetting -ErrorAction SilentlyContinue) {
    try {
        $hvFw = Get-NetFirewallHyperVVMSetting -PolicyStore ActiveStore -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -ErrorAction Stop
        $hvBad = ("$($hvFw.Enabled)" -eq 'False') -or ("$($hvFw.DefaultInboundAction)" -eq 'Allow')
        Add-Check 'Network' 'WSL firewall (Hyper-V firewall) on, inbound blocked' $(if ($hvBad) { 'WARN' } else { 'INFO' }) "Enabled=$($hvFw.Enabled) DefaultInboundAction=$($hvFw.DefaultInboundAction)$(if ($hvBad) { ' - Linux services in WSL are reachable from the network. Back to the default, in an administrator PowerShell: Set-NetFirewallHyperVVMSetting -Name ''{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'' -Enabled True -DefaultInboundAction Block' } else { ' (Windows default; applies to WSL once a distro is installed)' })"
    } catch { }
}

# --- Disks -------------------------------------------------------------------
# Internal disks as Windows judges them (SMART and the storage stack). -Hardware: a VM's
# virtual disk says nothing about the image.
try {
    $pd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { "$($_.BusType)" -notin 'USB', 'SD', 'MMC' })
    $pdBad = @($pd | Where-Object { "$($_.HealthStatus)" -eq 'Unhealthy' }); $pdWarn = @($pd | Where-Object { "$($_.HealthStatus)" -eq 'Warning' })
    $pdState = if ($pdBad.Count) { 'FAIL' } elseif ($pdWarn.Count) { 'WARN' } elseif ($pd.Count -and -not @($pd | Where-Object { "$($_.HealthStatus)" -ne 'Healthy' }).Count) { 'PASS' } else { 'INFO' }
    Add-Check 'Disk' 'Disk health' $pdState "$(($pd | ForEach-Object { "$($_.FriendlyName) ($($_.MediaType), $([math]::Round($_.Size / 1GB)) GB): $($_.HealthStatus), $($_.OperationalStatus)" }) -join '; ')$(if ($pdBad.Count -or $pdWarn.Count) { ' - the disk reports a problem: back up your files NOW (docs/MONTHLY.md, section Offline backup), then check the disk with its maker''s tool and replace it' })" -Hardware
    if ($isAdmin) {
        $rel = @(foreach ($d in $pd) { $c = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue; if ($c) { "$($d.FriendlyName): wear $($c.Wear) %, $($c.Temperature) C, $($c.PowerOnHours) h on, read errors $($c.ReadErrorsUncorrected), write errors $($c.WriteErrorsUncorrected)" } })
        if ($rel.Count) { Add-Check 'Disk' 'Disk reliability counters' 'INFO' "$($rel -join '; ') (empty = the disk doesn't report it; wear counts up to 100 %)" -Hardware }
    }
} catch { Add-Check 'Disk' 'Disk health' 'INFO' "not readable: $($_.Exception.Message)" -Hardware }
$sysVol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
if ($sysVol -and $sysVol.Size) {
    $freePct = [math]::Round(100 * $sysVol.FreeSpace / $sysVol.Size)
    Add-Check 'Disk' 'System drive has 15 % free' $(if ($freePct -ge 15) { 'PASS' } else { 'WARN' }) "$env:SystemDrive $([math]::Round($sysVol.FreeSpace / 1GB)) GB free of $([math]::Round($sysVol.Size / 1GB)) GB ($freePct %)$(if ($freePct -lt 15) { ' - updates, restore points and a rebuild (80 GB) need room: Settings > System > Storage > Cleanup recommendations; old ISOs and VM test files: docs/TROUBLESHOOTING.md, Freeing space' })"
}

# --- Firmware and driver age (information: only the maker's site knows if there is a newer one)
$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
if ($bios -and $bios.ReleaseDate) {
    $biosMonths = [int](((Get-Date) - $bios.ReleaseDate).TotalDays / 30.4)
    Add-Check 'Firmware' 'BIOS age' 'INFO' "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion), $($bios.ReleaseDate.ToString('yyyy-MM-dd')) ($biosMonths months old)$(if ($biosMonths -gt 12) { ' - over a year old: check the PC maker''s support page for a newer BIOS (Windows Update does not deliver firmware on this image; suspend BitLocker before flashing)' })" -Hardware
}
$nv = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { "$($_.AdapterCompatibility)" -match 'NVIDIA' -and $_.DriverDate } | Select-Object -First 1
if ($nv) {
    $nvDays = [int]((Get-Date) - $nv.DriverDate).TotalDays
    Add-Check 'Drivers' 'NVIDIA driver age' 'INFO' "$($nv.Name) driver $($nv.DriverVersion), $($nv.DriverDate.ToString('yyyy-MM-dd')) ($nvDays days old)$(if ($nvDays -gt 150) { ' - NVIDIA fixes security bugs in its drivers several times a year: see https://www.nvidia.com/en-us/security/ and install a newer driver deliberately (NVIDIA App or nvidia.com), then harvest again before the next build' })" -Hardware
}

# --- Logs: how far back they reach --------------------------------------------
$logSpan = {
    param([string]$Log)
    $first = Get-WinEvent -LogName $Log -Oldest -MaxEvents 1 -ErrorAction Stop
    $info = Get-WinEvent -ListLog $Log -ErrorAction Stop
    [pscustomobject]@{ Oldest = $first.TimeCreated; Days = [int]((Get-Date) - $first.TimeCreated).TotalDays; SizeMb = [math]::Round($info.FileSize / 1MB); MaxMb = [math]::Round($info.MaximumSizeInBytes / 1MB); Full = ($info.FileSize -ge 0.9 * $info.MaximumSizeInBytes) }
}
if ($isAdmin) {
    try {
        $ls = & $logSpan 'Security'
        # Under a week of history only matters when the log is full (it wraps), on a PC older than a week
        $lsWarn = $ls.Days -lt 7 -and $ls.Full -and -not (& $pcIsNew 7)
        Add-Check 'Logs' 'Security log reaches back 7 days' $(if ($lsWarn) { 'WARN' } elseif ($ls.Days -ge 7) { 'PASS' } else { 'INFO' }) "oldest event $($ls.Oldest.ToString('yyyy-MM-dd')) ($($ls.Days) days), $($ls.SizeMb) of $($ls.MaxMb) MB used$(if ($lsWarn) { ' - the log is full and overwrites itself in under a week, so an incident could not be traced back. Find what floods it (administrator PowerShell): Get-WinEvent -LogName Security -MaxEvents 20000 | Group-Object Id | Sort-Object Count -Descending | Select-Object -First 5  and see docs/reference/SECURITY-BASELINE.md, section Advanced audit policy' } elseif ($ls.Days -lt 7) { ' (not full yet: it simply starts there)' })"
    } catch { Add-Check 'Logs' 'Security log reaches back 7 days' 'INFO' "not readable: $($_.Exception.Message)" }
}
try {
    $lp2 = & $logSpan 'Microsoft-Windows-PowerShell/Operational'
    Add-Check 'Logs' 'PowerShell log reaches back' 'INFO' "oldest event $($lp2.Oldest.ToString('yyyy-MM-dd')) ($($lp2.Days) days), $($lp2.SizeMb) of $($lp2.MaxMb) MB used"
} catch { }

# The validator's own scheduled run (settings options.scheduledValidation; PostInstall registers it)
$svWanted = (Get-Setting 'options.scheduledValidation') -ne $false
$svTask = Get-ScheduledTask -TaskName 'W11Kit Validate PC' -ErrorAction SilentlyContinue
$svInfo = if ($svTask) { Get-ScheduledTaskInfo -InputObject $svTask -ErrorAction SilentlyContinue }
$svLast = if ($svInfo -and $svInfo.LastRunTime -and $svInfo.LastRunTime.Year -gt 2000) { "last run $($svInfo.LastRunTime.ToString('yyyy-MM-dd HH:mm')), result $($svInfo.LastTaskResult)" } else { 'not run yet' }
Add-Check 'Logs' "Validate PC runs by itself (settings options.scheduledValidation)" $(if (-not $svWanted) { 'INFO' } elseif ($svTask -and "$($svTask.State)" -ne 'Disabled') { 'PASS' } else { 'WARN' }) $(if (-not $svWanted) { "off$(if ($svTask) { ', but the task W11Kit Validate PC is there' })" } elseif (-not $svTask) { 'the task W11Kit Validate PC is missing: run the first-boot setup again, or rebuild' } else { "task W11Kit Validate PC $($svTask.State): Sundays 12:00 and after a Windows Update restart; $svLast (log: C:\ProgramData\W11Kit\Logs\scheduled-validation.txt)" })

# The PowerShell log's size (PostInstall raises it to 256 MB: every script PowerShell
# runs is logged there, and at Windows' 15 MB a build pushes a week of history out).
try {
    $psMax = (Get-WinEvent -ListLog 'Microsoft-Windows-PowerShell/Operational' -ErrorAction Stop).MaximumSizeInBytes
    Add-Check 'Logs' 'PowerShell log size 256 MB' $(if ($psMax -ge 256MB) { 'PASS' } else { 'WARN' }) "maximum $([math]::Round($psMax / 1MB)) MB$(if ($psMax -lt 256MB) { ' - set it again in an administrator PowerShell: wevtutil sl Microsoft-Windows-PowerShell/Operational /ms:268435456' })"
} catch { }
# Sysmon (Windows' built-in System Monitor, enabled by PostInstall with the kit's
# Sysmon-Config.xml; no row for an image without that file). Found as PostInstall finds
# it: service Sysmon or Sysmon64. If the feature needed a restart, the one-time startup
# task "W11Kit Sysmon setup" installs it after PostInstall's restart and deletes itself:
# so in the first-logon snapshot "not running yet" is INFO, afterwards a WARN.
if (Test-Path -LiteralPath 'C:\ProgramData\W11Kit\Sysmon-Config.xml') {
    $smSvc = Get-Service -Name 'Sysmon', 'Sysmon64' -ErrorAction SilentlyContinue | Select-Object -First 1
    $smTask = Get-ScheduledTask -TaskName 'W11Kit Sysmon setup' -ErrorAction SilentlyContinue
    $smMax = try { (Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational' -ErrorAction Stop).MaximumSizeInBytes } catch { $null }
    $smFacts = "service $(if ($smSvc) { "$($smSvc.Name) $($smSvc.Status)" } else { 'not installed' }); log $(if ($null -ne $smMax) { "maximum $([math]::Round($smMax / 1MB)) MB" } else { 'not there' }); one-time setup task $(if ($smTask) { 'still registered' } else { 'gone' })"
    $smFix = 'In an administrator PowerShell: Dism /Online /Enable-Feature /FeatureName:Sysmon /NoRestart  then (after a restart if it asks for one)  sysmon.exe -accepteula -i C:\ProgramData\W11Kit\Sysmon-Config.xml  and  wevtutil sl Microsoft-Windows-Sysmon/Operational /ms:268435456'
    if ($smSvc -and "$($smSvc.Status)" -eq 'Running' -and -not $smTask) {
        Add-Check 'Logs' 'Sysmon running (built into Windows)' $(if ($null -eq $smMax -or $smMax -ge 256MB) { 'PASS' } else { 'WARN' }) "$smFacts$(if ($null -ne $smMax -and $smMax -lt 256MB) { ' - the log is smaller than the kit sets it: wevtutil sl Microsoft-Windows-Sysmon/Operational /ms:268435456 (administrator PowerShell)' })"
    } elseif ($PreRestart) {
        Add-Check 'Logs' 'Sysmon running (built into Windows)' 'INFO' "$smFacts - $(if ($smTask) { 'Windows wants a restart before Sysmon can be installed: the one-time task finishes it after setup''s restart' } else { 'not running in this snapshot: see the Sysmon step in the PostInstall log' }); validate again after the restart"
    } else {
        Add-Check 'Logs' 'Sysmon running (built into Windows)' 'WARN' "$smFacts - Sysmon records nothing (it blocks nothing either way, but its log is what tells you afterwards what a program did).$(if ($smTask) { ' The one-time setup task has not finished: restart the PC once and validate again; its output is C:\ProgramData\W11Kit\Logs\sysmon-setup.txt. If it stays:' }) $smFix"
    }
}

# --- Since the last report -----------------------------------------------------
# What the event logs recorded since the previous report (its time is in
# W11Kit-Validation.json): sign-in failures, new accounts, group changes, new services
# and tasks, Defender detections and blocks, NTLM use. Not in the first-logon snapshot
# (setup itself creates the accounts, tasks and services) and not without an earlier report.
if ($PreRestart) {
    Add-Check 'Since last report' 'Security events since the last report' 'INFO' 'first-logon snapshot: counting starts with this report'
} elseif (-not $prevTime) {
    Add-Check 'Since last report' 'Security events since the last report' 'INFO' 'no earlier report on this PC: counting starts with this one'
} elseif (-not $isAdmin) {
    Add-Check 'Since last report' 'Security events since the last report' 'INFO' "Not elevated - re-run as administrator to count the events since $($prevTime.ToString('yyyy-MM-dd HH:mm'))"
} else {
    $since = $prevTime; $sinceNote = ''
    if ($since -lt (Get-Date).AddDays(-92)) { $since = (Get-Date).AddDays(-92); $sinceNote = ' (the last report is older: the last 92 days are counted)' }
    $sinceText = "since $($since.ToString('yyyy-MM-dd HH:mm'))$sinceNote"
    $evMax = 5000
    $evErr = New-Object System.Collections.Generic.List[string]
    # Bounded: one query per log, by ID and start time, newest $evMax at most.
    $getEv = {
        param([string]$Log, [int[]]$Ids)
        try { Get-WinEvent -FilterHashtable @{ LogName = $Log; Id = $Ids; StartTime = $since } -MaxEvents $evMax -ErrorAction Stop }
        catch { if ("$($_.FullyQualifiedErrorId)" -notlike 'NoMatchingEventsFound*') { $evErr.Add("${Log}: $($_.Exception.Message)") } }
    }
    # An event's named data fields (EventData) as a hashtable
    $evData = {
        param($e)
        $h = @{}
        try { foreach ($d in @(([xml]$e.ToXml()).Event.EventData.Data)) { if ($d.Name) { $h["$($d.Name)"] = "$($d.'#text')" } } } catch { }
        $h
    }
    $top = { param($items, [int]$n = 5) (@($items | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First $n | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ') }
    $capNote = { param($list) if (@($list).Count -ge $evMax) { " (at least: only the newest $evMax are read)" } else { '' } }

    $sec = @(& $getEv 'Security' @(4625, 4720, 4732, 4698, 1102))
    # Windows Setup's own account and group events run as MINWINPC$ (the PC's name during Setup):
    # not findings. A UAC prompt that was cancelled or got the wrong account logs a 4625 from
    # consent.exe with 0xC000010B: counted apart from real failed sign-ins.
    $notSetup = { (& $evData $_)['SubjectUserName'] -ne 'MINWINPC$' }
    $isUac = { $d = & $evData $_; "$($d['ProcessName'])" -like '*\consent.exe' -and "$($d['Status'])" -eq '0xc000010b' }
    $e4625all = @($sec | Where-Object Id -eq 4625); $e4625 = @($e4625all | Where-Object { -not (& $isUac) }); $uacCount = $e4625all.Count - $e4625.Count
    $e4720 = @($sec | Where-Object Id -eq 4720 | Where-Object $notSetup); $e4732 = @($sec | Where-Object Id -eq 4732 | Where-Object $notSetup)
    $e4698 = @($sec | Where-Object Id -eq 4698); $e1102 = @($sec | Where-Object Id -eq 1102)
    Add-Check 'Since last report' 'Failed sign-ins' 'INFO' "$($e4625.Count) $sinceText$(if ($e4625.Count) { ": $(& $top @($e4625 | Select-Object -First 500 | ForEach-Object { (& $evData $_)['TargetUserName'] }))" })$(& $capNote $sec) $(if ($uacCount) { "; plus $uacCount UAC prompt(s) cancelled or answered with the wrong account" }) (10 in a row lock an account for 15 minutes; many for an account you don't use deserve a look)"
    $newAcc = @($e4720 | ForEach-Object { $d = & $evData $_; "$($d['TargetUserName']) (by $($d['SubjectUserName']), $($_.TimeCreated.ToString('yyyy-MM-dd')))" })
    Add-Check 'Since last report' 'No new user accounts' $(if ($newAcc.Count) { 'WARN' } else { 'PASS' }) $(if ($newAcc.Count) { "created $sinceText`: $($newAcc -join '; ') - if that wasn't you, sign in as the administrator, disable it (Disable-LocalUser -Name '<name>'), run a full Defender scan and change your passwords" } else { "none $sinceText" })
    $grpAdd = @($e4732 | ForEach-Object { $d = & $evData $_; $who2 = try { (New-Object Security.Principal.SecurityIdentifier($d['MemberSid'])).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1] } catch { $d['MemberSid'] }; "$who2 -> $($d['TargetUserName']) ($($_.TimeCreated.ToString('yyyy-MM-dd')))" })
    Add-Check 'Since last report' 'No additions to local groups' $(if ($grpAdd.Count) { 'WARN' } else { 'PASS' }) $(if ($grpAdd.Count) { "added $sinceText`: $($grpAdd -join '; ') - expected right after you installed something that makes its own group (Docker, Hyper-V tools) or added a user yourself; otherwise undo it: Remove-LocalGroupMember -Group '<group>' -Member '<name>'" } else { "none $sinceText" })
    Add-Check 'Since last report' 'Security log not cleared' $(if ($e1102.Count) { 'WARN' } else { 'PASS' }) $(if ($e1102.Count) { "cleared $($e1102.Count) time(s) $sinceText, last $(($e1102 | Select-Object -First 1).TimeCreated.ToString('yyyy-MM-dd HH:mm')) - if you didn't clear it yourself, treat the PC as possibly compromised: full Defender scan, new passwords, and consider a reinstall from the stick" } else { "not cleared $sinceText" })
    $tasks = @($e4698 | Select-Object -First 500 | ForEach-Object { (& $evData $_)['TaskName'] } | Where-Object { $_ -and $_ -notlike '\Microsoft\*' } | Sort-Object -Unique)
    Add-Check 'Since last report' 'Scheduled tasks created' 'INFO' "$($e4698.Count) $sinceText$(if ($tasks.Count) { "; outside \Microsoft: $((@($tasks) | Select-Object -First 8) -join ', ')$(if ($tasks.Count -gt 8) { ', ...' })" }) (programs and Windows itself create tasks; look for names you can't place)"

    $svcNew = @(& $getEv 'System' @(7045))
    $svcNames = @($svcNew | Select-Object -First 200 | ForEach-Object { (& $evData $_)['ServiceName'] } | Where-Object { $_ } | Sort-Object -Unique)
    Add-Check 'Since last report' 'Services installed' 'INFO' "$($svcNew.Count) $sinceText$(if ($svcNames.Count) { ": $((@($svcNames) | Select-Object -First 10) -join ', ')$(if ($svcNames.Count -gt 10) { ', ...' })" }) (drivers and installers add services; look for names you can't place)"

    $def = @(& $getEv 'Microsoft-Windows-Windows Defender/Operational' @(1116, 1117, 1121, 1122, 5007, 5013))
    $det = @($def | Where-Object { $_.Id -in 1116, 1117 })
    $detNames = @($det | Select-Object -First 200 | ForEach-Object { (& $evData $_)['Threat Name'] } | Where-Object { $_ } | Sort-Object -Unique)
    Add-Check 'Since last report' 'No malware detections' $(if ($det.Count) { 'WARN' } else { 'PASS' }) $(if ($det.Count) { "$($det.Count) detection event(s) $sinceText`: $((@($detNames) | Select-Object -First 6) -join ', ') - open Windows Security > Virus & threat protection > Protection history: check that each was removed or quarantined, and where it came from" } else { "none $sinceText" })
    # ASR: blocks (1121) and audit-only hits (1122) per rule ID. The PsExec/WMI rule
    # d1e49aac-... is audit-only in the baseline: its count here is the data for deciding
    # whether it can be set to Block.
    $asrLine = { param($evs) $ids = @($evs | Select-Object -First 1000 | ForEach-Object { "$((& $evData $_)['ID'])".ToLowerInvariant() }); if ($ids.Count) { & $top $ids 8 } else { 'none' } }
    $asrBlock = @($def | Where-Object Id -eq 1121); $asrAudit = @($def | Where-Object Id -eq 1122)
    Add-Check 'Since last report' 'Attack surface reduction: blocked' 'INFO' "$($asrBlock.Count) $sinceText`: $(& $asrLine $asrBlock) (by rule ID; a rule that blocks a program you trust: Windows Security > Protection history shows which)"
    $psexecHits = @($asrAudit | Select-Object -First 1000 | Where-Object { "$((& $evData $_)['ID'])" -ieq 'd1e49aac-8f56-4280-b9ba-993a6d77406c' }).Count
    Add-Check 'Since last report' 'Attack surface reduction: audited only' 'INFO' "$($asrAudit.Count) $sinceText`: $(& $asrLine $asrAudit); PsExec/WMI process-creation rule d1e49aac-8f56-4280-b9ba-993a6d77406c: $psexecHits (0 over a month of normal use means it could be set to Block: docs/reference/SECURITY-BASELINE.md, 'Considered, not adopted')"
    Add-Check 'Since last report' 'Defender settings changed / tamper protection' 'INFO' "$(@($def | Where-Object Id -eq 5007).Count) configuration change(s), $(@($def | Where-Object Id -eq 5013).Count) change(s) stopped by tamper protection $sinceText$(& $capNote $def) (signature updates and builds change settings too)"

    # NTLM (the old sign-in protocol) is audited, not blocked: who still uses it
    $ntlm = @(& $getEv 'Microsoft-Windows-NTLM/Operational' @(8001, 8002, 8003))
    $ntlmTargets = @($ntlm | Where-Object Id -eq 8001 | Select-Object -First 500 | ForEach-Object { (& $evData $_)['TargetName'] })
    Add-Check 'Since last report' 'NTLM use (audited)' 'INFO' "outgoing $(@($ntlm | Where-Object Id -eq 8001).Count), incoming $(@($ntlm | Where-Object { $_.Id -in 8002, 8003 }).Count) $sinceText$(if ($ntlmTargets.Count) { "; outgoing to: $(& $top $ntlmTargets 6)" }) (old NAS boxes and printers use NTLM; nothing is blocked)"
    if ($evErr.Count) { Add-Check 'Since last report' 'Event logs readable' 'INFO' "some logs could not be read, their counts above are incomplete: $($evErr -join '; ')" }
}

# What changed since the last report: drivers from outside Windows (oem*.inf), services and
# their start types, enabled inbound allow rules of the firewall. Each is a sorted list of
# texts in the JSON (inventory), compared with the earlier report's. $null: not readable here.
$inv = [ordered]@{ drivers = $null; services = $null; firewallInbound = $null }
try { $inv.drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { "$($_.InfName)" -like 'oem*.inf' } | ForEach-Object { "$($_.DriverProviderName) $($_.DriverVersion): $($_.DeviceName)" } | Sort-Object -Unique) } catch { }
# A per-user service's instance (CDPUserSvc_1a2b3c) has a new suffix at each sign-in: its template is kept
try { $inv.services = @(Get-CimInstance Win32_Service -ErrorAction Stop | ForEach-Object { "$($_.Name -replace '_[0-9a-f]{4,8}$', '_*') ($($_.StartMode))" } | Sort-Object -Unique) } catch { }
try { $inv.firewallInbound = @(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Inbound -Enabled True -Action Allow -ErrorAction Stop | ForEach-Object { "$($_.DisplayName)" } | Sort-Object -Unique) } catch { }
$invNames = [ordered]@{ drivers = 'Drivers (not from Windows) since the last report'; services = 'Services and start types since the last report'; firewallInbound = 'Inbound firewall rules allowed since the last report' }
foreach ($k in @($invNames.Keys)) {
    $before = if ($prevJson -and $prevJson.inventory) { $prevJson.inventory.$k } else { $null }
    if ($null -eq $inv[$k]) { Add-Check 'Since last report' $invNames[$k] 'INFO' "Not compared: not readable here$(if (-not $isAdmin) { ' (run elevated)' })"; continue }
    if ($null -eq $before) { Add-Check 'Since last report' $invNames[$k] 'INFO' "$(@($inv[$k]).Count) now; the last report has none to compare with: comparing starts with this one"; continue }
    $added = @($inv[$k] | Where-Object { @($before) -notcontains $_ })
    $gone = @(@($before) | Where-Object { $inv[$k] -notcontains $_ })
    $show = { param($l) "$((@($l) | Select-Object -First 8) -join '; ')$(if (@($l).Count -gt 8) { '; ...' })" }
    Add-Check 'Since last report' $invNames[$k] 'INFO' $(if (-not $added.Count -and -not $gone.Count) { "no change ($(@($inv[$k]).Count))" } else { "$(if ($added.Count) { "new or changed ($($added.Count)): $(& $show $added)" })$(if ($added.Count -and $gone.Count) { ' | ' })$(if ($gone.Count) { "gone or changed before ($($gone.Count)): $(& $show $gone)" })" })
}

# --- Report ------------------------------------------------------------------
$fails = @($results | Where-Object State -eq 'FAIL').Count
$warns = @($results | Where-Object State -eq 'WARN').Count
$title = "# $hwName validation - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$note = if ($PreRestart) { '**Pre-restart snapshot** taken during setup: VBS, UAC settings and some policies take effect only after the restart. Run "Validate PC" (desktop) again after signing in.' } else { "Run as $env:USERDOMAIN\$env:USERNAME after $(((Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString('yyyy-MM-dd HH:mm')) boot." }
# How the rows are grouped for people (here only: the rows, their areas and names, and the
# .json stay as they are). An area that is not listed (a profile's own device checks may
# name any area) goes with the devices when it is a hardware row, else under 'Other'.
$groupAreas = [ordered]@{
    'Windows and updates'         = 'OS', 'Updates', 'Recovery', 'Firmware'
    'Security policy'             = 'Security', 'Baseline', 'Override', 'STIG', 'Conflicts', 'Browser'
    'Accounts and privacy'        = 'Account', 'Privacy'
    'Network and remote access'   = 'Network', 'Remote', 'Services'
    'Devices, drivers and power'  = 'GPU', 'Audio', 'Bluetooth', 'Devices', 'Drivers', 'Power', 'Disk'
    'Apps and tools'              = 'Apps', 'Store/Gaming', 'Runtimes', 'WSL', 'Dev', 'Self-hosting'
    'Backup and logs'             = 'Backup', 'Logs'
    'Since last report'           = 'Since last report'
}
$areaGroup = @{}
foreach ($g in $groupAreas.Keys) { foreach ($a in @($groupAreas[$g])) { $areaGroup[$a] = $g } }
$groupNames = @($groupAreas.Keys) + @('Other')
$byGroup = @{}
foreach ($g in $groupNames) { $byGroup[$g] = New-Object System.Collections.Generic.List[object] }
foreach ($r in $results) {
    $g = if ($areaGroup.ContainsKey("$($r.Area)")) { $areaGroup["$($r.Area)"] } elseif ($r.Hardware) { 'Devices, drivers and power' } else { 'Other' }
    $byGroup[$g].Add($r)
}
$countOf = { param($Rows, [string]$State) @($Rows | Where-Object State -eq $State).Count }
# What to look at: every FAIL row, then every WARN row, each in the order it was checked
$attention = @($results | Where-Object State -eq 'FAIL') + @($results | Where-Object State -eq 'WARN')
$mdRow = { param($r) "| $($r.Area) | $($r.Check) | $($r.State) | $(($r.Detail -replace '\|', '/')) |" }
$mdHead = '| Area | Check | Result | Detail |', '|---|---|---|---|'

$md = New-Object System.Collections.Generic.List[string]
foreach ($l in $title, '', $note, '', "Hardware profile: $(if ($hw) { "$($hw.id)" } else { 'not readable' })", '', "FAIL: $fails  WARN: $warns", '', '## Needs attention', '') { $md.Add($l) }
if ($attention.Count) {
    foreach ($r in $attention) {
        $md.Add("- **$($r.State)** $($r.Area): $($r.Check)")
        if ("$($r.Detail)".Trim()) { $md.Add("  $("$($r.Detail)".Trim())") }
        if ($r.Fix) { $md.Add("  Fix: $($r.Fix)") }
    }
} else { $md.Add('Nothing: no row is FAIL or WARN.') }
# A section per group: its PASS, WARN and FAIL rows. INFO rows (facts, nothing to judge)
# and the 'Since last report' rows (event counts) have sections of their own below.
foreach ($g in $groupNames) {
    if ($g -eq 'Since last report') { continue }
    $judged = @($byGroup[$g] | Where-Object State -ne 'INFO')
    if (-not $judged.Count) { continue }
    $md.Add(''); $md.Add("## $g"); $md.Add('')
    $md.Add("PASS: $(& $countOf $judged 'PASS')  WARN: $(& $countOf $judged 'WARN')  FAIL: $(& $countOf $judged 'FAIL')"); $md.Add('')
    foreach ($l in $mdHead) { $md.Add($l) }
    foreach ($r in $judged) { $md.Add((& $mdRow $r)) }
}
$infoRows = @($results | Where-Object { $_.State -eq 'INFO' -and $_.Area -ne 'Since last report' })
if ($infoRows.Count) {
    $md.Add(''); $md.Add('## For information'); $md.Add('')
    $md.Add('Facts about this PC: nothing to do.'); $md.Add('')
    foreach ($l in $mdHead) { $md.Add($l) }
    foreach ($r in $infoRows) { $md.Add((& $mdRow $r)) }
}
if ($byGroup['Since last report'].Count) {
    $md.Add(''); $md.Add('## Since last report'); $md.Add('')
    $md.Add('What the event logs recorded since the report before this one.'); $md.Add('')
    foreach ($l in $mdHead) { $md.Add($l) }
    foreach ($r in $byGroup['Since last report']) { $md.Add((& $mdRow $r)) }
}
# Machine-readable copy for the VM test graders and others' tooling (UTF-8 without BOM).
# schemaVersion: a new field leaves it; a renamed, removed or retyped field raises it
# (docs/TROUBLESHOOTING.md, "The validator's report"). .ToArray(): a generic List inside an
# [ordered] literal throws in PS 5.1, and a one-row array must stay an array.
$rows = New-Object System.Collections.Generic.List[object]
foreach ($r in $results) { $rows.Add([ordered]@{ area = "$($r.Area)"; check = "$($r.Check)"; result = "$($r.State)"; detail = "$($r.Detail)"; hardware = [bool]$r.Hardware; fix = "$($r.Fix)" }) }
$json = [ordered]@{
    schemaVersion = 1
    kitRevision = $(if ($bo -and $bo.KitRevision) { "$($bo.KitRevision)" } else { $null })
    profile = $(if ($hw) { "$($hw.id)" } else { $null })
    osBuild = "$($cv.CurrentBuild).$($cv.UBR)"
    inventory = $inv
    generated = (Get-Date).ToString('s')
    preRestart = [bool]$PreRestart
    # The same numbers as the window, and the code -ExitCode exits with
    summary = [ordered]@{ fail = $fails; warn = $warns; pass = @($results | Where-Object State -eq 'PASS').Count; info = @($results | Where-Object State -eq 'INFO').Count; exitCode = $(if ($fails) { 2 } elseif ($warns) { 1 } else { 0 }) }
    rows = $rows.ToArray()
} | ConvertTo-Json -Depth 5
$utf8 = New-Object System.Text.UTF8Encoding $false
$targets = @('C:\ProgramData\W11Kit', "$env:PUBLIC\Desktop")
$written = @()
foreach ($t in $targets) {
    if ($t -and (Test-Path $t)) {
        try {
            $md | Set-Content (Join-Path $t 'W11Kit-Validation.md') -Encoding UTF8 -ErrorAction Stop
            [IO.File]::WriteAllText((Join-Path $t 'W11Kit-Validation.json'), $json, $utf8)
            $written += $t
        } catch { }
    }
}
if (-not $written.Count) {
    # Not elevated: the Public desktop and W11Kit folder are admin-only
    $own = [Environment]::GetFolderPath('Desktop')
    $md | Set-Content (Join-Path $own 'W11Kit-Validation.md') -Encoding UTF8
    [IO.File]::WriteAllText((Join-Path $own 'W11Kit-Validation.json'), $json, $utf8)
    $written += $own
}

if ($All) {
    $results | Format-Table Area, Check, State, Detail -AutoSize -Wrap | Out-String -Width 220 | Write-Host
} else {
    # The window's width (100 when there is no window to ask, e.g. output into a file)
    $width = 100
    try { $w = [int]$Host.UI.RawUI.WindowSize.Width; if ($w -ge 60) { $width = [Math]::Min($w, 160) } } catch { }
    # Text as lines of at most $Width characters, each starting with $Indent; a word longer
    # than a line (a path, a command) is cut
    function Format-Wrapped([string]$Text, [int]$Width, [string]$Indent) {
        $room = [Math]::Max(20, $Width - $Indent.Length - 1)
        $lines = New-Object System.Collections.Generic.List[string]
        $line = ''
        foreach ($word in @("$Text" -split '\s+' | Where-Object { $_ })) {
            while ($word.Length -gt $room) {
                if ($line) { $lines.Add($line); $line = '' }
                $lines.Add($word.Substring(0, $room)); $word = $word.Substring($room)
            }
            if (-not $line) { $line = $word }
            elseif ($line.Length + 1 + $word.Length -le $room) { $line += ' ' + $word }
            else { $lines.Add($line); $line = $word }
        }
        if ($line) { $lines.Add($line) }
        foreach ($l in $lines) { $Indent + $l }
    }
    Write-Host ''
    Write-Host ($title -replace '^# ', '')
    if ($PreRestart) { Write-Host 'Snapshot before the first restart: some settings take effect only after it.' }
    Write-Host ''
    if ($attention.Count) {
        Write-Host "NEEDS ATTENTION ($fails FAIL, $warns WARN)"
        foreach ($r in $attention) {
            $color = if ($r.State -eq 'FAIL') { 'Red' } else { 'Yellow' }
            foreach ($l in @(Format-Wrapped "$($r.Area): $($r.Check)" $width "  $($r.State)  ")) { Write-Host $l -ForegroundColor $color }
            foreach ($l in @(Format-Wrapped "$($r.Detail)" $width '        ')) { Write-Host $l }
            if ($r.Fix) { foreach ($l in @(Format-Wrapped "Fix: $($r.Fix)" $width '        ')) { Write-Host $l } }
        }
    } else {
        Write-Host 'Nothing needs attention: no row is FAIL or WARN.' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host ('{0,-30} {1,5} {2,5} {3,5} {4,5}' -f 'ALL CHECKS, BY GROUP', 'PASS', 'INFO', 'WARN', 'FAIL')
    foreach ($g in $groupNames) {
        $rowsOf = $byGroup[$g]
        if (-not $rowsOf.Count) { continue }
        $gf = & $countOf $rowsOf 'FAIL'; $gw = & $countOf $rowsOf 'WARN'
        Write-Host ('{0,-30} {1,5} {2,5} {3,5} {4,5}' -f $g, (& $countOf $rowsOf 'PASS'), (& $countOf $rowsOf 'INFO'), $gw, $gf) -ForegroundColor $(if ($gf) { 'Red' } elseif ($gw) { 'Yellow' } else { 'Gray' })
    }
    Write-Host ''
    Write-Host 'PASS = as it should be; INFO = a fact, nothing to do; WARN = look at it; FAIL = not as the image was built.'
    Write-Host 'Every row is in the report file. As one table in this window: Validate-Pc.cmd -All'
}
Write-Host "FAIL: $fails  WARN: $warns  (report: $(($written | ForEach-Object { Join-Path $_ 'W11Kit-Validation.md' }) -join ', '); .json alongside)" -ForegroundColor $(if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' })
if ($ExitCode) { exit $(if ($fails) { 2 } elseif ($warns) { 1 } else { 0 }) }
