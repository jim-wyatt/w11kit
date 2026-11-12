<#
.SYNOPSIS
    Installs the build chain (the tools a PC needs to build the ISO) on demand.
    Run elevated. Idempotent: a tool that is already there is left alone.

.DESCRIPTION
    The build chain is never part of the image: a normal install has none of it.
    It is installed only when you want to build, by Run-Prepare.cmd (which asks
    first) or by Run-Build.cmd when a tool is missing (it asks too).

      git      Git for Windows      the build bundles the kit into the ISO
      python   Python 3             the build imports the security baselines with it;
                                    the download scripts (scripts\Get-*.py)
      adk      Windows ADK          only the Deployment Tools (oscdimg, writes the ISO)
               Deployment Tools
      hyperv   Hyper-V              only for the VM test (Run-VmTest.cmd); needs a restart

    Default: git, python, adk. Hyper-V only with -IncludeHyperV or -Tools hyperv.

    For each missing tool it takes the installer pinned in config\installers.json:
    first from <WorkRoot>\installers (C:\W11Kit\work\installers: where
    Restore-BuildInputs puts the ones the ISO carries; the ADK's web installer from
    <WorkRoot>\tools), else downloaded
    from the official URL. It checks the SHA-256, copies the file to a private
    temp folder, checks the SHA-256 again and the Authenticode signature (Valid,
    signed by exactly the pinned signer), installs silently for all users, then
    re-checks and prints a table. Never winget: winget can't run elevated under
    Administrator protection.

    Exit code (without -PassThru): 0 every requested tool is there, 3010 the same
    after a restart (Hyper-V), 2 something is missing (-Check), 1 an install failed.

.PARAMETER Tools
    Which tools: git, python, adk, hyperv (default git, python, adk).
.PARAMETER IncludeHyperV
    Add hyperv to the default set.
.PARAMETER Check
    Report only: change nothing (works without elevation; Hyper-V then shows as unknown).
.PARAMETER PassThru
    Return the result rows instead of printing the table and exiting (for Prepare-BuildPc.ps1).
.PARAMETER WorkRoot
    The build's work folder (installers in <WorkRoot>\installers, logs in <WorkRoot>\logs).
    Default <KitRoot>\work.
.PARAMETER Config
    The pin file. Default <KitRoot>\config\installers.json.
.PARAMETER KitRoot
    The kit folder. Needed when loaded as a scriptblock ($PSScriptRoot empty).
#>
[CmdletBinding()]
param(
    [ValidateSet('git', 'python', 'adk', 'hyperv')]
    [string[]]$Tools,
    [switch]$IncludeHyperV,
    [switch]$Check,
    [switch]$PassThru,
    [string]$WorkRoot,   # default: <KitRoot>\work
    [string]$Config,
    [string]$KitRoot
)

