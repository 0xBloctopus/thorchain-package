#!/bin/bash

GENESIS_FILE="/tmp/genesis.json"
TARGET_DIR="/root/.thornode/config"

mkdir -p "$TARGET_DIR"
cp "$GENESIS_FILE" "$TARGET_DIR/genesis.json"

echo "Genesis file moved to $TARGET_DIR/genesis.json"
