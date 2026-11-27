// SPDX-License-Identifier: GPL-3.0-or-later
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
import {resolve, sep} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

// Set the extension directory to exercise exact installed/package-stage bytes.
const installed = process.env.NORVI_GLASS_TEST_EXTENSION;
const root = installed ? pathToFileURL(resolve(installed) + sep) : new URL('../modules/', import.meta.url);
const app = new URL('components/applications/', root);
const policy = await import(new URL('glass_policy.js', app));
async function sourceText(file) {
    if (!installed && file === '../../conveniences/connections.js') {
        const archive = fileURLToPath(new URL('../sources/blur-my-shell-v76.tar.gz', import.meta.url));
        return execFileSync('tar', ['-xOzf', archive,
            'blur-my-shell-19ce844b8ca36efe4a181b2cf81504063eb4ce4b/src/conveniences/connections.js'],
            {encoding: 'utf8'});
    }
    return readFile(new URL(file, app), 'utf8');
}
const single = (params = {}) => ({effects: [{type: 'dual_kawase_blur', params}]});
const rect = (x, y, width, height) => ({x, y, width, height});

test('only equivalent v76 controls can select the native material', () => {
    assert.deepEqual(policy.nativeMaterial(single(), 0), {radius: 30, brightness: 0.6});
    assert.deepEqual(policy.nativeMaterial(single({unscaled_radius: 65, brightness: .9}), 0),
        {radius: 65, brightness: .9});
    for (const pipeline of [null, {effects: []}, {effects: [...single().effects, ...single().effects]},
        {effects: [{type: 'refraction'}]}, single({unsupported: 1}), single({opacity_factor: .2}),
        single({unscaled_radius: 0}), single({unscaled_radius: 0.25}), single({unscaled_radius: 30.5}),
        single({brightness: 1.2}), single({unscaled_radius: NaN})])
        assert.equal(policy.nativeMaterial(pipeline, 0), null);
    for (const selection of [1, 2])
        assert.equal(policy.nativeMaterial(single(), selection), null);
});

test('dirty bounds enter through direct edges and propagate the complete blurred pane', () => {
    const entry = (window, x, workspace = 1, sticky = false) =>
        ({window, rect: rect(x, 0, 100, 100), workspace, sticky, effect: {}});
    const entries = [entry('rear', 0), entry('middle', 60), entry('front', 130),
        entry('other workspace', 100, 2), entry('elsewhere', 320)];
    const targets = (graph, source, region) =>
        Array.from(policy.affectedPanes(graph, source, region), pane => pane.window);
    const graph = policy.buildGraph(entries);
    assert.deepEqual(targets(graph, 'rear', rect(10, 10, 4, 4)), []);
    assert.deepEqual(targets(graph, 'rear', rect(80, 10, 4, 4)), ['middle', 'front']);
    assert.deepEqual(targets(graph, 'front', rect(135, 10, 4, 4)), []);
    assert.deepEqual(targets(graph, 'rear', rect(57, 10, 3, 4)), ['middle', 'front']);
    assert.equal(policy.affectedPanes(graph, 'rear', null), null);
    assert.equal(policy.affectedPanes(graph, 'rear', rect(-2, 0, 3, 3)), null);
    assert.equal(policy.affectedPanes(graph, 'missing', rect(80, 10, 4, 4)), null);
    entries[3].sticky = true;
    assert.deepEqual(targets(policy.buildGraph(entries), 'rear', rect(80, 10, 4, 4)),
        ['middle', 'front', 'other workspace']);
});

// Execute the actual GNOME modules, replacing only their GJS imports. This
// keeps the graph, signal choice, lifecycle and focus entry points under test.
async function gjs(file, imports, globals = {}) {
    const context = vm.createContext({global: globals, console});
    const module = new vm.SourceTextModule(await sourceText(file), {context});
    await module.link(name => {
        assert.ok(Object.hasOwn(imports, name), name);
        const values = imports[name];
        return new vm.SyntheticModule(Object.keys(values), function () {
            for (const [key, value] of Object.entries(values))
                this.setExport(key, value);
        }, {context});
    });
    await module.evaluate();
    return module.namespace;
}

