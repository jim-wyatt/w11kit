# Build options

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

Every launcher, switch, input and output of the build and the VM test. The step-by-step path is
the [guide](../GUIDE.md); how the build works inside is in
[Build internals](../dev/BUILD-INTERNALS.md).

## The work folder

The kit lives in one folder, `C:\W11Kit`. Everything it downloads or makes is in its
[work folder](../GLOSSARY.md#work-folder), `C:\W11Kit\work`. The one exception: the Windows source
ISO may stay in your `Downloads` folder.

```text
C:\W11Kit\                       the kit (a Git clone)
  config\settings.local.json     your settings (you create it; Git ignores it)
  config\source-iso.local.json   your own accepted source ISO (optional; Git ignores it)
  profiles\<id>\profile.json     your hardware profile
  work\                          the work folder. Git ignores it.
    updates\                     this month's Windows updates (lcu, dotnet, safeos, setup)
    baselines\                   Microsoft's security baseline zips and the data imported from them
    installers\  tools\          the build tools' installers; a restored oscdimg
    DriverExport\                the drivers harvested from your PC (_Curated, _Reports, ...)
    DriverExport.zip (+ .sha256) the same as one archive
    source\                      the Windows source ISO, when Restore-BuildInputs put it back
    logs\                        build logs, DISM logs, install logs
    Win11Pro-...iso (+ .sha256, .manifest.json)   the ISOs you built
    accounts.txt                 the one-time passwords of the last real build (administrators only)
    vmtest\                      the VM test's files and results
    mount\ mount-re\ mount-boot\ scratch\ media\   only while a build runs
```

After the first build only administrators can change `C:\W11Kit` and everything in it; other
accounts can read it. That is the [folder lock](../GLOSSARY.md#folder-lock)
([how it works](../dev/BUILD-INTERNALS.md#folder-lock)). `-Preflight` only reports whether the
folders are locked.

**Another place.** Every launcher takes `-WorkRoot <folder>`, for example
`C:\W11Kit\Run-Build.cmd -WorkRoot D:\W11Work`. Give `Run-Prepare.cmd`, `Run-Harvest.cmd` and
`Run-VmTest.cmd` the same one. A kit in another folder than `C:\W11Kit` has its `work\` there.

**Cleaning up.** What you can delete piece by piece is in
[Freeing space](../TROUBLESHOOTING.md#freeing-space). To start over, delete the whole work folder:
the next build offers to download the updates (about 5 GB) and the security baselines again, and
to harvest the drivers again.

> [!CAUTION]
> `rmdir /s /q C:\W11Kit\work` also deletes the passwords file (`accounts.txt`) and every ISO you
> built. Save what you still need first.

> [!CAUTION]
> Never run `git clean -x` or `git clean -X` in `C:\W11Kit`. They delete what Git ignores, and Git
> ignores `work\` and your settings: updates, drivers, ISOs and the passwords file would be gone.
> `git status`, `git pull` and plain `git clean` never touch them.

## Run-Prepare.cmd

Checks that this PC can build, then offers to install what is missing. Safe to run again.

In a Command Prompt:

```text
C:\W11Kit\Run-Prepare.cmd                 check, then ask before installing what is missing
C:\W11Kit\Run-Prepare.cmd -Yes            install what is missing without asking
C:\W11Kit\Run-Prepare.cmd -Check          report only, change nothing
C:\W11Kit\Run-Prepare.cmd -SkipHyperV     don't offer Hyper-V (you will not run the VM test)
```

| Check | Result when it isn't met |
|---|---|
| Windows 11 Pro, Enterprise or Education | `BLOCK`. Home can't run the Hyper-V VM test and isn't supported as a build PC |
| Windows build 26100 (24H2) or later | `BLOCK`. An older Windows can't service a 26H2 image |
| A 64-bit Intel or AMD processor (x64) | `BLOCK`. The kit builds on an x64 PC and makes x64 images only; an ARM64 PC or ISO is refused |
| Not managed by an employer or school (no domain, no Microsoft Entra join, no device management enrolment) | `WARN`. The kit sets local policy, folder permissions and Defender exclusions and installs tools, which can fight the management: build on a PC of your own |
| Virtualization on in the BIOS | `WARN`, with the setting to change (AMD: SVM Mode; Intel: VT-x). The build works without it; the VM test doesn't |
| Hyper-V | Offered with the build tools. Restart Windows when it says so |
| Defender Controlled Folder Access off | `BLOCK`, with how to turn it off. It blocks DISM, the Windows tool that changes the image |
| Defender ASR rule *Block executable files unless they meet a prevalence, age or trusted list criterion* not in Block | `BLOCK`. The rule blocks even reading the tools the build runs |
| 80 GB free on the system drive and on the work folder's drive | `BLOCK`. See [Disk space](#disk-space) |
| The kit on a local path | `WARN` for a network or `\\wsl.localhost\...` path. Copy the kit to `C:\W11Kit` |
| The build tools | `WARN`, then `Install them now? [Y/n]`. An install that fails is a `FAIL`, with its log in `C:\W11Kit\work\logs` |

`Run-Prepare.cmd` never changes Defender's protection settings (Controlled Folder Access, the ASR
rules): you do that. It does clean up two leftovers of an interrupted run, as every build does at
its start: a copy of the VM test's ISO that was left behind, and Defender exclusions a stopped
build left for its own work folders. `-Check` only reports them.

It ends with `READY: this PC can build the ISO.`,
`READY after a restart: restart Windows to finish enabling Hyper-V.` or
`NOT READY: <n> item(s) block the build (marked BLOCK or FAIL above).` When the PC is ready, a
short list headed `Next, for the first build:` names the next two steps: the Windows ISO, then
`Run-Build.cmd`.

## The build tools

A PC needs three tools to build the ISO. The installed image has none of them: they are installed
only on a PC that builds, and only after you say yes.

| Tool | Why the build needs it | Installed from |
|---|---|---|
| Git for Windows | A real build puts a copy of the kit (a Git bundle) into the ISO, so you can get the kit back after a reinstall | The official release on GitHub |
| Python 3 | Every build imports Microsoft's security baselines with it. The download scripts need it too | python.org, for all users |
| Windows ADK Deployment Tools | `oscdimg`, the program that writes the ISO | Microsoft's ADK installer (only this one feature, about 100 MB) |
| Hyper-V (optional) | The VM test. Needs a restart | A Windows feature; `Run-Prepare.cmd` offers it, `Run-Build.cmd` doesn't |

How they are installed (`scripts\Install-BuildTools.ps1`):

1. Each installer is pinned in [config/installers.json](../../config/installers.json): version,
   download address, SHA-256 hash and the expected signer.
2. The kit uses the installer already in `C:\W11Kit\work\installers` (a restored PC has them
   there) or downloads it from the official address.
3. It copies the file to a private folder and checks the copy: the hash must match the pin, and
   the file's signature must be valid and from exactly the pinned signer. Otherwise nothing runs.
4. It installs silently for all users, writes a log to
   `C:\W11Kit\work\logs\install-<tool>-<time>.log` and checks that the tool works.

A tool that is already installed, in any version, is left alone. The kit never uses winget for
this. To remove the tools after a build: Settings → Apps → Installed apps. The next build offers
to install them again. Moving a pin to a newer version is a maintainer task:
[Updating the build tools](../dev/MAINTAINING.md#updating-the-build-tools).

## Inputs

| Input | Where the build looks | How it gets there |
|---|---|---|
| Windows source ISO | `C:\W11Kit\work\source`, then every user's `Downloads` folder, for `Windows11*.iso` or `Win11*.iso` (the newest wins); or `-SourceIso <file>` | You download it once in a browser ([guide, step 4](../GUIDE.md#step-4-download-windows)). Microsoft's page can't be scripted |
| Windows updates | `C:\W11Kit\work\updates\lcu`, `dotnet`, `safeos`, `setup` | `Run-Build.cmd` offers the download. By hand: `py C:\W11Kit\scripts\Get-Updates.py` |
| Microsoft's security baselines (two zip files) | `C:\W11Kit\work\baselines` | `Run-Build.cmd` offers the download with the updates. By hand: `py C:\W11Kit\scripts\Get-Baselines.py` ([how they are used](SECURITY-BASELINE.md#how-the-baselines-are-applied)) |
| Build-tool installers (Git, Python) | `C:\W11Kit\work\installers` | Only for a build that carries its [build inputs](#build-inputs-in-the-iso). `Run-Build.cmd` offers the download; by hand: `py C:\W11Kit\scripts\Get-Installers.py` |
| Hardware profile | `C:\W11Kit\profiles\<id>\profile.json` | `Run-Build.cmd` offers to make it. By hand: `C:\W11Kit\New-Profile.cmd` ([PROFILES](PROFILES.md)) |
| Curated drivers | `C:\W11Kit\work\DriverExport\_Curated` | `Run-Build.cmd` offers the harvest. By hand: `C:\W11Kit\Run-Harvest.cmd` ([DRIVERS](DRIVERS.md#harvest)) |
| Your settings | `C:\W11Kit\config\settings.local.json` (optional) | You write it ([CONFIGURATION](CONFIGURATION.md#your-settings)) |

How each input is checked:

- **Source ISO.** Its SHA-256 hash must be listed in
  [config/source-iso.json](../../config/source-iso.json) (the kit's list) or in your own
  `config\source-iso.local.json`. For an unknown ISO, preflight prints the file's hash and the
  exact text to put into the local file
  ([guide](../GUIDE.md#if-the-kit-doesnt-know-your-iso)). Its language must be the one in
  `locale.uiLanguage` ([Another language](CONFIGURATION.md#another-language)).
- **Updates.** [config/updates.json](../../config/updates.json) lists the update numbers (KB) for
  this month. `Get-Updates.py` finds exactly one Microsoft Update Catalog entry per KB, downloads
  it from Microsoft and removes every other file from the four folders, because the build applies
  everything it finds there. Microsoft puts each file's SHA-1 hash into its name; the build checks
  that hash right before it applies the file.
- **Old update list.** `config\updates.json` records the day its list was last moved (`pinned`).
  Preflight prints a `[NOTE]` when the list is older than 35 days and a `[WARN]` when it is older
  than 70 days; `Run-Build.cmd` then asks `Build with these old updates anyway? [y/N]` before it
  builds. Update the kit to get the current list ([Updating the kit](../MONTHLY.md#updating-the-kit)).
- **Baselines.** Each zip's SHA-256 hash must match the pin in `config\baselines\<id>\source.json`.
  Every build then imports the baselines again from those two zips, with Python, into
  `C:\W11Kit\work\baselines\<id>`: what goes into the image always comes from a zip with the
  pinned hash.
- **Curated drivers.** The harvest records the SHA-256 hash of every curated file. The build stops
  if a file was changed, added or removed since.

The work folder exists only on the build PC, and a reinstall of that PC erases it. A real build
therefore carries its inputs in the ISO ([below](#build-inputs-in-the-iso)).

## The launchers

Double-click a launcher, or run it from a Command Prompt to pass options. Each one asks for
administrator rights with a [UAC prompt](../GLOSSARY.md#uac-and-the-uac-prompt), which closes
itself after about 2 minutes: be at the PC.

| Launcher | What it does | Elevates |
|---|---|---|
| `C:\W11Kit\Run-Prepare.cmd` | Checks the build PC and offers the build tools and Hyper-V ([above](#run-preparecmd)) | Yes |
| `C:\W11Kit\New-Profile.cmd` | Writes a hardware profile for this PC ([PROFILES](PROFILES.md#making-a-profile-for-your-pc)) | Yes |
| `C:\W11Kit\Run-Harvest.cmd` | Collects this PC's drivers ([DRIVERS](DRIVERS.md#harvest)) | Yes |
| `C:\W11Kit\Run-Build.cmd` | Builds the ISO ([options](#build-options), [questions](#what-run-buildcmd-asks)) | Yes |
| `C:\W11Kit\Run-VmTest.cmd` | Installs the ISO in a Hyper-V virtual machine and grades the result ([options](#vm-test-options)) | Yes |
| `C:\W11Kit\Collect-Diagnostics.cmd` | Collects what a bug report needs into one zip on your Desktop, with the computer name, account names, serial numbers, MAC, e-mail and IP addresses and SIDs replaced, and in your settings file the expected apps and the local DNS zones. It never reads the passwords files. Look inside the zip before you attach it | No |
| `BuildInputs\Restore-BuildInputs.cmd` (on the stick) | Puts the kit and its inputs back on the installed PC ([below](#build-inputs-in-the-iso)) | Yes |
| `C:\ProgramData\W11Kit\Validate-Pc.cmd` (the *Validate PC* shortcut) | Checks the installed PC and writes the report | Yes |
| `C:\ProgramData\W11Kit\Enable-BitLocker.cmd` (the *Enable BitLocker (local key)* shortcut) | Turns on BitLocker with a recovery key you keep ([CONFIGURATION](CONFIGURATION.md#bitlocker)) | Yes |

Put double quotes around a path with spaces: `-SourceIso "D:\My ISOs\Win11.iso"`. The launchers
work even where a policy blocks PowerShell script files.

## Build options

In a Command Prompt:

```text
C:\W11Kit\Run-Build.cmd -Preflight              check everything, change nothing
C:\W11Kit\Run-Build.cmd                         the real build
C:\W11Kit\Run-Build.cmd -TestBuild              a test build, for the VM test only
```

| Option | Default | Meaning |
|---|---|---|
| `-Profile <id>` | The profile whose `match` fits this PC, else `generic` | The hardware profile to build for ([PROFILES](PROFILES.md)). The build prints which one it uses and why |
| `-Preflight` | Off | Check every input and stop. Asks nothing and changes nothing |
| `-TestBuild` | Off | A [test build](../GLOSSARY.md#test-build-and-real-build): no build inputs, passwords in `test-accounts.txt`, ISO named `Win11Pro-<isoTag>-TEST-...`, volume label ending in `_TEST`. Never install it on a real PC (the validator's *Image kind* row warns) |
| `-Settings <file>` | `config\settings.local.json`, when it exists | Use this file as your settings instead. Like `settings.local.json` it holds only the fields you change and is laid over the kit's defaults ([CONFIGURATION](CONFIGURATION.md#your-settings)). A relative path is tried as typed, then from the kit folder |
| `-ComputerName <name>` | `computerName` in your settings, then the profile's; if both are `null`, Windows picks a random name | The PC's name: 1 to 15 letters, digits or hyphens, not all digits |
| `-SourceIso <file>` | See [Inputs](#inputs) | The Windows source ISO to use |
| `-WorkRoot <folder>` | `C:\W11Kit\work` | The work folder. Its drive needs the free space |
| `-NoBuildInputs` | Carried in a real build | Leave the [build inputs](#build-inputs-in-the-iso) out. The ISO is then about 10 GB instead of 28 GB, and the installed PC can't rebuild without downloads |
| `-EncryptAccountsTo <file.cer>` | Off | Write the one-time passwords encrypted to your certificate, with no plain-text copy. For builds nobody watches ([Unattended builds](../dev/MAINTAINING.md#unattended-builds-and-encrypted-passwords)) |
| `-PauseDefenderProtection` | Off | Pause Defender's Controlled Folder Access and ASR prevalence rule while the build runs, and restore them at the end. Needed on a PC installed from the kit; `Run-Build.cmd` asks and passes it ([The build PC](CONFIGURATION.md#the-build-pc)) |
| `-Use2011BootManager` | Off | For a PC whose firmware doesn't trust Microsoft's 2023 certificate yet ([Secure Boot 2023 certificates](SECURITY-BASELINE.md#secure-boot-2023-certificates)) |

`-KitRoot` and `-ThisPcLocale` are passed by the launcher; you never type them. (`-ThisPcLocale`
carries this PC's keyboard, formats, time zone and country into the build:
[your settings](CONFIGURATION.md#your-settings).) Account names, time zone, language and the other
choices are not switches: they are your settings.

## What Run-Build.cmd asks

`Run-Build.cmd` asks up to eight questions before and after the build, each only when it applies
and at most once, in this order. The build itself (`scripts\Build-Iso.ps1`) asks nothing. With
`-Preflight` nothing is asked at all, apart from the UAC prompt.

| # | Question | When | If you say no |
|---|---|---|---|
| 1 | The UAC prompt | Always | Nothing runs |
| 2 | `Update the kit to its newest signed release first? [y/N]` | The kit is a Git clone and Git is installed | The kit stays as it is (the default: press Enter). With `y`: the newest release, only if it is signed by a key in the kit's own `config\release-signers` ([verifying a release](../../SECURITY.md#verifying-a-release)); then `Run-Build.cmd` stops, to be started again on the new release |
| 3 | `Build with these old updates anyway? [y/N]` | The list in `config\updates.json` is older than 70 days | `Stopped: nothing was built.` (the default), so you can update the kit |
| 4 | `Install them now? [Y/n]` | Git, Python or the ADK tools are missing | The build starts; preflight says what it still needs |
| 5 | `Download this month's Windows updates (~5 GB), Microsoft's security baselines (~2 MB) and the Git and Python installers (~100 MB) now? [Y/n]` | A pinned file isn't in the work folder. The question names only what is missing | The build starts; preflight says what is missing |
| 6 | `No hardware profile for this PC yet. Make one now from this PC? [Y/n]` | No `-Profile` was given and no profile fits this PC, so the build would use `generic`. Not asked on a virtual machine | The build uses `generic` |
| 7 | `Collect this PC's drivers now? (Only if this is the PC you will reinstall.) [Y/n]` | `C:\W11Kit\work\DriverExport\_Curated` holds no driver. Not asked for a profile of another PC model | Preflight stops at `Curated drivers`: the build needs the drivers |
| 8 | `Test this ISO in a virtual machine now (about 30 minutes)? [Y/n]` | The build succeeded and Hyper-V is enabled | Run `C:\W11Kit\Run-VmTest.cmd` later |

Before the first question the window shows a short notice: installing the ISO erases a disk, you
need your own licence and accept Microsoft's licence terms by building, the ISO is private, no
warranty.

Question 6 becomes a short list when the kit has profiles it never takes by itself (a profile
whose `match` is `null`, or your own profile for another PC model):
`Build with which profile? Type its number, G or N`. `G` is `generic`; `N` makes a new profile
from this PC. A profile made or chosen here is used for this run's harvest and build.

A download that fails doesn't stop the run: Microsoft's servers sometimes don't answer, and
preflight then says what is missing. Run `Run-Build.cmd` again a few minutes later; files already
downloaded are kept.

When nobody can answer (the window has no keyboard input, as in a scheduled task), questions 6, 7
and 8 count as "no".

## One-time passwords

The build makes a random password for the admin account and one for the daily account.

- **20 characters, letters and digits only.** Look-alikes (`0 O o 1 l I`) and `Y`/`Z` are left
  out, so a password types the same on US, UK and German keyboards. For a French keyboard, set
  `locale.inputLocale`.
- **Written to one file:** `C:\W11Kit\work\accounts.txt`, which only administrators can open. They
  never appear on screen or in the build log. To open it: Start → type `Notepad` → right-click →
  **Run as administrator** → File → Open.
- **The last line names the ISO** the passwords belong to (`ISO: <file name>  SHA-256 <hash>`).
  No such line means that build failed and the passwords are in no ISO.
- **A failed build deletes its file** and puts the previous one back. A later real build renames
  the earlier file to `accounts-<date>-<time>.txt` instead of overwriting it.
- **A test build** writes `test-accounts.txt` and never touches `accounts.txt`.
- **Both accounts must choose a new password at their first sign-in.**

Copy the two passwords off the PC before you install
([guide](../GUIDE.md#save-the-two-passwords-now)): the install erases the disk the file is on.

The ISO itself holds the two passwords, hidden but not encrypted, because an unattended install
needs them. Anyone who can read the ISO can recover them: keep the ISO and the stick private until
both accounts have their new passwords.

**A stick you keep for the next reinstall** still holds that build's two passwords, for as long as
it exists. A reinstall from it starts both accounts with those passwords again, until their first
sign-in forces new ones. So keep the stick as you would keep a password (not in the PC's bag, not
lent out), sign in to both accounts as soon as a reinstall from it finishes, and write the stick
again with each new build ([MONTHLY](../MONTHLY.md)), so that no old one lingers. How the
passwords are generated:
[Build internals](../dev/BUILD-INTERNALS.md#passwords).

## Outputs

| Output | Where |
|---|---|
| The ISO | `C:\W11Kit\work\Win11Pro-<isoTag>-<Windows build>-<time>.iso` (a test build: `Win11Pro-<isoTag>-TEST-...`) |
| Its hash | `<iso>.sha256` |
| The [manifest](../GLOSSARY.md#manifest) | `<iso>.manifest.json`, also in the ISO as `W11Kit-build-manifest.json` |
| The passwords | `C:\W11Kit\work\accounts.txt` ([above](#one-time-passwords)) |
| Logs | `C:\W11Kit\work\logs`: `build-<time>.txt`, the image check `verify-<time>.txt`, the boot-side check `verify-boot-<time>.txt`, one `dism-*.log` per update |

The manifest records what went into the ISO: the kit's revision, the profile, your effective
settings and where each came from (your file, this PC, or the kit's default), the computer name,
the new names of the built-in Administrator and Guest accounts, the source ISO's hash, every
update, the two baseline zips with their hashes, the drivers added and skipped, the apps removed,
both check results, and the SHA-256 hash of every
`sources\install*.swm` part. Compare those hashes with a written stick:
`Get-FileHash E:\sources\install*.swm` (E: = the stick).

`Run-Build.cmd` starts with a short notice (you accept Microsoft's licence terms, installing
erases a disk, no warranty). The build ends with the ISO's path (`ISO:`), its hash (`SHA256:`),
the new names of the two built-in accounts and where the passwords are; `Run-Build.cmd` adds
`Keep this ISO private: ...`. A failed build ends with `BUILD FAILED: ...`, removes its half-made
files and its passwords file, and leaves the log. Logs older than 30 days are deleted by the next
build.

## Disk space

Plan for about **150 GB free** on the drive that holds `C:\W11Kit\work`, and a **32 GB or larger
USB stick**.

| What | Size | When |
|---|---|---|
| Source ISO | about 7.5 GB | Stays in `Downloads` |
| Updates | about 5 GB | Stay in `work\updates` |
| Harvested drivers and their zip | A few GB (the reference PC: 2.8 GB curated, plus the full export and the zip) | Stay in `work\DriverExport` |
| Copy of the ISO's contents | about 8 GB | Only while a build runs |
| The image being changed, with DISM's scratch space | about 25 GB at the peak | Only while a build runs |
| Build inputs inside the ISO | 15 to 20 GB | Real build only |
| The finished ISO | about 10 GB (test build, or `-NoBuildInputs`); about 28 GB (real build) | Stays in `work` until you delete it |
| VM test: a copy of the ISO's contents and the VM test's copy, without build inputs | about 9 GB each | Only while the test runs |
| VM test: the virtual machine's disk | 20 to 25 GB (the test reserves 30 GB) | Deleted after a PASS; kept after a FAIL |

What the kit checks before it starts:

- `Run-Prepare.cmd`: **80 GB** free on the system drive and on the work folder's drive.
- Preflight of a real build: **80 GB** free on the work folder's drive, on top of the inputs
  already there. For a test build or with `-NoBuildInputs`: **40 GB**.
- `Run-VmTest.cmd`: twice the ISO's contents without build inputs, plus 30 GB. That is about
  **50 GB**.

Not enough room on `C:`? Use `-WorkRoot` on a bigger drive. To get space back afterwards:
[Freeing space](../TROUBLESHOOTING.md#freeing-space).

## Build inputs in the ISO

A real build carries its own [build inputs](../GLOSSARY.md#build-inputs) in the ISO, in the folder
`BuildInputs`, so the installed PC can build its next ISO without downloading anything.
`-NoBuildInputs` leaves them out; a test build never has them.

What is carried:

- the Windows source ISO, the updates and Microsoft's two security baseline zips (not the data
  imported from them: the next build imports it again);
- `DriverExport.zip` and its `.sha256`;
- `oscdimg` (the ISO writer from the ADK) and the Git and Python installers;
- the kit as a Git bundle (committed work only);
- your own kit files the bundle can't hold: `config\settings.local.json`,
  `config\source-iso.local.json` and every `profiles\<id>\profile.json` that is new or changed.

Each file is split into parts under 4 GB, because the stick must be FAT32 for Secure Boot, and
listed with its SHA-256 hash in `BuildInputs\manifest.json`. The passwords file is never
included.

The ISO and the stick are for your own PCs only. `oscdimg` comes from the Windows ADK, whose
licence lets you install and use any number of copies on your own devices to deploy and maintain
them, and forbids sharing, distributing or lending it to anyone else. That is one more reason,
after the passwords on them, never to give the ISO or the stick away.

On the installed PC, `Restore-BuildInputs.cmd` (in the stick's `BuildInputs` folder):

1. joins the parts and checks every hash;
2. puts the files into `C:\W11Kit\work`;
3. offers to install Git from the restored installer;
4. checks the kit out of its bundle into `C:\W11Kit`, as a normal Git clone, and puts your own
   files back in their places.

There is nothing to run for the baselines: the zips are back in `C:\W11Kit\work\baselines`, and
the next build imports them (it needs Python, which `Run-Build.cmd` offers to install).

It is safe to run again. A `C:\W11Kit` that is already a clone is left as it is; one that holds
other files stops the restore before anything is written. `Restore-BuildInputs.cmd D:\W11Kit`
restores to another folder. The steps for a user are in
[Getting the kit back](../AFTER-INSTALL.md#getting-the-kit-back).

Not carried: the ADK installer (it downloads from Microsoft anyway; `oscdimg` itself is carried),
a WSL distro, and your SSH keys.

## VM test options

`Run-VmTest.cmd` installs the ISO in a Hyper-V [virtual machine](../GLOSSARY.md#virtual-machine-vm)
without any input from you and ends with `RESULT: PASS` or `RESULT: FAIL`. You can test the real
ISO: the test works on a copy and never changes the ISO you install.

Options, typed after `C:\W11Kit\Run-VmTest.cmd` in a Command Prompt:

| Option | Default | Meaning |
|---|---|---|
| `-IsoPath <iso>` | The newest `Win11Pro-*.iso` in the work folder | The ISO to test |
| `-KeepVm` | Off | Leave the virtual machine in Hyper-V Manager to look at |
| `-KeepDisk` | Off | Keep the VM's disk after a PASS. After a FAIL it is always kept |
| `-TimeoutMinutes <n>` | 120 | Give up after this long |
| `-VmName <name>` | `W11Kit-ISO-Test` | The virtual machine's name. An old one of that name is removed first |
| `-WorkRoot <folder>` | `C:\W11Kit\work` | The work folder, as for the build |
| `-WorkDir <folder>` | `C:\W11Kit\work\vmtest` | Where the test keeps its files and results |

What it does:

1. Makes **the VM test's copy** of the ISO, `C:\W11Kit\work\vmtest\W11Kit-VMTEST-ONLY-wipes-disk.iso`.
   It differs from your ISO in four ways: it erases disk 0 without asking, it starts without
   *Press any key*, it has no `BuildInputs` folder, and it carries the generic Windows 11 Pro
   installation key when your ISO has none (a virtual machine has no firmware key).
2. Creates a virtual machine with Secure Boot, a virtual TPM, 4 processors, 6 GB of memory, an
   80 GB disk and the *Default Switch* network.
3. Installs, waits for first-boot setup and its restart, then shuts the VM down and collects the
   logs and the validator's report into `C:\W11Kit\work\vmtest\results`. The VM's answer file is
   kept only with the passwords removed.
4. Grades the result ([how](../dev/TESTING.md#the-hyper-v-vm-test)). Some rows always fail in a
   virtual machine and are expected ([list](../dev/TESTING.md#rows-expected-to-fail-in-a-vm)).

> [!CAUTION]
> The VM test's copy erases a disk without asking. Never write it to a USB stick. It is deleted
> when the test ends, pass or fail. As a second line of defence it is built to power the machine
> off, before it touches a disk, when it is started anywhere but in a Hyper-V virtual machine. Don't
> rely on that.

If Windows Setup has not restarted the VM after 8 minutes, the test saves a picture of the VM's
screen (`vm-screen-8min.png` in the results folder). After 20 minutes without a restart it stops
and collects Setup's early logs (`early-setuperr.log`, `early-setupact.log`). Hyper-V can't press
a power button or send a Wake-on-LAN packet, so hibernate and
wake are tested on the real PC ([guide, step 14](../GUIDE.md#step-14-check-the-pc)).

## Building on another PC

The drivers always come from the PC you reinstall, while it still runs its current Windows. If
you build on a different PC:

1. Copy the kit to the PC you reinstall as well.
2. There, run `C:\W11Kit\New-Profile.cmd` and `C:\W11Kit\Run-Harvest.cmd`.
3. Copy `C:\W11Kit\profiles\<id>\`, `C:\W11Kit\work\DriverExport` and
   `C:\W11Kit\work\DriverExport.zip` (with its `.sha256`) to the same places on the build PC.
4. Build there with `C:\W11Kit\Run-Build.cmd -Profile <id>`. With `-Profile`, `Run-Build.cmd`
   asks nothing about a profile, and it doesn't offer a harvest for a profile of another PC model.

The build prints `[NOTE] Its match does not fit this PC (...)` when you build for a profile that
doesn't fit the build PC. That is expected here. The build also takes keyboard, formats, time
zone and country from the build PC unless [your settings](CONFIGURATION.md#your-settings) name
them: check the lines ending in `(from this PC)` at the top of the build's window.

## Exit codes

| Launcher | Code | Meaning |
|---|---|---|
| `Run-Prepare.cmd` | 0 | Ready |
| | 3010 | Ready after a restart (Hyper-V was just turned on) |
| | 1 | Something blocks the build, or a tool didn't install |
| `Run-Build.cmd` | 0 | Preflight passed, or the ISO is built (and the VM test it started, if any, passed) |
| | 1 | The kit was just updated to a new release (start `Run-Build.cmd` again), or you answered no to `Build with these old updates anyway? [y/N]`, or the VM test it started ended in `RESULT: FAIL` (the ISO exists all the same) |
| | not 0 | `Pre-flight failed: ...` or `BUILD FAILED: ...` |
| `Run-VmTest.cmd` | 0 | `RESULT: PASS` |
| | 1 | `RESULT: FAIL` |
| `Run-Harvest.cmd`, `New-Profile.cmd`, `Collect-Diagnostics.cmd` | 0 | Done |
| | 1 | The script stopped with an error (the message is above it) |
| Any launcher that asks for elevation | 1 | The UAC prompt was cancelled or timed out |

Started from a window that is not elevated, a launcher opens an elevated window and ends at once
with 0: the code above is that window's. For a script or a scheduled task that needs the code,
start the launcher from an elevated prompt or a task that runs with the highest privileges.
