#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

NETWORK_TYPE=${1:-"local"}

if [ "$NETWORK_TYPE" = "local" ]; then
    RPC_ENDPOINT="http://127.0.0.1:32772"
    API_ENDPOINT="http://127.0.0.1:32769"
    ENCLAVE_NAME="local-thorchain"
elif [ "$NETWORK_TYPE" = "forked" ]; then
    RPC_ENDPOINT="http://127.0.0.1:32786"
    API_ENDPOINT="http://127.0.0.1:32783"
    ENCLAVE_NAME="forked-thorchain"
else
    echo "Usage: $0 [local|forked]"
    exit 1
fi

echo "THORChain Actual Contract Deployment"
echo "===================================="
echo "Network: $NETWORK_TYPE"
echo "RPC: $RPC_ENDPOINT"
echo "API: $API_ENDPOINT"
echo ""

check_network() {
    echo "Checking network connectivity..."
    
    if ! curl -s "$API_ENDPOINT/cosmos/base/tendermint/v1beta1/node_info" > /dev/null; then
        echo "✗ Cannot connect to API endpoint: $API_ENDPOINT"
        exit 1
    fi
    
    if ! curl -s "$RPC_ENDPOINT/status" > /dev/null; then
        echo "✗ Cannot connect to RPC endpoint: $RPC_ENDPOINT"
        exit 1
    fi
    
    echo "✓ Network connectivity verified"
}

setup_keys() {
    echo "Setting up deployment keys..."
    
    local mnemonic
    if mnemonic=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-faucet "cat /tmp/mnemonic/mnemonic.txt" 2>/dev/null); then
        echo "✓ Retrieved prefunded mnemonic"
        
        kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode keys delete demo-key --keyring-backend test --yes" 2>/dev/null || true
        
        kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "echo '$mnemonic' | thornode keys add demo-key --recover --keyring-backend test"
        
        local address
        address=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode keys show demo-key --keyring-backend test -a")
        echo "✓ Demo key imported: $address"
        
        local balance
        balance=$(curl -s "$API_ENDPOINT/cosmos/bank/v1beta1/balances/$address" | jq -r '.balances[0].amount // "0"')
        echo "✓ Account balance: $balance rune"
        
        if [ "$balance" = "0" ]; then
            echo "⚠ Warning: Account has no balance"
        fi
    else
        echo "✗ Could not retrieve prefunded mnemonic"
        exit 1
    fi
}

