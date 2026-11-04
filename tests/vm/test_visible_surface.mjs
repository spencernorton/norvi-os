// Runs with Node locally and with the guest's real GJS before VM acceptance.
import {hasVisibleSurface, waitForVisibleSurface} from './session-probe/visible-surface.js';

function check(condition, message) {
    if (!condition)
        throw new Error(message);
}

let clock = 0;
let waits = 0;
const actor = {mapped: true, width: 0, height: 0};
const app = {get_windows: () => [{get_compositor_private: () => actor}]};
const deadline = await waitForVisibleSurface(app, 'synthetic.desktop', {
    now: () => clock,
    wait: async milliseconds => {
        clock += milliseconds * 1000;
        if (++waits === 2) {
            actor.width = 640;
            actor.height = 480;
        }
    },
    describe: () => [],
});
check(waits === 2 && clock === 500000, 'A mapped empty actor must wait for allocation');
check(deadline === 30000000, 'The existing thirty-second budget must remain unchanged');
check(hasVisibleSurface(app), 'The allocated surface must be accepted');
actor.mapped = false;
check(!hasVisibleSurface(app), 'A disappearing window must still fail the later stability check');

for (const windows of [[], [null], [{mapped: false, width: 640, height: 480}],
                       [{mapped: true, width: 0, height: 480}], [{mapped: true, width: 640, height: 0}]]) {
    clock = 0;
    let refused = false;
    try {
        await waitForVisibleSurface({get_windows: () => windows.map(value => ({
            get_compositor_private: () => value,
        }))}, 'missing.desktop', {
            now: () => clock,
            wait: async milliseconds => { clock += milliseconds * 1000; },
            describe: () => [],
        });
    } catch (error) {
        refused = error.message.startsWith('No visible packaged application window: missing.desktop');
    }
    check(refused && clock === 30000000, 'Absent, unmapped and empty surfaces must time out');
}
console.log('PASS: delayed allocation, visibility, stability and bounded refusal');
