# Repeating Space around input-method switching

A Space tap that keeps inserting spaces until another key is pressed indicates
that a repeat producer did not receive, or did not accept, its release. Check
the whole path: Deskflow capture, Waynergy, Hyprland, Fcitx, and the application.
Chrome web apps running natively on Wayland also use this path.

Waynergy's `syn_key_cb` ignores server `DKRP` repeats; the compositor/application
or Fcitx normally provides repetition. Fcitx's Wayland frontend starts a repeat
timer on a repeatable press and stops it on the corresponding release. This
explains the symptom but does not locate the missing release.

Hyprland 0.56.2 also has a reported
[cross-keyboard release suppression problem](https://github.com/hyprwm/Hyprland/discussions/16275).
A stale pressed key on one keyboard can suppress releases from another. That
report is a candidate explanation, not proof of the cause on a different host.
Do not disable unrelated keyboard devices without evidence of stale state.

## Use Fcitx's native Ctrl+Space

If Shift+Space currently runs `omarchy-input-method cycle` through a Hyprland
binding, replace that path with a native Fcitx trigger. This keeps the switch
and its key events within the input method. The change is a mitigation until
the original intermittent failure is reproduced and traced.

Back up `~/.config/hypr/bindings.lua` and `~/.config/fcitx5/config` first.
Remove the user Shift+Space binding. In `bindings.lua`, after the Omarchy
defaults, add:

```lua
-- Fcitx owns Ctrl+Space, including its press and release.
hl.unbind("CTRL + SPACE")
```

Omarchy otherwise has a non-consuming Ctrl+Space binding that returns terminals
to direct input. Remove it too: it conflicts with using the same key to toggle
Fcitx. Ctrl+Space now belongs to the input method, including in terminals; a
tmux/Herdr Ctrl+Space prefix needs a different key if it is in use.

Add `Control+space` to the existing `[Hotkey/TriggerKeys]` list in Fcitx's
`config`, using the next unused numeric index. Preserve the other trigger keys
and all other sections. For example:

```ini
[Hotkey/TriggerKeys]
0=Zenkaku_Hankaku
1=Hangul
2=Control+space
```

Reload and verify:

```sh
fcitx5-remote --check -r
hyprctl reload
hyprctl configerrors
```

Require an empty `configerrors` result. In `hyprctl -j binds`, neither the old
Shift+Space switch nor the Ctrl+Space terminal binding should remain. Confirm
that Ctrl+Space switches input in a focused editor and that the language keys
still work. No Waynergy rebuild or Chrome flag change is required.

Omarchy's input setup currently removes `Control+space` in
`default/input-methods/configure.py:without_ctrl_space` to reserve terminal
prefixes. After rerunning input setup or defaults, check the Fcitx trigger
again and reapply this choice if necessary. Keep packaged files under
`/usr/share/omarchy` unchanged.

## Native acceptance

With Node >= 22, Google Chrome, Hyprland, and Fcitx running, and the current
Fcitx group containing `keyboard-us` and `hangul`, run:

```sh
node scripts/verify-ime-space.mjs
```

The check briefly stops an active Waynergy service and opens a disposable
Chrome Wayland profile with a local contenteditable field. An isolated real
Waynergy process connects to a loopback Deskflow protocol peer. It sends Space,
Shift, and Ctrl key sequences through the native compositor and input method;
it does not type into a real account or change the live server or TLS settings.
The live service, previous focus, and input mode are restored afterwards.

Checks include single taps, both modifier-release orders, overlapping Space
and modifier presses, held Space with normal repeat, held Ctrl+Space, and 24
alternating Korean/English switches with typing. Text must stop growing after
release. Holding the Fcitx trigger can cycle input modes more than once; that
does not indicate a missing release.

This does not exercise physical server capture or the X site's editor code.
Successful synthetic checks do not prove that an intermittent failure is gone.
Use the real X app with Ctrl+Space and watch for recurrence. If it recurs,
compare a plain Chrome editor and a native editor, then trace only Space and
its modifiers across the boundary that differs. Full Waynergy/Fcitx debug logs
can contain typed text; use a scratch field and keep diagnostic output scoped.
