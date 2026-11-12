# W11Kit: brief for AI coding agents and contributors

W11Kit builds a custom, security-hardened Windows 11 Pro install ISO for a user's own PC, from the
Windows that PC runs today, tests it in a Hyper-V virtual machine, and installs it unattended. It
runs on a Windows build PC (Windows PowerShell 5.1, elevated). The kit itself is not installed on
the PC; only its first-boot payload is (`C:\ProgramData\W11Kit`).

Three kinds of input shape an image:

- **The hardware profile** (`profiles/<id>/profile.json`): what differs between PC models.
- **The user's settings** (`config/settings.local.json`, untracked) over the kit's defaults
  (`config/settings.defaults.json`): keyboard and formats, time zone, account names, options,
  reminders.
- **The kit's opinions** (the rest of `config/`, and the scripts): the same for every PC.

Everything the kit downloads or makes is in one work folder, `<kit>\work` (`<work>` below;
git-ignored; `-WorkRoot` moves it).

## The pipeline

| Step | Entry point | What it does |
|---|---|---|
| Prepare | `Run-Prepare.cmd` → `scripts/Prepare-BuildPc.ps1` | Checks the build PC (edition, x64, virtualization, Defender settings that block DISM, free space) and offers to install the build tools and Hyper-V. |
| Build tools | `scripts/Install-BuildTools.ps1` | Git, Python 3 and the ADK Deployment Tools, on demand, from installers pinned in `config/installers.json` (SHA-256 and signer). Never winget. |
| Profile | `New-Profile.cmd` → `scripts/New-HardwareProfile.ps1` | Writes a profile from the running install. `scripts/KitProfile.ps1` resolves and validates profiles. |
| Harvest | `Run-Harvest.cmd` → `scripts/Invoke-DriverHarvest.ps1` | Exports the running install's drivers and keeps the profile's providers (never class `Firmware`) in `<work>\DriverExport\_Curated`. |
| Downloads | `scripts/Get-Updates.py`, `scripts/Get-Baselines.py`, `scripts/Get-Installers.py` | Pinned in `config/updates.json`, `config/baselines/<id>/source.json` and `config/installers.json`. |
| Build | `Run-Build.cmd` → `scripts/Invoke-KitLauncher.ps1` → `scripts/Build-Iso.ps1` | The launcher prints the notice, reads this PC's keyboard, formats, time zone and country before it elevates, and asks the questions, in this order: update the kit, old update pins, tools, downloads, profile, drivers; after the build, the VM test. `Build-Iso.ps1` never asks. |
| VM test | `Run-VmTest.cmd` → `scripts/Test-IsoInHyperV.ps1` | Hands-off install in a Hyper-V VM with Secure Boot and a TPM, graded against `config/vm-expected.json`: `RESULT: PASS` or `RESULT: FAIL`. |

`Build-Iso.ps1`, in order:

1. Folder lock (`scripts/KitAcl.ps1`): the kit, the work folder and the driver export become
   writable by Administrators and SYSTEM only. `-Preflight` only reports.
2. Preflight: settings (`scripts/KitSettings.ps1`), profile, source-ISO hash and language, update
   files, driver manifest, baseline zips against their pins, Python.
3. Baselines imported from Microsoft's zips (`scripts/Import-Baseline.py`) into
   `<work>\baselines`, at every build: Python is required.
4. Pro image exported; updates in Microsoft's order, each file's SHA-1 checked against its name
   right before it is applied; drivers; app removals; WSL features; offline registry.
5. First-boot payload staged (`payload/`, the baseline data, the overrides, the profile, the
   effective settings).
6. DISM read-back (`scripts/Test-OfflineImage.ps1`): any mismatch fails the build.
7. Split WIM; `boot.wim` serviced, with storage drivers; Setup files and the 2023 boot manager
   taken from it and compared; answer file; build inputs; `oscdimg`.

On the installed PC, `payload/PostInstall.ps1` runs once at the first automatic sign-in.
`Apply-Policy.ps1` merges the baselines, the overrides and the kit's policies into one local Group
Policy and reads the overrides back. Then come registry settings, AppLocker, the firewall rule,
Sysmon, power per profile, a validation snapshot and a restart (cancelled if the overrides
failed). The validator (`payload/Test-InstalledPc.ps1`) is the *Validate PC* desktop shortcut.

