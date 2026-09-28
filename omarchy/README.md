# Waynergy on Omarchy

This repository captures the working Waynergy setup for an Omarchy 4 / Hyprland
client. It is intended to make a future reinstall or troubleshooting session
repeatable without copying host-owned credentials or runtime state.

The public [sgu11/waynergy fork](https://github.com/sgu11/waynergy) includes
the Waynergy source at its root and this integration under `omarchy/`.
Run this document's commands from that `omarchy/` directory. See
[public publication](docs/publication.md) for the source and history boundaries.

## What is included

| Path | Installed location | Purpose |
| --- | --- | --- |
| `config/waynergy/config.ini.example` | `~/.config/waynergy/config.ini` | Waynergy connection, TLS, logging, and Windows media-key mapping |
| `systemd/waynergy.service` | `~/.config/systemd/user/waynergy.service` | Starts Waynergy as part of the graphical session |
| `systemd/waynergy-display-watch.service` | `~/.config/systemd/user/waynergy-display-watch.service` | Re-execs Waynergy after Hyprland monitor changes |
| `scripts/waynergy-ctl` | `~/.local/bin/waynergy-ctl` | Reports live connection state and safely controls service/autostart |
| `scripts/waynergy-display-watch` | `~/.local/bin/waynergy-display-watch` | Debounces Hyprland monitor add/remove events |
| `omarchy-plugin/sgu11.waynergy/` | `~/.config/omarchy/plugins/sgu11.waynergy/` | Omarchy connection-status and control panel |
| `packaging/waynergy-custom/` | pinned GitHub source build | Preferred: builds `0.0.17-6` instead of AUR |
| `scripts/install.sh` | run from this repository | Installs the captured configuration safely |
| `scripts/doctor.sh` | run from this repository | Read-only installation and runtime checks |

The live setup also has an optional `~/.local/bin/waynergy-connect` TCP retry
wrapper. It is documented in `docs/implementation-notes.md` but is not used by
the working systemd unit because Waynergy already reconnects by itself.

## Quick start

`wl-clipboard` enables clipboard synchronization. The installer now builds
Waynergy from a pinned `sgu11/waynergy` commit (`packaging/waynergy-custom`, `0.0.17-6`) which
contains the Deskflow/Synergy 1.8 EBAD fix and Barrier protocol support, instead
of the unpatched AUR package:

```bash
./scripts/install.sh \
  --host SERVER_ADDRESS \
  --name CLIENT_SCREEN_NAME \
  --packages \
  --enable
```

Use the current Synergy/Deskflow server address and the exact screen name from
the server layout. The default port is `24800`. Without `--enable`, the service
is installed but remains disabled. The Omarchy panel controls the running
service and login autostart independently.

`--packages` builds `packaging/waynergy-custom` (`EBAD fix + protocol 1.8 + wheel debounce`).
Use `--aur` only to force the legacy unpatched AUR package. For a mouse that
emits isolated reverse-direction wheel notches, the same fork already contains
the filter — just set the threshold:

```bash
./scripts/install.sh \
  --host SERVER_ADDRESS \
  --name CLIENT_SCREEN_NAME \
  --wheel-debounce \
  --enable
```

`--wheel-debounce` uses the verified 100 ms threshold. Use
`--wheel-debounce-ms MS` only after measuring receiving-side reversal
intervals. All wheel-debounce code lives in the root source tree.

The generated wlr configuration defaults to `wheel_mult=3`. The Omarchy panel
offers `×1`, `×2`, and `×3`; selecting a value updates only that setting,
keeps a timestamped configuration backup, and briefly restarts Waynergy.

The panel also has a wheel-debounce switch. It is guarded by a binary
capability check (looks for the debounce log marker), so the stock AUR binary
leaves it unavailable; the custom fork (`0.0.17-6`) enables it and uses the
last configured threshold or 100 ms when none is set.

The display watcher listens to Hyprland's v2 monitor add/remove events. It
waits one second for the layout to settle, coalesces repeated notifications,
then asks `waynergy-ctl refresh-display` to send `SIGUSR1` to the active
Waynergy process. Waynergy documents that signal as an in-process re-exec, so
its Wayland output state and Deskflow geometry are rebuilt without exercising
systemd's restart/start-limit path.

After installation, add the widget if it was not enabled automatically:

```bash
omarchy plugin enable sgu11.waynergy right
```

The public plugin ID is `sgu11.waynergy`. If upgrading an installation that
used a different plugin ID, disable the old widget before enabling this one
to avoid duplicate controls.

Then check the setup:

```bash
./scripts/doctor.sh
journalctl --user -u waynergy.service -n 100 --no-pager
```

A successful connection includes `Connected as client "<name>"` followed by
periodic `Got CALV` keepalive messages. The previous `0.0.17-1` AUR build showed
a single `Protocol error (EBAD)` on every connect due to an early `CCLP`
clipboard grab before `CINN` (`seq=0`), followed by a ~10 s reconnect loop;
the custom fork defers the grab until `CINN` and connects stably to
Deskflow 1.26 / Synergy 1.8 with clipboard sync enabled.

## Security and host-owned state

TLS is enabled with trust-on-first-use (TOFU). Review the server fingerprint on
first connection. Do not commit generated certificates, TOFU fingerprints,
`~/.config/waynergy/tls/cert`, logs, or other machine-specific runtime data.
The repository `.gitignore` excludes those files if they are copied here by
mistake.

If the server requires a client certificate, generate a host-local one after
installation and approve the printed SHA-256 fingerprint on the server:

```bash
~/.config/waynergy/tls/generate-client-cert.sh
```

## Current source baseline

Updated on 2026-09-28. The public fork includes upstream `master` through
`ad49be7`, plus the integrated protocol negotiation and display fixes:

- `waynergy 0.0.17-6` (existing fork fixes + protocol negotiation + display geometry protection)
- `wl-clipboard` for clipboard synchronization
- Wayland `wlr` input backend
- Deskflow 1.26.0.418 (legacy `Synergy` protocol, also supports `Barrier`) / Synergy 1.8 over port `24800`
- user service tied to `graphical-session.target`
- Omarchy shell panel polling service, autostart, and live TCP connection state

The custom fork accepts `Barrier`/`Deskflow`/`Synergy` hello messages, negotiates
up to protocol 1.8, and defers `CCLP` until `CINN`. It preserves the remaining
output list when the first monitor disappears and ignores nonpositive screen
sizes, keeping the last valid geometry. The display watcher remains available
for rebuilding compositor state after monitor changes.
Wheel debounce remains disabled (`0`) by default;
the package release is `0.0.17-6`. The binary reports `0.0.17`, optionally with
a Git-derived version suffix when built inside a checkout. The legacy AUR
build was `0.0.17-1.2`.

The four upstream commits improve Wayland connection errors, process cleanup,
clock rollback handling, and the Windows XKB keycode example. The existing
raw-keymap offset 8, monitor refresh, panel controls, and optional lock
synchronization are preserved. See [the package recipe](packaging/waynergy-custom/README.md)
for exact source provenance and build verification. Source verification does
not imply that the package has been installed or native lock acceptance rerun.

See `docs/implementation-notes.md` for the reasoning, known behavior, and
troubleshooting notes.

## Optional server lock synchronization

See [macOS server lock synchronization](docs/lock-sync.md) to lock this Omarchy
client when the Mac server locks, using the existing Waynergy CSEC callback.
