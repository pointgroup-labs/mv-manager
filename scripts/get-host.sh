#!/bin/bash
# Get first matching validator IP

ENV_FILTER="${1:-}"
HOST_FILTER="${2:-}"
INV="${MONAD_INV:-inventory/testnet.yml}"

jq_filter='true'
[ -n "$ENV_FILTER" ] && jq_filter="$jq_filter and .value.env == \"$ENV_FILTER\""
[ -n "$HOST_FILTER" ] && jq_filter="$jq_filter and .key == \"$HOST_FILTER\""

ansible-inventory -i "$INV" --list 2>/dev/null | \
    jq -r "._meta.hostvars | to_entries | map(select($jq_filter)) | .[0].value.ansible_host // empty"
