import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const wait = ms => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
    resolve();
    return GLib.SOURCE_REMOVE;
}));
const check = (condition, message) => { if (!condition) throw new Error(message); };
export default class Acceptance extends Extension {
    enable() {
        const run = () => this.run().catch(error => console.error(`NORVI-SESSION fail: ${error}\n${error.stack}`));
        if (Main.layoutManager._startingUp)
            Main.layoutManager.connect('startup-complete', run);
        else
            run();
    }
    disable() {}
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
        console.log('NORVI-SESSION ready');
    }
}
