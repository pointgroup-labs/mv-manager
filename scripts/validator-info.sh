#!/bin/bash
set -euo pipefail

INV="${MONAD_INV:-inventory/testnet.yml}"
HOST_FILTER="${1:-}"

G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'; D='\033[2m'; B='\033[1m'; M='\033[35m'; N='\033[0m'

get_hosts() {
    local filter='true'
    [ -n "$HOST_FILTER" ] && filter="$filter and .key == \"$HOST_FILTER\""
    ansible-inventory -i "$INV" --list 2>/dev/null | \
        jq -r "._meta.hostvars | to_entries | map(select($filter)) | .[] | \"\(.key)|\(.value.ansible_host)|\(.value.validator_id // \"\")|\(.value.type // \"validator\")\""
}

while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    NAME=$(echo "$entry" | cut -d'|' -f1)
    IP=$(echo "$entry" | cut -d'|' -f2)
    VAL_ID=$(echo "$entry" | cut -d'|' -f3)
    TYPE=$(echo "$entry" | cut -d'|' -f4)

    ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@$IP" bash -s "$TYPE" "$VAL_ID" "$NAME" "$IP" << 'REMOTE' 2>/dev/null || echo -e "\n  \033[31m✗ connection failed: $NAME ($IP)\033[0m"
G='\033[32m'; Y='\033[33m'; R='\033[31m'; C='\033[36m'
D='\033[2m'; B='\033[1m'; M='\033[35m'; N='\033[0m'

TYPE="${1:-validator}"
VAL_ID="${2:-}"
NODE_NAME="${3:-}"
NODE_IP="${4:-}"
HOME="/home/monad"
LOG="$HOME/log/monad-consensus.log"
if [ "$TYPE" = "validator" ]; then
    RPC_PORT=8002
    EXEC_SVC="monad-execution"
else
    RPC_PORT=8090
    EXEC_SVC="monad-${TYPE}-execution"
fi
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
exec_s=$(systemctl is-active "$EXEC_SVC" 2>/dev/null || echo "inactive")
rpc_s=$(systemctl is-active monad-rpc 2>/dev/null || echo "inactive")
sc_s=$(systemctl is-active fastlane-sidecar 2>/dev/null || echo "inactive")
sc_exists=$(systemctl cat fastlane-sidecar &>/dev/null && echo "yes" || echo "")
[ "$cons" = "active" ] && cs="${G}●${N}" || cs="${R}●${N}"
[ "$exec_s" = "active" ] && es="${G}●${N}" || es="${R}●${N}"
[ "$rpc_s" = "active" ] && rs="${G}●${N}" || rs="${R}●${N}"
[ "$sc_s" = "active" ] && scs="${G}●${N}" || scs="${R}●${N}"

echo ""
if [ -n "$sc_exists" ]; then
    echo -e "  $cs consensus   $es execution   $rs rpc   $scs sidecar"
else
    echo -e "  $cs consensus   $es execution   $rs rpc"
fi

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

        # Epoch remaining: 50,000 blocks/epoch × 0.4s/block ≈ 5.55h
        epoch_remaining=""
        if [ -n "$epoch" ] && [ -n "$block" ] && [ "$block" -gt 0 ]; then
            blocks_per_epoch=50000
            blocks_into=$((block % blocks_per_epoch))
            blocks_left=$((blocks_per_epoch - blocks_into))
            secs_left=$((blocks_left * 2 / 5))
            [ "$secs_left" -gt 0 ] && epoch_remaining="$(human_uptime "$secs_left")"
        fi

        if [ -n "$epoch" ]; then
            if [ -n "$epoch_remaining" ]; then
                printf "  ${D}Epoch${N}    %s  ${D}(%s remaining)${N}\n" "$epoch" "$epoch_remaining"
            else
                printf "  ${D}Epoch${N}    %s\n" "$epoch"
            fi
        fi
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
        total_stake=$(echo "$staking_output" | grep "Execution View: Stake" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        pool_rewards=$(echo "$staking_output" | grep "Unclaimed Rewards" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        commission_rate=$(echo "$staking_output" | grep "Execution View: Commission" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)
        auth_addr=$(echo "$staking_output" | grep "AuthAddress" | sed 's/.*│ *\(.*\) *│.*/\1/' | xargs)

        delegator_output=""
        if [ -n "$auth_addr" ]; then
            delegator_output=$(source "$HOME/staking-sdk-cli/cli-venv/bin/activate" && \
                cd "$HOME/staking-sdk-cli" && \
                python staking-cli/main.py query delegator --validator-id "$VAL_ID" \
                --delegator-address "$auth_addr" --config-path config.toml 2>/dev/null) || delegator_output=""
        fi

        delegators_output=$(source "$HOME/staking-sdk-cli/cli-venv/bin/activate" && \
            cd "$HOME/staking-sdk-cli" && \
            python staking-cli/main.py query delegators --validator-id "$VAL_ID" --config-path config.toml 2>/dev/null) || delegators_output=""

        total_stake_wei=$(echo "$total_stake" | grep -oP '^\d+')
        if [ -n "$total_stake" ] && [ "$total_stake" != "0 wei" ]; then
            printf "  ${D}Stake${N}      ${G}${B}%s MON${N}\n" "$(format_mon "$total_stake")"
        else
            printf "  ${D}Stake${N}      ${R}none${N}\n"
        fi

        if [ -n "$delegator_output" ]; then
            my_stake_wei=$(echo "$delegator_output" | grep "^│ Stake" | sed 's/.*│ *\(.*\) *│.*/\1/' | grep -oP '^\d+')
            if [ -n "$my_stake_wei" ] && [ "$my_stake_wei" != "0" ] && [ -n "$total_stake_wei" ] && [ "$total_stake_wei" != "0" ]; then
                ratio=$(awk "BEGIN { printf \"%.2f\", ${my_stake_wei} * 100 / ${total_stake_wei} }")
                printf "  ${D}Self-stake${N} %s MON ${D}(%s%%)${N}\n" "$(format_mon "$my_stake_wei wei")" "$ratio"
            fi
        fi

        if [ -n "$delegators_output" ]; then
            del_count=$(echo "$delegators_output" | grep -c "│.*0x" || echo "0")
            [ "$del_count" -gt 0 ] && printf "  ${D}Delegators${N} %d\n" "$del_count"
        fi

        [ -n "$commission_rate" ] && printf "  ${D}Commission${N} %s\n" "$commission_rate"

        pool_wei=$(echo "$pool_rewards" | grep -oP '^\d+')

        # MON price from CoinGecko
        mon_price=$(curl -s --connect-timeout 3 "https://api.coingecko.com/api/v3/simple/price?ids=monad&vs_currencies=usd" 2>/dev/null \
            | grep -oP '"usd":\K[\d.]+' || echo "")

        format_usd() {
            local mon_str="$1"
            if [ -n "$mon_price" ] && [ -n "$mon_str" ]; then
                local usd=$(awk "BEGIN { printf \"%.2f\", ${mon_str} * ${mon_price} }")
                local int=$(echo "$usd" | cut -d. -f1)
                local dec=$(echo "$usd" | cut -d. -f2)
                local fmt=$(LC_NUMERIC=en_US.UTF-8 printf "%'d" "$int" 2>/dev/null || echo "$int")
                echo "\$${fmt}.${dec}"
            fi
        }

        if [ -n "$delegator_output" ]; then
            my_rewards_wei=$(echo "$delegator_output" | grep "Total Rewards" | sed 's/.*│ *\(.*\) *│.*/\1/' | grep -oP '^\d+')
            if [ -n "$my_rewards_wei" ] && [ "$my_rewards_wei" != "0" ]; then
                my_rewards_mon=$(awk "BEGIN { printf \"%.2f\", ${my_rewards_wei} / 1e18 }")
                usd_str=$(format_usd "$my_rewards_mon")

                printf "  ${D}Rewards${N}    ${Y}${B}%s MON${N}" "$(format_mon "$my_rewards_wei wei")"
                [ -n "$usd_str" ] && printf "  ${D}(%s)${N}" "$usd_str"
                echo ""
            else
                printf "  ${D}Rewards${N}    0 MON\n"
            fi
        else
            if [ -n "$pool_rewards" ] && [ "$pool_rewards" != "0 wei" ]; then
                pool_mon=$(awk "BEGIN { printf \"%.2f\", ${pool_wei} / 1e18 }")
                usd_str=$(format_usd "$pool_mon")
                printf "  ${D}Rewards${N}    ${Y}${B}%s MON${N}" "$(format_mon "$pool_rewards")"
                [ -n "$usd_str" ] && printf "  ${D}(%s)${N}" "$usd_str"
                echo ""
            else
                printf "  ${D}Rewards${N}    0 MON\n"
            fi
        fi
    else
        printf "  ${D}Stake${N}      ${D}—${N}\n"
        printf "  ${D}Rewards${N}    ${D}—${N}\n"
    fi
fi

# ── MEV ─────────────────────────────────────────────────

if [ "$sc_s" = "active" ]; then
    sc_health=$(curl -s --connect-timeout 3 "http://localhost:8765/health" 2>/dev/null) || sc_health=""
    if [ -n "$sc_health" ]; then
        sc_txs=$(echo "$sc_health" | jq -r '.tx_received // empty' 2>/dev/null) || sc_txs=""
        sc_streamed=$(echo "$sc_health" | jq -r '.tx_streamed // empty' 2>/dev/null) || sc_streamed=""
        sc_last=$(echo "$sc_health" | jq -r '.last_received_at // empty' 2>/dev/null) || sc_last=""
        if [ -n "$sc_txs" ]; then
            echo ""
            mev_line="  ${D}MEV txs${N}  ${C}$(format_number "$sc_txs")${N} received"
            [ -n "$sc_streamed" ] && mev_line+="  ${C}$(format_number "$sc_streamed")${N} streamed"
            if [ -n "$sc_last" ]; then
                last_epoch=$(date -d "$sc_last" +%s 2>/dev/null || echo "")
                if [ -n "$last_epoch" ]; then
                    ago=$(( $(date +%s) - last_epoch ))
                    if [ "$ago" -ge 0 ] && [ "$ago" -lt 60 ]; then
                        mev_line+="  ${D}(last ${ago}s ago)${N}"
                    elif [ "$ago" -ge 60 ]; then
                        mev_line+="  ${D}(last $(human_uptime "$ago") ago)${N}"
                    fi
                fi
            fi
            echo -e "$mev_line"
        fi
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

triedb_size=$(lsblk -ndo SIZE /dev/triedb 2>/dev/null | xargs || echo "")
if [ -n "$triedb_size" ]; then
    triedb_real=$(readlink -f /dev/triedb 2>/dev/null || echo "")
    triedb_parent=$(echo "$triedb_real" | sed 's/p\?[0-9]*$//' | xargs -I{} basename {} 2>/dev/null || echo "")
    nvme_model="" ; nvme_temp="" ; nvme_wear="" ; nvme_health="" ; nvme_read="" ; nvme_written=""
    if [ -n "$triedb_parent" ]; then
        nvme_model=$(lsblk -ndo MODEL "/dev/$triedb_parent" 2>/dev/null | xargs)
        smart=$(nvme smart-log "/dev/$triedb_parent" 2>/dev/null) || smart=""
        if [ -n "$smart" ]; then
            nvme_temp=$(echo "$smart" | grep -i "^temperature" | head -1 | grep -oP '\d+' | head -1)
            nvme_wear=$(echo "$smart" | grep -i "percentage_used" | grep -oP '\d+' | head -1)
            read_units=$(echo "$smart" | grep -i "data_units_read" | grep -oP '[\d,]+' | head -1 | tr -d ',')
            write_units=$(echo "$smart" | grep -i "data_units_written" | grep -oP '[\d,]+' | head -1 | tr -d ',')
            [ -n "$read_units" ] && nvme_read=$(awk "BEGIN { v=$read_units*512000; if(v>=1e12) printf \"%.1fT\",v/1e12; else if(v>=1e9) printf \"%.1fG\",v/1e9; else printf \"%.0fM\",v/1e6 }")
            [ -n "$write_units" ] && nvme_written=$(awk "BEGIN { v=$write_units*512000; if(v>=1e12) printf \"%.1fT\",v/1e12; else if(v>=1e9) printf \"%.1fG\",v/1e9; else printf \"%.0fM\",v/1e6 }")
            if [ -n "$nvme_wear" ]; then
                remaining=$((100 - nvme_wear))
                if [ "$remaining" -ge 70 ]; then
                    nvme_health="${G}healthy${N}"
                elif [ "$remaining" -ge 30 ]; then
                    nvme_health="${Y}degrading${N}"
                else
                    nvme_health="${R}critical${N}"
                fi
            fi
        fi
    fi
    printf "  ${D}TrieDB${N}   %s" "$triedb_size"
    [ -n "$nvme_model" ] && printf "  ${D}%s${N}" "$nvme_model"
    echo ""
    if [ -n "$nvme_wear" ] || [ -n "$nvme_temp" ]; then
        printf "  ${D}NVMe${N}     "
        [ -n "$nvme_health" ] && printf "%b" "$nvme_health"
        [ -n "$nvme_wear" ] && printf "  ${D}life %s%%${N}" "$((100 - nvme_wear))"
        [ -n "$nvme_temp" ] && printf "  ${D}%s°C${N}" "$nvme_temp"
        [ -n "$nvme_written" ] && printf "  ${D}written %s${N}" "$nvme_written"
        echo ""
    fi
fi
REMOTE
done < <(get_hosts)

echo ""
