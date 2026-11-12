<#
.SYNOPSIS
    Enables BitLocker on the OS drive with a TPM protector and a recovery
    password that is saved ONLY to locations you choose. Nothing is escrowed
    to a Microsoft account.

.DESCRIPTION
    1. Checks TPM, Secure Boot, DMA protection and the account type. While
       the PC runs (or sits at the sign-in screen) the key is in RAM, so the
       ports must not allow DMA: Kernel DMA Protection on, or IOMMU active
       and no Thunderbolt/USB4 port. The hardware profile (profile.json,
       security.kernelDmaProtection) decides what a gap means: 'required'
       refuses (-AllowWithoutDmaProtection overrides), 'recommended' warns
       and asks (-Force skips the question). No readable profile: 'required'.
    2. Adds a recovery password protector (or reuses the existing one).
    3. Writes the recovery key to every backup location you pick, then reads
       each copy back to verify it, and notes the key's ID (not the key) in
       C:\ProgramData\W11Kit\bitlocker-recovery-id.json, so the validator can
       tell later whether the copy you keep is still the current one.
    4. Asks you to confirm the key is stored, then enables XTS-AES 256
       encryption with a TPM-only protector. Windows runs a hardware test on
       the next reboot before encryption starts.

    TPM-only (decision, 2026-10-07): a PC that hibernates and wakes over the LAN
    must boot and resume unattended; a startup PIN would stop every Wake-on-LAN
    at the pre-boot prompt. Hibernation writes memory to the encrypted disk, so
    the key is not in RAM while it is off.

    -ExportOnly  Only re-export recovery keys for all protected volumes.
    -StartupPin  Use TPM + startup PIN instead (breaks unattended Wake-on-LAN).
    -AddPin      Drive already encrypted with TPM only: switch it to TPM + PIN.

.EXAMPLE
    Enable-BitLocker.cmd                       (folder picker, interactive)
.EXAMPLE
    .\Enable-BitLockerLocal.ps1 -BackupPath E:\Keys, \\nas\secure\keys
.EXAMPLE
    Enable-BitLocker.cmd -AddPin               (add a startup PIN to an encrypted drive; breaks Wake-on-LAN)
#>
[CmdletBinding()]
param(
    [string]$MountPoint = $env:SystemDrive,
    [string[]]$BackupPath,
    [switch]$FullDisk,
    [switch]$ExportOnly,
    [switch]$Force,
    [switch]$AddPin,
    [switch]$StartupPin,
    # TPM-only BitLocker relies on DMA protection while the PC runs (see .DESCRIPTION).
    [switch]$AllowWithoutDmaProtection
)

$ErrorActionPreference = 'Stop'

# TPM-only unless a PIN was asked for
$useTpmOnly = -not $StartupPin -and -not $AddPin

# Hardware profile (docs/reference/PROFILES.md): DMA requirement and BIOS menu hints.
# Not readable: DMA protection is treated as required, hints are generic.
$hw = try { Get-Content -Raw -LiteralPath (Join-Path $env:ProgramData 'W11Kit\profile.json') -ErrorAction Stop | ConvertFrom-Json } catch { $null }
if (-not $hw) { Write-Warning 'Hardware profile (C:\ProgramData\W11Kit\profile.json) not readable: DMA protection treated as required.' }
$dmaPolicy = if ($hw -and "$($hw.security.kernelDmaProtection)" -eq 'recommended') { 'recommended' } else { 'required' }
$tpmHint = if ($hw -and $hw.firmwareHints -and $hw.firmwareHints.tpm) { "$($hw.firmwareHints.tpm)" } else { 'the TPM setting in your BIOS/UEFI security menu' }
$iommuHint = if ($hw -and $hw.firmwareHints -and $hw.firmwareHints.iommu) { "$($hw.firmwareHints.iommu)" } else { 'the IOMMU / VT-d / AMD-Vi setting' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw 'Run elevated (use Enable-BitLocker.cmd).' }

