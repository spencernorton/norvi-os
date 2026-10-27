#!/usr/bin/env bash
# norvi-os desktop layer — GTK4 surfaces + the compositor blur they depend on.
# Per-user, so NOT run as root: it writes ~/.config and the user's dconf.
# Idempotent.   ./install-desktop.sh [--uninstall|--stylesheet-only]
set -euo pipefail

[ "$(id -u)" -ne 0 ] || { echo "run WITHOUT sudo — this is per-user config" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
BMS="$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx"
# A distribution package installs it system-wide instead; the settings are per-user either way.
[ -d "$BMS" ] || BMS=/usr/share/gnome-shell/extensions/blur-my-shell@aunetx
APPS=org.gnome.shell.extensions.blur-my-shell.applications

# What this installer changed, so --uninstall can undo exactly that and no more.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/norvi-os"
ADDED="$STATE_DIR/blur-blacklist-added"
BMS_BEFORE="$STATE_DIR/blur-settings-before"

# The blur is the other half of the effect: the stylesheet only stops the window
# painting, it cannot blur anything (GTK has no backdrop-filter and Mutter does
# not expose backdrop blur to clients). Set both, or neither.
bms() {
  [ -d "$BMS/schemas" ] || { echo "SKIP blur: blur-my-shell not installed" >&2; return; }
  GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings set "$APPS" "$1" "$2"
}

# Every guard below says `return 0`: a bare `return` after a failed test returns
# that test's 1, and under `set -e` the caller then aborts. That turned a second
# --uninstall, or one after --stylesheet-only, into a silent exit 1.
#
# These four keys are the USER's settings too. Each is recorded once, before
# this installer first changes it, so uninstall can put back what was actually
# there rather than assuming a default. A key already in the record is never
# re-read: by then it holds our value, not the user's. A record written by an
# older version lacks the keys it did not manage yet (blur and opacity before
# 1.3.0); those are added now, while they still hold the user's own values.
# The file's existence is also the record of whether this installer ever
# touched the compositor at all -- after a --stylesheet-only install it does not
# exist, and uninstall leaves dconf alone.
bms_record_original() {
  [ -d "$BMS/schemas" ] || return 0
  install -d "$STATE_DIR"
  local k
  {
    [ -f "$BMS_BEFORE" ] && cat "$BMS_BEFORE"
    for k in blur opacity enable-all dynamic-opacity; do
      grep -qs "^$k=" "$BMS_BEFORE" && continue
      printf '%s=%s\n' "$k" "$(GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings get "$APPS" "$k")"
    done
  } > "$BMS_BEFORE.new"
  mv -f "$BMS_BEFORE.new" "$BMS_BEFORE"   # one rename: never a half-written record
}

bms_restore_original() {
  [ -d "$BMS/schemas" ] || return 0
  [ -f "$BMS_BEFORE" ] || return 0
  local k v
  while IFS='=' read -r k v; do
    [ -z "$k" ] || GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings set "$APPS" "$k" "$v"
  done < "$BMS_BEFORE"
  rm -f "$BMS_BEFORE"
}

# The blacklist is the USER's list, not ours -- add to it, never assign it, or a
# rerun silently drops entries somebody added by hand. Idempotent: re-adding an
# entry already present is a no-op.
bms_blacklist_add() {
  [ -d "$BMS/schemas" ] || { echo "SKIP blur: blur-my-shell not installed" >&2; return; }
  local cur
  cur=$(GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings get "$APPS" blacklist)
  case "$cur" in
    *"'$1'"*) return ;;                 # already there, ours or theirs -- not ours to claim
    "@as []"|"[]") cur="['$1']" ;;      # empty list, both spellings gsettings emits
    *)             cur="${cur%]}, '$1']" ;;
  esac
  GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings set "$APPS" blacklist "$cur"
  # Remember it, so --uninstall removes what WE added and nothing else. The
  # early return above matters here: an entry that was already present is not
  # recorded, so uninstall will not take away something the user put there.
  install -d "$(dirname "$ADDED")"
  printf '%s\n' "$1" >> "$ADDED"
}

# The inverse, and the same rule: string surgery on a list the user co-owns.
bms_blacklist_remove() {
  [ -d "$BMS/schemas" ] || return 0
  local cur out first item
  cur=$(GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings get "$APPS" blacklist)
  case "$cur" in "@as []"|"[]") return ;; esac
  out=""; first=1
  # Split on ", " after stripping the brackets, then drop the one entry.
  cur="${cur#[}"; cur="${cur%]}"
  local IFS=,
  for item in $cur; do
    item="${item# }"
    [ "$item" = "'$1'" ] && continue
    if [ "$first" = 1 ]; then out="$item"; first=0; else out="$out, $item"; fi
  done
  unset IFS
  [ "$first" = 1 ] && out="@as []" || out="[$out]"
  GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings set "$APPS" blacklist "$out"
}

