#!/usr/bin/env bash
# wheel_debounce() 를 waynergy 소스에서 그대로 추출해 실측 데이터로 돌린다.
# 지정한 소스의 동작만 검증한다. 설치된 바이너리의 동작은 별도로 검증한다.
#
#   ./verify-debounce.sh [waynergy source path]
# The default is the source tree produced by makepkg in this directory.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:-$HERE/src/waynergy}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SRC/src/wl_input.c" ] || { echo "wl_input.c 없음: $SRC" >&2; exit 1; }

sed -n '/^\/\* Some mice bounce/,/^}$/p' "$SRC/src/wl_input.c" > "$WORK/extracted.inc"
if [ ! -s "$WORK/extracted.inc" ]; then
	echo "wheel_debounce() 를 찾지 못했다 — 패치가 적용되지 않은 소스다" >&2
	exit 1
fi
echo "추출: $(wc -l < "$WORK/extracted.inc")줄  ($SRC/src/wl_input.c)"

gcc -Wall -Wextra -O2 -o "$WORK/t" "$HERE/verify-debounce.c" -I"$WORK"
"$WORK/t"
