# Glossary

> **W11Kit** · [Home](../README.md) · [1 Guide](GUIDE.md) → [2 After the install](AFTER-INSTALL.md) → [3 Monthly](MONTHLY.md)
> Stuck? [Troubleshooting](TROUBLESHOOTING.md) · **Glossary**

The terms the kit's pages use, in plain words, in alphabetical order. Start with the
[guide](GUIDE.md) if you haven't yet.

### Account lockout

After **10 wrong passwords** in a row, Windows locks that account for **15 minutes**; then you can
try again. It stops someone from guessing a password. It applies to the admin account too.

### Administrator and standard accounts

An **administrator** account can change anything on the PC: install programs for everyone, change
security settings. A **standard** account can use the PC and install programs for itself, but
needs an administrator's password for anything that changes Windows. The kit creates one of each:
the **admin account** (`LocalAdmin` by default, used only to approve changes) and the **daily
account** (`LocalUser` by default, for everything else). If something bad runs in your daily
account, it can't change Windows itself.

### Answer file (unattended install)

A file on the install stick (`autounattend.xml`) that answers Windows Setup's questions in
advance: language, accounts, privacy choices, and the licence terms. With it, Setup runs
**unattended** and asks only the one question the kit leaves open on purpose: which disk to
install to.

### AppLocker

A Windows feature that allows or blocks programs by rule. The kit uses it for one thing: the
admin account can't start a web browser.

### ASR (attack surface reduction)

A set of Microsoft Defender rules that block things malware often does, such as an Office
document starting a program. The image turns them on. On the build PC, one of these rules (it
blocks programs that few people run) also blocks the build's own tools, so `Run-Prepare.cmd`
checks for it.

### BIOS and UEFI

The PC's built-in firmware: the setup screens you reach with a key such as F2 or Del right after
switching on, before Windows starts. **UEFI** is the modern kind; people still call it "the BIOS".
It holds settings such as Secure Boot, the TPM and the boot order.

### BitLocker

