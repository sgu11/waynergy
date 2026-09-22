# Public fork

The public repository is [sgu11/waynergy](https://github.com/sgu11/waynergy),
a fork of [r-c-f/waynergy](https://github.com/r-c-f/waynergy).

Its root contains the patched Waynergy source. The `omarchy/` directory holds
the configuration examples, installer, panel plugin, package recipes, and
verification helpers from this integration repository. No installed
configuration, trust state, certificates, build output, or runtime logs belong
in the public tree.

## Publication boundary

This integration repository has separate history from the upstream C project.
Publish a reviewed snapshot of its tracked files, together with the source
changes on top of upstream `master`. Do not push this integration repository's
history, or a local source branch with non-public author metadata, to GitHub.

New public commits use the GitHub identity `sgu11` and
`21072846+sgu11@users.noreply.github.com`. Preserve existing upstream authorship
and licenses. The Omarchy plugin uses the public ID `sgu11.waynergy`.

The initial public source base is
`ad49be7fe8f0347e790aef6c76858dc29ebed3d4`. Its additional source changes retain
deferred clipboard grabs, protocol 1.8 compatibility, wheel debounce, and
screensaver callback child waiting. The package recipe remains reproducible
from `v0.0.17` and the two tracked patches.

Before each publication, inspect both the tree and every new reachable commit,
including author/committer emails, messages, paths, patch headers, and older
blob versions. Exclude private endpoints, local host/user names, absolute home
paths, credentials, and runtime data. Generic examples and public upstream
credits can remain. Push only the reviewed public branch, without private
branches or tags, and confirm its HEAD matches GitHub.

Compare every tracked integration path with the public Git index after import.
Upstream ignores `*.d` directories, so explicitly allow
`omarchy/config/waynergy/config.ini.d/lock-sync.ini` in the public root ignore
rules. A file present on disk can otherwise be absent from the published tree.

## Verification

Build with `makepkg --force` in `omarchy/packaging/waynergy-custom`. Then run
`verify-debounce.sh` and `bash verify-fork.sh` there against the prepared source.
Check shell syntax, plugin manifest/ID consistency, patch checksums, and source
equality with the public root. Native lock acceptance remains a separate
deployment check described in [lock-sync.md](lock-sync.md).
