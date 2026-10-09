#!/bin/sh
# Part D - pull bridge link stats from the R8000 (runs on the router).
#
#   ssh root@192.168.4.2 'sh -s' < scripts/link-stats.sh
#   ssh root@192.168.4.2 'sh -s -- --watch 5' < scripts/link-stats.sh   # repeat every 5 s
#
# Compare RSSI (closer to 0 is better; -60 good, -70 ok, -80 poor) and the
# negotiated rate at each candidate position, not the bars on your phone.
set -u
RADIO="${RADIO:-wl1}"; WATCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --radio) RADIO="$2"; shift ;;
    --watch) WATCH="$2"; shift ;;
  esac; shift
done
IF="$(nvram get ${RADIO}_ifname 2>/dev/null)"; [ -n "$IF" ] || IF="$RADIO"

once() {
  echo "=== $(date '+%H:%M:%S')  $RADIO ($IF)  mode=$(nvram get ${RADIO}_mode) ==="
  echo "-- upstream link to the Eero --"
  echo "status   : $(wl -i "$IF" status 2>&1 | sed -n '1,2p' | tr '\n' ' ')"
  echo "rssi     : $(wl -i "$IF" rssi 2>&1) dBm"
  echo "noise    : $(wl -i "$IF" noise 2>&1) dBm"
  echo "rate     : $(wl -i "$IF" rate 2>&1)"
  echo "nrate    : $(wl -i "$IF" nrate 2>&1)"
  echo "channel  : $(wl -i "$IF" chanspec 2>&1)"
  echo "-- clients on the virtual AP ($RADIO.1) --"
  wl -i "$IF" assoclist 2>&1
  echo "-- bridge --"
  ifconfig br0 2>/dev/null | grep 'inet addr' | sed 's/^ *//'
  gw="$(nvram get lan_gateway)"
  if ping -c 1 -W 2 "$gw" >/dev/null 2>&1; then echo "gateway $gw: reachable"
  else echo "gateway $gw: NOT reachable"; fi
  echo
}
if [ "$WATCH" -gt 0 ] 2>/dev/null; then
  while :; do once; sleep "$WATCH"; done
else
  once
fi
