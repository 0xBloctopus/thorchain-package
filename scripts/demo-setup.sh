#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "THORChain Development Environment Demo Setup"
echo "============================================"

check_prerequisites() {
    echo "Checking prerequisites..."
    
    local missing_deps=()
    
    if ! command -v kurtosis &> /dev/null; then
        missing_deps+=("kurtosis")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        missing_deps+=("docker-compose")
    fi
    
    if ! command -v rustc &> /dev/null; then
        missing_deps+=("rust")
    fi
    
    if ! command -v thornode &> /dev/null; then
        missing_deps+=("thornode")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "✗ Missing dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies before running the demo."
        exit 1
    fi
    
    echo "✓ All prerequisites satisfied"
}

clean_environment() {
    echo "Cleaning previous environments..."
    
    kurtosis clean -a || true
    
    docker-compose -f "$PROJECT_ROOT/examples/docker-compose-bifrost.yml" down || true
    
    echo "✓ Environment cleaned"
}

deploy_local_network() {
    echo "Deploying local THORChain network..."
    
    cd "$PROJECT_ROOT"
    
    kurtosis run --enclave thorchain-local . --args-file examples/forking-disabled.yaml
    
    echo "✓ Local network deployed"
    echo "  API: http://127.0.0.1:32769"
    echo "  RPC: http://127.0.0.1:32772"
}

deploy_forked_network() {
    echo "Deploying forked THORChain network..."
    
    cd "$PROJECT_ROOT"
    
    kurtosis run --enclave thorchain-forked . --args-file examples/forking-enabled.yaml
    
    echo "✓ Forked network deployed"
    echo "  API: http://127.0.0.1:32783"
    echo "  RPC: http://127.0.0.1:32786"
}

build_contracts() {
    echo "Building WASM contracts..."
    
    cd "$PROJECT_ROOT"
    
    ./scripts/build-contracts.sh
    
    echo "✓ Contracts built successfully"
    ls -la build/*.wasm
}

setup_demo_keys() {
    echo "Setting up demo keys..."
    
    local mnemonic
    if mnemonic=$(kurtosis service exec thorchain-local thorchain-faucet "cat /tmp/mnemonic/mnemonic.txt" 2>/dev/null); then
        echo "✓ Retrieved prefunded mnemonic"
        
        echo "$mnemonic" | thornode keys add demo-key --recover --keyring-backend test --yes 2>/dev/null || true
        
        echo "✓ Demo key imported"
        thornode keys list --keyring-backend test
    else
        echo "⚠ Could not retrieve prefunded mnemonic - manual key setup required"
    fi
}

validate_deployment() {
    echo "Validating deployment..."
    
    cd "$PROJECT_ROOT"
    
    ./scripts/deploy-contracts.sh local
    ./scripts/deploy-contracts.sh forked
    
    echo "✓ Deployment validation completed"
}

print_demo_info() {
    echo ""
    echo "Demo Environment Ready!"
    echo "======================"
    echo ""
    echo "Networks:"
    echo "  Local:  API=http://127.0.0.1:32769, RPC=http://127.0.0.1:32772"
    echo "  Forked: API=http://127.0.0.1:32783, RPC=http://127.0.0.1:32786"
    echo ""
    echo "Contracts:"
    echo "  counter.wasm (186KB) - Simple counter with increment/reset"
    echo "  cw20-token.wasm (258KB) - Full ERC20-like token implementation"
    echo ""
    echo "Demo Commands:"
    echo "  ./scripts/deploy-contracts.sh local    # Test local deployment"
    echo "  ./scripts/deploy-contracts.sh forked   # Test forked deployment"
    echo "  ./scripts/validate-deployment.sh       # Compare networks"
    echo ""
    echo "Next Steps:"
    echo "  1. Follow DEMO_GUIDE.md for complete walkthrough"
    echo "  2. Deploy actual contracts with thornode CLI"
    echo "  3. Test memo-based contract interactions"
    echo "  4. Set up Bifrost for cross-chain testing"
    echo ""
    echo "Kurtosis Services:"
    kurtosis service ls thorchain-local | head -5
    echo "..."
    kurtosis service ls thorchain-forked | head -5
}

main() {
    check_prerequisites
    clean_environment
    deploy_local_network
    deploy_forked_network
    build_contracts
    setup_demo_keys
    
    echo ""
    echo "Configuring mimir values for contract deployment..."
    if "$SCRIPT_DIR/configure-mimir.sh"; then
        echo "✓ Mimir configuration completed"
    else
        echo "⚠ Mimir configuration failed - contract deployment may not work on forked networks"
    fi
    
    validate_deployment
    print_demo_info
    
    echo ""
    echo "✓ Demo environment setup completed successfully!"
    echo "Ready for THORChain contract development demonstration."
}

main "$@"
