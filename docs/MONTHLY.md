# The monthly routine

> **W11Kit** · [Home](../README.md) · [1 Guide](GUIDE.md) → [2 After the install](AFTER-INSTALL.md) → **3 Monthly**
> Stuck? [Troubleshooting](TROUBLESHOOTING.md) · A word you don't know? [Glossary](GLOSSARY.md)

About an hour, once a month, a few days after Microsoft's update day (the second Tuesday).

Windows Update keeps the installed PC up to date by itself. This routine looks after what it
doesn't: your backup, the PC's firmware, a look at the security report, and a fresh ISO for the
day you need to reinstall.

## The monthly routine

| # | What | Time |
|---|---|---|
| 1 | [Offline backup](#offline-backup) | 10–30 minutes |
| 2 | [BIOS and firmware updates](#bios-and-firmware-updates): check, install if there is one | 5 minutes to check |
| 3 | [Update your programs](#update-your-programs) | 5 minutes |
| 4 | [Run *Validate PC*](#run-validate-pc) and read what needs attention | 5 minutes |
| 5 | [Rebuild the ISO](#rebuild-the-iso) and write the stick again (optional, recommended) | 1 hour, mostly waiting |

Steps 1 to 4 look after the PC you use. Step 5 makes the next ISO.

## Offline backup

Copy what matters to an external drive, then **unplug it**. Ransomware and a problem with an
online account can't reach a drive in a drawer.
([What a lost disk would cost](../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it))

Copy:

- your folders: Documents, Desktop, Pictures, Downloads, Videos, Music, and anything a program
  keeps in a folder of its own (game saves, add-ons);
- WSL, as one file per Linux installation. In a Command Prompt, as your daily account:

  ```
  wsl --export Ubuntu E:\Backup\ubuntu.tar
  ```

- your SSH keys: `C:\Users\<you>\.ssh` (the WSL export above holds the Linux ones);
- code that isn't pushed anywhere;
- the kit's files that are yours: `C:\W11Kit\config\settings.local.json`,
  `C:\W11Kit\config\source-iso.local.json` and your profile folder `C:\W11Kit\profiles\<id>`;
- the BitLocker recovery key file;
- the newest ISO, with the two one-time passwords from its `accounts.txt`, if you keep one for
  reinstalling.

Then tell the validator that you did it. In a Command Prompt:

```
copy /y nul "%PUBLIC%\Documents\W11Kit-offline-backup.txt"
```

*Validate PC* reads that file's date: its row *Offline backup in the last 35 days* WARNs when the
file is older than 35 days. You don't want the reminder? Set `reminders.offlineBackup` to `false`
in [your settings](reference/CONFIGURATION.md#your-settings).

## BIOS and firmware updates

Windows Update delivers no BIOS or firmware updates on this PC, on purpose, so nobody tells you
about one. Check yourself:

1. **Your PC maker's support page:** is there a newer BIOS than the one you run? The validator's
   *BIOS age* row shows yours.
2. **Your processor maker's security bulletins** (AMD, Intel). Some fixes arrive only in a BIOS.
   Example: AMD's bulletin AMD-SB-7064 concerns the firmware TPM, where BitLocker's key lives;
   its fix comes with a BIOS update from the PC maker.
3. **Your graphics card maker's security bulletins.** If your driver is older than the newest
   bulletin, install the current driver from the maker. Then run the harvest again before your
   next build ([step 6](GUIDE.md#step-6-collect-the-drivers)), so the next ISO carries it.

To install a BIOS update, read [Before any BIOS change](GUIDE.md#before-any-bios-change) first
(it pauses BitLocker), then follow the PC maker's instructions.

## Update your programs

As your daily account, in a Command Prompt:

```
winget upgrade
```

It lists what has an update. Install what you use with `winget upgrade --id <id>`, or everything
with `winget upgrade --all` once you've read the list.

Do it by hand, not on a schedule. An update you didn't see is hard to blame when something
breaks, and a scheduled task that installs software is one more thing to attack.

## Run Validate PC

Double-click **Validate PC** on the desktop and approve as the admin account. The window shows
what needs attention first.

- Every **FAIL** and **WARN** says what to do in its own text.
- The **Since last report** rows count what happened since the month before: failed sign-ins, new
  accounts, additions to groups, new services and tasks, Defender detections, and what changed in
  the drivers, the services' start types and the inbound firewall rules.
- A WARN in one of these four deserves five minutes: *No new user accounts*, *No additions to
  local groups*, *Security log not cleared*, *No malware detections*.

What each row means: [the validator's report](TROUBLESHOOTING.md#the-validators-report).

## Rebuild the ISO

This is optional: the installed PC is already up to date. A rebuild gives you a current ISO and a
stick that still starts.

**Why write the stick again?** The stick's start-up files come from that month's update. When
Microsoft raises their security version, a PC that has taken the update can refuse an older
stick ([Secure Boot certificates](reference/SECURITY-BASELINE.md#secure-boot-2023-certificates)).

1. **If the kit is not on this PC yet,** put it back first:
   [getting the kit back](AFTER-INSTALL.md#getting-the-kit-back).
2. **Build.** Double-click `C:\W11Kit\Run-Build.cmd`. It takes the profile that fits this PC.

   - Answer `y` to `Update the kit to its newest signed release first? [y/N]`. The update brings this month's list
     of Windows updates with it.
   - Answer `Y` to `Download this month's Windows updates now (~5 GB)? [Y/n]`.
   - If your hardware or drivers changed, run the harvest first
     ([step 6](GUIDE.md#step-6-collect-the-drivers)).
3. **Test.** Answer `Y` to `Test this ISO in a virtual machine now (about 30 minutes)? [Y/n]`
   at the end of the build, or run `C:\W11Kit\Run-VmTest.cmd` later. Go on only after
   `RESULT: PASS`.
4. **Save the two new one-time passwords** with the ISO's name
   ([how](GUIDE.md#save-the-two-passwords-now)). Every build makes new ones.
5. **Copy the ISO to your backup drive and write the stick again**
   ([step 10](GUIDE.md#step-10-copy-to-your-backup-drive-and-make-the-usb-stick)). Keep the stick
   with that build's passwords, and as safe as they are
   ([why](reference/BUILD-OPTIONS.md#one-time-passwords)).
6. **Delete the older ISOs** in `C:\W11Kit\work` once the new one is on your backup drive and
   stick. Each is about 28 GB ([freeing space](TROUBLESHOOTING.md#freeing-space)).

**If the build says the kit's update list is old** (`[NOTE] The update pins (config\updates.json)
are … days old`, after 35 days; after 70 days `Run-Build.cmd` asks
`Build with these old updates anyway? [y/N]`): the project hasn't refreshed the list this month.
The image would then be built with last month's updates; Windows Update brings it up to date
after the install. You can also refresh the list yourself:
[moving the pins](dev/MAINTAINING.md#monthly-move-the-pins).

## Updating the kit

`Run-Build.cmd` offers to update the kit each time it starts. To do it by hand, in a Command
Prompt (as administrator):

```
git -C C:\W11Kit pull
```

- In a normal Command Prompt this fails with *Permission denied* or *unable to write*. That is
  the [folder lock](GLOSSARY.md#folder-lock) doing its job.
- Your `settings.local.json`, your `source-iso.local.json` and your own profile folder are not
  touched: Git leaves files it doesn't track alone.
- If the kit added a new setting, the build's check lists it as `Not in the file, kit default
  used`. That's fine.
- If the kit renamed a setting you use, the check says which one, in which file, and what it is
  called now.

> [!CAUTION]
> **Never run `git clean -x` or `git clean -X` in `C:\W11Kit`.** Those delete what Git ignores,
> and that is exactly the work folder: your drivers, your ISOs and the passwords file.

## When this Windows version nears its end

The image keeps the PC on the Windows version it was built from (26H2), so a feature update never
arrives by surprise. Microsoft updates each version of Windows 11 Pro for 24 months: 26H2 until
**2028-10-10**. *Validate PC* shows the date in the row *Feature version still gets security
updates*: WARN from 90 days before it, FAIL after it.

When that row warns, do one of these:

- **Rebuild and reinstall** from a kit that names the next version. This is the kit's way: update
  the kit ([Updating the kit](#updating-the-kit)), then [rebuild the ISO](#rebuild-the-iso).
- **Lift the pin** and let Windows Update install the next version over this one. Sign in as the
  admin account, start `gpedit.msc`, and go to *Computer Configuration > Administrative Templates
  > Windows Components > Windows Update > Manage updates offered from Windows Update*. Open *Select
  the target Feature Update version*, type the new version (for example `27H2`) in the second
  box, and choose OK. Then check for updates. Afterwards *Validate PC* reports the changed value
  in its pin rows until the PC is reinstalled from a newer kit; that is expected.

## Once a year

Make or refresh a plain Windows **recovery drive** on a second stick: Start, type *Recovery
Drive*, use a stick of 16 GB or more, keep *Back up system files* ticked. It starts Windows'
repair tools when the PC won't start and the kit's stick isn't at hand. It asks for the BitLocker
recovery key.

---

← Previous: [After the install](AFTER-INSTALL.md) · [Home](../README.md)
