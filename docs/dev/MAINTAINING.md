# Maintaining the kit

> For contributors and maintainers. Using the kit? Start with the [guide](../GUIDE.md).

What a maintainer does to keep the kit current: move the pins each month, follow a new Windows
release or security baseline, update the build tools, build without anyone watching, and make
the public export. A user's own monthly routine is in [MONTHLY](../MONTHLY.md): they update the
kit and rebuild, and the pins you moved come with it.

The project's rule: stay on the latest **stable** version of everything the kit brings in. No
previews, release candidates or Insider builds. Every input and where it is pinned:
[DEPENDENCIES](DEPENDENCIES.md).

Commands here are for a contributor's shell (WSL or Linux, from the repository), so they use
`python3`. On Windows the same scripts run with `py`.

## Monthly: move the pins

Do this after Microsoft's update day, the second Tuesday of the month.
On the public repository, the workflow `.github/workflows/stale-pins.yml` asks the catalog every
Wednesday and opens an issue when there are newer updates than the pins (one open issue at a
time): it downloads and changes nothing.

### 1. The updates

`config/updates.json` pins four groups of updates, by KB number:

| Group | What | Used for |
|---|---|---|
| `lcu` | The cumulative update | The install image, WinRE and `boot.wim` |
| `dotnet` | The .NET Framework cumulative update | The install image |
| `safeos` | Safe OS Dynamic Updates | WinRE |
| `setup` | Setup Dynamic Updates | The media's `sources\` folder |

Ask the Update Catalog for the newest of each:

```
python3 scripts/Get-Updates.py --discover
```

It downloads nothing. Exit code 0 means newer KBs exist (it prints a `CHANGED` line per group);
3 means nothing is newer. To write the new pins into the file:

```
python3 scripts/Get-Updates.py --discover --write
```

