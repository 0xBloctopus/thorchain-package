#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_ACCOUNTS_FILE="/tmp/new_accounts.json"
TEMP_FILE="/tmp/genesis_temp.json"

NEW_ACCOUNTS=$(cat "$NEW_ACCOUNTS_FILE")

echo "$NEW_ACCOUNTS" | jq -c '.[]' | while read -r account; do
    ADDRESS=$(echo "$account" | jq -r '.address')
    
    EXISTS=$(jq --arg addr "$ADDRESS" '.app_state.auth.accounts[] | select(.address == $addr) | .address' "$GENESIS_FILE")
    
    if [ -z "$EXISTS" ]; then
        jq --argjson account "$account" '.app_state.auth.accounts += [$account]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"
        echo "Added account: $ADDRESS"
    else
        echo "Account already exists, skipping: $ADDRESS"
    fi
done

echo "Finished processing accounts"
