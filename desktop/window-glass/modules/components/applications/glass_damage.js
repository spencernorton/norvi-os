// SPDX-License-Identifier: GPL-3.0-or-later
// NorviOS application glass, November 2026.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { Connections } from '../../conveniences/connections.js';
import { affectedPanes, buildGraph, contains } from './glass_policy.js';

const captureProperties = new Set([
    'allocation', 'x', 'y', 'width', 'height', 'mapped', 'visible', 'z-position',
    'scale-x', 'scale-y', 'scale-z', 'translation-x', 'translation-y', 'translation-z',
    'rotation-angle-x', 'rotation-angle-y', 'rotation-angle-z', 'pivot-point', 'pivot-point-z',
    'transform', 'transform-set', 'child-transform', 'child-transform-set',
]);

function matchesFrame(actor, rect) {
    if (!actor.mapped || !actor.has_allocation() || actor.has_mapped_clones())
        return false;
    const [x, y] = actor.get_transformed_position();
    const [w, h] = actor.get_transformed_size();
    return Math.abs(x - rect.x) < 0.01 && Math.abs(y - rect.y) < 0.01 &&
        Math.abs(x + w - rect.x - rect.width) < 0.01 && Math.abs(y + h - rect.y - rect.height) < 0.01;
}

// Only constructed for a paired native renderer. v76 owns every other
// surface and continues to run its normal backdrop, clipping and paint code.
export class GlassDamage {
    constructor() {
        this.signals = new Connections();
        this.windows = new Connections();
        this.branches = new Connections();
        this.backgrounds = new Connections();
        this.effects = new Map();
        this.laters = global.compositor.get_laters();
        this.membershipSignals = GObject.signal_lookup('norvi-effects-changed', Clutter.Actor.$gtype) !== 0;
        this.dirty = true;
        this.guardsDirty = true;
        this.graph = new Map();
        this.pending = 0;
        this.animation = 0;
        this.animationEnd = 0;

        this.signals.connect(global.display, 'restacked', () => this.topologyChanged());
        this.signals.connect(global.display, 'grab-op-begin', () => { this.grab = true; this.invalidateAll(); });
        this.signals.connect(global.display, 'grab-op-end', () => { this.grab = false; this.topologyChanged(); });
        this.signals.connect(global.window_manager, ['map', 'destroy', 'minimize', 'unminimize', 'size-change'],
            () => { this.topologyChanged(); this.animate(600); });
        this.signals.connect(Main.overview, ['showing', 'hiding'], () => this.animate(800));
        this.signals.connect(Main.overview, 'hidden', () => this.topologyChanged());
        this.signals.connect(Main.layoutManager, 'monitors-changed', () => {
            this.topologyChanged();
            this.bindBackgrounds();
        });
        this.bindBackgrounds();
        if (!this.membershipSignals) {
            // ClutterActor:effect is write-only. Older Clutter cannot report
            // add/remove/clear; inspect actual memberships on already scheduled frames.
            this.signals.connect(global.stage, 'before-update', () => {
                if (this.effects.size && !this.dirty && this.membershipChanged()) {
                    this.guardsDirty = true;
                    this.refreshGuards();
                }
            });
        }
    }

    bindBackgrounds() {
        this.backgrounds.disconnect_all();
        for (const manager of Main.layoutManager._bgManagers ?? []) {
            this.backgrounds.connect(manager, 'changed', () => { this.bindBackgrounds(); this.animate(1500); });
            const image = manager.backgroundActor?.content?.background;
            if (image)
                this.backgrounds.connect(image, 'changed', () => this.animate(200));
        }
    }

    setPane(window, pipeline) {
        if (pipeline)
            this.effects.set(window, pipeline);
        else
            this.effects.delete(window);
        this.topologyChanged();
    }

    invalidateAll() {
        for (const {actor, effect} of this.effects.values()) {
            if (actor.visible)
                effect.invalidate();
        }
    }

    animate(duration) {
        this.animationEnd = Math.max(this.animationEnd, GLib.get_monotonic_time() + duration * 1000);
        if (this.animation || !this.effects.size)
            return;
        this.invalidateAll();
        this.animation = this.laters.add(Meta.LaterType.BEFORE_REDRAW, () => {
            this.invalidateAll();
            if (this.effects.size && GLib.get_monotonic_time() < this.animationEnd)
                return GLib.SOURCE_CONTINUE;
            this.animation = 0;
            return GLib.SOURCE_REMOVE;
        });
    }

    topologyChanged() {
        this.dirty = true;
        this.schedule();
    }

    guardChanged() {
        this.guardsDirty = true;
        this.schedule();
    }

    schedule() {
        if (this.pending)
            return;
        this.pending = this.laters.add(Meta.LaterType.BEFORE_REDRAW, () => {
            this.pending = 0;
            if (this.dirty)
                this.rebuild();
            else if (this.guardsDirty)
                this.refreshGuards();
            return GLib.SOURCE_REMOVE;
        });
    }

