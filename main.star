input_parser = import_module("./src/package_io/input_parser.star")
single_node_launcher = import_module("./src/network_launcher/single_node_launcher.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
swap_ui = import_module("./src/swap-ui/swap_ui_launcher.star")
mimir_configurator = import_module("./src/mimir-config/mimir_configurator.star")

def run(plan, args):
    parsed_args = input_parser.input_parser(args)

    # Launch single node for each chain
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        
        # Validate single-node configuration
        participant_count = 0
        for participant in chain["participants"]:
            participant_count += participant.get("count", 1)
        
        if participant_count != 1:
            fail("This package only supports single-node networks. Found {} participants.".format(participant_count))
        
        plan.print("Launching single-node network for {}".format(chain_name))
        
        # Launch the node
        node_info = single_node_launcher.launch_single_node(plan, chain)
        node_name = node_info["name"]
        
        # Wait for first block
        plan.print("Waiting for {} to produce first block...".format(node_name))
        forking_config = chain.get("forking", {})
        forking_height = str(forking_config.get("height", 0) + 1)
        plan.wait(
            service_name=node_name,
            recipe=GetHttpRequestRecipe(
                port_id="rpc",
                endpoint="/status",
                extract={
                    "block": ".result.sync_info.latest_block_height"
                }
            ),
            field="extract.block",
            assertion=">",
            target_value=forking_height,
            interval="2s",
            timeout="10m",
            description="Waiting for first block on {}".format(chain_name)
        )
        
        plan.print("✓ {} is producing blocks!".format(node_name))
        
        # Launch additional services
        additional_services = chain.get("additional_services", [])
        
        service_launchers = {
            "faucet": faucet.launch_faucet,
            "bdjuno": bdjuno.launch_bdjuno,
            "swap-ui": swap_ui.launch_swap_ui
        }
        
        for service in additional_services:
            if service in service_launchers:
                plan.print("Launching {} for {}".format(service, chain_name))
                if service == "faucet":
                    # Retrieve faucet mnemonic from node and launch faucet
                    faucet_mnemonic_res = plan.exec(
                        service_name=node_name,
                        recipe=ExecRecipe(
                            command=["/bin/sh","-lc","cat /tmp/faucet.mnemonic | tr -d '\\r'"],
                            extract={"mnemonic":"."},
                        ),
                        description="Read faucet mnemonic from node",
                    )
                    faucet_mnemonic = faucet_mnemonic_res["extract.mnemonic"]
                    faucet.launch_faucet(plan, chain_name, chain_id, faucet_mnemonic, chain["faucet"]["transfer_amount"])
                elif service == "bdjuno":
                    service_launchers[service](plan, chain_name)
                elif service == "swap-ui":
                    forking_config = chain.get("forking", {})
                    prefunded_mnemonics = []
                    service_launchers[service](plan, chain_name, chain_id, forking_config, prefunded_mnemonics)
        
        # Configure MIMIR values
        #mimir_configurator.configure_mimir_values(plan, chain, [node_info])
        
        plan.print("✓ {} deployment complete!".format(chain_name))
