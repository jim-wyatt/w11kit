#!/usr/bin/env python3
"""Check the relative links of every Markdown file: the target must exist, and a
`#anchor` must be a heading (or an `<a id="...">`) of the target page.

Checked: inline links and images `[text](target)`, and reference definitions
`[label]: target`. Not checked: web links (`https:`, `mailto:`, ...), anything inside a
fenced code block or a code span, and anchors on files that aren't Markdown.
Anchors follow GitHub's rule: lower case, punctuation dropped, spaces to hyphens, and
`-1`, `-2`, ... for a repeated heading.

Files: in a git checkout, the tracked files plus new ones that aren't ignored;
anywhere else (the public export's tree), every *.md under the folder.

--private-paths <file>  a list of path prefixes, one per line (`#` comments), as in
                        private/public-export.exclude: a page outside those folders
                        must not link into them (the public export leaves them out).

Usage: python3 dev/Test-DocLinks.py [folder] [--private-paths <file>]
       (default folder: the repository this script is in)
Prints `file:line: problem` per broken link, then `DOC LINKS OK: ...` (exit 0) or
`DOC LINKS FAIL: ...` (exit 1). Stdlib only.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

FENCE = re.compile(r'^\s{0,3}(```|~~~)')
HEADING = re.compile(r'^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$')
HTML_ID = re.compile(r'<a\s[^>]*\b(?:id|name)\s*=\s*["\']([^"\']+)["\']', re.I)
CODE_SPAN = re.compile(r'(`+)(.+?)\1')
INLINE = re.compile(r'\[(?:[^\]\\]|\\.)*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+(?:"[^"]*"|\'[^\']*\'))?\s*\)')
REFERENCE = re.compile(r'^\s{0,3}\[[^\]]+\]:\s*(<[^>]*>|\S+)')
EXTERNAL = re.compile(r'^[a-z][a-z0-9+.-]*:', re.I)   # https:, mailto:, ...


def markdown_files(root):
    """Tracked + new files in a git checkout whose top folder is `root`; else a walk."""
    try:
        top = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'],
                             capture_output=True, text=True, check=True).stdout.strip()
        if Path(top).resolve() == root:
            out = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others',
                                  '--exclude-standard', '--', '*.md'],
                                 capture_output=True, check=True).stdout.decode('utf-8')
            return sorted(root / f for f in out.split('\0') if f and (root / f).is_file())
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(f for f in root.rglob('*.md')
                  if f.is_file() and '.git' not in f.relative_to(root).parts)


def slug(heading):
    """GitHub's anchor for a heading."""
    h = heading.strip().lower().replace('`', '')
    h = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', h)     # a link in a heading: its text
    h = re.sub(r'[^\w\- ]', '', h)
    return h.replace(' ', '-')


def prose_lines(path):
    """(line number, text) for every line outside fenced code blocks."""
    fence = None
    for n, line in enumerate(path.read_text(encoding='utf-8-sig').split('\n'), 1):
        m = FENCE.match(line)
        if m and fence is None:
            fence = m.group(1)
        elif m and m.group(1) == fence:
            fence = None
        elif fence is None:
            yield n, line


def anchors_of(path):
    found, seen = set(), {}
    for _, line in prose_lines(path):
        m = HEADING.match(line)
        if m:
            s = slug(m.group(1))
            n = seen.get(s, 0)
            seen[s] = n + 1
            found.add(s if n == 0 else f'{s}-{n}')
        found.update(a.lower() for a in HTML_ID.findall(line))
    return found


def read_prefixes(file):
    out = []
    for line in Path(file).read_text(encoding='utf-8-sig').split('\n'):
        line = line.strip()
        if line and not line.startswith('#'):
            out.append(line.strip('/'))
    return out


def under(rel, prefixes):
    return any(rel == p or rel.startswith(p + '/') for p in prefixes)


def main(argv):
    ap = argparse.ArgumentParser(description='Check the relative Markdown links of a folder.')
    ap.add_argument('folder', nargs='?', default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument('--private-paths', metavar='FILE')
    args = ap.parse_args(argv)
    root = Path(args.folder).resolve()
    if not root.is_dir():
        print(f'{args.folder}: not a folder')
        return 2
    private = read_prefixes(args.private_paths) if args.private_paths else []

    files = markdown_files(root)
    anchors = {}
    checked = broken = 0
    for f in files:
        name = f.relative_to(root).as_posix()
        for n, line in prose_lines(f):
            line = CODE_SPAN.sub('', line)
            targets = [m.group(1) for m in INLINE.finditer(line)]
            m = REFERENCE.match(line)
            if m:
                targets.append(m.group(1))
            for target in targets:
                target = target.strip('<>')
                if not target or EXTERNAL.match(target):
                    continue
                checked += 1
                path, _, fragment = target.partition('#')
                path = unquote(path)
                if path.startswith('/'):
                    print(f'{name}:{n}: {target}: starts with / (use a relative link)')
                    broken += 1
                    continue
                dest = (f.parent / path).resolve() if path else f
                if not dest.exists():
                    print(f'{name}:{n}: {target}: no such file')
                    broken += 1
                    continue
                try:
                    dest_rel = dest.relative_to(root).as_posix()
                except ValueError:
                    print(f'{name}:{n}: {target}: points outside the repository')
                    broken += 1
                    continue
                if private and under(dest_rel, private) and not under(name, private):
                    print(f'{name}:{n}: {target}: a public page links into {dest_rel.split("/")[0]}/ '
                          '(left out of the public export)')
                    broken += 1
                    continue
                if fragment and dest.suffix.lower() == '.md' and dest.is_file():
                    if dest not in anchors:
                        anchors[dest] = anchors_of(dest)
                    if unquote(fragment).lower() not in anchors[dest]:
                        print(f'{name}:{n}: {target}: no heading for #{fragment} in {dest_rel}')
                        broken += 1
    summary = f'{checked} relative link(s) in {len(files)} Markdown file(s): {broken} broken'
    print(('DOC LINKS FAIL: ' if broken else 'DOC LINKS OK: ') + summary)
    return 1 if broken else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
