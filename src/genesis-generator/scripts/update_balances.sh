#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_BALANCES_FILE="/tmp/new_balances.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile new_balances "$NEW_BALANCES_FILE" '.app_state.bank.balances = $new_balances[0]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

RUNE_TOTAL=$(jq '[.app_state.bank.balances[].coins[] | select(.denom == "rune") | .amount | tonumber] | add | tostring' "$GENESIS_FILE")

sed -i "s/\"__RUNE_SUPPLY__\"/\"$RUNE_TOTAL\"/" "$GENESIS_FILE"

echo "Replaced balances and updated rune supply placeholder"
