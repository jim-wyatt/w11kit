#!/usr/bin/env python3
"""Imports a Microsoft security baseline (Security Compliance Toolkit zip) as data.

The kit carries no Microsoft file, no baseline setting and no LGPO.exe. It carries the
pins: config/baselines/<id>/source.json names the official zip, its download URL, its
SHA-256 and the GPOs of it to apply. This script turns that zip into text files in the
kit's work folder, <work>/baselines/<id>/, which the build stages into the image:

  registry-machine.json  every Computer registry.pol record of those GPOs, in order
  registry-user.json     every User registry.pol record, in order
  security.inf           the GPOs' GptTmpl.inf files merged (later GPO wins per entry);
                         UTF-16LE with BOM, CRLF, like any security template
  audit.csv              the GPOs' advanced audit CSVs merged (only if any has one)
  index.json             provenance: the zip's name and hash, each GPO's name, GUID,
                         client-side extensions and record counts, and the SHA-256 of
                         every file above

A registry record is {"gpo", "key", "valueName", "type", "data"}: data is a string
(REG_SZ, REG_EXPAND_SZ), a list of strings (REG_MULTI_SZ) or a number (REG_DWORD,
REG_QWORD), exactly as in the file; anything that doesn't re-encode to the same bytes
is kept as "hex" instead. The special value names (**del.<name>, **delvals.,
**DeleteValues, ...) are kept as they are. Every registry.pol is re-encoded from the
records and compared with the original byte for byte before anything is written,
so the data is exact and reversible (Apply-Policy.ps1 writes the same bytes back).

  python3 scripts/Import-Baseline.py <id>               the zip in <work>/baselines (downloaded
                                                        there from source.json's url if missing)
  python3 scripts/Import-Baseline.py <id> --zip FILE    a copy of the zip you already have
  python3 scripts/Import-Baseline.py <id> --check       for maintainers: download the zip again
                                                        (does Microsoft still serve the pinned
                                                        file?) and compare a fresh import with
                                                        the data in <work>/baselines/<id>/;
                                                        writes nothing
  --dest DIR    the baselines folder instead of <work>/baselines (the zips are in it, the
                data in DIR/<id>/)
  --no-download never download: the zip must be there already (the build imports this way)

scripts/Get-Baselines.py does this for every baseline the kit applies; Run-Build.cmd
offers it, and the build itself imports again from the zip before it stages the data.

The zip must match source.json's SHA-256, or nothing is written. The GPOs are picked
by display name (as Microsoft's Baseline-LocalInstall.ps1 does), and a GPO that the
package's own installer doesn't name is refused. Output is deterministic: importing
the same zip twice gives the same bytes. Standard library only; no admin.
"""
import argparse
import csv
import hashlib
import io
import json
import os
import re
import struct
import sys
import shutil
import tempfile
import urllib.error
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitfetch import default_work, download, file_sha, retry  # noqa: E402

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TYPES = {0: 'REG_NONE', 1: 'REG_SZ', 2: 'REG_EXPAND_SZ', 3: 'REG_BINARY', 4: 'REG_DWORD',
         7: 'REG_MULTI_SZ', 11: 'REG_QWORD'}
AUDIT_HEADER = 'Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value'


# --- Registry.pol (PReg) ------------------------------------------------------------
# File: 'PReg' + version 1, then records [key;value;type;size;data], each bracket and
# semicolon one UTF-16LE character; key and value are NUL-terminated UTF-16LE strings,
# type and size little-endian uint32 (MS-GPREG 2.2.1).
def parse_pol(b, where):
    if b[:8] != b'PReg\x01\x00\x00\x00':
        raise SystemExit(f'{where}: not a Registry.pol file (header {b[:8]!r})')
    i, out = 8, []

    def expect(i, ch):
        if b[i:i + 2] != ch.encode('utf-16le'):
            raise SystemExit(f'{where}: malformed record at byte {i}')
        return i + 2

    def string(i):
        j = i
        while b[j:j + 2] != b'\0\0':
            if j >= len(b):
                raise SystemExit(f'{where}: unterminated string at byte {i}')
            j += 2
        return b[i:j].decode('utf-16le'), j + 2

    while i < len(b):
        i = expect(i, '[')
        key, i = string(i)
        i = expect(i, ';')
        name, i = string(i)
        i = expect(i, ';')
        typ, = struct.unpack_from('<I', b, i)
        i = expect(i + 4, ';')
        size, = struct.unpack_from('<I', b, i)
        i = expect(i + 4, ';')
        data = b[i:i + size]
        if len(data) != size:
            raise SystemExit(f'{where}: record data runs past the end of the file')
        i = expect(i + size, ']')
        out.append((key, name, typ, data))
    return out


