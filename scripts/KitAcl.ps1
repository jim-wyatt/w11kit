<#
.SYNOPSIS
    Locks the build's folders (the kit, its work folder <kit>\work, the driver export
    in it) so that only administrators can change them, and checks that they are
    locked. Dot-sourced by Build-Iso.ps1, Install-BuildTools.ps1,
    Invoke-DriverHarvest.ps1, Invoke-KitLauncher.ps1 and Test-IsoInHyperV.ps1 (as a
    scriptblock, like every kit script).

.DESCRIPTION
    The build runs elevated and executes, applies or packs what is in these folders.
    Inherited from C:\ they are writable by every signed-in user, so a standard user
    (or malware in the daily account) could change what the elevated build runs or
    puts into the image. The lock:

      owner     BUILTIN\Administrators
      folder    protected DACL: SYSTEM Full, Administrators Full, BUILTIN\Users Read & Execute
                (all three inherited by everything below)
      below     every file and folder: owner Administrators, only the three inherited entries
                (explicit entries removed: no Authenticated Users / Everyone / user write)

    How (not icacls /T, not Set-Acl): one walk from the top down that opens each item by
    handle WITHOUT following links (FILE_FLAG_OPEN_REPARSE_POINT) and writes its security
    descriptor on that handle (no automatic propagation). A folder is locked BEFORE its
    contents are listed, so nothing new can appear in it during the walk. A junction or
    symbolic link anywhere below is never followed or changed: it is reported and the
    lock fails (a link planted there could otherwise point the elevated build, or the
    lock itself, at any folder on the PC). Mounted Windows images (DISM) are refused
    the same way: discard them first.

    Every item is then read back and checked by SID (not by name): its owner is SYSTEM,
    Administrators, TrustedInstaller or a member of the local Administrators group, it
    has a DACL, and no allow entry grants a write, delete, change-permissions or
    take-ownership right to any other SID.

    Folders inside folders (the work folder is <kit>\work by default, and the driver
    export is in it): Get-KitLockPlan turns the list of paths into one walk per path,
    from the outside in. Each is locked as a root of its own (protected DACL), and a
    walk does not enter a path that has its own walk (-SkipDirs), so nothing is walked
    twice and the kit's walk never goes into the work folder, where a build's mounted
    image may be. A skipped path that is a junction or link is still reported by the
    outer walk (links are checked when a folder is listed, before the skip), and a
    path that isn't matched by -SkipDirs (another spelling of it) is simply walked by
    both: never left out.

    What the lock can't cover is the folder ABOVE a locked folder: whoever may change
    that one (its owner, or an account with delete, delete-child or change-permissions
    rights on it) can move the locked folder aside and put another in its place.
    Directly under C:\ (C:\W11Kit) that is administrators only. Test-KitPathParents
    reports it for any other place (the build prints it as a warning).

    Lock-KitPath -NoOwner leaves owners alone (a non-elevated test can't set them).
#>

$kitAclType = 'W11Kit.FolderLock2'
if (-not ($kitAclType -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace W11Kit {
public static class FolderLock2 {
    const uint READ_CONTROL = 0x20000, WRITE_DAC = 0x40000, WRITE_OWNER = 0x80000, FILE_READ_ATTRIBUTES = 0x80;
    const uint FILE_SHARE_ALL = 7, OPEN_EXISTING = 3;
    const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000, FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    const uint OWNER_INFO = 1, DACL_INFO = 4;
    const uint ATTR_DIRECTORY = 0x10, ATTR_REPARSE = 0x400;
    // Write data/append/EA/delete child/attributes, DELETE, WRITE_DAC, WRITE_OWNER, GENERIC_ALL, GENERIC_WRITE
    public const int WriteMask = 0x2 | 0x4 | 0x10 | 0x40 | 0x100 | 0x10000 | 0x40000 | 0x80000 | 0x10000000 | 0x40000000;

    // SYSTEM, Administrators, Users. Read & Execute = 0x1200a9.
    const string RootDir   = "D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)";
    const string RootFile  = "D:PAI(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200a9;;;BU)";
    const string ChildDir  = "D:AI(A;OICIID;FA;;;SY)(A;OICIID;FA;;;BA)(A;OICIID;0x1200a9;;;BU)";
    const string ChildFile = "D:AI(A;ID;FA;;;SY)(A;ID;FA;;;BA)(A;ID;0x1200a9;;;BU)";

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool SetKernelObjectSecurity(SafeFileHandle h, uint info, byte[] sd);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool GetKernelObjectSecurity(SafeFileHandle h, uint info, byte[] sd, uint len, out uint needed);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle h, out FileInfo info);
    [StructLayout(LayoutKind.Sequential)]
    struct FileInfo { public uint Attributes, C1, C2, A1, A2, W1, W2, Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct FindData {
        public uint Attributes, C1, C2, A1, A2, W1, W2, SizeHigh, SizeLow, Reserved0, Reserved1;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AltName;
    }
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr FindFirstFileW(string name, out FindData data);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool FindNextFileW(IntPtr h, out FindData data);
    [DllImport("kernel32.dll")]
    static extern bool FindClose(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct Luid { public uint Low; public int High; }
    [StructLayout(LayoutKind.Sequential)]
    struct TokenPrivilege { public uint Count; public Luid Luid; public uint Attributes; }
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool LookupPrivilegeValueW(string system, string name, out Luid luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivilege state, uint len, ref TokenPrivilege previous, out uint returned);

    static string Long(string p) {
        if (p.StartsWith(@"\\?\")) return p;
        if (p.StartsWith(@"\\")) return @"\\?\UNC\" + p.Substring(2);
        return @"\\?\" + p;
    }

    // Enables the named privileges (if held) and returns what to undo.
    static List<TokenPrivilege> Enable(string[] names) {
        var undo = new List<TokenPrivilege>();
        IntPtr tok;
        if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return undo;   // ADJUST_PRIVILEGES | QUERY
        try {
            foreach (string n in names) {
                Luid l;
                if (!LookupPrivilegeValueW(null, n, out l)) continue;
                var s = new TokenPrivilege { Count = 1, Luid = l, Attributes = 2 };   // SE_PRIVILEGE_ENABLED
                var prev = new TokenPrivilege();
                uint ret;
                if (AdjustTokenPrivileges(tok, false, ref s, (uint)Marshal.SizeOf(typeof(TokenPrivilege)), ref prev, out ret)
                    && Marshal.GetLastWin32Error() == 0 && prev.Count == 1) undo.Add(prev);
            }
        } finally { CloseHandle(tok); }
        return undo;
    }
    static void Undo(List<TokenPrivilege> undo) {
        IntPtr tok;
        if (undo.Count == 0 || !OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return;
        try {
            foreach (var p in undo) {
                var s = p; var prev = new TokenPrivilege(); uint ret;
                AdjustTokenPrivileges(tok, false, ref s, (uint)Marshal.SizeOf(typeof(TokenPrivilege)), ref prev, out ret);
            }
        } finally { CloseHandle(tok); }
    }

    static byte[] Sd(string sddl, bool owner) {
        var sd = new RawSecurityDescriptor((owner ? "O:BA" : "") + sddl);
        var b = new byte[sd.BinaryLength];
        sd.GetBinaryForm(b, 0);
        return b;
    }

    static string Name(SecurityIdentifier sid) {
        try { return sid.Translate(typeof(NTAccount)).Value + " (" + sid.Value + ")"; } catch { return sid.Value; }
    }

    // Problems of one item's owner and DACL, by SID.
    static void Check(SafeFileHandle h, string path, HashSet<string> okSids, List<string> problems) {
        uint need;
        GetKernelObjectSecurity(h, OWNER_INFO | DACL_INFO, null, 0, out need);
        if (need == 0) { problems.Add(path + ": security not readable (error " + Marshal.GetLastWin32Error() + ")"); return; }
        var buf = new byte[need];
        if (!GetKernelObjectSecurity(h, OWNER_INFO | DACL_INFO, buf, need, out need)) { problems.Add(path + ": security not readable (error " + Marshal.GetLastWin32Error() + ")"); return; }
        var sd = new RawSecurityDescriptor(buf, 0);
        if (sd.Owner == null || !okSids.Contains(sd.Owner.Value)) problems.Add(path + ": owner " + (sd.Owner == null ? "(none)" : Name(sd.Owner)) + " is not an administrator");
        if (sd.DiscretionaryAcl == null) { problems.Add(path + ": no DACL (everyone has full access)"); return; }
        foreach (GenericAce ace in sd.DiscretionaryAcl) {
            var k = ace as KnownAce;
            if (k == null) continue;
            bool allow = ace.AceType == AceType.AccessAllowed || ace.AceType == AceType.AccessAllowedObject
                      || ace.AceType == AceType.AccessAllowedCallback || ace.AceType == AceType.AccessAllowedCallbackObject;
            if (allow && (k.AccessMask & WriteMask) != 0 && !okSids.Contains(k.SecurityIdentifier.Value))
                problems.Add(string.Format("{0}: {1} may write (rights 0x{2:X}{3})", path, Name(k.SecurityIdentifier), k.AccessMask,
                    (ace.AceFlags & AceFlags.InheritOnly) != 0 ? ", for new items inside" : ""));
        }
    }

    // fix=false: check only. setOwner=false: leave owners (a non-elevated test can't set them).
    // okSids: owners and writers that are fine (SYSTEM, Administrators, TrustedInstaller, admin members).
    // refuseDirs: full paths never to enter (mounted images): reported as problems.
    // skipDirs: full paths below 'path' that are left alone without a word, because the
    // caller locks each as a root of its own (the work folder inside the kit folder). Only
    // the item itself decides: it is skipped after its parent's listing has refused it if
    // it is a link, and 'path' itself is never skipped.
    // Returns the problems (empty = locked); at most maxReport are listed, then a count.
    public static List<string> Run(string path, bool fix, bool setOwner, string[] okSids, string[] refuseDirs, string[] skipDirs, int maxReport) {
        var all = new List<string>();
        var ok = new HashSet<string>(okSids, StringComparer.OrdinalIgnoreCase);
        var refuse = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string r in refuseDirs ?? new string[0]) refuse.Add(Path.GetFullPath(r).TrimEnd('\\'));
        var skip = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string k in skipDirs ?? new string[0]) skip.Add(Path.GetFullPath(k).TrimEnd('\\'));
        string root = Path.GetFullPath(path).TrimEnd('\\');
        var undo = fix ? Enable(new[] { "SeRestorePrivilege", "SeBackupPrivilege", "SeTakeOwnershipPrivilege" }) : new List<TokenPrivilege>();
        try {
            uint access = READ_CONTROL | FILE_READ_ATTRIBUTES | (fix ? WRITE_DAC | (setOwner ? WRITE_OWNER : 0) : 0);
            uint info = DACL_INFO | (setOwner ? OWNER_INFO : 0);
            var stack = new Stack<string>();
            stack.Push(root);
            while (stack.Count > 0) {
                string p = stack.Pop();
                bool isRoot = p == root;
                if (!isRoot && skip.Contains(p)) continue;   // locked by its own walk
                if (refuse.Contains(p)) { all.Add(p + ": a mounted Windows image: discard it first (dism /Cleanup-Mountpoints, or restart Windows)"); continue; }
                bool isDir;
                using (var h = CreateFileW(Long(p), access, FILE_SHARE_ALL, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero)) {
                    if (h.IsInvalid) { all.Add(p + ": cannot open (" + new Win32Exception(Marshal.GetLastWin32Error()).Message + ")"); continue; }
                    FileInfo fi;
                    if (!GetFileInformationByHandle(h, out fi)) { all.Add(p + ": cannot read its attributes"); continue; }
                    if ((fi.Attributes & ATTR_REPARSE) != 0) { all.Add(p + ": a junction or symbolic link (not followed, not changed): remove it"); continue; }
                    isDir = (fi.Attributes & ATTR_DIRECTORY) != 0;
                    if (fix) {
                        string sddl = isRoot ? (isDir ? RootDir : RootFile) : (isDir ? ChildDir : ChildFile);
                        if (!SetKernelObjectSecurity(h, info, Sd(sddl, setOwner))) { all.Add(p + ": cannot set its permissions (" + new Win32Exception(Marshal.GetLastWin32Error()).Message + ")"); continue; }
                    }
                    Check(h, p, ok, all);
                }
                if (!isDir) continue;
                FindData fd;
                IntPtr f = FindFirstFileW(Long(p) + @"\*", out fd);
                if (f == new IntPtr(-1)) {
                    int e = Marshal.GetLastWin32Error();
                    if (e != 2 && e != 18) all.Add(p + ": cannot list (" + new Win32Exception(e).Message + ")");
                    continue;
                }
                try {
                    do {
                        if (fd.Name == "." || fd.Name == "..") continue;
                        string c = p + "\\" + fd.Name;
                        if ((fd.Attributes & ATTR_REPARSE) != 0) { all.Add(c + ": a junction or symbolic link (not followed, not changed): remove it"); continue; }
                        stack.Push(c);
                    } while (FindNextFileW(f, out fd));
                } finally { FindClose(f); }
            }
        } finally { Undo(undo); }
        if (all.Count <= maxReport) return all;
        var shown = all.GetRange(0, maxReport);
        shown.Add(string.Format("... and {0} more", all.Count - maxReport));
        return shown;
    }
}
}
'@
}

# SIDs that may own and write the build's folders: SYSTEM, Administrators, TrustedInstaller,
# and the members of the local Administrators group (an elevated admin's new files are
# owned by that admin's own account, unless policy makes the group the owner).
function Get-KitAdminSids {
    $sids = New-Object System.Collections.Generic.List[string]
    foreach ($s in 'S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464') { $sids.Add($s) }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $sids.Add($me.User.Value) }
    try {
        # ADSI, not Get-LocalGroupMember (it fails on an orphaned member SID)
        $grp = [ADSI]'WinNT://./Administrators,group'
        foreach ($m in @($grp.psbase.Invoke('Members'))) {
            $bytes = $m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null)
            if ($bytes) { $sids.Add((New-Object Security.Principal.SecurityIdentifier ([byte[]]$bytes), 0).Value) }
        }
    } catch { }
    [string[]]@($sids | Sort-Object -Unique)
}

# Folders the lock must never touch: a drive root, Windows, Program Files, ProgramData,
# C:\Users and a user profile itself. Throws.
function Assert-KitLockablePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -notmatch '^[A-Za-z]:\\.') { throw "Won't lock '$Path': only a folder on a local drive (not a drive root or a network path). Copy the kit to a local folder such as C:\W11Kit." }
    $guard = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:SystemDrive 'Users')) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    foreach ($g in $guard) {
        if ($full -ieq $g -or $g.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Won't lock '$full': it is or contains $g." }
    }
    if ((Split-Path $full -Parent) -ieq (Join-Path $env:SystemDrive 'Users')) { throw "Won't lock '$full': it is a user profile folder. Use a folder of its own, such as C:\W11Kit." }
}

