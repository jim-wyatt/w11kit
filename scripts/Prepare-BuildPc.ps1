<#
.SYNOPSIS
    Readies a Windows PC to build (and VM-test) the W11Kit ISO: the one entry
    point for a build PC. Run elevated (Run-Prepare.cmd). Idempotent: run it as
    often as you like.

.DESCRIPTION
    Checks, and fixes only where it is safe to:
      - Windows 11 Pro / Enterprise / Education, build 26100 (24H2) or later
        (Home: not supported as a build PC, no Hyper-V for the VM test: stop),
        on an x64 processor (ARM64: stop; the kit builds x64 images only)
      - virtualization enabled in the firmware
      - Defender Controlled Folder Access off and the ASR rule "Block executable
        files unless they meet a prevalence, age or trusted list criterion" not
        in Block mode: both break the build. Reported with how to fix; this
        script never changes Defender policy.
      - 80 GB free on the system drive and on the work folder's (build inputs)
      - leftovers of an interrupted build or VM test: Defender ASR exclusions for
        the build's own work folders are removed, and a VM-test ISO left in
        <work>\vmtest (it erases disk 0 without asking) is deleted. -Check only
        reports them.
      - the build chain (scripts\Install-BuildTools.ps1): Git for Windows,
        Python 3, the Windows ADK Deployment Tools (oscdimg), and Hyper-V for
        the VM test (Run-VmTest.cmd; restart needed). What is missing is
        OFFERED: it asks before installing anything (-Yes: don't ask).
    The image never runs this: a normal install has none of these tools. They
    come only when you want to build (this script, or Run-Build.cmd, which runs
    it with -ForBuild when a build tool is missing).
    Prints a checklist. Exit code: 0 ready, 3010 ready after a restart,
    1 something blocks the build.

.PARAMETER Check
    Report only: change nothing (works without elevation, with fewer details).
.PARAMETER Yes
    Install the missing build tools (and Hyper-V, unless -SkipHyperV) without asking.
.PARAMETER SkipHyperV
    Don't offer Hyper-V (you don't want the VM test on this PC).
.PARAMETER ForBuild
    Run-Build.cmd's mode: if Git, Python and the ADK are all there, return at
    once and silently; otherwise ask once whether to install them, then run the
    checks and install them (no Hyper-V). Answering no continues the build.
.PARAMETER WorkRoot
    The build's work folder (its drive is checked too). Default <KitRoot>\work.
