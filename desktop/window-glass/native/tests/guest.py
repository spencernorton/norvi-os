# SPDX-License-Identifier: GPL-3.0-or-later
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time

state = Path(os.environ['XDG_STATE_HOME'])
proc = Path('/proc')
os.environ['DBUS_SYSTEM_BUS_ADDRESS'] = os.environ['DBUS_SESSION_BUS_ADDRESS']
expected = sys.argv[1] == 'native'
subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions',
                "['native-loader-test@example.invalid']"], check=True)
subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'disable-user-extensions', 'false'], check=True)
with (state / 'shell.log').open('w') as log:
    generated = state / 'generated/org.gnome.Shell@ubuntu.service.d/00-norvi-window-glass.conf'
    subprocess.run(['/usr/lib/systemd/user-generators/norvi-window-glass', str(state / 'generated'),
                    str(state / 'early'), str(state / 'late')], check=True)
    if sys.argv[2] in ('changed-vendor-unit', 'new-vendor-instance'):
        assert not generated.exists()
        filename = 'org.gnome.Shell@ubuntu.service' if sys.argv[2] == 'new-vendor-instance' else 'org.gnome.Shell@.service'
        vendor = (Path('/usr/lib/systemd/user') / filename).read_text()
        start = next(line.removeprefix('ExecStart=') for line in vendor.splitlines()
                     if line.startswith('ExecStart='))
        cmd = shlex.split(start.replace('%i', 'ubuntu'))
    else:
        assert list((state / 'generated').rglob('*.conf')) == [generated]
        start = next(line.removeprefix('ExecStart=:') for line in generated.read_text().splitlines()
                     if line.startswith('ExecStart=:'))
        cmd = shlex.split(start)
        assert cmd[0] == '/bin/sh' and cmd[-1] == '--mode=ubuntu', cmd
    shell = subprocess.Popen([*cmd, '--headless', '--no-x11', '--wayland-display=test-wayland',
                             '--virtual-monitor', '1024x768@60'], stdout=log, stderr=log)
    try:
        resultfile = state / 'result.json'
        end = time.monotonic() + 22
        while not resultfile.exists() and shell.poll() is None and time.monotonic() < end:
            time.sleep(.1)
        if not resultfile.exists(): raise RuntimeError((state / 'shell.log').read_text()[-4000:])
        result = json.loads(resultfile.read_text())
        own = proc / str(shell.pid)
        lines = (own / 'maps').read_text().splitlines()
        result.update(exe=os.readlink(own / 'exe'), comm=(own / 'comm').read_text().strip(),
                      maps=sorted({line.split()[-1] for line in lines
                                   if 'norvi-window-glass' in line or 'libmutter-18.so' in line
                                   or 'libmutter-clutter-18.so' in line}))
        print(json.dumps(result, sort_keys=True))
        assert result['bounds'] == result['effects'] == expected
        assert result['exe'] == '/usr/bin/gnome-shell' and result['comm'] == 'gnome-shell'
        assert all(result[key] is None and result['child'][key] is None for key in ('preload', 'audit', 'marker'))
        assert all('norvi-window-glass' not in path for path in result['child']['maps'])
        assert len(result['child']['maps']) == 2, result
        private = [path for path in result['maps'] if 'norvi-window-glass' in path]
        assert len(private) == (3 if expected else 0), result
        assert len(result['maps']) == (3 if expected else 2), result
        assert b'norvi-window-glass' not in (own / 'environ').read_bytes()
        assert b'NORVI_WINDOW_GLASS_LAUNCH_PID' not in (own / 'environ').read_bytes()
    finally:
        shell.terminate()
        try: shell.wait(timeout=5)
        except subprocess.TimeoutExpired:
            shell.kill()
            shell.wait()
