# THORChain Mimir: permissionless WASM and how this package configures it

## Overview

THORChain uses Mimir to override certain network settings at runtime. The `WASMPERMISSIONLESS` key controls whether CosmWasm code upload/instantiate is open to everyone (1) or restricted/whitelisted (0). Only a validator (node operator) can submit a Mimir vote.

## Why deployments failed in local forks

- Forked/local networks may inherit restrictive Mimir from mainnet (e.g., `WASMPERMISSIONLESS=0`).
- Some local builds attempted to charge account fees on `MsgMimir` before the handler could deduct from bond, causing tx code 5 (insufficient funds).
- Quoting/JSON errors in instantiate messages can surface as generic errors that look like authorization issues.

## What this package does

- Runs a Mimir configurator after the first block to set requested keys from your args, e.g. `WASMPERMISSIONLESS=1`.
- Submits votes from each validator using `--gas-prices 0rune` so no spendable balance is required in local runs.
- Forces `minimum-gas-prices = "0rune"` at boot for predictable, fee‑free local testing.
- Provides an example args file that enables Mimir automatically.

Key files:
- `main.star` – invokes the configurator after services are up.
- `src/mimir-config/mimir_configurator.star` – submits `MsgMimir` votes from validators.
- `src/network_launcher/templates/start-node.sh.tmpl` – enforces `minimum-gas-prices = 0rune` and fast local timings.
- `examples/wasm-enabled.yaml` – turns on Mimir and sets `WASMPERMISSIONLESS: 1`.

## Configure via args

Minimal example (see `examples/wasm-enabled.yaml`):
```yaml
chains:
  - name: thorchain
    chain_id: thorchain
    mimir:
      enabled: true
      values:
        WASMPERMISSIONLESS: 1
    participants:
      - image: fravlaca/thornode-forking:1.0.6"
        account_balance: 1000000000000000
        bond_amount: "300000000000000"
        count: 1
        staking: true
```

## Manual operations (inside a validator container)

- Set Mimir:
```bash
thornode tx thorchain mimir WASMPERMISSIONLESS 1 \
  --from validator --keyring-backend test \
  --chain-id thorchain --node tcp://localhost:26657 \
  --yes --broadcast-mode sync --gas-prices 0rune -o json
```
- Read back:
```bash
curl -s http://127.0.0.1:<api>/thorchain/mimir/key/WASMPERMISSIONLESS
```

## Verifying WASM execution (proof beyond tx acceptance)

1) Store a contract (e.g., cw20_base.wasm) and confirm RPC code=0.
2) Instantiate with a valid init (name 3–50 chars, symbol 3–12 uppercase) and `--no-admin`.
3) Query state:
```bash
thornode query wasm contract <contract_addr> -o json
thornode query wasm contract-state all <contract_addr> -o json
```
You should see `token_info` and balances reflecting the init values if execution succeeded.

## Notes

- Dev-only image: the example pins `thornode-local:mimir-bond-ante-2` to remove fee frictions in local runs. Use official images in production.
- In forked mode, Mimir may be inherited from the forked source. The configurator applies your desired overrides after startup.
- Common instantiate errors come from malformed JSON or invalid cw20 fields; prefer writing JSON to a file or using `jq -nc`.

## Quick start

```bash
kurtosis clean -a --yes
kurtosis run /path/to/thorchain-package --enclave thorchain-local \
  --args-file examples/wasm-enabled.yaml | cat
# Verify
API=$(kurtosis port print thorchain-local thorchain-node-1 api | cut -d: -f2)
curl -s http://127.0.0.1:$API/thorchain/mimir/key/WASMPERMISSIONLESS
```
