#!/usr/bin/env bash
# Runs as root only inside run.py's disposable guest.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export https_proxy=http://192.0.2.100:18888 http_proxy=http://192.0.2.100:18888
cd /tmp/accept
mkdir -p evidence
exec > >(tee evidence/acceptance.log) 2>&1
fail() { echo "FAIL: $*" >&2; exit 1; }
test "$(cat /sys/class/dmi/id/product_name)" = 'Norvi Acceptance' || fail 'acceptance requires the disposable QEMU guest'
test -d /run/systemd/system || fail 'systemd is not running'
dpkg-query -W > evidence/packages-before.tsv
for package in build-essential debhelper libmutter-18-dev libgtk-4-dev qt6-base-dev; do
    if dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
        fail "developer package $package was preinstalled in the clean guest"
    fi
done
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl gnupg ubuntu-session gnome-shell \
    gnome-control-center gdm3 plymouth-theme-spinner dconf-cli dbus-x11 \
    libgl1-mesa-dri libegl-mesa0 gvfs at-spi2-core unzip python3 python3-gi \
    gir1.2-gtk-4.0 piuparts debootstrap
if [ -d archive ]; then
    # The same setup.sh and authenticated APT path, served from these exact
    # unpublished bytes. Only this guest trusts their disposable signing key.
    # shellcheck source=tests/vm/archive.sh
    source source/tests/vm/archive.sh archive
fi
curl -fLsS https://apt.norvitech.com/setup.sh -o evidence/setup.sh
sh < evidence/setup.sh
test "$(dpkg-query -S /etc/apt/sources.list.d/norvi.sources)" = 'norvi-archive-keyring: /etc/apt/sources.list.d/norvi.sources'
test "$(dpkg-query -S /usr/share/keyrings/norvi-archive-keyring.gpg)" = 'norvi-archive-keyring: /usr/share/keyrings/norvi-archive-keyring.gpg'
# Qualification also exercises packages waiting in the signed candidate
# channel. This separate source never changes the keyring-owned stable source.
sed 's/^Suites: resolute$/Suites: resolute-candidate/' /etc/apt/sources.list.d/norvi.sources > /etc/apt/sources.list.d/norvi-candidate.sources
apt-get update
if curl -fLsS --max-time 10 https://example.invalid > /dev/null 2>&1; then
    fail 'unknown HTTPS origin was permitted'
fi
if timeout 3 bash -c 'exec 3<>/dev/tcp/192.0.2.2/22'; then
    fail 'guest reached an unforwarded host service'
fi
apt-get install -y -t resolute-candidate norvi-os
dpkg-query -W > evidence/packages-installed.tsv
apt-cache policy norvi-os > evidence/package-policy.txt
if [ ! -f candidate.deb ] && [ -d archive ]; then
    apt-get download "norvi-os=$(dpkg-query -W -f='${Version}' norvi-os)"
    mv norvi-os_*_all.deb candidate.deb
fi
test -s candidate.deb || fail 'the producer candidate artifact is required'
sha256sum candidate.deb > evidence/candidate.sha256
apt-get install -y --reinstall ./candidate.deb
test "$(dpkg-query -W -f='${Version}' norvi-os)" = "$(dpkg-deb -f candidate.deb Version)"
dpkg --audit > evidence/dpkg-audit.txt
test ! -s evidence/dpkg-audit.txt
recommends=$(dpkg-query -W -f='${Recommends}' norvi-os | tr ',' '\n' | awk '{print $1}')
# Debian validates these package-name fields; splitting the list is intentional.
# shellcheck disable=SC2086
dpkg --verify norvi-os $recommends > evidence/dpkg-verify.txt
test ! -s evidence/dpkg-verify.txt
systemctl start gdm3
systemctl is-active --quiet gdm3
for _ in $(seq 30); do
    pgrep -f 'gnome-shell --mode=gdm' > /dev/null && break
    sleep 1
done
pgrep -f 'gnome-shell --mode=gdm' > evidence/greeter-pids.txt || fail 'GDM did not launch its GNOME greeter'
systemctl status gdm3 --no-pager > evidence/gdm-status.txt
curl -fLsS 'https://github.com/aunetx/blur-my-shell/releases/download/v76/blur-my-shell%40aunetx.shell-extension.zip' -o blur-my-shell.zip
printf '%s\n' 'fff4deaf74d384171241e2242c4034b4c2acbc9c516264d29ddbd34f7737da0e  blur-my-shell.zip' | sha256sum -c -
chown demo:demo evidence
multiarch=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("MULTIARCH"))')
GI_TYPELIB_PATH="/usr/lib/$multiarch/mutter-18"
export GI_TYPELIB_PATH
runuser -u demo -- bash source/tests/vm/session.sh

# Save the real distribution state before branding. Nothing in this comparison
# assumes what Ubuntu's conffiles, alternatives or diversion list look like.
mkdir -p evidence/before evidence/after
snapshot() {
    local dest=$1
    cp /etc/gdm3/greeter.dconf-defaults "$dest/greeter"
    sha256sum /usr/share/pixmaps/ubuntu-logo-text{,-dark}.svg > "$dest/logos.sha256"
    dpkg-divert --list | LC_ALL=C sort > "$dest/diversions"
    update-alternatives --query default.plymouth > "$dest/plymouth"
}
snapshot evidence/before
for pass in 1 2; do
    echo "Branding install cycle $pass"
    bash source/install.sh
    grep -q "logo='/usr/local/share/norvitech/norvitech-gdm-logo.svg'" /etc/gdm3/greeter.dconf-defaults
    test "$(readlink -f /usr/share/plymouth/themes/default.plymouth)" = /usr/share/plymouth/themes/norvitech/norvitech.plymouth
    cmp source/assets/norvitech-logo-dark.svg /usr/share/pixmaps/ubuntu-logo-text.svg
    cmp source/assets/norvitech-logo-light.svg /usr/share/pixmaps/ubuntu-logo-text-dark.svg
    strings /var/lib/gdm3/greeter-dconf-defaults | grep -q norvitech-gdm-logo
    newest=$(find /boot -name 'initrd.img-*' | sort -V | tail -1)
    if command -v lsinitramfs >/dev/null; then
        lsinitramfs "$newest" | grep -F norvitech/watermark.png > /dev/null
    else
        lsinitrd "$newest" | grep -F norvitech/watermark.png > /dev/null
    fi
done
bash source/uninstall.sh
bash source/uninstall.sh
snapshot evidence/after
diff -ru evidence/before evidence/after
echo 'PASS: branding installs twice and restores the original system state twice'

# A metapackage must remain independently removable; its recommended components
# stay installed while the metapackage passes each package-manager transition.
apt-get install -y --reinstall ./candidate.deb
apt-get remove -y norvi-os
test "$(dpkg-query -W -f='${db:Status-Status}' gnome-shell-extension-xdock)" = installed
apt-get purge -y norvi-os
apt-get install -y ./candidate.deb
dpkg --audit > evidence/dpkg-audit-final.txt
test ! -s evidence/dpkg-audit-final.txt
dpkg-query -W > evidence/packages-final.tsv
echo 'PASS: candidate install, upgrade, remove, purge and reinstall'
bash source/tests/vm/piuparts.sh
