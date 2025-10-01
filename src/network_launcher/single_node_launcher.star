def launch_single_node(plan, chain_cfg):
    """
    Launch a single THORChain node that handles its own genesis modification.
    No separate genesis service or peering logic needed.
    """
    chain_name = chain_cfg["name"]
    chain_id = chain_cfg["chain_id"]
    binary = "thornode"
    config_folder = "/root/.thornode/config"
    
    # Get configuration from chain config
    forking_config = chain_cfg.get("forking", {})
    forking_image = forking_config.get("image", "tiljordan/thornode-forking:1.0.15")
    
    participant = chain_cfg["participants"][0]  # Single node only
    account_balance = participant["account_balance"]
    bond_amount = participant.get("bond_amount", "500000000000")
    faucet_amount = chain_cfg["faucet"]["faucet_amount"]
    
    app_version = chain_cfg["app_version"]
    initial_height = str(chain_cfg.get("initial_height", 1))
    
    # Calculate genesis time (use python:3.11-alpine for date calculation)
    genesis_delay = chain_cfg.get("genesis_delay", 5)
    genesis_time_service = plan.add_service(
        name="genesis-time-calc",
        config=ServiceConfig(
            image="python:3.11-alpine",
            entrypoint=["/bin/sh", "-c", "sleep infinity"]
        )
    )
    
    genesis_time_result = plan.exec(
        service_name="genesis-time-calc",
        recipe=ExecRecipe(
            command=["python", "-c", "from datetime import datetime, timedelta; print((datetime.utcnow() + timedelta(seconds={})).strftime('%Y-%m-%dT%H:%M:%SZ'))".format(genesis_delay)]
        )
    )
    genesis_time = genesis_time_result["output"].strip()
    
    # Remove the helper service
    plan.remove_service("genesis-time-calc")
    
    # Get consensus block configuration
    consensus = chain_cfg.get("consensus", {})
    consensus_block = {
        "block": {
            "max_bytes": str(consensus.get("block_max_bytes", "22020096")),
            "max_gas": str(consensus.get("block_max_gas", "50000000"))
        },
        "evidence": {
            "max_age_num_blocks": str(consensus.get("evidence_max_age_num_blocks", "100000")),
            "max_age_duration": str(consensus.get("evidence_max_age_duration", "172800000000000")),
            "max_bytes": str(consensus.get("evidence_max_bytes", "1048576"))
        },
        "validator": {
            "pub_key_types": consensus.get("validator_pub_key_types", ["ed25519"])
        }
    }
    
    bond_module_addr = "thor17gw75axcnr8747pkanye45pnrwk7p9c3uhzgff"
    
    # Prepare template data
    template_data = {
        "Binary": binary,
        "ConfigFolder": config_folder,
        "ChainID": chain_id,
        "AppVersion": app_version,
        "GenesisTime": genesis_time,
        "InitialHeight": initial_height,
        "AccountBalance": str(account_balance),
        "BondAmount": str(bond_amount),
        "FaucetAmount": str(faucet_amount),
        "BondModuleAddr": bond_module_addr,
        "ConsensusBlock": json.encode(consensus_block)
    }
    
    # Render start script
    start_script = plan.render_templates(
        config={
            "start-node.sh": struct(
                template=read_file("templates/start-single-node.sh.tmpl"),
                data=template_data
            )
        },
        name="{}-start-script".format(chain_name)
    )
    
    # Configure ports
    ports = {
        "rpc": PortSpec(number=26657, transport_protocol="TCP", wait="3m"),
        "p2p": PortSpec(number=26656, transport_protocol="TCP", wait=None),
        "grpc": PortSpec(number=9090, transport_protocol="TCP", wait=None),
        "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
        "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None)
    }
    
    # Start the node
    node_service = plan.add_service(
        name="{}-node".format(chain_name),
        config=ServiceConfig(
            image=forking_image,
            ports=ports,
            files={
                "/tmp/scripts": start_script
            },
            entrypoint=["/bin/sh", "/tmp/scripts/start-node.sh"],
            min_cpu=participant.get("min_cpu", 500),
            min_memory=participant.get("min_memory", 512)
        )
    )
    
    node_name = "{}-node".format(chain_name)
    
    # Return node info
    return {
        "name": node_name,
        "ip": node_service.ip_address
    }
