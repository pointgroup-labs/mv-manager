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

HOME="/home/monad"
LOG="$HOME/log/monad-consensus.log"
RPC_PORT="${1:-8002}"
VAL_ID="${2:-}"
NODE_NAME="${3:-}"
NODE_IP="${4:-}"
RPC_URL="http://localhost:${RPC_PORT}"

rpc() {
    curl -s --connect-timeout 3 -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":[$2],\"id\":1}" 2>/dev/null | jq -r '.result // empty' 2>/dev/null
}

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

format_mon() {
    local wei="$1"
    local mon=$(echo "$wei" | grep -oP '^\d+' | awk '{printf "%.2f", $1/1e18}')
    local int_part=$(echo "$mon" | cut -d. -f1)
    local dec_part=$(echo "$mon" | cut -d. -f2)
    local fmt=$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$int_part" 2>/dev/null || echo "$int_part")
    [ "$dec_part" = "00" ] && echo "$fmt" || echo "${fmt}.${dec_part}"
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

chain_hex=$(rpc "eth_chainId" "")
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

block_hex=$(rpc "eth_blockNumber" "")

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

    # Block time: average over last 10 blocks
    if [ "$block" -gt 10 ]; then
        b_prev=$(printf "0x%x" $((block - 10)))
        t_now=$(curl -s --connect-timeout 3 -X POST "$RPC_URL" \
          -H "Content-Type: application/json" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$block_hex\",false],\"id\":1}" 2>/dev/null \
          | jq -r '.result.timestamp // empty' 2>/dev/null) || t_now=""
        t_prev=$(curl -s --connect-timeout 3 -X POST "$RPC_URL" \
          -H "Content-Type: application/json" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$b_prev\",false],\"id\":1}" 2>/dev/null \
          | jq -r '.result.timestamp // empty' 2>/dev/null) || t_prev=""
        if [ -n "$t_now" ] && [ -n "$t_prev" ]; then
            diff_ms=$(( ($(printf "%d" "$t_now") - $(printf "%d" "$t_prev")) * 1000 / 10 ))
            if [ "$diff_ms" -ge 1000 ]; then
                printf "  ${D}Blk time${N} %d.%ds\n" "$((diff_ms / 1000))" "$(( (diff_ms % 1000) / 100 ))"
            else
                printf "  ${D}Blk time${N} %dms\n" "$diff_ms"
            fi
        fi
    fi
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

# ── Consensus ────────────────────────────────────────────

if [ -f "$LOG" ]; then
    echo ""
    log_tail=$(tail -5000 "$LOG" 2>/dev/null) || log_tail=""

    if [ -n "$log_tail" ]; then
        # Epoch & round
        epoch=$(echo "$log_tail" | grep -oP '"epoch":"?\K\d+' | tail -1) || epoch=""
        round=$(echo "$log_tail" | grep -oP '"round":"?\K\d+' | tail -1) || round=""
        [ -n "$epoch" ] && printf "  ${D}Epoch${N}    %s\n" "$epoch"
        [ -n "$round" ] && printf "  ${D}Round${N}    %s\n" "$(format_number "$round")"

        # Skipped rounds: measured from recent log window
        first_commit=$(echo "$log_tail" | grep "committing block proposed" | head -1) || first_commit=""
        last_commit=$(echo "$log_tail" | grep "committing block proposed" | tail -1) || last_commit=""
        if [ -n "$first_commit" ] && [ -n "$last_commit" ]; then
            first_r=$(echo "$first_commit" | grep -oP 'block_round":"?\K\d+') || first_r=""
            last_r=$(echo "$last_commit" | grep -oP 'block_round":"?\K\d+') || last_r=""
            first_s=$(echo "$first_commit" | grep -oP 'seq_num":"?\K\d+') || first_s=""
            last_s=$(echo "$last_commit" | grep -oP 'seq_num":"?\K\d+') || last_s=""
            if [ -n "$first_r" ] && [ -n "$last_r" ] && [ -n "$first_s" ] && [ -n "$last_s" ]; then
                round_span=$((last_r - first_r))
                block_span=$((last_s - first_s))
                if [ "$round_span" -gt 0 ]; then
                    skipped=$((round_span - block_span))
                    skip_pct=$((skipped * 100 / round_span))
                    if [ "$skip_pct" -le 1 ]; then
                        skip_color="$G"
                    elif [ "$skip_pct" -le 5 ]; then
                        skip_color="$Y"
                    else
                        skip_color="$R"
                    fi
                    printf "  ${D}Skipped${N}  ${skip_color}%s${N}/%s rounds ${D}(%s%%)${N}\n" \
                        "$(format_number "$skipped")" "$(format_number "$round_span")" "$skip_pct"
                fi
            fi
        fi

        # Voting: our votes vs rounds seen
        votes=$(echo "$log_tail" | grep -c "vote successful") || votes=0
        rounds=$(echo "$log_tail" | grep -c "advancing round") || rounds=0
        if [ "$rounds" -gt 0 ]; then
            vote_pct=$((votes * 100 / rounds))
            if [ "$vote_pct" -ge 95 ]; then
                vote_color="$G"
            elif [ "$vote_pct" -ge 80 ]; then
                vote_color="$Y"
            else
                vote_color="$R"
            fi
            printf "  ${D}Voting${N}   ${vote_color}${B}%d%%${N} ${D}(%d/%d rounds)${N}\n" "$vote_pct" "$votes" "$rounds"
        fi

        # Network participation from QC signers bitvec
        signer_line=$(echo "$log_tail" | grep "advancing round" | tail -1) || signer_line=""
        if [ -n "$signer_line" ]; then
            total_bits=$(echo "$signer_line" | grep -oP 'bits: \K\d+' | head -1) || total_bits=""
            if [ -n "$total_bits" ] && [ "$total_bits" -gt 0 ]; then
                ones=$(echo "$signer_line" | grep -oP '\[[\d, ]+\]' | head -1 | tr -cd '1' | wc -c) || ones=0
                net_pct=$((ones * 100 / total_bits))
                if [ "$net_pct" -ge 67 ]; then
                    net_color="$G"
                elif [ "$net_pct" -ge 50 ]; then
                    net_color="$Y"
                else
                    net_color="$R"
                fi
                printf "  ${D}Network${N}  ${net_color}%d/%d signers${N} ${D}(%d%%)${N}\n" "$ones" "$total_bits" "$net_pct"
            fi
        fi

        # Peers from keepalive packets
        peers=$(echo "$log_tail" | grep -oP 'remote_addr":"\K[^:]+' | sort -u | wc -l) || peers=0
        [ "$peers" -gt 0 ] && printf "  ${D}Peers${N}    %d\n" "$peers"

        # Proposals (we were leader)
        proposals=$(echo "$log_tail" | grep -c "proposal stats") || proposals=0
        [ "$proposals" -gt 0 ] && printf "  ${D}Proposed${N} %d blocks\n" "$proposals"
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
            printf "  ${D}Stake${N}      ${G}${B}%s MON${N}\n" "$(format_mon "$stake")"
        else
            printf "  ${D}Stake${N}      ${R}none${N}\n"
        fi
        rewards=$(echo "$staking_output" | grep "Unclaimed Rewards" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        if [ -n "$rewards" ] && [ "$rewards" != "0 wei" ]; then
            printf "  ${D}Rewards${N}    ${Y}${B}%s MON${N}\n" "$(format_mon "$rewards")"
        else
            printf "  ${D}Rewards${N}    0 MON\n"
        fi
        commission=$(echo "$staking_output" | grep "Execution View: Commission" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        [ -n "$commission" ] && printf "  ${D}Commission${N} %s\n" "$commission"
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
    [ -n "$secp" ] && printf "  ${D}SECP  ${secp}${N}\n"
    [ -n "$bls" ] && printf "  ${D}BLS   ${bls}${N}\n"
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
