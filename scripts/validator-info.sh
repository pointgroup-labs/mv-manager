#!/bin/bash
set -euo pipefail

INV="inventory/local.yml"
HOST_FILTER="${1:-}"
RPC_PORT=8002

G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; D='\033[2m'; B='\033[1m'; M='\033[35m'; N='\033[0m'

get_hosts() {
    local filter='.value.type == "validator"'
    [ -n "$HOST_FILTER" ] && filter="$filter and .key == \"$HOST_FILTER\""
    ansible-inventory -i "$INV" --list 2>/dev/null | \
        jq -r "._meta.hostvars | to_entries | map(select($filter)) | .[] | \"\(.key)|\(.value.ansible_host)|\(.value.validator_id // \"\")\""
}

for entry in $(get_hosts); do
    NAME=$(echo "$entry" | cut -d'|' -f1)
    IP=$(echo "$entry" | cut -d'|' -f2)
    VAL_ID=$(echo "$entry" | cut -d'|' -f3)

    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no "root@$IP" bash -s "$RPC_PORT" "$VAL_ID" "$NAME" "$IP" << 'REMOTE' 2>/dev/null || echo -e "\n  \033[31m✗ connection failed: $NAME ($IP)\033[0m"
G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'
D='\033[2m'; B='\033[1m'; M='\033[35m'; N='\033[0m'

HOME="/opt/monad-consensus"
RPC_PORT="${1:-8002}"
VAL_ID="${2:-}"
NODE_NAME="${3:-}"
NODE_IP="${4:-}"
RPC_URL="http://localhost:${RPC_PORT}"

progress_bar() {
    local used="$1" total="$2" width=20
    [ "$total" -le 0 ] 2>/dev/null && return
    local pct=$((used * 100 / total))
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local color="$G"
    [ "$pct" -ge 70 ] && color="$Y"
    [ "$pct" -ge 90 ] && color="$R"
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "${color}${bar}${N}"
}

format_number() {
    LC_NUMERIC=en_US.UTF-8 printf "%'d" "$1" 2>/dev/null || echo "$1"
}

human_uptime() {
    local secs="$1"
    if [ "$secs" -ge 86400 ]; then
        echo "$((secs / 86400))d $((secs % 86400 / 3600))h"
    elif [ "$secs" -ge 3600 ]; then
        echo "$((secs / 3600))h $((secs % 3600 / 60))m"
    else
        echo "$((secs / 60))m"
    fi
}

# ── Header ───────────────────────────────────────────────

