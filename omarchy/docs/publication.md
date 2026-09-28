# Public fork

[sgu11/waynergy](https://github.com/sgu11/waynergy) is the source of truth for
the Waynergy client and Omarchy integration. It is a fork of
[r-c-f/waynergy](https://github.com/r-c-f/waynergy).

The root holds the C source. `omarchy/` holds configuration examples, the
installer, panel plugin, package recipe, and verification helpers. Change
behavior in the root source and update the package's pinned GitHub commit.
Do not maintain a separate integration source checkout or generated fork patch.

## Contribution flow

Use `origin` for `sgu11/waynergy` and `upstream` for `r-c-f/waynergy`. Contributors
without write access push to their GitHub fork and open a PR against
`sgu11/waynergy:master`. Any private mirror is a secondary copy.

New public commits use the GitHub identity `sgu11` and
`21072846+sgu11@users.noreply.github.com`. Preserve existing upstream authorship
and licenses. The Omarchy plugin uses the public ID `sgu11.waynergy`.

The initial public source base was `ad49be7fe8f0347e790aef6c76858dc29ebed3d4`.
Package `0.0.17-6` replaces release-archive patches with a pinned, SHA-256-checked
archive from this public fork. See the [package update procedure](../packaging/waynergy-custom/README.md).
Preserve the pinned source commit when merging, or update the recipe after a squash/rebase.

## Publication boundary

Inspect the tree and every new reachable commit before publication, including
author/committer emails, messages, paths, and older blob versions. Exclude
private endpoints, local host/user names, absolute home paths, credentials,
installed configuration, certificates, build output, and runtime logs.
Generic examples and public upstream credits can remain.

Push only the reviewed public branch, without private branches or tags, and
confirm its HEAD matches GitHub. The previous private source history is not
part of a contribution merely because its fixes are ported.

Ensure `omarchy/config/waynergy/config.ini.d/lock-sync.ini` remains tracked.
Upstream's `*.d` ignore pattern otherwise hides that configuration directory.

## Verification

Build with `makepkg --cleanbuild --force` in `omarchy/packaging/waynergy-custom`.
Its `check()` runs the protocol, callback, display, wheel, OS, and configuration
checks against the packaged source. Check shell syntax, plugin manifest/ID
consistency, archive checksums, and source equality with the intended commit.
Native lock acceptance is a deployment check described in [lock-sync.md](lock-sync.md).
