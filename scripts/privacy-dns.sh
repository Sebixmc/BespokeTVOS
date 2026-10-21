#!/usr/bin/env bash
# Usage: scripts/privacy-dns.sh [on|off|status|test]
# Points the TV's Private DNS (DNS-over-TLS) at AdGuard DNS, which blocks Amazon device metrics, ads and analytics.
# Only the TV changes, not the router. `off` restores Fire OS's default (automatic).
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${ANDROID_SERIAL:-}" ]; then
  ip=$(tr -d '[:space:]' < my-tv/tv-ip.txt 2>/dev/null)
  [ -n "$ip" ] || { echo "Put your TV's IP address in my-tv/tv-ip.txt (or set ANDROID_SERIAL)."; exit 1; }
  export ANDROID_SERIAL="$ip:5555"
fi
HOST="${PRIVATE_DNS_HOST:-dns.adguard-dns.com}"
nc -z -G 3 "${ANDROID_SERIAL%:*}" 5555 2>/dev/null || { echo "TV not reachable at $ANDROID_SERIAL (is it on, with ADB debugging ON?)"; exit 1; }
adb connect "$ANDROID_SERIAL" >/dev/null 2>&1
[ "$(adb get-state 2>/dev/null)" = device ] || { echo "TV not reachable at $ANDROID_SERIAL"; exit 1; }

resolve() { adb shell "ping -c1 -W2 $1 2>&1 | head -1" | tr -d '\r' | sed -E 's/^PING [^ ]+ \(([0-9.]+)\).*/\1/; s/^ping: .*/unresolved/'; }

case "${1:-status}" in
  on)  adb shell settings put global private_dns_specifier "$HOST"
       adb shell settings put global private_dns_mode hostname
       echo "Private DNS -> $HOST" ;;
  off) adb shell settings put global private_dns_mode opportunistic
       adb shell settings delete global private_dns_specifier >/dev/null
       echo "Private DNS -> automatic (default)" ;;
  status) echo "mode=$(adb shell settings get global private_dns_mode | tr -d '\r') host=$(adb shell settings get global private_dns_specifier | tr -d '\r')" ;;
  test)
    echo "-- should be blocked (0.0.0.0) --"
    for d in device-metrics-us.amazon.com device-metrics-us-2.amazon.com mads.amazon.com aax-us-east.amazon-adsystem.com mobileanalytics.us-east-1.amazonaws.com; do printf "  %-44s %s\n" "$d" "$(resolve $d)"; done
    echo "-- must resolve --"
    for d in api.amazon.com atv-ps.amazon.com mas-ext.amazon.com avs-alexa-19-na.amazon.com www.netflix.com www.hulu.com tv.apple.com; do printf "  %-44s %s\n" "$d" "$(resolve $d)"; done ;;
  *) echo "usage: $0 [on|off|status|test]"; exit 2 ;;
esac
