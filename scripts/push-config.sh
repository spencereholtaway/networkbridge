#!/usr/bin/env bash
# Deliver Part C to the router over SSH (runs on your laptop).
#
#   scripts/push-config.sh             dry run on the router: verify keys, print the plan
#   scripts/push-config.sh --commit    apply the plan (nvram set + commit)
#   scripts/push-config.sh --commit --reboot
#
# Reads ./config.env (copy config.env.example) and streams it, followed by
# repeater-bridge.sh, into one SSH session (one password prompt). Nothing is
# written to the router except the nvram settings themselves.
#
# Equivalent by hand:  cat config.env scripts/repeater-bridge.sh | ssh root@192.168.1.1 sh -s
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/config.env"
[[ -f "$ENV_FILE" ]] || { echo "config.env not found - cp config.env.example config.env and fill it in" >&2; exit 1; }
# shellcheck disable=SC1090
ROUTER_IP="$(. "$ENV_FILE"; printf '%s' "${ROUTER_IP:-192.168.1.1}")"

echo "Running repeater-bridge.sh ${*:-(dry run)} on root@$ROUTER_IP" >&2
cat "$ENV_FILE" "$ROOT/scripts/repeater-bridge.sh" | ssh "root@$ROUTER_IP" "sh -s -- $*"
