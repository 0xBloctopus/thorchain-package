# THORChain Testing Methodology - Advanced Scenarios & Best Practices

## Testing Philosophy

### Layered Testing Approach
The testing strategy employs a layered approach that validates functionality at multiple levels:

1. **Unit Level**: Individual contract functions and WASM module behavior
2. **Integration Level**: Contract interactions with THORChain modules
3. **System Level**: Full stack behavior including Bifrost and external chains
4. **End-to-End Level**: Complete user workflows across multiple chains

### Test Environment Isolation
Each testing approach provides different levels of isolation:

- **Mocknet**: Complete isolation, fastest feedback
- **Hybrid**: Controlled external dependencies, realistic state
- **Full Stack**: Production-like environment, comprehensive validation

## Advanced Test Scenarios

### Contract Deployment Edge Cases

#### Scenario 1: Large Contract Deployment
**Objective**: Test deployment of contracts approaching size limits

**Test Setup**:
```yaml
contract_tests:
  large_contract:
    size: "800KB"  # Near WASM size limit
    complexity: "high"
    dependencies: ["multiple_imports"]
```

**Validation Points**:
- Contract upload succeeds within gas limits
- Instantiation completes without timeout
- Runtime performance remains acceptable
- Memory usage stays within bounds

#### Scenario 2: Concurrent Contract Deployments
**Objective**: Validate system behavior under concurrent deployment load

**Test Matrix**:
| Concurrent Deployments | Expected Behavior | Validation |
|------------------------|-------------------|------------|
| 5 simultaneous | All succeed | Gas estimation accurate |
| 10 simultaneous | Queue management | No resource conflicts |
| 20 simultaneous | Rate limiting | Graceful degradation |

#### Scenario 3: Contract Upgrade Scenarios
**Objective**: Test contract migration and upgrade patterns

**Test Flow**:
1. Deploy initial contract version
2. Establish contract state and interactions
3. Deploy upgraded contract version
4. Migrate state using migration functions
5. Validate state consistency and functionality

### Bifrost Integration Edge Cases

#### Scenario 4: Chain Reorganization Handling
**Objective**: Test Bifrost behavior during blockchain reorganizations

**Test Setup**:
- Create competing Bitcoin regtest chains
- Generate reorganization scenario
- Monitor Bifrost transaction handling

**Validation Criteria**:
- Bifrost detects reorganization
- Invalid transactions are rolled back
- Valid transactions are reprocessed
- No double-spending occurs

#### Scenario 5: High Transaction Volume
**Objective**: Validate Bifrost performance under transaction load

**Load Profile**:
```yaml
transaction_load:
  bitcoin:
    rate: "10 tx/minute"
    duration: "30 minutes"
  ethereum:
    rate: "50 tx/minute" 
    duration: "30 minutes"
```

**Performance Metrics**:
- Transaction detection latency < 30 seconds
- Witness submission rate > 95%
- Memory usage growth < 10% per hour
- No transaction queue overflow

#### Scenario 6: Multi-Chain State Synchronization
**Objective**: Test state consistency across multiple external chains

**Test Scenario**:
1. Generate transactions on Bitcoin, Ethereum, BSC simultaneously
2. Monitor Bifrost processing across all chains
3. Validate THORChain state reflects all transactions
4. Check for race conditions or state conflicts

### Network Resilience Testing

#### Scenario 7: Partial Network Connectivity
**Objective**: Test system behavior with intermittent connectivity

**Network Conditions**:
- 50% packet loss to external chains
- High latency (5+ seconds) to THORChain RPC
- Intermittent DNS resolution failures

**Expected Behavior**:
- Graceful degradation of services
- Automatic retry mechanisms engage
- No data corruption during outages
- Clean recovery when connectivity restored

#### Scenario 8: Resource Exhaustion
**Objective**: Validate behavior under resource constraints

**Resource Limits**:
```yaml
resource_constraints:
  memory: "512MB"  # Below recommended
  cpu: "0.5 cores"  # Limited processing
  disk: "1GB"      # Minimal storage
```

**Validation Points**:
- Services start with warnings
- Performance degrades gracefully
- No crashes or data corruption
- Appropriate error messages

## Testing Data Management

### Test Data Generation

