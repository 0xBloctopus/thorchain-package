#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NEW_ACCOUNTS_FILE="/tmp/new_accounts.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile new_accounts "$NEW_ACCOUNTS_FILE" '
  .app_state.auth.accounts += $new_accounts[0] |
  .app_state.auth.accounts = [.app_state.auth.accounts[] | select(.address | length == 43)]
' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Appended new accounts and filtered invalid addresses"
