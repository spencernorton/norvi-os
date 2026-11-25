#!/bin/bash
# Checks bms_blacklist_add in install-desktop.sh against a stubbed gsettings.
#
# The function edits a dconf LIST that the user also owns, by string surgery on
# gsettings' output. Getting a branch wrong does not error -- it silently writes
# a malformed or truncated blacklist, which shows up much later as "why is my
# desktop blurry again". Hence a check.
#
#   ./tests-blacklist-merge.sh     (exits non-zero on the first bad case)
set -uo pipefail

BMS=$(mktemp -d); APPS=fake.schema; mkdir -p "$BMS/schemas"
trap 'rm -rf "$BMS"' EXIT

STATE=""
declare -A KEYS=([blur]=false [opacity]=215 [enable-all]=false [dynamic-opacity]=true)
# gsettings set <schema> <key> <value>  -- the value is $4, not $3.
gsettings() {
  if [ "$1" = get ]; then
    if [ "$3" = blacklist ]; then printf '%s\n' "$STATE"; else printf '%s\n' "${KEYS[$3]}"; fi
  else
    if [ "$3" = blacklist ]; then STATE="$4"; else KEYS[$3]="$4"; fi
  fi
}

ADDED="$BMS/added"
STATE_DIR="$BMS/state"
BMS_BEFORE="$STATE_DIR/blur-settings-before"

# Kept byte-identical to install-desktop.sh. If you change one, change both.
bms_blacklist_add() {
  [ -d "$BMS/schemas" ] || { echo "SKIP blur: blur-my-shell not installed" >&2; return; }
  local cur
  cur=$(GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings get "$APPS" blacklist)
  case "$cur" in
    *"'$1'"*) return ;;
    "@as []"|"[]") cur="['$1']" ;;
    *)             cur="${cur%]}, '$1']" ;;
  esac
  GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings set "$APPS" blacklist "$cur"
  install -d "$(dirname "$ADDED")"
  printf '%s\n' "$1" >> "$ADDED"
}

bms_blacklist_remove() {
  [ -d "$BMS/schemas" ] || return 0
  local - cur out first item
  set -f   # entries can be wildcards ('crx_*'): the split below must not glob them against $PWD
  cur=$(GSETTINGS_SCHEMA_DIR="$BMS/schemas" gsettings get "$APPS" blacklist)
  case "$cur" in "@as []"|"[]") return ;; esac
  out=""; first=1
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

fail=0
check() {
  if [ "$STATE" = "$2" ]; then echo "ok   - $1"
  else echo "FAIL - $1"; echo "         want: $2"; echo "         got:  $STATE"; fail=1; fi
}

STATE="['Plank', 'com.desktop.ding', 'Conky']"; bms_blacklist_add gjs
check "appends to an existing list" "['Plank', 'com.desktop.ding', 'Conky', 'gjs']"

STATE="[]"; bms_blacklist_add gjs
check "empty list" "['gjs']"

STATE="@as []"; bms_blacklist_add gjs
check "empty list, the '@as []' spelling gsettings also emits" "['gjs']"

STATE="['Plank', 'gjs', 'Conky']"; bms_blacklist_add gjs
check "already present -- idempotent rerun, no duplicate" "['Plank', 'gjs', 'Conky']"

# The regression this function exists for: the first version assigned the whole
# list, so a rerun deleted anything the user had added themselves.
STATE="['MyOwnApp']"; bms_blacklist_add gjs
check "never clobbers a hand-added entry" "['MyOwnApp', 'gjs']"

# install-desktop.sh now calls this three times in a row (gjs + the two
# browsers). Each add must see the previous one's write.
STATE="['Plank']"
bms_blacklist_add gjs; bms_blacklist_add google-chrome; bms_blacklist_add brave-browser
check "three sequential adds accumulate" "['Plank', 'gjs', 'google-chrome', 'brave-browser']"

# --- removal, which --uninstall does. The rule is the same in reverse: take
# back what this installer added and leave everything else exactly where it is.

