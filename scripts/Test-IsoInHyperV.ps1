<#
.SYNOPSIS
    End-to-end test of the built ISO in a Hyper-V virtual machine, before the
    USB stick is written. Run elevated (Run-VmTest.cmd). The user-facing VM test:
    the build-PC preparation (Run-Prepare.cmd) enables Hyper-V.

.DESCRIPTION
    1. Makes a TEST copy of the ISO, <WorkDir>\W11Kit-VMTEST-ONLY-wipes-disk.iso:
       identical, except its autounattend.xml also wipes and partitions the
       VM's disk 0 without asking (the only manual step on the real PC; EFI,
       MSR, Windows and a recovery partition, as Setup lays a disk out itself),
       carries the generic Pro installation key when the answer file has no key
       (a VM has no firmware key; the real ISO is never changed), it boots
       without "Press any key" (efisys_noprompt*.bin), and it leaves out the
       BuildInputs folder (Setup never reads it). The test ISO is deleted when
       the test ends, pass or fail: never write it to a USB stick. As a second
       line of defence its answer file starts with a check that powers the
       machine off, before any disk is touched, unless it is a Hyper-V virtual
       machine (system manufacturer "Microsoft Corporation", product "Virtual
       Machine"); a leftover test ISO is also deleted by the next build and by
       Run-Prepare.cmd. Before the
       copy, a free-space check: 2 x the ISO's contents (without BuildInputs:
       the copied media and the test ISO) + 30 GB for the VM's disk. The work
       folder is made writable by administrators only (scripts\KitAcl.ps1).
    2. Creates a Generation 2 VM: Secure Boot (Microsoft Windows template),
       virtual TPM, 4 vCPU, 6 GB RAM, 80 GB disk, Default Switch.
    3. Installs hands-off: ejects the ISO after Setup's first restart, follows
       PostInstall.ps1's report through Hyper-V Key-Value Pair Exchange (progress
       only), then waits for its restart and for Windows to come back up.
    4. Shuts the VM down, mounts its disk READ-ONLY and collects Setup logs,
       the PostInstall log/status, the image's profile.json and the validation
       report (.json and .md) into <WorkDir>\results (plus the VM's
       answer file with the passwords removed, vm-autounattend-redacted.xml).
    5. Grades the install and prints a summary that
       ends with RESULT: PASS or RESULT: FAIL (exit code 0 / 1). PASS needs:
       PostInstall reported (status file on the VM disk), not critical, no
       failures; no cached answer files in Windows\Panther; Windows came back
       up after PostInstall's restart; and no FAIL/WARN validator row that isn't
       expected in a VM: rows with hardware=true (the profile's device checks
       and Wake-on-LAN) and rows listed in config\vm-expected.json under
       'common' or 'hyperv'.

    Not covered here: hibernation and the power button (Hyper-V offers its
    guests neither), Wake-on-LAN and the real devices (only on the real PC).
#>
[CmdletBinding()]
param(
    [string]$IsoPath,
    [string]$KitRoot,
    [string]$WorkRoot,   # default: <KitRoot>\work (the build's work folder: the newest ISO, oscdimg)
    [string]$WorkDir,    # default: <WorkRoot>\vmtest
    [string]$VmName = 'W11Kit-ISO-Test',
    [int]$TimeoutMinutes = 120,
    [switch]$KeepVm,
    # Keep the VM's disk after a PASSED test too (a failed test's disk is always kept)
    [switch]$KeepDisk
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run elevated (use Run-VmTest.cmd).' }
# Loaded as a scriptblock (Run-VmTest.cmd), $PSScriptRoot is empty: the launcher passes -KitRoot.
if (-not $KitRoot -and $PSScriptRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
if (-not $KitRoot) { throw 'Pass -KitRoot <kit folder> (Run-VmTest.cmd does).' }
$KitRoot = $KitRoot.TrimEnd('\')
if (-not $WorkRoot) { $WorkRoot = Join-Path $KitRoot 'work' }
if (-not $WorkDir) { $WorkDir = Join-Path $WorkRoot 'vmtest' }
# The work folder: writable by administrators only, like the build's (scripts\KitAcl.ps1)
. ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $KitRoot 'scripts\KitAcl.ps1'))))
if (-not (Get-Module -ListAvailable -Name Hyper-V)) { throw 'The Hyper-V PowerShell module is missing: enable Hyper-V on this PC first (Run-Prepare.cmd; docs/reference/BUILD-OPTIONS.md, "Run-Prepare.cmd").' }
Import-Module Hyper-V

function Log([string]$Text) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $Text" }
function Invoke-Quiet([scriptblock]$Block) { $o = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & $Block } finally { $ErrorActionPreference = $o } }