# Creates a missing folder already locked (no window with the inherited, user-writable ACL).
function New-KitLockedFolder([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return }
    Assert-KitLockablePath $Path
    $sec = New-Object Security.AccessControl.DirectorySecurity
    $sec.SetSecurityDescriptorSddlForm('O:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)')
    $null = [IO.Directory]::CreateDirectory($Path, $sec)
}

# Locks a folder (or one file) and everything in it, then checks it by SID. Returns the
# problems, one string each (none = locked; wrap the call in @()). -NoOwner: owners unchanged (non-elevated test).
# -SkipDirs: paths below it that have a walk of their own (Get-KitLockPlan): not entered here.
function Lock-KitPath([string]$Path, [switch]$NoOwner, [string[]]$RefuseDirs = @(), [string[]]$SkipDirs = @(), [int]$MaxReport = 20) {
    Assert-KitLockablePath $Path
    [W11Kit.FolderLock2]::Run($Path, $true, -not $NoOwner, (Get-KitAdminSids), $RefuseDirs, $SkipDirs, $MaxReport).ToArray()
}

# Checks only (no elevation needed, changes nothing). Returns the problems (none = locked).
function Test-KitPathLocked([string]$Path, [string[]]$RefuseDirs = @(), [string[]]$SkipDirs = @(), [int]$MaxReport = 20) {
    [W11Kit.FolderLock2]::Run($Path, $false, $false, (Get-KitAdminSids), $RefuseDirs, $SkipDirs, $MaxReport).ToArray()
}

