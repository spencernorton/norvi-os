#!/usr/bin/env bash
# The real piuparts tool runs in the same disposable VM as the desktop checks.
# Its minimal chroot checks metapackage/keyring ownership and package cleanup;
# the surrounding VM route separately tests every recommended desktop component.
set -euo pipefail
base=/tmp/accept/piuparts-base
debootstrap --variant=minbase --include=ca-certificates,curl,gnupg \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    resolute "$base" https://archive.ubuntu.com/ubuntu > evidence/debootstrap.log 2>&1 || {
    cat evidence/debootstrap.log; exit 1;
}
# /tmp may be nodev. Bootstrap needs real /dev/null and /dev/urandom before
# piuparts creates its own chroot and device bind mounts.
mount --bind /dev "$base/dev"
trap 'umount "$base/dev"' EXIT
install -d "$base/usr/share/keyrings" "$base/etc/apt/apt.conf.d" "$base/etc/apt/sources.list.d"
cp /etc/apt/apt.conf.d/99acceptance-proxy "$base/etc/apt/apt.conf.d/"
cp /etc/apt/sources.list.d/norvi-candidate.sources "$base/etc/apt/sources.list.d/"
cp /etc/hosts "$base/etc/hosts"
if [ -d archive ]; then
    # The same isolated signing/TLS fixture as the outer guest. Preserve its
    # key through dpkg without relaxing signature or certificate checks.
    install -d "$base/tmp/accept" "$base/usr/local/share/ca-certificates"
    cp /tmp/accept/fixture-signing.gpg "$base/tmp/accept/"
    cp /usr/local/share/ca-certificates/acceptance-archive.crt "$base/usr/local/share/ca-certificates/"
    cp /etc/apt/apt.conf.d/99acceptance-archive-{direct,key} "$base/etc/apt/apt.conf.d/"
    chroot "$base" update-ca-certificates > /dev/null
fi
# The documented bootstrap is the prerequisite for this metapackage, not a
# developer dependency. It installs the keyring as an explicitly selected
# package, so removing norvi-os must preserve that existing subscriber state.
chroot "$base" sh < evidence/setup.sh > evidence/piuparts-bootstrap.log 2>&1 || {
    cat evidence/piuparts-bootstrap.log; exit 1;
}
if [ -d archive ]; then
    # The outer guest exercised setup.sh with the branch key. Filesystem
    # qualification must leave every packaged byte intact: use separate APT
    # fixture sources/trust in this chroot instead of rewriting an owned key.
    version=$(dpkg-query -W -f='${Version}' norvi-archive-keyring)
    apt-get download "norvi-archive-keyring=$version"
    keyring_deb=$(find . -maxdepth 1 -name 'norvi-archive-keyring_*_all.deb' -print -quit)
    original=$(mktemp -d)
    dpkg-deb -x "$keyring_deb" "$original"
    expected=$(python3 - <<'PY'
import re
from pathlib import Path
pins = re.findall(r'^FINGERPRINT=([0-9A-Fa-f]{40})$', Path('evidence/setup.sh').read_text(), re.MULTILINE)
assert len(pins) == 1, 'bootstrap must name exactly one production trust fingerprint'
print(pins[0].upper())
PY
    )
    embedded=$(gpg --batch --show-keys --with-colons "$original/usr/share/keyrings/norvi-archive-keyring.gpg" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')
    test "$embedded" = "$expected"
    cp "$original/usr/share/keyrings/norvi-archive-keyring.gpg" "$base/usr/share/keyrings/"
    rm -rf "$original"
    rm "$base/etc/apt/apt.conf.d/99acceptance-archive-key"
    install -d "$base/usr/local/share/keyrings" "$base/etc/apt/acceptance-sources.d"
    cp /tmp/accept/fixture-signing.gpg "$base/usr/local/share/keyrings/acceptance.gpg"
    for file in norvi.sources norvi-candidate.sources; do
        sed 's|/usr/share/keyrings/norvi-archive-keyring.gpg|/usr/local/share/keyrings/acceptance.gpg|' \
            "$base/etc/apt/sources.list.d/$file" > "$base/etc/apt/acceptance-sources.d/$file"
    done
    printf '%s\n' 'Dir::Etc::sourceparts "/etc/apt/acceptance-sources.d";' > "$base/etc/apt/apt.conf.d/99acceptance-piuparts-sources"
    chroot "$base" dpkg --verify norvi-archive-keyring > evidence/piuparts-keyring-verify.txt
    test ! -s evidence/piuparts-keyring-verify.txt
fi
umount "$base/dev"
trap - EXIT
piuparts --defaults=ubuntu --distribution=resolute \
    --mirror=https://archive.ubuntu.com/ubuntu \
    --proxy=http://192.0.2.100:18888 --existing-chroot="$base" \
    --install-purge-install --install-remove-install \
    --log-file=evidence/piuparts.log candidate.deb
echo 'PASS: real piuparts install/upgrade/remove/purge/reinstall and ownership checks'
