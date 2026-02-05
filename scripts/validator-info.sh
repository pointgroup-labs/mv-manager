#!/bin/bash
set -euo pipefail

INV="inventory/local.yml"
HOST_FILTER="${1:-}"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; D='\033[2m'; N='\033[0m'

get_hosts() {
    local filter='.value.type == "validator"'
    [ -n "$HOST_FILTER" ] && filter="$filter and .key == \"$HOST_FILTER\""
    ansible-inventory -i "$INV" --list 2>/dev/null | \
        jq -r "._meta.hostvars | to_entries | map(select($filter)) | .[] | \"\(.key)|\(.value.ansible_host)\""
}

for entry in $(get_hosts); do
    NAME=$(echo "$entry" | cut -d'|' -f1)
    IP=$(echo "$entry" | cut -d'|' -f2)

    echo -e "\n${C}[$NAME]${N} ${D}$IP${N}"

    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "root@$IP" bash -s << 'EOF' 2>/dev/null || echo -e "  ${R}connection failed${N}"
G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; D='\033[2m'; N='\033[0m'
HOME="/opt/monad-consensus"
LOG="$HOME/log/monad-consensus.log"

# Services
cons=$(systemctl is-active monad-consensus 2>/dev/null || echo "inactive")
exec=$(systemctl is-active monad-execution 2>/dev/null || echo "inactive")
[ "$cons" = "active" ] && cs="${G}●${N}" || cs="${R}●${N}"
[ "$exec" = "active" ] && es="${G}●${N}" || es="${R}●${N}"
echo -e "  Services:  $cs consensus  $es execution"

# Block
block=$(grep '"committed block"' "$LOG" 2>/dev/null | tail -1 | sed 's/.*block_num"://; s/},.*//')
[ -n "$block" ] && echo -e "  Block:     ${C}$block${N}" || echo -e "  Block:     ${Y}syncing...${N}"

# Keys
secp=$(cat "$HOME/key/id-secp.pub" 2>/dev/null)
bls=$(cat "$HOME/key/id-bls.pub" 2>/dev/null)
[ -n "$secp" ] && echo -e "  SECP:      ${D}${secp}${N}"
[ -n "$bls" ] && echo -e "  BLS:       ${D}${bls}${N}"

# Resources
disk=$(df -h / 2>/dev/null | awk 'NR==2{print $3"/"$2" ("$5")"}')
mem=$(free -h 2>/dev/null | awk '/Mem:/{print $3"/"$2}')
echo -e "  Disk:      $disk"
echo -e "  Memory:    $mem"

# Uptime
since=$(systemctl show monad-consensus -p ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
[ -n "$since" ] && echo -e "  Since:     ${D}$since${N}"
EOF
done

echo ""
