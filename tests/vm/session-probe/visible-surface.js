export function hasVisibleSurface(app) {
    return app.get_windows().some(window => {
        const actor = window.get_compositor_private();
        return actor?.mapped && actor.width > 0 && actor.height > 0;
    });
}

export async function waitForVisibleSurface(app, id, {now, wait, describe}) {
    const until = now() + 30000000;
    // Mapping can precede the first nonempty compositor allocation.
    while (!hasVisibleSurface(app)) {
        if (now() >= until)
            throw new Error(`No visible packaged application window: ${id}; observed ${JSON.stringify(describe())}`);
        await wait(250);
    }
    return until;
}
