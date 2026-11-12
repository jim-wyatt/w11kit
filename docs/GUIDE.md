# Your first build, step by step

> **W11Kit** · [Home](../README.md) · **1 Guide** ([Prepare](#step-1-back-up-and-take-notes) → [Build and test](#step-8-build-the-iso) → [Install](#step-11-biosuefi-settings) → [Check and encrypt](#step-14-check-the-pc)) → [2 After the install](AFTER-INSTALL.md) → [3 Monthly](MONTHLY.md)
> Stuck? [Troubleshooting](TROUBLESHOOTING.md) · A word you don't know? [Glossary](GLOSSARY.md)

This guide takes you from nothing to a freshly installed, checked Windows 11 Pro on your PC. You
don't need to have built a Windows image or used custom install media before. Follow the steps in
order and do exactly what each one says. Each step tells you what you'll see, roughly how long it
takes, and what to do if it goes wrong.

**The short version.** On the PC you want to reinstall, while it still runs its current Windows,
the kit collects that PC's drivers and builds an install *[ISO](GLOSSARY.md#iso)* (a file that
holds a whole Windows installer). The kit tests that ISO in a
*[virtual machine](GLOSSARY.md#virtual-machine-vm)* first. Then you copy it to a USB stick, start
the PC from the stick, and install. After the install the PC configures itself, and you check the
result with one click.

> [!NOTE]
> **Beta: this version has not been installed on a real PC yet.** The ISO builds and passes its
> hands-off test install in a virtual machine. A real install may find problems the virtual
> machine can't show: starting from the USB stick, drivers, BitLocker, Wake-on-LAN. So keep a full
> backup, prepare your [Plan B](#plan-b-your-way-back) before you install, and don't reuse your
> backup drive until the new install has worked for a while.
> [What is tested](../README.md#status-beta).

**Contents**

| Part | Steps |
|---|---|
| **Prepare** | [1 Back up and take notes](#step-1-back-up-and-take-notes) · [2 Get the kit](#step-2-get-the-kit) · [3 Prepare the PC](#step-3-prepare-the-pc) · [4 Download Windows](#step-4-download-windows) · [5 Your PC's profile](#step-5-your-pcs-profile) · [6 Collect the drivers](#step-6-collect-the-drivers) · [7 Your settings](#step-7-your-settings) |
| **Build and test** | [8 Build the ISO](#step-8-build-the-iso) · [9 Test it in a virtual machine](#step-9-test-it-in-a-virtual-machine) · [10 Copy to your backup drive and make the USB stick](#step-10-copy-to-your-backup-drive-and-make-the-usb-stick) |
| **Install** | [11 BIOS/UEFI settings](#step-11-biosuefi-settings) · [12 Install](#step-12-install) · [13 First sign-in](#step-13-first-sign-in) |
| **Check and encrypt** | [14 Check the PC](#step-14-check-the-pc) · [15 Turn on BitLocker](#step-15-turn-on-bitlocker) |

Before the steps: [What you need](#what-you-need) and
[Before any BIOS change](#before-any-bios-change).

## What you need

| | |
|---|---|
| **The PC you reinstall** | It runs **Windows 11 Pro** (or Enterprise or Education), version 24H2 or later, today. It has a 64-bit Intel or AMD processor (not ARM) and meets Windows 11's requirements: *[Secure Boot](GLOSSARY.md#secure-boot)* and *[TPM 2.0](GLOSSARY.md#tpm)* |
| **A Windows 11 Pro licence for that PC** | The kit installs Pro only. Settings → System → Activation should say *Windows 11 Pro* and *Active*. A licence from your employer or school won't activate the new install: you need your own |
| **Free space** | About **150 GB** free on `C:`: 80 GB for the build, about 50 GB more while the test in step 9 runs, and the Windows download. To check: File Explorer → **This PC** |
| **Memory and processor** | The test virtual machine uses 6 GB of memory and 4 processor cores while it runs. A PC with 16 GB of memory is fine |
| **A USB stick of 32 GB or more** | It will be erased. The ISO is about 28 GB, so a 64 GB stick leaves room |
| **A backup drive** | An external disk or a network share with 100 GB or more free, formatted NTFS or exFAT. Not the USB stick |
| **Internet, by cable** | For the downloads and for the install itself |
| **A safe place for passwords that is not on this PC** | A password manager you can open on your **phone or another PC**, or paper kept somewhere safe. The install erases this PC |
| **Time** | About **3 to 4 hours**, plus your backup. Most of it is waiting, but some steps ask you to click *Yes* within 2 minutes, so stay near the PC |

Roughly how the time adds up: the backup takes 30 minutes to a few hours; preparing and
downloading 1 hour; building 45–75 minutes (an estimate); testing 15–45 minutes; copying and
writing the stick 30–60 minutes; installing and checking 1 hour.

- **Windows 11 Home?** Buy the Pro upgrade first (Settings → System → Activation). Home can't
  build or test, and the kit installs Pro only.
- **Still on Windows 10?** Update this PC to Windows 11 first, or build on another Windows 11 Pro
  PC ([building on another PC](reference/BUILD-OPTIONS.md#building-on-another-pc)).
- **Not sure your kind of PC is covered?** See [tested hardware](../README.md#tested-hardware).

> [!CAUTION]
> **Everything on the disk you install to will be erased.** That's why step 1 is a backup.

**Three things you'll do often:**

- **Approve a UAC prompt.** That is the Windows box that asks *"Do you want to allow this app to
  make changes to your device?"*. Click **Yes**. If it asks for a password, type your
  administrator password. The prompt cancels itself after about 2 minutes.
  ([More](GLOSSARY.md#uac-and-the-uac-prompt))
- **Open a Command Prompt (as administrator).** Press the Windows key and type `cmd`. Right-click
  **Command Prompt** → **Run as administrator**. Click **Yes**. The window's title starts with
  *Administrator:*. You type or paste a command there and press Enter.
- **Edit a file in the kit's folder.** Press the Windows key and type `notepad`. Right-click
  **Notepad** → **Run as administrator**. Then use **File → Open**. (A Notepad opened the normal
  way can't save there: only administrators may change the kit's folder.)

## Before any BIOS change

The *[BIOS/UEFI](GLOSSARY.md#bios-and-uefi)* is the PC's built-in setup screen, before Windows
starts. This guide sends you there up to three times: in step 3 (only if virtualization is off),
in step 11, and after the install for a BIOS password. Each time, do this first.

> **BIOS updates and BIOS settings are at your own risk.** Follow your PC maker's instructions,
> never interrupt a BIOS update, and note every setting before you change it. A failed update can
> leave a PC unable to start.

1. **If your disk is encrypted, pause the encryption first.** Otherwise the PC may ask for the
   recovery key at the next start. Step 1 tells you how to find out and how to save that key. In a
   Command Prompt (as administrator):

   ```
   manage-bde -protectors -disable C: -RebootCount 1
   ```

   **You'll see:** *Key protectors are disabled for volume C:*. The disk stays encrypted. Windows
   turns the protection back on by itself after the next restart, so run the command again
   before each visit to the BIOS.
2. **Restart and press the BIOS key repeatedly** as soon as the screen lights up. It is often
   **F2**, **Del** or **F1**; the start screen sometimes shows it. Your profile's README, if it
   has one, names the keys and menus for its model (for the reference PC:
   [profiles/legion-t5/README.md](../profiles/legion-t5/README.md#bios-settings)).
3. Change only what the step tells you. Save and exit, usually with **F10**.

## Step 1: Back up and take notes

*About 30 minutes to a few hours, depending on how much data you have.*

Do this first, on your current Windows.

1. **Copy your own files to the backup drive.** Documents, Desktop, Pictures, Downloads, game
   saves, anything a program keeps in its own folder, and browser data that isn't synced to an
   account.
   - If you use a VPN app, export its settings (WireGuard: *Export tunnels to zip*).
   - If you use WSL (Linux on Windows), copy your SSH keys (`~/.ssh`), settings files and any code
     that isn't pushed anywhere. The Linux installations themselves are not kept. Do this copy
     last, so it is current.
2. **Check your Windows licence.** Open **Settings → System → Activation** and write down what it
   says.
   - **Windows 11 Pro** and **Active**: good. The new install activates by itself once it is
     online. ([Why that works](GLOSSARY.md#digital-licence))
   - **Windows 11 Home**: buy the Pro upgrade on that page first, then come back.
   - If you have a Pro product key (on a card, in an email), put it in your password manager. You
     won't type it during the install, but keep it in case activation fails.
3. **Write down your Wi-Fi name and password**, if you use Wi-Fi. The install uses the network
   cable; you connect to Wi-Fi yourself afterwards.
4. **Note your system disk.** During the install you pick the disk by its size.
   - Right-click the Start button → **Disk Management**. Find the disk that holds `C:` (usually
     *Disk 0*) and write down its **size** (for example *953.85 GB*).
   - Right-click the grey box on the left that says *Disk 0* → **Properties**. Write down the
     disk's **model** too.
   - Note the size of **every other disk** listed there. If two internal disks have almost the
     same size, take extra care in step 12.
5. **Check for disk encryption and save its recovery key.** Many Windows 11 PCs come with the
   disk already encrypted (*device encryption* or *BitLocker*). A BIOS change can make the PC ask
   for the recovery key, and without it you can't get back into your current Windows, which you
   still need until the new install works.
   - In a Command Prompt (as administrator), run `manage-bde -status C:`. *Protection Status:
     Protection Off* and *Percentage Encrypted: 0.0%* mean the disk isn't encrypted.
   - **If it is encrypted:** in the same window, run `manage-bde -protectors -get C:`. Copy the
     48-digit **Numerical Password** (the recovery key) into your password manager on your phone,
     or onto paper. Don't keep it only on this PC.

**You'll see:** nothing new yet. You have a full backup and a few notes.

## Step 2: Get the kit

*About 5 minutes.*

The kit is a folder of scripts. It must end up in **`C:\W11Kit`**, and it must be a
*[Git](GLOSSARY.md#git) clone* (a copy made with Git, a tool that downloads a project and tracks
its versions). The build puts a copy of the kit into the ISO with Git, so you can rebuild after
the reinstall.

**If you already have Git** (type `git --version` in a Command Prompt; it prints a version
number): in a Command Prompt (as administrator):

```
git clone --branch v0.1.0-beta https://github.com/jim-wyatt/w11kit.git C:\W11Kit
git -C C:\W11Kit -c gpg.ssh.allowedSignersFile=C:/W11Kit/config/release-signers verify-tag v0.1.0-beta
```

The first line downloads the release `v0.1.0-beta` (the project page lists newer ones: use the
newest). **You'll see** a few lines ending with `done.` The second checks the release's signature:
it prints `Good "git" signature for w11kit-release` and a fingerprint, which must be the one in
[SECURITY.md](../SECURITY.md#verifying-a-release) on the project's page. Anything else: stop, and
[report it](../SECURITY.md#reporting-a-vulnerability). Then go on to [step 3](#step-3-prepare-the-pc).

**Why as administrator?** The kit decides what goes into your new Windows, so only an
administrator should be able to change it. The kit locks its folder: other accounts can read it
but not change it ([folder lock](GLOSSARY.md#folder-lock)).

**If you don't have Git** (the command says *'git' is not recognized*): the kit installs it for
you in step 3. Until then, use a ZIP download:

1. On the project's page, choose **Download ZIP**.
2. In your Downloads folder, right-click the ZIP → **Properties**. If there is an **Unblock** box
   at the bottom, tick it and click **OK**. (This stops Windows warning about every file in it.)
3. Right-click the ZIP → **Extract All…** and extract it to `C:\W11Kit-download`.
4. Open `C:\W11Kit-download`. If you see another folder inside with the same files in it, go into
   it. You should see files such as `Run-Prepare.cmd` and `README.md`.

The last item of step 3 replaces this ZIP copy with a Git clone.

**One folder holds everything.** Whatever the kit downloads or makes goes into its
*[work folder](GLOSSARY.md#work-folder)*, `C:\W11Kit\work`: the updates, your drivers, the logs,
the finished ISO and the file with the passwords.

## Step 3: Prepare the PC

*10–20 minutes, plus one restart.*

`Run-Prepare.cmd` checks that this PC can build the ISO and installs what is missing. It changes
nothing without asking.

1. Open the kit folder (`C:\W11Kit`, or `C:\W11Kit-download` if you used the ZIP) and double-click
   **`Run-Prepare.cmd`**. Approve the UAC prompt.
2. A window lists checks with `[OK   ]`, `[WARN ]` or `[BLOCK]` in front of each.
3. It says what is missing and asks `Install them now? [Y/n]`. Type `Y` and press Enter.

What it installs, and why:

| Tool | Why |
|---|---|
| Git for Windows | Copies the kit into the ISO, so you can rebuild after the reinstall |
| Python 3 | Every build reads Microsoft's security baselines with it. It also runs the scripts that download the Windows updates |
| Windows ADK Deployment Tools | Microsoft's tool that writes the ISO file (only this one part, about 100 MB) |
| Hyper-V | Windows' own virtual machine feature, for the test in step 9. Needs a restart |

Each one comes from its official download. The kit checks its *[hash](GLOSSARY.md#hash-sha-256)*
(a file's fingerprint) and its digital signature before it runs. None of these tools end up in
the Windows you install. By installing them you accept their publishers' licence terms.

**You'll see** at the end:

```text
READY: this PC can build the ISO.
```

or, in yellow, `READY after a restart: restart Windows to finish enabling Hyper-V.` Then *Press
any key to continue*.

4. If it said *restart*, restart Windows now.
5. **Only if you used the ZIP:** Git is installed now. Open a **new** Command Prompt (as
   administrator), so that it finds Git, and run:

   ```
   git clone --branch v0.1.0-beta https://github.com/jim-wyatt/w11kit.git C:\W11Kit
   git -C C:\W11Kit -c gpg.ssh.allowedSignersFile=C:/W11Kit/config/release-signers verify-tag v0.1.0-beta
   ```

   The second line checks the signature, as in [step 2](#step-2-get-the-kit).

   From now on, use `C:\W11Kit`. You can delete `C:\W11Kit-download`; Windows asks for
   administrator approval, because the kit made a locked `work` folder inside it.

**If it goes wrong:**

| You see | Do this |
|---|---|
| `[BLOCK] Windows edition` … `Home` | Upgrade to Pro (Settings → System → Activation), then run it again |
| `[BLOCK] Controlled Folder Access` | Windows Security → Virus & threat protection → Ransomware protection → **Controlled folder access: Off**. Run it again ([what this is](GLOSSARY.md#controlled-folder-access)) |
| `[BLOCK] ASR prevalence rule` | A security rule on this PC blocks the build's tools ([ASR](GLOSSARY.md#asr-attack-surface-reduction)). The line after it says where to change it. If your employer manages this PC, build on another PC |
| `[BLOCK] Free space` | Free up space on `C:` and run it again ([what you can delete](TROUBLESHOOTING.md#freeing-space)) |
| `[WARN ] Virtualization in firmware: off` | The build works, but the test in step 9 needs it. Read [Before any BIOS change](#before-any-bios-change), then turn on *SVM* (AMD) or *Intel Virtualization Technology* (Intel) in the BIOS and run it again ([what this is](GLOSSARY.md#virtualization-svm-vt-x)) |
| `[FAIL ]` next to a tool | Its download or install failed. Check the internet connection and run it again. The log is in the `work\logs` folder of the kit folder you ran it from |

More: [Troubleshooting](TROUBLESHOOTING.md#preparing-and-building).

## Step 4: Download Windows

*15–30 minutes, mostly download time.*

The kit builds on top of the official Windows 11 ISO from Microsoft. Microsoft doesn't allow
scripts to download it, so you download it once in your browser.

1. Go to Microsoft's [Windows 11 download page](https://www.microsoft.com/software-download/windows11).
2. Find the section **Download Windows 11 Disk Image (ISO) for x64 devices**.
3. In *Select Download*, choose **Windows 11 (multi-edition ISO for x64 devices)** and click
   **Download Now**.
4. In *Select the product language*, choose **English (United States)** and click **Confirm**.
   (English International works too. Other display languages aren't supported yet:
   [another language](reference/CONFIGURATION.md#another-language).)
5. Click **64-bit Download**. Save the file in your **Downloads** folder. It is about 7–9 GB.
6. Don't rename it if its name starts with `Win11` or `Windows11`: the kit looks for those names
   in Downloads.

**Why the kit checks the ISO.** Every file has a *[SHA-256 hash](GLOSSARY.md#hash-sha-256)*: a
long code that changes completely if even one byte of the file changes. The kit knows the hashes
of the official ISOs it was tested with (`config\source-iso.json`) and stops at any other file.
That way you know you're building from Microsoft's untouched Windows.

### If the kit doesn't know your ISO

In step 8 the check may say `[FAIL] Source ISO is an accepted, official release`. That usually
means Microsoft has published a newer ISO than the kit knows.

**You'll see:**

```text
  [FAIL] Source ISO is an accepted, official release  SHA-256 <your file's hash> is in neither config\source-iso.json nor config\source-iso.local.json
         To accept this ISO:
         1. Compare the SHA-256 above with the one Microsoft lists for your language under 'Verify your download' on
            https://www.microsoft.com/software-download/windows11 . Not the same: the file is damaged or not Microsoft's; download it again.
         2. The same: save this as C:\W11Kit\config\source-iso.local.json (git ignores that file), then run the build again:
            { "accepted": [ { "file": "<your file's name>", "sha256": "<your file's hash>", "verified": "<today>, against Microsoft's download page" } ] }
```

You can accept the ISO yourself, after checking that it really is Microsoft's:

1. Back on Microsoft's download page, after you picked the language, there is a **Verify your
   download** link. It lists the SHA-256 of each language. Find your language and compare it with
   the SHA-256 in the kit's message. **They must be the same.** If they differ, delete the file
   and download it again. Don't accept it.
2. Check the version on that page. If it is still **26H2**, go on. If it is a newer release (for
   example 27H2), stop: the kit itself needs an update for that release.
3. Open Notepad as administrator. Paste the last line of the message (the one in `{ }`). Choose
   **File → Save as**, set *Save as type* to **All files**, and save as
   `C:\W11Kit\config\source-iso.local.json`.
4. Run the check from step 8 again.

That file is yours: updating the kit never touches it, and the ISO carries a copy.

## Step 5: Your PC's profile

*2 minutes. You can skip this step: `Run-Build.cmd` in step 8 offers to make the profile for you.
Do it here if you want to look at the profile first.*

A *[hardware profile](GLOSSARY.md#hardware-profile)* is a small file that describes your PC model:
which makers' drivers to carry, which devices must work after the install, how the PC sleeps, and
how Windows is licensed on it.

1. Double-click **`C:\W11Kit\New-Profile.cmd`** and approve the UAC prompt. It asks no questions.
   It reads this PC and writes the profile.
2. **You'll see** `Profile '<id>' written to C:\W11Kit\profiles\<id>\profile.json` in green, and a
   summary. The id (for example `dell-xps-8960`) is made from your PC's maker and model. You
   don't have to type it later: the harvest and the build find the profile that fits this PC.
3. Press a key to close the window.

The summary's lines, in plain words:

| Line | Meaning |
|---|---|
| `match` | The maker and model this profile is for. The kit takes the profile by itself on a PC that fits. `null` (a PC whose maker left the model name empty): `Run-Build.cmd` lists the profile and asks |
| `ISO name` | What the finished ISO will be called. The computer name is random unless you set `computerName` in [your settings](#step-7-your-settings) |
| `licence` | How the new install selects Pro. A firmware key for Pro: your PC has a Pro key built in. Otherwise the generic Windows 11 Pro installation key selects the edition (it does not activate Windows and is not a licence), and your PC's [digital licence](GLOSSARY.md#digital-licence) activates it |
| `drivers` | The makers whose drivers go into the image (for example AMD, NVIDIA, Realtek). Usually right as it is |
| `power` | `default`: the kit sets no power options of its own. `hibernate`: see the options below |
| `Kernel DMA` | Whether the PC protects its memory from plugged-in devices. It decides how strict the BitLocker step is ([step 15](#step-15-turn-on-bitlocker)) |
| `checks` | The devices the validator must find working after the install (graphics, sound, network, Bluetooth) |

The profile is yours: updating the kit leaves it alone, and the ISO carries a copy.

**The reference PC.** For a Lenovo Legion T5 30AGB10 (machine type 90YJ) with a GeForce RTX 5070
and MediaTek RZ616 Wi-Fi, the kit already has the profile `legion-t5`. Skip this step and read
its notes: [profiles/legion-t5/README.md](../profiles/legion-t5/README.md). A Legion T5 with
other parts needs its own profile.

**Options** (most people don't need them). In a Command Prompt:

```
C:\W11Kit\New-Profile.cmd -Hibernate -WakeOnLan -Force
```

- `-Hibernate`: the PC [hibernates](GLOSSARY.md#hibernate) after 30 minutes idle and on the power
  button, instead of sleeping.
- `-WakeOnLan`: another device on your network can switch this PC on through its wired network
  port ([Wake-on-LAN](GLOSSARY.md#wake-on-lan)).
- `-Force`: overwrite a profile you made before.

Every field of the file: [Profiles](reference/PROFILES.md).

## Step 6: Collect the drivers

*5–15 minutes. You can skip this step too: `Run-Build.cmd` in step 8 offers it.*

*[Drivers](GLOSSARY.md#driver)* are the small programs that let Windows use your hardware. The
kit copies the drivers your PC uses **right now** into the new image: they work, so they are the
safest choice. This is called the [harvest](GLOSSARY.md#harvest). Do it on the PC you reinstall,
before you reinstall it. It changes nothing on the PC.

1. Double-click **`C:\W11Kit\Run-Harvest.cmd`**. It takes the profile that fits this PC. (Only if
   your profile's `match` line said `null`: in a Command Prompt, run
   `C:\W11Kit\Run-Harvest.cmd -Profile <id>` with your profile's id.)
2. Approve the UAC prompt. A new window opens.
3. **You'll see** `Hardware profile: …`, then `Exported N driver packages.`, a table of the
   drivers it keeps (`Curated: N packages. Excluded: N.`), and at the end, in green:

   ```text
   Harvest complete.
   ```

What it does:

- It saves the drivers in `C:\W11Kit\work\DriverExport`, and a copy in
  `C:\W11Kit\work\DriverExport.zip`.
- It writes a list of every driver file with its hash. The build checks the drivers against that
  list, so nothing can be slipped in between the harvest and the build.
- It never copies BIOS or firmware updates: they could rewrite your PC's firmware during the
  install.

**If it goes wrong:**

| You see | Do this |
|---|---|
| `PROFILE MISMATCH`, three times | The profile you named with `-Profile` is for a different PC model. Drivers always come from the PC the harvest runs on |
| `Some bound platform drivers are missing from the curated set.` | A driver the profile should carry couldn't be copied. Keep the window open and see [Troubleshooting](TROUBLESHOOTING.md#drivers-and-devices) |

## Step 7: Your settings

*2–5 minutes. Many people change nothing here.*

Without any settings from you, the new Windows gets:

- **this PC's own** time zone, keyboard layout, date and number formats, and country;
- two accounts named `LocalAdmin` (the admin account) and `LocalUser` (your daily account);
- the kit's options at their defaults: no gaming tweaks, Smart App Control left as Windows sets
  it, a monthly reminder to make an offline backup.

The build in step 8 shows what it will use, and where each value comes from. **You'll see**, near
the top of its window (the values are your PC's):

```text
  keyboard       0809:00000809                (from this PC)
  formats        en-GB                        (from this PC)
  system locale  en-GB                        (from this PC)
  time zone      GMT Standard Time            (from this PC)
  home location  GB (242)                     (from this PC)
  (this PC's values were read as MYPC\Alex, the account that started Run-Build.cmd)
```

If that is what you want, go on to [step 8](#step-8-build-the-iso). The values are those of the
account that starts `Run-Build.cmd`, so start it from your own account (a double-click, or a
normal Command Prompt), not from a window that another administrator account opened.

**To change something**, make your own settings file. The kit's defaults are in
`C:\W11Kit\config\settings.defaults.json`. **Don't edit that file.** Yours is
`settings.local.json` next to it. It holds only what you want different, and updating the kit
never touches it.

1. Open Notepad as administrator.
2. Type your settings. For example, your own account names and the gaming tweaks:

   ```json
   {
     "accounts": { "admin": "HomeAdmin", "user": "Alex" },
     "options": { "gamingTweaks": true }
   }
   ```

   Or a UK keyboard, formats, time and country on a PC that is set up differently today:

   ```json
   {
     "locale": {
       "inputLocale": "0809:00000809",
       "systemLocale": "en-GB",
       "userLocale": "en-GB",
       "timeZone": "GMT Standard Time",
       "homeLocation": { "geoId": 242, "isoCode": "GB" }
     }
   }
   ```

3. Choose **File → Save as**, set *Save as type* to **All files**, and save as
   `C:\W11Kit\config\settings.local.json`.

The settings most people look at:

| Setting | What it is |
|---|---|
| `accounts` → `admin`, `user` | The names of the two accounts. Choosing your own is a good idea |
| `computerName` | The PC's name on the network. Without it Windows picks a random one |
| `locale` → `timeZone`, `inputLocale`, `userLocale`, `systemLocale`, `homeLocation` | Time zone, keyboard, formats, and your country (the Microsoft Store uses it) |
| `options` → `gamingTweaks` | Game Mode, GPU scheduling, the Xbox services set to start when a game needs them, and the Xbox app pinned to Start. Off unless you turn it on |
| `options` → `smartAppControl` | `"leave"` (as Windows sets it) or `"off"` (if you run programs you build yourself) |
| `reminders` | What *Validate PC* reminds you of: offline backup, OneDrive folder backup, and more |

Every field, with its values: [your settings](reference/CONFIGURATION.md#your-settings).

**Your keyboard matters.** `inputLocale` is the keyboard layout the new Windows starts with, at
the sign-in screen too. The kit's one-time passwords use only letters and digits that sit in the
same place on common layouts, but the passwords you choose later may not.

Rules for this kind of file ([JSON](GLOSSARY.md#json)):

- Names and text are in double quotes. `true`, `false` and numbers have no quotes.
- Entries inside a `{ }` block are separated by commas. The last one has no comma.
- The time zone must be Windows' own name for it. In a Command Prompt, `tzutil /l` lists them
  (the second line of each pair is the name to use).

You don't have to check the file yourself. The next step does, and names the field that is wrong.
If you get stuck, delete `settings.local.json` and start again.

## Step 8: Build the ISO

*45–75 minutes, plus the downloads the first time.*

`Run-Build.cmd` asks before each thing it does, checks everything it needs (the
*[preflight](GLOSSARY.md#preflight)*), and then builds.

1. Double-click **`C:\W11Kit\Run-Build.cmd`** and approve the UAC prompt. A new window opens.

   **You'll see** first:

   ```text
   W11Kit - builds a Windows 11 Pro install ISO for YOUR OWN PC.          (beta, MIT License, NO WARRANTY)
     * Installing the ISO ERASES the disk you choose and applies a strict security configuration.
     * You need your own Windows 11 Pro licence. The install is unattended: by building and installing
       you accept Microsoft's licence terms for Windows and for the tools this build installs.
     * The ISO holds Windows, your drivers and your one-time passwords: never share or upload it.
     * Independent project: not affiliated with or endorsed by Microsoft or DISA; not a compliance product.
   ```

2. Then it asks its questions, each only when it applies:

   | It asks | Answer on your first build |
   |---|---|
   | `Update the kit to its newest signed release first? [y/N]` | Press Enter (No). You just downloaded it |
   | `Install them now? [Y/n]` (a build tool is missing) | `Y` |
   | `Download this month's Windows updates (~5 GB), Microsoft's security baselines (~2 MB) and the Git and Python installers (~100 MB) now? [Y/n]` | `Y`. Everything comes from Microsoft's and the tools' official servers, and every file's hash is checked. The question names only what is still missing |
   | `No hardware profile for this PC yet. Make one now from this PC? [Y/n]` (you skipped step 5) | `Y`, unless you build for another PC or want the `generic` profile on purpose |
   | `Collect this PC's drivers now? (Only if this is the PC you will reinstall.) [Y/n]` (you skipped step 6) | `Y`, **only if this is the PC you will reinstall** |

3. The preflight follows. It reads the Windows ISO (about a minute) and lists its checks with
   `[OK  ]`, `[NOTE]` or `[FAIL]`. If a line says `[FAIL]`, the build stops with `Pre-flight
   failed: … Nothing was changed.` The line says what is wrong; the common ones are in the table
   below.
4. The build runs through steps that start with `==> [time]`, for example `Adding <update>.msu`,
   `Component cleanup`, `Adding drivers from …`, `Verifying the image …` and `Building …iso`.
   Some steps print nothing for 10 minutes or more. That's normal. Don't close the window. The
   build keeps the PC from going to sleep while it runs; on a laptop, keep the lid open and the
   charger plugged in.
5. **You'll see** at the end:

   ```text
   BUILD COMPLETE.
   ISO:    C:\W11Kit\work\Win11Pro-<tag>-<build>-<date>-<time>.iso
   SHA256: <a long code>
   Built-in accounts (disabled): Administrator is renamed <name>, Guest is renamed <name> (drawn for this build; also in build-options.json on the installed PC)
   Accounts: LocalAdmin / LocalUser, one-time passwords in C:\W11Kit\work\accounts.txt (admins only; its last line names this ISO). Put them in a password manager you can open on another device (or on paper) BEFORE reinstalling this PC: the reinstall wipes C:, then delete the file
     To open it: Start > type Notepad > right-click Notepad > Run as administrator > File > Open > C:\W11Kit\work\accounts.txt
   Keep this ISO private: it contains Microsoft Windows, your drivers and your one-time passwords. Do not share, upload or sell it.
   ```

   `<tag>` is a short name from your profile. The *Built-in accounts* line is only for your
   information: Windows' own Administrator and Guest accounts stay switched off, and the build
   gives them new names.
6. The last question is `Test this ISO in a virtual machine now (about 30 minutes)? [Y/n]`.
   Answer `Y`: that is [step 9](#step-9-test-it-in-a-virtual-machine). While it runs, save the
   passwords (below).

**Only want the check?** `C:\W11Kit\Run-Build.cmd -Preflight` (in a Command Prompt) asks nothing,
downloads nothing and changes nothing. It ends with `Pre-flight passed. Nothing was changed.` in
green, or with the `[FAIL]` lines. `[FAIL]` lines about the updates, the security baselines, the
installers or the drivers are normal before the first build: the build itself offers to get them.

**Before the build writes the ISO, it checks the finished image** against everything it was
supposed to contain. If anything doesn't match, it stops with `BUILD FAILED` instead of giving
you a broken ISO.

### Save the two passwords now

The build created two accounts for the new Windows, each with a random **one-time password**:

- **`LocalAdmin`** (or the name you chose): the admin account. You only use it to approve
  installs and changes.
- **`LocalUser`** (or the name you chose): your daily account.

The passwords are in `C:\W11Kit\work\accounts.txt`, which only an administrator can open. **The
reinstall erases `C:`, so copy them now to a place that is not on this PC:**

1. Open Notepad as administrator.
2. **File → Open**, type `C:\W11Kit\work\accounts.txt` in *File name*, and press Enter.
3. Look at the **last line** of the file: it names the ISO these passwords belong to. They fit
   that ISO and no other. Every build makes new passwords.
4. Copy both passwords, **and the ISO name with them**, into a password manager you can open on
   your **phone or another PC**, or write them on paper and keep it somewhere safe.
5. Close Notepad.

Good to know:

- The passwords are 20 characters, letters and digits only. Look-alikes (such as `0` and `O`) and
  the letters `Y` and `Z` are left out, so you can read them off paper and type them on any common
  keyboard. Upper and lower case matter.
- They are "one-time": at the first sign-in, Windows makes you choose your own password for each
  account.
- **Type carefully.** After 10 wrong passwords in a row, Windows locks that account for 15
  minutes. Then you can try again.
- Lost one? See [Lost or forgot a password?](AFTER-INSTALL.md#lost-or-forgot-a-password)

**If it goes wrong:**

| You see | Do this |
|---|---|
| `[FAIL] Source ISO  none found: …` | The ISO must be in a Downloads folder and its name must start with `Win11` or `Windows11`. Or name it: `Run-Build.cmd -SourceIso "D:\My ISOs\Win11.iso"` (double quotes around a path with spaces) |
| `[FAIL] Source ISO is an accepted, official release` | See [If the kit doesn't know your ISO](#if-the-kit-doesnt-know-your-iso) |
| `[FAIL] Settings valid` | The message names the wrong field. Fix it in `settings.local.json` ([step 7](#step-7-your-settings)) |
| `[FAIL] Cumulative update`, `.NET update`, `Safe OS updates` or `Security baseline zip: …` | Run the build again and answer `Y` to the download question |
| `[FAIL] Python 3 (the build imports the security baselines with it)` | Run the build again and answer `Y` to `Install them now? [Y/n]` |
| `[FAIL] Curated drivers` | Run the build again and answer `Y` to the drivers question, or do [step 6](#step-6-collect-the-drivers) |
| `[FAIL] Build inputs: git can read the kit` … `is not a Git clone` | The kit folder is a ZIP copy. Do the clone at the end of [step 3](#step-3-prepare-the-pc) and build from `C:\W11Kit` |
| `[FAIL] Firmware key is a Pro key` | Your PC's built-in key isn't for Pro. Open `C:\W11Kit\profiles\<id>\profile.json` in Notepad (as administrator), change `"productKey": "firmware"` to `"productKey": "generic"`, save, run again |
| `BUILD FAILED: …` | Keep the window open. The log is `C:\W11Kit\work\logs\build-<date>-<time>.txt`. See [Troubleshooting](TROUBLESHOOTING.md#preparing-and-building) |

Every option of the build: [build options](reference/BUILD-OPTIONS.md#build-options).

## Step 9: Test it in a virtual machine

*15–45 minutes. You only start it; it runs by itself.*

Before you erase your PC, the kit installs the new ISO in a
*[virtual machine](GLOSSARY.md#virtual-machine-vm)* (a simulated PC inside Windows, using
Hyper-V) and checks the result. Everything happens as it will on your PC: Setup, the
*[first-boot setup](GLOSSARY.md#first-boot-setup)*, the restart, and the validator's report.

1. If you answered `Y` at the end of the build, the test is already running. Otherwise
   double-click **`C:\W11Kit\Run-VmTest.cmd`** and approve the UAC prompt. It tests the newest
   ISO in `C:\W11Kit\work`.
2. The test keeps the PC from going to sleep while it runs. On a laptop, keep the lid open and
   the charger plugged in: a PC that sleeps makes the test run out of time and fail.
3. **You'll see** lines with times, such as `Making a test copy of …`, `VM started: Windows Setup
   is running (unattended)`, `VM restarted (#1)`, `PostInstall reported: …` and `Windows is back
   up after the PostInstall restart`. You can watch the virtual PC (Hyper-V Manager →
   *W11Kit-ISO-Test* → Connect), but don't type anything in it.
4. At the end it prints a **VM TEST SUMMARY** and, last, in green:

   ```text
   RESULT: PASS
   ```

**Your ISO isn't changed.** The test works on its own copy, which is why it needs about 50 GB
free while it runs. That copy is set up to erase the virtual machine's disk without asking. Two
things keep it away from a real PC: it switches itself off on anything that is not a Hyper-V
virtual machine, and the kit deletes it when the test ends.

**Reading the summary.** Some checks *can't* pass in a virtual machine, because it doesn't have
your PC's hardware: your graphics card, sound, Wi-Fi, Wake-on-LAN, a Windows licence, and
BitLocker (you turn that on yourself later). These are listed as `expected` with the reason in
brackets. They are fine. A line starting with **`UNEXPECTED`** (in red) is a real problem.

**Go on only after `RESULT: PASS`.** If it says `RESULT: FAIL`, read the `UNEXPECTED` lines and
see [Troubleshooting](TROUBLESHOOTING.md#the-vm-test). All the test's files are in
`C:\W11Kit\work\vmtest\results`.

## Step 10: Copy to your backup drive and make the USB stick

*30–60 minutes.*

**Which ISO.** The newest file named `Win11Pro-<tag>-<build>-<date>-<time>.iso` directly in
`C:\W11Kit\work` (sort by *Date modified*). Open `accounts.txt` again and check that the ISO name
on its **last line** is exactly this file's name. If it isn't, the passwords you saved belong to
another build: save the ones in this file instead.

Never use a file with `TEST` in its name. That is a *[test build](GLOSSARY.md#test-build-and-real-build)*
(made with `-TestBuild`): it has other passwords and is for the virtual machine only.

**Which stick, later.** Every ISO has a file `W11KIT-THIS-STICK.txt` at its top level. On any PC,
open it from the stick to see which ISO the stick was made from, when, for which profile, and
whether it is a test build. A test build's stick is also named `WIN11PRO_<TAG>_TEST` in Explorer.

> [!CAUTION]
> **Keep the ISO and the stick private.** They hold Windows, your drivers and your one-time
> passwords. Don't upload, share or sell them.

**Copy to the backup drive first** (the reinstall erases these):

- that ISO, with its `.sha256` and `.manifest.json` files (the
  [manifest](GLOSSARY.md#manifest) lists what went into the build);
- `C:\W11Kit\work\DriverExport.zip` and `C:\W11Kit\work\DriverExport.zip.sha256`;
- your profile folder `C:\W11Kit\profiles\<id>`, and `settings.local.json` and
  `source-iso.local.json` from `C:\W11Kit\config` if you made them (the ISO carries a copy too,
  but a second copy costs nothing);
- **the Windows ISO from your Downloads folder** (the one from step 4): it is your
  [Plan B](#plan-b-your-way-back).

**Make the USB stick** with [Rufus](https://rufus.ie), a free tool for this:

1. Download Rufus from rufus.ie and start it. Plug in the USB stick.
2. **Device:** your USB stick (check the size and name). Unplug your backup drive first, so you
   can't pick it by mistake.
3. **Boot selection:** click **SELECT** and choose the ISO you picked above.
4. **Partition scheme:** GPT. **Target system:** UEFI (non CSM). **File system:** FAT32 (if Rufus
   shows NTFS, change it to FAT32). Leave the rest as it is.
5. Click **START**. If a box called **Windows User Experience** appears, **untick every option**
   and click **OK**: the ISO already has its own answers for Setup.
6. Confirm that the stick may be erased. Wait until the status bar says **READY** (15–40
   minutes).

> [!CAUTION]
> **Rufus erases everything on the stick you select.** Check the device name and size twice.

The ISO is about 28 GB, larger than usual, because it carries everything needed to rebuild it
later ([build inputs](GLOSSARY.md#build-inputs)). Microsoft's Media Creation Tool can't write a
custom ISO; use Rufus.

### Plan B: your way back

Prepare this **before** you install, while your current Windows still works. If the install fails
or the new Windows doesn't work on your PC, this is how you get back to a working PC:

- **Until you delete partitions in step 12, nothing is lost.** If anything looks wrong before
  that point (the stick doesn't start, Setup shows an error, you're not sure which disk is which),
  unplug the stick and restart. Your current Windows starts as before.
- **A plain Windows installer.** The official Windows ISO from step 4 is on your backup drive.
  With Rufus you can write it to a USB stick and install standard Windows 11 the usual way, with
  Setup's own questions. No second PC with Rufus? On any Windows PC, Microsoft's *Media Creation
  Tool* ([Windows 11 download page](https://www.microsoft.com/software-download/windows11)) makes
  the same kind of stick. Your Pro licence activates that install too, once it's online.
- **Your backup** brings your files back onto whichever Windows you end up with.
- **Your old disk's recovery key** (if step 1 found the disk encrypted) lets you into the old
  Windows if a BIOS change makes it ask for the key, as long as you haven't installed over it.
- **Keep the backup drive as it is** until the new install has run well for a few weeks.

## Step 11: BIOS/UEFI settings

*10 minutes.*

Read [Before any BIOS change](#before-any-bios-change) first: it tells you how to pause disk
encryption and how to get into the BIOS. Each PC maker's screens look different, so this step is
general.

1. If your PC maker's support site has a **newer BIOS** for your model, install it first,
   following the maker's instructions. The new Windows won't get BIOS updates by itself.
2. Check these settings. **Change only these:**

| Setting | Should be | Why |
|---|---|---|
| Secure Boot | **Enabled**, keys as they came | Only trusted start-up code runs. Windows' memory protection and BitLocker depend on it ([Secure Boot](GLOSSARY.md#secure-boot)) |
| TPM (also called fTPM, PTT, Pluton or Security Chip) | **Enabled** | Holds the BitLocker key and the Windows Hello PIN ([TPM](GLOSSARY.md#tpm)) |
| Virtualization (SVM on AMD, VT-x on Intel) | **Enabled** | Windows' memory protection and WSL use it ([virtualization](GLOSSARY.md#virtualization-svm-vt-x)) |
| IOMMU (AMD) or VT-d (Intel) | **Enabled** | Protects memory from plugged-in devices. BitLocker relies on it ([DMA protection](GLOSSARY.md#dma-protection-kernel-dma-protection-iommu)) |
| Boot mode | **UEFI** only; *CSM* / *Legacy* off | The stick starts in UEFI mode only ([GPT and CSM](GLOSSARY.md#gpt-uefi-and-csm)) |
| Boot order | **Internal disk first** | You start from the stick with a one-time menu instead (next step) |
| Wake on LAN, and [ErP](GLOSSARY.md#erp) / deep sleep (only if your profile uses Wake-on-LAN) | Wake on LAN **Enabled**, ErP **Disabled** | Otherwise the network card has no power while the PC is off |

3. Save and exit.

Leave the **BIOS administrator password** for later. You set it once the new Windows works
([a BIOS password](AFTER-INSTALL.md#a-bios-password)): on some PCs it also guards the boot menu
or a BIOS update, which you still need now.

## Step 12: Install

*30–60 minutes, mostly waiting.*

> [!CAUTION]
> **Installing erases the disk you choose, completely.** Everything on it is gone: your old
> Windows, your programs, your files. There is no undo. Before you start, check:
>
> - your backup is complete, and you've opened a few files **from the backup drive** to make sure;
> - the two passwords **and the ISO name** are saved off this PC
>   ([step 8](#save-the-two-passwords-now)), and the ISO name matches the stick
>   ([step 10](#step-10-copy-to-your-backup-drive-and-make-the-usb-stick));
> - your [Plan B](#plan-b-your-way-back) is ready.

> **Your decision, your risk.** From here on the install runs by itself. It accepts the Microsoft
> Software License Terms for Windows on your behalf (you need your own Windows 11 Pro licence),
> erases the disk you pick, and applies a strict security configuration. The kit comes with no
> warranty ([LICENSE](../LICENSE)): if the install fails, a device has no driver, or a program you
> need no longer runs, your backup and your [Plan B](#plan-b-your-way-back) are the way back.

1. **Unplug the backup drive and every other USB disk or stick** (external disks, card readers
   with a card in them, phones in file-transfer mode). Only the install stick stays. A
   disconnected disk is one you can't erase by mistake.
2. Plug in the **network cable** and the **USB stick**.
3. Restart the PC and press the **[boot menu](GLOSSARY.md#boot-menu) key** repeatedly: often
   **F12**, **F11**, **F8** or **Esc**. A list of devices appears.
4. Pick the entry for your USB stick that starts with **UEFI**. If you see *Press any key to boot
   from CD or DVD*, press a key.
5. Windows Setup starts. It asks **one** question: *Select location to install Windows 11*.
   - Find your internal disk by the **size you noted in step 1**. Setup rounds it a little
     (*953.85 GB* may show as *953.9 GB*). Not the USB stick.
   - **More than one internal disk?** Setup names them *Disk 0*, *Disk 1* and so on, and these
     may not be the numbers Disk Management showed. Go by the sizes. If two disks have almost the
     same size, or you can't tell which one held `C:`, **stop here**: unplug the stick and
     restart into your current Windows. Nothing has changed yet.
   - Click each of that disk's partitions in turn and click **Delete partition**, until the disk
     shows only **Unallocated space**. (**This is where your old Windows is erased.**)
   - Select that **Unallocated space** and click **Next**.
6. Setup copies files. **When the PC restarts for the first time, unplug the USB stick.**
7. Windows finishes by itself, with no more questions. After a few restarts, the admin account
   signs in **by itself, once**, and a PowerShell window runs the first-boot setup: security
   settings, power settings, a restore point, updates. **Don't close it.** Usually after 10–30
   minutes (on a slow PC up to 40) it says the PC restarts in 2 minutes, and restarts.

**Why Setup asks about the disk.** The kit never chooses a disk for you, so Setup never erases a
disk by itself. You can still pick the wrong one: check its size.

**If it goes wrong:**

| You see | Do this |
|---|---|
| Anything looks wrong **before** you delete partitions | Unplug the stick and restart. Your current Windows is untouched |
| The USB stick isn't in the boot menu | Try another USB port (on a desktop, one at the back). Check that Secure Boot is on and the PC starts in UEFI mode |
| *Secure Boot violation* | The PC's firmware is too old for the stick's start-up files. See [Troubleshooting](TROUBLESHOOTING.md#installing) |
| Setup asks for a product key | See [Troubleshooting](TROUBLESHOOTING.md#installing) |
| Red text `SECURITY BASELINE OVERRIDES FAILED - DO NOT RESTART YET`, or the PC doesn't restart by itself | **Don't restart.** Follow [Setup did not finish](TROUBLESHOOTING.md#setup-did-not-finish) |
| Anything else after the old Windows is gone | [Plan B](#plan-b-your-way-back) |

## Step 13: First sign-in

*10 minutes.*

The new Windows has two accounts, and you sign in to both once:

- The **admin account** (`LocalAdmin`). You never work in it. Windows asks for its password when
  something needs administrator rights.
- The **daily account** (`LocalUser`). It is a
  [standard account](GLOSSARY.md#administrator-and-standard-accounts): if a program or a website
  tricks you into running something bad, it can't change Windows itself.

Neither is a Microsoft account. You can still sign in **inside** apps (Store, OneDrive, Edge).

1. At the sign-in screen, choose **LocalAdmin** and type its one-time password. Windows says the
   password must be changed: click **OK**, type the old password once and the new one twice.
   - The new password needs at least **11 characters** and three of: upper case, lower case,
     digits, symbols.
   - Save it in your password manager (the one on your phone or another PC).
2. **Sign out** (Start → your account name → Sign out).
3. Choose **LocalUser** and do the same. **From now on, always use this account.**
4. Optional but handy: **Settings → Accounts → Sign-in options → PIN (Windows Hello)**. A PIN (at
   least 6 characters) is quicker than the password and works only on this PC.
5. Connect to Wi-Fi if you use it (the network icon at the bottom right). The sign-in screen has
   no network menu on this image, so you do it after signing in.
6. **Settings → Windows Update → Check for updates.** Install everything and restart. Repeat
   until nothing is left.
7. **Settings → System → Activation** should say **Active**. If it doesn't, stay online and wait
   a few minutes, then use **Troubleshoot** on that page.

Problems here: [first sign-in and activation](TROUBLESHOOTING.md#first-sign-in-and-activation).

## Step 14: Check the PC

*5 minutes.*

1. On the desktop, double-click **Validate PC**. Windows asks for an administrator: choose
   **LocalAdmin** and type its password.
2. A window shows what needs attention first (the FAIL and WARN rows, each with what to do), then
   one line per group of checks, and at the end the totals.

   **You'll see** (your rows and numbers will differ):

   ```text
   NEEDS ATTENTION (0 FAIL, 1 WARN)
     WARN  Security: BitLocker on, TPM-only
           <what the row found, and what to do>

   ALL CHECKS, BY GROUP            PASS  INFO  WARN  FAIL
   Windows and updates               14     4     0     0
   Security policy                   75     6     1     0
   Accounts and privacy              10     1     0     0
   ...

   PASS = as it should be; INFO = a fact, nothing to do; WARN = look at it; FAIL = not as the image was built.
   Every row is in the report file. As one table in this window: Validate-Pc.cmd -All
   FAIL: 0  WARN: 1  (report: C:\ProgramData\W11Kit\W11Kit-Validation.md, C:\Users\Public\Desktop\W11Kit-Validation.md; .json alongside)
   ```

3. The full report is **W11Kit-Validation.md** on the desktop. Open it with Notepad (right-click
   → Open with → Notepad). Its first section is *Needs attention*; then comes one section per
   group, with every row.

Each row is **PASS** (good), **WARN** (works, but read it), **FAIL** (something to fix) or
**INFO** (just information). The goal is `FAIL: 0`. Normal on a fresh install:

| Row | Result | Why |
|---|---|---|
| BitLocker on, TPM-only | WARN | You haven't turned BitLocker on yet: next step |
| Secure Boot DB has Windows UEFI CA 2023; Secure Boot KEK has Microsoft KEK 2K CA 2023; Installed boot manager signed with Windows UEFI CA 2023 | WARN (sometimes) | Windows is still installing Microsoft's new Secure Boot certificates. It finishes over the next restarts |
| Defender tamper protection; Defender signatures current (3 days) | WARN or INFO (first hour) | Defender hasn't had its first update yet. Stay online; they turn to PASS by themselves |
| Defender quick scan in the last 14 days; Offline backup in the last 35 days | INFO | Nothing has had time to happen yet |
| Since last report | INFO | These rows count security events between two reports. The first report has nothing to compare with |

Every WARN and FAIL says what to do in its own text. The less obvious ones are explained in
[the validator's report](TROUBLESHOOTING.md#the-validators-report).

**A FAIL in a hardware row** (graphics, sound, network, Bluetooth) usually means a missing
driver: see [drivers and devices](TROUBLESHOOTING.md#drivers-and-devices).

**Only if your profile uses Wake-on-LAN:** note the MAC address in the *Wake-on-LAN: magic
packet* row. Hibernate the PC (Start → Power → Hibernate) and wait until it's off. From another
device on your network, send a [magic packet](GLOSSARY.md#mac-address-and-magic-packet) to that
address (a phone app called *Wake On LAN*, or `wakeonlan <MAC>` on Linux). The PC should start.
Try once after **Shut down** too.

## Step 15: Turn on BitLocker

*5 minutes, then it works in the background.*

*[BitLocker](GLOSSARY.md#bitlocker)* encrypts your disk. If the PC or the disk is stolen, nobody
can read your files without the PC's own TPM chip or the
**[recovery key](GLOSSARY.md#recovery-key)**.

> [!CAUTION]
> **Lose the recovery key and the data is gone.** Nobody, including Microsoft and this project,
> can recover a BitLocker disk without it. Save it in two places that are not this PC before
> you continue.

Wait until everything works as you want it. Then:

1. Plug in a USB stick (any small one), or have a network folder ready.
2. On the desktop, double-click **Enable BitLocker (local key)** and approve as **LocalAdmin**.
3. It checks the TPM, Secure Boot and DMA protection (about 30 seconds).
4. A folder picker opens: choose **where to save the recovery key**. Pick the USB stick or a
   network share (type it as `\\server\share`; drive letters like `Z:` don't show here). Never
   only `C:`. The script saves the key and reads it back to make sure.
5. Also copy the key into your password manager on your phone or another PC, or onto paper. Open
   the file it saved; the key is a long row of numbers.
6. Type **`YES`** to start. Restart when it says so. Windows tests the TPM, then encrypts in the
   background while you work.

**From now on, before you change any BIOS setting or update the BIOS**, pause BitLocker as
[Before any BIOS change](#before-any-bios-change) says. Otherwise the PC asks for the recovery
key at the next start.

**If it refuses** because *DMA protection* is missing (a line starting *Fix: in the BIOS/UEFI
setup turn on …*): the IOMMU or VT-d setting from step 11 is off. Turn it on as the message says
and try again. More: [BitLocker problems](TROUBLESHOOTING.md#bitlocker).

BitLocker here uses the TPM only, with no PIN at start-up, so the PC can start by itself. Why,
and how to add a PIN: [BitLocker](reference/CONFIGURATION.md#bitlocker). What that leaves open:
[threat model](../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it).

## Done

You have a clean, checked, encrypted Windows 11 Pro. Two short pages take over from here:

- [After the install](AFTER-INSTALL.md): what is different on this PC, installing your programs,
  a BIOS password, backups, getting the kit back.
- [The monthly routine](MONTHLY.md): backup, BIOS check, *Validate PC*, a fresh ISO.

---

← [Home](../README.md) · Next: [After the install](AFTER-INSTALL.md) →