STATE="['MyOwnApp', 'gjs', 'Conky']"; bms_blacklist_remove gjs
check "removes one entry, keeps the user's" "['MyOwnApp', 'Conky']"

STATE="['gjs']"; bms_blacklist_remove gjs
check "removing the only entry gives the empty list gsettings expects" "@as []"

STATE="['MyOwnApp']"; bms_blacklist_remove gjs
check "removing something that is not there changes nothing" "['MyOwnApp']"

STATE="['gjs', 'google-chrome', 'brave-browser', 'MyOwnApp']"
bms_blacklist_remove gjs; bms_blacklist_remove google-chrome; bms_blacklist_remove brave-browser
check "a full uninstall leaves the hand-added entry alone" "['MyOwnApp']"

# --- wildcard entries: the browsers' app windows and Steam. They are stored as
# literal patterns for Blur my Shell to match; the shell must never expand them.

STATE="['Plank']"; bms_blacklist_add 'crx_*'; bms_blacklist_add 'crx_*'
check "a wildcard entry is added literally, once" "['Plank', 'crx_*']"

STATE="['Plank']"
for e in gjs google-chrome brave-browser 'crx_*' 'brave-*' 'chrome-*' steam 'steam_app_*'; do
  bms_blacklist_add "$e"
done
check "every installer entry accumulates in order" \
  "['Plank', 'gjs', 'google-chrome', 'brave-browser', 'crx_*', 'brave-*', 'chrome-*', 'steam', 'steam_app_*']"

# The regression set -f exists for: removal splits the list with an unquoted
# expansion, and a file in the working directory whose name fits a wildcard
# entry got substituted for it -- the list came back with the FILE NAME in it.
GLOBDIR=$(mktemp -d); touch "$GLOBDIR/'crx_x'"
STATE="['crx_*', 'MyOwnApp', 'gjs']"
( cd "$GLOBDIR" && bms_blacklist_remove gjs && printf '%s\n' "$STATE" > "$GLOBDIR/out" )
STATE=$(cat "$GLOBDIR/out"); rm -rf "$GLOBDIR"
check "removal never globs a wildcard entry against the working directory" "['crx_*', 'MyOwnApp']"

STATE="['MyOwnApp', 'gjs', 'google-chrome', 'brave-browser', 'crx_*', 'brave-*', 'chrome-*', 'steam', 'steam_app_*']"
for e in gjs google-chrome brave-browser 'crx_*' 'brave-*' 'chrome-*' steam 'steam_app_*'; do
  bms_blacklist_remove "$e"
done
check "a full uninstall with wildcard entries leaves the hand-added entry alone" "['MyOwnApp']"

# The finding this pair exists for: an entry the user ALREADY had must never be
# recorded as ours, or uninstall takes away something we never added.
rm -f "$ADDED"; STATE="['gjs']"; bms_blacklist_add gjs
if [ -f "$ADDED" ]; then echo "FAIL - a pre-existing entry was recorded as ours"; fail=1
else echo "ok   - a pre-existing entry is not recorded as ours"; fi

rm -f "$ADDED"; STATE="['MyOwnApp']"; bms_blacklist_add gjs
if [ "$(cat "$ADDED" 2>/dev/null)" = "gjs" ]; then echo "ok   - an entry we added is recorded"
else echo "FAIL - an entry we added was not recorded"; fail=1; fi

# --- the compositor keys. Same rule again: record what was there before the
# first managed change, and on uninstall put back exactly that. The earlier
# version set enable-all=false unconditionally, turning OFF a setting the user
# may well have had on, and never restored dynamic-opacity at all.

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

checkk() {
  if [ "${KEYS[$2]}" = "$3" ]; then echo "ok   - $1"
  else echo "FAIL - $1"; echo "         want $2=$3, got ${KEYS[$2]}"; fail=1; fi
}

