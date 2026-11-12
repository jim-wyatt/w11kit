# Contributing to W11Kit

Thanks for helping. W11Kit builds a Windows install that people put on their own PCs, so every
change is tested before it is merged, and every behaviour is documented where users look for it.
This page says what to read before you change code, where the docs for each change live, how to
contribute a hardware profile, and what can't be accepted.

Bugs: open an issue with the *Bug report* form. Security problems: **don't open an issue**, follow
[SECURITY.md](SECURITY.md).

## Where things are

| | |
|---|---|
| How the build works, the scripts, the repository layout | [docs/dev/BUILD-INTERNALS.md](docs/dev/BUILD-INTERNALS.md) |
| How changes are tested, and how to report a test run | [docs/dev/TESTING.md](docs/dev/TESTING.md) |
| Why the kit is the way it is | [docs/dev/DECISIONS.md](docs/dev/DECISIONS.md) |
| Traps in PowerShell 5.1, DISM, permissions, Defender, AppLocker | [docs/dev/GOTCHAS.md](docs/dev/GOTCHAS.md) |
| Moving the update list, a new baseline, a new Windows release | [docs/dev/MAINTAINING.md](docs/dev/MAINTAINING.md) |
| What counts as a breaking change, and how a release is cut | [docs/dev/MAINTAINING.md](docs/dev/MAINTAINING.md#versions-breaking-changes-and-releases) |
| Every external input and how it is verified | [docs/dev/DEPENDENCIES.md](docs/dev/DEPENDENCIES.md) |
| The short brief for AI coding agents and contributors | [CLAUDE.md](CLAUDE.md) |

## How changes are tested

In short ([details](docs/dev/TESTING.md)):

1. **The syntax gate**, before every commit: seconds, no administrator rights, changes nothing
   ([syntax gate](docs/dev/TESTING.md#syntax-gate)). The lint workflow runs the same checks on
   every push and pull request.
2. **The build's own read-back** of the finished image: automatic in every `Run-Build.cmd`.
3. **The Hyper-V VM test**, for anything that changes the build, the first-boot setup, the
   validator or the image's configuration: `Run-Build.cmd -TestBuild`, then `Run-VmTest.cmd`,
   until `RESULT: PASS`.
4. **A real PC**, where you can: *Validate PC* with `FAIL: 0`.

Put what you ran and its result in the pull request description
([reporting a test run](docs/dev/TESTING.md#reporting-a-test-run)). The VM test can't show real
hardware: device drivers, Wake-on-LAN, BitLocker, and the firmware starting the stick. Say so
when a change touches them. Pure documentation changes need only the syntax gate and working
links.

## Security-sensitive paths

Some files decide what runs as administrator or what goes into the image: the answer file, the
baseline overrides and the baseline pins, the update, installer and source-ISO pins, the release
keys, the first-boot payload, the folder lock, the update and the launchers, and the repository's
own workflows. [.github/CODEOWNERS](.github/CODEOWNERS) lists them. A pull request that touches
one needs the maintainer's review, and the maintainer's own Hyper-V VM test run before it is
merged, whatever the description reports.

## Before you change PowerShell

The kit runs on **Windows PowerShell 5.1** (not PowerShell 7), as administrator, often loaded as a
scriptblock, against DISM and offline registry hives. Much of what looks like odd code is there
because the obvious version failed. Read [the gotchas](docs/dev/GOTCHAS.md) before you change a
script. If you learn a new one, add it there in the same change.

Also read [the decisions](docs/dev/DECISIONS.md): they say what is deliberate. A pull request that
reverses a decision must say why and update the docs that explain it.

## Docs change with the code

A setting, decision, check, default or message that changes is documented **in the same commit**.
Every fact has one home; other pages link to it.

| You change | Update |
|---|---|
| A security setting or an exception to a baseline | [SECURITY-BASELINE](docs/reference/SECURITY-BASELINE.md), the validator, and `Test-OfflineImage.ps1` if the image carries it |
| What the image configures (registry, features, power, accounts) | [CONFIGURATION](docs/reference/CONFIGURATION.md); apps: [REMOVED-APPS](docs/reference/REMOVED-APPS.md) |
| A field of the settings file | [Your settings](docs/reference/CONFIGURATION.md#your-settings), `config/settings.defaults.json`, and every reader of the field |
| Profile fields or their rules | [PROFILES](docs/reference/PROFILES.md), and both profile checks ([syntax gate](docs/dev/TESTING.md#syntax-gate)) |
| Driver harvest or selection | [DRIVERS](docs/reference/DRIVERS.md) |
| A launcher, a build option, an input, an output | [BUILD-OPTIONS](docs/reference/BUILD-OPTIONS.md) |
| How the build works inside | [BUILD-INTERNALS](docs/dev/BUILD-INTERNALS.md) |
| The VM test, validator rows, what a VM may fail | [TESTING](docs/dev/TESTING.md), `config/vm-expected.json` (with a reason for each expected row) |
| A step the user performs, or what they see | [GUIDE](docs/GUIDE.md), [AFTER-INSTALL](docs/AFTER-INSTALL.md) or [MONTHLY](docs/MONTHLY.md) |
| A message the user can see | [TROUBLESHOOTING](docs/TROUBLESHOOTING.md) if it needs an action (it quotes messages word for word); a new term in the [GLOSSARY](docs/GLOSSARY.md) |
| A pinned input (update list, installer, baseline, ISO) | [DEPENDENCIES](docs/dev/DEPENDENCIES.md) |
| A decision | [DECISIONS](docs/dev/DECISIONS.md) |
| Anything a user will notice | [CHANGELOG.md](CHANGELOG.md) |

Write for someone doing this for the first time: plain words, short sentences, a reason for each
step. Keep project history, dates of internal decisions and personal set-ups out of the docs and
out of code comments. Facts about one PC model belong in that profile's `README.md`.

## Contributing a hardware profile

A profile makes the kit carry the right drivers for a model and check that its devices work after
the install ([profiles](docs/reference/PROFILES.md)). To add one:

1. **Generate it on the real PC**, while it still runs its current Windows: `New-Profile.cmd`
   (add `-Hibernate` / `-WakeOnLan` if you use them). It asks for administrator rights and writes
   `profiles/<id>/profile.json`.
2. **Review it.** Check `match` (it should fit your model, not every PC of that maker),
   `drivers.providers` (only the hardware makers, no utilities), `checks[]` (the devices that
   must work), `productKey` (`firmware` only if the firmware key is for **Pro**), `power`, and
   `computerName` (`null` or a model name, never your own PC's name).
3. **Write `profiles/<id>/README.md`**, following
   [profiles/legion-t5/README.md](profiles/legion-t5/README.md): the model and machine type, the
   devices with their **hardware IDs**, the **BIOS settings** the install needs with menu paths
   and the keys for the BIOS and the boot menu, which edition the firmware key is for, and driver
   notes (what was left out and why). Model facts only: nothing about your own unit's state.
4. **Test it.** Harvest, build with `-Profile <id>` and run the Hyper-V test (`Run-VmTest.cmd`).
   Include its `RESULT:` line and the summary in the pull request. In a VM the profile's device
   checks are expected to fail; everything else must pass.
5. **Ideally, install it on the real PC** and attach the validator's report
   (`W11Kit-Validation.md`) with **personal data removed**: the computer name, MAC addresses,
   account names, serial numbers, and anything else that identifies you or your network.
6. Open the pull request, or a *New hardware profile* issue with the same evidence.

A profile without a real-install report can be merged as *VM-tested only*; its README says so.

## What will not be accepted

- **Product keys.** The only key in the kit is the generic Windows 11 Pro installation key
  (it selects the edition, never activates, and is not a licence). No real keys, in profiles,
  docs, logs or issues.
- **Drivers or Microsoft files** in the repository. Drivers come from the user's own PC at build
  time. Windows, the updates, the ADK and Microsoft's security baselines are downloaded from
  Microsoft at build time; only their address and hash are pinned here
  ([a new baseline](docs/dev/MAINTAINING.md#new-microsoft-security-baseline)).
- **Firmware updates** (BIOS, EC, device firmware) in the image or in a profile's drivers. BIOS
  updates stay a deliberate step on the user's PC.
- **Anything that weakens the security baselines** without a documented exception: a reason, an
  entry in [SECURITY-BASELINE](docs/reference/SECURITY-BASELINE.md), and a validator check that
  shows the exception is exactly what it claims.
- **Secrets** in any form: passwords (generated or test), `accounts.txt` contents, tokens,
  certificates with private keys, validator reports or build logs with personal data left in.
- **Telemetry**, analytics or "phone home" code in the kit or the image.
- **A Microsoft account requirement**, or anything that needs one to install or use the PC.
- **Text or settings you have no right to share**: see the next section.

## Pull requests

- One topic per pull request. Describe what changed and why, and which tests you ran.
- Run the syntax gate before you push.
- Commit messages: a short summary line, then details if needed.
- Sign your commits off (`git commit -s`): see below.

## Licence of contributions

W11Kit is licensed under the [MIT License](LICENSE). By submitting a contribution you agree that
it is licensed under the same terms (inbound = outbound), and you certify the
[Developer Certificate of Origin 1.1](https://developercertificate.org/): you wrote it or
otherwise have the right to submit it under the MIT License. Add a `Signed-off-by: Your Name
<email>` line to each commit (`git commit -s`). No copyright assignment is asked for; you keep
your copyright, and the project's notice reads "The W11Kit contributors".

Do not contribute anything you have no right to share: Microsoft files, drivers, firmware, text
copied from CIS Benchmarks or other licensed guides, other projects' configurations without a
compatible licence, or product keys. If an AI tool helped you write a contribution, you remain
responsible for it and for its origin. Please follow the [code of conduct](CODE_OF_CONDUCT.md).
