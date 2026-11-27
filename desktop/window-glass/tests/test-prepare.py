#!/usr/bin/python3
"""Test user-owned files against the checked-in v76 source and manifest."""
import hashlib
import os
from pathlib import Path
import runpy
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

HERE = Path(__file__).resolve().parents[1]
BRIDGE = runpy.run_path(str(HERE / 'prepare-extension'))
prepare = BRIDGE['prepare']
ENTRIES = BRIDGE['ENTRIES']
MANIFEST = {name: digest for digest, name in
        (line.split('  ', 1) for line in (HERE / 'upstream.sha256').read_text().splitlines())}


class BridgeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = {}
        with tarfile.open(HERE / 'sources/blur-my-shell-v76.tar.gz') as source:
            members = set(source.getnames())
            for name, expected in MANIFEST.items():
                choices = ['blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b/' + prefix + name for prefix in ('', 'src/', 'resources/')]
                member = next(candidate for candidate in choices if candidate in members)
                data = source.extractfile(member).read()
                assert hashlib.sha256(data).hexdigest() == expected, name
                cls.original[name] = data
            templates = {name.split('/resources/')[1] for name in members
                         if '/resources/ui/' in name and name.endswith('.ui')}
            assert templates == {name for name in MANIFEST if name.startswith('ui/')}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.user = self.base / 'user'
        self.system = self.base / 'system'
        self.system.mkdir()
        for name in ENTRIES:
            (self.system / name).write_text('packaged')
        for name, data in self.original.items():
            target = self.user / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)

    def enable(self):
        return prepare(self.user, HERE, self.system)

    def assertOriginal(self, *names):
        for name in names:
            entry = self.user / name
            self.assertFalse(entry.is_symlink())
            self.assertEqual(entry.read_bytes(), self.original[name])

    def test_independent_dispatch_and_restore(self):
        (self.user / 'prefs.js').chmod(0o640)
        self.assertTrue(self.enable())
        wrappers = [self.user / name for name in ENTRIES]
        marker, = self.user.glob('.norvi-glass-loader-*.js')
        inodes = {p.stat().st_ino for p in [marker, *wrappers]}
        self.assertEqual(len(inodes), 3)
        self.assertTrue(self.enable())
        self.assertEqual({p.stat().st_ino for p in [marker, *wrappers]}, inodes)
        self.assertEqual((self.user / 'prefs.js').stat().st_mode & 0o777, 0o640)
        prepare(self.user, HERE, self.system, restore=True)
        self.assertOriginal(*ENTRIES)
        self.assertFalse(any(self.user.glob('.norvi-*')))

    def test_in_place_upstream_zip_and_independent_user_edit(self):
        self.assertTrue(self.enable())
        release = self.base / 'update.zip'
        with zipfile.ZipFile(release, 'w') as pack:
            for name in ENTRIES:
                pack.writestr(name, self.original[name])
        with zipfile.ZipFile(release) as pack:
            pack.extractall(self.user)
        self.assertOriginal(*ENTRIES)
        self.assertTrue(self.enable())
        # Many editors open the destination and truncate it in place.
        (self.user / 'extension.js').write_text('export default class MyExtension {}')
        self.assertNotEqual((self.user / 'prefs.js').read_text(), (self.user / 'extension.js').read_text())
        self.assertFalse(self.enable())
        self.assertEqual((self.user / 'extension.js').read_text(), 'export default class MyExtension {}')
        self.assertOriginal('prefs.js')

    def test_full_new_release_is_preserved(self):
        self.assertTrue(self.enable())
        for name in ['metadata.json', *ENTRIES]:
            (self.user / name).write_bytes(self.original[name] + b'\n')
        self.assertFalse(self.enable())
        for name in ['metadata.json', *ENTRIES]:
            self.assertEqual((self.user / name).read_bytes(), self.original[name] + b'\n')

    def test_old_shared_dispatch_symlinks_become_independent_files(self):
        self.assertTrue(self.enable())
        marker, = self.user.glob('.norvi-glass-loader-*.js')
        for name in ENTRIES:
            entry = self.user / name
            entry.unlink()
            entry.symlink_to(marker.name)
        self.assertTrue(self.enable())
        entries = [self.user / name for name in ENTRIES]
        self.assertTrue(all(not entry.is_symlink() for entry in entries))
        self.assertEqual(len({file.stat().st_ino for file in [marker, *entries]}), 3)

    def test_custom_template_and_shader_decline_or_restore(self):
        shader = next(name for name in MANIFEST if name.endswith('.glsl'))
        for name in ['ui/applications.ui', shader]:
            with self.subTest(name=name):
                self.assertTrue(self.enable())
                changed = self.original[name] + b'\n'
                (self.user / name).write_bytes(changed)
                self.assertFalse(self.enable())
                self.assertOriginal(*ENTRIES)
                self.assertFalse(self.enable())
                self.assertEqual((self.user / name).read_bytes(), changed)
                (self.user / name).write_bytes(self.original[name])

    def test_interrupted_second_entry_recovers_and_preserves_user_replacement(self):
        replace = os.replace
        def stop_prefs(source, target):
            if target == self.user / 'prefs.js':
                raise OSError('simulated interrupted preparation')
            replace(source, target)
        with patch('os.replace', stop_prefs), self.assertRaises(OSError):
            self.enable()
        self.assertOriginal('prefs.js')
        self.assertNotEqual((self.user / 'extension.js').read_bytes(), self.original['extension.js'])
        self.assertTrue(self.enable())
        replacement = self.base / 'replacement'
        replacement.write_text('export default class MyPreferences {}')
        replace(replacement, self.user / 'prefs.js')
        self.assertFalse(self.enable())
        self.assertOriginal('extension.js')
        self.assertEqual((self.user / 'prefs.js').read_text(), 'export default class MyPreferences {}')

    def test_declines_external_symlinks_and_foreign_reserved_files(self):
        external = self.base / 'external'
        original = self.user / 'prefs.js'
        original.rename(external)
        original.symlink_to(external)
        self.assertFalse(self.enable())
        self.assertEqual(external.read_bytes(), self.original['prefs.js'])
        original.unlink()
        external.rename(original)
        saved = self.user / '.norvi-v76-prefs.js'
        saved.write_text('mine')
        self.assertFalse(self.enable())
        self.assertEqual(saved.read_text(), 'mine')
        self.assertOriginal(*ENTRIES)


if __name__ == '__main__':
    unittest.main()
