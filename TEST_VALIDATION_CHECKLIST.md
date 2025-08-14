# THORChain Contract Deployment & Bifrost Integration - Validation Checklist

## Pre-Test Setup Validation

### Environment Preparation
- [ ] Kurtosis installed and running
- [ ] Docker daemon active with sufficient resources
- [ ] Git repository cloned and up-to-date
- [ ] Required images pulled (thornode-forking, bifrost, etc.)
- [ ] Network connectivity to external RPC endpoints verified

### Configuration Files Validation
- [ ] `enhanced-testing-config.yaml` syntax validated
- [ ] `bifrost-config-stub.yaml` matches bifrost/config types
- [ ] `docker-compose-bifrost.yml` services defined correctly
- [ ] `test-contract-deployment.sh` executable permissions set
- [ ] All placeholder values (IPs, addresses) updated

## Phase 1: Contract Deployment Testing

### 1.1 WASM Permission Verification
- [ ] **Local Network Deployment**
  - [ ] Network starts successfully
  - [ ] First block produced within timeout
  - [ ] RPC endpoint accessible (port 26657)
  - [ ] API endpoint accessible (port 1317)
  - [ ] WASM module parameters retrieved successfully

- [ ] **Forked Network Deployment**
  - [ ] Forking configuration applied correctly
  - [ ] Mainnet state fetched successfully
  - [ ] Cache enabled and functioning
  - [ ] Network starts with forked state
  - [ ] WASM module parameters match local network

- [ ] **Permission Comparison**
  - [ ] `code_upload_access.permission` = "Everybody" on both
  - [ ] `instantiate_default_permission` = "Everybody" on both
  - [ ] No additional restrictions on forked network
  - [ ] API responses identical between networks

### 1.2 Contract State Persistence
- [ ] **Contract Deployment**
  - [ ] Test contract (counter.wasm) uploads successfully
  - [ ] Contract instantiation completes without errors
  - [ ] Contract address returned and accessible
  - [ ] Initial state query returns expected values

- [ ] **State Modification**
  - [ ] Execute state-changing transactions
  - [ ] Transaction confirmations received
  - [ ] State queries reflect changes
  - [ ] Gas usage within expected ranges

- [ ] **Persistence Validation**
  - [ ] Network restart completed successfully
  - [ ] Contract state preserved after restart
  - [ ] State queries return consistent data
  - [ ] No data corruption detected

### 1.3 Network Type Comparison
- [ ] **Deployment Consistency**
  - [ ] Same contract deploys on both networks
  - [ ] Gas costs within 5% variance
  - [ ] Execution times within 10% variance
  - [ ] Error messages identical

- [ ] **API Endpoint Validation**
  - [ ] `/cosmwasm/wasm/v1/params` returns consistent data
  - [ ] `/cosmwasm/wasm/v1/code` shows uploaded contracts
  - [ ] `/thorchain/pools` returns forked pool data (forked network)
  - [ ] `/cosmos/bank/v1beta1/balances/{address}` shows correct balances

## Phase 2: Bifrost Integration Testing

### 2.1 Bifrost Connection Validation
- [ ] **THORChain Network Ready**
  - [ ] Forked THORChain network running
  - [ ] RPC endpoint accessible from Bifrost container
  - [ ] API endpoint accessible from Bifrost container
  - [ ] Chain ID matches Bifrost configuration

- [ ] **Bifrost Configuration**
  - [ ] `bifrost-config-stub.yaml` syntax valid
  - [ ] THORChain endpoints correctly specified
  - [ ] External chain configurations present
  - [ ] Disabled chains properly excluded

- [ ] **Connection Establishment**
  - [ ] Bifrost container starts successfully
  - [ ] RPC connection to THORChain established
  - [ ] Chain ID validation passes
  - [ ] TSS initialization begins
  - [ ] No connection errors in logs

### 2.2 External Chain Integration
- [ ] **Bitcoin Regtest Setup**
  - [ ] bitcoind-regtest container running
  - [ ] RPC endpoint accessible (port 18443)
  - [ ] Authentication working (thorchain:password)
  - [ ] Initial blocks generated
  - [ ] Bifrost connects to Bitcoin RPC

- [ ] **Ethereum Anvil Setup**
  - [ ] anvil-eth container running
  - [ ] Fork from mainnet successful
  - [ ] RPC endpoint accessible (port 8545)
  - [ ] Recent block data available
  - [ ] Bifrost connects to Ethereum RPC

- [ ] **Chain Watcher Validation**
  - [ ] Bitcoin watcher starts successfully
  - [ ] Ethereum watcher starts successfully
  - [ ] Block scanning begins from configured height
  - [ ] No watcher errors in Bifrost logs

### 2.3 Cross-Chain Transaction Monitoring
- [ ] **Transaction Generation**
  - [ ] Bitcoin regtest transactions created
  - [ ] Ethereum anvil transactions created
  - [ ] Transactions include THORChain memos
  - [ ] Transactions confirmed on respective chains

- [ ] **Bifrost Detection**
  - [ ] Bifrost detects Bitcoin transactions
  - [ ] Bifrost detects Ethereum transactions
  - [ ] Memo parsing successful
  - [ ] Transaction details extracted correctly

- [ ] **Witness Submission**
  - [ ] Witness messages submitted to THORChain
  - [ ] Witness transactions confirmed
  - [ ] THORChain state updated correctly
  - [ ] No duplicate or missed transactions