# GTK3 and GTK4 read ONE stylesheet each and it is the per-user one. Measured
# with strace on live processes: only $XDG_CONFIG_HOME/gtk-{3,4}.0/gtk.css is
# opened. /etc/gtk-{3,4}.0/settings.ini exists and is read; gtk.css has no
# system search path at all. That is why this script is per-user, not root.
VERSIONS="3 4"

MODE="install"
case "${1:-}" in
  --uninstall)        MODE="uninstall" ;;
  --stylesheet-only)  MODE="stylesheet-only" ;;
  "")                 ;;
  *) echo "unknown option: $1 (expected --uninstall or --stylesheet-only)" >&2; exit 2 ;;
esac

if [ "$MODE" = "uninstall" ]; then
  for v in $VERSIONS; do
    d="$CFG/gtk-$v.0/gtk.css"
    # Exactly one of the two markers exists while an install is managed, and
    # neither exists once it is not. `rm -f "$d"` must therefore be reached ONLY
    # through the sentinel -- the earlier `else rm` was an unguarded delete, so a
    # second uninstall (or a retry after a later step failed) removed the very
    # stylesheet the first one had just restored. That is user data.
    if [ -f "$d.pre-norvi" ]; then
      mv -f "$d.pre-norvi" "$d"
      rm -f "$d.norvi-absent-before"
    elif [ -f "$d.norvi-absent-before" ]; then
      rm -f "$d" "$d.norvi-absent-before"
    fi
    # else: no marker, so nothing here is ours. Leave it alone.
  done
  # Take back the blacklist entries this installer added, and only those.
  if [ -f "$ADDED" ]; then
    if [ -d "$BMS/schemas" ]; then
      while IFS= read -r entry; do
        [ -z "$entry" ] || bms_blacklist_remove "$entry"
      done < "$ADDED"
      rm -f "$ADDED"
    else
      # The extension is gone, so bms_blacklist_remove can do nothing -- but the
      # dconf values outlive it, and reinstalling blur-my-shell would bring our
      # entries back. Keep the record rather than forget what we owe.
      echo "NOTE: blur-my-shell is not installed, so its blacklist was left alone." >&2
      echo "      Kept $ADDED; re-run --uninstall once the extension is back to" >&2
      echo "      finish removing: $(tr "\n" " " < "$ADDED")" >&2
    fi
  fi
  # Put the compositor keys back to whatever they were, and only if this
  # installer is the thing that changed them. The earlier version set
  # enable-all=false unconditionally, which turned OFF a setting the user may
  # have had on, and never restored dynamic-opacity at all.
  bms_restore_original
  echo "DONE. Reverted. Apps pick it up as they restart."
  exit 0
fi

# Set both halves or neither. The stylesheet only stops the window painting; it
# cannot blur anything (GTK has no backdrop-filter and Mutter does not expose
# backdrop blur to clients). Installing it alone leaves translucency over an
# UNBLURRED desktop, which is not the effect and reads as a broken theme -- and
# the script said as much at the top while doing it anyway.
if [ ! -d "$BMS/schemas" ] && [ "$MODE" != "stylesheet-only" ]; then
  cat >&2 <<'NOBLUR'
blur-my-shell is not installed, so only half of this effect can be applied.
Translucent windows over an unblurred desktop is not the house style; it is a
washed-out desktop. Install blur-my-shell first:

    https://extensions.gnome.org/extension/3193/blur-my-shell/

Or, if you actually want the stylesheet on its own:

    ./install-desktop.sh --stylesheet-only
NOBLUR
  exit 1
fi

# Installed is not running. A disabled extension leaves the same washed-out
# desktop the check above prevents, and only GNOME Shell knows its state; outside
# the desktop session there is no answer, so that refuses too.
bms_state=$(gnome-extensions info blur-my-shell@aunetx 2>/dev/null || true)
if [ "$MODE" != "stylesheet-only" ] && [[ "$bms_state" != *"State: ACTIVE"* ]]; then
  cat >&2 <<'NOTACTIVE'
blur-my-shell is installed but not running, so the blur half would not apply.
Enable it (a newly installed extension needs a log-out and back in first), then
run this again from your desktop session:

    gnome-extensions enable blur-my-shell@aunetx

Or, if you actually want the stylesheet on its own:

    ./install-desktop.sh --stylesheet-only
NOTACTIVE
  exit 1
fi