def encode_data(rec):
    """Bytes of a record's data, from its JSON form."""
    if 'hex' in rec:
        return bytes.fromhex(rec['hex'])
    t, d = rec['type'], rec['data']
    if t in ('REG_SZ', 'REG_EXPAND_SZ'):
        return (d + '\0').encode('utf-16le')
    if t == 'REG_MULTI_SZ':
        return ''.join(s + '\0' for s in d).encode('utf-16le') + b'\0\0'
    if t == 'REG_DWORD':
        return struct.pack('<I', d)
    if t == 'REG_QWORD':
        return struct.pack('<Q', d)
    raise ValueError(f'unknown type {t}')


def type_code(rec):
    t = rec['type']
    if isinstance(t, int):
        return t
    return {v: k for k, v in TYPES.items()}[t]


def to_record(gpo, key, name, typ, data):
    rec = {'gpo': gpo, 'key': key, 'valueName': name, 'type': TYPES.get(typ, typ)}
    try:
        if typ in (1, 2) and len(data) % 2 == 0:
            rec['data'] = data.decode('utf-16le')[:-1] if data.endswith(b'\0\0') else None
        elif typ == 7 and len(data) % 2 == 0 and data.endswith(b'\0\0\0\0'):
            rec['data'] = data.decode('utf-16le')[:-2].split('\0')
        elif typ == 4 and len(data) == 4:
            rec['data'] = struct.unpack('<I', data)[0]
        elif typ == 11 and len(data) == 8:
            rec['data'] = struct.unpack('<Q', data)[0]
        if rec.get('data') is None or encode_data(rec) != data:
            raise ValueError
    except (ValueError, UnicodeDecodeError, KeyError):
        rec.pop('data', None)
        rec['hex'] = data.hex()
    return rec


def write_pol(records):
    out = bytearray(b'PReg\x01\x00\x00\x00')
    for r in records:
        data = encode_data(r)
        out += '['.encode('utf-16le') + (r['key'] + '\0').encode('utf-16le') + ';'.encode('utf-16le')
        out += (r['valueName'] + '\0').encode('utf-16le') + ';'.encode('utf-16le')
        out += struct.pack('<I', type_code(r)) + ';'.encode('utf-16le')
        out += struct.pack('<I', len(data)) + ';'.encode('utf-16le') + data + ']'.encode('utf-16le')
    return bytes(out)


# --- Security templates (GptTmpl.inf) -----------------------------------------------
def inf_entry_key(section, line):
    """The identity of an entry within its section: later GPOs replace it."""
    s = section.lower()
    if s in ('service general setting', 'registry keys', 'file security'):
        return next(csv.reader([line]))[0].strip().lower()
    return line.split('=', 1)[0].strip().lower()


def read_inf(b, where):
    if not b.startswith(b'\xff\xfe'):
        raise SystemExit(f'{where}: security template is not UTF-16LE with a BOM')
    sections, cur = {}, None
    for raw in b[2:].decode('utf-16le').splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith(';'):
            continue
        m = re.fullmatch(r'\[(.+)\]', line.strip())
        if m:
            cur = m.group(1)
            sections.setdefault(cur, {})
            continue
        if cur is None:
            raise SystemExit(f'{where}: entry outside a section: {line!r}')
        sections[cur][inf_entry_key(cur, line)] = line
    return sections


