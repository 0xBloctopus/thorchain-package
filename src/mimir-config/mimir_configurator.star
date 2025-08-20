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
                # 2) Ask faucet to fund the validator (HTTP POST /fund/<addr>)
                plan.wait(
                    service_name="{}-faucet".format(chain_name),
                    recipe=PostHttpRequestRecipe(
                        port_id="api",
                        endpoint="/fund/{}".format(validator_addr),
                        body="",
                    ),
                    field="code",
                    assertion="==",
                    target_value="200",
                    interval="1s",
                    timeout="15s",
                    description="Funding validator via faucet"
                )

        # Ensure minimum-gas-prices is 0rune (already set in start script) and use 0rune gas-prices; send sync to capture result
        for mimir_key, mimir_value in mimir_values.items():
            plan.print("Setting MIMIR {}={} from {}".format(mimir_key, mimir_value, validator_node))

            plan.exec(
                service_name=validator_node,
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh", "-c",
                        "thornode tx thorchain mimir {} {} --from validator --keyring-backend test --chain-id {} --yes --broadcast-mode sync -o json --node tcp://localhost:26657 --gas-prices 0rune".format(
                            mimir_key, mimir_value, chain_id
                        )
                    ]
                ),
                description="Setting MIMIR {}={} from {}".format(mimir_key, mimir_value, validator_node)
            )

            # Brief wait to allow inclusion
            plan.wait(
                service_name=validator_node,
                recipe=GetHttpRequestRecipe(
                    port_id="rpc",
                    endpoint="/status",
                    extract={
                        "block": ".result.sync_info.latest_block_height"
                    }
                ),
                field="extract.block",
                assertion=">=",
                target_value="2",
                interval="1s",
                timeout="30s",
                description="Waiting for MIMIR tx from {}".format(validator_node)
            )

    plan.print("✅ MIMIR configuration complete for chain {}".format(chain_name))
