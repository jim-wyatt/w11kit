<#
.SYNOPSIS
    Registry customizations for the W11Kit image (privacy, consumer
    content, gaming, sleep, OOBE/account, BitLocker policy, region, Brave,
    Edge, network and remote-access hardening).

.DESCRIPTION
    Every value is a documented Windows setting or policy. No service
    stripping, timer/BCD tweaks or performance "myths".

    -Mode Offline  Loads SOFTWARE, SYSTEM and the Default user hive from a
                   mounted image (-MountPath) and writes there. New users
                   inherit the per-user values.
    -Mode Online   Writes to the running system: HKLM, the current user
                   (HKCU) and the Default user profile hive. Safe to re-run.
    -ListOnly      Prints the table of values without writing.
    -PolicyTextPath  Writes every *policy* value (the ones under ...\Policies\)
                   to a text file (four lines per entry: Computer|User, key, value,
                   action; the format of config/baseline-overrides.txt) instead of
                   touching the registry. Apply-Policy.ps1 merges it into local
                   Group Policy after the Microsoft security baselines and the
                   overrides, so a policy refresh can never flip these back.

.PARAMETER Settings
    The effective settings of the image (docs/reference/CONFIGURATION.md): a
    path to the file or the parsed object/hashtable. The build passes its
    effective settings (config/settings.defaults.json with the user's file over
    it); PostInstall and the DISM read-back pass the staged copy
    (C:\ProgramData\W11Kit\settings.json). Used here: locale.homeLocation
    (Region values), options.gamingTweaks / bravePolicies / longPaths (true
    sets their values) and options.smartAppControl ("off" sets its value;
    "leave" leaves Smart App Control to Windows), options.asrExclusions (per-rule
    exclusions for the two ASR reputation rules). An option that is off leaves
    its values unset (nothing is deleted).
    This script declares no defaults of its own: the staged file is complete.
    Without -Settings, or for a field that is missing, the option is off and no
    Region value is set.
    options.allowMicrosoftAccount false (or missing): "Users can't add
    Microsoft accounts" (NoConnectedUser=1) is set, so a Store or Xbox sign-in
    can never convert the local Windows account into a Microsoft account (which
    would also send BitLocker recovery keys to Microsoft). Signing in to an app
    (Store, Xbox, Edge) is unaffected. true leaves that policy unset.
