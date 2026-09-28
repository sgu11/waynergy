# Implementation notes

## Architecture

```text
Omarchy bar panel
    | waynergy-ctl (state, service, autostart)
    v
waynergy.service -- graphical-session.target
    |
    +-- ~/.config/waynergy/config.ini
    +-- Wayland wlr virtual input backend
    +-- wl-clipboard (optional clipboard synchronization)
    v
Synergy / Deskflow server: TCP 24800 with TLS TOFU

Hyprland monitor add/remove
    | waynergy-display-watch (1 s debounce)
    v
waynergy-ctl refresh-display -- SIGUSR1 re-exec
```

The systemd user service is the single process owner. Hyprland's
`~/.config/hypr/autostart.lua` deliberately does not launch Waynergy, avoiding
duplicate clients and `EBSY` errors. The unit is tied to
`graphical-session.target`, imports `XDG_RUNTIME_DIR`, and only starts when
`WAYLAND_DISPLAY` exists in the user manager environment.

The service calls `/usr/bin/waynergy` without connection flags. Waynergy reads
`~/.config/waynergy/config.ini`, keeping host, port, client name, TLS mode, log
settings, and key mapping in one place.

`waynergy-display-watch.service` is a second graphical-session user unit. It
subscribes to Hyprland's event socket and consumes only `monitoraddedv2` and
`monitorremovedv2`, because Hyprland also emits legacy duplicates. A one-second
resettable timer lets the final monitor layout settle before it calls
`waynergy-ctl refresh-display`.

The refresh sends Waynergy's documented `SIGUSR1` re-exec signal to the unit's
main process only when `waynergy.service` is active. This is preferable to a
systemd restart: it rebuilds Wayland output and virtual-input geometry while
avoiding the start-limit path. A brief Deskflow reconnect is still expected.

This recovery exists because an internal-panel disable was observed to produce
`Lost output`, followed by `Sending DINF`, then repeated `Could not find xdg
output` / `Output not found in list` messages. A re-exec immediately rebuilt
the correct remaining output. The watcher is a containment fix; correcting the
stale xdg-output lifecycle in Waynergy remains the upstream root fix.

## Why the raw key map exists

The Windows server sends single-byte PS/2 set-1 scancodes that share Linux
evdev values. `[raw-keymap] offset=8` converts that range to XKB keycodes.
Extended (`E0`) keys use explicit final XKB values and
`offset_on_explicit=false`, avoiding an implicit second transformation.
The status panel reports the effective offset, including the legacy global
`xkb_key_offset` when an older configuration still uses it.

Waynergy's INI parser recognizes `;` as the comment marker. Keep generated
configuration comments in that form, particularly when a comment contains
`=`.

## Live state and safe control

`waynergy-ctl` is the single state and mutation boundary used by the panel and
doctor. It distinguishes an active systemd unit from a live server connection
by checking whether the Waynergy process owns an established socket to the
configured `host:port`. Historical journal entries are not current connection
evidence.

Service state and login autostart are separate controls. Before starting,
`waynergy-ctl` clears a possible systemd start-limit failure and verifies the
requested transition. Destructive one-key shortcuts and right-click service
toggles are intentionally absent because stopping Waynergy can remove the
session's remote input path.

Routine status refresh is deliberately invisible. The earlier bar widget
treated its polling processes as a visual busy state and lowered icon opacity
while each process ran, causing a brief flicker every five seconds. The current
panel retains the last complete state until the next JSON snapshot arrives;
only a user-requested service mutation uses optimistic visual state.

The panel also exposes a three-value wheel multiplier selector (`×1`, `×2`,
`×3`). `waynergy-ctl set-wheel-mult` validates the value, preserves the rest
of `config.ini`, writes a timestamped backup, replaces the setting through a
same-directory temporary file, and restarts Waynergy. The repository default
is `3`; changing it can briefly interrupt remote input while the client
reconnects.

The panel's wheel-debounce switch is guarded by a binary capability check. The
helper looks for the patched binary's debounce log marker, so a stock AUR
installation cannot appear enabled while silently ignoring the setting. On a
patched build, enabling preserves the configured threshold (or selects 100 ms
if it was unset); disabling writes zero and both transitions restart Waynergy.

## Custom fork (`packaging/waynergy-custom`)