# One walk per path, for paths that may lie inside each other (the work folder inside the
# kit folder, the driver export inside the work folder). Returns one object per distinct
# path, outer folders first: Path (full path) and SkipDirs (the other listed paths below
# it: each has its own walk, so this one does not enter them). A path that does not exist
# yet stays in the plan (and in SkipDirs): the caller leaves it out when it locks.
function Get-KitLockPlan([string[]]$Paths) {
    $full = New-Object System.Collections.Generic.List[string]
    foreach ($p in $Paths) {
        if (-not $p) { continue }
        $f = [IO.Path]::GetFullPath($p).TrimEnd('\')
        if (-not @($full | Where-Object { $_ -ieq $f }).Count) { $full.Add($f) }
    }
    # Outer before inner: a parent's path is shorter than anything below it
    foreach ($f in @($full | Sort-Object Length)) {
        $below = @($full | Where-Object { $_.StartsWith($f + '\', [StringComparison]::OrdinalIgnoreCase) })
        [pscustomobject]@{ Path = $f; SkipDirs = [string[]]$below }
    }
}

# The folders above a locked folder (not the drive root): each must belong to an
# administrator and give no one else the rights to replace what is in it (delete it or
# its children, change its permissions or owner). Otherwise that account could move the
# locked folder aside and put its own in its place. Read-only; returns one line per such
# folder (none = fine). A folder that can't be read is left out.
function Test-KitPathParents([string]$Path) {
    $ok = Get-KitAdminSids
    $replace = 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000   # delete child, DELETE, WRITE_DAC, WRITE_OWNER, GENERIC_ALL, GENERIC_WRITE
    $dir = Split-Path ([IO.Path]::GetFullPath($Path).TrimEnd('\')) -Parent
    while ($dir -and $dir -notmatch '^[A-Za-z]:\\?$' -and (Split-Path $dir -Parent)) {
        try {
            $sd = New-Object Security.AccessControl.RawSecurityDescriptor ((Get-Acl -LiteralPath $dir -ErrorAction Stop).Sddl)
            $who = New-Object System.Collections.Generic.List[string]
            if ($sd.Owner -and $ok -notcontains $sd.Owner.Value) { $who.Add("its owner $(try { $sd.Owner.Translate([Security.Principal.NTAccount]).Value } catch { $sd.Owner.Value })") }
            foreach ($ace in @($sd.DiscretionaryAcl)) {
                if ($ace -isnot [Security.AccessControl.CommonAce] -or $ace.AceType -ne 'AccessAllowed') { continue }
                if (([int]$ace.AceFlags -band 8) -or -not ([int]$ace.AccessMask -band $replace)) { continue }   # 8 = inherit-only: not for the folder itself
                if ($ok -notcontains $ace.SecurityIdentifier.Value) { $who.Add("$(try { $ace.SecurityIdentifier.Translate([Security.Principal.NTAccount]).Value } catch { $ace.SecurityIdentifier.Value })") }
            }
            if ($who.Count) { "$dir can be changed by $(@($who | Sort-Object -Unique) -join ', ')" }
        } catch { }
        $dir = Split-Path $dir -Parent
    }
}