#### Synthetic Transaction Generation
```bash
# Bitcoin regtest transaction generator
generate_btc_transactions() {
    for i in {1..100}; do
        bitcoin-cli -regtest sendtoaddress $THOR_ADDRESS 0.001 "" "" false false 1 "SWAP:ETH.ETH:$ETH_ADDRESS"
        sleep 6  # Block time
    done
}

# Ethereum transaction generator  
generate_eth_transactions() {
    for i in {1..50}; do
        cast send --rpc-url $ETH_RPC --private-key $PRIVATE_KEY $ROUTER_ADDRESS "depositWithExpiry(address,address,uint256,string,uint256)" $ASSET_ADDRESS $VAULT_ADDRESS $AMOUNT "SWAP:BTC.BTC:$BTC_ADDRESS" $EXPIRY
        sleep 12  # Block time
    done
}
```

#### State Validation Data
```yaml
validation_data:
  known_addresses:
    - address: "thor1dheycdevq39qlkxs2a6wuuzyn4aqxhve4qxtxt"
      expected_balance: "1000000000000"
      chain: "thorchain"
    - address: "0x742d35Cc6634C0532925a3b8D4C9db96"
      expected_balance: "500000000000000000"
      chain: "ethereum"
  
  pool_states:
    - asset: "BTC.BTC"
      expected_depth: "100000000000"
    - asset: "ETH.ETH" 
      expected_depth: "50000000000000000000"
```

### Test Environment Snapshots

#### State Checkpoint Creation
```bash
# Create THORChain state snapshot
create_thorchain_snapshot() {
    local snapshot_name=$1
    kubectl exec thorchain-node-1 -- thornode export > "snapshots/${snapshot_name}_genesis.json"
    docker commit thorchain-node-1 "thorchain-snapshot:${snapshot_name}"
}

# Create external chain snapshots
create_external_snapshots() {
    local snapshot_name=$1
    docker commit bitcoind-regtest "bitcoin-snapshot:${snapshot_name}"
    docker commit anvil-eth "ethereum-snapshot:${snapshot_name}"
}
```

#### State Restoration
```bash
# Restore from snapshot
restore_from_snapshot() {
    local snapshot_name=$1
    docker run -d --name thorchain-restored "thorchain-snapshot:${snapshot_name}"
    docker run -d --name bitcoin-restored "bitcoin-snapshot:${snapshot_name}"
    docker run -d --name ethereum-restored "ethereum-snapshot:${snapshot_name}"
}
```

## Monitoring & Observability

### Metrics Collection

#### THORChain Metrics
```yaml
thorchain_metrics:
  consensus:
    - block_height
    - block_time
    - validator_count
    - missed_blocks
  
  application:
    - pool_depths
    - swap_volume
    - pending_transactions
    - gas_usage
  
  wasm:
    - contracts_deployed
    - contract_executions
    - gas_consumed
    - execution_time
```

#### Bifrost Metrics
```yaml
bifrost_metrics:
  connectivity:
    - thorchain_connection_status
    - external_chain_connections
    - rpc_response_times
    - connection_failures
  
  processing:
    - transactions_detected
    - witnesses_submitted
    - processing_latency
    - queue_depth
  
  performance:
    - memory_usage
    - cpu_utilization
    - network_bandwidth
    - error_rates
```

### Alerting Rules

#### Critical Alerts
```yaml
critical_alerts:
  - name: "THORChain Node Down"
    condition: "thorchain_node_up == 0"
    duration: "30s"
    
  - name: "Bifrost Connection Lost"
    condition: "bifrost_thorchain_connection == 0"
    duration: "60s"
    
  - name: "Contract Deployment Failed"
    condition: "wasm_deployment_failures > 0"
    duration: "0s"
```

#### Warning Alerts
```yaml
warning_alerts:
  - name: "High Transaction Latency"
    condition: "transaction_processing_time > 30s"
    duration: "300s"
    
  - name: "Memory Usage High"
    condition: "memory_usage_percent > 80"
    duration: "600s"
    
  - name: "Cache Hit Rate Low"
    condition: "forking_cache_hit_rate < 70"
    duration: "300s"
```

## Troubleshooting Guides

### Common Issues & Solutions

#### Issue 1: Contract Upload Fails
**Symptoms**: Contract upload returns "insufficient gas" error

**Diagnosis Steps**:
1. Check WASM module parameters: `curl $API/cosmwasm/wasm/v1/params`
2. Verify contract size: `wasm-opt --print-size contract.wasm`
3. Check account balance: `curl $API/cosmos/bank/v1beta1/balances/$ADDRESS`

**Solutions**:
- Increase gas limit in transaction
- Optimize contract size with wasm-opt
- Fund account with sufficient tokens

