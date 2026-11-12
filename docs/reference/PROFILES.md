# Hardware profiles

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

A [hardware profile](../GLOSSARY.md#hardware-profile) tells the kit what is specific to one PC
model: which drivers to carry, which devices the validator must find working, how the PC sleeps
and wakes, and how Windows is licensed on it. Everything else (security, privacy, apps, accounts)
is the same for every profile.

```text
C:\W11Kit\profiles\
  generic\profile.json     any PC: every third-party driver in use, no device checks
  legion-t5\profile.json   Lenovo Legion T5 30AGB10, the reference PC
  legion-t5\README.md      its hardware, BIOS settings, licence and driver notes
  <yours>\profile.json     made by New-Profile.cmd on your PC
```

The build and the harvest take `-Profile <id>`. Without it they use the profile whose `match`
fits the PC they run on, and otherwise `generic`; they print which one and why. When it would be
`generic`, `Run-Build.cmd` first offers to make a profile from this PC, or lists the profiles
that are only used by choice ([What Run-Build.cmd asks](BUILD-OPTIONS.md#what-run-buildcmd-asks)).
The build puts
the chosen profile into the image as `C:\ProgramData\W11Kit\profile.json`, where first-boot setup,
the validator and the BitLocker script read it.

## Making a profile for your PC

Do this on the PC you reinstall, before you reinstall it. In a Command Prompt, or by
double-click:

```text
C:\W11Kit\New-Profile.cmd
```

Approve the UAC prompt. The launcher runs as administrator because, after the first build, only
administrators can write into the kit folder. The script itself only reads from Windows.
`Run-Build.cmd` offers this step by itself when no profile fits your PC.

It reads the running Windows (model, graphics, sound, network, Bluetooth, the drivers they use,
sleep states, whether the firmware holds a Windows key, DMA protection) and writes
`C:\W11Kit\profiles\<model>\profile.json`. It never reads a product key itself: only whether one
exists and for which edition.

| Option | Effect |
|---|---|
| `-Hibernate` | `power.mode` = `hibernate`. Only if `powercfg /a` lists Hibernate on this PC |
| `-WakeOnLan` | Wake-on-LAN on the first wired network adapter that is connected |
| `-Id <name>` | The profile's name and folder. Default: made from the maker and model |
| `-OutFile <file>` | Write somewhere else, for a trial run |
| `-Force` | Overwrite an existing profile |

Then:

1. **Review the file.** Remove vendors of peripherals from `drivers.providers`
   ([DRIVERS](DRIVERS.md#curation-rules)) and set `firmwareHints`. For a fixed computer name, set
   `computerName` in [your settings](CONFIGURATION.md#your-settings), or here.
2. **Build** with `C:\W11Kit\Run-Build.cmd`, on this PC. It takes the profile by itself, because
   its `match` fits this PC, and offers to collect the drivers
   ([guide, step 8](../GUIDE.md#step-8-build-the-iso)).

A PC whose maker left the model name empty (*To be filled by O.E.M.* and the like) gets a profile
with `match` set to `null`. The kit never takes such a profile by itself: `Run-Build.cmd` lists
it and asks, and `-Profile <id>` names it.

**Your profile stays yours.** Git leaves a file it doesn't know alone, so updating the kit never
touches it. A real build carries every new or changed `profile.json` in its
[build inputs](BUILD-OPTIONS.md#build-inputs-in-the-iso), so the installed PC can rebuild with
it.

**Sharing it** helps the next person with the same model. Add a `README.md` next to it with what
they need to know (BIOS keys and menu names, licence, driver notes), as
[profiles/legion-t5/README.md](../../profiles/legion-t5/README.md) does, and see
[Contributing a hardware profile](../../CONTRIBUTING.md#contributing-a-hardware-profile).

## Fields

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | number | The version of this layout: `1`. The first field. `New-Profile.cmd` writes it; don't change it. A profile without it, or with a newer number than the kit reads, is refused |
| `id` | text | The folder name, and the value for `-Profile`. Lower-case letters, digits and hyphens |
| `displayName` | text | Shown in logs and in the validator's report |
| `description` | text | Free text |
| `match` | object or `null` | `manufacturer` and `model`: patterns compared with what Windows reports for this PC. Used to pick the profile and to warn when you harvest or build on other hardware. `null`: never picked by itself |
| `computerName` | text or `null` | 1 to 15 letters, digits or hyphens, not all digits. Used only when neither `-ComputerName` nor `computerName` in your settings gives a name. `null` (as `New-Profile.cmd` writes it): Windows picks a random name |
| `isoTag` | text | Part of the ISO's file name, `Win11Pro-<isoTag>-...iso`. 1 to 23 letters and digits |
| `productKey` | `firmware`, `generic` or `prompt` | How Setup gets the edition. See [below](#productkey) |
| `drivers.providers` | pattern | The driver vendors the harvest carries. `.` means every third-party vendor |
| `drivers.skipInf` | pattern or `null` | Driver files (by `.inf` name) that never go into the image ([DRIVERS](DRIVERS.md#curation-rules)) |
| `power.mode` | `hibernate` or `default` | `hibernate`: hibernate instead of sleep. `default`: sleep as Windows sets it ([CONFIGURATION](CONFIGURATION.md#power-hibernate-and-wake-on-lan)) |
| `power.wakeOnLan` | object or `null` | `adapter`: a pattern for the network adapter's name; `label`: its name in reports; `advanced`: driver settings to apply where the driver offers them |
| `security.kernelDmaProtection` | `required` or `recommended` | `required`: the BitLocker script refuses to encrypt without DMA protection. `recommended`: it warns and asks ([CONFIGURATION](CONFIGURATION.md#bitlocker)) |
| `checks` | list | Devices the validator must find working. See [below](#checks) |
| `firmwareHints` | object | Free text shown in messages: where the BIOS has its `tpm` and `iommu` settings |

`description`, `match`, `computerName` and `firmwareHints` may be left out; the other fields are
required. The patterns are regular expressions. The build checks the profile before anything else
and stops on a missing field or a value it can't use; the message (`Profile ... is invalid`)
names each one.

### productKey

The image holds Windows 11 Pro only, so Setup must be told to install Pro.

- **`firmware`**: the PC has a Windows 11 **Pro** key in its firmware
  ([glossary](../GLOSSARY.md#firmware-key-msdm)). The ISO carries no key; Setup finds the PC's
  own. Preflight refuses this value on a PC whose firmware key isn't for Pro.
- **`generic`**: the ISO carries the generic Windows 11 Pro installation key (a default key that
  only selects the edition during Setup; it does not activate Windows and is not a licence).
  Windows then activates from the PC's [digital licence](../GLOSSARY.md#digital-licence) for Pro,
  if it has one.
- **`prompt`**: Setup asks you for a key.

You need your own Windows 11 Pro licence in every case. The kit does nothing to activation, and
no real product key ever goes into the ISO.

### checks

Each entry has an `area` and a `name` (the report's row) and a `type`:

| `type` | Matches | Extra fields |
|---|---|---|
| `video` | The graphics adapter's name (`match`) | `vendor`: the driver's vendor |
| `sound` | The sound device's name (`match`) | |
| `netadapter` | The network adapter's description (`match`). WARN when it is there but not connected | |
| `pnp` | Any device's name (`match`) | `class`: the device class, such as `Bluetooth` |

A device that is missing or not working is a FAIL. These are hardware rows: a VM test expects
them to fail, because a virtual machine has none of that hardware
([Rows expected to fail in a VM](../dev/TESTING.md#rows-expected-to-fail-in-a-vm)).

## What isn't in a profile

- **The kit's choices**, the same for every profile: the security baselines and their overrides
  (`config\baseline-overrides.*`), registry settings (`scripts\Set-KitRegistry.ps1`), removed apps
  (`config\removal-manifest.json`), Windows features (`config\image.json`) and this month's
  updates (`config\updates.json`).
- **Your choices** that don't depend on the hardware: language, time zone, account names, options
  and reminders. They are [your settings](CONFIGURATION.md#your-settings).
- **Facts for people**, not for the build: BIOS keys, menu names, known quirks. They belong in a
  `README.md` next to the profile.