.PARAMETER KitRoot
    The kit folder. Needed when loaded as a scriptblock ($PSScriptRoot empty).
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Yes,
    [switch]$SkipHyperV,
    [switch]$ForBuild,
    [string]$WorkRoot,   # default: <KitRoot>\work
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
if (-not $KitRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
$KitRoot = "$KitRoot".TrimEnd('\')
if (-not $WorkRoot) { $WorkRoot = Join-Path $KitRoot 'work' }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Check) { throw 'Run elevated (use Run-Prepare.cmd), or add -Check to only report.' }

# The build chain lives in one script; loaded as a scriptblock like the launchers do (.ps1 may be blocked)
$installToolsSb = [scriptblock]::Create((Get-Content -Raw -LiteralPath (Join-Path $KitRoot 'scripts\Install-BuildTools.ps1')))
function Invoke-BuildTools([string[]]$Tools, [switch]$CheckOnly) {
    & $installToolsSb -KitRoot $KitRoot -WorkRoot $WorkRoot -Tools $Tools -Check:$CheckOnly -PassThru
}

# Run-Build.cmd: the build is the trigger. Nothing to do (and nothing printed) when the tools are there.
if ($ForBuild) {
    $missing = @(Invoke-BuildTools -Tools git, python, adk -CheckOnly | Where-Object State -ne 'OK')
    if (-not $missing.Count) { exit 0 }
    $list = ($missing | ForEach-Object Name) -join ', '
    Write-Host ''
    Write-Host "This PC is missing the build tools ($list)." -ForegroundColor Yellow
    Write-Host 'They are installed only on a PC that builds, never in the image; from the official installers'
    Write-Host 'pinned in config\installers.json (SHA-256 and signature checked).'
    if (-not $Yes) {
        $answer = Read-Host 'Install them now? [Y/n]'
        if ($answer -match '^\s*n') {
            Write-Host 'Not installed. Continuing: the build''s pre-flight says what it still needs.' -ForegroundColor Yellow
            exit 0
        }
    }
    $Yes = $true; $SkipHyperV = $true   # the build doesn't need Hyper-V; Run-Prepare.cmd offers it
    Write-Host ''
}

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row([string]$State, [string]$Item, [string]$Detail, [string]$Fix = '') {
    # State: OK, BLOCK (the build can't run), FAIL (an install failed), WARN (works, but read this), DONE (changed now), INFO
    $rows.Add([pscustomobject]@{ State = $State; Item = $Item; Detail = $Detail; Fix = $Fix })
    $color = switch ($State) { 'OK' { 'Gray' } 'DONE' { 'Green' } 'BLOCK' { 'Red' } 'FAIL' { 'Red' } 'WARN' { 'Yellow' } default { 'Gray' } }
    Write-Host ("  [{0,-5}] {1}: {2}" -f $State, $Item, $Detail) -ForegroundColor $color
    if ($Fix) { Write-Host "          -> $Fix" -ForegroundColor $color }
}
$restart = $false
Write-Host "Preparing this PC as a W11Kit build PC$(if ($Check) { ' (-Check: report only, nothing is changed)' })"
Write-Host ''

# --- Windows edition and version --------------------------------------------------------
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$edition = "$($cv.EditionID)"
$build = [Environment]::OSVersion.Version.Build
$okEdition = $edition -match '^(Professional|ProfessionalWorkstation|ProfessionalEducation|Enterprise|EnterpriseS|Education|IoTEnterprise|IoTEnterpriseS)(N)?$'
if ($okEdition) { Add-Row 'OK' 'Windows edition' "$($cv.ProductName -replace 'Windows 10', 'Windows 11') ($edition)" }
elseif ($edition -match '^Core') {
    Add-Row 'BLOCK' 'Windows edition' "Windows 11 Home ($edition)" 'Home cannot host the VM test (no Hyper-V) and is not supported as a build PC. Build on a Pro/Enterprise/Education PC, or upgrade this one to Pro (Settings > System > Activation).'
} else { Add-Row 'BLOCK' 'Windows edition' "$edition is not Windows 11 Pro/Enterprise/Education" 'Use a Windows 11 Pro, Enterprise or Education PC.' }
if ($build -ge 26100) { Add-Row 'OK' 'Windows version' "build $build.$($cv.UBR) ($($cv.DisplayVersion))" }
else { Add-Row 'BLOCK' 'Windows version' "build $build" 'Servicing a 26H2 image needs a 24H2 (26100) or later host DISM: update Windows first.' }
# x64 only. Win32_Processor reports the real processor (9 = x64, 12 = ARM64), even to an
# emulated x64 PowerShell on an ARM64 PC.
$cpu = @(Get-CimInstance Win32_Processor)[0]
$arch = [int]$cpu.Architecture
if ($arch -eq 9) { Add-Row 'OK' 'Processor architecture' 'x64' }
else { Add-Row 'BLOCK' 'Processor architecture' $(if ($arch -eq 12) { 'ARM64' } else { "not x64 (Win32_Processor.Architecture $arch)" }) 'The kit builds on an x64 PC and makes x64 images only. Build on an x64 PC.' }

# --- Managed by an employer or school? --------------------------------------------------
# The kit sets local policy, folder permissions and Defender exclusions, and installs tools: on a
# managed PC that fights the management. No translated tool text: domain membership (CIM), a
# Microsoft Entra join (CloudDomainJoin\JoinInfo), and an MDM enrolment by Windows' own
# IsDeviceRegisteredWithManagement (mdmregistration.dll; the Enrollments key also holds Windows'
# own entries on every PC, so it can't tell).
$mgd = New-Object System.Collections.Generic.List[string]
$csInfo = Get-CimInstance Win32_ComputerSystem
if ($csInfo.PartOfDomain) { $mgd.Add("joined to the domain $($csInfo.Domain)") }
if (@(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo' -ErrorAction SilentlyContinue).Count) { $mgd.Add('joined to Microsoft Entra ID') }
$mdmNote = ''
try {
    if (-not ('W11Kit.Mdm' -as [type])) { Add-Type -Namespace W11Kit -Name Mdm -MemberDefinition '[DllImport("mdmregistration.dll", CharSet = CharSet.Unicode)] public static extern int IsDeviceRegisteredWithManagement(out bool isRegistered, int cchUpn, System.Text.StringBuilder upn);' }
    $mdmUpn = New-Object System.Text.StringBuilder 512; $mdmOn = $false
    $hr = [W11Kit.Mdm]::IsDeviceRegisteredWithManagement([ref]$mdmOn, $mdmUpn.Capacity, $mdmUpn)
    if ($hr -ne 0) { $mdmNote = "; device management not readable (0x$('{0:x8}' -f $hr))" }
    elseif ($mdmOn) { $mgd.Add('enrolled in device management (MDM)') }
} catch { $mdmNote = "; device management not readable ($($_.Exception.Message))" }
if ($mgd.Count) { Add-Row 'WARN' 'Not managed by an employer or school' ($mgd -join '; ') 'The kit sets local policy, folder permissions and Defender exclusions on this PC, and installs build tools: that can fight the management. Build on a PC of your own, or ask whoever manages this one.' }
else { Add-Row 'OK' 'Not managed by an employer or school' "no domain, no Microsoft Entra join, no device management enrolment$mdmNote" }

# --- Virtualization ---------------------------------------------------------------------
$cs = Get-CimInstance Win32_ComputerSystem
# With a hypervisor running (Hyper-V, VBS, WSL2), Windows reports VirtualizationFirmwareEnabled
# as False: a running hypervisor proves virtualization is on.
$virtOn = [bool]$cs.HypervisorPresent -or [bool]$cpu.VirtualizationFirmwareEnabled
if ($virtOn) { Add-Row 'OK' 'Virtualization in firmware' $(if ($cs.HypervisorPresent) { 'on (a hypervisor is running)' } else { 'on' }) }
else { Add-Row 'WARN' 'Virtualization in firmware' 'off' 'Enable it in the BIOS/UEFI (AMD: SVM Mode; Intel: Intel Virtualization Technology / VT-x). The build works without it; the VM test does not.' }

# --- Hyper-V: checked and offered with the build tools below ------------------------------
$wantHyperV = -not $SkipHyperV
if ($ForBuild) {
    # Run-Build.cmd's mode: the build doesn't need Hyper-V; Run-Prepare.cmd offers it
} elseif ($SkipHyperV) {
    Add-Row 'INFO' 'Hyper-V' 'skipped (-SkipHyperV): the VM test (Run-VmTest.cmd) needs it'
} elseif (-not $okEdition) {
    $wantHyperV = $false
    Add-Row 'INFO' 'Hyper-V' 'not available on this edition'
}

# --- Defender: Controlled Folder Access and the prevalence ASR rule ---------------------------
$mpp = try { Get-MpPreference } catch { $null }
if (-not $mpp) {
    Add-Row 'INFO' 'Microsoft Defender' "preferences not readable (another antivirus?): check that it does not block DISM in $WorkRoot"
} else {
    $cfa = [int]$mpp.EnableControlledFolderAccess
    $egKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard'
    $cfaPolicy = $null -ne (Get-ItemProperty "$egKey\Controlled Folder Access" -ErrorAction SilentlyContinue).EnableControlledFolderAccess
    switch ($cfa) {
        # Set as a Defender preference (as the kit's image does), a build pauses it with your consent
        # (Run-Build.cmd asks) and restores it. Set by policy, only whoever set it can change it.
        1 { if ($cfaPolicy) { Add-Row 'BLOCK' 'Controlled Folder Access' 'on, set by policy: it blocks DISM while servicing the image, and a build cannot pause it' 'Set it to Not configured or Audit where the policy comes from (gpedit: Microsoft Defender Antivirus > Microsoft Defender Exploit Guard > Controlled Folder Access), or build on another PC.' } else { Add-Row 'OK' 'Controlled Folder Access' 'on: Run-Build.cmd asks before pausing it for the build, and turns it back on afterwards' } }
        3 { Add-Row 'WARN' 'Controlled Folder Access' 'block disk modification only' 'If the build fails with access denied, turn Controlled folder access off.' }
        default { Add-Row 'OK' 'Controlled Folder Access' $(if ($cfa -eq 2) { 'audit only' } else { 'off' }) }
    }
    $ids = @($mpp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLower() })
    $acts = @($mpp.AttackSurfaceReductionRules_Actions)
    $prevId = '01443614-cd74-433a-b99e-2ecdc07bfc25'   # executables need prevalence, age or trusted list
    $pi = [array]::IndexOf($ids, $prevId)
    $prevAct = if ($pi -ge 0) { [int]$acts[$pi] } else { 0 }
    switch ($prevAct) {
        1 { if ($null -ne (Get-ItemProperty "$egKey\ASR\Rules" -ErrorAction SilentlyContinue).$prevId) { Add-Row 'BLOCK' 'ASR prevalence rule' 'Block, set by policy: it blocks the self-built tools the build runs, and a build cannot pause it' "Set rule $prevId to Audit (2) or Not configured where it is set (gpedit: Microsoft Defender Antivirus > Microsoft Defender Exploit Guard > Attack Surface Reduction), or build on another PC." } else { Add-Row 'OK' 'ASR prevalence rule' 'Block: Run-Build.cmd asks before setting it to audit for the build, and back to block afterwards' } }
        6 { Add-Row 'WARN' 'ASR prevalence rule' 'Warn mode: background tools are blocked without a prompt' "Set rule $prevId to Audit (2) or Not configured." }
        default { Add-Row 'OK' 'ASR prevalence rule' $(if ($prevAct -eq 2) { 'audit only' } else { 'not configured' }) }
    }
    $ci = [array]::IndexOf($ids, 'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb')
    if ($ci -ge 0 -and [int]$acts[$ci] -in 1, 6) { Add-Row 'INFO' 'ASR copied-system-tools rule' 'on: the build excludes its own work folders while it runs (nothing to do)' }
}

# --- Leftovers of an interrupted build or VM test -----------------------------------------
# The build excludes its DISM folders from Defender's ASR rules while it runs and removes
# the exclusions when it ends; a build that was killed leaves them. Removed here, unless a
# build is running in another window: it holds the mutex Global\W11KitBuild (Windows
# releases it when that process ends), or has an image mounted in one of the folders.
# Where policy hides exclusions (Get-MpPreference returns 'N/A: ...') none can be seen, so
# the removal doesn't depend on reading them: removing a path that isn't excluded changes nothing.
$asrDirs = @('mount', 'mount-re', 'mount-boot', 'scratch' | ForEach-Object { Join-Path $WorkRoot.TrimEnd('\') $_ })
$asrSeen = @(try { @($mpp.AttackSurfaceReductionOnlyExclusions) | Where-Object { $_ -and $asrDirs -contains "$_".TrimEnd('\') } } catch { })
$buildMounts = @(try { Get-WindowsImage -Mounted -ErrorAction Stop | ForEach-Object { "$($_.Path)".TrimEnd('\') } | Where-Object { $asrDirs -contains $_ } } catch { })
$buildRunning = $false
try { $mx = $null; $buildRunning = [Threading.Mutex]::TryOpenExisting('Global\W11KitBuild', [ref]$mx); if ($mx) { $mx.Dispose() } }
catch [UnauthorizedAccessException] { $buildRunning = $true }   # it exists, held by another account
catch { }
if ($Check) {
    if ($asrSeen.Count) { Add-Row 'WARN' 'Defender ASR exclusions left by an interrupted build' ($asrSeen -join ', ') 'Run-Prepare.cmd (without -Check) or the next build removes them.' }
} elseif ($buildRunning -or $buildMounts.Count) {
    Add-Row 'INFO' 'Defender ASR exclusions of the build' "not touched: $(if ($buildRunning) { 'a build is running on this PC' } else { "an image is mounted in $($buildMounts -join ', ') (a build is running, or one was interrupted: the next build cleans up)" })"
} elseif ($mpp) {
    try {
        Remove-MpPreference -AttackSurfaceReductionOnlyExclusions $asrDirs -ErrorAction Stop
        if ($asrSeen.Count) { Add-Row 'DONE' 'Defender ASR exclusions left by an interrupted build' "removed: $($asrSeen -join ', ')" }
    } catch {
        if ($asrSeen.Count) { Add-Row 'WARN' 'Defender ASR exclusions left by an interrupted build' "$($asrSeen -join ', '): not removed ($($_.Exception.Message))" 'Windows Security > Virus & threat protection > Manage settings > Exclusions shows them; the next build tries again.' }
    }
}
# The Hyper-V test's copy of an ISO erases disk 0 without asking. The test deletes it when
# it ends; one left by a test that was killed is deleted here (not while a test VM uses it).
$vmTestIso = Join-Path $WorkRoot.TrimEnd('\') 'vmtest\W11Kit-VMTEST-ONLY-wipes-disk.iso'
if (Test-Path -LiteralPath $vmTestIso) {
    $wipes = 'It erases disk 0 without asking: never write it to a USB stick.'
    if ($Check) { Add-Row 'WARN' 'VM-test ISO left behind' $vmTestIso "$wipes Run-Prepare.cmd (without -Check) or the next build deletes it." }
    else {
        Remove-Item -LiteralPath $vmTestIso -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $vmTestIso) { Add-Row 'WARN' 'VM-test ISO left behind' "$vmTestIso could not be deleted (is a VM test running?)" "$wipes Delete it when the test has ended." }
        else { Add-Row 'DONE' 'VM-test ISO left behind' "deleted $vmTestIso (left by an interrupted VM test)" }
    }
}

# --- Disk space -------------------------------------------------------------------------
$sysDrive = $env:SystemDrive.TrimEnd(':')
foreach ($d in @($sysDrive, $WorkRoot.Substring(0, 1)) | Sort-Object -Unique) {
    $free = [math]::Round((Get-PSDrive $d).Free / 1GB)
    if ($free -ge 80) { Add-Row 'OK' "Free space on ${d}:" "$free GB" }
    else { Add-Row 'BLOCK' "Free space on ${d}:" "$free GB (need 80: work folder, image, build inputs)" 'Free up space, or build with -WorkRoot on a bigger drive (with -NoBuildInputs 40 GB is enough).' }
}

# --- Kit location -----------------------------------------------------------------------
if ($KitRoot -match '^\\\\') { Add-Row 'WARN' 'Kit location' $KitRoot 'Copy the kit to a local folder (e.g. C:\W11Kit): the elevated admin may not see network or \\wsl.localhost paths.' }
elseif ($KitRoot) { Add-Row 'OK' 'Kit location' $KitRoot }

# --- Build chain: Git, Python, ADK Deployment Tools (+ Hyper-V for the VM test) -----------
# Never in the image: installed here, on a PC that builds, and only after you say yes (or -Yes).
$toolList = @('git', 'python', 'adk')
if ($wantHyperV) { $toolList += 'hyperv' }
$why = @{
    git    = 'a real build bundles the kit into the ISO (or build with -NoBuildInputs)'
    python = 'the build imports Microsoft''s security baselines with it, and the download scripts need it'
    adk    = 'oscdimg writes the ISO (the build would install it itself)'
    hyperv = 'the VM test, Run-VmTest.cmd (restart needed)'
}
$offer = New-Object System.Collections.Generic.List[object]
foreach ($r in @(Invoke-BuildTools -Tools $toolList -CheckOnly)) {
    switch ($r.State) {
        'OK' {
            if ($r.Restart) { $restart = $true; Add-Row 'WARN' $r.Name 'enabled, restart pending' 'Restart Windows before the VM test.' }
            else { Add-Row 'OK' $r.Name ("$($r.Version)  $($r.Path)").Trim() }
        }
        'N/A' { Add-Row 'WARN' $r.Name $r.Detail }
        'UNKNOWN' { Add-Row 'INFO' $r.Name $r.Detail }
        default {
            $offer.Add($r)
            Add-Row 'WARN' $r.Name "not installed: $($why[$r.Tool])" $(if ($Check) { 'Run-Prepare.cmd (without -Check) offers to install it.' })
        }
    }
}
if ($offer.Count -and -not $Check) {
    $go = [bool]$Yes
    if (-not $go) {
        Write-Host ''
        Write-Host "Missing: $(($offer | ForEach-Object Name) -join ', ')." -ForegroundColor Yellow
        Write-Host 'They come from the official installers pinned in config\installers.json (SHA-256 and signature'
        Write-Host 'checked), installed for all users. Only this build PC gets them, never the image.'
        if (@($offer | Where-Object Tool -eq 'hyperv').Count) { Write-Host 'Hyper-V needs a restart afterwards.' }
        $go = (Read-Host 'Install them now? [Y/n]') -notmatch '^\s*n'
    }
    Write-Host ''
    if ($go) {
        foreach ($r in @(Invoke-BuildTools -Tools @($offer | ForEach-Object Tool))) {
            if ($r.State -in 'INSTALLED', 'OK') {
                if ($r.Restart) { $restart = $true }
                Add-Row 'DONE' $r.Name ("installed $($r.Version)$(if ($r.Restart) { '; RESTART Windows before the VM test' })")
            } else {
                Add-Row 'FAIL' $r.Name "$($r.State): $($r.Detail)" "Logs in $WorkRoot\logs. Fix it and run Run-Prepare.cmd again."
            }
        }
    } else {
        Add-Row 'INFO' 'Build tools' 'not installed (you said no): Run-Build.cmd asks again when you start a build'
    }
}

# --- Summary ----------------------------------------------------------------------------
$block = @($rows | Where-Object State -in 'BLOCK', 'FAIL')
Write-Host ''
if ($block.Count) {
    Write-Host "NOT READY: $($block.Count) item(s) block the build (marked BLOCK or FAIL above)." -ForegroundColor Red
    exit 1
}
if ($ForBuild) {
    Write-Host 'Build tools ready. Starting the build.' -ForegroundColor Green
    exit 0
}
Write-Host 'Next, for the first build:'
Write-Host '  1. The Windows 11 ISO from Microsoft, in your Downloads folder (docs\GUIDE.md, step 4). One the kit does not'
Write-Host '     know yet: the build''s pre-flight says how to accept it.'
Write-Host '  2. Run-Build.cmd, on the PC you will reinstall. It asks before each thing it does: the downloads (Windows'
Write-Host '     updates, Microsoft''s security baselines), a hardware profile for this PC, this PC''s drivers, and, after'
Write-Host '     the build, a test of the ISO in a virtual machine.'
Write-Host '  Building for another PC: its profile and drivers are made on that PC first (docs\reference\BUILD-OPTIONS.md,'
Write-Host '  "Building on another PC").'
if ($restart) {
    Write-Host ''
    Write-Host 'READY after a restart: restart Windows to finish enabling Hyper-V.' -ForegroundColor Yellow
    exit 3010
}
Write-Host ''
Write-Host 'READY: this PC can build the ISO.' -ForegroundColor Green
exit 0
