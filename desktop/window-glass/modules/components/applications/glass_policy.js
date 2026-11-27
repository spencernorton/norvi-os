// SPDX-License-Identifier: GPL-3.0-or-later
// NorviOS application glass, November 2026.

// Only this v76 pipeline has a corresponding native material. Other pipelines
// keep their original implementation, including the user's effect order.
export function nativeMaterial(pipeline, corners) {
    if (corners !== 0 || pipeline?.effects?.length !== 1)
        return null;
    const [effect] = pipeline.effects;
    if (effect.type !== 'dual_kawase_blur')
        return null;
    const params = effect.params ?? {};
    if (Object.keys(params).some(key => !['unscaled_radius', 'brightness', 'opacity_factor'].includes(key)))
        return null;
    const radius = params.unscaled_radius ?? 30;
    const brightness = params.brightness ?? 0.6;
    // The native GI radius is an integer. Preserve v76's fractional kernels.
    if (!Number.isInteger(radius) || radius <= 0 || radius > 200 ||
        !Number.isFinite(brightness) || brightness < 0 || brightness > 1 ||
        (params.opacity_factor ?? 1) !== 1)
        return null;
    return {radius, brightness};
}

function overlaps(a, b) {
    return a.x < b.x + b.width && a.x + a.width > b.x &&
        a.y < b.y + b.height && a.y + a.height > b.y;
}

export function contains(outer, inner) {
    return outer.x <= inner.x && outer.y <= inner.y &&
        inner.x + inner.width <= outer.x + outer.width &&
        inner.y + inner.height <= outer.y + outer.height;
}

function sameWorkspace(a, b) {
    return a.sticky || b.sticky || !a.workspace || !b.workspace || a.workspace === b.workspace;
}

// Stack order is bottom to top. Build edges when the scene changes, not for
// every client frame. All potentially overlapping glass is included, even if
// another application's opaque region currently covers some of it.
export function buildGraph(entries) {
    const nodes = new Map();
    for (let i = entries.length - 1; i >= 0; i--) {
        const source = entries[i];
        const direct = [], above = new Set();
        for (let j = i + 1; j < entries.length; j++) {
            const pane = entries[j];
            if (!pane.effect || !sameWorkspace(source, pane) || !overlaps(source.rect, pane.rect))
                continue;
            direct.push(pane);
            above.add(pane);
            for (const upper of nodes.get(pane.window).above)
                above.add(upper);
        }
        nodes.set(source.window, {source, direct, above});
    }
    return nodes;
}

// Mutter reports outward-rounded logical stage coordinates. Only the first
// hop can be clipped to a client's small damage. The material's output may
// change anywhere within each admitted pane, including its blurred edges.
export function affectedPanes(graph, window, damage) {
    const node = graph.get(window);
    if (!node || !damage || !(damage.width > 0 && damage.height > 0) ||
        !contains(node.source.rect, damage))
        return null;
    const region = {x: damage.x - 1, y: damage.y - 1, width: damage.width + 2, height: damage.height + 2};
    const out = new Set();
    for (const pane of node.direct) {
        if (!overlaps(region, pane.rect))
            continue;
        out.add(pane);
        for (const upper of graph.get(pane.window).above)
            out.add(upper);
    }
    return out;
}
