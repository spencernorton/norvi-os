#!/usr/bin/env bash
# Install the producer's bytes even when this version is already in candidate.
set -euo pipefail
candidate=$1
test "$(dpkg-deb -f "$candidate" Package)" = norvi-os
version=$(dpkg-deb -f "$candidate" Version)
if [ "$(dpkg-query -W -f='${db:Status-Status}' norvi-os 2>/dev/null || true)" = installed ]; then
    installed=$(dpkg-query -W -f='${Version}' norvi-os)
    dpkg --compare-versions "$version" ge "$installed" || {
        echo "Refusing older candidate $version (installed: $installed)" >&2
        exit 1
    }
fi
# Resolve the producer's relationships, not the archive's same-version
# metadata. The desktop acceptance requires its recommended components too.
# APT can otherwise choose an archive payload after a purge or while repairing
# dependencies. Only dpkg receives the explicit producer file for installation.
relationships=()
for field in Pre-Depends Depends Recommends; do
    relation=$(dpkg-deb -f "$candidate" "$field")
    if [ -n "$relation" ]; then
        relationships+=("$relation")
    fi
done
if [ "${#relationships[@]}" -gt 0 ]; then
    apt-get satisfy -y --no-remove "${relationships[@]}"
fi
dpkg --install "$candidate"
test "$(dpkg-query -W -f='${Version}' norvi-os)" = "$version"
control=$(mktemp -d)
trap 'rm -rf "$control"' EXIT
dpkg-deb -e "$candidate" "$control"
cmp "$control/md5sums" /var/lib/dpkg/info/norvi-os.md5sums
verification=$(dpkg --verify norvi-os)
test -z "$verification" || { printf '%s\n' "$verification" >&2; exit 1; }
