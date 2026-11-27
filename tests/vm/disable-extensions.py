"""Let the disposable Shell tear down its active extensions in activation order reversed."""

import sys
import time
from pathlib import Path

from gi.repository import Gio


if Path("/sys/class/dmi/id/product_name").read_text().strip() != "Norvi Acceptance":
    raise SystemExit("Extension teardown requires the disposable desktop VM")

ACTIVE, INACTIVE, ERROR = 1, 2, 3
interface = "org.gnome.Shell.Extensions"
proxy = Gio.DBusProxy.new_for_bus_sync(
    Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None, interface,
    "/org/gnome/Shell/Extensions", interface, None,
)


def states():
    result = proxy.call_sync("ListExtensions", None, Gio.DBusCallFlags.NONE, 3000, None)
    return {uuid: int(info["state"]) for uuid, info in result.unpack()[0].items()}


active = {uuid for uuid, state in states().items() if state == ACTIVE}
missing = set(sys.argv[1:]) - active
if missing:
    raise SystemExit(f"Extensions missing before teardown: {sorted(missing)}")

# Shell processes one settings change in reverse activation order. This also
# lets Ubuntu's Desktop Icons process exit once, with its Shell extension.
settings = Gio.Settings.new("org.gnome.shell")
disabled = settings.get_strv("disabled-extensions")
if not settings.set_strv("disabled-extensions", disabled + sorted(active - set(disabled))):
    raise SystemExit("Could not set the disposable session's disabled extensions")
Gio.Settings.sync()
deadline = time.monotonic() + 15
while True:
    current = states()
    pending = {uuid: current.get(uuid) for uuid in active if current.get(uuid) != INACTIVE}
    if not pending:
        break
    if ERROR in pending.values() or time.monotonic() >= deadline:
        raise SystemExit(f"Shell did not cleanly disable all active extensions: {pending}")
    time.sleep(0.1)