inner=42
gap=$((inner - ${#NODE_NAME} - ${#NODE_IP}))
[ "$gap" -lt 1 ] && gap=1
printf -v pad "%${gap}s" ""
border=$(printf '─%.0s' $(seq 1 $((inner + 2))))

echo ""
echo "╭${border}╮"
printf "│ ${M}${B}%s${N}%s${D}%s${N} │\n" "$NODE_NAME" "$pad" "$NODE_IP"
echo "╰${border}╯"

# ── Services ─────────────────────────────────────────────

cons=$(systemctl is-active monad-consensus 2>/dev/null || echo "inactive")
exec_s=$(systemctl is-active monad-execution 2>/dev/null || echo "inactive")
rpc_s=$(systemctl is-active monad-rpc 2>/dev/null || echo "inactive")
[ "$cons" = "active" ] && cs="${G}●${N}" || cs="${R}●${N}"
[ "$exec_s" = "active" ] && es="${G}●${N}" || es="${R}●${N}"
[ "$rpc_s" = "active" ] && rs="${G}●${N}" || rs="${R}●${N}"

echo ""
echo -e "  $cs consensus   $es execution   $rs rpc"

# ── Node info ────────────────────────────────────────────

ver=$(monad-node --version 2>&1 | grep -oP 'tag":"v\K[^"]+' || echo "unknown")

chain_hex=$(curl -s --connect-timeout 3 -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
network="unknown"
if [ -n "$chain_hex" ]; then
    chain_id=$((chain_hex))
    case $chain_id in
        10143) network="testnet" ;;
        143)   network="mainnet" ;;
        *)     network="chain:${chain_id}" ;;
    esac
fi

echo ""
printf "  ${D}Version${N}  %-14s ${D}Network${N}  ${Y}%s${N}\n" "v${ver}" "$network"

block_hex=$(curl -s --connect-timeout 3 -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)

if [ -n "$block_hex" ]; then
    block=$((block_hex))
    block_fmt=$(format_number "$block")

    syncing=$(curl -s --connect-timeout 3 -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' 2>/dev/null | jq -r '.result' 2>/dev/null)
    if [ "$syncing" = "false" ]; then
        sync_str="${G}✓ synced${N}"
    else
        sync_str="${Y}⟳ syncing${N}"
    fi
    printf "  ${D}Block${N}    ${C}%-14s${N} ${D}Sync${N}     %b\n" "$block_fmt" "$sync_str"
else
    printf "  ${D}Block${N}    ${R}%-14s${N} ${D}Sync${N}     ${R}%s${N}\n" "unavailable" "—"
fi

since_str=$(systemctl show monad-consensus -p ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
if [ -n "$since_str" ] && [ "$since_str" != " " ]; then
    since_epoch=$(date -d "$since_str" +%s 2>/dev/null || echo "")
    if [ -n "$since_epoch" ]; then
        diff_secs=$(($(date +%s) - since_epoch))
        [ "$diff_secs" -ge 0 ] && printf "  ${D}Uptime${N}   %s\n" "$(human_uptime "$diff_secs")"
    fi
fi

# ── Staking ──────────────────────────────────────────────

if [ -n "$VAL_ID" ]; then
    echo ""
    staking_output=$(source "$HOME/staking-sdk-cli/cli-venv/bin/activate" && \
        cd "$HOME/staking-sdk-cli" && \
        python staking-cli/main.py query validator --validator-id "$VAL_ID" --config-path config.toml 2>/dev/null) || staking_output=""

    printf "  ${D}Validator${N}  ${C}${B}#${VAL_ID}${N}\n"

    if [ -n "$staking_output" ]; then
        stake=$(echo "$staking_output" | grep "Execution View: Stake" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        if [ -n "$stake" ] && [ "$stake" != "0 wei" ]; then
            stake_val=$(echo "$stake" | grep -oP '^\d+' | awk '{printf "%.0f", $1/1e18}')
            stake_fmt=$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$stake_val" 2>/dev/null || echo "$stake_val")
            printf "  ${D}Stake${N}      ${G}${B}${stake_fmt} MON${N}\n"
        else
            printf "  ${D}Stake${N}      ${R}none${N}\n"
        fi
        rewards=$(echo "$staking_output" | grep "Unclaimed Rewards" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        if [ -n "$rewards" ] && [ "$rewards" != "0 wei" ]; then
            printf "  ${D}Rewards${N}    ${Y}${B}${rewards}${N}\n"
        else
            printf "  ${D}Rewards${N}    0 MON\n"
        fi
    else
        printf "  ${D}Stake${N}      ${D}—${N}\n"
        printf "  ${D}Rewards${N}    ${D}—${N}\n"
    fi
fi

# ── Keys ─────────────────────────────────────────────────

secp=$(cat "$HOME/key/id-secp.pub" 2>/dev/null || echo "")
bls=$(cat "$HOME/key/id-bls.pub" 2>/dev/null || echo "")
if [ -n "$secp" ] || [ -n "$bls" ]; then
    echo ""
    [ -n "$secp" ] && printf "  ${D}SECP  ${secp:0:48}…${N}\n"
    [ -n "$bls" ] && printf "  ${D}BLS   ${bls:0:48}…${N}\n"
fi

# ── Resources ────────────────────────────────────────────

echo ""

disk_used_raw=$(df / 2>/dev/null | awk 'NR==2{print $3}')
disk_total_raw=$(df / 2>/dev/null | awk 'NR==2{print $2}')
disk_used_h=$(df -h / 2>/dev/null | awk 'NR==2{print $3}')
disk_total_h=$(df -h / 2>/dev/null | awk 'NR==2{print $2}')
disk_pct=$(df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
if [ -n "$disk_used_raw" ] && [ -n "$disk_total_raw" ]; then
    bar=$(progress_bar "$disk_used_raw" "$disk_total_raw")
    printf "  ${D}Disk${N}     %b  %s / %s ${D}(%s%%)${N}\n" "$bar" "$disk_used_h" "$disk_total_h" "$disk_pct"
fi

mem_used_raw=$(free 2>/dev/null | awk '/Mem:/{print $3}')
mem_total_raw=$(free 2>/dev/null | awk '/Mem:/{print $2}')
mem_used_h=$(free -h 2>/dev/null | awk '/Mem:/{print $3}')
mem_total_h=$(free -h 2>/dev/null | awk '/Mem:/{print $2}')
if [ -n "$mem_used_raw" ] && [ -n "$mem_total_raw" ]; then
    bar=$(progress_bar "$mem_used_raw" "$mem_total_raw")
    printf "  ${D}Memory${N}   %b  %s / %s\n" "$bar" "$mem_used_h" "$mem_total_h"
fi

triedb_size=$(lsblk -ndo SIZE /dev/triedb 2>/dev/null || echo "")
[ -n "$triedb_size" ] && printf "  ${D}TrieDB${N}   %s\n" "$triedb_size"
REMOTE
done

echo ""
