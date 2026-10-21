#!/usr/bin/env bash
# Usage: scripts/debloat.sh [apply|restore|status]
# Applies or undoes config/disable.txt on the TV. Every change is `pm disable-user`, which `pm enable` reverses.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${ANDROID_SERIAL:-}" ]; then
  ip=$(tr -d '[:space:]' < my-tv/tv-ip.txt 2>/dev/null)
  [ -n "$ip" ] || { echo "Put your TV's IP address in my-tv/tv-ip.txt (or set ANDROID_SERIAL)."; exit 1; }
  export ANDROID_SERIAL="$ip:5555"
fi
mode="${1:-status}"
pkgs=$(sed -E 's/#.*//; s/[[:space:]]+//g; /^$/d' config/disable.txt)

nc -z -G 3 "${ANDROID_SERIAL%:*}" 5555 2>/dev/null || { echo "TV not reachable at $ANDROID_SERIAL (is it on, with ADB debugging ON?)"; exit 1; }
adb connect "$ANDROID_SERIAL" >/dev/null 2>&1
[ "$(adb get-state 2>/dev/null)" = device ] || { echo "TV not reachable at $ANDROID_SERIAL"; exit 1; }

disabled=$(adb shell pm list packages -d | tr -d '\r' | sed 's/package://')
installed=$(adb shell pm list packages | tr -d '\r' | sed 's/package://')
ok=0; skip=0; fail=0
for p in $pkgs; do
  if ! grep -qx "$p" <<<"$installed"; then echo "  -  $p (not installed)"; skip=$((skip+1)); continue; fi
  is_off=$(grep -qx "$p" <<<"$disabled" && echo 1 || echo 0)
  case "$mode" in
    status)  [ "$is_off" = 1 ] && echo "  off $p" || echo "  ON  $p" ;;
    apply)
      if [ "$is_off" = 1 ]; then echo "  =  $p (already off)"; ok=$((ok+1)); continue; fi
      out=$(adb shell pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')
      if grep -q "new state: disabled" <<<"$out"; then echo "  ✓  $p"; ok=$((ok+1)); else echo "  ✗  $p — $out"; fail=$((fail+1)); fi ;;
    restore)
      if [ "$is_off" = 0 ]; then echo "  =  $p (already on)"; ok=$((ok+1)); continue; fi
      out=$(adb shell pm enable --user 0 "$p" 2>&1 | tr -d '\r')
      if grep -q "new state: enabled" <<<"$out"; then echo "  ✓  $p"; ok=$((ok+1)); else echo "  ✗  $p — $out"; fail=$((fail+1)); fi ;;
    *) echo "usage: $0 [apply|restore|status]"; exit 2 ;;
  esac
done
[ "$mode" != status ] && echo "done: $ok ok, $fail failed, $skip not installed"
adb shell 'grep MemAvailable /proc/meminfo'
