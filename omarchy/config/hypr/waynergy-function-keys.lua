-- Only the Waynergy virtual keyboard: keep F16-F20 as ordinary function keys.
-- The installer preserves existing global XKB options in this device override.
hl.device({
  name = "hl-virtual-keyboard-waynergy",
  kb_options = "__KB_OPTIONS__",
})
