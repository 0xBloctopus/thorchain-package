# THORChain Mimir Configuration Guide

## Overview

THORChain uses a custom mimir system for runtime governance that can override genesis permissions. This guide explains how to configure mimir values for contract deployment on forked networks.

## The Problem: "Unauthorized" Errors on Forked Networks

When deploying contracts on forked THORChain networks, developers encounter:

```
Error: Query failed with (6): rpc error: code = Unknown desc = failed to execute message; message index: 0: unauthorized
```

**Root Cause**: 
- Forked networks inherit mainnet mimir configuration, where `WASMPERMISSIONLESS=0` (disabled)
- THORChain's mimir system overrides genesis WASM permissions at runtime
- Genesis template sets `code_upload_access: "Everybody"` but mimir takes precedence
- THORChain uses a whitelisted contract system - `WASMPERMISSIONLESS=1` enables deployment outside the whitelist

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

### Understanding THORChain Mimir System

THORChain uses a **mimir system** for runtime configuration that overrides genesis settings. Key points:

- **Runtime Override**: Mimir values take precedence over genesis module parameters at runtime
- **Dynamic Configuration**: Can be changed without network restarts or upgrades
- **Validator Control**: Mimir values are set using validator keys with consensus
- **Contract Permissions**: `WASMPERMISSIONLESS` specifically controls CosmWasm deployment permissions outside the whitelist system
- **THORChain-Specific**: Different from standard Cosmos chains - uses whitelisted contract system with mimir-controlled permissionless bypass
- **Forked Network Issue**: Forked networks inherit mainnet mimir values, which typically have `WASMPERMISSIONLESS=0`

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
