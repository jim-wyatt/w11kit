# What the image configures

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

The state of a PC installed from this kit, and the reason for each choice. Three things decide it:

- **The kit**: everything on this page, the same for every PC.
- **Your settings**: language, time zone, account names and a few options ([below](#your-settings)).
- **The hardware profile**: drivers, device checks, sleep and wake, licence ([PROFILES](PROFILES.md)).

Related pages: security settings are in [SECURITY-BASELINE](SECURITY-BASELINE.md), removed apps in
[REMOVED-APPS](REMOVED-APPS.md), drivers in [DRIVERS](DRIVERS.md). What you will notice in daily
use is one table: [What is different on this PC](../AFTER-INSTALL.md#what-is-different-on-this-pc).

## Your settings

The kit's defaults are in `config\settings.defaults.json`, the only place they are declared.
**Don't edit that file.** Put your own values in `config\settings.local.json`: Git ignores it, so
updating the kit never touches it. The local file needs only the fields you want to change, in
the same layout. There are 21 fields in five groups; the tables below list every one.

The build takes each setting from the first place that has it:

1. your `config\settings.local.json`;
2. for keyboard, formats, system locale, time zone and home location: **the build PC's own
   current values**;
3. the kit's `config\settings.defaults.json`.

**From this PC.** `Run-Build.cmd` reads the five values before it asks for administrator rights,
as the account that started it. The time zone and the system locale are the PC's; the keyboard,
the formats and the home location are that account's. A value Windows Setup would not accept (a
home location *World*, for example) is not used: the kit's default stays and a `[NOTE]` says so.
The build prints where each value came from, at the top of its window and in the manifest:

```text
  keyboard       0809:00000809                (from this PC)
  formats        en-GB                        (from this PC)
  system locale  en-GB                        (from this PC)
  time zone      W. Europe Standard Time      (settings.local.json)
  home location  US (244)                     (kit default)
  (this PC's values were read as MYPC\Sam, the account that started Run-Build.cmd)
```

If you start `Run-Build.cmd` from a window that another account opened (a Command Prompt of a
separate administrator account), the keyboard, formats and home location are that account's.
Start it from your own account, or set the fields.

**Checked before the build.** The preflight row `Settings valid` stops the build on an unknown
field or a wrong value, so a typo is never silently ignored. The message names the file and the
field, for example
`settings.local.json: unknown field 'locale.keyboard' (the fields are in config\settings.defaults.json)`.
For a field this kit renamed, it gives the new name:

| Old field | Message |
|---|---|
| `checks` | `'checks' is not a field any more: it is now called 'reminders' (the same fields inside)` |
| `options.smartAppControlOff` | `'options.smartAppControlOff' is not a field any more: it is now 'options.smartAppControl': "off" (was true) or "leave" (was false)` |
| `options.developerTweaks` | `'options.developerTweaks' is not a field any more: it is now called 'options.longPaths'` |

The result is stored on the installed PC as `C:\ProgramData\W11Kit\settings.json`, which
first-boot setup and the validator follow, and the build manifest records it.

**Another file.** `Run-Build.cmd -Settings <file>` uses that file in place of
`config\settings.local.json`. It is laid over the kit's defaults in the same way, so it too holds
only the fields you change.

An example `config\settings.local.json`:

```json
{
  "locale": { "timeZone": "W. Europe Standard Time" },
  "accounts": { "user": "Sam" },
  "options": { "gamingTweaks": true }
}
```

### Language and region (`locale`)

| Field | Default | Effect |
|---|---|---|
| `uiLanguage` | `en-US` | Windows' display language: `en-US` or `en-GB` for now ([Another language](#another-language)). It must be the source ISO's language: preflight reads the ISO and stops if they differ |
| `inputLocale` | From the build PC (file: `0409:00000409`) | Keyboard, as `<language id>:<layout id>` (US English: `0409:00000409`). Several are separated by `;`, the first is the default |
| `systemLocale` | From the build PC (file: `en-US`) | Language for older, non-Unicode programs. A language tag such as `en-US` or `de-DE` |
| `userLocale` | From the build PC (file: `en-US`) | Formats: dates, numbers, currency. A language tag |
| `timeZone` | From the build PC (file: `UTC`) | A Windows time zone ID. `tzutil /l` lists them |
| `homeLocation` | From the build PC (file: `{ "geoId": 244, "isoCode": "US" }`) | Country. It is the Microsoft Store's market; the two values must name the same country |

The values marked *file* are what `config\settings.defaults.json` holds. They are used only when
nothing was read from the PC: a build started without `Run-Build.cmd` (`scripts\Build-Iso.ps1`
directly, as an automated job does). The build then prints
`[NOTE] Not in your settings, and not read from this PC (...): the kit's default is used for ...`.
A home location left at *World* makes every Microsoft Store install fail, so the kit always sets a
country.

### Computer name (`computerName`)

| Field | Default | Effect |
|---|---|---|
| `computerName` | `null` | The PC's name: 1 to 15 letters, digits or hyphens, not all digits, and not an account name. `null`: the profile's `computerName`, and if that is `null` too, Windows picks a random name |

`Run-Build.cmd -ComputerName <name>` overrides both for one build.

### Accounts (`accounts`)

| Field | Default | Effect |
|---|---|---|
| `admin` | `LocalAdmin` | The admin account: used at UAC prompts and for installs only |
| `user` | `LocalUser` | The daily account, a standard user |
| `builtinAdministratorName` | `null`: a new name for each build | The new name of Windows' built-in Administrator account, which stays disabled ([Accounts](#accounts)) |
| `builtinGuestName` | `null`: a new name for each build | The new name of Windows' built-in Guest account, which stays disabled |
| `expectedExtra` | `[]` | Local accounts you add on purpose after the install, for example a service account. The validator accepts them in the Administrators group and among the enabled accounts; any other extra account is still reported |

Names are 1 to 20 letters, digits, `.`, `_` or `-`, with no `.` at either end. The four names and
the computer name must all differ, and none may be a name Windows uses itself (`Administrator`,
`Guest`, `DefaultAccount`, `WDAGUtilityAccount`, `defaultuser0`).

### Options (`options`)

An option that is off sets nothing: Windows' own defaults, or Microsoft's baseline, then apply.

| Field | Default | Effect when on |
|---|---|---|
| `gamingTweaks` | `false` | Game Mode, hardware-accelerated GPU scheduling, variable refresh rate; the Xbox services and Secondary Logon usable, the Xbox app pinned to Start and the two Xbox apps checked as required ([Gaming](#gaming)) |
| `smartAppControl` | `"leave"` | `"off"` turns Smart App Control off; `"leave"` leaves it to Windows ([Smart App Control](#smart-app-control)) |
| `bravePolicies` | `false` | Four security policies for the Brave browser ([details](SECURITY-BASELINE.md#optional-brave-policies)) |
| `longPaths` | `false` | Windows programs may use file paths longer than 260 characters (`LongPathsEnabled`). Useful for software development |
| `allowMicrosoftAccount` | `false` | The Windows sign-in may be converted to a Microsoft account ([Accounts](#accounts)) |

| `windowsUpdateDrivers` | `false` | Windows Update delivers driver and firmware updates for the devices already in the PC (BIOS and embedded controller included). A newly connected device still gets no driver from an online search. What it costs: [DECISIONS](../dev/DECISIONS.md#windows-update-does-not-deliver-drivers) (Windows Update may swap a driver, and brings vendor extensions with it) |
| `optionalUpdates` | `"off"` | `"auto"`: Windows Update installs the optional monthly previews and gradual feature rollouts by itself; `"userChoice"`: you pick them in Settings → Windows Update → Advanced options. The Windows release stays pinned either way |
| `controlledFolderAccess` | `true` | Defender's ransomware protection for your documents and pictures folders. A program it doesn't know can't change files there until you allow it (Windows Security → Ransomware protection → Allow an app). `false` turns it off. A build on this PC pauses it, after asking ([The build PC](#the-build-pc)) |
| `asrPrevalenceRule` | `"block"` | Defender's rule that stops programs few people run, unless signed by a known publisher: `"block"`, `"audit"` (only logged) or `"off"`. Programs you build yourself are blocked under `"block"`. A build pauses it to audit, after asking |
| `asrExclusions` | `[]` | Folders or programs, by full path (`"C:\\Tools\\runner"`), that Defender's two reputation rules let run: the prevalence rule above and the baseline's *Use advanced protection against ransomware*, which also stops programs without a reputation yet. Every other ASR rule still covers them. Name a program or a small folder of your own, never a whole drive or a folder others can write to |
| `scheduledValidation` | `true` | *Validate PC* runs by itself, as SYSTEM: on Sundays at 12:00 (or at the next start), and after a Windows Update restart. It writes the report as always, and shows a message to whoever is signed in when a row has turned FAIL since the last report ([the validator's report](../TROUBLESHOOTING.md#the-validators-report)). `false`: no scheduled task |
| `netbios` | `"off"` | NetBIOS over TCP/IP off on every network adapter, so the PC no longer answers old NetBIOS name queries. `"leave"` keeps Windows' default. An adapter added later needs it again: the validator says so |
| `firstNetworkCategory` | `"public"` | `"private"`: the network Windows Setup used becomes *Private* at first boot. On *Public* (Windows' choice for a new network) the baseline ignores firewall rules that apps add themselves, so an app that waits for connections (a remote-access tool) gets none; on *Private* they apply, and Windows' discovery rules open. Networks met later stay *Public* |
| `idleHibernate` | `true` | `false`: the PC never sleeps or hibernates by itself, for a desktop that also serves. The power button still hibernates (a `hibernate` profile) |
| `dns` | `overHttps` `"leave"` | DNS over HTTPS. `overHttps` `"require"` sets `servers` (each `{ "address": "...", "template": "https://..." }`) on every network adapter, each one DNS over HTTPS only, never plain DNS. `localZones` (each `{ "namespace": ".lan", "servers": ["192.168.1.1"] }`) sends the names only your own network knows to its own DNS server. Example below |

`smartAppControl`, `optionalUpdates`, `asrPrevalenceRule`, `netbios` and `firstNetworkCategory` take one of their texts; `dns` is an object; `asrExclusions` is a list; the others are `true` or `false`.

DNS over HTTPS with Cloudflare's malware-blocking resolver and Quad9, and a home network whose router answers for `.lan`:

```json
"dns": {
  "overHttps": "require",
  "servers": [
    { "address": "1.1.1.2", "template": "https://security.cloudflare-dns.com/dns-query" },
    { "address": "9.9.9.9", "template": "https://dns.quad9.net/dns-query" }
  ],
  "localZones": [ { "namespace": ".lan", "servers": ["192.168.1.1"] } ]
}
```

Without `localZones`, names that only your router knows (`printer.lan`) no longer resolve. Add the
IPv6 addresses of the same resolvers if your network has IPv6, or IPv6 DNS from your router bypasses
them (the validator reports adapters with other DNS servers).

#### The build PC

The image runs with Defender's ransomware protection on (`controlledFolderAccess`,
`asrPrevalenceRule`), and both block the tools a build uses. To build on a PC installed from the
kit, `Run-Build.cmd` explains this and asks `Pause the protection for this build? [y/N]`. With
yes, the build pauses both for its duration (about an hour) and turns them back on when it ends,
also after an error. A build that was killed is repaired by the next build, from
`<work>\defender-paused.json`. The PC is not a throwaway machine: during that hour, start nothing
new and stay nearby. Started directly, `Build-Iso.ps1` needs `-PauseDefenderProtection` for the
same. If a policy sets the protection, the build can't pause it, and `Run-Prepare.cmd` says so.

### Reminders (`reminders`)

Reminders are rows in the validator's report. None of them changes the PC.

| Field | Default | The validator's row |
|---|---|---|
| `offlineBackup` | `true` | `Offline backup in the last 35 days`: WARN when you haven't recorded an offline backup for 35 days ([Backups](#backups)). Off: INFO |
| `remoteAccessOnDemand` | `true` | `Remote-access tools` and `No remote shell service (OpenSSH server, WinRM)`: WARN when one starts with Windows, or Remote Desktop is on ([Remote access](#remote-access-and-auto-updaters)). Off: INFO |
| `oneDriveBackup` | `false` | `OneDrive folder backup (<user>)`: WARN until the daily account's Documents, Desktop and Pictures are in OneDrive. Off: INFO |
| `nvidiaApp` | `false` | `NVIDIA App`: PASS when it is installed, INFO when not. Off: no row |
| `expectedApps` | `[]` (none) | One row per app you list, named `<name> installed`: PASS when it is installed, otherwise INFO with the command that installs it |

`expectedApps` is a list of entries like `{ "name": "7-Zip", "wingetId": "7zip.7zip" }`:

- `name` (required): the app's name as Windows lists it under *Installed apps*. 1 to 60 letters,
  digits, spaces or `. _ + & ( ) -`.
- `wingetId` (optional): the app's [winget](../GLOSSARY.md#winget) ID. The row then shows
  `Not installed yet: winget install -e --id <wingetId>`. Find an ID with `winget search <name>`.
- `path` (optional): the full path of the app's program file, such as
  `%ProgramFiles%\7-Zip\7zFM.exe`. With it, the app counts as installed when that file exists;
  without it, when a program of that name is registered for uninstall.

### Layout version (`schemaVersion`)

`config\settings.defaults.json` starts with `"schemaVersion": 1`, the version of this layout. Your
own file doesn't need it. If it has one that is newer than the kit reads, preflight says
`schemaVersion 2 is newer than this kit reads (1): update the kit (Run-Build.cmd, first question) and build again`.

### Another language

Windows' display language is **English only for now**: `uiLanguage` `en-US` (the tested one) or
`en-GB`. The settings check refuses any other, with *the kit builds English Windows only (en-US or
en-GB) for now*. Two things stand in the way:

- The answer file adds the accounts to the groups `Administrators` and `Users` by their English
  names. A German Windows calls them `Administratoren` and `Benutzer`.
- No image in another display language has had a VM test. The validator's pass/fail rows read
  Windows' own numbers, not translated text, but a few information-only rows still show a tool's
  text as it is.

Your keyboard, formats, time zone and country don't depend on the display language. English
Windows with a German keyboard and formats, for example:

```json
"locale": {
  "uiLanguage": "en-US",
  "inputLocale": "0407:00000407",
  "systemLocale": "de-DE",
  "userLocale": "de-DE",
  "timeZone": "W. Europe Standard Time",
  "homeLocation": { "geoId": 94, "isoCode": "DE" }
}
```

A country's GeoId: `(New-Object Globalization.RegionInfo 'DE').GeoId` in PowerShell. For
`en-GB`, download the ISO in *English International* and set `uiLanguage` to `en-GB`; preflight
checks that the two match.

## Base image

| | |
|---|---|
| Source ISO | `Windows11_Client_x64_en-us_26300_9457.iso`: Microsoft's official multi-edition ISO |
| Edition | Windows 11 Pro only |
| Version | **26H2**, build 26300 |
| Cumulative update | The month's cumulative update (it sets the build number after `26300.`). It contains the servicing stack |
| .NET | The month's cumulative update for .NET Framework 3.5 and 4.8.1 |
| Recovery environment (WinRE) | The cumulative update, then the Safe OS Dynamic Update, plus network and storage drivers |
| Windows Setup on the stick | `boot.wim` gets the cumulative update and the PC's storage drivers. The Setup Dynamic Update updates Setup's own files |

The update numbers (KB numbers) change every month. Their one home is
[config/updates.json](../../config/updates.json); the build prints them. Windows Update installs newer updates after
setup. To have them in the image, [rebuild the ISO](../MONTHLY.md#rebuild-the-iso).

**Why 26H2.** Windows 11 Pro 24H2 reaches its end of servicing on 2026-10-13. Releases 24H2, 25H2
and 26H2 share one core, so drivers harvested from a 24H2 or 25H2 install carry over.

**What the BIOS must provide:** Secure Boot, TPM 2.0 and virtualization on. The guide has the
table: [Step 11: BIOS/UEFI settings](../GUIDE.md#step-11-biosuefi-settings).

**Drivers.** The image carries the PC's own drivers, and Windows Update delivers none:
[DRIVERS](DRIVERS.md).

## Install and first boot

| Phase | Result |
|---|---|
| Windows Setup | No edition question and no product key question (the profile's `productKey` decides, [PROFILES](PROFILES.md#fields)). You pick the disk by hand: Setup never erases a disk on its own |
| Setup's first-run pages | None: no Microsoft account, network, OneDrive, Microsoft 365, privacy or Recall pages. Both local accounts come from the answer file |
| First-boot setup | The admin account signs in by itself, once, and first-boot setup (PostInstall) runs. Its log is in `C:\ProgramData\W11Kit\Logs` |
| Restart | After 2 minutes. Then both accounts must choose a new password, and the cached answer files are deleted |

First-boot setup does this, in order:

1. Applies Microsoft's security baselines, the kit's overrides and the kit's own policies as one
   set, then reads the overrides back ([how](SECURITY-BASELINE.md#how-the-baselines-are-applied)).
2. Writes the registry settings on this page for the PC, the admin account and every account
   created later.
3. Blocks web browsers for administrators, blocks outgoing file-sharing connections to the
   Internet, enlarges the PowerShell log and turns on Sysmon
   ([details](SECURITY-BASELINE.md#additions-beyond-the-baseline)).
4. Turns password expiry off. Length, complexity and lockout stay.
5. Sets the power plan to Balanced with the display off after 15 minutes, then applies the
   profile's power settings ([Power](#power-hibernate-and-wake-on-lan)).
6. Turns the Wi-Fi Direct virtual adapters off and queues Microsoft's Secure Boot certificate
   update if the firmware needs it
   ([why](SECURITY-BASELINE.md#secure-boot-2023-certificates)).
7. Turns System Restore on for `C:` and makes a first restore point.
8. Syncs the clock, updates Defender's signatures, runs `wsl --update` and starts a Windows
   Update scan.
9. Puts the *Validate PC* and *Enable BitLocker (local key)* shortcuts on the desktop and locks
   the kit's files on the installed PC (`C:\ProgramData\W11Kit`) so only administrators can
   change them.
10. Removes Setup's temporary account `defaultuser0` and its profile.
11. Runs the validator once and writes `postinstall-status.json`.

Every step handles its own errors: a failure is recorded and the rest still run. Steps that can
hang have a time limit (Sysmon, System Restore and `wsl --update` 10 minutes each, Defender's
signatures 5), and an overrun is a recorded failure.

**If the overrides fail,** first-boot setup does not restart. It shows red text, waits up to 15
minutes for Enter, and puts `W11Kit setup NOT finished - read me.txt` on the desktop. What to do:
[Setup did not finish](../TROUBLESHOOTING.md#setup-did-not-finish).

## Accounts

The image has two local accounts and never needs a Microsoft account for the Windows sign-in.

- **The daily account** (`LocalUser`) is a standard user. You work in it.
- **The admin account** (`LocalAdmin`) is for UAC prompts and installs. At a UAC prompt it is
  listed, and you type its password.

Why two: a program that runs in the daily account can't change Windows without the admin
password. Apps install per user where they can; others ask for the admin password once.

**Microsoft account.** The policy `NoConnectedUser=1` stops a Store or Xbox sign-in from turning
the Windows account into a Microsoft account, which would also send the BitLocker key to
Microsoft. Signing in *inside* apps (Store, Xbox, Edge, OneDrive) still works. Set
`options.allowMicrosoftAccount` to `true` to leave the policy unset.

**Passwords.** The build generates a one-time password for each account
([One-time passwords](BUILD-OPTIONS.md#one-time-passwords)), and each account must choose its own
at its first sign-in. The rules for the new one: at least 11 characters; three of upper-case,
lower-case, digit and symbol; not containing the account name. Passwords don't expire.

**A forgotten password.** The admin account can reset the daily account's password. Nothing on
this image can reset the admin account's, so keep both passwords somewhere off the PC
([Lost or forgot a password?](../AFTER-INSTALL.md#lost-or-forgot-a-password)).

**Built-in accounts.** Windows' built-in Administrator and Guest accounts stay disabled and are
renamed. Each build draws two new names (eight letters, easy to read out, such as `Rinusaka`),
prints them, and records them in the manifest and in `C:\ProgramData\W11Kit\build-options.json`.
They are not secrets. To choose them yourself, set `accounts.builtinAdministratorName` and
`accounts.builtinGuestName`. To see them on the installed PC, look at the validator's row
`Built-in Administrator and Guest renamed and disabled`, or in PowerShell:

```text
Get-LocalUser | Where-Object { $_.SID -match '-50[01]$' }
```

The account lockout, the administrators' browser block and the other sign-in rules are security
settings: [SECURITY-BASELINE](SECURITY-BASELINE.md#disa-stig-additions).

## Privacy

Diagnostic data is set to **Required**, the lowest level Windows 11 Pro honours. It has no effect
on Windows Update.

Off, for the whole PC:

- Recall (the feature is disabled; its files stay, because removing them can break updates) and
  Click to Do;
- the advertising ID and "tailored experiences";
- Widgets, on the taskbar and on the lock screen;
- lock-screen tips and Spotlight pictures;
- suggestions and promotions in Start and Settings, and apps that install themselves;
- activity history and cross-device experiences;
- OneDrive's setup at first sign-in (OneDrive itself can be installed and used).

**Three policies that do nothing on Pro.** `DisableWindowsConsumerFeatures`,
`DisableConsumerAccountStateContent` and `DisableCloudOptimizedContent` are honoured by Windows
Enterprise and Education only. The kit still writes them: they are harmless, and right if the
edition ever changes. On Pro the work is done by per-user values in every new account
(`ContentDeliveryManager`), the clean Start layout and the [removed apps](REMOVED-APPS.md).

### Privacy settings you may notice

| What | Setting | What you notice |
|---|---|---|
| No web (Bing) results in Start and taskbar search | User policy `Explorer\DisableSearchBoxSuggestions=1` | Start search finds apps, settings and files only. File Explorer's search box also stops remembering earlier searches |
| No search highlights, no location in search | `Windows Search\EnableDynamicContentInWSB=0`, `AllowSearchToUseLocation=0` | A plain search box |
| Location services off | `LocationAndSensors\DisableLocation=1` | Maps, Weather and websites can't locate the PC. The time zone doesn't follow you when you travel: set it in Settings |
| Find My Device off | `FindMyDevice\AllowFindMyDevice=0` | A lost PC can't be located from account.microsoft.com. BitLocker protects the data once you have turned it on |
| No clipboard sync to other devices | `System\AllowCrossDeviceClipboard=0` | Clipboard history on this PC (Win+V) still works |
| Start has no *Recommended* section | `Explorer\HideRecommendedSection=1`, `HideRecommendedPersonalizedSites=1` | Recently opened files and new apps aren't listed in Start. File Explorer's *Recent* still has the files |
| Settings has no *Home* page | `SettingsPageVisibility=hide:home` | Settings opens on *System* |
| Paint and Notepad: AI features off | `Policies\Paint\DisableCocreator`, `DisableGenerativeFill`, `DisableImageCreator`; `Policies\WindowsNotepad\DisableAIFeatures` | No Cocreator, Generative fill or Image Creator in Paint; no Rewrite or Summarize in Notepad. Both apps otherwise work |
| Online speech recognition off for new accounts | Per-user value `OnlineSpeechPrivacy\HasAccepted=0` | Win+H dictation asks to turn it on the first time |
| No typing and inking personalisation for new accounts | Per-user values `InputPersonalization\RestrictImplicitTextCollection=1`, `RestrictImplicitInkCollection=1` | Slightly less tailored text suggestions |

Why each one:

- **Search.** What you type into Start isn't sent to Bing. The better-known "don't search the web"
  policies work on Enterprise and Education only; this one works on Pro.
- **Location.** No app and no Windows component gets the PC's position. The image sets the time
  zone itself. Apps that list Wi-Fi networks need location permission and get none; connecting to
  Wi-Fi from the taskbar and Settings works.
- **Find My Device** needs a Microsoft account sign-in to Windows and location. The image uses
  neither.
- **Clipboard sync** would send copied text, passwords included, through Microsoft's cloud.
- **Recommended and Home** mix your files with suggestions, promoted sites and Microsoft account
  cards.
- **AI features in Paint and Notepad** need a Microsoft account and send the picture or text to
  Microsoft.
- **Speech and typing.** The stricter policy `AllowInputPersonalization=0` is not set on purpose:
  it would also disable Win+H dictation.

**Policy or per-user value.** A policy applies to everyone and is re-applied by Windows. A
per-user value is copied into every account created from now on, and that user can change it in
Settings. An account that already exists keeps its own choices.

**Undo.** Change a per-user value in Settings. Change a policy as
[Changing a setting later](SECURITY-BASELINE.md#changing-a-setting-later) describes.

## Microsoft Edge

Edge stays in the image, managed by policy: Windows and many apps need it and its WebView2
runtime. On top of the Edge security baseline and its three overrides
([SECURITY-BASELINE](SECURITY-BASELINE.md#microsoft-edge-security-baseline)), the kit sets these
policies under `HKLM\SOFTWARE\Policies\Microsoft\Edge`. They are always on; `edge://policy` shows
them. Each name is a page of Microsoft's
[Edge policy reference](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies).

| Group | Policies | Effect |
|---|---|---|
| Privacy | `PersonalizationReportingEnabled=0`, `DiagnosticData=1`, `UserFeedbackAllowed=0`, `AutoImportAtFirstRun=4` | Browsing data isn't used to personalise ads, search and news, and Edge sends required diagnostic data only. No feedback prompts; nothing is imported from another browser by itself |
| Nags | `HideFirstRunExperience=1`, `DefaultBrowserSettingsCampaignEnabled=0`, `ShowRecommendationsEnabled=0`, `SpotlightExperiencesAndRecommendationsEnabled=0`, `ShowPDFDefaultRecommendationsEnabled=0`, `EdgeShoppingAssistantEnabled=0`, `ShowMicrosoftRewards=0`, `NewTabPageContentEnabled=0` | No first-run pages and no "make Edge your default" or "use Edge for PDFs" prompts. No feature tips, shopping bars, Rewards or news feed |
| Background | `StartupBoostEnabled=0`, `BackgroundModeEnabled=0` | Edge doesn't start with Windows and doesn't keep running after its last window closes. It opens a moment slower |
| AI | `HubsSidebarEnabled=0`, `CopilotAddressBarSuggestionsEnabled=0`, `EdgeHistoryAISearchEnabled=0`, `NewTabPageBingChatEnabled=0`, `GenAILocalFoundationalModelSettings=1`, `BuiltInAIAPIsEnabled=0` | No sidebar, no Copilot suggestions, no AI search of the history. No multi-gigabyte local AI model download |
| Shortcut | `EdgeUpdate\CreateDesktopShortcutDefault=0` | An Edge update doesn't put a shortcut back on the desktop |

Not touched: WebView2 (it reads its own policy key), Edge's sign-in and sync, extensions,
SmartScreen and the rest of the security baseline.

A policy shows as *managed* in `edge://settings` and can't be changed there. To change one, see
[Changing a setting later](SECURITY-BASELINE.md#changing-a-setting-later).

## Gaming

Off by default. With `options.gamingTweaks` set to `true` in [your settings](#your-settings):

- Game Mode on;
- hardware-accelerated GPU scheduling on;
- variable refresh rate and the optimizations for windowed games on;
- the four Xbox services set to Manual, as Windows ships them, instead of Disabled as Microsoft's
  baseline sets them ([override](SECURITY-BASELINE.md#overrides));
- the Secondary Logon service set to Manual, as Windows ships it, instead of Disabled: some game
  launchers refuse to install without it
  ([STIG additions](SECURITY-BASELINE.md#disa-stig-additions));
- the Xbox app pinned to Start.

With the option off, the kit sets none of these, and the Xbox services follow the baseline
(Disabled). The Xbox app and the Xbox sign-in component (`Microsoft.GamingApp`,
`Microsoft.XboxIdentityProvider`) stay in the image either way; with the option off the build and
the validator just don't require them. The Xbox app, Store games that sign in to Xbox, cloud saves
and Xbox controller accessories then may not work. Turn the option on and rebuild if you play
games on this PC.

For every image:

- The power plan is **Balanced**, not *Ultimate Performance*. AMD recommends it for Ryzen
  processors: the speed is the same, and idle cores can rest (cooler and quieter).
- The kit removes no services and applies no timer, boot or "network throttling" tweaks.
- DirectX, WebView2, the Visual C++ runtimes, .NET and Edge are untouched: games and game
  launchers need them.
- With an NVIDIA graphics card, turn G-SYNC on in the NVIDIA Control Panel if the monitor
  supports it.

## Power: hibernate and Wake-on-LAN

The hardware profile decides ([PROFILES](PROFILES.md#fields), `power`).

**`power.mode` = `default`.** Sleep, hibernate and the buttons stay as Windows sets them.
First-boot setup sets only the Balanced plan and the display timeout. One limit applies to every
profile: Microsoft's baseline turns classic sleep (S1 to S3) off. A PC with Modern Standby still
sleeps; a PC that only has S3 sleep can hibernate or shut down.

**`power.mode` = `hibernate`.** The PC [hibernates](../GLOSSARY.md#hibernate) instead of sleeping:

- **Hibernate after 30 minutes idle.** The power and sleep buttons hibernate too. The display
  turns off after 15 minutes, and waking asks for the password.
- **No sleep.** Microsoft's baseline turns standby (sleep) off, and the kit leaves it off. In
  sleep, the disk key stays in memory; in hibernate it doesn't. The idle timer for sleep is set
  to never.
- **Fast Startup off.** Every shutdown is a real one, and waking from shutdown works more
  reliably.
- **Secure Launch** stays as the baseline sets it. It only runs on hardware that supports it.

**`power.wakeOnLan`.** [Wake-on-LAN](../GLOSSARY.md#wake-on-lan) is set up on the network adapter
the profile names:

- The adapter wakes the PC on a *magic packet* only, not on other network traffic.
- It works from hibernate and, where the driver offers it, from shutdown.
- The BIOS must have Wake on LAN on and ErP (deep power saving) off
  ([guide](../GUIDE.md#step-11-biosuefi-settings)).
- Set `power.wakeOnLan` to `null` in the profile to leave it off.

`C:\W11Kit\New-Profile.cmd -Hibernate -WakeOnLan` writes a profile with both. The reference
profile `legion-t5` uses both ([why](../../profiles/legion-t5/README.md#power-hibernate-and-wake-on-lan)).

This is why BitLocker has no start-up PIN by default: a PC that wakes over the network must start
by itself ([BitLocker](#bitlocker)).

The validator checks the hibernate, Fast Startup, idle and button settings, the adapter's
magic-packet setting and that the adapter may wake the PC. A virtual machine can't test the wake
itself: try it on the real PC ([guide, step 14](../GUIDE.md#step-14-check-the-pc)).

## WSL

The image turns on two Windows features: *Windows Subsystem for Linux* and *Virtual Machine
Platform* ([config/image.json](../../config/image.json)). That is the minimum for WSL 2. The
Hyper-V role, its management tools and Windows Sandbox are not turned on.

- No Linux distribution is installed. Install one with `wsl --install -d Ubuntu`, or bring your
  own back with `wsl --import`.
- First-boot setup runs `wsl --update`.
- Every new account gets a `.wslconfig` ([config/wslconfig](../../config/wslconfig)): mirrored
  networking, DNS tunneling, automatic proxy, the Hyper-V firewall, gradual memory reclaim and a
  disk file that shrinks.

## Start menu and apps

New accounts get a short list of Start pins
([config/LayoutModification.json](../../config/LayoutModification.json)): Edge, File Explorer,
Settings, Microsoft Store, Terminal, Notepad, Calculator, Photos and Snipping Tool, plus the Xbox
app with `options.gamingTweaks`.

Consumer apps are removed from the image: [REMOVED-APPS](REMOVED-APPS.md). Start has no
*Recommended* section, and its search shows no web results ([Privacy](#privacy)).

## Recovery

- **System Restore** is on for `C:` (up to 5 % of the disk), with a restore point from first-boot
  setup.
- **The recovery environment** (WinRE) has this month's cumulative update, the Safe OS updates and
  the PC's network and storage drivers.
- **Updates stay removable.** The build doesn't reset the image's component store, so an update
  can be uninstalled and a later Windows release can be installed over it.

Don't use *Reset this PC*: [why](../AFTER-INSTALL.md#never-use-reset-this-pc).

## BitLocker

BitLocker is **not turned on by the install**. You turn it on when everything works
([guide, step 15](../GUIDE.md#step-15-turn-on-bitlocker)).

- **Nothing encrypts by itself.** Windows' automatic device encryption is prevented
  (`PreventDeviceEncryption=1`), so no recovery key is ever sent to Microsoft.
- **Unlock is TPM-only by default.** The PC starts without a PIN. A PC that hibernates and wakes
  over the network must start by itself, and a PIN would stop it at a prompt before Windows.
- **The recovery key is saved only where you choose.**

What that protects against, and what it doesn't:
[the threat model](../../SECURITY.md#threat-model-what-is-left-open-and-what-closes-it).

The *Enable BitLocker (local key)* shortcut (`C:\ProgramData\W11Kit\Enable-BitLocker.cmd`):

1. Checks the TPM, Secure Boot and protection against DMA attacks
   ([glossary](../GLOSSARY.md#dma-protection-kernel-dma-protection-iommu)).
2. Asks for one or more folders for the recovery key: a USB drive or a network path, never only
   `C:`.
3. Writes the key to each folder and reads it back to check it.
4. Asks you to type `YES`, then turns on encryption (XTS-AES 256, used space only). A policy in the
   image pins the same cipher if you turn BitLocker on through Windows' own settings instead.
5. After the restart Windows tests the TPM, then encrypts in the background.

> [!CAUTION]
> Without the recovery key, a BitLocker disk can't be read after a hardware or BIOS change.
> Nobody can recover it for you. Keep a copy off the PC.

Options, typed after `C:\ProgramData\W11Kit\Enable-BitLocker.cmd` in a Command Prompt:

| Option | Effect |
|---|---|
| `-StartupPin` | Encrypt with TPM **and** a start-up PIN. Every start and every wake then stops at the PIN prompt, so Wake-on-LAN can't bring the PC up unattended |
| `-AddPin` | Add a start-up PIN to a drive that is already encrypted |
| `-ExportOnly` | Write the recovery keys out again, for every protected drive |
| `-BackupPath <folder>[,<folder>]` | Name the key folders instead of picking them |
| `-FullDisk` | Encrypt the whole drive, not only the used space |
| `-Force` | Skip the question a `recommended` profile asks when DMA protection is missing |

A start-up PIN has 6 to 20 characters. The screen that asks for it uses a US keyboard layout.

**DMA protection.** While the PC runs, the disk key is in memory, so the ports must not give
direct memory access. The profile's `security.kernelDmaProtection` decides what a gap means:
`required` makes the script refuse; `recommended` makes it warn and ask. With no readable profile
it is `required`. The script also refuses if something changed the start-up policy so that
TPM-only unlock is no longer allowed ([Other hardening tools](SECURITY-BASELINE.md#other-hardening-tools)).

**Before any BIOS change or update,** in PowerShell (as administrator):

```text
Suspend-BitLocker -MountPoint C: -RebootCount 1
```

Otherwise the PC asks for the recovery key at the next start
([Before any BIOS change](../GUIDE.md#before-any-bios-change)).

## Backups

The kit doesn't back up your data. It reminds you:

- **Offline backup** (`reminders.offlineBackup`, on). After a backup to a drive you unplug
  afterwards, record it in a Command Prompt:

  ```text
  copy /y nul "%PUBLIC%\Documents\W11Kit-offline-backup.txt"
  ```

  The validator WARNs when that file is older than 35 days. On an install younger than 35 days
  the row is INFO. What to copy: [Offline backup](../MONTHLY.md#offline-backup).
- **OneDrive folder backup** (`reminders.oneDriveBackup`, off). If you use OneDrive for the daily
  account's Documents, Desktop and Pictures, turn this on: the validator then WARNs while one of
  the three isn't in OneDrive.
- **Only on this disk.** The validator always lists what lives on this disk alone, such as SSH
  keys, WSL disks and Git folders (row `Only on this disk (<user>)`; with
  `reminders.oneDriveBackup` on it is named `Not covered by OneDrive (<user>)`).
- **The BitLocker recovery key** is in the folders you chose, never only on `C:`.

More: [Backups and accounts](../AFTER-INSTALL.md#backups-and-accounts).

## Remote access and auto-updaters

The image installs none of these. If you add them, the kit recommends:

- **Remote access on demand.** Set a remote-access tool's service to Manual and keep it from
  starting at sign-in; open it when you need it. A service that starts with Windows is a standing
  way in, and it bypasses the baseline's rule that local accounts can't sign in over the network.
  Remote Desktop into this PC is off by policy.
- **GPU vendor apps: no automatic driver installs.** Set the app to notify only, and update
  drivers deliberately ([DRIVERS](DRIVERS.md#overrides)).
- **Vendor download assistants: leave them out.** A device's companion software can install
  further software by itself. Install the vendor's app by hand if you want it.

The validator lists remote-access tools in every report: WARN if one starts with Windows or
Remote Desktop is on (INFO with `reminders.remoteAccessOnDemand` set to `false`). It lists
auto-updaters as INFO.

## Smart App Control

Left to Windows by default (`options.smartAppControl` = `"leave"`). A clean install starts in
*evaluation* mode, and Windows then turns Smart App Control on or off by itself. The kit writes
nothing, and the validator reports the state as INFO (row `Smart App Control`).

Smart App Control blocks programs that are unsigned or rarely seen. That includes programs you
build yourself and many small open-source tools, also when they run as a Windows service. When
Windows switches it on, at a restart, such a program stops starting: *An Application Control
policy has blocked this file*. There is no list of exceptions; it is on or off. If you develop software on this PC, set `options.smartAppControl` to `"off"`:
the image then starts with it off, and the validator's row `Smart App Control off (decision)`
WARNs if it is on. Defender, SmartScreen and the attack surface reduction rules still apply.
