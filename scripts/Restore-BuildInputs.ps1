<#
.SYNOPSIS
    Restores the build inputs carried in the ISO's BuildInputs folder onto a
    freshly installed PC, and the kit itself, so the PC can build its next ISO
    without downloads.

.DESCRIPTION
    Runs elevated from the install USB (Restore-BuildInputs.cmd next to it).
    Everything goes into ONE folder, the kit folder (-KitRoot, default C:\W11Kit):
    the kit as a Git clone, and everything else in its work folder:

      source ISO          C:\W11Kit\work\source\
      updates             C:\W11Kit\work\updates\  (lcu, dotnet, safeos, setup, manifest)
      security baselines  C:\W11Kit\work\baselines\  (Microsoft's zips as downloaded; the next
                          build imports them itself, with Python: nothing to run here)
      drivers             C:\W11Kit\work\DriverExport.zip (+ .sha256), extracted to
                          C:\W11Kit\work\DriverExport
      oscdimg             C:\W11Kit\work\tools\Oscdimg\  (Microsoft-signed, no ADK install needed)
      installers          C:\W11Kit\work\installers\  (the build chain: Git for Windows, Python 3)
      kit                 C:\W11Kit\work\kit\w11kit.bundle (git bundle of the repo), checked
                          out into C:\W11Kit
      your own kit files  C:\W11Kit\work\kit\local\  (config\settings.local.json,
                          config\source-iso.local.json and profiles\<id>\profile.json files
                          that weren't committed), copied into the clone at the same paths

    1. The kit folder is looked at first, before anything is written: missing, empty or
       holding only a work folder (an earlier restore) is fine; a Git clone is fine too
       (it is left as it is); anything else stops the run with a message.
    2. For every file in manifest.json it joins the <4 GB parts (FAT32 can't hold
       larger files), checks size and SHA-256, and only then moves it into place. A
       file already in place with the right hash is skipped, so a rerun is safe. A
       mismatch stops the run and leaves nothing half-written.
    3. If Git is missing, it offers to install Git for Windows from the restored
       installer (Install-BuildTools.ps1, carried next to this script: SHA-256 and
       signature checked).
    4. The kit: 'git clone' refuses a folder that isn't empty, and the kit folder
       already holds work\. So the bundle (its SHA-256 checked again) is cloned without
       files into a temporary folder in work\kit, its .git folder is moved into the kit
       folder, and the files are checked out there: a normal clone, 'origin' pointing at
       the bundle. Git ignores work\ (.gitignore).
    5. Your own files are copied into the clone.
    Without Git (you answered no) steps 4 and 5 wait: install Git and run this again.
    Run-Prepare.cmd in the kit installs the rest of the build tools.

    A kit folder (and a work folder) this creates is writable by administrators only
    from the start (owner Administrators; users may read), as the build makes it.

.PARAMETER Root
    The BuildInputs folder. Default: the folder this script was loaded from
    (pass it explicitly when loaded as a scriptblock).
.PARAMETER KitRoot
    Where the kit and its work folder go. Default C:\W11Kit (on the system drive).
    Restore-BuildInputs.cmd takes it as its one argument: Restore-BuildInputs.cmd D:\W11Kit
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = $PSScriptRoot }
$defaultKit = Join-Path "$env:SystemDrive\" 'W11Kit'
if (-not $KitRoot) { $KitRoot = $defaultKit }
$KitRoot = [IO.Path]::GetFullPath($KitRoot).TrimEnd('\')
if ($KitRoot -notmatch '^[A-Za-z]:\\.') { throw "-KitRoot must be a folder on a local drive (not a drive root or a network path): $KitRoot" }
$workRoot = Join-Path $KitRoot 'work'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# (Not elevated into another folder than the default: a test restore.)
if (-not $isAdmin -and $KitRoot -ieq $defaultKit) { throw 'Run elevated (Restore-BuildInputs.cmd asks for it).' }
$manifestPath = Join-Path $Root 'manifest.json'
if (-not (Test-Path $manifestPath)) { throw "No manifest.json in ${Root}: is this the BuildInputs folder of a W11Kit ISO (the install USB stick)?" }
$manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
# Every file goes into the work folder, nowhere else: a manifest that names any other
# path is refused
foreach ($f in $manifest.files) {
    if ("$($f.dest)" -notmatch '^work\\[^:]+$' -or "$($f.dest)" -match '(^|\\)\.\.(\\|$)') { throw "manifest.json lists '$($f.dest)', which is not a path in the kit's work folder: this BuildInputs folder is not from this version of the kit. Use the Restore-BuildInputs.cmd that is on the same stick as the manifest." }
}

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
# A folder this creates: writable by administrators only from the start, as scripts\KitAcl.ps1
# makes the kit and its work folder (everything restored below inherits it). Not elevated
# (a test restore): a plain folder.
function New-LockedFolder([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return }
    if (-not $isAdmin) { $null = [IO.Directory]::CreateDirectory($Path); return }
    $sec = New-Object Security.AccessControl.DirectorySecurity
    $sec.SetSecurityDescriptorSddlForm('O:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)')
    $null = [IO.Directory]::CreateDirectory($Path, $sec)
}
# git with a local 'Continue' (its stderr would be terminating under 'Stop'); returns the exit code
function Invoke-Git {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $null = & $gitExe @args 2>&1 | ForEach-Object { Write-Host "    $_" }; $LASTEXITCODE } finally { $ErrorActionPreference = $old }
}

