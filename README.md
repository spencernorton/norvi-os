<h1 align="center">NorviOS</h1>

<p align="center">
  <strong>The NorviTech look for Ubuntu 26.04, from the boot splash to the window glass.</strong><br>
  A reversible layer over stock Ubuntu and GNOME 50, applied only through the override points Ubuntu provides, so updates keep working and one command puts the original back.
</p>

<p align="center">
  <a href="https://norvitech.com"><img alt="NorviTech Suite" src="https://img.shields.io/badge/NorviTech-Suite-FD8024.svg"></a>
  <a href="https://github.com/spencernorton/norvi-os/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/spencernorton/norvi-os/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/spencernorton/norvi-os/tags"><img alt="Latest release" src="https://img.shields.io/github/v/tag/spencercnorton/norvi-os?label=release&sort=semver"></a>
  <a href="#install"><img alt="Install with APT" src="https://img.shields.io/badge/install-APT-2D2D2D.svg"></a>
  <a href="LICENSE"><img alt="Licence" src="https://img.shields.io/badge/licence-GPL--3.0--or--later-blue.svg"></a>
  <a href="https://buy.stripe.com/8x26oH2U44f65TRe574wM04"><img alt="Donate" src="https://img.shields.io/badge/donate-Stripe-635bff.svg?logo=stripe&logoColor=white"></a>
</p>

<p align="center">
  <img alt="The NorviOS desktop on Ubuntu 26.04: a transparent top bar with named workspaces on the left and the weather and clock on the right, three sticky notes pinned to the right edge, a Files window rendered as frosted glass, and a centred dock with a blurred plate at the bottom." src="docs/screenshots/desktop.png" width="900">
</p>

Every screenshot here was captured on a fresh Ubuntu 26.04 virtual machine with a demo account, a generated wallpaper and invented notes; nothing personal.

NorviOS is the desktop the NorviTech apps are built on: stock Ubuntu 26.04 LTS
with GNOME 50 on Wayland, rebranded from the first boot frame and restyled so
GTK windows read as frosted glass. It is not a separate distribution. This
repository is a layer you install on an existing Ubuntu desktop, and remove
again, with one command for each half.

## What it does

**Brands the boot.** A Plymouth theme — the NorviTech mark on black, above
Ubuntu's own spinner — is registered with `update-alternatives` at a higher
priority than Ubuntu's, and built into the initramfs of every installed
kernel. No Ubuntu file is edited.

**Brands the login screen and Settings → About.** The login screen logo goes
through Debian's greeter-customisation conffile, and the edit is validated
with `dconf compile` before it can reach the live greeter. The About logo, in
a light and a dark variant, replaces Ubuntu's two logo files through local
`dpkg` diversions, with Ubuntu's copies kept beside them.

<p align="center">
  <img alt="The NorviOS boot splash: the orange NorviTech mark centred on black, with Ubuntu's spinner near the bottom." src="docs/screenshots/boot.png" width="445">
  <img alt="The Ubuntu login screen with the white NorviTech mark at the bottom in place of Ubuntu's logo." src="docs/screenshots/login.png" width="445">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/about-dark.png">
    <img alt="GNOME Settings open at About, showing the NorviTech logo where Ubuntu's would be, in the NorviOS desktop." src="docs/screenshots/about-light.png" width="700">
  </picture>
</p>

