#!/bin/sh
# "The bridge won't connect" - dump everything relevant (runs on the router).
#
#   ssh root@<router-ip> 'sh -s' < scripts/diagnose.sh
#   ssh root@<router-ip> 'sh -s -- --radio wl2' < scripts/diagnose.sh
#
# Prints the radio's nvram config (passwords masked), whether the R8000 can even
# see the Eero in a scan, the LAN/WAN settings, and gateway reachability.
set -u
RADIO="${RADIO:-wl1}"
while [ $# -gt 0 ]; do
  case "$1" in --radio) RADIO="$2"; shift ;; esac; shift
done
IF="$(nvram get ${RADIO}_ifname 2>/dev/null)"; [ -n "$IF" ] || IF="$RADIO"
TARGET="$(nvram get ${RADIO}_ssid)"

echo "== nvram: $RADIO and $RADIO.1 =="
nvram show 2>/dev/null | grep -E "^${RADIO}(\.1)?_" | sort | sed -E 's/^(.*wpa_psk=).*/\1********/'
echo
echo "== nvram: LAN / WAN / firewall =="
for k in lan_ipaddr lan_netmask lan_gateway lan_proto sv_localdns wan_proto filter; do
  echo "$k=$(nvram get $k)"
done
echo
echo "== interface $IF status =="
wl -i "$IF" status 2>&1
echo
echo "== scanning for '$TARGET' on $IF (takes a few seconds) =="
wl -i "$IF" scan >/dev/null 2>&1; sleep 4
res="$(wl -i "$IF" scanresults 2>&1)"
if printf '%s\n' "$res" | grep -q "SSID: \"$TARGET\""; then
  echo "Eero SSID is visible from this radio:"
  printf '%s\n' "$res" | grep -A6 "SSID: \"$TARGET\"" | grep -E 'SSID|RSSI|Channel|Chanspec|BSSID'
else
  echo "Eero SSID '$TARGET' NOT seen on $IF. Either wrong band for this SSID, out of range,"
  echo "or a typo in the bridged SSID. All SSIDs seen:"
  printf '%s\n' "$res" | grep '^SSID:' | sort -u
fi
echo
echo "== bridge / routing =="
brctl show 2>/dev/null
ifconfig br0 2>/dev/null | grep 'inet addr'
ip route 2>/dev/null || route -n 2>/dev/null
gw="$(nvram get lan_gateway)"
if ping -c 2 -W 2 "$gw" >/dev/null 2>&1; then echo "gateway $gw: reachable"
else echo "gateway $gw: NOT reachable"; fi
if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then echo "internet: reachable"
else echo "internet: NOT reachable"; fi
