// SPDX-License-Identifier: GPL-3.0-or-later
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
export default class LoaderProbe extends Extension {
    enable() {
        // Initialize classes before asking whether the native libraries export the signals.
        GObject.type_class_ref(Clutter.Actor.$gtype);
        GObject.type_class_ref(Meta.WindowActor.$gtype);
        const flags = Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE;
        const child = Gio.Subprocess.new(['/usr/bin/python3', '-I', '/opt/test/child.py'], flags);
        const [, output, error] = child.communicate_utf8(null, null);
        if (!child.get_successful()) throw Error(error);
        const result = {
            bounds: !!GObject.signal_lookup('damaged-with-bounds', Meta.WindowActor.$gtype),
            effects: !!GObject.signal_lookup('norvi-effects-changed', Clutter.Actor.$gtype),
            preload: GLib.getenv('LD_PRELOAD'), audit: GLib.getenv('LD_AUDIT'),
            marker: GLib.getenv('NORVI_WINDOW_GLASS_LAUNCH_PID'),
            child: JSON.parse(output),
        };
        GLib.file_set_contents(GLib.build_filenamev([GLib.get_user_state_dir(), 'result.json']),
                               JSON.stringify(result));
    }
    disable() {}
}
