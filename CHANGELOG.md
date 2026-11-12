# Changelog

Notable changes to W11Kit, newest first. What the kit is and how to use it:
[README.md](README.md).

## 0.1.0-beta: first public release (2026-11-12)

The kit builds a Windows 11 Pro 26H2 install ISO for your own PC from the Windows that PC runs
today, tests it in a virtual machine, and installs it unattended.

**Windows build:** 26300.9974, from the pins in `config/updates.json`: cumulative update
KB5132061, .NET Framework KB5127694, Safe OS KB5132060, Setup KB5127650 and KB5128977. Tested
with a build and the Hyper-V VM test (`RESULT: PASS`) for the `legion-t5` and `generic`
profiles.

- **Hardware profiles**: what a PC model needs (driver providers, device checks, power mode and
  Wake-on-LAN, product-key source, BitLocker's DMA policy) in one small file. `generic` fits any
  PC, `legion-t5` is the reference, and `New-Profile.cmd` writes one for your PC.
- **Your settings in one file** (`config/settings.local.json`): keyboard, formats, time zone,
  account names, options (gaming tweaks, Smart App Control, Brave policies, long paths) and four
  validator reminders plus a list of apps you expect. With nothing set, the build takes locale and
  time zone from the build PC.
- **`Run-Build.cmd` carries the flow**: it offers the build tools, the downloads, a profile, the
  driver harvest and the VM test when each is needed.
- **A report that starts with what needs attention**: *Validate PC* shows the FAIL and WARN rows
  first, then a count per group.
- **Build tools on demand**: Git, Python and the Windows ADK Deployment Tools are installed only
  on a PC that builds, from official installers pinned by SHA-256 and signer.
- **Your PC's own drivers**, exported from the running Windows; firmware is never carried. Storage
  drivers also go into Setup's own image, so Setup can see the disk.
- **Pinned, verified inputs**: the official source ISO by SHA-256, the month's cumulative, .NET
  and recovery updates from the Microsoft Update Catalog, a warning when the pins are old.
- **Microsoft's Windows 11 v26H2 and Edge v151 security baselines**, applied in full with
  documented overrides, imported from Microsoft's own zips at build time and applied with Windows'
  built-in tools. Nothing of Microsoft's is in the repository.
- **Selected DISA STIG settings** and further hardening: outbound SMB to the Internet blocked,
  Remote Desktop and WinRM off, unused network services disabled, browsers blocked for
  administrator accounts, Windows' built-in Sysmon. The image is not STIG-compliant.
- **Two local accounts** (an administrator and a standard daily account) with generated one-time
  passwords of 20 characters that must be changed at the first sign-in. No Microsoft account
  needed.
- **Privacy defaults**: diagnostic data at *Required*; Recall, widgets, ads and suggestions off;
  consumer apps removed. Windows Update delivers no drivers.
- **Power per profile**: hibernate instead of sleep, with Wake-on-LAN, or Windows' defaults. A
  BitLocker helper (TPM-only, the recovery key saved where you choose).
- **Checked three times**: the build reads the finished image back before it writes the ISO; a
  hands-off install in a Hyper-V VM with Secure Boot and a TPM ends in `RESULT: PASS` or
  `RESULT: FAIL`; *Validate PC* on the installed PC checks the settings and devices and writes a
  report.
- **Locked build folders**: the kit and its one work folder are writable by administrators only
  while you build.
- **Boot media signed with the Windows UEFI CA 2023**, with Setup and its boot image serviced to
  the same update level as Windows.
- **Build inputs in the ISO**: a real build carries what it was built from, so the installed PC
  can rebuild its own ISO.
- **Told before anything is erased**: the build's pre-flight reads this PC's Secure Boot database
  and says whether its firmware will start a stick signed with the 2023 certificate.
- **A stick says what it is**: `W11KIT-THIS-STICK.txt` on every ISO names the ISO, the build time,
  the profile and the kit revision; a test build's volume label ends in `_TEST`, and the validator
  warns on a real PC installed from a test build.
- **Devices without a driver, listed before the reinstall**: the harvest prints the devices that
  are not working on this PC now, so none is a surprise afterwards.
- **`Collect-Diagnostics.cmd`** puts what a bug report needs into one zip, with names, serial
  numbers, MAC addresses, SIDs and e-mail addresses replaced and the passwords files never read.

### Known limitations

- **Installed on one real PC only.** Every change is built and tested in Hyper-V virtual
  machines. The `legion-t5` reference PC has been installed from the kit, but this version's
  `Enable-BitLocker.cmd` and the restore of the build inputs have not been run on real hardware.
- **One reference PC model** (`legion-t5`, a desktop with an AMD processor). Laptops, Intel PCs
  and PCs with Wi-Fi only are untested.
- **Storage drivers for Setup** (Intel VMD, RAID): the build adds them to Setup's image and checks
  them, but Setup finding a disk behind such a controller has not been seen on a real PC.
- **Only English (United States) is tested.** Another language is a setting; a few validator rows
  read English command output.
- **x64 only**, Windows 11 Pro only.
- **No upgrade in place.** The kit reinstalls: everything on the disk you install to is erased.
- The Windows ISO is a manual download (Microsoft blocks scripted downloads), and BIOS, firmware
  and driver updates on the installed PC are manual by design.