# --- 1. The kit folder: can the kit go there? (before anything is written) ----------------
$hasGit = Test-Path -LiteralPath (Join-Path $KitRoot '.git')
$kitState = 'new'      # 'new' = the kit is checked out below; 'clone' = already a clone, left as it is
if ($hasGit) { $kitState = 'clone' }
elseif (Test-Path -LiteralPath $KitRoot) {
    if (-not (Test-Path -LiteralPath $KitRoot -PathType Container)) { throw "$KitRoot is a file, not a folder: rename it, or restore somewhere else (Restore-BuildInputs.cmd <folder>)." }
    $others = @(Get-ChildItem -LiteralPath $KitRoot -Force | Where-Object { $_.Name -ine 'work' } | ForEach-Object Name)
    if ($others.Count) {
        throw "$KitRoot exists, is not a Git clone of the kit and is not empty (it holds: $(@($others | Select-Object -First 5) -join ', ')$(if ($others.Count -gt 5) { ', ...' })). The kit is checked out into that folder, so nothing was restored. Rename or empty it (keep its work folder if it has one), or restore somewhere else: Restore-BuildInputs.cmd <folder>, e.g. Restore-BuildInputs.cmd C:\W11Kit2"
    }
}
New-LockedFolder $KitRoot
New-LockedFolder $workRoot

