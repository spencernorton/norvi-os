import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import GioUnix from 'gi://GioUnix';
import Shell from 'gi://Shell';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const wait = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));
const check = (condition, message) => { if (!condition) throw new Error(message); };
export default class Acceptance extends Extension {
    enable() {
        const run = () => {
            if (this._startupId)
                Main.layoutManager.disconnect(this._startupId);
            this._startupId = 0;
            this.run().catch(error => console.error(`NORVI-SESSION fail: ${error}\n${error.stack}`));
        };
        if (Main.layoutManager._startingUp)
            this._startupId = Main.layoutManager.connect('startup-complete', run);
        else
            run();
    }
    disable() {
        if (this._startupId)
            Main.layoutManager.disconnect(this._startupId);
        this._startupId = 0;
    }
    async run() {
        const uuids = [
            'xdock@spencercnorton.github.io', 'workspace-bar@spencercnorton.github.io',
            'transparent-top-bar@spencercnorton.github.io', 'power-only-quicksettings@spencercnorton.github.io',
            'lock-screen-suite@spencercnorton.github.io', 'wallpaper-suite@spencercnorton.github.io',
            'xnote-placement@spencercnorton.github.io',
        ];
        const expected = [...uuids, 'blur-my-shell@aunetx'];
        const deadline = GLib.get_monotonic_time() + 60000000;
        while (!expected.every(uuid => Main.extensionManager.lookup(uuid)?.state === 1)) {
            check(GLib.get_monotonic_time() < deadline,
                `Extensions did not become active: ${expected.map(uuid => `${uuid}=${Main.extensionManager.lookup(uuid)?.state}`).join(', ')}`);
            await wait(250);
        }
        for (const uuid of uuids) {
            const extension = Main.extensionManager.lookup(uuid);
            check(extension?.state === 1, `${uuid} failed to load: ${extension?.state} ${extension?.error}`);
            check(extension.path === `/usr/share/gnome-shell/extensions/${uuid}`, `${uuid} is shadowed by a user copy`);
            console.log(`NORVI-SESSION loaded: ${uuid}`);
        }
        const bms = Main.extensionManager.lookup('blur-my-shell@aunetx');
        check(bms?.state === 1, `Blur my Shell failed: ${bms?.state} ${bms?.error}`);
        Main.overview.hide();
        Main.panel.statusArea.quickSettings.menu.open();
        await wait(500);
        check(Main.panel.statusArea.quickSettings.menu.isOpen, 'Quick Settings did not open');
        Main.panel.statusArea.quickSettings.menu.close();
        const dock = Main.extensionManager.lookup(uuids[0]);
        const {DockManager} = await import(`file://${dock.path}/docking.js`);
        const manager = DockManager.getDefault();
        check(manager.mainDock?.mapped, 'Packaged dock is not mapped');
        manager._appLauncher.open(manager.mainDock.dash.showAppsButton);
        await wait(500);
        check(manager._appLauncher._menu?.isOpen, 'Packaged application launcher did not open');
        manager._appLauncher.close({animate: false});
        // Launch the installed entry points in this guest's synthetic profile.
        // No source-tree launcher or development dependency can stand in for
        // the packaged GTK/Qt applications and their runtime dependencies.
        for (const [id, action] of [
            ['xnote.desktop', null],
            ['tech.norvi.snipsnap.desktop', 'Configure'],
            ['dev.norvi.Timecrate.desktop', null],
        ]) {
            const path = `/usr/share/applications/${id}`;
            const entry = GioUnix.DesktopAppInfo.new_from_filename(path);
            check(entry?.get_filename() === path, `Installed desktop entry missing: ${id}`);
            const context = global.create_app_launch_context(0, -1);
            if (action)
                entry.launch_action(action, context);
            else
                check(entry.launch([], context), `Could not launch ${id}`);
            let marker;
            if (id === 'xnote.desktop') {
                // An empty XNote profile without a tray intentionally exits
                // when there is no note. Exercise its actual document command.
                marker = `NorviOS acceptance ${GLib.uuid_string_random()}`;
                const file = `${GLib.get_home_dir()}/acceptance-note.txt`;
                GLib.file_set_contents(file, `${marker}\n`);
                await wait(500);
                const launcher = new Gio.SubprocessLauncher({flags: Gio.SubprocessFlags.NONE});
                launcher.set_environ(context.get_environment());
                launcher.spawnv(['/usr/bin/xnote', '--new-from-file', file]);
            }
            const app = Shell.AppSystem.get_default().lookup_app(id);
            check(app, `Installed application is not registered: ${id}`);
            const until = GLib.get_monotonic_time() + 30000000;
            while (!app?.get_windows().some(window => window.get_compositor_private()?.mapped)) {
                const windows = global.get_window_actors().map(actor => ({
                    title: actor.meta_window.get_title(),
                    app: Shell.WindowTracker.get_default().get_window_app(actor.meta_window)?.get_id(),
                }));
                check(GLib.get_monotonic_time() < until,
                    `No mapped packaged application window: ${id}; observed ${JSON.stringify(windows)}`);
                await wait(250);
            }
            await wait(250);
            check(app.get_windows().some(window => {
                const actor = window.get_compositor_private();
                return actor?.mapped && actor.width > 0 && actor.height > 0;
            }), `Packaged application has no visible surface: ${id}`);
            if (marker) {
                const notes = Gio.File.new_for_path(`${GLib.get_user_config_dir()}/xnote`);
                const persisted = () => {
                    if (!notes.query_exists(null))
                        return false;
                    const files = notes.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
                    try {
                        for (let file; (file = files.next_file(null));) {
                            if (!file.get_name().startsWith('content-'))
                                continue;
                            const [, bytes] = GLib.file_get_contents(notes.get_child(file.get_name()).get_path());
                            if (new TextDecoder().decode(bytes).includes(marker))
                                return true;
                        }
                        return false;
                    } finally {
                        files.close(null);
                    }
                };
                while (!persisted()) {
                    check(GLib.get_monotonic_time() < until, 'XNote did not persist the synthetic document');
                    await wait(250);
                }
                console.log('NORVI-SESSION XNote document persisted');
            }
            console.log(`NORVI-SESSION application: ${id}`);
            app.request_quit();
            await wait(500);
        }
        console.log('NORVI-SESSION ready');
    }
}
