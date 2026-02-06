#!/bin/bash
set -euo pipefail

INV="${INV:-inventory/local.yml}"
NODE="${1:-}"
LIMIT="${NODE:+--limit $NODE}"

echo -e "\033[1;36m=== Running Speedtest ===\033[0m"
echo "(this may take 30-60 seconds)"
echo ""

ansible -i "$INV" $LIMIT validators -m shell -a '
  curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple 2>/dev/null
' 2>/dev/null | grep -v "CHANGED\|SUCCESS\|DeprecationWarning"