class Emitter {
    handlers = new Map();
    next = 1;
    connect(signal, callback) {
        const id = this.next++;
        this.handlers.set(id, {signal, callback});
        return id;
    }
    disconnect(id) { this.handlers.delete(id); }
    emit(name, ...args) {
        for (const {signal, callback} of [...this.handlers.values()]) {
            if (signal === name) callback(this, ...args);
        }
    }
}

class Actor extends Emitter {
    children = [];
    effects = [];
    visible = true;
    mapped = true;
    constructor(parent, bounds) {
        super();
        this.parent = parent;
        this.bounds = bounds;
        parent?.children.push(this);
    }
    get_parent() { return this.parent; }
    get_children() { return this.children; }
    get_effects() { return [...this.effects]; }
    has_effects() { return this.effects.length > 0; }
    has_allocation() { return true; }
    has_mapped_clones() { return Boolean(this.cloned); }
    get_transformed_position() { return [this.bounds.x, this.bounds.y]; }
    get_transformed_size() { return [this.bounds.width, this.bounds.height]; }
}

async function scene(notified) {
    const pending = new Map();
    let next = 1;
    const laters = {
        add(_, callback) { const id = next++; pending.set(id, callback); return id; },
        remove(id) { pending.delete(id); },
    };
    const stage = new Actor(null, rect(0, 0, 800, 600));
    const window_group = new Actor(stage, stage.bounds);
    const layoutManager = Object.assign(new Emitter(), {monitors: [{...stage.bounds, geometry_scale: 1}]});
    const Main = {actionMode: 1, overview: Object.assign(new Emitter(), {visible: false}), layoutManager};
    const global = {stage, window_group, display: new Emitter(), window_manager: new Emitter(),
        compositor: {get_laters: () => laters}, get_window_actors: () => window_group.children};
    const GObject = {signal_lookup: signal => signal === 'norvi-effects-changed' && notified ? 1 : 0};
    const {Connections} = await gjs('../../conveniences/connections.js', {'gi://GObject': {default: GObject}});
    const {GlassDamage} = await gjs('glass_damage.js', {
        'gi://GObject': {default: GObject}, 'gi://Clutter': {default: {Actor: {$gtype: {}}}},
        'gi://Meta': {default: {LaterType: {BEFORE_REDRAW: 1}}},
        'gi://GLib': {default: {get_monotonic_time: () => 1000, SOURCE_REMOVE: false, SOURCE_CONTINUE: true}},
        'gi://Shell': {default: {ActionMode: {NORMAL: 1}}},
        'resource:///org/gnome/shell/ui/main.js': Main, '../../conveniences/connections.js': {Connections},
        './glass_policy.js': policy,
    }, global);
    const tracker = new GlassDamage();
    const panes = [0, 60, 130, 390].map(x => {
        const bounds = rect(x, 0, 100, 100);
        const actor = new Actor(window_group, bounds);
        const window = Object.assign(new Emitter(), {get_frame_rect: () => bounds,
            get_workspace: () => 1, is_on_all_workspaces: () => false});
        actor.meta_window = window;
        const source = new Actor(actor, bounds);
        const material = new Actor(actor, bounds);
        const effect = {calls: 0, invalidate() { this.calls++; }};
        material.effects = [effect];
        const blocker = Object.assign(new Emitter(), {enabled: true});
        actor.effects = [blocker];
        tracker.setPane(window, {actor: material, effect, blocker});
        return {actor, window, source, material, effect};
    });
    const drain = () => {
        for (const [id, callback] of [...pending]) {
            pending.delete(id);
            assert.equal(callback(), false);
        }
    };
    drain();
    const clear = () => panes.forEach(({effect}) => { effect.calls = 0; });
    const counts = () => panes.map(({effect}) => effect.calls);
    const send = (i, damage) => panes[i].actor.emit('damaged-with-bounds', damage);
    clear();
    return {panes, global, Main, tracker, drain, clear, counts, send};
}

