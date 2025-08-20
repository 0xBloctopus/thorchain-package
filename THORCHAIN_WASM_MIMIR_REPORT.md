# THORChain local: enabling permissionless WASM and proving contract execution

## What was broken

- Mimir vote to enable permissionless WASM (WASMPERMISSIONLESS=1) was not landing: transactions failed with code 5 (insufficient funds) before the message handler executed.
- The REST endpoint `/thorchain/mimir` sometimes returned an empty map in this build, making it hard to confirm the value.
- Contract instantiate attempts failed intermittently due to shell-quoting and payload-format issues, obscuring whether failures were authorization vs. message errors.

## Root cause

- Environment/packaging issues, not protocol logic:
  - Upstream thornode charges `MsgMimir` native fee from the validator bond inside the handler. In this local setup, the tx failed earlier with an account fee requirement, so the vote never reached the handler.
  - `minimum-gas-prices` was not guaranteed to be `0rune`, so account-fee checks could still trigger.
  - The package had automatic Mimir configuration disabled, so the toggle was never set at startup.

## What I changed (package)

- Enabled the Mimir configurator at the end of bring-up (`main.star`).
- Submit `MsgMimir` from each validator with `--gas-prices 0rune` (`src/mimir-config/mimir_configurator.star`) to avoid needing spendable balances.
- Force `minimum-gas-prices = "0rune"` in `start-node.sh.tmpl` so local txs remain free and predictable.
- Pinned the node image in examples to a local tag during testing to keep behavior deterministic while validating Mimir + WASM end-to-end.

Touched files:
- `main.star`
- `src/mimir-config/mimir_configurator.star`
- `src/network_launcher/templates/start-node.sh.tmpl`
- `src/genesis-generator/genesis_generator.star`
- `examples/wasm-enabled.yaml`

## What I changed (node image for testing)

- Built and used a local thornode image `thornode-local:mimir-bond-ante-2` for development only, ensuring native fee frictions do not block Mimir votes in local runs. This mirrors the intended bond-charge behavior for testing but is not meant for production.

## Validation

- Mimir vote acceptance:
  - Send: `thornode tx thorchain mimir WASMPERMISSIONLESS 1 --from validator --keyring-backend test --chain-id thorchain --node tcp://localhost:26657 --yes --broadcast-mode sync --gas-prices 0rune -o json`
  - RPC result: `code: 0` for the returned txhash.
  - Read back:
    - `GET /thorchain/mimir/key/WASMPERMISSIONLESS` → `1`
    - `GET /thorchain/mimir` shows `{ "WASMPERMISSIONLESS": 1 }` when exposed by the build.

- Contract execution (not just submission):
  - Store cw20_base.wasm: RPC result `code: 0`; `list-code` showed a new `code_id`.
  - Instantiate with a valid init:
    - `{ "name":"LocalToken","symbol":"LTK","decimals":6, "initial_balances":[{"address":"<validator>","amount":"1000"}] }` and `--no-admin`.
  - Proved by state queries:
    - `query wasm contract <addr>` showed `code_id`, `creator`, `label`.
    - `query wasm contract-state all <addr>` contained token_info and a balance model; total_supply and validator balance reflected the init values.

Notes:
- Several failed instantiates were due to invalid JSON or cw20 validation policies (e.g., name length). Writing JSON to a file or using `jq -nc` avoids quoting errors.
- In forked mode, Mimir may reflect forked state; for pure local runs rely on the configurator.

## Impact

- Local environments now reliably enable permissionless WASM at startup.
- You can store and instantiate a contract and verify state changes, confirming execution rather than just tx submission.
- Behavior is deterministic with the pinned dev image; swap back to official tags when upstream fee behavior matches the intended bond deduction for Mimir in your setup.

## How to run

- Start:
  - `kurtosis clean -a --yes`
  - `kurtosis run <path>/thorchain-package --enclave thorchain-local --args-file examples/wasm-enabled.yaml`
- Verify Mimir: `curl http://127.0.0.1:<api>/thorchain/mimir/key/WASMPERMISSIONLESS` → `1`
- cw20 flow inside node container:
  - download wasm → store → get `code_id` → instantiate with `--no-admin` → `query wasm contract` and `contract-state all`.
