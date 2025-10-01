#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
NODE_ACCOUNTS_FILE="/tmp/node_accounts.json"

NODE_ACCOUNTS_DATA=$(cat "$NODE_ACCOUNTS_FILE" | tr -d '\n' | sed 's/"/\\"/g')

sed -i "s|\"__NODE_ACCOUNTS__\"|$NODE_ACCOUNTS_DATA|g" "$GENESIS_FILE"

echo "Replaced node_accounts with custom validator set"
