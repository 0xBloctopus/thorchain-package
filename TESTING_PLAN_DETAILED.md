# Comprehensive Contract Deployment & Bifrost Integration Testing Plan

## Executive Summary

This document outlines a comprehensive testing strategy for validating contract deployment capabilities on THORChain networks and integrating Bifrost watchers for cross-chain functionality. The plan addresses three key scenarios: local development, forked mainnet testing, and full stack integration.

## Architecture Overview

### THORChain Package Current State
- **WASM Module**: Configured with open permissions ("Everybody" can upload/instantiate)
- **Forking Support**: Built-in mainnet state forking with configurable RPC endpoints
- **Service Architecture**: Modular design with faucet, bdjuno, and swap-ui services
- **No Bifrost**: Current package only deploys THORChain validators

### Bifrost Integration Architecture
- **Separate Daemon**: Bifrost runs independently from THORChain consensus
- **Chain Client Separation**: Lives in `/bifrost` package outside core state machine
- **Configuration-Driven**: Points to any THORChain via `ChainRPC` configuration
- **Multi-Chain Support**: Watches multiple L1s via per-chain `RPCHost` settings

## Testing Approaches

### Approach 1: Mocknet/Local (Development)
**Purpose**: Rapid contract iteration and memo flow testing
**Components**: THORNode + Midgard + mock L1s
**Benefits**: Fastest feedback loop, isolated environment
**Use Cases**: 
- Contract development and debugging
- Basic functionality validation
- Unit testing equivalent for contracts

### Approach 2: Hybrid (Recommended)
**Purpose**: Realistic testing with controlled external dependencies
**Components**: Forked THORChain + own Bifrost + real/forked L1s
**Benefits**: Balance of realism and control
**Use Cases**:
- Integration testing with real mainnet state
- Cross-chain transaction validation
- Performance testing under realistic conditions

### Approach 3: Full Stack (Comprehensive)
**Purpose**: Complete hermetic testing environment
**Components**: THORChain + Bifrost + forked L1s (BTC regtest, ETH anvil)
**Benefits**: Complete isolation and reproducibility
**Use Cases**:
- End-to-end testing
- Regression testing
- Production-like validation

## Detailed Test Scenarios

### Phase 1: Contract Deployment Validation

#### Test 1.1: WASM Permission Consistency
**Objective**: Verify identical contract deployment behavior across network types

**Test Matrix**:
| Network Type | WASM Upload | WASM Instantiate | Expected Result |
|--------------|-------------|------------------|-----------------|
| Local Testnet | ✓ | ✓ | Success |
| Forked Mainnet | ✓ | ✓ | Success |
| Comparison | - | - | Identical behavior |

**Validation Criteria**:
- Both networks return identical WASM module parameters
- Contract upload succeeds with same gas costs
- Instantiation permissions match exactly
- No network-specific restrictions observed

**Test Commands**:
```bash
# Check WASM parameters
curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/params" | jq '.params'

# Verify upload permissions
curl -s "$THORCHAIN_API/cosmwasm/wasm/v1/code" | jq '.code_infos'
```

#### Test 1.2: Contract State Persistence
**Objective**: Ensure contract state survives network operations

**Test Sequence**:
1. Deploy contract on both network types
2. Execute state-changing transactions
3. Query contract state via CosmWasm API
4. Restart network services
5. Re-query state and verify persistence
6. Compare state consistency between networks

**Validation Criteria**:
- Contract state persists across service restarts
- State queries return consistent data
- No data corruption in forked environment
- State transitions work identically on both networks

#### Test 1.3: Contract Interaction Patterns
**Objective**: Validate complex contract interaction scenarios

**Test Contracts**:
- **Counter Contract**: Basic state management
- **CW20 Token**: Token standard implementation  
- **Multi-Contract System**: Contract-to-contract calls
- **Cross-Module Integration**: Interaction with THORChain modules

**Validation Criteria**:
- All contract types deploy successfully
- Inter-contract calls work correctly
- Gas estimation matches between networks
- Error handling behaves consistently

### Phase 2: Bifrost Integration Testing

#### Test 2.1: Bifrost Connection Validation
**Objective**: Verify Bifrost can connect to forked THORChain

**Configuration Test**:
```yaml
thorchain:
  chain_rpc: "http://forked-thorchain:26657"
  chain_host: "http://forked-thorchain:1317"
  chain_id: "thorchain-testnet"
```

**Validation Steps**:
1. Start forked THORChain network
2. Configure Bifrost with forked endpoints
3. Verify Bifrost connects successfully
4. Check Bifrost logs for connection status
5. Validate TSS key generation process

**Success Criteria**:
- Bifrost establishes RPC connection
- Chain ID validation passes
- TSS initialization completes
- No connection errors in logs

#### Test 2.2: External Chain Integration
**Objective**: Test Bifrost monitoring of external chains

**External Chain Matrix**:
| Chain | Type | RPC Endpoint | Router Contract |
|-------|------|--------------|-----------------|
| Bitcoin | Regtest | bitcoind:18443 | N/A |
| Ethereum | Anvil Fork | anvil:8545 | Deployed |
| BSC | Testnet | bsc-testnet:8545 | Deployed |

**Test Sequence**:
1. Deploy external chain infrastructure
2. Configure Bifrost chain watchers
3. Generate test transactions on external chains
4. Verify Bifrost detects and processes transactions
5. Check witness submissions to THORChain

**Validation Criteria**:
- All configured chains connect successfully
- Transaction detection works correctly
- Witness messages submitted to THORChain
- No missed or duplicate transactions

#### Test 2.3: Cross-Chain Transaction Flow
**Objective**: End-to-end cross-chain transaction validation

**Test Flow**:
1. **Inbound**: External chain → THORChain
2. **Swap**: THORChain internal processing
3. **Outbound**: THORChain → External chain

