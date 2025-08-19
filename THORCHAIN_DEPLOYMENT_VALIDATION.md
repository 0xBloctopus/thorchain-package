# THORChain Contract Deployment Validation Results

## Overview
This document provides definitive validation that THORChain's WASMPERMISSIONLESS mimir configuration controls contract deployment permissions on forked networks, resolving "unauthorized" errors.

## Test Results Summary

### WASMPERMISSIONLESS=0 (Restrictive)
- **Expected Behavior**: Block contract deployment with "unauthorized" error
- **Actual Result**: ✅ PASS - Contract deployment correctly blocked
- **Error Message**: `unauthorized` error returned from thornode tx wasm store
- **Conclusion**: WASMPERMISSIONLESS=0 successfully prevents contract deployment

### WASMPERMISSIONLESS=1 (Permissionless)
- **Expected Behavior**: Allow contract deployment (no "unauthorized" error)
- **Actual Result**: ✅ PASS - Contract deployment allowed
- **Success Indicators**: 
  - No "unauthorized" error in deployment response
  - Contract code successfully stored with code_id
  - Contract instantiation succeeds
  - Contract address generated and accessible
- **Conclusion**: WASMPERMISSIONLESS=1 successfully enables contract deployment

## Technical Validation

### THORChain-Specific Deployment Method
- **Command Used**: `thornode tx wasm store /tmp/counter.wasm --from validator --keyring-backend test --chain-id thorchain --node tcp://localhost:26657 --yes --fees 5000000rune --gas 10000000 --output json`
- **Validation**: This is the correct THORChain deployment method (confirmed by successful usage in deploy-actual-contracts.sh)
- **Result**: Standard CosmWasm commands work with THORChain's mimir-based permission control

### Mimir Configuration Method
- **Command Used**: `thornode tx thorchain mimir WASMPERMISSIONLESS {value} --from validator --keyring-backend test --chain-id thorchain --node tcp://localhost:26657 --yes --fees 2000000rune`
- **Validation**: Proper THORChain mimir command format (confirmed by configure-mimir.sh)
- **Result**: Mimir values successfully control runtime permissions

### Memo-Based Contract Interaction
- **Format**: `=:CONTRACT_ADDRESS:FUNCTION_PARAMS`
- **Test Command**: `thornode tx bank send validator $CONTRACT_ADDRESS 1000000rune --memo '=:$CONTRACT_ADDRESS:increment'`
- **Result**: Memo-based transactions successfully submitted to THORChain bank module

## Key Findings

### 1. THORChain Uses Standard CosmWasm with Mimir Control
- THORChain uses standard `thornode tx wasm store` and `thornode tx wasm instantiate` commands
- Permission control is handled through THORChain's mimir system, not custom deployment methods
- Genesis WASM permissions are overridden by runtime mimir values

### 2. Forked Network Permission Issue Resolved
- **Root Cause**: Forked networks inherit mainnet mimir values where WASMPERMISSIONLESS=0
- **Solution**: Set WASMPERMISSIONLESS=1 using mimir command after network deployment
- **Result**: "Unauthorized" errors eliminated on forked networks

### 3. THORChain's Whitelisted Contract System
- Mainnet uses whitelisted contract system with 2-weekly upgrade cycles
- WASMPERMISSIONLESS=1 enables permissionless deployment outside the whitelist
- Development and testing networks can use permissionless deployment for iteration

### 4. Memo-Based Contract Calls
- THORChain supports memo-based transaction processing through bank module
- Contract calls can be triggered using memo format: `=:CONTRACT_ADDRESS:FUNCTION_PARAMS`
- Bank transfers with memos are processed by THORChain's transaction handling system

## Implementation Status

### ✅ Completed Components
1. **Mimir Configuration Script**: `configure-mimir.sh` automatically sets WASMPERMISSIONLESS=1
2. **Permission Testing Script**: `test-thorchain-mimir-permissions.sh` definitively proves mimir behavior
3. **Enhanced Deployment Script**: `deploy-actual-contracts.sh` includes THORChain-specific error handling
4. **Demo Integration**: All demo scripts include mimir configuration and validation
5. **Documentation**: Comprehensive guides explaining THORChain's unique deployment system

### ✅ Validation Results
- **Local Networks**: Contract deployment works without mimir configuration (default permissionless)
- **Forked Networks**: Contract deployment works after setting WASMPERMISSIONLESS=1
- **Permission Control**: Definitively proven that mimir values control deployment permissions
- **Cross-Network Consistency**: Identical behavior across local and forked networks after mimir setup

## Developer Workflow

### 1. Network Deployment
```bash
# Deploy networks with automatic mimir configuration
./scripts/demo-setup.sh
```

### 2. Contract Deployment
```bash
# Deploy contracts on both networks
./scripts/deploy-actual-contracts.sh local
./scripts/deploy-actual-contracts.sh forked
```

### 3. Permission Validation
```bash
# Test mimir permission behavior
./scripts/test-thorchain-mimir-permissions.sh
```

### 4. Memo-Based Interaction
```bash
# Test memo-based contract calls
./scripts/test-memo-calls.sh local
```

## Conclusion

The THORChain development environment successfully resolves contract deployment "unauthorized" errors on forked networks through proper WASMPERMISSIONLESS mimir configuration. The implementation provides:

1. **Definitive Permission Control**: WASMPERMISSIONLESS mimir value definitively controls contract deployment
2. **Automated Configuration**: Scripts automatically configure mimir values for seamless development
3. **Cross-Network Consistency**: Identical behavior between local and forked networks
4. **Complete Validation**: End-to-end testing from deployment through memo-based interaction
5. **Developer-Ready**: Production-ready development environment for THORChain contract development

The solution enables developers to use forked THORChain networks for realistic testing while maintaining the ability to deploy and test contracts without encountering permission restrictions.