#### Issue 2: Bifrost Cannot Connect to THORChain
**Symptoms**: Bifrost logs show "connection refused" errors

**Diagnosis Steps**:
1. Verify THORChain RPC accessibility: `curl $THORCHAIN_RPC/status`
2. Check network connectivity: `ping thorchain-node-ip`
3. Validate configuration: `cat bifrost-config.yaml | yq .thorchain`

**Solutions**:
- Update RPC endpoint in Bifrost config
- Check firewall rules and port accessibility
- Verify THORChain service is running

#### Issue 3: Forked State Not Loading
**Symptoms**: Forked network returns empty pool data

**Diagnosis Steps**:
1. Check forking configuration: `grep -A 10 "forking:" config.yaml`
2. Verify RPC endpoint: `curl $MAINNET_RPC/status`
3. Check cache status: `curl $LOCAL_API/thorchain/pools | jq length`

**Solutions**:
- Verify mainnet RPC endpoint is accessible
- Increase cache size and timeout values
- Check for network connectivity issues

### Performance Optimization

#### THORChain Node Optimization
```yaml
performance_tuning:
  consensus:
    timeout_propose: "3s"
    timeout_prevote: "1s"
    timeout_precommit: "1s"
    
  application:
    pruning: "custom"
    pruning_keep_recent: "100"
    pruning_interval: "10"
    
  forking:
    cache_size: 50000
    timeout: "30s"
    gas_cost_per_fetch: 500
```

#### Bifrost Optimization
```yaml
bifrost_tuning:
  chain_clients:
    bitcoin:
      block_scan_processors: 2
      http_request_timeout: "30s"
      max_gas_limit: 500000
      
    ethereum:
      block_scan_processors: 4
      http_request_timeout: "15s"
      max_gas_limit: 8000000
```

## Security Considerations

### Test Environment Security

#### Network Isolation
- Use dedicated test networks
- Implement proper firewall rules
- Isolate test traffic from production

#### Credential Management
```yaml
security_practices:
  secrets:
    - use_environment_variables: true
    - rotate_test_keys_regularly: true
    - never_commit_private_keys: true
    
  access_control:
    - limit_rpc_access: true
    - use_authentication: true
    - monitor_access_logs: true
```

#### Container Security
- Use minimal base images
- Run containers as non-root users
- Implement resource limits
- Regular security updates

### Test Data Security

#### Sensitive Data Handling
- Use synthetic test data only
- Never use production private keys
- Implement data retention policies
- Secure test environment access

## Continuous Integration Integration

### CI Pipeline Structure

#### Stage 1: Environment Setup
```yaml
setup_stage:
  - name: "Prepare Test Environment"
    steps:
      - checkout_code
      - setup_kurtosis
      - pull_docker_images
      - validate_configurations
```

#### Stage 2: Contract Testing
```yaml
contract_testing:
  - name: "WASM Contract Tests"
    parallel: true
    jobs:
      - local_network_tests
      - forked_network_tests
      - performance_tests
```

#### Stage 3: Bifrost Integration
```yaml
bifrost_testing:
  - name: "Bifrost Integration Tests"
    depends_on: [contract_testing]
    jobs:
      - connection_tests
      - transaction_monitoring_tests
      - cross_chain_tests
```

#### Stage 4: End-to-End Validation
```yaml
e2e_testing:
  - name: "Full Stack Tests"
    depends_on: [bifrost_testing]
    jobs:
      - complete_workflow_tests
      - performance_validation
      - security_tests
```

### Test Result Reporting

#### Metrics Dashboard
- Test execution times
- Pass/fail rates by category
- Performance trend analysis
- Resource utilization patterns

#### Automated Reporting
```bash
# Generate test report
generate_test_report() {
    local test_run_id=$1
    
    echo "# Test Execution Report - Run $test_run_id" > report.md
    echo "## Summary" >> report.md
    echo "- Total Tests: $(count_total_tests)" >> report.md
    echo "- Passed: $(count_passed_tests)" >> report.md
    echo "- Failed: $(count_failed_tests)" >> report.md
    echo "- Duration: $(calculate_duration)" >> report.md
    
    echo "## Performance Metrics" >> report.md
    generate_performance_summary >> report.md
    
    echo "## Failed Tests" >> report.md
    list_failed_tests >> report.md
}
```

This methodology provides comprehensive guidance for implementing and executing the testing plan with advanced scenarios, monitoring, troubleshooting, and CI integration capabilities.
