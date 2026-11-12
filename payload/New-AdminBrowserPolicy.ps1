<#
.SYNOPSIS
    The AppLocker policy that stops administrator accounts from running web
    browsers (DISA STIG V-253294, CAT I; docs/reference/SECURITY-BASELINE.md). Returns the
    policy XML; PostInstall applies it with Set-AppLockerPolicy (local Group Policy).

.DESCRIPTION
    Deny-list mode, not allowlisting: the executable (Exe) rule collection allows
    everything for Everyone, so nothing but the browsers below is affected. The
    packaged-app (Appx) collection must be configured too: with Exe rules enforced
    and no Appx rules, AppLocker denies EVERY packaged app to every user (Start,
    Settings, Terminal, Store, winget, WSL). It gets one rule: all signed packaged
    apps, for Everyone. Msi, Script and Dll stay unconfigured (not enforced), so
    PowerShell stays in Full Language mode and installers and scripts are untouched. AppLocker applies to user
    processes only (services running as SYSTEM / LOCAL SERVICE / NETWORK SERVICE
    are exempt unless a policy turns on services enforcement; this one doesn't), so
    browser updaters running as SYSTEM keep working.

    Deny rules (deny always wins over allow):
      - BUILTIN\Administrators (S-1-5-32-544): any elevated admin token, e.g. the
        daily user elevating through a UAC credential prompt, or any admin added later.
      - -AdminSid, the kit's admin account itself: its non-elevated session too
        (UAC filters the Administrators group out of that token).
    Each browser is matched twice: by publisher (its vendor's signing certificate +
    the original file name in the signed binary, any product, any version: a renamed
    or copied signed exe is caught) and by path (*\<name>.exe on any drive, signed
    or not). msedge.exe, brave.exe, chrome.exe, firefox.exe. msedgewebview2.exe
    (WebView2: Settings, installers, the NVIDIA App) is a different file and is NOT
    blocked. (A publisher condition needs the publisher's name: with PublisherName="*"
    AppLocker ignores the file name and the rule matches nothing; tested with
    Test-AppLockerPolicy, 2026-10-08. The Edge publisher string was read from
    msedge.exe with Get-AppLockerFileInformation; the other three are their vendors'
    certificate subjects, and the path rules cover them whatever the signer.)

    Limits (documented): an unsigned browser build or a browser not in the list
    isn't blocked; an administrator can remove the policy (it stops accidental and
    habitual browsing as admin, not a determined admin); enforcement needs the
    Application Identity service (AppIDSvc), which PostInstall sets to Automatic.
#>
[CmdletBinding()]
param(
    # SID of the kit's admin account (build-options.json AdminName); optional
    [string]$AdminSid
)

$ErrorActionPreference = 'Stop'
# file name, display name, signer (AppLocker publisher: the certificate subject's O, L, S, C)
$browsers = @(
    @('MSEDGE.EXE', 'Microsoft Edge', 'O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US'),
    @('BRAVE.EXE', 'Brave', 'O=BRAVE SOFTWARE, INC., L=SAN FRANCISCO, S=CALIFORNIA, C=US'),
    @('CHROME.EXE', 'Google Chrome', 'O=GOOGLE LLC, L=MOUNTAIN VIEW, S=CALIFORNIA, C=US'),
    @('FIREFOX.EXE', 'Mozilla Firefox', 'O=MOZILLA CORPORATION, L=SAN FRANCISCO, S=CALIFORNIA, C=US')
)
# Stable rule IDs: a GUID from the rule's name, so a re-run writes the same policy
function Get-RuleId([string]$Name) {
    $md5 = [Security.Cryptography.MD5]::Create()
    try { ([guid]::new($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("W11Kit AppLocker: $Name")))).ToString() } finally { $md5.Dispose() }
}
function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }

# Leading comma: a one-item list of lists would unroll into strings
$principals = @(, @('S-1-5-32-544', 'Administrators group (elevated admin tokens)'))
if ($AdminSid) {
    if ($AdminSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw "AdminSid '$AdminSid' is not a local account SID" }
    $principals += , @($AdminSid, 'the admin account (also non-elevated)')
}

$rules = New-Object System.Collections.Generic.List[string]
$allowName = 'W11Kit: everyone may run all programs (deny-list mode, no allowlisting)'
$rules.Add(('    <FilePathRule Id="{0}" Name="{1}" Description="{2}" UserOrGroupSid="S-1-1-0" Action="Allow">' -f (Get-RuleId 'allow-all'), (Esc $allowName), (Esc 'Only the deny rules below restrict anything (docs/reference/SECURITY-BASELINE.md).')))
$rules.Add('      <Conditions><FilePathCondition Path="*" /></Conditions>')
$rules.Add('    </FilePathRule>')
foreach ($p in $principals) {
    foreach ($b in $browsers) {
        $desc = Esc 'DISA STIG V-253294: administrative accounts must not use web browsers (docs/reference/SECURITY-BASELINE.md).'
        $rules.Add(('    <FilePublisherRule Id="{0}" Name="{1}" Description="{2}" UserOrGroupSid="{3}" Action="Deny">' -f (Get-RuleId "$($p[0])|$($b[0])"), (Esc "W11Kit: no $($b[1]) for $($p[1]) (signed)"), $desc, $p[0]))
        $rules.Add(("      <Conditions><FilePublisherCondition PublisherName=""{0}"" ProductName=""*"" BinaryName=""{1}""><BinaryVersionRange LowSection=""*"" HighSection=""*"" /></FilePublisherCondition></Conditions>" -f (Esc $b[2]), $b[0]))
        $rules.Add('    </FilePublisherRule>')
        $rules.Add(('    <FilePathRule Id="{0}" Name="{1}" Description="{2}" UserOrGroupSid="{3}" Action="Deny">' -f (Get-RuleId "$($p[0])|path|$($b[0])"), (Esc "W11Kit: no $($b[1]) for $($p[1]) (file name)"), $desc, $p[0]))
        $rules.Add(("      <Conditions><FilePathCondition Path=""*\{0}"" /></Conditions>" -f $b[0]))
        $rules.Add('    </FilePathRule>')
    }
}

@"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
$($rules -join "`r`n")
  </RuleCollection>
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="$(Get-RuleId 'allow-signed-appx')" Name="W11Kit: all signed packaged apps" Description="Exe rules alone would deny every packaged app (Start, Settings, Store, Terminal, WSL)" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePublisherCondition PublisherName="*" ProductName="*" BinaryName="*"><BinaryVersionRange LowSection="0.0.0.0" HighSection="*" /></FilePublisherCondition></Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@
