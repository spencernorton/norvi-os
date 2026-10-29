#!/usr/bin/env bash
# Source inside the disposable guest to qualify an unpublished signed archive.
set -euo pipefail
archive=$(realpath "$1")
test -s "$archive/norvi-archive-keyring.asc"
test -s "$archive/dists/resolute/InRelease"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout /tmp/accept/fixture-private.pem -out /tmp/accept/fixture-ca.crt \
    -subj /CN=apt.globalentry.systems \
    -addext subjectAltName=DNS:apt.globalentry.systems,DNS:apt.norvitech.com > /dev/null 2>&1
install -m644 /tmp/accept/fixture-ca.crt /usr/local/share/ca-certificates/acceptance-archive.crt
update-ca-certificates > /dev/null
printf '%s\n' '127.0.0.1 apt.globalentry.systems apt.norvitech.com' >> /etc/hosts
cat > /etc/apt/apt.conf.d/99acceptance-archive-direct <<'CONFIG'
Acquire::https::Proxy::apt.globalentry.systems "DIRECT";
Acquire::https::Proxy::apt.norvitech.com "DIRECT";
CONFIG
export no_proxy=apt.globalentry.systems,apt.norvitech.com,127.0.0.1,localhost
export NO_PROXY="$no_proxy"
gpg --batch --yes --dearmor -o /tmp/accept/fixture-signing.gpg "$archive/norvi-archive-keyring.asc"
export NORVI_APT_FINGERPRINT
NORVI_APT_FINGERPRINT=$(gpg --batch --show-keys --with-colons "$archive/norvi-archive-keyring.asc" 2>/dev/null | awk -F: '$1=="fpr" {print $10; exit}')
[[ "$NORVI_APT_FINGERPRINT" =~ ^[0-9A-F]{40}$ ]]
# Branch signing keys are disposable. The package's production public key
# must not replace the branch key halfway through this isolated transaction.
cat > /etc/apt/apt.conf.d/99acceptance-archive-key <<'CONFIG'
DPkg::Post-Invoke { "install -m644 /tmp/accept/fixture-signing.gpg /usr/share/keyrings/norvi-archive-keyring.gpg"; };
CONFIG
python3 source/tests/vm/serve-archive.py "$archive" > evidence/archive-server.log 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
for _ in $(seq 30); do
    curl -fLsS https://apt.globalentry.systems/dists/resolute/InRelease > /dev/null 2>&1 && break
    kill -0 "$fixture_pid"
    sleep 1
done
curl -fLsS https://apt.globalentry.systems/dists/resolute/InRelease > evidence/fixture-InRelease
cmp "$archive/dists/resolute/InRelease" evidence/fixture-InRelease
