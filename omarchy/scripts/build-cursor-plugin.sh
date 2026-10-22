#!/usr/bin/env bash
# Build against the installed compositor headers; pluginInit checks the hash.
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output="${1:-$(mktemp -d -t waynergy-cursor-plugin.XXXXXX)/waynergy-cursor-refresh.so}"
read -r -a flags <<< "$(pkg-config --cflags hyprland)"
c++ -std=c++23 -O2 -fPIC -shared "${flags[@]}" \
  "$repo_dir/hyprland/cursor-refresh.cpp" -o "$output"
printf '%s\n' "$output"