#>
[CmdletBinding()]
param(
    [ValidateSet('Offline', 'Online')]
    [string]$Mode = 'Online',
    [string]$MountPath,
    # The hardware profile's power.mode: 'hibernate' adds the hibernate / Fast Startup values
    [ValidateSet('hibernate', 'default')]
    [string]$PowerMode = 'hibernate',
    # The effective settings: a path or the parsed object (see .PARAMETER Settings)
    $Settings,
    [switch]$ListOnly,
    [string]$PolicyTextPath,
    # Offline only: read every value back from the mounted image and compare.
    # Nothing is written. Throws if any value is wrong or missing, except the
    # few marked -DeferToGp (left to Group Policy at first logon).
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

# -DeferToGp: a policy value some hosts refuse to write (even offline, as admin);
# if the write fails it is left to local Group Policy at first logon. Only these
# may be missing from the image: every other value must write and verify.
function S([string]$Hive, [string]$Path, [string]$Name, $Value, [string]$Area, [string]$Why, [string]$Type = 'REG_DWORD', [switch]$DeferToGp) {
    [pscustomobject]@{ Hive = $Hive; Path = $Path; Name = $Name; Type = $Type; Value = $Value; Area = $Area; Why = $Why; Delete = $false; DeferToGp = [bool]$DeferToGp }
}
function D([string]$Hive, [string]$Path, [string]$Name, [string]$Area, [string]$Why) {
    [pscustomobject]@{ Hive = $Hive; Path = $Path; Name = $Name; Type = ''; Value = ''; Area = $Area; Why = $Why; Delete = $true; DeferToGp = $false }
}

# --- The image's settings ---------------------------------------------------------
# Only what this script needs. The defaults are declared once, in the kit's
# config/settings.defaults.json, and the build stages the complete result; here a
# missing field simply means "off" (no value set). Wrong types throw (the build
# validates the whole file before it gets here).
$cfg = $Settings
if ($cfg -is [string]) { $cfg = if ($cfg) { [IO.File]::ReadAllText($cfg) | ConvertFrom-Json } else { $null } }
function Get-Setting([string]$Path) {
    $v = $cfg
    foreach ($part in $Path -split '\.') { if ($null -eq $v) { break }; $v = $v.$part }
    $v
}
$opt = @{}
foreach ($o in 'gamingTweaks', 'bravePolicies', 'longPaths', 'allowMicrosoftAccount', 'windowsUpdateDrivers') {
    $v = Get-Setting "options.$o"
    if ($null -eq $v) { $v = $false }
    if ($v -isnot [bool]) { throw "Settings: options.$o must be true or false, not '$v'" }
    $opt[$o] = $v
}
$sac = Get-Setting 'options.smartAppControl'
if ($null -eq $sac) { $sac = 'leave' }
if ($sac -cnotin 'leave', 'off') { throw "Settings: options.smartAppControl must be `"leave`" or `"off`", not '$sac'" }
$allowMsa = $opt.allowMicrosoftAccount
$optUpd = Get-Setting 'options.optionalUpdates'
if ($null -eq $optUpd) { $optUpd = 'off' }
if ($optUpd -cnotin 'off', 'auto', 'userChoice') { throw "Settings: options.optionalUpdates must be `"off`", `"auto`" or `"userChoice`", not '$optUpd'" }
$doh = Get-Setting 'options.dns.overHttps'
if ($null -eq $doh) { $doh = 'leave' }
if ($doh -cnotin 'leave', 'require') { throw "Settings: options.dns.overHttps must be `"leave`" or `"require`", not '$doh'" }
if ($doh -eq 'require') {
    $dohServers = @(Get-Setting 'options.dns.servers')
    if (-not $dohServers.Count) { throw 'Settings: options.dns.overHttps "require" needs options.dns.servers ([{ "address": "...", "template": "https://..." }])' }
    foreach ($ds in $dohServers) {
        $ip = $null
        if (-not [Net.IPAddress]::TryParse("$($ds.address)", [ref]$ip) -or "$($ds.template)" -notmatch '^https://[^\s]+$') { throw "Settings: options.dns.servers needs an IP address and an https:// template in each entry (found '$($ds.address)' / '$($ds.template)')" }
    }
    foreach ($z in @(Get-Setting 'options.dns.localZones')) {
        if ("$($z.namespace)" -notmatch '^\.[A-Za-z0-9.-]+$' -or -not @($z.servers).Count) { throw "Settings: options.dns.localZones needs a namespace starting with a dot (.lan) and its servers in each entry (found '$($z.namespace)')" }
    }
}
$asrExcl = @(Get-Setting 'options.asrExclusions' | Where-Object { $null -ne $_ })
foreach ($x in $asrExcl) {
    if ($x -isnot [string] -or $x -notmatch '^[A-Za-z]:\\' -or $x -match '["<>|\x00-\x1F]' -or $x -match '^[A-Za-z]:\\[\\*?.]*$') { throw "Settings: options.asrExclusions needs full paths of folders or programs (found '$x')" }
}
$geoId = Get-Setting 'locale.homeLocation.geoId'
$geoIso = "$(Get-Setting 'locale.homeLocation.isoCode')"
$hasGeo = $null -ne $geoId -or $geoIso
if ($hasGeo -and ("$geoId" -notmatch '^\d+$' -or $geoIso -notmatch '^[A-Za-z]{2}$')) { throw "Settings: locale.homeLocation needs a numeric geoId and a two-letter isoCode (found '$geoId' / '$geoIso')" }
$geoName = if ($hasGeo) { try { (New-Object Globalization.RegionInfo $geoIso).EnglishName } catch { $geoIso } }

$cdm = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'

$values = @(
    # --- Recall / AI ---------------------------------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0 'Recall' 'Recall cannot be enabled (policy)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'Recall' 'Turn off saving snapshots (device policy)'
    S DEFAULTUSER 'Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1 'Recall' 'Turn off saving snapshots (user policy)'
    # Click to Do (screen analysis, Copilot+ PCs), machine and user as for Recall (WindowsCopilot.admx)
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1 'AI' 'Click to Do off (device policy)'
    S DEFAULTUSER 'Software\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1 'AI' 'Click to Do off (user policy)'
    # Paint and Notepad: the AI features need a Microsoft account sign-in and send the
    # picture/text to Microsoft. The apps themselves stay (WindowsCopilot.admx; Notepad:
    # Microsoft Learn "Manage Notepad", its ADMX is a separate download).
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 1 'AI' 'Paint: Cocreator off'
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 1 'AI' 'Paint: generative fill off'
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 1 'AI' 'Paint: Image Creator off'
    S SOFTWARE 'SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1 'AI' 'Notepad: AI features (Rewrite, Summarize, Write) off'

    # --- Advertising ID / tailored experiences -------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1 'Privacy' 'Advertising ID off'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0 'Privacy' 'Advertising ID off (user toggle)'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0 'Privacy' 'Tailored experiences off'
    S DEFAULTUSER 'Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1 'Privacy' 'Tailored experiences off (policy)'
    # Per-user privacy toggles, written to the Default profile so accounts created LATER
    # start with them off too (Microsoft: "Manage connections from Windows 11 operating
    # system components to Microsoft services", 18.6 Speech and 18.21 Inking & Typing).
    # Not the AllowInputPersonalization=0 policy: that one also kills Win+H dictation.
    S DEFAULTUSER 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0 'Privacy' 'Online speech recognition off (voice not sent to Microsoft; the user can turn it on)'
    S DEFAULTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1 'Privacy' 'No typing personalisation (custom dictionary from what you type)'
    S DEFAULTUSER 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1 'Privacy' 'No inking personalisation'
    # Location services off for the whole PC (Sensors.admx). The kit sets the time zone
    # itself, so automatic time zone isn't needed. Not the home location (Region, below):
    # that is the Store's market and must stay.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1 'Privacy' 'Location services off (apps and Windows get no location)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0 'Privacy' 'Find My Device off (needs a Microsoft account and location; neither is used)'

    # --- Telemetry: Required (1) is the lowest level honoured on Pro ---------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1 'Telemetry' 'Required diagnostic data only; Windows Update unaffected'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 'Telemetry' 'No feedback prompts'

    # --- Widgets --------------------------------------------------------------
    # Policies\Microsoft\Dsh is blocked for reg.exe/PowerShell on some hosts (even offline)
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'Widgets' 'Widgets board and taskbar button off' -DeferToGp
    # 1 = no widgets on the lock screen (Policy CSP NewsAndInterests/DisableWidgetsOnLockScreen).
    # NewsAndInterests.admx on 26H2 writes 0 for "Enabled", against its own help text and
    # the CSP: the kit follows the CSP and the value's name.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Dsh' 'DisableWidgetsOnLockScreen' 1 'Widgets' 'No widgets (weather, news) on the lock screen' -DeferToGp

    # --- Consumer experience / suggested apps ---------------------------------
    # These three CloudContent policies are Enterprise/Education only (Microsoft's Policy
    # CSP, Experience: AllowWindowsConsumerFeatures, DisableConsumerAccountStateContent,
    # DisableCloudOptimizedContent all list Pro as not supported). On Pro they do NOTHING;
    # they are kept because they are harmless and correct should the edition ever change.
    # What does the work on Pro: the per-user ContentDeliveryManager values below, the
    # clean Start layout and the removed apps.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1 'Consumer' 'Consumer features policy (no effect on Pro: Ent/Edu only; the per-user values below do the work)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 1 'Consumer' 'No account-state promotions (no effect on Pro: Ent/Edu only)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1 'Consumer' 'No cloud-optimized content (no effect on Pro: Ent/Edu only)'
    S DEFAULTUSER $cdm 'ContentDeliveryAllowed' 0 'Consumer' 'Content delivery off'
    S DEFAULTUSER $cdm 'FeatureManagementEnabled' 0 'Consumer' 'Promoted feature management off'
    S DEFAULTUSER $cdm 'OemPreInstalledAppsEnabled' 0 'Consumer' 'No OEM promoted apps'
    S DEFAULTUSER $cdm 'PreInstalledAppsEnabled' 0 'Consumer' 'No promoted pre-installed apps'
    S DEFAULTUSER $cdm 'PreInstalledAppsEverEnabled' 0 'Consumer' 'No promoted pre-installed apps'
    S DEFAULTUSER $cdm 'SilentInstalledAppsEnabled' 0 'Consumer' 'No silently installed suggested apps'
    S DEFAULTUSER $cdm 'SoftLandingEnabled' 0 'Consumer' 'No tips and suggestions'
    S DEFAULTUSER $cdm 'SubscribedContentEnabled' 0 'Consumer' 'No subscribed content'
    S DEFAULTUSER $cdm 'SystemPaneSuggestionsEnabled' 0 'Start' 'No Start suggestions'
    S DEFAULTUSER $cdm 'SubscribedContent-338388Enabled' 0 'Start' 'No Start suggestions'
    S DEFAULTUSER $cdm 'SubscribedContent-338389Enabled' 0 'Consumer' 'No tips/tricks'
    S DEFAULTUSER $cdm 'SubscribedContent-310093Enabled' 0 'Consumer' 'No Windows welcome experience'
    S DEFAULTUSER $cdm 'SubscribedContent-338393Enabled' 0 'Settings' 'No suggested content in Settings'
    S DEFAULTUSER $cdm 'SubscribedContent-353694Enabled' 0 'Settings' 'No suggested content in Settings'
    S DEFAULTUSER $cdm 'SubscribedContent-353696Enabled' 0 'Settings' 'No suggested content in Settings'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 'Consumer' 'No "finish setting up your device" nag'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications' 'EnableAccountNotifications' 0 'Consumer' 'No account notifications in Settings'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0 'Consumer' 'No sync-provider ads in File Explorer'

    # --- Lock screen ads -----------------------------------------------------
    S DEFAULTUSER $cdm 'RotatingLockScreenEnabled' 0 'LockScreen' 'Spotlight rotation off (lock screen uses a picture)'
    S DEFAULTUSER $cdm 'RotatingLockScreenOverlayEnabled' 0 'LockScreen' 'No lock screen fun facts/tips'
    S DEFAULTUSER $cdm 'SubscribedContent-338387Enabled' 0 'LockScreen' 'No lock screen fun facts/tips'

    # --- Start menu recommendations -------------------------------------------
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0 'Start' 'No tips/app promotions in Recommended'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_AccountNotifications' 0 'Start' 'No account notifications in Start'
    # StartMenu.admx (both policies have no explicit data: enabled = 1)
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedPersonalizedSites' 1 'Start' 'No website recommendations in Start'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Explorer' 'HideRecommendedSection' 1 'Start' 'No Recommended section in Start (recent files and apps are not listed there)'
    # Settings opens on System instead of the Home page (account and Microsoft 365 cards)
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'hide:home' 'Settings' 'Settings: Home page hidden' 'REG_SZ'

    # --- Search: no web results, no highlights, no location ---------------------
    # The documented "no web results" policies (ConnectedSearchUseWeb / DoNotUseWebResults)
    # are Enterprise/Education only. This user policy (WindowsExplorer.admx) is what turns
    # Bing results off in Start/taskbar search on Pro; as its name says it also stops
    # File Explorer's search box from remembering earlier searches.
    S DEFAULTUSER 'Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 'Search' 'No web (Bing) results in Start search; no search-box history in File Explorer'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0 'Search' 'No search highlights (the daily picture and trivia in the search box)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowSearchToUseLocation' 0 'Search' 'Search does not use the location'

    # --- Activity history / cross-device ------------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0 'Activity' 'Activity history off'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0 'Activity' 'Do not publish activities'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0 'Activity' 'Do not upload activities'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'EnableCdp' 0 'CrossDevice' 'Cross-device experiences ("continue on this PC") off'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0 'CrossDevice' 'Clipboard is not synchronized to other devices (local clipboard history, Win+V, still works)'

    # --- OOBE / account -----------------------------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\OOBE' 'DisablePrivacyExperience' 1 'OOBE' 'No privacy-settings OOBE for additional users'
    D DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup' 'OneDrive' 'Do not auto-run OneDrive setup at first logon'
    D DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive' 'OneDrive' 'Do not auto-start OneDrive'

    # --- BitLocker: no automatic device encryption / key escrow ---------------
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' 1 'BitLocker' 'No automatic Device Encryption; enable manually with Enable-BitLockerLocal.ps1'
    # Startup authentication pinned to "TPM-only allowed" (decision: no startup
    # PIN). The Microsoft baseline leaves these unset; another hardening tool
    # on the live PC required TPM+PIN, so Enable-BitLockerLocal failed.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'UseAdvancedStartup' 1 'BitLocker' 'Configure startup authentication (values below)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'EnableBDEWithNoTPM' 0 'BitLocker' 'TPM required (no USB-key-only unlock)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'UseTPM' 2 'BitLocker' 'TPM-only unlock allowed'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'UseTPMPIN' 2 'BitLocker' 'Startup PIN allowed, not required'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'UseTPMKey' 2 'BitLocker' 'Startup key allowed, not required'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'UseTPMKeyPIN' 2 'BitLocker' 'Startup key + PIN allowed, not required'
    # Cipher, whichever way BitLocker is turned on (Windows' own settings use XTS-AES 128
    # without it). VolumeEncryption.admx, EncryptionMethodWithXts_Name: 4 = AES-CBC 256,
    # 7 = XTS-AES 256; removable drives keep AES-CBC so older Windows can read them.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'EncryptionMethodWithXtsOs' 7 'BitLocker' 'XTS-AES 256 for the Windows drive'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'EncryptionMethodWithXtsFdv' 7 'BitLocker' 'XTS-AES 256 for other fixed drives'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'EncryptionMethodWithXtsRdv' 4 'BitLocker' 'AES-CBC 256 for removable drives (readable on older Windows)'

    # --- Feature version pin ------------------------------------------------------
    # Windows Update stays on 26H2 until a rebuild moves it (bump with the kit's
    # source ISO; docs/dev/MAINTAINING.md, 'New Windows feature release'). Quality updates still flow.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'TargetReleaseVersion' 1 'Updates' 'Pin the Windows feature version'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ProductVersion' 'Windows 11' 'Updates' 'Pinned product' 'REG_SZ'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'TargetReleaseVersionInfo' '26H2' 'Updates' 'Pinned feature version (= source ISO)' 'REG_SZ'

    # --- Region ---------------------------------------------------------------
    # Home location (settings locale.homeLocation). Left at "World" (GeoId 39070), the
    # Store queries its catalog with market=001 and every install fails with 404.
    if ($hasGeo) {
        S DEFAULTUSER 'Control Panel\International\Geo' 'Nation' "$geoId" 'Region' "Home location $geoName (Store catalog market)" 'REG_SZ'
        S DEFAULTUSER 'Control Panel\International\Geo' 'Name' $geoIso.ToUpperInvariant() 'Region' "Home location $geoName (Store catalog market)" 'REG_SZ'
    }

    # --- Gaming (settings options.gamingTweaks) ---------------------------------
    if ($opt.gamingTweaks) {
        S DEFAULTUSER 'Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 'Gaming' 'Game Mode on'
        S DEFAULTUSER 'Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 'Gaming' 'Game Mode on'
        S SYSTEM 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'Gaming' 'Hardware-accelerated GPU scheduling on (takes effect after reboot)'
        S DEFAULTUSER 'Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;' 'Gaming' 'Variable refresh rate + windowed-game optimizations on (Settings > Display > Graphics)' 'REG_SZ'
    }

    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51' 'ACSettingIndex' 1 'Sleep' 'Require a password on wake (plugged in)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51' 'DCSettingIndex' 1 'Sleep' 'Require a password on wake (battery)'

    # --- Windows Update -------------------------------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' $(if ($opt.windowsUpdateDrivers) { 0 } else { 1 }) 'Updates' 'No drivers from Windows Update: the curated drivers stay put; update drivers deliberately'
    # Optional updates (settings options.optionalUpdates; WindowsUpdate.admx, AllowOptionalContent:
    # 1 = automatically, including gradual feature rollouts; 3 = the user chooses). The feature
    # version pin stays either way.
    if ($optUpd -ne 'off') {
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'SetAllowOptionalContent' 1 'Updates' 'Optional updates: policy set (settings options.optionalUpdates)'
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'AllowOptionalContent' $(if ($optUpd -eq 'auto') { 1 } else { 3 }) 'Updates' $(if ($optUpd -eq 'auto') { 'Optional updates and feature rollouts arrive automatically' } else { 'The user picks optional updates (Settings > Windows Update > Advanced options)' })
    }
    # DNS over HTTPS (settings options.dns.overHttps "require"; DnsClient.admx DNS_Doh: 2 = allowed).
    # Not 3 (required): that would also force the local zones, whose servers don't speak DoH.
    # PostInstall registers each server DoH-only (no fallback) and sets them on the adapters.
    if ($doh -eq 'require') {
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'DoHPolicy' 2 'Network' 'DNS over HTTPS allowed (the configured servers are DoH-only; see PostInstall)'
    }
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'AllowMUUpdateService' 1 'Updates' 'Also update other Microsoft products (.NET runtimes, etc.)'
    # The policy above covers monthly updates only: for a NEW device Windows still
    # fetches its driver and the vendor's software from Windows Update when it is
    # connected. Close that path too.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'SearchOrderConfig' 0 'Updates' 'New devices: do not search Windows Update for drivers'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Device Metadata' 'PreventDeviceMetadataFromNetwork' 1 'Updates' 'New devices: no manufacturer apps/metadata from the Internet'
    # Belt and braces for plugged-in devices: the older 'Turn off Windows Update device driver
    # searching' policy and its prompt, and no "request additional software" / "generic driver"
    # reports to Microsoft (the reply can offer vendor companion apps).
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'DontSearchWindowsUpdate' 1 'Updates' 'New devices: never search Windows Update for drivers (older policy, same intent)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'DontPromptForWindowsUpdate' 1 'Updates' 'New devices: no prompt offering a Windows Update driver search'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings' 'DisableSendRequestAdditionalSoftwareToWER' 1 'Updates' 'New devices: no "additional software" request to Microsoft (no companion-app offers)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings' 'DisableSendGenericDriverNotFoundToWER' 1 'Updates' 'New devices: no "generic driver installed" report to Microsoft'

    # --- Virtualization-based security (proven compatible on this hardware) --
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 1 'Security' 'VBS on'
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\DeviceGuard' 'RequirePlatformSecurityFeatures' 1 'Security' 'VBS requires Secure Boot'
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 1 'Security' 'Memory integrity (HVCI) on'
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\KernelShadowStacks' 'Enabled' 1 'Security' 'Kernel-mode hardware-enforced stack protection on'

    # --- Defender -------------------------------------------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender' 'PUAProtection' 1 'Security' 'Block potentially unwanted apps'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR' 'ExploitGuard_ASR_Rules' 1 'Security' 'Attack surface reduction rules configured by policy'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules' '56a863a9-875e-4185-98a7-b882c64b5ce5' '1' 'Security' 'ASR: block abuse of exploited vulnerable signed drivers' 'REG_SZ'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules' '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' '1' 'Security' 'ASR: block credential stealing from LSASS' 'REG_SZ'
    # Paths the two reputation rules let run (settings options.asrExclusions): the prevalence
    # rule (a preference, PostInstall) and the baseline's ransomware rule (policy). Per-rule
    # exclusions (WindowsDefender.admx, ExploitGuard_ASR_ASROnlyPerRuleExclusions): the value
    # name is the rule's GUID, lowercase and without braces (Defender ignores the braced form of
    # the ADMX example), the data the paths joined by '>'. Every other ASR rule still covers them.
    if ($asrExcl.Count) {
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR' 'ExploitGuard_ASR_ASROnlyPerRuleExclusions' 1 'Security' 'ASR per-rule exclusions configured by policy (settings options.asrExclusions)'
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\ASROnlyPerRuleExclusions' '01443614-cd74-433a-b99e-2ecdc07bfc25' ($asrExcl -join '>') 'Security' 'ASR prevalence rule: these paths may run (settings options.asrExclusions)' 'REG_SZ'
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\ASROnlyPerRuleExclusions' 'c1db55ab-c21a-4637-bb3f-a12568109d35' ($asrExcl -join '>') 'Security' 'ASR ransomware rule: these paths may run (settings options.asrExclusions)' 'REG_SZ'
    }

    # --- Brave (not covered by the Edge baseline; settings options.bravePolicies) ---
    # Chromium security policies Brave honours. Brave's own features (Shields,
    # Rewards, Wallet, Leo...) are left to the user.
    if ($opt.bravePolicies) {
        S SOFTWARE 'SOFTWARE\Policies\BraveSoftware\Brave' 'SafeBrowsingProtectionLevel' 1 'Brave' 'Safe Browsing on (standard protection; Brave proxies the lookups)'
        S SOFTWARE 'SOFTWARE\Policies\BraveSoftware\Brave' 'DownloadRestrictions' 1 'Brave' 'Block downloads Safe Browsing flags as dangerous'
        S SOFTWARE 'SOFTWARE\Policies\BraveSoftware\Brave' 'BasicAuthOverHttpEnabled' 0 'Brave' 'No Basic authentication over plain HTTP (as the Edge baseline)'
        S SOFTWARE 'SOFTWARE\Policies\BraveSoftware\Brave' 'SitePerProcess' 1 'Brave' 'Site isolation for every site (as the Edge baseline)'
    }

    # --- Microsoft Edge: privacy, nags, background, AI -----------------------------
    # On top of the Edge security baseline (none of these is a baseline value). Names and
    # data from Microsoft's Edge policy reference (learn.microsoft.com/deployedge/
    # microsoft-edge-policies/<name>). Mandatory policies under ...\Policies\Microsoft\Edge
    # apply to the Edge browser only: WebView2 (msedgewebview2.exe, used by apps and
    # installers) reads ...\Edge\WebView2 and is not affected.
    foreach ($e in @(
            @('PersonalizationReportingEnabled', 0, 'browsing data is not used to personalise ads, search and news'),
            @('DiagnosticData', 1, 'required diagnostic data only (0 = off is "not recommended" by Microsoft; 2 = optional)'),
            @('AutoImportAtFirstRun', 4, 'no automatic import from another browser at first run'),
            @('UserFeedbackAllowed', 0, 'no feedback and survey prompts'),
            @('HideFirstRunExperience', 1, 'no first-run pages'),
            @('DefaultBrowserSettingsCampaignEnabled', 0, 'no "make Edge and Bing your default" campaigns'),
            @('ShowRecommendationsEnabled', 0, 'no feature recommendations and "tips" notifications'),
            @('SpotlightExperiencesAndRecommendationsEnabled', 0, 'no Spotlight suggestions for Microsoft services'),
            @('ShowPDFDefaultRecommendationsEnabled', 0, 'no "make Edge your PDF reader" prompts'),
            @('EdgeShoppingAssistantEnabled', 0, 'no shopping, coupon and price-comparison features'),
            @('ShowMicrosoftRewards', 0, 'no Microsoft Rewards'),
            @('NewTabPageContentEnabled', 0, 'no Microsoft news feed on the new tab page'),
            @('StartupBoostEnabled', 0, 'Edge does not start with Windows (startup boost off)'),
            @('BackgroundModeEnabled', 0, 'Edge does not keep running after its last window closes'),
            @('HubsSidebarEnabled', 0, 'no sidebar'),
            @('CopilotAddressBarSuggestionsEnabled', 0, 'no Copilot suggestions in the address bar'),
            @('EdgeHistoryAISearchEnabled', 0, 'no AI search over the browsing history'),
            @('NewTabPageBingChatEnabled', 0, 'no Copilot/Bing chat entry points on the new tab page'),
            @('GenAILocalFoundationalModelSettings', 1, 'the local AI model is not downloaded (1 = disallowed; several GB)'),
            @('BuiltInAIAPIsEnabled', 0, 'web pages cannot use the built-in AI APIs'))) {
        S SOFTWARE 'SOFTWARE\Policies\Microsoft\Edge' $e[0] $e[1] 'Edge' "Edge: $($e[2])"
    }
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' 0 'Edge' 'Edge updates and reinstalls do not put a shortcut on the desktop'

    # --- Network and remote-access hardening (docs/reference/SECURITY-BASELINE.md) -----------
    # Each one closes something this PC does not use; the doc says what it costs and how
    # to undo it. Key, value and data read from the named ADMX of Windows 11 26H2.
    # Print spooler (Printing2.admx, Printing.admx): no remote clients (2 = the policy's
    # "Disabled"; local and network printing still work, this PC just can't act as a
    # print server), and the Point and Print prompts pinned to "warn and elevate"
    # (KB5005010; the baseline already restricts driver installation to administrators).
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'RegisterSpoolerRemoteRpcEndPoint' 2 'Network' 'Print spooler accepts no remote client connections'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' 'NoWarningNoElevationOnInstall' 0 'Network' 'Point and Print: warning and elevation prompt when installing a driver'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint' 'UpdatePromptSettings' 0 'Network' 'Point and Print: warning and elevation prompt when updating a driver'
    # Remote Desktop off by policy (TerminalServer.admx: 1 = the policy's "Disabled"), so the
    # Settings switch can't turn it on; no unsolicited Remote Assistance (RemoteAssistance.admx;
    # the baseline already turns solicited Remote Assistance off)
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fDenyTSConnections' 1 'Network' 'Remote Desktop connections refused (policy)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' 'fAllowUnsolicited' 0 'Network' 'No unsolicited (offered) Remote Assistance'
    # WinRM / PowerShell remoting INTO this PC (WindowsRemoteManagement.admx,
    # WindowsRemoteShell.admx). Nothing in the kit uses it; local CIM/WMI cmdlets and
    # PowerShell Direct into Hyper-V VMs don't go through a WinRM listener.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WinRM\Service' 'AllowAutoConfig' 0 'Network' 'WinRM service answers no remote requests (no listener configuration)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS' 'AllowRemoteShellAccess' 0 'Network' 'No remote shell (WinRS)'
    # mDNS off (DnsClient.admx), next to the baseline's LLMNR and NetBIOS: no name
    # answers from whoever shouts first on the local network. Costs automatic printer
    # discovery and .local names (add printers by IP address).
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMDNS' 0 'Network' 'Multicast DNS (mDNS) name resolution off'
    # WPAD (automatic proxy discovery) off for everything that uses WinHTTP (Microsoft
    # Learn: "Disable HTTP proxy auth features", Windows 10 1809+). Not a policy path:
    # written directly. A network that hands out its proxy by WPAD needs it set by hand.
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' 'DisableWpad' 1 'Network' 'No automatic proxy discovery (WPAD) through WinHTTP'
    # Outbound SMB (TCP 445) to public addresses blocked: a link to \\<internet host>\share would offer the
    # user's NTLM credentials to that host. A local-Group-Policy firewall rule as its registry value (the
    # format of every rule under ...\FirewallPolicy\FirewallRules; v2.26 = the baseline's PolicyVersion 538):
    # the Public profile ignores rules of the ordinary local store (baseline), and New-NetFirewallRule
    # -PolicyStore localhost needs a network path to this PC. Private ranges (10/8, 172.16/12, 192.168/16,
    # 169.254/16, 100.64/10, 127/8, IPv6 fc00::/7 and fe80::/10) are not listed: a NAS on the LAN works as before.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules' 'W11Kit-Block-SMB-Out-Internet' 'v2.26|Action=Block|Active=TRUE|Dir=Out|Protocol=6|RPort=445|RA4=1.0.0.0-9.255.255.255|RA4=11.0.0.0-100.63.255.255|RA4=100.128.0.0-126.255.255.255|RA4=128.0.0.0-169.253.255.255|RA4=169.255.0.0-172.15.255.255|RA4=172.32.0.0-192.167.255.255|RA4=192.169.0.0-223.255.255.255|RA6=2000::/3|Name=W11Kit: block SMB (TCP 445) to the Internet|Desc=File sharing (SMB) only to private network addresses, never to Internet addresses. docs/reference/SECURITY-BASELINE.md|' 'Network' 'Outbound SMB (TCP 445) to Internet addresses blocked' 'REG_SZ'
    # winget / App Installer (DesktopAppInstaller.admx): winget itself, the Store source and
    # the community source keep working; only the ways around its checks are closed.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppInstaller' 'EnableMSAppInstallerProtocol' 0 'Security' 'winget: no installs started by a web page (ms-appinstaller: links)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppInstaller' 'EnableHashOverride' 0 'Security' 'winget: an installer whose SHA-256 does not match is refused (no --ignore-security-hash)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppInstaller' 'EnableExperimentalFeatures' 0 'Security' 'winget: no experimental features'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppInstaller' 'EnableLocalArchiveMalwareScanOverride' 0 'Security' 'winget: the malware scan of a local archive cannot be skipped'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppInstaller' 'EnableBypassCertificatePinningForMicrosoftStore' 0 'Security' 'winget: the Microsoft Store certificate is always checked'
    # No security questions for local accounts (CredUI.admx): their answers are guessable
    # and stored on the PC. A forgotten password is reset from the admin account.
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'NoLocalPasswordResetQuestions' 1 'Security' 'No security questions for local accounts'
    # Stricter Authenticode check (CVE-2013-3900): a signed file with data appended to its
    # signature counts as unsigned. Opt-in on every Windows; DWORD 1 in both views (MSRC
    # CVE-2013-3900 v2.4, and SecGuide.admx). Not a policy path: written directly. A few
    # old installers may then show as unsigned (Unblock, or get a current build).
    S SOFTWARE 'SOFTWARE\Microsoft\Cryptography\Wintrust\Config' 'EnableCertPaddingCheck' 1 'Security' 'Strict Authenticode signature check (CVE-2013-3900), 64-bit'
    S SOFTWARE 'SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config' 'EnableCertPaddingCheck' 1 'Security' 'Strict Authenticode signature check (CVE-2013-3900), 32-bit'

    # --- Hardening carried over from the old baseline ------------------------
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging' 1 'Security' 'PowerShell script block logging (audit trail)'
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255 'Security' 'AutoRun off for all drive types'
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoAutorun' 1 'Security' 'AutoRun commands ignored'
    S DEFAULTUSER 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0 'Security' 'Show file extensions (spot invoice.pdf.exe)'

    # --- DISA Windows 11 STIG V2R11 (docs/reference/SECURITY-BASELINE.md, "DISA STIG additions") ---
    # Values the Microsoft baseline leaves at a Windows default (or unset) and the STIG
    # wants written down. Only the Security log size changes a baseline value (an override).
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\FVE' 'MinimumPIN' 6 'STIG' 'WN11-00-000032: a BitLocker startup PIN, if one is ever added, has 6+ digits (TPM-only stays the default)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\Group Policy\{35378EAC-683F-11D2-A89A-00C04FBBCFA2}' 'NoGPOListChanges' 0 'STIG' 'WN11-CC-000090: re-apply registry policy at every refresh, even if unchanged'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows NT\Printers' 'DisableHTTPPrinting' 1 'STIG' 'WN11-CC-000110: no printing over HTTP'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\System' 'DontDisplayNetworkSelectionUI' 1 'STIG' 'WN11-CC-000120: no network picker on the sign-in screen'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1 'STIG' 'WN11-CC-000175: Inventory Collector off'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'STIG' 'WN11-CC-000206: Delivery Optimization HTTP only (no downloads from or uploads to other PCs)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\PassportForWork' 'RequireSecurityDevice' 1 'STIG' 'WN11-CC-000255: Windows Hello keys only in the TPM (Enabled is not set: no Hello for Business provisioning)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\PassportForWork\PINComplexity' 'MinimumPINLength' 6 'STIG' 'WN11-CC-000260: Windows Hello PIN 6+ characters'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsActivateWithVoice' 2 'STIG' 'WN11-CC-000366: apps cannot be activated by voice'
    S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters' 'SupportedEncryptionTypes' 2147483640 'STIG' 'WN11-SO-000190: Kerberos AES128/AES256 + future types only (no DES/RC4)'
    S SOFTWARE 'SOFTWARE\Policies\Microsoft\Windows\EventLog\Security' 'MaxSize' 1048576 'STIG' 'WN11-AU-000505: Security event log 1 GB (KB; baseline override: 196608 = 192 MB)'
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0 'STIG' 'WN11-CC-000038: WDigest keeps no plaintext credentials (already the default behaviour)'
    S SYSTEM 'SYSTEM\CurrentControlSet\Control\Lsa\pku2u' 'AllowOnlineID' 0 'STIG' 'WN11-SO-000185: no PKU2U authentication with online identities'
    # "Run as different user" off the Explorer menus (it also fails with the Secondary
    # Logon service disabled: baseline-overrides.inf). Not a policy path: written directly.
    foreach ($cls in 'batfile', 'cmdfile', 'exefile', 'mscfile') {
        S SOFTWARE "SOFTWARE\Classes\$cls\shell\runasuser" 'SuppressionPolicy' 4096 'STIG' "WN11-CC-000039: no ""Run as different user"" for $cls"
    }

    # --- Win32 long paths (settings options.longPaths) -----------------------
    if ($opt.longPaths) {
        S SYSTEM 'SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 'Dev' 'Win32 long paths (node_modules, deep repos)'
    }
    # Smart App Control off (settings options.smartAppControl "off": for a PC that runs
    # its own unsigned builds). With "leave" nothing is set: a clean install starts in
    # evaluation mode (2) and Windows switches it on or off by itself.
    if ($sac -eq 'off') {
        S SYSTEM 'SYSTEM\CurrentControlSet\Control\CI\Policy' 'VerifiedAndReputablePolicyState' 0 'Security' 'Smart App Control off (decision; can be turned on again in Windows Security since 25H2)'
    }
)

# Hibernate instead of sleep (profile power.mode 'hibernate'): S1-S3 stay disallowed
# by the baseline, and the BitLocker key is never in RAM while the PC is off.
if ($PowerMode -eq 'hibernate') {
    $values += S SYSTEM 'SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabledDefault' 1 'Sleep' 'Hibernation on by default'
    $values += S SYSTEM 'SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 1 'Sleep' 'Hibernation on (idle and power button hibernate; PostInstall)'
    $values += S SYSTEM 'SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'Sleep' 'Fast Startup (hibernate-based boot) off'
}

if (-not $allowMsa) {
    $values += S SOFTWARE 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'NoConnectedUser' 1 'OOBE' 'Users cannot convert/add a Microsoft account for Windows sign-in (app sign-in unaffected)'
}

if ($ListOnly) {
    $values | Format-Table Area, Hive, Path, Name, Value, Delete -AutoSize | Out-String -Width 300
    return
}

# Values under ...\Policies\ are also written to local Group Policy at first
# logon (PostInstall: Apply-Policy.ps1, which calls Set-KitRegistry -PolicyTextPath).
$policyPath = '^(?i)software\\(policies|microsoft\\windows\\currentversion\\policies)\\'

if ($PolicyTextPath) {
    $typeMap = @{ REG_DWORD = 'DWORD'; REG_SZ = 'SZ' }
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add('; Generated by Set-KitRegistry.ps1 -PolicyTextPath; Apply-Policy.ps1 merges it into local Group Policy')
    $count = 0
    foreach ($s in $values) {
        if ($s.Hive -eq 'SYSTEM' -or $s.Path -notmatch $policyPath) { continue }
        $out.Add('')
        $out.Add($(if ($s.Hive -eq 'DEFAULTUSER') { 'User' } else { 'Computer' }))
        $out.Add($s.Path)
        $out.Add($s.Name)
        $out.Add($(if ($s.Delete) { 'DELETE' } else { "$($typeMap[$s.Type]):$($s.Value)" }))
        $count++
    }
    $out | Set-Content -LiteralPath $PolicyTextPath -Encoding ASCII
    Write-Host "Wrote $count policy values to $PolicyTextPath"
    return
}

# --- Hive plumbing ----------------------------------------------------------
# reg.exe writes to stderr on "not found"; under Windows PowerShell 5.1 with
# ErrorActionPreference=Stop, redirected native stderr becomes a terminating
# error. Run every reg.exe call with a local 'Continue' and use the exit code.
$regLast = @{ Out = '' }   # reg.exe's message from the last call, for warnings
function Invoke-Reg {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $o = & reg.exe @args 2>&1
        $regLast.Out = (($o | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ')
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
}

# Registry path under HKLM\W11K_* / HKLM / HKCU for a setting
function Resolve-SettingPath($s, [string]$root) {
    $path = $s.Path
    if ($root -like 'HKLM\W11K_*' -and $s.Hive -ne 'DEFAULTUSER') {
        # Offline machine hives are loaded at their own root: strip the hive prefix
        $path = $path -creplace '^(SOFTWARE|SYSTEM)\\', ''
        if ($s.Hive -eq 'SYSTEM') { $path = $path -replace '^CurrentControlSet\\', 'ControlSet001\' }
    }
    "$root\$path"
}

$loaded = New-Object System.Collections.Generic.List[string]

function Mount-Hive([string]$Name, [string]$File) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Hive file not found: $File" }
    if ((Invoke-Reg load "HKLM\$Name" $File) -ne 0) { throw "reg load failed for $File" }
    $loaded.Add("HKLM\$Name")
}

function Dismount-Hives {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    foreach ($h in $loaded) {
        $rc = 1
        for ($i = 0; $i -lt 10; $i++) {
            $rc = Invoke-Reg unload $h
            if ($rc -eq 0) { break }
            [gc]::Collect()
            Start-Sleep -Seconds 2
        }
        if ($rc -ne 0) { Write-Warning "Could not unload $h - unload it manually before dismounting." }
    }
    $loaded.Clear()
}

$roots = @{}
try {
    if ($Mode -eq 'Offline') {
        if (-not $MountPath) { throw '-MountPath is required for -Mode Offline' }
        Mount-Hive 'W11K_SOFTWARE' (Join-Path $MountPath 'Windows\System32\config\SOFTWARE')
        Mount-Hive 'W11K_SYSTEM'   (Join-Path $MountPath 'Windows\System32\config\SYSTEM')
        Mount-Hive 'W11K_DEFAULT'  (Join-Path $MountPath 'Users\Default\NTUSER.DAT')
        $roots.SOFTWARE    = @('HKLM\W11K_SOFTWARE')
        $roots.SYSTEM      = @('HKLM\W11K_SYSTEM')
        $roots.DEFAULTUSER = @('HKLM\W11K_DEFAULT')
    } else {
        $defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
        Mount-Hive 'W11K_DEFAULT' $defaultHive
        $roots.SOFTWARE    = @('HKLM')
        $roots.SYSTEM      = @('HKLM')
        $roots.DEFAULTUSER = @('HKCU', 'HKLM\W11K_DEFAULT')
    }

    if ($Verify) {
        if ($Mode -ne 'Offline') { throw '-Verify is for -Mode Offline' }
        $good = 0; $bad = New-Object System.Collections.Generic.List[string]; $pend = New-Object System.Collections.Generic.List[string]
        foreach ($s in $values) {
            foreach ($root in $roots[$s.Hive]) {
                $full = Resolve-SettingPath $s $root
                $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(($full -replace '^HKLM\\', ''))
                $actual = if ($key) { $key.GetValue($s.Name, $null) } else { $null }
                if ($key) { $key.Close() }
                $okNow = if ($s.Delete) { $null -eq $actual } else { $null -ne $actual -and "$actual" -eq "$($s.Value)" }
                if ($okNow) { $good++ }
                elseif ($s.DeferToGp) { $pend.Add("$full\$($s.Name) (applied at first logon via Group Policy)") }
                else { $bad.Add("$full\$($s.Name): expected '$(if ($s.Delete) { '<absent>' } else { $s.Value })', found '$actual'") }
            }
        }
        Write-Host "Registry verify: $good correct, $($pend.Count) policy value(s) left to Group Policy, $($bad.Count) wrong."
        $pend | ForEach-Object { Write-Host "  deferred: $_" }
        $bad | ForEach-Object { Write-Warning "WRONG: $_" }
        if ($bad.Count) { throw "Registry verification failed: $($bad.Count) value(s) wrong" }
        return
    }

    $ok = 0; $fail = 0; $deferred = 0
    foreach ($s in $values) {
        foreach ($root in $roots[$s.Hive]) {
            $full = Resolve-SettingPath $s $root
            if ($s.Delete) {
                if ((Invoke-Reg query $full /v $s.Name) -ne 0) { continue }   # already absent
                $rc = Invoke-Reg delete $full /v $s.Name /f
            } else {
                $rc = Invoke-Reg add $full /v $s.Name /t $s.Type /d "$($s.Value)" /f
            }
            if ($rc -eq 0) { $ok++ }
            elseif ($s.DeferToGp) {
                # Only the values marked -DeferToGp (Policies\Microsoft\Dsh is blocked
                # for reg.exe/PowerShell even as admin); applied at first logon via Group Policy.
                $deferred++
                Write-Warning "Not written now ($($regLast.Out)); applied at first logon via local Group Policy: $full\$($s.Name)"
            }
            else { $fail++; Write-Warning "Failed: $full\$($s.Name): $($regLast.Out)" }
        }
    }
    Write-Host "Registry ($Mode): $ok applied, $deferred deferred to Group Policy, $fail failed."
    if ($fail) { throw "$fail registry operations failed" }
}
finally {
    Dismount-Hives
}