# Same search as Build-Iso.ps1's Find-Oscdimg (copied, not imported).
function Find-Oscdimg {
    # A copy restored from an ISO's BuildInputs (no ADK install), then the ADK, then PATH; each
    # only if validly signed by exactly the ADK's pinned signer (config\installers.json 'adk'),
    # not just any Microsoft-signed program renamed oscdimg.exe.
    $signer = try { "$(([IO.File]::ReadAllText((Join-Path $KitRoot 'config\installers.json')) | ConvertFrom-Json).adk.signer)" } catch { '' }
    if (-not $signer) { $signer = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' }
    $local = Join-Path $WorkRoot 'tools\Oscdimg\oscdimg.exe'
    $c = @($local,
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        (Get-Command oscdimg.exe -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($x in $c) {
        $sig = Get-AuthenticodeSignature -LiteralPath $x
        if ($sig.Status -eq 'Valid' -and "$($sig.SignerCertificate.Subject)" -ceq $signer) { return $x }
        Write-Warning "Ignoring ${x}: not validly signed by '$signer' (status $($sig.Status), signer '$($sig.SignerCertificate.Subject)')."
    }
    return $null
}

# --- Grading -------------------------------------------------------------------------
function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

# Rows from W11Kit-Validation.json (ProgramData copy, else the Public desktop one)
function Get-ValidationRows([string]$Dir) {
    foreach ($name in 'W11Kit-Validation.json', 'public-desktop-W11Kit-Validation.json') {
        $v = Read-JsonFile (Join-Path $Dir $name)
        if ($v -and $null -ne $v.rows) {
            $rows = @(@($v.rows) | Where-Object { $_ } | ForEach-Object {
                [pscustomobject]@{ Area = "$($_.area)"; Check = "$($_.check)"; Result = "$($_.result)"; Detail = "$($_.detail)"; Hardware = ($_.hardware -eq $true) }
            })
            return [pscustomobject]@{ Source = 'json'; Profile = $v.profile; Rows = $rows }
        }
    }
    return [pscustomobject]@{ Source = $null; Profile = $null; Rows = @() }
}

# FAIL/WARN rows split into expected (with the reason) and unexpected, by
# config\vm-expected.json: hardware=true rows and the 'common' + 'hyperv' entries.
# The regexes are case-sensitive.
function Get-Grade($Rows) {
    $cfgPath = Join-Path $KitRoot 'config\vm-expected.json'
    $cfg = Read-JsonFile $cfgPath
    if (-not $cfg) { throw "$cfgPath missing or not valid JSON" }
    $entries = @(@($cfg.common) + @($cfg.hyperv) | Where-Object { $_ })
    $expected = New-Object System.Collections.Generic.List[object]
    $unexpected = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($Rows)) {
        if ($r.Result -notin 'FAIL', 'WARN') { continue }
        $key = "$($r.Area) | $($r.Check)"
        $why = $null
        if ($r.Hardware) { $why = 'hardware check (profile): the VM has none of that hardware' }
        else {
            foreach ($e in $entries) {
                if ([regex]::IsMatch($key, $e.match) -and (-not $e.detail -or [regex]::IsMatch($r.Detail, $e.detail))) {
                    $why = if ($e.why) { $e.why } else { $e.match }
                    break
                }
            }
        }
        $line = "$($r.Result) ${key}: $($r.Detail)"
        if ($why) { $expected.Add([pscustomobject]@{ Line = $line; Why = $why }) } else { $unexpected.Add($line) }
    }
    return [pscustomobject]@{ Expected = $expected.ToArray(); Unexpected = $unexpected.ToArray() }
}

function Shorten([string]$Text, [int]$Max) { $t = ($Text -replace '\s+', ' ').Trim(); if ($t.Length -gt $Max) { $t.Substring(0, $Max) } else { $t } }

if (-not $IsoPath) {
    $IsoPath = Get-ChildItem $WorkRoot -Filter 'Win11Pro-*.iso' -File -ErrorAction SilentlyContinue | Where-Object Extension -eq '.iso' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $IsoPath -or -not (Test-Path $IsoPath)) { throw "No built ISO found in $WorkRoot. Run the build first, or name the ISO: Run-VmTest.cmd -IsoPath ""<path to the .iso>"" (double quotes around a path with spaces)." }
$IsoPath = (Resolve-Path $IsoPath).Path
$oscdimg = Find-Oscdimg
if (-not $oscdimg) { throw 'oscdimg.exe not found (Windows ADK Deployment Tools, or a Microsoft-signed copy in tools\Oscdimg): run the build once, it installs the ADK.' }
$adk = Split-Path $oscdimg
if (-not (Test-Path (Join-Path $KitRoot 'config\vm-expected.json'))) { throw "config\vm-expected.json not found under $KitRoot" }

# Locked before anything in it is removed or used (a junction planted there is refused, not followed)
if (Test-Path -LiteralPath $WorkDir) {
    $bad = @(Lock-KitPath $WorkDir)
    if ($bad.Count) { throw "Could not make $WorkDir writable by administrators only: $($bad -join '; ')" }
} else {
    if (-not (Test-Path -LiteralPath (Split-Path $WorkDir -Parent))) { New-KitLockedFolder (Split-Path $WorkDir -Parent) }
    New-KitLockedFolder $WorkDir
}
# The TEST ISO wipes disk 0 without asking: its name says so, and it never outlives the test
$testIso = Join-Path $WorkDir 'W11Kit-VMTEST-ONLY-wipes-disk.iso'
$media = Join-Path $WorkDir 'media'
$results = Join-Path $WorkDir 'results'
if (Test-Path $results) { Remove-Item $results -Recurse -Force }
New-Item -ItemType Directory -Path $results | Out-Null
Start-Transcript -Path (Join-Path $results 'vmtest-transcript.txt') | Out-Null

$ok = $false
# No sleep during the test (its deadline is wall-clock time); this thread's request ends with it
if (-not ('W11Kit.Awake' -as [type])) { Add-Type -Namespace W11Kit -Name Awake -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);' }
$null = [W11Kit.Awake]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS | ES_SYSTEM_REQUIRED
try {
    # --- 0. Any previous test VM (it may still hold the old test ISO open) -----
    $vhd = Join-Path $WorkDir "$VmName.vhdx"
    if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) {
        Log "Removing the previous test VM $VmName"
        Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $VmName -Force
    }
    # A disk left mounted by an interrupted earlier run
    if ((Test-Path $vhd) -and (Get-DiskImage -ImagePath $vhd -ErrorAction SilentlyContinue).Attached) { Invoke-Quiet { Dismount-VHD -Path $vhd -ErrorAction SilentlyContinue } }
    if (Test-Path $vhd) { Remove-Item $vhd -Force }

    # --- 1. Test ISO ------------------------------------------------------------
    Log "Making a test copy of $(Split-Path $IsoPath -Leaf)"
    if (Test-Path $media) { Remove-Item $media -Recurse -Force }
    if (Test-Path -LiteralPath $testIso) { Remove-Item -LiteralPath $testIso -Force }
    # As Build-Iso.ps1: reuse the ISO if it is already mounted (e.g. opened in
    # Explorer) and leave it mounted; the drive letter can take a while to appear.
    $img = Get-DiskImage -ImagePath $IsoPath
    $weMounted = -not $img.Attached
    if ($weMounted) { $img = Mount-DiskImage -ImagePath $IsoPath -PassThru }
    try {
        $letter = $null
        for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
            $letter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume -ErrorAction SilentlyContinue).DriveLetter
            if (-not $letter) { Start-Sleep -Seconds 1 }
        }
        if (-not $letter) { throw 'The ISO mounted but has no drive letter.' }
        # Free space: the copied media and the test ISO (each as large as the ISO without
        # BuildInputs) exist together for a moment, then the VM's disk grows (about 20-25 GB)
        $payload = [long]0
        foreach ($f in @(Get-ChildItem -LiteralPath "$($letter):\" -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            if ($f.FullName -notmatch '^[A-Za-z]:\\BuildInputs\\') { $payload += $f.Length }
        }
        $needGb = [math]::Ceiling((2 * $payload + 30GB) / 1GB)
        $freeGb = [math]::Floor((Get-PSDrive ([IO.Path]::GetFullPath($WorkDir).Substring(0, 1))).Free / 1GB)
        Log ("Free space: {0} GB on {1}; the test needs about {2} GB (2 x {3:N1} GB for the media copy and the test ISO + 30 GB for the VM's disk)" -f $freeGb, [IO.Path]::GetFullPath($WorkDir).Substring(0, 2), $needGb, ($payload / 1GB))
        if ($freeGb -lt $needGb) { throw "Not enough free space for the VM test: $freeGb GB free, about $needGb GB needed. Free up space (older ISOs in $WorkRoot, a kept VM disk in $WorkDir), or use -WorkDir on a bigger drive." }
        # Without BuildInputs: Setup never reads them, and they would double the copy (~15-20 GB)
        & robocopy.exe "$($letter):\" $media /E /XD "$($letter):\BuildInputs" /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    } finally { if ($weMounted) { Dismount-DiskImage -ImagePath $IsoPath | Out-Null } }
    Get-ChildItem $media -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    $ua = Join-Path $media 'autounattend.xml'
    $xml = [IO.File]::ReadAllText($ua)
    $setupRx = '(?s)(<component name="Microsoft-Windows-Setup"[^>]*>)(.*?)(</component>)'
    $m = [regex]::Match($xml, $setupRx)
    if (-not $m.Success) { throw 'Microsoft-Windows-Setup component not found in autounattend.xml' }
    $userData = [regex]::Match($m.Groups[2].Value, '(?s)<UserData>.*?</UserData>').Value
    # A VM has no firmware (MSDM) product key, so Setup would stop at "enter
    # your product key". The TEST copy uses the generic Windows 11 Pro installation
    # key (selects the edition during Setup; does not activate; not a licence).
    # The real ISO is never changed (a 'firmware' profile stays keyless).
    if ($userData -notmatch '<ProductKey>') {
        $userData = $userData -replace '</UserData>', "  <ProductKey><Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key><WillShowUI>OnError</WillShowUI></ProductKey>`r`n      </UserData>"
    }
    $dynUpd = [regex]::Match($m.Groups[2].Value, '(?s)<DynamicUpdate>.*?</DynamicUpdate>').Value
    # The VM's disk, laid out like Microsoft's default for a UEFI PC (and like Setup's own
    # layout on the real PC, where the answer file has no disk configuration): EFI system
    # partition, MSR, Windows, then a recovery partition right after Windows (GPT type
    # DE94BBA4-...: Setup puts WinRE there instead of on C:). The answer file can't say
    # "the rest minus 2.6 GB", so Windows gets a fixed 79000 MB of the VM's 80 GB disk
    # (81920 MB) and the recovery partition the rest, about 2.6 GB: room for Winre.wim
    # plus the 250 MB free Microsoft asks for.
    #
    # The guard. This answer file wipes disk 0 without asking, so it must never run on a real
    # PC. Its first instruction is a windowsPE RunSynchronous command: Windows Setup runs those
    # when it starts, before it applies the disk configuration. The command asks the firmware
    # (SMBIOS, as Windows PE keeps it in HKLM\HARDWARE\DESCRIPTION\System\BIOS) who made the
    # machine: a Hyper-V virtual machine reports the manufacturer "Microsoft Corporation" and
    # the product "Virtual Machine". 'reg query /f <text> /d /e /c' succeeds only when a value
    # of that key is exactly that text. Unless both are found, the machine is powered off
    # (wpeutil shutdown) and the command never returns (an endless loop), so Setup can't go on
    # to the disk. Anything that goes wrong (no such key, reg.exe missing) counts as "not
    # found". Only tools that are in Windows Setup's boot image: cmd, reg, wpeutil (it has
    # no findstr, no PowerShell). An answer file takes at most 259 characters here.
    # The halt after the shutdown is 'for /l ... do @ver>nul', never '@rem': rem swallows the rest of
    # the line, closing bracket included, the whole line is then a syntax error (exit code 1), and
    # Setup stops with 0x80070001 on every machine, VM or not.
    $guardCmd = 'cmd.exe /c "reg.exe query HKLM\HARDWARE\DESCRIPTION\System\BIOS /f "Virtual Machine" /d /e /c>nul&&reg.exe query HKLM\HARDWARE\DESCRIPTION\System\BIOS /f "Microsoft Corporation" /d /e /c>nul||(wpeutil.exe shutdown&for /l %i in (0,0,1) do @ver>nul)"'
    if ($guardCmd.Length -gt 259) { throw "The test ISO's hardware guard is $($guardCmd.Length) characters long; an answer file allows 259." }
    $vmBlock = @"

      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>W11Kit VM-test ISO: power off unless this is a Hyper-V virtual machine</Description>
          <Path>$([Security.SecurityElement]::Escape($guardCmd))</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Size>79000</Size></CreatePartition>
            <CreatePartition wcm:action="add"><Order>4</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>2</PartitionID></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>3</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
            <ModifyPartition wcm:action="add"><Order>4</Order><PartitionID>4</PartitionID><Format>NTFS</Format><Label>Recovery</Label><TypeID>de94bba4-06d1-4d40-a16a-bfd50179d6ac</TypeID></ModifyPartition>
          </ModifyPartitions>
        </Disk>
        <WillShowUI>OnError</WillShowUI>
      </DiskConfiguration>
      $dynUpd
      <ImageInstall>
        <OSImage>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
          <WillShowUI>OnError</WillShowUI>
        </OSImage>
      </ImageInstall>
      $userData

"@
    $xml = $xml.Substring(0, $m.Groups[2].Index) + $vmBlock + $xml.Substring($m.Groups[2].Index + $m.Groups[2].Length)
    # Well-formed, and the guard is in it exactly as written above (never a test ISO without it)
    $guardBack = @(([xml]$xml).unattend.settings | Where-Object { $_.pass -eq 'windowsPE' } | ForEach-Object { $_.component } | Where-Object { $_.name -eq 'Microsoft-Windows-Setup' } | ForEach-Object { $_.RunSynchronous.RunSynchronousCommand.Path })
    if ($guardBack.Count -ne 1 -or "$($guardBack[0])" -cne $guardCmd) { throw "The test ISO's answer file does not carry the hardware guard (found $($guardBack.Count) command(s)): no test ISO is made." }
    [IO.File]::WriteAllText($ua, $xml, (New-Object Text.UTF8Encoding $false))
    # For the record, WITHOUT the passwords (they are only obfuscated in an answer file)
    $redacted = [regex]::Replace($xml, '(?s)(<(Password|AdministratorPassword)>\s*<Value>)[^<]*(</Value>)', '$1(removed)$3')
    [IO.File]::WriteAllText((Join-Path $results 'vm-autounattend-redacted.xml'), $redacted, (New-Object Text.UTF8Encoding $false))
    $redacted = $null
    # No-keypress UEFI boot image signed like the ISO's own boot manager: 2023
    # media needs efisys_noprompt_EX.bin (next to oscdimg, else this host's DVD_EX copy).
    $isoIssuer = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile("$media\efi\boot\bootx64.efi").Issuer
    $bootCa = if ($isoIssuer -match 'CN=Windows UEFI CA 2023') { 'Windows UEFI CA 2023' } elseif ($isoIssuer -match 'Production PCA 2011') { 'Microsoft Windows Production PCA 2011' } else { $isoIssuer }
    if ($bootCa -eq 'Windows UEFI CA 2023') {
        $noPrompt = @("$adk\efisys_noprompt_EX.bin", "$env:SystemRoot\Boot\DVD_EX\EFI\en-US\efisys_noprompt_EX.bin") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $noPrompt) { throw 'The ISO boots with the 2023 boot manager but no efisys_noprompt_EX.bin was found (next to oscdimg or in Windows\Boot\DVD_EX)' }
    } else {
        $noPrompt = @("$adk\efisys_noprompt.bin", "$env:SystemRoot\Boot\DVD\EFI\en-US\efisys_noprompt.bin") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $noPrompt) { throw 'No efisys_noprompt.bin found (next to oscdimg or in Windows\Boot\DVD)' }
    }
    Log "Test ISO boot image: $noPrompt (ISO boot manager signed by: $bootCa)"
    $bootData = "2#p0,e,b$media\boot\etfsboot.com#pEF,e,b$noPrompt"
    # oscdimg prints progress on stderr: run it with 'Continue' so PS 5.1 does not
    # treat that as an error, and judge it by its exit code only.
    $rc = Invoke-Quiet { $null = & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" -lW11KIT_VMTEST $media $testIso 2>&1; $LASTEXITCODE }
    if ($rc -ne 0) { throw "oscdimg failed ($rc)" }
    Remove-Item $media -Recurse -Force
    Log "Test ISO: $testIso (VM only: it wipes disk 0 without asking; on anything but a Hyper-V VM it powers the machine off instead; deleted when the test ends)"

    # --- 2. VM ------------------------------------------------------------------------
    # The Default Switch by its fixed Id (its name can be localized); none = no network
    $vmSwitch = Get-VMSwitch -ErrorAction SilentlyContinue | Where-Object { "$($_.Id)" -eq 'c08cb7b8-9b3c-408e-8e30-5e16a3aeb444' -or $_.Name -eq 'Default Switch' } | Select-Object -First 1
    Log "Creating VM $VmName (Gen 2, Secure Boot, vTPM, 4 vCPU, 6 GB, 80 GB, $(if ($vmSwitch) { "switch '$($vmSwitch.Name)'" } else { 'NO network: Default Switch not found' }))"
    $newVm = @{ Name = $VmName; Generation = 2; MemoryStartupBytes = 6GB; NewVHDPath = $vhd; NewVHDSizeBytes = 80GB }
    if ($vmSwitch) { $newVm.SwitchName = $vmSwitch.Name }
    New-VM @newVm | Out-Null
    Set-VM -Name $VmName -ProcessorCount 4 -StaticMemory -CheckpointType Disabled -AutomaticCheckpointsEnabled $false -AutomaticStartAction Nothing
    Set-VMFirmware -VMName $VmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Set-VMKeyProtector -VMName $VmName -NewLocalKeyProtector
    Enable-VMTPM -VMName $VmName
    Add-VMDvdDrive -VMName $VmName -Path $testIso
    Set-VMFirmware -VMName $VmName -FirstBootDevice (Get-VMDvdDrive -VMName $VmName)
    # Integration services by Id (names are localized): Heartbeat, Key-Value Pair Exchange, Shutdown
    $icIds = '84EAAE65-2F2E-45F5-9BB5-0E857DC8EB47', '2A34B1C2-FD73-4043-8A5B-DD2159BC743F', '9F8233AC-BE49-4C79-8EE3-E7E1985B2077'
    Get-VMIntegrationService -VMName $VmName | Where-Object { $id = "$($_.Id)"; @($icIds | Where-Object { $id -match $_ }).Count -or $_.Name -match 'Key-Value|Heartbeat|Shutdown' } | Enable-VMIntegrationService
    # The VM's screen as a PNG in the results (Hyper-V's thumbnail of the console): what Setup
    # shows when it stops is otherwise lost, and before Windows is on the disk there are no logs.
    function Save-VmScreen([string]$Name) {
        try {
            $w = 1024; $h = 768
            $cs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$VmName'"
            $svc = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_VirtualSystemManagementService
            $sd = Get-CimAssociatedInstance -InputObject $cs -ResultClassName Msvm_VirtualSystemSettingData |
                Where-Object { $_.VirtualSystemType -eq 'Microsoft:Hyper-V:System:Realized' } | Select-Object -First 1
            $r = Invoke-CimMethod -InputObject $svc -MethodName GetVirtualSystemThumbnailImage -Arguments @{ TargetSystem = $sd; WidthPixels = [uint16]$w; HeightPixels = [uint16]$h }
            if ($r.ReturnValue -ne 0 -or -not $r.ImageData) { throw "GetVirtualSystemThumbnailImage returned $($r.ReturnValue)" }
            Add-Type -AssemblyName System.Drawing
            $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format16bppRgb565)
            try {
                $data = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $w, $h), 'WriteOnly', $bmp.PixelFormat)
                [Runtime.InteropServices.Marshal]::Copy([byte[]]$r.ImageData, 0, $data.Scan0, [Math]::Min($r.ImageData.Length, $data.Stride * $h))
                $bmp.UnlockBits($data)
                $file = Join-Path $results $Name
                $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
                Log "VM screen saved: $file"
            } finally { $bmp.Dispose() }
        } catch { Log "VM screen not saved ($Name): $($_.Exception.Message)" }
    }
    function Get-Heartbeat { Get-VMIntegrationService -VMName $VmName | Where-Object { "$($_.Id)" -match $icIds[0] -or $_.Name -match 'Heartbeat' } | Select-Object -First 1 }

    # --- 3. Install and wait -------------------------------------------------------------
    Start-VM -Name $VmName
    Log 'VM started: Windows Setup is running (unattended)'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $lastUp = 0; $reboots = 0; $ejected = $false; $done = $null; $doneAt = $null; $rebootAfterDone = $false; $restart3At = $null; $bootWaitFrom = $null
    $outcome = 'timed out'
    while ((Get-Date) -lt $deadline) {
        $vm = Get-VM -Name $VmName
        if ($vm.State -eq 'Off') {
            Log 'VM turned off on its own'
            if (-not $reboots) { Log '  Before Setup''s first restart: the test ISO''s hardware guard powers the machine off when Windows PE does not report a Hyper-V VM (HKLM\HARDWARE\DESCRIPTION\System\BIOS: SystemManufacturer "Microsoft Corporation", SystemProductName "Virtual Machine").' }
            $outcome = 'VM turned off on its own'; break
        }
        $up = $vm.Uptime.TotalSeconds
        if ($up -lt $lastUp) {
            $reboots++
            Log "VM restarted (#$reboots)"
            if (-not $ejected) { Set-VMDvdDrive -VMName $VmName -Path $null; $ejected = $true; Log 'Test ISO ejected (Setup continues from disk)' }
            if ($done) { $rebootAfterDone = $true }
        }
        $lastUp = $up
        # Setup copies Windows and restarts within a few minutes (about 4 here). No restart
        # after 20 means it stopped in its first phase (an error page waits for a click that
        # never comes): don't sit out the whole time limit.
        if (-not $reboots -and -not $slowShot -and ((Get-Date) - $deadline.AddMinutes(-$TimeoutMinutes)).TotalMinutes -gt 8) {
            $slowShot = $true
            Log 'No first restart after 8 minutes (usually about 4): saving what the VM shows'
            Save-VmScreen 'vm-screen-8min.png'
        }
        if (-not $reboots -and ((Get-Date) - $deadline.AddMinutes(-$TimeoutMinutes)).TotalMinutes -gt 20) {
            Log 'WARNING: Windows Setup has not restarted the VM after 20 minutes: it stopped in its first phase (error page?); collecting its logs'
            $outcome = 'Setup stopped before its first restart'; break
        }
        if (-not $done) {
            $cs = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$VmName'"
            $kvp = Get-CimAssociatedInstance -InputObject $cs -ResultClassName Msvm_KvpExchangeComponent -ErrorAction SilentlyContinue
            # PostInstall writes ...\Virtual Machine\Guest: the host reads it as GuestExchangeItems
            foreach ($item in @($kvp.GuestExchangeItems)) {
                if (-not $item) { continue }
                $x = [xml]$item
                $n = ($x.INSTANCE.PROPERTY | Where-Object NAME -eq 'Name').VALUE
                if ($n -eq 'W11KitPostInstall') { $done = ($x.INSTANCE.PROPERTY | Where-Object NAME -eq 'Data').VALUE }
            }
            if ($done) { $doneAt = Get-Date; Log "PostInstall reported: $done" }
        }
        if ($reboots -ge 3 -and -not $restart3At) { $restart3At = Get-Date }
        # Without the Key-Value Pair report, restart #3 is PostInstall's own restart
        # (Setup restarts twice): after 3 quiet minutes treat it as the last boot.
        # The status file on the VM disk decides the result either way.
        $lastBoot = ($done -and $rebootAfterDone) -or (-not $done -and $restart3At -and ((Get-Date) - $restart3At).TotalMinutes -gt 3)
        if ($lastBoot) {
            # Prove the PC boots with the baseline applied, then shut down from here
            if (-not $bootWaitFrom) {
                $bootWaitFrom = Get-Date
                Log $(if ($done) { 'PostInstall restart seen; waiting for Windows to come back up' } else { 'No Key-Value Pair report; restart #3 (PostInstall) seen 3+ minutes ago; waiting for Windows to come back up' })
            }
            if ("$((Get-Heartbeat).PrimaryOperationalStatus)" -eq 'Ok') {
                Log 'Windows is back up after the PostInstall restart (heartbeat OK); settling 60 seconds'
                Start-Sleep -Seconds 60
                $outcome = 'complete'
                break
            }
            if (((Get-Date) - $bootWaitFrom).TotalMinutes -gt 10) { Log 'WARNING: no heartbeat 10 minutes after the PostInstall restart'; $outcome = 'no heartbeat after the PostInstall restart'; break }
        } elseif ($done -and ((Get-Date) - $doneAt).TotalMinutes -gt 6) {
            Log 'WARNING: PostInstall reported but did not restart within 6 minutes (critical failure?)'
            $outcome = 'PostInstall did not restart'
            break
        }
        Start-Sleep -Seconds 15
    }
    if ($outcome -eq 'timed out') { Log "WARNING: not finished within $TimeoutMinutes minutes; collecting what exists" }

    # --- 4. Collect -----------------------------------------------------------------------
    if ($outcome -ne 'complete') { Save-VmScreen 'vm-screen-at-end.png' }
    Log 'Shutting the VM down'
    Invoke-Quiet { Stop-VM -Name $VmName -Force -ErrorAction SilentlyContinue }
    $t = 0
    while ((Get-VM -Name $VmName).State -ne 'Off' -and $t -lt 36) { Start-Sleep 5; $t++ }
    if ((Get-VM -Name $VmName).State -ne 'Off') { Stop-VM -Name $VmName -TurnOff -Force }

    Log 'Reading the VM disk (read-only)'
    $cachedAnswers = @()
    $diskRead = $false
    $disk = Mount-VHD -Path $vhd -ReadOnly -Passthru | Get-Disk
    try {
        $win = $null
        for ($try = 0; $try -lt 10 -and -not $win; $try++) {
            Start-Sleep -Seconds 2
            foreach ($p in Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue) {
                if (-not $p.DriveLetter -and $p.Size -gt 20GB) { Invoke-Quiet { $p | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue }; $p = Get-Partition -DiskNumber $disk.Number -PartitionNumber $p.PartitionNumber }
                if ($p.DriveLetter -and (Test-Path "$($p.DriveLetter):\Windows\System32")) { $win = "$($p.DriveLetter):" }
            }
        }
        if (-not $win) {
            # Setup failed before Windows was on the disk: its first-phase logs say why
            foreach ($p in Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue) {
                $early = if ($p.DriveLetter) { "$($p.DriveLetter):\`$Windows.~BT\Sources\Panther" }
                if ($early -and (Test-Path -LiteralPath $early)) {
                    Get-ChildItem -LiteralPath $early -File -Filter 'setup*.log' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $results ('early-' + $_.Name)) -Force }
                    Log "Setup's first-phase logs copied to $results (early-setuperr.log, early-setupact.log)"
                    $err = Join-Path $results 'early-setuperr.log'
                    if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err | Where-Object { $_ -match ', Error ' } | Select-Object -Last 8 | ForEach-Object { Log "  $_" } }
                }
            }
            throw 'Windows partition not found on the VM disk'
        }
        $diskRead = $true
        # PostInstall locks C:\ProgramData\W11Kit to Administrators/SYSTEM, so copy in
        # backup mode (robocopy /B uses the Backup privilege and ignores the ACLs).
        function Copy-Backup([string]$SrcDir, [string]$Files, [string]$Prefix) {
            if (-not (Test-Path $SrcDir)) { return }
            $tmp = Join-Path $results '_copy'
            Invoke-Quiet { $null = & robocopy.exe $SrcDir $tmp $Files /B /NFL /NDL /NJH /NJS /R:0 /W:0 2>&1 }
            if (-not (Test-Path $tmp)) { return }
            Get-ChildItem $tmp -File | ForEach-Object { Move-Item $_.FullName (Join-Path $results ($Prefix + $_.Name)) -Force }
            Remove-Item $tmp -Recurse -Force
        }
        $panther = Join-Path $win 'Windows\Panther'
        Copy-Backup $panther 'setupact.log' 'panther-'
        Copy-Backup $panther 'setuperr.log' 'panther-'
        # The last first-logon command deletes the cached answer files (they hold the passwords)
        $cachedAnswers = @(Get-ChildItem "$panther\unattend*.xml", "$panther\Unattend\unattend*.xml" -Force -ErrorAction SilentlyContinue | ForEach-Object Name)
        $w11kit = Join-Path $win 'ProgramData\W11Kit'
        foreach ($f in 'postinstall-status.json', 'profile.json', 'W11Kit-Validation.json', 'W11Kit-Validation.md') { Copy-Backup $w11kit $f '' }
        Copy-Backup (Join-Path $w11kit 'Logs') '*' ''
        Copy-Backup (Join-Path $win 'Windows\System32\GroupPolicy') 'gpt.ini' 'grouppolicy-'
        foreach ($f in 'W11Kit-Validation.json', 'W11Kit-Validation.md') { Copy-Backup (Join-Path $win 'Users\Public\Desktop') $f 'public-desktop-' }
    } finally {
        Dismount-VHD -Path $vhd
    }

    # --- 5. Grade and summary -----------------------------------------------------------
    $status = Read-JsonFile (Join-Path $results 'postinstall-status.json')
    $imgProfile = Read-JsonFile (Join-Path $results 'profile.json')
    $val = Get-ValidationRows $results
    $profileId = if ($val.Profile) { $val.Profile } elseif ($imgProfile) { $imgProfile.id } else { $null }
    $unexpected = New-Object System.Collections.Generic.List[string]

    Write-Host ''
    Write-Host '================ VM TEST SUMMARY (Hyper-V) ================' -ForegroundColor Cyan
    Write-Host "ISO: $(Split-Path $IsoPath -Leaf)"
    Write-Host "ISO boot manager: $bootCa"
    Write-Host "Restarts: $reboots; outcome: $outcome$(if (-not $done) { ' (no Key-Value Pair report)' })"
    # PostInstall failures a VM can't avoid (config\vm-expected.json 'postInstallFailures')
    $vmCfg = Read-JsonFile (Join-Path $KitRoot 'config\vm-expected.json')
    $pfRules = @(@($vmCfg.postInstallFailures.common) + @($vmCfg.postInstallFailures.hyperv) | Where-Object { $_ -and $_.match })
    $allFails = @($status.failures | Where-Object { $_ })
    $realFails = @($allFails | Where-Object { $f = "$_"; -not @($pfRules | Where-Object { $f -cmatch $_.match }).Count })
    if ($status) {
        Write-Host "PostInstall finished: $($status.finished)  critical=$($status.critical)  warnings=$($allFails.Count) ($($allFails.Count - $realFails.Count) expected in a VM)  kit=$($status.kitRevision)"
        foreach ($f in $allFails) { $r = @($pfRules | Where-Object { "$f" -cmatch $_.match }) | Select-Object -First 1; if ($r) { Write-Host "  expected   $f  [$($r.why.Substring(0, [Math]::Min(80, $r.why.Length)))]" } else { Write-Host "  - $f" -ForegroundColor Yellow } }
    } else {
        Write-Host "PostInstall status file NOT found - first logon did not complete.$(if (-not $diskRead) { ' (VM disk not readable)' })" -ForegroundColor Red
    }
    Write-Host "Cached answer files in Windows\Panther: $(if ($cachedAnswers.Count) { $cachedAnswers -join ', ' } elseif ($diskRead) { 'none (removed)' } else { 'not checked (VM disk not readable)' })"
    Write-Host "Profile: $(if ($profileId) { $profileId } else { '(not found)' }); hibernation and the power button are not tested here (Hyper-V offers neither to its guests)"
    if ($val.Source) {
        $g = Get-Grade $val.Rows
        Write-Host ''
        Write-Host "Validation (pre-restart snapshot, W11Kit-Validation.json): $(@($g.Unexpected).Count) unexpected FAIL/WARN, $(@($g.Expected).Count) expected in a VM (config\vm-expected.json)"
        foreach ($l in @($g.Unexpected)) { Write-Host "  UNEXPECTED $(Shorten $l 200)" -ForegroundColor Red; $unexpected.Add($l) }
        foreach ($e in @($g.Expected)) { Write-Host "  expected   $(Shorten $e.Line 110)  [$(Shorten $e.Why 80)]" }
        if (-not @($val.Rows).Count) { $unexpected.Add('validation report has no rows') }
    } else {
        $unexpected.Add('W11Kit-Validation.json missing')
        Write-Host 'Validation report (W11Kit-Validation.json) NOT found.' -ForegroundColor Red
    }
    $err = Join-Path $results 'panther-setuperr.log'
    if ((Test-Path $err) -and (Get-Item $err).Length -gt 0) {
        Write-Host ''
        Write-Host 'Windows Setup errors (setuperr.log, last 15 lines):'
        Get-Content $err -Tail 15 | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ''
    Write-Host "All files: $results"
    $ok = [bool]($status -and -not $status.critical -and -not $realFails.Count -and $diskRead -and -not $cachedAnswers.Count -and $outcome -eq 'complete' -and -not $unexpected.Count)
    Write-Host ''
    Write-Host "RESULT: $(if ($ok) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
catch {
    Log "ERROR: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
    $ok = $false
    Write-Host ''
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
}
finally {
    if (-not $KeepVm -and (Get-VM -Name $VmName -ErrorAction SilentlyContinue)) {
        Invoke-Quiet { Stop-VM -Name $VmName -TurnOff -Force -ErrorAction SilentlyContinue; Remove-VM -Name $VmName -Force -ErrorAction SilentlyContinue }
        # A passed test's disk (20+ GB) has nothing left to tell; a failed one's is the evidence
        if ($ok -and -not $KeepDisk -and (Test-Path -LiteralPath $vhd)) {
            Invoke-Quiet { Remove-Item -LiteralPath $vhd -Force -ErrorAction SilentlyContinue }
            Log "VM $VmName and its disk removed (-KeepDisk keeps the disk of a passed test)"
        } else {
            Log "VM $VmName removed (its disk stays at $WorkDir for inspection; the next test replaces it)"
        }
    }
    # The test ISO (wipes disk 0 without asking) and the media copy (its answer file holds the
    # passwords): gone, pass or fail. A kept VM gets its DVD drive emptied first.
    if (Get-VM -Name $VmName -ErrorAction SilentlyContinue) { Invoke-Quiet { Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue | Set-VMDvdDrive -Path $null -ErrorAction SilentlyContinue } }
    Invoke-Quiet { Remove-Item -LiteralPath $media -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $testIso) {
        Invoke-Quiet { Remove-Item -LiteralPath $testIso -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $testIso) { Write-Warning "Could not delete $testIso. Delete it by hand and NEVER write it to a USB stick: it erases disk 0 without asking." }
        else { Log 'Test ISO deleted' }
    }
    $null = [W11Kit.Awake]::SetThreadExecutionState([uint32]2147483648)   # ES_CONTINUOUS: sleep allowed again
    Stop-Transcript | Out-Null
}
exit $(if ($ok) { 0 } else { 1 })
