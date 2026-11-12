#!/usr/bin/env python3
"""Unit tests for the kit's pure Python logic (standard library only):

    python3 dev/Test-Units.py

Import-Baseline.py: the Registry.pol reader and writer (byte-identical round trip, the
delete markers, odd data kept as hex), the security-template merge (later wins per entry,
section names without regard to case) and the audit CSV merge (later wins per subcategory).
Get-Updates.py: the catalog result parsing and the choice of the newest month.

No network, no files outside a temporary folder. dev/Test-KitSyntax.sh and the lint
workflow run it.
"""
import importlib.util
import os
import struct
import sys
import unittest

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True


def load(name):
    """A script with a dash in its name, as a module (its main() does not run)."""
    path = os.path.join(KIT, 'scripts', name)
    spec = importlib.util.spec_from_file_location(name.replace('-', '_').replace('.py', ''), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


ib = load('Import-Baseline.py')
gu = load('Get-Updates.py')


def u16(s):
    return s.encode('utf-16le')


def pol(records):
    """A Registry.pol built by hand, independent of write_pol: [(key, name, type, data)]."""
    out = b'PReg\x01\x00\x00\x00'
    for key, name, typ, data in records:
        out += (u16('[') + u16(key + '\0') + u16(';') + u16(name + '\0') + u16(';') + struct.pack('<I', typ) + u16(';')
                + struct.pack('<I', len(data)) + u16(';') + data + u16(']'))
    return out


class RegistryPol(unittest.TestCase):
    RAW = [
        (r'Software\Policies\Kit', 'Number', 4, struct.pack('<I', 0x80000001)),
        (r'Software\Policies\Kit', 'Text', 1, u16('Block\0')),
        (r'Software\Policies\Kit', 'Expand', 2, u16('%SystemRoot%\\x\0')),
        (r'Software\Policies\Kit', 'List', 7, u16('a\0b c\0\0')),
        (r'Software\Policies\Kit', 'Big', 11, struct.pack('<Q', 2 ** 40 + 5)),
        (r'Software\Policies\Kit', '**del.Gone', 1, u16(' \0')),
        (r'Software\Policies\Kit\List', '**delvals.', 1, u16(' \0')),
        (r'Software\Policies\Kit', 'Empty', 1, u16('\0')),
        (r'Software\Policies\Kit', 'OddText', 1, b'\x41\x00\x42'),        # not valid UTF-16: kept as hex
        (r'Software\Policies\Kit', 'ShortNumber', 4, b'\x01\x00'),        # a DWORD of 2 bytes: kept as hex
        (r'Software\Policies\Kit', 'Binary', 3, b'\x00\x01\xfe\xff'),
        (r'Software\Policies\Kit', 'NoData', 0, b''),
    ]

    def records(self):
        return [ib.to_record('gpo', *r) for r in ib.parse_pol(pol(self.RAW), 'test')]

    def test_parse_reads_every_record(self):
        self.assertEqual(ib.parse_pol(pol(self.RAW), 'test'), self.RAW)

    def test_round_trip_is_byte_identical(self):
        self.assertEqual(ib.write_pol(self.records()), pol(self.RAW))

    def test_readable_values(self):
        by = {r['valueName']: r for r in self.records()}
        self.assertEqual(by['Number']['data'], 0x80000001)
        self.assertEqual(by['Number']['type'], 'REG_DWORD')
        self.assertEqual(by["Text"]["data"], "Block")
        self.assertEqual(by['List']['data'], ['a', 'b c'])
        self.assertEqual(by['Big']['data'], 2 ** 40 + 5)
        self.assertEqual(by['Empty']['data'], '')
        self.assertEqual(by['**del.Gone']['data'], ' ')

    def test_odd_data_is_kept_as_hex(self):
        by = {r['valueName']: r for r in self.records()}
        for name in 'OddText', 'ShortNumber', 'Binary':
            self.assertNotIn('data', by[name], name)
            self.assertIn('hex', by[name], name)
        self.assertEqual(by['Binary']['hex'], '0001feff')

    def test_bad_files_are_refused(self):
        good = pol(self.RAW[:1])
        for bad in (b'XReg\x01\x00\x00\x00', good[:-2], good[:20], good + u16('[')):
            with self.assertRaises((SystemExit, struct.error, IndexError), msg=repr(bad[:12])):
                ib.parse_pol(bad, 'test')


class SecurityTemplate(unittest.TestCase):
    @staticmethod
    def inf(text):
        return b'\xff\xfe' + u16(text.replace('\n', '\r\n'))

    def test_read_and_merge_later_wins(self):
        a = ib.read_inf(self.inf('[Unicode]\nUnicode=yes\n[System Access]\nMinimumPasswordLength = 14\nLockoutBadCount = 10\n'
                                 '[Privilege Rights]\nSeDebugPrivilege = *S-1-5-32-544\n; a comment\n'), 'a')
        b = ib.read_inf(self.inf('[system access]\nminimumpasswordlength = 11\n[Registry Values]\nMACHINE\\X\\Y=4,1\n'), 'b')
        text = ib.merge_inf([('a', a), ('b', b)])
        self.assertTrue(text.startswith('[Unicode]\r\nUnicode=yes\r\n[Version]\r\n'))
        self.assertIn('minimumpasswordlength = 11', text)
        self.assertNotIn('MinimumPasswordLength = 14', text)
        self.assertIn('LockoutBadCount = 10', text)
        self.assertIn('SeDebugPrivilege = *S-1-5-32-544', text)
        self.assertEqual(text.lower().count('[system access]'), 1)
        self.assertNotIn('comment', text)

    def test_entry_identity(self):
        self.assertEqual(ib.inf_entry_key('Service General Setting', '"seclogon",4,""'), 'seclogon')
        self.assertEqual(ib.inf_entry_key('Registry Values', 'MACHINE\\A\\B=4,1'), 'machine\\a\\b')

    def test_wrong_encoding_is_refused(self):
        with self.assertRaises(SystemExit):
            ib.read_inf(b'[System Access]\r\n', 'ansi')
        with self.assertRaises(SystemExit):
            ib.read_inf(self.inf('Orphan = 1\n'), 'no section')


class AuditCsv(unittest.TestCase):
    def test_later_wins_per_subcategory(self):
        head = ib.AUDIT_HEADER
        g1, g2 = '{0CCE922B-69AE-11D9-BED3-505054503030}', '{0CCE9228-69AE-11D9-BED3-505054503030}'
        a = f'{head}\n,System,Process Creation,{g1},Success,,1\n,System,Sensitive Privilege Use,{g2},Success,,1\n'
        b = f'{head}\n,System,Process Creation,{g1.lower()},Success and Failure,,3\n'
        out = ib.merge_audit([('a', a), ('b', b)]).split('\r\n')
        self.assertEqual(out[0], head)
        self.assertEqual(len([ln for ln in out if ln]), 3)
        self.assertIn(f',System,Process Creation,{g1.lower()},Success and Failure,,3', out)
        self.assertIn(f',System,Sensitive Privilege Use,{g2},Success,,1', out)

    def test_bad_csv_is_refused(self):
        with self.assertRaises(SystemExit):
            ib.merge_audit([('x', 'Not,the,header\n')])
        with self.assertRaises(SystemExit):
            ib.merge_audit([('x', ib.AUDIT_HEADER + '\nonly,three,fields\n')])


class UpdateCatalog(unittest.TestCase):
    PAGE = """
      <a id='11111111-1111-1111-1111-111111111111_link' href='#' class='x'>
          2026-09 Cumulative Update Preview for Windows 11, version 26H2 for x64-based Systems (KB5124010) (26300.9550)
      </a>
      <a id='22222222-2222-2222-2222-222222222222_link' href='#'>2026-10 Cumulative Update for Windows 11, version 26H2 for x64-based Systems (KB5129999) (26300.9700)</a>
      <a id='33333333-3333-3333-3333-333333333333_link' href='#'>2026-10 Cumulative Update for Windows 11, version 26H2 for arm64-based Systems (KB5129999) (26300.9700)</a>
      <a id='44444444-4444-4444-4444-444444444444_link' href='#'>2026-09 Cumulative Update for Windows 11, version 26H2 for x64-based Systems (KB5120000) (26300.9500)</a>
      <a id='55555555-5555-5555-5555-555555555555_link' href='#'>2026-10 Cumulative Update for Microsoft server operating system version 26H2 for x64-based Systems (KB5129999)</a>
      <a id='not-a-guid_link'>ignored &amp; skipped</a>
    """

    def setUp(self):
        class Page:
            def read(_self):
                return self.PAGE.encode()
        self.saved = gu.get, gu.retry
        gu.get = lambda url, data=None: Page()
        gu.retry = lambda what, fn, ok: fn()

    def tearDown(self):
        gu.get, gu.retry = self.saved

    def test_search_reads_ids_and_titles(self):
        hits = gu.search('anything')
        self.assertEqual(len(hits), 5)
        self.assertEqual(hits[0][0], '11111111-1111-1111-1111-111111111111')
        self.assertEqual(hits[0][1], '2026-09 Cumulative Update Preview for Windows 11, version 26H2 for x64-based Systems (KB5124010) (26300.9550)')

    def test_pick_wants_exactly_one_client_entry(self):
        self.assertEqual(gu.pick('KB5129999', '26H2', 'x64')[0], '22222222-2222-2222-2222-222222222222')
        with self.assertRaises(SystemExit):
            gu.pick('KB0000000', '26H2', 'x64')

    def test_newest_takes_the_latest_month_and_honours_exclude(self):
        title = 'Cumulative Update for Windows 11, version {release} for {arch}-based Systems'
        found = gu.newest(title, '26H2', 'x64', exclude=['Preview'])
        self.assertEqual([(f[0], f[1], f[2]) for f in found], [('2026-10', 'KB5129999', '26300.9700')])

    def test_build_key_orders_builds_as_numbers(self):
        self.assertGreater(gu.build_key('26300.10000'), gu.build_key('26300.9700'))
        self.assertEqual(gu.build_key(None), (0,))


if __name__ == '__main__':
    unittest.main(verbosity=1)