function Select-BackupFolders {
    Add-Type -AssemblyName System.Windows.Forms
    $paths = New-Object System.Collections.Generic.List[string]
    do {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Choose a folder for the BitLocker recovery key: a USB drive, or a NAS share typed as \\nas\share (mapped drive letters belong to the daily account and do not show here). Not on the drive being encrypted.'
        $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq 'OK') { $paths.Add($dlg.SelectedPath) }
        $more = [System.Windows.Forms.MessageBox]::Show("Selected so far:`n$($paths -join "`n")`n`nAdd another backup location?", 'BitLocker key backup', 'YesNo')
    } while ($more -eq 'Yes')
    $paths
}

# Notes WHICH recovery password was saved (its ID and the date, never the key itself) in
# C:\ProgramData\W11Kit\bitlocker-recovery-id.json. The validator compares the ID with the
# one on the disk: if they differ, the key file you keep no longer unlocks the drive.
# The ID is not a secret (the recovery screen shows it). A failure here only warns.
function Save-RecoveryRecord([string]$Volume, [string[]]$Ids) {
    $file = Join-Path $env:ProgramData 'W11Kit\bitlocker-recovery-id.json'
    try {
        $vols = @()
        try { $vols = @((Get-Content -Raw -LiteralPath $file -ErrorAction Stop | ConvertFrom-Json).volumes | Where-Object { $_ -and "$($_.volume)" -ne $Volume }) } catch { }
        $vols += [pscustomobject]@{ volume = $Volume; ids = @($Ids); saved = (Get-Date).ToString('yyyy-MM-dd') }
        $json = [ordered]@{
            description = 'IDs of the BitLocker recovery passwords that Enable-BitLockerLocal.ps1 last saved to your backup locations (not the keys). Test-InstalledPc.ps1 compares them with the drive.'
            volumes = @($vols)
        } | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding $false))
    } catch { Write-Warning "Could not record the recovery key's ID in ${file}: $_ (the key itself was saved; the validator just can't compare it)" }
}

function Save-RecoveryKeys([string[]]$Targets, [string]$Volume) {
    $vol = Get-BitLockerVolume -MountPoint $Volume
    $recovery = @($vol.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword')
    if (-not $recovery.Count) { throw "No recovery password protector on $Volume" }
    $text = @(
        'BitLocker Drive Encryption recovery key'
        ''
        "Computer:        $env:COMPUTERNAME"
        "Volume:          $Volume"
        "Created:         $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        ''
    )
    foreach ($r in $recovery) {
        $text += "Identifier:      $($r.KeyProtectorId)"
        $text += "Recovery key:    $($r.RecoveryPassword)"
        $text += ''
    }
    $text += 'Match the first characters of the Identifier with the value shown on the recovery screen.'
    $saved = 0
    foreach ($t in $Targets) {
        New-Item -ItemType Directory -Path $t -Force | Out-Null
        $id = $recovery[0].KeyProtectorId.Trim('{}').Substring(0, 8)
        $file = Join-Path $t "BitLocker-Recovery-$env:COMPUTERNAME-$($Volume.TrimEnd(':'))-$id.txt"
        $text | Set-Content -LiteralPath $file -Encoding UTF8
        $check = Get-Content -LiteralPath $file -Raw
        if ($recovery | Where-Object { $check -notmatch [regex]::Escape($_.RecoveryPassword) }) {
            Write-Warning "Verification FAILED for $file"
        } else {
            Write-Host "Saved and verified: $file" -ForegroundColor Green
            $saved++
        }
    }
    if ($saved -ge 1) { Save-RecoveryRecord $Volume @($recovery | ForEach-Object { "$($_.KeyProtectorId)" }) }
    return $saved
}

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

# Startup PIN, typed twice. Enhanced PINs (letters allowed) are enabled by the
# baseline (UseEnhancedPin=1); the length minimum is the policy's or 6.
function Read-StartupPin {
    $min = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -ErrorAction SilentlyContinue).MinimumPIN
    if (-not $min) { $min = 6 }
    Write-Host "Choose a BitLocker startup PIN ($min-20 characters). You type it at every cold boot, before Windows starts."
    Write-Host 'The pre-boot screen uses a US keyboard layout: avoid characters that sit elsewhere on other layouts.' -ForegroundColor Yellow
    $a = Read-Host 'Startup PIN' -AsSecureString
    $b = Read-Host 'Confirm startup PIN' -AsSecureString
    # Zero and free the unmanaged copies, so the PIN doesn't stay in memory
    $ba = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a)
    $bb = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
    try {
        $pa = [Runtime.InteropServices.Marshal]::PtrToStringAuto($ba)
        $pb = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bb)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ba)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bb)
    }
    if ($pa -cne $pb) { throw 'The PINs do not match - nothing changed.' }
    if ($pa.Length -lt $min -or $pa.Length -gt 20) { throw "The PIN must be $min-20 characters - nothing changed." }
    $pa = $null; $pb = $null
    $a
}

# Replace a TPM-only protector with TPM + PIN. The PIN protector is added first
# and the TPM-only one removed only after that worked; if Windows refuses a
# second TPM-based protector, the TPM-only one is removed and put back on failure.
function Set-TpmPinProtector([string]$MountPoint, [securestring]$Pin) {
    $tpmOnly = @((Get-BitLockerVolume -MountPoint $MountPoint).KeyProtector | Where-Object KeyProtectorType -eq 'Tpm')
    try {
        Add-BitLockerKeyProtector -MountPoint $MountPoint -TpmAndPinProtector -Pin $Pin -ErrorAction Stop | Out-Null
    } catch {
        if (-not $tpmOnly.Count) { throw }
        foreach ($p in $tpmOnly) { Remove-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $p.KeyProtectorId | Out-Null }
        try { Add-BitLockerKeyProtector -MountPoint $MountPoint -TpmAndPinProtector -Pin $Pin -ErrorAction Stop | Out-Null }
        catch { Add-BitLockerKeyProtector -MountPoint $MountPoint -TpmProtector | Out-Null; throw "Adding the PIN failed; the TPM-only protector was restored: $_" }
    }
    foreach ($p in @((Get-BitLockerVolume -MountPoint $MountPoint).KeyProtector | Where-Object KeyProtectorType -eq 'Tpm')) {
        Remove-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $p.KeyProtectorId | Out-Null
    }
    $types = @((Get-BitLockerVolume -MountPoint $MountPoint).KeyProtector | ForEach-Object KeyProtectorType)
    if ($types -notcontains 'TpmPin') { throw "No TPM + PIN protector after the change (protectors: $($types -join ', '))" }
    Write-Host "Startup PIN set. Protectors: $($types -join ', ')" -ForegroundColor Green
}

# --- Pre-flight --------------------------------------------------------------
$tpm = Get-Tpm
$sb = try { Confirm-SecureBootUEFI } catch { $false }
Write-Host "TPM present/ready: $($tpm.TpmPresent)/$($tpm.TpmReady)   Secure Boot: $sb"
if (-not $tpm.TpmReady) { throw "TPM is not ready. Enable $tpmHint and retry." }

if (-not $ExportOnly) {
    # Asked of Windows itself (NtQuerySystemInformation, SystemDmaGuardPolicyInformation), not read
    # from msinfo32's report: that text is translated on a PC with another display language.
    $dmaGuard = -1
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
        if ([W11KitDmaGuard]::NtQuerySystemInformation(202, [ref]$b, 1, [ref]$ret) -eq 0) { $dmaGuard = [int]($b -ne 0) }
    } catch { }
    Write-Host "  Kernel DMA Protection: $(if ($dmaGuard -eq 1) { 'On' } elseif ($dmaGuard -eq 0) { 'Off' } else { 'not readable (treated as off)' })"
    if ($dmaGuard -ne 1) {
        $x = Get-DmaExposure
        Write-Host "  IOMMU active: $($x.Iommu)   Thunderbolt/USB4 controllers: $(if ($x.External.Count) { $x.External -join ', ' } else { 'none' })"
        if ($x.Ok) {
            Write-Host '  Accepted: IOMMU on and no external DMA-capable port (docs/reference/CONFIGURATION.md, "BitLocker").'
        } else {
            # The fix first; the override only as an expert option, on its own line
            $msg = if (-not $x.Iommu) { "Kernel DMA Protection is off and the IOMMU is not active." }
                   else { "Kernel DMA Protection is off and this PC has an external DMA-capable port ($($x.External -join ', '))." }
            $fix = if (-not $x.Iommu) { "Fix: in the BIOS/UEFI setup turn on $iommuHint (the IOMMU: called IOMMU or AMD-Vi on AMD, VT-d on Intel), save, start Windows and run Enable BitLocker again." }
                   else { 'Fix: update the BIOS from your PC maker''s support site and turn on Kernel DMA Protection (or Thunderbolt/USB4 "pre-boot DMA protection") if it offers it, then run Enable BitLocker again.' }
            if ($AllowWithoutDmaProtection) { Write-Warning "$msg Encrypting anyway (-AllowWithoutDmaProtection)." }
            elseif ($dmaPolicy -eq 'required') {
                Write-Host "$msg This hardware profile requires DMA protection: BitLocker was not started, nothing changed." -ForegroundColor Red
                Write-Host $fix -ForegroundColor Yellow
                Write-Host ''
                Write-Host 'Experts only: C:\ProgramData\W11Kit\Enable-BitLocker.cmd -AllowWithoutDmaProtection (from a Command Prompt) encrypts anyway. The risk: while the PC is on (or at the sign-in screen) the key is in memory, and a device plugged into a DMA-capable port could read it.'
                throw 'DMA protection missing: nothing changed (see above).'
            }
            else {
                # Profile: 'recommended'. While the PC runs, the key is in RAM and a DMA-capable
                # device could read it; the owner decides.
                Write-Warning "$msg This hardware profile only recommends DMA protection."
                Write-Host $fix -ForegroundColor Yellow
                if (-not $Force) {
                    $go = Read-Host 'Encrypt anyway? Type YES to continue'
                    if ($go -cne 'YES') { Write-Host 'Stopped - nothing changed.'; return }
                }
            }
        }
    }
}

if (-not $ExportOnly) {
    # The image's policy allows TPM-only and TPM + PIN (Set-KitRegistry,
    # BitLocker section). Another hardening tool on the old install changed it,
    # and Enable-BitLocker then failed with "Value does not fall within the
    # expected range". Check that the protector we're about to add is allowed.
    $fve = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -ErrorAction SilentlyContinue
    $blocked = @()
    if ($useTpmOnly) {
        if ($fve.UseTPM -eq 0) { $blocked += 'UseTPM=0 (TPM-only unlock not allowed)' }
        foreach ($n in 'UseTPMPIN', 'UseTPMKey', 'UseTPMKeyPIN') { if ($fve.$n -eq 1) { $blocked += "$n=1 (required)" } }
    } else {
        if ($fve.UseTPMPIN -eq 0) { $blocked += 'UseTPMPIN=0 (startup PIN not allowed)' }
        foreach ($n in 'UseTPMKey', 'UseTPMKeyPIN') { if ($fve.$n -eq 1) { $blocked += "$n=1 (startup key required)" } }
    }
    if ($blocked) {
        Write-Host "BitLocker policy does not allow this unlock method: $($blocked -join ', ')." -ForegroundColor Red
        Write-Host 'Something changed the image''s policy, usually another hardening tool (docs/reference/SECURITY-BASELINE.md, "Other hardening tools"): remove it first.' -ForegroundColor Yellow
        Write-Host 'Then re-apply the kit''s policies from an administrator PowerShell (docs/reference/SECURITY-BASELINE.md, "Changing a setting later"):' -ForegroundColor Yellow
        Write-Host '  cd C:\ProgramData\W11Kit'
        Write-Host '  $p = (Get-Content -Raw profile.json | ConvertFrom-Json).power.mode'
        Write-Host '  & ([scriptblock]::Create((Get-Content -Raw .\Apply-Policy.ps1))) -PowerMode $p -Settings (Get-Content -Raw settings.json | ConvertFrom-Json) -LogDir .\Logs'
        Write-Host 'and run Enable BitLocker again.' -ForegroundColor Yellow
        throw "BitLocker policy does not allow this unlock method: $($blocked -join ', ') - nothing changed (see above)."
    }
    # Policy may force full-disk (1) or used-space-only (2) encryption
    if ($fve.OSEncryptionType -eq 1 -and -not $FullDisk) { Write-Host 'Policy requires full-disk encryption: encrypting the whole drive.'; $FullDisk = $true }
}

$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$msa = Get-LocalUser -Name ($me.Split('\')[-1]) -ErrorAction SilentlyContinue | Where-Object PrincipalSource -eq 'MicrosoftAccount'
if ($msa) { Write-Warning 'This Windows account is a Microsoft account. Windows may back up the key to it automatically.' }

if ($ExportOnly) {
    if (-not $BackupPath) { $BackupPath = Select-BackupFolders }
    Get-BitLockerVolume | Where-Object { $_.KeyProtector.KeyProtectorType -contains 'RecoveryPassword' } | ForEach-Object {
        Save-RecoveryKeys $BackupPath $_.MountPoint | Out-Null
    }
    return
}

$vol = Get-BitLockerVolume -MountPoint $MountPoint
Write-Host "Volume $MountPoint : $($vol.VolumeStatus), protection $($vol.ProtectionStatus), method $($vol.EncryptionMethod)"

if ($AddPin) {
    if ($vol.VolumeStatus -eq 'FullyDecrypted') { throw "$MountPoint is not encrypted: run without -AddPin to encrypt it with a PIN." }
    if (-not ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword')) { throw "$MountPoint has no recovery password protector: run without -AddPin first so a recovery key is created and saved." }
    if ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin') { Write-Host 'A startup PIN is already set; setting a new one.' }
    Set-TpmPinProtector $MountPoint (Read-StartupPin)
    Write-Host 'From the next cold boot BitLocker asks for the PIN. Your recovery key is unchanged.' -ForegroundColor Green
    return
}

if (-not $BackupPath) { $BackupPath = Select-BackupFolders }
$BackupPath = @($BackupPath | Where-Object { $_ })
if (-not $BackupPath.Count) { throw 'No backup location chosen - nothing changed.' }
$onTarget = $BackupPath | Where-Object { $_.TrimEnd('\').StartsWith($MountPoint.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }
if ($onTarget) { throw "Backup location(s) on the drive being encrypted are not allowed: $($onTarget -join ', ')" }

# --- Recovery password ---------------------------------------------------------
if (-not ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword')) {
    Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector | Out-Null
}
$saved = Save-RecoveryKeys $BackupPath $MountPoint
if ($saved -lt 1) { throw 'Recovery key could not be saved anywhere - encryption NOT started.' }

if (-not $Force) {
    $answer = Read-Host "Recovery key saved to $saved location(s). Type YES to start encryption"
    if ($answer -cne 'YES') { Write-Host 'Stopped. The recovery protector stays in place; re-run to continue.'; return }
}

# --- Encrypt -----------------------------------------------------------------
$vol = Get-BitLockerVolume -MountPoint $MountPoint
if ($vol.VolumeStatus -eq 'FullyDecrypted') {
    $params = @{ MountPoint = $MountPoint; EncryptionMethod = 'XtsAes256' }
    if ($useTpmOnly) { $params.TpmProtector = $true } else { $params.TpmAndPinProtector = $true; $params.Pin = Read-StartupPin }
    if (-not $FullDisk) { $params.UsedSpaceOnly = $true }
    Enable-BitLocker @params | Out-Null
    Write-Host 'BitLocker is enabled. Reboot: Windows runs a hardware test and then encrypts in the background.' -ForegroundColor Green
    Write-Host 'IMPORTANT: without PCR7 binding (msinfo32: PCR7 Configuration) ANY BIOS setting change or BIOS update triggers the recovery screen.' -ForegroundColor Yellow
    Write-Host '           Before entering the BIOS, run as admin:  Suspend-BitLocker -MountPoint C: -RebootCount 1' -ForegroundColor Yellow
} else {
    # Already encrypted (e.g. device encryption waiting for activation): add the
    # TPM (+ PIN) protector and turn protection on.
    if ($useTpmOnly) {
        # TPM-only: a TPM+PIN protector (the 2026-10-05 design) is replaced, since a PIN
        # stops every Wake-on-LAN at the pre-boot prompt. Only one TPM-based protector
        # can exist, so the PIN one goes first; the recovery password stays meanwhile.
        foreach ($p in @($vol.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -in 'TpmPin', 'TpmPinStartupKey', 'TpmStartupKey' })) {
            Write-Host "Removing the $($p.KeyProtectorType) protector (TPM-only from now on)"
            Remove-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $p.KeyProtectorId | Out-Null
        }
        $vol = Get-BitLockerVolume -MountPoint $MountPoint
        if (-not ($vol.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'Tpm' })) { Add-BitLockerKeyProtector -MountPoint $MountPoint -TpmProtector | Out-Null }
    } elseif (-not ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin')) {
        Set-TpmPinProtector $MountPoint (Read-StartupPin)
    }
    Resume-BitLocker -MountPoint $MountPoint | Out-Null
    Write-Host 'Protection is on.' -ForegroundColor Green
}
Get-BitLockerVolume -MountPoint $MountPoint | Format-List MountPoint, VolumeStatus, ProtectionStatus, EncryptionMethod, EncryptionPercentage, KeyProtector