for (const notified of [true, false]) {
    test('source and target effects, geometry, and cleanup with membership signal ' + notified, async () => {
        const {panes, global, Main, tracker, drain, clear, counts, send} = await scene(notified);
        const outside = rect(10, 10, 4, 4);
        for (const pane of panes) {
            const signals = [...pane.actor.handlers.values()].map(v => v.signal);
            assert.equal(signals.filter(s => s === 'damaged-with-bounds').length, 1);
            assert.ok(!signals.includes('damaged'));
        }
        send(0, outside);
        assert.deepEqual(counts(), [0, 0, 0, 0]);
        send(0, rect(80, 10, 4, 4));
        assert.deepEqual(counts(), [0, 1, 1, 0]);
        for (const branch of [panes[3].material, panes[3].source]) {
            const foreign = Object.assign(new Emitter(), {enabled: true});
            const membership = () => {
                if (notified) branch.emit('norvi-effects-changed');
                else global.stage.emit('before-update');
                drain();
                clear();
            };
            branch.effects.push(foreign);
            membership();
            send(2, rect(134, 10, 4, 4));
            assert.deepEqual(counts(), [1, 1, 1, 1]);
            foreign.enabled = false;
            foreign.emit('notify', {name: 'enabled'});
            drain(); clear(); send(0, outside);
            assert.deepEqual(counts(), [0, 0, 0, 0]);
            const replacement = Object.assign(new Emitter(), {enabled: true});
            branch.effects[branch.effects.indexOf(foreign)] = replacement;
            membership(); send(0, outside);
            assert.deepEqual(counts(), [1, 1, 1, 1]);
            branch.effects.splice(branch.effects.indexOf(replacement), 1);
            membership(); send(0, outside);
            assert.deepEqual(counts(), [0, 0, 0, 0]);
        }
        send(0, null);
        assert.deepEqual(counts(), [1, 1, 1, 1]);
        for (const alter of [
            () => { Main.overview.visible = true; },
            () => { Main.overview.visible = false; tracker.grab = true; },
            () => { tracker.grab = false; Main.layoutManager.monitors.push({x: 800, y: 0, width: 200, height: 300, geometry_scale: 2}); tracker.topologyChanged(); },
            () => { Main.layoutManager.monitors.pop(); panes[2].material.cloned = true; tracker.topologyChanged(); },
        ]) {
            alter(); drain(); clear(); send(0, outside);
            assert.deepEqual(counts(), [1, 1, 1, 1]);
        }
        tracker.destroy();
        assert.equal(global.stage.handlers.size, 0);
        for (const {actor, window, source, material} of panes)
            for (const node of [actor, window, source, material])
                assert.equal(node.handlers.size, 0);
    });
}

async function applications(globals, native = true) {
    const {ApplicationsBlur} = await gjs('index.js', {
        'gi://Gio': {default: {}}, 'gi://Meta': {default: {}},
        'resource:///org/gnome/shell/ui/main.js': {},
        '../../dbus/services.js': {ApplicationsService: class {}},
        '../../pipelines/pipeline.js': {Pipeline: class {}},
        '../../conveniences/window.js': {is_desktop_window: () => false},
        '../../render/dynamic_surface.js': {DynamicPipeline: class {}},
        '../../render/rounded_pipeline.js': {RoundedPipeline: class {}},
        './window_rules.js': {WindowRules: class { update() {} }},
        './window_opacity.js': {BLUR_ACTOR_NAME: 'glass', WindowOpacity: class {}},
        './window_geometry.js': {compute_scale() {}, place_dynamic_blur() {}, place_static_blur() {}},
        './overview_drag.js': {finish_preview_fade() {}},
        './glass_damage.js': {GlassDamage: class {}}, './glass_policy.js': policy,
        './native_glass.js': {available: native, NativeGlassPipeline: class {}},
    }, globals);
    return new ApplicationsBlur({connect() {}}, {applications: {DYNAMIC_OPACITY: false,
        STATIC_BLUR: false, ROUNDED_CORNERS: 0, PIPELINE: 'standard'}}, {});
}

test('focus changes only reconcile the previous and current eligible window', async () => {
    const global = {display: {focus_window: 'one'}};
    const component = await applications(global);
    ['one', 'two', 'three'].forEach(w => component.meta_windows.add(w));
    const visits = [];
    component.reconcile_window_visibility = window => visits.push(window);
    component.focused_window = null;
    component.set_focus_for_window('one');
    assert.deepEqual(visits, []);
    component.settings.applications.DYNAMIC_OPACITY = true;
    component.init_dynamic_opacity();
    component.set_focus_for_window('two');
    component.set_focus_for_window('two');
    component.settings.applications.DYNAMIC_OPACITY = false;
    component.init_dynamic_opacity();
    assert.deepEqual(visits, ['one', 'one', 'two', 'two']);
});

