# THORChain Mimir Configuration Guide

## Overview

THORChain uses a custom mimir system for runtime governance that can override genesis permissions. This guide explains how to configure mimir values for contract deployment on forked networks.

## The Problem

When deploying a forked THORChain network, users may encounter "unauthorized" errors during contract deployment:

```
Error: Query failed with (6): rpc error: code = Unknown desc = failed to execute message; message index: 0: unauthorized
```

This occurs because:
1. Genesis permissions are correctly set to "Everybody" for WASM contract deployment
2. Forked networks inherit mainnet mimir values where `WASMPERMISSIONLESS=0`
3. Mimir values override genesis permissions at runtime

## The Solution

Set `WASMPERMISSIONLESS=1` using THORChain's mimir system:

```bash
# Set WASMPERMISSIONLESS to enable contract deployment
thornode tx thorchain mimir WASMPERMISSIONLESS 1 \
  --from validator \
  --keyring-backend test \
  --chain-id thorchain \
  --node tcp://localhost:26657 \
  --yes \
  --fees 2000000rune
```

## Automated Configuration

The THORChain package includes an automated mimir configuration script:

```bash
# Configure mimir values on all running networks
./scripts/configure-mimir.sh
```

This script:
- Detects running local and forked networks
- Sets `WASMPERMISSIONLESS=1` on each network
- Verifies the configuration was applied successfully
- Provides detailed status reporting

## Manual Verification

Check current mimir values:
```bash
# Query mimir values
curl -s http://127.0.0.1:32769/thorchain/mimir

# Expected output should include:
# {"WASMPERMISSIONLESS": "1"}
```

Check genesis permissions (for comparison):
```bash
# Query WASM module parameters
curl -s http://127.0.0.1:32769/cosmos/wasm/v1/params
```

## Integration with Demo

The demo setup automatically configures mimir values:

1. **During network deployment**: Networks are deployed with genesis permissions
2. **After first block**: Mimir configuration script runs automatically
3. **Before contract deployment**: Scripts verify mimir configuration

## Troubleshooting

### Mimir Transaction Fails
- Ensure validator account has sufficient balance (needs 2000000rune for fees)
- Verify network is producing blocks before setting mimir values
- Check that validator key exists in keyring

### Mimir Value Not Set
- Wait a few seconds after transaction for propagation
- Query mimir endpoint to verify value was set
- Check transaction hash for confirmation

### Contract Deployment Still Fails
- Verify `WASMPERMISSIONLESS=1` is set: `curl -s http://localhost:1317/thorchain/mimir`
- Check that you're using the correct network endpoint
- Ensure contract WASM file is valid and not corrupted

## Technical Details

### Mimir System
- THORChain's custom governance system for runtime configuration
- Overrides genesis parameters without requiring chain upgrades
- Values are stored in the blockchain state and persist across restarts

### Key Mimir Values for Contract Deployment
- `WASMPERMISSIONLESS`: Controls who can deploy contracts (0=restricted, 1=permissionless)
- Other WASM-related mimir values may be added in future versions

### Authentication
- Mimir transactions require admin privileges
- Validator account has sufficient privileges for mimir configuration
- Transactions require gas fees (2000000rune recommended)

## Best Practices

1. **Always configure mimir after network deployment**
2. **Verify configuration before attempting contract deployment**
3. **Include mimir configuration in automated deployment scripts**
4. **Document mimir requirements for team members**
5. **Monitor mimir values in production environments**

## Integration Examples

### Kurtosis Package Integration
```starlark
# Add mimir configuration step after network deployment
def _configure_mimir_values(plan, service_name, chain_id):
    plan.exec(
        service_name = service_name,
        recipe = ExecRecipe(
            command = ["thornode", "tx", "thorchain", "mimir", "WASMPERMISSIONLESS", "1", 
                      "--from", "validator", "--keyring-backend", "test", 
                      "--chain-id", chain_id, "--node", "tcp://localhost:26657", 
                      "--yes", "--fees", "2000000rune"]
        )
    )
```

### Docker Compose Integration
```yaml
# Add mimir configuration as init container or startup script
services:
  thorchain-mimir-config:
    image: thorchain/thornode
    depends_on:
      - thorchain-node
    command: |
      sh -c "
        sleep 30 && 
        thornode tx thorchain mimir WASMPERMISSIONLESS 1 \
          --from validator --keyring-backend test \
          --chain-id thorchain --node tcp://thorchain-node:26657 \
          --yes --fees 2000000rune
      "
```

This guide ensures developers can successfully deploy contracts on forked THORChain networks by properly configuring the mimir system.
