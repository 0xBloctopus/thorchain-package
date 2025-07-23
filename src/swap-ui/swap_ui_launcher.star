def launch_swap_ui(plan, chain_name, chain_id, forking_config, prefunded_mnemonics):
    
    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )
    
    # Prepare prefunded account mnemonic
    mnemonic = ""
    if prefunded_mnemonics and len(prefunded_mnemonics) > 0:
        mnemonic = prefunded_mnemonics[0]
    
    # Create mnemonic file
    mnemonic_file = plan.render_templates(
        config={
            "mnemonic": struct(
                template=mnemonic,
                data={}
            )
        },
        name="{}-swap-ui-mnemonic".format(chain_name)
    )
    
    # Create nginx configuration
    nginx_config = plan.render_templates(
        config={
            "nginx.conf": struct(
                template=read_file("templates/nginx.conf.tmpl"),
                data={
                    "NodeURL": "http://{}:1317".format(first_node.ip_address),
                    "NodeRPC": "http://{}:26657".format(first_node.ip_address)
                }
            )
        },
        name="{}-swap-ui-nginx-config".format(chain_name)
    )
    
    # Add swap UI service
    swap_ui_service = plan.add_service(
        name="{}-swap-ui".format(chain_name),
        config = ServiceConfig(
            image = "tiljordan/thorchain-swap-ui:1.0.0",
            ports = {
                "http": PortSpec(number=80, transport_protocol="TCP", wait=None)
            },
            files = {
                "/tmp/mnemonic": mnemonic_file,
                "/etc/nginx": nginx_config
            },
            env_vars = {
                "CHAIN_ID": chain_id,
                "NODE_URL": "http://{}:1317".format(first_node.ip_address),
                "NODE_RPC": "http://{}:26657".format(first_node.ip_address),
                "PREFUNDED_MNEMONIC": mnemonic,
                "REACT_APP_CHAIN_ID": chain_id,
                "REACT_APP_NODE_URL": "http://{}:1317".format(first_node.ip_address),
                "REACT_APP_NODE_RPC": "http://{}:26657".format(first_node.ip_address)
            }
        )
    )
    
    plan.print("Swap UI started successfully at http://{}:80".format(swap_ui_service.ip_address))
    
    return swap_ui_service