def merge_inf(templates):
    """templates: [(name, sections)] in apply order. Returns the merged text (str)."""
    merged = {}
    for _, secs in templates:
        for sec, entries in secs.items():
            if sec.lower() in ('unicode', 'version'):
                continue
            tgt = next((k for k in merged if k.lower() == sec.lower()), None)
            if tgt is None:
                tgt = sec
                merged[tgt] = {}
            merged[tgt].update(entries)
    lines = ['[Unicode]', 'Unicode=yes', '[Version]', 'signature="$CHICAGO$"', 'Revision=1']
    for sec, entries in merged.items():
        lines.append(f'[{sec}]')
        lines.extend(entries.values())
    return '\r\n'.join(lines) + '\r\n'


# --- Audit CSVs ---------------------------------------------------------------------
def merge_audit(csvs):
    rows = {}
    for where, text in csvs:
        lines = [ln for ln in text.splitlines() if ln.strip()]
        if not lines or ','.join(c.strip() for c in lines[0].split(',')) != AUDIT_HEADER:
            raise SystemExit(f'{where}: unexpected audit CSV header')
        for ln in lines[1:]:
            f = [c.strip() for c in ln.split(',')]
            if len(f) != 7:
                raise SystemExit(f'{where}: expected 7 fields: {ln!r}')
            rows[f[3].lower() or 'name:' + f[2].lower()] = ','.join(f)
    return '\r\n'.join([AUDIT_HEADER] + list(rows.values())) + '\r\n'


# --- The zip ------------------------------------------------------------------------
def find(names, pattern):
    rx = re.compile(pattern, re.I)
    return [n for n in names if rx.fullmatch(n)]


def extension_lists(text):
    """'[{cse}{tool}...][...]' -> [[cse, tool, ...], ...] (upper case)."""
    return [re.findall(r'\{[0-9A-Fa-f-]{36}\}', blk.upper()) for blk in re.findall(r'\[([^\[\]]*)\]', text or '')]


