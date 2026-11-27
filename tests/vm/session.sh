#!/usr/bin/env bash
# A private session belonging only to the disposable guest's normal user.
set -euo pipefail
test "$(id -u)" -ne 0
export HOME="/tmp/accept/user/${NORVI_GLASS_TEST_PROFILE:-baseline}"
export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data" XDG_CACHE_HOME="$HOME/cache" \
    XDG_STATE_HOME="$HOME/state" XDG_RUNTIME_DIR="$HOME/run" \
    XDG_CURRENT_DESKTOP=GNOME LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"
# A normal Ubuntu login creates the standard directories used by Desktop Icons.
xdg-user-dirs-update
ext="$XDG_DATA_HOME/gnome-shell/extensions"
mkdir -p "$ext/acceptance@norvi.test"
cp source/tests/vm/session-probe/* "$ext/acceptance@norvi.test/"
gjs -m source/tests/vm/test_visible_surface.mjs
timeout --foreground --kill-after=10s 320s dbus-run-session -- bash -euo pipefail <<'SESSION'
case "${NORVI_GLASS_TEST_PROFILE:-baseline}" in
    upgrade)
        gnome-extensions install --force blur-my-shell.zip
        # The installed Ubuntu service hook prepares this existing user copy at launch.
        ;;
    optout)
        mkdir -p "$XDG_CONFIG_HOME/norvi-window-glass"
        touch "$XDG_CONFIG_HOME/norvi-window-glass/disable-native"
        ;;
    fresh) ;;
    baseline) gnome-extensions install --force blur-my-shell.zip ;;
esac
# Ubuntu's web search provider looks up the desktop's registered HTTPS browser.
if [[ ${NORVI_GLASS_TEST_PROFILE:-baseline} != baseline ]]; then
    gio mime x-scheme-handler/https org.gnome.Epiphany.desktop
fi
gsettings set org.gnome.shell welcome-dialog-last-shown-version '999'
gsettings set org.gnome.desktop.interface enable-animations false
# XDock owns the dock and its keyboard shortcuts in the NorviOS session.
gsettings set org.gnome.shell disabled-extensions "['ubuntu-dock@ubuntu.com']"
gsettings set org.gnome.shell enabled-extensions \
    "['acceptance@norvi.test', 'blur-my-shell@aunetx', 'xdock@spencercnorton.github.io', 'workspace-bar@spencercnorton.github.io', 'transparent-top-bar@spencercnorton.github.io', 'power-only-quicksettings@spencercnorton.github.io', 'lock-screen-suite@spencercnorton.github.io', 'wallpaper-suite@spencercnorton.github.io', 'xnote-placement@spencercnorton.github.io']"
source source/tests/vm/stop-shell.sh
command=(gnome-shell --headless --wayland --virtual-monitor 1280x800)
if [[ ${NORVI_GLASS_TEST_PROFILE:-baseline} != baseline ]]; then
    command=(/usr/bin/python3 -I source/tests/vm/glass-session-start.py)
fi
G_DEBUG=fatal-criticals "${command[@]}" > evidence/shell.log 2>&1 &
shell=$!
trap 'finish_shell "$?" "$shell" evidence/shell.exit' EXIT
for _ in $(seq 180); do
    grep -q 'NORVI-SESSION ready' evidence/shell.log && break
    grep -q 'NORVI-SESSION fail:' evidence/shell.log && break
    kill -0 "$shell" 2>/dev/null || break
    sleep 1
done
cat evidence/shell.log
test "$(grep -c 'NORVI-SESSION ready' evidence/shell.log)" -eq 1
if [[ ${NORVI_GLASS_TEST_PROFILE:-baseline} != baseline ]]; then
    grep -Eq 'NORVI-LOADER checked (native|stock)' evidence/shell.log
fi
if grep -E 'NORVI-SESSION fail:|JS ERROR:|-CRITICAL' evidence/shell.log; then exit 1; fi
export GSETTINGS_SCHEMA_DIR="$XDG_DATA_HOME/gnome-shell/extensions/blur-my-shell@aunetx/schemas"
if [[ ${NORVI_GLASS_TEST_PROFILE:-} == fresh || ${NORVI_GLASS_TEST_PROFILE:-} == optout ]]; then
    export GSETTINGS_SCHEMA_DIR=/usr/share/gnome-shell/extensions/blur-my-shell@aunetx/schemas
fi
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
if grep -E 'NORVI-SESSION fail:|JS ERROR:|-CRITICAL' evidence/shell.log; then exit 1; fi
# Assert the packaged components are active and observe Shell disabling them
# alongside the Ubuntu extensions as the disposable session finishes.
python3 -I source/tests/vm/disable-extensions.py \
    xnote-placement@spencercnorton.github.io wallpaper-suite@spencercnorton.github.io \
    lock-screen-suite@spencercnorton.github.io power-only-quicksettings@spencercnorton.github.io \
    transparent-top-bar@spencercnorton.github.io workspace-bar@spencercnorton.github.io \
    xdock@spencercnorton.github.io blur-my-shell@aunetx acceptance@norvi.test
kill -0 "$shell"
echo 'PASS: packaged GNOME components load and operate; desktop install and rollback preserve user CSS and dconf'
SESSION
# Includes shutdown callbacks: a pre-termination grep would miss GC/actor
# lifetime failures produced while Shell exits.
! grep -E 'NORVI-SESSION fail:|JS ERROR:|-CRITICAL' evidence/shell.log
