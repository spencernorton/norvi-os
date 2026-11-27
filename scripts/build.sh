#!/usr/bin/env bash
# Build the independently installable desktop and amd64 window glass packages.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=$(realpath -m "${1:-$root/dist}")
version=$(dpkg-parsechangelog -l "$root/debian/changelog" -S Version)
stamp=${SOURCE_DATE_EPOCH:-$(dpkg-parsechangelog -l "$root/debian/changelog" -S Timestamp)}
export SOURCE_DATE_EPOCH="$stamp"
mkdir -p "$out"
packages=("norvi-os_${version}_all.deb")
build_type=--build=all
if [ "$(dpkg-architecture -qDEB_HOST_ARCH)" = amd64 ]; then
    packages+=("norvi-window-glass_${version}_amd64.deb")
    build_type=--build=binary
fi
(cd "$root" && dpkg-buildpackage -us -uc "$build_type")
for file in "${packages[@]}"; do
    mv "$root/../$file" "$out/"
done
rm -f "$root/../norvi-os_${version}"_*.buildinfo "$root/../norvi-os_${version}"_*.changes
test "$(dpkg-deb --field "$out/norvi-os_${version}_all.deb" Depends)" = norvi-archive-keyring
ls -l "$out"
