# Security policy

W11Kit builds the Windows install that people run every day, so a weakness in it is a weakness on
every PC installed from it. Please report problems privately first.

## Reporting a vulnerability

**Don't open a public issue or pull request.** Instead, use the repository's private
vulnerability reporting: on [https://github.com/jim-wyatt/w11kit](https://github.com/jim-wyatt/w11kit), the *Security* tab →
*Report a vulnerability*. Only the maintainers see the report.

Include: the kit commit (`git rev-parse --short HEAD`), the profile id, what you found, how to
reproduce it, and what an attacker gains. Leave out real passwords, `accounts.txt` contents and
personal data; a description of where a secret appears is enough.

What to expect: an acknowledgement within 7 days, an assessment and a plan within 30 days, and
credit in [CHANGELOG.md](CHANGELOG.md) when the fix ships, unless you prefer not to be named.
Please give us a reasonable time to fix the problem before you disclose it.

This is a beta maintained in spare time: only the latest commit on the default branch is
supported. There are no backports.

## Good-faith research

We welcome research on the kit's own scripts and configuration, done on your own PCs and virtual
machines. If you act in good faith, report privately as described above, avoid harming others
or their data, and give us reasonable time before you publish, we will not pursue or support
legal action against you for that research, and we will credit you if you wish. We can only
speak for this project: this does not authorise testing of Microsoft's, GitHub's or anyone else's
products or services, which have their own policies (Microsoft: https://msrc.microsoft.com/).

This is a volunteer project. The response times above are goals, not commitments, and the table
below describes what the kit is designed to do, not a warranty: the software is provided "as is"
under the [MIT License](LICENSE).

## Scope

In scope:

- **The kit's scripts**: the launchers (`*.cmd`), `scripts/` (build, harvest, profile tools,
  the download scripts, the VM test) and `payload/` (first-boot setup, validator, BitLocker
  helper). For example: a secret written where it shouldn't be (console, log, a file other users
  can read, the image), a download that isn't checked against its pinned hash or signature,
  privilege problems in the kit's folder on the installed PC or in a scheduled task, command
  injection through a profile or an option.
- **The image's configuration**: the exceptions the kit makes to Microsoft's baselines, the
  registry settings, the answer file, the accounts and their rights, the permissions the kit
  sets, and a validator check that reports PASS for a setting that isn't in effect.

Out of scope (report these to their owners):

