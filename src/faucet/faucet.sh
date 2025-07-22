#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Configuration                                                                #
###############################################################################
CHAIN_ID="${CHAIN_ID:-thorchain-1}"
NODE_URL="${NODE_URL:-http://localhost:26657}"
TRANSFER_AMOUNT="${TRANSFER_AMOUNT:-100000000}rune"   # value must include 'rune'
PORT="${PORT:-8090}"
MONITORING_PORT="${MONITORING_PORT:-8091}"
LOCK_FILE="/tmp/faucet.lock"          # serialises key-ring access

###############################################################################
# One-time setup                                                               #
###############################################################################
echo "Starting Thorchain faucet service..."
echo "Chain ID:            $CHAIN_ID"
echo "Node URL:            $NODE_URL"
echo "Transfer Amount:     $TRANSFER_AMOUNT"
echo "API Port:            $PORT"
echo "Monitoring Port:     $MONITORING_PORT"

echo "Installing packages (bash image is slim)…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive \
apt-get install -y --no-install-recommends \
        netcat-openbsd util-linux jq > /dev/null
rm -rf /var/lib/apt/lists/*

echo "Importing faucet key…"
thornode keys delete faucet --keyring-backend test --yes 2>/dev/null || true
< /tmp/mnemonic/mnemonic.txt thornode keys add faucet --recover --keyring-backend test \
    >/dev/null
echo "Faucet key imported"

###############################################################################
# Helper: wait for node                                                       #
###############################################################################
check_node_ready() {
    for ((i = 1; i <= 30; i++)); do
        curl -sf "$NODE_URL/status" >/dev/null && { echo "Node is ready!"; return 0; }
        echo "Waiting for node… ($i/30)"; sleep 2
    done
    echo "Node did not become ready"; exit 1
}
check_node_ready

###############################################################################
# Funding logic                                                               #
###############################################################################
handle_funding_request() {
    local address="$1"
    local tmpdir; tmpdir=$(mktemp -d)
    local raw="$tmpdir/tx_raw.json"
    local signed="$tmpdir/tx.json"

    echo "[fund] $(date +%T) → $address" >&2

    # ---- build MsgSend (generate-only) -------------------------------------
    flock "$LOCK_FILE" thornode tx bank send faucet "$address" "$TRANSFER_AMOUNT" \
        --chain-id "$CHAIN_ID" --node "$NODE_URL" \
        --keyring-backend test --generate-only --output json >"$raw"

    # ---- patch Msg type for THORChain --------------------------------------
    sed -i 's|/cosmos.bank.v1beta1.MsgSend|/types.MsgSend|g' "$raw"

    # ---- sign (amino-json) -------------------------------------------------
    flock "$LOCK_FILE" thornode tx sign "$raw" \
        --from faucet --sign-mode amino-json --chain-id "$CHAIN_ID" \
        --keyring-backend test --node "$NODE_URL" --output json >"$signed"

    # ---- broadcast & capture result ---------------------------------------
    local bcast; bcast=$(thornode tx broadcast "$signed" \
                    --chain-id "$CHAIN_ID" --node "$NODE_URL" \
                    --gas auto --output json 2>&1) || true

    rm -rf "$tmpdir"

    # ---- build HTTP response ----------------------------------------------
    if jq -e '.code? // 0' <<<"$bcast" | grep -q '^0$'; then
        local hash; hash=$(jq -r '.txhash' <<<"$bcast")
        printf '{"status":"success","txHash":"%s","message":"Funded %s with %s"}' \
               "$hash" "$address" "$TRANSFER_AMOUNT"
    else
        # escape newlines↴
        bcast=${bcast//$'\n'/  }
        printf '{"status":"error","message":"%s"}' "$bcast"
    fi
}

handle_balance_request() {
    local address="$1"
    local res; res=$(thornode query bank balances "$address" --node "$NODE_URL" -o json)
    printf '{"status":"success","balances":%s}' "$res"
}

handle_health_check() {
    printf '{"status":"healthy","chain_id":"%s","node_url":"%s"}' \
           "$CHAIN_ID" "$NODE_URL"
}

###############################################################################
# Tiny HTTP listener (Bash + nc + coproc)                                     #
###############################################################################
echo "HTTP server listening on :$PORT"

while true; do
    coproc NC { nc -l -p "$PORT" -q 0; }

    IFS= read -r request_line <&"${NC[0]}" || { exec {NC[0]}>&- {NC[1]}>&-; continue; }
    IFS= read -r _host_line   <&"${NC[0]}"

    # Parse headers & capture Content-Length (so we can drain the body)
    content_length=0
    origin_header=""
    while IFS= read -r hdr <&"${NC[0]}"; do
        hdr=${hdr%$'\r'}
        [[ -z $hdr ]] && break
        case "$hdr" in
            Content-Length:*) content_length=${hdr#*: }; content_length=${content_length//[[:space:]]/} ;;
            Origin:*)         origin_header=${hdr#*: } ;;
        esac
    done

    method=${request_line%% *}
    path=${request_line#* }; path=${path%% *}
    echo "[$(date +%T)] $method $path" >&2

    # Drain request body if present (we don't actually use it)
    if [[ "$content_length" -gt 0 ]]; then
        dd bs=1 count="$content_length" of=/dev/null <&"${NC[0]}" 2>/dev/null
    fi

    case "$method $path" in
        OPTIONS\ *)
            status='HTTP/1.1 204 No Content'; body='' ;;
        GET\ /health)
            status='HTTP/1.1 200 OK';        body=$(handle_health_check) ;;
        POST\ /fund/*)
            addr=${path#/fund/}
            status='HTTP/1.1 200 OK';        body=$(handle_funding_request "$addr") ;;
        GET\ /balance/*)
            addr=${path#/balance/}
            status='HTTP/1.1 200 OK';        body=$(handle_balance_request "$addr") ;;
        *)
            status='HTTP/1.1 404 Not Found'; body='{"status":"error","message":"Endpoint not found"}' ;;
    esac

    {
        printf '%s\r\n' "$status"
        printf 'Content-Type: application/json\r\n'
        # CORS headers
        printf 'Access-Control-Allow-Origin: *\r\n'
        printf 'Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n'
        printf 'Access-Control-Allow-Headers: *\r\n'
        printf 'Access-Control-Max-Age: 86400\r\n'
        printf 'Connection: close\r\n'
        printf 'Content-Length: %s\r\n' "${#body}"
        printf '\r\n%s' "$body"
    } >&"${NC[1]}"

    exec {NC[0]}>&- {NC[1]}>&-
done