## Phase 3: Network Swapping Validation

### 3.1 THORChain Instance Swapping
- [ ] **Initial Setup**
  - [ ] THORChain Instance A running
  - [ ] Bifrost connected to Instance A
  - [ ] Contracts deployed on Instance A
  - [ ] Baseline transaction monitoring active

- [ ] **Instance Deployment**
  - [ ] THORChain Instance B deployed successfully
  - [ ] Instance B has different state/configuration
  - [ ] Instance B accessible via different endpoints
  - [ ] Instance B producing blocks normally

- [ ] **Configuration Update**
  - [ ] Bifrost configuration updated to Instance B endpoints
  - [ ] Configuration reload/restart completed
  - [ ] New connection established successfully
  - [ ] Old connection cleanly terminated

- [ ] **Service Continuity**
  - [ ] No transaction loss during transition
  - [ ] Monitoring resumes on Instance B
  - [ ] State consistency maintained
  - [ ] External services adapt correctly

### 3.2 External Chain Swapping
- [ ] **Baseline Configuration**
  - [ ] Original external chains configured
  - [ ] Transaction monitoring active
  - [ ] Baseline metrics established
  - [ ] No errors in initial state

- [ ] **Chain Replacement**
  - [ ] New external chain endpoints configured
  - [ ] Bifrost configuration updated
  - [ ] Service restart completed successfully
  - [ ] New chain connections established

- [ ] **Monitoring Validation**
  - [ ] New chain monitoring begins
  - [ ] Block scanning starts from correct height
  - [ ] Transaction detection working
  - [ ] No configuration conflicts

## Phase 4: Performance & Load Testing

### 4.1 Forking Performance
- [ ] **Cache Performance**
  - [ ] Cache hit rates > 80% under normal load
  - [ ] Cache miss handling within timeout
  - [ ] Memory usage within acceptable limits
  - [ ] No cache corruption detected

- [ ] **Load Testing**
  - [ ] 10 req/sec sustained for 10 minutes
  - [ ] 50 req/sec sustained for 5 minutes
  - [ ] 100 req/sec burst for 1 minute
  - [ ] Response times < 2s at p95

- [ ] **Resource Monitoring**
  - [ ] CPU usage < 80% under load
  - [ ] Memory usage < 4GB under load
  - [ ] Network bandwidth within limits
  - [ ] Disk I/O not bottlenecked

### 4.2 Contract Execution Performance
- [ ] **Performance Comparison**
  - [ ] Local network baseline established
  - [ ] Forked network performance measured
  - [ ] Variance within acceptable limits
  - [ ] No performance regressions detected

- [ ] **Load Testing**
  - [ ] Multiple concurrent contract executions
  - [ ] Complex contract interactions tested
  - [ ] Gas usage patterns analyzed
  - [ ] Performance metrics collected

## Phase 5: Security & Edge Cases

### 5.1 Network Partition Handling
- [ ] **Connection Loss Scenarios**
  - [ ] Bifrost handles THORChain disconnection gracefully
  - [ ] External chain RPC failures handled correctly
  - [ ] Automatic reconnection attempts work
  - [ ] Transaction queuing during outages

- [ ] **Recovery Validation**
  - [ ] Services recover after network restoration
  - [ ] No transaction loss during outages
  - [ ] State consistency maintained
  - [ ] Error reporting accurate

### 5.2 Configuration Validation
- [ ] **Invalid Configuration Handling**
  - [ ] Invalid RPC endpoints rejected
  - [ ] Malformed configuration files detected
  - [ ] Missing required fields flagged
  - [ ] Graceful error messages provided

- [ ] **Security Validation**
  - [ ] No sensitive data in logs
  - [ ] Proper authentication mechanisms
  - [ ] Network access controls working
  - [ ] Container security best practices followed

## Final Validation

### Documentation Completeness
- [ ] All configuration files documented
- [ ] Test procedures clearly explained
- [ ] Troubleshooting guides available
- [ ] Example configurations provided

### Automation Readiness
- [ ] Test scripts executable
- [ ] CI/CD integration possible
- [ ] Monitoring and alerting configured
- [ ] Backup and recovery procedures documented

### Production Readiness
- [ ] All tests passing consistently
- [ ] Performance requirements met
- [ ] Security requirements satisfied
- [ ] Operational procedures documented

## Sign-off

### Technical Validation
- [ ] **Contract Deployment**: All tests passing
- [ ] **Bifrost Integration**: All tests passing  
- [ ] **Network Swapping**: All tests passing
- [ ] **Performance**: Requirements met
- [ ] **Security**: No critical issues

### Operational Validation
- [ ] **Documentation**: Complete and accurate
- [ ] **Automation**: Working and tested
- [ ] **Monitoring**: Configured and alerting
- [ ] **Support**: Procedures documented

### Final Approval
- [ ] **Technical Lead**: _________________ Date: _________
- [ ] **DevOps Lead**: _________________ Date: _________
- [ ] **Security Lead**: _________________ Date: _________
- [ ] **Product Owner**: _________________ Date: _________

---

**Notes**: Use this checklist to systematically validate each component of the testing plan. Check off items as they are completed and note any issues or deviations in the comments section below.

**Comments**:
_Use this space to document any issues, deviations, or additional notes during testing._
