# SPDX-License-Identifier: GPL-3.0-or-later
import ctypes
import json
import os
from pathlib import Path

ctypes.CDLL('/usr/lib/x86_64-linux-gnu/libmutter-18.so.0')
lines = Path('/proc/self/maps').read_text().splitlines()
print(json.dumps({'preload': os.environ.get('LD_PRELOAD'), 'audit': os.environ.get('LD_AUDIT'),
                  'marker': os.environ.get('NORVI_WINDOW_GLASS_LAUNCH_PID'), 'maps': sorted(
    {line.split()[-1] for line in lines if ('libmutter-18.so' in line
                                             or 'libmutter-clutter-18.so' in line
                                             or 'norvi-window-glass' in line)})}))
