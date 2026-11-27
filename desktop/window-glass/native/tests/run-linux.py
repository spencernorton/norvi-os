#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-3.0-or-later
"""Test the installed overlay with a private Wayland session and a stock Ubuntu guest view.

Usage: run-linux.py STAGE STOCK_LIB_DEB STOCK_GIR_DEB
The host must supply the matched Ubuntu GNOME Shell, Mesa llvmpipe, bubblewrap
and dbus-daemon. Does not change the host session, packages or home directory.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

TEST = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('stage', type=Path)
parser.add_argument('stock_library', type=Path)
parser.add_argument('stock_gir', type=Path)
args = parser.parse_args()
uid = str(os.getuid())
stage = args.stage.resolve()
base = 'usr/lib/x86_64-linux-gnu'
private = base + '/norvi-window-glass'
with tempfile.TemporaryDirectory() as temp:
    scratch = Path(temp)
    stock = scratch / 'stock'
    stock.mkdir()
    records = []
    for binary in (args.stock_library, args.stock_gir):
        subprocess.run(['dpkg-deb', '-x', binary, stock], check=True)
        record = subprocess.check_output(['dpkg-deb', '-f', binary], text=True)
        records.append('Status: install ok installed\n' + record.rstrip() + '\n')
    for name in ('gnome-shell', 'gnome-shell-common'):
        records.append(subprocess.check_output(['dpkg-query', '-s', name], text=True).rstrip() + '\n')
    status = scratch / 'status'
    original = '\n'.join(records)
    status.write_text(original)
    bus = scratch / 'bus.conf'
    bus.write_text('<busconfig><type>session</type><apparmor mode="disabled"/><listen>unix:tmpdir=/tmp</listen>'
        '<standard_session_servicedirs/><policy context="default"><allow send_destination="*"/>'
        '<allow eavesdrop="true"/><allow own="*"/></policy></busconfig>')
    for name, expect in [('base', 'native'), ('ubuntu-update', 'stock'), ('user-disabled', 'stock'),
                         ('unqualified-library', 'stock'), ('missing-payload', 'stock'),
                         ('missing-selector', 'stock'), ('unsupported-os', 'stock'),
                         ('empty-manifest', 'stock'), ('changed-vendor-unit', 'stock'),
                         ('new-vendor-instance', 'stock')]:
        root = scratch / name
        root.mkdir()
        home = root / 'home'
        state = home / '.local/state'
        state.mkdir(parents=True)
        ext = home / '.local/share/gnome-shell/extensions/native-loader-test@example.invalid'
        ext.mkdir(parents=True)
        shutil.copy2(TEST / 'extension.js', ext)
        (ext / 'metadata.json').write_text(json.dumps(dict(uuid=ext.name,
            name='Native loader test', description='Test fixture', **{'shell-version': ['50']})))
        if name == 'user-disabled':
            flag = home / '.config/norvi-window-glass/disable-native'
            flag.parent.mkdir(parents=True)
            flag.touch()
        status.write_text(original.replace('Version: 50.1-0ubuntu2.5\n',
                          'Version: 50.1-0ubuntu2.6\n') if name == 'ubuntu-update' else original)
        additional_usr = root / 'usr'
        additional_usr.mkdir()
        if name == 'new-vendor-instance':
            instance = additional_usr / 'lib/systemd/user/org.gnome.Shell@ubuntu.service'
            instance.parent.mkdir(parents=True)
            vendor = Path('/usr/lib/systemd/user/org.gnome.Shell@.service').read_text()
            instance.write_text(vendor.replace('--mode=%i', '--mode=ubuntu'))
        cmd = ['bwrap', '--die-with-parent', '--unshare-pid', '--unshare-ipc', '--unshare-net',
               '--unshare-uts', '--new-session', '--overlay-src', '/usr', '--overlay-src', str(stage / 'usr'),
               '--overlay-src', str(additional_usr), '--ro-overlay', '/usr', '--ro-bind', '/etc', '/etc',
               '--ro-bind', '/sys', '/sys', '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/bin', '/bin',
               '--symlink', 'usr/lib64', '/lib64', '--proc', '/proc', '--dev', '/dev',
               '--tmpfs', '/tmp', '--tmpfs', '/var', '--tmpfs', '/run', '--dir', '/run/user',
               '--perms', '0700', '--dir', '/run/user/'+uid, '--dir','/home', '--bind', str(home), '/home/test',
               '--ro-bind', str(status), '/var/lib/dpkg/status', '--ro-bind', str(TEST), '/opt/test',
               '--ro-bind', str(bus), '/opt/bus.conf']
        for obj in sorted((stock / base).rglob('*')):
            if obj.is_file() and not obj.is_symlink() and ('.so.' in obj.name or obj.suffix == '.typelib'):
                cmd += ['--ro-bind', str(obj), '/' + str(obj.relative_to(stock))]
        if name == 'unqualified-library':
            library = Path(base) / 'libmutter-18.so.0.0.0'
            changed = root / 'different-ubuntu-library'
            shutil.copyfile(stock / library, changed)
            with changed.open('ab') as stream: stream.write(b'qualification test')
            cmd += ['--ro-bind', str(changed), '/' + str(library)]
        if name in ('missing-payload', 'empty-manifest', 'unsupported-os', 'changed-vendor-unit'):
            changed = root / 'changed'
            if name == 'empty-manifest':
                target, contents = '/usr/share/norvi-window-glass/native/payload.sha256', ''
            elif name == 'unsupported-os':
                target, contents = '/usr/lib/os-release', 'ID=ubuntu\nVERSION_CODENAME=unknown\n'
            elif name == 'changed-vendor-unit':
                target = '/usr/lib/systemd/user/org.gnome.Shell@.service'
                contents = Path(target).read_text() + '\n# Future vendor template\n'
            else:
                target, contents = '/' + private + '/loader-audit.so', ''
            changed.write_text(contents)
            cmd += ['--ro-bind', str(changed), target]
        if name == 'missing-selector':
            empty = root / 'removed'
            empty.mkdir()
            cmd += ['--ro-bind', str(empty), '/usr/libexec/norvi-window-glass']
        env = dict(HOME='/home/test', USER='test', PATH='/usr/bin:/bin', LANG='C.UTF-8',
                   XDG_RUNTIME_DIR='/run/user/'+uid, XDG_CONFIG_HOME='/home/test/.config',
                   XDG_DATA_HOME='/home/test/.local/share', XDG_CACHE_HOME='/home/test/.cache',
                   XDG_STATE_HOME='/home/test/.local/state', XDG_SESSION_TYPE='wayland',
                   XDG_CURRENT_DESKTOP='ubuntu:GNOME', LIBGL_ALWAYS_SOFTWARE='1',
                   NO_AT_BRIDGE='1', GTK_A11Y='none')
        cmd += ['--clearenv']
        for key, value in env.items(): cmd += ['--setenv', key, value]
        cmd += ['--chdir', '/home/test', 'dbus-run-session', '--config-file=/opt/bus.conf',
                '--', '/usr/bin/python3', '-I', '/opt/test/guest.py', expect, name]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        if result.returncode:
            sys.exit(name + ' failed\n' + result.stdout[-1200:] + result.stderr[-3500:])
        print(name, result.stdout.strip(), flush=True)
