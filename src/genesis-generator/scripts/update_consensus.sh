#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
CONSENSUS_FILE="/tmp/consensus_block.json"
TEMP_FILE="/tmp/genesis_temp.json"

jq --slurpfile consensus "$CONSENSUS_FILE" '.consensus = $consensus[0]' "$GENESIS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$GENESIS_FILE"

echo "Updated consensus block"
