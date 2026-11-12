# Testing

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

How the image is checked, what has been proven so far, and what a change needs before it is
merged. The switches of `Run-VmTest.cmd` are in
[VM test options](../reference/BUILD-OPTIONS.md#vm-test-options); messages and what to do about
them are in [TROUBLESHOOTING](../TROUBLESHOOTING.md#the-vm-test).

On this page `<work>` is the work folder (`C:\W11Kit\work` unless `-WorkRoot` names another).

## How the image is checked

Three layers. Each one catches what the layer before it cannot see.

| Layer | Tool | When | What it proves |
|---|---|---|---|
| The image, offline | `scripts\Test-OfflineImage.ps1` | Every build, before the ISO is written | What the build meant to put into the image is in it |
| The install, in a VM | `scripts\Test-IsoInHyperV.ps1` (`Run-VmTest.cmd`) | After a build | The ISO installs hands-off, first-boot setup finishes, and the installed Windows passes the validator |
| The installed PC | `payload\Test-InstalledPc.ps1` (*Validate PC*) | At first boot, then whenever you run it | The real hardware and the settings in effect |

Before any of them, a seconds-long [syntax gate](#syntax-gate) runs on every commit.

### Layer 1: the offline read-back

The build mounts the image, changes it, and then reads it back with DISM. Any mismatch stops the
build before the image is saved. It checks:

- the edition is Professional, and the update level is above the source ISO's;
- a cumulative update newer than the source is installed, and no package operation is pending;
- every curated driver is in the image;
- every feature in `config\image.json` is in the state the file asks for;
- the removed apps are gone, each is marked deprovisioned, and the required apps are still there
  (the two Xbox apps count as required only with `options.gamingTweaks`);
- every registry value the kit sets (`Set-KitRegistry.ps1 -Verify`, with the staged profile and
  settings);
- `Winre.wim` is present;
- every payload file is staged, and `profile.json` names the same profile as
  `build-options.json`;
- the baseline data in the image is what the import of the pinned zips gave: each file's SHA-256
  as in its `index.json`;
- the staged security template carries the built-in accounts' new names that
  `build-options.json` records, and its Xbox service lines and the Start layout's Xbox pin follow
  `options.gamingTweaks`.

One value may be missing offline: the Widgets policy, which some build PCs refuse to write. It is
marked `-DeferToGp` in `Set-KitRegistry.ps1`, applied through Group Policy at first boot, and
checked there.

A second pass, `-BootMedia`, checks the boot side after `boot.wim` has been serviced
([Boot media](BUILD-INTERNALS.md#boot-media)). Reports: `<work>\logs\verify-<stamp>.txt` and
`verify-boot-<stamp>.txt`.

### Layer 2: the VM test

[The Hyper-V VM test](#the-hyper-v-vm-test), below.

### Layer 3: the validator

First-boot setup (PostInstall) runs the validator once, before its restart: the *pre-restart
snapshot*. Some rows show their pre-restart state there (memory integrity, UAC), so they are INFO
instead of WARN. After that the validator is the *Validate PC* shortcut on the desktop. It writes
`W11Kit-Validation.md` and `W11Kit-Validation.json`; `FAIL: 0` is the goal.

What a healthy install shows, in general terms:

| Area | The validator checks |
|---|---|
| Devices | No unknown or failed device; the profile's own device checks; driver and BIOS age |
| Power | What the profile's `power` asks for: hibernate available, idle and button values, Wake-on-LAN armed on the profile's adapter |
| Security | Every baseline value in effect, one row per override, the DISA STIG additions, memory integrity, DMA protection, BitLocker, Secure Boot certificates, AppLocker |
| Updates and Store | Update services not disabled, no drivers from Windows Update, Store packages present, home location as in the settings |
| Apps | Removed apps stay removed; the required apps are present |
| Self-hosting | Nothing on the PC would block its next build ([Self-hosting](BUILD-INTERNALS.md#self-hosting)) |
| Reminders | What your settings switch on under `reminders`: backups, remote access, expected apps |
| Since last report | Sign-in failures, new accounts, group changes, new services and tasks, Defender detections; drivers, services and inbound firewall rules compared with the last report |

What each row means and what to do about it:
[The validator's report](../TROUBLESHOOTING.md#the-validators-report).

## Status

Built and tested in Hyper-V virtual machines for the `legion-t5` and `generic` profiles, and installed
on the `legion-t5` reference PC.

| | What | State |
|---|---|---|
| Proven | The build | Passes for `legion-t5` and `generic` |
| Proven | The offline image check and the boot-side check | Pass in every build |
| Proven | The Hyper-V VM test: hands-off install, first-boot setup, validator | `RESULT: PASS` for `legion-t5` and `generic` |
| Proven | A build with the kit's default settings only (no `config/settings.local.json`) | `RESULT: PASS` for `generic` |
| Proven | A build with other settings (another keyboard, formats and time zone, renamed accounts, a computer name, `allowMicrosoftAccount`) | `RESULT: PASS` for `generic` |
| Proven | An install on real hardware | The `legion-t5` reference PC: Setup, first-boot setup with no failures, the profile's drivers, the validator |
| Proven | A USB boot of the 2023-signed media on real firmware | On the `legion-t5` reference PC |
| Proven | Wake-on-LAN | On the `legion-t5` reference PC (the profile's Realtek 2.5GbE adapter) |
| Proven | A build on the installed PC from the repository alone | The `legion-t5` reference PC: every input except the Windows ISO downloaded again from the pins, its drivers harvested, then build and VM test `RESULT: PASS` |
| Proven | A storage driver from the curated set goes into both `boot.wim` images and is read back | With one non-inbox `SCSIAdapter` driver in a `legion-t5` test build; the VM test still passes |
| Not proven | Setup listing a disk behind a controller that needs such a driver (Intel VMD, RAID) | Needs a PC with one. The VM's disk and the reference PC's use Windows' own drivers |
| Not proven | Turning BitLocker on (`Enable-BitLocker.cmd`) | A manual step the VM test never runs; on the reference PC BitLocker was turned on through Windows' own settings instead |
| Not proven | Restore and rebuild on the installed PC (`Restore-BuildInputs.cmd`, then a build) | Not done yet |
| Not proven | Builds with `-Use2011BootManager` or `-NoBuildInputs`, and a real build with `-EncryptAccountsTo` outside the monthly workflow | Their pre-flight passes; no such ISO has been built and installed in a test |
| Not proven | A profile with `productKey` `firmware` or `prompt`; running the first-boot setup a second time | Never run in a recorded test |
| Not proven | Display languages other than `en-US` | Supported by the settings, untested |
| Not proven | A profile made with `New-Profile.cmd` on another PC | Not done yet |

A VM cannot prove real hardware. Device drivers, Wake-on-LAN, hibernation on the power button,
BitLocker with a real TPM and the firmware's boot of the media are proven only on a PC. When a
change touches one of them, say so in the pull request.

## The Hyper-V VM test

`Run-VmTest.cmd` → `scripts\Test-IsoInHyperV.ps1`, elevated. It needs Hyper-V
(`Run-Prepare.cmd` offers to turn it on) and takes 15 to 45 minutes.

You can test the real ISO: the test makes its own copy and never changes the ISO you install.

**What it does:**

1. Locks its folder, `<work>\vmtest`, like the build's folders, and removes an earlier test's VM
   first (the old VM holds the old copy open).
2. Checks the free space: 2 × the ISO's contents without `BuildInputs`, plus 30 GB for the VM's
   disk.
3. Makes **the VM test's copy**, `<work>\vmtest\W11Kit-VMTEST-ONLY-wipes-disk.iso`. It differs
   from your ISO in five ways:
   - disk partitioning that **wipes disk 0 without asking** (EFI, MSR, Windows, and a recovery
     partition after Windows, as Setup lays out a disk itself);
   - a check that powers the machine off unless it is a Hyper-V VM (next section);
   - the generic Windows 11 Pro installation key when the answer file has none: a VM has no
     firmware key (it only selects the edition and does not activate);
   - no *Press any key to boot from CD or DVD*;
   - no `BuildInputs` folder: Setup never reads it, so the copy is about 9 GB even for a real ISO.
4. Creates the VM and installs hands-off. It ejects the copy after Setup's first restart.
5. Follows first-boot setup through Hyper-V Key-Value Pair Exchange (progress only), waits for
   its restart, and waits for Windows to come back up (heartbeat).
6. Shuts the VM down, mounts its disk read-only, and collects the results.
7. Grades and prints `RESULT: PASS` or `RESULT: FAIL` (exit code 0 or 1).

**The VM:** Generation 2, Secure Boot with the *Microsoft Windows* template, a virtual TPM,
4 virtual processors, 6 GB of memory, an 80 GB disk, the Default Switch. No nested
virtualization.

**Time limits:**

| Limit | What happens |
|---|---|
| 120 minutes in all (`-TimeoutMinutes`) | The test stops waiting and collects what exists |
| 8 minutes without Setup's first restart (it usually comes after about 4) | The test saves a picture of the VM's screen, `vm-screen-8min.png`, and goes on waiting. Before Windows is on the disk there are no logs, so the picture is the only record of what Setup shows |
| 20 minutes without Setup's first restart | Setup stopped in its first phase (an error page). The test copies Setup's early logs from the VM disk (`early-setupact.log`, `early-setuperr.log`) |
| 6 minutes after first-boot setup reported, without a restart | First-boot setup cancelled its restart: a critical failure |
| 10 minutes without a heartbeat after that restart | Windows did not come back up |

A VM that shows the sign-in screen after the third restart is the correct end state: first-boot
setup ran during the one-time automatic sign-in and restarted. Read `postinstall-status.json`.

**Results**, in `<work>\vmtest\results` (emptied at the start of each test):

- `vmtest-transcript.txt`: the test's own console, with the summary;
- `panther-setupact.log`, `panther-setuperr.log`: Windows Setup's logs;
- `vm-screen-8min.png`, only when Setup was slow to restart: the VM's screen at that moment;
- `postinstall-status.json` and the first-boot setup log, with the policy files it applied
  (security template, `secedit` log, merged audit CSV);
- `W11Kit-Validation.json` and `.md`: the validator's pre-restart snapshot;
- `profile.json`: the profile the image carries; `grouppolicy-gpt.ini`: the local GPO's version;
- `vm-autounattend-redacted.xml`: the VM's answer file with the password values replaced by
  `(removed)`. The file itself is never kept.

**What makes a PASS.** All of these:

- first-boot setup wrote its status file, is not critical and has no failure (other than one
  listed as unavoidable in a VM);
- no cached answer file is left in `Windows\Panther`;
- Windows came back up after first-boot setup's restart;
- the validation report exists, has rows, and has no FAIL or WARN row other than those
  [expected in a VM](#rows-expected-to-fail-in-a-vm).

**Afterwards.** The VM is removed (`-KeepVm` keeps it). A passed test deletes the VM's disk
(`-KeepDisk` keeps it); a failed test's disk stays in `<work>\vmtest` as evidence, until the next
test replaces it.

### The VM test's copy refuses real hardware

The copy erases disk 0 without asking, so it must never start a real PC. Three things stand in
the way:

- **It checks where it runs.** Before Setup touches the disk, a command in the answer file reads
  the machine's maker and model. Unless they are Hyper-V's (`Microsoft Corporation`,
  `Virtual Machine`), it powers the machine off.
- **It is deleted** when the test ends, pass or fail, and with `-KeepVm` too (the VM's DVD drive
  is emptied first). If it cannot be deleted, the test says so in a warning.
- **A leftover is removed** at the start of the next build and of `Run-Prepare.cmd`.

> [!CAUTION]
> Never write `W11Kit-VMTEST-ONLY-wipes-disk.iso` to a USB stick. If you find the file, delete it.

## Rows expected to fail in a VM

A VM is not a PC, so some validator rows FAIL or WARN there for a reason that has nothing to do
with the image. The test treats a FAIL or WARN row as expected in exactly two cases:

1. **The validator marks the row `hardware: true`.** These are the profile's device checks,
   Wake-on-LAN, and the disk, firmware and driver-age rows. The VM has none of that hardware.
2. **[config/vm-expected.json](../../config/vm-expected.json) lists it**, with a reason.

What the file lists:

| Row | Why it fails in the VM |
|---|---|
| *OS \| Activation* | The copy installs with the generic key, which never activates |
| *Devices \| No failed devices*, only for *Hyper-V Virtual Machine Bus Provider* code 37 | The image turns on the Virtual Machine Platform, and the VM has no nested virtualization |
| *Security \| BitLocker on, TPM-only* | BitLocker is a manual step; the test never runs it |
| *Security \| DMA protection* | Hyper-V passes no DMA remapping to a guest |
| *Security \| Windows RE on its own recovery partition*, only when Windows RE stayed on `C:` | A safeguard for a VM disk without a recovery partition; the test's own layout has one |
| *Security \| VBS running*, *Memory integrity (HVCI)*, *Kernel-mode stack protection* | They need virtualization inside the guest |
| *Power \| Hibernate available* (a `hibernate` profile) | Hyper-V offers no hibernation to its guests |

The same file lists the first-boot setup failures a VM cannot avoid (`postInstallFailures`): the
`powercfg /hibernate` steps of a `hibernate` profile.

Rules for this file:

- An entry matches a row by `Area | Check`, and where needed by its detail text. The *failed
  devices* entry accepts only that one device: any other failed device fails the test.
- Any other FAIL or WARN is a finding. `RESULT: PASS` needs none.
- A new VM-only row goes into this file with its reason. It never goes into the validator: the
  validator must not know it runs in a test.
- The summary prints each expected row with its reason, so a reader of the log sees what was
  waved through.

## Syntax gate

Run it before every commit. It takes seconds, needs no administrator and changes nothing.

In WSL, from the repository:

```
bash dev/Test-KitSyntax.sh
```

It checks:

- every `*.ps1` with **Windows PowerShell 5.1's own parser** (it calls `powershell.exe` from WSL:
  the kit runs on 5.1, and PowerShell 7 accepts syntax that 5.1 does not);
- every `*.py` with `python3 -m py_compile`;
- every `*.sh` with `bash -n`, and with shellcheck if it is installed (shown, not fatal);
- every JSON file under `config/` parses (the baseline pins in `config/baselines/` too);
- every `profiles/*/profile.json` against the profile rules (`dev/Test-Profiles.py`);
- the unit tests of the Python logic (`dev/Test-Units.py`, standard library only): the
  Registry.pol reader and writer, the security-template and audit merges, and the update
  catalog parsing. The PowerShell logic has no unit tests yet;
- every relative link and `#anchor` in the Markdown files resolves (`dev/Test-DocLinks.py`).

It ends with one line, for example
`SYNTAX OK: 20 PowerShell, 7 Python, 2 shell, 12 JSON files, 2 profiles, 933 doc links: 0 error(s), 0 shellcheck warning(s)`,
or `SYNTAX FAIL: ...`. A page must not link to a file that is not published: the gate fails on
that too.

**`dev/Test-DocLinks.py`** can be run alone: `python3 dev/Test-DocLinks.py`. It prints
`file:line: problem` for each broken link and ends with `DOC LINKS OK: ...` or
`DOC LINKS FAIL: ...`. It doesn't check web links.

**`dev/Test-Profiles.py`** can also be run alone, with or without file names. It checks required
fields, value domains, that every regular expression compiles, and the `isoTag` and
`computerName` patterns. It mirrors `Test-KitProfile` in `scripts\KitProfile.ps1`, which the
build and the harvest run: change both together.

**The lint workflow** ([.github/workflows/lint.yml](../../.github/workflows/lint.yml)) runs the
same checks on every push and pull request, on GitHub's own runners:

- a Windows job: the PowerShell 5.1 parse, the JSON files with `ConvertFrom-Json` (what the kit
  reads them with), and `config/autounattend.xml` is well-formed;
- a Linux job: Python, `bash -n`, shellcheck (there a warning fails the run), the profile check,
  the Markdown link check and the gate itself.

It builds nothing, starts no VM and downloads nothing from Microsoft. A build and a VM test need
an elevated Windows PC with Hyper-V: [CI](CI.md).

## Reporting a test run

The repository keeps no log of test runs. A run belongs to the change it tested, so its result
goes in the **pull request description**.

What needs what:

| Change | Needs |
|---|---|
| Documentation only | The syntax gate |
| A profile | The syntax gate; a build and a VM test if you can run them ([Contributing a hardware profile](../../CONTRIBUTING.md#contributing-a-hardware-profile)) |
| The build, the payload, the validator, a config file | The syntax gate, a test build (`Run-Build.cmd -TestBuild`) and `Run-VmTest.cmd` ending in `RESULT: PASS` |

Put in the description:

- the profile, and whether it was a test build or a real build;
- the update level the image reached (the build prints it; it is `lcuBuild` in the manifest);
- the summary block the test prints, from `VM TEST SUMMARY` to the `RESULT:` line (it is in
  `vmtest-transcript.txt`);
- every row listed as `UNEXPECTED`, if the run failed, and what you learned. A failed run is
  worth reporting too;
- what the change touches that a VM cannot prove ([Status](#status)).

Never attach an ISO, `accounts.txt`, `test-accounts.txt` or an answer file.
`vm-autounattend-redacted.xml` is safe to share. Read a log before you post it: Setup logs name
the computer and the accounts.

Did you install on real hardware? That is the report the project needs most. Open an issue with
the model, the profile, and the validator's report with the computer name removed.
