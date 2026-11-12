# Profile `legion-t5`: Lenovo Legion T5 30AGB10

> Model notes for one hardware profile. First time here? Start with the
> [guide](../../docs/GUIDE.md). Words: [glossary](../../docs/GLOSSARY.md).

The kit's reference profile: a desktop PC set up to hibernate and to wake over the network. The
profile itself is [profile.json](profile.json); its fields are explained in
[PROFILES](../../docs/reference/PROFILES.md). Everything on this page is specific to this model.

Use this profile only for a machine type 90YJ with **these parts** (the GeForce RTX 5070 and the
MediaTek RZ616 below): its device checks expect them. Another configuration needs its own
profile ([how](../../docs/reference/PROFILES.md#making-a-profile-for-your-pc)).

The image for this profile is built and tested in a virtual machine only
([status](../../docs/dev/TESTING.md#status)).

## Hardware

Values read from a 90YJ on BIOS O6EKT2CA.

| | |
|---|---|
| Model | Lenovo Legion T5 30AGB10, machine type (MTM) **90YJ**, board `3787` |
| BIOS | O6EKT2CA, EC 1.18 |
| Processor | AMD Ryzen 7 7800X3D (its integrated graphics are not exposed) |
| Graphics | NVIDIA GeForce RTX 5070, `PCI\VEN_10DE&DEV_2F04&SUBSYS_248817AA` |
| Memory and disk | 32 GB; WD PC SN740 1 TB NVMe (Windows' own driver; Setup shows it as about 954 GB); an AMD SATA controller (Windows' own driver) |
| Network | Realtek Gaming 2.5GbE, `PCI\VEN_10EC&DEV_8125&SUBSYS_378717AA` (the Wake-on-LAN adapter) · MediaTek RZ616 (MT7922) Wi-Fi 6E and Bluetooth, `PCI\VEN_14C3&DEV_0616&SUBSYS_E0C617AA` |
| Sound | Realtek ALC623 (`SUBSYS_17AA3787`) and NVIDIA HDMI audio |
| Firmware | UEFI, Secure Boot, TPM 2.0 (AMD firmware TPM), Kernel DMA Protection; no Thunderbolt or USB4 ports |
| Sleep states | The firmware offers S3 sleep and hibernate, not Modern Standby |
| Windows key in the firmware | Windows 11 **Home** (see [Licence](#licence)) |

## BIOS settings

Enter the BIOS with **F1** at power-on (try **F2** or **Del** if that does nothing). The one-time
boot menu is **F12**; **F10** saves and exits. Lenovo's menu names vary between BIOS versions.
What each setting is for, and the order to do things in, is in the guide:
[Step 11: BIOS/UEFI settings](../../docs/GUIDE.md#step-11-biosuefi-settings).

| Setting | Value |
|---|---|
| Secure Boot | Enabled, keys as they came |
| TPM | Enabled (AMD fTPM; Security → TPM) |
| SVM (virtualization) | Enabled |
| IOMMU | Enabled; Kernel DMA Protection needs it (AMD CBS → NBIO → IOMMU) |
| Boot order | Internal disk first; USB only through the F12 menu |
| Wake on LAN | Enabled (look under Power) |
| ErP / deep sleep / energy-saving standby | Disabled, or the network adapter has no power while the PC is off |

As shipped, Secure Boot, the TPM, SVM and the IOMMU are already on.

The TPM and IOMMU paths are also in `firmwareHints` in [profile.json](profile.json), so the
BitLocker script and the validator show them in their messages.

**Kernel DMA Protection.** With these settings Windows reports Kernel DMA Protection *On*. The
profile sets `security.kernelDmaProtection` to `required`: if a BIOS change ever turns it off, the
BitLocker script refuses to encrypt and the validator FAILs its DMA row.

**BIOS password, network boot, USB boot.** Set these after the install works:
[A BIOS password](../../docs/AFTER-INSTALL.md#a-bios-password). Lenovo calls the BIOS password
the *supervisor* or *administrator* password.

**BIOS updates** come from Lenovo's support site for machine type 90YJ. Windows Update doesn't
deliver them on this image ([BIOS and firmware updates](../../docs/MONTHLY.md#bios-and-firmware-updates)).
This model's TPM is a firmware TPM, and fixes for it arrive only in a BIOS update: check Lenovo's
BIOS notes for AMD-SB-7064 before relying on TPM-only BitLocker.

**Starting from the stick.** A 90YJ on BIOS O6EKT2CA with Windows' updates installed trusts Microsoft's 2023
Secure Boot certificate (`UEFICA2023Status` = `Updated`), so the default ISO needs no
`-Use2011BootManager`. Check yours:
[Secure Boot 2023 certificates](../../docs/reference/SECURITY-BASELINE.md#secure-boot-2023-certificates).

## Licence

This model ships with a Windows 11 **Home** key in its firmware, so the profile uses
`productKey: generic`. You need your own Windows 11 Pro licence.

- The image holds only Pro, so Setup can't use the Home key.
- With `generic`, the ISO carries the generic Windows 11 Pro installation key (a default key that
  only selects the edition during Setup; it does not activate Windows and is not a licence).
- Windows then activates by itself if this PC already has a digital licence for Pro, which it has
  once Pro was activated on it. Otherwise buy Pro in Settings → System → Activation before the
  reinstall, or enter your Pro key after it.

A Legion T5 that ships with a **Pro** key in its firmware could use `productKey: firmware`
instead. Preflight refuses `firmware` when the firmware key isn't for Pro.

## Power: hibernate and Wake-on-LAN

The profile sets `power.mode` to `hibernate` and `power.wakeOnLan` on the Realtek 2.5GbE adapter.
It is meant for a PC used as a small server that must stay reachable after hours of idle:

- It hibernates after 30 minutes and wakes when another device on the network sends a magic
  packet, from hibernate and from shutdown.
- In hibernate the disk key is not in memory. That is why Microsoft's baseline turns sleep (S3)
  off, and the kit keeps it off although this firmware offers S3.
- BitLocker is TPM-only, so the PC starts by itself after a wake. A start-up PIN would stop every
  wake at a prompt.

The adapter's driver settings the profile applies (`power.wakeOnLan.advanced`):

| Driver setting | Value |
|---|---|
| `*WakeOnMagicPacket` | `1` (on) |
| `*WakeOnPattern` | `0` (off) |
| `S5WakeOnLan` | `1` (wake from shutdown) |
| `WolShutdownLinkSpeed` | `2` |

The BIOS must have Wake on LAN on and ErP off (table above). The wake itself can only be tested
on the real PC ([guide, step 14](../../docs/GUIDE.md#step-14-check-the-pc)). If you don't want any
of this, set `power.mode` to `default` and `power.wakeOnLan` to `null` in a copy of the profile.

## Drivers

**Vendors carried** (`drivers.providers`): AMD (also under its names *Advanced Micro Devices* and
*ATI Technologies*), NVIDIA, Realtek, MediaTek, and Intel for extension packages those vendors
may ship. `New-Profile.cmd` proposes the first four on this PC.

**Left out** (`drivers.skipInf`), although the harvest finds them:

| Package | Why it is skipped |
|---|---|
| `u<number>.inf`, `amdwin-u<number>.inf` | Superseded AMD display packages, which get a new file name with every release |
| `hdx_lenovoext_*.inf` | Lenovo's sound extension. It wires in the Nahimic effects and adds the three Realtek software components below |
| `realtekapo.inf`, `realtekhsa.inf`, `realtekservice.inf` | Realtek's effects component, support app hook and service. The base Realtek driver runs the ALC623 on its own |
| `nvvad.inf` | NVIDIA Virtual Audio. It binds only to a device that NVIDIA's recording software creates |

The result is a Device Manager without unused software devices. Sound works through Realtek's
base driver. **Nahimic** is not carried: install Lenovo's audio software by hand if you want its
effects.

**Firmware.** Lenovo ships BIOS, EC and device firmware updates as driver packages
(`o6ekt2ca.inf`, `o6ect12a.inf`, `o6elt190.inf` on this BIOS level). The harvest never carries
them, for any profile ([why](../../docs/reference/DRIVERS.md#curation-rules)).

**Also not carried,** because their vendors are not in `drivers.providers`: VPN adapters,
peripheral and monitor utilities, and virtual display drivers. They come back with their own
apps.

**Overrides:** none ([table](../../docs/reference/DRIVERS.md#overrides)).

### Notes per device

| Device | Driver in the image | Notes |
|---|---|---|
| AMD chipset (3D V-Cache optimizer, GPIO, PCI, SMBus, PSP, provisioning) | Harvested | The 7800X3D has one core group, so the V-Cache optimizer does little here; it is in use, so it is kept. AMD Chipset Software is optional after the install |
| NVIDIA GeForce RTX 5070 and its HDMI audio | Harvested | The display works from the first start. The NVIDIA App is optional: use the same or a newer driver and turn its automatic driver installs off |
| Realtek ALC623 sound | Harvested (base driver only) | See *Left out* above |
| MediaTek RZ616 Wi-Fi 6E and Bluetooth | Harvested | Later versions come from Lenovo's support site, by hand |
| Realtek Gaming 2.5GbE (RTL8125) | Harvested | The Wake-on-LAN adapter |
| NVMe disk, SATA controller, USB controllers | Windows' own | Nothing to add |
| Lenovo BIOS, EC and device firmware | **Not in the image** | Firmware (above) |

### Platform devices and hardware IDs

Read with `scripts\New-DriverInventory.ps1` on BIOS O6EKT2CA. Hardware IDs are shown without the
per-device suffix. Compare them with the inventory of your own PC
([how](../../docs/reference/DRIVERS.md#harvest)): a different `SUBSYS_` or `DEV_` value means a
different board or card, and this profile may not cover it. Versions are the ones harvested from
the reference PC; yours may be newer.

| Device | Hardware ID | INF | Version | In the image |
|---|---|---|---|---|
| AMD 3D V-Cache Performance Optimizer | `ACPI\AMDI0101` | `amd3dvcache.inf` | 1.0.0.12 | Yes |
| AMD GPIO Controller | `ACPI\AMDI0030` | `amdgpio2.inf` | 2.2.0.134 | Yes |
| AMD GPIO Controller | `ACPI\AMDIF031` | `amdgpio3.inf` | 3.0.3.0 | Yes |
| AMD PCI | `PCI\VEN_1022&DEV_14DE&SUBSYS_378717AA` | `amdinterface.inf` | 2.0.0.23 | Yes |
| AMD Provisioning Packages | `ACPI\AMDI0052` | `amdppkg.inf` | 8.0.0.58 | Yes |
| AMD PSP 11.0 Device | `PCI\VEN_1022&DEV_1649&SUBSYS_378717AA` | `amdpsp.inf` | 5.41.0.0 | Yes |
| AMD SMBus | `PCI\VEN_1022&DEV_790B&SUBSYS_378717AA` | `smbusamd.inf` | 5.12.0.44 | Yes |
| NVIDIA GeForce RTX 5070 | `PCI\VEN_10DE&DEV_2F04&SUBSYS_248817AA` | `nvlei.inf` | 32.0.16.1714 (617.14) | Yes |
| NVIDIA High Definition Audio (HDMI/DP) | `HDAUDIO\FUNC_01&VEN_10DE&DEV_00AF` | `nvhda.inf` | 1.4.6.3 | Yes |
| NVIDIA Virtual Audio Device | `ROOT\UNNAMED_DEVICE` | `nvvad.inf` | 4.92.0.0 | No (`skipInf`) |
| Realtek High Definition Audio (ALC623) | `HDAUDIO\FUNC_01&VEN_10EC&DEV_0623&SUBSYS_17AA3787` | `hdxlv.inf` | 6.0.9915.1 | Yes |
| Realtek Audio Effects Component | software component | `realtekapo.inf` | 13.0.6000.1905 | No (`skipInf`) |
| Realtek Hardware Support Application | software component | `realtekhsa.inf` | 11.0.6000.381 | No (`skipInf`) |
| Realtek Audio Universal Service | software component | `realtekservice.inf` | 1.0.924.0 | No (`skipInf`) |
| Realtek Gaming 2.5GbE Family Controller | `PCI\VEN_10EC&DEV_8125&SUBSYS_378717AA` | `rt640x64.inf` | 10.79.50.1003 | Yes |
| MediaTek RZ616 Wi-Fi 6E 160MHz | `PCI\VEN_14C3&DEV_0616&SUBSYS_E0C617AA` | `mtkwl6ex.inf` | 25.40.2.586 | Yes |
| MediaTek RZ616 Bluetooth | `USB\VID_0489&PID_E0D8&MI_00` | `mtkbtfilter.inf` | 26.40.2.228 | Yes |
| HD Audio controllers (AMD, NVIDIA) | `PCI\VEN_1022&DEV_15E3`, `PCI\VEN_10DE&DEV_2F80` | `hdaudbus.inf` | Windows' own | Windows' own |
| NVMe disk (WD PC SN740) | `PCI\VEN_15B7&DEV_5017&SUBSYS_501715B7` | `stornvme.inf` | Windows' own | Windows' own |
| SATA AHCI controller | `PCI\VEN_1022&DEV_43F6&SUBSYS_10621B21` | `mshdc.inf` | Windows' own | Windows' own |
| USB xHCI (processor) | `PCI\VEN_1022&DEV_15B6` / `15B7` / `15B8`, `SUBSYS_378717AA` | `usbxhci.inf` | Windows' own | Windows' own |
| USB xHCI (chipset) | `PCI\VEN_1022&DEV_43F7&SUBSYS_11421B21` | `usbxhci.inf` | Windows' own | Windows' own |
| Lenovo BIOS, EC and device firmware | firmware resources | `o6ekt2ca.inf`, `o6ect12a.inf`, `o6elt190.inf` | | No (firmware) |
| Nahimic audio effects component | `SWD\DRIVERENUM\...#AVOLUTE_NH4APO` | (A-Volute) | | No |

## Device checks

The validator must find these working on the installed PC (`checks` in the profile). A missing
one is a FAIL, which is expected in a virtual machine:

- the GeForce RTX 5070 on NVIDIA's driver;
- Realtek HD Audio;
- the Realtek 2.5GbE adapter (WARN when it is there but not connected);
- MediaTek RZ616 Wi-Fi;
- the MediaTek RZ616 Bluetooth adapter.

## Other notes

- **Power plan:** Balanced, as for every profile. It is AMD's recommendation for Ryzen
  processors.
- **Computer name:** the profile sets none, so Windows picks a random name. For a fixed one, set
  `computerName` in [your settings](../../docs/reference/CONFIGURATION.md#your-settings), or build
  with `-ComputerName <name>`. The ISO is named `Win11Pro-LegionT5-...`.
- **Memory integrity** needs the UEFI Memory Attributes Table, which this firmware has. The
  harvested drivers are compatible with memory integrity.
