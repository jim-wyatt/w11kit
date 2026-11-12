#!/usr/bin/env python3
"""Validate hardware profiles (profiles/*/profile.json) against docs/reference/PROFILES.md.

The rules mirror Test-KitProfile in scripts/KitProfile.ps1, which the build and the
harvest run: a profile this script passes, they accept, and the other way round. Keep
the two in step (and PROFILES.md with them).

PowerShell semantics copied on purpose: field names are looked up case-insensitively,
and enumerated values (`productKey`, `power.mode`, ...) and the `id` / `computerName`
patterns compare case-insensitively (`-in`, `-match`). Spellings that PowerShell accepts
but the docs don't use are reported as warnings.

Errors (exit 1):   anything Test-KitProfile rejects; JSON that doesn't parse (or has
                   keys that collide case-insensitively, which ConvertFrom-Json rejects);
                   no `generic` profile (the build's fallback).
Warnings (exit 0): documented but unchecked fields with the wrong type (`description`,
                   `firmwareHints`, a check's `class`), unknown fields, two profiles
                   with the same isoTag, non-canonical case.

Regexes are compiled with Python's `re`; profile regexes are run by .NET. The common
syntax is the same; .NET-only constructs (e.g. `(?<name>...)`) are reported as errors.

Usage: python3 dev/Test-Profiles.py [profile.json ...]   (default: every profile)
Stdlib only.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

REQUIRED = ('id', 'displayName', 'isoTag', 'productKey', 'drivers', 'power', 'security', 'checks')
KNOWN_TOP = set(REQUIRED) | {'schemaVersion', 'description', 'match', 'computerName', 'firmwareHints'}
SCHEMA_VERSION = 1   # the profile format this kit reads
PRODUCT_KEYS = ('firmware', 'generic', 'prompt')
POWER_MODES = ('hibernate', 'default')
DMA = ('required', 'recommended')
CHECK_TYPES = ('video', 'sound', 'netadapter', 'pnp')


class DuplicateKey(ValueError):
    pass


def _pairs(pairs):
    seen = {}
    for k, _ in pairs:
        low = k.lower()
        if low in seen:
            raise DuplicateKey(f"duplicate key '{k}' (same as '{seen[low]}' for PowerShell)")
        seen[low] = k
    return dict(pairs)


def has(obj, name):
    """PowerShell `PSObject.Properties.Name -contains`: case-insensitive."""
    return isinstance(obj, dict) and any(k.lower() == name.lower() for k in obj)


def get(obj, name):
    if not isinstance(obj, dict):
        return None
    for k, v in obj.items():
        if k.lower() == name.lower():
            return v
    return None


def q(v):
    """A value in a message, as PowerShell prints it (null = empty)."""
    return '' if v is None else v


def nonempty_str(v):
    return isinstance(v, str) and v.strip() != ''


def regex_ok(v):
    try:
        re.compile(v)
        return True
    except (re.error, TypeError):
        return False


def in_ci(v, allowed):
    """PowerShell `-in` on strings: case-insensitive."""
    return isinstance(v, str) and v.lower() in allowed


def check_profile(p, folder_id):
    """Errors exactly as Test-KitProfile; warnings for documented extras."""
    bad, warn = [], []
    if not isinstance(p, dict):
        return ['the profile must be a JSON object'], warn
    for f in REQUIRED:
        if not has(p, f):
            bad.append(f"missing field '{f}'")
    # The profile format's version (PowerShell: -isnot [int], so true/false and 1.0 are refused)
    sv = get(p, 'schemaVersion')
    if not has(p, 'schemaVersion'):
        bad.append('missing field \'schemaVersion\' (add "schemaVersion": 1 as the first field)')
    elif isinstance(sv, bool) or not isinstance(sv, int) or sv < 1:
        bad.append(f"schemaVersion '{q(sv)}': a whole number (this kit reads {SCHEMA_VERSION})")
    elif sv > SCHEMA_VERSION:
        bad.append(f'schemaVersion {sv} is newer than this kit reads ({SCHEMA_VERSION}): update the kit (Run-Build.cmd, first question)')
    if bad:
        return bad, warn

    pid = get(p, 'id')
    if not isinstance(pid, str) or not re.fullmatch(r'[a-z0-9][a-z0-9-]*', pid, re.I):
        bad.append(f"id '{q(pid)}': lower-case letters, digits and hyphens")
    elif folder_id and pid.lower() != folder_id.lower():
        bad.append(f"id '{q(pid)}' differs from its folder name '{folder_id}'")
    elif pid != pid.lower() or (folder_id and pid != folder_id):
        warn.append(f"id '{q(pid)}': use lower case, exactly the folder name '{folder_id}'")

    if not nonempty_str(get(p, 'displayName')):
        bad.append('displayName must be a non-empty string')

    match = get(p, 'match')
    if match is not None:
        for k in ('manufacturer', 'model'):
            v = get(match, k)
            if not nonempty_str(v) or not regex_ok(v):
                bad.append(f'match.{k} must be a valid regex (or set match to null)')

    cn = get(p, 'computerName')
    if cn is not None and (not isinstance(cn, str)
                           or not re.fullmatch(r'[A-Za-z0-9-]{1,15}', cn)
                           or re.fullmatch(r'\d+', cn)):
        bad.append(f"computerName '{q(cn)}': 1-15 letters, digits or hyphens, not all digits (or null for a random name)")

    tag = get(p, 'isoTag')
    if not isinstance(tag, str) or not re.fullmatch(r'[A-Za-z0-9]{1,23}', tag):
        bad.append(f"isoTag '{q(tag)}': 1-23 letters and digits")

    pk = get(p, 'productKey')
    if not in_ci(pk, PRODUCT_KEYS):
        bad.append(f"productKey '{q(pk)}': firmware, generic or prompt")
    elif pk not in PRODUCT_KEYS:
        warn.append(f"productKey '{q(pk)}': write it in lower case")

    drivers = get(p, 'drivers')
    prov = get(drivers, 'providers')
    if not nonempty_str(prov) or not regex_ok(prov):
        bad.append('drivers.providers must be a valid regex (. = every third-party provider)')
    skip = get(drivers, 'skipInf')
    if skip is not None and (not nonempty_str(skip) or not regex_ok(skip)):
        bad.append('drivers.skipInf must be a valid regex or null')

    power = get(p, 'power')
    mode = get(power, 'mode')
    if not in_ci(mode, POWER_MODES):
        bad.append(f"power.mode '{q(mode)}': hibernate or default")
    elif mode not in POWER_MODES:
        warn.append(f"power.mode '{q(mode)}': write it in lower case")
    wol = get(power, 'wakeOnLan')
    if wol is not None:
        adapter = get(wol, 'adapter')
        if not nonempty_str(adapter) or not regex_ok(adapter):
            bad.append('power.wakeOnLan.adapter must be a valid regex')
        if not nonempty_str(get(wol, 'label')):
            bad.append('power.wakeOnLan.label must be a non-empty string')
        adv = get(wol, 'advanced')
        if has(wol, 'advanced') and adv is not None and not isinstance(adv, dict):
            bad.append('power.wakeOnLan.advanced must be an object')

    dma = get(get(p, 'security'), 'kernelDmaProtection')
    if not in_ci(dma, DMA):
        bad.append(f"security.kernelDmaProtection '{q(dma)}': required or recommended")
    elif dma not in DMA:
        warn.append(f"security.kernelDmaProtection '{q(dma)}': write it in lower case")

    checks = get(p, 'checks')
    if checks is not None and not isinstance(checks, list):
        bad.append('checks must be an array')
        checks = [checks]   # PowerShell's @() would still walk the single value
    i = 0
    for c in checks or []:
        if c is None:
            continue
        i += 1
        n = f'checks[{i}]'
        for k in ('area', 'name'):
            if not nonempty_str(get(c, k)):
                bad.append(f'{n}.{k} must be a non-empty string')
        ctype = get(c, 'type')
        if not in_ci(ctype, CHECK_TYPES):
            bad.append(f"{n}.type '{q(ctype)}': video, sound, netadapter or pnp")
        m = get(c, 'match')
        if not nonempty_str(m) or not regex_ok(m):
            bad.append(f'{n}.match must be a valid regex')
        vendor = get(c, 'vendor')
        if has(c, 'vendor') and vendor is not None and not regex_ok(vendor):
            bad.append(f'{n}.vendor must be a valid regex')
        # Documented, not checked by Test-KitProfile
        cls = get(c, 'class')
        if cls is not None and not nonempty_str(cls):
            warn.append(f'{n}.class should be a non-empty string')
        if has(c, 'class') and in_ci(ctype, CHECK_TYPES) and ctype.lower() != 'pnp':
            warn.append(f"{n}.class is used only by type 'pnp'")
        if has(c, 'vendor') and in_ci(ctype, CHECK_TYPES) and ctype.lower() != 'video':
            warn.append(f"{n}.vendor is used only by type 'video'")
        if isinstance(c, dict):
            extra = sorted(k for k in c if k.lower() not in {'area', 'name', 'type', 'match', 'vendor', 'class'})
            if extra:
                warn.append(f"{n}: unknown field(s) {', '.join(extra)}")

    # Documented, not checked by Test-KitProfile
    if has(p, 'description') and not isinstance(get(p, 'description'), str):
        warn.append('description should be a string')
    hints = get(p, 'firmwareHints')
    if has(p, 'firmwareHints') and hints is not None and (
            not isinstance(hints, dict) or not all(isinstance(v, str) for v in hints.values())):
        warn.append('firmwareHints should be an object of strings')
    extra = sorted(k for k in p if k.lower() not in {f.lower() for f in KNOWN_TOP})
    if extra:
        warn.append(f"unknown field(s) {', '.join(extra)} (see docs/reference/PROFILES.md)")
    for f in KNOWN_TOP:
        for k in p:
            if k.lower() == f.lower() and k != f:
                warn.append(f"field '{k}': documented as '{f}'")
    return bad, warn


def rel(path):
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def main(argv):
    explicit = [Path(a) for a in argv]
    files = explicit or sorted(REPO.glob('profiles/*/profile.json'))
    errors = warnings = 0
    tags = {}
    for f in files:
        name = rel(f)
        try:
            p = json.loads(f.read_text(encoding='utf-8-sig'), object_pairs_hook=_pairs)
        except (OSError, ValueError) as e:
            print(f'{name}: not valid JSON: {e}')
            errors += 1
            continue
        bad, warn = check_profile(p, f.resolve().parent.name)
        for m in bad:
            print(f'{name}: {m}')
        for m in warn:
            print(f'{name}: warning: {m}')
        errors += len(bad)
        warnings += len(warn)
        tag = get(p, 'isoTag')
        if isinstance(tag, str):
            tags.setdefault(tag.lower(), []).append(name)
    for tag, names in sorted(tags.items()):
        if len(names) > 1:
            print(f"warning: isoTag '{q(tag)}' used by {', '.join(names)} (their ISOs get the same name)")
            warnings += 1
    if not explicit:
        if not (REPO / 'profiles' / 'generic' / 'profile.json').is_file():
            print('profiles/generic/profile.json is missing (the build falls back to it)')
            errors += 1
        for d in sorted((REPO / 'profiles').glob('*/')):
            if d.is_dir() and not (d / 'profile.json').is_file():
                print(f'warning: {rel(d)}/ has no profile.json (the build ignores it)')
                warnings += 1
    summary = f'{len(files)} profile(s): {errors} error(s), {warnings} warning(s)'
    print(('PROFILES FAIL: ' if errors else 'PROFILES OK: ') + summary)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