deploy_counter_contract() {
    echo "Deploying counter contract..."
    
    if [ ! -f "$PROJECT_ROOT/build/counter.wasm" ]; then
        echo "✗ Counter contract not found. Run build-contracts.sh first."
        exit 1
    fi
    
    echo "Uploading counter contract..."
    
    local wasm_b64=$(base64 -w 0 "$PROJECT_ROOT/build/counter.wasm")
    local chunk_size=8000
    local total_length=${#wasm_b64}
    local chunks=$((total_length / chunk_size + 1))
    
    echo "Transferring contract in $chunks chunks..."
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "rm -f /tmp/counter.wasm /tmp/counter.b64"
    
    for ((i=0; i<chunks; i++)); do
        local start=$((i * chunk_size))
        local chunk="${wasm_b64:$start:$chunk_size}"
        if [ -n "$chunk" ]; then
            kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "echo -n '$chunk' >> /tmp/counter.b64"
        fi
    done
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "base64 -d /tmp/counter.b64 > /tmp/counter.wasm && rm /tmp/counter.b64"
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "ls -la /tmp/counter.wasm"
    
    local upload_result
    upload_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode tx wasm store /tmp/counter.wasm \
        --from demo-key \
        --keyring-backend test \
        --chain-id thorchain \
        --node tcp://localhost:26657 \
        --gas auto \
        --gas-adjustment 1.3 \
        --yes \
        --output json")
    
    local tx_hash
    tx_hash=$(echo "$upload_result" | jq -r '.txhash')
    echo "✓ Upload transaction: $tx_hash"
    
    echo "Waiting for transaction confirmation..."
    sleep 5
    
    local code_id
    code_id=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm list-code --node tcp://localhost:26657 --output json" | jq -r '.code_infos[-1].code_id')
    echo "✓ Counter contract code ID: $code_id"
    
    echo "Instantiating counter contract..."
    local instantiate_result
    instantiate_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode tx wasm instantiate $code_id '{\"count\": 42}' \
        --from demo-key \
        --keyring-backend test \
        --chain-id thorchain \
        --node tcp://localhost:26657 \
        --label demo-counter \
        --gas auto \
        --gas-adjustment 1.3 \
        --yes \
        --output json")
    
    local instantiate_tx_hash
    instantiate_tx_hash=$(echo "$instantiate_result" | jq -r '.txhash')
    echo "✓ Instantiate transaction: $instantiate_tx_hash"
    
    echo "Waiting for instantiation confirmation..."
    sleep 5
    
    local contract_addr
    contract_addr=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm list-contract-by-code $code_id --node tcp://localhost:26657 --output json" | jq -r '.contracts[0]')
    echo "✓ Counter contract address: $contract_addr"
    
    echo "Testing counter contract..."
    local count_result
    count_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm contract-state smart $contract_addr '{\"get_count\":{}}' --node tcp://localhost:26657 --output json")
    local count_value
    count_value=$(echo "$count_result" | jq -r '.data.count')
    echo "✓ Initial counter value: $count_value"
    
    echo "$contract_addr" > "$PROJECT_ROOT/counter-contract-address.txt"
    echo "✓ Counter contract deployed successfully"
}

deploy_cw20_contract() {
    echo "Deploying CW20 token contract..."
    
    if [ ! -f "$PROJECT_ROOT/build/cw20-token.wasm" ]; then
        echo "✗ CW20 contract not found. Run build-contracts.sh first."
        exit 1
    fi
    
    echo "Uploading CW20 contract..."
    
    local wasm_b64=$(base64 -w 0 "$PROJECT_ROOT/build/cw20-token.wasm")
    local chunk_size=8000
    local total_length=${#wasm_b64}
    local chunks=$((total_length / chunk_size + 1))
    
    echo "Transferring contract in $chunks chunks..."
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "rm -f /tmp/cw20-token.wasm /tmp/cw20-token.b64"
    
    for ((i=0; i<chunks; i++)); do
        local start=$((i * chunk_size))
        local chunk="${wasm_b64:$start:$chunk_size}"
        if [ -n "$chunk" ]; then
            kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "echo -n '$chunk' >> /tmp/cw20-token.b64"
        fi
    done
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "base64 -d /tmp/cw20-token.b64 > /tmp/cw20-token.wasm && rm /tmp/cw20-token.b64"
    
    kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "ls -la /tmp/cw20-token.wasm"
    
    local upload_result
    upload_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode tx wasm store /tmp/cw20-token.wasm \
        --from demo-key \
        --keyring-backend test \
        --chain-id thorchain \
        --node tcp://localhost:26657 \
        --gas auto \
        --gas-adjustment 1.3 \
        --yes \
        --output json")
    
    local tx_hash
    tx_hash=$(echo "$upload_result" | jq -r '.txhash')
    echo "✓ Upload transaction: $tx_hash"
    
    echo "Waiting for transaction confirmation..."
    sleep 5
    
    local code_id
    code_id=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm list-code --node tcp://localhost:26657 --output json" | jq -r '.code_infos[-1].code_id')
    echo "✓ CW20 contract code ID: $code_id"
    
    local demo_address
    demo_address=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode keys show demo-key --keyring-backend test -a")
    
    echo "Instantiating CW20 contract..."
    local instantiate_msg
    instantiate_msg=$(cat <<EOF
{
  "name": "Demo Token",
  "symbol": "DEMO",
  "decimals": 6,
  "initial_balances": [
    {
      "address": "$demo_address",
      "amount": "1000000000"
    }
  ],
  "mint": {
    "minter": "$demo_address",
    "cap": "10000000000"
  }
}
EOF
)
    
    local instantiate_result
    instantiate_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode tx wasm instantiate $code_id '$instantiate_msg' \
        --from demo-key \
        --keyring-backend test \
        --chain-id thorchain \
        --node tcp://localhost:26657 \
        --label demo-token \
        --gas auto \
        --gas-adjustment 1.3 \
        --yes \
        --output json")
    
    local instantiate_tx_hash
    instantiate_tx_hash=$(echo "$instantiate_result" | jq -r '.txhash')
    echo "✓ Instantiate transaction: $instantiate_tx_hash"
    
    echo "Waiting for instantiation confirmation..."
    sleep 5
    
    local contract_addr
    contract_addr=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm list-contract-by-code $code_id --node tcp://localhost:26657 --output json" | jq -r '.contracts[0]')
    echo "✓ CW20 contract address: $contract_addr"
    
    echo "Testing CW20 contract..."
    local balance_result
    balance_result=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm contract-state smart $contract_addr '{\"balance\":{\"address\":\"$demo_address\"}}' --node tcp://localhost:26657 --output json")
    local balance_value
    balance_value=$(echo "$balance_result" | jq -r '.data.balance')
    echo "✓ Demo account token balance: $balance_value"
    
    echo "$contract_addr" > "$PROJECT_ROOT/cw20-contract-address.txt"
    echo "✓ CW20 contract deployed successfully"
}

test_contract_interactions() {
    echo "Testing contract interactions..."
    
    if [ -f "$PROJECT_ROOT/counter-contract-address.txt" ]; then
        local counter_addr
        counter_addr=$(cat "$PROJECT_ROOT/counter-contract-address.txt")
        
        echo "Testing counter increment..."
        kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode tx wasm execute $counter_addr '{\"increment\":{}}' \
            --from demo-key \
            --keyring-backend test \
            --chain-id thorchain \
            --node tcp://localhost:26657 \
            --gas auto \
            --gas-adjustment 1.3 \
            --yes" > /dev/null
        
        sleep 3
        
        local new_count
        new_count=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm contract-state smart $counter_addr '{\"get_count\":{}}' --node tcp://localhost:26657 --output json" | jq -r '.data.count')
        echo "✓ Counter after increment: $new_count"
    fi
    
    if [ -f "$PROJECT_ROOT/cw20-contract-address.txt" ]; then
        local cw20_addr
        cw20_addr=$(cat "$PROJECT_ROOT/cw20-contract-address.txt")
        
        echo "Testing token info query..."
        local token_info
        token_info=$(kurtosis service exec "$ENCLAVE_NAME" thorchain-node-1 "thornode query wasm contract-state smart $cw20_addr '{\"token_info\":{}}' --node tcp://localhost:26657 --output json")
        local token_name
        token_name=$(echo "$token_info" | jq -r '.data.name')
        local token_symbol
        token_symbol=$(echo "$token_info" | jq -r '.data.symbol')
        echo "✓ Token info: $token_name ($token_symbol)"
    fi
}

generate_deployment_report() {
    echo "Generating deployment report..."
    
    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local report_file="$PROJECT_ROOT/actual-deployment-report-$NETWORK_TYPE-$timestamp.json"
    
    local counter_addr=""
    local cw20_addr=""
    
    if [ -f "$PROJECT_ROOT/counter-contract-address.txt" ]; then
        counter_addr=$(cat "$PROJECT_ROOT/counter-contract-address.txt")
    fi
    
    if [ -f "$PROJECT_ROOT/cw20-contract-address.txt" ]; then
        cw20_addr=$(cat "$PROJECT_ROOT/cw20-contract-address.txt")
    fi
    
    cat > "$report_file" <<EOF
{
  "deployment_type": "actual",
  "network_type": "$NETWORK_TYPE",
  "timestamp": "$timestamp",
  "endpoints": {
    "rpc": "$RPC_ENDPOINT",
    "api": "$API_ENDPOINT"
  },
  "contracts": {
    "counter": {
      "address": "$counter_addr",
      "status": "deployed"
    },
    "cw20_token": {
      "address": "$cw20_addr",
      "status": "deployed"
    }
  },
  "next_steps": [
    "Test memo-based contract calls",
    "Set up Bifrost integration",
    "Test cross-chain interactions"
  ]
}
EOF
    
    echo "✓ Deployment report saved: $report_file"
}

main() {
    check_network
    setup_keys
    deploy_counter_contract
    deploy_cw20_contract
    test_contract_interactions
    generate_deployment_report
    
    echo ""
    echo "✓ Actual contract deployment completed successfully!"
    echo ""
    echo "Deployed Contracts:"
    if [ -f "$PROJECT_ROOT/counter-contract-address.txt" ]; then
        echo "  Counter: $(cat "$PROJECT_ROOT/counter-contract-address.txt")"
    fi
    if [ -f "$PROJECT_ROOT/cw20-contract-address.txt" ]; then
        echo "  CW20 Token: $(cat "$PROJECT_ROOT/cw20-contract-address.txt")"
    fi
    echo ""
    echo "Next: Test memo-based contract calls with these addresses"
}

main "$@"
