/* SPDX-License-Identifier: GPL-3.0-or-later
 * GNOME Shell links the SONAMEs at startup, then GObject Introspection also
 * opens files by absolute name. Both lookups must reach one object. glibc's
 * documented rtld-audit object-search hook can cover both before mapping.
 * No symbol binding or per-call tracing is requested.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <link.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define PRIVATE "/usr/lib/x86_64-linux-gnu/norvi-window-glass/"
#define MUTTER "libmutter-18.so.0"
#define CLUTTER "libmutter-clutter-18.so.0"
#define MUTTER_PATH "/lib/x86_64-linux-gnu/" MUTTER
#define CLUTTER_PATH "/lib/x86_64-linux-gnu/mutter-18/" CLUTTER

static char mutter_fd[40], clutter_fd[40];
/* All assignments passed by the selector are ordinary glibc-owned initial
 * environment strings. Also erase the original bytes exposed by procfs. */
static void
remove_assignment (const char *name)
{
    char *value = getenv (name);
    if (value) {
        char *assignment = value - strlen (name) - 1;
        size_t length = strlen (assignment);
        unsetenv (name);
        explicit_bzero (assignment, length);
    }
}

unsigned int
la_version (unsigned int supported)
{
    const char executable[] = "/usr/bin/gnome-shell";
    char path[sizeof executable];
    int mutter, clutter;

    char expected_pid[32];
    const char *audit = getenv ("LD_AUDIT");
    const char *pid = getenv ("NORVI_WINDOW_GLASS_LAUNCH_PID");
    int selected;
    if (!audit || strcmp (audit, PRIVATE "loader-audit.so") != 0)
        return 0;

    snprintf (expected_pid, sizeof expected_pid, "%ld", (long) getpid ());
    selected = pid && strcmp (pid, expected_pid) == 0;
    remove_assignment ("LD_AUDIT");
    remove_assignment ("NORVI_WINDOW_GLASS_LAUNCH_PID");
    if (!selected || supported < LAV_CURRENT ||
        readlink ("/proc/self/exe", path, sizeof path) != sizeof executable - 1 ||
        memcmp (path, executable, sizeof executable - 1) != 0)
        return 0;

    /* Pin both files together across package removal/rename. Future children
     * drop the descriptors at exec; later GI opens reuse the same paths. */
    mutter = open (PRIVATE MUTTER, O_RDONLY | O_CLOEXEC);
    clutter = open (PRIVATE CLUTTER, O_RDONLY | O_CLOEXEC);
    if (mutter == -1 || clutter == -1) {
        if (mutter != -1) close (mutter);
        if (clutter != -1) close (clutter);
        return 0;
    }
    snprintf (mutter_fd, sizeof mutter_fd, "/proc/self/fd/%d", mutter);
    snprintf (clutter_fd, sizeof clutter_fd, "/proc/self/fd/%d", clutter);
    return LAV_CURRENT;
}

char *
la_objsearch (const char *name, uintptr_t *cookie, unsigned int flag)
{
    (void) cookie;
    if (flag == LA_SER_ORIG) {
        if (strcmp (name, MUTTER) == 0 || strcmp (name, MUTTER_PATH) == 0 ||
            strcmp (name, "/usr" MUTTER_PATH) == 0 || strcmp (name, MUTTER_PATH ".0.0") == 0 ||
            strcmp (name, "/usr" MUTTER_PATH ".0.0") == 0)
            return mutter_fd;
        if (strcmp (name, CLUTTER) == 0 || strcmp (name, CLUTTER_PATH) == 0 ||
            strcmp (name, "/usr" CLUTTER_PATH) == 0 || strcmp (name, CLUTTER_PATH ".0.0") == 0 ||
            strcmp (name, "/usr" CLUTTER_PATH ".0.0") == 0)
            return clutter_fd;
    }
    return (char *) name;
}
