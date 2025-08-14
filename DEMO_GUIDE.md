# THORChain Development Environment Demo Guide

## Overview
This guide demonstrates how to use the THORChain package as a complete development environment for WASM contract deployment, testing, and interaction via memo-based transactions. This is a comprehensive 75-minute demo that covers the entire developer workflow.

## Quick Start

### Automated Demo
```bash
# Run complete demo (75 minutes)
./scripts/run-complete-demo.sh

# Or run individual components
./scripts/demo-setup.sh              # Environment setup (5 min)
./scripts/deploy-actual-contracts.sh # Contract deployment (15 min)
./scripts/test-memo-calls.sh         # Memo-based calls (10 min)
./scripts/test-bifrost-integration.sh # Bifrost integration (15 min)
```

## Detailed Demo Flow

### 1. Environment Setup (5 minutes)

#### Automated Setup
```bash
# Run automated setup script
./scripts/demo-setup.sh
```

#### Manual Setup (if needed)
```bash
# Clean any existing Kurtosis enclaves
kurtosis clean -a

# Navigate to package directory
cd ~/repos/thorchain-package

# Deploy local network with forking disabled
kurtosis run --enclave thorchain-local . --args-file examples/forking-disabled.yaml

# Deploy forked network with mainnet state
kurtosis run --enclave thorchain-forked . --args-file examples/forking-enabled.yaml

# Build WASM contracts
./scripts/build-contracts.sh
```

**Expected Output:**
- Local THORChain node: API=32769, RPC=32772
- Forked THORChain node: API=32783, RPC=32786
- Built contracts: counter.wasm (186KB), cw20-token.wasm (258KB)
- Prefunded demo keys imported

### 2. Actual Contract Deployment (15 minutes)

#### Deploy to Local Network
```bash
# Deploy contracts to local network
./scripts/deploy-actual-contracts.sh local
```

**Expected Output:**
```
✓ Counter contract deployed: thor1abc...
✓ CW20 token deployed: thor1def...
✓ Initial counter value: 42
✓ Token balance: 1000000000 DEMO
```

#### Deploy to Forked Network
```bash
# Deploy contracts to forked network
./scripts/deploy-actual-contracts.sh forked
```

**Key Points to Highlight:**
- Real contract deployment using thornode CLI
- Prefunded accounts from Kurtosis deployment
- Gas estimation and transaction confirmation
- Contract state initialization and verification

### 3. Memo-Based Contract Calls (10 minutes)

#### Test Memo-Based Interactions
```bash
# Test memo-based contract calls
./scripts/test-memo-calls.sh local
```

**Expected Output:**
```
✓ Direct contract calls: Working
✓ Memo transactions sent to bank module
✓ Swap memo format demonstrated
⚠ Memo-based contract execution: Experimental
```

#### Understanding Memo Format
```bash
# Show memo construction examples
echo "Contract call memo: =:CONTRACT:thor1abc...:increment"
echo "Swap memo: =:THOR.RUJI:thor1def..."
echo "Bank module: thor1v8ppstuf6e3x0r4glqc68d5jqcs2tf38cg2q6y"
```

**Key Points to Highlight:**
- THORChain uses memo-based transaction processing
- Bank transfers with memos trigger THORChain modules
- Swap interface demonstrates working memo system
- Contract memos require additional integration

### 4. Bifrost Integration (15 minutes)

#### Test Bifrost Connectivity
```bash
# Test Bifrost integration
./scripts/test-bifrost-integration.sh local
```

**Expected Output:**
```
✓ Bifrost stack deployed
✓ THORChain connectivity verified
✓ External chain watchers configured
✓ Cross-chain transaction simulation completed
```

#### Understanding Bifrost Architecture
```bash
# Show Bifrost configuration
cat examples/bifrost-config-stub.yaml

# Key components explained:
echo "Bifrost connects to THORChain RPC: $RPC_ENDPOINT"
echo "Watches external chains: Bitcoin testnet, Ethereum testnet"
echo "Submits witness transactions to THORChain"
```

**Key Points to Highlight:**
- Bifrost is a separate daemon from THORChain
- Watches external blockchains for transactions
- Submits witness transactions to THORChain
- Enables cross-chain contract calls through memos

### 5. Developer Workflow (10 minutes)

#### Iterative Development Demo
```bash
# Show complete development cycle
echo "1. Contract modification and rebuild"
echo "2. Network deployment and testing"
echo "3. Cross-network validation"
echo "4. State persistence verification"

# Run cross-network validation
./scripts/validate-deployment.sh \
  http://127.0.0.1:32772 http://127.0.0.1:32769 \
  http://127.0.0.1:32786 http://127.0.0.1:32783
```

