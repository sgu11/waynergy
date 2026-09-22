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
