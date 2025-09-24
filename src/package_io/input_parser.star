def read_json_file(file_path):
    local_contents = read_file(src=file_path)
    return json.decode(local_contents)

# Paths to the default JSON files
DEFAULT_THORCHAIN_FILE = "./thorchain_defaults.json"

def apply_chain_defaults(chain, defaults):
    # Simple key-value defaults
    chain["name"] = chain.get("name", defaults["name"])
    chain["type"] = chain.get("type", defaults["type"])
    chain["chain_id"] = chain.get("chain_id", defaults["chain_id"])
    chain["genesis_delay"] = chain.get("genesis_delay", defaults["genesis_delay"])
    chain["initial_height"] = chain.get("initial_height", defaults["initial_height"])
    chain["chain_contracts"] = chain.get("chain_contracts", defaults["chain_contracts"])
    chain["app_version"] = chain.get("app_version", defaults["app_version"])
    chain["reserve_amount"] = chain.get("reserve_amount", defaults["reserve_amount"])
    # Optional config keys for patching; if omitted, default to empty
    if "additional_accounts" not in chain:
        chain["additional_accounts"] = []
    if "balance_overrides" not in chain:
        chain["balance_overrides"] = {}
    if "thorchain_additions" not in chain:
        chain["thorchain_additions"] = {}
    if "node_accounts" not in chain["thorchain_additions"]:
        chain["thorchain_additions"]["node_accounts"] = []
    if "chain_contracts" not in chain["thorchain_additions"]:
        chain["thorchain_additions"]["chain_contracts"] = []

    # Nested defaults
    chain["denom"] = chain.get("denom", {})
    for key, value in defaults["denom"].items():
        chain["denom"][key] = chain["denom"].get(key, value)

    chain["faucet"] = chain.get("faucet", {})
    for key, value in defaults["faucet"].items():
        chain["faucet"][key] = chain["faucet"].get(key, value)

    chain["consensus"] = chain.get("consensus", {})
    for key, value in defaults["consensus"].items():
        chain["consensus"][key] = chain["consensus"].get(key, value)

    chain["modules"] = chain.get("modules", {})
    for module, module_defaults in defaults["modules"].items():
        chain["modules"][module] = chain["modules"].get(module, {})
        for key, value in module_defaults.items():
            chain["modules"][module][key] = chain["modules"][module].get(key, value)

    # Apply defaults to participants
    if "participants" not in chain:
        chain["participants"] = defaults["participants"]
    else:
        default_participant = defaults["participants"][0]
        participants = []
        for participant in chain["participants"]:
            for key, value in default_participant.items():
                participant[key] = participant.get(key, value)
            participants.append(participant)
        chain["participants"] = participants

    # Apply defaults to additional services
    if "additional_services" not in chain:
        chain["additional_services"] = defaults["additional_services"]

    # Apply defaults to prefunded_accounts
    if "prefunded_accounts" not in chain:
        chain["prefunded_accounts"] = {}

    # Apply defaults to forking
    chain["forking"] = chain.get("forking", {})
    for key, value in defaults["forking"].items():
        chain["forking"][key] = chain["forking"].get(key, value)

    # Apply defaults to mimir
    chain["mimir"] = chain.get("mimir", {})
    for key, value in defaults["mimir"].items():
        if key == "values":
            # Handle nested mimir values
            chain["mimir"][key] = chain["mimir"].get(key, {})
            for mimir_key, mimir_value in value.items():
                chain["mimir"][key][mimir_key] = chain["mimir"][key].get(mimir_key, mimir_value)
        else:
            chain["mimir"][key] = chain["mimir"].get(key, value)

    return chain

def validate_input_args(input_args):
    if not input_args or "chains" not in input_args:
        fail("Input arguments must include the 'chains' field.")

    chain_names = []
    for chain in input_args["chains"]:
        if "name" not in chain or "type" not in chain:
            fail("Each chain must specify a 'name' and a 'type'.")
        if chain["name"] in chain_names:
            fail("Duplicate chain name found: " + chain["name"])
        if chain["type"] != "thorchain":
            fail("Unsupported chain type: "+ chain["type"])
        chain_names.append(chain["name"])

def input_parser(input_args=None):
    thorchain_defaults = read_json_file(DEFAULT_THORCHAIN_FILE)

    result = {"chains": []}

    if not input_args:
        input_args = {"chains": [thorchain_defaults]}

    validate_input_args(input_args)

    if "chains" not in input_args:
        result["chains"].append(thorchain_defaults)
    else:
        for chain in input_args["chains"]:
            chain_type = chain.get("type", "thorchain")
            if chain_type == "thorchain":
                defaults = thorchain_defaults
            else:
                fail("Unsupported chain type: " + chain_type)

            # Apply defaults to chain
            chain_config = apply_chain_defaults(chain, defaults)
            result["chains"].append(chain_config)

    return result
