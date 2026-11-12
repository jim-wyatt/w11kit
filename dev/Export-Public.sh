#!/usr/bin/env bash
# The public export: writes the tree of one commit into an empty folder, without the private
# paths, and checks that nothing private is left in it. Runs in WSL or Linux. No network,
# changes nothing in this repository, creates no commit and pushes nothing: when the checks
# pass, it prints the commands that make the single-commit public history.
#
#   dev/Export-Public.sh <target-dir> [options]
#   dev/Export-Public.sh --check-only [options]
#
#   <target-dir>          where the public tree goes: a new or empty folder outside this repository
#   --ref <git ref>       the commit to export (default: HEAD)
#   --allow-dirty         run although the worktree has uncommitted changes (they are NOT exported)
#   --check-only          export into a temporary folder, run the checks, delete the folder
#   --final               for the real publication: a placeholder that is still there is an error
#   --author-email <a>    the e-mail address for the printed commit commands
#                         (for example 12345678+name@users.noreply.github.com)
#   --remote-url <url>    the public repository's address for the printed commands
#
# The export is `git archive <ref>` minus every path matching a pattern in
# private/public-export.exclude (one pattern per line, relative to the top folder; a trailing /
# means the whole folder; shell wildcards allowed; # comments and blank lines ignored).
#
# The checks (each violation is one line; any violation = exit 1):
#   a  nothing an exclude pattern matches is left, no folder named private anywhere, and no
#      hidden file or folder at the top but the ones in TOP_HIDDEN_OK
#   b  no text file, and no file name, matches a line of private/export-denylist.txt (a line's
#      exact strings from private/export-allow.txt are cut before it is matched)
#      (printed as  file:line: <pattern>, never the line itself)
#   c  placeholders: only the three known ones (listed below in ALLOWED) may be there, and none
#      with --final
#   d  every relative Markdown link and #anchor resolves (dev/Test-DocLinks.py on the exported tree)
#   e  no file over 1 MB, no binary, executable or archive file, no symbolic link
#   f  the exported tree passes its own dev/Test-KitSyntax.sh
#   g  no commit hash of this repository in the text (after the squash it points at nothing)
#
# Exit code: 0 = all checks passed, 1 = violations, 2 = refused (usage, target, dirty worktree).
set -euo pipefail

ALLOWED=('<repository URL>' '<security contact>' 'OWNER/REPO')
# What an unknown placeholder looks like. The first list is matched as written, the second
# without regard to case.
SUSPECT_CS='\bTODO\b|\bTBD\b|\bFIXME\b|\bXXX\b|CHANGE[-_ ]?ME|FILL[-_ ]ME|\bOWNER\b|\bYOUR[-_](ORG|NAME|USER|USERNAME|REPO|EMAIL)\b'
SUSPECT_CI='<(repo|repository|security|contact|maintainer|owner|author)( [^>]{0,40})?>|example\.(com|org|net)\b|lorem ipsum'
# Binary files the public tree may hold: none. Everything the kit ships is text (scripts,
# JSON, XML, Markdown, the UTF-16 security template); a binary could not be reviewed here.
BINARY_OK=()
# Hidden entries the top folder may hold. Any other one (a forge's workflow folder, an editor's
# or an assistant's settings) is private until it is added here on purpose.
TOP_HIDDEN_OK=(.github .gitattributes .gitignore)
MAX_BYTES=1048576
AUTHOR_NAME='W11Kit contributors'
TAG='v0.1.0-beta'

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }
refuse() { echo "Export-Public: $*" >&2; exit 2; }

target='' ref=HEAD allow_dirty=0 check_only=0 final=0 author_email='' remote_url=''
while (( $# )); do
    case $1 in
        --ref)          [[ $# -ge 2 ]] || refuse '--ref needs a value'; ref=$2; shift ;;
        --author-email) [[ $# -ge 2 ]] || refuse '--author-email needs a value'; author_email=$2; shift ;;
        --remote-url)   [[ $# -ge 2 ]] || refuse '--remote-url needs a value'; remote_url=$2; shift ;;
        --allow-dirty)  allow_dirty=1 ;;
        --check-only)   check_only=1 ;;
        --final)        final=1 ;;
        -h|--help)      usage; exit 0 ;;
        -*)             refuse "unknown option $1 (see --help)" ;;
        *)              [[ -z $target ]] || refuse "one target folder only (got '$target' and '$1')"; target=$1 ;;
    esac
    shift
