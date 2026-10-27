# How NorviOS works

NorviOS changes four things on a stock Ubuntu 26.04 desktop: the boot splash,
the login screen, the logo in Settings → About, and the way GTK windows paint.
Each one goes through an override point that Ubuntu or Debian already provides,
so no Ubuntu-owned file is edited in place, package upgrades keep working, and
`uninstall.sh` returns the stock look.

## The three branded surfaces

`sudo ./install.sh` handles these. It is idempotent and takes about a minute,
most of it rebuilding the initramfs.

| Surface | Mechanism | Why an update cannot break it |
|---|---|---|
| Boot splash | Its own Plymouth theme at `/usr/share/plymouth/themes/norvitech`, registered with `update-alternatives` at priority 200 (Ubuntu's `bgrt` theme is 110) | No Ubuntu file is modified. Alternatives survive upgrades, and the worst case is Plymouth falling back to the stock theme. |
| Login and lock screen (GDM) | The `logo=` key in `/etc/gdm3/greeter.dconf-defaults`, a ucf-managed conffile. The edit is staged, validated with `dconf compile`, moved into place atomically, then compiled by `/usr/share/gdm/generate-config`, the same command `gdm3.service` runs at every start | This is Debian's own greeter-customisation path, and local conffile edits survive `gdm3` upgrades. A malformed edit can never reach the live greeter: the installer aborts first and leaves the greeter untouched. |
| Settings → About | `dpkg-divert --no-rename` on `/usr/share/pixmaps/ubuntu-logo-text.svg` and `ubuntu-logo-text-dark.svg`, the two `base-files` pixmaps GNOME Settings loads by fixed path | GTK4 draws these as a picture, with no icon-theme fallback, so a diversion is the only override that works. `--no-rename` rather than `--rename`, because `base-files` is Essential: dpkg only redirects its future writes and never moves our file. The installer keeps its own copy of the stock files for a clean revert. |

### Boot splash details

- The spinner animation frames are **copied**, not symlinked, into the theme
  directory. The initramfs receives only the theme's own directory, so a
  symlink into `../spinner` would dangle inside it. Re-running `install.sh`
  re-syncs them after a Plymouth upgrade; they almost never change.
- A fresh Ubuntu 26.04 install builds its initramfs with dracut, and a
  machine upgraded from an earlier release may still use initramfs-tools.
  `install.sh` goes through `update-initramfs`, which both provide, and has
  been run on a fresh install.
- The firmware (BGRT) logo is dropped on purpose. Boot is a black screen with
  the NorviTech mark and Ubuntu's own spinner.
- `install.sh` rebuilds the initramfs for every installed kernel (`-k all`),
  then checks that the newest one actually contains the watermark and says so
  if it does not.
- The splash can only appear as early as there is a framebuffer. With
  `efifb` or `simpledrm` that is from the first moments of boot. On a machine
  that has neither, such as an NVIDIA card whose driver loads late, the theme
  still applies but becomes visible only once the GPU driver loads. Ubuntu's
  `framebuffer-nvidia` initramfs hook, with `nvidia_drm modeset=1 fbdev=1`,
  brings kernel modesetting up inside the initramfs and closes that gap. The
  timing is cosmetic; nothing fails either way.
- The watermark is 256 px so it stays legible on 4K panels.
- The in-session lock shield (the clock screen) has no logo slot by GNOME's
  design. The branded surface is the GDM greeter you unlock and log in
  through.

### The logo variants

The vector master was traced with potrace from a hand-drawn original. Each
variant ships as a scalable SVG plus a 380 px PNG, and each surface gets the
variant that contrasts with its real background.

| Variant | Fill | Used for |
|---|---|---|
| `norvitech-logo-color` | `#FD8024` | Boot splash watermark, on pure black |
| `norvitech-logo-light` | `#FFFFFF` | GDM greeter logo (dark background); Settings → About in dark mode |
| `norvitech-logo-dark` | `#2D2D2D` | Settings → About in light mode |

![The three logo variants side by side: orange on black, white on dark grey, and dark grey on white.](../assets/preview-variants.png)

The sized artefacts are `plymouth/watermark.png` (256 px, colour) and
`gdm/norvitech-gdm-logo.svg` (light, an SVG so GDM renders it crisply at any
display scale).

## Window glass

`./desktop/install-desktop.sh` is per-user: it writes to `~/.config` and your
own dconf settings, and it refuses to run under `sudo`. It has two halves that
only work together.

| Half | What | Where |
|---|---|---|
| The window stops painting | `window.background` at alpha **0.72**, so any region an app does not fill itself shows through | `desktop/gtk3.css` and `desktop/gtk4.css`, installed as `~/.config/gtk-3.0/gtk.css` and `~/.config/gtk-4.0/gtk.css` |
| Something blurs behind it | [Blur my Shell](https://extensions.gnome.org/extension/3193/blur-my-shell/)'s **Applications** blur: `blur` on, `opacity` 255, `enable-all` on, `dynamic-opacity` off | Blur my Shell's dconf settings |

Transparency alone is not glass. GTK has no `backdrop-filter`, and Mutter does
not expose backdrop blur to client windows, so without the compositor half the
result is a translucent window over a sharp wallpaper. That is why the
installer refuses to install the stylesheet alone unless you pass
`--stylesheet-only`. Blur my Shell ships with application blur **off**, so the
installer turns it on; without that step a fresh machine gets exactly the
translucent-but-sharp result. `opacity` 255 keeps the window itself fully
opaque, because Blur my Shell's default of 215 fades the whole window, text
included; the stylesheet alone decides what shows through. `dynamic-opacity`
is the subtle one: Blur my Shell's default hides the blur on the **focused**
window, so the person evaluating the effect is the one person who cannot see
it.

**One file owns the numbers.** `desktop/glass-tokens.json` holds the
window alpha, the menu plate, the blur strength, and the corners.
`desktop/check_glass_tokens.py` runs in CI and in the desktop installer
and refuses stylesheets that drift from it. Blur itself has one owner per
surface: Blur my Shell for windows and menus, the wallpaper blur for the
top bar, and each app only decides whether its own surfaces paint.

**What turns to glass is decided by the apps, not by a list.** A surface shows
through exactly when its author chose not to paint it. In practice header bars
and page backgrounds go glass, while `.view` surfaces (text, lists, canvases)
paint `@view_bg_color` and stay opaque, so text never sits over a moving
desktop.

**The focus cue is the sidebar.** A window's navigation column is solid while
the window has focus and glass when it does not: an active and inactive
signal that never grows an opaque bar across the top.

**GTK3 needs two declarations GTK4 does not**, both measured on Nemo:

- GTK3 does **not** draw the window background under the title bar, so with
  only the window rule the title bar went fully transparent and its text and
  buttons became illegible. The title bar carries the alpha itself.
- Menu bars and tool bars **do** paint their own fill in Yaru, so they are
  cleared to `transparent` rather than given 0.72 of their own, because 0.72
  over 0.72 composites to 92% and bands. Alpha is set on exactly one node per
  region.

**Scope is GTK3 and GTK4 apps.** Electron, Chrome, Steam, Qt and Java apps draw
opaque backgrounds by construction and do not use GTK for their windows.
Blur my Shell still attaches a blur under them, which costs a little GPU and
shows nothing, so the installer adds the two Chromium browsers to Blur my
Shell's blacklist. It also blacklists `gjs`, the window class of the Desktop
Icons extension's desktop: with `enable-all` on, blurring that window blurs
the wallpaper itself. The cost is that other `gjs` windows, such as extension
preference dialogs, lose their blur. Blur my Shell matches on window class
only, so there is no finer key.

**Chromium samples GTK colours; it does not render with GTK.** For bubble
menus and dialogs it reads a background colour from a GTK window it never
shows, and paints it as if it were opaque. An unscoped glass rule handed it a
translucent colour and its menus went see-through. The glass rule is
therefore scoped to `window.background.csd`: GTK adds `csd` to a window when it
is realised, so every real window matches and Chromium's sampling window does
not. A running browser keeps the colours it sampled at start-up until it is
restarted.

**GTK4 re-reads the stylesheet live; GTK3 never does.** Dropping the alpha on
disk left a running GTK3 file manager at exactly its previous value. Worse, a
single-instance app re-focuses the stale process when you click its launcher,
so the change never appears until the process exits. The installer lists the
running GTK3 processes for that reason, and never kills them: one of them may
be somebody's unsaved document.

**Glass needs something behind it.** At 0.72 over a *dark* backdrop the window
chrome reads almost exactly as it would opaque. The effect shows over a
wallpaper or a bright page, not over a dark terminal.

**Both toolkits read exactly one stylesheet, and it is the per-user one.**
Traced with `strace` on running GTK3 and GTK4 processes, only
`$XDG_CONFIG_HOME/gtk-{3,4}.0/gtk.css` is ever opened. `settings.ini` has a
system search path; `gtk.css` does not. That is why this half is per-user.

### Accessibility is the reason for 0.72

The alpha is the one number that can silently break accessibility: lower it and
text starts floating over the desktop. `desktop/check_contrast.py` computes the
worst-case WCAG contrast of primary text for both toolkits, both colour schemes
and three backdrops (black, mid grey, white), asserts that it clears the AA
threshold of 4.5:1, and reports the floor. At 0.72 the worst case is 5.24:1
(GTK3, light scheme, over black); the floor is **0.67**. The installer runs
the check first and refuses to install a failing alpha.

### Undoing it

`./desktop/install-desktop.sh --uninstall` puts back exactly what was there
before the first install, and nothing more:

- A stylesheet you already had is kept as `gtk.css.pre-norvi` and restored.
  If there was none, a marker file records that, so uninstall removes only the
  file it installed. A second uninstall, or a retry after a failure, never
  deletes a stylesheet it did not install.
- Blur my Shell's four application keys — `blur`, `opacity`, `enable-all`
  and `dynamic-opacity` — are recorded before the first change and restored to
  those values, not to a guessed default.
- Blacklist entries are added to your list, never assigned over it, and
  uninstall removes only the entries it added. An entry that was already
  there is not recorded, so uninstall will not take it away.

`desktop/test-blacklist-merge.sh` and `desktop/test-uninstall-restore.sh` pin
those rules against a stubbed `gsettings` and a scratch directory.
