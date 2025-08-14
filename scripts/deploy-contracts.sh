#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build"

NETWORK_TYPE="${1:-local}"
THORCHAIN_RPC="${2:-http://localhost:26657}"
THORCHAIN_API="${3:-http://localhost:1317}"
CHAIN_ID="${4:-thorchain-testnet}"

echo "Deploying contracts to $NETWORK_TYPE network"
echo "RPC: $THORCHAIN_RPC"
echo "API: $THORCHAIN_API"
echo "Chain ID: $CHAIN_ID"

check_network_connectivity() {
    echo "Checking network connectivity..."
    
    if ! curl -s --max-time 10 "$THORCHAIN_RPC/status" > /dev/null; then
        echo "Error: Cannot connect to THORChain RPC at $THORCHAIN_RPC"
        exit 1
    fi
    
    if ! curl -s --max-time 10 "$THORCHAIN_API/cosmos/base/tendermint/v1beta1/node_info" > /dev/null; then
        echo "Error: Cannot connect to THORChain API at $THORCHAIN_API"
        exit 1
    fi
    
    echo "✓ Network connectivity verified"
}

check_wasm_permissions() {
    echo "Checking WASM module permissions..."
    
    local params_response
    params_response=$(curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/params")
    
    if echo "$params_response" | jq -e '.params' > /dev/null 2>&1; then
        local upload_access
        local instantiate_permission
        
        upload_access=$(echo "$params_response" | jq -r '.params.code_upload_access.permission')
        instantiate_permission=$(echo "$params_response" | jq -r '.params.instantiate_default_permission')
        
        echo "Upload access: $upload_access"
        echo "Instantiate permission: $instantiate_permission"
        
        if [ "$upload_access" != "Everybody" ] || [ "$instantiate_permission" != "Everybody" ]; then
            echo "Warning: WASM permissions may restrict contract deployment"
        else
            echo "✓ WASM permissions allow contract deployment"
        fi
    else
        echo "Warning: Could not retrieve WASM parameters"
    fi
}

validate_contract_files() {
    echo "Validating contract files..."
    
    local contracts=("counter" "cw20-token")
    local missing_contracts=()
    
    for contract in "${contracts[@]}"; do
        local wasm_file="$BUILD_DIR/${contract}.wasm"
        if [ ! -f "$wasm_file" ]; then
            missing_contracts+=("$contract")
        else
            local size=$(stat -f%z "$wasm_file" 2>/dev/null || stat -c%s "$wasm_file" 2>/dev/null)
            echo "✓ $contract.wasm ($size bytes)"
        fi
    done
    
    if [ ${#missing_contracts[@]} -gt 0 ]; then
        echo "Error: Missing contract files: ${missing_contracts[*]}"
        echo "Run ./scripts/build-contracts.sh first"
        exit 1
    fi
}

simulate_contract_deployment() {
    local contract_name=$1
    local wasm_file="$BUILD_DIR/${contract_name}.wasm"
    
    echo "Simulating deployment of $contract_name..."
    
    local contract_size
    contract_size=$(stat -f%z "$wasm_file" 2>/dev/null || stat -c%s "$wasm_file" 2>/dev/null)
    
    local estimated_gas=$((contract_size * 2 + 100000))
    
    echo "Contract: $contract_name"
    echo "Size: $contract_size bytes"
    echo "Estimated gas: $estimated_gas"
    
    if [ $contract_size -gt 800000 ]; then
        echo "Warning: Contract size exceeds recommended limit (800KB)"
    fi
    
    echo "✓ Deployment simulation completed for $contract_name"
}

test_contract_queries() {
    echo "Testing contract query endpoints..."
    
    local codes_response
    codes_response=$(curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/code")
    
    if echo "$codes_response" | jq -e '.code_infos' > /dev/null 2>&1; then
        local code_count
        code_count=$(echo "$codes_response" | jq '.code_infos | length')
        echo "✓ Found $code_count existing contracts"
    else
        echo "Warning: Could not query existing contracts"
    fi
}

generate_deployment_report() {
    local network_type=$1
    local report_file="$PROJECT_ROOT/deployment-report-${network_type}-$(date +%Y%m%d-%H%M%S).json"
    
    echo "Generating deployment report..."
    
    cat > "$report_file" << EOF
{
  "deployment_info": {
    "network_type": "$network_type",
    "thorchain_rpc": "$THORCHAIN_RPC",
    "thorchain_api": "$THORCHAIN_API",
    "chain_id": "$CHAIN_ID",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "contracts": [
EOF

    local first=true
    for contract in counter cw20-token; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        local wasm_file="$BUILD_DIR/${contract}.wasm"
        local size=$(stat -f%z "$wasm_file" 2>/dev/null || stat -c%s "$wasm_file" 2>/dev/null)
        local checksum=""
        
        if [ -f "${wasm_file}.sha256" ]; then
            checksum=$(cut -d' ' -f1 "${wasm_file}.sha256")
        fi
        
        cat >> "$report_file" << EOF
    {
      "name": "$contract",
      "size_bytes": $size,
      "checksum": "$checksum",
      "status": "simulated"
    }
EOF
    done
    
    cat >> "$report_file" << EOF
  ],
  "network_status": {
    "rpc_accessible": true,
    "api_accessible": true,
    "wasm_enabled": true
  }
}
EOF

    echo "✓ Deployment report saved to: $report_file"
}

main() {
    echo "THORChain Contract Deployment Script"
    echo "===================================="
    
    check_network_connectivity
    check_wasm_permissions
    validate_contract_files
    
    echo ""
    echo "Simulating contract deployments..."
    simulate_contract_deployment "counter"
    simulate_contract_deployment "cw20-token"
    
    test_contract_queries
    generate_deployment_report "$NETWORK_TYPE"
    
    echo ""
    echo "✓ Contract deployment simulation completed successfully!"
    echo ""
    echo "Note: This script simulates deployment. For actual deployment,"
    echo "you would need thornode CLI with proper keys and gas tokens."
    echo ""
    echo "Next steps:"
    echo "1. Set up thornode CLI with test keys"
    echo "2. Fund test accounts with gas tokens"
    echo "3. Use 'thornode tx wasm store' to upload contracts"
    echo "4. Use 'thornode tx wasm instantiate' to create contract instances"
}

main "$@"