python3 "$SRC/check_contrast.py" >/dev/null   # refuse to install an inaccessible alpha
python3 "$SRC/check_glass_tokens.py" >/dev/null   # refuse drift from glass-tokens.json
for v in $VERSIONS; do
  d="$CFG/gtk-$v.0/gtk.css"
  mkdir -p "$(dirname "$d")"   # not install -d: that resets an existing dir to 0755
  # Record what was here BEFORE the first managed install, exactly once, and
  # never revisit it. The earlier version only checked for the backup, so on a
  # clean box -- where there was no predecessor and so no backup -- the next
  # upgrade saw an existing file that differed from the new source and filed OUR
  # older stylesheet as the user's original. Uninstall then restored a Norvi
  # stylesheet instead of removing it. The sentinel is the missing half: one of
  # these two files always exists after the first install, so the "is this the
  # first install?" question has an answer that does not depend on comparing
  # file contents.
  if [ ! -f "$d.pre-norvi" ] && [ ! -f "$d.norvi-absent-before" ]; then
    if [ -f "$d" ]; then
      cp -a "$d" "$d.pre-norvi"
      echo "  kept previous stylesheet as $d.pre-norvi"
    else
      : > "$d.norvi-absent-before"
    fi
  fi
  install -m644 "$SRC/gtk$v.css" "$d"
  echo "== stylesheet -> $d"
done

if [ "$MODE" = "stylesheet-only" ]; then
  echo "== compositor blur SKIPPED (--stylesheet-only): dconf is left untouched"
else
echo "== compositor blur (blur-my-shell Applications)"
bms_record_original         # before the first change, so uninstall can undo it
bms blur true               # Blur my Shell ships application blur OFF: without this there is no glass
bms opacity 255             # its default 215 fades the whole window, text included; the stylesheet
                            # alone makes backgrounds translucent, and check_contrast.py assumes that
bms enable-all true         # every window, not just a whitelist
bms dynamic-opacity false   # else the blur is hidden on the window you are looking at

# `gjs` blacklists the DESKTOP. With enable-all, "every window" includes DING's
# desktop window, and blurring that blurs the wallpaper itself -- the whole
# desktop went soft while the overview stayed sharp (blur-on-overview is false).
# The pre-existing `com.desktop.ding` entry never fired: blur-my-shell matches on
# wm_class, and the shell reports DING as plain `gjs` (its patterns are anchored,
# case-insensitive wildcards, so this cannot over-match e.g. gjs-console).
# Cost: other gjs windows (extension prefs dialogs) lose blur too. Accepted --
# there is no finer key, wm_class is all blur-my-shell gets.
bms_blacklist_add gjs

# Take the browsers out of the blur layer entirely. blur-my-shell attaches a
# blur actor under every NORMAL window (measured: 11 attachments to wm_class
# `google-chrome`, 1 to `brave-browser` in a single session), and Chromium
# paints an opaque background of its own -- so the blur is sampled, composited
# and then completely hidden. Pure GPU cost, no pixels.
#
# NOT a fix for the broken extensions/app menus reported on Chrome and Brave.
# Those are popups, and check_blur() filters on frame type
# [NORMAL, DIALOG, MODAL_DIALOG], so blur-my-shell never touched them. The
# popover rules in gtk4.css were also cleared: rendered against a plain GTK4
# app they produce a correct dark plate, so they are not it either.
#
# RESOLVED 2026-08-23. It was the third candidate this comment named -- Chromium
# sampling GTK for colours it paints itself, `window.background` handing it our
# 0.72 alpha for a colour it treats as opaque. Measured by toggling ONLY Brave's
# `system_theme` between 1 (GTK) and 0 (Classic) against a geolocation prompt
# over a text page: on GTK the page's own heading read straight through the
# bubble, on Classic it did not.
#
# This comment also concluded that half "cannot be fixed here; it is Brave's own
# Appearance setting". That was wrong. There is no per-app selector, but there
# does not need to be -- Chromium samples from a GtkWindow it never realizes and
# GTK adds `csd` in realize, so `window.background.csd` in gtk4.css is invisible
# to the sampler and still reaches every real window. See that rule's header for
# the probe. The blacklist below stays: it is a separate, GPU-cost-only argument.
bms_blacklist_add google-chrome
bms_blacklist_add brave-browser
fi

# GTK4 re-reads the user stylesheet live; GTK3 does NOT. Measured: dropping the
# alpha to 0.30 left a running Nemo's title bar at exactly its old value. Worse,
# Nemo is a singleton GApplication, so clicking its launcher re-focuses the stale
# process and the change never appears. Name the processes rather than kill them —
# some of them are somebody's unsaved LibreOffice document.
stale_gtk3() {
  for d in /proc/[0-9]*; do
    [ -r "$d/maps" ] && grep -qs libgtk-3 "$d/maps" && ps -o comm= -p "${d#/proc/}" 2>/dev/null
  done | sort -u
}
stale="$(stale_gtk3 || true)"

echo
if [ "$MODE" = "stylesheet-only" ]; then
  echo "DONE. GTK4 apps re-read the stylesheet live."
else
  echo "DONE. GTK4 apps re-read the stylesheet live; the blur applies immediately."
fi
if [ -n "$stale" ]; then
  echo
  echo "GTK3 does NOT re-read it. These GTK3 processes are running; any of them"
  echo "with a window will look unchanged until it is fully quit and reopened (for"
  echo "singletons like Nemo, closing the window is not enough — the process has to"
  echo "exit). Background services in the list have no window and can be ignored:"
  echo "$stale" | sed 's/^/    /'
fi
