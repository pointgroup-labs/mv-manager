#!/bin/bash
set -euo pipefail

INV="${INV:-inventory/local.yml}"
NODE="${1:-}"
LIMIT="${NODE:+--limit $NODE}"

header() { echo -e "\n\033[1;36m=== $1 ===\033[0m"; }

header "CPU"
ansible -i "$INV" $LIMIT validators -m shell -a '
  lscpu | grep -E "Model name|^CPU\(s\):|Thread|Core|Socket|MHz|Cache"
' 2>/dev/null | grep -v "CHANGED\|SUCCESS"

header "Memory"
ansible -i "$INV" $LIMIT validators -m shell -a '
  free -h | head -2
' 2>/dev/null | grep -v "CHANGED\|SUCCESS"

header "Storage"
ansible -i "$INV" $LIMIT validators -m shell -a '
  lsblk -d -o NAME,SIZE,ROTA,TRAN,MODEL | grep -v loop
' 2>/dev/null | grep -v "CHANGED\|SUCCESS"

header "NVMe Details"
ansible -i "$INV" $LIMIT validators -m shell -a '
  for dev in /dev/nvme?; do
    smartctl -i "$dev" 2>/dev/null | grep -E "Model Number|Total NVM Capacity" || true
  done
' 2>/dev/null | grep -v "CHANGED\|SUCCESS"

header "Disk Usage"
ansible -i "$INV" $LIMIT validators -m shell -a '
  df -h | grep -E "^/dev|Filesystem" | grep -v loop
' 2>/dev/null | grep -v "CHANGED\|SUCCESS"