That updates the KB lists, `lcuBuild` (the OS build the LCU brings) and `pinned` (today's date).

How discovery chooses (the `discover` rules in the same file):

- Each rule is a catalog title. The newest month with that title wins.
- The `lcu` rule excludes titles with `Preview`, so the kit follows the security releases.
  Remove the exclusion to follow the optional preview releases too.
- It never goes backwards: an LCU with a lower OS build than `lcuBuild` is ignored.

Then fetch them, to test with:

```
python3 scripts/Get-Updates.py
```

It finds exactly one catalog entry per KB, downloads the file from Microsoft, and checks the
SHA-1 that Microsoft puts in each file name. It also **removes every other file** from the four
folders, because the build applies all it finds there. `--list` only shows the catalog matches.

The file holds KB numbers, not hashes. The hash check is the SHA-1 in the file name, on download
and again in the build right before a file is applied.

**Why `pinned` matters.** A user who builds with old pins gets an image that is months behind
and a boot manager that an up-to-date PC may refuse. So preflight prints a note when `pinned` is
more than 35 days old, and `Run-Build.cmd` asks before it goes on when it is more than 70 days
old. Both point to `Get-Updates.py --discover --write`.

### 2. Everything else that has versions

1. **Security baselines.** Open the
   [toolkit page](https://www.microsoft.com/download/details.aspx?id=55319): a new Windows or
   Edge baseline, or a renamed file (`... v2.zip`), is an update. Then check that each pinned
   file still downloads and still matches:
   `python3 scripts/Import-Baseline.py windows-11-v26h2 --check`, and the same for the Edge id.
   It writes nothing: it downloads the pinned zip again into a temporary folder
   (`<file>: Microsoft still serves the pinned file (SHA-256 OK)`) and compares a fresh import
   with the data in `<work>/baselines/<id>/`. A failure means Microsoft replaced the file
   ([below](#new-microsoft-security-baseline)).
2. **Build tools.** Git for Windows, Python and the ADK
   ([below](#updating-the-build-tools)).
3. **DISA STIG.** [NIST NCP checklist 1028](https://ncp.nist.gov/checklist/1028) lists a new
   Windows 11 STIG release. A new release means a new review
   ([DISA STIG additions](../reference/SECURITY-BASELINE.md#disa-stig-additions)).
4. **The lint workflow's actions.** `actions/checkout` is pinned by commit hash, with the version
   in a comment. Dependabot opens a pull request when there is a newer one: check that the hash
   is the one the action's release tag points at, then merge.
5. **The source ISO.** Microsoft's download page, in a browser. A newer build means a new entry
   in `config/source-iso.json`, with the SHA-256 from the page's *Verify your download* list.

### 3. Test, then record

1. For anything but the monthly updates (their numbers live only in `config/updates.json`): update
   the base-image table in [CONFIGURATION](../reference/CONFIGURATION.md#base-image) and the
   *Pinned version* and *Last checked* columns in [DEPENDENCIES](DEPENDENCIES.md#the-inputs).
2. Run a test build and the VM test until `RESULT: PASS`
   ([Reporting a test run](TESTING.md#reporting-a-test-run)).
3. Add a line to `CHANGELOG.md`.

## New Windows feature release

The image pins Windows Update to its own feature version, so an installed PC moves to a new
release only when it is rebuilt. The pin is three values in `scripts/Set-KitRegistry.ps1`:
`TargetReleaseVersion` = 1, `ProductVersion` = `Windows 11` and `TargetReleaseVersionInfo` =
`26H2`.

For a new release (for example 27H2):

1. Download the new ISO and add its entry to `config/source-iso.json`.
2. Set `release` in `config/updates.json` and run `--discover --write`.
3. Change `TargetReleaseVersionInfo`, and `featureVersion` in `config/image.json` (version and
   the Home and Pro end-of-servicing date from Microsoft's lifecycle page; the validator warns
   from 90 days before it), and the date in [MONTHLY.md](../MONTHLY.md#when-this-windows-version-nears-its-end).
4. Take the ADK that supports the new release ([below](#updating-the-build-tools)).
5. Expect a new security baseline for it ([below](#new-microsoft-security-baseline)).
6. Search the scripts for the old release name: build-number checks and messages mention it.
7. Test, and update the docs that name the release.

## New Microsoft security baseline

The repository holds no baseline data. Each baseline is one folder, `config/baselines/<id>/`,
with one file, `source.json`: the official file name (`file`), its download URL (`url`), the
download page (`page`), its SHA-256, the GPOs to apply, in order (`gpos`), and the client-side
extensions to register (`extensions`). `config/baselines/baselines.json` lists which ids are
applied, in order. `scripts/Get-Baselines.py` downloads each pinned zip into `<work>/baselines`
and imports it (`Run-Build.cmd` offers to run it); every build then imports again from the zips
([Build steps](BUILD-INTERNALS.md#build-steps)).

**Microsoft replaces files in place.** A baseline zip can become `... v2.zip` on the same page,
with new GPO GUIDs and a changed setting, and the old URL then stops working. A user who does
not have the old zip yet can then not build until the pin moves, so check the pins monthly.
The download and the preflight name the download page and say how to use a zip you already
have: `python3 scripts/Get-Baselines.py --zip <file>` (any file name; its SHA-256 decides).

For a new release (a new Windows baseline, or a new Edge version):

1. **Download the zip** from the toolkit page (the page's source lists the
   `download.microsoft.com` links) and hash it.
2. **Make `config/baselines/<new-id>/source.json`**, copied from the old one. Change the name,
   file, URL and SHA-256.
3. **Check the GPO list.** Take the names from the zip's `Scripts/Baseline-LocalInstall.ps1`.
   For Windows, use the set it applies with `-Win11DomainJoined`. The script applies its GPOs
   **sorted by display name**, not in the order it lists them; keep that order. `extensions` are
   the client-side extensions its `LGPO /e` line registers.
4. **Import it**: `python3 scripts/Import-Baseline.py <new-id> --zip <file>`. The data goes to
   `<work>/baselines/<new-id>/`, never into `config/`. The importer refuses a zip with another
   hash and a GPO the package's own installer does not name. It re-encodes every `registry.pol`
   from its records and compares the bytes with the original before it writes anything.
5. **Replace the old id** in `baselines.json` and delete the old folder.
6. **Compare old and new data** (a build or the importer leaves it in `<work>\baselines\<id>\`,
   in the work folder) for settings that conflict with the kit's decisions: standby,
   Secure Launch, UAC, UEFI locks, Xbox services, passwords. The decisions are in
   [DECISIONS](DECISIONS.md); the overrides are in
   [SECURITY-BASELINE](../reference/SECURITY-BASELINE.md#overrides).
7. **Update** `config/baseline-overrides.txt` / `.inf`, the override tables in SECURITY-BASELINE,
   and the validator's override rows in `payload/Test-InstalledPc.ps1`. Its *every baseline value
   in effect* row follows the data by itself.
8. Test.

One thing the data cannot carry: Microsoft's installer also disables the `XblGameSaveTask`
scheduled task as a script step, not as a GPO.

## Updating the build tools

The build tools are pinned in `config/installers.json`: Git for Windows and Python under
`installers` (the ISO carries these two as build inputs), the ADK under `adk`.

To pin a newer version, change `version`, `file`, `url`, `sha256` and `signer` **together**:

1. **Find the version.**
   - Git: `https://api.github.com/repos/git-for-windows/git/releases/latest`. The asset's
     `digest` is its SHA-256.
   - Python: the newest final 3.x on python.org, not an alpha, beta or release candidate.
   - ADK: the release that Microsoft's
     [ADK page](https://learn.microsoft.com/windows-hardware/get-started/adk-install) says
     supports the Windows release the kit builds. That is not always the highest version number.
2. **Download the file and hash it.** Compare with the publisher's hash where there is one.
3. **Read the signer**, in Windows PowerShell:
   `(Get-AuthenticodeSignature <file>).SignerCertificate.Subject`. The status must be `Valid`.
   The kit compares the whole subject, so copy it exactly.
4. **Test** that `C:\W11Kit\Run-Prepare.cmd` installs it on a PC without the tool.

A PC that already has a tool keeps its version: the kit leaves an installed tool alone. `oscdimg`
is used only when it is signed by exactly the ADK's pinned signer, so a wrong `signer` under
`adk` stops every build.

## Unattended builds and encrypted passwords

A build that nobody watches (a scheduled task, a CI job) must not leave plain-text passwords
behind. `-EncryptAccountsTo <file.cer>` writes the one-time passwords encrypted to a certificate
whose private key only you hold. The file is then `<work>\accounts.txt.cms`, and no plain-text
copy is written.

**Once, make the certificate.** As yourself, in PowerShell, on the PC where you will read the
passwords:

```powershell
$c = New-SelfSignedCertificate -Type DocumentEncryptionCert -Subject "CN=W11Kit accounts ($env:USERNAME)" `
     -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(5)
Export-Certificate -Cert $c -FilePath C:\W11Kit\work\accounts-recipient.cer
```

The `.cer` holds only the public key. Preflight checks that it is a Document Encryption
certificate.

The private key can't be exported, so it doesn't survive a reinstall of that PC: the passwords
files made for it can't be read afterwards. Read the ones you still need before you reinstall,
then make a new certificate on the new install and replace the `.cer` before the next build.

**Build** with `-EncryptAccountsTo C:\W11Kit\work\accounts-recipient.cer`.

**Read the passwords** as the account that made the certificate, in a PowerShell that is **not**
elevated:

1. The file is readable by administrators only, so copy it out first. In PowerShell (as
   administrator):
   `Copy-Item C:\W11Kit\work\accounts.txt.cms C:\Users\Public\W11Kit-accounts.txt.cms`
2. In your normal PowerShell: `Unprotect-CmsMessage -Path C:\Users\Public\W11Kit-accounts.txt.cms`
3. Save the passwords, then delete the copy.

Why two windows: with Administrator protection on, an elevated window runs as a separate
`ADMIN_<name>` account that does not hold your key. Without it, an elevated window as yourself
can read the file directly.

Good to know:

- The last line of the file, outside the encrypted block, names the ISO and its SHA-256.
- The key is not exportable, on purpose. To read the passwords on another PC, make the
  certificate there and copy the `.cer` to the build PC.
- **The ISO still holds the passwords**, only obfuscated, as any unattended install must. Every
  local user of the build PC can read the ISO. The forced change at first sign-in retires them.
- The VM test keeps only a copy of the answer file with the passwords removed.

A build asks nothing when you call `scripts\Build-Iso.ps1` directly: the questions belong to
`Run-Build.cmd`. Running a whole test cycle on a runner: [CI](CI.md).

## Versions, breaking changes and releases

The kit's version is `MAJOR.MINOR.PATCH` in `CHANGELOG.md`, and a release is a tag `v<version>`
on a commit that passed the tests. While the version is `0.x`, a **minor** bump may break an
adopter's files and a **patch** bump may not.

**Breaking** means that someone who runs `git pull` has to change something they own, or that
an ISO built before can't restore into the kit after. That is any of:

- a field renamed, removed or re-typed in `config/settings.defaults.json` (an adopter's
  `settings.local.json` is then refused as "unknown field") or in the profile schema;
- a path that moved in the payload folder (`C:\ProgramData\W11Kit`) or in the work folder;
- a change of the build inputs' layout in the ISO;
- a launcher or `Build-Iso.ps1` parameter renamed or removed.

For a breaking change, in the same commit:

1. Raise `schemaVersion` in the file whose shape changed (settings or profile), and make the
   error for the old shape name the new field ("`x` is now `y`").
2. Add the change to `CHANGELOG.md` under a **Breaking** heading, with the one edit the adopter
   makes.
3. Keep reading the old work-folder or build-input layout for one release where that is
   possible (`scripts/Move-KitWork.ps1` is the pattern), and say so.

A monthly move of the pins, a new check, a new default-off option and a doc change are not
breaking.

**Cutting a release:**

1. The gate passes (`dev/Test-KitSyntax.sh`) and the Hyper-V test ends in `RESULT: PASS` for
   `legion-t5` and `generic` on the commit ([TESTING.md](TESTING.md)).
2. `CHANGELOG.md` gets a section `## <version>` with the date, what changed for the user, the
   Windows build and update numbers the pins give, and the breaking changes first.
3. Update the *Status* table in [TESTING.md](TESTING.md#status) if what is proven changed.
4. Tag the commit `v<version>` and publish the tag's notes from the CHANGELOG section. The
   notes name the commit, so a download can be compared with it.

## The public export

The public repository is a filtered snapshot of the working repository, with a fresh history.
`dev/Export-Public.sh` makes it:

```
bash dev/Export-Public.sh <target-dir> [options]
bash dev/Export-Public.sh --check-only [options]
```

| Option | Meaning |
|---|---|
| `<target-dir>` | Where the public tree goes: a new or empty folder outside this repository |
| `--ref <git ref>` | The commit to export. Default: `HEAD` |
| `--allow-dirty` | Run although the worktree has uncommitted changes. They are not exported |
| `--check-only` | Export into a temporary folder, run the checks, delete the folder |
| `--final` | For the real publication: a placeholder that is still there is an error |
| `--author-email <address>` | The e-mail address for the commit commands it prints |
| `--remote-url <url>` | The public repository's address for the commands it prints |

It writes the tree of one commit (`git archive`) into the target folder, without the paths the
export's exclude list names. It works from the commit, so commit first; with uncommitted changes
it refuses, unless you pass `--allow-dirty`. It uses no network, makes no commit and pushes
nothing. Exit code 0 means every check passed, 1 means violations, 2 means it refused to run.

Then it runs seven checks, `[a]` to `[g]`, and prints one line per violation:

| | The exported tree must have |
|---|---|
| a | Nothing the exclude list names, and no hidden file or folder at the top other than `.github`, `.gitattributes` and `.gitignore` |
| b | No text and no file name that matches the maintainer's deny-list (names, addresses, host names, old project names). A hit prints the file, the line number and the pattern, never the line |
| c | No placeholder other than the three the script lists (`--help` shows them). With `--final`, none at all |
| d | Only relative Markdown links and anchors that resolve (`dev/Test-DocLinks.py`) |
| e | No file over 1 MB, and no binary, executable, archive or symbolic link |
| f | A passing syntax gate of its own (`dev/Test-KitSyntax.sh`, run on the exported tree) |
| g | No commit hash of the working repository in its text: after the squash it would point at nothing |

It ends with `EXPORT OK: ...` or `EXPORT FAIL: <n> violation(s) ...`. After a failed run the tree
is left in the target folder to look at: don't publish it, and delete it before the next run.

When it passes, it prints the commands that create the single-commit history with a neutral
author (`W11Kit contributors`), and does not run them.

**For the real publication:**

1. Fill in the placeholders in the working repository, and delete the comment line at the top of
   `.github/ISSUE_TEMPLATE/config.yml` that names them. Commit.
2. Export again with `--final`, `--author-email` and `--remote-url`.
3. Run the commands it prints, in the target folder.

What this means for anyone who writes docs or comments:

- A public page must not link to, or mention, a file the export leaves out. The syntax gate
  already fails on such a link.
- Write no names, host names, dates of internal decisions, commit hashes or run numbers into
  docs, code comments or messages. The technical reason stays; the diary goes.
