#!/usr/bin/env bash
# Installs only lock synchronization; preserves connection, input and TLS settings.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/waynergy/config.ini.d"
helper="$HOME/.local/bin/waynergy-lock"
snippet="$config_dir/lock-sync.ini"
backup="${XDG_STATE_HOME:-$HOME/.local/state}/waynergy-backups/lock-sync-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup" "$config_dir"
install -d -m 755 "$HOME/.local/bin"
for target in "$helper" "$snippet"; do
  if [[ -e "$target" ]]; then
    cp -p -- "$target" "$backup/$(basename "$target")"
  else
    printf '%s\n' "$target" >> "$backup/previously-absent"
  fi
done
install -m 755 "$repo_dir/scripts/waynergy-lock" "$helper"
install -m 600 "$repo_dir/config/waynergy/config.ini.d/lock-sync.ini" "$snippet"
if systemctl --user is-active --quiet waynergy.service; then
  systemctl --user restart waynergy.service
fi
printf 'Lock synchronization installed; backup: %s\n' "$backup"
