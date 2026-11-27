#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-3.0-or-later
"""Stage the private library pair from a local, patched Ubuntu binary build."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ARCH = 'x86_64-linux-gnu'
PRIVATE = Path('usr/lib') / ARCH / 'norvi-window-glass'
DATA = Path('usr/share/norvi-window-glass/native')
LIBRARIES = {
    f'usr/lib/{ARCH}/mutter-18/libmutter-clutter-18.so.0': b'norvi-effects-changed\0',
    f'usr/lib/{ARCH}/libmutter-18.so.0': b'damaged-with-bounds\0',
}


def seal(stage):
    lines = []
    for name in ('loader-audit.so', *(Path(item).name for item in LIBRARIES)):
        relative = PRIVATE / name
        with (stage / relative).open('rb') as stream:
            lines.append(f'{hashlib.file_digest(stream, "sha256").hexdigest()}  /{relative}\n')
    (stage / DATA / 'payload.sha256').write_text(''.join(lines))


def install(binary, stage):
    control = subprocess.check_output(['dpkg-deb', '-f', binary, 'Package', 'Architecture'], text=True)
    if control.splitlines() != ['Package: libmutter-18-0', 'Architecture: amd64']:
        raise SystemExit('Expected an amd64 libmutter-18-0 build.')
    with tempfile.TemporaryDirectory() as scratch:
        extracted = Path(scratch)
        subprocess.run(['dpkg-deb', '-x', binary, extracted], check=True)
        libdir = stage / PRIVATE
        libdir.mkdir(parents=True, exist_ok=True)
        for relative, signal in LIBRARIES.items():
            source = extracted / relative
            if signal not in source.read_bytes():
                raise SystemExit(f'Patched signal missing from {source.name}')
            shutil.copyfile(source, libdir / source.name)
        subprocess.run(['cc', '-O2', '-fPIC', '-shared', '-Wall', '-Wextra', '-Werror',
                        '-Wl,-z,relro,-z,now,--build-id=sha1', str(HERE / 'loader-audit.c'),
                        '-o', str(libdir / 'loader-audit.so')], check=True)
        for relative, source in {
            'usr/libexec/norvi-window-glass/compatible': HERE / 'compatible',
            'usr/lib/systemd/user-generators/norvi-window-glass': HERE / 'generator',
            DATA / 'ubuntu.sha256': HERE / 'ubuntu.sha256',
            'usr/share/doc/norvi-window-glass/mutter-copyright':
                extracted / 'usr/share/doc/libmutter-18-0/copyright',
        }.items():
            destination = stage / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        for name in ['loader-audit.so', *(Path(item).name for item in LIBRARIES)]:
            (libdir / name).chmod(0o644)
        seal(stage)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('binary', nargs='?', type=Path,
                        help='Patched Ubuntu build. Omit to seal the final payload after Debian stripping.')
    args = parser.parse_args()
    if args.binary:
        install(args.binary.resolve(), args.stage)
    else:
        seal(args.stage)
