def launch_faucet(plan, chain_name, chain_id, mnemonic, transfer_amount):
    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    mnemonic_data = {
        "Mnemonic": mnemonic
    }

    mnemonic_file = plan.render_templates(
        config = {
            "mnemonic.txt": struct(
                template = read_file("templates/mnemonic.txt.tmpl"),
                data = mnemonic_data
            )
        },
        name="{}-faucet-mnemonic-file".format(chain_name)
    )

    # Use the Thorchain image directly
    faucet_image = "registry.gitlab.com/thorchain/thornode:mainnet"

    # Create faucet script as a template
    faucet_script = plan.render_templates(
        config = {
            "faucet.sh": struct(
                template = read_file("./faucet.sh"),
                data = {}
            )
        },
        name="{}-faucet-script".format(chain_name)
    )

    # Launch the faucet service
    plan.add_service(
        name="{}-faucet".format(chain_name),
        config = ServiceConfig(
            image = faucet_image,
            ports = {
                "api": PortSpec(number=8090, transport_protocol="TCP", wait=None),
                "monitoring": PortSpec(number=8091, transport_protocol="TCP", wait=None)
            },
            files = {
                "/tmp/mnemonic": mnemonic_file,
                "/app": faucet_script
            },
            entrypoint = ["/bin/sh", "/app/faucet.sh"],
            env_vars = {
                "CHAIN_ID": chain_id,
                "NODE_URL": "http://{}:26657".format(first_node.ip_address),
                "TRANSFER_AMOUNT": str(transfer_amount),
                "PORT": "8090",
                "MONITORING_PORT": "8091"
            }
        )
    )