$ErrorActionPreference = 'Stop'
if (-not $KitRoot -and $PSScriptRoot) { $KitRoot = Split-Path -Parent $PSScriptRoot }
if (-not $Config) {
    if (-not $KitRoot) { throw 'Pass -KitRoot (or -Config) when loading this script as a scriptblock.' }
    $Config = Join-Path "$KitRoot".TrimEnd('\') 'config\installers.json'
}
if (-not $WorkRoot) {
    if (-not $KitRoot) { throw 'Pass -KitRoot (or -WorkRoot) when loading this script as a scriptblock.' }
    $WorkRoot = Join-Path "$KitRoot".TrimEnd('\') 'work'
}
if (-not $Tools) { $Tools = @('git', 'python', 'adk') }
if ($IncludeHyperV -and $Tools -notcontains 'hyperv') { $Tools = @($Tools) + 'hyperv' }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Check) { throw 'Installing the build tools needs elevation: use Run-Prepare.cmd, or add -Check to only report.' }

$cfg = Get-Content -Raw -LiteralPath $Config | ConvertFrom-Json
$pins = @{}
foreach ($p in @($cfg.installers) + @($cfg.adk)) { if ($p -and $p.tool) { $pins[$p.tool] = $p } }
$names = @{ git = 'Git for Windows'; python = 'Python 3'; adk = 'Windows ADK Deployment Tools'; hyperv = 'Hyper-V' }
$installerDir = Join-Path $WorkRoot 'installers'
$logDir = Join-Path $WorkRoot 'logs'

# A work folder this script creates is writable by administrators only from the start, like
# the build makes it (scripts\KitAcl.ps1): the elevated build runs and packs what is in it.
function Initialize-WorkRoot {
    if (Test-Path -LiteralPath $WorkRoot) { return }
    if ($KitRoot -and (Test-Path -LiteralPath (Join-Path "$KitRoot".TrimEnd('\') 'scripts\KitAcl.ps1'))) {
        . ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path "$KitRoot".TrimEnd('\') 'scripts\KitAcl.ps1'))))
        New-KitLockedFolder $WorkRoot
    }
}

# Native tools: a local 'Continue' (stderr would be terminating under 'Stop' in PS 5.1); first line of output
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return "$(@($out)[0])".Trim()
    } catch { return $null } finally { $ErrorActionPreference = $old }
}

function Update-ProcessPath {
    # New installs add to the Machine/User PATH in the registry; this process still has the old one.
    $env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) |
        Where-Object { $_ }) -join ';'
}

function Find-Oscdimg {
    # The same search as the build: a copy restored from an ISO's BuildInputs, then the ADK, then PATH;
    # each only if validly signed by exactly the ADK's pinned signer (config\installers.json 'adk').
    $signer = "$(if ($pins['adk'].signer) { $pins['adk'].signer } else { 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' })"
    $local = Join-Path $WorkRoot 'tools\Oscdimg\oscdimg.exe'
    $c = @($local,
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        (Get-Command oscdimg.exe -ErrorAction SilentlyContinue).Source) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($x in $c) {
        $sig = Get-AuthenticodeSignature -LiteralPath $x
        if ($sig.Status -eq 'Valid' -and "$($sig.SignerCertificate.Subject)" -ceq $signer) { return $x }
        Write-Warning "Ignoring ${x}: not validly signed by '$signer' (status $($sig.Status), signer '$($sig.SignerCertificate.Subject)')."
    }
    return $null
}

# State of one tool: Present = $true / $false / $null (unknown), Available = can it be installed here
function Get-ToolState([string]$Tool) {
    $s = [pscustomobject]@{ Tool = $Tool; Name = $names[$Tool]; Present = $false; Available = $true; Version = ''; Path = ''; Detail = ''; Restart = $false }
    switch ($Tool) {
        'git' {
            $exe = @((Get-Command git.exe -ErrorAction SilentlyContinue).Source, "$env:ProgramFiles\Git\cmd\git.exe") |
                Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
            if ($exe) {
                $v = Invoke-Native $exe @('--version')
                if ($v) { $s.Present = $true; $s.Path = $exe; $s.Version = $v -replace '^git version\s*', '' }
                else { $s.Detail = "$exe does not run" }
            }
        }
        'python' {
            # The scripts need 3.8+ (they use :=). The WindowsApps python.exe is only a Store stub.
            $cands = New-Object System.Collections.Generic.List[string]
            foreach ($n in 'python.exe', 'py.exe') {
                foreach ($c in @(Get-Command $n -All -ErrorAction SilentlyContinue)) { if ($c.Source -notmatch '\\WindowsApps\\') { $cands.Add($c.Source) } }
            }
            foreach ($d in @(Get-ChildItem "$env:ProgramFiles\Python3*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
                $cands.Add((Join-Path $d.FullName 'python.exe'))
            }
            foreach ($exe in $cands) {
                if (-not (Test-Path -LiteralPath $exe)) { continue }
                $a = @('-c', 'import sys;print(sys.version.split()[0])')
                if ((Split-Path $exe -Leaf) -eq 'py.exe') { $a = @('-3') + $a }
                $v = Invoke-Native $exe $a
                if ($v -match '^3\.(\d+)' -and [int]$Matches[1] -ge 8) { $s.Present = $true; $s.Path = $exe; $s.Version = $v; break }
                if ($v) { $s.Detail = "$exe is Python $v (need 3.8 or later)" }
            }
        }
        'adk' {
            $osc = Find-Oscdimg
            if ($osc) {
                $s.Present = $true; $s.Path = $osc
                $s.Version = "$((Get-Item -LiteralPath $osc).VersionInfo.ProductVersion)".Trim()
            }
        }
        'hyperv' {
            if (-not $isAdmin) { $s.Present = $null; $s.Detail = 'state unknown (needs elevation to query)'; break }
            $f = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction SilentlyContinue
            if (-not $f) { $s.Available = $false; $s.Detail = 'not available on this Windows edition (Windows 11 Home has no Hyper-V): the VM test needs Pro, Enterprise or Education'; break }
            switch ("$($f.State)") {
                # Before the restart Windows can already report Enabled: the service then doesn't exist yet
                'Enabled' { $s.Present = $true; $s.Version = 'enabled'; if (-not (Get-Service vmms -ErrorAction SilentlyContinue)) { $s.Restart = $true; $s.Detail = 'restart Windows to finish' } }
                'EnablePending' { $s.Present = $true; $s.Version = 'enabled'; $s.Restart = $true; $s.Detail = 'restart Windows to finish' }
                default {
                    $s.Detail = "state $($f.State)"
                    $cs = Get-CimInstance Win32_ComputerSystem
                    $cpu = @(Get-CimInstance Win32_Processor)[0]
                    # A running hypervisor makes VirtualizationFirmwareEnabled read False: it still proves virtualization is on
                    if (-not ([bool]$cs.HypervisorPresent -or [bool]$cpu.VirtualizationFirmwareEnabled)) {
                        $s.Available = $false; $s.Detail = 'virtualization is off in the firmware: turn it on in the BIOS (AMD: SVM Mode; Intel: VT-x), then run this again'
                    }
                }
            }
        }
    }
    $s
}

function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpper() }

# The pinned installer, verified, in a private folder only this (elevated) account can write to.
# Returns the path of the private copy; the caller deletes its folder.
function Get-VerifiedInstaller($Pin) {
    $want = "$($Pin.sha256)".ToUpper()
    $cache = if ($Pin.tool -eq 'adk') { Join-Path $WorkRoot 'tools' } else { $installerDir }
    $found = @((Join-Path $cache $Pin.file), (Join-Path $installerDir $Pin.file)) |
        Where-Object { (Test-Path -LiteralPath $_) -and (Get-Sha256 $_) -eq $want } | Select-Object -First 1
    if ($found) { Write-Host "    using $found (SHA-256 OK)" }
    else {
        $found = Join-Path $cache $Pin.file
        Initialize-WorkRoot
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Write-Host "    downloading $($Pin.url)"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $part = "$found.part"
        $oldPref = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'   # PS 5.1's progress bar slows downloads a lot
        try { Invoke-WebRequest -UseBasicParsing -Uri $Pin.url -OutFile $part } finally { $ProgressPreference = $oldPref }
        $got = Get-Sha256 $part
        if ($got -ne $want) {
            Remove-Item -LiteralPath $part -Force
            throw "$($Pin.file): SHA-256 $got does not match the pinned $want (config\installers.json). Deleted, not run."
        }
        Move-Item -LiteralPath $part -Destination $found -Force
    }
    # Check the copy that runs, not the cached one (the work folder may not be locked yet: the build locks it).
    $priv = Join-Path $env:TEMP ('w11kit-tools-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $priv -Force | Out-Null
    $exe = Join-Path $priv $Pin.file
    try {
        Copy-Item -LiteralPath $found -Destination $exe
        if ((Get-Sha256 $exe) -ne $want) { throw "$($Pin.file): SHA-256 changed while copying. Not run." }
        $sig = Get-AuthenticodeSignature -LiteralPath $exe
        $subject = "$($sig.SignerCertificate.Subject)"
        if ($sig.Status -ne 'Valid') { throw "$($Pin.file): Authenticode signature is $($sig.Status) ($($sig.StatusMessage)). Not run." }
        if ($subject -ne $Pin.signer) { throw "$($Pin.file): signed by '$subject', expected '$($Pin.signer)' (config\installers.json). Not run." }
    } catch {
        Remove-Item -LiteralPath $priv -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    Write-Host "    signature Valid: $subject"
    return $exe
}

function Install-Tool([string]$Tool) {
    if ($Tool -eq 'hyperv') {
        Write-Host '    enabling Microsoft-Hyper-V-All (no restart now)'
        $r = Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -All -NoRestart
        return [bool]$r.RestartNeeded
    }
    $pin = $pins[$Tool]
    if (-not $pin) { throw "No pin for '$Tool' in $Config." }
    Initialize-WorkRoot
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $log = Join-Path $logDir ("install-{0}-{1}.log" -f $Tool, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $exe = Get-VerifiedInstaller $pin
    try {
        $argList = switch ($Tool) {
            'git' { '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES', '/ALLUSERS', "/LOG=`"$log`"" }
            'python' { '/quiet', 'InstallAllUsers=1', 'PrependPath=1', 'Include_test=0', '/log', "`"$log`"" }
            'adk' { '/quiet', '/norestart', '/ceip', 'off', '/features', 'OptionId.DeploymentTools', '/log', "`"$log`"" }
        }
        Write-Host "    installing $($pin.name) $($pin.version) (silent, for all users$(if ($Tool -eq 'adk') { '; the ADK installer downloads about 100 MB' })); log: $log"
        $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru
        if ($p.ExitCode -notin 0, 3010) { throw "$($pin.name) setup ended with exit code $($p.ExitCode). Log: $log" }
        return ($p.ExitCode -eq 3010)
    } finally {
        Remove-Item -LiteralPath (Split-Path $exe) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Check, install what is missing, check again -----------------------------------------
if (-not $PassThru) { Write-Host "Build tools: $($Tools -join ', ')$(if ($Check) { ' (-Check: report only, nothing is changed)' })" }
$rows = New-Object System.Collections.Generic.List[object]
foreach ($t in $Tools) {
    $s = Get-ToolState $t
    $state = if ($s.Present -eq $true) { 'OK' } elseif ($null -eq $s.Present) { 'UNKNOWN' } elseif (-not $s.Available) { 'N/A' } else { 'MISSING' }
    if ($state -eq 'MISSING' -and -not $Check) {
        Write-Host "  $($s.Name): not installed"
        try {
            $restartNeeded = Install-Tool $t
            Update-ProcessPath
            $s = Get-ToolState $t
            if ($restartNeeded) { $s.Restart = $true }
            if ($s.Present -eq $true) { $state = 'INSTALLED' }
            else { $state = 'FAILED'; $s.Detail = 'installed, but still not found' + $(if ($s.Detail) { ": $($s.Detail)" }) }
        } catch {
            $state = 'FAILED'; $s.Detail = $_.Exception.Message
        }
    }
    $rows.Add([pscustomobject]@{
        Tool = $s.Tool; Name = $s.Name; State = $state; Version = $s.Version; Path = $s.Path
        Restart = [bool]$s.Restart; Detail = $s.Detail
        Pinned = $(if ($pins[$t]) { "$($pins[$t].version)" } else { '' })
    })
}

if ($PassThru) { return $rows.ToArray() }

Write-Host ''
$rows | Format-Table -AutoSize -Wrap Name, State, Version, @{ n = 'Where / note'; e = { if ($_.Detail) { $_.Detail } else { $_.Path } } } | Out-String -Width 160 | Write-Host
$failed = @($rows | Where-Object State -eq 'FAILED')
$missing = @($rows | Where-Object State -in 'MISSING', 'N/A')
if ($failed.Count) { Write-Host "FAILED: $(($failed | ForEach-Object Name) -join ', ') (see above)." -ForegroundColor Red; exit 1 }
if ($missing.Count) { Write-Host "Missing: $(($missing | ForEach-Object Name) -join ', '). Run-Prepare.cmd installs them." -ForegroundColor Yellow; exit 2 }
if (@($rows | Where-Object Restart).Count) { Write-Host 'Ready after a restart: restart Windows to finish (Hyper-V).' -ForegroundColor Yellow; exit 3010 }
Write-Host 'All requested build tools are installed.' -ForegroundColor Green
exit 0
