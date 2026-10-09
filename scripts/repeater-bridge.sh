#!/bin/sh
# Part C - configure a DD-WRT Netgear R8000 as a Repeater Bridge via nvram.
#
# RUNS ON THE ROUTER (BusyBox ash, POSIX sh only). Normally delivered over SSH
# by scripts/push-config.sh, which also copies config.env to /tmp/bridge.env.
#
#   sh repeater-bridge.sh            dry run: verify keys, print the full plan
#   sh repeater-bridge.sh --commit   apply with nvram set + nvram commit
#   sh repeater-bridge.sh --commit --reboot   ...and reboot afterwards
#
# Settings come from /tmp/bridge.env (or the environment). See config.env.example.
set -u

COMMIT=0; REBOOT=0
for a in "$@"; do
  case "$a" in
    --commit) COMMIT=1 ;;
    --reboot) REBOOT=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

[ -f /tmp/bridge.env ] && . /tmp/bridge.env

RADIO="${RADIO:-wl0}"
EERO_SEC="${EERO_SEC:-psk2}"
EXT_SSID="${EXT_SSID:-Office-Ext}"
LAN_IP="${LAN_IP:-192.168.4.2}"
LAN_MASK="${LAN_MASK:-255.255.255.0}"
GATEWAY="${GATEWAY:-192.168.4.1}"
DNS="${DNS:-$GATEWAY}"
VIF="${RADIO}.1"

fail() { echo "ERROR: $*" >&2; exit 1; }
for v in EERO_SSID EERO_PSK EXT_PSK; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || fail "$v is not set (fill in config.env)"
done
[ ${#EERO_PSK} -ge 8 ] || fail "EERO_PSK must be at least 8 characters"
[ ${#EXT_PSK} -ge 8 ] || fail "EXT_PSK must be at least 8 characters"
command -v nvram >/dev/null 2>&1 || fail "nvram not found - is this really DD-WRT?"

echo "== Router =="
echo "firmware : $(nvram get os_version 2>/dev/null)  (build $(nvram get DD_BOARD 2>/dev/null) / $(nvram get os_date 2>/dev/null))"
echo "LAN now  : $(nvram get lan_ipaddr) / $(nvram get lan_netmask)   wan_proto=$(nvram get wan_proto)"
echo

# Ask the driver which band an interface is (wl bands: a = 5 GHz, b = 2.4 GHz).
# nvram wlN_nband is not reliable on fresh R8000 defaults (reads 1 on all radios).
radio_band() {
  case "$(wl -i "$1" bands 2>/dev/null)" in
    *a*) echo "5 GHz" ;; *b*) echo "2.4 GHz" ;; *) echo "band ?" ;;
  esac
}

echo "== Radios on this build =="
NV="$(nvram show 2>/dev/null)"
for r in wl0 wl1 wl2; do
  ifn="$(nvram get ${r}_ifname)"
  [ -n "$ifn" ] || continue
  band="$(radio_band "$ifn")"
  printf '  %s -> %-5s %-8s mode=%-9s ssid=%s\n' "$r" "$ifn" "$band" "$(nvram get ${r}_mode)" "$(nvram get ${r}_ssid)"
done
IFNAME="$(nvram get ${RADIO}_ifname)"
[ -n "$IFNAME" ] || fail "radio $RADIO does not exist on this build (no ${RADIO}_ifname)"
RBAND="$(radio_band "$IFNAME")"
echo "Bridge radio: $RADIO = $IFNAME, $RBAND"
[ "$RBAND" = "5 GHz" ] || echo "NOTE: $RADIO is not a 5 GHz radio. Fine only if you chose 2.4 GHz on purpose."
echo

# --- Confirm the variable names exist in this build's defaults -----------------
echo "== Checking nvram key names against this build =="
missing=0
for k in mode ssid security_mode akm crypto wpa_psk channel net_mode; do
  if printf '%s\n' "$NV" | grep -q "^${RADIO}_${k}="; then
    printf '  ok      %s_%s\n' "$RADIO" "$k"
  else
    printf '  MISSING %s_%s\n' "$RADIO" "$k"; missing=$((missing+1))
  fi
done
for k in lan_ipaddr lan_netmask lan_gateway lan_proto wan_proto filter; do
  if printf '%s\n' "$NV" | grep -q "^${k}="; then printf '  ok      %s\n' "$k"
  else printf '  MISSING %s\n' "$k"; missing=$((missing+1)); fi
done
if printf '%s\n' "$NV" | grep -q "^${RADIO}_vifs="; then
  echo "  ok      ${RADIO}_vifs (currently: '$(nvram get ${RADIO}_vifs)')"
else
  echo "  note    ${RADIO}_vifs not present yet - normal on fresh defaults, it is created when a virtual AP is added"
fi
echo "  note    ${VIF}_* keys are created by this script; they do not exist on fresh defaults"
for k in ${RADIO}_bridged sv_localdns; do
  printf '%s\n' "$NV" | grep -q "^${k}=" || echo "  note    $k not present yet - only stored once saved, created by this script"
done
if [ "$missing" -gt 0 ]; then
  echo
  echo "$missing expected key(s) are missing on this build. Variable names differ by revision;"
  echo "run 'nvram show | grep ^${RADIO}_ | sort' and adjust this script before committing."
  [ "$COMMIT" -eq 1 ] && fail "refusing to commit with missing keys"
fi
echo

# --- The plan ---------------------------------------------------------------------
# DD-WRT wireless modes: ap, sta (client), wet (client bridge), apsta (repeater),
# apstawet (repeater bridge). We want apstawet.
PLAN="
${RADIO}_mode=apstawet
${RADIO}_ssid=${EERO_SSID}
${RADIO}_security_mode=${EERO_SEC}
${RADIO}_akm=${EERO_SEC}
${RADIO}_crypto=aes
${RADIO}_wpa_psk=${EERO_PSK}
${RADIO}_channel=0
${RADIO}_bridged=1
${RADIO}_vifs=${VIF}
${VIF}_ssid=${EXT_SSID}
${VIF}_mode=ap
${VIF}_security_mode=psk2
${VIF}_akm=psk2
${VIF}_crypto=aes
${VIF}_wpa_psk=${EXT_PSK}
${VIF}_bridged=1
${VIF}_closed=0
${VIF}_ap_isolate=0
${VIF}_macmode=disabled
lan_ipaddr=${LAN_IP}
lan_netmask=${LAN_MASK}
lan_gateway=${GATEWAY}
sv_localdns=${DNS}
lan_proto=static
wan_proto=disabled
filter=off
"

echo "== Planned nvram changes (radio $RADIO = $IFNAME) =="
printf '%s\n' "$PLAN" | sed '/^$/d' | while IFS= read -r line; do
  key="${line%%=*}"
  case "$key" in *wpa_psk) echo "  nvram set $key=********" ;; *) echo "  nvram set $line" ;; esac
