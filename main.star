input_parser = import_module("./src/package_io/input_parser.star")
genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
network_launcher = import_module("./src/network_launcher/network_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
swap_ui = import_module("./src/swap-ui/swap_ui_launcher.star")
mimir_configurator = import_module("./src/mimir-config/mimir_configurator.star")

def run(plan, args):
    parsed_args = input_parser.input_parser(args)

    genesis_files = genesis_generator.generate_genesis_files(plan, parsed_args)

    networks = network_launcher.launch_network(plan, genesis_files, parsed_args)

    service_launchers = {
        "faucet": faucet.launch_faucet,
        "bdjuno": bdjuno.launch_bdjuno,
        "swap-ui": swap_ui.launch_swap_ui
    }

    # Launch additional services for each chain
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        additional_services = chain.get("additional_services", [])

        node_info = networks[chain_name]
        node_names = []
        for node in node_info:
            node_names.append(node["name"])

        # Wait until first block is produced before deploying additional services
        plan.wait(
            service_name = node_names[0],
            recipe = GetHttpRequestRecipe(
                port_id = "rpc",
                endpoint = "/status",
                extract = {
                    "block": ".result.sync_info.latest_block_height"
                }
            ),
            field = "extract.block",
            assertion = ">=",
            target_value = "1",
            interval = "1s",
            timeout = "1m",
            description = "Waiting for first block for chain " + chain_name
        )

        for service in service_launchers:
            if service in additional_services:
                plan.print("Launching {} for chain {}".format(service, chain_name))
                if service == "faucet":
                    faucet_mnemonic = genesis_files[chain_name]["mnemonics"][-1]
                    transfer_amount = chain["faucet"]["transfer_amount"]
                    service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                elif service == "bdjuno":
                    service_launchers[service](plan, chain_name)
                elif service == "swap-ui":
                    forking_config = chain.get("forking", {})
                    prefunded_mnemonics = genesis_files[chain_name]["prefunded_mnemonics"]
                    service_launchers[service](plan, chain_name, chain_id, forking_config, prefunded_mnemonics)

        # Configure MIMIR values AFTER all services are deployed
        mimir_configurator.configure_mimir_values(plan, chain, node_info)

    plan.print(genesis_files)
