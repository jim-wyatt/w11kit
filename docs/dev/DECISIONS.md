# Decisions

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

The choices this kit is built on, each with its reason and its cost. Change one only on purpose,
and change the docs in the same commit. What each setting is and how to undo it on your own PC is
in the reference pages ([CONFIGURATION](../reference/CONFIGURATION.md),
[SECURITY-BASELINE](../reference/SECURITY-BASELINE.md)); this page says why.

**Structure**

- [Hardware in profiles, your choices in settings](#hardware-in-profiles-your-choices-in-settings)
- [Neutral shipped defaults](#neutral-shipped-defaults)
- [Windows 11 Pro 26H2, x64](#windows-11-pro-26h2-x64)
- [One work folder](#one-work-folder)

**Drivers and firmware**

- [Drivers come from the running install](#drivers-come-from-the-running-install)
- [Windows Update does not deliver drivers](#windows-update-does-not-deliver-drivers)
- [No firmware in the image; BIOS updates by hand](#no-firmware-in-the-image-bios-updates-by-hand)

**Accounts and passwords**

- [Two local accounts, no Microsoft account](#two-local-accounts-no-microsoft-account)
- [Generated one-time passwords](#generated-one-time-passwords)

**Security**

- [Microsoft's security baselines, in full, with documented overrides](#microsofts-security-baselines-in-full-with-documented-overrides)
- [The domain-joined baseline set on a standalone PC](#the-domain-joined-baseline-set-on-a-standalone-pc)
- [Baselines imported at build time, applied with built-in tools](#baselines-imported-at-build-time-applied-with-built-in-tools)
- [Selected DISA STIG settings](#selected-disa-stig-settings)
- [Additions from the best-practice survey](#additions-from-the-best-practice-survey)
- [BitLocker: manual, TPM-only](#bitlocker-manual-tpm-only)
- [No second hardening tool](#no-second-hardening-tool)
- [Remote access on demand](#remote-access-on-demand)
- [Diagnostic data at Required; consumer features off](#diagnostic-data-at-required-consumer-features-off)

**Power and platform**

- [Power per profile](#power-per-profile)
- [Balanced power plan](#balanced-power-plan)
- [WSL and Virtual Machine Platform only](#wsl-and-virtual-machine-platform-only)
- [Product key per profile](#product-key-per-profile)

**The build**

- [Build folders writable by administrators only](#build-folders-writable-by-administrators-only)
- [Build tools installed on demand, never in the image](#build-tools-installed-on-demand-never-in-the-image)
- [Self-hosting](#self-hosting)
- [Build inputs in the ISO](#build-inputs-in-the-iso)
- [Boot media signed with the Windows UEFI CA 2023](#boot-media-signed-with-the-windows-uefi-ca-2023)
- [Hyper-V is the one VM test](#hyper-v-is-the-one-vm-test)
- [A release is proven by the VM test](#a-release-is-proven-by-the-vm-test)

**Outside the kit's job**

- [The kit does not back up your data](#the-kit-does-not-back-up-your-data)
- [GPU vendor apps come after the image](#gpu-vendor-apps-come-after-the-image)

---

## Structure

### Hardware in profiles, your choices in settings

**Decision.** What differs between PC models lives in a hardware profile
(`profiles/<id>/profile.json`): driver providers, device checks, power mode and Wake-on-LAN, the
product-key source, the Kernel DMA Protection policy for BitLocker, BIOS hints. Your own choices
(keyboard, formats, time zone, computer name, account names, options, reminders) live in
`config/settings.local.json`, laid field by field over the kit's defaults
(`config/settings.defaults.json`, the only place a default is declared). The kit's own opinions
live in the rest of `config/` and in the
scripts, and are the same for every profile.

**Why.** One kit for any PC. A profile is data: it can be reviewed, shared and checked by a
schema. Your settings file is untracked, so `git pull` never conflicts with it.

**Cost.** Three places to look. Preflight validates both files and refuses unknown fields; the
build writes the effective settings and their sources into the manifest. Facts about one PC model
belong in that profile's README, not in the general docs
([PROFILES](../reference/PROFILES.md)).

### Neutral shipped defaults

**Decision.** The kit's defaults suit any PC. Anything that is a personal taste is a setting you
turn on:

- `options.gamingTweaks`, `options.bravePolicies`, `options.longPaths`,
  `options.allowMicrosoftAccount`: off.
- `options.smartAppControl`: `"leave"` (Windows decides); `"off"` is for a PC that runs its own
  unsigned builds.
- `reminders.oneDriveBackup` and `reminders.nvidiaApp`: off. `reminders.offlineBackup` and
  `reminders.remoteAccessOnDemand`: on. `reminders.expectedApps`: empty.
- `options.firstNetworkCategory`: `public`, Windows' own choice for a new network.
- `options.scheduledValidation`: on. The validator only reads, and a scheduled run catches a
  Windows Update change (a driver, a policy) without anyone opening *Validate PC*.
- Keyboard, formats, system locale, time zone and home location: taken from the build PC's own
  current values when you set none. `Run-Build.cmd` reads them as the account that started it,
  and the build prints where each value came from.
- The computer name: none (Windows picks a random one). The new names of the built-in
  Administrator and Guest accounts: drawn for each build.

**Why.** A shipped default is what every user gets without having chosen it. A gaming tweak, a
browser's policies or a backup reminder for one cloud service is one person's choice.

**Cost.** A user who wants those has to edit the settings file once
([CONFIGURATION, Your settings](../reference/CONFIGURATION.md#your-settings)).

### Windows 11 Pro 26H2, x64

**Decision.** The image is Windows 11 Pro, version 26H2, x64. Windows' display language is English
(United States, or English International as `en-GB`); the settings check refuses another. The source ISO is pinned by
SHA-256 (`config/source-iso.json`, or your own in `config/source-iso.local.json`).

**Why.** Servicing of 24H2 Pro ended on 2026-10-13, and 26H2 is the same core. One edition and one
architecture keep the image and its checks the same for everyone.

**Cost.** Home, Enterprise, Education and ARM64 are out of scope; the build refuses a non-x64 PC
or source. Another display language waits for account creation that doesn't name the groups in
English, and for a VM test in that language; keyboard, formats, time zone and country are
settings of their own.

### One work folder

**Decision.** Everything the kit downloads or makes is in `<kit>\work`: updates, baselines,
installers, drivers, logs, mounts, finished ISOs, the passwords file, VM test files. `-WorkRoot`
moves it. The folder is git-ignored.

**Why.** One place to back up, lock and delete. Nothing is left in `C:\` or in a user profile.

**Cost.** `git clean -x` in the kit folder would delete all of it (see
[GOTCHAS](GOTCHAS.md#git)).

## Drivers and firmware

### Drivers come from the running install

**Decision.** The harvest exports the drivers the PC's current Windows uses and keeps those of the
profile's providers. A driver from anywhere else is an override, with a documented reason
([DRIVERS, Overrides](../reference/DRIVERS.md#overrides)).

**Why.** They are known to work on this exact hardware.

**Cost.** A PC whose current drivers are bad or missing needs an override. The harvest must run on
the PC that will be reinstalled.

### Windows Update does not deliver drivers

**Decision.** By default, quality updates exclude drivers (`ExcludeWUDriversInQualityUpdate`); `options.windowsUpdateDrivers` lets a user choose otherwise. For newly
connected devices Windows does not search Windows Update (`DriverSearching\SearchOrderConfig` = 0,
`DontSearchWindowsUpdate`, `DontPromptForWindowsUpdate`), fetches no device metadata, and sends no
"additional software" or "generic driver" reports (`DeviceInstall\Settings`).

**Why.** Driver swaps by Windows Update and vendor installers have broken GPU drivers on AMD
systems. The curated set stays as built. A newly connected device also cannot pull its vendor's
companion software.

**Cost.** Firmware capsules for the BIOS or embedded controller don't arrive through Windows
Update either, so firmware updates are manual. A new device with no inbox driver needs its driver
installed by hand ([AFTER-INSTALL](../AFTER-INSTALL.md#a-device-without-a-driver)).

### No firmware in the image; BIOS updates by hand

**Decision.** The harvest never keeps class `Firmware`. BIOS and firmware are updated by hand from
the PC maker's support site, checked at each monthly rebuild.

**Why.** A capsule staged in a fresh install could reflash the firmware at first boot. A firmware
update should be a deliberate step, with BitLocker suspended first.

**Cost.** One manual check a month ([MONTHLY](../MONTHLY.md#bios-and-firmware-updates)).

## Accounts and passwords

### Two local accounts, no Microsoft account

**Decision.** A standard daily account (`LocalUser`) and a separate admin account (`LocalAdmin`).
Converting either into a Microsoft account is blocked unless `options.allowMicrosoftAccount` is
set. The built-in Administrator and Guest stay disabled and get new names generated for each
build.

**Why.** Least privilege: everyday work cannot change the system without the admin's password.
Windows itself must never need a Microsoft account. App sign-in (Store, Edge, OneDrive) is not
affected.

**Cost.** A credential prompt for every admin task. There is one admin: if it locks out or its
password is lost, see
[AFTER-INSTALL](../AFTER-INSTALL.md#lost-or-forgot-a-password).

### Generated one-time passwords

**Decision.** The build generates both passwords: 20 characters from 52 letters and digits (no
look-alikes, no `Y` or `Z`, no symbols), drawn from the cryptographic random generator without
bias, redrawn until the password has an upper-case letter, a lower-case letter and a digit: about
114 bits. They are written to `<work>\accounts.txt`, created readable by administrators only,
never to the console or a log. Both must be changed at the first sign-in.

**Why.** No typed or reused secret ends up in the ISO. The alphabet types the same on US, UK and
German keyboards.

**Cost.** The ISO holds the passwords only obfuscated and local users can read it, so the ISO and
the stick stay private until both passwords are changed. When the build PC is the PC you
reinstall, the passwords must be copied off it first
([BUILD-INTERNALS, Passwords](BUILD-INTERNALS.md#passwords)).

## Security

### Microsoft's security baselines, in full, with documented overrides

**Decision.** The image applies Microsoft's Windows 11 v26H2 and Edge v151 security baselines
completely. Every deviation is an override with a written reason: 17 in a build with the kit's
default settings, and one more (the Xbox services) with `options.gamingTweaks`. They are listed in
[SECURITY-BASELINE, Overrides](../reference/SECURITY-BASELINE.md#overrides). They cover:

- the credential prompt for the standard user, Administrator protection off, the admin listed at
  the prompt, an 11-character minimum password;
- write access to USB drives, no UEFI lock on memory integrity, Credential Guard and LSA
  protection;
- only safe samples sent to Microsoft, Edge extensions, native messaging and certificate-error
  click-through;
- the Xbox save task left enabled, and, only with `options.gamingTweaks`, the Xbox services;
- four that make the baseline stricter, from the STIG review (lockout 15 minutes, deny-logon
  rights for Guests, a 1 GB Security log, two audit subcategories for success and failure).

**Why.** Secure by default, with Microsoft's reasoning behind each value. An override that is
written down can be reviewed and reversed; a silent one can't.

**Cost.** Some things work differently from a stock Windows
([AFTER-INSTALL](../AFTER-INSTALL.md#what-is-different-on-this-pc)). First-boot setup reads every
override back: a baseline value in an override's place cancels the restart.

### The domain-joined baseline set on a standalone PC

**Decision.** The kit applies the GPO set that Microsoft's `Baseline-LocalInstall.ps1
-Win11DomainJoined` applies, although the PC is in no domain.

**Why.** The non-domain-joined set differs by re-enabling remote administration with local
accounts. This PC has only local accounts, so that difference is exactly what should stay closed.

**Cost.** No remote administration with a local account (no admin shares, no remote registry or
WMI as `LocalAdmin`).

### Baselines imported at build time, applied with built-in tools

**Decision.** The repository holds no Microsoft baseline file and no baseline data: only the pins
(`config/baselines/<id>/source.json`: URL, file name, SHA-256, GPO order). `Run-Build.cmd` offers
to download each official zip into `<work>\baselines` (`Get-Baselines.py`). Every build checks
the zips' hashes and runs `Import-Baseline.py`, which turns them into reviewable data; data left
in the work folder by an earlier run is never trusted. On the installed PC `Apply-Policy.ps1`
merges baselines, overrides and the kit's
policies once and applies them with Windows' own tools (`Registry.pol` + `gpt.ini`, `secedit`,
`auditpol`, `gpupdate`). No `LGPO.exe`.

**Why.** Nothing of Microsoft's is redistributed. Every value comes from an official file whose
hash is pinned. Because there is one merge, an override can never trail behind a bare baseline,
and the validator can check every baseline value on the live PC.

**Cost.** Every build needs Python, and the first one an Internet connection for the zips (they
then travel in the build inputs). Microsoft sometimes replaces a zip in place: the pin then fails until
it is moved ([MAINTAINING](MAINTAINING.md#new-microsoft-security-baseline)). The ADMX templates
are not installed, so `gpedit.msc` shows some of these settings without a label.

### Selected DISA STIG settings

**Decision.** The kit adopts the settings of the DISA Windows 11 STIG (Version 2, Release 11) that
are cheap and don't conflict with another decision here: the 29 "adopt" items of the
[STIG review](reviews/STIG-REVIEW.md) and four of its "consider" items (browsers denied to
administrators with AppLocker, lockout 15 minutes, Security log 1 GB, Wi-Fi Direct adapters off).
The list is in
[SECURITY-BASELINE, DISA STIG additions](../reference/SECURITY-BASELINE.md#disa-stig-additions).

**Why.** Most are one value the baseline leaves at a Windows default, or an audit subcategory the
baseline doesn't set.

**Cost.** The image is **not STIG-compliant**, and doesn't try to be. The rules that conflict with
a decision stay deviations: a BitLocker startup PIN, a 3-attempt lockout, 14-character passwords,
password expiry, application allowlisting, blocking all consumer-account sign-in, and, with
`options.gamingTweaks`, Secondary Logon left at Manual (some game launchers refuse
to install without it). Audit rows are
only ever applied as one merged file (see
[GOTCHAS](GOTCHAS.md#group-policy-baselines-and-audit-policy)).

### Additions from the best-practice survey

**Decision.** Beyond the baselines and the STIG items, the kit adds what a
[survey of current guidance](reviews/BEST-PRACTICE-SURVEY.md) found worth its cost:

- two more attack-surface-reduction rules (Safe Mode reboot, copied system tools), the feature
  version pinned, the Secure Boot 2023 certificates queued and checked;
- outbound SMB to the Internet blocked, NTLM audited (not blocked), WPAD off, the spooler takes no
  remote clients, Remote Desktop and WinRM off by policy, the WebClient, Server, SSDP and UPnP
  services disabled, mDNS off;
- winget's bypass switches off, no security questions, the stricter Authenticode check, Windows'
  built-in Sysmon with the kit's own configuration;
- Edge privacy and AI policies, no web results in Start search, more bundled apps removed.

Each is described in
[SECURITY-BASELINE, Additions beyond the baseline](../reference/SECURITY-BASELINE.md#additions-beyond-the-baseline).

**Why.** Each closes a way in that a home PC doesn't need open.

**Cost.** Printers are added by IP address (no mDNS). The PC shares no folders or printers. Some
installers show as unsigned under the stricter check. What was looked at and left out (for example
Windows protected print mode, which blocks vendor printer drivers, and revoking the 2011 boot
certificate, which can't be undone) is in
[SECURITY-BASELINE, Considered, not adopted](../reference/SECURITY-BASELINE.md#considered-not-adopted).

### BitLocker: manual, TPM-only

**Decision.** BitLocker is a step you run after the install. It uses the TPM alone, with no
startup PIN, and saves the recovery key where you choose; nothing is sent to Microsoft. The helper
checks Kernel DMA Protection first, per profile (`security.kernelDmaProtection`): `required`
refuses without it, `recommended` warns. No readable profile counts as `required`.

**Why.** A startup PIN would stop every Wake-on-LAN start at the pre-boot prompt. Hibernating
instead of sleeping keeps the key out of memory while the PC is off.

**Cost.** Someone who takes the whole PC can start it up to the Windows sign-in screen. What that
leaves open, and what closes it, is in
[SECURITY.md](../../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it). The validator
warns until `C:` is encrypted.

### No second hardening tool

**Decision.** The kit is the only thing that hardens the image. Don't run another hardening tool
on top of it.

**Why.** Two tools that both write security policy can conflict, and the result belongs to neither.
Examples of settings such a tool may apply that conflict with decisions here: turning sleep states
off or on again, requiring a BitLocker startup PIN, a stricter account lockout (which can lock out
the only admin), blocking `.ps1` scripts (which the kit's own tools need).

**Cost.** None. The kit pins the BitLocker startup policy, and the validator reports another
hardening tool it recognises
([SECURITY-BASELINE, Other hardening tools](../reference/SECURITY-BASELINE.md#other-hardening-tools)).

### Remote access on demand

**Decision.** Remote Desktop is off by policy. If you use a remote-access tool, start it when you
need it: its service set to Manual, nothing in the tray at sign-in. The validator warns otherwise
(`reminders.remoteAccessOnDemand`).

**Why.** A remote-access service that starts with Windows is a standing way in, and it goes
around "no network logon for local accounts".

**Cost.** Somebody has to be at the PC to start the tool.

### Diagnostic data at Required; consumer features off

**Decision.** Diagnostic data is set to *Required*, the lowest level Pro honours. Recall,
widgets, ads, suggestions, activity history and cross-device features are off.

**Why.** Privacy without breaking Windows Update, which needs the Required level. Measures that go
further (removing Edge or the Store, disabling update services) break servicing and are not
adopted.

**Cost.** None known.

## Power and platform

### Power per profile

**Decision.** `power.mode` in the profile: `hibernate` means the PC hibernates instead of
sleeping and Fast Startup is off; `default` leaves sleep as Windows sets it. Wake-on-LAN (magic
packet, from hibernate and from shutdown) is set up only when the profile has `power.wakeOnLan`.
The baseline's standby ban and System Guard Secure Launch stay as Microsoft ships them for every
profile.

**Why.** A desktop that is also reached remotely should be off with its disk key out of memory,
and still startable over the network.

**Cost.** Resuming from hibernation is slower than from sleep. Wake itself can only be tested on
real hardware.

### Balanced power plan

**Decision.** The image keeps the *Balanced* plan.

**Why.** It is AMD's guidance for Ryzen: the X3D processors rely on the chipset driver's core
parking, which works under Balanced.

**Cost.** None known.

### WSL and Virtual Machine Platform only

**Decision.** The image enables the two Windows features WSL2 needs, and not the Hyper-V role. No
Linux distribution is installed.

**Why.** The minimum for WSL2. Hyper-V is needed only on a PC that runs the VM test, and is
installed there on demand.

**Cost.** None on the installed PC.

### Product key per profile

**Decision.** `productKey` in the profile: `firmware` puts no key in the answer file (Setup uses
the Pro key in the PC's firmware), `generic` uses the generic Windows 11 Pro installation key (a
default key that only selects the edition during Setup; it does not activate Windows and is not a
licence), `prompt` lets Setup ask. Preflight refuses `firmware` when the firmware key isn't Pro.

**Why.** The image is Pro-only. A PC sold with Home and later upgraded to Pro has a Home key in
its firmware, and needs `generic` so that Setup picks Pro. No real product key ever goes into the
ISO.

**Cost.** You need your own Pro licence; the kit doesn't provide or check one.

## The build

### Build folders writable by administrators only

**Decision.** Before a build, the kit folder, the work folder and the driver export are made
writable by Administrators and SYSTEM only (owner Administrators; Users read and execute). The
walk opens every item by handle, never follows a link and refuses junctions. Git trusts
(`safe.directory`) the clone only. Each update file's SHA-1 is checked against its name right
before it is applied, drivers are checked against the harvest's SHA-256 manifest, and `oscdimg`
runs only with the exact ADK signer.

**Why.** The build runs elevated. An input a standard user can write is a path from standard user
to administrator, and a way into the next image.

**Cost.** Editing the kit or running `git pull` needs an administrator's terminal (or
`Run-Build.cmd`'s offer to update). Details:
[BUILD-INTERNALS, Folder lock](BUILD-INTERNALS.md#folder-lock).

### Signed releases, and updates only to them

**Decision.** Each release is a git tag `v<version>` signed with an SSH key made for the project
(`config/release-signers`). The guide clones a release and checks its signature.
`Run-Build.cmd` updates the kit only to the newest release signed by a key in the list the kit
already has; anything else is refused.

**Why.** The kit runs as administrator and decides what the next Windows contains: an unverified
`git pull` that runs at once is a path into every PC built from it.

**Cost.** Commits between releases arrive only with the next release; a maintainer pulls them by
hand. The private key, and its passphrase, must not be lost: a new key needs a release signed by
the old one that lists the new key, or every user checks a new fingerprint by hand.

### Build tools installed on demand, never in the image

**Decision.** Git for Windows, Python 3 and the ADK Deployment Tools (and Hyper-V for the VM test)
are installed only on a PC that builds, after a `[Y/n]` question, from official installers pinned
by version, SHA-256 and Authenticode signer (`config/installers.json`). Never through winget.

**Why.** The installed PC stays minimal and carries no tools it doesn't use; a PC that wants to
build gets them back in one step. winget can't run elevated when Administrator protection is on.

**Cost.** The pins need moving when a tool is updated
([MAINTAINING](MAINTAINING.md#updating-the-build-tools)).

### Self-hosting

**Decision.** The installed PC must be able to rebuild its own ISO from a clone of this
repository.

**Why.** The build PC is usually the PC being reinstalled, and next month it will be the installed
one.

**Cost.** Nothing in the image may block a build for good: Administrator protection stays off.
Defender's Controlled Folder Access and the "prevalence, age or trusted list" ASR rule are on, as
preferences, because the installed PC is not a throwaway build machine: a build pauses them only
after the user agrees (`Run-Build.cmd` asks; CI passes `-PauseDefenderProtection`) and restores
them when it ends. Checklist:
[BUILD-INTERNALS, Self-hosting](BUILD-INTERNALS.md#self-hosting).

### Build inputs in the ISO

**Decision.** A real build puts what it was built from into the ISO: the source ISO, the updates,
the baseline zips, the driver export, `oscdimg`, the build-tool installers, a bundle of the kit
and your untracked files (settings, source-ISO pin, your own profile). Large files are split under
4 GB, each with its SHA-256. `Restore-BuildInputs.cmd` puts everything back under one folder.

**Why.** A reinstall erases `C:`, and the source ISO (about 9 GB) can't be downloaded by a script.

**Cost.** The stick must be 32 GB or larger. `-NoBuildInputs` leaves them out
([BUILD-OPTIONS](../reference/BUILD-OPTIONS.md#build-inputs-in-the-iso)).

### Boot media signed with the Windows UEFI CA 2023

**Decision.** The ISO boots with the boot manager signed by the *Windows UEFI CA 2023*.
`-Use2011BootManager` opts out.

**Why.** The *Microsoft Windows Production PCA 2011* certificate is valid only until 2026-10-19. A PC with
current firmware trusts the 2023 certificate.

**Cost.** A PC whose firmware doesn't have the 2023 certificate yet can't boot the stick without
the opt-out. Proven in the Hyper-V VM test only ([Boot media](BUILD-INTERNALS.md#boot-media)).

### Hyper-V is the one VM test

**Decision.** The kit has one VM test: a hands-off install in a Hyper-V VM with Secure Boot and a
TPM, graded against `config/vm-expected.json`, ending in `RESULT: PASS` or `RESULT: FAIL`.

**Why.** It runs on the same Windows the build runs on, with nothing else to install, so a user
can run exactly the test the project runs.

**Cost.** What a Hyper-V VM can't show stays untested until a real install: device drivers,
hibernation, Wake-on-LAN, a USB boot ([TESTING](TESTING.md#rows-expected-to-fail-in-a-vm)).

### A release is proven by the VM test

**Decision.** A release, the first beta included, needs a build and the Hyper-V VM test with
`RESULT: PASS`. It does not wait for a reinstall of the reference PC. The real-hardware checks
still open (turning BitLocker on with `Enable-BitLocker.cmd`, restoring the build inputs and
rebuilding, a second *Validate PC* run) are done at the reference PC's next reinstall.

**Why.** A reinstall wipes the build PC, its CI runner and its working setup. The VM test runs
the same install, first-boot setup and validator on every change. The reference PC has already
been installed once from the kit.

**Cost.** Until that reinstall, those checks are listed as not proven
([TESTING, Status](TESTING.md#status)), and a release can carry a fault that only real hardware
shows.

## Outside the kit's job

### The kit does not back up your data

**Decision.** The kit makes no backups. The validator reminds: `reminders.offlineBackup` warns
when the stamp of the last offline backup is older than 35 days, and `reminders.oneDriveBackup`
(off by default) warns when Documents, Desktop or Pictures are not in OneDrive.

**Why.** Where your data goes is your choice. A reminder costs nothing.

**Cost.** None ([MONTHLY, Offline backup](../MONTHLY.md#offline-backup)).

### GPU vendor apps come after the image

**Decision.** A GPU vendor's companion app is optional and installed after the image, with
automatic driver installs turned off. `reminders.nvidiaApp` (off by default) makes the validator
check that.

**Why.** Driver updates stay deliberate, for the same reason Windows Update doesn't deliver them.

**Cost.** GPU driver updates are a manual step.
