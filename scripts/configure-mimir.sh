#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Configuring THORChain mimir values for contract deployment..."

check_network_connectivity() {
    local network_type=$1
    local api_port=$2
    local rpc_port=$3
    
    echo "Checking $network_type network connectivity..."
    
    for i in {1..30}; do
        if curl -s "http://127.0.0.1:$api_port/status" > /dev/null 2>&1; then
            echo "✓ $network_type network API accessible at port $api_port"
            break
        fi
        
        if [ $i -eq 30 ]; then
            echo "✗ Failed to connect to $network_type network after 30 attempts"
            return 1
        fi
        
        echo "Waiting for $network_type network... ($i/30)"
        sleep 2
    done
    
    for i in {1..30}; do
        local status=$(curl -s "http://127.0.0.1:$rpc_port/status" | jq -r '.result.sync_info.latest_block_height // "0"' 2>/dev/null || echo "0")
        if [ "$status" != "0" ] && [ "$status" != "null" ]; then
            echo "✓ $network_type network producing blocks (height: $status)"
            return 0
        fi
        
        if [ $i -eq 30 ]; then
            echo "✗ $network_type network not producing blocks after 30 attempts"
            return 1
        fi
        
        echo "Waiting for first block on $network_type network... ($i/30)"
        sleep 2
    done
}

set_mimir_value() {
    local network_type=$1
    local rpc_port=$2
    local key=$3
    local value=$4
    
    echo "Setting mimir value $key=$value on $network_type network..."
    
    local enclave_name
    if [ "$network_type" = "local" ]; then
        enclave_name="thorchain-local"
    else
        enclave_name="thorchain-forked"
    fi
    
    local result
    result=$(kurtosis service exec "$enclave_name" thorchain-node-1 \
        "thornode tx thorchain mimir $key $value --from validator --keyring-backend test --chain-id thorchain --node tcp://localhost:26657 --yes --fees 2000000rune --output json" 2>&1)
    
    if echo "$result" | grep -q '"code":0' || echo "$result" | grep -q '"code": 0' || echo "$result" | grep -q 'code: 0'; then
        echo "✓ Successfully set $key=$value on $network_type network"
        
        sleep 3
        
        local verification
        verification=$(kurtosis service exec "$enclave_name" thorchain-node-1 \
            "curl -s http://localhost:1317/thorchain/mimir" 2>/dev/null || echo "{}")
        
        if echo "$verification" | grep -q "\"$key\""; then
            echo "✓ Mimir value $key verified on $network_type network"
        else
            echo "⚠ Mimir value $key set but not immediately visible (may take time to propagate)"
        fi
        
        return 0
    else
        echo "✗ Failed to set $key=$value on $network_type network"
        echo "Error: $result"
        return 1
    fi
}

configure_network_mimir() {
    local network_type=$1
    local api_port=$2
    local rpc_port=$3
    
    echo ""
    echo "=== Configuring $network_type Network Mimir Values ==="
    
    if ! check_network_connectivity "$network_type" "$api_port" "$rpc_port"; then
        echo "✗ Cannot configure mimir - $network_type network not accessible"
        return 1
    fi
    
    if ! set_mimir_value "$network_type" "$rpc_port" "WASMPERMISSIONLESS" "1"; then
        echo "✗ Failed to configure WASMPERMISSIONLESS on $network_type network"
        return 1
    fi
    
    echo "✓ $network_type network mimir configuration complete"
    return 0
}

main() {
    echo "THORChain Mimir Configuration Script"
    echo "===================================="
    
    local local_api_port=$(kurtosis port print thorchain-local thorchain-node-1 api 2>/dev/null | cut -d: -f2 || echo "")
    local local_rpc_port=$(kurtosis port print thorchain-local thorchain-node-1 rpc 2>/dev/null | cut -d: -f2 || echo "")
    
    local forked_api_port=$(kurtosis port print thorchain-forked thorchain-node-1 api 2>/dev/null | cut -d: -f2 || echo "")
    local forked_rpc_port=$(kurtosis port print thorchain-forked thorchain-node-1 rpc 2>/dev/null | cut -d: -f2 || echo "")
    
    local local_configured=false
    local forked_configured=false
    
    if kurtosis enclave ls | grep -q "thorchain-local.*RUNNING" && [ -n "$local_api_port" ] && [ -n "$local_rpc_port" ]; then
        echo "Found running local network (API: $local_api_port, RPC: $local_rpc_port)"
        if configure_network_mimir "local" "$local_api_port" "$local_rpc_port"; then
            local_configured=true
        fi
    else
        echo "Local network not running or ports not accessible - skipping mimir configuration"
    fi
    
    if kurtosis enclave ls | grep -q "thorchain-forked.*RUNNING" && [ -n "$forked_api_port" ] && [ -n "$forked_rpc_port" ]; then
        echo "Found running forked network (API: $forked_api_port, RPC: $forked_rpc_port)"
        if configure_network_mimir "forked" "$forked_api_port" "$forked_rpc_port"; then
            forked_configured=true
        fi
    else
        echo "Forked network not running or ports not accessible - skipping mimir configuration"
    fi
    
    echo ""
    echo "=== Mimir Configuration Summary ==="
    if [ "$local_configured" = true ]; then
        echo "✓ Local network: WASMPERMISSIONLESS=1 configured"
    else
        echo "⚠ Local network: Not configured (network not running or configuration failed)"
    fi
    
    if [ "$forked_configured" = true ]; then
        echo "✓ Forked network: WASMPERMISSIONLESS=1 configured"
    else
        echo "⚠ Forked network: Not configured (network not running or configuration failed)"
    fi
    
    if [ "$local_configured" = true ] || [ "$forked_configured" = true ]; then
        echo ""
        echo "✓ Contract deployment should now work on configured networks"
        echo "Note: Mimir values override genesis WASM permissions at runtime"
        return 0
    else
        echo ""
        echo "✗ No networks were configured - ensure networks are running before mimir setup"
        return 1
    fi
}

main "$@"
