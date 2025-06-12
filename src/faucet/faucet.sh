#!/bin/bash

set -euo pipefail

CHAIN_ID="${CHAIN_ID:-thorchain-localnet-1}"
NODE_URL="${NODE_URL:-http://localhost:26657}"
TRANSFER_AMOUNT="${TRANSFER_AMOUNT:-100000000}"
PORT="${PORT:-8090}"
MONITORING_PORT="${MONITORING_PORT:-8091}"

echo "Starting Thorchain faucet service..."
echo "Chain ID: $CHAIN_ID"
echo "Node URL: $NODE_URL"
echo "Transfer Amount: $TRANSFER_AMOUNT"
echo "API Port: $PORT"
echo "Monitoring Port: $MONITORING_PORT"

echo "Importing faucet key..."
thornode keys delete faucet --keyring-backend test --yes 2>/dev/null || true
cat /tmp/mnemonic/mnemonic.txt | thornode keys add faucet --recover --keyring-backend test --chain-id "$CHAIN_ID"

echo "Faucet key imported successfully"

check_node_ready() {
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$NODE_URL/status" > /dev/null 2>&1; then
            echo "Node is ready!"
            return 0
        fi
        echo "Waiting for node to be ready... (attempt $attempt/$max_attempts)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo "Node failed to become ready after $max_attempts attempts"
    return 1
}

handle_funding_request() {
    local address="$1"
    echo "Funding address: $address"
    result=$(thornode tx bank send faucet "$address" "$TRANSFER_AMOUNT" --chain-id "$CHAIN_ID" --node "$NODE_URL" --keyring-backend test --yes 2>&1)
    success=$?
    
    if [ $success -eq 0 ]; then
        echo "{\"status\":\"success\",\"message\":\"Funded $address with $TRANSFER_AMOUNT\"}"
    else
        echo "{\"status\":\"error\",\"message\":\"Failed to fund address: $result\"}"
    fi
}

handle_balance_request() {
    local address="$1"
    echo "Checking balance for address: $address"
    result=$(thornode query bank balances "$address" --node "$NODE_URL" --output json 2>&1)
    success=$?
    
    if [ $success -eq 0 ]; then
        echo "{\"status\":\"success\",\"balances\":$result}"
    else
        echo "{\"status\":\"error\",\"message\":\"Failed to get balance: $result\"}"
    fi
}

handle_health_check() {
    echo "{\"status\":\"healthy\",\"chain_id\":\"$CHAIN_ID\",\"node_url\":\"$NODE_URL\"}"
}

check_node_ready

echo "Starting HTTP server on port $PORT..."

while true; do
    {
        read -r request_line
        read -r host_line
        
        while read -r header && [ "$header" != $'\r' ]; do
            continue
        done
        
        method=$(echo "$request_line" | cut -d' ' -f1)
        path=$(echo "$request_line" | cut -d' ' -f2)
        
        echo "Received $method request for $path"
        
        case "$path" in
            "/health")
                response=$(handle_health_check)
                ;;
            "/fund/"*)
                if [ "$method" = "POST" ]; then
                    address=$(echo "$path" | sed 's|/fund/||')
                    response=$(handle_funding_request "$address")
                else
                    response="{\"status\":\"error\",\"message\":\"Method not allowed. Use POST.\"}"
                fi
                ;;
            "/balance/"*)
                address=$(echo "$path" | sed 's|/balance/||')
                response=$(handle_balance_request "$address")
                ;;
            *)
                response="{\"status\":\"error\",\"message\":\"Endpoint not found. Available endpoints: /health, /fund/{address} (POST), /balance/{address}\"}"
                ;;
        esac
        
        echo -e "HTTP/1.1 200 OK\r"
        echo -e "Content-Type: application/json\r"
        echo -e "Access-Control-Allow-Origin: *\r"
        echo -e "Access-Control-Allow-Methods: GET, POST, OPTIONS\r"
        echo -e "Access-Control-Allow-Headers: Content-Type\r"
        echo -e "Content-Length: ${#response}\r"
        echo -e "\r"
        echo -n "$response"
        
    } | nc -l -p "$PORT" -q 1
done