Windows' disk encryption. With BitLocker on, the data on the disk is unreadable without the PC's
own [TPM](#tpm) (which unlocks it automatically when nothing has been tampered with) or the
[recovery key](#recovery-key). The kit leaves it off until you turn it on yourself, so you choose
where the recovery key is kept.

### Boot menu

A one-time list of devices to start from (internal disk, USB stick), shown when you press a key
such as F12 right after switching on. Use it to start from the install stick without changing the
boot order.

### Build inputs

Everything the build used (the Windows ISO, the updates, Microsoft's security baselines, your
drivers, the build tools' installers and a copy of the kit), carried inside the finished ISO in a
folder named `BuildInputs`, so you can rebuild after the reinstall without downloading again.

### Build PC

The PC where you run the kit to make the ISO. Usually the same PC you then reinstall.

### Build tools

The programs a PC needs to build the ISO: Git, Python and Microsoft's ADK Deployment Tools (and
Hyper-V for the test). `Run-Prepare.cmd` installs them on the build PC; the Windows you install
never contains them.

### Command Prompt

A text window where you type commands (press the Windows key, type `cmd`, press Enter).
**PowerShell** is a similar, more powerful window. "As administrator" means: right-click it in the
Start menu → **Run as administrator**.

### Controlled Folder Access

Microsoft Defender's ransomware protection: only programs on an approved list may change files in
protected folders. It also blocks the tool that edits the Windows image, so it must be off while
you build, and the image leaves it off so the installed PC can rebuild its own ISO.

### Cumulative update (LCU)

Microsoft's monthly Windows update (the *latest cumulative update*). It contains every fix since
the release, so only the newest one is needed. The kit builds it into the image, together with the
monthly **.NET** update, the **Safe OS** update for the recovery environment
([WinRE](#winre-windows-recovery-environment)) and the **Setup** updates for the installer itself.

### Curated drivers

The drivers the kit keeps out of everything the [harvest](#harvest) exported: those of the makers
your [hardware profile](#hardware-profile) names, never firmware updates. They are in
`C:\W11Kit\work\DriverExport\_Curated`, and the build checks them against a list of hashes that
the harvest wrote.

### Digital licence

Proof, stored by Microsoft, that Windows 11 Pro was activated on this exact hardware before. A PC
with one activates Pro again by itself after a clean install, once it's online. You can see it in
Settings → System → Activation ("Active").

### DISA STIG

A security checklist for Windows 11 from the US Defense Information Systems Agency. The kit adopts
selected settings from it; the image is not STIG-compliant
([which ones](reference/SECURITY-BASELINE.md#disa-stig-additions)).

### DMA protection (Kernel DMA Protection, IOMMU)

Some devices can read the PC's memory directly (*Direct Memory Access*). **Kernel DMA Protection**
stops a device from doing that without permission, using a chip feature called the **IOMMU** (AMD)
or **VT-d** (Intel), switched on in the BIOS. It matters for BitLocker: while the PC runs, the
encryption key is in memory.

### Driver

A small program that lets Windows talk to a piece of hardware (graphics card, sound, network,
Wi-Fi, Bluetooth). Windows has many built in; others come from the hardware's maker.

### Elevated

Running with administrator rights. An elevated window says *Administrator* in its title bar. The
kit's `.cmd` files elevate themselves, which shows a [UAC prompt](#uac-and-the-uac-prompt).

### ErP

A BIOS setting (*ErP*, *EuP*, *deep sleep* or *energy-saving standby*) that cuts almost all power
while the PC is off, to meet EU energy rules. With it on, the network card has no power and
[Wake-on-LAN](#wake-on-lan) can't work, so a profile with Wake-on-LAN needs it off.

### Firmware

Software built into the hardware itself: the [BIOS/UEFI](#bios-and-uefi), and small programs
inside devices. A **firmware update** (or "capsule") rewrites it. The kit never puts firmware
updates into the image.

### Firmware key (MSDM)

A Windows [product key](#product-key-and-the-generic-key) that the PC maker stored in the PC's
firmware (in a table called *MSDM*). Setup reads it by itself. It may be for Home even if you
bought Pro later; then the profile uses the generic key instead.

### First-boot setup

What the kit does by itself the first time the new Windows starts: the admin account signs in
once, automatically, and a script (`PostInstall.ps1`) applies the security settings, power
settings, a restore point and more, then restarts the PC. Not the same as your own
**first sign-in**, which comes after it.

### Folder lock

The kit makes its own folder (`C:\W11Kit`) and its [work folder](#work-folder) changeable by
administrators only; every other account can read them. The kit runs with administrator rights
and decides what goes into your new Windows, so a program running in a standard account must not
be able to change it. The cost: you edit or update the kit from a window opened as administrator.

### Git

A tool that downloads a project and keeps track of its versions. A **clone** is a full Git copy of
a project. The kit needs to be a clone so the build can put a copy of it into the ISO.

### GPT, UEFI and CSM

**GPT** is the modern way a disk (or USB stick) is divided into
[partitions](#partition-and-unallocated-space); [UEFI](#bios-and-uefi) firmware starts Windows
from GPT disks. **CSM** (*Compatibility Support Module*, sometimes called *Legacy* boot) makes
UEFI firmware behave like an old BIOS. Windows 11 with [Secure Boot](#secure-boot) needs UEFI with
CSM off, which is why the stick is written as *GPT* for *UEFI (non CSM)*.

### Hardware profile

A small file (`profiles\<id>\profile.json`) that describes one PC model for the kit: which makers'
drivers to carry, which devices to check, how the PC sleeps, how Windows is licensed on it.
`New-Profile.cmd` writes one for your PC ([profiles](reference/PROFILES.md)).

### Harvest

The step where the kit copies the drivers your PC is using right now, so the new install gets the
same, working ones (`Run-Harvest.cmd`).

### Hash (SHA-256)

A file's fingerprint: a 64-character code calculated from its contents. If even one byte of the
file changes, the code is completely different. Comparing a file's SHA-256 with the one its
publisher lists shows that you have the untouched original. The kit checks the hash of everything
it downloads.

### Hibernate

A way of switching off that keeps your work: Windows writes everything in memory to the disk and
powers off completely. Starting again brings you back where you were. Unlike sleep, it uses no
power, and with BitLocker the key isn't in memory while the PC is off.

### Hyper-V

Windows' own [virtual machine](#virtual-machine-vm) feature, in Windows 11 Pro. The kit uses it
for the test install.

### Image (Windows image)

A packed copy of a complete Windows installation, ready to be put on a disk. The kit takes
Microsoft's image, adds updates, drivers and settings, and checks it. It is stored in a **WIM**
file (Windows Imaging format) inside the ISO; for a USB stick, the kit splits it into parts smaller
than 4 GB.

### ISO

A single file that holds the complete contents of an install disc. Microsoft publishes Windows as
an ISO; the kit makes a new ISO from it. You write an ISO to a USB stick with [Rufus](#rufus).

### JSON

A simple text format for settings, such as `config\settings.local.json`. Names and text are in
double quotes, entries are separated by commas, and blocks are in `{ }`. Notepad can edit it.

### Kit

W11Kit itself: the folder of scripts and settings in `C:\W11Kit` that builds your ISO. The kit is
not installed on the new Windows; only a few of its files go there
(`C:\ProgramData\W11Kit`: the first-boot setup, the validator, the BitLocker helper).

### Local account and Microsoft account

A **local account** exists only on this PC, with its own password. A **Microsoft account** is an
online account (an email address) that you can also sign in to Windows with. The kit uses local
accounts only; you can still sign in to apps such as the Store or OneDrive with a Microsoft account.

### MAC address and magic packet

A **MAC address** is the network card's own hardware address: six pairs of characters such as
`00-1A-2B-3C-4D-5E`. A **magic packet** is a special network message that contains that address
many times over; a network card set up for [Wake-on-LAN](#wake-on-lan) switches the PC on when it
sees one. Phone apps and tools like `wakeonlan` send it.

### Manifest

A list, written by a tool, of what it made or used, usually with a [hash](#hash-sha-256) for each
file. The build writes `<ISO name>.manifest.json` next to the ISO: the Windows ISO, updates and
drivers that went in, and the hash of each part of the image. The harvest writes one for the
drivers, and the build checks against it.

### mDNS

*Multicast DNS*: how devices on a home network announce themselves and find each other without a
server (names ending in `.local`, printers that appear by themselves). The image turns it off, so
the PC doesn't answer or ask on every network it joins; add printers by their IP address.

### Memory integrity (VBS, HVCI)

Windows protection features that use the processor's
[virtualization](#virtualization-svm-vt-x) to wall off the most sensitive part of Windows from
the rest. **VBS** (*virtualization-based security*) is the wall; **memory integrity** (also
*HVCI*) uses it to make sure only trusted drivers run. The image turns them on. A few games'
anti-cheat tools and very old drivers don't work with them.

### NTLM

An old Windows sign-in method for network connections, weaker than its successor (Kerberos) and a
favourite of attackers. Old NAS boxes and printers still use it. The image doesn't block it; it
logs each use, and the validator's *NTLM use (audited)* row counts them.

### Offline backup

A copy of your files on a drive that is **unplugged** when the copy is done. Ransomware and a
problem with an online account can't reach it. The validator reminds you once a month
([how](MONTHLY.md#offline-backup)).

### Partition and unallocated space

A disk is divided into **partitions** (sections), such as the one that holds `C:`. Deleting all of
them leaves **unallocated space**: an empty disk that Setup can lay out afresh.

### Passkey

A sign-in for websites that replaces the password: a key stored in your password manager, phone or
Windows Hello, which only answers to the real site. It is designed to resist guessing, reuse and
phishing.

### Payload

The developers' word for the kit's files on the installed PC (`C:\ProgramData\W11Kit`): the
[first-boot setup](#first-boot-setup), the [validator](#validator-validate-pc), the BitLocker
helper, and copies of your profile and settings. Only administrators can change that folder.

### PCR 7

A slot in the [TPM](#tpm) that records the PC's [Secure Boot](#secure-boot) state at every start.
BitLocker normally ties its key to it: as long as Secure Boot is on with the same certificates, the
disk unlocks, even after a BIOS update. Without PCR 7, BitLocker ties the key to the firmware
itself, and every BIOS change asks for the [recovery key](#recovery-key).

### Policy (Group Policy)

A setting that an administrator fixes for the whole PC, so programs and users can't change it.
**Local Group Policy** holds these on a PC that isn't part of a company network. The
[security baselines](#security-baseline) are applied as policies.

### PostInstall

The script that does the [first-boot setup](#first-boot-setup).

### Preflight

A check of everything the build needs (`Run-Build.cmd -Preflight`) that changes nothing and
downloads nothing. The kit's own message spells it `Pre-flight`.

### Product key and the generic key

A **product key** is a 25-character code that selects and activates a Windows edition. Many PCs
have one built into the firmware ([firmware key](#firmware-key-msdm)). The **generic Windows 11
Pro installation key** is a default key that only selects the Pro edition during Setup. It does
not activate Windows and is not a licence; activation comes from your
[digital licence](#digital-licence). The kit never puts a real product key into the ISO.

### PXE (network boot)

Starting a PC from a server on the network instead of its own disk. Useful in offices; at home it
is one more way to start the PC with software that isn't yours, so the kit suggests turning it off
in the BIOS ([a BIOS password](AFTER-INSTALL.md#a-bios-password)).
[Wake-on-LAN](#wake-on-lan) doesn't need it.

### Recovery key

A 48-digit number that unlocks a BitLocker disk when the TPM won't (for example after a BIOS change
or a motherboard swap). Without it, an encrypted disk can't be read. Keep it in two safe places,
never only on the encrypted PC.

### Recovery partition

A small, hidden part of the disk (under 1 GB, after Windows) that holds
[WinRE](#winre-windows-recovery-environment), the rescue tools. Setup creates it when you install
onto empty (unallocated) space. It must be outside `C:`, because the rescue tools have to start
when `C:` is encrypted or broken.

### Rufus

A free tool (rufus.ie) that writes an ISO to a USB stick so a PC can start from it.

### Secure Boot

A firmware feature that lets the PC start only software signed by a trusted publisher, so malware
can't slip in before Windows. Windows 11 requires it. The certificates it trusts are being
renewed (the "2023" certificates replace those from 2011); the kit's USB stick uses the new ones
([details](reference/SECURITY-BASELINE.md#secure-boot-2023-certificates)).

### Security baseline

A set of recommended security settings published by Microsoft for Windows and for Edge, several
hundred settings in all. `Run-Build.cmd` downloads Microsoft's two files (it asks first), every
build reads the settings out of them, and the image applies them in
full, with a short, documented list of exceptions
([security baseline](reference/SECURITY-BASELINE.md)). See also [policy](#policy-group-policy).

### Smart App Control and SmartScreen

**SmartScreen** warns about or blocks downloads and programs that Microsoft doesn't recognise; on
this PC it blocks them (use *Unblock* in the file's Properties for one you trust). **Smart App
Control** is a stricter Windows feature that blocks unsigned programs. The kit leaves it as
Windows sets it unless you choose `"smartAppControl": "off"` in your settings.

### SMB

The protocol Windows uses for shared folders and printers on a network. The image still lets this
PC open shares on a NAS or another PC, but it offers none itself, asks for a current, signed
version of the protocol, and never lets it out to the internet.

### Sysmon

*System Monitor*: a Microsoft tool, built into Windows 11 26H2 as an optional feature, that writes
a detailed log of what programs do (started processes, loaded drivers, network connections). It
blocks nothing; the log is for finding out afterwards what happened.

### Tamper protection

A Defender setting that stops programs, even ones with administrator rights, from switching
Defender off or weakening it. It can only be changed by hand in Windows Security.

### Test build and real build

A **real build** is what `Run-Build.cmd` makes by default: the ISO you install, with its build
inputs and its passwords in `accounts.txt`. A **test build** (`Run-Build.cmd -TestBuild`) is a
smaller, quicker ISO for the virtual machine only: it has `TEST` in its name and at the end of
its volume label (`WIN11PRO_<TAG>_TEST`), carries no build inputs, and has other passwords. Never
install a test build on a real PC; if you do, *Validate PC* warns (*Image kind*). Not to be confused with
**the VM test's copy** of an ISO, which the kit makes and deletes itself during the test.

### TPM

*Trusted Platform Module*: a security chip (or a firmware feature of the processor) that stores
keys safely, such as the BitLocker key and your Windows Hello PIN. Windows 11 requires TPM 2.0.

### UAC and the UAC prompt

*User Account Control*: when a program needs administrator rights, Windows dims the screen and
asks. In an administrator account you click **Yes**; in a standard account you type an
administrator's name and password. On the installed PC that is the admin account.

### Unattended install

See [answer file](#answer-file-unattended-install).

### Validator (Validate PC)

The kit's check of the installed PC, started with the *Validate PC* shortcut on the desktop. It
checks about 150 rows covering several hundred settings and devices, and writes a report with
PASS, WARN, FAIL and INFO rows. What needs attention comes first, in the window and in the
report; `C:\ProgramData\W11Kit\Validate-Pc.cmd -All` prints every row in the window.

### Virtual machine (VM)

A simulated PC running in a window on your real PC, with its own virtual disk. The kit installs the
new ISO in one to test it before you touch your real disk.

### Virtualization (SVM, VT-x)

A processor feature that lets one PC run others inside it as
[virtual machines](#virtual-machine-vm). AMD calls it **SVM** (or *AMD-V*), Intel **VT-x** (or
*Intel Virtualization Technology*); you turn it on in the [BIOS](#bios-and-uefi). Windows also
uses it for its own protection features ([memory integrity](#memory-integrity-vbs-hvci)), and WSL
needs it.

### Wake-on-LAN

Switching a PC on over the network: another device sends a special
["magic packet"](#mac-address-and-magic-packet) to the network card, which wakes the PC from
hibernate or shutdown. It needs a wired connection and a BIOS setting (and [ErP](#erp) off).
Anyone on the same network can send that packet.

### Windows Hello PIN

A PIN (at least 6 characters here) for signing in to this PC. It is stored in the TPM and works
only on this PC, so it is safer than reusing a password.

### winget

Windows' own command-line tool for installing and updating programs (`winget install …`,
`winget upgrade`). It works in your daily account.

### WinRE (Windows Recovery Environment)

A small rescue system on the disk that starts when Windows can't, with tools to repair, restore or
reset.

### Work folder

**`C:\W11Kit\work`**: the one folder that holds everything the kit downloads or makes: the Windows
updates, your harvested drivers, the logs, the finished ISOs and the passwords file
(`accounts.txt`). It sits inside the kit folder, Git ignores it, and only administrators can
change it ([folder lock](#folder-lock)). Never run `git clean -x` in `C:\W11Kit`: that deletes it.
What is in it: [the work folder](reference/BUILD-OPTIONS.md#the-work-folder).

### WSL

*Windows Subsystem for Linux*: runs Linux inside Windows. The image turns it on, without any Linux
installed yet (`wsl --install -d Ubuntu`).

---

← [Home](../README.md) · [Guide](GUIDE.md) · [Troubleshooting](TROUBLESHOOTING.md)
