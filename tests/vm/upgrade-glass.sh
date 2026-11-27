#!/usr/bin/env bash
# Use the producer's two Debians as a signed local repository in the VM.
# Let Ubuntu's normal upgrade select the newly recommended desktop component.
set -euo pipefail
test "$(cat /sys/class/dmi/id/product_name)" = 'Norvi Acceptance'
repo=/var/tmp/norvi-producer
install -d -m755 "$repo"
for file in candidate.deb companion.deb; do
    name=$(dpkg-deb -f "$file" Package)
    version=$(dpkg-deb -f "$file" Version)
    architecture=$(dpkg-deb -f "$file" Architecture)
    install -m644 "$file" "$repo/${name}_${version}_${architecture}.deb"
done
# Before this desktop reaches the archive, exercise its published components.
# The archive publication test installs exclusively from the signed archive.
add_release_package() {
    local project=$1 tag=$2 file=$3 digest=$4
    curl -fLsS "https://github.com/spencernorton/$project/releases/download/$tag/$file" -o "$repo/$file"
    (cd "$repo" && printf '%s  %s\n' "$digest" "$file" | sha256sum -c -)
}
add_release_package gnome-rounded-blur v2.0.0 gnome-rounded-blur_2.0.0-1_amd64.deb \
    7a19de3972c8ed0acb1b7b69ca207522354dd2234103097319e25d8e2e17a681
add_release_package workspace-bar v1.0.4 gnome-shell-extension-workspace-bar_1.0.4_all.deb \
    0ae7b2f6ab6a29f1f87f4ed573f63d72f3ab4e8a001cdae4d1c3143e6986f3a4
add_release_package xdock v2.4.0 gnome-shell-extension-xdock_2.4.0_all.deb \
    fd346b78776d373135e3704a26968f099b9a3b01d187c7d3a2b8afc48bfd7f27
key=$(mktemp -d)
trap 'rm -rf "$key"' EXIT
gpg --homedir "$key" --batch --passphrase '' --quick-generate-key 'Desktop package test' ed25519 sign 1d
gpg --homedir "$key" --export > /usr/share/keyrings/norvi-producer-test.gpg
(cd "$repo" && apt-ftparchive packages . > Packages && apt-ftparchive release . > Release.new && mv Release.new Release &&
    gpg --batch --homedir "$key" --clearsign -o InRelease Release)
list=/etc/apt/sources.list.d/norvi-producer.list
echo 'deb [signed-by=/usr/share/keyrings/norvi-producer-test.gpg] file:/var/tmp/norvi-producer ./' > "$list"
apt-get update -qq
apt-cache policy norvi-os norvi-window-glass gnome-rounded-blur gnome-shell-extension-workspace-bar gnome-shell-extension-xdock > evidence/upgrade-policy.txt
LC_ALL=C apt -s upgrade > evidence/default-upgrade.txt 2>&1
grep -Eq '^Inst norvi-window-glass(:amd64)? ' evidence/default-upgrade.txt

# Apply the same upgrade policy to the producer's candidates in this guest.
# The full simulation above includes all configured Ubuntu and Norvi sources.
mkdir -p "$key/empty-sources.d"
apt-get -y --no-remove --with-new-pkgs \
    -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts="$key/empty-sources.d" upgrade
test "$(dpkg-query -W -f='${db:Status-Status}' gnome-rounded-blur)" = installed
dpkg --compare-versions "$(dpkg-query -W -f='${Version}' gnome-rounded-blur)" ge 2.0.0
dpkg --compare-versions "$(dpkg-query -W -f='${Version}' gnome-shell-extension-workspace-bar)" ge 1.0.4
dpkg --compare-versions "$(dpkg-query -W -f='${Version}' gnome-shell-extension-xdock)" ge 2.4.0
LC_ALL=C apt-get -s remove norvi-window-glass > evidence/optional-glass-removal.txt
grep -Eq '^Remv norvi-window-glass(:amd64)? ' evidence/optional-glass-removal.txt
if grep -Eq '^Remv norvi-os(:[a-z0-9-]+)? ' evidence/optional-glass-removal.txt; then
    echo 'Removing optional glass would remove the desktop metapackage.' >&2
    exit 1
fi
for file in candidate.deb companion.deb; do
    package=$(dpkg-deb -f "$file" Package)
    test "$(dpkg-query -W -f='${Version}' "$package")" = "$(dpkg-deb -f "$file" Version)"
    ctrl=$(mktemp -d)
    dpkg-deb -e "$file" "$ctrl"
    cmp "$ctrl/md5sums" "/var/lib/dpkg/info/$package.md5sums"
    rm -rf "$ctrl"
done