Details: [docs/dev/BUILD-INTERNALS.md](docs/dev/BUILD-INTERNALS.md).

## Working rules

**Code**

- **Windows PowerShell 5.1 only.** No PowerShell 7 syntax or modules.
- **Scripts are loaded as scriptblocks** (some PCs block `.ps1` files by policy). `$PSScriptRoot`
  is empty: pass `-KitRoot`. `$script:` points at the caller's scope: don't use it for state.
- **Run native tools under a local `$ErrorActionPreference = 'Continue'`** and judge them by
  `$LASTEXITCODE`. Under `'Stop'`, redirected stderr from `reg.exe` or `oscdimg` is a terminating
  error.
- **Never print a secret.** The build console is transcribed. Passwords exist only in the
  admin-only `<work>\accounts.txt`.
- **Verify every GUID, policy key and value name against Microsoft's reference**, or against
  `C:\Windows\PolicyDefinitions\*.admx`. A check that reads back the value it was given proves
  nothing about the value. Never invent a registry value, a parameter or an API.
- **`Build-Iso.ps1` stays non-interactive.** Questions belong in `Invoke-KitLauncher.ps1`.
- **Nothing in the image may block a build**: the installed PC must be able to rebuild its own
  ISO.
- **Built-in Windows tools only on the installed PC.** No Microsoft files, no baseline data and
  no third-party binaries in the repository.
- Read the group for your tool in [docs/dev/GOTCHAS.md](docs/dev/GOTCHAS.md) before you change
  DISM, ACL, AppLocker, Group Policy or boot-media code.

**Docs**

- **Docs change with the code, in the same commit.** An override, decision, check or message that
  changes belongs in the matching page.
- **One home per fact.** Other pages give one sentence and a link. The glossary and the
  troubleshooting page quote the kit's messages: keep them in step when a message changes.
- **Model-specific facts go in the profile's README**, not in the general docs.
- **No project history and no personal habits** in docs, comments or messages: no dates of
  internal decisions, no incident stories, no commit hashes. Keep the technical reason.
- **A decision changes only on purpose**: update [docs/dev/DECISIONS.md](docs/dev/DECISIONS.md)
  with it.
- Plain words and short sentences, for a first-time power user.

**Before every commit**

- Run the syntax gate: `bash dev/Test-KitSyntax.sh` (PowerShell 5.1 parser, Python, bash, JSON,
  the profiles with `dev/Test-Profiles.py`, and the doc links with `dev/Test-DocLinks.py`; it
  takes seconds).
- A change to what the image contains is proven by the Hyper-V VM test
  ([docs/dev/TESTING.md](docs/dev/TESTING.md#the-hyper-v-vm-test)).

## Where things are

| Read | For |
|---|---|
| [README.md](README.md) | What the kit is, status, layout |
| [docs/GUIDE.md](docs/GUIDE.md), [AFTER-INSTALL](docs/AFTER-INSTALL.md), [MONTHLY](docs/MONTHLY.md) | The user's path |
| [TROUBLESHOOTING](docs/TROUBLESHOOTING.md), [GLOSSARY](docs/GLOSSARY.md) | The kit's messages; terms |
| [CONFIGURATION](docs/reference/CONFIGURATION.md), [SECURITY-BASELINE](docs/reference/SECURITY-BASELINE.md) | What the image sets; every security setting and override |
| [BUILD-OPTIONS](docs/reference/BUILD-OPTIONS.md), [PROFILES](docs/reference/PROFILES.md), [DRIVERS](docs/reference/DRIVERS.md), [REMOVED-APPS](docs/reference/REMOVED-APPS.md) | Switches and outputs; profiles; driver rules; app removals |
| [docs/dev/DECISIONS.md](docs/dev/DECISIONS.md) | Why the kit is the way it is |
| [docs/dev/GOTCHAS.md](docs/dev/GOTCHAS.md) | Tool behaviour that cost time, by tool |
| [docs/dev/BUILD-INTERNALS.md](docs/dev/BUILD-INTERNALS.md) | How the build works |
| [docs/dev/TESTING.md](docs/dev/TESTING.md) | How the image is checked; status |
| [MAINTAINING](docs/dev/MAINTAINING.md), [DEPENDENCIES](docs/dev/DEPENDENCIES.md) | Moving the pins, new baselines; every external input |
| [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) | How to contribute; threat model and reporting |
