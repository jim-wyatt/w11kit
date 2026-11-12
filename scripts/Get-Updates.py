#!/usr/bin/env python3
"""Downloads the updates in config/updates.json from the Microsoft Update Catalog.

Headless, official source only: catalog search -> exactly one entry per KB for
"Windows 11, version <release> for <arch>" -> download link from the catalog's
download dialog (Microsoft CDN) -> SHA-1 check against the hash Microsoft puts in
every file name. Files land in <dest>/<folder> (default: updates in the kit's work
folder, C:\\W11Kit\\work\\updates, where the build looks for them), with
updates-manifest.json listing title, URL, SHA-1 and
SHA-256 of each file. Each folder ends up holding exactly its configured KBs:
other files there (last month's updates) are removed, because the build applies
every package in lcu\\, dotnet\\, safeos\\ and setup\\. Runs in WSL or anywhere
with Python 3; no admin needed.

  python3 scripts/Get-Updates.py            download what's missing
  python3 scripts/Get-Updates.py --list     show the catalog matches only
  python3 scripts/Get-Updates.py --discover --write
                                            move the pins in config/updates.json to
                                            the newest updates in the catalog (and set
                                            their "pinned" date); then download as above
"""
import argparse
import datetime
import html
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitfetch import default_work, download, file_sha, get, retry  # noqa: E402

CATALOG = 'https://www.catalog.update.microsoft.com'
KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def search(query):
    t = get(f'{CATALOG}/Search.aspx?q={urllib.parse.quote(query)}').read().decode('utf-8', 'replace')
    return [(m.group(1), html.unescape(re.sub(r'\s+', ' ', m.group(2))).strip())
            for m in re.finditer(r"(?s)<a id='([0-9a-f-]{36})_link'[^>]*>(.*?)</a>", t)]


def pick(kb, release, arch):
    def matches():
        return [(uid, title) for uid, title in search(kb)
                if kb.lower() in title.lower() and f'version {release}'.lower() in title.lower()
                and f'for {arch}'.lower() in title.lower() and 'server' not in title.lower()]
    hits = retry(f'{kb} search', matches, lambda h: len(h) > 0)
    if len(hits) != 1:
        raise SystemExit(f'{kb}: expected exactly one catalog entry for Windows 11 {release} {arch}, found {len(hits)}: {[t for _, t in hits]}')
    return hits[0]


def links(uid):
    body = urllib.parse.urlencode({'updateIDs': json.dumps([{'size': 0, 'languages': '', 'uidInfo': uid, 'updateID': uid}])}).encode()
    t = get(f'{CATALOG}/DownloadDialog.aspx', data=body).read().decode('utf-8', 'replace')
    return re.findall(r"\.url = '([^']+)'", t)


def newest(title, release, arch, exclude):
    """The newest month's catalog entries whose title (after the 'YYYY-MM ' prefix)
    is `title`: [(month, kb, build or None, full title)]."""
    want = title.format(release=release, arch=arch).lower()
    found = []
    for _, t in retry(f'"{want}" search', lambda: search(want), lambda h: len(h) > 0):
        m = re.match(r'(\d{4}-\d{2}) (.*?) \((KB\d+)\)(?: \((\d+\.\d+)\))?$', t)
        if m and m.group(2).lower() == want and not any(x.lower() in t.lower() for x in exclude):
            found.append((m.group(1), m.group(3), m.group(4), t))
    if not found:
        raise SystemExit(f'no catalog entry titled "<YYYY-MM> {want} (KB...)"')
    month = max(f[0] for f in found)
    return [f for f in found if f[0] == month]


def build_key(b):
    return tuple(int(x) for x in b.split('.')) if b else (0,)


def discover(cfg):
    """Newest KBs per folder from the catalog, by the config's 'discover' rules. Never
    goes backwards: an LCU with a lower build than the pinned one is ignored (e.g. the
    security release after a preview of the same month)."""
    release, arch, new = cfg['release'], cfg['arch'], {}
    for folder, rule in cfg['discover'].items():
        if not rule:
            new[folder] = cfg['updates'].get(folder, [])
            continue
        hits = newest(rule['title'], release, arch, rule.get('exclude', []))
        if folder == 'lcu':
            top = max(hits, key=lambda h: build_key(h[2]))
            if build_key(top[2]) <= build_key(cfg.get('lcuBuild')):
                print(f'lcu: newest {top[3]} is not newer than the pinned {cfg["updates"]["lcu"]} ({cfg.get("lcuBuild")})')
                new[folder], new['lcuBuild'] = cfg['updates']['lcu'], cfg.get('lcuBuild')
                continue
            hits, new['lcuBuild'] = [top], top[2]
        new[folder] = sorted(h[1] for h in hits)
        for h in hits:
            print(f'{folder}: {h[3]}')
    return new


