# Hide the cursor outside the client

Install on an active Omarchy / Hyprland Lua session:

```sh
bash scripts/install-cursor-sync.sh
```

Waynergy's `screen/exit` hook hides the compositor cursor; its
`screen/enter` hook shows it again. This hides the entire client cursor,
including a mouse plugged directly into the client. The systemd drop-in shows
the cursor when the service starts or stops, including process failure.
The helper uses `hyprctl eval` and checks the effective `cursor:invisible`
value. `hyprctl keyword` is not supported by the Lua configuration provider
and can exit successfully without changing the option.

Hyprland 0.56 normally updates `cursor:invisible` on a 500 ms timer. The small
native plugin in `hyprland/cursor-refresh.cpp` exposes only the compositor's
cursor visibility refresh through `hl.plugin.waynergy.refresh_cursor()`.
The helper changes visibility and calls this function in the same Lua request,
so both hiding and showing skip the timer. It injects no input and preserves
the cursor position, inactivity timeout and keyboard/touch hiding options.

The installer builds the plugin using `c++`, `pkg-config` and the installed
Hyprland headers. It installs the binary under `~/.local/lib/waynergy/` and
backs up its four files under
`~/.local/state/waynergy-backups/`, rejects conflicting screen hooks, and
restarts an active Waynergy service. Connection settings, keyboard maps,
clipboard configuration and TLS state stay host-owned.

The service loads the plugin at startup. The plugin rejects a header/runtime
commit or library ABI mismatch before registering its callback. After a Hyprland upgrade,
start the new compositor and rerun this installer to rebuild against its
matching headers. If the plugin cannot load, cursor visibility still works
through the normal compositor timer; the service keeps starting. The installer
uses an immutable SHA-256-named binary and atomically replaces a stable symlink.
The loader resolves that symlink before loading, avoiding stale `dlopen` images
and never overwriting a mapped library.

Verify by moving the server pointer out of the client and back, checking that
the client cursor disappears and returns. Query the compositor state with:

```sh
systemd-run --user --quiet --wait --pipe --collect hyprctl getoption cursor:invisible
```

Run `python3 scripts/verify-cursor-sync.py` in the active session to exercise
the installed binary with loopback CINN/COUT messages and verify that killing
the managed test client restores visibility. It uses isolated configuration
and keeps the pointer position, sending no key, clipboard or lock events.

Run `python3 scripts/verify-cursor-sync.py --render` with `grim` and
`python-pillow` available to also check that the rendered cursor disappears
and returns within 200 ms of each screen event. This briefly stops and then
restarts the live client to prevent
real screen transitions from interfering with the test. It compares a small
cursor region in memory without saving screenshots, checks the original
timeout and pointer position, and covers visibility recovery after a crash.
It also unloads and reloads the native plugin to check startup compatibility
and callback registration across reloads.

The pinned source still uses `SA_NOCLDWAIT` for screen callbacks, so Waynergy
may report `Screen state ... failed with code -1` even after the command
succeeds. Use the helper's `hidden=true/false` output and the compositor's
effective state to verify this feature. Screensaver callbacks already have
the separate child-wait fix.

To remove this feature, move `cursor-sync.ini` outside `config.ini.d` and
`cursor-sync.conf` outside `waynergy.service.d`, restore any previous files
from the backup, and run `systemctl --user daemon-reload` followed by a
service restart. Show the cursor immediately with:

```sh
systemd-run --user --quiet --wait --pipe --collect "$HOME/.local/bin/waynergy-cursor" show
```

After removing the hooks, unload the optional native plugin with
`hyprctl plugin unload "$(readlink -f "$HOME/.local/lib/waynergy/waynergy-cursor-refresh.so")"`.
Restore any previous plugin binary from the backup only after unloading it.