test('sticky windows reconcile once per settings update and receive one set of handlers', async () => {
    const sticky = new Emitter(), onlyHere = new Emitter();
    const global = {workspace_manager: {
        get_n_workspaces: () => 3,
        get_workspace_by_index: index => ({list_windows: () => index === 0 ? [sticky, onlyHere] : [sticky]}),
    }};
    const component = await applications(global);
    const checked = [], sources = [];
    component.connections.connect = (window, signal) => sources.push([window, signal]);
    component._log = () => {};
    component.check_blur = window => checked.push(window);
    component.update_all_windows();
    component.update_all_windows();
    assert.deepEqual(checked, [sticky, onlyHere, sticky, onlyHere]);
    assert.equal(sources.filter(([window, signal]) => window === sticky && signal === 'unmanaging').length, 1);
    assert.equal(sources.filter(([window, signal]) => window === sticky && signal === 'workspace-changed').length, 1);
});

test('v76 preferences and capability changes preserve the renderer selection', async () => {
    const pipelines = {standard: single({unscaled_radius: 22}), custom: {effects: [{type: 'color'}]}};
    const global = {blur_my_shell: {_pipelines_manager: {pipelines}}};
    const stock = await applications(global, false);
    assert.equal(stock.selected_native_material(), null);
    const component = await applications(global);
    const apps = component.settings.applications;
    component.native_material = component.selected_native_material();
    let changed = 0, painted = 0;
    const pipeline = {updateMaterial() { changed++; }};
    component.glass_damage = {effects: new Map([['first', pipeline]]), invalidateAll() { painted++; }};
    pipelines.standard = single({unscaled_radius: 45, brightness: .75});
    assert.equal(component.sync_native_material(), false);
    assert.deepEqual([pipeline.material.radius, pipeline.material.brightness, changed, painted], [45, .75, 1, 1]);
    component.sync_native_material();
    assert.deepEqual([changed, painted], [1, 1]);
    let restarts = 0;
    component.change_blur_type = () => {
        restarts++;
        component.native_material = component.selected_native_material();
    };
    apps.PIPELINE = 'custom';
    assert.equal(component.sync_native_material(), true);
    assert.equal(component.native_material, null);
    apps.PIPELINE = 'standard';
    assert.equal(component.sync_native_material(), true);
    apps.ROUNDED_CORNERS = 2;
    assert.equal(component.sync_native_material(), true);
    apps.ROUNDED_CORNERS = 0;
    apps.STATIC_BLUR = true;
    assert.equal(component.sync_native_material(), false);
    apps.STATIC_BLUR = false;
    assert.equal(component.sync_native_material(), true);
    assert.equal(restarts, 4);
});

test('legacy notice recognizes native cache metadata without loading the compositor', async () => {
    for (const modern of [false, true]) {
        for (const [versions, method, properties, show] of [
            [[], false, [], false], [['1.0'], false, ['radius'], true],
            [['1.0'], true, ['radius'], true], [['1.0'], true, ['radius', 'cache-background'], false],
        ]) {
            const getProperty = i => ({get_name: () => properties[i]});
            const info = modern ? {find_method: () => method, get_n_properties: () => properties.length,
                get_property: getProperty} : {};
            class Repository {
                enumerate_versions() { return versions; }
                require(name, version, flags) {
                    assert.deepEqual([name, version, flags], ['Blur', '1.0', 1]);
                }
                find_by_name() { return info; }
            }
            if (!modern) Repository.get_default = () => new Repository();
            const api = {Repository, RepositoryLoadFlags: modern ? {LAZY: 1} : {IREPOSITORY_LOAD_FLAG_LAZY: 1},
                object_info_find_method: () => method, object_info_get_n_properties: () => properties.length,
                object_info_get_property: (_, i) => getProperty(i)};
            const marker = new Error('upstream removal notice displayed');
            const Adw = {get_minor_version: () => 10, ActionRow: class { constructor() { throw marker; } }};
            const prefs = await gjs('../../preferences/legacy_blur_notice.js', {
                'gi://Adw': {default: Adw}, 'gi://GIRepository': {default: api}, 'gi://Gtk': {default: {}},
                'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js': {gettext: s => s},
            });
            const open = () => prefs.initialize_legacy_blur_notice({}, {get_boolean: () => false});
            if (show) assert.throws(open, error => error === marker);
            else assert.doesNotThrow(open);
        }
    }
});