def run_discover(a, cfg):
    new = discover(cfg)
    changed = {f: kbs for f, kbs in new.items() if f != 'lcuBuild' and sorted(kbs) != sorted(cfg['updates'].get(f, []))}
    for f, kbs in changed.items():
        print(f'CHANGED {f}: {cfg["updates"].get(f, [])} -> {kbs}')
    if not changed:
        print('No newer updates than the pins.')
    elif a.write:
        cfg['updates'].update({f: kbs for f, kbs in new.items() if f != 'lcuBuild'})
        cfg['lcuBuild'] = new.get('lcuBuild', cfg.get('lcuBuild'))
        # The day the pins moved: the build notes pins older than 35 days, and
        # Run-Build.cmd asks before building with pins older than 70 days.
        cfg['pinned'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
        with open(a.config, 'w', encoding='utf-8', newline='\n') as fh:
            json.dump(cfg, fh, indent=2)
            fh.write('\n')
        print(f'Wrote {a.config}')
    if os.environ.get('GITHUB_OUTPUT'):   # a CI job's step outputs
        with open(os.environ['GITHUB_OUTPUT'], 'a') as fh:
            fh.write(f'changed={"true" if changed else "false"}\nlcu={",".join(new.get("lcu", []))}\nlcu_build={new.get("lcuBuild") or ""}\n')
    sys.exit(0 if changed else 3)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--config', default=os.path.join(KIT, 'config', 'updates.json'))
    ap.add_argument('--dest', default=os.path.join(default_work(), 'updates'), help='default: %(default)s')
    ap.add_argument('--list', action='store_true', help='show catalog matches, download nothing')
    ap.add_argument('--discover', action='store_true', help='find the newest KBs by the config\'s "discover" rules; exit 0 if they differ from the pins, 3 if not; downloads nothing')
    ap.add_argument('--write', action='store_true', help='with --discover: write the new pins, and today as their "pinned" date, into the config file')
    a = ap.parse_args()
    cfg = json.load(open(a.config, encoding='utf-8'))
    if a.discover:
        run_discover(a, cfg)
    release, arch = cfg['release'], cfg['arch']
    manifest = []
    for folder, kbs in cfg['updates'].items():
        dest = os.path.join(a.dest, folder)
        wanted = []
        if kbs and not a.list:
            os.makedirs(dest, exist_ok=True)
        for kb in kbs:
            uid, title = pick(kb, release, arch)
            urls = retry(f'{kb} download links', lambda: [u for u in links(uid) if kb.lower() in os.path.basename(u).lower()], lambda u: len(u) > 0)
            if not urls:
                raise SystemExit(f'{kb}: no download link containing {kb} for "{title}"')
            print(f'{folder}: {title}')
            for url in urls:
                name = os.path.basename(urllib.parse.urlparse(url).path)
                m = re.search(r'_([0-9a-f]{40})\.(msu|cab)$', name, re.I)
                if not m:
                    raise SystemExit(f'{name}: no SHA-1 in the file name')
                path = os.path.join(dest, name)
                wanted.append(name)
                if a.list:
                    print(f'    {name}')
                    continue
                want = m.group(1).lower()
                sha1, sha256 = file_sha(path) if os.path.exists(path) else (None, None)
                if sha1 == want:
                    print(f'    {name}: present, SHA-1 OK')
                else:
                    print(f'    downloading {name}')
                    sha1, sha256 = retry(f"download {name}", lambda: download(url, path, lambda h1, _: None if h1 == want else f"{name}: SHA-1 mismatch ({h1}) - deleted"), errors=(OSError,), reason="dropped download")
                manifest.append({'folder': folder, 'kb': kb, 'title': title, 'file': name, 'url': url, 'sha1': sha1, 'sha256': sha256})
        if not a.list and os.path.isdir(dest):
            # The build applies every package in the folder (and BuildInputs carries
            # them): keep exactly the configured KBs' files, nothing from last month.
            for f in sorted(os.listdir(dest)):
                if f not in wanted and os.path.isfile(os.path.join(dest, f)):
                    print(f'    removing {folder}\\{f} (not a configured {folder} KB)')
                    os.remove(os.path.join(dest, f))
    if not a.list:
        json.dump({'release': release, 'arch': arch, 'files': manifest}, open(os.path.join(a.dest, 'updates-manifest.json'), 'w'), indent=2)
        print(f'All updates verified (SHA-1 from Microsoft\'s file names). Manifest: {os.path.join(a.dest, "updates-manifest.json")}')


if __name__ == '__main__':
    main()
