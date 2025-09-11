def configure_mimir_values(plan, chain_config, node_info):
    """Configure MIMIR values after network startup"""
    chain_name = chain_config["name"]
    chain_id = chain_config["chain_id"]
    mimir_config = chain_config.get("mimir", {})

    if not mimir_config.get("enabled", False):
        plan.print("MIMIR configuration disabled for chain {}".format(chain_name))
        return

    mimir_values = mimir_config.get("values", {})
    if not mimir_values:
        plan.print("No MIMIR values to configure for chain {}".format(chain_name))
        return

    plan.print("Configuring MIMIR values for chain {}".format(chain_name))

    # Detect forking mode to optionally fund validator before sending MsgMimir
    forking_cfg = chain_config.get("forking", {})
    forking_enabled = bool(forking_cfg.get("enabled", False))
    tx_chain_id = chain_id
    if forking_enabled:
        tx_chain_id = "thorchain"


    # Submit votes from all validators (handles 2/2 or >=2/3 cases)
    for node in node_info:
        validator_node = node["name"]

        # Optionally fund the validator account in forking mode to avoid insufficient funds on MsgMimir
        if forking_enabled:
            # 1) Read validator address from the node's keyring
            res = plan.exec(
                service_name=validator_node,
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh", "-lc",
                        "thornode keys show validator -a --keyring-backend test | tr -d '\n'"
                    ]
                ),
                description="Read validator address for funding"
            )
            validator_addr = res.get("output", "").replace("\n", "").replace("\r", "")

            if validator_addr:
                # 2) Ask faucet to fund the validator by curling from the validator container
                plan.print("Funding validator via faucet")
                plan.exec(
                    service_name=validator_node,
                    recipe=ExecRecipe(
                        command=[
                            "/bin/sh", "-lc",
                            "curl -sf --connect-timeout 5 --max-time 15 -X POST --data '' http://{}-faucet:8090/fund/{} || true".format(
                                chain_name,
                                validator_addr,
                            )
                        ]
                    ),
                    description="Trigger faucet funding from node"
                )

        # Ensure minimum-gas-prices is 0rune (already set in start script) and use 0rune gas-prices; send sync to capture result
        for mimir_key, mimir_value in mimir_values.items():
            plan.print("Waiting for RPC on {} before MIMIR tx".format(validator_node))
            plan.exec(
                service_name=validator_node,
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh","-lc",
                        "for i in $(seq 1 120); do curl -sf --connect-timeout 1 --max-time 2 http://localhost:26657/health && curl -sf --connect-timeout 1 --max-time 2 http://localhost:26657/status && break || sleep 1; done && for i in $(seq 1 120); do h=$(curl -sf --connect-timeout 1 --max-time 2 http://localhost:26657/status | grep -o '\"latest_block_height\":\"[0-9]*\"' | grep -o '[0-9]*'); test -n \"$h\" || h=0; [ \"$h\" -ge 3 ] && break || sleep 1; done"
                    ]
                ),
                description="Wait for CometBFT RPC health on {}".format(validator_node),
            )

            plan.print("Setting MIMIR {}={} from {}".format(mimir_key, mimir_value, validator_node))
            plan.exec(
                service_name=validator_node,
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh", "-lc",
                        "for i in $(seq 1 12); do echo \"[mimir] attempt $i: sending tx {}={}\"; TX_OUT=$(thornode tx thorchain mimir {} {} --from validator --keyring-backend test --chain-id {} --yes --broadcast-mode sync -o json --node tcp://localhost:26657 --gas-prices 0rune 2>&1); RC=$?; echo \"$TX_OUT\"; if [ $RC -ne 0 ]; then echo \"[mimir] tx failed rc=$RC\" 1>&2; sleep 2; continue; fi; sleep 1; LCD=$(curl -s http://localhost:1317/thorchain/mimir | tr -d '\\r\\n'); echo \"[mimir] lcd: ${{LCD:0:400}}\"; echo \"$LCD\" | grep -q '\"{}\": {}' && exit 0; echo \"$LCD\" | grep -q '\"{}\": \"{}\"' && exit 0; sleep 2; done; echo \"[mimir] failed to set {} after retries\" 1>&2; exit 1".format(mimir_key, mimir_value, mimir_key, mimir_value, tx_chain_id, mimir_key, mimir_value, mimir_key, mimir_value, mimir_key)
                    ]
                ),
                description="Setting MIMIR {}={} from {}".format(mimir_key, mimir_value, validator_node)
            )

    plan.print("✅ MIMIR configuration complete for chain {}".format(chain_name))