done
echo "  nvram commit"
echo
echo "Notes:"
echo "  - lan_proto=static turns the R8000's DHCP server OFF; the Eero hands out addresses."
echo "  - wan_proto=disabled: no WAN in repeater-bridge mode; the WAN port stays empty."
echo "  - filter=off disables the SPI firewall, required for bridged traffic to flow."
echo "  - ${RADIO}_channel=0: the bridge follows whatever channel the Eero is on."

if [ "$COMMIT" -ne 1 ]; then
  echo
  echo "DRY RUN - nothing written. Re-run with --commit to apply."
  exit 0
fi

echo
echo "== Applying =="
printf '%s\n' "$PLAN" | sed '/^$/d' | while IFS= read -r line; do
  key="${line%%=*}"; val="${line#*=}"
  nvram set "$key=$val" || { echo "nvram set $key failed" >&2; exit 1; }
done || fail "aborted during nvram set (nothing committed)"
nvram commit || fail "nvram commit failed"
echo "nvram committed."
echo
echo "The router's LAN IP is now $LAN_IP (takes effect after restart)."
echo "Wired laptop: give it a static IP on $GATEWAY's subnet (e.g. 192.168.4.50/24) to reach it again."
if [ "$REBOOT" -eq 1 ]; then
  echo "Rebooting..."; sleep 1; reboot
else
  echo "Now power-cycle the R8000: off ~30 s, back on. (A normal power cycle - NEVER 30-30-30.)"
fi
