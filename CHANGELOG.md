# Changelog

All notable changes to NorviOS are documented here.

## Unreleased

- `desktop/glass-tokens.json` now owns the glass numbers (window alpha,
  menu plate, blur strength, corners). A new gate,
  `desktop/check_glass_tokens.py`, runs in CI and in the desktop installer
  and refuses stylesheets that drift from the tokens.

## 1.4.1 — 2026-10-29

- The desktop installer finds Blur my Shell under `XDG_DATA_HOME`.
- CI installs its exact package in a clean Ubuntu VM, loads and exercises the
  packaged desktop, verifies both installers and rollback, and runs piuparts.
- Document the signed candidate channel currently carrying NorviOS.
- Pin the verified upstream Blur my Shell v76 release, which fixes repeated
  application-blur cleanup after settings changes.

## 1.4.0 — 2026-10-04

- New `norvi-os` Debian package, a metapackage in the NorviTech APT
  repository. It depends on `norvi-archive-keyring` and recommends the
  desktop components and apps: gnome-rounded-blur, Lock Screen Suite, Power
  Only Quick Settings, Transparent Top Bar (Auto), Workspace Bar, XDock,
  Wallpaper Suite, XNote, XNote Placement, SnipSnap and the Timecrate app. It
  suggests Helios. No version is pinned, so each component updates on its own
  and any one of them can be removed without removing the rest.
- The install is three steps: run the repository's `setup.sh`,
  `sudo apt install norvi-os`, and install Blur my Shell v73 from its upstream
  release, checked against the release's SHA-256. The branding and the window
  glass still install from source with `install.sh` and
  `desktop/install-desktop.sh`.
- Each release now carries the `.deb` beside the source archive and the
  checksums. CI builds the package twice and compares the bytes.

## 1.3.7 — 2026-09-30

Fixes from a clean-machine run of 1.3.6 on a fresh Ubuntu 26.04 desktop:

- `install-desktop.sh --uninstall` no longer stops with exit status 1 before
  finishing when there is no Blur my Shell record to restore: a second
  uninstall, or one after a `--stylesheet-only` install.
- The desktop installer now refuses when Blur my Shell is installed but not
  running, as the README says. It used to go ahead and leave translucent
  windows over a sharp wallpaper.
- GTK3 right-click menus, the desktop's included, keep their rounded corners.
  The window-glass rule also matched a menu's own toplevel window and painted a
  square glass plate behind it.
- A window's sidebar turns to glass again when the window loses focus.
  libadwaita 1.9 paints the sidebar on a node the stylesheet did not cover,
  so it stayed solid.
- The desktop installer leaves the permissions of an existing
  `~/.config/gtk-3.0` alone, and its marker file is no longer executable.
- `install.sh` checks the initramfs with dracut's `lsinitrd` when
  `lsinitramfs` is not installed. It used to print a false "watermark not
  found" warning.

Checks:

- CI parses both stylesheets with the real GTK 3 and GTK 4 parsers. A broken
  rule does not stop an app; GTK skips it silently. The check proves it fails
  on a broken rule in either file, and CI now runs on the supported Ubuntu
  26.04.
- The contrast check covers the right-click menus too. They are one dark
  plate in light and dark style with no blur behind it, so its alpha alone
  keeps the labels readable over a white wallpaper.

Documentation:

- The README links each desktop extension that now has its own public
  repository and release: XDock, gnome-rounded-blur, Workspace Bar,
  Transparent Top Bar (Auto), Power Only Quick Settings, Lock Screen Suite and
  Wallpaper Suite. Blur my Shell is the upstream release, and Workspace Bar
  replaces Space Bar.

## 1.3.6 — 2026-09-27

- Establish GitHub pull requests as the development workflow, with privacy checks.
- Add deployment, configuration, security, upgrade and recovery documentation.

## 1.3.5 — 2026-09-23

