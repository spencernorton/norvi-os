#!/usr/bin/env python3
"""Run the candidate in a disposable Ubuntu guest, never the host desktop.

Requires qemu-system-x86_64, qemu-img, genisoimage, curl and OpenSSH. The base
is pinned to Ubuntu's signed 2026-10-16 resolute cloud-image manifest. A fresh
overlay, SSH identity and NoCloud seed are discarded even when a check fails.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import subprocess as sp
import sys
import tarfile
import tempfile
import time
from network import Proxy

IMAGE = "ubuntu-26.04-server-cloudimg-amd64.img"
BASE = "https://cloud-images.ubuntu.com/releases/resolute/release-20261016"
SHA256 = "5645d0318ad21f643ebb1ac4567514620e9893380b07b0201fda163baa5b7eb5"


def run(*args, **kwargs):
    return sp.run(args, check=True, **kwargs)


def cancel(_signal, _frame):
    raise KeyboardInterrupt("VM acceptance cancelled")


def main():
    signal.signal(signal.SIGTERM, cancel)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/norvi-vm")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--payload", default="tests/vm/accept.sh")
    parser.add_argument("--archive", type=Path, help="Optional signed APT tree to qualify before publication")
    parser.add_argument("--timeout", type=int, default=2400)
    args = parser.parse_args()
    if not args.candidate and not args.archive:
        parser.error("--candidate from the producer or --archive is required; the guest never builds its own substitute")
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    image = args.cache.resolve() / IMAGE
    if not image.exists():
        run("curl", "-fLsS", "--retry", "3", "--max-time", "600", f"{BASE}/{IMAGE}", "-o", str(image) + ".part")
        Path(str(image) + ".part").replace(image)
    if hashlib.file_digest(image.open("rb"), "sha256").hexdigest() != SHA256:
        raise RuntimeError("Ubuntu cloud image SHA-256 does not match the pinned signed manifest")
    image.chmod(0o444)
    result = {"base_url": f"{BASE}/{IMAGE}", "base_sha256": SHA256, "passed": False}
    vm = None
    with tempfile.TemporaryDirectory(prefix="norvi-vm-") as directory:
        work = Path(directory)
        key = work / "id_ed25519"
        run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key))
        seed = work / "seed"
        seed.mkdir()
        (seed / "meta-data").write_text(json.dumps({"instance-id": "norvi-acceptance", "local-hostname": "demo"}))
        (seed / "user-data").write_text("#cloud-config\n" + json.dumps({
            "users": [{"name": "demo", "shell": "/bin/bash", "lock_passwd": True,
                       "sudo": "ALL=(ALL) NOPASSWD:ALL", "ssh_authorized_keys": [key.with_suffix(".pub").read_text().strip()]}],
            "ssh_pwauth": False, "disable_root": True, "package_update": False,
        }))
        # A restricted SLIRP network deliberately provides no DHCP. Seed its
        # static documentation-only address before the first boot instead.
        (seed / "network-config").write_text(json.dumps({"version": 2, "ethernets": {"acceptance": {
            "match": {"macaddress": "52:54:00:12:34:56"}, "optional": True,
            "addresses": ["192.0.2.15/24"], "routes": [{"to": "default", "via": "192.0.2.2"}],
            "nameservers": {"addresses": ["192.0.2.3"]},
        }}}))
        run("genisoimage", "-quiet", "-output", str(work / "seed.iso"), "-volid", "cidata", "-joliet", "-rock", str(seed))
        run("qemu-img", "create", "-q", "-f", "qcow2", "-F", "qcow2", "-b", str(image), str(work / "guest.qcow2"), "28G")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        accel = "kvm" if os.access("/dev/kvm", os.R_OK | os.W_OK) else "tcg"
        proxy = Proxy()
        forward = shlex.join([sys.executable, str(Path(__file__).with_name("network.py").resolve()), str(proxy.server_address[1])])
        result["acceleration"] = accel
        ssh = ["ssh", "-i", str(key), "-p", str(port), "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=no",
               "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5", "demo@127.0.0.1"]
        vm = sp.Popen(["qemu-system-x86_64", "-accel", accel, "-cpu", "host" if accel == "kvm" else "max",
                       "-smbios", "type=1,manufacturer=QEMU,product=Norvi Acceptance",
                       "-smp", "4", "-m", "6144", "-vga", "virtio", "-display", "none", "-monitor", "none", "-no-reboot",
                       "-drive", f"file={work / 'guest.qcow2'},if=virtio,format=qcow2",
                       "-drive", f"file={work / 'seed.iso'},media=cdrom,readonly=on",
                       "-netdev", f"user,id=n,restrict=on,net=192.0.2.0/24,host=192.0.2.2,dhcpstart=192.0.2.15,dns=192.0.2.3,hostfwd=tcp:127.0.0.1:{port}-:22,guestfwd=tcp:192.0.2.100:18888-cmd:{forward}",
                       "-device", "virtio-net-pci,netdev=n,mac=52:54:00:12:34:56", "-serial", f"file:{args.out / 'serial.log'}"],
                      stdout=open(args.out / "qemu.log", "w"), stderr=sp.STDOUT)
        try:
            until = time.monotonic() + 300
            while time.monotonic() < until:
                if vm.poll() is not None:
                    raise RuntimeError("QEMU exited before the guest booted")
                if sp.run(ssh + ["true"], stdout=sp.DEVNULL, stderr=sp.DEVNULL).returncode == 0:
                    break
                time.sleep(3)
            else:
                raise TimeoutError("Guest did not accept SSH within five minutes")
            run(*ssh, "sudo cloud-init status --wait", timeout=180)
            run(*ssh, "sudo sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources")
            run(*ssh, "sudo tee /etc/apt/apt.conf.d/99acceptance-proxy >/dev/null",
                input='Acquire::https::Proxy "http://192.0.2.100:18888";\n', text=True)
            with tarfile.open(work / "inputs.tar", "w") as archive:
                for item in args.source.resolve().iterdir():
                    if item.name not in {".git", "dist", ".venv", "node_modules"}:
                        archive.add(item, arcname="source/" + item.name)
                if args.candidate:
                    archive.add(args.candidate.resolve(), arcname="candidate.deb")
                    result["candidate_sha256"] = hashlib.file_digest(args.candidate.open("rb"), "sha256").hexdigest()
                if args.archive:
                    archive.add(args.archive.resolve(), arcname="archive")
            with (work / "inputs.tar").open("rb") as data:
                run(*ssh, "mkdir -p /tmp/accept && tar -xf - -C /tmp/accept", stdin=data)
            with (args.out / "acceptance.log").open("w") as log:
                completed = sp.run(ssh + [f"cd /tmp/accept && sudo timeout {args.timeout} bash {shlex.quote('source/' + args.payload)}"],
                                   stdout=log, stderr=sp.STDOUT, timeout=args.timeout + 60)
                result["passed"] = completed.returncode == 0
            print((args.out / "acceptance.log").read_text(), flush=True)
            if not result["passed"]:
                raise RuntimeError("Guest acceptance failed; see acceptance.log and serial.log")
        finally:
            try:
                with (args.out / "guest-evidence.tar.gz").open("wb") as evidence:
                    sp.run(ssh + ["sudo tar -czf - -C /tmp/accept evidence"], stdout=evidence, stderr=sp.DEVNULL, timeout=30)
            except (sp.TimeoutExpired, OSError):
                pass
            vm.terminate()
            try:
                vm.wait(15)
            except sp.TimeoutExpired:
                vm.kill()
                vm.wait()
            proxy.close(args.out / "network.json")
            (args.out / "result.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
