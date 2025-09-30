#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NODE_ACCOUNTS_FILE="/tmp/node_accounts.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile node_accounts "$NODE_ACCOUNTS_FILE" '.app_state.thorchain.node_accounts = $node_accounts[0]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Replaced node_accounts with custom validator set"
