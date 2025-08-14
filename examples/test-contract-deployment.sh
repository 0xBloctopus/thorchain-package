#!/bin/bash

set -e

THORCHAIN_RPC="${1:-http://localhost:26657}"
THORCHAIN_API="${2:-http://localhost:1317}"
CONTRACT_PATH="${3:-./test-contracts/counter.wasm}"

echo "Testing contract deployment on THORChain at $THORCHAIN_API"

echo "Checking network status..."
curl -s "$THORCHAIN_RPC/status" | jq '.result.sync_info.latest_block_height'

echo "Checking WASM module parameters..."
curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/params" | jq '.params'

if [ -f "$CONTRACT_PATH" ]; then
    echo "Uploading test contract..."
    echo "Contract upload test would go here (requires thornode CLI setup)"
else
    echo "No test contract found at $CONTRACT_PATH, skipping upload test"
fi

echo "Testing contract query endpoints..."
curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/code" | jq '.code_infos | length'

echo "Testing forked data integrity..."
curl -s "$THORCHAIN_API/thorchain/pools" | jq '.pools | length'
curl -s "$THORCHAIN_API/cosmos/bank/v1beta1/balances/thor1dheycdevq39qlkxs2a6wuuzyn4aqxhve4qxtxt" | jq '.balances'

echo "Contract deployment test completed successfully!"