# --- 2. The files, each verified before it is put in place ---------------------------------
Write-Host "Build inputs from $($manifest.built) (kit $($manifest.kitRevision)): $(@($manifest.files).Count) files -> $workRoot" -ForegroundColor Cyan
$n = 0
foreach ($f in $manifest.files) {
    $n++
    $dest = Join-Path $KitRoot $f.dest
    $label = "[$n/$(@($manifest.files).Count)] $($f.dest)"
    if ((Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -eq $f.size -and (Get-Sha256 $dest) -eq $f.sha256) {
        Write-Host "$label already in place"
        continue
    }
    Write-Host "$label ($([math]::Round($f.size / 1MB)) MB)"
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    $tmp = "$dest.restoring"
    $sha = [Security.Cryptography.SHA256]::Create()
    $out = [IO.File]::Create($tmp)
    try {
        $buf = New-Object byte[] (4MB)
        foreach ($part in $f.parts) {
            $in = [IO.File]::OpenRead((Join-Path $Root $part))
            try {
                while (($read = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $read)
                    [void]$sha.TransformBlock($buf, 0, $read, $null, 0)
                }
            } finally { $in.Dispose() }
        }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
    } finally { $out.Dispose() }
    $hash = -join ($sha.Hash | ForEach-Object { $_.ToString('X2') })
    $size = (Get-Item -LiteralPath $tmp).Length
    if ($size -ne $f.size -or $hash -ne $f.sha256) {
        Remove-Item -LiteralPath $tmp -Force
        throw "$($f.dest): size $size / SHA-256 $hash does not match the manifest ($($f.size) / $($f.sha256)). The USB copy is damaged; nothing was written."
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
}

# The build reads the curated drivers from <work>\DriverExport\_Curated.
$zip = Join-Path $workRoot 'DriverExport.zip'
$driverExport = Join-Path $workRoot 'DriverExport'
if ((Test-Path $zip) -and -not (Test-Path (Join-Path $driverExport '_Curated'))) {
    Write-Host "Extracting $zip to $driverExport"
    # No _Curated means no complete extract: clear a half-done one (ExtractToDirectory won't overwrite)
    if (Test-Path $driverExport) { Remove-Item $driverExport -Recurse -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $workRoot)   # the archive holds the folder DriverExport\
}

Write-Host ''
Write-Host 'All build inputs restored and verified.' -ForegroundColor Green

# --- 3. Git: the kit comes back from its git bundle -----------------------------------------
# Only on request: restoring the build inputs is the step where you choose to build again.
$gitExe = @((Get-Command git.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\Git\cmd\git.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$tools = Join-Path $Root 'Install-BuildTools.ps1'
$pins = Join-Path $Root 'installers.json'
if (-not $gitExe -and $kitState -eq 'new' -and $isAdmin -and (Test-Path $tools) -and (Test-Path $pins)) {
    Write-Host ''
    if ((Read-Host "Git for Windows is needed to get the kit back. Install it now from $workRoot\installers? [Y/n]") -notmatch '^\s*n') {
        $sb = [scriptblock]::Create((Get-Content -Raw -LiteralPath $tools))
        $r = @(& $sb -Tools git -Config $pins -WorkRoot $workRoot -PassThru)
        if ($r.Count -and $r[0].State -in 'INSTALLED', 'OK') {
            $gitExe = $r[0].Path
            Write-Host "Git for Windows installed: $gitExe" -ForegroundColor Green
        } else { Write-Host "Git was not installed: $($r[0].Detail)" -ForegroundColor Yellow }
    }
}

# --- 4. The kit, checked out into the folder that already holds work\ ------------------------
$bundleRel = 'work\kit\w11kit.bundle'
$bundle = Join-Path $KitRoot $bundleRel
$bundleEntry = @($manifest.files | Where-Object { $_.dest -eq $bundleRel })[0]
Write-Host ''
if ($kitState -eq 'clone') {
    Write-Host "$KitRoot is already a Git clone: left as it is (its commits and your changes are not touched)." -ForegroundColor Yellow
    Write-Host "  To take the kit this ISO was built from:  git -C `"$KitRoot`" pull `"$bundle`""
    Write-Host "  (No files next to its .git folder? An earlier restore was interrupted:  git -C `"$KitRoot`" reset --hard)"
} elseif (-not $gitExe) {
    Write-Host 'The kit is not checked out yet: Git for Windows is missing.' -ForegroundColor Yellow
    Write-Host "  Install it (the Git-*.exe in $workRoot\installers: check its signature first), then run"
    Write-Host '  Restore-BuildInputs.cmd again: it skips the files that are in place and checks the kit out.'
} elseif (-not $bundleEntry -or -not (Test-Path -LiteralPath $bundle)) {
    Write-Host "No kit bundle ($bundleRel) in these build inputs: get the kit from its repository (git clone <url>) into another folder." -ForegroundColor Yellow
} else {
    # The bundle again, right before it is used (it was verified when it was restored)
    if ((Get-Sha256 $bundle) -ne $bundleEntry.sha256) { throw "$bundle changed since it was restored (SHA-256 mismatch): run Restore-BuildInputs.cmd again." }
    Write-Host "Checking the kit out into $KitRoot"
    $tmpClone = Join-Path $workRoot 'kit\clone.tmp'
    if (Test-Path -LiteralPath $tmpClone) { Remove-Item -LiteralPath $tmpClone -Recurse -Force }   # an interrupted earlier run
    # 'git clone' picks the branch the bundle's HEAD names, records 'origin' and its branches:
    # everything a clone has, without files. Then its .git moves next to work\ (a rename).
    if ((Invoke-Git clone --quiet --no-checkout $bundle $tmpClone) -ne 0) { throw "git clone of $bundle failed (see above). The build inputs are in place: run Restore-BuildInputs.cmd again." }
    [IO.Directory]::Move((Join-Path $tmpClone '.git'), (Join-Path $KitRoot '.git'))
    Remove-Item -LiteralPath $tmpClone -Recurse -Force
    # safe.directory for this one call: the .git made a moment ago, in a folder that may
    # belong to another account (elevated git refuses a repository owned by someone else)
    $safe = 'safe.directory=' + ($KitRoot -replace '\\', '/')
    if ((Invoke-Git -c $safe -C $KitRoot reset --quiet --hard) -ne 0) { throw "The kit's .git folder is in $KitRoot, but checking its files out failed (see above). Run:  git -C `"$KitRoot`" reset --hard" }
    $kitState = 'restored'
    Write-Host "The kit is in $KitRoot (a Git clone; 'origin' is the bundle)." -ForegroundColor Green
}

# --- 5. Your own files that weren't in the kit's commits -------------------------------------
# (settings.local.json, source-iso.local.json, uncommitted profiles)
$localFiles = @($manifest.localFiles | Where-Object { $_ })
$localRoot = Join-Path $workRoot 'kit\local'
$localPending = $false
if ($localFiles.Count) {
    if ($kitState -in 'clone', 'restored') {
        foreach ($r in $localFiles) {
            if ("$r" -match '(^|\\)\.\.(\\|$)|^\\|:') { continue }   # kit-relative paths only
            $src = Join-Path $localRoot $r; $dst = Join-Path $KitRoot $r
            if (-not (Test-Path -LiteralPath $src)) { continue }
            if ((Test-Path -LiteralPath $dst) -and (Get-Sha256 $dst) -ne (Get-Sha256 $src)) {
                Write-Host "Kept $dst (it differs from the one in the build inputs: $src)" -ForegroundColor Yellow
                continue
            }
            New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            Copy-Item -LiteralPath $src -Destination $dst -Force
            Write-Host "Your file restored: $dst"
        }
    } else { $localPending = $true }
}

Write-Host ''
if ($kitState -in 'clone', 'restored') {
    Write-Host 'Next, in a new administrator terminal (new, so it sees Git; administrator, because only administrators can change the kit folder):'
    if ($kitState -eq 'restored') { Write-Host "  git -C `"$KitRoot`" remote set-url origin <your-remote>     point the kit at your own repository" }
    Write-Host "  $KitRoot\Run-Prepare.cmd     installs the build tools (Python, Windows ADK) and checks the PC"
    Write-Host '(or just start Run-Build.cmd: it offers to install them). docs\reference\BUILD-OPTIONS.md, "Run-Prepare.cmd".'
    if (@($manifest.files | Where-Object { "$($_.dest)" -like 'work\baselines\*.zip' }).Count) { Write-Host "Microsoft's security baseline zips are in $workRoot\baselines: the build imports them itself (it needs Python 3, one of the build tools)." }
    Write-Host "Everything the kit downloads or makes is in $workRoot."
} elseif ($localPending) {
    Write-Host "Your own files the build carried ($($localFiles -join ', ')) are put back when the kit is checked out (run this again with Git installed)."
}
