#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_BALANCES_FILE="/tmp/new_balances.json"
TEMP_FILE="/tmp/genesis_temp.json"

NEW_BALANCES=$(cat "$NEW_BALANCES_FILE")

echo "$NEW_BALANCES" | jq -c '.[]' | while read -r balance_entry; do
    ADDRESS=$(echo "$balance_entry" | jq -r '.address')
    COINS=$(echo "$balance_entry" | jq -c '.coins')
    
    BALANCE_INDEX=$(jq --arg addr "$ADDRESS" '[.app_state.bank.balances[] | .address] | index($addr)' "$GENESIS_FILE")
    
    if [ "$BALANCE_INDEX" != "null" ]; then
        jq --arg addr "$ADDRESS" --argjson coins "$COINS" \
           '(.app_state.bank.balances[] | select(.address == $addr) | .coins) = $coins' \
           "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"
        echo "Updated balance for: $ADDRESS"
    else
        jq --argjson balance "$balance_entry" '.app_state.bank.balances += [$balance]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"
        echo "Added balance for: $ADDRESS"
    fi
done

echo "Finished processing balances"
