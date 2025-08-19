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
    
    # Get the first node (validator node)
    validator_node = node_info[0]["name"]
    
    # Solution: Transfer funds from faucet to validator for MIMIR operations
    plan.print("Funding validator account for MIMIR operations...")
        
    plan.exec(
        service_name=validator_node,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", "-c", 
                "cat /tmp/mnemonic/mnemonic.txt | thornode keys add faucet-key --recover --keyring-backend test"
            ]
        ),
        description="Creating faucet key for fund transfer"
    )
    
    # Transfer funds from faucet to validator for transaction fees
    plan.exec(
        service_name=validator_node,
        recipe=ExecRecipe(
            command=[
                "/bin/sh", "-c", 
                "thornode tx bank send faucet-key validator 50000000rune --from faucet-key --keyring-backend test --chain-id {} --node tcp://localhost:26657 --yes --fees 5000000rune".format(chain_id)
            ]
        ),
        description="Transferring funds from faucet to validator for MIMIR operations"
    )
    
    # Wait for transfer to complete
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
        interval="2s", 
        timeout="30s",
        description="Waiting for fund transfer to complete"
    )
    
    mimir_account = "validator"
    
    # Configure each MIMIR value
    for mimir_key, mimir_value in mimir_values.items():
        plan.print("Setting MIMIR value {}={} on chain {} using admin account".format(mimir_key, mimir_value, chain_name))
        
        # Execute MIMIR setting command with admin account
        plan.exec(
            service_name=validator_node,
            recipe=ExecRecipe(
                command=[
                    "/bin/sh", "-c", 
                    "thornode tx thorchain mimir {} {} --from {} --keyring-backend test --chain-id {} --yes --node tcp://localhost:26657 --fees 5000000rune".format(
                        mimir_key, mimir_value, mimir_account, chain_id
                    )
                ]
            ),
            description="Setting MIMIR {}={} on {} using admin account".format(mimir_key, mimir_value, chain_name)
        )
        
        # Wait a moment for transaction processing
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
            target_value="3",
            interval="2s", 
            timeout="30s",
            description="Waiting for MIMIR transaction to process"
        )
    
    plan.print("✅ MIMIR configuration complete for chain {}".format(chain_name))
