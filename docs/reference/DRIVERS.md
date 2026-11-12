# Drivers

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

How [drivers](../GLOSSARY.md#driver) get from the PC you run today into the new image, and how to
change one on purpose.

The idea: the image carries the exact drivers your PC runs now, taken from that PC, so the new
install works without vendor installers. Which ones are carried is set by the hardware profile's
`drivers` fields ([PROFILES](PROFILES.md#fields)). Examples below are from the reference profile
`legion-t5`; its own notes are in
[profiles/legion-t5/README.md](../../profiles/legion-t5/README.md#drivers).

## Harvest

The [harvest](../GLOSSARY.md#harvest) runs on the PC you reinstall, while it still runs its
current Windows. In a Command Prompt, or by double-click:

```text
C:\W11Kit\Run-Harvest.cmd
```

It changes nothing on the PC: it only reads, and writes its export.

| Option | Effect |
|---|---|
| `-Profile <id>` | The hardware profile to curate for. Default: the profile that fits this PC, else `generic` |
| `-CurateOnly` | Don't export again; rebuild `_Curated` from the export that is there (after you changed the profile) |
| `-SkipArchive` | Don't write `DriverExport.zip`. A real build needs the zip for its build inputs |
| `-WorkRoot <folder>` | Another work folder. Give the build the same one |

**The drivers always come from the PC the harvest runs on.** If you name a profile whose `match`
doesn't fit this PC, the harvest prints a `PROFILE MISMATCH` warning: the image would lack that
model's drivers.

What it writes into `C:\W11Kit\work\DriverExport`:

| Item | What it is |
|---|---|
| `<inf>_amd64_<hash>\` folders | Every third-party driver package in Windows' driver store, old versions included (*export*) |
| `_Curated\` | The drivers that go into the image (*curate*, [next section](#curation-rules)) |
| `_Reports\curated-drivers.csv`, `excluded-drivers.csv` | What goes into the image, and why everything else doesn't |
| `_Reports\curated-sha256.txt` | The SHA-256 hash of every curated file |
| `_Reports\export-index.csv` | Every exported package: name, class, vendor, version, date |
| `_Reports\harvest-profile.json` | The profile the harvest used |
| `_Reports\platform-diagnostics.txt` | Secure Boot, TPM, Secure Boot certificates and sleep states of this PC |
| `_Reports\devices-not-working.txt` | Devices in an error state at harvest time (code 28 = no driver). The harvest also prints them: they won't work after the reinstall either, so install the driver first and harvest again ([A device without a driver](../AFTER-INSTALL.md#a-device-without-a-driver)) |
| `DRIVER-INVENTORY.md`, `driver-inventory.csv` | Which driver each device uses, by device class |
| `pnputil-drivers.txt`, `driverquery.csv`, `computerinfo.txt`, `msinfo32.txt` | Windows' own reports, for reference |

Next to the folder it writes `C:\W11Kit\work\DriverExport.zip` and its `.sha256`.

The build checks `_Curated` against `curated-sha256.txt` and stops if a file was changed, added
or removed since the harvest. The export is writable by administrators only, like the rest of the
work folder.

**To look before you harvest,** run the inventory alone. In PowerShell:

```text
& ([scriptblock]::Create((Get-Content -Raw C:\W11Kit\scripts\New-DriverInventory.ps1))) -OutDir "$env:USERPROFILE\Desktop\drivers"
```

It needs no administrator rights and writes `DRIVER-INVENTORY.md` and `driver-inventory.csv` into
the folder you name. If your profile's README
lists hardware IDs, compare: a different `SUBSYS_` or `DEV_` value means a different board or
card, and a set curated on another PC may not cover it.

**Harvesting again on a PC installed from this kit** exports the drivers running now. That is the
same curated set, with any [override](#overrides) you installed since.

## Curation rules

The export holds every package the old Windows ever installed: superseded graphics driver
releases, VPN adapters, peripheral drivers, firmware updates. Putting all of that into the image
would let Windows choose an older or untested package. `_Curated` gets:

1. **Every package in use by a device right now**, if its vendor matches the profile's
   `drivers.providers`. That is the version running stably today. (`legion-t5`: AMD, NVIDIA,
   Realtek, MediaTek and Intel; `.` means every third-party vendor.) Microsoft's own drivers are
   in Windows already and are never exported.
2. **Extension and component packages not bound to a device**, from those vendors: the newest
   version of each. They attach to a base device and apply only where the hardware matches.
3. **No other unbound device drivers.** They are for hardware this PC doesn't have, and came in
   with vendor bundles or Windows Update.
4. **Nothing whose `.inf` name matches `drivers.skipInf`.** The harvest skips unbound packages
   with such a name. The build skips every package with such a name, bound or not, so a profile
   can leave a package out without a new harvest. The build's manifest lists what was skipped.
5. **Never firmware** (device class `Firmware`), whatever the profile says. PC makers ship BIOS
   and device firmware updates as driver packages. In a fresh install they could rewrite the
   firmware, so firmware updates stay a step you take yourself
   ([BIOS and firmware updates](../MONTHLY.md#bios-and-firmware-updates)).

The harvest **fails** if a driver in use, from a carried vendor, is missing from the curated set.

**What a narrow `drivers.providers` leaves out.** A profile that lists only the PC's own chip
vendors leaves these to their own installers: VPN adapters, peripheral and monitor utilities,
virtual display drivers and audio-effect add-ons. Reinstall the apps you use and their drivers
come back with them. `generic` (`.`) carries everything in use, those included.

**What `New-Profile.cmd` proposes.** It lists the vendors of third-party drivers used by built-in
hardware, without Microsoft, firmware, software-only devices and external devices (webcams,
receivers, docks). Review the list: a vendor that ships its extension packages under a second
name may need adding by hand. `legion-t5` lists `AMD` and `ATI Technologies` next to
`Advanced Micro Devices` for that reason.

## Integration

| Part of the ISO | Drivers added |
|---|---|
| The Windows that gets installed (`install.wim`) | All of `_Curated`, less `drivers.skipInf`. Windows binds them to the devices at first start |
| The recovery environment (`winre.wim`) | Network and storage drivers only (classes `Net`, `SCSIAdapter`, `HDC`), so recovery can reach the disk and the network |
| Windows Setup on the stick (`boot.wim`) | Storage drivers only (classes `SCSIAdapter`, `HDC`), so Setup can see the disk |

Most PCs need no storage driver: Windows has its own for NVMe and SATA disks. The build then says
`boot.wim: no storage drivers in the curated set: nothing to add to boot.wim`. Otherwise the
preflight notes how many there are, and the build names them
(`boot.wim: N storage driver(s) in the curated set go into every image: ...`). A PC whose disk
controller needs a vendor driver (some RAID and
Intel VMD setups) gets it from the harvest, and without it Setup would show no disk to install
to.

The image check after the build compares the drivers in the image with `_Curated`, and the
manifest next to the ISO lists every third-party driver in it.

## Windows Update delivers no drivers

On the installed PC, Windows Update leaves drivers alone. The reason: an automatic driver swap
underneath a vendor's own software is a known cause of broken graphics drivers, and the curated
set should stay as tested.

| Setting | What it stops |
|---|---|
| `WindowsUpdate\ExcludeWUDriversInQualityUpdate=1` | Drivers arriving with the monthly updates |
| `DriverSearching\SearchOrderConfig=0`, `DontSearchWindowsUpdate=1`, `DontPromptForWindowsUpdate=1` | Windows Update being searched when you connect a new device |
| `Device Metadata\PreventDeviceMetadataFromNetwork=1` | Vendor apps and device information fetched for a new device |
| `DeviceInstall\Settings\DisableSendRequestAdditionalSoftwareToWER=1`, `DisableSendGenericDriverNotFoundToWER=1` | Reports to Microsoft whose replies can offer vendor software |

What follows from that:

- A device you plug in gets Windows' built-in driver or one the image carries, and nothing from
  the Internet. A device with neither shows as unknown until you install its driver by hand
  ([A device without a driver](../AFTER-INSTALL.md#a-device-without-a-driver)).
- Newer driver versions come from the PC maker's or chip vendor's site, when you decide.
- **BIOS and firmware updates don't arrive through Windows Update either.** Check for them
  yourself ([BIOS and firmware updates](../MONTHLY.md#bios-and-firmware-updates)).

The validator checks all of these settings.

## Notes per device class

| Device | In the image | Notes |
|---|---|---|
| Chipset | Yes | The vendor's chipset installer adds only extras such as power-plan tweaks. It is optional after the install |
| Graphics card, with its HDMI/DisplayPort audio | Yes | The display works from the first start. The vendor's app is optional; see below |
| Sound, with the PC maker's extensions | Yes | An effects add-on that was disabled on the old Windows stays out |
| Wi-Fi, Bluetooth, Ethernet | Yes | Later versions come from the PC maker's site, by hand |
| NVMe and SATA disks, USB controllers | Usually Windows' own | A vendor storage driver in use is carried like any other, and also goes into Setup and recovery |
| BIOS and device firmware | **Never** | Curation rule 5 |
| Peripherals (webcams, mice, keyboards, docks) | Only with `generic` | Install their software by hand if you want it |

**The graphics vendor's app** (NVIDIA App, AMD Software) isn't in the image. If you install it:
use the same or a newer driver than the harvested one, and turn off its automatic driver
installs. The same goes for chipset software.

A model's own table of devices, hardware IDs and driver versions belongs in its profile's README
([example](../../profiles/legion-t5/README.md#platform-devices-and-hardware-ids)).

## Overrides

An override is a driver you replace on purpose. The order of preference:

1. the driver harvested from the running PC (the default);
2. a newer release from the PC maker's support site for your model;
3. a newer release from the chip vendor;
4. Windows' own built-in driver.

Replace a harvested driver only with a reason: a fix you need, a security advisory, or a failure
on the new install. How:

1. Install the newer driver on the running Windows and check that the device works.
2. Run `C:\W11Kit\Run-Harvest.cmd` again. The harvest takes the driver now in use.
3. Write the change into the table below (or into your profile's README) and rebuild.

Don't change files in `_Curated` by hand: the build compares the folder with the harvest's hashes
and stops. To leave a package **out** without harvesting again, add its `.inf` name to the
profile's `drivers.skipInf`.

A restore point from first-boot setup is there if a new driver misbehaves on the installed PC.

| Device | Old version | New version | Source | Reason |
|---|---|---|---|---|
| | | | | None for `legion-t5`. |
