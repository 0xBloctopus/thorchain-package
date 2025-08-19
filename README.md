# THORChain Package

A Kurtosis package for deploying private THORChain testnets with automated genesis generation, network launching, and auxiliary services.

## Overview

This package automates the deployment of complete THORChain networks through a coordinated orchestration pipeline:

1. **Configuration parsing** - Validates and applies defaults to user configuration
2. **Genesis file generation** - Creates blockchain initial state with validator keys and prefunded accounts
3. **Network deployment** - Launches THORChain nodes with proper seed node topology
4. **Service deployment** - Waits for first block production, then deploys auxiliary services

### Key Features
- **Automated genesis creation** with validator cryptographic material and account funding
- **Proper P2P topology** with first node as seed for network formation
- **Auxiliary services** including token faucets, blockchain indexers, and trading interfaces
- **State forking** support for testing against mainnet data
- **Flexible configuration** with comprehensive defaults and customization options

## Prerequisites

- [Kurtosis](https://docs.kurtosis.com/install) installed and running
- Basic understanding of THORChain and Cosmos SDK blockchain architecture
- Docker for running containerized services

## Quick Start

### Basic Deployment

Deploy a default THORChain network:

```bash
kurtosis run --enclave thorchain-testnet github.com/LZeroAnalytics/thorchain-package
```

### Custom Configuration

Create a configuration file and deploy:

```bash
kurtosis run --enclave thorchain-testnet github.com/LZeroAnalytics/thorchain-package --args-file config.yaml
```

Example minimal configuration:

```yaml
chains:
  - name: "my-thorchain"
    type: "thorchain"
    chain_id: "thorchain-testnet"
```

## Configuration

The package uses a comprehensive configuration system with defaults from `thorchain_defaults.json`. All parameters are optional and will fall back to sensible defaults.

### Chain Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `name` | Chain identifier for services | `"thorchain"` |
| `type` | Must be `"thorchain"` | `"thorchain"` |
| `chain_id` | Blockchain network ID | `"thorchain"` |
| `app_version` | THORChain application version | `"3.7.0"` |
| `participants` | Validator node configuration | 1 validator |
| `additional_services` | Services to deploy | `["faucet", "bdjuno"]` |
| `prefunded_accounts` | Genesis account funding | `{}` |
| `forking` | State forking configuration | Disabled |

### Module Configuration

The package supports extensive Cosmos SDK module configuration including:
- **Consensus parameters** - Block size, gas limits, evidence parameters
- **Auth module** - Transaction limits, signature verification costs
- **Staking module** - Validator limits, minimum self-delegation
- **Mint module** - Inflation parameters, annual provisions
- **Bank module** - Token denomination and metadata

### Validator Configuration

```yaml
participants:
  - image: "registry.gitlab.com/thorchain/thornode:mainnet"
    account_balance: 1000000000000000
    bond_amount: "300000000000000"
    count: 1
    min_cpu: 500
    min_memory: 512
```

### Available Services

The package supports three auxiliary services that are deployed after the network produces its first block:

- **`faucet`** - HTTP API for token distribution using the last generated validator mnemonic
- **`bdjuno`** - Complete blockchain indexing stack with PostgreSQL database, Hasura GraphQL API, Big Dipper web explorer, and Nginx reverse proxy
- **`swap-ui`** - Web interface for token swapping with support for prefunded account integration

## Service Endpoints

After deployment, services are accessible at:

### THORChain Nodes
- **RPC**: `http://<node-ip>:26657` - Tendermint RPC
- **API**: `http://<node-ip>:1317` - Cosmos REST API  
- **gRPC**: `<node-ip>:9090` - Cosmos gRPC (local)
- For mainnet forking, use gRPC endpoint `grpc.thor.pfc.zone:443` (TLS)
- **P2P**: `<node-ip>:26656` - Peer-to-peer networking
- **Metrics**: `http://<node-ip>:26660` - Prometheus metrics

### Faucet Service
- **API**: `http://<faucet-ip>:8090` - Token distribution endpoint (`/fund/<address>`)
- **Monitoring**: `http://<faucet-ip>:8091` - Health monitoring
- **Usage**: `curl -X POST http://<faucet-ip>:8090/fund/thor1your_address_here`

### Block Explorer (BdJuno)
- **Explorer**: `http://<explorer-ip>:80` - Web interface
- **GraphQL**: `http://<hasura-ip>:8080` - Hasura GraphQL API
- **Database**: `<postgres-ip>:5432` - PostgreSQL database

### Swap UI
- **Interface**: `http://<swap-ui-ip>:80` - Web trading interface

## Advanced Features

### Prefunded Accounts

Fund accounts at genesis time using either THORChain addresses or mnemonics. The package automatically converts mnemonics to addresses using the THORChain derivation path. See [README_PREFUNDED_ACCOUNTS.md](README_PREFUNDED_ACCOUNTS.md) for detailed documentation including TypeScript and Go integration examples.

### State Forking

Fork from mainnet state for realistic testing. Requires a forking-enabled THORNode image that can fetch state from the specified RPC endpoint. The package supports caching and configurable gas costs for state fetching operations.

## Examples

### Basic Deployment
Use default configuration with a single validator:
```bash
kurtosis run --enclave thorchain-testnet github.com/LZeroAnalytics/thorchain-package
```

### Prefunded Accounts
Fund specific accounts at genesis time ([example_prefunded.yaml](example_prefunded.yaml)):
```yaml
chains:
  - name: "thorchain-test"
    type: "thorchain"
    prefunded_accounts:
      "thor1abc123def456ghi789jkl012mno345pqr678stu": "1000000000000"  # Direct address
      "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about": "2000000000000"  # Mnemonic
```

### State Forking
Fork from mainnet state ([examples/forking-enabled.yaml](examples/forking-enabled.yaml)):
```yaml
chains:
  - name: thorchain
    type: thorchain
    participants:
      - image: "tiljordan/thornode-forking:1.0.5"
        account_balance: 1000000000000000
        bond_amount: "300000000000000"
        count: 1
    forking:
      enabled: true
      grpc: "grpc.thor.pfc.zone:443"
      chain_id: "thorchain-1"
      height: 22071722
      cache_enabled: true
      cache_size: 10000
      timeout: "60s"
      gas_cost_per_fetch: 1000
```

### Custom Services
Deploy specific auxiliary services:
```yaml
chains:
  - name: "thorchain-custom"
    type: "thorchain"
    additional_services: ["faucet", "bdjuno", "swap-ui"]
    faucet:
      transfer_amount: 500000000  # Custom faucet amount
```

## Network Architecture

The package implements proper seed node topology:
- First node starts without seeds (becomes the seed node)
- Subsequent nodes connect to the first node via `--p2p.seeds`
- Ensures reliable network formation and connectivity

## Cleanup

Remove the deployment:

```bash
kurtosis enclave rm thorchain-testnet
```

## Support

For detailed configuration options and troubleshooting:
- Service configuration templates in `src/` directory
- [Prefunded accounts documentation](README_PREFUNDED_ACCOUNTS.md)
- [Kurtosis package configuration](kurtosis.yml) - Contains comprehensive package description, prerequisites, and seed node topology details
- Individual service launcher implementations for advanced customization
