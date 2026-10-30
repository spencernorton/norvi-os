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
# APT treats same-version local bytes as a downgrade when the archive also
# offers that version. The explicit version guard above forbids real downgrade.
apt-get install -y --reinstall --allow-downgrades "$candidate"
test "$(dpkg-query -W -f='${Version}' norvi-os)" = "$version"
control=$(mktemp -d)
trap 'rm -rf "$control"' EXIT
dpkg-deb -e "$candidate" "$control"
cmp "$control/md5sums" /var/lib/dpkg/info/norvi-os.md5sums
verification=$(dpkg --verify norvi-os)
test -z "$verification" || { printf '%s\n' "$verification" >&2; exit 1; }
