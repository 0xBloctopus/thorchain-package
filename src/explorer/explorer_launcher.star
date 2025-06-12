def launch_explorer(plan, chain_name, chain_id, node_info):
    """
    Launches the Thorchain Explorer v2 (NuxtJS application)
    
    Args:
        plan: The Kurtosis plan
        chain_name: The name of the chain
        chain_id: The chain ID
        node_info: Information about the nodes in the network
    """
    plan.print("Launching Thorchain Explorer v2 for chain {}".format(chain_name))
    
    # Get the first node for API connections
    first_node = node_info[0]
    node_api_url = "http://{}:1317".format(first_node["ip"])
    node_rpc_url = "http://{}:26657".format(first_node["ip"])
    
    # Configure environment variables for the explorer
    explorer_env_vars = {
        "NUXT_PUBLIC_API_BASE_URL": node_api_url,
        "NUXT_PUBLIC_RPC_BASE_URL": node_rpc_url,
        "NUXT_PUBLIC_CHAIN_ID": chain_id,
        "NUXT_PUBLIC_CHAIN_NAME": chain_name,
        "NUXT_PUBLIC_NETWORK": "localnet",
        "NODE_ENV": "production",
        "NITRO_PORT": "3000",
        "NITRO_HOST": "0.0.0.0"
    }
    
    # Use the official Thorchain Explorer v2 image or build from source
    # For now, we'll use a generic Node.js image and clone the repository
    explorer_image = "node:18-alpine"
    
    # Create a startup script for the explorer
    explorer_startup_script = """#!/bin/sh
set -e

echo "Setting up Thorchain Explorer v2..."

# Install git and other dependencies
apk add --no-cache git

# Clone the thorchain-explorer-v2 repository
cd /app
git clone https://github.com/thorchain/thorchain-explorer-v2.git .

# Install dependencies
npm install

# Build the application
npm run build

echo "Starting Thorchain Explorer v2..."
echo "API Base URL: $NUXT_PUBLIC_API_BASE_URL"
echo "RPC Base URL: $NUXT_PUBLIC_RPC_BASE_URL"
echo "Chain ID: $NUXT_PUBLIC_CHAIN_ID"

# Start the application
exec npm run preview
"""
    
    startup_script_artifact = plan.render_templates(
        config={
            "start-explorer.sh": struct(
                template=explorer_startup_script,
                data={}
            )
        },
        name="{}-explorer-startup-script".format(chain_name)
    )
    
    # Launch the explorer service
    explorer_service = plan.add_service(
        name="{}-explorer".format(chain_name),
        config=ServiceConfig(
            image=explorer_image,
            ports={
                "http": PortSpec(number=3000, transport_protocol="TCP", wait="2m")
            },
            files={
                "/tmp/scripts": startup_script_artifact
            },
            entrypoint=["/bin/sh", "/tmp/scripts/start-explorer.sh"],
            env_vars=explorer_env_vars,
            min_cpu=500,
            min_memory=1024
        )
    )
    
    explorer_url = "http://{}:{}".format(explorer_service.ip_address, 3000)
    
    plan.print("Thorchain Explorer v2 URL: {}".format(explorer_url))
    
    return {
        "explorer_url": explorer_url,
        "service_name": "{}-explorer".format(chain_name)
    }
