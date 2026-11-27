# Native glass support for Ubuntu GNOME Shell

This component adds optional damage bounds and effect-list notifications for the Ubuntu 26.04 amd64 desktop. A compatible GNOME Shell can tell when a background change reaches a glass pane. The extension can use Ubuntu's normal repaint notifications on other builds.

## Build

Restore the exact upstream inputs before building. A release includes both `source.tar.gz` and `upstream-source.tar.gz`. From the extracted source root, restore the supplement with `python3 -I desktop/window-glass/source-inputs.py unpack /path/to/upstream-source.tar.gz`. A fresh Git checkout can instead run `python3 -I desktop/window-glass/source-inputs.py fetch`. The digest checks use `desktop/window-glass/source-inputs.lock.json`.

Install the top-level package build tools and the build dependencies in an amd64 Ubuntu 26.04 builder. Run the following commands from the repository root.

```sh
apt-get update
apt-get -y --no-install-recommends --build-profiles=nocheck build-dep \
    ./desktop/window-glass/native/upstream/mutter_50.1-0ubuntu2.5.dsc
desktop/window-glass/native/build "$DESTDIR"
```

The build checks the hashes in `sources.sha256`, unpacks Ubuntu's source, applies `surface-damage.patch`, and runs Ubuntu's binary build offline. Only the private library pair, startup selector, generator, loader and license information enter the package staging directory. The top-level build should run `python3 -I desktop/window-glass/native/install-overlay.py "$DESTDIR"` after Debian's final stripping step. This records hashes of the exact installed payload.

The verified source supplement contains Ubuntu's original tarball, Debian packaging tarball, source descriptor and the original Blur my Shell v76 commit archive. The release's project-source archive contains this patch, loader, build scripts and the readable input lock. Taken together they supply the complete corresponding source for the package. Keep both archives available alongside the binaries. Ubuntu's licensing notices are installed under `/usr/share/doc/norvi-window-glass/mutter-copyright.gz`.

## Activation

The systemd user generator recognizes Ubuntu's verified GNOME Shell unit and emits a drop-in for `org.gnome.Shell@ubuntu.service`. At each start a compatibility check reads the OS identity, installed Mutter and GNOME Shell package versions, the hashes of the installed binary interfaces and the hashes of both private libraries and the loader. It also honors a user's existing loader settings or a `~/.config/norvi-window-glass/disable-native` file. The unit runs Ubuntu's ordinary `/usr/bin/gnome-shell` in every case. Removing the opt-out file restores automatic selection at the next eligible Shell start.

An eligible launch uses glibc's object-search audit hook for the two known Mutter SONAMEs and their Ubuntu paths. GNOME's dynamic linker and GObject Introspection then reach the same library objects. The hook checks the Shell executable and a one-use PID marker, clears the two selector variables, and pins both files with close-on-exec descriptors. Child applications load system libraries. The hook subscribes only to library searches. No polling or per-frame callback runs in the loader. [Linux dynamic-linker auditing](https://man7.org/linux/man-pages/man7/rtld-audit.7.html)

A newer Ubuntu package, an unrecognized OS, a changed system library, an incomplete payload or an unavailable compatibility helper gives the next Shell Ubuntu's stock libraries. A changed vendor unit keeps its vendor command. The GNOME Shell already running continues to use its mapped objects until it exits. A package install or removal can reload user unit declarations without restarting the desktop. [systemd generators](https://www.freedesktop.org/software/systemd/man/latest/systemd.generator.html)

## Test a staged package

On an amd64 Ubuntu host with matching GNOME Shell, bubblewrap, dbus-daemon and Mesa software rendering, extract the package to a temporary directory and supply the two original Ubuntu packages to the fixture.

```sh
dpkg-deb -x "$GLASS_DEB" "$STAGE"
python3 -I desktop/window-glass/native/tests/run-linux.py "$STAGE" \
    "$UBUNTU_MUTTER_DEB" "$UBUNTU_GIR_DEB"
```

Each case starts GNOME Shell with a virtual monitor, a private Wayland session and a new home. An extension queries both GObject signals and launches a child that opens Mutter. The fixture checks the shell executable, mapped objects and child environment. The fallback cases cover a simulated newer Ubuntu revision, user opt-out, a modified stock library, missing files, an empty manifest, another OS release, a changed Ubuntu unit and a new vendor-provided Ubuntu instance service.