# A user who already had blur on, with dynamic-opacity on too.
rm -f "$BMS_BEFORE"; KEYS=([blur]=false [opacity]=215 [enable-all]=true [dynamic-opacity]=true)
bms_record_original
gsettings set "$APPS" enable-all true; gsettings set "$APPS" dynamic-opacity false
bms_restore_original
checkk "uninstall does not turn off blur the user already had on" enable-all true
checkk "uninstall restores dynamic-opacity it had turned off" dynamic-opacity true

# A user who had neither.
rm -f "$BMS_BEFORE"; KEYS=([blur]=false [opacity]=215 [enable-all]=false [dynamic-opacity]=false)
bms_record_original
gsettings set "$APPS" enable-all true; gsettings set "$APPS" dynamic-opacity false
bms_restore_original
checkk "uninstall turns blur back off when it was off" enable-all false

# A stock Blur my Shell: application blur off, window opacity 215. Install turns
# the blur on and makes windows opaque; uninstall must hand back exactly that.
rm -f "$BMS_BEFORE"; KEYS=([blur]=false [opacity]=215 [enable-all]=false [dynamic-opacity]=true)
bms_record_original
gsettings set "$APPS" blur true; gsettings set "$APPS" opacity 255
gsettings set "$APPS" enable-all true; gsettings set "$APPS" dynamic-opacity false
bms_restore_original
checkk "uninstall turns application blur back off on a stock Blur my Shell" blur false
checkk "uninstall restores the stock window opacity" opacity 215

# Upgrading from a release before 1.3.0: the record holds only enable-all and
# dynamic-opacity, written while both still held the user's values. Blur and
# opacity were never touched by that release, so they still hold the user's
# values too. The upgrade must add those two -- and must not re-read the two
# already recorded, which by now hold ours.
rm -f "$BMS_BEFORE"; install -d "$STATE_DIR"
printf 'enable-all=%s\ndynamic-opacity=%s\n' false true > "$BMS_BEFORE"   # 1.2.x record
KEYS=([blur]=false [opacity]=215 [enable-all]=true [dynamic-opacity]=false)    # 1.2.x applied
bms_record_original                                                             # the 1.3.0 upgrade
gsettings set "$APPS" blur true; gsettings set "$APPS" opacity 255
bms_restore_original
checkk "an upgraded install restores application blur it switched on" blur false
checkk "an upgraded install restores the window opacity it changed" opacity 215
checkk "an upgraded install still restores the 1.2.x record" enable-all false
checkk "and never re-reads a key already recorded" dynamic-opacity true
if [ -e "$BMS_BEFORE.new" ]; then echo "FAIL - a temporary record was left behind"; fail=1
else echo "ok   - no temporary record is left behind"; fi

# Recording happens once. A second install must not capture our own values.
rm -f "$BMS_BEFORE"; KEYS=([blur]=false [opacity]=215 [enable-all]=true [dynamic-opacity]=true)
bms_record_original
gsettings set "$APPS" enable-all true; gsettings set "$APPS" dynamic-opacity false
bms_record_original                       # the upgrade
bms_restore_original
checkk "an upgrade does not overwrite the original record" dynamic-opacity true

# --stylesheet-only never records, so uninstall must leave dconf alone.
rm -f "$BMS_BEFORE"; KEYS=([blur]=false [opacity]=215 [enable-all]=true [dynamic-opacity]=true)
bms_restore_original
checkk "uninstall after --stylesheet-only touches nothing" enable-all true

# The record must survive an uninstall attempted while the extension is gone,
# because the dconf values outlive the extension and a reinstall brings them back.
rm -f "$ADDED"; STATE="['MyOwnApp']"; bms_blacklist_add gjs
mv "$BMS/schemas" "$BMS/schemas.away"
bms_blacklist_remove gjs
if [ -f "$ADDED" ]; then echo "ok   - the record survives an uninstall with the extension gone"
else echo "FAIL - the record was discarded with entries still in dconf"; fail=1; fi
mv "$BMS/schemas.away" "$BMS/schemas"
check "and dconf was not touched while it was gone" "['MyOwnApp', 'gjs']"

exit "$fail"
