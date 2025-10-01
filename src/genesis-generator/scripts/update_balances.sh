#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_BALANCES_FILE="/tmp/new_balances.json"
TEMP_FILE="/tmp/genesis_temp.json"

MAINNET_RUNE_SUPPLY=42537131234170029

jq --slurpfile new_balances "$NEW_BALANCES_FILE" '.app_state.bank.balances += $new_balances[0]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

OUR_RUNE_TOTAL=$(jq '[.[].coins[] | select(.denom == "rune") | .amount | tonumber] | add' "$NEW_BALANCES_FILE")

TOTAL_RUNE_SUPPLY=$((MAINNET_RUNE_SUPPLY + OUR_RUNE_TOTAL))

sed -i "s/\"__RUNE_SUPPLY__\"/\"$TOTAL_RUNE_SUPPLY\"/" "$GENESIS_FILE"

echo "Appended balances and updated rune supply placeholder with total: $TOTAL_RUNE_SUPPLY"
