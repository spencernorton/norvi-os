# Clean guest acceptance

The required `checks` result requires both package checks and a clean VM run;
failure, cancellation or skipping either cannot produce a green aggregate.
The runtime job downloads the package artifact from its own workflow run and
records its SHA-256. It never substitutes a separately built binary.

`run.py` verifies a pinned Ubuntu 26.04 cloud image, creates a disposable disk
overlay and SSH identity, boots systemd and runs `accept.sh`. QEMU uses KVM when
available and records the accelerator. Its restricted user network forwards
only SSH and an HTTPS proxy whose allowlist resolves exclusively to public
addresses. Unknown origins and direct host access are negative controls. The
guest uses real signed APT metadata; package policy, versions, checksums,
GDM status, loaded extension paths, dconf/CSS comparisons and rollback results
are retained. No SSH identity, guest disk or fixture private key is uploaded.

The route installs the signed candidate-channel metapackage, upgrades it with
the workflow's exact candidate, loads all seven packaged extensions from
`/usr/share` in a real private GNOME session and opens Quick Settings and the
application launcher. Blur my Shell v73 uses the documented upstream release
and checksum. The actual normal-user desktop installer must preserve existing
CSS and dconf through two installs and two uninstalls. The root installer must
populate the initramfs and greeter database and restore the original GDM file,
Plymouth alternative, About logos and diversion list through two cycles. APT
also exercises reinstall, remove, purge and final install.
In that same guest, real `piuparts -d resolute` uses a separately bootstrapped
minimal chroot with the documented keyring bootstrap to check metapackage
upgrade, remove, purge, reinstall and filesystem ownership. `dpkg --verify` checks the installed
metapackage and every recommended component before branding changes.

For an unpublished signed archive, `--archive PATH` copies that exact tree into
the guest. The guest serves it under the public repository names with its own
temporary CA and signing key. Branch keys remain confined to the guest, normal
TLS and APT signature verification remain enabled, and the package is fetched
from that authenticated index. This lets a publisher qualify its own output
before deploying it. No production signing secret is needed by this harness.

Local prerequisites: Python 3.11+, QEMU, OpenSSH, genisoimage and curl:

```sh
python3 tests/vm/run.py --candidate dist/norvi-os_1.4.1_all.deb --out vm-evidence
```

This is software-rendered guest qualification. Physical GPU rendering and a
person's visual comparison remain separate acceptance work.
