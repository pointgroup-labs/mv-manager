#!/bin/bash
set -euo pipefail

INV="${MONAD_INV:-inventory/testnet.yml}"
NODE="${1:-}"
ARGS=()
[ -n "$NODE" ] && ARGS+=(--limit "$NODE")

echo -e "\033[1;36m=== Running Speedtest ===\033[0m"
echo "(this may take 30-60 seconds)"
echo ""

ansible -i "$INV" "${ARGS[@]}" validators:fullnodes -m shell -a '
  if ! command -v speedtest-cli >/dev/null 2>&1; then
    echo "speedtest-cli not installed. Install via: apt install -y speedtest-cli (managed by prepare_server role)." >&2
    exit 1
  fi
  speedtest-cli --simple 2>/dev/null
' 2>/dev/null | grep -v "CHANGED\|SUCCESS\|DeprecationWarning"
