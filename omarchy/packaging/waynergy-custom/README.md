# waynergy-custom

Package `0.0.17-6` builds the root C source from
[sgu11/waynergy](https://github.com/sgu11/waynergy). `PKGBUILD` pins the full
source commit and its archive SHA-256. No behavior patches or nested source
checkout are required.

The pinned source includes protocol negotiation up to 1.8, deferred clipboard
grabs, wheel debounce, screensaver child waiting, upstream timeout/PID/keymap
fixes, and display geometry protection. The package metadata and verification
helpers can advance independently of the source pin when the C source is unchanged.

## Build and verify

Install the dependencies listed in `PKGBUILD`, then run from this directory:

```sh
makepkg --cleanbuild --force
```

`makepkg` verifies the archive checksum, compiles the client, runs `check()`,
and creates the package. The verification scripts and C fixtures are included
in `source` with checksums, so `makepkg --source` produces a self-contained recipe. `check()` runs both verification helpers against the
actual prepared source. To repeat only those checks:

```sh
bash ./verify-fork.sh
bash ./verify-debounce.sh
```

`src/waynergy` points to the unpacked pinned source. An explicit source directory
can also be passed to either helper after its Meson build has generated headers.

The checks cover protocol 1.6 fallback and the 1.8 cap after reconnect, three
hello names, clipboard deferral, key events, secure-input/layout notifications,
CSEC callbacks and real command-child reaping, timeout boundaries, positive-PID
cleanup, display geometry and output removal, and wheel debounce regressions.
They invoke the upstream OS/configuration tests directly to propagate failures.
Native compositor lock and live Deskflow acceptance require a separate deployment
check; see [lock-sync.md](../../docs/lock-sync.md).

## Update the source

1. Commit and push reviewed root source changes to GitHub.
2. Set `_commit` in `PKGBUILD` to that full commit ID and increment `pkgrel`.
3. Download its archive from `sgu11/waynergy` and update `sha256sums`.
4. Run `makepkg --cleanbuild --force` and compare the prepared C source with the intended commit.
5. Commit the recipe and documentation update after the source commit.

Keep the source commit reachable when merging a PR. Use a merge commit, or
update the pin and checksum to the resulting commit after a squash/rebase.
Do not point the recipe at a moving branch or add behavior patches alongside it.

The former release-archive patches and wheel-only package are available in Git
history before this migration.

For the real client handshake check, run from the repository root in an active
Wayland session with Python 3 available:

```sh
python3 test/protocol-handshake.py build/waynergy
```

This starts isolated clients against loopback servers, checks protocol 1.6–1.8
negotiation and rejection of unsupported versions, and sends no input or lock events.
