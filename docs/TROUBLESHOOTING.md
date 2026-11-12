# Troubleshooting

> **W11Kit** · [Home](../README.md) · [1 Guide](GUIDE.md) → [2 After the install](AFTER-INSTALL.md) → [3 Monthly](MONTHLY.md)
> **Troubleshooting** · A word you don't know? [Glossary](GLOSSARY.md)

What you see, what it means, and what to do. Messages are quoted as the kit prints them, so you
can search this page for a few words of yours (Ctrl+F). `…` stands for the details of your PC.

**If nothing here fits:** keep the window open, take a photo or screenshot, and look at the log
the message names.

| Where | Logs |
|---|---|
| Build PC | `C:\W11Kit\work\logs` |
| VM test | `C:\W11Kit\work\vmtest\results` |
| Installed PC | `C:\ProgramData\W11Kit\Logs` |

**Sections:** [Preparing and building](#preparing-and-building) ·
[The VM test](#the-vm-test) · [Installing](#installing) ·
[Setup did not finish](#setup-did-not-finish) ·
[First sign-in and activation](#first-sign-in-and-activation) ·
[Drivers and devices](#drivers-and-devices) · [BitLocker](#bitlocker) ·
[The validator's report](#the-validators-report) · [Everyday use](#everyday-use) ·
[Freeing space](#freeing-space)

## Preparing and building

### Starting one of the kit's files

| What you see | What it means | What to do |
|---|---|---|
| *Windows protected your PC* or *Open File - Security Warning* when you double-click a `.cmd` file | The kit came as a ZIP from the internet, and Windows marks such files | Click **More info → Run anyway** or **Run**. Better: get the kit with Git ([step 2](GUIDE.md#step-2-get-the-kit)) |
| `Run-….cmd did not start: the Windows UAC prompt was cancelled or timed out`, or nothing happens | The UAC prompt was cancelled, or it timed out after about 2 minutes | Run it again and click **Yes** |
| The UAC prompt or an administrator window keeps coming back after you click **Yes**, on a PC installed from the kit | The kit's files from before the fix checked for administrator rights with a command that needs the Server service, which the image turns off | Update the kit (`git pull`). On the installed PC, *Validate PC* and *Enable BitLocker* have the old check: in `C:\ProgramData\W11Kit\Validate-Pc.cmd` and `Enable-BitLocker.cmd` (as administrator, in Notepad), replace `net session` with `fltmc` |
| `A parameter cannot be found that matches parameter name '…'` | An option is misspelled, no longer exists, or a path with spaces has no double quotes | Check the option ([build options](reference/BUILD-OPTIONS.md#build-options)). Quote paths: `-SourceIso "D:\My ISOs\Win11.iso"` |
| Your antivirus warns about a `.cmd` file of the kit | The launchers start PowerShell with the script's text instead of a script file, so that they also work where a policy blocks script files. Some scanners dislike that pattern | Open the `.cmd` in Notepad to see what it runs ([the launchers](reference/BUILD-OPTIONS.md#the-launchers)). Allow it only if the kit came from the project's own address |
| `'git' is not recognized` or `'py' is not recognized`, right after `Run-Prepare.cmd` installed them | The Command Prompt was open before the install | Close it and open a new one |

### Run-Prepare.cmd

| What you see | What it means | What to do |
|---|---|---|
| `[BLOCK] Windows edition: Windows 11 Home` | Home can't run the test VM and isn't supported for building | Upgrade to Pro (Settings → System → Activation), or [build on another PC](reference/BUILD-OPTIONS.md#building-on-another-pc) |
| `[BLOCK] Windows version: build …` | This Windows is older than 24H2 | Update Windows (Settings → Windows Update), then run it again |
| `[BLOCK] Processor architecture: ARM64`, or `This PC's processor is not x64 (ARM64): …` | The kit builds on PCs with 64-bit Intel or AMD processors (x64) and makes x64 images only | Build on an x64 PC. An ARM PC can't be the PC you reinstall |
| `[DONE ] Defender ASR exclusions left by an interrupted build: removed: …` or `[DONE ] VM-test ISO left behind: deleted …` | An earlier build or VM test was interrupted and left something behind. The kit has cleaned it up | Nothing |
| `[BLOCK] Controlled Folder Access: on, set by policy …` | Defender's ransomware protection blocks the tool that edits the image, and a policy sets it, so the build can't pause it | Set it to Not configured or Audit where the policy comes from, or build on another PC. Set by the kit's image instead, `Run-Build.cmd` asks to pause it ([The build PC](reference/CONFIGURATION.md#the-build-pc)) |
| `[BLOCK] ASR prevalence rule: Block, set by policy …` | A Defender rule blocks programs that few people run, including the build's own tools, and a policy sets it | Set that rule to Audit or Not configured where the message says. On a work-managed PC, build on another PC |
| `Defender's Controlled Folder Access or ASR prevalence rule is on … pass -PauseDefenderProtection` | `Build-Iso.ps1` was started directly on a PC with the protection on | Use `Run-Build.cmd`, which asks, or pass `-PauseDefenderProtection` yourself |
| `Defender protection NOT restored …` | The build couldn't turn the protection back on | Run the next build or `Run-Prepare.cmd`; or in an administrator PowerShell: `Set-MpPreference -EnableControlledFolderAccess Enabled` |
| `[BLOCK] Free space on C:` | The build needs 80 GB free | [Freeing space](#freeing-space), or build on a bigger drive with `-WorkRoot` ([disk space](reference/BUILD-OPTIONS.md#disk-space)) |
| `[WARN ] Not managed by an employer or school  joined to the domain …`, `… Microsoft Entra ID` or `… device management (MDM)` | Your employer or school manages this PC. Its policies can undo what the kit sets, or block the build | Build on a PC of your own. The kit doesn't support managed PCs ([Is this for you?](../README.md#is-this-for-you)) |
| `[WARN ] Virtualization in firmware: off` | The VM test can't run | Turn on SVM (AMD) or Intel Virtualization Technology in the BIOS ([before any BIOS change](GUIDE.md#before-any-bios-change)) |
| `[WARN ] Kit location: \\…` | The kit is on a network or WSL path that the administrator window may not see | Put it in `C:\W11Kit` ([step 2](GUIDE.md#step-2-get-the-kit)) |
| `[FAIL ] Git for Windows` (or Python, ADK) after `Install them now?` | A download or install failed | Check the internet connection and run `Run-Prepare.cmd` again. The log is `C:\W11Kit\work\logs\install-<tool>-<time>.log` |
| `READY after a restart: restart Windows to finish enabling Hyper-V.` | Hyper-V was turned on | Restart Windows before the VM test |
| `NOT READY: … item(s) block the build (marked BLOCK or FAIL above).` | At least one row above it is `BLOCK` or `FAIL` | Fix those rows (each has a line starting `->` that says how) and run it again |

### The check before the build (preflight): Windows ISO, settings, profile

| What you see | What it means | What to do |
|---|---|---|
| `[FAIL] Source ISO  none found: …` | No Windows ISO found | Put it in a Downloads folder, with a name starting with `Win11` or `Windows11` ([step 4](GUIDE.md#step-4-download-windows)), or pass `-SourceIso "<file>"` |
| `[FAIL] Source ISO  … not found` | The `-SourceIso` path is wrong | Check it. Put double quotes around a path with spaces |
| `[FAIL] Source ISO is an accepted, official release  SHA-256 … is in neither config\source-iso.json nor config\source-iso.local.json` | The kit doesn't know this ISO. Usually Microsoft published a newer one | Compare the hash with Microsoft's, then accept it: [If the kit doesn't know your ISO](GUIDE.md#if-the-kit-doesnt-know-your-iso) |
| `[FAIL] Your own source ISO list (config\source-iso.local.json)  …` | Your `source-iso.local.json` isn't valid JSON, or an entry's `sha256` isn't 64 characters | Save the line the message above printed again, exactly as printed |
| `[FAIL] Source ISO language matches locale.uiLanguage (…)` | The ISO's language and `uiLanguage` in your settings differ | Download the English ISO (en-US, or en-GB for English International), or set `locale.uiLanguage` to the ISO's ([another language](reference/CONFIGURATION.md#another-language)) |
| `[FAIL] Settings valid  … locale.uiLanguage '…': the kit builds English Windows only (en-US or en-GB) for now …` | Your settings ask for another display language | Download the English ISO and set `uiLanguage` to `en-US` (or `en-GB`). Keyboard, formats, time zone and country stay yours ([another language](reference/CONFIGURATION.md#another-language)) |
| `[FAIL] Source ISO is x64 media  ARM64 media: …` | The download is the ISO for ARM PCs | Download *Windows 11 (multi-edition ISO for x64 devices)* |
| `[NOTE] Defender ASR exclusions left by an interrupted build: …` or `[NOTE] A VM-test ISO was left behind: …` | An earlier build or VM test was interrupted. The preflight changes nothing, so it only tells you | Nothing: the next build (or `Run-Prepare.cmd`) removes them. Never write that VM-test ISO to a stick |
| `[FAIL] Settings valid  …` naming a field (for example `locale.timeZone: '…' is not a Windows time zone ID (tzutil /l lists them)`) | A value in your settings is wrong | Fix that field in `C:\W11Kit\config\settings.local.json` ([step 7](GUIDE.md#step-7-your-settings)) |
| `[FAIL] Settings valid  … settings.local.json: unknown field '…' (the fields are in config\settings.defaults.json)` | A field name is misspelled, or sits in the wrong `{ }` block | Compare with `C:\W11Kit\config\settings.defaults.json` and correct the name |
| `[FAIL] Settings valid  … settings.local.json: '…' is not a field any more: it is now called '…'` | The kit renamed a setting. The message gives the new name | Rename the field in your `settings.local.json` |
| `[FAIL] Settings valid  … settings.local.json: schemaVersion … is newer than this kit reads (…): update the kit (Run-Build.cmd, first question) and build again` | Your settings file was written for a newer kit | Answer `y` to `Update the kit to its newest signed release first? [y/N]` |
| `[FAIL] Settings valid  … settings.local.json is not readable: …` | The file isn't valid JSON (a missing comma or quote) | Compare it with the examples in [step 7](GUIDE.md#step-7-your-settings), or delete it and make it again |
| A line ending in `(from this PC)` | Your settings don't say, so the build uses this PC's own keyboard, formats, time zone or country | Nothing, if that is what you want. Otherwise set the field ([step 7](GUIDE.md#step-7-your-settings)) |
| The keyboard or formats in those lines aren't yours; a line says `(this PC's values were read as …, the account that started Run-Build.cmd)` | `Run-Build.cmd` was started from a window that another account opened (a Command Prompt as a separate administrator account), so it read that account's values | Start `Run-Build.cmd` with a double-click from your own account, or set the fields under `locale` in your settings |
| `[NOTE] This PC's … can't be used (…): the kit's default … is used.` | A value of this PC isn't one Windows Setup accepts (for example the country *World*) | Set that field under `locale` in your settings, as the note says |
| `[NOTE] Not in your settings, and not read from this PC (Run-Build.cmd does that; Build-Iso.ps1 was started directly): the kit's default is used for …` | The build was started without `Run-Build.cmd`, so nothing was read from the PC: US keyboard, `en-US` formats, time zone UTC | Start the build with `Run-Build.cmd`, or set the fields under `locale` in your settings |
| `Pre-flight failed: Profile '…' not found` | No profile with that id | Check the spelling (the folder name under `C:\W11Kit\profiles`), or make one ([step 5](GUIDE.md#step-5-your-pcs-profile)) |
| `Profile … is invalid` | A field in `profile.json` is wrong; the message lists each | Fix it as [profiles](reference/PROFILES.md) describes, or make it again: `New-Profile.cmd -Force` |
| `[FAIL] Firmware key is a Pro key (profile productKey 'firmware')` | Your PC's built-in key is for Home (common: a Home PC upgraded to Pro later) | In `C:\W11Kit\profiles\<id>\profile.json` set `"productKey": "generic"` |
| `[NOTE] Its match does not fit this PC` or `[NOTE] The drivers were curated for profile '…'` | You're building for another profile than this PC's, or than the drivers you harvested | Fine if you meant it. Otherwise use the right `-Profile`, or harvest again |

### The check before the build: updates, baselines, drivers

| What you see | What it means | What to do |
|---|---|---|
| `[FAIL] Cumulative update`, `.NET update` or `Safe OS updates  none in …` | The updates aren't in `C:\W11Kit\work\updates` | Run `Run-Build.cmd` without `-Preflight` and answer `Y` to the download question |
| `[NOTE] The updates differ from config\updates.json (…)` | Last month's updates are there, or some are missing | Same as the row above. The download removes last month's files |
| `[NOTE] The update pins (config\updates.json) are … days old (pinned …): newer Windows updates are probably out.` | The kit's update list is more than 35 days old | Answer `y` to `Update the kit to its newest signed release first? [y/N]`. Still old: build anyway (Windows Update catches up after the install), or [refresh it yourself](dev/MAINTAINING.md#monthly-move-the-pins) |
| `[WARN] The update pins (config\updates.json) are … days old (pinned …): Microsoft has released newer Windows updates since, and this image will start out that far behind.` and, when the build starts, `Build with these old updates anyway? [y/N]` | The list is more than 70 days old | As the row above. Enter or `n` ends with `Stopped: nothing was built.`; `y` builds with the old updates |
| `[FAIL] Security baseline zip: …  not in C:\W11Kit\work\baselines.` | Microsoft's baseline files aren't downloaded yet | Run `Run-Build.cmd` without `-Preflight` and answer `Y` to the download question |
| `[FAIL] Security baseline zip: …  … has SHA-256 …, not the pinned …: not the file this kit pins (damaged, or another release; the download replaces it).` | The zip in the work folder is damaged, or it is another release of the baseline | Same as the row above: the download replaces the file |
| `…: Microsoft does not serve this file any more (HTTP 404 for …).` or `…: the file Microsoft serves at this address has SHA-256 …, not the pinned one. Deleted, not used.` during the download | Microsoft has replaced the baseline file on its download page. The kit accepts only the file it pins | Update the kit (answer `y` to `Update the kit to its newest signed release first? [y/N]`) and build again. Or use a copy of the pinned zip you already have: `py C:\W11Kit\scripts\Get-Baselines.py --zip "<path to the zip>"` |
| `[FAIL] Python 3 (the build imports the security baselines with it)  not installed: …` | Every build needs Python | Run `Run-Prepare.cmd`, or `Run-Build.cmd` without `-Preflight` and answer `Y` to `Install them now? [Y/n]` |
| `Importing the security baseline … from … failed (exit code …, see above). Nothing was built.` | The importer could not read a baseline zip | Read the lines above the message. Delete `C:\W11Kit\work\baselines` and let `Run-Build.cmd` download the zips again |
| `… SHA-1 … does not match the one in its name` or `… is not named like an Update Catalog file` | An update file changed or was damaged after the download. Microsoft puts each file's SHA-1 hash in its name, and the build checks it again just before use | Delete that file and let `Run-Build.cmd` download the updates again |
| `[FAIL] Curated drivers  … (0 INF files): run Run-Harvest.cmd on the PC the image is for.` | No drivers harvested yet | Run `Run-Build.cmd` without `-Preflight` and answer `Y` to `Collect this PC's drivers now?`, or run the harvest ([step 6](GUIDE.md#step-6-collect-the-drivers)) |
| `[NOTE] The curated drivers include … storage driver(s) (class SCSIAdapter or HDC: …).` | Your PC's disk controller uses a driver that isn't built into Windows | Nothing. The build also puts those drivers into Windows Setup, so Setup can see the disk |
| `[FAIL] Curated drivers unchanged since the harvest (SHA-256)` … `changed since the harvest`, `is not from the harvest` or `missing` | A file in `C:\W11Kit\work\DriverExport\_Curated` was changed, added or deleted after the harvest ([curated drivers](GLOSSARY.md#curated-drivers)) | Harvest again. If you changed the set on purpose: `Run-Harvest.cmd -CurateOnly` records it ([drivers](reference/DRIVERS.md)) |
| `[FAIL] Build inputs: DriverExport.zip + .sha256` | The harvest's archive is missing | Run the harvest again |
| `[FAIL] Build inputs: installer …  missing or wrong hash: …` | The Git or Python installer for the ISO isn't in `C:\W11Kit\work\installers` | Run `Run-Build.cmd` without `-Preflight` and answer `Y` to the download question |
| `[FAIL] Build inputs: git can read the kit (for the bundle)  … is not a Git clone` | The kit folder is a ZIP copy | Clone it (end of [step 3](GUIDE.md#step-3-prepare-the-pc)) and build from `C:\W11Kit`. Or build with `-NoBuildInputs`; then the ISO can't rebuild itself later |
| `[FAIL] Build inputs: git can read the kit (for the bundle)  Git for Windows is not installed: …` | Git isn't installed | Run `Run-Prepare.cmd`, or build with `-NoBuildInputs` |
| `scripts\Get-Updates.py failed (exit code …).` (or `Get-Baselines.py`, `Get-Installers.py`) after you answered `Y` | Microsoft's servers sometimes don't answer | Run `Run-Build.cmd` again in a few minutes. Files already downloaded are kept |
| `Python 3 is not installed, so nothing can be downloaded: run Run-Prepare.cmd (it installs it), then Run-Build.cmd again.` | You answered `n` to `Install them now? [Y/n]` | Run `Run-Prepare.cmd`, then `Run-Build.cmd` again |
| `No profile was made (see above). Continuing with the 'generic' profile.` | You answered `Y` to `Make one now from this PC? [Y/n]`, and the profile could not be written | Read the lines above it. The build goes on with the `generic` profile; to stop it, close the window. Then run `C:\W11Kit\New-Profile.cmd` by itself ([step 5](GUIDE.md#step-5-your-pcs-profile)) |
| `No hardware profile fits this PC by itself (…). These are used only when you choose them:` and a numbered list | The kit has profiles that it never takes by itself: one without a `match`, or your own for another PC model | Type the number of the profile for the PC you will reinstall, `G` for `generic`, or `N` to make a new profile from this PC |
| `No drivers are collected yet (…), and profile '…' is for another PC model than this one (…).` | You build for another PC, and its drivers aren't in the work folder | Harvest on that PC and copy the two items over ([building on another PC](reference/BUILD-OPTIONS.md#building-on-another-pc)) |

### The folder lock

The kit makes its folder and its work folder changeable by administrators only
([folder lock](GLOSSARY.md#folder-lock)).

| What you see | What it means | What to do |
|---|---|---|
| `git pull`, `copy` or Notepad's *Save* in `C:\W11Kit`: *Permission denied*, *unable to write*, *Access is denied* | The lock is doing its job | Use a Command Prompt or Notepad opened **as administrator**. `Run-Build.cmd` also offers to update the kit |
| `Could not make … writable by administrators only, so the build stops` | Something inside refused: a file in use, or a link to another folder | Close programs that use files there (Explorer windows, editors, a terminal inside the folder) and build again. A link inside is refused on purpose: remove it |
| `WARNING: … can be changed by …, so that account could replace the locked build folder in it as a whole` | The kit sits inside a folder that a standard account may change, such as your user folder | The build goes on. To close the gap, keep the kit directly under the drive: `C:\W11Kit` |
| `Won't lock '…': only a folder on a local drive` or `it is a user profile folder` | The kit or work folder is a drive root, a network path or your user folder | Put the kit in a folder of its own: `C:\W11Kit` |

How the lock works: [folder lock internals](dev/BUILD-INTERNALS.md#folder-lock).

### During the build

| What you see | What it means | What to do |
|---|---|---|
| No new line for 10–20 minutes | Some steps (updates, clean-up, drivers) are slow and silent | Wait. Don't close the window. The build keeps the PC awake; on a laptop, keep the lid open |
| `BUILD FAILED: … 0x80070005` while adding updates | Something blocks the image tool, usually a Defender rule | Check Controlled Folder Access and the ASR rule ([Run-Prepare.cmd](#run-preparecmd)), then build again |
| `BUILD FAILED: WinRE lacks the curated storage driver(s) …` | A storage driver couldn't be added to the recovery environment; the warning above it says why | Usually a driver that doesn't fit Windows PE: harvest again, or name it in the profile's `drivers.skipInf` if the disk doesn't need it ([DRIVERS](reference/DRIVERS.md)) |
| `BUILD FAILED: WinRE was not serviced: no Safe OS update applied …` | The month's Safe OS update didn't go into the recovery environment | Download the updates again (`Run-Build.cmd`, the downloads question) and build again; the warnings above name the update |
| `BUILD FAILED: …` (anything else) | The build stopped and cleaned up | Read the end of `C:\W11Kit\work\logs\build-<date>-<time>.txt`. Running the build again is safe |
| `boot.wim image …: storage driver … not added: …` | Windows' image tool refused one of your storage drivers for Windows Setup. The build goes on | If Setup later doesn't show your disk ([Installing](#installing)), report it with the PC model and the driver's name |
| `Not tested in a virtual machine: Hyper-V is not enabled on this PC. Run-Prepare.cmd enables it (one restart); then Run-VmTest.cmd tests this ISO.` | The build is done, but the VM test can't run yet | Run `Run-Prepare.cmd`, restart, then `Run-VmTest.cmd` |
| `Removed Defender ASR exclusions left by an interrupted build: …` at the start | A build that was interrupted left Defender told to skip its work folders | Nothing. The kit has removed them |
| `Could not delete the VM-test ISO … (is a VM test running?)` | The VM test's copy of an ISO is still there and in use | Wait for the VM test to end, or stop its virtual machine. Never write that file to a stick |

### The passwords file

| What you see | What it means | What to do |
|---|---|---|
| You can't open `C:\W11Kit\work\accounts.txt` (*Access is denied*) | Only administrators can read it, on purpose | Open it with Notepad started **as administrator** ([step 8](GUIDE.md#save-the-two-passwords-now)) |
| The last line of `accounts.txt` names a different ISO than the one you want to install | Every build makes new passwords. The older file is kept as `accounts-<date>-<time>.txt` | Use the passwords from the file whose last line names **your** ISO |
| `This build's passwords are in no ISO: … is the previous build's file again` (or `was deleted`) after `BUILD FAILED` | A failed build deletes its passwords file. If there was an earlier one, it is `accounts.txt` again | Nothing. Build again |
| `accounts.txt` has no last line starting `ISO:` | That build was cut short (the window was closed, or the PC went off). Its passwords are in no ISO | Build again |

## The VM test

| What you see | What it means | What to do |
|---|---|---|
| `The Hyper-V PowerShell module is missing` | Hyper-V isn't on | Run `Run-Prepare.cmd`, answer `Y`, restart |
| `No built ISO found in C:\W11Kit\work` | Nothing built yet, or the ISO is elsewhere | Build first, or `Run-VmTest.cmd -IsoPath "<path to the .iso>"` |
| `oscdimg.exe not found` | The ISO tool isn't installed | Run the build once; it installs it |
| The VM doesn't start, or Hyper-V reports too little memory | The VM needs 6 GB of memory and 4 processor cores | Close big programs and try again |
| `Not enough free space for the VM test: … GB free, about … GB needed` | The test copies the ISO's contents, builds its own copy, and needs 30 GB for the VM's disk | [Freeing space](#freeing-space), or run the test with `-WorkDir D:\…` on a bigger drive |
| `expected   …  [reason]` lines in the summary | Checks a VM can't pass: your hardware, activation, BitLocker | Nothing. They're listed so you can see them |
| `UNEXPECTED …` in red, and `RESULT: FAIL` | A check failed that should pass in a VM too | Read the row, and `W11Kit-Validation.md` in `C:\W11Kit\work\vmtest\results`. Fix, rebuild, test again. If it's in the kit itself, report it |
| `PostInstall status file NOT found - first logon did not complete` | The first-boot setup didn't run or didn't finish | Look at the Setup logs and the PostInstall log in the results folder. Run the test once more; if it repeats, report it |
| `PostInstall finished: … critical=True` | The kit's security settings didn't apply in the VM | Read the PostInstall log in the results folder. **Don't install this ISO** |
| `Cached answer files in Windows\Panther: …` | The files with the one-time passwords weren't deleted | The test fails on purpose. Report it. **Don't install this ISO** |
| `WARNING: not finished within 120 minutes; collecting what exists` | The install hung or is very slow, or the PC slept during the test | Keep the PC awake. Run again with `-KeepVm` and look at *W11Kit-ISO-Test* in Hyper-V Manager. On a slow PC: `-TimeoutMinutes 180` |
| `No first restart after 8 minutes (usually about 4): saving what the VM shows`, then `WARNING: Windows Setup has not restarted the VM after 20 minutes: it stopped in its first phase (error page?); collecting its logs` | Windows Setup stopped at an error page, or the PC is very slow | Open `vm-screen-8min.png` in `C:\W11Kit\work\vmtest\results`: it shows the VM's screen. `early-setuperr.log` next to it has Setup's errors. Report it with both files |
| `VM turned off on its own`, then `Before Setup's first restart: the test ISO's hardware guard powers the machine off when Windows PE does not report a Hyper-V VM …` | The VM test's copy of the ISO erases a disk without asking, so it switches the machine off unless it finds itself in a Hyper-V virtual machine. Here it didn't recognise the VM | Run the test again. If it repeats, report it with the files in the results folder |
| `The test ISO's answer file does not carry the hardware guard (found … command(s)): no test ISO is made.` | The kit could not put that guard into the VM test's copy, so it made no copy | Nothing was changed. Report it |
| A real PC switches off right after starting from a stick | The stick was written from the VM test's copy, `W11Kit-VMTEST-ONLY-wipes-disk.iso`. That switch-off is its safety guard | Never use that file. Write the stick from your own ISO ([step 10](GUIDE.md#step-10-copy-to-your-backup-drive-and-make-the-usb-stick)) |
| `Validation report (W11Kit-Validation.json) NOT found.` | The validator didn't run in the VM, so the first-boot setup didn't finish | Look at the PostInstall log in the results folder. Run the test once more; if it repeats, report it |

What a VM may fail, with the reasons: [rows expected to fail in a VM](dev/TESTING.md#rows-expected-to-fail-in-a-vm).
Options of the test: [VM test options](reference/BUILD-OPTIONS.md#vm-test-options).

## Installing

| What you see | What it means | What to do |
|---|---|---|
| The USB stick isn't in the boot menu | The firmware doesn't see it as a UEFI start-up device | Use another USB port (on a desktop, one at the back). Check that Secure Boot is on and *CSM* / *Legacy* is off. Write the stick again with Rufus (GPT, UEFI) |
| *Secure Boot violation* or a red *invalid signature* screen | The stick uses Microsoft's 2023 start-up certificate, and this firmware doesn't trust it yet | The build's pre-flight tells you beforehand: `[OK  ] This PC's firmware trusts the stick's boot manager (Windows UEFI CA 2023)`, or `[NOTE] This PC's firmware does not trust the 2023 certificate …`. Update the BIOS from your PC maker's site. Background and the fallback switch: [Secure Boot certificates](reference/SECURITY-BASELINE.md#secure-boot-2023-certificates) |
| *Press any key to boot from CD or DVD* | Normal on some PCs | Press a key once |
| Setup lists more disks than you expected, or you can't tell which is which | Another disk is connected | **Delete nothing.** Unplug the stick and restart into your current Windows. Unplug every USB disk, and compare sizes in Disk Management ([step 12](GUIDE.md#step-12-install)) |
| Your disk isn't in *Select location to install Windows 11* | Setup has no driver for the disk controller (some RAID or Intel VMD modes) | **Delete nothing** and restart into your current Windows. Run the harvest and the build again on this PC: the build puts this PC's storage drivers into Setup too. Still missing: report it with the PC model |
| Setup asks for a **product key** | The profile's `productKey` doesn't fit this PC, or the profile uses `prompt` | Click *I don't have a product key* if offered, or type your Pro key. For next time: `"productKey": "generic"` ([profiles](reference/PROFILES.md#fields)) |
| Setup starts again from the beginning after a restart | The PC started from the stick again | Unplug the stick and restart |
| *Windows could not parse or process the unattend answer file* | The answer file doesn't fit this Setup | Write down the exact message, go no further, and report it |
| `Finished with … warning(s) - see …` in yellow, then a restart | Some first-boot steps failed, but nothing critical | Carry on. *Validate PC* shows which ([step 14](GUIDE.md#step-14-check-the-pc)) |
| The first-boot window seems stuck for 20 minutes or more | Restore point, Defender or WSL update are slow. Each has a time limit | Wait up to 40 minutes. A step that overruns is recorded and skipped |
| Red `SECURITY BASELINE OVERRIDES FAILED - DO NOT RESTART YET.`, a file `W11Kit setup NOT finished - read me.txt` on the desktop, or no restart | Setup cancelled its restart on purpose | **Don't restart.** Follow [Setup did not finish](#setup-did-not-finish) |
| After the restart, the sign-in screen and nothing else | That's the correct end of setup | Sign in ([step 13](GUIDE.md#step-13-first-sign-in)) |

## Setup did not finish

You see red text `SECURITY BASELINE OVERRIDES FAILED - DO NOT RESTART YET.` in the first-boot
window (it waits for Enter, at most 15 minutes), or the file `W11Kit setup NOT finished - read
me.txt` on the desktop, or the PC doesn't restart by itself.

Some of the kit's changes to Microsoft's security settings didn't apply.

1. **Don't restart.**
2. Open PowerShell (as administrator): Windows key, type `powershell`, right-click → **Run as
   administrator**.
3. Run:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\PostInstall.ps1
   ```

4. If it succeeds, the PC restarts after 2 minutes and the desktop file is deleted. You are done.
5. If the red text appears again, still don't restart. Report it, with the newest
   `postinstall-*.txt` from `C:\ProgramData\W11Kit\Logs`.

**Why not restart?** A restart now would lock two security settings into the PC's firmware and
stop your daily account from approving administrator prompts.

## First sign-in and activation

| What you see | What it means | What to do |
|---|---|---|
| *The user's password must be changed before signing in* | Expected: the one-time passwords must be replaced | Click OK, type the old password, then the new one twice |
| *The password doesn't meet the password policy requirements* | The new password is too short or too simple | At least 11 characters, three of: upper case, lower case, digits, symbols. Not containing the account name |
| *The referenced account is currently locked out* | 10 wrong passwords in a row | Wait 15 minutes, then try again. Check the keyboard layout first |
| The one-time password is refused | A typo, another keyboard layout, or passwords from another build | [Lost or forgot a password?](AFTER-INSTALL.md#lost-or-forgot-a-password) |
| You can't change your password again the same day | Passwords can be changed once a day | Wait a day, or let `LocalAdmin` set a new one ([how](AFTER-INSTALL.md#lost-or-forgot-a-password)) |
| No Wi-Fi list at the sign-in screen | On purpose on this image | Sign in, then connect with the network icon |
| Settings → Activation: *not activated* | Activation from your digital licence needs the internet, and sometimes a few minutes | Stay online and wait, then **Troubleshoot** on that page. If this PC never had Pro activated, enter your Pro key there |
| A UAC prompt rejects the admin password | Wrong account picked, or a typo | Pick **LocalAdmin** in the prompt. 10 wrong tries lock it for 15 minutes |
| Validator FAIL `No cached answer files with passwords` | Setup's copies of the answer file weren't deleted | PowerShell (as administrator): `Remove-Item -Force C:\Windows\Panther\unattend*.xml`, then validate again |

## Drivers and devices

| What you see | What it means | What to do |
|---|---|---|
| `PROFILE MISMATCH` (three times) during the harvest | The profile is for another PC model | Use this PC's profile. Drivers always come from the PC the harvest runs on |
| `Some bound platform drivers are missing from the curated set.` | A driver of a maker the profile carries couldn't be copied | The table above the message names it. Run the harvest again; if it repeats, report it with `C:\W11Kit\work\DriverExport\_Reports` |
| Validator FAIL in a hardware row (graphics, sound, network, Wi-Fi, Bluetooth), or FAIL `No unknown devices (code 28)` | A device has no working driver. Windows Update won't fetch one on this image | [A device without a driver](AFTER-INSTALL.md#a-device-without-a-driver) |
| A newly plugged-in device (mouse, printer, webcam) doesn't work | Windows has no built-in driver for it | [A device without a driver](AFTER-INSTALL.md#a-device-without-a-driver) |
| Graphics work, but the maker's control app is missing | The image carries the driver, not the app | Install the app and turn off its automatic driver installs ([installing your programs](AFTER-INSTALL.md#installing-your-programs)) |
| A sound-effects app that came with the PC is missing, or one of its parts shows as disabled in Device Manager | The image carries the drivers, not the makers' companion apps. Disabled devices don't count as failures | Nothing; sound works through the audio driver. Model notes: your profile's README (the reference PC: [drivers](../profiles/legion-t5/README.md#drivers)) |
| Validator WARN `Wi-Fi Direct adapters disabled (no hotspot / casting)` | A Wi-Fi driver update re-created the Wi-Fi Direct adapter | The row shows the command to disable it again |
| Wake-on-LAN doesn't wake the PC | A BIOS setting, the cable, or the wrong address | Check the BIOS (Wake on LAN on, ErP off) and the validator's two Wake-on-LAN rows. Send the packet to the MAC address shown there, from the same network |

## BitLocker

| What you see | What it means | What to do |
|---|---|---|
| `TPM is not ready. Enable … and retry.` | The TPM is off in the BIOS | Turn on TPM / fTPM / PTT ([step 11](GUIDE.md#step-11-biosuefi-settings)) |
| `Kernel DMA Protection is off and the IOMMU is not active. This hardware profile requires DMA protection: BitLocker was not started, nothing changed.` | Your profile requires DMA protection, and the BIOS setting is off | Do what the `Fix:` line says: turn on IOMMU (AMD) or VT-d (Intel) in the BIOS. Leave the *Experts only* line alone unless you understand the risk |
| `… this PC has an external DMA-capable port (Thunderbolt/USB4)` | Kernel DMA Protection is off and the PC has such a port | Update the BIOS and turn on Kernel DMA Protection, if your PC maker offers it |
| `This hardware profile only recommends DMA protection.` … `Encrypt anyway? Type YES` | The `generic` profile warns instead of refusing | Fix the BIOS setting if you can. Otherwise decide, and type `YES` to go on |
| `No backup location chosen - nothing changed.` | You closed the folder picker | Run it again and pick a USB stick or network folder |
| `Backup location(s) on the drive being encrypted are not allowed` | You picked a folder on `C:` | Pick a USB stick or a network share |
| `BitLocker policy does not allow this unlock method: …` | Something changed the BitLocker start-up policy | Remove other hardening tools ([why](reference/SECURITY-BASELINE.md#other-hardening-tools)), then put the kit's policies back with the commands the message prints |
| A blue **BitLocker recovery** screen at start-up | Something the TPM measures changed: a BIOS setting, a BIOS update, a new start-up device | Type the 48-digit recovery key from your backup. Next time, pause BitLocker first ([before any BIOS change](GUIDE.md#before-any-bios-change)) |
| You forgot the BitLocker start-up PIN (only if you added one) | | Press Esc at the PIN screen and type the recovery key. Then set a new PIN: `Enable-BitLocker.cmd -AddPin` |

## The validator's report

Rows of *Validate PC* that need more than their own message. The first column is the row's name.
In the window and in the report each name follows its area, for example `Security: BitLocker on,
TPM-only`. The window shows only the FAIL and WARN rows in full;
`C:\ProgramData\W11Kit\Validate-Pc.cmd -All` prints every row, and the report file has them all.
A WARN or FAIL row whose message doesn't say what to do has a *Fix:* line: for a setting that
comes from the kit's local Group Policy, putting the policies back
([Changing a setting later](reference/SECURITY-BASELINE.md#changing-a-setting-later)); for a
device, Device Manager and [a device without a driver](AFTER-INSTALL.md#a-device-without-a-driver).
For a scheduled task or a script, run it with an exit code (as administrator):
`powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\W11Kit\Test-InstalledPc.ps1 -ExitCode`
exits with 0 (no FAIL or WARN), 1 (WARN only) or 2 (at least one FAIL).

With `options.scheduledValidation` (on by default), the task *W11Kit Validate PC* runs the
validator on Sundays at 12:00 and after a Windows Update restart (when Windows' build changed
since the last report), as SYSTEM. A row that is FAIL and wasn't in the report before shows as a
message to whoever is signed in: *W11Kit Validate PC: N new FAIL row(s) since the last report*.
Its log: `C:\ProgramData\W11Kit\Logs\scheduled-validation.txt`.

The rows about one account's own settings (*Variable refresh rate*, *Game Mode*, apps installed for
one account) read the daily account's when the validator runs as another account (elevated, or
the scheduled run) and the daily account is signed in; the row names whose settings it read. When
the daily account isn't signed in, the row says so: sign in as it and run *Validate PC*.

For your own tools, `W11Kit-Validation.json` (next to the report) has `schemaVersion` (1),
`kitRevision`, `profile`, `osBuild` (like `26300.9711`), `generated`, `inventory` (`drivers`, `services` and `firewallInbound`: sorted lists of texts), `preRestart`, `summary` (`fail`, `warn`, `pass`, `info` and
the `exitCode` above) and `rows`, each with `area`, `check`, `result` (PASS, WARN, FAIL or INFO),
`detail`, `hardware` and `fix` (what to do, on a WARN or FAIL row; empty otherwise). A new field leaves `schemaVersion` as it is; a renamed, removed or
retyped field raises it. Row names can change between kit versions: match on `area` and `result`
rather than on a `check` text.

### After the install

| Row | What it means | What to do |
|---|---|---|
| WARN `PostInstall finished cleanly` with `Sysmon : this Windows image has no optional feature named Sysmon …` | The Windows in the image is older than the update that brought Sysmon | Nothing is broken; there is just no Sysmon log. It comes with the next rebuild on current updates |
| WARN `PostInstall finished cleanly` with `Sysmon : …` (anything else) | The first-boot setup couldn't turn on [Sysmon](GLOSSARY.md#sysmon). The PC is complete otherwise: Sysmon only records | Restart once, then validate. The row *Sysmon running (built into Windows)* shows the commands to install it by hand |
| WARN `PostInstall finished cleanly` with `Firewall rule (outbound SMB to the Internet) : …` | Windows Firewall hadn't loaded the kit's rule yet when the first-boot setup checked | Restart, then validate. If *Outbound SMB to the Internet blocked (firewall rule)* still WARNs, run the command it shows |
| WARN `PostInstall finished cleanly` with `PowerShell event log size : …` | The PowerShell log kept Windows' small size | PowerShell (as administrator): `wevtutil sl Microsoft-Windows-PowerShell/Operational /ms:268435456` |
| WARN `Sysmon running (built into Windows)` … `Sysmon records nothing` | Sysmon isn't running | If the row says the one-time setup task is still registered, restart and validate again. Otherwise run the commands in the row |
| WARN `Windows RE on its own recovery partition` … `Windows RE is on the Windows partition` | The disk has no [recovery partition](GLOSSARY.md#recovery-partition), so the rescue tools stop working once `C:` is encrypted | The install went onto an existing partition. Easiest: reinstall and delete all the disk's partitions first ([step 12](GUIDE.md#step-12-install)) |
| WARN `HVCI not UEFI-locked` | A memory-protection setting is locked into the firmware, left by the Windows that was on this PC before | It works and is secure. What it means and how to clear it: [overrides](reference/SECURITY-BASELINE.md#overrides) |

### Secure Boot and BitLocker

| Row | What it means | What to do |
|---|---|---|
| WARN `Installed boot manager signed with Windows UEFI CA 2023` … `still the 2011 boot manager` | The PC still starts with the start-up program signed by Microsoft's 2011 certificate | Run the two commands the row shows, restart twice, validate again. If it stays, update the BIOS ([background](reference/SECURITY-BASELINE.md#secure-boot-2023-certificates)) |
| WARN `Secure Boot 2023 update: no error recorded` … `the firmware refused part of the update` | Windows tried to install the new Secure Boot certificates and the firmware said no | Install the newest BIOS from the PC maker, restart twice, validate again |
| WARN `BitLocker on, TPM-only` … `SUSPENDED` | BitLocker was paused and not turned back on | PowerShell (as administrator): `Resume-BitLocker -MountPoint C:` |
| WARN `BitLocker on, TPM-only` … `not encrypted yet, but BitLocker is prepared: restart the PC` | You ran *Enable BitLocker* and haven't restarted since | Restart |
| WARN `BitLocker bound to Secure Boot (PCR 7)` | BitLocker watches the firmware itself instead of the Secure Boot state ([PCR 7](GLOSSARY.md#pcr-7)). It works, but every BIOS change asks for the recovery key | Always pause BitLocker before a BIOS change. To bind it properly, follow the two commands in the row, with the recovery key at hand |
| WARN `BitLocker recovery key on file is the current one` | The recovery key on the disk was replaced after you saved it | `C:\ProgramData\W11Kit\Enable-BitLocker.cmd -ExportOnly`, save the new key, replace every old copy |
| INFO `BitLocker recovery key on file is the current one` … `no record for C:` | BitLocker was turned on with another tool | Run `Enable-BitLocker.cmd -ExportOnly` once |

### Defender, updates and settings

| Row | What it means | What to do |
|---|---|---|
| WARN `Defender tamper protection` | [Tamper protection](GLOSSARY.md#tamper-protection) is off. Right after the install it is INFO: Windows turns it on with Defender's first update | Windows Security → Virus & threat protection → Manage settings → **Tamper Protection: On** |
| WARN `Defender running in normal mode` | A second antivirus is installed, or Defender is broken | Uninstall the other antivirus (the image relies on Defender), restart, validate again |
| WARN `Defender signatures current (3 days)` | No new signatures for more than 3 days | Go online. Windows Security → Virus & threat protection → Protection updates → Check for updates |
| WARN `Defender quick scan in the last 14 days` | No scan for two weeks | Windows Security → Virus & threat protection → Quick scan |
| WARN `No Defender exclusions left behind` | Defender is told to skip a folder or program | If you don't know it, remove it: PowerShell (as administrator), `Remove-MpPreference -ExclusionPath '<path>'` or `-AttackSurfaceReductionOnlyExclusions '<path>'` |
| WARN `An update installed in the last 40 days` | Windows hasn't installed anything for over a month | Settings → Windows Update → Check for updates |
| WARN `No restart pending for updates` | Updates are installed but not active yet | Start → Power → **Restart** (not Shut down) |
| WARN `Overrides and kit policies: every value in effect` or `Security options the kit sets` | A setting the kit made has another value now | Put the kit's settings back ([changing a setting later](reference/SECURITY-BASELINE.md#changing-a-setting-later)). The row names the values |
| WARN `Services the kit disables` | A service the image switches off is on again | PowerShell (as administrator): `Set-Service <name> -StartupType Disabled; Stop-Service <name>` |
| WARN `WPAD off and strict signature check on`, `PowerShell log size 256 MB`, `Outbound SMB to the Internet blocked (firewall rule)`, `WSL firewall (Hyper-V firewall) on, inbound blocked` | One of the kit's settings was changed back | Run the command the row shows |
| WARN `Firewall on for every network type` | Windows Firewall is off for a network type | Windows Security → Firewall & network protection: turn it on |
| WARN `Removed apps not reinstalled` | The Store put a removed app back, or you installed it | A note only ([removed apps](reference/REMOVED-APPS.md#if-a-removed-app-comes-back)) |
| WARN `No second hardening tool` | Another hardening tool is installed. Its settings may conflict with this image | Uninstall it ([other hardening tools](reference/SECURITY-BASELINE.md#other-hardening-tools)), then put the kit's settings back ([changing a setting later](reference/SECURITY-BASELINE.md#changing-a-setting-later)) |
| INFO `Xbox service …` with `Disabled (the baseline's value is Disabled; the kit makes it usable only with options.gamingTweaks in the settings)` | The image was built without the gaming option, so Microsoft's baseline keeps the Xbox services off | Nothing, unless a game needs them: then set `options.gamingTweaks` to `true` and rebuild ([gaming](reference/CONFIGURATION.md#gaming)) |

### Accounts, network, disk and backups

| Row | What it means | What to do |
|---|---|---|
| WARN `Administrators group: only LocalAdmin` | Another account is an administrator | If you didn't add it: `Remove-LocalGroupMember -Group Administrators -Member '<name>'` (PowerShell as administrator), and find out where it came from |
| WARN `Enabled accounts: only LocalAdmin and LocalUser` | There is another account that can sign in | Fine if you made it. If not: `Disable-LocalUser -Name '<name>'` |
| WARN `No remote shell service (OpenSSH server, WinRM)` or `Remote-access tools` | A remote-access service runs, or starts with Windows | Set it to start by hand: `Set-Service <name> -StartupType Manual`. You want it always on: set `reminders.remoteAccessOnDemand` to `false` |
| WARN `No shared folders or printers` | A folder or printer of this PC is shared, so the file-sharing service is on again | Stop sharing what you don't need. The row *Services the kit disables* shows how to switch the service off |
| FAIL or WARN `Disk health` | Windows says the disk is failing | **Back up now.** Then check with the disk maker's tool and replace the disk |
| WARN `System drive has 15 % free` | `C:` is nearly full | Settings → System → Storage → Cleanup recommendations. The kit's leftovers: [Freeing space](#freeing-space) |
| WARN `Security log reaches back 7 days` | Something writes so many security events that a week doesn't fit | Run the command in the row to see which event floods the log |
| WARN `Offline backup in the last 35 days` | No offline backup recorded for over a month | [Offline backup](MONTHLY.md#offline-backup) |
| WARN `OneDrive folder backup` (only if you turned that reminder on) | Documents, Desktop or Pictures isn't in OneDrive | As the daily account: Settings → Accounts → Windows backup |

### Since last report

| Row | What it means | What to do |
|---|---|---|
| INFO `Security events since the last report` … `counting starts with this report` | There is no earlier report to compare with | Nothing |
| WARN `No new user accounts` | An account was created since the last report | If it wasn't you or something you installed: disable it, run a full Defender scan, change your passwords |
| WARN `No additions to local groups` | An account was put into a group | Expected after installing software that makes its own group. Otherwise remove it; the row shows who and where |
| WARN `Security log not cleared` | Somebody emptied the Security log. Hardly any program does that | If it wasn't you: full Defender scan, new passwords from another device, and consider reinstalling from the stick |
| WARN `No malware detections` | Defender found something | Windows Security → Virus & threat protection → Protection history: was it removed? Where did the file come from? |
| INFO `Attack surface reduction: audited only` | Counts what a rule *would* have blocked | Nothing |
| INFO `Drivers (not from Windows) since the last report`, `Services and start types …`, `Inbound firewall rules allowed …` | What is new or different compared with the last report's list (`inventory` in its `.json`). A driver update shows as new (its new version) and as gone (its old one) | After Windows Update or an install: expected. A service or an inbound rule you can't place deserves a look (Services; Windows Defender Firewall → Inbound Rules) |
| INFO `NTLM use (audited)` | [NTLM](GLOSSARY.md#ntlm) is an old sign-in method. The image logs its use and blocks nothing | Nothing. The devices listed still need it (an old NAS or printer) |

## Everyday use

What behaves differently on the installed PC, and why, is in one table:
[What is different on this PC](AFTER-INSTALL.md#what-is-different-on-this-pc). The rows below are
the problems that table doesn't cover.

| What you see | What it means | What to do |
|---|---|---|
| A Microsoft Store install fails with error 404 | The country in Windows is *World* | Settings → Time & language → Language & region → Country or region: your country |
| A program you removed is back | The Store reinstalled it | [If a removed app comes back](reference/REMOVED-APPS.md#if-a-removed-app-comes-back) |
| *Reset this PC* is tempting after a problem | It puts a plain Windows back and removes what the kit set up | Don't. [Never use Reset this PC](AFTER-INSTALL.md#never-use-reset-this-pc) |
| `Restore-BuildInputs.cmd`: `C:\W11Kit exists, is not a Git clone of the kit and is not empty (it holds: …)` | That folder already holds other files | Nothing was restored. Rename the folder and run it again, or restore elsewhere: `Restore-BuildInputs.cmd D:\W11Kit` |
| `Restore-BuildInputs.cmd`: `The kit is not checked out yet: Git for Windows is missing.` | You answered `n` to installing Git, or its install failed | Install Git (the installer is in `C:\W11Kit\work\installers`) and run it again. Files in place are skipped |
| `Restore-BuildInputs.cmd`: `C:\W11Kit is already a Git clone: left as it is` | The kit is already there | Nothing. The files went into its `work` folder |
| `Restore-BuildInputs.cmd`: `… does not match the manifest … The USB copy is damaged; nothing was written.` | A file on the stick doesn't have the hash recorded at build time | Write the stick again from the ISO on your backup drive, then run it again |

## Freeing space

Everything the kit downloads or makes is in one folder, `C:\W11Kit\work`. Nothing of it is
anywhere else on the PC; only the Windows ISO you downloaded yourself is in your Downloads. How
much the kit needs: [disk space](reference/BUILD-OPTIONS.md#disk-space).

The folder is locked, so Windows asks for administrator approval when you delete in it.

**Piece by piece**, safe to delete once you no longer need them:

| What | Where | When |
|---|---|---|
| Older ISOs, each with its `.sha256` and `.manifest.json` (about 28 GB each) | `C:\W11Kit\work\Win11Pro-*.iso` | When the newest ISO is on your backup drive and stick. Keep the passwords file whose last line names the ISO you install |
| Test builds and their passwords | `C:\W11Kit\work\*-TEST-*.iso` and `test-accounts.txt` | Any time. They're never installed on a real PC |
| The VM test's files | `C:\W11Kit\work\vmtest` | Any time no test is running. After `RESULT: PASS` the test deletes the VM's disk itself; after a failed test the disk (20 GB or more) stays until the next test |
| Older driver harvests | `C:\W11Kit\work\DriverExport.<date>` | Any time. The build uses `C:\W11Kit\work\DriverExport` |
| Old logs | `C:\W11Kit\work\logs` | Any time. The build deletes logs older than 30 days itself |
| The imported baseline data | The folders (not the `.zip` files) in `C:\W11Kit\work\baselines` | Any time. Every build makes them again from the zips |

**Don't delete before your next build:** `DriverExport`, `DriverExport.zip`, `updates`,
`baselines` and `installers` in `C:\W11Kit\work`, and the Windows ISO. The build can download the
updates, baselines and installers again, but not the Windows ISO or your drivers.

**To get all the space back:**

> [!CAUTION]
> This deletes your harvested drivers, every ISO and the passwords file. Save `accounts.txt` and
> any ISO you still need first.

In a Command Prompt (as administrator):

```
rmdir /s /q C:\W11Kit\work
```

The kit itself stays and works. The next build offers to download the updates and the security
baselines again and to collect the drivers again
([step 6](GUIDE.md#step-6-collect-the-drivers)).

**To remove the kit completely:** delete `C:\W11Kit`. The work folder goes with it.

---

← [Home](../README.md) · [Guide](GUIDE.md) · [Glossary](GLOSSARY.md)
