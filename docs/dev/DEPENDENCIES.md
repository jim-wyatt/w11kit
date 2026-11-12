# External inputs (dependencies)

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

Everything the kit brings in from outside, and where each one is pinned. Nothing here is in the
repository: it carries pins (version, URL, hash, signer), never the files themselves.

The project's rule is to stay on the latest **stable** version of each. How to check for newer
versions and move a pin: [MAINTAINING](MAINTAINING.md#monthly-move-the-pins). Update *Last
checked* when you do.

## The inputs

### Downloaded for a build

| Input | Pinned version | Verified by | Pinned in | Last checked |
|---|---|---|---|---|
| Windows 11 source ISO (multi-edition, x64, en-US) | Build 26300.9457, `Windows11_Client_x64_en-us_26300_9457.iso`, SHA-256 `BD4307DF…5EA650` | SHA-256, compared with the *Verify your download* list on Microsoft's page | `config/source-iso.json` | 2026-10-09 |
| Cumulative update (LCU) | The KB number and build in `config/updates.json` (`updates.lcu`, `lcuBuild`) | The SHA-1 in each Update Catalog file name, on download and again before the build applies the file | `config/updates.json` | `pinned` in that file |
| .NET Framework cumulative update | `updates.dotnet` in `config/updates.json` | As the LCU | `config/updates.json` | `pinned` in that file |
| Safe OS Dynamic Update (for WinRE) | `updates.safeos` in `config/updates.json` | As the LCU | `config/updates.json` | `pinned` in that file |
| Setup Dynamic Update (for the media) | `updates.setup` in `config/updates.json` | As the LCU | `config/updates.json` | `pinned` in that file |
| Microsoft Windows 11 v26H2 Security Baseline | v2, `Windows 11 v26H2 Security Baseline v2.zip`, SHA-256 `369f8dad…5e45d18` | SHA-256; the importer refuses anything else | `config/baselines/windows-11-v26h2/source.json` | 2026-10-09 |
| Microsoft Edge Security Baseline | v151, `Microsoft Edge v151 Security Baseline.zip`, SHA-256 `c8d1be70…c7a6ab` | SHA-256 | `config/baselines/edge-v151/source.json` | 2026-10-09 |

Where they come from:

- **Source ISO**: [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11),
  by hand, in a browser. Microsoft blocks scripted ISO downloads. An ISO the kit does not list
  yet goes into your own `config/source-iso.local.json`.
- **Updates**: the [Microsoft Update Catalog](https://www.catalog.update.microsoft.com), fetched
  by `scripts/Get-Updates.py`.
- **Baselines**: Microsoft's
  [Security Compliance Toolkit](https://www.microsoft.com/download/details.aspx?id=55319) page.
  Each `source.json` holds the direct `download.microsoft.com` link. `scripts/Get-Baselines.py`
  downloads the zips into the work folder (`Run-Build.cmd` offers it), and every build imports
  them there with `scripts/Import-Baseline.py`. Microsoft replaces
  these files in place ([New Microsoft security baseline](MAINTAINING.md#new-microsoft-security-baseline)).

### Build tools, installed on a build PC on demand

| Input | Pinned version | Verified by | Pinned in | Last checked |
|---|---|---|---|---|
| Git for Windows | 2.56.0.2, `Git-2.56.0.2-64-bit.exe`, SHA-256 `52188F91…2D60F6` | SHA-256 and the exact Authenticode signer | `config/installers.json` (`installers`) | 2026-10-09 |
| Python 3 | 3.14.8, `python-3.14.8-amd64.exe`, SHA-256 `759BE887…99F8EF` | SHA-256 and the exact Authenticode signer | `config/installers.json` (`installers`) | 2026-10-09 |
| Windows ADK Deployment Tools (`oscdimg`) | 10.1.26100.9457, `adksetup.exe`, SHA-256 `AC6A930F…77300F` | SHA-256 and the exact Authenticode signer | `config/installers.json` (`adk`) | 2026-10-09 |

Where they come from:

- **Git for Windows**: its [GitHub releases](https://github.com/git-for-windows/git/releases/latest).
- **Python**: [python.org](https://www.python.org/downloads/windows/), the 64-bit installer.
- **ADK**: Microsoft's [ADK page](https://learn.microsoft.com/windows-hardware/get-started/adk-install).
  Take the ADK that supports the Windows release the kit builds, not the highest version number.

The signer subjects are in `config/installers.json`. The Git and Python installers also ride in a
real ISO as build inputs; the ADK installer does not (it is a web installer), but `oscdimg`
itself does. How to move a pin: [Updating the build tools](MAINTAINING.md#updating-the-build-tools).

### Reviewed, not downloaded by the kit

| Input | Version | Verified by | Where it shows | Last checked |
|---|---|---|---|---|
| DISA Windows 11 STIG | V2R11, `U_MS_Windows_11_V2R11_STIG.zip`, SHA-256 `5a1337e8…260d54` | SHA-256, recorded in the review | [STIG-REVIEW](reviews/STIG-REVIEW.md); the values in `scripts/Set-KitRegistry.ps1` and `config/baseline-overrides.*` | 2026-10-09 |

It is listed by [NIST NCP checklist 1028](https://ncp.nist.gov/checklist/1028). The kit adopts
selected DISA STIG settings; the image is not STIG-compliant
([DISA STIG additions](../reference/SECURITY-BASELINE.md#disa-stig-additions)).

### The repository's own checks

| Input | Pinned version | Verified by | Pinned in | Last checked |
|---|---|---|---|---|
| `actions/checkout` (the lint workflow) | v7.0.1, by its full commit hash | The commit hash; Dependabot proposes newer ones (`.github/dependabot.yml`) | `.github/workflows/lint.yml` | 2026-10-13 |

## Not pinned

- **What Windows brings in by itself** at and after install: inbox apps, Defender definitions,
  Store apps, later updates. Windows Update and the Store keep those current.
- **Your drivers.** They come from the PC you reinstall, not from the internet
  ([DRIVERS](../reference/DRIVERS.md#harvest)).
- **Tools you choose yourself**, such as the program that writes the USB stick.
- **A CI runner's own toolchain**, if you run one ([CI](CI.md)).
