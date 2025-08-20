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

    # Submit votes from all validators (handles 2/2 or >=2/3 cases)
    for node in node_info:
        validator_node = node["name"]

        # Ensure minimum-gas-prices is 0rune (already set in start script) and use 0rune gas-prices
        for mimir_key, mimir_value in mimir_values.items():
            plan.print("Setting MIMIR {}={} from {}".format(mimir_key, mimir_value, validator_node))

            plan.exec(
                service_name=validator_node,
                recipe=ExecRecipe(
                    command=[
                        "/bin/sh", "-c",
                        "thornode tx thorchain mimir {} {} --from validator --keyring-backend test --chain-id {} --yes --node tcp://localhost:26657 --gas-prices 0rune".format(
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