def import_zip(zf, src):
    names = zf.namelist()
    backups = {}
    for bx in find(names, r'(?:[^/]+/)*GPOs/\{[0-9A-F-]{36}\}/Backup\.xml'):
        x = zf.read(bx).decode('utf-8', 'replace')
        m = re.search(r'<DisplayName><!\[CDATA\[(.*?)\]\]></DisplayName>', x)
        if not m:
            raise SystemExit(f'{bx}: no DisplayName')

        def ext(tag):
            mm = re.search(rf'<{tag}><!\[CDATA\[(.*?)\]\]></{tag}>', x)
            return mm.group(1) if mm else ''
        backups[m.group(1)] = {'dir': bx[:-len('Backup.xml')], 'guid': bx.split('/')[-2],
                               'machine': ext('MachineExtensionGuids'), 'user': ext('UserExtensionGuids')}
    missing = [g for g in src['gpos'] if g not in backups]
    if missing:
        raise SystemExit(f'GPOs not in the zip: {missing} (found: {sorted(backups)})')
    # Microsoft's own installer decides what a local install applies: a GPO it doesn't
    # name (unless it applies every GPO of the package) is not ours to apply.
    li = find(names, r'(?:[^/]+/)*Scripts/Baseline-LocalInstall\.ps1')
    if not li:
        raise SystemExit('no Scripts/Baseline-LocalInstall.ps1 in the zip')
    li_text = zf.read(li[0]).decode('utf-8-sig', 'replace')
    named = set(re.findall(r'"(MSFT [^"]+)"', li_text))
    if named:
        bad = [g for g in src['gpos'] if g not in named]
        if bad:
            raise SystemExit(f'{li[0]} does not apply {bad}: check source.json gpos')
    elif sorted(src['gpos']) != sorted(backups):
        raise SystemExit(f'{li[0]} applies every GPO of the package ({sorted(backups)}); source.json gpos must list them all')

    machine, user, infs, audits, gpos = [], [], [], [], []
    for g in src['gpos']:
        d = backups[g]['dir']
        info = {'name': g, 'guid': backups[g]['guid'],
                'machineExtensions': extension_lists(backups[g]['machine']),
                'userExtensions': extension_lists(backups[g]['user'])}
        for side, recs, label in (('Machine', machine, 'registryMachine'), ('User', user, 'registryUser')):
            pols = find(names, re.escape(d) + rf'DomainSysvol/GPO/{side}/registry\.pol')
            n = 0
            for p in pols:
                raw = zf.read(p)
                these = [to_record(g, *r) for r in parse_pol(raw, p)]
                if write_pol(these) != raw:   # exact and reversible, or nothing is written
                    raise SystemExit(f'{p}: re-encoding the records does not reproduce the file')
                recs.extend(these)
                n += len(these)
            info[label] = n
        tmpl = find(names, re.escape(d) + r'DomainSysvol/GPO/Machine/microsoft/windows nt/SecEdit/GptTmpl\.inf')
        info['securityTemplate'] = bool(tmpl)
        for t in tmpl:
            infs.append((g, read_inf(zf.read(t), t)))
        aud = find(names, re.escape(d) + r'DomainSysvol/GPO/Machine/microsoft/windows nt/Audit/audit\.csv')
        info['auditCsv'] = bool(aud)
        for a in aud:
            audits.append((a, zf.read(a).decode('utf-8-sig')))
        gpos.append(info)

    def records_json(recs):
        if not recs:
            return '[]\n'
        return '[\n' + ',\n'.join(json.dumps(r, ensure_ascii=True) for r in recs) + '\n]\n'

    files = {
        'registry-machine.json': records_json(machine).encode('ascii'),
        'registry-user.json': records_json(user).encode('ascii'),
    }
    if infs:
        files['security.inf'] = b'\xff\xfe' + merge_inf(infs).encode('utf-16le')
    if audits:
        files['audit.csv'] = merge_audit(audits).encode('ascii')

    # Client-side extensions: every GPO's Backup.xml lists, plus the installer's extra ones
    ext = {'machine': {}, 'user': {}}
    for side, key in (('machine', 'machineExtensions'), ('user', 'userExtensions')):
        for info in gpos:
            for blk in info[key]:
                ext[side].setdefault(blk[0], set()).update(blk[1:])
        for cse in src.get('extensions', {}).get(side, []):
            ext[side].setdefault(cse.upper(), set())
    index = {
        'description': 'Generated by scripts/Import-Baseline.py from the official zip named in source.json. Do not edit: re-import instead.',
        'name': src['name'],
        'source': {'file': src['file'], 'sha256': src['sha256']},
        'gpos': gpos,
        'extensions': {side: [[cse] + sorted(tools) for cse, tools in sorted(ext[side].items())] for side in ('machine', 'user')},
        'files': {n: hashlib.sha256(b).hexdigest() for n, b in sorted(files.items())},
    }
    files['index.json'] = (json.dumps(index, indent=2, ensure_ascii=True) + '\n').encode('ascii')
    return files, gpos


# --- The pins, the zip, the data folder -----------------------------------------------
GENERATED = ('registry-machine.json', 'registry-user.json', 'security.inf', 'audit.csv', 'index.json')
GET_BASELINES = 'py scripts\\Get-Baselines.py' if os.name == 'nt' else 'python3 scripts/Get-Baselines.py'
TOOLKIT_PAGE = 'https://www.microsoft.com/en-us/download/details.aspx?id=55319'


def default_dest():
    """<work>/baselines: the pinned zips, and the imported data in <id>/ next to them."""
    return os.path.join(default_work(), 'baselines')


def baseline_ids():
    """The baselines the kit applies, in order (config/baselines/baselines.json)."""
    with open(os.path.join(KIT, 'config', 'baselines', 'baselines.json'), encoding='utf-8') as f:
        return [i for i in json.load(f)['apply'] if i]


def load_source(bid):
    path = os.path.join(KIT, 'config', 'baselines', bid, 'source.json')
    if not os.path.isfile(path):
        raise SystemExit(f'{path} not found: {bid!r} is not a baseline of this kit')
    with open(path, encoding='utf-8') as f:
        src = json.load(f)
    for k in ('name', 'file', 'url', 'sha256', 'gpos'):
        if not src.get(k):
            raise SystemExit(f"{path}: no '{k}'")
    if os.path.basename(src['file']) != src['file'] or not src['file'].lower().endswith('.zip'):
        raise SystemExit(f"{path}: 'file' must be a plain .zip file name")
    src['id'] = bid
    return src


