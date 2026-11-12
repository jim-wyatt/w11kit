# After the install

> **W11Kit** · [Home](../README.md) · [1 Guide](GUIDE.md) → **2 After the install** → [3 Monthly](MONTHLY.md)
> Stuck? [Troubleshooting](TROUBLESHOOTING.md) · A word you don't know? [Glossary](GLOSSARY.md)

You have finished the [guide](GUIDE.md): Windows is installed, checked and encrypted. This page is
about living with that PC: what behaves differently and why, how to install your programs, and
the few things to set up once.

The examples use the default account names: `LocalAdmin` (the admin account) and `LocalUser` (the
daily account). Read your own names if you chose others.

**On this page**

- [What is different on this PC](#what-is-different-on-this-pc)
- [Installing your programs](#installing-your-programs)
- [A device without a driver](#a-device-without-a-driver)
- [Your files, WSL and VPN](#your-files-wsl-and-vpn)
- [A BIOS password](#a-bios-password)
- [Backups and accounts](#backups-and-accounts)
- [Never use Reset this PC](#never-use-reset-this-pc)
- [Getting the kit back](#getting-the-kit-back)
- [Changing a setting later](#changing-a-setting-later)
- [Lost or forgot a password?](#lost-or-forgot-a-password)

## What is different on this PC

Everything here is on purpose. The third column says what to do when you need the old behaviour.
"Reference" links go to the page that explains the setting itself.

### Accounts and sign-in

| What you notice | Why | If you need it |
|---|---|---|
| You work in a standard account. Windows asks for `LocalAdmin`'s password when something needs administrator rights | If something bad runs in your daily account, it can't change Windows itself | Nothing to change. Type the admin password when Windows asks ([accounts](reference/CONFIGURATION.md#accounts)) |
| `LocalAdmin` can't open a web browser: *This app has been blocked by your system administrator* | An administrator account that browses the web is a big risk | Browse as `LocalUser`. When an installer opens a web page at the end, close the message ([reference](reference/SECURITY-BASELINE.md#browsers-blocked-for-administrators-applocker)) |
| *Run as different user* is gone | The service behind it is switched off. Typing an administrator's password inside a standard user's session can expose it to theft | Use *Run as administrator*, or sign in as the other account |
| Windows itself has no Microsoft account, and won't convert yours into one | The PC must never depend on an online account | Sign in **inside** apps (Store, OneDrive, Edge) as usual. For Windows itself: the setting `options.allowMicrosoftAccount` ([your settings](reference/CONFIGURATION.md#your-settings)) |
| After 10 wrong passwords an account is locked for 15 minutes, the admin account too | It stops password guessing | Wait 15 minutes. Check Caps Lock and the keyboard layout first |
| A new password needs 11 characters or more, and you can change your own only once a day | Baseline and STIG rules for passwords | `LocalAdmin` can set a new password for another account at any time |
| No Wi-Fi list on the sign-in screen | Nobody can change the network before signing in | Sign in, then connect with the network icon |
| The screen locks after 15 minutes without input | A baseline rule | Sign back in. A Windows Hello PIN makes that quick |
| A password typed wrong can't be fixed with security questions | The image has none: their answers are easy to guess | Keep both passwords off the PC ([lost a password?](#lost-or-forgot-a-password)) |

### Programs and downloads

| What you notice | Why | If you need it |
|---|---|---|
| *Windows protected your PC* has no *Run anyway* button | SmartScreen blocks downloads it doesn't recognise | For a file you trust: right-click → **Properties** → tick **Unblock** → **OK** |
| A few installers show *Unknown publisher* although their maker signs them | The image checks program signatures more strictly than Windows does by default | Get the current version from the maker. For a file you trust: **Unblock**, as above |
| Windows Update installs no drivers and no BIOS updates | Your working drivers are not swapped behind your back, and firmware is never changed unasked | [A device without a driver](#a-device-without-a-driver); BIOS updates: [monthly routine](MONTHLY.md#bios-and-firmware-updates) |
| Some preinstalled apps are missing | They were removed from the image | Install the one you want from the Microsoft Store ([removed apps](reference/REMOVED-APPS.md)) |
| A program that worked no longer starts after a restart: *An Application Control policy has blocked this file* | Windows has switched [Smart App Control](GLOSSARY.md#smart-app-control-and-smartscreen) from evaluation to on. It blocks programs that are unsigned or rarely seen, and it has no list of exceptions | If you need such programs: Windows Security → App & browser control → Smart App Control settings → **Off**. For your next image: `options.smartAppControl` = `"off"` ([Smart App Control](reference/CONFIGURATION.md#smart-app-control)) |
| `winget` refuses `--ignore-security-hash` | winget's safety checks can't be switched off here | Try again later (the catalogue is often a few hours behind a release), or download from the maker |
| A game's anti-cheat refuses to run | It conflicts with one of Windows' memory protections | [Overrides](reference/SECURITY-BASELINE.md#overrides) says which setting is involved |
| The Xbox app, or a Store game that signs in to Xbox, doesn't work | Microsoft's baseline switches the Xbox services off. The kit turns them back on only with `options.gamingTweaks` | Set `gamingTweaks` in [your settings](reference/CONFIGURATION.md#your-settings) and rebuild ([gaming](reference/CONFIGURATION.md#gaming)) |
| A game launcher won't install, and says it needs the Windows *Secondary Logon* service | The kit disables Secondary Logon (a DISA STIG setting) unless `options.gamingTweaks` is on | Now, in a Command Prompt (as administrator): `sc config seclogon start= demand`. For your next image: set `gamingTweaks` ([gaming](reference/CONFIGURATION.md#gaming)) |
| Game Bar can't record | A baseline rule | [Changing a setting later](#changing-a-setting-later) |
| Edge shows its settings as *managed*, and has no sidebar, shopping or news feed | The Edge baseline and the kit's Edge settings | [Microsoft Edge](reference/CONFIGURATION.md#microsoft-edge) lists them |
| Defender blocks more than on a plain Windows | The attack surface reduction rules ([ASR](GLOSSARY.md#asr-attack-surface-reduction)) are on | Windows Security → Protection history shows what was blocked ([reference](reference/SECURITY-BASELINE.md#additions-beyond-the-baseline)) |

### Network

| What you notice | Why | If you need it |
|---|---|---|
| Other computers can't open a shared folder or printer on this PC | The file-sharing service is off. This PC still opens shares on a NAS or another PC | Put the files on a NAS or in a cloud folder. To share from this PC after all: [reference](reference/SECURITY-BASELINE.md#network-exposure-sign-in-and-monitoring) |
| A network printer isn't found by itself; names ending in `.local` don't answer | The "find devices by themselves" protocols ([mDNS](GLOSSARY.md#mdns), network discovery) are off, so the PC doesn't announce itself on any network it joins (on a Private network it still answers old NetBIOS name queries) | Add the printer by its IP address: Settings → Bluetooth & devices → Printers & scanners → Add device → *Add manually* |
| Remote Desktop is off, and its switch in Settings can't turn it on | A standing way in from the network | Use a remote-access tool that you start when you need it ([reference](reference/CONFIGURATION.md#remote-access-and-auto-updaters)) |
| *Network* in File Explorer lists no routers, TVs or media servers; a game may report a stricter NAT type | The discovery protocol behind them (UPnP) is off | Forward ports on the router by hand. To turn it back on: [reference](reference/SECURITY-BASELINE.md#network-exposure-sign-in-and-monitoring) |
| A LAN device answers by IP address but not by its bare name | Two old name-lookup methods are off (a baseline rule) | Use the device's IP address or its full DNS name |
| No Mobile hotspot, no *Cast* to a TV | Wi-Fi Direct is off | [Reference](reference/SECURITY-BASELINE.md#disa-stig-additions) says how to turn it back on |
| An app that waits for connections from other devices (a remote-access tool, a game server) gets none | On a *Public* network, Windows' choice for a new one, Microsoft's baseline ignores firewall rules that apps add themselves | For a network you trust: Settings → Network & internet → the connection → *Network profile type*: **Private**. For your next image: `options.firstNetworkCategory` ([settings](reference/CONFIGURATION.md#options-options)) |
| A very old NAS doesn't connect | The image asks for a current, signed version of the file-sharing protocol ([SMB](GLOSSARY.md#smb)) | Update the NAS |

### Windows itself

| What you notice | Why | If you need it |
|---|---|---|
| Start has no *Recommended* section, Settings has no *Home* page, Start search shows no web results | Less advertising and fewer suggestions | [Privacy](reference/CONFIGURATION.md#privacy) lists each setting |
| Weather and Maps don't know where you are; *Set time zone automatically* is greyed out | Location services are off for the whole PC | Type your town in once. To allow location: [privacy](reference/CONFIGURATION.md#privacy) |
| No widgets, no Recall, no cloud clipboard | Privacy settings | [Privacy](reference/CONFIGURATION.md#privacy) |
| On most desktop PCs there is no *Sleep* in the power menu | Microsoft's baseline turns classic standby off: a sleeping PC keeps the disk key in memory | Use Hibernate or Shut down ([power](reference/CONFIGURATION.md#power-hibernate-and-wake-on-lan)) |
| The PC hibernates after 30 minutes idle and on the power button (only with a `hibernate` profile) | In hibernate the disk key is not kept in memory | A profile with `power.mode` = `default` ([profiles](reference/PROFILES.md#fields)) |
| Windows stays on version 26H2; monthly updates install as usual | The feature release is pinned to the one the image was built and tested with | Rebuild with a newer kit ([monthly routine](MONTHLY.md#rebuild-the-iso)) |
| A policy value you change in the registry by hand comes back | Windows re-applies policies regularly | [Changing a setting later](#changing-a-setting-later) |
| More is logged than on a plain Windows, including the command lines of started programs | A record to look at after an incident ([Sysmon](GLOSSARY.md#sysmon)). Only administrators can read it | Don't put passwords on a command line ([reference](reference/SECURITY-BASELINE.md#sysmon)) |

Problems with any of these: [everyday use](TROUBLESHOOTING.md#everyday-use).

**Going back to a plain Windows.** The kit has no uninstall: its settings are spread over
policies, the registry and services. To go back, install Microsoft's own Windows from the ISO you
kept ([Plan B](GUIDE.md#plan-b-your-way-back)). That erases the disk again, so back up first.

## Installing your programs

- **Work as `LocalUser`.** Install programs from there. When an installer needs administrator
  rights, Windows asks: choose **LocalAdmin** and type its password.
- The **Microsoft Store** and **[winget](GLOSSARY.md#winget)** work as `LocalUser`. Many programs
  install for your account only and don't ask at all.
- **Your graphics card's control app** (from NVIDIA, AMD or Intel) is not in the image; only the
  driver is. Install the app if you want its settings, and turn off its automatic driver
  installs, so that driver updates stay your decision.
- **A remote-access tool**, if you use one: set it to start only when you need it, not with
  Windows. A tool that is always running is a standing way into the PC.

## A device without a driver

Windows Update doesn't deliver drivers on this PC. Your hardware's drivers came with the image. A
device you plug in later works if Windows has a built-in driver for it. If not, Device Manager
(right-click Start) shows it with a warning sign.

1. Download the driver from the device maker's or the PC maker's support site, as `LocalUser`.
2. If it is an installer, run it and approve as `LocalAdmin`.
3. If it is a folder with an `.inf` file, open a Command Prompt (as administrator) and run, with
   your path:

   ```
   pnputil /add-driver "C:\Users\LocalUser\Downloads\driver\*.inf" /install
   ```

4. If this is the PC you build on, run the harvest again before your next build
   ([step 6](GUIDE.md#step-6-collect-the-drivers)), so the next image carries the driver.

How the kit chooses drivers: [drivers](reference/DRIVERS.md).

## Your files, WSL and VPN

- **Your files:** copy them back from the backup drive, as `LocalUser`.
- **WSL** is turned on, without a Linux installed. In a Command Prompt: `wsl --install -d Ubuntu`.
  Copy your `~/.ssh` folder back, then in Linux:
  `chmod 700 ~/.ssh && chmod 600 ~/.ssh/* && chmod 644 ~/.ssh/*.pub`.
- **VPN:** install the client again and import its settings (WireGuard: *Import tunnel(s) from
  file*).

## A BIOS password

Once the new Windows works and BitLocker is on, set a **BIOS administrator password** (often
called *supervisor password*).

**Why.** BitLocker on this PC unlocks from the TPM alone, with no PIN at start-up. Someone with a
few minutes at the PC could otherwise start it from a USB stick or from the network with an old,
faulty Microsoft start-up program that the firmware still trusts, and get the disk key handed
over. With the three settings below, the PC starts only from its own disk.
([Threat model](../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it))

1. Read [Before any BIOS change](GUIDE.md#before-any-bios-change) and pause BitLocker as it says.
2. In the BIOS, set the **administrator (supervisor) password**. Your profile's README names the
   menu, if it has one.
3. Switch off **network boot** (called *PXE*, *Network Boot* or *LAN Option ROM*).
4. Switch off **USB boot**. If the one-time boot menu asks for the BIOS password once one is set,
   USB boot can stay available there: try it.
5. Leave **Secure Boot** on, in its normal (*deployed* or *user*) mode: never *setup mode* or *custom keys*, which let anyone change what the PC trusts.
6. Save and exit.

Keep the BIOS current: Windows Update delivers it when you allow drivers through it
(`options.windowsUpdateDrivers`); otherwise from the maker's support page.

> [!CAUTION]
> **Don't lose the BIOS password.** On many PCs a forgotten one can only be removed by the
> maker's service, at a cost. You need it for every later BIOS change and BIOS update. Keep it
> with your other passwords, off this PC.

Wake-on-LAN keeps working: waking a PC and starting it from the network are separate settings.
Before the next reinstall, turn USB boot back on.

## Backups and accounts

- **The kit backs up nothing.** By default *Validate PC* reminds you once a month to make an
  **offline backup**: a copy on a drive that you unplug afterwards. What to copy and how:
  [monthly routine](MONTHLY.md#offline-backup).
- **OneDrive folder backup is not a full backup.** If you use it, it holds Documents, Desktop and
  Pictures only. Not Downloads, WSL, your SSH keys, or game saves kept elsewhere. And it is one
  online account: if that account is locked or taken over, the copy is out of your hands. What
  it does and doesn't give you: [backups](reference/CONFIGURATION.md#backups).
- **Two-step verification** for your Microsoft account (the one behind the Store and OneDrive):
  <https://account.microsoft.com/security>. Use an authenticator app or a passkey rather than SMS.
- **A password manager** that also works on your phone: for the two Windows passwords, the BIOS
  password, the BitLocker recovery key and your web accounts. Where a website offers a
  **[passkey](GLOSSARY.md#passkey)**, use it.

## Never use Reset this PC

*Reset this PC* (Settings → System → Recovery) puts a plain Windows back. It silently removes
what the kit set up: the security policy, the registry settings and the kit's files in
`C:\ProgramData\W11Kit`. The PC would look the same and be far less protected.

To start over, **install from the stick again** ([step 12](GUIDE.md#step-12-install)).

## Getting the kit back

The install erased `C:`, the kit with it. The USB stick carries everything needed to build the
next ISO (the [build inputs](GLOSSARY.md#build-inputs)). To put it back, as `LocalUser`:

1. Plug in the install stick. Open its `BuildInputs` folder and double-click
   **`Restore-BuildInputs.cmd`**. Approve as `LocalAdmin`.
2. It checks every file against the hash recorded at build time and restores into
   `C:\W11Kit\work`: the Windows ISO, the updates, Microsoft's security baselines, your drivers
   and the tool installers.
3. It asks whether to install Git. Answer `Y`. (The installed PC has no build tools until then,
   on purpose.)
4. It puts the kit itself back into `C:\W11Kit`, as a Git clone, with your own settings and
   profile.

Everything is in that one folder again. Then:

- It is safe to run again: files already in place are skipped. If you answered `n` to Git,
  install it and run the script once more.
- Tell Git where the project lives, so the kit can be updated. In a Command Prompt (as
  administrator):

  ```
  git -C C:\W11Kit remote set-url origin https://github.com/jim-wyatt/w11kit.git
  ```

- The other build tools come with the next build: `C:\W11Kit\Run-Build.cmd` offers to install
  them.
- A kit file you changed and never committed with Git is not in the ISO's copy: take it from
  your backup. (Your settings and your profile travel anyway.)

If `C:\W11Kit` already holds other files, the script stops before it writes anything and says
so. Messages of this script: [everyday use](TROUBLESHOOTING.md#everyday-use). What the ISO
carries: [build inputs in the ISO](reference/BUILD-OPTIONS.md#build-inputs-in-the-iso).

## Changing a setting later

- **For the next install:** change [your settings](reference/CONFIGURATION.md#your-settings) or
  your [profile](reference/PROFILES.md) and build again.
- **On the installed PC, now:** the kit's settings are policies, so Windows' own Settings pages
  show them greyed out. [Changing a setting later](reference/SECURITY-BASELINE.md#changing-a-setting-later)
  explains how to change one, and how to put the kit's settings back.
- **Don't add a second hardening tool** on top. Their settings can contradict the kit's
  ([other hardening tools](reference/SECURITY-BASELINE.md#other-hardening-tools)).

## Lost or forgot a password?

The installed PC has two accounts: `LocalAdmin` and `LocalUser`. Windows' built-in Administrator
account is switched off, so there is no hidden third way in. What you can do depends on which
password is gone.

### Before the first sign-in: the one-time passwords are refused

- Check Caps Lock. The sign-in screen uses the keyboard layout the image was built with: the one
  in your settings, or the build PC's own if you set none.
- The passwords belong to the ISO named on the **last line** of `accounts.txt`. Every build makes
  new ones. Check that the passwords you saved came from the file that names the ISO on your
  stick.
- Stop before 10 tries, or the account locks for 15 minutes.
- If you still have the stick and the matching passwords file, installing from that stick again
  gives you the same one-time passwords.
- If the build PC was the PC you installed, `accounts.txt` was erased with the old `C:`. Only the
  copy you saved elsewhere helps.

### You forgot the daily account's password, and know the admin's

1. At the sign-in screen, choose **LocalAdmin** and sign in.
2. Open a Command Prompt (as administrator).
3. Run `net user LocalUser *` and type a new password twice. It must follow the same rules: 11
   characters or more, three of upper case, lower case, digits, symbols.
4. Sign in as `LocalUser` with the new password.

What Windows had stored under the old password is gone: saved passwords in Credential Manager
(some apps and network shares ask again). You may have to set up the Windows Hello PIN again.

### You forgot the admin account's password, and know the daily account's

This image has no way to reset it from inside Windows. The daily account isn't allowed to change
other accounts (that is the point of a standard account), and the built-in Administrator is off.

1. Keep using `LocalUser` for everything that doesn't need an administrator.
2. Copy your files to a backup drive.
3. Reinstall: from the kit's stick (it creates the accounts again with the one-time passwords of
   its `accounts.txt`), from a new build, or from a plain Windows ISO
   ([Plan B](GUIDE.md#plan-b-your-way-back)).

### Both passwords are lost

Only a reinstall helps, and it erases the disk. Files you didn't back up are on the encrypted
disk. To read them from another PC you need the 48-digit **recovery key** you saved in
[step 15](GUIDE.md#step-15-turn-on-bitlocker). Without it, they are gone.

### To avoid all this

Keep both passwords in a password manager you can open on your phone or another PC, or on paper
somewhere safe. Never only on this PC. After you change them at the first sign-in, save the new
ones the same way.

---

← Previous: [Guide](GUIDE.md) · Next: [The monthly routine](MONTHLY.md) →
