# waynergy-custom

Custom package `0.0.17-5`, based on r-c-f/waynergy `v0.0.17` plus upstream
`master` through `ad49be7fe8f0347e790aef6c76858dc29ebed3d4` (2026-09-13), with:

- EBAD fix: defer CCLP clipboard grab until first CINN (fixes Deskflow/Synergy 1.8 EBAD loop)
- Protocol 1.8: bump minor to 8, add Deskflow hello, handle DKDL/SECN/LSYN/DFTR/DDRG/EICV/EUNK
- Wheel debounce: filter encoder bounce (from packaging/wheel-debounce)
- Screensaver callbacks: wait for command children and report completion

The four upstream commits since `v0.0.17` improve Wayland connection errors,
avoid sending SIGTERM to the client's own process group during cleanup, avoid
false timeouts on backward clock ticks, and correct Windows XKB keycodes
(offset 8 and distinct F11/F12 codes).

The tracked source recipe is the `v0.0.17` archive, `custom-fork.patch`, then
`screensaver-child-wait.patch`. All three inputs have SHA-256 checksums in
`PKGBUILD`; the combined patch includes the upstream changes and the first
three fork features above. The screensaver patch remains separate.

`../../upstream` is an optional, ignored development checkout, not a build
dependency. The release archive and tracked patches fully reproduce the
source tree without requiring a previous local checkout or its commit history.

Build without installing, then check the prepared implementation:

```sh
cd packaging/waynergy-custom
makepkg --force
./verify-debounce.sh
bash ./verify-fork.sh
```

`verify-debounce.sh` checks the measured 100 ms threshold and return-protection
regressions, returning nonzero on failures. `verify-fork.sh` exercises the
prepared protocol source and extracted callback/cleanup functions: protocol
1.8 hellos and key events, deferred clipboard grabs, CSEC on/off and reconnect,
real command child reaping, clock rollback/wraparound, and positive-PID cleanup.
It also runs upstream's OS and configuration tests with exit-status checks.
The callback harness uses harmless commands and a simulated compositor; native
lock acceptance still follows [lock-sync.md](../../docs/lock-sync.md).

When updating this source checkout again, merge upstream before regenerating
the combined patch from the release base. Run the following from the repository
root. Exclude `src/main.c` because its callback change is applied by the separate
screensaver patch:

```sh
git -C upstream diff --src-prefix=a/ --dst-prefix=b/ v0.0.17 HEAD -- \
  . ':(exclude)src/main.c' > packaging/waynergy-custom/custom-fork.patch
```

Review the full delta, update the checksums and package release, and verify
that the prepared package source matches the merged checkout.

The separate `0001-ebad-fix.patch` / `0002-protocol-1.8.patch` are the logical splits
of the original fork changes, kept for review. They are not applied separately.
