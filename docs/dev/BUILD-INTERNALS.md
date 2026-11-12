# Build internals

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

What `scripts\Build-Iso.ps1` does, step by step, and why. This page is about how the build works
inside. What you type, where files go and how much space you need is in
[BUILD-OPTIONS](../reference/BUILD-OPTIONS.md). Why the kit decided what it decided is in
[DECISIONS](DECISIONS.md), and the traps of the tools it uses are in [GOTCHAS](GOTCHAS.md).

On this page `<work>` is the work folder (`C:\W11Kit\work` unless `-WorkRoot` names another).

## Build steps

`Run-Build.cmd` prints a short notice (you accept Microsoft's licence terms, the ISO erases a
disk, there is no warranty) and asks its questions first (`scripts\Invoke-KitLauncher.ps1`:
[What Run-Build.cmd asks](../reference/BUILD-OPTIONS.md#what-run-buildcmd-asks)). Then it starts
`Build-Iso.ps1`, which never asks anything. After a build that succeeded, the launcher prints the
`Keep this ISO private: ...` line and offers the VM test. A build started directly
(`Build-Iso.ps1` from a job) has neither the notice nor that line. With `-Preflight` the launcher
asks nothing, and the build stops after step 3 and changes nothing.

Before the numbered steps, the build:

- refuses to run unelevated (except with `-Preflight`), on a Windows older than build 26100
  (24H2: its DISM services the image) and on a PC that is not x64;
- removes Defender exclusions that an interrupted build left on its own work folders, and, right
  after the lock, deletes a VM test's copy that an interrupted test left in `<work>\vmtest`
  (`-Preflight` only reports both).

While it runs, a build holds the named mutex `Global\W11KitBuild`. `Run-Prepare.cmd` looks for it
and leaves a running build's Defender exclusions alone.

The steps:

1. **Folder lock.** The kit folder, `<work>`, the driver export and its `.zip`/`.sha256` are made
   writable by administrators only, before anything in them is used ([Folder lock](#folder-lock)).
   An earlier failed run's mounted images are discarded first.
2. **Profile and settings.** `scripts\KitProfile.ps1` resolves the hardware profile (`-Profile`,
   else the one whose `match` fits this PC, else `generic`). `scripts\KitSettings.ps1` reads the
   settings: the kit's defaults (`config\settings.defaults.json`) overlaid field by field by
   `config\settings.local.json`, or by the file given with `-Settings` in its place. A value you
   did not set for keyboard, formats, system locale, time zone and home location comes from the
   build PC: `Run-Build.cmd` reads the five before it elevates, as the account that started it,
   and hands them over as `-ThisPcLocale` (Base64 of a small JSON object). Without that parameter
   the defaults file's values stand, with a `[NOTE]`. The build prints each value with its source
   (`from this PC`, the file's name or `kit default`). The computer name is `-ComputerName`, else
   your settings', else the profile's, else random
   ([Your settings](../reference/CONFIGURATION.md#your-settings)).
3. **Preflight.** Every input is checked, and the build stops with the whole list if anything
   fails. It prints `Pre-flight checks:` and one `[OK  ]` or `[FAIL]` line per check:
   - the settings (an unknown or renamed field is an error) and the profile; the security
     template and the Start layout can be staged for these settings;
   - the source ISO: found, its SHA-256 listed in `config\source-iso.json` or your
     `config\source-iso.local.json` (for an unknown ISO the row prints the hash and the JSON to
     save as the local file), x64 media, and its language (read from `sources\lang.ini`) equal
     to `locale.uiLanguage`;
   - the curated drivers, each file against the harvest's `_Reports\curated-sha256.txt`;
   - the updates: an LCU, a .NET update and a Safe OS update are there, and every file is named
     as the Update Catalog names it, `<kb>_<SHA-1>`;
   - each baseline's `source.json`, and its zip in `<work>\baselines` against the SHA-256 pinned
     there; the data already imported from it (a `[NOTE]` when it is missing or stale: the build
     imports it anyway);
   - Python 3 is installed (the build imports the baselines with it);
   - the kit's own templates and payload files; `config\autounattend.xml` parses;
   - Controlled Folder Access is off; free space; `oscdimg` is found and signed by the pinned
     signer;
   - for a profile whose `productKey` is `firmware`: this PC's firmware key is a Pro key;
   - for a real build: `DriverExport.zip`, the build-tool installers (SHA-256) and a Git that can
     read the clone.

   A `[NOTE]` line tells you something without failing: folders not locked yet (`-Preflight`),
   a profile that does not fit this PC, drivers curated for another profile, updates that differ
   from `config\updates.json`, update pins older than 35 days (`pinned` in `config\updates.json`;
   over 70 days the line is a `[WARN]`), uncommitted kit changes that the kit bundle will not
   hold, a storage driver in the curated set.
4. **Baselines imported**, at every build (the build's own step list calls it step 0). For each
   baseline it runs `python -I -B scripts\Import-Baseline.py <id> --dest <work>\baselines
   --no-download --quiet`, which turns the pinned zip into data files in `<work>\baselines\<id>\`
   (registry records, security template, audit CSV, an index with hashes). It downloads nothing
   and takes seconds. Data already in that folder is never trusted: what is staged always comes
   from a zip with the pinned hash. Nothing of Microsoft's is in the repository; step 12 stages
   the data.
5. **Passwords.** One-time passwords are generated and written to `<work>\accounts.txt`
   ([Passwords](#passwords)).
6. **Media and the Pro image.** The ISO is mounted and copied to `<work>\media`. Only the
   **Professional** image is exported from `install.wim` (or `install.esd`) and mounted. Its
   language is checked again on the image itself.
7. **Updates**, in Microsoft's order: LCU → component cleanup (no `/ResetBase`, so updates stay
   uninstallable on the installed PC) → .NET. Each file's SHA-1 is checked against the one in its
   name right before it is applied; a mismatch stops the build. Only the target LCU belongs in
   `updates\lcu`: every package there must apply.
8. **WinRE** (the recovery environment, `Winre.wim` inside the image): the LCU first, for its
   servicing stack, then the Safe OS updates, then the curated drivers of class `Net`,
   `SCSIAdapter` and `HDC`, a cleanup (`/ResetBase /Defer`) and an export. A Safe OS update older
   than what is already applied is skipped and recorded in the manifest. Read back while WinRE is
   mounted: a curated storage driver it lacks fails the build (WinRE couldn't see the disk), a
   network driver only warns; WinRE's level is its own kernel's version (`winreVersion` in the
   manifest), because the LCU leaves only its servicing stack there. No Safe OS update applied and
   a kernel older than the LCU fails the build.
9. **Drivers.** Every curated INF is added, except those the profile's `drivers.skipInf` names.
10. **Apps.** The provisioned apps in `config\removal-manifest.json` are removed. An entry that
    matches a protected pattern aborts the build. Each removed app also gets its
    `AppxAllUserStore\Deprovisioned` key: offline removal does not always write it, and without
    it Windows provisions the app again.
11. **Features and registry.** The optional features in `config\image.json` are enabled or
    disabled (payload kept). `scripts\Set-KitRegistry.ps1 -Mode Offline` writes every registry
    value the kit sets: power values per the profile, options per the settings.
12. **Payload.** The first-boot setup's files go to `ProgramData\W11Kit` in the image:
    everything in `payload\`, `Set-KitRegistry.ps1`, the override files, `removal-manifest.json`,
    `image.json`, the baseline data as `Baselines\`, the profile as `profile.json`, the effective
    settings as `settings.json`, and `build-options.json` (`AdminName`, `UserName`,
    `ComputerName`, `BuiltinAdministratorName`, `BuiltinGuestName`, `Profile`, `KitRevision`,
    `TimeZone`, `UiLanguage`; no secrets). Two files are staged as the settings make them
    (`scripts\KitSettings.ps1`): `baseline-overrides.inf` gets the two built-in accounts' new
    names (drawn for this build unless your settings name them) and keeps its four Xbox service
    lines only with `options.gamingTweaks`; the Start layout keeps the Xbox pin only with that
    option. The Start layout and `.wslconfig` go into the default user profile.
13. **Read-back.** `scripts\Test-OfflineImage.ps1` reads the mounted image back with DISM and
    stops the build on any mismatch ([TESTING](TESTING.md#how-the-image-is-checked)). Report:
    `<work>\logs\verify-<stamp>.txt`.
14. **Commit and split.** The image is saved, exported with maximum compression and, when it is
    over 3.9 GB, split into `.swm` parts of at most 3800 MB (the stick stays FAT32). The first
    part is opened again and must hold exactly the one Pro image. The SHA-256 of every part goes
    into the manifest (`mediaHashes`).
15. **Boot media.** `boot.wim` is serviced, then the media's Setup files and boot manager are
    taken from it, then a second read-back ([Boot media](#boot-media)). Report:
    `<work>\logs\verify-boot-<stamp>.txt`.
16. **Build inputs** (a real build, unless `-NoBuildInputs`): the source ISO, updates, baseline
    zips, `DriverExport.zip`, `oscdimg`, the build-tool installers, a Git bundle of the kit and
    your untracked kit files are added as `BuildInputs\`, split into parts under 4 GB, each with
    its SHA-256 in `manifest.json`
    ([Build inputs in the ISO](../reference/BUILD-OPTIONS.md#build-inputs-in-the-iso)).
17. **Answer file and ISO.** `autounattend.xml` is written from `config\autounattend.xml`:
    accounts, computer name (or `*` for a random one), language, locales, time zone, the product
    key per the profile, and the first-logon commands that force both password changes and delete
    the cached answer files. `W11KIT-THIS-STICK.txt` (ISO name, build time, profile, kit revision, test or
    real; no secrets) goes in the media's top level. `oscdimg` writes the ISO (UDF, volume label
    `WIN11PRO_<ISOTAG>`, a test build's ending in `_TEST`, at most 32 characters). The ISO is hashed, the manifest copied next to it, and the ISO's name
    and SHA-256 appended to `accounts.txt`. The build's last lines are `ISO:`, `SHA256:`, the new
    names of the built-in accounts and where the passwords are.

**Product key.** A profile with `productKey` = `generic` gets the generic Windows 11 Pro
installation key (a default key that only selects the edition during Setup; it does not activate
Windows and is not a licence). `firmware` and `prompt` put no key in the answer file. No real
product key ever goes into an ISO.

**While it runs**, the build:

- keeps the PC awake (`SetThreadExecutionState`; no setting is changed);
- writes its console to `<work>\logs\build-<stamp>.txt`, so no step may print a secret, and
  deletes log files older than 30 days;
- adds Defender exclusions for `mount`, `mount-re`, `mount-boot` and `scratch` when the ASR rule
  *Block use of copied or impersonated system tools* is on, waits 15 seconds for them to apply,
  and removes them at the end ([Host settings that block a build](#host-settings-that-block-a-build)).

**When it fails** (`BUILD FAILED: ...`), the build discards every mounted image and deletes the
half-made media (with its answer file), the half-made image files, a half-written ISO and this
build's `accounts.txt`. The previous `accounts.txt` comes back.

## Boot media

An install stick holds two Windows systems. `sources\install.wim` (here split into `.swm` parts)
is the Windows that ends up on the PC. `sources\boot.wim` is the small Windows the stick itself
boots: **Windows PE** (image 1) and **Windows Setup** on top of it (image 2). In front of both
sits the **boot manager** (`efi\boot\bootx64.efi`): the first Windows program the firmware
starts, and the one Secure Boot checks.

The build updates both, following Microsoft's procedure,
[Update Windows installation media with Dynamic Update](https://learn.microsoft.com/windows/deployment/update/media-dynamic-update).

| What | What the build does | Why |
|---|---|---|
| `boot.wim`, every image | The LCU, the curated storage drivers, a cleanup (`/ResetBase /Defer`), an export into a fresh file with the same boot index | Setup runs with this month's fixes and can see the disk |
| Setup Dynamic Updates (`updates\setup`) | Expanded into `media\sources` before the next row | They carry Setup files newer than the source ISO's |
| Setup's files in `sources\` | Every file that the Setup image's `sources\` shares with the media is copied from the serviced Setup image | Setup fails when the two sides are at different levels |
| Boot manager, boot fonts, `boot.stl`, the ISO's UEFI boot image | Copied from the serviced Setup image (`Windows\Boot`) | The boot manager must be this month's (below) |

Details:

- **Each image must reach the install image's LCU level.** The build reads the package list of
  every `boot.wim` image and stops if its cumulative update level differs. Error `0x8007007e`
  from the LCU on WinRE or `boot.wim` is tolerated, as in Microsoft's sample; on `boot.wim` the
  LCU is then added a second time and must succeed.
- **Storage drivers.** The curated drivers of class `SCSIAdapter` and `HDC` (the selection WinRE
  gets, without `Net`) go into every `boot.wim` image. Without them Setup shows no disk on a PC
  whose storage controller has no inbox driver. With none in the curated set the step says
  `boot.wim: no storage drivers in the curated set: nothing to add to boot.wim`. A driver that
  DISM refuses is a warning, not a stop, and is recorded in the manifest (`skipped`); the names
  added to each image are in `bootWim.images[].storageDrivers`.
- **Why every shared Setup file.** Microsoft's procedure names `setup.exe` and `setuphost.exe`
  and relies on a Setup Dynamic Update of the same level for the rest. There is not always one.
  With only those two files replaced, Setup stops seconds in with `0xC1900100`, right after
  *Determine if the expected version of Setup Platform has been loaded* in `setupact.log`.
- **Which boot manager.** By default the `_EX` files: `bootmgfw_EX.efi`, `bootmgr_EX.efi`,
  `efisys_EX.bin` and the `FONTS_EX` fonts, signed by **Windows UEFI CA 2023**.
  `-Use2011BootManager` takes the 2011-signed files from the same serviced image, for a PC whose
  firmware does not trust the 2023 CA yet.
- **Read-back.** `Test-OfflineImage.ps1 -BootMedia` checks that the Setup image holds the LCU
  and the storage drivers that were added (row `Storage drivers in the Setup image`),
  and that the media's `setup.exe`, `setuphost.exe`, every other shared Setup file and
  `bootx64.efi` are byte for byte the files inside it. Last, the build reads the **embedded**
  signer of `bootx64.efi` (`X509Certificate.CreateFromSignedFile`) and stops unless it is
  Windows UEFI CA 2023. `Get-AuthenticodeSignature` is no use here: for Windows boot files it
  returns the catalog signature.
- **Integrity.** Every WIM the build saves, exports or splits carries an integrity table
  (`-CheckIntegrity`), so DISM notices a damaged file the next time it opens it.

**Why the boot manager must be this month's.** Secure Boot lets the firmware start only boot
managers signed by a certificate it trusts. Old boot managers with known holes are signed too, so
Microsoft is closing them out in two ways
([KB5025885](https://support.microsoft.com/help/5025885)):

- a new signing certificate, Windows UEFI CA 2023 (the 2011 one is valid only until 2026-10-19 and can
  then be revoked);
- a **Secure Version Number (SVN)**: a counter inside the boot manager that a security update
  raises. Once a PC has recorded the new number in its firmware, it refuses every boot manager
  with a lower one, including the one on a stick written earlier.

Every build takes the boot manager from the `boot.wim` it has just updated, and the manifest
records its version (`bootManagerVersion`). What is left for the user is to write the stick again
after every monthly build ([Rebuild the ISO](../MONTHLY.md#rebuild-the-iso)).

**Cost.** The LCU is applied four times (install image, WinRE, two `boot.wim` images). No more
free space is needed: `boot.wim` is serviced after the install image has been committed and its
mount and scratch space freed.

## Folder lock

The build runs elevated and runs, applies or packs whatever is in the kit folder and `<work>`.
Inherited from `C:\`, a new folder there is writable by every signed-in user. A standard user,
or malware in the daily account, could then change what the next build runs as administrator or
puts into the image. So `Build-Iso.ps1` locks the kit folder, `<work>`, the driver export and
`DriverExport.zip` with its `.sha256` before it uses anything in them (`scripts\KitAcl.ps1`).

What the lock sets:

- owner `BUILTIN\Administrators`; SYSTEM and Administrators Full, `BUILTIN\Users` Read & Execute;
  not inherited from above;
- every file and folder below inherits exactly that: explicit entries are removed and owners set
  to Administrators.

How it works:

- **One top-down walk per folder.** It opens each item without following links
  (`FILE_FLAG_OPEN_REPARSE_POINT`) and sets the security on that handle, a folder before its
  contents. It never uses `icacls /T` or `Set-Acl`, which may follow a junction planted inside.
- **A junction or symbolic link inside is refused**, never followed or changed: the build stops
  with its path. Remove it and build again.
- **Folders inside folders.** `<work>` is inside the kit folder and the driver export inside
  `<work>`. Each gets its own walk, outer folder first, and a walk leaves out the folders that
  have their own. So the kit's walk never enters `work\`, where a build mounts a Windows image,
  and nothing is walked twice.
- **Read back by SID.** Every item's owner must be SYSTEM, Administrators, TrustedInstaller or a
  member of the local Administrators group. No other SID may hold a write, delete,
  change-permissions or take-ownership right. Any problem stops the build.
- **Refused paths.** The lock never touches a drive root, a network path, the Windows, Program
  Files or ProgramData folders, `C:\Users` or a user profile folder itself.

`-Preflight` only reports (`not locked yet (the build locks them first)`). Folders the kit creates
itself (`Run-Prepare.cmd`, the launcher's downloads, the harvest, the VM test, a restore) are
created locked.

**The folder above.** The lock cannot cover the folder *above* a locked folder: whoever may
change that one can move the locked folder aside and put another in its place. Directly under
`C:\` only administrators can. Anywhere else (a kit inside a user profile) the build prints a
warning that names the folder and the account. Keep the kit in a folder of its own directly under
the drive.

What else protects the build's inputs:

| What | Protection |
|---|---|
| Elevated `git` on the kit | `safe.directory` is that clone only, never `*`. The launcher's pull offer passes none, so Git refuses a clone that is not locked yet |
| Updates | Each file's SHA-1 is checked against the one in its Update Catalog name right before it is applied. DISM checks the packages' signatures |
| Baseline zips | SHA-256 pinned in each `source.json`; the importer refuses anything else. Every build imports again from the checked zip, and the read-back compares the staged data with the import's index |
| Curated drivers | The harvest writes the SHA-256 of every `_Curated` file; the build refuses a changed, added or missing file |
| `oscdimg.exe` | Used only if validly signed by exactly the ADK's pinned signer (`config\installers.json`), wherever it is found |
| Build-tool installers | SHA-256 pinned, copied to a private temp folder, hashed again, exact Authenticode signer |
| `accounts.txt` | Created with an ACL for SYSTEM and Administrators only, in the create call itself |
| The VM test's copy | In the locked `vmtest` folder, deleted when the test ends |

Not covered:

- **The source ISO may stay in a user's `Downloads`.** It is hashed at preflight and mounted
  later, so its owner could swap it in between. A real build hashes it again while copying it
  into `BuildInputs` and stops on a change, but the image was made from the earlier read.
- **Everyone can still read the folders**, including the ISOs, which hold the one-time passwords
  only obfuscated ([Known risks accepted](../reference/SECURITY-BASELINE.md#known-risks-accepted)).

What the lock means for a user (administrator terminal for `git pull` and for editing
`config\settings.local.json`) is in the guide and in
[TROUBLESHOOTING](../TROUBLESHOOTING.md#preparing-and-building).

## Passwords

What a user needs to know is in
[One-time passwords](../reference/BUILD-OPTIONS.md#one-time-passwords). This is how they are made.

**Generation** (`New-AccountPassword` in `Build-Iso.ps1`):

- 20 characters from an alphabet of 52: 22 upper-case letters, 22 lower-case letters, 8 digits.
- Left out: the look-alikes `0 O o 1 l I`; `Y y Z z`, which swap places on a German keyboard; and
  every symbol, whose keys move between layouts.
- Each character is drawn from the operating system's cryptographic random number generator by
  rejection sampling, so there is no modulo bias.
- The password policy asks for upper case, lower case and a digit, and no account name inside.
  A draw that misses is thrown away **whole** and drawn again. That keeps every valid password
  equally likely: about 114 bits (52^20, less the few per cent of draws that are rejected).

**In the ISO.** The answer file carries both passwords in Setup's own encoding
(Base64 of UTF-16), which is obfuscation only. That is why both accounts must choose a new
password at first sign-in, and why the last first-logon command deletes the cached answer files
from `Windows\Panther`.

**The accounts file:**

1. A real build writes `<work>\accounts.txt`; a test build (`-TestBuild`) writes
   `<work>\test-accounts.txt` and so never touches a real build's file.
2. The file is created readable by SYSTEM and Administrators only. The ACL is part of the create
   call, so there is no moment with the folder's inherited permissions. The passwords never reach
   the console or the build log.
3. Its first line names the profile and the build stamp. When the ISO is done, the build appends
   the **last line**, `ISO: <file name>  SHA-256 <hash>`. A file without that line belongs to a
   build that failed: its passwords are in no ISO.
4. A real build never overwrites an older file: it renames it to
   `accounts-<yyyyMMdd-HHmmss>.txt`, the time the old file was last written.
5. A failed build deletes its own file and renames the previous one back to `accounts.txt`.

With `-EncryptAccountsTo` the file is `accounts.txt.cms`, and no plain-text copy is written
([Unattended builds and encrypted passwords](MAINTAINING.md#unattended-builds-and-encrypted-passwords)).

## Self-hosting

Requirement: after a reinstall from this kit, the PC must be able to restore the kit and run
`Run-Build.cmd` to produce its next ISO, with no policy changed by hand. The build PC is often the
PC you reinstall, and a reinstall wipes it.

What makes that work:

- **The build inputs ride in the ISO.** `Restore-BuildInputs.cmd` (in the stick's `BuildInputs`
  folder) joins the parts, checks every SHA-256 and puts the files back into `C:\W11Kit\work`.
  The baseline zips come back as zips (`work\baselines`); the next build imports them, so the
  restore has nothing to run for them.
- **The kit comes back as a normal Git clone.** `git clone` refuses a folder that is not empty,
  and `C:\W11Kit` already holds `work\`. So the script clones the bundle without files into a
  temporary folder, moves its `.git` into `C:\W11Kit` and checks the files out there. Your
  untracked kit files (`config\settings.local.json`, `config\source-iso.local.json`, changed or
  new `profiles\<id>\profile.json`) go back to the same paths.
- **The build tools are not in the image.** The restore offers to install Git from the restored
  installer; `Run-Prepare.cmd` or the first `Run-Build.cmd` installs the rest
  ([The build tools](../reference/BUILD-OPTIONS.md#the-build-tools)).
- **Nothing in the image blocks a build**: the next section.

The validator's **Self-hosting** rows catch a regression on the installed PC: Controlled Folder
Access on is a FAIL, the ASR prevalence rule in Block or Warn is a WARN. Its *No Defender
exclusions left behind* row WARNs when an interrupted build left its exclusions.

This path is not proven yet on real hardware ([Status](TESTING.md#status)).

## Host settings that block a build

Settings a build PC may have, from its own policy, an organisation or a hardening tool, and what
the kit does about each. The image sets none of the blocking ones.

| Setting on the build PC | What it breaks | What the kit does |
|---|---|---|
| Defender **Controlled Folder Access** on (Block) | DISM cannot service the mounted image | `Run-Prepare.cmd` and preflight refuse, with how to turn it off. The kit never changes Defender policy |
| ASR rule *Block executable files unless they meet a prevalence, age or trusted list criterion* (`01443614-…`) in Block or Warn | Even reading a self-built or rare executable fails with *Access denied* | `Run-Prepare.cmd` reports BLOCK (Warn mode: WARN). Set the rule to Audit or Not configured |
| ASR rule *Block use of copied or impersonated system tools* (`c0033c00-…`) in Block or Warn | `Add-WindowsPackage` fails with `0x80070005`: the servicing stack runs from the mounted image | The build excludes its own four work folders while it runs. The image has this rule on |
| **Administrator protection** (elevation runs as a hidden `ADMIN_` account) | No winget, another user profile, no `\\wsl.localhost` paths | Build tools come from pinned installers, never winget, and the ISO is searched in every profile's `Downloads`. The image turns it off (an [override](../reference/SECURITY-BASELINE.md#overrides)) |
| A policy that blocks `.ps1` files | Machine policy beats `-ExecutionPolicy Bypass` | Every launcher loads its script as a scriptblock, so no host policy is changed |
| The kit on a network or `\\wsl.localhost` path | The elevated account may not see it | `Run-Prepare.cmd` warns: copy the kit to `C:\W11Kit` |
| Windows Home, Windows older than 24H2, or a PC that is not x64 | No Hyper-V; an older DISM cannot service the image | `Run-Prepare.cmd` and the build refuse |

A second hardening tool on the installed PC can set the first two rows:
[Other hardening tools](../reference/SECURITY-BASELINE.md#other-hardening-tools).

## Kit scripts

"Elevated" means the script needs an administrator; the `.cmd` launchers ask for it themselves
([The launchers](../reference/BUILD-OPTIONS.md#the-launchers)). The launchers load each script as
a scriptblock and pass `-KitRoot`, because `$PSScriptRoot` is empty then.

| Script | Runs on | Elevated | Does |
|---|---|---|---|
| `Run-Prepare.cmd` → `scripts\Prepare-BuildPc.ps1` | build PC | yes | Checks the PC and offers to install the build tools and Hyper-V. `-ForBuild` is the mode `Run-Build.cmd` uses |
| `scripts\Install-BuildTools.ps1` | build PC | yes (`-Check`: no) | Installs the missing build tools from the installers pinned in `config\installers.json`, SHA-256 and signer checked |
| `New-Profile.cmd` → `scripts\New-HardwareProfile.ps1` | the PC you reinstall | by the launcher (the script needs none) | Writes `profiles\<id>\profile.json` from the running Windows |
| `Run-Harvest.cmd` → `scripts\Invoke-DriverHarvest.ps1` | the PC you reinstall | yes | Exports the drivers and curates the set for a profile ([DRIVERS](../reference/DRIVERS.md#harvest)) |
| `scripts\New-DriverInventory.ps1` | any PC | no | Device-to-driver inventory; called by the harvest |
| `scripts\KitProfile.ps1` | (library) | | Resolves and validates profiles, for the build and the harvest |
| `scripts\KitSettings.ps1` | (library) | | Reads and checks the settings, draws the built-in accounts' names, and makes the settings-dependent files the build stages |
| `scripts\KitAcl.ps1` | (library) | | The [folder lock](#folder-lock) and its read-back |
| `scripts\Invoke-KitLauncher.ps1` | (library) | | The launchers' common part: elevation, argument passing, and `Run-Build.cmd`'s questions |
| `Run-Build.cmd` → `scripts\Build-Iso.ps1` | build PC | yes (`-Preflight`: no) | The build ([Build steps](#build-steps)) |
| `scripts\Set-KitRegistry.ps1` | build PC and installed PC | yes | Every registry value the kit sets, offline and online; `-ListOnly` prints them |
| `scripts\Test-OfflineImage.ps1` | build PC | yes | DISM read-back of the mounted image; with `-BootMedia`, of the boot side |
| `scripts\Get-Updates.py` | build PC (Python) | no | Fetches the updates pinned in `config\updates.json` from the Update Catalog; `--list`, `--discover [--write]` |
| `scripts\Get-Installers.py` | build PC (Python) | no | Fetches the build-tool installers the ISO carries, SHA-256 checked |
| `scripts\Get-Baselines.py` | build PC (Python) | no | Fetches the pinned baseline zips into `<work>\baselines`, SHA-256 checked, and imports them; `--zip <file>` takes a copy you already have |
| `scripts\Import-Baseline.py` | build PC (Python) | no | Turns one pinned Microsoft baseline zip into data in `<work>\baselines\<id>`; `--zip`, `--no-download`, `--check`. The build runs it at every build |
| `scripts\kitfetch.py` | (library) | | Download helpers for the Python scripts |
| `Run-VmTest.cmd` → `scripts\Test-IsoInHyperV.ps1` | build PC with Hyper-V | yes | The VM test ([TESTING](TESTING.md#the-hyper-v-vm-test)) |
| `scripts\Restore-BuildInputs.cmd` / `.ps1` | installed PC, from the stick | yes | Restores the build inputs and the kit ([Self-hosting](#self-hosting)) |
| `payload\PostInstall.ps1` | installed PC, once | yes (autologon) | First-boot setup ([Install and first boot](../reference/CONFIGURATION.md#install-and-first-boot)) |
| `payload\Apply-Policy.ps1` | installed PC | yes | Baselines, overrides and kit policies into local Group Policy with Windows' own tools, and the read-back ([How the baselines are applied](../reference/SECURITY-BASELINE.md#how-the-baselines-are-applied)) |
| `payload\Merge-AuditPolicy.ps1` | installed PC | yes | Builds the one merged audit policy file |
| `payload\New-AdminBrowserPolicy.ps1` | installed PC | yes | The AppLocker policy that keeps administrators from running browsers |
| `payload\Test-InstalledPc.ps1` (`Validate-Pc.cmd`) | installed PC | yes (fewer rows without) | The validator |
| `payload\Enable-BitLockerLocal.ps1` (`Enable-BitLocker.cmd`) | installed PC | yes | BitLocker with a recovery key you keep yourself |
| `dev/Test-KitSyntax.sh` | a contributor's WSL | no | The [syntax gate](TESTING.md#syntax-gate) |
| `dev/Test-Profiles.py` | any Python | no | Checks every `profile.json` against the rules of `KitProfile.ps1` |
| `dev/Test-DocLinks.py` | any Python | no | Checks every relative Markdown link and `#anchor`; part of the syntax gate |
| `dev/Export-Public.sh` | a maintainer's shell | no | [The public export](MAINTAINING.md#the-public-export) |

## Repository layout

```
Run-Prepare.cmd  New-Profile.cmd  Run-Harvest.cmd  Run-Build.cmd  Run-VmTest.cmd
           the launchers: they elevate themselves and work where a policy blocks .ps1 files
profiles/  hardware profiles: legion-t5 (the reference), generic, and yours
scripts/   what a user's build runs: Prepare-BuildPc, Install-BuildTools, New-HardwareProfile,
           KitProfile, KitSettings, Invoke-DriverHarvest, New-DriverInventory, Build-Iso,
           Set-KitRegistry, Test-OfflineImage, Test-IsoInHyperV, Get-Updates.py,
           Get-Baselines.py, Get-Installers.py, Import-Baseline.py, kitfetch.py,
           Restore-BuildInputs, KitAcl, Invoke-KitLauncher
payload/   what the image carries in C:\ProgramData\W11Kit: PostInstall, Apply-Policy,
           Merge-AuditPolicy, New-AdminBrowserPolicy, Test-InstalledPc (the validator),
           Enable-BitLockerLocal, their two launchers, Sysmon-Config.xml
config/    settings.defaults.json   the kit's defaults (yours: settings.local.json, untracked)
           source-iso.json          accepted source ISOs (yours: source-iso.local.json, untracked)
           updates.json             the month's KBs, the date they were pinned, discover rules
           installers.json          the build tools: version, URL, SHA-256, signer
           baselines/               baselines.json and one source.json per baseline (pins only)
           baseline-overrides.txt / .inf / -audit.csv   the kit's overrides
           autounattend.xml         the answer file template
           removal-manifest.json  image.json  LayoutModification.json  wslconfig
           vm-expected.json         validator rows expected to fail in a VM
dev/       maintainer tooling: Test-KitSyntax.sh, Test-Profiles.py, Test-Units.py, Test-DocLinks.py,
           Export-Public.sh
docs/      GUIDE, AFTER-INSTALL, MONTHLY, TROUBLESHOOTING, GLOSSARY; reference/; dev/
.github/   the lint workflow, issue and pull-request templates
work/      NOT in the repository (git ignores it): the work folder of a build PC
```

> [!CAUTION]
> Never run `git clean -x` or `git clean -X` in the kit folder. Git ignores `work\`, so those
> commands delete the downloaded updates, your drivers, the finished ISOs and the passwords file.
