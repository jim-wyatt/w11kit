# W11Kit: a clean, hardened Windows 11 Pro install for your own PC

W11Kit helps you reinstall Windows 11 Pro on your own PC from scratch, with Microsoft's security
baselines applied from the first sign-in. It builds a custom install file (an ISO) from Microsoft's
official Windows, with your PC's own drivers and this month's updates already inside. It tests that
ISO in a virtual machine, and it gives you a one-click check for the finished PC.

> **Important: read before you use this**
>
> - **It erases a disk.** Installing the image deletes everything on the disk you choose in
>   Setup. Back up first and check the backup. There is no undo.
> - **It changes how Windows behaves.** The image applies Microsoft's security baselines and the
>   kit's own settings: it removes apps, disables services, blocks driver and firmware delivery
>   through Windows Update, and restricts the administrator account. Some programs, devices and
>   habits will stop working until you change a setting. What you will notice, and how to change
>   it: [What is different on this PC](docs/AFTER-INSTALL.md#what-is-different-on-this-pc). There
>   is no uninstall: going back means installing Microsoft's own Windows again.
> - **You need your own licence.** W11Kit contains no Windows, no Microsoft files and no licence.
>   You download Windows from Microsoft and need a valid Windows 11 Pro licence for the PC. The
>   kit does not activate Windows and does nothing to activation. The installation runs
>   unattended: **by building and installing the image you accept the Microsoft Software License
>   Terms for Windows** and the licence terms of the tools the build installs (Windows ADK,
>   Sysmon, Git for Windows, Python), which Setup would otherwise show you.
> - **Never share what you build.** The ISO and the USB stick contain Microsoft Windows, your
>   PC's drivers, other publishers' installers and your one-time passwords. Do not upload, publish,
>   sell or pass them on. They are for your own PC.
> - **No warranty, at your own risk.** W11Kit is beta software from volunteers, provided "as is"
>   under the [MIT License](LICENSE), without warranty of any kind. You alone are responsible for
>   your data, your hardware and your licences. It has been tested on one PC model and in virtual
>   machines; BIOS and firmware steps and BitLocker are your decisions and your risk. If you lose
>   the BitLocker recovery key, the data on that disk is lost.
> - **Not a compliance product.** The image follows Microsoft's security baselines and adopts
>   selected DISA STIG settings, with documented exceptions. It is **not** STIG-compliant, CIS-
>   certified, audited or approved by anyone, and it is not meant for regulated, corporate or
>   safety-critical systems without your own review. A hardened configuration lowers risk; it
>   does not make a PC secure.
> - **Not affiliated.** W11Kit is an independent project. It is not affiliated with, endorsed or
>   sponsored by Microsoft, the U.S. Department of Defense / DISA, Lenovo or any other company
>   named here. See [NOTICE](NOTICE).

> [!NOTE]
> **Status: beta.** The image builds and passes its hands-off test install in Hyper-V virtual
> machines for two hardware profiles. **This version has not been installed on a real PC yet.**
> Details: [Status](#status-beta).

## Is this for you?

**Yes, if:**

- your PC runs Windows 11 **Pro** today and you have your own Pro licence for it;
- you are comfortable in Windows Settings and can follow exact steps, even if you have never
  built install media or done a clean install;
- you want local accounts (no Microsoft account for Windows itself) and a locked-down PC;
- you have a spare evening and a backup drive.

**No, if:**

- the PC runs Windows 11 Home and you don't plan to buy Pro;
- the PC is managed by your employer or school;
- the PC's firmware (BIOS) doesn't trust Microsoft's 2023 Secure Boot certificate and its maker
  offers no BIOS update that adds it. The USB stick starts with the boot manager signed by that
  certificate. The build checks this PC and tells you before anything is erased
  ([Secure Boot 2023 certificates](docs/reference/SECURITY-BASELINE.md#secure-boot-2023-certificates));
- the PC must share folders or printers with other computers, or you can't live with the
  differences listed in [What will feel different](#what-will-feel-different).

You don't need to write code. The guide explains every step and every term.

## What it costs

| | |
|---|---|
| **Time** | About 3 to 4 hours the first time, plus your backup. Most of it is waiting. Later rebuilds take about an hour |
| **Disk space** | About 150 GB free on `C:` while you build and test ([how that adds up](docs/reference/BUILD-OPTIONS.md#disk-space)) |
| **A USB stick** | 32 GB or more. It is erased |
| **A backup drive** | An external disk or network share with 100 GB or more free |
| **A network cable** | For the downloads and for the install itself |

## Start here: [docs/GUIDE.md](docs/GUIDE.md)

Your first build, step by step, from downloading the kit to a checked, encrypted PC. Words you
don't know are in the [glossary](docs/GLOSSARY.md). If something doesn't look as described, see
[troubleshooting](docs/TROUBLESHOOTING.md).

## What you get

- **Windows 11 Pro 26H2** with the month's updates built in
  ([base image](docs/reference/CONFIGURATION.md#base-image)).
- **Your PC's own drivers**, copied from the Windows it runs today. Never firmware updates
  ([drivers](docs/reference/DRIVERS.md)).
- **Microsoft's Windows 11 and Edge security baselines**, applied in full with a short list of
  documented exceptions, plus selected DISA STIG settings. The image is not STIG-compliant
  ([security baseline](docs/reference/SECURITY-BASELINE.md)).
- **Two local accounts**: an admin account to approve changes and a daily account for everything
  else. Both start with one-time passwords that you replace at the first sign-in. No Microsoft
  account is needed ([accounts](docs/reference/CONFIGURATION.md#accounts)).
- **Privacy settings**: diagnostic data at the lowest level Pro allows; no Recall, widgets, ads
  or suggestions ([privacy](docs/reference/CONFIGURATION.md#privacy)).
- **Fewer preinstalled apps**. The Store and the media apps stay
  ([removed apps](docs/reference/REMOVED-APPS.md)).
- **BitLocker ready to turn on**, with the recovery key kept only where you choose. WSL2 is ready
  too (no Linux installed yet).
- **Checked three times**: the build reads the finished image back before it writes the ISO; a
  hands-off test install in a virtual machine must end in `RESULT: PASS`; and *Validate PC* on the
  installed PC checks about 150 rows covering several hundred settings.

What one PC model needs (drivers, device checks, sleep and wake, licence source) is in a small
**hardware profile** ([profiles](docs/reference/PROFILES.md)). Your own choices (time zone,
keyboard, account names, a few options) are in **your settings**
([your settings](docs/reference/CONFIGURATION.md#your-settings)). Everything else is the same for
every PC.

## What will feel different

- **You work as a standard user.** Windows asks for the admin account's password when something
  needs administrator rights.
- **The admin account can't run a web browser.** You browse as the daily account.
- **Windows Update installs no drivers and no BIOS updates.** A new device without a driver built
  into Windows needs its maker's driver. BIOS updates are a manual step.
- **This PC shares nothing on the network** and doesn't find printers by itself. You add a
  printer by its IP address.

The full list, with the reason for each and how to change it:
[What is different on this PC](docs/AFTER-INSTALL.md#what-is-different-on-this-pc).

## What this is, and what it is not

- **It is** a build kit for one PC at a time: yours. You run it, you keep the result.
- **It is not a debloater or a performance mod.** It removes few apps, keeps Windows servicing
  intact and turns security features on, not off.
- **It is not a compliance or certification tool.** See the *Important* box above.
- **It is not for fleets.** Organisations have their own deployment and management tools.
- **It bypasses nothing.** It installs only Windows 11 Pro, on hardware that meets Windows 11's
  requirements (TPM 2.0, Secure Boot), with your own licence.
- **It is a clean install only.** There is no upgrade in place: to move to a newer image you
  reinstall, or you simply let Windows Update keep the installed PC current.

## Status: beta

| | |
|---|---|
| **Proven** | The image builds and passes the build's own read-back check. The hands-off Hyper-V VM test (Setup, first-boot setup, validation) passes for the `legion-t5` and `generic` profiles. An install on the `legion-t5` reference PC, from a stick that starts with the 2023-signed boot manager, and the next build on that installed PC |
| **Not yet proven** | An install on any other PC. Turning BitLocker on with the kit's script on a real PC. Restoring the build inputs on an installed PC and rebuilding. Profiles made with `New-Profile.cmd` on other PCs |

This version has been installed on the reference PC only. Expect rough edges: back up everything, prepare a way
back ([Plan B](docs/GUIDE.md#plan-b-your-way-back)) and keep the backup until the new install has
worked for a while. How the image is tested: [docs/dev/TESTING.md](docs/dev/TESTING.md). What comes
next: [ROADMAP.md](ROADMAP.md).

The stick starts with a boot manager signed with Microsoft's *Windows UEFI CA 2023*, so the PC's
firmware must trust that certificate (a current BIOS, or Windows has installed it). The build checks
the PC it runs on: [Secure Boot 2023 certificates](docs/reference/SECURITY-BASELINE.md#secure-boot-2023-certificates).

### Tested hardware

| | |
|---|---|
| **Tested** (build and Hyper-V VM test; `legion-t5` also a real install) | The reference profile `legion-t5` (Lenovo Legion T5 30AGB10: AMD Ryzen CPU, NVIDIA GeForce graphics, Realtek wired network, MediaTek Wi-Fi) and the `generic` profile. English (United States). Build PC: Windows 11 Pro |
| **Expected to work, unproven** | A real install on other models. Intel CPUs. Intel or AMD graphics. Laptops. PCs with Wi-Fi only (the install expects a network cable). A `hibernate` profile on a PC that only supports Modern Standby |
| **Not supported** | Display languages other than English (`en-US`, `en-GB`) for now ([why](docs/reference/CONFIGURATION.md#another-language)). ARM64 PCs. Windows 11 Home (as the build PC or as the installed edition). A Windows 10 build PC. Dual boot. PCs managed by an employer or school. Upgrading an existing install in place |

Installed it on another model? A [hardware profile](CONTRIBUTING.md#contributing-a-hardware-profile)
with your report helps the next person.

### Support

W11Kit is maintained by volunteers in their spare time. There is no support promise and no
service level. The update list the kit ships is refreshed about once a month, when someone has
time; the build tells you when that list is getting old, and
[docs/dev/MAINTAINING.md](docs/dev/MAINTAINING.md) shows how to refresh it yourself. An installed
PC does not depend on the project: it keeps getting its updates from Windows Update.

Bugs: open an issue. Security problems: follow [SECURITY.md](SECURITY.md), not a public issue.

## Documentation

**Do it**

| | |
|---|---|
| [Guide](docs/GUIDE.md) | **Start here.** Your first build and install, step by step |
| [After the install](docs/AFTER-INSTALL.md) | Living with the installed PC: what is different, your programs, backups, getting the kit back |
| [Monthly routine](docs/MONTHLY.md) | Backup, BIOS check, *Validate PC*, a fresh ISO |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | What you see, what it means, what to do |
| [Glossary](docs/GLOSSARY.md) | Every term in plain words |

**Understand it**

| | |
|---|---|
| [Build options](docs/reference/BUILD-OPTIONS.md) | The work folder, every launcher and option, disk space, what the ISO carries |
| [Configuration](docs/reference/CONFIGURATION.md) | What the image sets and why; your settings file |
| [Security baseline](docs/reference/SECURITY-BASELINE.md) | Microsoft's baselines, every exception and its reason, what the kit adds |
| [Security policy and threat model](SECURITY.md) | Reporting a vulnerability; what the kit is designed to do, and what it doesn't |
| [Profiles](docs/reference/PROFILES.md) | Hardware profiles: making one, every field |
| [Drivers](docs/reference/DRIVERS.md) | How drivers are collected and chosen |
| [Removed apps](docs/reference/REMOVED-APPS.md) | Apps removed, kept and protected |
| [The reference PC](profiles/legion-t5/README.md) | Lenovo Legion T5 30AGB10: hardware, BIOS menus, drivers |

**Work on it**

| | |
|---|---|
| [Contributing](CONTRIBUTING.md) | How changes are tested; contributing a hardware profile |
| [Build internals](docs/dev/BUILD-INTERNALS.md) | How the build works, step by step; the scripts |
| [Testing](docs/dev/TESTING.md) | How the image is checked; what is proven |
| [Maintaining](docs/dev/MAINTAINING.md) | Moving the update list, a new baseline, a new Windows release |
| [Dependencies](docs/dev/DEPENDENCIES.md) | Every external input: version, source, how it is verified |
| [Decisions](docs/dev/DECISIONS.md) and [gotchas](docs/dev/GOTCHAS.md) | Why the kit is the way it is; traps in Windows tooling |
| [Reviews](docs/dev/reviews/STIG-REVIEW.md) | The DISA STIG compared rule by rule, and a [best-practice survey](docs/dev/reviews/BEST-PRACTICE-SURVEY.md) |
| [Changelog](CHANGELOG.md) | Changes per release |

## Third-party components

The kit contains none of these. The build gets each one from its publisher, and each stays under
its publisher's licence ([NOTICE](NOTICE); versions and sources:
[dependencies](docs/dev/DEPENDENCIES.md)).

| Component | How the build gets it |
|---|---|
| Windows 11 (the ISO) | You download it from Microsoft in your browser. The build checks its hash |
| Windows updates | Downloaded from the Microsoft Update Catalog, under Microsoft's terms |
| Microsoft's security baselines for Windows 11 and Edge | Downloaded from Microsoft at build time and read by the kit's importer. Nothing of them is in this repository |
| Build tools: Git for Windows, Python 3, Windows ADK Deployment Tools | Installed on the build PC only, when you agree, from official installers checked by hash and signature. Never in the image |
| Your PC's drivers | Copied from your own running Windows |

## Licence

[MIT](LICENSE) for the kit's own scripts, configuration and documentation. What it does not
cover, and trademarks: [NOTICE](NOTICE). Please follow the [code of conduct](CODE_OF_CONDUCT.md).
