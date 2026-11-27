#!/usr/bin/python3
"""Exercise the dispatcher with real GJS in temporary user and package trees."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ENTRIES = ('extension.js', 'prefs.js')


@unittest.skipUnless(shutil.which('gjs'), 'GJS is required for URI and Gio rollback checks')
class LoaderTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.user = self.base / 'user'
        self.system = self.base / 'system'
        self.companion = self.base / 'companion'
        self.user.mkdir()
        self.system.mkdir()
        source = (HERE / 'loader.js').read_text()
        # Only the two absolute package locations are relocated for this
        # fixture. The checksums and dispatcher code are used verbatim.
        source = source.replace('/usr/share/gnome-shell/extensions/blur-my-shell@aunetx/', self.system.as_posix() + '/')
        source = source.replace('/usr/share/norvi-window-glass/v76/loader.js', self.companion.as_posix())
        data = source.encode()
        self.marker = self.user / ('.norvi-glass-loader-' + hashlib.sha256(data).hexdigest() + '.js')
        self.marker.write_bytes(data)
        for name in ENTRIES:
            (self.user / name).write_bytes(data)
            (self.system / name).write_text("export {default} from './sibling.js';")
            (self.user / ('.norvi-v76-' + name)).write_text("export {default} from './sibling.js';")
        (self.system / 'sibling.js').write_text('export default "system";')
        (self.user / 'sibling.js').write_text('export default "user";')
        self.companion.touch()

    def run_entry(self, name):
        driver = self.base / 'driver.js'
        driver.write_text('import value from ' + json.dumps((self.user / name).as_uri()) + '; print(value);')
        result = subprocess.run(['gjs', '-m', driver], capture_output=True, text=True, check=True)
        self.assertEqual(result.stderr, '')
        return result.stdout.strip()

    def test_uri_selection_and_independent_restoration(self):
        for active, other in [ENTRIES, tuple(reversed(ENTRIES))]:
            with self.subTest(active=active):
                self.companion.touch()
                self.assertEqual(self.run_entry(active), 'system')
                with tarfile.open(HERE / 'sources/blur-my-shell-v76.tar.gz') as source:
                    original = source.extractfile('blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b/src/' + other).read()
                backup = self.user / ('.norvi-v76-' + other)
                backup.write_bytes(original)
                # The unaltered public checksum authorizes restoring the other
                # real entry. Our synthetic active backup remains untouched.
                self.companion.unlink()
                self.assertEqual(self.run_entry(active), 'user')
                self.assertEqual((self.user / other).read_bytes(), original)
                self.assertTrue(self.marker.exists())
                (self.user / other).write_bytes(self.marker.read_bytes())
                backup.write_text("export {default} from './sibling.js';")

    def test_runtime_removal_preserves_external_entry_edit(self):
        user_prefs = self.user / 'prefs.js'
        user_prefs.write_text('export default "custom preferences";')
        self.companion.unlink()
        self.assertEqual(self.run_entry('extension.js'), 'user')
        self.assertEqual(self.run_entry('prefs.js'), 'custom preferences')

    @unittest.skipUnless(Path('/usr/share/gnome-shell/org.gnome.Shell.Extensions.src.gresource').is_file()
                         and shutil.which('glib-compile-schemas'), 'requires GNOME Shell preferences and GLib')
    def test_shell_metadata_keeps_user_schema_with_packaged_modules(self):
        schema = 'org.gnome.shell.extensions.blur-my-shell'
        with tarfile.open(HERE / 'sources/blur-my-shell-v76.tar.gz') as source:
            xml = source.extractfile('blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b/schemas/' + schema + '.gschema.xml').read()
        for path, default in [(self.user, 'false'), (self.system, 'true')]:
            schemas = path / 'schemas'
            schemas.mkdir()
            (schemas / (schema + '.gschema.xml')).write_bytes(xml)
            (schemas / '99-fixture.gschema.override').write_text('[' + schema + ']\ndebug=' + default + '\n')
            subprocess.run(['glib-compile-schemas', '--strict', schemas], check=True)
        (self.system / 'prefs.js').write_text("""
            import {ExtensionBase} from 'resource:///org/gnome/Shell/Extensions/js/extensions/sharedInternals.js';
            export default class Preferences extends ExtensionBase {}
        """)
        driver = self.base / 'schema-driver.js'
        driver.write_text("""
            import Gio from 'gi://Gio';
            const resource = Gio.Resource.load('/usr/share/gnome-shell/org.gnome.Shell.Extensions.src.gresource');
            Gio.resources_register(resource);
            const dir = Gio.File.new_for_path(ARGV[0]);
            const {default: Preferences} = await import(dir.get_child('prefs.js').get_uri());
            const prefs = new Preferences({uuid: 'blur-my-shell@aunetx', dir, path: dir.get_path(), 'settings-schema': ARGV[1]});
            const settings = prefs.getSettings();
            print(JSON.stringify([settings.settings_schema.has_key('pipelines'), settings.get_default_value('debug').get_boolean()]));
        """)
        result = subprocess.run(['gjs', '-m', driver, self.user, schema], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), [True, False])


if __name__ == '__main__':
    unittest.main()
