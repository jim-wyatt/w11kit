# Removed apps

> Reference. First time here? Start with the [guide](../GUIDE.md). Words: [glossary](../GLOSSARY.md).

The apps the build takes out of Windows, the ones it keeps on purpose, and what to do when one
comes back. The list the build uses is
[config/removal-manifest.json](../../config/removal-manifest.json); edit that file to change it.

How removal works:

- Windows carries its built-in apps as *provisioned packages*: each new account gets a copy. The
  build removes the listed packages from the image, so no account ever gets them.
- A package is matched by its **exact name**. A name that isn't in your source ISO is skipped and
  logged.
- Each removed app is also marked *deprovisioned*
  (`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\<family>`),
  so Windows doesn't provision it again. The build's image check verifies every mark.
- The build stops if an entry on the removal list also matches the [protected](#protected) list.

## Removed

| App | Package | Note |
|---|---|---|
| Clipchamp | `Clipchamp.Clipchamp` | |
| Dev Home | `Microsoft.Windows.DevHome` | Retired by Microsoft; usually absent already |
| Feedback Hub | `Microsoft.WindowsFeedbackHub` | |
| Get Started / Tips | `Microsoft.Getstarted` | |
| News | `Microsoft.BingNews` | |
| Weather | `Microsoft.BingWeather` | |
| People | `Microsoft.People` | Not shipped since 24H2 |
| Family | `MicrosoftCorporationII.MicrosoftFamily` | |
| Mixed Reality Portal | `Microsoft.MixedReality.Portal` | Microsoft removed Windows Mixed Reality in 24H2 |
| Teams (personal) | `MSTeams`, `MicrosoftTeams` | |
| Outlook (new) | `Microsoft.OutlookForWindows` | Removing the provisioned package is Microsoft's own instruction. See below |
| Quick Assist | `MicrosoftCorporationII.QuickAssist` | A remote-control tool that support scammers talk people into opening (Ctrl+Win+Q) |
| Solitaire Collection | `Microsoft.MicrosoftSolitaireCollection` | Ad-supported |
| Microsoft To Do | `Microsoft.Todos` | Needs a Microsoft account |
| Power Automate | `Microsoft.PowerAutomateDesktop` | Needs a Microsoft account |
| Sticky Notes | `Microsoft.MicrosoftStickyNotes` | |
| Bing Search | `Microsoft.BingSearch` | Supplies Bing results in Start and taskbar search. See below |

That is 17 apps and 18 package names. Dev Home, People and Mixed Reality Portal are normally not
in a 26H2 ISO at all; they stay on the list in case a later ISO brings one back.

Any of these can be installed again from the Microsoft Store for one account. The validator's
*Removed apps not reinstalled* row then WARNs. That is only a reminder.

**Outlook (new).** For Windows 11 releases after 23H2, Microsoft says to remove the provisioned
package; Windows Update then doesn't reinstall it
([Control the installation of new Outlook](https://learn.microsoft.com/microsoft-365-apps/outlook/get-started/control-install)).
Classic Outlook from Microsoft 365 and webmail are not affected.

**Quick Assist.** If you use it to help family, install it from the Store when you need it.

**Bing Search.** The image also turns web results off by policy
([CONFIGURATION](CONFIGURATION.md#privacy)). After an install, check that Start search still
finds apps, settings and files; the VM test checks it too. If it doesn't, take this entry out of
`remove` and rebuild: the policy alone keeps web results off.

## Kept on purpose

- **Get Help, Camera, Clock, Media Player, Sound Recorder and Phone Link** stay (a project
  decision): everyday tools that many people use.
- **Microsoft 365** (`Microsoft.MicrosoftOfficeHub`) stays, because many people use it and the
  Store can install it again for a user anyway. To remove it, take it off `protect` and add it to
  `remove` in the removal list.
- **Copilot** isn't on the list because there is nothing to remove: `Microsoft.Copilot` is not in
  the 26H2 ISO the kit builds from. If a later ISO carries it, add it to `remove`.

### Turned off, not removed

| Item | How | Why it isn't removed |
|---|---|---|
| Suggested apps and promotions | Per-user settings in every new account and a clean Start layout ([CONFIGURATION](CONFIGURATION.md#privacy)) | They are delivered from the cloud; there is no package to remove |
| Widgets | The policies `AllowNewsAndInterests=0` and `DisableWidgetsOnLockScreen=1` | Its package is shared with other parts of Windows |
| AI features in Paint and Notepad, Click to Do | Policies ([CONFIGURATION](CONFIGURATION.md#privacy)) | Paint and Notepad themselves are wanted |
| Recall | The policies `AllowRecallEnablement=0` and `DisableAIDataAnalysis=1`; the Windows feature is disabled and its files are kept | Removing the files can break Windows updates |
| OneDrive's automatic setup | Its first-sign-in entries are removed from new accounts | `OneDriveSetup.exe` is a Windows file that updates expect. You can still install and use OneDrive |

### Protected

The build refuses to remove these, even if they are added to the removal list:

- **Store:** Microsoft Store, Store Purchase App, App Installer (winget).
- **Gaming:** Xbox app, Gaming Services, Xbox Identity Provider, Game Bar, Xbox TCUI, the speech
  overlay, Edge Game Assist.
- **Browser:** Edge and the WebView2 runtime.
- **Security:** Windows Security.
- **Frameworks and codecs:** Visual C++ libraries, UI XAML, .NET Native, Windows App Runtime, the
  media and image codecs, and the shared package behind Widgets.
- **Everyday tools:** Photos, Terminal, Notepad, Calculator, Snipping Tool, Paint, Cross Device.
- **Microsoft 365** (see above).

Nothing else is taken out. The build removes no Windows features, services, scheduled tasks or
system components. Windows Update, Defender, SmartScreen, recovery, DirectX, .NET Framework and
the Visual C++ runtimes are untouched.

## If a removed app comes back

On a real install of an earlier version of this kit, two removed apps came back within hours of
setup:

- **Dev Home.** Removing it from the image hadn't marked it deprovisioned, so Windows provisioned
  it again for every account. The build now writes that mark for every app on the list, also for
  one the source image doesn't carry (by the package family name in `config/removal-manifest.json`).
- **Microsoft 365.** It was marked deprovisioned, and the Store still installed it for the daily
  account. The kit can't prevent a Store install. Microsoft 365 is now kept by default, so the
  validator doesn't report it.

The validator reports a returned app as a WARN (*Removed apps not reinstalled*). To remove one
again, in PowerShell (as administrator). The third line also marks it deprovisioned:

```text
$n = 'Microsoft.Windows.DevHome'
Get-AppxPackage -AllUsers -Name $n | Remove-AppxPackage -AllUsers
Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq $n | Remove-AppxProvisionedPackage -Online
```
