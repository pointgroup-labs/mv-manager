#!/bin/bash
# Bootstrap a new validator host: generates keys and funded wallet, writes
# a vault file (plaintext by default; encrypt later with ansible-vault), and
# prints the inventory snippet to paste.
#
# Usage: make bootstrap NAME=<name>  (e.g. NAME=kiwi-testnet)

set -euo pipefail

NAME="${NAME:?NAME= required, e.g. NAME=kiwi-testnet}"

# Derive env from name suffix (foo-testnet / foo-mainnet). Override with ENV=.
if [ -z "${ENV:-}" ]; then
    case "$NAME" in
        *-mainnet) ENV=mainnet ;;
        *-testnet) ENV=testnet ;;
        *) echo "error: cannot infer ENV from NAME=$NAME; pass ENV=testnet|mainnet" >&2; exit 1 ;;
    esac
fi

INV="inventory/$ENV.yml"
DIR="inventory/host_vars/$NAME"

# Preflight
[ -f "$INV" ] || { echo "error: $INV not found" >&2; exit 1; }
[ -e "$DIR" ] && { echo "error: $DIR already exists; refusing to overwrite" >&2; exit 1; }
command -v openssl >/dev/null || { echo "error: openssl not found" >&2; exit 1; }
command -v jq      >/dev/null || { echo "error: jq not found"      >&2; exit 1; }

# Wallet generation: prefer foundry's cast, fall back to python eth_account.
gen_wallet() {
    if command -v cast >/dev/null; then
        cast wallet new --json | jq -r '.[0] | "\(.private_key) \(.address)"'
    elif command -v python3 >/dev/null && python3 -c 'import eth_account' 2>/dev/null; then
        python3 -c '
from eth_account import Account
a = Account.create()
print(a.key.hex(), a.address)
'
    else
        echo "error: need either foundry cast or python3 with eth_account" >&2
        exit 1
    fi
}

umask 077
mkdir -p "$DIR"

SECP_IKM=$(openssl rand -hex 32)
BLS_IKM=$(openssl rand -hex 32)
PASS=$(openssl rand -base64 32)
read -r PRIV ADDR < <(gen_wallet)
[[ "$PRIV" == 0x* ]] || PRIV="0x$PRIV"

cat > "$DIR/vault.yml" <<EOF
---
# IKM (used to regenerate keystores if needed)
vault_secp_ikm: "$SECP_IKM"
vault_bls_ikm: "$BLS_IKM"

# On-chain addresses
vault_auth_address: "$ADDR"
vault_beneficiary_address: "$ADDR"

# Keystore password
vault_keystore_password: "$PASS"

# Funded wallet used to fund the staking tx (100k+ MON)
vault_funded_wallet_private_key: "$PRIV"
EOF

unset SECP_IKM BLS_IKM PASS PRIV

cat <<EOF

Vault written (plaintext): $DIR/vault.yml

Next steps:

  1. Fund this address with 100k+ MON on $ENV:
       $ADDR

  2. Add the host to $INV under validators.hosts:

       $NAME:
         ansible_host: "<IP>"
         type: validator

  3. Deploy:
       make deploy NODE=$NAME $([ "$ENV" != testnet ] && echo "ENV=$ENV")

  4. After the node syncs, register on-chain:
       make register NODE=$NAME $([ "$ENV" != testnet ] && echo "ENV=$ENV")

  5. Before committing, encrypt the vault:
       ansible-vault encrypt $DIR/vault.yml
EOF
