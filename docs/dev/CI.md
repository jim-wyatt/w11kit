# Running the test cycle on your own self-hosted runner

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

The repository's own workflow only lints ([Syntax gate](TESTING.md#syntax-gate)). A build and a
VM test need an elevated Windows PC with Hyper-V, which a hosted runner is not. This page says
what it takes to run them on a runner of your own. It works with any CI system that can run a
PowerShell step on a Windows machine.

> [!CAUTION]
> **Never attach a self-hosted runner that runs as an administrator to a public repository, and
> never let it run pull requests from forks.** A workflow is code. Whoever can get a workflow to
> run on that runner is an administrator of that PC. Keep such a runner on a private repository
> or a private mirror, registered for that one repository only.

## What a cycle is

1. **Check out** the commit to test.
2. **Fetch the inputs**: `py scripts\Get-Updates.py --dest C:\W11Kit\work\updates` and
   `py scripts\Get-Baselines.py --dest C:\W11Kit\work\baselines`. Each checks every file and ends
   with exit code 0 only when everything is in place; files already there are kept.
3. **Build**: `scripts\Build-Iso.ps1 -TestBuild -Profile <id> -WorkRoot C:\W11Kit\work`. The
   script asks nothing. Its log has a line that starts with `ISO:` and names the finished ISO.
4. **VM test**: `scripts\Test-IsoInHyperV.ps1 -IsoPath <that ISO> -WorkRoot C:\W11Kit\work`.
5. **Judge** by the exit code: 0 (the summary says `RESULT: PASS`) or 1 (`RESULT: FAIL`).

To test the very ISO you would install, build without `-TestBuild` and with `-EncryptAccountsTo`
([Unattended builds and encrypted passwords](MAINTAINING.md#unattended-builds-and-encrypted-passwords)),
then run the VM test on that ISO. What you install is then what was tested.

## What the runner needs

- **Windows 11 Pro, Enterprise or Education**, 24H2 or later, x64, with **Hyper-V** on.
- **An account that can elevate without a prompt.** Nobody is there to approve a UAC prompt, so
  the runner's account is a local administrator and its jobs run elevated.
- **The source ISO**, in `C:\W11Kit\work\source`. Microsoft blocks scripted ISO downloads, so
  you put it there once by hand.
- **The drivers**, for any profile but `generic`: a harvest in `C:\W11Kit\work\DriverExport`.
- **The build tools**: run `C:\W11Kit\Run-Prepare.cmd -Yes` once, then restart the runner's
  service so it sees the new `PATH`.
- **Disk space**: [Disk space](../reference/BUILD-OPTIONS.md#disk-space), plus every ISO you keep.
- **One job at a time.** A build and a VM test share the work folder.

## Things that differ from a build by hand

- **Pass `-WorkRoot` to every script.** A script's default work folder is `work\` inside its own
  kit folder, and a runner empties its checkout for every job. A fixed work folder keeps the
  updates and the drivers between jobs.
- **Lock the folder above the work folder.** The build locks its work folder, but not the folder
  above it ([Folder lock](BUILD-INTERNALS.md#folder-lock)). Keep that folder (here `C:\W11Kit`)
  writable by administrators only.
- **Load scripts as scriptblocks** where a policy blocks `.ps1` files. A runner usually writes
  each step to a `.ps1` file and runs it, and machine policy beats `-ExecutionPolicy Bypass`.
  The kit's launchers load every script like this:

  ```powershell
  & ([scriptblock]::Create([IO.File]::ReadAllText('C:\src\kit\scripts\Build-Iso.ps1'))) -KitRoot C:\src\kit -TestBuild
  ```

  The script cannot find its own folder then, so always pass `-KitRoot`.
- **Your settings.** A job has no `Run-Build.cmd`, so nothing is read from the PC: without a
  settings file the image gets the kit's defaults (US keyboard, `en-US` formats, time zone UTC),
  and the build prints a `[NOTE]`. Put your own file at `config\settings.local.json` in the
  checkout before the build, or pass `-Settings <file>`
  ([Your settings](../reference/CONFIGURATION.md#your-settings)).
- **Python is required.** Every build imports the security baselines with it.
- **Defender's ransomware protection on the runner.** A PC installed from the kit runs with
  Controlled Folder Access and the ASR prevalence rule on. Both CI workflows pass
  `-PauseDefenderProtection`, so each build pauses them and restores them when it ends
  ([The build PC](../reference/CONFIGURATION.md#the-build-pc)). A runner job is that consent.
- **Keep the PC awake.** Each script holds the PC awake only while it runs.
- **Kept ISOs.** If the runner keeps the ISOs it builds, keep few, and remember that every local
  user of that PC can read them. An ISO holds its one-time passwords only obfuscated.
- **A test build's ISO must never be installed on a real PC.** Delete it when the job ends.

## If the runner is the PC you reinstall

Reinstalling it wipes the runner, the checkout and the work folder. After the install, run
`Restore-BuildInputs.cmd` from the stick ([Self-hosting](BUILD-INTERNALS.md#self-hosting)) and
set the runner up again. Two things on a kit install matter to a runner:

- A `hibernate` profile hibernates the PC after 30 minutes idle. A scheduled job cannot start
  while it hibernates: wake the PC first.
- The image disables the Secondary Logon service, so `runas` does not work
  ([DISA STIG additions](../reference/SECURITY-BASELINE.md#disa-stig-additions)).
