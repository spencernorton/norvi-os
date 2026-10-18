# Contributing to NorviOS

Thanks for your interest. NorviOS is a small project with one maintainer, so
the process is deliberately light — but a few things are fixed.

## How changes land

GitHub is the development home. Branch from `main` and open a pull request
into `main`. Build, test and privacy checks must pass before merge. Changes
ship in tagged releases; see [the release guide](docs/RELEASING.md).

Use a GitHub noreply address for commit authorship if you prefer to keep
your personal address private. Review your diff and commit messages before
pushing: public history, logs and uploaded screenshots are public data.

## Before you start

- **Bugs** — open a [bug report](https://github.com/spencernorton/norvi-os/issues/new/choose).
  A report with reproduction steps, versions and a scrubbed log excerpt is
  usually fixed faster than a pull request that arrives without one.
- **Features** — open a feature request first. NorviOS has strong opinions
  about going only through the override points Ubuntu provides, and about
  undoing exactly what it did (see the README); an idea that cuts across them
  needs a conversation before code.
- **Security** — never in a public issue. Use
  [private vulnerability reporting](https://github.com/spencernorton/norvi-os/security/advisories/new);
  see [SECURITY.md](SECURITY.md).

## Working on the code

```bash
sudo apt install shellcheck python3 python3-gi gir1.2-gtk-3.0 gir1.2-gtk-4.0 build-essential debhelper dpkg-dev
python3 desktop/check_contrast.py              # what CI runs: the glass alpha keeps text readable
python3 desktop/check_gtk_css.py               # both stylesheets parse with the real GTK parsers
bash desktop/test-gtk-css-check.sh
bash desktop/test-blacklist-merge.sh
bash desktop/test-uninstall-restore.sh
bash desktop/test-install-desktop.sh
shellcheck -S warning install.sh uninstall.sh desktop/*.sh scripts/build.sh   # lint; CI enforces it
scripts/build.sh                               # the norvi-os metapackage into dist/
```

The installers change boot and login configuration, so they are not run in
CI. Try a change on a virtual machine with a fresh Ubuntu 26.04 desktop, and
say in the pull request what you ran and what you saw.

- Never edit an Ubuntu-owned file in place. Use the override point Ubuntu or
  Debian provides — `update-alternatives`, a local `dpkg-divert`, a conffile,
  a per-user file — and make the matching uninstall step undo exactly that.
- The desktop installer records what it changes before it changes it, and
  `--uninstall` removes only what is recorded. Keep both halves in step; the
  two test scripts carry byte-identical copies of the functions they check.
- Keep a change to one concern. A pull request that fixes a bug and
  reformats a file is two pull requests.
- Tests: a bug fix carries a regression test; a feature carries the smallest
  test that fails without it.
- Commits carry a `Signed-off-by:` line (`git commit -s`, the Developer
  Certificate of Origin). There is no CLA.
- No secrets, hostnames, personal data or screenshots of a real desktop in
  the diff — the export gate rejects them and the pull request will be sent
  back.

## Out of scope

So nobody wastes an evening on it, NorviOS will not accept:

- telemetry, analytics, or any network access in either installer
- editing Ubuntu-owned files in place, or anything that stops an Ubuntu update from applying
- changes to the NorviTech artwork — it is not under the GPL; see [NOTICE](NOTICE)
- a theme switcher or settings app — NorviOS applies one look and removes it cleanly

## Pull request checklist

The template asks for what changed, why, and how it was tested, plus a
confirmation that the diff carries no secrets, machine names or personal
paths. Fill it in — it is what the reviewer reads first.

## Licence

By contributing you agree that your contribution is licensed under the
[GNU General Public License, version 3 or later](LICENSE) that covers the
project's code. The NorviTech artwork is not open to contributions.
