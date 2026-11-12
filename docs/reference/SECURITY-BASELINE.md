# Security baseline: what is applied and what is changed

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

The image applies two of Microsoft's [security baselines](../GLOSSARY.md#security-baseline) in
full: the **Windows 11 v26H2 Security Baseline** and the **Microsoft Edge v151 Security
Baseline**. On top of them come a short list of documented overrides, selected settings from the
DISA Windows 11 STIG, and a few additions of the kit's own.

All of it is applied during first-boot setup into the PC's local Group Policy, so Windows keeps
the settings in place by itself. What you will notice in daily use is one table:
[What is different on this PC](../AFTER-INSTALL.md#what-is-different-on-this-pc). What the kit is
designed to protect against is in
[SECURITY.md](../../SECURITY.md#what-the-kit-is-designed-to-do-and-what-it-doesnt).

## How the baselines are applied

### Where the baseline settings come from

The kit contains nothing of Microsoft's. Each build gets the baselines from Microsoft's own
download:

1. `config\baselines\baselines.json` lists the baselines to apply, in order. Each has a
   `source.json` with Microsoft's file name, its download address, the download page, its SHA-256
   hash and the names of the policy sets (GPOs) to take from it.
2. `Run-Build.cmd` offers to download each zip from Microsoft into `C:\W11Kit\work\baselines`
   (`scripts\Get-Baselines.py`). A file whose hash differs from the pin is deleted, and the
   preflight refuses it.
3. Every build then runs `scripts\Import-Baseline.py`, right after the preflight. It turns each
   zip into plain data in `C:\W11Kit\work\baselines\<id>`: every registry policy record, the
   security template, the audit policy, and an index with each file's hash. The build never
   trusts data that is already in that folder: it imports again from the checked zip. This is why
   a build needs Python.
4. The build puts that data into the image, in `C:\ProgramData\W11Kit\Baselines`, and its
   read-back checks the staged files against the index.

| Baseline | Microsoft's file | SHA-256 |
|---|---|---|
| `windows-11-v26h2` | `Windows 11 v26H2 Security Baseline v2.zip` | `369f8dad…5e45d18` |
| `edge-v151` | `Microsoft Edge v151 Security Baseline.zip` | `c8d1be70…a6ab` |

Both are part of Microsoft's Security Compliance Toolkit. Microsoft sometimes replaces a file
under the same address. The download then says so (`Microsoft does not serve this file any more`,
or a SHA-256 that is `not the pinned one`), names Microsoft's download page, and shows how to use
a copy of the pinned zip you already have: `py scripts\Get-Baselines.py --zip "<path to the zip>"`.
The pin moves with the next kit update
([for maintainers](../dev/MAINTAINING.md#new-microsoft-security-baseline)). A real build carries
the two zips in its [build inputs](BUILD-OPTIONS.md#build-inputs-in-the-iso), so the installed PC
can rebuild without the download.

Microsoft's own installer for these baselines uses a tool called `LGPO.exe`. The kit doesn't: it
applies the same values with tools that are part of Windows. The baselines' ADMX files, which
only give a few settings a name in the policy editor, are not used.

### What first-boot setup does

`C:\ProgramData\W11Kit\Apply-Policy.ps1` does all of it, in this order:

1. **Registry policies, merged once.** The Windows baseline, then the Edge baseline, then the
   overrides (`baseline-overrides.txt`), then the kit's own policies. A later one wins. The result
   is written as the local Group Policy's `Registry.pol` files. Because there is only the merged
   result, the PC never runs with the baseline alone.
2. **The local policy's `gpt.ini`**: its version is raised and the policy extensions the baselines
   need are listed, so Windows applies the files.
3. **The security template.** The baseline's template plus `baseline-overrides.inf` (password and
   lockout policy, user rights, services, security options), applied with `secedit`.
4. **The audit policy, as one file.** The baseline's rows plus the kit's additions
   ([below](#advanced-audit-policy)), applied with `auditpol`.
5. **`gpupdate /force`, then a read-back** of every override.
6. The rest of first-boot setup ([CONFIGURATION](CONFIGURATION.md#install-and-first-boot)), and a
   restart after 2 minutes.

**If an override reads back with the baseline's value,** first-boot setup cancels the restart and
says so in red. A restart with the plain baseline would lock memory integrity and LSA protection
into the firmware and make Windows refuse the daily account's administrator prompts. What to do:
[Setup did not finish](../TROUBLESHOOTING.md#setup-did-not-finish).

The outcome is in `C:\ProgramData\W11Kit\postinstall-status.json` and the log in
`C:\ProgramData\W11Kit\Logs`. The validator checks it again on the running PC:

- *Baseline: every policy value in effect* compares every computer policy value of both baselines
  with the live registry, except those an override or kit policy replaces.
- *Overrides and kit policies: every value in effect* does the same for the overrides and the
  kit's own policies.
- *Services the kit disables* and *Security options the kit sets* cover the security template.

### Why the domain-joined set on a standalone PC

Microsoft's installer has two modes. The one for PCs outside a domain applies the same settings
and then relaxes two things for remote management: it lets local accounts administer the PC over
the network, and it removes the rule that denies local accounts network and Remote Desktop
sign-in. A home PC doesn't need remote administration, so the kit keeps the stricter set.

## Overrides

An override is a setting where the image deliberately differs from a baseline. A build with the
kit's default settings has **17**: 14 of the 15 below and three for Edge
([next section](#microsoft-edge-security-baseline)). Row 5, the Xbox services, is the 18th: it
applies only with `options.gamingTweaks`.

| # | Setting | Baseline | This image |
|---|---|---|---|
| 1 | UAC prompt for standard users | Automatically deny | **Ask for an administrator's password** |
| 2 | Administrator protection (`TypeOfAdminApprovalMode`) | 2 = on | **1** = classic Admin Approval Mode |
| 3 | List administrator accounts at the UAC prompt (`EnumerateAdministrators`) | 0 = type the name | **1** = the admin account is listed |
| 4 | Minimum password length | 14 | **11** |
| 5 | Xbox services (`XboxGipSvc`, `XblAuthManager`, `XblGameSave`, `XboxNetApiSvc`) | Disabled | **Manual**, with `options.gamingTweaks` |
| 6 | Scheduled task `XblGameSaveTask` | Disabled by Microsoft's installer script | **Left enabled** |
| 7 | Deny writing to USB drives not protected by BitLocker | Enabled | **Disabled** |
| 8 | Memory integrity (HVCI) | On, locked in the firmware | **On, not locked** |
| 9 | Credential Guard | On, locked in the firmware | **On, not locked** |
| 10 | LSA protection (`RunAsPPL`) | On, locked in the firmware | **On, not locked** |
| 11 | Defender sample submission | Send all samples | **Send safe samples** |
| 12 | Account lockout duration and counter reset | 10 minutes | **15 minutes** (still 10 attempts) |
| 13 | Deny network and Remote Desktop sign-in | Local accounts | Local accounts **and Guests**; Guests also can't sign in locally |
| 14 | Security event log size | 192 MB | **1 GB** |
| 15 | Audit of Process Creation and Sensitive Privilege Use | Success | **Success and Failure** |

Why, row by row:

1. **UAC prompt.** You work as a standard user. "Automatically deny" would force a full switch of
   user for every install.
2. **Administrator protection.** With it on, administrator prompts run as a hidden second
   account. On a real install of an earlier version of this kit, that reset the daily account's
   settings at every sign-in. It also stops winget from running as administrator, and some
   installers refuse to run. The prompt still needs the admin password, on the secure desktop.
3. **Admin account listed.** There is one admin account and an account lockout. A mistyped
   account name counts as a failed sign-in and can lock that one admin account out. The password
   is still required.
4. **Password length.** The admin password is typed at every UAC prompt, so the kit trades three
   characters for usability. Complexity, the history of 24 passwords and the 10-attempt lockout
   stay as the baseline sets them.
5. **Xbox services.** The Xbox app, Store games, cloud saves and Xbox controller accessories need
   them. Without `options.gamingTweaks` the baseline's value (Disabled) stays: the build leaves
   the four service lines out of the security template it puts into the image, and the validator
   shows the services as INFO.
6. **`XblGameSaveTask`.** Microsoft's installer disables this task with a script step, not a
   policy. The kit doesn't run that script.
7. **USB drives.** Needed for USB installers, for saving the BitLocker recovery key to a USB
   drive and for ordinary file copies.
8. **Memory integrity.** The protection is the same. Without the firmware lock it can still be
   turned off to track down a driver or anti-cheat problem, without a special reset tool.
9. **Credential Guard.** Same reasoning. Credential Guard itself needs Windows Enterprise or
   Education, so on Pro the setting does nothing.
10. **LSA protection.** Same reasoning as memory integrity.
11. **Sample submission.** Files that may hold personal data or source code are asked about, not
    sent.
12. **Lockout duration.** From the DISA STIG (WN11-AC-000005, -000015). The STIG's limit of 3
    attempts is not adopted: with a single admin account it locks you out too easily.
13. **Guests.** From the DISA STIG (WN11-UR-000070, -000085, -000090).
14. **Security log.** From the DISA STIG (WN11-AU-000505): room for at least a week of events now
    that more is audited. It costs up to 1 GB of disk.
15. **Audit.** From the DISA STIG (WN11-AU-000585, -000110, -000588). Failures of Sensitive
    Privilege Use (event 4673) can be frequent with some games' anti-cheat software.

To change the password length, edit `MinimumPasswordLength` in `config\baseline-overrides.inf`.

### Baseline settings kept on purpose

Everything else is applied as Microsoft ships it, including these, although they touch gaming or
convenience:

- **Kernel-mode hardware stack protection** is enforced. If a game's anti-cheat software refuses
  to run with it, set `ConfigureKernelShadowStacksLaunch` to 0 under
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard`
  ([Changing a setting later](#changing-a-setting-later)).
- **Memory integrity needs the UEFI Memory Attributes Table.** Current firmware generally has it.
  Without it memory integrity doesn't start, and the validator's *Memory integrity (HVCI)* row
  FAILs.
- **Game DVR (Game Bar recording) is off.** Game Mode is not affected.
- **Windows `sudo` is off.**
- **Windows LAPS** points at a directory service. On a standalone PC it does nothing except log
  an occasional event.

What the baseline itself sets and you may meet:

- **Passwords:** complexity, history of 24, and a screen lock after 15 minutes without input.
- **SmartScreen for apps is set to Block:** there is no *Run anyway* for an unrecognised
  download. For a file you trust: right-click → Properties → **Unblock**.
- **PowerShell script block logging** is on, and AutoRun is off for all drives.
- **Defender:** 15 attack surface reduction rules, network protection, cloud protection at level
  High, and blocking of potentially unwanted apps.
- **Firewall:** on for all network types, with logging. On a *Public* network, rules that apps
  create themselves are ignored.
- **File sharing (SMB) client:** SMB 3.0 or newer, signing required, no guest access.
- **Name lookup:** LLMNR and NetBIOS name resolution are off.
- **External PCIe devices** that can't be isolated are blocked (Kernel DMA Protection).

### Firmware lock left by an earlier install

If an earlier Windows on the same PC applied Microsoft's baseline unchanged, it turned memory
integrity on **with** the firmware lock. After installing this image the setting reads
`Locked=0` (under
`HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity`)
and the validator's row passes.

That value shows the configuration. It can't show whether the earlier install's firmware variable
is still there. This matters only if you ever turn memory integrity off: if it stays on, use
Microsoft's documented procedure for opting out of VBS. The validator WARNs if `Locked=1` comes
back.

## Microsoft Edge security baseline

Applied in the same merge as the Windows baseline. Edge gets:

- one process per site, and sandboxed renderer and network processes;
- protection against code injection;
- enhanced security mode (balanced);
- SmartScreen, with blocking of potentially unwanted apps and typo-squatting protection;
- no basic authentication over plain HTTP;
- a locked-down Internet Explorer mode.

Three overrides keep it usable as an everyday browser:

| Setting | Edge baseline | This image | Why |
|---|---|---|---|
| Extension blocklist | `*`: every extension is blocked | Removed | Password managers, ad blockers and developer extensions from the Edge Add-ons store work |
| Native messaging for per-user programs | Blocked | Allowed | An extension can talk to a desktop program installed for one user, such as a password manager |
| Continue past a certificate error (`SSLErrorOverrideAllowed`) | Not allowed | Allowed | LAN devices (routers, NAS boxes, printers) often use self-signed certificates. Edge still shows the full-page warning every time |

Kept, with a workaround: Edge won't let you keep an "uncommon download" that SmartScreen flags.
For a tool you trust, use `winget install`, or download it with `curl`, then **Unblock** it.

The kit's other Edge policies (privacy, prompts, AI features) are not security settings:
[CONFIGURATION](CONFIGURATION.md#microsoft-edge).

## DISA STIG additions

The DISA Windows 11 STIG (Version 2, Release 11) is the US Department of Defense's configuration
standard for Windows 11. The image was compared with it rule by rule
([the review](../dev/reviews/STIG-REVIEW.md)), and **selected settings** were adopted: those that
cost little and conflict with nothing else here.

**The image is not STIG-compliant** and doesn't try to be. Rules that conflict with a project
decision are not applied: a BitLocker start-up PIN, lockout after 3 attempts, 14-character
passwords, password expiry and application allowlisting, among others.

Four adopted items change a baseline value and are [overrides](#overrides) 12 to 15. The rest add
to the baseline:

| STIG ID | Setting | Effect here |
|---|---|---|
| WN11-CC-000090 | Registry policy is re-applied at every refresh (`NoGPOListChanges=0`) | A hand edit of a policy value is reverted within about 90 minutes |
| WN11-CC-000110 | No printing over HTTP (`DisableHTTPPrinting=1`) | Network and USB printers are not affected |
| WN11-CC-000120 | No network picker on the sign-in screen (`DontDisplayNetworkSelectionUI=1`) | Choose a Wi-Fi network after signing in |
| WN11-CC-000175 | Inventory Collector off (`DisableInventory=1`) | None |
| WN11-CC-000206 | Delivery Optimization: HTTP only (`DODownloadMode=0`) | Updates are never downloaded from, or uploaded to, other PCs |
| WN11-CC-000255 | Windows Hello keys only in the TPM (`RequireSecurityDevice=1`) | After a TPM clear, set the Hello PIN up again |
| WN11-CC-000260 | Windows Hello PIN of 6 or more characters (`MinimumPINLength=6`) | Windows' own minimum is 4 |
| WN11-00-000032 | A BitLocker start-up PIN, if you add one, has 6 or more digits (`FVE\MinimumPIN=6`) | None while BitLocker is TPM-only |
| WN11-CC-000366 | Apps can't be started by voice (`LetAppsActivateWithVoice=2`) | No voice wake words for apps |
| WN11-SO-000190 | Kerberos encryption: AES only, no DES or RC4 (`SupportedEncryptionTypes=2147483640`) | None on a standalone PC. A very old NAS or domain that needs RC4 would fail |
| WN11-CC-000038 | WDigest keeps no plain-text credentials (`UseLogonCredential=0`) | None: it is Windows' behaviour already, now written down |
| WN11-SO-000185 | No PKU2U sign-in with online identities (`AllowOnlineID=0`) | None |
| WN11-CC-000039 | *Run as different user* removed from the right-click menu (`SuppressionPolicy=4096`) | Shift+right-click no longer offers it |
| WN11-00-000175 | Secondary Logon service (`seclogon`) disabled; **Manual** with `options.gamingTweaks` | `runas` and `Start-Process -Credential` fail. UAC prompts are a different service and work. Some game launchers refuse to install without it, so the gaming option leaves it at Manual, as Windows ships it |
| WN11-AC-000030 | Minimum password age: 1 day | You can't change your own password twice within 24 hours. An administrator's reset still works |
| WN11-SO-000020, -000025 | The built-in Administrator and Guest accounts are renamed | See [below](#renamed-built-in-accounts) |
| WN11-AU-000107, -000110, -000588, -000120, -000583, -000585, -000589, -000586, -000065 | Seven more audit subcategories | See [Advanced audit policy](#advanced-audit-policy) |
| WN11-00-000030 | BitLocker on every fixed disk | A validator row only: WARN until `C:` is encrypted, and a row for data drives when there are any |
| WN11-00-000240 | Administrator accounts can't run web browsers | See [below](#browsers-blocked-for-administrators-applocker) |
| WN11-00-000400 | Wi-Fi Direct virtual adapters disabled | No Mobile hotspot, no wireless casting to a TV, no Wi-Fi Direct printers. Ordinary Wi-Fi works |

The registry values are set by `scripts\Set-KitRegistry.ps1`; the service and the password age
are in `config\baseline-overrides.inf`, and the build adds the two account names to the copy of
that file it puts into the image. The validator has one *STIG* row per group.

**If you need Secondary Logon** without the gaming option (a tool's setup that uses `runas`), in a Command Prompt (as
administrator): `sc config seclogon start= demand` and `net start seclogon`; afterwards
`sc config seclogon start= disabled`.

**If you need Wi-Fi Direct,** in PowerShell (as administrator):
`Get-NetAdapter -IncludeHidden 'Microsoft Wi-Fi Direct*' | Enable-NetAdapter`. The validator then
WARNs. A Wi-Fi driver update can also bring the adapter back.

### Renamed built-in accounts

Windows' built-in Administrator and Guest accounts stay disabled and get new names. Each build
draws a new pair of names (eight letters each), prints them, and records them in the manifest and
in `C:\ProgramData\W11Kit\build-options.json`; you can choose them in
[your settings](CONFIGURATION.md#your-settings) (`accounts.builtinAdministratorName`,
`accounts.builtinGuestName`). How to see them on the installed PC:
[Accounts](CONFIGURATION.md#accounts).

The names are not secret: any user of the PC can list them. The rename answers the STIG rule and
defeats scripts that assume the name `Administrator`. Recovery instructions that say "Administrator"
mean the renamed account, which is still disabled. The admin account you use is `LocalAdmin`.

### Advanced audit policy

The audit policy says which events go to the Security log. The kit adds seven rows
(`config\baseline-overrides-audit.csv`) to the baseline's 23:

| Subcategory | Setting | In the baseline |
|---|---|---|
| Process Creation | Success and Failure | Success |
| Sensitive Privilege Use | Success and Failure | Success |
| Authorization Policy Change | Success | Not set |
| IPsec Driver | Failure | Not set |
| Handle Manipulation | Failure | Not set |
| Registry | Success and Failure | Not set |
| Logoff | Success | Not set (it is Windows' default) |

The result is 28 subcategories: the baseline's 23, two of them raised, and 5 new ones. Registry
and Handle events are written only for objects that have auditing switched on, which few have.

Local Group Policy keeps one audit file and re-applies it at every refresh. If the kit wrote only
its seven rows there, the baseline's rows would be gone after the next refresh. So
`Merge-AuditPolicy.ps1` always builds the full set: the baseline's rows, then what the PC already
has, then the kit's rows, a later one winning. If it finds no baseline rows, nothing is applied
and first-boot setup records a failure.

The validator reads the live policy and checks both the additions and every baseline row.

### Browsers blocked for administrators (AppLocker)

The STIG says administrator accounts must not be used to browse the web. On this PC the admin
account exists for UAC prompts, so the image makes that rule real with
[AppLocker](../GLOSSARY.md#applocker), a Windows feature that decides which programs an account
may start.

The policy (`C:\ProgramData\W11Kit\New-AdminBrowserPolicy.ps1`):

- **Allows everything for everyone.** It is a deny-list, not an allowlist: nothing else on the PC
  changes. A second rule allows all signed Store apps, because without it AppLocker would block
  every one of them.
- **Denies `msedge.exe`, `brave.exe`, `chrome.exe` and `firefox.exe`** to the Administrators
  group and to the admin account itself. That covers a browser started from a UAC prompt and one
  started in the admin account's own session.
- **Matches each browser twice:** by its publisher's signature (a renamed copy is still caught)
  and by file name on any path.
- **Leaves WebView2 alone** (`msedgewebview2.exe`). Settings, installers and apps that show web
  content work.
- **Needs the Application Identity service** (`AppIDSvc`). First-boot setup sets it to start
  automatically.

There are no DLL, script or installer rules, so PowerShell works as before. Services that run as
SYSTEM are not affected.

**What it is, and isn't.** This is a procedural aid, not a security boundary:

- An administrator can remove the policy. It stops habit and accident, not intent.
- A browser that isn't on the list isn't blocked.
- E-mail programs aren't covered.
- A program running as administrator that opens a web link shows an AppLocker error instead of a
  browser. Copy the link and open it in the daily account.

The validator FAILs if the policy is missing or doesn't deny `msedge.exe` to the admin account,
and WARNs if `AppIDSvc` isn't running.

**Undo:** `secpol.msc` → Application Control Policies → AppLocker, and remove the rules.

Two other ways were considered and rejected. A per-user `DisallowRun` list stops only programs
started through File Explorer. Browser policies for the Administrators group cover only some
browsers, and those browsers may drop their administrator rights before the policy applies.

## Additions beyond the baseline

| Addition | Why |
|---|---|
| Defender ASR rule *Block rebooting machine in Safe Mode* (`33ddedf1-c6e0-47cb-833e-de6133960387`), Block | Ransomware restarts into Safe Mode to get around Defender. Nothing here needs it |
| Defender ASR rule *Block use of copied or impersonated system tools* (`c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb`), Block | Stops renamed copies of Windows' own tools, a common attack technique |
| Windows release pinned to 26H2 (`TargetReleaseVersion`) | A new Windows release arrives only by rebuilding. Monthly updates still install |
| The image's BitLocker start-up policy pinned | TPM required, TPM-only unlock allowed, a PIN allowed but not required ([CONFIGURATION](CONFIGURATION.md#bitlocker)) |
| BitLocker cipher pinned (`FVE\EncryptionMethodWithXtsOs`/`Fdv` = 7, `Rdv` = 4) | XTS-AES 256 for internal drives, AES-CBC 256 for removable drives, whichever way BitLocker is turned on. Without it, Windows' own settings use XTS-AES 128 |
| File name extensions shown, for new accounts | `invoice.pdf.exe` is visible as what it is |
| Selected DISA STIG settings | [Above](#disa-stig-additions) |
| Network exposure, sign-in and monitoring | [Below](#network-exposure-sign-in-and-monitoring) |
| Sysmon | [Below](#sysmon) |
| Secure Boot 2023 certificates | [Below](#secure-boot-2023-certificates) |
| A BIOS password, and the internal disk first in the boot order | You set these yourself: [A BIOS password](../AFTER-INSTALL.md#a-bios-password) |

**Attack surface reduction rules, counted.** The baseline configures 15 rules: 14 in Block mode
and one in Audit mode (*Block process creations originating from PSExec and WMI commands*, which
only writes events). With the kit's two, **17 rules** are configured, **16 of them blocking**.

**The copied-tools rule and the build.** That rule also blocks DISM working inside a mounted
image. While a build runs, it excludes its own four work folders (`mount`, `mount-re`,
`mount-boot`, `scratch`) from the ASR rules and removes the exclusions at the end. Exclusions
left by an interrupted build are removed at the start of the next one, and by `Run-Prepare.cmd`.

### Network exposure, sign-in and monitoring

Each of these closes something a home PC rarely uses, or records something worth having on
record. None changes a baseline value. The short version:

| What | What it costs you |
|---|---|
| [No file sharing (SMB) to Internet addresses](#outbound-smb-to-the-internet-blocked) | Nothing on a home network |
| [NTLM sign-ins are logged](#ntlm-auditing) | A few log entries |
| [This PC shares no folders or printers](#file-sharing-server-off) | You can't share from this PC |
| [UPnP off](#upnp-off) | Network devices aren't listed by themselves; some games report a stricter NAT type |
| [WebDAV client off](#webdav-client-off) | No WebDAV folders as drive letters |
| [mDNS off](#mdns-off) | Add printers by IP address; no `.local` names |
| [Automatic proxy discovery off](#automatic-proxy-discovery-wpad-off) | Set a proxy by hand where a network needs one |
| [Print spooler takes no remote clients](#print-spooler-accepts-no-remote-clients) | This PC can't be a print server |
| [Remote Desktop and WinRM off by policy](#remote-desktop-and-winrm-refused) | No remote sessions into this PC |
| [winget's safety checks can't be switched off](#wingets-safety-checks-pinned) | No `--ignore-security-hash` |
| [No security questions](#no-security-questions-for-local-accounts) | A forgotten password is reset from the admin account |
| [Strict signature check](#strict-authenticode-signature-check) | A few installers show as unsigned |
| [PowerShell log 256 MB](#powershell-log-256-mb) | Up to 256 MB of disk |

Some words first. *[SMB](../GLOSSARY.md#smb)* is Windows file sharing (network port 445).
*[NTLM](../GLOSSARY.md#ntlm)* is Windows' older sign-in protocol: a server you connect to can
capture a value derived from your password and try to crack or relay it.
*[mDNS](../GLOSSARY.md#mdns)*, *LLMNR* and *WPAD* find names or a proxy by asking everyone on the
local network, where anyone can answer. *UPnP* lets programs ask the router to open ports.
*WinRM* is Windows' remote management service.

Settings marked *policy* are set by `scripts\Set-KitRegistry.ps1`. Those marked *template* are in
`config\baseline-overrides.inf`. To undo one for good, see
[Changing a setting later](#changing-a-setting-later).

#### Outbound SMB to the Internet blocked

- **Setting:** a firewall rule, `W11Kit-Block-SMB-Out-Internet`: outbound, TCP 445, Block, all
  network types, for every public IPv4 range and IPv6 `2000::/3`. It is a *policy* value under
  `HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules`, because the baseline makes
  the Public network type ignore ordinary local rules.
- **Why:** a link or document that points at `\\some-internet-host\share` makes Windows offer
  your sign-in to that host
  ([Microsoft: *Secure SMB traffic*](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-secure-traffic)).
- **Cost:** none on a home network. Private addresses (10.x, 172.16-31.x, 192.168.x, 169.254.x,
  100.64-127.x as VPN overlays use, IPv6 `fc00::/7` and `fe80::/10`) are not in the rule, so a
  NAS works as before. A file server on the Internet is unreachable. A LAN device addressed by a
  public IPv6 address is blocked too: use its IPv4 address.
- **Check:** `Get-NetFirewallRule -PolicyStore ActiveStore -Name W11Kit-Block-SMB-Out-Internet`.

#### NTLM auditing

- **Setting** (*template*): *Restrict NTLM: Outgoing NTLM traffic to remote servers* = Audit all;
  *Audit Incoming NTLM Traffic* = Enable auditing for all accounts. Nothing is blocked.
- **Why:** it shows which servers this PC still talks NTLM to. That is the evidence you would need
  before blocking NTLM.
- **Where to look:** Event Viewer → Applications and Services Logs → Microsoft → Windows → NTLM →
  Operational (events 8001 to 8003). The validator's *NTLM use (audited)* row counts them.
- **Undo:** `secpol.msc` → Local Policies → Security Options.

#### File-sharing server off

- **Setting** (*template*): the *Server* service (`LanmanServer`) is disabled.
- **Why:** port 445 doesn't listen at all, so no flaw in the file-sharing server and no weak
  share can be reached.
- **Cost:** this PC can't share folders or printers, and tools that manage it over SMB don't
  work. Connecting *to* other PCs' shares is a different service and works. WSL's
  `\\wsl.localhost` and Hyper-V are not affected.
- **Undo**, in a Command Prompt (as administrator): `sc config LanmanServer start= auto`, then
  `net start LanmanServer`.

#### UPnP off

- **Setting** (*template*): the services `SSDPSRV` (SSDP Discovery) and `upnphost` (UPnP Device
  Host) are disabled.
- **Why:** they answer discovery requests from the local network and let programs open router
  ports without asking.
- **Cost:** *Network* in File Explorer doesn't list routers, media servers and TVs, and *Cast to
  Device* doesn't find them. A game that opens ports through UPnP can show a stricter NAT type:
  forward the ports on the router instead.
- **Undo:** `sc config SSDPSRV start= demand` and `sc config upnphost start= demand`.

#### Network discovery announcements off

- **Setting** (*template*): the service `FDResPub` (Function Discovery Resource Publication) is
  disabled.
- **Why:** it announces the PC to the local network (WS-Discovery), so other devices find it
  without asking. On a Private network Windows' own firewall rules let those announcements out.
- **Cost:** the PC doesn't appear under *Network* in other PCs' File Explorer. Old NetBIOS name
  queries are still answered on a Private network.
- **Undo:** `sc config FDResPub start= demand`, then `net start FDResPub`.

#### WebDAV client off

- **Setting** (*template*): the `WebClient` service is disabled.
- **Why:** it starts by itself when anything opens a web address as a share and then sends your
  sign-in over HTTP, which credential-relay attacks rely on.
- **Cost:** no WebDAV folder as a drive letter (some NAS and SharePoint setups). Browsers and sync
  programs don't use it.
- **Undo:** `sc config WebClient start= demand`.

#### mDNS off

- **Setting** (*policy*): `DNSClient\EnableMDNS=0`.
- **Why:** the same reason the baseline turns LLMNR and NetBIOS off. A name asked of the whole
  local network can be answered by anyone on it.
- **Cost:** printers aren't found by themselves, and `.local` names stop working. Add a printer by
  its IP address (Settings → Bluetooth & devices → Printers & scanners → Add manually). Apps with
  their own mDNS code, such as a browser's casting, are not affected.
- **Undo:** `gpedit.msc` → Computer Configuration → Administrative Templates → Network → DNS
  Client → *Configure multicast DNS (mDNS) protocol*.

#### Automatic proxy discovery (WPAD) off

- **Setting** (a registry value, not a policy): `Internet Settings\WinHttp\DisableWpad=1`
  ([Microsoft](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/disable-http-proxy-auth-features)).
- **Why:** Windows asks the network whether there is a proxy. Whoever answers first gets to route,
  and read, the traffic.
- **Cost:** on a network that hands out its proxy this way, set the proxy by hand.
- **Note:** the per-user switch *Automatically detect settings* (Settings → Network & internet →
  Proxy) is not changed. Turn it off there too if you want browsers to skip WPAD.
- **Undo:** delete the value and restart.

#### Print spooler accepts no remote clients

- **Setting** (*policy*): `Printers\RegisterSpoolerRemoteRpcEndPoint=2`; the Point and Print
  prompts are pinned on (`NoWarningNoElevationOnInstall=0`, `UpdatePromptSettings=0`).
- **Why:** several serious print spooler flaws were reached over the network or through silent
  driver installs.
- **Cost:** this PC can't be a print server. Printing to USB and network printers works.
  Installing a shared printer's driver shows a warning and a UAC prompt.
- **Undo:** `gpedit.msc` → Computer Configuration → Administrative Templates → Printers.

#### Remote Desktop and WinRM refused

- **Setting** (*policy*): `Terminal Services\fDenyTSConnections=1`, `fAllowUnsolicited=0`,
  `WinRM\Service\AllowAutoConfig=0`, `WinRS\AllowRemoteShellAccess=0`.
- **Why:** each is a standing way into the PC. With the policy set, the switch in Settings can't
  turn Remote Desktop on.
- **Cost:** no Remote Desktop, PowerShell remoting or `winrs` *into* this PC. Connecting from it
  to others works, and so do local PowerShell and Hyper-V's own console.
- **Undo:** `gpedit.msc` → … → Remote Desktop Services, and → Windows Remote Management (WinRM).

#### winget's safety checks pinned

- **Setting** (*policy*, under `AppInstaller`): `EnableHashOverride=0`,
  `EnableLocalArchiveMalwareScanOverride=0`, `EnableBypassCertificatePinningForMicrosoftStore=0`,
  `EnableExperimentalFeatures=0`, `EnableMSAppInstallerProtocol=0`.
- **Why:** winget refuses an installer whose hash differs from its listing. These keep anyone from
  switching that off, and keep web pages from starting installs.
- **Cost:** `winget install --ignore-security-hash` is refused. Normal installs, upgrades and the
  Store work as before.
- **Undo:** `gpedit.msc` → … → Windows Components → Desktop App Installer.

#### No security questions for local accounts

- **Setting** (*policy*): `System\NoLocalPasswordResetQuestions=1`.
- **Why:** the answers are guessable facts, stored on the PC.
- **Cost:** a forgotten daily-account password is reset from the admin account
  ([how](../AFTER-INSTALL.md#lost-or-forgot-a-password)).

#### Strict Authenticode signature check

- **Setting** (registry values, 64- and 32-bit): `Wintrust\Config\EnableCertPaddingCheck=1`
  ([Microsoft's advisory, CVE-2013-3900](https://msrc.microsoft.com/update-guide/vulnerability/CVE-2013-3900)).
- **Why:** without it, data hidden inside a file's signature doesn't make the signature invalid.
  Malware has used that to hide in validly signed files.
- **Cost:** a few installers that stamp per-download data into their signature show as unsigned.
  SmartScreen then blocks them: **Unblock** a file you trust, or get a current version.
- **Undo:** set both values to 0 and restart.

#### PowerShell log 256 MB

- **Setting:** first-boot setup raises the log *Microsoft-Windows-PowerShell/Operational* from
  Windows' 15 MB to 256 MB.
- **Why:** the baseline turns on PowerShell script block logging, which writes every script that
  runs to this log. 15 MB holds little: one ISO build can push a week of history out.
- **Undo:** `wevtutil sl Microsoft-Windows-PowerShell/Operational /ms:15728640`.

### Sysmon

[Sysmon](../GLOSSARY.md#sysmon) (System Monitor) is Microsoft's tool for recording what happens
on a PC in more detail than the Security log. It is part of Windows 11 as an optional feature,
off by default ([KB5077241](https://support.microsoft.com/kb/5077241)).

First-boot setup turns the feature on and loads the kit's own configuration,
`C:\ProgramData\W11Kit\Sysmon-Config.xml`. The events go to Event Viewer → Applications and
Services Logs → Microsoft → Windows → Sysmon → Operational, a log of up to 256 MB.

| Event | What is recorded | Left out, so the log stays readable |
|---|---|---|
| 1 Process creation | Every program start with its command line, its parent and its SHA-256 hash | Console hosts, browsers' helper processes, Git's and WSL's helpers |
| 6 Driver loaded | Every driver not signed by Windows itself | Windows' own drivers |
| 3 Network connection | Only from script hosts and tools attackers misuse (`powershell`, `cmd`, `wscript`, `mshta`, `rundll32`, `certutil`, …) and from programs in Temp, Downloads or `C:\Users\Public` | Browsers, games and everything else |
| 2 File creation time changed | For programs and scripts: the trick of making a new file look old | The kit's work folder, DISM, Windows servicing, `msiexec`, `robocopy` |
| 25 Process tampering | A program's code replaced in memory | Browsers, whose sandboxes trigger it constantly |
| 19-21 WMI subscriptions | A way for malware to survive restarts | Nothing |

Everything else Sysmon can record (DLL loads, file creation, registry, DNS queries, …) is
switched off, because it would flood the log.

**Trade-offs.**

- A driver and a service run all the time, at a small processor cost.
- Command lines are recorded. A password typed on a command line ends up in the log, which only
  administrators can read.
- Standard users can read the configuration file, so its exclusions are no secret.

**If it isn't there.** On a Windows image without the feature, first-boot setup records a failure
and nothing else is affected. If Windows wants a restart first, a one-time task (*W11Kit Sysmon
setup*) finishes the job after the restart and deletes itself.

**Change or undo,** in a Command Prompt (as administrator):

- edit the file, then `sysmon -c C:\ProgramData\W11Kit\Sysmon-Config.xml` loads it;
- `sysmon -c` alone shows the running configuration;
- `sysmon -u` uninstalls it, and `Dism /Online /Disable-Feature /FeatureName:Sysmon` turns the
  feature off.

### Secure Boot 2023 certificates

[Secure Boot](../GLOSSARY.md#secure-boot) lets the PC start only software signed by a certificate
its firmware trusts. Microsoft's certificates from 2011 are running out:

- *Microsoft Corporation KEK CA 2011* and *Microsoft UEFI CA 2011* expired in June 2026.
- *Microsoft Windows Production PCA 2011*, which signed the older Windows boot manager, is valid
  only until 2026-10-19.

An expired certificate still starts what it already signed, but it can't sign fixes any more. So
the firmware needs Microsoft's 2023 certificates, and a new install stick should use the boot
manager signed by *Windows UEFI CA 2023*.

What the kit does:

- **The ISO starts with the 2023 boot manager.** The build takes it from the same updated files
  as Windows Setup.
- **First-boot setup queues Microsoft's certificate update** when the firmware lacks the 2023
  certificates (`AvailableUpdates=0x5944`: the signature database, the key exchange key and the
  2023 boot manager). Windows installs it over the next restarts. Nothing is revoked.
- **The validator checks** that the firmware's signature database has *Windows UEFI CA 2023*,
  that its key exchange keys include *Microsoft KEK 2K CA 2023*, and that the update recorded no
  error.

**Does your PC trust the 2023 certificate already?** On the running Windows, in PowerShell:

```text
(Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing).UEFICA2023Status
```

`Updated` means yes. The build's pre-flight reads the firmware itself and prints
`[OK  ] This PC's firmware trusts the stick's boot manager (Windows UEFI CA 2023)`, or a `[NOTE]`
that it doesn't. If the stick shows a Secure Boot violation instead of starting, the firmware
doesn't trust it yet: update the BIOS from the PC maker.

**The way out for a firmware without the 2023 certificate** is a build with
`-Use2011BootManager` ([Build options](BUILD-OPTIONS.md#build-options)). Know what you get: a
stick that starts with the boot manager signed in 2011. Its certificate is valid only until
2026-10-19, so no repaired boot manager will ever be signed with it, and a PC whose firmware has
revoked the 2011 certificate will not start that stick. Use it to get the PC installed, let
Windows install the 2023 certificates, and build the next stick without the switch.

**Keep the stick current.** A stick's boot manager is as old as its build. A PC that has all its
updates can one day refuse an old one, so write the stick again after each monthly rebuild
([Rebuild the ISO](../MONTHLY.md#rebuild-the-iso)).

**Not done: revoking the 2011 boot manager.** See [Considered, not adopted](#considered-not-adopted)
and, for what that leaves open,
[the threat model](../../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it).

### Optional Brave policies

With `options.bravePolicies` set to `true` in [your settings](CONFIGURATION.md#your-settings),
the image sets four security policies for the Brave browser, which the Edge baseline doesn't
cover (`HKLM\SOFTWARE\Policies\BraveSoftware\Brave`):

- Safe Browsing on (standard level);
- downloads that Safe Browsing flags as dangerous are blocked;
- no basic authentication over plain HTTP;
- one process per site.

Brave itself is not in the image, and the policies do nothing until you install it. Its own
features are left to you. `brave://policy` shows the four. The option is off by default.

## Ransomware protection and other settings

These follow your settings ([CONFIGURATION, Options](CONFIGURATION.md#options-options)); the
defaults are listed.

- **Defender Controlled Folder Access on** (`controlledFolderAccess`) and the **ASR rule *Block
  executable files unless they meet a prevalence, age or trusted list criterion*** in Block
  (`asrPrevalenceRule`), both as Defender preferences set at first boot, not as policy, so a build
  on the PC can pause them after asking ([The build PC](CONFIGURATION.md#the-build-pc)). Cost:
  programs you build yourself, and unknown programs writing to your documents, are stopped until
  you allow them.
- **ASR exceptions** (`asrExclusions`, empty by default): per-rule exclusions
  (`ExploitGuard_ASR_ASROnlyPerRuleExclusions`) for the prevalence rule and the baseline's
  *Use advanced protection against ransomware* (`c1db55ab-c21a-4637-bb3f-a12568109d35`) only. Both
  judge a program by its reputation, so a program you build or a small tool nobody else runs is
  stopped. The other ASR rules still cover the listed paths. Cost: Defender no longer judges the
  listed programs by their reputation.
- **NetBIOS over TCP/IP off** (`netbios`) on every adapter present at first boot.
- **The first network's category** (`firstNetworkCategory`, `public` by default): with `private`, the
  network Setup used is *Private* at first boot. The baseline sets
  `WindowsFirewall\PublicProfile\AllowLocalPolicyMerge` = 0, so on *Public* only the baseline's
  and the kit's firewall rules count; on *Private*, rules that apps add themselves apply too.
- **DNS over HTTPS** (`dns`, off by default): the policy allows DoH (`DNSClient\DoHPolicy` = 2), and
  each configured server is registered DoH-only (no fallback to plain DNS). Not `3` (require):
  that would also force the local zones, whose servers rarely speak DoH.
- **Windows Update drivers and optional updates** (`windowsUpdateDrivers`, `optionalUpdates`, off
  by default): [DECISIONS](../dev/DECISIONS.md#windows-update-does-not-deliver-drivers).

## Considered, not adopted

| Not adopted | Why |
|---|---|
| Smart App Control forced on; application allowlisting (App Control for Business, AppLocker allow rules) | They block programs you build yourself. Smart App Control is left to Windows ([CONFIGURATION](CONFIGURATION.md#smart-app-control)); AppLocker is used only as a deny-list for administrators' browsers |
| ASR rule *process creations from PsExec and WMI commands* in Block mode | The baseline leaves it in Audit. Management tools and some installers start programs through WMI: look at the audit events (Defender event 1122) before blocking |
| A BitLocker start-up PIN by default | It stops a PC that wakes over the network at a prompt. You can add one ([CONFIGURATION](CONFIGURATION.md#bitlocker)) |
| Revoking the 2011 boot manager in the firmware (the Secure Boot DBX and the boot manager's version number) | It can't be undone, and every older stick, recovery drive and image stops starting. The 2023 certificates are added without revocations |
| Windows protected print mode | It allows only driverless (IPP) printers: no vendor printer drivers and no raw TCP/IP ports. The spooler is hardened another way ([above](#print-spooler-accepts-no-remote-clients)) |
| Windows LAPS | It needs a directory service to store the password |
| Personal Data Encryption, hotpatching | They need Microsoft Entra and Intune |
| Sudo for Windows | The baseline leaves it disabled. The separate admin account is the model here |
| PowerShell transcription and module logging | Large logs, and transcripts capture everything shown on screen, secrets included. Script block logging is on |
| Locking down WSL by policy | WSL is there to be used for development |
| Removing VBScript | Microsoft is retiring it on its own schedule, and old installers still call it |
| Hiding the password reveal button | Typing a 20-character one-time password blind causes lockouts. The button shows it only while held |
| Windows Error Reporting off | Crash reports are how driver and app faults reach their makers |
| DNS over HTTPS | It depends on the DNS server in use. Set it per network if you want it |
| Quick Machine Recovery | Left as Windows sets it. The validator reports its state |
| The STIG rules that conflict with a project decision | [The review](../dev/reviews/STIG-REVIEW.md) lists each with its reason |

The wider survey behind this table is in
[BEST-PRACTICE-SURVEY](../dev/reviews/BEST-PRACTICE-SURVEY.md); the reasons for the project's
main decisions are in [DECISIONS](../dev/DECISIONS.md).

## Known risks accepted

| Risk | Why it stays | What limits it |
|---|---|---|
| The ISO holds the two one-time passwords, hidden but not encrypted | An unattended install must carry them | New for every build; both accounts must change them at first sign-in; Setup's cached copies are deleted and the validator checks that. Keep the ISO and the stick private until then |
| The finished ISOs in `C:\W11Kit\work` are readable by every user of the build PC | The folder lock makes the build's folders read-only for other users, not hidden | The same as above. Delete ISOs you no longer need |
| The source ISO is read from a user's `Downloads` folder | Microsoft's ISO is downloaded once, by hand, in a browser | Its SHA-256 hash is pinned and checked before the build uses it |
| BitLocker unlocks from the TPM alone, with no PIN | A PC that wakes over the network must start by itself | Hibernate instead of sleep, DMA protection, a BIOS password. The full picture is in [the threat model](../../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it) |
| Some protections are off or not forced: Administrator protection, Smart App Control (left to Windows) | Each one blocks building the next ISO or programs you build yourself | Defender with tamper protection, SmartScreen set to Block, 17 ASR rules, blocking of potentially unwanted apps |
| The browser block for administrators can be removed by an administrator | A deny-list is an aid, not a boundary | The validator FAILs when it is missing |

**The build PC.** The build runs as administrator, so everything it reads must be changeable by
administrators only. The kit locks its folders and checks each input before use:
[Folder lock](../dev/BUILD-INTERNALS.md#folder-lock).

## Other hardening tools

Don't run a second hardening tool on top of this image. Such tools set many of the same policies
to other values, and the two then work against each other. Examples of settings that conflict:

| A second tool sets | Effect here |
|---|---|
| BitLocker start-up: TPM and PIN required | The *Enable BitLocker (local key)* script refuses to start |
| Account lockout after a few attempts, for many hours | With a single admin account, you are locked out of administration |
| PowerShell scripts blocked by machine policy | The validator and the BitLocker script can't run |
| Smart multi-homed name resolution off | DNS lookups can stall for about 10 seconds behind a full-tunnel VPN |

The image pins the BitLocker start-up policy itself, and the BitLocker script refuses to start if
something changed it. The validator has rows for these settings (their names start with
`Conflicts:` and `Self-hosting:`), and the row `No second hardening tool`, which WARNs when it
finds one installed.

## Changing a setting later

Everything here lives in local Group Policy, and the files that set it are in
`C:\ProgramData\W11Kit` on the installed PC. Because registry policy is re-applied at every
refresh, a change made only in the registry doesn't last: change the file, then apply everything
again.

| What you want to change | File |
|---|---|
| A baseline registry policy, or an override of one | `baseline-overrides.txt` |
| The UAC prompt, Administrator protection, password and lockout policy, built-in account names, sign-in rights, the NTLM audit options, services | `baseline-overrides.inf` |
| An audit subcategory | `baseline-overrides-audit.csv` |
| One of the kit's own policies (privacy, Edge, network) | `Set-KitRegistry.ps1`: remove or change its line |

`baseline-overrides.txt` has four lines per entry: `Computer` or `User`, the key, the value name,
and an action. Actions are `DWORD:n`, `QWORD:n`, `SZ:text`, `EXSZ:text`, `MULTISZ:a\0b`,
`BINARY:00,ff`, `DELETE`, `DELETEALLVALUES`, `DELETEKEYS`, or `CLEAR` to drop a key from the
policy altogether. `baseline-overrides.inf` is UTF-16 with CRLF line ends: keep it so.

Then apply everything again, exactly as first-boot setup did. In PowerShell (as administrator):

```text
cd C:\ProgramData\W11Kit
$p = (Get-Content -Raw profile.json | ConvertFrom-Json).power.mode
& ([scriptblock]::Create((Get-Content -Raw .\Apply-Policy.ps1))) -PowerMode $p -Settings (Get-Content -Raw settings.json | ConvertFrom-Json) -LogDir .\Logs
```

It prints what it applied and what the read-back found (`Failures`, `Critical`).

Make the same change in the kit (`C:\W11Kit\config\baseline-overrides.*` or
`C:\W11Kit\scripts\Set-KitRegistry.ps1`), or the next image you build undoes it. A setting that
exists as an option is easier: change it in [your settings](CONFIGURATION.md#your-settings) and
rebuild. That goes for the built-in accounts' names and the Xbox services too: in the kit they
come from your settings (`accounts.builtinAdministratorName`, `accounts.builtinGuestName`,
`options.gamingTweaks`), not from `config\baseline-overrides.inf`.

Moving to a newer Microsoft baseline is a maintainer task:
[New Microsoft security baseline](../dev/MAINTAINING.md#new-microsoft-security-baseline).
