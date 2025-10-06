def launch_faucet(plan, chain_name, chain_id, mnemonic, transfer_amount):
    # Get first node
    first_node = plan.get_service(
        name = "{}-node".format(chain_name)
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

    # Render faucet server
    faucet_server = plan.render_templates(
        config = {
            "faucet_server.py": struct(
                template = read_file("templates/faucet_server.py.tmpl"),
                data = {}
            )
        },
        name="{}-faucet-server".format(chain_name)
    )

    # Use thornode forking image to get thornode CLI in container
    faucet_image = "tiljordan/thornode-forking:1.0.17"

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
                "/app": faucet_server
            },
            entrypoint = ["/bin/sh","-lc","export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && exec python3 /app/faucet_server.py"],
            env_vars = {
                "CHAIN_ID": chain_id,
                "NODE_URL": "http://{}:26657".format(first_node.ip_address),
                "PORT": "8090",
                "KEY_NAME": "faucet",
                "KEYRING_BACKEND": "test",
                "MNEMONIC_PATH": "/tmp/mnemonic/mnemonic.txt"
            }
        )
    )
