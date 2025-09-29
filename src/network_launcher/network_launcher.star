def launch_network(plan, genesis_files, parsed_args):
    networks = {}
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        binary = "thornode"
        config_folder = "/root/.thornode/config"
        
        # Build thornode_args dynamically based on forking configuration
        thornode_args = ""
        # Note: For forking mode, we use genesis patching instead of runtime forking flags
        # The Docker image doesn't support --fork.* flags, so we leave thornode_args empty
        
        genesis_result = genesis_files[chain_name]
        genesis_file = genesis_result["genesis_file"]
        mnemonics = genesis_result["mnemonics"]
        
        node_info = start_network(plan, chain, binary, chain_id, config_folder, thornode_args, genesis_result, mnemonics)
        networks[chain_name] = node_info
    
    return networks

def start_network(plan, chain, binary, chain_id, config_folder, thornode_args, genesis_result, mnemonics):
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
                    genesis_result, 
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
                    genesis_result, 
                    mnemonic,
                    False, 
                    first_node_id, 
                    first_node_ip
                )
                node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})
            
            node_counter += 1
    
    return node_info

def start_node(plan, node_name, participant, binary, chain_id, thornode_args, config_folder, genesis_result, mnemonic, is_first_node, first_node_id, first_node_ip):
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
    
    # Debug: Print genesis_result structure
    plan.print("DEBUG: genesis_result type: {}".format(type(genesis_result)))
    plan.print("DEBUG: genesis_result keys: {}".format(list(genesis_result.keys()) if type(genesis_result) == "dict" else "not a dict"))
    
    # Check if this is forking mode (patch_data exists in genesis_result)
    if type(genesis_result) == "dict" and "patch_data" in genesis_result:
        # Forking mode - add forking-specific template data for the embedded script
        patch_data = genesis_result["patch_data"]
        plan.print("DEBUG: patch_data keys: {}".format(list(patch_data.keys())))
        template_data["AppVersion"] = patch_data.get("app_version", "1.0.14")
        template_data["GenesisTime"] = patch_data.get("genesis_time", "")
        template_data["ChainId"] = patch_data.get("chain_id", chain_id)
        template_data["InitialHeight"] = patch_data.get("initial_height", "1")
        template_data["AccountBalance"] = str(participant.get("account_balance", 1000000000000000))
        template_data["BondAmount"] = str(participant.get("bond_amount", "300000000000000"))
        
        # Debug: Print template data being used
        plan.print("DEBUG: Template data for start script:")
        plan.print("  AppVersion: {}".format(template_data["AppVersion"]))
        plan.print("  GenesisTime: {}".format(template_data["GenesisTime"]))
        plan.print("  ChainId: {}".format(template_data["ChainId"]))
        plan.print("  InitialHeight: {}".format(template_data["InitialHeight"]))
        plan.print("  AccountBalance: {}".format(template_data["AccountBalance"]))
        plan.print("  BondAmount: {}".format(template_data["BondAmount"]))
    
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
    
    # Extract genesis file from result
    genesis_file = genesis_result["genesis_file"]
    
    # Prepare files for the node - handle both template and forking modes
    files = {
        "/tmp/scripts": start_script_template
    }
    
    # For forking mode, don't mount template genesis - use mainnet genesis from Docker image
    # For template mode, mount the template genesis file
    if type(genesis_result) != "dict" or "patch_data" not in genesis_result:
        # Template mode - mount the genesis file
        if genesis_file != None:
            files["/tmp/genesis"] = genesis_file
    
    # Add forking mode files if needed
    if type(genesis_result) == "dict" and "patch_data" in genesis_result:
        # Forking mode - add template files (patch script is embedded in start-node.sh)
        patch_data = genesis_result["patch_data"]
        plan.print("DEBUG: About to access patch_data keys for files")
        files["/tmp/patch_script"] = patch_data["patch_script"]  # Marker file to detect forking mode
        files["/tmp/templates"] = patch_data["consensus_file"] 
        files["/tmp/state"] = patch_data["state_file"]
        plan.print("DEBUG: Using mainnet genesis from Docker image at /tmp/genesis.json")
    
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
