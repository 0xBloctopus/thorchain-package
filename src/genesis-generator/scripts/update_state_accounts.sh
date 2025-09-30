#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
BOND_MODULE_ACCOUNT_FILE="/tmp/bond_module_account.json"
TEMP_FILE="/tmp/genesis_temp.json"

if ! jq -e '.app_state.state' "$GENESIS_FILE" > /dev/null 2>&1; then
    jq '.app_state.state = {}' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"
fi

jq --slurpfile bond_account "$BOND_MODULE_ACCOUNT_FILE" '.app_state.state.accounts = [$bond_account[0]]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Updated state.accounts with bond module account"
