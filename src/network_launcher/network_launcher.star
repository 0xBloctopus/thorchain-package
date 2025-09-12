def launch_network(plan, genesis_files, parsed_args):
    networks = {}
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        binary = "thornode"
        config_folder = "/root/.thornode/config"
        
        # Build thornode_args dynamically based on forking configuration
        thornode_args = ""
        if chain.get("forking", {}).get("enabled", False):
            forking_config = chain["forking"]
            thornode_args = "--fork.enabled=true --fork.grpc={} --fork.chain-id={} --fork.height={} --fork.cache-enabled={} --fork.cache-size={} --fork.timeout={} --fork.gas-cost-per-fetch={} --fork.trusting-period={} --fork.max-clock-drift={}".format(
                forking_config.get("grpc", "grpc.thor.pfc.zone:443"),
                forking_config.get("chain_id", "thorchain-mainnet-v1"),
                forking_config.get("height", 0),
                str(forking_config.get("cache_enabled", True)).lower(),
                forking_config.get("cache_size", 10000),
                forking_config.get("timeout", "60s"),
                forking_config.get("gas_cost_per_fetch", 1000),
                forking_config.get("trusting_period", "24h"),
                forking_config.get("max_clock_drift", "10s"),
            )
        
        genesis_file = genesis_files[chain_name]["genesis_file"]
        mnemonics = genesis_files[chain_name]["mnemonics"]
        
        node_info = start_network(plan, chain, binary, chain_id, config_folder, thornode_args, genesis_file, mnemonics)
        networks[chain_name] = node_info
    
    return networks

def start_network(plan, chain, binary, chain_id, config_folder, thornode_args, genesis_file, mnemonics):
    chain_name = chain["name"]
    participants = chain["participants"]
    
    node_info = []
    node_counter = 1
    first_node_id = ""
    first_node_ip = ""
    
    for participant in participants:
        count = participant["count"]
        for i in range(count):
            node_name = "{}-node-{}".format(chain_name, node_counter)
            mnemonic = mnemonics[node_counter - 1]
            
            # Determine if this is the first node (seed node)
            is_first_node = node_counter == 1
            
            if is_first_node:
                # Start seed node
                first_node_id, first_node_ip = start_node(
                    plan, 
                    node_name, 
                    participant, 
                    binary,
                    chain_id,
                    thornode_args, 
                    config_folder, 
                    genesis_file, 
                    mnemonic,
                    True, 
                    first_node_id, 
                    first_node_ip
                )
                node_info.append({"name": node_name, "node_id": first_node_id, "ip": first_node_ip})
            else:
                # Start normal nodes
                node_id, node_ip = start_node(
                    plan, 
                    node_name, 
                    participant, 
                    binary,
                    chain_id,
                    thornode_args, 
                    config_folder, 
                    genesis_file, 
                    mnemonic,
                    False, 
                    first_node_id, 
                    first_node_ip
                )
                node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})
            
            node_counter += 1
    
    return node_info

def start_node(plan, node_name, participant, binary, chain_id, thornode_args, config_folder, genesis_file, mnemonic, is_first_node, first_node_id, first_node_ip):
    image = participant["image"]
    min_cpu = participant.get("min_cpu", 500)
    min_memory = participant.get("min_memory", 512)
    
    # Configure seed options - critical seed topology implementation
    seed_options = ""
    if not is_first_node:
        # All non-first nodes connect to the first node as seed
        seed_address = "{}@{}:{}".format(first_node_id, first_node_ip, 26656)
        seed_options = "--p2p.seeds {}".format(seed_address)
    
    # Prepare template data
    template_data = {
        "NodeName": node_name,
        "ChainID": chain_id,
        "Binary": binary,
        "ConfigFolder": config_folder,
        "ThorNodeArgs": thornode_args,
        "SeedOptions": seed_options,
        "Mnemonic": mnemonic,
    }
    
    # Render start script template
    start_script_template = plan.render_templates(
        config={
            "start-node.sh": struct(
                template=read_file("templates/start-node.sh.tmpl"),
                data=template_data
            )
        },
        name="{}-start-script".format(node_name)
    )
    
    # Prepare files for the node
    files = {
        "/tmp/genesis": genesis_file,
        "/tmp/scripts": start_script_template
    }
    
    # Configure ports
    ports = {
        "rpc": PortSpec(number=26657, transport_protocol="TCP", wait="2m"),
        "p2p": PortSpec(number=26656, transport_protocol="TCP", wait=None),
        "grpc": PortSpec(number=9090, transport_protocol="TCP", wait=None),
        "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
        "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None)
    }
    
    # Configure resource requirements
    min_cpu_millicores = min_cpu
    min_memory_mb = min_memory
    
    # Add the service
    service = plan.add_service(
        name=node_name,
        config=ServiceConfig(
            image=image,
            ports=ports,
            files=files,
            entrypoint=["/bin/sh", "/tmp/scripts/start-node.sh"],
            min_cpu=min_cpu_millicores,
            min_memory=min_memory_mb
        )
    )
    
    # Get node ID and IP
    node_id_result = plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "{} tendermint show-node-id".format(binary)],
            extract={
                "node_id": "."
            }
        )
    )
    
    node_id = node_id_result["extract.node_id"]
    node_ip = service.ip_address
    
    return node_id, node_ip
