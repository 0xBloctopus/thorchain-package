#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LOCAL_RPC="${1:-http://localhost:26657}"
LOCAL_API="${2:-http://localhost:1317}"
FORKED_RPC="${3:-http://localhost:26658}"
FORKED_API="${4:-http://localhost:1318}"

echo "Validating contract deployment across network types"
echo "Local network - RPC: $LOCAL_RPC, API: $LOCAL_API"
echo "Forked network - RPC: $FORKED_RPC, API: $FORKED_API"

validate_network_status() {
    local network_name=$1
    local rpc_url=$2
    local api_url=$3
    
    echo "Validating $network_name network status..."
    
    local status_response
    if status_response=$(curl -s --max-time 10 "$rpc_url/status"); then
        local latest_height
        latest_height=$(echo "$status_response" | jq -r '.result.sync_info.latest_block_height')
        echo "✓ $network_name RPC accessible - Latest height: $latest_height"
    else
        echo "✗ $network_name RPC not accessible at $rpc_url"
        return 1
    fi
    
    local node_info_response
    if node_info_response=$(curl -s --max-time 10 "$api_url/cosmos/base/tendermint/v1beta1/node_info"); then
        local chain_id
        chain_id=$(echo "$node_info_response" | jq -r '.default_node_info.network')
        echo "✓ $network_name API accessible - Chain ID: $chain_id"
    else
        echo "✗ $network_name API not accessible at $api_url"
        return 1
    fi
}

compare_wasm_parameters() {
    echo "Comparing WASM module parameters..."
    
    local local_params
    local forked_params
    
    if local_params=$(curl -s "$LOCAL_API/cosmwasm/wasm/v1/params"); then
        echo "✓ Retrieved local WASM parameters"
    else
        echo "✗ Failed to retrieve local WASM parameters"
        return 1
    fi
    
    if forked_params=$(curl -s "$FORKED_API/cosmwasm/wasm/v1/params"); then
        echo "✓ Retrieved forked WASM parameters"
    else
        echo "✗ Failed to retrieve forked WASM parameters"
        return 1
    fi
    
    local local_upload_access
    local forked_upload_access
    local local_instantiate_perm
    local forked_instantiate_perm
    
    local_upload_access=$(echo "$local_params" | jq -r '.params.code_upload_access.permission')
    forked_upload_access=$(echo "$forked_params" | jq -r '.params.code_upload_access.permission')
    local_instantiate_perm=$(echo "$local_params" | jq -r '.params.instantiate_default_permission')
    forked_instantiate_perm=$(echo "$forked_params" | jq -r '.params.instantiate_default_permission')
    
    echo "Local network:"
    echo "  Upload access: $local_upload_access"
    echo "  Instantiate permission: $local_instantiate_perm"
    
    echo "Forked network:"
    echo "  Upload access: $forked_upload_access"
    echo "  Instantiate permission: $forked_instantiate_perm"
    
    if [ "$local_upload_access" = "$forked_upload_access" ] && [ "$local_instantiate_perm" = "$forked_instantiate_perm" ]; then
        echo "✓ WASM parameters match between networks"
    else
        echo "✗ WASM parameters differ between networks"
        return 1
    fi
}

validate_forked_data_integrity() {
    echo "Validating forked data integrity..."
    
    local pools_response
    if pools_response=$(curl -s "$FORKED_API/thorchain/pools"); then
        local pool_count
        pool_count=$(echo "$pools_response" | jq '.pools | length')
        echo "✓ Forked network has $pool_count pools"
        
        if [ "$pool_count" -gt 0 ]; then
            echo "✓ Forked data appears to be loaded correctly"
        else
            echo "⚠ Warning: No pools found in forked network"
        fi
    else
        echo "✗ Failed to query pools on forked network"
        return 1
    fi
    
    local test_address="thor1dheycdevq39qlkxs2a6wuuzyn4aqxhve4qxtxt"
    local balance_response
    if balance_response=$(curl -s "$FORKED_API/cosmos/bank/v1beta1/balances/$test_address"); then
        local balance_count
        balance_count=$(echo "$balance_response" | jq '.balances | length')
        echo "✓ Test address has $balance_count balance entries"
    else
        echo "⚠ Warning: Could not query test address balance"
    fi
}

