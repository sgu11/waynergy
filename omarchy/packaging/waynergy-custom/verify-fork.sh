#!/usr/bin/env bash
# Run after makepkg: use the actual prepared sources and generated headers.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
SRC="$(realpath "${1:-$HERE/src/waynergy-0.0.17}")"
WORK="$(mktemp -d -t waynergy-fork-check.XXXXXX)"
# Leave these disposable test artifacts to OS-managed temporary cleanup.
for spec in 'cleanup:cleanup' 'sig_handle:sig-handle' 'sigWaitSIGCHLD:sig-wait'; do
  func="${spec%%:*}"
  output="${spec#*:}"
  sed -n "/^\(static \)\?void $func(/,/^}/p" "$SRC/src/sig.c" > "$WORK/$output.inc"
  test -s "$WORK/$output.inc"
done
sed -n '/^static void syn_screensaver_cb(/,/^}/p' "$SRC/src/main.c" > "$WORK/screensaver.inc"
test -s "$WORK/screensaver.inc"
mkdir "$WORK/config"
printf '[screensaver]\nstart=true\nstop=true\n' > "$WORK/config/config.ini"
cc -D_GNU_SOURCE -DUSYNERGY_LITTLE_ENDIAN -g -O2 \
  -I"$WORK" -I"$SRC/include" -I"$SRC/build/waynergy.p" \
  "$HERE/verify-fork.c" "$SRC/src/uSynergy.c" "$SRC/src/ssp.c" \
  "$SRC/src/os.c" "$SRC/src/config.c" "$SRC/src/log.c" -o "$WORK/verify-fork"
"$WORK/verify-fork" "$WORK/config" > "$WORK/result.log" 2>&1 || {
  cat "$WORK/result.log"
  exit 1
}
cat "$WORK/result.log"
test "$(grep -c 'Screensaver callback state start command #0 completed' "$WORK/result.log")" -eq 2
test "$(grep -c 'Screensaver callback state stop command #0 completed' "$WORK/result.log")" -eq 1
if grep -Eq 'failed with code|Parsing Error|Unknown packet' "$WORK/result.log"; then
  exit 1
fi

# Upstream's run.sh only prints failures; invoke each test directly so its
# exit status is a verification gate.
cc -D_GNU_SOURCE -DWAYNERGY_TEST -g -I"$SRC/include" \
  "$SRC/test/os.c" "$SRC/src/os.c" "$SRC/src/log.c" -o "$WORK/test-os"
"$WORK/test-os"
cc -D_GNU_SOURCE -DWAYNERGY_TEST -g -I"$SRC/include" \
  "$SRC/test/config.c" "$SRC/src/os.c" "$SRC/src/log.c" \
  "$SRC/src/config.c" -o "$WORK/test-config"
(cd "$SRC/test" && "$WORK/test-config")
