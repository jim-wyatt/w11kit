#!/usr/bin/env bash
# Fast syntax gate for the kit (WSL; seconds, no admin, changes nothing). Run it
# before every commit.
#   *.ps1        Windows PowerShell 5.1's own parser (powershell.exe, one call)
#   *.py         python3 -m py_compile (bytecode into a temp dir, not the repo)
#   *.sh         bash -n; shellcheck too if installed (warnings shown, not fatal)
#   config/*.json, config/baselines/**.json (the baseline pins), private/*.json (when the
#                folder is there)  must parse
#   profiles/*/profile.json  dev/Test-Profiles.py (the rules of KitProfile.ps1's Test-KitProfile)
#   *.md         dev/Test-DocLinks.py: every relative link and #anchor resolves
# Files: tracked plus new untracked ones (not ignored); in a folder that is not a git
# checkout (the public export's tree), every file under it. Exit 0 only if no errors.
# W11KIT_SKIP_PS=1        skips the PowerShell parse (CI's Linux job; the Windows job parses them).
# W11KIT_SKIP_DOCLINKS=1  skips the link check (dev/Export-Public.sh runs it as its own check).
set -uo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO" || exit 1
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

if [[ $(git rev-parse --show-toplevel 2>/dev/null) == "$REPO" ]]; then
    mapfile -d '' FILES < <(git ls-files -z --cached --others --exclude-standard)
else   # not a checkout of its own
    mapfile -d '' FILES < <(find . \( -name .git -o -path ./work \) -prune -o -type f -printf '%P\0')
fi
pick() {   # pick <extension>: existing files with that extension
    local f
    for f in "${FILES[@]}"; do [[ $f == *."$1" && -f $f ]] && printf '%s\n' "$f"; done | sort -u
}
mapfile -t PS < <(pick ps1)
mapfile -t PY < <(pick py)
mapfile -t SH < <(pick sh)
JSON=()
for f in config/*.json config/baselines/*.json config/baselines/*/*.json private/*.json; do
    [[ -f $f ]] && JSON+=("$f")
done
errors=0 warnings=0
fail() { echo "$*"; errors=$((errors + 1)); }

# --- PowerShell 5.1 parser ------------------------------------------------------------
if (( ${#PS[@]} )) && [[ ${W11KIT_SKIP_PS:-} == 1 ]]; then
    echo "PowerShell parse skipped (W11KIT_SKIP_PS=1): ${#PS[@]} files"
elif (( ${#PS[@]} )); then
    pwsh51=$(command -v powershell.exe || echo /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)
    if [[ ! -x $pwsh51 ]]; then
        fail 'powershell.exe not found (WSL interop off?): PowerShell files not checked'
    else
        # One call for all files: a list of 'repo path|UNC path' lines, read by the parser script
        list=''
        for f in "${PS[@]}"; do list+="'${f//\'/\'\'}|$(wslpath -w "$REPO/$f" | sed "s/'/''/g")',"; done
        ps_script="\$n = 0
foreach (\$pair in @(${list%,})) {
    \$rel, \$path = \$pair -split '\\|', 2
    \$tokens = \$null; \$errs = \$null
    try {
        [void][System.Management.Automation.Language.Parser]::ParseFile(\$path, [ref]\$tokens, [ref]\$errs)
    } catch { \"\${rel}:0: cannot read: \$(\$_.Exception.Message)\"; \$n++; continue }
    foreach (\$e in \$errs) { \"\${rel}:\$(\$e.Extent.StartLineNumber): \$(\$e.Message)\"; \$n++ }
}
exit [Math]::Min(\$n, 255)"
        enc=$(printf '%s' "$ps_script" | iconv -f utf-8 -t utf-16le | base64 -w0)
        out=$(cd /mnt/c && "$pwsh51" -NoProfile -NonInteractive -EncodedCommand "$enc" 2>&1 | tr -d '\r')
        rc=$?   # pipefail: powershell.exe's exit code = number of errors (capped at 255)
        [[ -n $out ]] && echo "$out"
        (( rc )) && errors=$((errors + rc))
    fi
fi

# --- Python ---------------------------------------------------------------------------
for f in "${PY[@]}"; do
    PYTHONPYCACHEPREFIX="$TMP/pycache" python3 -m py_compile "$f" 2>&1 || fail "$f: py_compile failed"
done

# --- Shell ----------------------------------------------------------------------------
for f in "${SH[@]}"; do
    bash -n "$f" || fail "$f: bash -n failed"
done
if (( ${#SH[@]} )) && command -v shellcheck >/dev/null; then
    sc=$(shellcheck -f gcc "${SH[@]}" 2>&1)
    if [[ -n $sc ]]; then
        while IFS= read -r line; do echo "shellcheck (not fatal): $line"; done <<<"$sc"
        warnings=$(grep -c . <<<"$sc")
    fi
fi

# --- JSON -----------------------------------------------------------------------------
for f in "${JSON[@]}"; do
    msg=$(python3 -c '
import json, sys
try:
    json.load(open(sys.argv[1], encoding="utf-8-sig"))
except ValueError as e:
    print(e); sys.exit(1)' "$f") || fail "$f: not valid JSON: $msg"
done

# --- Hardware profiles ----------------------------------------------------------------
PROFILES=(profiles/*/profile.json)
PYTHONPYCACHEPREFIX="$TMP/pycache" python3 dev/Test-Profiles.py | grep -v '^PROFILES OK:'
(( PIPESTATUS[0] )) && fail 'profiles: dev/Test-Profiles.py found errors'

# --- Unit tests of the pure Python logic (quiet unless one fails) ------------------------
units=$(PYTHONPYCACHEPREFIX="$TMP/pycache" python3 dev/Test-Units.py 2>&1) || { echo "$units"; fail 'unit tests: dev/Test-Units.py failed'; }

# --- Markdown links -------------------------------------------------------------------
# With the export's exclude list at hand, a public page that links into a private folder
# is an error here already, not only when the export runs.
links=skipped
if [[ ${W11KIT_SKIP_DOCLINKS:-} != 1 ]]; then
    link_args=()
    [[ -f private/public-export.exclude ]] && link_args=(--private-paths private/public-export.exclude)
    out=$(PYTHONPYCACHEPREFIX="$TMP/pycache" python3 dev/Test-DocLinks.py "$REPO" "${link_args[@]}")
    rc=$?
    last=${out##*$'\n'}
    [[ $last =~ ^DOC\ LINKS\ [A-Z]+:\ ([0-9]+) ]] && links=${BASH_REMATCH[1]}
    if (( rc )); then
        echo "$out"
        fail 'docs: dev/Test-DocLinks.py found broken links'
    fi
fi

# --- Release placeholders ---------------------------------------------------------------
# The repository URL and the security contact are filled in; none may come back (private/ is
# not published). The patterns are split so that this file doesn't contain them.
ph=$(git -C "$REPO" grep -n -e '<repository'' URL>' -e '<security'' contact>' -e 'OWN''ER/REPO' -- ':!private' ':!dev/Export-Public.sh' 2>/dev/null)
[[ -n $ph ]] && { echo "$ph"; fail 'placeholders: a release placeholder (repository URL, security contact, owner/repo) is back (above)'; }

summary="${#PS[@]} PowerShell, ${#PY[@]} Python, ${#SH[@]} shell, ${#JSON[@]} JSON files, ${#PROFILES[@]} profiles, $links doc links: $errors error(s), $warnings shellcheck warning(s)"
if (( errors )); then echo "SYNTAX FAIL: $summary"; exit 1; fi
echo "SYNTAX OK: $summary"