- The suite links at the foot of the README point to Indigo, the new name of
  Swiss UI.

## 1.3.4 — 2026-09-23

- The README shows how to make a drawer in the launcher: right-click, New
  Drawer, name it, drag apps onto it.

## 1.3.3 — 2026-09-23

- The README shows XDock's app launcher — opening it from the dock, All Apps,
  and search — which the earlier screenshots left out.

## 1.3.2 — 2026-09-23

- The workspace-switching animation shows the same glass Files window on
  every workspace. Its Media workspace had opened an empty folder, and GNOME's
  "Folder is Empty" page paints its own opaque background, so it looked like a
  different theme.

## 1.3.1 — 2026-09-22

- The screenshots now show the whole NorviOS desktop — XDock, the Space Bar
  workspaces, Transparent Top Bar, GEweather, the lock screen and the
  power-only system menu — instead of a stock Ubuntu desktop with this
  repository's branding on it. All were captured on a fresh Ubuntu 26.04
  virtual machine with nothing personal in them.
- The README names every extension on screen, says which are forks and of
  what, and says plainly that they are not published yet.
- No installer or stylesheet changed.

## 1.3.0 — 2026-09-22

- First public release, on GitHub, under the name NorviOS.
- The window glass now works on a fresh machine. Blur my Shell ships with
  application blur off, so the desktop installer turns it on, and sets the
  window opacity to 255 so that the stylesheet alone decides what is
  translucent and text stays fully opaque. Both values are recorded first and
  restored on `--uninstall`. Earlier releases relied on blur already being on.
- Upgrading keeps `--uninstall` exact: a record written by an earlier release
  gains the two new keys at the values they hold before this release changes
  them, and the record is rewritten in one rename.
- The desktop installer also finds a Blur my Shell installed system-wide, not
  only one under your home directory.
- The list of running GTK3 processes printed after an install now says that
  background services in it have no window and can be ignored.
- Verified end to end on a clean Ubuntu 26.04 virtual machine: boot splash,
  login screen, About logo, glass, and both uninstallers.
- Licence and provenance: GPL-3.0-or-later for the code, with the NorviTech
  artwork under its own terms in `NOTICE`.
- Community files, issue forms, a GitHub CI workflow (contrast check,
  installer tests, shellcheck), and the design notes moved from the README to
  `docs/how-it-works.md`.

## 1.2.1 — 2026-08-23

- Scope the window-glass rule to `window.background.csd`, so Chromium-based
  browsers stop sampling the translucent colour for their menus and dialogs.

## 1.2.0 — 2026-08-22

`1.1.0` and `1.2.0` name the same tree.

- Window glass: per-user GTK3 and GTK4 stylesheets at alpha 0.72, with Blur
  my Shell's application blur behind them, and a WCAG contrast check that
  refuses an alpha that would make text unreadable.
- A window's sidebar is solid while it has focus and glass when it does not;
  there is no opaque bar across the top.
- Nemo's navigation column is sized for reading, its split title bar paints as
  one column, and stray borders are cleared.
- Blur my Shell's blacklist is added to, never overwritten, and the desktop
  icons window is kept out of the blur so the wallpaper stays sharp.
- `--uninstall` restores the Blur my Shell settings it changed, never deletes
  a stylesheet it did not install, and `--stylesheet-only` leaves Blur my
  Shell untouched.

## 1.0.3 — 2026-07-21

- Boot splash: centre the logo and move the spinner to the bottom, ending an
  overlap on low-resolution framebuffers.

## 1.0.2 — 2026-07-20

- A 256 px boot watermark, legible on 4K panels.

## 1.0.1 — 2026-07-20

- Divert the About panel's logo files with `dpkg-divert --no-rename`, because
  the package that owns them is Essential.

## 1.0.0 — 2026-07-20

- Branding for Ubuntu 26.04: the boot splash (Plymouth), the login screen
  (GDM) and the logo in Settings → About.