The AUR `0.0.17-1` build (`USYNERGY_PROTOCOL_MINOR 6`, `src/uSynergy.c:297` hello
`{"Barrier","Synergy"}`) negotiates down to `1.6` and sends a `CCLP` clipboard
grab with `seq=0` before the first `CINN`. Deskflow 1.26 / Synergy 1.8 treats
that as a protocol violation and replies `EBAD` (`src/uSynergy.c:736`), causing
the `Protocol error → 10 s timeout → reconnect` loop. The fork fixes this by
buffering the grab in `m_clipGrabPending` (`include/uSynergy.h:374`) and
announcing it once `CINN` provides a valid sequence number
(`src/uSynergy.c:408`, `src/uSynergy.c:1015`, from `virgiliogaca` PR #111).

Protocol alignment:

- `USYNERGY_PROTOCOL_MINOR 6 → 8` (`include/uSynergy.h:101`) so Deskflow creates
  a `1.8` proxy instead of `1.6`. Hello now accepts `{"Barrier","Deskflow","Synergy"}`
  (`src/uSynergy.c:297`).
- New `1.8` messages are handled instead of falling into `Unknown packet`:
  `DKDL` (key down with language), `DKRP` optional trailing language, `SECN`/`LSYN`
  (secure input / language sync), `DFTR`/`DDRG` (file transfer), plus explicit
  `EICV`/`EUNK`.

Wheel debounce in the root source filters a direction reversal inside a
configured interval and protects the user's returning notch. Return-protection is armed only when the escaping reversal
arrived close to the window (within 2x). Horizontal and vertical axes are
independent and the default is zero.

The captured receiving-side samples cleanly separated measured bounce (up to
78 ms) from intentional reversals (from 202 ms). The installer therefore uses
100 ms for `--wheel-debounce`, but this is device-specific. Hardware replacement
remains the root fix.

After `makepkg` has prepared the source, validate the extracted implementation:

```bash
bash ./packaging/waynergy-custom/verify-debounce.sh
```

The `0.0.17-6` recipe downloads a pinned, SHA-256-checked commit archive from
`sgu11/waynergy`. Source changes live at the repository root. The earlier
`0.0.17-5` release archive and generated patches are retained in Git history.
See the [package notes](../packaging/waynergy-custom/README.md) for the update
procedure and verification commands.

The integrated client negotiates the lower of its supported minor version and
the server's minor version, so a 1.6 server receives a 1.6 hello. It reports
secure-input applications and server keyboard layouts in the log. Removing
the first Wayland output preserves the rest of the list; nonpositive geometry
updates leave the last valid screen size and input-backend geometry intact.

Upstream now guards clipboard monitor PIDs with `> 0` during cleanup, avoiding
accidental process-group SIGTERM when a monitor was never started. Both network
timeout paths use a signed elapsed-time comparison so a backward tick does
not look like a long idle period. The Windows XKB example uses offset 8 and
separate F11/F12 keycodes, consistent with this repository's existing raw-keymap.

## Runtime behavior observed

On 2026-08-24 with the unpatched `0.0.17-1` build, the journal showed:

1. connection to the configured server on port 24800;
2. identification of the server as Synergy 1.8;
3. a successful client registration;
4. one immediate protocol error (`EBAD` from early `CCLP` `seq=0`) and TLS close;
5. automatic reconnection about 200 ms later;
6. regular `CALV` keepalives for more than a minute;
7. a clean SIGTERM shutdown from systemd.

That single error was tolerated because the client reconnected, but with
Deskflow 1.26 / Synergy 1.8 and clipboard sync enabled it repeats on every
connect (~10 s loop). After the custom fork (`0.0.17-3`), the same setup shows
`Connected as client "<name>"` with no `EBAD`, followed immediately by stable
`Got CALV` keepalives. Persistent `EBAD` without keepalives remains a real
failure; use `waynergy -L debugsyn` to capture the `DINF`/`CCLP`/`CINN`
sequence.

## Optional retry wrapper

The live host contains this older helper:

```bash
#!/bin/bash
set -u
host="${WAYNERGY_HOST:-SERVER_ADDRESS}"
port="${WAYNERGY_PORT:-24800}"

while true; do
  if timeout 2 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
    exec waynergy
  fi
  sleep 3
done
```

It waits until the server TCP port is reachable. The current service does not
use it because Waynergy reconnects internally and systemd also restarts the
process. Keep the wrapper only if startup produces a reproducible failure that
Waynergy cannot recover from; otherwise it adds a second retry layer without a
benefit.

## Troubleshooting

Run read-only checks first:

```bash
./scripts/doctor.sh
systemctl --user status waynergy.service --no-pager -l
journalctl --user -u waynergy.service -n 100 --no-pager
systemctl --user show-environment | grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR)='
```

Common cases:

- `WAYLAND_DISPLAY` missing: the user manager did not receive the graphical
  session environment, so the unit condition prevents startup.
- `EBSY` or duplicate client name: stop other Waynergy processes and make the
  `name=` value match exactly one screen in the server configuration.
- no clipboard: install `wl-clipboard`; use `no-clip` only when clipboard sync
  must be disabled deliberately.
- TLS trust failure: inspect the current server certificate and TOFU state.
  Never copy another host's certificate or fingerprint blindly.
- input does not arrive: confirm the session is Hyprland/Wayland and keep
  `backend=wlr`. The `uinput fd open failed` line can appear even when the wlr
  backend is used and does not by itself indicate a failure.

## Files intentionally excluded

- `~/.config/waynergy/tls/cert`: private client key/certificate material
- TOFU fingerprints: trust state belongs to the individual host
- `waynergy.log` and journal exports: runtime data may contain topology details
- package build cache: reproducible installation is documented via Omarchy/AUR

## Omarchy integration

The bar plugin is user-owned under `~/.config/omarchy/plugins/`, so Omarchy
updates do not overwrite it. The installer uses `omarchy plugin validate` and
`omarchy plugin enable`, rather than directly rewriting `shell.json`. The
plugin uses a native Shape version of the Deskflow symbolic icon. A curve
renderer and exact 2x texture supersampling avoid the scaling artifacts seen
with the SVG/Image path while retaining the bar foreground color.

Ordinary plugin edits hot-reload. This package changes the legacy entrypoint
and registers IPC handlers, so the installer restarts the shell once after
enabling it; a rescan alone can retain the old instance and produce a file-name
case mismatch. For later content-only changes, rescan with:

```bash
omarchy-shell shell rescanPlugins
```
