# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub:
**[Report a vulnerability](https://github.com/spencernorton/norvi-os/security/advisories/new)**.
Do not open a public issue, and do not include real credentials, machine names
or personal paths in the report — a description and a minimal reproduction
are enough.

There is no e-mail address for security reports; the advisory form is the
only channel, and it is the one that is monitored. You will get an
acknowledgement within a week. Fixes ship as a tagged release; the advisory
is published once the release is out, and credits you unless you ask
otherwise.

## Supported versions

Only the latest tagged release is supported. NorviOS has no LTS line.

## Scope

In scope: this repository's code and the artefacts it ships.
Out of scope: Blur my Shell itself (report to
[its own project](https://github.com/aunetx/blur-my-shell)), the Ubuntu
packages NorviOS configures — Plymouth, GDM, GNOME Settings — which are
reported to Ubuntu, and machines the maintainer does not operate.

## What NorviOS does with credentials and data

Understanding the trust model helps you judge what is and is not a finding:

- **The system half runs as root, once.** `install.sh` and `uninstall.sh` write
  a Plymouth theme, one line of GDM greeter configuration and two local
  `dpkg` diversions, then rebuild the initramfs. They take no input other than
  the repository they run from. A way to make either one write outside the
  paths listed in the README is a bug worth reporting.
- **No network, no credentials.** Neither installer downloads anything, and
  nothing in this repository holds or asks for a secret.
- **The desktop half is per-user and refuses root.** It changes your own GTK
  stylesheets and Blur my Shell's settings, and nothing else.
- **Styling is not a security boundary, but legibility is a safety property.**
  The glass stylesheet changes how windows paint, not what any app can do. A
  change that makes a password prompt, a permission dialog or any primary text
  illegible is a bug; the contrast check exists to stop one shipping.
- **Local state** lives under `~/.local/state/norvi-os/` with ordinary user
  permissions: the Blur my Shell settings and blacklist entries the desktop
  installer changed, kept so that `--uninstall` can undo exactly those. No
  telemetry is sent anywhere.
