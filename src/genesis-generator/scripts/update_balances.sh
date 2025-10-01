#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_BALANCES_FILE="/tmp/new_balances.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile new_balances "$NEW_BALANCES_FILE" '.app_state.bank.balances = $new_balances[0]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Replaced balances with validator/faucet accounts"
