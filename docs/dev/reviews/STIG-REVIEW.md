# DISA Windows 11 STIG and the W11Kit image: gap analysis

> For contributors and maintainers. Using the kit? Start with the [guide](../../GUIDE.md).

> **Snapshot of 2026-10-08.** The current state is in
> [SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md).

A rule-by-rule comparison of the image this kit builds with the DISA *Microsoft Windows 11
Security Technical Implementation Guide*. It was done to find settings worth adopting, and to
write down why the rest are not.

It is a static review of the configuration, read from the kit's files. It is **not a STIG
assessment**, no scanner was run, and the image is **not STIG-compliant**: the kit applies
selected STIG settings ([DECISIONS](../DECISIONS.md#selected-disa-stig-settings)). The classes
below are those after the adopted items went into the kit.

## Result

- **Meets the rule's check as configured: 223 of 257** (static review; not a STIG assessment).
- 13 rules don't apply to a standalone PC, 4 are procedures, 2 could not be decided by reading.
- **15 findings remain**: 8 rules that are not met (GAP) and 7 where a documented decision of the
  kit deviates from the rule.
- The review led to **33 rules being adopted** (they were GAP and are now set by the kit), and to
  a validator warning for one procedural rule (BitLocker). They are listed under
  [Adopted](#adopted) and described for users in
  [SECURITY-BASELINE, DISA STIG additions](../../reference/SECURITY-BASELINE.md#disa-stig-additions).

## Source and method

**STIG:** Microsoft Windows 11 Security Technical Implementation Guide, **Version 2, Release 11**
(XCCDF status date 2026-09-01, "Benchmark Date: 30 Sep 2026"): 257 rules (27 CAT I, 215 CAT II,
15 CAT III). Source: DISA's official XCCDF,
`https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_MS_Windows_11_V2R11_STIG.zip`
(SHA-256 `5a1337e899f113a2482debd3ef240a867fdd205423cbf134e8961de249260d54`), which NIST's
National Checklist Program listed as the current release.

**Method:** the XCCDF was parsed rule by rule. The effective configuration was modelled in the
order first-boot setup applies it:

1. Microsoft's Windows 11 v26H2 baseline (the `-Win11DomainJoined` set, so the non-domain-joined
   difference is not applied), read from the `registry.pol`, `GptTmpl.inf` and `audit.csv` files
   of the official zip;
2. the Edge v151 baseline;
3. the kit's overrides (`config/baseline-overrides.txt`, `.inf` and `-audit.csv`);
4. the kit's own policies and registry values (`scripts/Set-KitRegistry.ps1`);
5. the rest of `payload/PostInstall.ps1` (for example `net accounts /maxpwage:unlimited`).

Every registry check of the STIG was compared value by value; the rest was judged by hand.

**Limits:**

- No installed PC was read. DEFAULT means "Windows 11's default already meets the check, and
  nothing in the kit changes it". The few defaults that deserve a look on a real PC are under
  [Verify on the installed PC](#verify-on-the-installed-pc).
- The Windows 11 STIG is meant to be used together with the Defender Antivirus, Edge, Firewall and
  OneDrive STIGs. Those are **out of scope**. Several kit overrides (the Edge extension and
  certificate-error ones, Defender sample submission) would show up there instead.

## Summary

| Class | Meaning | CAT I | CAT II | CAT III | Total |
|---|---|---:|---:|---:|---:|
| BASELINE | Set by Microsoft's security baseline | 18 | 123 | 7 | 148 |
| KIT | Set by the kit (its own settings, or a STIG item it adopted) | 3 | 36 | 2 | 41 |
| DEFAULT | Windows 11's default already meets the check, and nothing in the kit changes it | 3 | 28 | 3 | 34 |
| OVERRIDE-DEVIATES | A documented override or decision of the kit deviates from the rule | 1 | 6 | 0 | 7 |
| GAP | Not met, and not set by the kit | 1 | 7 | 0 | 8 |
| N/A-STANDALONE | Doesn't apply to a standalone PC outside the US Department of Defense | 0 | 11 | 2 | 13 |
| MANUAL/PROCEDURAL | A procedure, not a setting | 1 | 2 | 1 | 4 |
| UNKNOWN | Could not be decided by reading; see *Verify on the installed PC* | 0 | 2 | 0 | 2 |
| **Total** | | 27 | 215 | 15 | 257 |

Meeting the check as configured: BASELINE 148 + KIT 41 + DEFAULT 34 = **223**. Findings:
GAP 8 + OVERRIDE-DEVIATES 7 = **15**.

Of the kit's 18 overrides of the baseline (17 in a build without `options.gamingTweaks`), five
touch a Windows 11 STIG rule: Credential Guard
without UEFI lock (CAT I, but not achievable on Pro anyway), memory integrity without lock (the
check is still met: the STIG accepts the value 2), the admin listed at the UAC prompt, the
credential prompt for the standard user, and the 11-character minimum password. Four more
overrides come from this review and make the baseline stricter. Three decisions of the kit also
deviate: BitLocker TPM-only (CAT I), no application allowlisting, and no password expiry (2
rules).

## CAT I rules (all 27)

| Rule | STIG ID | Title | Class | Evidence |
|---|---|---|---|---|
| V-253259 | WN11-00-000030 | Windows 11 information systems must use BitLocker to encrypt all disks to protect the confidentiality and integrity of all information at rest. | MANUAL/PROCEDURAL | BitLocker is a deliberate manual step after the install (`Enable-BitLocker.cmd`, TPM-only), so the disk is not encrypted at image time. The validator WARNs until `C:` and every fixed data drive are encrypted. |
| V-253260 | WN11-00-000031 | Windows 11 systems must use a BitLocker PIN for pre-boot authentication. | OVERRIDE-DEVIATES | Project decision: BitLocker TPM-only ([DECISIONS](../DECISIONS.md#bitlocker-manual-tpm-only)). `UseTPMPIN` = 2 and `UseTPMKeyPIN` = 2: a PIN is allowed, not required. The STIG requires it (1). Deviation by decision. |
| V-253263 | WN11-00-000040 | Windows 11 systems must be maintained at a supported servicing level. | KIT | 26H2 (support to ~2028-10 for Pro), monthly rebuild with the current LCU, Windows Update on, feature version pinned to 26H2 (TargetReleaseVersion). |
| V-253264 | WN11-00-000045 | The Windows 11 system must use an antivirus program. | BASELINE | Defender Antivirus GPO (real-time on, cloud protection, PUA); kit adds PUAProtection, signature update during first-boot setup; validator checks real-time protection. |
| V-253265 | WN11-00-000050 | Local volumes must be formatted using NTFS. | DEFAULT | Windows Setup formats the OS volume NTFS (disk selection is interactive). Caveat: a Dev Drive (ReFS) or exFAT data volume with a drive letter would be a finding. |
| V-253269 | WN11-00-000070 | Only accounts responsible for the administration of a system must have Administrator rights on the system. | KIT | Decision: standard daily account LocalUser (Users) + separate LocalAdmin (Administrators), autounattend. |
| V-253275 | WN11-00-000100 | Internet Information System (IIS) or its subcomponents must not be installed on a workstation. | DEFAULT | IIS is an optional feature, off by default; image.json enables only WSL + VirtualMachinePlatform. |
| V-253284 | WN11-00-000150 | Structured Exception Handling Overwrite Protection (SEHOP) must be enabled. | BASELINE | DisableExceptionChainValidation=0 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253294 | WN11-00-000240 | Administrative accounts must not be used with applications that access the internet, such as web browsers, or with potential internet sources, such as email. | KIT | AppLocker deny rules keep web browsers from running for administrator accounts ([SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md#browsers-blocked-for-administrators-applocker)). E-mail clients are not covered; the two-account design covers that part by procedure. |
| V-253305 | WN11-AC-000045 | Reversible password encryption must be disabled. | BASELINE | ClearTextPassword = 0. |
| V-253370 | WN11-CC-000075 | Credential Guard must be running on Windows 11 systems. | GAP | Credential Guard must be running. It can't run on Windows 11 Pro (an Enterprise and Education feature), and the override also sets `LsaCfgFlags` = 2 (no UEFI lock) where the STIG wants 1. Not achievable on Pro. |
| V-253382 | WN11-CC-000155 | Solicited Remote Assistance must not be allowed. | BASELINE | fAllowToGetHelp=0 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253386 | WN11-CC-000180 | Autoplay must be turned off for non-volume devices. | BASELINE | NoAutoplayfornonVolume=1 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253387 | WN11-CC-000185 | The default autorun behavior must be configured to prevent autorun commands. | BASELINE | NoAutorun=1 (BASELINE:MSFT Windows 11 26H2 - Computer (+ kit, same value)) |
| V-253388 | WN11-CC-000190 | Autoplay must be disabled for all drives. | BASELINE | NoDriveTypeAutoRun=255 (BASELINE:MSFT Windows 11 26H2 - Computer (+ kit, same value)) |
| V-253411 | WN11-CC-000315 | The Windows Installer feature "Always install with elevated privileges" must be disabled. | BASELINE | AlwaysInstallElevated=0 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253416 | WN11-CC-000330 | The Windows Remote Management (WinRM) client must not use Basic authentication. | BASELINE | AllowBasic=0 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253418 | WN11-CC-000345 | The Windows Remote Management (WinRM) service must not use Basic authentication. | BASELINE | AllowBasic=0 (BASELINE:MSFT Windows 11 26H2 - Computer) |
| V-253452 | WN11-SO-000140 | Anonymous SID/Name translation must not be allowed. | BASELINE | GptTmpl LSAAnonymousNameLookup = 0. |
| V-253453 | WN11-SO-000145 | Anonymous enumeration of SAM accounts must not be allowed. | BASELINE | RestrictAnonymousSAM=1 (BASELINE:MSFT Windows 11 26H2 - Computer (GptTmpl)) |
| V-253454 | WN11-SO-000150 | Anonymous enumeration of shares must be restricted. | BASELINE | RestrictAnonymous=1 (BASELINE:MSFT Windows 11 26H2 - Computer (GptTmpl)) |
| V-253456 | WN11-SO-000165 | Anonymous access to Named Pipes and Shares must be restricted. | BASELINE | RestrictNullSessAccess=1 (BASELINE:MSFT Windows 11 26H2 - Computer (GptTmpl)) |
| V-253461 | WN11-SO-000195 | The system must be configured to prevent the storage of the LAN Manager hash of passwords. | DEFAULT | Lsa NoLMHash ships as 1 (since Windows Vista); not changed by baseline or kit. |
| V-253462 | WN11-SO-000205 | The LanMan authentication level must be set to send NTLMv2 response only, and to refuse LM and NTLM. | BASELINE | LmCompatibilityLevel=5 (BASELINE:MSFT Windows 11 26H2 - Computer (GptTmpl)) |
| V-253481 | WN11-UR-000015 | The "Act as part of the operating system" user right must not be assigned to any groups or accounts. | BASELINE | SeTcbPrivilege = (none). |
| V-253486 | WN11-UR-000045 | The "Create a token object" user right must not be assigned to any groups or accounts. | BASELINE | SeCreateTokenPrivilege = (none). |
| V-253490 | WN11-UR-000065 | The "Debug programs" user right must only be assigned to the Administrators group. | BASELINE | SeDebugPrivilege = Administrators. |

**The CAT I situation.** 24 of 27 meet the rule's check as configured (18 baseline, 3 kit, 3
Windows default). The other three:

- **V-253259, BitLocker on all disks**: met only after you run *Enable BitLocker (local key)*.
  That is the documented procedure; the validator WARNs until `C:` and every fixed data drive are
  encrypted, so the step can't be forgotten.
- **V-253260, BitLocker startup PIN**: deviates by decision (TPM-only, so that Wake-on-LAN
  works). Accepted risk. The documented mitigations are a BIOS admin password, Kernel DMA
  Protection, the internal disk first in the boot order and hibernate instead of sleep. With
  TPM-only, hibernation does not protect against someone who powers a stolen PC on: the disk
  unlocks, and the Windows sign-in (lockout, 11-character passwords, Hello PIN) is then the
  barrier.
- **V-253370, Credential Guard running**: impossible on Windows 11 **Pro**. The override's "no
  UEFI lock" (2 instead of 1) is secondary. LSA protection (`RunAsPPL`), memory integrity and the
  ASR rule for LSASS cover part of the risk.

V-253294 (administrators must not browse or read e-mail) was met only by procedure at review time:
the two-account design, with nothing that technically stopped the admin account from opening a
browser. The kit now denies browsers to administrators with AppLocker. A per-group policy with a
URL blocklist was considered first; it would have covered only some browsers.

## Adopted

These rules were GAP at review time and are now set by the kit (class KIT), plus the BitLocker
reminder. None of them touches WSL, Wake-on-LAN, hibernation or the PC's ability to build its own
ISO.

| Rule | Sev | Title | What the kit sets | Side effects |
|---|---|---|---|---|
| V-253259 | CAT I | Windows 11 information systems must use BitLocker to encrypt all disks to protect the confidentiality and integrity of all information at rest. | Nothing in the image: BitLocker stays a manual step. The validator's BitLocker row is WARN (not INFO) while `C:` is unencrypted, and a second row covers fixed data drives. | None beyond the documented procedure. |
| V-253294 | CAT I | Administrative accounts must not be used with applications that access the internet, such as web browsers, or with potential internet sources, such as email. | AppLocker in deny-list mode: `msedge.exe`, `brave.exe`, `chrome.exe` and `firefox.exe` are denied to `BUILTIN\Administrators` and to the admin account's own SID, by publisher and by path. One Appx rule keeps every signed packaged app allowed (`payload/New-AdminBrowserPolicy.ps1`). | An elevated installer can't open a browser window (sign-in pages, release notes). WebView2 is not blocked. An unsigned or unlisted browser isn't caught, and an administrator can remove the policy. E-mail clients are not covered. |
| V-253261 | CAT II | Windows 11 systems must use a BitLocker PIN with a minimum length of six digits for pre-boot authentication. | `Software\Policies\Microsoft\FVE` `MinimumPIN` = 6. | None while TPM-only. Only applies if you ever add a PIN (Enable-BitLockerLocal -StartupPin / -AddPin); Windows' own default minimum is already 6. Enable-BitLockerLocal must still pass its policy self-check. |
| V-253289 | CAT II | The Secondary Logon service must be disabled on Windows 11. | Service `seclogon` Disabled (`baseline-overrides.inf`, `[Service General Setting]`). | Breaks *Run as different user*, `runas.exe` and `Start-Process -Credential` (`CreateProcessWithLogonW`). UAC elevation is not affected, so the standard user's credential prompt keeps working. Some third-party installers and launchers relaunch themselves through runas-style calls. |
| V-253302 | CAT II | The minimum password age must be configured to at least 1 day. | `baseline-overrides.inf` [System Access] MinimumPasswordAge = 1. | A user cannot change their own password twice within 24 h (e.g. after a mistake right after the forced first-sign-in change); an admin reset (net user / lusrmgr) still works. The forced change at first sign-in is not blocked. |
| V-253327 | CAT II | The system must be configured to audit Policy Change - Authorization Policy Change successes. | Audit Authorization Policy Change = Success ({0cce9231-...}). | Few events (user-right/token policy changes). |
| V-253328 | CAT II | The system must be configured to audit Privilege Use - Sensitive Privilege Use failures. | Audit Sensitive Privilege Use = Success and Failure (3). | Can be chatty (4673 failures from some apps/anti-cheat); watch Security log size. |
| V-253330 | CAT II | The system must be configured to audit System - IPsec Driver failures. | Audit IPsec Driver = Failure ({0cce9213-...}, value 2). | Practically no events (no IPsec in use). |
| V-278928 | CAT II | Windows 11 must be configured to audit handle manipulation failures. | Audit Handle Manipulation = Failure ({0cce9223-...}, 2). | Events only for objects with SACLs (few by default). |
| V-257770 | CAT II | Windows 11 must have command line process auditing events enabled for failures. | Audit Process Creation = Success and Failure (3). | Few failure events. |
| V-278931 | CAT II | Windows 11 must be configured to audit registry successes. | Same entry as V-278930. | As V-278930. |
| V-278933 | CAT II | Windows 11 must be configured to audit sensitive privilege use failures. | Same entry as V-253328. | As V-253328. |
| V-278930 | CAT II | Windows 11 must be configured to audit registry failures. | Audit Registry = Success and Failure ({0cce921e-...}, 3). | Events only for keys with SACLs (few by default); a tool that adds broad SACLs would flood the log. |
| V-253358 | CAT II | WDigest Authentication must be disabled. | `SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest` `UseLogonCredential` = 0 (not a policy path: `Set-KitRegistry.ps1` writes it directly). | None (already the default behaviour). |
| V-253359 | CAT II | Run as different user must be removed from context menus. | SuppressionPolicy = 4096 (DWORD) under HKLM\SOFTWARE\Classes\batfile\|cmdfile\|exefile\|mscfile\shell\runasuser (4 Set-KitRegistry SOFTWARE entries). | Shift+right-click "Run as different user" disappears from Explorer. |
| V-253373 | CAT II | Group Policy objects must be reprocessed even if they have not changed. | Computer, Software\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}, NoGPOListChanges, DWORD:0. | Local registry policy is re-applied at every refresh (90 min) even when unchanged: a local admin/app that edits a policy value gets reverted. Negligible CPU. |
| V-253376 | CAT II | Printing over HTTP must be prevented. | Computer, Software\Policies\Microsoft\Windows NT\Printers, DisableHTTPPrinting, DWORD:1. | No printing to http:// print URLs (IPP over HTTP); normal network/USB printers unaffected. |
| V-253378 | CAT II | The network selection user interface (UI) must not be displayed on the logon screen. | Computer, Software\Policies\Microsoft\Windows\System, DontDisplayNetworkSelectionUI, DWORD:1. | Cannot pick a Wi-Fi network from the sign-in screen (Ethernet is primary). |
| V-253400 | CAT II | The use of a hardware security device with Windows Hello for Business must be enabled. | Computer, Software\Policies\Microsoft\PassportForWork, RequireSecurityDevice, DWORD:1. | A Windows Hello PIN must be backed by the TPM (it already is on a PC with a TPM 2.0). If the TPM is cleared, Hello must be set up again. |
| V-253401 | CAT II | Windows 11 must be configured to require a minimum PIN length of six characters or greater. | Computer, Software\Policies\Microsoft\PassportForWork\PINComplexity, MinimumPINLength, DWORD:6. | Hello PIN needs >= 6 digits (Windows default 4). TPM anti-hammering still applies. |
| V-289260 | CAT II | Windows 11 must be configured to prevent Windows apps from being activated by voice. | Computer, Software\Policies\Microsoft\Windows\AppPrivacy, LetAppsActivateWithVoice, DWORD:2 (Force Deny). | No voice-activated apps (voice wake words) while signed in. |
| V-253435 | CAT II | The built-in administrator account must be renamed. | `NewAdministratorName` in the staged security template: a name generated for each build (or `accounts.builtinAdministratorName`). | None: the built-in Administrator is disabled, and `LocalAdmin` is the real admin. Recovery instructions that say "Administrator" need the new name. |
| V-253436 | CAT II | The built-in guest account must be renamed. | `NewGuestName`: a name generated for each build (or `accounts.builtinGuestName`). | None (Guest is disabled). |
| V-253459 | CAT II | PKU2U authentication using online identities must be prevented. | `SYSTEM\CurrentControlSet\Control\Lsa\pku2u` `AllowOnlineID` = 0 (`Set-KitRegistry.ps1`). | Blocks PKU2U online-ID authentication between PCs (used by Entra-joined peer auth / old HomeGroup); none used here. |
| V-253460 | CAT II | Kerberos encryption types must be configured to prevent the use of DES and RC4 encryption suites. | `SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters` `SupportedEncryptionTypes` = 2147483640: AES128, AES256 and future types (`Set-KitRegistry.ps1`). | None on a standalone PC (no Kerberos realm). Would matter only if joined to an old NAS/AD that needs RC4. |
| V-253491 | CAT II | The "Deny access to this computer from the network" user right on workstations must be configured to prevent access from highly privileged domain accounts and local accounts on domain systems and unauthenticated access on all systems. | `baseline-overrides.inf` [Privilege Rights] SeDenyNetworkLogonRight = *S-1-5-113,*S-1-5-32-546. | None (Guests already covered via Local account). |
| V-253494 | CAT II | The "Deny log on locally" user right on workstations must be configured to prevent access from highly privileged domain accounts on domain systems and unauthenticated access on all systems. | [Privilege Rights] SeDenyInteractiveLogonRight = *S-1-5-32-546 (Guests). | None (Guest disabled; LocalUser is in Users, not Guests). |
| V-253495 | CAT II | The "Deny log on through Remote Desktop Services" user right on Windows 11 workstations must be configured to prevent access from highly privileged domain accounts and local accounts on domain systems and unauthenticated access on all systems. | `[Privilege Rights]` `SeDenyRemoteInteractiveLogonRight` = `*S-1-5-113,*S-1-5-32-546`: the baseline's *Local account* entry stays, and Guests are added. | None: Remote Desktop is off by decision, and a remote-access tool doesn't use a Remote Desktop Services logon. |
| V-288475 | CAT II | All Wi-Fi Direct adapters must be disabled on the system. | First-boot setup disables the *Microsoft Wi-Fi Direct* virtual adapters; the validator has a row. | No Mobile hotspot, no Miracast casting to a TV or monitor, no Wi-Fi Direct printers, no Nearby sharing over Wi-Fi Direct. Ordinary Wi-Fi is unaffected. A driver update may create the adapter again. |
| V-253297 | CAT II | Windows 11 account lockout duration must be configured to 15 minutes or greater. | `baseline-overrides.inf` `[System Access]` `LockoutDuration` = 15. | A lockout lasts 15 instead of 10 minutes, for the only admin too (`AllowAdministratorLockout` = 1). |
| V-253299 | CAT II | The period of time before the bad logon counter is reset must be configured to 15 minutes. | ResetLockoutCount = 15. | None noticeable (bad-attempt counter forgets after 15 instead of 10 minutes). Must be <= LockoutDuration. |
| V-253338 | CAT II | The security event log size must be configured to a value that holds at least one week's worth of audit records. | `Software\Policies\Microsoft\Windows\EventLog\Security` `MaxSize` = 1048576 KB (1 GB). The STIG's own example value is 5120000 KB; the rule asks for a week of records. | Disk space only; a larger log is slower to open in Event Viewer. Whether 1 GB holds a week depends on use: see *Verify on the installed PC*. |
| V-253385 | CAT III | The Application Compatibility Program Inventory must be prevented from collecting data and sending the information to Microsoft. | Computer, Software\Policies\Microsoft\Windows\AppCompat, DisableInventory, DWORD:1. | Turns off the (deprecated) Inventory Collector; no compatibility-assessment upload. Feature updates are done by rebuild anyway. |
| V-253394 | CAT III | Windows Update must not obtain updates from other PCs on the internet. | `Software\Policies\Microsoft\Windows\DeliveryOptimization` `DODownloadMode` = 0 (HTTP only). | No peer-to-peer update downloads (a single PC has no peers anyway); Store and WU still download via HTTP. |

How they are applied:

- **Registry values** are in `scripts/Set-KitRegistry.ps1`, area *STIG*: written into the offline
  image, exported to local Group Policy where they are policy values, and checked by the build's
  read-back and by the validator.
- **Account policy, user rights and the Secondary Logon service** are in
  `config/baseline-overrides.inf`. A `[Privilege Rights]` line replaces the baseline's whole list
  for that right, so each line repeats the baseline's entries and adds Guests.
- **The built-in Administrator and Guest accounts** get names drawn for each build (or the ones in
  `accounts.builtinAdministratorName` / `accounts.builtinGuestName`), added to the staged copy of
  `baseline-overrides.inf` and recorded in the image's `build-options.json`. Both accounts stay
  disabled.
- **`PassportForWork`** sets only the hardware-device and PIN-length rules, not `Enabled` (which
  would start Windows Hello for Business provisioning).
- **Seven audit subcategories** are in `config/baseline-overrides-audit.csv`: Process Creation,
  Sensitive Privilege Use and Registry (success and failure); IPsec Driver and Handle Manipulation
  (failure); Authorization Policy Change and Logoff (success). They cover V-257770, V-253328 and
  V-278933, V-278930 and V-278931, V-253330, V-278928 and V-253327. The file is never applied on
  its own: first-boot setup merges it with the baseline's `audit.csv`
  (`payload/Merge-AuditPolicy.ps1`) and applies the one merged file.
- Sensitive Privilege Use failures (event 4673) can be frequent with some applications. That is
  one reason for the larger Security log.

## Remaining findings

The 15 rules that are not met. *Open* means undecided: it could still be adopted. *Deviation* and
*Not adopted* mean it conflicts with a decision
([DECISIONS](../DECISIONS.md),
[SECURITY-BASELINE, Known risks accepted](../../reference/SECURITY-BASELINE.md#known-risks-accepted)).

| Rule | Sev | Class | Title | What it would take | Side effects | Status | Why |
|---|---|---|---|---|---|---|---|
| V-253260 | CAT I | OVERRIDE-DEVIATES | Windows 11 systems must use a BitLocker PIN for pre-boot authentication. | `FVE` `UseTPMPIN` = 1 / `UseTPMKeyPIN` = 1 (require a startup PIN), and add a PIN protector. | Every start and every Wake-on-LAN start from hibernate or shutdown stops at the pre-boot PIN prompt: remote wake becomes useless. Network Unlock (the STIG's way out) needs WDS and Active Directory. | Deviation | [DECISIONS](../DECISIONS.md#bitlocker-manual-tpm-only): BitLocker manual, TPM-only. Accepted risk: a stolen PC starts up to the Windows sign-in screen. Mitigations: a BIOS admin password, Kernel DMA Protection, the internal disk first in the boot order, hibernate instead of sleep. |
| V-253370 | CAT I | GAP | Credential Guard must be running on Windows 11 systems. | Windows 11 Enterprise or Education (Credential Guard doesn't run on Pro), plus `LsaCfgFlags` = 1 (UEFI lock). | An edition change means a different licence. The UEFI lock would also block turning VBS features off to troubleshoot a driver or an anti-cheat-protected game. | Not adopted | Not achievable on Pro. Decisions: Windows 11 Pro only; override "no UEFI lock". LSA protection (`RunAsPPL` = 2) and memory integrity cover part of the credential-theft risk, and the ASR rule "block credential stealing from LSASS" is on. |
| V-268317 | CAT II | GAP | Copilot must be disabled for Windows 11. | Nothing to add. `Microsoft.Copilot` is not a provisioned app in the 26H2 image the kit builds from (the build manifest's `provisionedAfter` list has no Copilot package), and the `TurnOffWindowsCopilot` policy this rule was written around is deprecated (it controlled the old Copilot sidebar). | None. | Open | Nothing to adopt today. If a later source ISO carries `Microsoft.Copilot`, add it to `removal-manifest.json` "remove". Related: Click to Do, the Paint and Notepad AI features and Edge's Copilot entry points are off by policy. |
| V-253291 | CAT II | GAP | Bluetooth must be turned off unless approved by the organization. | `PolicyManager` Connectivity `AllowBluetooth` = 0, or the radio turned off. | No Bluetooth mice, headsets or controllers, and no Phone Link. | Open | Project decision: keep Bluetooth on a home PC and treat the rule as accepted. The STIG allows Bluetooth when it is approved. |
| V-253363 | CAT II | GAP | Windows 11 must be configured to prioritize ECC Curves with longer key lengths first. | `Software\Policies\Microsoft\Cryptography\Configuration\SSL\00010002` `EccCurves` = `REG_MULTI_SZ` NistP384, NistP256. | Schannel (Windows Update, the Store, .NET and PowerShell web requests, `curl.exe`) stops offering curve25519 and any newer groups Windows adds. Chromium browsers and Firefox use their own TLS and are unaffected. Low risk of breakage, small security gain. | Open | Low value for a home PC. `Set-KitRegistry.ps1` would need `REG_MULTI_SZ` support. Worth it only if a clean STIG scan matters. |
| V-253415 | CAT II | GAP | PowerShell Transcription must be enabled on Windows 11. | `Software\Policies\Microsoft\Windows\PowerShell\Transcription`: `EnableTranscripting` = 1, `OutputDirectory` = an admin-owned folder that users can only write to, `EnableInvocationHeader` = 1. | Every PowerShell session, the multi-hour build and the validator included, writes a full transcript: disk growth, and anything typed or printed lands in a file (the kit never prints passwords; other tools might). Without `OutputDirectory` the default is the user's Documents folder, which a cloud folder backup would upload. | Open | A useful audit trail, but it needs the folder and its ACL in first-boot setup and a clean-up plan. See also the [best-practice survey](BEST-PRACTICE-SURVEY.md#considered-not-adopted). |
| V-253466 | CAT II | GAP | The system must be configured to use FIPS-compliant algorithms for encryption, hashing, and signing. | Security option "System cryptography: Use FIPS compliant algorithms" = Enabled (`Lsa\FipsAlgorithmPolicy\Enabled` = 1). | Non-FIPS algorithms throw in .NET Framework apps (`RijndaelManaged`, MD5), in some development tools and tests, in older games and launchers and in some VPN clients. Microsoft itself doesn't recommend it outside regulated environments. | Open | Not recommended: it breaks things unpredictably on a PC used for development or games. |
| V-253476 | CAT II | OVERRIDE-DEVIATES | Passwords for enabled local Administrator accounts must be changed at least every 180 days. | Change the admin account's password at least every 180 days (LAPS needs a directory; "an alternative process ... is acceptable if documented"). | A manual chore twice a year. No forced expiry needed. | Deviation (open) | A cheap middle way that keeps the no-expiry decision: a validator WARN when the admin's password is older than 180 days. Not adopted yet. |
| V-253262 | CAT II | OVERRIDE-DEVIATES | The operating system must employ a deny-all, permit-by-exception policy to allow the execution of authorized software programs. | App Control for Business or AppLocker as a deny-by-default allowlist, packaged apps included. | Blocks your own unsigned builds, WSL interop binaries in development trees, game launchers and patchers (their updates write new executables) and the kit's own ISO build (`oscdimg`, DISM from mounts), unless every path or publisher is allowlisted. High upkeep. | Deviation | [SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md#considered-not-adopted); [DECISIONS](../DECISIONS.md#self-hosting): the installed PC must be able to rebuild its own ISO. |
| V-279688 | CAT II | GAP | Windows 11 systems must block consumer account user authentication. | `Software\Policies\Microsoft\MicrosoftAccount` `DisableUserAuth` = 1. | Blocks every sign-in to an app with a consumer Microsoft account: Store purchases, the Xbox app, OneDrive personal, Edge sync. | Not adopted | Signing in to an app stays your choice. The kit already blocks a Microsoft account for *Windows* sign-in (`NoConnectedUser` = 1). |
| V-253298 | CAT II | GAP | The number of allowed bad logon attempts must be configured to three or less. | `LockoutBadCount` = 3. | Three mistyped admin passwords at a UAC prompt lock out the only admin for 15 minutes. | Not adopted | The 10-attempt lockout stays as the baseline sets it ([SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md#overrides)). With one admin account, a stricter lockout is a denial of service against yourself. |
| V-253301 | CAT II | OVERRIDE-DEVIATES | The maximum password age must be configured to 180 days or less. | Remove `net accounts /maxpwage:unlimited` from first-boot setup (the Windows default is 42 days), or set `MaximumPasswordAge` to 180 or less. | Forced password changes for both accounts. NIST SP 800-63B and Microsoft's baseline (since 2019) advise against periodic expiry. | Deviation | Password expiry is off on purpose, following current Microsoft and NIST guidance. |
| V-253303 | CAT II | OVERRIDE-DEVIATES | Passwords must, at a minimum, be 14 characters. | `MinimumPasswordLength` = 14 (drop the override), and the matching check in `Build-Iso.ps1`. | A longer admin password typed at every UAC prompt. The generated one-time passwords have 20 characters already. | Deviation | Documented override: an 11-character minimum. The cheapest override to revisit. |
| V-253391 | CAT II | OVERRIDE-DEVIATES | Administrator accounts must not be enumerated during elevation. | `EnumerateAdministrators` = 0 (drop the override). | On a real install of an earlier version of this kit, with one admin and the lockout, having to type the admin's name at the UAC prompt ended in a lockout of the only admin. | Deviation | Documented override: the admin account is listed at the UAC prompt. |
| V-253471 | CAT II | OVERRIDE-DEVIATES | User Account Control must automatically deny elevation requests for standard users. | `ConsentPromptBehaviorUser` = 0 (drop the override). | The standard daily user can no longer elevate with the admin's credentials: every install or admin task needs a full switch of user. | Deviation | Documented override: the credential prompt for the standard user, which is what makes a standard daily account practical. |

## Verify on the installed PC

These DEFAULT and UNKNOWN classes rest on Windows defaults. One look in PowerShell (as
administrator) confirms them:

These DEFAULT/UNKNOWN claims rest on Windows defaults. One elevated look confirms them:

- `auditpol /get /subcategory:Logoff`: Success (V-253315).
- `Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" | ft Name,Disabled,PasswordExpires`: is the never-expires flag
  set on LocalAdmin/LocalUser by Setup? (V-253273; UNKNOWN). `net user Guest` is disabled (V-253433).
- Bluetooth "Alert me when a new Bluetooth device wants to connect" (More Bluetooth settings) (V-253293; UNKNOWN).
- `secedit /export /cfg x.inf /areas USER_RIGHTS`: `SeCreateSymbolicLinkPrivilege` = Administrators only, with no
  `NT VIRTUAL MACHINE` from VirtualMachinePlatform (V-253489). `SeSystemtimePrivilege` = Administrators, LOCAL SERVICE (V-253484).
- `reg query HKLM\SYSTEM\CurrentControlSet\Control\Lsa /v NoLMHash` = 1, `/v everyoneincludesanonymous` = 0;
  Winlogon `CachedLogonsCount` = 10; Netlogon `MaximumPasswordAge` = 30 (V-253461, V-253455, V-253447, V-253442).
- `netsh interface portproxy show all` empty (V-257592); no ReFS/exFAT fixed volumes with a letter, e.g. a Dev Drive (V-253265).
- `Get-AppxPackage -AllUsers *Copilot*` and `Get-NetAdapter -IncludeHidden 'Microsoft Wi-Fi Direct*'` (confirm V-268317 / V-288475).
- The age of the oldest event in the Security log after a week of normal use: does 1 GB hold a
  week (V-253338)?

## Files

- [STIG-REVIEW-rules.csv](STIG-REVIEW-rules.csv): all 257 rules (id, STIG id, rule id, severity,
  title, class, evidence, recommendation). It is the review's working data: its `class` and
  `recommendation` columns are those from before the adopted items went into the kit (the 33
  adopted rules are still GAP there), and its evidence text names files as they were then.

## Appendix: every rule and its class

| Rule | STIG ID | Sev | Class |
|---|---|---|---|
| V-253254 | WN11-00-000005 | II | N/A-STANDALONE |
| V-253255 | WN11-00-000010 | II | KIT |
| V-253256 | WN11-00-000015 | II | KIT |
| V-253257 | WN11-00-000020 | II | KIT |
| V-253259 | WN11-00-000030 | I | MANUAL/PROCEDURAL |
| V-253260 | WN11-00-000031 | I | OVERRIDE-DEVIATES |
| V-253261 | WN11-00-000032 | II | KIT |
| V-253262 | WN11-00-000035 | II | OVERRIDE-DEVIATES |
| V-253263 | WN11-00-000040 | I | KIT |
| V-253264 | WN11-00-000045 | I | BASELINE |
| V-253265 | WN11-00-000050 | I | DEFAULT |
| V-253266 | WN11-00-000055 | II | DEFAULT |
| V-253267 | WN11-00-000060 | II | DEFAULT |
| V-253269 | WN11-00-000070 | I | KIT |
| V-253270 | WN11-00-000075 | II | DEFAULT |
| V-253271 | WN11-00-000080 | II | KIT |
| V-253272 | WN11-00-000085 | III | N/A-STANDALONE |
| V-253273 | WN11-00-000090 | II | UNKNOWN |
| V-253274 | WN11-00-000095 | II | DEFAULT |
| V-253275 | WN11-00-000100 | I | DEFAULT |
| V-253276 | WN11-00-000105 | II | DEFAULT |
| V-253277 | WN11-00-000110 | II | DEFAULT |
| V-253278 | WN11-00-000115 | II | DEFAULT |
| V-253279 | WN11-00-000120 | II | DEFAULT |
| V-253280 | WN11-00-000130 | II | MANUAL/PROCEDURAL |
| V-253281 | WN11-00-000135 | II | BASELINE |
| V-253282 | WN11-00-000140 | II | N/A-STANDALONE |
| V-253284 | WN11-00-000150 | I | BASELINE |
| V-253285 | WN11-00-000155 | II | DEFAULT |
| V-253286 | WN11-00-000160 | II | BASELINE |
| V-253287 | WN11-00-000165 | II | BASELINE |
| V-253288 | WN11-00-000170 | II | BASELINE |
| V-253289 | WN11-00-000175 | II | KIT |
| V-253290 | WN11-00-000190 | II | DEFAULT |
| V-253291 | WN11-00-000210 | II | GAP |
| V-253293 | WN11-00-000230 | II | UNKNOWN |
| V-253294 | WN11-00-000240 | I | KIT |
| V-253296 | WN11-00-000260 | III | N/A-STANDALONE |
| V-253297 | WN11-AC-000005 | II | KIT |
| V-253298 | WN11-AC-000010 | II | GAP |
| V-253299 | WN11-AC-000015 | II | KIT |
| V-253300 | WN11-AC-000020 | II | BASELINE |
| V-253301 | WN11-AC-000025 | II | OVERRIDE-DEVIATES |
| V-253302 | WN11-AC-000030 | II | KIT |
| V-253303 | WN11-AC-000035 | II | OVERRIDE-DEVIATES |
| V-253304 | WN11-AC-000040 | II | BASELINE |
| V-253305 | WN11-AC-000045 | I | BASELINE |
| V-253306 | WN11-AU-000005 | II | BASELINE |
| V-253307 | WN11-AU-000010 | II | BASELINE |
| V-253308 | WN11-AU-000030 | II | BASELINE |
| V-253309 | WN11-AU-000035 | II | BASELINE |
| V-253310 | WN11-AU-000040 | II | BASELINE |
| V-253311 | WN11-AU-000045 | II | BASELINE |
| V-253312 | WN11-AU-000050 | II | BASELINE |
| V-253313 | WN11-AU-000054 | II | BASELINE |
| V-253314 | WN11-AU-000060 | II | BASELINE |
| V-253315 | WN11-AU-000065 | II | DEFAULT |
| V-253316 | WN11-AU-000070 | II | BASELINE |
| V-253317 | WN11-AU-000075 | II | BASELINE |
| V-253318 | WN11-AU-000080 | II | BASELINE |
| V-253319 | WN11-AU-000081 | II | BASELINE |
| V-253320 | WN11-AU-000082 | II | BASELINE |
| V-253321 | WN11-AU-000083 | II | BASELINE |
| V-253322 | WN11-AU-000084 | II | BASELINE |
| V-253323 | WN11-AU-000085 | II | BASELINE |
| V-253324 | WN11-AU-000090 | II | BASELINE |
| V-253325 | WN11-AU-000100 | II | BASELINE |
| V-253326 | WN11-AU-000105 | II | BASELINE |
| V-253327 | WN11-AU-000107 | II | KIT |
| V-253328 | WN11-AU-000110 | II | KIT |
| V-253329 | WN11-AU-000115 | II | BASELINE |
| V-253330 | WN11-AU-000120 | II | KIT |
| V-253331 | WN11-AU-000130 | II | BASELINE |
| V-253332 | WN11-AU-000135 | II | BASELINE |
| V-253333 | WN11-AU-000140 | II | BASELINE |
| V-253334 | WN11-AU-000150 | II | BASELINE |
| V-253335 | WN11-AU-000155 | II | BASELINE |
| V-253336 | WN11-AU-000160 | II | BASELINE |
| V-253337 | WN11-AU-000500 | II | BASELINE |
| V-253338 | WN11-AU-000505 | II | KIT |
| V-253339 | WN11-AU-000510 | II | BASELINE |
| V-253340 | WN11-AU-000515 | II | DEFAULT |
| V-253341 | WN11-AU-000520 | II | DEFAULT |
| V-253342 | WN11-AU-000525 | II | DEFAULT |
| V-253344 | WN11-AU-000555 | II | BASELINE |
| V-253345 | WN11-AU-000560 | II | BASELINE |
| V-253346 | WN11-AU-000565 | II | BASELINE |
| V-253347 | WN11-AU-000570 | II | BASELINE |
| V-253348 | WN11-AU-000575 | II | BASELINE |
| V-253349 | WN11-AU-000580 | II | BASELINE |
| V-253350 | WN11-CC-000005 | II | BASELINE |
| V-253351 | WN11-CC-000007 | II | MANUAL/PROCEDURAL |
| V-253352 | WN11-CC-000010 | II | BASELINE |
| V-253353 | WN11-CC-000020 | II | BASELINE |
| V-253354 | WN11-CC-000025 | II | BASELINE |
| V-253355 | WN11-CC-000030 | III | BASELINE |
| V-253356 | WN11-CC-000035 | III | BASELINE |
| V-253357 | WN11-CC-000037 | II | BASELINE |
| V-253358 | WN11-CC-000038 | II | KIT |
| V-253359 | WN11-CC-000039 | II | KIT |
| V-253360 | WN11-CC-000040 | II | BASELINE |
| V-253361 | WN11-CC-000044 | II | BASELINE |
| V-253362 | WN11-CC-000050 | II | BASELINE |
| V-253363 | WN11-CC-000052 | II | GAP |
| V-253364 | WN11-CC-000055 | II | DEFAULT |
| V-253365 | WN11-CC-000060 | II | BASELINE |
| V-253367 | WN11-CC-000066 | II | BASELINE |
| V-253368 | WN11-CC-000068 | II | BASELINE |
| V-253369 | WN11-CC-000070 | II | BASELINE |
| V-253370 | WN11-CC-000075 | I | GAP |
| V-253371 | WN11-CC-000080 | II | BASELINE |
| V-253372 | WN11-CC-000085 | II | BASELINE |
| V-253373 | WN11-CC-000090 | II | KIT |
| V-253374 | WN11-CC-000100 | II | BASELINE |
| V-253375 | WN11-CC-000105 | II | BASELINE |
| V-253376 | WN11-CC-000110 | II | KIT |
| V-253377 | WN11-CC-000115 | II | DEFAULT |
| V-253378 | WN11-CC-000120 | II | KIT |
| V-253379 | WN11-CC-000130 | II | BASELINE |
| V-253380 | WN11-CC-000145 | II | BASELINE |
| V-253381 | WN11-CC-000150 | II | BASELINE |
| V-253382 | WN11-CC-000155 | I | BASELINE |
| V-253383 | WN11-CC-000165 | II | BASELINE |
| V-253384 | WN11-CC-000170 | III | BASELINE |
| V-253385 | WN11-CC-000175 | III | KIT |
| V-253386 | WN11-CC-000180 | I | BASELINE |
| V-253387 | WN11-CC-000185 | I | BASELINE |
| V-253388 | WN11-CC-000190 | I | BASELINE |
| V-253389 | WN11-CC-000195 | II | BASELINE |
| V-253391 | WN11-CC-000200 | II | OVERRIDE-DEVIATES |
| V-253392 | WN11-CC-000204 | II | KIT |
| V-253393 | WN11-CC-000205 | II | KIT |
| V-253394 | WN11-CC-000206 | III | KIT |
| V-253395 | WN11-CC-000210 | II | BASELINE |
| V-253396 | WN11-CC-000215 | II | DEFAULT |
| V-253397 | WN11-CC-000220 | III | DEFAULT |
| V-253398 | WN11-CC-000225 | II | DEFAULT |
| V-253399 | WN11-CC-000252 | II | BASELINE |
| V-253400 | WN11-CC-000255 | II | KIT |
| V-253401 | WN11-CC-000260 | II | KIT |
| V-253402 | WN11-CC-000270 | II | BASELINE |
| V-253403 | WN11-CC-000275 | II | BASELINE |
| V-253404 | WN11-CC-000280 | II | BASELINE |
| V-253405 | WN11-CC-000285 | II | BASELINE |
| V-253406 | WN11-CC-000290 | II | BASELINE |
| V-253407 | WN11-CC-000295 | II | BASELINE |
| V-253408 | WN11-CC-000300 | II | DEFAULT |
| V-253409 | WN11-CC-000305 | II | BASELINE |
| V-253410 | WN11-CC-000310 | II | BASELINE |
| V-253411 | WN11-CC-000315 | I | BASELINE |
| V-253412 | WN11-CC-000320 | II | DEFAULT |
| V-253413 | WN11-CC-000325 | II | BASELINE |
| V-253414 | WN11-CC-000326 | II | BASELINE |
| V-253415 | WN11-CC-000327 | II | GAP |
| V-253416 | WN11-CC-000330 | I | BASELINE |
| V-253417 | WN11-CC-000335 | II | BASELINE |
| V-253418 | WN11-CC-000345 | I | BASELINE |
| V-253419 | WN11-CC-000350 | II | BASELINE |
| V-253420 | WN11-CC-000355 | II | BASELINE |
| V-253421 | WN11-CC-000360 | II | BASELINE |
| V-253422 | WN11-CC-000365 | II | BASELINE |
| V-253423 | WN11-CC-000370 | II | BASELINE |
| V-253424 | WN11-CC-000385 | II | BASELINE |
| V-253425 | WN11-CC-000390 | III | BASELINE |
| V-253426 | WN11-EP-000310 | II | BASELINE |
| V-253427 | WN11-PK-000005 | II | N/A-STANDALONE |
| V-253428 | WN11-PK-000010 | II | N/A-STANDALONE |
| V-253429 | WN11-PK-000015 | II | N/A-STANDALONE |
| V-253430 | WN11-PK-000020 | II | N/A-STANDALONE |
| V-253431 | WN11-RG-000005 | II | DEFAULT |
| V-253433 | WN11-SO-000010 | II | DEFAULT |
| V-253434 | WN11-SO-000015 | II | BASELINE |
| V-253435 | WN11-SO-000020 | II | KIT |
| V-253436 | WN11-SO-000025 | II | KIT |
| V-253437 | WN11-SO-000030 | II | BASELINE |
| V-253438 | WN11-SO-000035 | II | BASELINE |
| V-253439 | WN11-SO-000040 | II | BASELINE |
| V-253440 | WN11-SO-000045 | II | BASELINE |
| V-253441 | WN11-SO-000050 | III | BASELINE |
| V-253442 | WN11-SO-000055 | III | DEFAULT |
| V-253443 | WN11-SO-000060 | II | BASELINE |
| V-253444 | WN11-SO-000070 | II | BASELINE |
| V-253445 | WN11-SO-000075 | II | N/A-STANDALONE |
| V-253447 | WN11-SO-000085 | III | DEFAULT |
| V-253448 | WN11-SO-000095 | II | BASELINE |
| V-253449 | WN11-SO-000100 | II | BASELINE |
| V-253450 | WN11-SO-000110 | II | BASELINE |
| V-253451 | WN11-SO-000120 | II | BASELINE |
| V-253452 | WN11-SO-000140 | I | BASELINE |
| V-253453 | WN11-SO-000145 | I | BASELINE |
| V-253454 | WN11-SO-000150 | I | BASELINE |
| V-253455 | WN11-SO-000160 | II | DEFAULT |
| V-253456 | WN11-SO-000165 | I | BASELINE |
| V-253457 | WN11-SO-000167 | II | BASELINE |
| V-253458 | WN11-SO-000180 | II | BASELINE |
| V-253459 | WN11-SO-000185 | II | KIT |
| V-253460 | WN11-SO-000190 | II | KIT |
| V-253461 | WN11-SO-000195 | I | DEFAULT |
| V-253462 | WN11-SO-000205 | I | BASELINE |
| V-253463 | WN11-SO-000210 | II | BASELINE |
| V-253464 | WN11-SO-000215 | II | BASELINE |
| V-253465 | WN11-SO-000220 | II | BASELINE |
| V-253466 | WN11-SO-000230 | II | GAP |
| V-253467 | WN11-SO-000240 | III | BASELINE |
| V-253468 | WN11-SO-000245 | II | BASELINE |
| V-253469 | WN11-SO-000250 | II | BASELINE |
| V-253470 | WN11-SO-000251 | II | N/A-STANDALONE |
| V-253471 | WN11-SO-000255 | II | OVERRIDE-DEVIATES |
| V-253472 | WN11-SO-000260 | II | BASELINE |
| V-253473 | WN11-SO-000265 | II | BASELINE |
| V-253474 | WN11-SO-000270 | II | BASELINE |
| V-253475 | WN11-SO-000275 | II | BASELINE |
| V-253476 | WN11-SO-000280 | II | OVERRIDE-DEVIATES |
| V-253477 | WN11-UC-000015 | III | BASELINE |
| V-253478 | WN11-UC-000020 | II | DEFAULT |
| V-253479 | WN11-UR-000005 | II | BASELINE |
| V-253480 | WN11-UR-000010 | II | BASELINE |
| V-253481 | WN11-UR-000015 | I | BASELINE |
| V-253482 | WN11-UR-000025 | II | BASELINE |
| V-253483 | WN11-UR-000030 | II | BASELINE |
| V-253484 | WN11-UR-000035 | II | DEFAULT |
| V-253485 | WN11-UR-000040 | II | BASELINE |
| V-253486 | WN11-UR-000045 | I | BASELINE |
| V-253487 | WN11-UR-000050 | II | BASELINE |
| V-253488 | WN11-UR-000055 | II | BASELINE |
| V-253489 | WN11-UR-000060 | II | DEFAULT |
| V-253490 | WN11-UR-000065 | I | BASELINE |
| V-253491 | WN11-UR-000070 | II | KIT |
| V-253492 | WN11-UR-000075 | II | N/A-STANDALONE |
| V-253493 | WN11-UR-000080 | II | N/A-STANDALONE |
| V-253494 | WN11-UR-000085 | II | KIT |
| V-253495 | WN11-UR-000090 | II | KIT |
| V-253496 | WN11-UR-000095 | II | BASELINE |
| V-253497 | WN11-UR-000100 | II | BASELINE |
| V-253498 | WN11-UR-000110 | II | BASELINE |
| V-253499 | WN11-UR-000120 | II | BASELINE |
| V-253500 | WN11-UR-000125 | II | BASELINE |
| V-253501 | WN11-UR-000130 | II | BASELINE |
| V-253502 | WN11-UR-000140 | II | BASELINE |
| V-253503 | WN11-UR-000145 | II | BASELINE |
| V-253504 | WN11-UR-000150 | II | BASELINE |
| V-253505 | WN11-UR-000160 | II | BASELINE |
| V-253506 | WN11-UR-000165 | II | BASELINE |
| V-256893 | WN11-CC-000391 | II | DEFAULT |
| V-257592 | WN11-00-000395 | II | DEFAULT |
| V-257770 | WN11-AU-000585 | II | KIT |
| V-268317 | WN11-00-000125 | II | GAP |
| V-268318 | WN11-CC-000063 | II | N/A-STANDALONE |
| V-278928 | WN11-AU-000583 | II | KIT |
| V-278930 | WN11-AU-000589 | II | KIT |
| V-278931 | WN11-AU-000586 | II | KIT |
| V-278932 | WN11-AU-000587 | II | BASELINE |
| V-278933 | WN11-AU-000588 | II | KIT |
| V-279688 | WN11-00-000126 | II | GAP |
| V-288475 | WN11-00-000400 | II | KIT |
| V-288812 | WN11-00-000065 | III | MANUAL/PROCEDURAL |
| V-289260 | WN11-CC-000366 | II | KIT |
