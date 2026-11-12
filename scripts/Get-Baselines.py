#!/usr/bin/env python3
"""Fetches Microsoft's security baselines and imports them into the kit's work folder.

Default --dest: baselines in the kit's work folder (C:\\W11Kit\\work\\baselines).

The kit applies Microsoft's security baselines for Windows 11 and Microsoft Edge, but
carries none of their content: only the pins in config/baselines/<id>/source.json (the
official zip's name, download URL and SHA-256, and which of its GPOs are applied).
For every baseline listed in config/baselines/baselines.json this script

  1. gets the pinned zip into <dest>/<file name>: a file already there with the right
     SHA-256 is kept; a download with another hash is deleted, never kept;
  2. imports it (scripts/Import-Baseline.py) into <dest>/<id>/: the settings as text
     files plus index.json with the zip's hash and each file's SHA-256.

The build checks each zip against its pin, imports it again and stages the data into
the image. A real build's ISO carries the zips, so a reinstalled PC rebuilds offline.

  python3 scripts/Get-Baselines.py                    every baseline the kit applies
  python3 scripts/Get-Baselines.py --zip FILE ...     use zips you already have: each is
                                                      matched to its baseline by SHA-256
                                                      (the file name does not matter) and
                                                      copied into <dest>; nothing is
                                                      downloaded for a baseline it matches
  python3 scripts/Get-Baselines.py --dest DIR         another folder than <work>/baselines
  python3 scripts/Get-Baselines.py <id> ...           only these baselines

Microsoft replaces baseline files in place now and then. When the pinned file is gone,
the message says what to do: update the kit (newer pins), or pass a copy of the pinned
zip with --zip. Exit code 0 only when every baseline is in place and imported.
Standard library only; no admin (the folder must be writable: after the first build
the kit's work folder is writable by administrators only).
"""
import argparse
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def load_importer():
    """scripts/Import-Baseline.py as a module (its name is not a Python identifier)."""
    spec = importlib.util.spec_from_file_location('import_baseline', os.path.join(HERE, 'Import-Baseline.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    ib = load_importer()
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('ids', nargs='*', metavar='id', help='baseline ids (default: all in config/baselines/baselines.json)')
    ap.add_argument('--dest', default=ib.default_dest(), help='default: %(default)s')
    ap.add_argument('--zip', action='append', default=[], metavar='FILE',
                    help='a baseline zip you already have (repeat for several); matched by SHA-256')
    a = ap.parse_args()
    sys.stdout.reconfigure(errors='replace')   # a path the console's code page can't show must not stop the run
    for z in a.zip:
        if not os.path.isfile(z):
            raise SystemExit(f'--zip {z}: no such file')

    ids = a.ids or ib.baseline_ids()
    if a.zip:
        # Say so when a given file is not one the kit pins (a newer or older release)
        pins = {ib.load_source(i)['sha256'].lower(): i for i in ib.baseline_ids()}
        for z in a.zip:
            got = ib.file_sha(z)[1]
            if got not in pins:
                print(f'    --zip {z}: SHA-256 {got} is not a baseline this kit pins '
                      f"({', '.join(ib.load_source(i)['file'] for i in ib.baseline_ids())}): not used")
    failed = []
    for bid in ids:
        try:
            ib.import_baseline(bid, a.dest, a.zip)
        except SystemExit as e:   # this baseline's problem, said in full; the others still run
            print(e.code if isinstance(e.code, str) else f'{bid}: failed ({e.code})')
            failed.append(bid)
        except (OSError, ValueError, KeyError) as e:
            print(f'{bid}: failed ({type(e).__name__}: {e})')
            failed.append(bid)
    if failed:
        raise SystemExit(f"Not ready: {', '.join(failed)} (see above). {len(ids) - len(failed)} of {len(ids)} baseline(s) in {a.dest}")
    print(f'All {len(ids)} security baseline(s) verified and imported in {a.dest}')


if __name__ == '__main__':
    main()