def replaced_help(src, reason):
    """What to do when the pinned file can't be downloaded any more."""
    return (f"{src['file']}: {reason}\n"
            f"  Microsoft replaces its baseline files in place, and the kit accepts only the file it pins\n"
            f"  (config/baselines/{src['id']}/source.json, SHA-256 {src['sha256'].lower()}).\n"
            f"  - Update the kit (git pull): a newer kit pins the file Microsoft serves now. Then run this again.\n"
            f"  - Or use a copy of the pinned zip that you already have (any file name; its SHA-256 decides):\n"
            f"      {GET_BASELINES} --zip \"<path to the zip>\"\n"
            f"  - Microsoft's download page, to see what is offered now: {src.get('page') or TOOLKIT_PAGE}")


def fetch_zip(src, path):
    """Downloads the pinned zip to path. A file with another hash is deleted, never kept."""
    want = src['sha256'].lower()
    if not src['url'].startswith('https://download.microsoft.com/'):
        raise SystemExit(f"config/baselines/{src['id']}/source.json: 'url' is not a direct download from "
                         f"download.microsoft.com ({src['url']}): download {src['file']} yourself and pass --zip <file>")
    print(f"    downloading {src['file']}")
    print(f"      {src['url']}")

    def check(_, s256):
        return None if s256 == want else replaced_help(
            src, f'the file Microsoft serves at this address has SHA-256 {s256}, not the pinned one. Deleted, not used.')

    def once():
        try:
            return download(src['url'], path, check, timeout=120, progress=False)
        except urllib.error.HTTPError as e:
            if e.code in (403, 404, 410):   # gone: no retry will bring it back
                raise SystemExit(replaced_help(src, f'Microsoft does not serve this file any more (HTTP {e.code} for {src["url"]}).'))
            raise
    try:
        retry(f"{src['file']} download", once, errors=(OSError,))
    except OSError as e:
        raise SystemExit(f"{src['file']}: download failed ({type(e).__name__}: {e}). No Internet connection, or Microsoft's "
                         f"server does not answer: try again in a few minutes, or use a copy you already have: "
                         f"{GET_BASELINES} --zip \"<path to the zip>\"")


def ensure_zip(src, dest, given=(), may_download=True):
    """The pinned zip as <dest>/<file>, SHA-256 checked: the one already there, else one of
    the files in `given` (matched by hash, copied in), else a download. Returns its path."""
    want = src['sha256'].lower()
    path = os.path.join(dest, src['file'])
    os.makedirs(dest, exist_ok=True)
    if os.path.isfile(path):
        got = file_sha(path)[1]
        if got == want:
            print(f"    {src['file']}: present, SHA-256 OK")
            return path
        if not may_download and not given:
            raise SystemExit(f"{path}: SHA-256 {got} is not the pinned {want} "
                             f"(config/baselines/{src['id']}/source.json): refusing it")
        print(f"    {src['file']}: present, but its SHA-256 {got} is not the pinned {want}: replacing it")
    for g in given:
        if file_sha(g)[1] == want:
            tmp = path + '.part'
            shutil.copyfile(g, tmp)
            os.replace(tmp, path)
            print(f"    {src['file']}: copied from {g}, SHA-256 OK")
            return path
    if not may_download:
        raise SystemExit(f"{src['file']} is not in {dest} (--no-download): get it with {GET_BASELINES}")
    fetch_zip(src, path)
    print(f"    {src['file']}: downloaded, SHA-256 OK")
    return path


def generate(src, zip_path):
    """(files, gpos) from a zip whose SHA-256 is the pinned one; anything else is refused."""
    got, want = file_sha(zip_path)[1], src['sha256'].lower()
    if got != want:
        raise SystemExit(f"{zip_path}: SHA-256 {got} is not the pinned {want} "
                         f"(config/baselines/{src['id']}/source.json): refusing it")
    with zipfile.ZipFile(zip_path) as zf:
        return import_zip(zf, src)


