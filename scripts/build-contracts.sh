#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONTRACTS_DIR="$PROJECT_ROOT/contracts"
BUILD_DIR="$PROJECT_ROOT/build"

echo "Building THORChain test contracts..."

mkdir -p "$BUILD_DIR"

check_rust_toolchain() {
    if ! command -v rustc &> /dev/null; then
        echo "Error: Rust is not installed. Please install Rust first."
        exit 1
    fi
    
    if ! rustup target list --installed | grep -q "wasm32-unknown-unknown"; then
        echo "Installing wasm32-unknown-unknown target..."
        rustup target add wasm32-unknown-unknown
    fi
}

optimize_wasm() {
    local contract_name=$1
    local wasm_file="$BUILD_DIR/${contract_name}.wasm"
    
    if command -v wasm-opt &> /dev/null; then
        echo "Optimizing $contract_name with wasm-opt..."
        wasm-opt -Oz --enable-sign-ext "$wasm_file" -o "$wasm_file"
    else
        echo "Warning: wasm-opt not found. Install binaryen for optimization."
    fi
    
    echo "Contract size: $(du -h "$wasm_file" | cut -f1)"
}

build_contract() {
    local contract_name=$1
    local contract_dir="$CONTRACTS_DIR/$contract_name"
    
    if [ ! -d "$contract_dir" ]; then
        echo "Error: Contract directory $contract_dir not found"
        return 1
    fi
    
    echo "Building contract: $contract_name"
    cd "$contract_dir"
    
    cargo build --release --target wasm32-unknown-unknown
    
    local wasm_file="target/wasm32-unknown-unknown/release/${contract_name//-/_}.wasm"
    if [ -f "$wasm_file" ]; then
        cp "$wasm_file" "$BUILD_DIR/${contract_name}.wasm"
        optimize_wasm "$contract_name"
        echo "✓ Built $contract_name successfully"
    else
        echo "✗ Failed to build $contract_name"
        return 1
    fi
}

generate_checksums() {
    echo "Generating checksums..."
    cd "$BUILD_DIR"
    for wasm_file in *.wasm; do
        if [ -f "$wasm_file" ]; then
            sha256sum "$wasm_file" > "${wasm_file}.sha256"
        fi
    done
}

main() {
    echo "THORChain Contract Build Script"
    echo "==============================="
    
    check_rust_toolchain
    
    local contracts=("counter" "cw20-token")
    local failed_contracts=()
    
    for contract in "${contracts[@]}"; do
        if ! build_contract "$contract"; then
            failed_contracts+=("$contract")
        fi
    done
    
    if [ ${#failed_contracts[@]} -eq 0 ]; then
        generate_checksums
        echo ""
        echo "✓ All contracts built successfully!"
        echo "Built contracts:"
        ls -la "$BUILD_DIR"/*.wasm
    else
        echo ""
        echo "✗ Failed to build contracts: ${failed_contracts[*]}"
        exit 1
    fi
}

main "$@"