test_contract_query_endpoints() {
    local network_name=$1
    local api_url=$2
    
    echo "Testing contract query endpoints on $network_name network..."
    
    local codes_response
    if codes_response=$(curl -s "$api_url/cosmwasm/wasm/v1/code"); then
        local code_count
        code_count=$(echo "$codes_response" | jq '.code_infos | length')
        echo "✓ $network_name: Found $code_count existing contracts"
    else
        echo "✗ $network_name: Failed to query contract codes"
        return 1
    fi
    
    local contracts_response
    if contracts_response=$(curl -s "$api_url/cosmwasm/wasm/v1/contract"); then
        local contract_count
        contract_count=$(echo "$contracts_response" | jq '.contracts | length')
        echo "✓ $network_name: Found $contract_count contract instances"
    else
        echo "⚠ $network_name: Could not query contract instances"
    fi
}

generate_validation_report() {
    local report_file="$PROJECT_ROOT/validation-report-$(date +%Y%m%d-%H%M%S).json"
    
    echo "Generating validation report..."
    
    local local_status="unknown"
    local forked_status="unknown"
    local wasm_params_match="unknown"
    local forked_data_valid="unknown"
    
    if curl -s --max-time 5 "$LOCAL_RPC/status" > /dev/null; then
        local_status="accessible"
    else
        local_status="inaccessible"
    fi
    
    if curl -s --max-time 5 "$FORKED_RPC/status" > /dev/null; then
        forked_status="accessible"
    else
        forked_status="inaccessible"
    fi
    
    cat > "$report_file" << EOF
{
  "validation_info": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "local_network": {
      "rpc": "$LOCAL_RPC",
      "api": "$LOCAL_API",
      "status": "$local_status"
    },
    "forked_network": {
      "rpc": "$FORKED_RPC",
      "api": "$FORKED_API",
      "status": "$forked_status"
    }
  },
  "validation_results": {
    "network_connectivity": {
      "local_accessible": $([ "$local_status" = "accessible" ] && echo "true" || echo "false"),
      "forked_accessible": $([ "$forked_status" = "accessible" ] && echo "true" || echo "false")
    },
    "wasm_parameters_match": null,
    "forked_data_integrity": null,
    "contract_endpoints_functional": null
  },
  "recommendations": [
    "Verify both networks are running before deployment testing",
    "Ensure WASM permissions are consistent across network types",
    "Validate forked data integrity before contract testing",
    "Test contract deployment on both networks with identical parameters"
  ]
}
EOF

    echo "✓ Validation report saved to: $report_file"
}

main() {
    echo "THORChain Contract Deployment Validation"
    echo "========================================"
    
    local validation_passed=true
    
    if ! validate_network_status "Local" "$LOCAL_RPC" "$LOCAL_API"; then
        validation_passed=false
    fi
    
    if ! validate_network_status "Forked" "$FORKED_RPC" "$FORKED_API"; then
        validation_passed=false
    fi
    
    if [ "$validation_passed" = true ]; then
        if ! compare_wasm_parameters; then
            validation_passed=false
        fi
        
        validate_forked_data_integrity
        
        test_contract_query_endpoints "Local" "$LOCAL_API"
        test_contract_query_endpoints "Forked" "$FORKED_API"
    fi
    
    generate_validation_report
    
    echo ""
    if [ "$validation_passed" = true ]; then
        echo "✓ Validation completed successfully!"
        echo "Both networks are ready for contract deployment testing."
    else
        echo "✗ Validation failed!"
        echo "Please address the issues before proceeding with contract deployment."
        exit 1
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Run ./scripts/build-contracts.sh to build test contracts"
    echo "2. Run ./scripts/deploy-contracts.sh local to test local deployment"
    echo "3. Run ./scripts/deploy-contracts.sh forked to test forked deployment"
    echo "4. Compare deployment results between networks"
}

main "$@"