done
if (( check_only )); then
    [[ -z $target ]] || refuse '--check-only uses a temporary folder: give no target folder'
else
    [[ -n $target ]] || { usage >&2; exit 2; }
fi
if [[ -n $author_email && ! $author_email =~ ^[^[:space:]@\'\"]+@[^[:space:]@\'\"]+\.[^[:space:]@\'\"]+$ ]]; then
    refuse "--author-email '$author_email' is not an e-mail address"
fi
[[ $remote_url != *[[:space:]\'\"]* ]] || refuse '--remote-url must not contain spaces or quotes'
for tool in git tar python3 file find grep sed awk iconv realpath du; do
    command -v "$tool" >/dev/null || refuse "'$tool' is not installed"
done

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null) || refuse 'this script must run from a git checkout of the kit'
REPO=$(realpath "$REPO")
commit=$(git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}") || refuse "'$ref' is not a commit of this repository"

dirty=$(git -C "$REPO" status --porcelain | wc -l)
if (( dirty )); then
    if (( ! allow_dirty )); then
        refuse "the worktree has $dirty uncommitted change(s). The export is made from a commit: commit first (or pass --allow-dirty to export '$ref' as it is)."
    fi
    echo '######################################################################################'
    echo "# WARNING: the worktree has $dirty uncommitted change(s). They are NOT in this export."
    echo "# Exported: commit ${commit:0:12} ($ref), exactly as committed."
    echo '######################################################################################'
fi

WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
if (( check_only )); then
    TREE=$WORK/tree
    mkdir "$TREE"
else
    TREE=$(realpath -m -- "$target")
    case $TREE/ in "$REPO"/*) refuse "the target '$TREE' is inside this repository ($REPO): choose a folder outside it" ;; esac
    case $REPO/ in "$TREE"/*) refuse "the target '$TREE' contains this repository" ;; esac
    if [[ -e $TREE ]]; then
        [[ -d $TREE && ! -L $TREE ]] || refuse "the target '$TREE' exists and is not a folder"
        [[ -z $(ls -A -- "$TREE") ]] || refuse "the target '$TREE' is not empty: choose a new folder, or delete it first"
    else
        mkdir -p -- "$TREE"
    fi
fi

# --- Export -------------------------------------------------------------------------
git -C "$REPO" archive --format=tar "$commit" | tar -x -C "$TREE"

# The two private lists come from the exported commit (so the result depends on the commit
# alone); a commit from before a list existed takes the worktree's copy.
private_file() {   # private_file <name>: prints the path of the copy to use
    local name=$1
    if [[ -f $TREE/private/$name ]]; then
        cp -- "$TREE/private/$name" "$WORK/$name"
    elif [[ -f $REPO/private/$name ]]; then
        echo "Note: private/$name is not in commit ${commit:0:12}: using the worktree's copy." >&2
        cp -- "$REPO/private/$name" "$WORK/$name"
    else
        refuse "private/$name is missing (in commit ${commit:0:12} and in the worktree)"
    fi
    echo "$WORK/$name"
}
exclude_file=$(private_file public-export.exclude)
deny_file=$(private_file export-denylist.txt)
allow_file=$(private_file export-allow.txt)
# Exact strings (case-sensitive) that may contain a deny-list match, e.g. the public repository's
# address: cut from a hit's line before its pattern is tried again
mapfile -t ALLOW < <(sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$allow_file" | grep -v -e '^#' -e '^$' || true)

mapfile -t EXCLUDE < <(sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$exclude_file" | grep -v -e '^#' -e '^$' || true)
(( ${#EXCLUDE[@]} )) || refuse 'private/public-export.exclude lists no pattern'
for pat in "${EXCLUDE[@]}"; do
    [[ $pat != /* && $pat != *..* && ${pat%/} != '' && ${pat%/} != '.' && ${pat%/} != '*' ]] ||
        refuse "private/public-export.exclude: pattern '$pat' is not a path inside the tree"
done
matches() {   # matches <pattern>: the paths in the tree that an exclude pattern matches, NUL-separated
    ( cd "$TREE" && shopt -s nullglob dotglob && IFS='' && for m in ${1%/}; do
          if [[ -e $m || -L $m ]]; then printf '%s\0' "$m"; fi; done )
}
for pat in "${EXCLUDE[@]}"; do
    while IFS= read -r -d '' m; do rm -rf -- "${TREE:?}/$m"; done < <(matches "$pat")
done

# --- Checks -------------------------------------------------------------------------
total=0
declare -A count=([a]=0 [b]=0 [c]=0 [d]=0 [e]=0 [f]=0 [g]=0)
check=''
begin() { check=$1; echo; echo "[$1] $2"; }
violation() { echo "  $*"; count[$check]=$(( count[$check] + 1 )); total=$((total + 1)); }
passed() { (( count[$check] )) || echo "  ok${1:+: $1}"; }

mapfile -d '' FILES < <(cd "$TREE" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\0' | sort -z)
(( ${#FILES[@]} )) || refuse "the export of commit ${commit:0:12} is empty"

# Text in UTF-16 (the security template) is binary to grep: the text checks read a UTF-8 copy.
U16=$WORK/u16
mkdir "$U16"
declare -A MIME=()
for f in "${FILES[@]}"; do
    [[ -L $TREE/$f ]] && { MIME[$f]='symbolic link'; continue; }
    MIME[$f]=$(file -b --mime -- "$TREE/$f")
    if [[ ${MIME[$f]} =~ charset=utf-16(le|be) ]]; then
        mkdir -p -- "$U16/$(dirname "$f")"
        iconv -f UTF-16 -t UTF-8 -- "$TREE/$f" >"$U16/$f" 2>/dev/null ||
            iconv -f "UTF-16${BASH_REMATCH[1]^^}" -t UTF-8 -- "$TREE/$f" >"$U16/$f"
    fi
done
scan() {   # scan <grep options>: grep over all exported text; prints path:line:text
    local root
    for root in "$TREE" "$U16"; do
        ( cd "$root" && grep -r -I -n "$@" . 2>/dev/null || true ) | sed 's|^\./||'
    done
}

begin a 'Private paths are gone (private/public-export.exclude, private/, hidden top-level entries)'
while IFS= read -r -d '' m; do violation "$m: still in the export"; done \
    < <(cd "$TREE" && find . -name private -printf '%P\0')
while IFS= read -r -d '' m; do
    for ok in "${TOP_HIDDEN_OK[@]}"; do [[ $m == "$ok" ]] && continue 2; done
    violation "$m: still in the export (a hidden top-level entry that is not in TOP_HIDDEN_OK)"
done < <(cd "$TREE" && find . -mindepth 1 -maxdepth 1 -name '.*' -printf '%P\0')
for pat in "${EXCLUDE[@]}"; do
    while IFS= read -r -d '' m; do
        [[ $m == private || $m == .* ]] || violation "$m: still in the export (pattern '$pat')"
    done < <(matches "$pat")
done
for f in "${FILES[@]}"; do
    [[ $f != *[:\\$'\n']* ]] || violation "${f//$'\n'/?}: a file name with a colon, backslash or line break"
done
passed "${#EXCLUDE[@]} exclude pattern(s)"

begin b 'Deny-list (private/export-denylist.txt): file:line: <pattern>'
n_deny=0
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
    opt=(-i); pat=$line
    if [[ $line == CASE:* ]]; then opt=(); pat=${line#CASE:}; fi
    rc=0; grep -q -E "${opt[@]}" -e "$pat" </dev/null || rc=$?
    if (( rc > 1 )); then violation "private/export-denylist.txt: not a valid regular expression: $line"; continue; fi
    if grep -q -E "${opt[@]}" -e "$pat" <<<''; then
        violation "private/export-denylist.txt: this pattern matches an empty line (it would match everything): $line"; continue
    fi
    n_deny=$((n_deny + 1))
    while IFS= read -r hit; do
        [[ -n $hit ]] || continue
        text=$(cut -d: -f3- <<<"$hit")
        for a in "${ALLOW[@]}"; do text=${text//"$a"/}; done
        grep -q -E "${opt[@]}" -e "$pat" <<<"$text" && violation "$(cut -d: -f1,2 <<<"$hit"): <$line>"
    done < <(scan -E "${opt[@]}" -e "$pat")
    for f in "${FILES[@]}"; do
        grep -q -E "${opt[@]}" -e "$pat" <<<"$f" && violation "$f: (file name) <$line>"
    done
    if [[ -n $author_email ]] && grep -q -E "${opt[@]}" -e "$pat" <<<"$author_email"; then
        violation "--author-email: <$line>"
    fi
done <"$deny_file"
(( n_deny )) || violation 'private/export-denylist.txt holds no pattern'
passed "$n_deny pattern(s), no hit"

begin c "Placeholders (allowed: ${ALLOWED[*]})"
SELF=dev/Export-Public.sh   # this script names the placeholders; it is not searched for them
allowed_opts=(); strip=()
for a in "${ALLOWED[@]}"; do
    allowed_opts+=(-e "$a")
    strip+=(-e "s|${a//[.*^\$\[\]\\|]/.}||g")   # no regex character in the three: . stands in for any
done
mapfile -t PLACEHOLDERS < <(scan -o -F "${allowed_opts[@]}" | grep -v "^$SELF:" || true)
for kind in cs ci; do
    if [[ $kind == cs ]]; then sus=$SUSPECT_CS; opt=(); else sus=$SUSPECT_CI; opt=(-i); fi
    while IFS= read -r hit; do
        [[ -n $hit ]] || continue
        where=$(cut -d: -f1,2 <<<"$hit")
        [[ $where == "$SELF":* ]] && continue
        rest=$(cut -d: -f3- <<<"$hit" | sed "${strip[@]}")
        while IFS= read -r token; do
            [[ -n $token ]] && violation "$where: unknown placeholder: $token"
        done < <(grep -o -E "${opt[@]}" -e "$sus" <<<"$rest" | sort -u || true)
    done < <(scan -E "${opt[@]}" -e "$sus")
done
if (( ${#PLACEHOLDERS[@]} )); then
    if (( final )); then
        for hit in "${PLACEHOLDERS[@]}"; do
            violation "$(cut -d: -f1,2 <<<"$hit"): placeholder still there (--final): $(cut -d: -f3- <<<"$hit")"
        done
    else
        echo "  ${#PLACEHOLDERS[@]} placeholder(s) to fill in before publication (an error with --final):"
        printf '%s\n' "${PLACEHOLDERS[@]}" |
            awk '{ i = index($0, ":"); f = substr($0, 1, i - 1); r = substr($0, i + 1); j = index(r, ":");
                   n[f "  " substr(r, j + 1)]++ }
                 END { for (k in n) printf "    %3d  %s\n", n[k], k }' | sort -k2
    fi
fi
passed "${#PLACEHOLDERS[@]} known placeholder(s), no unknown one"

begin d 'Markdown links (dev/Test-DocLinks.py on the exported tree)'
checker=$TREE/dev/Test-DocLinks.py
[[ -f $checker ]] || checker=$REPO/dev/Test-DocLinks.py
rc=0
out=$(PYTHONPYCACHEPREFIX="$WORK/pycache" python3 "$checker" "$TREE" 2>&1) || rc=$?
if (( rc )); then
    while IFS= read -r l; do
        if [[ $l == 'DOC LINKS FAIL:'* ]]; then echo "  $l"; else violation "$l"; fi
    done <<<"$out"
    (( count[d] )) || violation "Test-DocLinks.py failed (exit code $rc)"
fi
passed "${out##*$'\n'}"

begin e 'File sizes and types (nothing over 1 MB, no binary, executable or archive, no link)'
bytes=0
for f in "${FILES[@]}"; do
    m=${MIME[$f]}
    if [[ $m == 'symbolic link' ]]; then violation "$f: a symbolic link"; continue; fi
    size=$(stat -c %s -- "$TREE/$f")
    bytes=$((bytes + size))
    (( size <= MAX_BYTES )) || violation "$f: $size bytes (over 1 MB)"
    (( size )) || continue
    for ok in "${BINARY_OK[@]}"; do [[ $f == "$ok" ]] && continue 2; done
    if [[ $m == *charset=binary* ]] ||
       [[ $m =~ executable|x-dosexec|x-sharedlib|x-object|octet-stream|archive|compress|zip|x-tar|x-7z|x-xz|x-rar|x-msi|x-cab|x-iso|pdf|^image/|^audio/|^video/|^font/ ]]; then
        violation "$f: not a text file ($m)"
    fi
done
passed "${#FILES[@]} files, $bytes bytes"

begin f 'The exported tree passes its own syntax gate (dev/Test-KitSyntax.sh)'
if [[ ! -f $TREE/dev/Test-KitSyntax.sh ]]; then
    violation 'dev/Test-KitSyntax.sh is not in the export'
else
    skip_ps=${W11KIT_SKIP_PS:-}
    if [[ $skip_ps != 1 ]] && ! command -v powershell.exe >/dev/null &&
       [[ ! -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]]; then
        skip_ps=1
        echo '  Windows PowerShell is not reachable from here: the *.ps1 files are NOT parsed in this run.'
    fi
    rc=0
    out=$(W11KIT_SKIP_PS=$skip_ps W11KIT_SKIP_DOCLINKS=1 bash "$TREE/dev/Test-KitSyntax.sh" 2>&1) || rc=$?
    if (( rc )); then
        while IFS= read -r l; do
            if [[ $l == 'SYNTAX FAIL:'* ]]; then echo "  $l"; else violation "$l"; fi
        done <<<"$out"
        (( count[f] )) || violation "Test-KitSyntax.sh failed (exit code $rc)"
    fi
    passed "${out##*$'\n'}"
fi

begin g 'No commit hash of this repository in the text'
mapfile -t CANDIDATES < <(scan -o -h -w -E -e '[0-9a-fA-F]{7,40}' | cut -d: -f2- | tr 'A-F' 'a-f' | sort -u)
if (( ${#CANDIDATES[@]} )); then
    mapfile -t VERDICT < <(printf '%s^{commit}\n' "${CANDIDATES[@]}" | git -C "$REPO" cat-file --batch-check 2>/dev/null)
    (( ${#VERDICT[@]} == ${#CANDIDATES[@]} )) || refuse 'git cat-file --batch-check: unexpected output (check g)'
    for i in "${!CANDIDATES[@]}"; do
        [[ ${VERDICT[$i]} =~ ^[0-9a-f]{40,64}\ commit\  ]] || continue
        h=${CANDIDATES[$i]}
        while IFS= read -r hit; do
            [[ -n $hit ]] && violation "$(cut -d: -f1,2 <<<"$hit"): commit hash $h"
        done < <(scan -i -w -F -e "$h")
    done
fi
passed "${#CANDIDATES[@]} hexadecimal word(s) looked up, none is a commit"

# --- Result -------------------------------------------------------------------------
echo
per_check=''
for k in a b c d e f g; do per_check+="$k: ${count[$k]}, "; done
if (( total )); then
    echo "EXPORT FAIL: $total violation(s) in commit ${commit:0:12} (${per_check%, })"
    if (( ! check_only )); then
        echo "The tree was left in $TREE for you to look at. It must NOT be published; delete it before the next run."
    fi
    exit 1
fi

size_h=$(du -sh --apparent-size -- "$TREE" | cut -f1)
echo "EXPORT OK: ${#FILES[@]} files, $bytes bytes ($size_h), from commit ${commit:0:12} ($ref); ${#PLACEHOLDERS[@]} placeholder(s) left"
echo "Top level: $(cd "$TREE" && find . -mindepth 1 -maxdepth 1 -printf '%P\n' | sort | tr '\n' ' ')"
if (( check_only )); then
    echo 'Check only: the temporary tree is deleted. Nothing was written.'
    exit 0
fi

mail=${author_email:-'<author e-mail>'}
url=${remote_url:-git@github.com:jim-wyatt/w11kit.git}
q=$(printf '%q' "$TREE")
cat <<EOF

The public tree is in $TREE. Nothing was committed or pushed.
EOF
(( ${#PLACEHOLDERS[@]} )) && echo "Before the real publication: fill in the placeholders in the working repository, commit, and export again with --final."
[[ -n $author_email ]] || echo "No --author-email given: replace <author e-mail> below (for example 12345678+name@users.noreply.github.com)."
cat <<EOF

To create the single-commit history (author and committer '$AUTHOR_NAME', no personal name,
no local time zone, not signed with your key):

  cd $q
  git init -b main
  git add -A
  TZ=UTC GIT_AUTHOR_NAME='$AUTHOR_NAME' GIT_AUTHOR_EMAIL='$mail' GIT_COMMITTER_NAME='$AUTHOR_NAME' GIT_COMMITTER_EMAIL='$mail' git -c commit.gpgsign=false commit -m 'W11Kit ${TAG#v}: first public release'
  git log --format='%an <%ae> | %cn <%ce> | %ad'      # check: one commit, the neutral name twice
  git status --short                                  # check: prints nothing

The signed release tag, with the project's release key (config/release-signers; it asks for the
key's passphrase), and its check:

  TZ=UTC GIT_COMMITTER_NAME='$AUTHOR_NAME' GIT_COMMITTER_EMAIL='$mail' git -c gpg.format=ssh -c user.signingkey=\$HOME/.ssh/w11kit-release tag -s $TAG -m 'W11Kit ${TAG#v}'
  git -c gpg.ssh.allowedSignersFile=config/release-signers verify-tag $TAG

The GitHub remote (create the empty repository on GitHub first; this script never pushes):

  git remote add origin $url
  # when you have checked everything:  git push -u origin main   (and: git push origin $TAG)
EOF
