#!/usr/bin/env bash
set -u

failures=0
warnings=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK    %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

warn_check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'OK    %s\n' "$label"
  else
    printf 'WARN  %s\n' "$label"
    warnings=$((warnings + 1))
  fi
}

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ctl="$(command -v waynergy-ctl 2>/dev/null || true)"
[[ -n "$ctl" ]] || ctl="$repo_dir/scripts/waynergy-ctl"
check 'waynergy executable is installed' command -v waynergy
warn_check 'waynergy has custom fork protocol support (0.0.17 + Deskflow)' \
  sh -c 'waynergy --version 2>&1 | grep -q "0.0.17" && strings "$(command -v waynergy)" | grep -q Deskflow'
warn_check 'wl-copy is installed for clipboard sync' command -v wl-copy
check 'ss is installed for live connection checks' command -v ss
check 'socat is installed for Hyprland monitor events' command -v socat
check 'Waynergy config exists' test -f "$config_dir/waynergy/config.ini"
check 'systemd user unit exists' test -f "$config_dir/systemd/user/waynergy.service"
check 'display watcher unit exists' test -f "$config_dir/systemd/user/waynergy-display-watch.service"
check 'Omarchy Waynergy plugin exists' test -f "$config_dir/omarchy/plugins/sgu11.waynergy/manifest.json"
check 'waynergy-ctl is available' test -x "$ctl"
check 'display watcher is installed' test -x "${XDG_BIN_HOME:-$HOME/.local/bin}/waynergy-display-watch"
warn_check 'WAYLAND_DISPLAY reached the systemd user manager' \
  sh -c 'systemctl --user show-environment | grep -q "^WAYLAND_DISPLAY="'
warn_check 'Waynergy service is enabled' systemctl --user is-enabled --quiet waynergy.service
warn_check 'Waynergy service is active' systemctl --user is-active --quiet waynergy.service
warn_check 'display watcher is enabled' systemctl --user is-enabled --quiet waynergy-display-watch.service
warn_check 'display watcher is active' systemctl --user is-active --quiet waynergy-display-watch.service

if [[ -x "$ctl" ]]; then
  "$ctl" state >/dev/null 2>&1
  state=$?
  case "$state" in
    0) printf '%s\n' 'OK    Waynergy has a live server connection' ;;
    1)
      printf '%s\n' 'WARN  service is active but has no live server connection'
      warnings=$((warnings + 1))
      ;;
    2)
      printf '%s\n' 'WARN  Waynergy service is stopped'
      warnings=$((warnings + 1))
      ;;
    3)
      printf '%s\n' 'FAIL  Waynergy executable or service unit is unavailable'
      failures=$((failures + 1))
      ;;
    *)
      printf 'FAIL  waynergy-ctl returned unexpected state %s\n' "$state"
      failures=$((failures + 1))
      ;;
  esac
fi

printf '\nResult: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
((failures == 0))