**Turns GTK windows to glass.** A per-user GTK3 and GTK4 stylesheet stops
each window painting its background at full opacity, and
[Blur my Shell](https://extensions.gnome.org/extension/3193/blur-my-shell/)
blurs the desktop behind it. Header bars and page backgrounds go glass, a
window's sidebar turns solid while the window has focus, and text, lists and
canvases stay opaque. The installer refuses any transparency that would take
primary text below WCAG AA contrast.

**Undoes exactly what it did.** `uninstall.sh` restores Ubuntu's boot splash,
login screen and logo files. The desktop installer records what it changes
before changing it — a stylesheet you already had, your Blur my Shell
settings, the blacklist entries it adds — and `--uninstall` puts back exactly
that, and nothing that was yours.

### The desktop around it

The screenshots show the whole NorviOS desktop, not just what this repository
installs. The rest is a set of GNOME Shell extensions, most of them
NorviTech's own and several of them forks. The ones marked *published* have
their own repositories and releases. The others are **not published yet**:
each needs its own licence and code review first. Until then this is what
they are, so nothing on this page is a mystery.

| On screen | Extension | Origin |
|---|---|---|
| The dock, centred at the bottom, blurred, and the app launcher that opens from it, with drawers you create from a right-click | [XDock](https://github.com/spencernorton/xdock) | NorviTech fork of [Dash to Dock](https://github.com/micheleg/dash-to-dock), *published* |
| The blur behind menus and windows, with rounded corners | [Blur my Shell](https://github.com/aunetx/blur-my-shell) and [gnome-rounded-blur](https://github.com/spencernorton/gnome-rounded-blur) | Blur my Shell as upstream releases it (blurred menus need v73 or later); gnome-rounded-blur is the Ubuntu build of [kancko/gnome-rounded-blur](https://github.com/kancko/gnome-rounded-blur), *published* |
| Named workspaces on the left of the top bar | [Workspace Bar](https://github.com/spencernorton/workspace-bar) | NorviTech, *published* |
| The top bar that turns transparent over the desktop, at an opacity measured from the wallpaper | [Transparent Top Bar (Auto)](https://github.com/spencernorton/transparent-top-bar) | NorviTech fork of [Transparent Top Bar](https://github.com/lamarios/gnome-shell-extension-transparent-top-bar), *published* |
| The weather in the top bar and its forecast panel | GEweather | NorviTech fork of [SimpleWeather](https://github.com/romanlefler/SimpleWeather) |
| The clock on the right of the top bar | Move Clock | [Third-party](https://extensions.gnome.org/extension/2/move-clock/), unchanged |
| A system menu that shows only the power button | [Power Only Quick Settings](https://github.com/spencernorton/power-only-quicksettings) | NorviTech, *published* |
| The large clock and weather on the lock screen | [Lock Screen Suite](https://github.com/spencernorton/lock-screen-suite) | NorviTech, *published* |
| Per-monitor wallpapers and rotation | [Wallpaper Suite](https://github.com/spencernorton/wallpaper-suite) | NorviTech, *published* |
| Sticky notes that come back where you left them | [XNote](https://github.com/spencernorton/xnote) and [XNote Placement](https://github.com/spencernorton/xnote-placement) | NorviTech, *published* |

<p align="center">
  <img alt="The dock's app launcher: clicking the first dock button opens a panel with the user's name, a search field and recently used apps; All Apps fills the grid, and typing note narrows it to XNote and Text Editor before the panel closes." src="docs/screenshots/launcher.png" width="900">
</p>

<p align="center">
  <img alt="Making a drawer in the launcher: right-clicking All Apps offers New Drawer, the name Writing is typed into the sidebar, Text Editor and XNote are dragged onto the new Writing drawer, and opening it shows just those two apps." src="docs/screenshots/drawers.png" width="600">
</p>

<p align="center">
  <img alt="Clicking through the named workspaces in the top bar: Home with the Files window and notes, Code with a text editor, Media with an empty music folder, then back to Home. Occupied workspaces are bright, empty ones dim." src="docs/screenshots/workspaces.png" width="900">
</p>

<p align="center">
  <img alt="The weather panel open from the top bar: current conditions, a seven-day forecast and details, on a blurred rounded menu, with its data sources credited." src="docs/screenshots/weather.png" width="445">
  <img alt="The system menu open from the power button: volume, network, power mode, dark style and do not disturb, on the same blurred rounded material." src="docs/screenshots/quick-settings.png" width="445">
</p>

<p align="center">
  <img alt="The NorviOS lock screen: a large clock with seconds, the date, and the current weather over a softened wallpaper." src="docs/screenshots/lock-screen.png" width="700">
</p>

**Sits under the NorviTech desktop apps**, each of which is its own
repository:

| App | What it is |
|---|---|
| [Helios](https://github.com/spencernorton/helios) | A native desktop for coding agents: Claude Code, OpenAI Codex and OpenRouter |
| [XNote](https://github.com/spencernorton/xnote) | Sticky notes that stay on your desktop |
| [XNote Placement](https://github.com/spencernorton/xnote-placement) | A GNOME Shell extension that puts each XNote note back where you left it |
| [SnipSnap](https://github.com/spencernorton/snipsnap) | Screenshot any region of any monitor on GNOME Wayland |


## Install

### Ubuntu 26.04 — the desktop, in three steps

1. Add the NorviTech APT repository. The script checks the archive's signing
   key against its published fingerprint and installs `norvi-archive-keyring`,
   which keeps the repository source and key current from then on:

   ```bash
   curl -fsSL https://apt.norvitech.com/setup.sh | sudo sh
   ```

2. Install NorviOS:

   ```bash
   sudo apt install norvi-os
   ```

   `norvi-os` is a metapackage. It recommends the desktop components and apps —
   XDock, gnome-rounded-blur, Workspace Bar, Transparent Top Bar (Auto), Power
   Only Quick Settings, Lock Screen Suite, Wallpaper Suite, XNote with XNote
   Placement, SnipSnap and Timecrate — and suggests Helios. It pins no
   versions, so each component updates on its own, and you can remove any one
   of them without removing the rest.

3. Install [Blur my Shell](https://github.com/aunetx/blur-my-shell) v73 from
   its upstream release, checked against the release's SHA-256.
   extensions.gnome.org still offers v72 for GNOME 50, and blurred menus need
   v73:

   ```bash
   curl -fsSLo blur-my-shell.zip https://github.com/aunetx/blur-my-shell/releases/download/v73/blur-my-shell%40aunetx.shell-extension.zip
   echo '237a59e04b3cffd3fb86aa3cd18b32f929c61e2af8dcc781379364a59d53b129  blur-my-shell.zip' | sha256sum --check
   gnome-extensions install --force blur-my-shell.zip
   ```

Then log out and back in once, so GNOME Shell sees the new extensions, and
turn them on:

```bash
for uuid in blur-my-shell@aunetx xdock@spencercnorton.github.io \
    workspace-bar@spencercnorton.github.io transparent-top-bar@spencercnorton.github.io \
    power-only-quicksettings@spencercnorton.github.io lock-screen-suite@spencercnorton.github.io \
    wallpaper-suite@spencercnorton.github.io xnote-placement@spencercnorton.github.io; do
  gnome-extensions enable "$uuid"
done
```

### The boot splash, login screen and window glass — from source

The branding and the glass are not packaged yet. Install them from this
repository:

```bash
git clone https://github.com/spencernorton/norvi-os.git
cd norvi-os
sudo ./install.sh              # boot splash, login screen and About logo, from the next boot
./desktop/install-desktop.sh   # window glass for your user; no sudo
```

`install.sh` takes about a minute, most of it rebuilding the initramfs.
Nothing restarts; the boot splash and the login screen change from the next
boot, and Settings shows the new logo the next time it opens.

The glass needs Blur my Shell installed and enabled first (step 3 above).
Without it the desktop installer stops and says so, rather than leaving
translucent windows over a sharp wallpaper. Run it from a terminal inside your
desktop session: it asks GNOME Shell whether Blur my Shell is running.
`./desktop/install-desktop.sh --stylesheet-only` installs the stylesheet on
its own if that is what you want.

To remove everything:

```bash
sudo ./uninstall.sh
./desktop/install-desktop.sh --uninstall
sudo apt remove norvi-os       # then sudo apt autoremove takes the components it pulled in
```

NorviOS has only been tested on Ubuntu 26.04 LTS with GNOME 50 on Wayland.

## Documentation

- [Deployment and operations guide](docs/OPERATIONS.md) — setup, configuration, verification, upgrades, recovery and troubleshooting.
- [Releasing](docs/RELEASING.md) — public builds, release checks and private deployment boundaries.

- [How it works](docs/how-it-works.md) — the override point behind each
  surface, why each one survives an Ubuntu update, and the measurements behind
  the glass
- [NOTICE](NOTICE) — what the GPL covers, and the separate terms for the
  NorviTech artwork
- [CHANGELOG.md](CHANGELOG.md) — one entry per release

## Where your data lives

| Path | Purpose |
|---|---|
| `/usr/share/plymouth/themes/norvitech/` | The boot splash theme, registered with `update-alternatives` |
| `/etc/gdm3/greeter.dconf-defaults` | One `logo=` line pointing the login screen at the NorviTech mark |
| `/usr/share/pixmaps/ubuntu-logo-text.svg` and `ubuntu-logo-text-dark.svg` | Replaced through local `dpkg` diversions; Ubuntu's files are kept beside them as `*.stock-norvi` |
| `/usr/local/share/norvitech/` | The logo files and an install timestamp |
| `/boot/initrd.img-*` | Rebuilt so that the splash is inside the initramfs |
| `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` | The glass stylesheet; one you already had is kept as `gtk.css.pre-norvi` and restored on uninstall |
| Blur my Shell's settings | Application blur on at full window opacity, for every window except the desktop icons and two Chromium browsers |
| `~/.local/state/norvi-os/` | What the desktop installer changed, so that `--uninstall` undoes exactly that |

Nothing leaves the machine: neither installer uses the network.

## Contributing and support

- Bugs and feature requests: [open an issue](https://github.com/spencernorton/norvi-os/issues/new/choose). Questions: [Discussions](https://github.com/spencernorton/norvi-os/discussions).
- Security reports: [private vulnerability reporting](https://github.com/spencernorton/norvi-os/security/advisories/new) — see [SECURITY.md](SECURITY.md). There is no e-mail address; that is deliberate.
- Pull requests are welcome; read [CONTRIBUTING.md](CONTRIBUTING.md) first — changes are reviewed and merged on GitHub, then shipped in tagged releases.
- If NorviOS saves you time, you can [support its development](https://buy.stripe.com/8x26oH2U44f65TRe574wM04).

## Development

```bash
python3 desktop/check_contrast.py              # what CI runs: the glass keeps text above WCAG AA
python3 desktop/check_gtk_css.py               # both stylesheets parse with the real GTK 3 and GTK 4
bash desktop/test-gtk-css-check.sh
bash desktop/test-blacklist-merge.sh
bash desktop/test-uninstall-restore.sh
bash desktop/test-install-desktop.sh           # the real installer, end to end, in a scratch HOME
shellcheck -S warning install.sh uninstall.sh desktop/*.sh scripts/build.sh
scripts/build.sh                               # the norvi-os .deb into dist/; needs debhelper and dpkg-dev
```

The installers change boot and login configuration, so they are run on a
clean Ubuntu 26.04 virtual machine before a release rather than in CI. The
screenshots above come from that machine.

## Licence

[GPL-3.0-or-later](LICENSE) © Spencer Norton

The NorviTech artwork — the logo files under `assets/` and `gdm/`, and
`plymouth/watermark.png` — is not under the GPL. [NOTICE](NOTICE) sets its
terms, which do not allow modifying it or using it to brand another product.

---

<p align="center">
  <a href="https://norvitech.com"><img alt="Part of the NorviTech Suite — open-source apps for the Linux desktop and the self-hosted stack" src="https://norvitech.com/assets/banner.svg" width="640"></a>
</p>

<p align="center">
  <a href="https://github.com/spencernorton/helios">Helios</a> ·
  <a href="https://github.com/spencernorton/bitagent">BitAgent</a> ·
  <a href="https://github.com/spencernorton/xnote">XNote</a> ·
  <a href="https://github.com/spencernorton/xnote-placement">XNote Placement</a> ·
  <a href="https://github.com/spencernorton/snipsnap">SnipSnap</a> ·
  <a href="https://github.com/spencernorton/conductor">Conductor</a> ·
  <a href="https://github.com/spencernorton/norvi-os">NorviOS</a> ·
  <a href="https://github.com/spencernorton/indigo">Indigo</a> ·
  <a href="https://github.com/spencernorton/roadtrack">Road Track</a> ·
  <a href="https://norvitech.com">norvitech.com</a>
</p>
