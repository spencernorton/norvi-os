#!/usr/bin/python3
"""Verify an installed v76 extension against its public source and overlay."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

HERE = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('extension', type=Path, nargs='?',
                    default=Path('/usr/share/gnome-shell/extensions/blur-my-shell@aunetx'))
extension = parser.parse_args().extension.resolve()
base = {name: digest for digest, name in
        (line.split('  ', 1) for line in (HERE / 'upstream.sha256').read_text().splitlines())}
modules = {p.relative_to(HERE / 'modules').as_posix(): p for p in (HERE / 'modules').rglob('*.js')}
assert len(modules) == 5
for name in base.keys() | modules.keys():
    data = (extension / name).read_bytes()
    expected = hashlib.sha256(modules[name].read_bytes()).hexdigest() if name in modules else base[name]
    assert hashlib.sha256(data).hexdigest() == expected, name

with tarfile.open(HERE / 'sources/blur-my-shell-v76.tar.gz') as archive:
    entry = 'blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b/LICENSE'
    assert (extension / 'LICENSE').read_bytes() == archive.extractfile(entry).read()
metadata = json.loads((extension / 'metadata.json').read_text())
assert metadata['uuid'] == 'blur-my-shell@aunetx' and metadata['version'] == 76
schema = extension / 'schemas'
assert (schema / 'gschemas.compiled').is_file()
keys = subprocess.check_output(['gsettings', '--schemadir', str(schema), 'list-keys',
                                'org.gnome.shell.extensions.blur-my-shell.applications'], text=True)
assert {'blur', 'pipeline', 'dynamic-opacity', 'opacity', 'rounded-corners'} <= set(keys.splitlines())
print(f'Verified {len(base.keys() | modules.keys())} installed modules/assets, the GPL license, UUID and application schema.')