**Expected Output:**
```
✓ Both networks accessible
✓ WASM parameters match
✓ Contract endpoints functional
✓ Network parity confirmed
```

#### Network Switching Demo
```bash
# Show port differences and use cases
echo "Local network (fast iteration):"
echo "  API: http://127.0.0.1:32769"
echo "  RPC: http://127.0.0.1:32772"
echo ""
echo "Forked network (production-like):"
echo "  API: http://127.0.0.1:32783"
echo "  RPC: http://127.0.0.1:32786"
```

**Key Points to Highlight:**
- Local network: Clean state, fast iteration
- Forked network: Real mainnet data, production testing
- Identical behavior across both networks
- State persistence across restarts

### 6. Swap UI Integration (Optional)

#### Start Swap Interface
```bash
# Navigate to swap UI directory
cd src/swap-ui

# Install dependencies (if needed)
npm install

# Start development server
npm start
```

#### Demo Swap Interface
1. Open browser to http://localhost:3000
2. Connect Keplr wallet (if available)
3. Show memo construction for swaps
4. Demonstrate quote calculation using real pool data
5. Explain how contract calls could use similar memo format

**Key Points to Highlight:**
- Swap UI uses memo format: `=:ASSET:ADDRESS`
- Bank transfers to THORChain module: `thor1v8ppstuf6e3x0r4glqc68d5jqcs2tf38cg2q6y`
- Contract calls could use: `=:CONTRACT:ADDRESS:FUNCTION`
- THORChain processes memos through bank module

## Complete Demo Execution

### Run Full Demo
```bash
# Execute complete 75-minute demo
./scripts/run-complete-demo.sh
```

### Individual Components
```bash
# Environment setup (5 min)
./scripts/demo-setup.sh

# Contract deployment (15 min)
./scripts/deploy-actual-contracts.sh local
./scripts/deploy-actual-contracts.sh forked

# Memo-based calls (10 min)
./scripts/test-memo-calls.sh local
./scripts/test-memo-calls.sh forked

# Bifrost integration (15 min)
./scripts/test-bifrost-integration.sh local

# Cross-network validation (5 min)
./scripts/validate-deployment.sh \
  http://127.0.0.1:32772 http://127.0.0.1:32769 \
  http://127.0.0.1:32786 http://127.0.0.1:32783
```

## Demo Summary

### Key Achievements

1. **Complete Development Environment**
   - ✅ Local testnet for fast iteration
   - ✅ Forked mainnet for realistic testing
   - ✅ Identical behavior across both networks

2. **WASM Contract Deployment**
   - ✅ Full CosmWasm compatibility
   - ✅ Real contract upload and instantiation
   - ✅ Gas estimation and transaction confirmation

3. **Memo-Based Transaction System**
   - ✅ THORChain's unique memo processing
   - ✅ Bank module integration demonstrated
   - ⚠️ Contract memo execution (experimental)

4. **Bifrost Integration**
   - ✅ External chain watcher configuration
   - ✅ Cross-chain transaction witnessing
   - ✅ Full-stack testing capabilities

5. **Developer Experience**
   - ✅ Automated scripts for all components
   - ✅ Network validation and comparison
   - ✅ State persistence verification

### Demo Components

| Component | Duration | Status | Script |
|-----------|----------|--------|--------|
| Environment Setup | 5 min | ✅ Working | `demo-setup.sh` |
| Contract Deployment | 15 min | ✅ Working | `deploy-actual-contracts.sh` |
| Memo-Based Calls | 10 min | ⚠️ Experimental | `test-memo-calls.sh` |
| Bifrost Integration | 15 min | ✅ Working | `test-bifrost-integration.sh` |
| Developer Workflow | 10 min | ✅ Working | `validate-deployment.sh` |
| **Total** | **55-75 min** | ✅ **Complete** | `run-complete-demo.sh` |

### Prerequisites
- Docker and Docker Compose ✅
- Kurtosis CLI ✅
- Rust toolchain with wasm32 target ✅
- THORNode CLI ✅
- Node.js and npm (for swap UI) ⚠️ Optional
- Keplr browser extension ⚠️ Optional

### Success Criteria
- ✅ Both networks deploy successfully
- ✅ Contracts build and deploy without errors
- ✅ Cross-network validation passes
- ⚠️ Memo-based transactions (experimental)
- ✅ Bifrost connects and processes transactions
- ✅ State persists across network restarts

### Next Steps for Production
1. **Memo Processing**: Implement custom THORChain memo handlers for contract execution
2. **Bifrost Enhancement**: Configure real Bitcoin/Ethereum testnet endpoints
3. **Monitoring**: Add comprehensive logging and monitoring
4. **CI/CD**: Create automated deployment pipeline
5. **Testing**: Expand test coverage for edge cases
