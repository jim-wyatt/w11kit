"""Shared download helpers for Get-Updates.py, Get-Installers.py and Get-Baselines.py.

Streams a download to <file>.part while hashing it (SHA-1 and SHA-256), checks
it, and only then moves it into place: a file with the wrong hash is deleted,
never kept. Standard library only.
"""
import hashlib
import os
import time
import urllib.request

UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}


def default_work():
    """The kit's work folder: everything the kit downloads or makes is in <kit>/work
    (the build's -WorkRoot default). The kit is the one this script is in; run from a
    clone inside WSL's own file system (a developer's), where the Windows build can't
    see a work folder, it is the documented kit on the Windows side, C:\\W11Kit."""
    kit = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if os.name != 'nt' and not kit.startswith('/mnt/') and os.path.isdir('/mnt/c'):
        kit = '/mnt/c/W11Kit'
    return os.path.join(kit, 'work')
CHUNK = 4 * 1024 * 1024


def get(url, data=None, timeout=60):
    headers = dict(UA)
    if data is not None:
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    return urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=timeout)


def retry(what, fn, ok=lambda r: True, attempts=5, errors=(), reason='empty catalog answer'):
    """Calls fn() until ok(result), with back-off (3, 6, 12, 24 s). The Update Catalog
    now and then answers a request with an empty result (seen: 1 of 3 identical
    searches found nothing). Exceptions in `errors` (e.g. OSError for a dropped
    download) are retried too; the last attempt's result or exception is final."""
    for i in range(attempts):
        last = i == attempts - 1
        try:
            r = fn()
        except errors as e:
            if last:
                raise
            why = f'{type(e).__name__}: {e}'
        else:
            if ok(r) or last:
                return r
            why = reason
        wait = 3 * 2 ** i
        print(f'    {what}: {why}, retrying in {wait} s')
        time.sleep(wait)


def file_sha(path):
    """(sha1, sha256) of a file, lowercase hex."""
    sha1, sha256 = hashlib.sha1(), hashlib.sha256()
    with open(path, 'rb') as f:
        while chunk := f.read(CHUNK):
            sha1.update(chunk); sha256.update(chunk)
    return sha1.hexdigest(), sha256.hexdigest()


def download(url, path, check, timeout=300, progress=True):
    """Downloads url to path via path + '.part'. check(sha1, sha256) returns None if
    the file is right, else an error message: the .part file (and any stale file at
    path) is then deleted and the script stops with that message. Returns (sha1, sha256)."""
    sha1, sha256 = hashlib.sha1(), hashlib.sha256()
    tmp = path + '.part'
    with get(url, timeout=timeout) as r, open(tmp, 'wb') as f:
        total = int(r.headers.get('Content-Length') or 0)
        done = 0
        while chunk := r.read(CHUNK):
            f.write(chunk); sha1.update(chunk); sha256.update(chunk)
            done += len(chunk)
            if progress and total:
                print(f'\r    {done * 100 // total:3d}% of {total // 1024 ** 2} MB', end='', flush=True)
    if progress:
        print()
    hashes = sha1.hexdigest(), sha256.hexdigest()
    err = check(*hashes)
    if err:
        for p in (tmp, path):
            if os.path.exists(p):
                os.remove(p)
        raise SystemExit(err)
    os.replace(tmp, path)
    return hashes
