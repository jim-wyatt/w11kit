<#
.SYNOPSIS
    Updates a kit clone to its newest signed release, and only to a release signed by a key
    the kit already trusts. Dot-sourced by Invoke-KitLauncher.ps1 (Run-Build.cmd's first
    question), as a scriptblock like every kit script.

.DESCRIPTION
    Update-KitToSignedRelease -KitRoot <clone> -GitExe <git.exe>:
      1. copies config\release-signers (the allowed_signers list of the release keys) out of
         the clone BEFORE anything is fetched: the list that decides is the one this kit
         came with, never one a new release brings along;
      2. fetches the tags from origin (an existing tag is never overwritten);
      3. takes the newest tag named v<version> (git's version sort);
      4. git verify-tag against the copied list: a tag that is unsigned, or signed by any
         other key, is refused, and the clone stays as it is;
      5. checks the tag out (detached HEAD: the kit is then exactly that release).
    Returns an object: Result (Updated, Current, NoRelease, Refused, Failed), Tag, Message.
    Git 2.34 or newer verifies SSH signatures; Git for Windows brings ssh-keygen with it.
    What it proves: the release was signed by a key in this kit's list. Whether that list is
    the project's: compare its key with the one shown in SECURITY.md on the project's page.
#>

function Update-KitToSignedRelease([string]$KitRoot, [string]$GitExe) {
    $res = { param($r, $t, $m) [pscustomobject]@{ Result = $r; Tag = $t; Message = $m } }
    # Native git under 'Continue': its progress and warnings go to stderr
    $git = {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = @(& $GitExe -C $KitRoot @args 2>&1 | ForEach-Object { "$_" }); [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out } }
        finally { $ErrorActionPreference = $old }
    }
    $signers = Join-Path $KitRoot 'config\release-signers'
    if (-not (Test-Path -LiteralPath $signers -PathType Leaf)) {
        return (& $res 'Failed' $null 'This kit has no list of release keys (config\release-signers), so no update can be checked. Get the newest release from the project page (docs\GUIDE.md, step 2).')
    }
    $trusted = Join-Path ([IO.Path]::GetTempPath()) ('w11kit-signers-' + [guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $signers -Destination $trusted -ErrorAction Stop
        $f = & $git fetch --quiet --tags origin
        if ($f.Code -ne 0) { return (& $res 'Failed' $null "git fetch failed (exit code $($f.Code)): $($f.Out -join ' ')") }
        $tags = @((& $git tag --list 'v*' --sort=-v:refname).Out | Where-Object { $_ -match '^v\d+\.\d+\.\d+' })
        if (-not $tags.Count) { return (& $res 'NoRelease' $null 'The project has no release yet (no tag v<version> on origin).') }
        $newest = $tags[0]
        $here = (& $git describe --tags --exact-match HEAD).Out | Select-Object -First 1
        if ("$here" -eq $newest) { return (& $res 'Current' $newest "The kit is the newest release already ($newest).") }
        $v = & $git -c "gpg.ssh.allowedSignersFile=$trusted" verify-tag $newest
        if ($v.Code -ne 0) {
            return (& $res 'Refused' $newest "$newest is not signed by a key this kit trusts (config\release-signers): not installed, the kit stays as it is. git verify-tag: $(($v.Out | Select-Object -Last 2) -join ' ')")
        }
        $c = & $git -c advice.detachedHead=false checkout --quiet $newest
        if ($c.Code -ne 0) { return (& $res 'Failed' $newest "Signature good, but git checkout $newest failed (exit code $($c.Code)): $($c.Out -join ' ') (changed files in the kit folder? git -C $KitRoot status shows them)") }
        & $res 'Updated' $newest "Updated to $newest, signed by a key in config\release-signers: $(($v.Out | Where-Object { $_ -match 'Good' } | Select-Object -First 1))"
    } finally { Remove-Item -LiteralPath $trusted -Force -ErrorAction SilentlyContinue }
}
