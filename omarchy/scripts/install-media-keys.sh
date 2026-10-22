#!/usr/bin/env bash
# Install only volume/mute mappings; preserve connection, raw keys and TLS.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/waynergy/config.ini.d"
snippet="$config_dir/media-keys.ini"
backup="${XDG_STATE_HOME:-$HOME/.local/state}/waynergy-backups/media-keys-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup" "$config_dir"
if [[ -e "$snippet" ]]; then
  cp -p -- "$snippet" "$backup/media-keys.ini"
else
  printf '%s\n' "$snippet" > "$backup/previously-absent"
fi
install -m 600 "$repo_dir/config/waynergy/config.ini.d/media-keys.ini" "$snippet"
if systemctl --user is-active --quiet waynergy.service; then
  systemctl --user restart waynergy.service
fi
printf 'Volume/mute mappings installed; backup: %s\n' "$backup"
