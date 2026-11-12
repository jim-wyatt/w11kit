# Gotchas

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

Behaviour of Windows, PowerShell, DISM and friends that cost time while this kit was built. Each
entry gives the fact, the reason where it is known, and the rule the kit follows. Read the group
for the tool you are about to touch.

- [PowerShell 5.1](#powershell-51)
- [Launchers and elevation](#launchers-and-elevation)
- [DISM and image servicing](#dism-and-image-servicing)
- [ACLs and the folder lock](#acls-and-the-folder-lock)
- [Defender and ASR](#defender-and-asr)
- [AppLocker](#applocker)
- [Group Policy, baselines and audit policy](#group-policy-baselines-and-audit-policy)
- [Setup, boot media and Secure Boot](#setup-boot-media-and-secure-boot)
- [First-boot setup](#first-boot-setup)
- [Hyper-V VM test](#hyper-v-vm-test)
- [Microsoft's download sources](#microsofts-download-sources)
- [Windows quirks](#windows-quirks)
- [WSL](#wsl)
- [Git](#git)
- [CI on Windows runners](#ci-on-windows-runners)

## PowerShell 5.1

The kit runs on Windows PowerShell 5.1 only, because that is what every Windows 11 has.

- **`$ErrorActionPreference = 'Stop'` plus redirected native stderr is a terminating error.**
  `reg.exe` writes "not found" to stderr, and `oscdimg` writes its progress there. Run native tools
  under a local `'Continue'` and judge them by `$LASTEXITCODE` (see `Invoke-Reg` in
  `Set-KitRegistry.ps1`, and `Invoke-Quiet`).
- **Scripts are loaded as scriptblocks**, because some PCs block `.ps1` files by Group Policy.
  `$PSScriptRoot` is then empty (pass `-KitRoot`), and `$script:` points at the caller's scope:
  don't use it for state.
- **`Get-ChildItem -Filter *.inf` also matches folders** named like `x.inf_amd64_<hash>` (the
  Win32 three-character-extension wildcard). Use `-File` and compare `Extension -eq '.inf'`.
- **`"$name:"` in a string is a scope qualifier.** Write `"${name}:"`.
- **`@($list)` of a generic `List` inside an `[ordered]@{}` literal throws** "Argument types do
  not match". Use `.ToArray()`.
- **`Measure-Object -Property` can't read the keys of an ordered dictionary.**
- **Hashtables are case-insensitive**: `'A'` and `'a'` collide.
- **A one-item list of lists unrolls in a `foreach`.** Keep it a list with a leading comma.
- **A byte-backed enum (`AceFlags`) after `-band` can't be used with `-or`** ("Specified cast is
  not valid"). Cast to `[int]` first.
- **`$list.Add($a -replace 'x', 'y')` is a two-argument call**, because of the comma. Wrap the
  expression: `$list.Add(($a -replace 'x', 'y'))`.
- **`Out-File -Encoding utf8` writes a byte-order mark.** Where the first bytes matter (a CI
  step's output file, a file another tool parses), write with `[IO.File]::WriteAllText` or
  `AppendAllText`.
- **`Get-WindowsOptionalFeature -FeatureName` takes one name**, and a parameter-binding error is
  terminating even with `ErrorActionPreference = 'Continue'`. Every first-boot step has its own
  `try`/`catch`, and an outer `catch` records anything else, so the status file can't claim a
  clean run falsely.
- **The build console is transcribed** to `<work>\logs\build-*.txt`. Never print a secret: the
  passwords exist only in the admin-only `accounts.txt`.

## Launchers and elevation

- **Never paste a launcher's `%*` into a `powershell -Command "..."` string.** `powershell.exe`
  splits it again: `-SourceIso "C:\My ISOs\x.iso"` loses its quotes, and an apostrophe in an
  argument or in the kit's path ends the quoted string. The launchers `set "W11KIT_ARGS=%*"`, and
  `Invoke-KitLauncher.ps1` splits that the way cmd does and passes each value as a single-quoted
  literal. It also doubles the typographic quotes U+2018 to U+201B, which PowerShell treats as
  `'`. Elevation hands the same text to `Start-Process -Verb RunAs` unchanged.
- **Elevation may run as a different user profile**: a separate admin account, or Administrator
  protection's hidden `ADMIN_<name>` account. That profile has no per-user `winget` and a
  different Downloads folder. The build tools come from pinned installers, and the search for the
  source ISO looks in every profile's Downloads.
- **Administrator protection** (`TypeOfAdminApprovalMode` = 2): the hidden `ADMIN_` account can't
  run winget (a per-user Store app, even by full path), and some installers refuse to run under
  it. `winget install --scope machine` from the normal user fails with `0x8A150019` for packages
  that exist only as MSIX. The image keeps Administrator protection off
  ([DECISIONS](DECISIONS.md#self-hosting)).
- **With Administrator protection on, an elevated window can't decrypt `accounts.txt.cms`**: it
  runs as `ADMIN_<name>`, which doesn't have the user's certificate key. Copy the encrypted file
  out and decrypt it non-elevated.
- **`net session` can't tell whether a launcher is elevated on a kit install.** It needs the Server
  service (`LanmanServer`), which the image disables, so it fails even elevated, and a launcher
  that re-launches itself on failure loops on the UAC prompt. The launchers use `fltmc`: it needs
  administrator rights and no service.
- **A launcher started from PowerShell 7 hands its `PSModulePath` to Windows PowerShell 5.1**,
  through `cmd`. PowerShell 7's module folders come first, and 5.1 then reports *The term
  'Get-FileHash' is not recognized*. (PowerShell 7 corrects the path only when it starts
  `powershell.exe` itself.) Every launcher clears `PSModulePath` after `setlocal`, and 5.1 takes
  its default.
- **An elevated admin account can't see `\\wsl.localhost\...`** (that is the daily user's WSL
  session). Run the launchers from a local folder (`C:\W11Kit`).

## DISM and image servicing

- **Defender's Controlled Folder Access blocks DISM.** Preflight refuses to build while it is on.
- **The 24H2 checkpoint update KB5043080 does not apply to a 26300.9457 or later source** (CompDB
  parse error). Only the target cumulative update belongs in `updates\lcu`.
- **Microsoft's stock image already lists old RollupFix packages as *Staged*.** To see whether an
  update went in, look for an installed cumulative update newer than the source's revision, not
  for "nothing staged".
- **`boot.wim` has two images, and Setup runs from the second.** Both must be serviced, or Setup,
  WinPE and the media's boot manager stay at the source ISO's level. See
  [BUILD-INTERNALS, Boot media](BUILD-INTERNALS.md#boot-media).
- **Offline `Remove-AppxProvisionedPackage` doesn't always mark the app as deprovisioned**: one app
  had no `AppxAllUserStore\Deprovisioned` key and Windows provisioned it again after Setup. The
  build writes the key for every removed app. The Store can still give an app to a user; the
  validator warns.
- **Don't run a diagnostic that mounts `<work>\install.wim` while a build runs.**
- **On one build PC, `reg.exe` and PowerShell could not write
  `HKLM\...\Policies\Microsoft\Dsh`** (the Widgets policy), even in an offline hive. Those values
  are deferred to Group Policy at first boot (`-DeferToGp` in `Set-KitRegistry.ps1`) and checked
  there.

## ACLs and the folder lock

- **`icacls <dir> /inheritance:r ... /T` gives every file an empty DACL**: unreadable even by
  administrators. Set the folder's ACL, then `icacls "<dir>\*" /reset /T`, and read a file back.
- **For a folder other users could write, don't use `icacls /T` or `Set-Acl` at all.** They may
  follow a junction planted inside. `KitAcl.ps1` opens every item with
  `FILE_FLAG_OPEN_REPARSE_POINT`, sets its security on that handle (no propagation), refuses
  links, and locks a folder before it lists it.
- **A locked folder under an unlocked parent can be swapped whole** by whoever owns the parent.
  The lock warns about parents a non-administrator can change. When the work folder is inside the
  kit folder, lock the kit folder too.

## Defender and ASR

- **The ASR rule "Block use of copied or impersonated system tools" (`c0033c00-...`) breaks
  DISM.** It blocks `poqexec.exe` running from `mount\Windows\CbsTemp`, and `Add-WindowsPackage`
  fails with `0x80070005` "error applying the Unattend.xml file from the .msu" after about 20
  minutes of retries. The build excludes its own work folders from the rule while it runs. Warn
  mode (6) blocks background tools too.
- **ASR exclusions take effect a few seconds after event 5007**, not at once. Wait about 15
  seconds before relying on one.
- **The ASR rule "prevalence, age or trusted list" blocks even reading a self-built `.exe`** (a
  `copy` fails with *Access denied*), and "unblocking" it in Windows Security does nothing. An
  ASR exclusion does work, per rule or ASR-only (`options.asrExclusions`).
- **The baseline's ASR rule *Use advanced protection against ransomware* (`c1db55ab-...`) also
  stops a program without a reputation yet**: a freshly compiled `.exe` fails with *Access is
  denied* (event 1121), whatever the prevalence rule is set to.
- **A per-rule ASR exclusion's value name is the rule's GUID, lowercase and without braces.**
  The braced form of the ADMX example (`{01443614-...}`) is silently ignored. Exclusions apply
  to processes started after them. Defender keeps the `ASROnlyPerRuleExclusions` key once it
  has read it: even an administrator can't delete it, but without
  `ExploitGuard_ASR_ASROnlyPerRuleExclusions` = 1 an empty key does nothing.
- **The baseline's `HideExclusionsFromLocalAdmins` makes `Get-MpPreference` return `N/A:` for
  exclusions, even elevated.** Without that policy, non-administrators still can't see them.
- **A check that reads back the value it was given proves nothing about the value.** An ASR rule
  entered under another rule's GUID is never active, and a validator row built from the same GUID
  passes anyway. Verify every GUID and value name against Microsoft's reference, or against the
  PC's own `C:\Windows\PolicyDefinitions\*.admx`, the best source for a policy's key, name and
  data. ("Block rebooting machine in Safe Mode" is `33ddedf1-c6e0-47cb-833e-de6133960387`.)

## AppLocker

- **Enforced Exe rules without any Appx rule deny every packaged app to every user**: Start,
  Settings, the Store, Terminal, winget, WSL. `Test-AppLockerPolicy -Packages` shows
  *DeniedByDefault*. Always add the "all signed packaged apps" Appx rule (`PublisherName="*"`
  works there: it is Microsoft's default rule).
- **An Exe publisher rule needs the publisher's name.** With `PublisherName="*"` the file name
  (`BinaryName`) is ignored and the rule matches nothing. Name the signer
  (`Get-AppLockerFileInformation <exe>`), or use a path rule (`*\name.exe` works).
- **`Test-AppLockerPolicy -User BUILTIN\Administrators` simulates the bare group** (without
  *Everyone*). Test with a real member account.
- **`Test-AppLockerPolicy -XmlPolicy <file>` validates a policy and its decisions without applying
  it**, and needs no administrator. Use it before changing `New-AdminBrowserPolicy.ps1`.
  `-Packages` works only with `-XmlPolicy`, not `-PolicyObject`: save the effective policy to a
  temporary XML file and test that (the validator does).

## Group Policy, baselines and audit policy

- **The local GPO keeps one `audit.csv`**, applied again at every refresh. Never apply
  `baseline-overrides-audit.csv` alone: `Merge-AuditPolicy.ps1` builds the full set, and only the
  merged file is applied.
- **The local GPO holds no security template.** `C:\Windows\System32\GroupPolicy` has
  `Machine\Registry.pol`, `audit.csv` and `gpt.ini` only. Account policy, user rights and security
  options live in the system; `secedit` applies them from a temporary database.
- **`Registry.pol` (PReg) delete markers** are records: `**del.<value>` and `**delvals.` with
  `REG_SZ` data of a space and a NUL (4 bytes). For a merge, a value and its `**del.` marker are
  the same value.
- **Microsoft's `Baseline-LocalInstall.ps1` applies its GPOs sorted by display name**
  (`$GPOs.Keys | Sort-Object`), not in the order its script lists them. Each `source.json` keeps
  that order. The script also disables `XblGameSaveTask` as a script step, not through a GPO, so
  the imported data doesn't carry it.
- **Microsoft replaces Security Compliance Toolkit files in place.** A baseline zip can become a
  "v2" with new GPO GUIDs under the same page. Pin the SHA-256, keep `--zip` for a copy you have,
  and expect an import's URL to stop working one day.
- **`NewsAndInterests.admx` writes `DisableWidgetsOnLockScreen` = 0 for "Enabled"**, against its
  own help text and the Policy CSP (1 = no widgets). The kit follows the CSP.
- **Clean-ups of a "bad" policy must check the value, not delete the key.** Deleting a whole
  policy key can remove a setting that is wanted (the baseline's standby ban lives in such a key).
- **`New-NetFirewallRule -PolicyStore localhost` reaches the local GPO over a network path to the
  PC itself.** During first-boot setup it failed with "The specified network name is no longer
  available" (the image disables the Server service). A local-GPO firewall rule is just a
  `REG_SZ` under `HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules`
  (`v2.26|Action=Block|Active=TRUE|Dir=Out|Protocol=6|RPort=445|RA4=a-b|RA6=x::/n|Name=...|`).
  The kit sets it as a policy value;
  `Get-NetFirewallRule -PolicyStore ActiveStore -Name <value name>` proves it loaded.

## Setup, boot media and Secure Boot

- **Copying only `setup.exe` and `setuphost.exe` from a serviced `boot.wim` breaks Setup** when
  the Setup Dynamic Update on the media is at a different level. Setup stops within seconds, at an
  error page, with `0xC1900100` after "Determine if the expected version of Setup Platform has
  been loaded" (`$Windows.~BT\Sources\Panther\setupact.log` on the disk being installed). The
  build expands the pinned Setup Dynamic Updates and then copies every file that `boot.wim`'s
  `sources\` shares with the media (about 95).
- **`Get-AuthenticodeSignature` on a Windows boot file returns the catalog signature**, not the
  embedded one the firmware checks. To tell 2011-signed from 2023-signed boot media, read
  `[X509Certificate]::CreateFromSignedFile($efi).Issuer` (`Windows UEFI CA 2023` or
  `Microsoft Windows Production PCA 2011`).
- **Every copy of the boot manager on the media must be replaced**, including the root
  `bootmgfw.efi`. `Test-OfflineImage.ps1 -BootMedia` compares them with the serviced `boot.wim`.
- **Never put the generic key into the real ISO of a `productKey: firmware` profile.** On such a
  PC the Pro key in the firmware must select and activate Pro. A `generic` profile's real ISO
  carries the generic key on purpose
  ([DECISIONS](DECISIONS.md#product-key-per-profile)).
- **Files written during Setup are stamped before the time zone is applied** (in UTC), so
  `Windows.old` and `Panther\unattend-original.xml` can look hours off. That is not a later
  event.
- **`cmd /c del /f /q "a*" "b\c*"` deletes nothing if one of the paths doesn't exist** ("cannot
  find the file"). On a real install of an earlier version of this kit that left the cached
  answer files, with their passwords, in `Windows\Panther`. Use PowerShell
  `Remove-Item -ErrorAction SilentlyContinue -Path a, b`. The VM test checks `Panther`.

## First-boot setup

- **A first-boot step can hang.** On a real install of an earlier version of this kit, turning on
  System Restore took over 30 minutes. Slow steps and steps that use the network run through
  `Invoke-Bounded` (a child PowerShell with a time limit); an overrun is a recorded failure.
- **Leaving the home location at *World* (GeoId 39070) makes every Microsoft Store install fail**
  with 404. The image always sets a real home location.
- **System Guard Secure Launch needs Modern Standby.** On a PC that only has S3 sleep it can't
  run, but while it is configured Windows disables S3. This doesn't matter for a profile that
  hibernates.
- **`reagentc /getrecoverysettings` output can contain a Wi-Fi password.** The validator prints
  only the two `state` attributes.

## Hyper-V VM test

- **A Hyper-V VM has no firmware product key.** The VM test's copy of the answer file adds the
  generic Windows 11 Pro installation key, which only selects the edition.
- **Remove the old VM before making the VM test's copy of the ISO again**: the old VM holds the
  file open.
- **The sign-in screen after the third restart is the correct end state**: first-boot setup ran
  during the one-time automatic sign-in and restarted. Read `postinstall-status.json`; don't
  judge by the screen.
- **KVP data from guest to host goes in `HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest`** (the
  host reads `GuestExchangeItems`). `...\Auto` is Windows' own set.
- ***Hyper-V Virtual Machine Bus Provider* with code 37 is expected** in the VM: Virtual Machine
  Platform without nested virtualization.
- **A Hyper-V VM can't hibernate**, so the power rows of a `hibernate` profile are expected to
  fail there ([TESTING](TESTING.md#rows-expected-to-fail-in-a-vm)).
- **Setup that stops before its first restart leaves no log where the test normally looks.** The
  test saves a picture of the VM's screen after 8 minutes without a first restart, gives up after
  20 and collects Setup's early logs.

## Microsoft's download sources

- **The Update Catalog can be scripted** (`Get-Updates.py`). Search results use single-quoted
  `id='<guid>_link'`; the download links come from a POST to `DownloadDialog.aspx`. The catalog
  sometimes answers a search with no results at all: the script retries with a back-off.
- **The Windows ISO can't.** Microsoft blocks scripted downloads of it (and bans the address), the
  Media Creation Tool's catalog served only 24H2 when last checked, and the 26H2 enablement package isn't in
  the Update Catalog. A new Windows release is a manual download, pinned by SHA-256.

## Windows quirks

- **`powercfg /query` leaves out hidden settings** (the power button on a desktop). Use `/qh`.
- **`msinfo32 /report` works without elevation** (Kernel DMA Protection, Secure Boot state). PCR 7
  and `Get-SecureBootUEFI` need elevation.
- **`Get-AppxPackage -AllUsers` needs elevation.** Without it the call fails or sees only the
  caller. The validator falls back to the current user when it isn't elevated.
- **Windows protected print mode** (`...\Printers\WPP`) allows only driverless IPP printers: no
  vendor printer drivers, no raw TCP/IP (port 9100) ports, and the "TCP/IP device" choice
  disappears from the add-printer wizard. The kit doesn't set it.

## WSL

For a contributor whose clone lives in WSL, and for WSL on the installed PC.

- **`wsl.exe` output into a pipe is UTF-16** unless `WSL_UTF8=1` is set.
- **From WSL, `Start-Process -Verb RunAs cmd.exe` can return at once as cancelled**, with no UAC
  prompt, while the same with `powershell.exe` works. Elevate through `powershell.exe`.
- **Linux `7z x` of a zip made on Windows with backslash paths creates flat files named `a\b`.**
  Extract such archives with Windows (`[IO.Compression.ZipFile]::ExtractToDirectory`).
- **A distribution's `ext4.vhdx` grows and doesn't shrink by itself.** Run `sudo fstrim /`, then
  compact the file from Windows after `wsl --shutdown`, or set the distribution to sparse.

## Git

- **Never run `git clean -x` or `-X` in the kit folder.** `work\` is git-ignored and holds the
  updates, drivers, finished ISOs and the passwords file. Because `/work/` is ignored, the build's
  own Git commands (`status --porcelain`, `bundle create --all`, `checkout`) never open it.
- **A locked kit folder is owned by Administrators**, and Git refuses a clone another user owns.
  Run `git pull` from an administrator's terminal, or let `Run-Build.cmd` offer it. The build
  passes `safe.directory` for the clone only, never `*`.

## CI on Windows runners

For a self-hosted Windows runner ([CI](CI.md)).

- **A step with `shell: powershell` fails where local Group Policy blocks `.ps1` files.** The
  runner writes each step to a `.ps1` file and runs it, and machine policy beats
  `-ExecutionPolicy Bypass`. Run every Windows step as a scriptblock (a custom
  `defaults.run.shell`), as the launchers do.
- **`actions/setup-python` fails for the same reason** (it runs `setup.ps1`). Install Python
  machine-wide on the runner and restart the runner service so that it sees the new `PATH`.
- **`actions/checkout` can fail with `0xC0000142` inside a Windows runner service** (Git's
  `sh.exe` can't start a child process). Check out with `git.exe` alone: `init`, `fetch` with
  `http.extraHeader=Authorization: ...`, `checkout`.
- **A byte-order mark as the first bytes of `$GITHUB_OUTPUT` turns `key=value` into
  `<BOM>key=value`**, and the output arrives empty. Write step outputs with
  `[IO.File]::AppendAllText(...)`, not `Out-File -Encoding utf8`.
