# Best-practice survey

> For contributors and maintainers. Using the kit? Start with the [guide](../../GUIDE.md).

> **Snapshot of 2026-10-09.** The current state is in
> [SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md).

A record of one review: what current Windows 11 guidance recommends beyond what the kit already
did, what was adopted, and what was left out and why. It is a snapshot, like the
[STIG review](STIG-REVIEW.md). The living description of every setting is
[SECURITY-BASELINE](../../reference/SECURITY-BASELINE.md) and
[CONFIGURATION](../../reference/CONFIGURATION.md); the reasons are in
[DECISIONS](../DECISIONS.md#additions-from-the-best-practice-survey).

## How it was done

Four passes. Each first read what the kit already applies, so that only real gaps came back, then
surveyed current sources and compared.

| Pass | Main sources |
|---|---|
| Security hardening | Microsoft's Defender attack-surface-reduction reference, SMB and NTLM hardening pages, Policy CSP pages, the 26H2 baseline; ASD guidance, and second-hand references to CIS guidance, for cross-checking |
| Privacy, AI features, bundled apps | Microsoft's Policy CSP and Edge policy reference, "Manage connections from Windows 11 operating system components to Microsoft services"; the settings lists of two community privacy tools, for cross-checking |
| How the image is built and installed | Microsoft's "Update Windows installation media with Dynamic Update" (2026-08-04), KB5025885 (Secure Boot), the UEFI/GPT partition guidance |
| Resilience and upkeep | NCSC and CISA backup guidance, Microsoft's BitLocker, Defender and Secure Boot pages |

Notes on the sources:

- The CIS benchmark documents themselves were not read. Nothing in the kit derives from their
  text or numbering.
- The two community tools were read only to see whether a setting had been missed. No text, code
  or configuration of theirs is in the kit.
- Every policy name, value and identifier that went into the kit was checked against Windows
  26H2's own policy definitions (`C:\Windows\PolicyDefinitions\*.admx`) or the Microsoft page that
  documents it. What could not be confirmed was left out.

## What it changed in the build and the checks

| Finding | What the kit does |
|---|---|
| `boot.wim` (the small Windows that runs Setup from the stick) has to receive the monthly update too, or Setup and the stick's boot manager stay at the source ISO's level | The build services it, takes the Setup files and every boot manager copy from it, and fails if they don't match ([BUILD-INTERNALS](../BUILD-INTERNALS.md#boot-media)) |
| Microsoft puts a servicing-stack step before the recovery environment's Safe OS updates | The cumulative update goes into the recovery environment first |
| A real install has a recovery partition | The VM test's disk layout has one too |
| A check that reads back the identifier it was given can't find a wrong identifier | Every Defender rule identifier was compared with Microsoft's reference |
| Three settings meant to quiet consumer content work only on Enterprise and Education | Kept (harmless) and documented as having no effect on Pro; the per-user values do the work |

## Adopted

Each item is a project decision. The costs are listed with each setting in the two living pages.

- **Network exposure:** outbound SMB to the Internet blocked; NTLM use audited (not blocked);
  automatic proxy discovery off; the print spooler takes no remote clients; Remote Desktop and
  WinRM off by policy; the WebDAV client, file-sharing server and SSDP/UPnP services disabled;
  mDNS off.
- **Software trust:** winget's bypass switches off; the stricter Authenticode check
  (CVE-2013-3900); no security questions for local accounts.
- **Monitoring:** Windows' built-in Sysmon with the kit's own configuration; a larger PowerShell
  log; a validator summary of security events since the last report.
- **Privacy:** Edge privacy, first-run, background and AI policies; no web results in Start
  search; search highlights, cloud clipboard, Click to Do, Find My Device and location off;
  Start's *Recommended* section and Settings' *Home* page hidden; Paint and Notepad AI off; speech
  and typing collection off for accounts created later.
- **Bundled apps removed:** new Outlook, Quick Assist, Solitaire, To Do, Power Automate, Sticky
  Notes, the Bing search app ([REMOVED-APPS](../../reference/REMOVED-APPS.md)).
- **Validator:** Defender health and leftover exclusions, the installed boot manager's signer, the
  recovery partition, BitLocker state and a stale recovery key, update currency, account drift,
  network exposure, disk health, firmware and driver age, log retention, backup coverage, an
  offline-backup reminder, and generic checks of every override, kit policy value and disabled
  service.
- **Checklists:** a monthly offline backup, firmware and driver advisories, app updates, rescue
  media ([MONTHLY](../../MONTHLY.md#the-monthly-routine)); network and USB boot off in the BIOS
  ([GUIDE, step 11](../../GUIDE.md#step-11-biosuefi-settings)); and "never use Reset this PC"
  ([AFTER-INSTALL](../../AFTER-INSTALL.md#never-use-reset-this-pc)).

## Considered, not adopted

| Item | Why not (and when to look again) |
|---|---|
| Windows protected print mode | It allows only driverless (IPP) printers: no vendor printer drivers and no plain TCP/IP printer ports |
| Revoking the 2011 boot certificate in the firmware (DBX) and raising the boot manager's security version | It can't be undone, and older rescue media stop booting. It is the lasting fix for the boot-manager downgrade attack on TPM-only BitLocker: revisit. Until then: network and USB boot off in the BIOS |
| The "PsExec and WMI process creation" Defender rule in Block instead of Audit | Installers and tools may rely on it. The validator counts its audit events, so decide after a month of data |
| PowerShell transcription and module logging | Log volume during builds, and transcripts would capture secrets such as a BitLocker recovery key |
| Controlled Folder Access, the "prevalence" Defender rule, application allowlisting, a BitLocker startup PIN, Credential Guard, Windows LAPS | Each conflicts with a decision of this kit (the installed PC builds its own ISO; unattended Wake-on-LAN) or needs Enterprise or a directory |
| Forcing Smart App Control on | Left as Windows sets it. A PC that runs its own unsigned builds turns it off (`options.smartAppControl`) |
| Policy lockdown of WSL, removing VBScript, hiding the password-reveal button, Windows Error Reporting off, DNS over HTTPS | Low value against their side effects, or your own choice per network |
| "Debloat" measures: telemetry below Required, removing Edge, OneDrive or the Store, disabling update services | They break servicing or contradict decisions |

## Not verified by the survey

- Whether Quick Machine Recovery (the recovery environment going online to repair a PC that won't
  start) is on by default on Pro: sources disagree. The validator reports the PC's actual state.
- Whether hiding search-box suggestions still removes web results from Start on 26H2: Microsoft
  documents the policy only for File Explorer. Check Start search after an install.
- The date of AMD's firmware-TPM bulletin (AMD-SB-7064) and whether a given BIOS has its fix:
  check the PC maker's support page.