    rebuild() {
        this.dirty = false;
        const entries = [];
        const watched = new Set();
        for (const actor of global.get_window_actors()) {
            const window = actor.meta_window;
            if (!window)
                continue;
            watched.add(actor);
            watched.add(window);
            if (!this.windows.records.has(actor)) {
                this.windows.connect(actor, 'damaged-with-bounds', (_, damage) => this.damage(window, damage));
                this.windows.connect(actor, ['notify::mapped', 'cloned', 'decloned'], () => this.topologyChanged());
            }
            if (!this.windows.records.has(window)) {
                this.windows.connect(window, ['size-changed', 'position-changed', 'workspace-changed'],
                    () => this.topologyChanged());
            }
            if (!actor.mapped && !actor.has_mapped_clones())
                continue;
            const pipeline = this.effects.get(window);
            entries.push({
                window, actor, rect: window.get_frame_rect(), workspace: window.get_workspace(),
                sticky: window.is_on_all_workspaces(),
                effect: pipeline?.actor.visible ? pipeline.effect : null,
            });
        }
        for (const object of this.windows.records.keys()) {
            if (!watched.has(object))
                this.windows.disconnect_all_for(object);
        }
        this.graph = buildGraph(entries);
        this.entries = entries;
        this.refreshGuards();
        // A restack, reveal, motion or eligibility change can alter the backdrop
        // without any client damage. Cover old and new positions before paint.
        this.invalidateAll();
    }

    membershipChanged() {
        try {
            for (const [actor, previous] of this.memberships ?? []) {
                if (previous.length === 0 && !actor.has_effects())
                    continue;
                const current = actor.get_effects();
                if (current.length !== previous.length || current.some((effect, i) => effect !== previous[i]))
                    return true;
            }
        } catch { return true; }
        return false;
    }

    refreshGuards() {
        this.guardsDirty = false;
        const actors = new Set(), foreign = new Set(), known = new Set();
        this.memberships = this.membershipSignals ? null : new Map();
        this.contentActors = new Set();
        for (const pipeline of this.effects.values()) {
            known.add(pipeline.blocker);
            known.add(pipeline.effect);
        }
        const monitors = Main.layoutManager.monitors;
        const scale = monitors[0]?.geometry_scale;
        let safe = scale >= 1 && monitors.every(m => m.geometry_scale === scale);
        const changed = () => this.guardChanged();
        const inspect = actor => {
            if (actors.has(actor))
                return;
            actors.add(actor);
            if (!this.branches.records.has(actor)) {
                const contentChanged = () => {
                    if (this.contentActors.has(actor))
                        this.topologyChanged();
                    else
                        changed();
                };
                this.branches.connect(actor, 'notify', (_, property) => {
                    if (captureProperties.has(property.name) || property.name === 'opacity') contentChanged();
                });
                this.branches.connect(actor, ['parent-set', 'child-added', 'child-removed', 'cloned', 'decloned'], contentChanged);
                if (this.membershipSignals)
                    this.branches.connect(actor, 'norvi-effects-changed', changed);
            }
            const effects = actor.get_effects();
            this.memberships?.set(actor, effects);
            for (const effect of effects) {
                if (known.has(effect))
                    continue;
                foreign.add(effect);
                if (!this.branches.records.has(effect))
                    this.branches.connect(effect, 'notify', (_, p) => {
                        if (p.name === 'enabled' || effect.enabled) changed();
                    });
                if (effect.enabled)
                    safe = false;
            }
        };
        try {
            for (const entry of this.entries) {
                // A foreign effect on a different window's content can itself
                // sample the framebuffer. Guard that whole visible branch too.
                const children = [entry.actor];
                while (children.length) {
                    const child = children.pop();
                    this.contentActors.add(child);
                    inspect(child);
                    children.push(...child.get_children());
                }
                let ancestor = entry.actor.get_parent();
                while (ancestor && ancestor !== global.stage) {
                    inspect(ancestor);
                    ancestor = ancestor.get_parent();
                }
                if (ancestor) inspect(ancestor);
                if (!ancestor || entry.actor.get_parent() !== global.window_group)
                    safe = false;
                const pipe = this.effects.get(entry.window);
                if (entry.effect && (!matchesFrame(pipe.actor, entry.rect) ||
                    !monitors.some(m => contains(m, entry.rect))))
                    safe = false;
            }
        } catch { safe = false; }
        for (const object of this.branches.records.keys()) {
            if (!actors.has(object) && !foreign.has(object))
                this.branches.disconnect_all_for(object);
        }
        if (this.ordinary === false || !safe)
            this.invalidateAll();
        this.ordinary = safe;
    }

    damage(window, bounds) {
        if (!this.effects.size)
            return;
        if (this.dirty) {
            this.rebuild();
            return;
        }
        if (this.guardsDirty || (!this.membershipSignals && this.membershipChanged()))
            this.refreshGuards();
        if (!bounds || !this.ordinary || this.animation || this.grab || Main.overview.visible ||
            Main.actionMode !== Shell.ActionMode.NORMAL) {
            this.invalidateAll();
            return;
        }
        const panes = affectedPanes(this.graph, window, bounds);
        if (!panes) {
            this.invalidateAll();
            return;
        }
        for (const {effect} of panes)
            effect.invalidate();
    }

    destroy() {
        if (this.pending) this.laters.remove(this.pending);
        if (this.animation) this.laters.remove(this.animation);
        for (const signals of [this.signals, this.windows, this.branches, this.backgrounds])
            signals.disconnect_all();
        this.effects.clear();
    }
}