**Validation Points**:
- Inbound transaction detection
- Memo parsing and validation
- Pool state updates
- Outbound transaction signing
- External chain confirmation

### Phase 3: Network Swapping Validation

#### Test 3.1: THORChain Instance Swapping
**Objective**: Verify seamless THORChain instance replacement

**Test Procedure**:
1. Deploy initial forked THORChain (Instance A)
2. Deploy contracts and establish state
3. Start Bifrost pointing to Instance A
4. Deploy new forked THORChain (Instance B)
5. Update Bifrost configuration to point to Instance B
6. Verify service continuity

**Validation Criteria**:
- Bifrost reconnects without restart
- No transaction loss during transition
- State consistency maintained
- External services adapt correctly

#### Test 3.2: External Chain Swapping
**Objective**: Test switching external chain endpoints

**Test Matrix**:
| Original | Target | Expected Behavior |
|----------|--------|-------------------|
| Mainnet ETH | Anvil Fork | Seamless transition |
| Testnet BTC | Regtest | Configuration update |
| Live BSC | Local Fork | State reset handling |

**Validation Steps**:
1. Configure Bifrost with original endpoints
2. Establish baseline transaction monitoring
3. Update chain configuration to target endpoints
4. Restart Bifrost with new configuration
5. Verify new chain monitoring begins correctly

## Performance & Load Testing

### Test 4.1: Forking Performance
**Objective**: Validate forking performance under load

**Test Parameters**:
- Cache sizes: 1K, 10K, 100K entries
- Concurrent requests: 10, 50, 100 per second
- State fetch patterns: Sequential, random, burst

**Metrics**:
- Response time percentiles (p50, p95, p99)
- Cache hit rates
- Memory usage patterns
- Network bandwidth utilization

### Test 4.2: Contract Execution Performance
**Objective**: Compare contract performance across network types

**Test Contracts**:
- Compute-intensive operations
- Storage-heavy operations
- Cross-contract calls
- Module interactions

**Comparison Matrix**:
| Metric | Local Network | Forked Network | Variance |
|--------|---------------|----------------|----------|
| Gas Usage | Baseline | Measured | < 5% |
| Execution Time | Baseline | Measured | < 10% |
| Memory Usage | Baseline | Measured | < 15% |

## Security & Edge Case Testing

### Test 5.1: Network Partition Handling
**Objective**: Validate behavior during network issues

**Scenarios**:
- Bifrost loses connection to THORChain
- External chain RPC becomes unavailable
- Partial network connectivity
- High latency conditions

**Validation**:
- Graceful degradation
- Automatic reconnection
- Transaction queue handling
- Error reporting accuracy

### Test 5.2: State Inconsistency Detection
**Objective**: Identify and handle state mismatches

**Test Cases**:
- Forked state diverges from mainnet
- Contract state corruption
- Cross-chain state inconsistencies
- Rollback scenarios

**Detection Methods**:
- State hash comparisons
- Transaction replay validation
- Cross-reference with multiple sources
- Automated inconsistency alerts

## Automation & CI Integration

### Test 6.1: Automated Test Suite
**Components**:
- Contract deployment automation
- Bifrost configuration validation
- Cross-chain transaction simulation
- Performance regression detection

**Test Execution**:
```bash
# Run complete test suite
./run-thorchain-tests.sh --mode=comprehensive

# Run specific test phases
./run-thorchain-tests.sh --phase=contracts
./run-thorchain-tests.sh --phase=bifrost
./run-thorchain-tests.sh --phase=integration
```

### Test 6.2: Continuous Validation
**Monitoring**:
- Network health checks
- Contract state validation
- Bifrost connectivity monitoring
- Performance metric tracking

**Alerting**:
- Test failure notifications
- Performance degradation alerts
- Configuration drift detection
- Security anomaly reporting

## Success Criteria Summary

### Contract Deployment
- ✅ Identical WASM permissions across network types
- ✅ Contract state persistence and consistency
- ✅ Performance parity within acceptable variance
- ✅ Error handling consistency

### Bifrost Integration
- ✅ Successful connection to forked THORChain
- ✅ External chain monitoring functionality
- ✅ Cross-chain transaction processing
- ✅ Network swapping capabilities

### Developer Experience
- ✅ Clear iteration path: local → staging → mainnet
- ✅ Comprehensive documentation and examples
- ✅ Automated testing and validation
- ✅ Troubleshooting guides and error resolution

## Risk Mitigation

### Technical Risks
- **State Divergence**: Regular state validation and rollback procedures
- **Performance Degradation**: Continuous monitoring and alerting
- **Security Vulnerabilities**: Regular security audits and penetration testing
- **Integration Failures**: Comprehensive test coverage and staging validation

### Operational Risks
- **Configuration Errors**: Automated configuration validation
- **Service Dependencies**: Health checks and automatic failover
- **Data Loss**: Regular backups and recovery procedures
- **Monitoring Gaps**: Comprehensive observability and alerting

## Implementation Timeline

### Phase 1: Foundation (Weeks 1-2)
- Set up test infrastructure
- Implement basic contract deployment tests
- Validate WASM configuration consistency

### Phase 2: Bifrost Integration (Weeks 3-4)
- Implement Bifrost configuration and deployment
- Test external chain integration
- Validate cross-chain transaction flows

### Phase 3: Advanced Testing (Weeks 5-6)
- Performance and load testing
- Security and edge case validation
- Automation and CI integration

### Phase 4: Documentation & Handoff (Week 7)
- Complete documentation
- Training and knowledge transfer
- Production readiness validation

This comprehensive testing plan ensures thorough validation of both contract deployment capabilities and Bifrost integration while maintaining developer productivity and system reliability.