- **Microsoft's security baselines themselves**, Windows, Edge, Defender and the updates:
  [Microsoft Security Response Center](https://msrc.microsoft.com/). If the kit applies a
  baseline wrongly or changes a setting without documenting it, that *is* in scope.
- Drivers and firmware of a PC model (the kit carries the user's own drivers unchanged).
- Third-party software a user installs after the image.
- Weaknesses that need an administrator of the build PC or the installed PC (they can change
  anything already), unless the kit makes them easier than Windows does by default.

## What the kit is designed to do, and what it doesn't

These are design goals, not warranties; see [LICENSE](LICENSE). The settings and their reasons
are in [docs/reference/SECURITY-BASELINE.md](docs/reference/SECURITY-BASELINE.md); how the build
handles passwords and folders in
[docs/dev/BUILD-INTERNALS.md](docs/dev/BUILD-INTERNALS.md#passwords).

| | |
|---|---|
| **Generated passwords** | Each build makes the two accounts' one-time passwords with the operating system's cryptographic random generator: 20 letters and digits, about 114 bits. They are written only to `C:\W11Kit\work\accounts.txt`, which only administrators and Windows itself can read (or only encrypted to your certificate, with `-EncryptAccountsTo`). They are never shown in the console, the build log or the VM test's results |
| **Build folders locked** | The kit folder and its work folder can be changed by administrators and Windows itself only; other users can read them. A standard account can't simply change the scripts that run as administrator or what goes into the image. This narrows one path; it doesn't rule out compromise |
| **Inputs checked** | The Windows ISO, Microsoft's baseline files and the build-tool installers are checked against SHA-256 hashes pinned in `config/`; the installers also against their signer. Each update file is checked against the SHA-1 hash that Microsoft's Update Catalog puts in its file name (the kit pins update numbers, not update hashes). Drivers are checked against the list the harvest wrote |
| **One-time passwords in the ISO** | Any unattended install needs the passwords in its answer file. In the ISO they are **only obfuscated (base64), not encrypted**: anyone with the ISO or the stick can read them. That is why both accounts must choose a new password at the first sign-in, and why Setup's cached answer files are deleted from the installed PC (the validator FAILs if they remain) |
| **Keep the ISO private** | Treat the ISO and the stick like the passwords on them: don't share them, and wipe the stick when you no longer need it. The ISO also carries Windows, your PC's drivers and other publishers' installers, which aren't yours to pass on |
| **The VM test's copy** | The copy of the ISO that the Hyper-V test makes erases a disk without asking. It switches itself off on anything that is not a Hyper-V virtual machine, and the kit deletes it when the test ends |
| **No telemetry from the kit** | The kit sends nothing anywhere. Its only network traffic is downloads from the sources named in `config/`: Microsoft's Update Catalog and download servers, and the installers in `config/installers.json`. Windows itself still contacts Microsoft (required diagnostic data, activation, updates); the image sets diagnostic data to *Required*, the lowest level Pro allows |
| **No Microsoft account** | The image creates local accounts only and blocks conversion to a Microsoft account, unless you set `options.allowMicrosoftAccount`. The kit never sends a BitLocker recovery key to Microsoft |
| **Not promised** | That the image resists an attacker with physical access before BitLocker is on (it is off until you turn it on). That a profile someone else wrote carries only the drivers it should (review `drivers.providers` and the harvest's report). That the VM test says anything about hardware security features (DMA protection, memory protection on real hardware, Wake-on-LAN). That a kit you downloaded from somewhere other than the project's own address is the project's kit |

If you find that the kit doesn't do what a row above says, please report it as described at the
top.

### Who the build trusts

The build runs as administrator and decides what your next Windows contains. It trusts: this
repository as you downloaded it (and every update `Run-Build.cmd` installs: only releases signed by
a key in its `config\release-signers`, [below](#verifying-a-release)); Microsoft's download servers over
HTTPS, plus the pinned hashes above; the build tools' publishers, by pinned hash and signer; the
drivers of the PC the harvest ran on; and every administrator of the build PC. It does not trust
standard accounts on the build PC: that is what the folder lock is for.

### Verifying a release

Releases are git tags `v<version>`, signed with the project's release key, an SSH key
(fingerprint `SHA256:+pRxQySeKITmU6beE9HVVONgKIsFkerKYeY3xZ5h6gc`). Its public half is in
[config/release-signers](config/release-signers). Check a clone of a release, in a Command Prompt:

```
git -C C:\W11Kit -c gpg.ssh.allowedSignersFile=C:/W11Kit/config/release-signers verify-tag v0.1.0-beta
```

It prints `Good "git" signature for w11kit-release` and the key's fingerprint. Compare that with
the fingerprint above, as shown on the project's page.

`Run-Build.cmd` updates the kit only to the newest release signed by a key in the
`config\release-signers` the kit **already has**, never by a list the new release brings along. A
release signed by any other key, or not signed, is refused, and the kit stays as it is
([scripts/KitUpdate.ps1](scripts/KitUpdate.ps1)).

What this proves: the release was signed by a key in that list. It doesn't prove the list itself
is the project's: that is what comparing the fingerprint, once, when you first download the kit,
is for. A ZIP download has no signature: clone the release with Git to check it.

### How the launchers start PowerShell, and your antivirus

Every `.cmd` file of the kit starts Windows PowerShell with
`-ExecutionPolicy Bypass -Command "& ([scriptblock]::Create([IO.File]::ReadAllText(...)))"`: it
reads a script of the kit as text and runs that text. Malware uses the same pattern, so a
scanner may flag it. What it does and doesn't do here:

- **Why.** On some PCs a policy blocks `.ps1` script files outright (managed PCs, or a PC with a
  second hardening tool). Running the text works there too.
- **It changes no policy.** The execution policy is set for that one PowerShell process and is
  gone when the window closes. Nothing is written to the registry for it.
- **Your antivirus still sees everything.** Windows hands the script text to the installed
  antivirus before it runs (the Antimalware Scan Interface), exactly as for a script file.
- **The kit never asks you to turn antivirus protection off.** Two things it does around
  Microsoft Defender, both visible in the build's output: it refuses to build while *Controlled
  folder access* is on (DISM can't work with it; turning it off is your decision), and while a
  build runs it excludes its own work folders from attack surface reduction rules, then removes
  those exclusions.
- **If your antivirus flags a launcher:** open the `.cmd` in Notepad; it is a few lines and
  names the script it runs under `scripts\`. Allow it only if the kit came from this project's
  own address and the file is unchanged (`git status` shows nothing modified).

Tested with Microsoft Defender only. Not tested under any other antivirus.

## Threat model: what is left open, and what closes it

Two choices leave gaps. Neither is a bug; both have mitigations that are **your** steps, not the
image's.

### Someone with the PC in their hands (TPM-only BitLocker)

BitLocker here unlocks from the [TPM](docs/GLOSSARY.md#tpm) alone, with no PIN at start-up. The
reason is profiles that hibernate and wake over the network: a PIN prompt would stop every such
start ([why](docs/reference/CONFIGURATION.md#bitlocker)). BitLocker is designed to keep the disk
unreadable when it is taken out of the PC, and to keep the data protected at the Windows sign-in
screen. What TPM-only does **not** stop is an attacker who has the whole PC for a while and makes
it hand over the key during start-up:

| Attack | What stops it |
|---|---|
| Starting the PC from the network (PXE) or a USB stick with an **old, flawed Microsoft boot manager** that the firmware still trusts, which then gets the disk key released (the "bitpixie" family of attacks, CVE-2023-21563) | A **BIOS administrator password**, **network boot off**, and **USB boot off** or behind that password ([how](docs/AFTER-INSTALL.md#a-bios-password)). The validator shows whether the PC already starts from the 2023 boot manager and whether the firmware already refuses the 2011 ones. The kit does not revoke them itself: that step can't be undone |
| Changing BIOS settings (Secure Boot off, another boot order) | The same BIOS password; and BitLocker bound to Secure Boot (validator: *BitLocker bound to Secure Boot (PCR 7)*), so a change asks for the recovery key |
| Reading the key from memory through a port while the PC runs (DMA) | Kernel DMA Protection / the IOMMU. The BitLocker script refuses or warns without it, per profile (validator: *DMA protection (BitLocker, running PC)*) |
| Reading memory after pulling the plug (cold boot), or listening on the TPM's wires | Hibernate instead of sleep: the key isn't in memory while the PC is off. A firmware TPM has no wires to tap, but depends on the processor's firmware being current ([monthly check](docs/MONTHLY.md#bios-and-firmware-updates)) |
| A flaw in the TPM itself | BIOS updates, by hand: Windows Update doesn't deliver firmware on this image |
| Waking the PC over the network (profiles with Wake-on-LAN) | Nothing: anyone on the same network can send the wake-up packet. The PC then starts to the sign-in screen with the disk unlocked, which is what the rows above are about |

If your PC doesn't need to start unattended, a start-up PIN addresses the first row:
`Enable-BitLocker.cmd -StartupPin` (or `-AddPin`).

### What a lost disk or ransomware would cost

The kit doesn't back up anything. By default the validator reminds you once a month to make an
offline backup. A cloud folder backup such as OneDrive's is optional, and covers Documents,
Desktop and Pictures only.

| Event | With a cloud folder backup only | What closes the gap |
|---|---|---|
| The disk fails, or the PC is stolen | Lost: everything outside those folders (Downloads, WSL, SSH keys, code that isn't pushed, your settings file and profile). Windows itself comes back from the stick | A monthly **offline backup** to a drive you unplug ([how](docs/MONTHLY.md#offline-backup)). The validator reminds you (*Offline backup in the last 35 days*) |
| Ransomware encrypts your files | The encrypted files sync to the cloud too. Getting everything back to an earlier date may need a paid plan | The offline backup. A standard daily account, SmartScreen and the ASR rules make an infection less likely, not impossible |
| The online account is locked, taken over or closed | The online copy is gone or in someone else's hands | Two-step verification on that account; the offline backup |
| The disk warns before it fails | | The validator's *Disk health* row |

Controlled Folder Access, Windows' own ransomware protection, stays **off** on purpose: it blocks
the image tool the PC needs to rebuild its own ISO
([self-hosting](docs/dev/BUILD-INTERNALS.md#self-hosting)).

### What the validator watches for you

*Validate PC*, run monthly, also reports what changed since its last report (the **Since last
report** rows): new user accounts, additions to local groups, a cleared Security log and Defender
detections are WARNs; failed sign-ins, new services and tasks, blocked or audited ASR events and
NTLM use are listed. Between reports nobody watches: the kit has no alerting.
