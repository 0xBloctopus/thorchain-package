#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
CONSENSUS_FILE="/tmp/consensus_block.json"

CONSENSUS_DATA=$(cat "$CONSENSUS_FILE" | tr -d '\n' | sed 's/"/\\"/g')

sed -i "s|\"__CONSENSUS_BLOCK__\"|$CONSENSUS_DATA|g" "$GENESIS_FILE"

echo "Updated consensus block"
