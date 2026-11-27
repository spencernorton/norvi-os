#!/usr/bin/python3 -I
"""Launch the installed Ubuntu service command with a private virtual monitor."""
import hashlib
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

SOURCE = Path(__file__).resolve().parents[2]
VENDOR = Path('/usr/lib/systemd/user')
TEMPLATE = VENDOR / 'org.gnome.Shell@.service'
INSTANCE = VENDOR / 'org.gnome.Shell@ubuntu.service'
GENERATOR = '/usr/lib/systemd/user-generators/norvi-window-glass'
BASE_SHA256 = '896f54a56af9905124eae7ea5d90ad36ef7a8808dd7196ec954db728108017d0'
PACKAGES = {'gnome-shell': '50.1-0ubuntu1.5', 'gnome-shell-common': '50.1-0ubuntu1.5',
            'libmutter-18-0:amd64': '50.1-0ubuntu2.5', 'gir1.2-mutter-18:amd64': '50.1-0ubuntu2.5'}


def reference_build():
    versions = subprocess.run(['dpkg-query', '-W', '-f', '${binary:Package} ${Version}\\n',
                               *PACKAGES], capture_output=True, text=True)
    if versions.returncode not in (0, 1):
        raise RuntimeError(versions.stderr)
    installed = dict(line.split() for line in versions.stdout.splitlines())
    print('Ubuntu package versions', installed, flush=True)
    release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines()
                   if '=' in line)
    if (release.get('ID', '').strip('"'), release.get('VERSION_CODENAME', '').strip('"')) != ('ubuntu', 'resolute') or installed != PACKAGES:
        return False
    # This oracle checks clean Ubuntu files from the tagged source. It never
    # calls the installed selector or trusts the installed Norvi hash manifests.
    manifest = (SOURCE / 'desktop/window-glass/native/ubuntu.sha256').read_bytes()
    if hashlib.sha256(manifest).hexdigest() != BASE_SHA256:
        raise RuntimeError('Update the independent Ubuntu reference before testing a new base')
    for line in manifest.decode().splitlines():
        expected, name = line.split('  ', 1)
        with open(name, 'rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != expected:
                raise RuntimeError(f'The clean reference Ubuntu package has unexpected bytes at {name}')
    return True


def prepare_user_extension():
    hook = VENDOR / 'org.gnome.Shell@ubuntu.service.d/20-norvi-prepare-extension.conf'
    commands = [line.removeprefix('ExecStartPre=-') for line in hook.read_text().splitlines()
                if line.startswith('ExecStartPre=-')]
    if commands != ['/usr/libexec/norvi-window-glass/prepare-extension']:
        raise RuntimeError('The packaged Ubuntu login hook is missing or unexpected')
    subprocess.run(commands, check=True)


def start_command(reference):
    with tempfile.TemporaryDirectory(dir=os.environ['XDG_RUNTIME_DIR']) as temp:
        outputs = [Path(temp) / name for name in ('normal', 'early', 'late')]
        for directory in outputs:
            directory.mkdir()
        subprocess.run([GENERATOR, *outputs], check=True)
        dropin = outputs[0] / 'org.gnome.Shell@ubuntu.service.d/00-norvi-window-glass.conf'
        if reference and not dropin.is_file():
            raise RuntimeError('The matched reference did not generate an Ubuntu Shell drop-in')
        unit = dropin if dropin.exists() else (INSTANCE if INSTANCE.exists() else TEMPLATE)
        commands = [line.removeprefix('ExecStart=') for line in unit.read_text().splitlines()
                    if line.startswith('ExecStart=') and line != 'ExecStart=']
        if len(commands) != 1:
            raise RuntimeError(f'Unexpected GNOME Shell ExecStart in {unit}')
        start = commands[0]
        if dropin.exists() and not start.startswith(':'):
            raise RuntimeError('The generated shell command must preserve its literal variables')
        argv = shlex.split(start.removeprefix(':').replace('%i', 'ubuntu'))
        print('Installed Ubuntu entry', unit.name, argv, flush=True)
        return argv


if __name__ == '__main__':
    os.environ['XDG_SESSION_TYPE'] = 'wayland'
    reference = reference_build()
    opted_out = (Path(os.environ['XDG_CONFIG_HOME']) / 'norvi-window-glass/disable-native').exists()
    os.environ['NORVI_GLASS_VM_SELECTION'] = 'native' if reference and not opted_out else 'stock'
    argv = start_command(reference)
    prepare_user_extension()
    argv += ['--headless', '--wayland', '--virtual-monitor', '1280x800']
    os.execv(argv[0], argv)
