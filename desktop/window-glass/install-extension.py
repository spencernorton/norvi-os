#!/usr/bin/python3
"""Assemble the public v76 extension and the user-session upgrade helper."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
UUID = 'blur-my-shell@aunetx'
SOURCE = HERE / 'sources/blur-my-shell-v76.tar.gz'
SOURCE_HASH = 'bd6fbdfe80ee2368ebe9e377ad72adba66563a5ae78f95ca620c03a947a35835'
MODULES = ('components/applications/index.js', 'components/applications/glass_damage.js',
           'components/applications/glass_policy.js', 'components/applications/native_glass.js',
           'preferences/legacy_blur_notice.js')


def install(stage):
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_HASH:
        raise ValueError('The upstream v76 source archive does not match its recorded digest.')
    extension = stage / 'usr/share/gnome-shell/extensions' / UUID
    manifest = {name: digest for digest, name in
                    (line.split('  ', 1) for line in (HERE / 'upstream.sha256').read_text().splitlines())}
    with tempfile.TemporaryDirectory() as scratch:
        with tarfile.open(SOURCE) as source:
            source.extractall(scratch, filter='data')
        tree = Path(scratch) / 'blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b'
        subprocess.run(['make', '-C', str(tree), 'build'], check=True)
        with zipfile.ZipFile(tree / 'build' / (UUID + '.shell-extension.zip')) as pack:
            for name, expected in manifest.items():
                if hashlib.sha256(pack.read(name)).hexdigest() != expected:
                    raise ValueError(f'The rebuilt upstream module differs from v76: {name}')
            pack.extractall(extension)
    for name in MODULES:
        shutil.copyfile(HERE / 'modules' / name, extension / name)
    subprocess.run(['glib-compile-schemas', '--strict', str(extension / 'schemas')], check=True)
    for src, dst in {
        'prepare-extension': 'usr/libexec/norvi-window-glass/prepare-extension',
        '20-norvi-prepare-extension.conf': 'usr/lib/systemd/user/org.gnome.Shell@ubuntu.service.d/20-norvi-prepare-extension.conf',
        'loader.js': 'usr/share/norvi-window-glass/v76/loader.js',
        'upstream.sha256': 'usr/share/norvi-window-glass/v76/upstream.sha256',
        'NOTICE': 'usr/share/doc/norvi-window-glass/extension-notice',
    }.items():
        target = stage / dst
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(HERE / src, target)


if __name__ == '__main__':
    install(Path(sys.argv[1]).resolve())