def compare_data(folder, files):
    """Names in `files` that are missing or different in folder, and generated files left over."""
    bad = []
    for n, b in files.items():
        p = os.path.join(folder, n)
        if not os.path.isfile(p):
            bad.append(n)
            continue
        with open(p, 'rb') as f:
            if f.read() != b:
                bad.append(n)
    extra = [n for n in GENERATED if n not in files and os.path.exists(os.path.join(folder, n))]
    return bad, extra


def write_data(folder, files):
    """Writes the data files; index.json last, so a half-written folder never matches its index."""
    os.makedirs(folder, exist_ok=True)
    index = os.path.join(folder, 'index.json')
    if os.path.exists(index):
        os.remove(index)
    # A data file the zip no longer produces (e.g. audit.csv) must not linger
    for n in GENERATED:
        if n not in files and os.path.exists(os.path.join(folder, n)):
            os.remove(os.path.join(folder, n))
            print(f'      removed {n}')
    for n in sorted(files, key=lambda n: n == 'index.json'):
        with open(os.path.join(folder, n), 'wb') as f:
            f.write(files[n])


def import_baseline(bid, dest, zips=(), quiet=False, may_download=True):
    """Fetches (if needed) and imports one baseline into <dest>/<id>/. Returns the folder."""
    src = load_source(bid)
    files, gpos = generate(src, ensure_zip(src, dest, zips, may_download))
    folder = os.path.join(dest, bid)
    write_data(folder, files)
    if not quiet:
        for g in gpos:
            print(f"      {g['name']}: {g['registryMachine']} computer + {g['registryUser']} user registry records"
                  f"{', security template' if g['securityTemplate'] else ''}{', audit policy' if g['auditCsv'] else ''}")
    print(f"    {bid}: imported into {folder} ({', '.join(sorted(files))})")
    return folder


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('id', help='baseline id: a folder in config/baselines with a source.json')
    ap.add_argument('--zip', help='a copy of the baseline zip you already have (default: the one in --dest, '
                                  "downloaded from source.json's url if it is not there)")
    ap.add_argument('--dest', default=default_dest(),
                    help='the baselines folder: the zips, and the data in <id>/ (default: %(default)s)')
    ap.add_argument('--check', action='store_true',
                    help='download the pinned zip again and compare a fresh import with the data in --dest; write nothing')
    ap.add_argument('--no-download', action='store_true',
                    help='never download: the zip must be in --dest (or given with --zip); the build imports this way')
    ap.add_argument('--quiet', action='store_true', help='one line per baseline')
    a = ap.parse_args()
    sys.stdout.reconfigure(errors='replace')   # a path the console's code page can't show must not stop the import
    if a.zip and not os.path.isfile(a.zip):
        raise SystemExit(f'--zip {a.zip}: no such file')

    if not a.check:
        import_baseline(a.id, a.dest, [a.zip] if a.zip else [], a.quiet, not a.no_download)
        return

    src = load_source(a.id)
    folder = os.path.join(a.dest, a.id)
    with tempfile.TemporaryDirectory() as tmp:
        if a.zip:
            path = a.zip
        else:
            path = os.path.join(tmp, 'baseline.zip')
            fetch_zip(src, path)
            print(f"    {src['file']}: Microsoft still serves the pinned file (SHA-256 OK)")
        files, _ = generate(src, path)
    if not os.path.isfile(os.path.join(folder, 'index.json')):
        print(f'{a.id}: the zip imports cleanly ({len(files)} files); no earlier import in {folder} to compare it with '
              f'(make one: {GET_BASELINES})')
        return
    bad, extra = compare_data(folder, files)
    if bad or extra:
        raise SystemExit(f"{a.id}: the data in {folder} differs from a fresh import of the zip: {', '.join(bad) or 'none'}"
                         f"{'; left over: ' + ', '.join(extra) if extra else ''}. Import it again: {GET_BASELINES}")
    print(f'{a.id}: the data in {folder} is what a fresh import of the zip gives ({len(files)} files)')


if __name__ == '__main__':
    main()
