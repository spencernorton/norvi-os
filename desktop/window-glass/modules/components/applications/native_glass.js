// SPDX-License-Identifier: GPL-3.0-or-later
// NorviOS application glass, November 2026.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import St from 'gi://St';

let Blur = null;
if (GLib.getenv('NORVI_WINDOW_GLASS_RENDERER') !== 'upstream' &&
    GLib.getenv('NORVI_BLUR_ALGORITHM') !== 'gaussian' &&
    GObject.signal_lookup('damaged-with-bounds', Meta.WindowActor.$gtype)) {
    try {
        const module = (await import('gi://Blur')).default;
        const properties = module.BlurEffect.list_properties().map(p => p.name);
        if (module.BlurMode?.BACKGROUND !== undefined &&
            typeof module.BlurEffect.prototype.invalidate === 'function' &&
            ['cache-background', 'corner-radius', 'radius', 'brightness'].every(p => properties.includes(p)))
            Blur = module;
    } catch {
        // The v76 renderer is fully supported without the optional native library.
    }
}
export const available = Blur !== null;

// A native no-op on the window actor stops Mutter's opaque-region culling
// from discarding pixels needed by the blur child. It has no JS paint vfunc.
const CullBlocker = GObject.registerClass({GTypeName: 'BmsNorviGlassCullBlocker'},
    class CullBlocker extends Clutter.Effect {});

export class NativeGlassPipeline {
    constructor(material) {
        this.material = material;
        this.cornerRadius = 0;
        this.straightCorners = false;
    }

    create_background_with_effect(container, name) {
        this.actor = new St.Widget({name, reactive: false, clip_to_allocation: true});
        this.container = container;
        this.effect = new Blur.BlurEffect({mode: Blur.BlurMode.BACKGROUND, cache_background: true});
        this.theme = St.ThemeContext.get_for_stage(global.stage);
        this.scaleId = this.theme.connect('notify::scale-factor', () => this.updateMaterial());
        this.blocker = new CullBlocker();
        container.add_effect(this.blocker);
        this.actor.add_effect(this.effect);
        container.insert_child_at_index(this.actor, 0);
        this.updateMaterial();
        const manager = new Clutter.Actor();
        manager.backgroundActor = this.actor;
        manager._bms_pipeline = this;
        return [this.actor, manager];
    }

    updateMaterial() {
        const scale = this.theme.scale_factor;
        this.effect.radius = Math.round(this.material.radius * scale);
        this.effect.brightness = this.material.brightness;
        this.effect.corner_radius = this.straightCorners ? 0 : this.cornerRadius * scale;
    }

    set_corner_radius(radius) {
        if (radius !== this.cornerRadius) {
            this.cornerRadius = radius;
            this.updateMaterial();
        }
    }

    set_straight_corners(straight) {
        if (straight !== this.straightCorners) {
            this.straightCorners = straight;
            this.updateMaterial();
        }
    }

    repaint_effect() {
        this.effect.invalidate();
    }

    setVisible(visible) {
        if (this.blocker.enabled !== visible)
            this.blocker.enabled = visible;
    }

    destroy() {
        this.theme.disconnect(this.scaleId);
        this.container.remove_effect(this.blocker);
        this.actor.remove_effect(this.effect);
    }
}
