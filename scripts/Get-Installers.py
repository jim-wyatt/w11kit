#!/usr/bin/env python3
"""Fetches the build-chain installers in config/installers.json into the kit's work folder.

Default --dest: installers in the kit's work folder (C:\\W11Kit\\work\\installers).

These are the installers of the build chain (Git for Windows, Python 3). They
ride along in the ISO's BuildInputs folder (see Build-Iso.ps1) so a reinstalled
PC can install them again offline (scripts/Install-BuildTools.ps1, through
Run-Prepare.cmd). The image never installs them. The ADK's web installer
(config key 'adk') is not carried: Install-BuildTools downloads it when needed.

Each file is checked against its pinned SHA-256; a present file with the right
hash is not fetched again, and a download with the wrong hash is deleted, never
kept. The Authenticode signature (pinned 'signer') can't be checked here (WSL /
Linux): Install-BuildTools checks it on Windows before it runs an installer. A
dropped connection is retried with back-off (kitfetch.py, shared with
Get-Updates.py).
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitfetch import default_work, download, file_sha, retry  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--config', default=os.path.join(REPO, 'config', 'installers.json'))
    ap.add_argument('--dest', default=os.path.join(default_work(), 'installers'), help='default: %(default)s')
    a = ap.parse_args()

    cfg = json.load(open(a.config))
    os.makedirs(a.dest, exist_ok=True)
    for item in cfg['installers']:
        path = os.path.join(a.dest, item['file'])
        want = item['sha256'].upper()
        if os.path.exists(path) and file_sha(path)[1].upper() == want:
            print(f"    {item['file']}: present, SHA-256 OK")
            continue
        print(f"    downloading {item['file']} ({item.get('name', item.get('tool', ''))} {item.get('version', '')})")

        def check(_, h256, item=item, want=want):
            got = h256.upper()
            return None if got == want else f"{item['file']}: SHA-256 {got} does not match the pinned {want}; deleted"
        retry(f"{item['file']} download", lambda: download(item['url'], path, check, timeout=120, progress=False),
              errors=(OSError,))
        print(f"    {item['file']}: verified")
    print(f'All installers verified in {a.dest}')


if __name__ == '__main__':
    main()
