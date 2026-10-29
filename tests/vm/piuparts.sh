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
umount "$base/dev"
trap - EXIT
piuparts --defaults=ubuntu --distribution=resolute \
    --mirror=https://archive.ubuntu.com/ubuntu \
    --proxy=http://192.0.2.100:18888 --existing-chroot="$base" \
    --install-purge-install --install-remove-install \
    --log-file=evidence/piuparts.log candidate.deb
echo 'PASS: real piuparts install/upgrade/remove/purge/reinstall and ownership checks'
