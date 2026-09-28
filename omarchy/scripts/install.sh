#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh --host HOST --name NAME [options]

Options:
  --port PORT       Synergy/Deskflow port (default: 24800)
  --packages        Build waynergy from the pinned GitHub source (packaging/waynergy-custom) and wl-clipboard
  --aur             Install waynergy from AUR instead of the GitHub fork (legacy)
  --wheel-debounce  Build the patched package and use a 100 ms threshold (now part of custom fork)
  --wheel-debounce-ms MS
                    Build the patched package with a custom 1-1000 ms threshold
  --enable          Enable Waynergy and its display watcher for graphical sessions
  --force-config    Replace an existing config.ini (a timestamped backup is kept)
  -h, --help        Show this help
EOF
}

host=""
client_name=""
port="24800"
install_packages=false
use_aur=false
enable_service=false
force_config=false
wheel_debounce=false
wheel_debounce_ms=0

while (($#)); do
  case "$1" in
    --host) host="${2:-}"; shift 2 ;;
    --name) client_name="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
    --packages) install_packages=true; shift ;;
    --aur) install_packages=true; use_aur=true; shift ;;
    --wheel-debounce) wheel_debounce=true; wheel_debounce_ms=100; shift ;;
    --wheel-debounce-ms)
      wheel_debounce=true
      wheel_debounce_ms="${2:-}"
      shift 2
      ;;
    --enable) enable_service=true; shift ;;
    --force-config) force_config=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
# --wheel-debounce implies --packages from the custom fork (which already bundles the filter)
if $wheel_debounce; then
  install_packages=true
fi

if [[ -z "$host" || -z "$client_name" ]]; then
  printf '%s\n' '--host and --name are required.' >&2
  usage >&2
  exit 2
fi
if [[ ! "$host" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  printf '%s\n' 'Invalid host. Use a hostname or IP address.' >&2
  exit 2
fi
if [[ ! "$client_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf '%s\n' 'Invalid client name.' >&2
  exit 2
fi
if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
  printf '%s\n' 'Port must be an integer from 1 to 65535.' >&2
  exit 2
fi
if $wheel_debounce && { [[ ! "$wheel_debounce_ms" =~ ^[0-9]+$ ]] ||
   ((wheel_debounce_ms < 1 || wheel_debounce_ms > 1000)); }; then
  printf '%s\n' 'Wheel debounce must be an integer from 1 to 1000 ms.' >&2
  exit 2
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
waynergy_dir="$config_dir/waynergy"
service_dir="$config_dir/systemd/user"
plugin_dir="$config_dir/omarchy/plugins/sgu11.waynergy"
tls_dir="$waynergy_dir/tls"

if $install_packages; then
  omarchy pkg add wl-clipboard
  if $use_aur; then
    omarchy pkg aur add waynergy
  else
    command -v makepkg >/dev/null || {
      printf '%s\n' 'makepkg is required to build the custom waynergy package.' >&2
      exit 1
    }
    (
      cd "$repo_dir/packaging/waynergy-custom"
      makepkg -si --needed
    )
  fi
fi

command -v waynergy >/dev/null || {
  printf '%s\n' 'waynergy is missing. Re-run with --packages or install it first.' >&2
  exit 1
}

install -d -m 700 "$waynergy_dir" "$tls_dir"
install -d -m 755 "$service_dir" "$plugin_dir" "${XDG_BIN_HOME:-$HOME/.local/bin}"

config_file="$waynergy_dir/config.ini"
if [[ -e "$config_file" && "$force_config" != true ]]; then
  printf 'Keeping existing %s (use --force-config to replace it).\n' "$config_file"
else
  if [[ -e "$config_file" ]]; then
    backup="$config_file.bak.$(date +%Y%m%d%H%M%S)"
    cp -- "$config_file" "$backup"
    printf 'Backed up existing config to %s\n' "$backup"
  fi
  sed \
    -e "s|__HOST__|$host|g" \
    -e "s|__PORT__|$port|g" \
    -e "s|__NAME__|$client_name|g" \
    -e "s|__HOME__|$HOME|g" \
    -e "s|__WHEEL_DEBOUNCE_MS__|$wheel_debounce_ms|g" \
    "$repo_dir/config/waynergy/config.ini.example" >"$config_file"
  chmod 600 "$config_file"
fi

sed -e "s|__NAME__|$client_name|g" \
  "$repo_dir/config/waynergy/tls/openssl.cnf.example" >"$tls_dir/openssl.cnf"
install -m 755 "$repo_dir/config/waynergy/tls/generate-client-cert.sh" \
  "$tls_dir/generate-client-cert.sh"

install -m 644 "$repo_dir/systemd/waynergy.service" "$service_dir/waynergy.service"
install -m 644 "$repo_dir/systemd/waynergy-display-watch.service" \
  "$service_dir/waynergy-display-watch.service"
install -m 755 "$repo_dir/scripts/waynergy-ctl" "${XDG_BIN_HOME:-$HOME/.local/bin}/waynergy-ctl"
install -m 755 "$repo_dir/scripts/waynergy-display-watch" \
  "${XDG_BIN_HOME:-$HOME/.local/bin}/waynergy-display-watch"
install -m 644 "$repo_dir/omarchy-plugin/sgu11.waynergy/manifest.json" "$plugin_dir/manifest.json"
install -m 644 "$repo_dir/omarchy-plugin/sgu11.waynergy/Waynergy.qml" "$plugin_dir/Waynergy.qml"
install -m 644 "$repo_dir/omarchy-plugin/sgu11.waynergy/DeskflowIcon.qml" "$plugin_dir/DeskflowIcon.qml"

systemctl --user daemon-reload
omarchy plugin validate "$plugin_dir"
omarchy plugin enable sgu11.waynergy right
# The panel adds IPC handlers and replaces the legacy BarWidget entrypoint.
# A rescan/hot reload can retain the old instance and report a file-name case
# mismatch, so finish installation with a clean shell instance.
omarchy restart shell

if $enable_service; then
  systemctl --user enable --now waynergy.service waynergy-display-watch.service
else
  printf '%s\n' 'Services installed but not enabled. Use the bar widget for Waynergy, then:'
  printf '%s\n' '  systemctl --user enable --now waynergy-display-watch.service'
fi

printf '%s\n' 'Installation complete. Run ./scripts/doctor.sh to verify it.'
