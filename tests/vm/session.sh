#!/usr/bin/env bash
# A private session belonging only to the disposable guest's normal user.
set -euo pipefail
test "$(id -u)" -ne 0
export HOME=/tmp/accept/user XDG_CONFIG_HOME=/tmp/accept/user/config \
    XDG_DATA_HOME=/tmp/accept/user/data XDG_CACHE_HOME=/tmp/accept/user/cache \
    XDG_STATE_HOME=/tmp/accept/user/state XDG_RUNTIME_DIR=/tmp/accept/user/run \
    XDG_CURRENT_DESKTOP=GNOME LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
ext="$XDG_DATA_HOME/gnome-shell/extensions"
mkdir -p "$ext/acceptance@norvi.test"
cp source/tests/vm/session-probe/* "$ext/acceptance@norvi.test/"
dbus-run-session -- bash -euo pipefail <<'SESSION'
gnome-extensions install --force blur-my-shell.zip
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999'
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.shell enabled-extensions \
    "['acceptance@norvi.test', 'blur-my-shell@aunetx', 'xdock@spencercnorton.github.io', 'workspace-bar@spencercnorton.github.io', 'transparent-top-bar@spencercnorton.github.io', 'power-only-quicksettings@spencercnorton.github.io', 'lock-screen-suite@spencercnorton.github.io', 'wallpaper-suite@spencercnorton.github.io', 'xnote-placement@spencercnorton.github.io']"
gnome-shell --headless --wayland --virtual-monitor 1280x800 > evidence/shell.log 2>&1 &
shell=$!
trap 'kill "$shell" 2>/dev/null || true; wait "$shell" 2>/dev/null || true' EXIT
for _ in $(seq 90); do
    grep -q 'NORVI-SESSION ready' evidence/shell.log && break
    grep -q 'NORVI-SESSION fail:' evidence/shell.log && break
    kill -0 "$shell" 2>/dev/null || break
    sleep 1
done
cat evidence/shell.log
test "$(grep -c 'NORVI-SESSION ready' evidence/shell.log)" -eq 1
! grep -E 'NORVI-SESSION fail:|JS ERROR:' evidence/shell.log
export GSETTINGS_SCHEMA_DIR="$XDG_DATA_HOME/gnome-shell/extensions/blur-my-shell@aunetx/schemas"
schema=org.gnome.shell.extensions.blur-my-shell.applications
gsettings set "$schema" opacity 190
gsettings set "$schema" blacklist "['org.example.Preserve']"
gsettings set "$schema" blur false
gsettings set "$schema" enable-all false
gsettings set "$schema" dynamic-opacity true
mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
for gtk in gtk-3.0 gtk-4.0; do
    printf '/* Existing user stylesheet */\n' > "$XDG_CONFIG_HOME/$gtk/gtk.css"
    cp "$XDG_CONFIG_HOME/$gtk/gtk.css" "$HOME/$gtk.before"
done
dconf dump /org/gnome/shell/extensions/blur-my-shell/ > evidence/dconf-before.ini
bash source/desktop/install-desktop.sh
bash source/desktop/install-desktop.sh
test "$(gsettings get "$schema" blur)" = true
test "$(gsettings get "$schema" opacity)" = 255
for version in 3 4; do
    cmp "source/desktop/gtk$version.css" "$XDG_CONFIG_HOME/gtk-$version.0/gtk.css"
done
bash source/desktop/install-desktop.sh --uninstall
bash source/desktop/install-desktop.sh --uninstall
for gtk in gtk-3.0 gtk-4.0; do
    cmp "$HOME/$gtk.before" "$XDG_CONFIG_HOME/$gtk/gtk.css"
done
dconf dump /org/gnome/shell/extensions/blur-my-shell/ > evidence/dconf-after.ini
diff -u evidence/dconf-before.ini evidence/dconf-after.ini
sleep 1
kill -0 "$shell"
! grep -E 'NORVI-SESSION fail:|JS ERROR:' evidence/shell.log
echo 'PASS: packaged GNOME components load and operate; desktop install and rollback preserve user CSS and dconf'
SESSION
