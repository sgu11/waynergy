# macOS server lock synchronization

The macOS Deskflow fork sends the existing CSEC screensaver message for session
lock transitions. Waynergy 0.0.17 already handles CSEC through `screensaver/start`
and `screensaver/stop`; the existing protocol is sufficient. Since `0.0.17-4`,
the local package also fixes callback exit reporting (retained in `0.0.17-5`):
SA_NOCLDWAIT made system() return ECHILD (-1)
even when the lock command succeeded. The callback now temporarily enables
child waiting, following the existing clipboard probe pattern.

Install this optional configuration on an Omarchy 4 client:

```sh
bash scripts/install-lock-sync.sh
```

This copies only `scripts/waynergy-lock` and the `lock-sync.ini` snippet, with
backups under `~/.local/state/waynergy-backups/`. An active Waynergy service is
restarted to load the snippet. Existing connection settings, key mappings,
clipboard settings and TLS state are preserved. The general installer does
not enable this optional feature automatically.

The helper uses the existing Omarchy shell `lock lock` IPC. It checks the `ok`
reply and reports a rejected request to Waynergy's journal. It supplies
`/usr/share/omarchy/bin` on PATH because the live Waynergy unit limits PATH to
`/usr/local/bin:/usr/bin`. Omarchy's lock service performs local PAM
authentication. `screensaver/stop` is empty: unlocking the Mac does not unlock
Linux. Repeated start requests are idempotent in Omarchy's lock service.

For another distribution, replace the start helper with its session locker
(e.g. a desktop's supported D-Bus lock request). Keep the stop action empty.
Do not run a foreground locker directly from the callback: Waynergy waits for
the command to return. The Omarchy IPC command returns after requesting a lock.

## Native acceptance

In a Deskflow checkout that provides the lock-sync verifier, set
`WAYNERGY_CLIENT_SSH_HOST` to your client SSH alias, then run
`deploy/mac/verify-lock-sync.py "$WAYNERGY_CLIENT_SSH_HOST" --reconnect`.
Start with both desktops unlocked, lock the Mac when prompted, wait for the
client lock and reconnect checks, then unlock only the Mac. The check requires
Omarchy `sessionLocked=true` and `secure=true`, and verifies Linux remains locked
when macOS unlocks. Authenticate locally on Linux afterward. Merely receiving
`ok`, starting a process, or opening the lock preview is not acceptance.

Read current state without changing it:

```sh
systemd-run --user --quiet --wait --pipe /usr/share/omarchy/bin/omarchy-shell lock status
journalctl --user -u waynergy.service --since '5 minutes ago' --no-pager
```

Rollback: move `~/.config/waynergy/config.ini.d/lock-sync.ini` out of that
directory, restore any prior snippet/helper from the printed backup, then
restart `waynergy.service`. Removing synchronization does not unlock an already
locked desktop.
