// A verified upstream per-user installation keeps its original entry points.
// Select the package when installed. Restore the upstream files after removal.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const entry = Gio.File.new_for_uri(import.meta.url);
const folder = entry.get_parent();
const name = entry.get_basename();
const stock = folder.get_child('.norvi-v76-' + name);
const system = Gio.File.new_for_path('/usr/share/gnome-shell/extensions/blur-my-shell@aunetx/' + name);
const companion = Gio.File.new_for_path('/usr/share/norvi-window-glass/v76/loader.js');
const hashes = {
    "extension.js": "a0637967812b4cb669447e936b19d52ad2ad3eab81f94e1f2acb89ec2effc9b2",
    "prefs.js": "8a317af1a05cbcd4e06e55fa9552c88739e021439cc7d54f8cf4faa51f20e292"
};
const sha = file => GLib.compute_checksum_for_bytes(GLib.ChecksumType.SHA256, file.load_bytes(null)[0]);
const regular = file => file.query_file_type(Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null) === Gio.FileType.REGULAR;

function markerFor(file) {
    if (!regular(file))
        return null;
    const [bytes, etag] = file.load_bytes(null);
    const digest = GLib.compute_checksum_for_bytes(GLib.ChecksumType.SHA256, bytes);
    const marker = folder.get_child('.norvi-glass-loader-' + digest + '.js');
    return regular(marker) && sha(marker) === digest ? {marker, etag} : null;
}

function restore() {
    const loaders = new Map();
    for (const [filename, expected] of Object.entries(hashes)) {
        const current = folder.get_child(filename);
        const owner = markerFor(current);
        if (!owner)
            continue;
        const backup = folder.get_child('.norvi-v76-' + filename);
        if (regular(backup) && sha(backup) === expected) {
            // Keep the backup until another concurrently starting Shell or
            // preferences process has finished importing its upstream module.
            const [okay, bytes] = backup.load_contents(null);
            if (okay) {
                current.replace_contents(bytes, owner.etag, false, Gio.FileCreateFlags.NONE, null);
                loaders.set(owner.marker.get_basename(), owner.marker);
            }
        }
    }
    for (const [name, loader] of loaders) {
        const inUse = Object.keys(hashes).some(filename => markerFor(folder.get_child(filename))?.marker.get_basename() === name);
        if (!inUse)
            loader.delete(null);
    }
}

let implementation;
if (companion.query_exists(null) && system.query_exists(null)) {
    implementation = await import(system.get_uri());
} else {
    implementation = await import(stock.get_uri());
    try {
        restore();
    } catch (error) {
        console.warn(`Window glass is using the upstream files: ${error.message}`);
    }
}
export default implementation.default;
