#!/usr/bin/env bash
# Install only screen hooks and cursor recovery; preserve connection and keys.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
config_dir="$config_root/waynergy/config.ini.d"
service_dir="$config_root/systemd/user/waynergy.service.d"
helper="$HOME/.local/bin/waynergy-cursor"
snippet="$config_dir/cursor-sync.ini"
dropin="$service_dir/cursor-sync.conf"
plugin="$HOME/.local/lib/waynergy/waynergy-cursor-refresh.so"
# A second screen hook would replace an existing command when INI files merge.
python3 - "$config_root/waynergy" "$snippet" <<'PY'
import configparser
from pathlib import Path
import sys

root, own = map(Path, sys.argv[1:])
for path in [root / 'config.ini', *sorted((root / 'config.ini.d').glob('*'))]:
    if not path.is_file() or path == own:
        continue
    config = configparser.ConfigParser(interpolation=None, strict=False)
    # Waynergy permits global properties before the first section.
    config.read_string('[DEFAULT]\n' + path.read_text())
    if config.has_section('screen') and any(config.get('screen', key, fallback='').strip() for key in ('enter', 'exit')):
        raise SystemExit(f'Existing screen hooks in {path}; combine them before installing cursor sync.')
PY
compiled_plugin=$(bash "$repo_dir/scripts/build-cursor-plugin.sh")
# Fail before installation if this is not a compatible, active Hyprland session.
systemd-run --user --quiet --wait --pipe --collect "$repo_dir/scripts/waynergy-cursor" show
backup="${XDG_STATE_HOME:-$HOME/.local/state}/waynergy-backups/cursor-sync-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup" "$config_dir"
install -d -m 755 "$HOME/.local/bin" "$service_dir" "$(dirname "$plugin")"
for target in "$helper" "$snippet" "$dropin" "$plugin"; do
  if [[ -e "$target" ]]; then
    cp -p -- "$target" "$backup/$(basename "$target")"
  else
    printf '%s\n' "$target" >> "$backup/previously-absent"
  fi
done
# dlopen can retain unloaded libraries. Use an immutable content-addressed
# path, resolve it when loading, and replace only the stable symlink.
old_plugin=$(readlink -f -- "$plugin" || true)
if [[ -n "$old_plugin" ]]; then
  systemd-run --user --quiet --wait --pipe --collect hyprctl plugin unload "$old_plugin" >/dev/null 2>&1 || true
fi
digest=$(sha256sum "$compiled_plugin")
digest=${digest%% *}
versioned_plugin="$(dirname "$plugin")/waynergy-cursor-refresh-$digest.so"
if [[ -e "$versioned_plugin" ]]; then
  cmp -- "$compiled_plugin" "$versioned_plugin"
else
  install -m 755 "$compiled_plugin" "$versioned_plugin"
fi
ln -sfn -- "$(basename "$versioned_plugin")" "$plugin.next"
mv -Tf -- "$plugin.next" "$plugin"
install -m 755 "$repo_dir/scripts/waynergy-cursor" "$helper"
install -m 600 "$repo_dir/config/waynergy/config.ini.d/cursor-sync.ini" "$snippet"
install -m 644 "$repo_dir/systemd/waynergy-cursor-sync.conf" "$dropin"
systemd-run --user --quiet --wait --pipe --collect "$helper" init
systemd-run --user --quiet --wait --pipe --collect "$helper" show
systemctl --user daemon-reload
if systemctl --user is-active --quiet waynergy.service; then
  systemctl --user restart waynergy.service
fi
printf 'Cursor synchronization installed; backup: %s\n' "$backup"
