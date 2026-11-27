# NorviOS deployment and operations

NorviOS is a reversible branding and glass-style layer for Ubuntu, rather
than a separate distribution. The screenshots show a wider desktop suite;
the `norvi-os` package installs most of the extensions pictured (the README's
table says which are published), and this repository's installers add the
branding and per-user GTK styling. The desktop package supplies the window-glass engine.

## Supported environment

The supported baseline is Ubuntu 26.04 LTS, GNOME 50 and a Wayland desktop.
Have a working backup, a normal user account, sudo access and enough free
space in `/boot` for initramfs regeneration. Test organizational desktop
policies in a virtual machine before rolling them out to workstations.

```bash
cat /etc/os-release
gnome-shell --version
df -h /boot
```

## Install and configure

The desktop components and apps install from the NorviTech APT repository,
through APT:

```bash
curl -fsSL https://apt.norvitech.com/setup.sh | sudo sh   # checks the key fingerprint, installs norvi-archive-keyring
sudo apt install norvi-os                                  # the metapackage: components and apps as Recommends

```

The stable archive includes the metapackage and most of its components.
For XDock, Wallpaper Suite and Timecrate, follow the [full desktop
install instructions](../README.md#install) to use the signed candidate channel.

`norvi-os` pins no versions: each component updates on its own through apt
and unattended-upgrades, and any one of them can be removed without removing
the metapackage. Desktop releases from 1.5.0 include the v76 extension in `norvi-window-glass`. Sign out and back in, then enable the extension as described in the README. A recognized per-user v76 installation follows packaged updates. Custom extensions and disabled settings retain their existing behavior.

The branding and the window glass install from this repository:

```bash
git clone https://github.com/spencernorton/norvi-os.git
cd norvi-os
# For reproducibility, check out a reviewed version tag before installation.
sudo ./install.sh
./desktop/install-desktop.sh
```

The first command installs Plymouth, the greeter logo and About-panel logos.
It updates boot files and needs sudo. The desktop command changes only your
user's GTK styles and blur settings; run it without sudo.

Enable Blur my Shell first. Without it the desktop installer refuses to make
windows translucent. `--stylesheet-only` is an explicit alternative when you
manage blur separately.

![NorviOS with a demo account and synthetic notes](screenshots/desktop.png)

## Verify each surface

1. Read the installers' final checks and keep the output privately.
2. Reopen Settings → About and inspect both light and dark appearance.
3. Open Files and a text editor; confirm labels are legible over your wallpaper.
4. On the next planned reboot, check the splash and login logo.
5. Verify launcher, workspace and weather extensions separately if you installed
   them. Those components have their own compatibility and configuration.

![The launcher and search workflow](screenshots/launcher.png)

## Configuration and ownership

| Surface | Configuration owner |
|---|---|
| Boot splash | Plymouth alternative and generated initramfs |
| Greeter logo | Debian's greeter customization conffile |
| About logos | Local package diversions, preserving original files |
| GTK glass | Per-user GTK3 and GTK4 stylesheets |
| Background blur | The user's Blur my Shell settings |
| Reversal record | `~/.local/state/norvi-os/` |

Keep the reversal record and the saved pre-install stylesheets. They tell the
uninstaller what was yours before installation. Do not delete them as cache.
The installers themselves do not access the network.

## Rollback and upgrades

```bash
sudo ./uninstall.sh
./desktop/install-desktop.sh --uninstall
```

These restore the original branding and the user's recorded desktop settings.
`sudo apt remove norvi-os` removes the metapackage; `sudo apt autoremove` then
removes the components it pulled in.
Check About, GTK styles and the next boot again after rollback. Before a major
Ubuntu or GNOME upgrade, verify compatibility in a fresh VM. Do not assume an
extension for one Shell major version works on another.

## Troubleshooting

| Symptom | Check and next action |
|---|---|
| Installer refuses the desktop | Check Ubuntu/GNOME versions, that Blur my Shell is installed and enabled (`gnome-extensions info blur-my-shell@aunetx` shows `State: ACTIVE`), and that you ran it from inside the desktop session. |
| Background is translucent but sharp | Confirm blur is enabled; inspect extension compatibility. |
| Boot branding looks unchanged | Check installer output and reboot into the regenerated kernel image. |
| User stylesheet already existed | Preserve the pre-install copy; use the uninstall path to restore it. |
| Empty folder looks opaque | Some GTK status pages remain opaque; this is a known styling boundary. |

Use a demo account for public reports. Remove usernames, wallpaper metadata,
window titles and real notes from screenshots. See [how it works](how-it-works.md)
for the exact override points and contrast checks.

## Window glass upgrades

On an existing amd64 desktop, use `sudo apt update` followed by `sudo apt upgrade` once the new release appears in its configured channel. This allows APT to add the new glass recommendation while upgrading the desktop.

The extension reuses cached application backdrops on a matching Ubuntu 26.04 Wayland compositor. Custom effects and fractional blur radii use their original v76 pipelines. The native component checks the installed Ubuntu packages and library hashes at login. A newer Ubuntu update starts the standard compositor until a corresponding glass build is available.

To return to the standard compositor while keeping window glass, create `~/.config/norvi-window-glass/disable-native` and sign in again. Remove the file and start a new session to select the compatible native component again. To remove the packaged extension, use `sudo apt remove norvi-window-glass`. An existing supported per-user v76 installation resumes its upstream entry points. To restore those entry points immediately before removal, run `/usr/libexec/norvi-window-glass/prepare-extension --restore` in the desktop user account.
