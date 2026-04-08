#!/bin/bash
set -euo pipefail

INV="${MONAD_INV:-inventory/testnet.yml}"
NODE="${1:-}"
LIMIT="${NODE:+--limit $NODE}"

echo -e "\033[1;36m=== Running Speedtest ===\033[0m"
echo "(this may take 30-60 seconds)"
echo ""

ansible -i "$INV" $LIMIT validators:fullnodes -m shell -a '
  command -v speedtest-cli >/dev/null 2>&1 || pip3 install -q speedtest-cli
  speedtest-cli --simple 2>/dev/null
' 2>/dev/null | grep -v "CHANGED\|SUCCESS\|DeprecationWarning"
