# Waynergy command callbacks

Waynergy normally installs SIGCHLD with SA_NOCLDWAIT. Wrap synchronous system()
callbacks with sigWaitSIGCHLD(true) and sigWaitSIGCHLD(false), as clipHaveWlClipboard
already does. Otherwise a successful command can report ECHILD (-1).
Verify CSEC on/off and reconnect through the real Waynergy process and the
compositor lock status. Child stdout in the user journal may lack the parent
systemd InvocationID, so use a parent-process log for callback acceptance.

# Packaged-source checks

Upstream `test/run.sh` prints failures without propagating their exit status.
After building, use `bash packaging/waynergy-custom/verify-fork.sh SOURCE_DIR`:
it checks the packaged protocol/callbacks and runs each upstream test directly.
Run `packaging/waynergy-custom/verify-debounce.sh SOURCE_DIR` for wheel regressions.
These source tests do not replace native lock acceptance after deployment.

Upstream `src/uSynergy.c` retains mixed CRLF/LF lines. Preserve them when
importing source; use the public fork's `whitespace=cr-at-eol` attribute or
`git -c core.whitespace=cr-at-eol diff --check` to check that source correctly.

For public snapshots, compare the public Git index against every tracked
integration path, not only files on disk. Upstream's `*.d` ignore rule hides
`config.ini.d`; the public root must explicitly allow `lock-sync.ini`,
`cursor-sync.ini`, `macos-function-keys.ini`, and `media-keys.ini` so the
optional installers remain complete.

# Deskflow macOS media keys

Map media keys through `[id-keymap]`, not the raw macOS scancode table:
Deskflow's native media events can share raw button zero. The volume/mute
snippet and scoped installer preserve normal keyboard mapping. Verify the
live server-to-client path with physical keys and the resulting audio state;
XKB symbol checks alone do not prove capture or compositor binding execution.

# Extended function-key symbols

Linux XKB `inet(evdev)` maps F16-F18 to launch actions and F20 to microphone
mute by default. For this Waynergy/Hyprland setup, preserve existing keyboard
options and add `fkeys:basic_13-24` only to `hl-virtual-keyboard-waynergy`.
Verify the device's effective options and resulting symbols; raw keycodes
194-198 alone are not evidence that applications receive F16-F20.

# Source package verification

List every check() script and C fixture in PKGBUILD source with checksums,
and run the extracted helpers from srcdir. Verify makepkg --source by unpacking
the resulting archive into a fresh directory and building there; a repository
checkout can hide missing source-package inputs.

# Hyprland cursor callbacks

With the Lua config provider, use `hyprctl eval` with `hl.config` for dynamic
cursor options. `hyprctl keyword` can return zero while reporting that it
cannot work with non-legacy parsers. Check `getoption cursor:invisible` after
each change and restore visibility on service stop or failure.
Waynergy INI files allow global keys before any section. When inspecting them
with Python ConfigParser, prepend a default section rather than reading them
as ordinary section-only INI files.

TLS pin status must check the configured host's `tls/hash/<host>` file, matching
native `net.c`. A top-level TLS-file search misses that nested pin and can
mistake templates or client identities for server trust. Verify the status
against the actual configured-host pin without printing its value.

Hyprland 0.56 applies `cursor:invisible` on a 500 ms renderer tick. An option
readback alone cannot verify cursor latency. The optional native plugin calls
ensureCursorRenderingMode through a plugin-owned Lua callback, without input
injection or timeout changes. Use addLuaFunction / hl.plugin for this Lua
compositor; legacy dispatcher names are interpreted as Lua expressions.
Check the compositor/header commit and library ABI before registering native callbacks, never
overwrite a loaded plugin inode, and run the native cursor check with
`--render` to verify both hiding and showing within 200 ms.
`hyprctl plugin load` can exit zero while rejecting a plugin. Require its
literal `ok` reply and verify the registered callback rather than trusting the
exit status alone.
Native plugin reloads can retain dlopen images and process-unique static
strings. Load an immutable SHA-256-named binary via its resolved path, and
construct the ABI fingerprint from version macros in local storage rather
than using the header's inline client-hash helper across unload/reload.

# Native IME shortcut acceptance

When assigning Ctrl+Space to Fcitx, remove Omarchy's non-consuming terminal
Ctrl+Space binding as well as any compositor-owned IME shortcut being replaced.
Verify real press/release sequences through Waynergy, Hyprland, Fcitx, and a
Chrome Wayland editor with `node scripts/verify-ime-space.mjs`. Check taps,
modifier-release ordering, normal held-key repeat, and no growth after release.
An unreproduced intermittent failure remains unconfirmed after synthetic checks.
See `docs/ime-shortcut.md` for setup, terminal-prefix conflicts, and the Omarchy
input-setup behavior that can remove the native Fcitx trigger.
