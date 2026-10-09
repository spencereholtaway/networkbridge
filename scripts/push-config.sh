#!/usr/bin/env bash
# Deliver Part C to the router over SSH (runs on your laptop).
#
#   scripts/push-config.sh             dry run on the router: verify keys, print the plan
#   scripts/push-config.sh --commit    apply the plan (nvram set + commit)
#   scripts/push-config.sh --commit --reboot
#
# Reads ./config.env (copy config.env.example). Copies it to the router as
# /tmp/bridge.env (RAM only, gone after reboot), then streams repeater-bridge.sh
# to the router's shell. Nothing is left on the router's flash except nvram.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/config.env"
[[ -f "$ENV_FILE" ]] || { echo "config.env not found - cp config.env.example config.env and fill it in" >&2; exit 1; }
# shellcheck disable=SC1090
ROUTER_IP="$(. "$ENV_FILE"; printf '%s' "${ROUTER_IP:-192.168.1.1}")"

echo "Copying config to root@$ROUTER_IP:/tmp/bridge.env" >&2
scp -O -q "$ENV_FILE" "root@$ROUTER_IP:/tmp/bridge.env" 2>/dev/null \
  || scp -q "$ENV_FILE" "root@$ROUTER_IP:/tmp/bridge.env"
echo "Running repeater-bridge.sh ${*:-(dry run)} on the router" >&2
ssh "root@$ROUTER_IP" "sh -s -- $*" < "$ROOT/scripts/repeater-bridge.sh"
