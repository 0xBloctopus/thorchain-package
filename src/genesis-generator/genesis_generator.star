BOND_MODULE_ADDR = "thor17gw75axcnr8747pkanye45pnrwk7p9c3uhzgff"

def generate_genesis_files(plan, parsed_args):
    out = {}

    for chain_cfg in parsed_args["chains"]:
        out[chain_cfg["name"]] = _one_chain(plan, chain_cfg)

    return out


################################################################################
# One‑chain pipeline
################################################################################
def _one_chain(plan, chain_cfg):
    # Check if forking mode is enabled
    if chain_cfg.get("forking", {}).get("enabled", False):
        return _one_chain_forking(plan, chain_cfg)
    else:
        return _one_chain_template(plan, chain_cfg)

def _one_chain_template(plan, chain_cfg):
    binary          = "thornode"
    config_dir      = "/root/.thornode/config"
    chain_id        = chain_cfg["chain_id"]

    total_count = 0
    account_balances = []
    bond_amounts = []

    for participant in chain_cfg["participants"]:
        total_count += participant["count"]
        for _ in range(participant["count"]):
            account_balances.append("{}".format(participant["account_balance"]))
            if participant.get("staking", True):
                bond_amounts.append("{}".format(participant["bond_amount"]))
    account_balances.append("{}".format(chain_cfg["faucet"]["faucet_amount"]))

    # Process prefunded accounts
    prefunded_addresses = []
    prefunded_amounts = []
    prefunded_mnemonics = []
    
    for account_key, amount in chain_cfg.get("prefunded_accounts", {}).items():
        if account_key.startswith("thor"):  # It's an address
            prefunded_addresses.append(account_key)
            prefunded_amounts.append("{}".format(amount))
        else:  # It's a mnemonic
            prefunded_mnemonics.append(account_key)
            prefunded_amounts.append("{}".format(amount))



    # -------------------------------------------------------------------------
    # 1) Generate files & keys in a disposable container
    # -------------------------------------------------------------------------
    _start_genesis_service(
        plan      = plan,
        chain_cfg = chain_cfg,
        binary    = binary,
        config_dir= config_dir,
    )

    (
        mnemonics,
        addresses,
        secp_pks,
        ed_pks,
        cons_pks,
    ) = _generate_validator_keys(
        plan       = plan,
        binary     = binary,
        chain_id = chain_id,
        count      = total_count,
    )

    # Generate addresses from prefunded mnemonics
    if prefunded_mnemonics:
        prefunded_mnemonic_addresses = _generate_prefunded_addresses(plan, binary, prefunded_mnemonics)
        prefunded_addresses.extend(prefunded_mnemonic_addresses)

    # -------------------------------------------------------------------------
    # 2) Write the *Cosmos* accounts & balances
    # -------------------------------------------------------------------------
    
    # Add validator and faucet accounts through thornode (these exist in keyring)
    _add_balances(plan, binary, addresses, account_balances)

    # -------------------------------------------------------------------------
    # 3) Build THORChain node_accounts objects
    # -------------------------------------------------------------------------
    node_accounts = []
    for i in range(total_count):
        node_accounts.append({
            "node_address":            addresses[i],
            "version":                 chain_cfg["app_version"],
            "status":                  "Active",
            "bond":                    bond_amounts[i],
            "active_block_height":     "0",
            "bond_address":            addresses[i],
            "signer_membership":       [],
            "validator_cons_pub_key":  cons_pks[i],
            "pub_key_set": {
                "secp256k1":           secp_pks[i],
                "ed25519":             ed_pks[i],
            },
        })

    # -------------------------------------------------------------------------
    # 4) Build other dynamic lists (accounts, balances, chain contracts …)
    # -------------------------------------------------------------------------
    # Combine validator/faucet addresses with prefunded addresses for genesis
    all_addresses = addresses + prefunded_addresses
    all_amounts = account_balances + prefunded_amounts
    
    accounts_json  = json.encode(_mk_accounts_array(all_addresses))
    balances_json  = json.encode(_mk_balances_array(
        all_addresses,
        all_amounts
    ))
    contracts_json = json.encode(chain_cfg["chain_contracts"])
    nodeacc_json   = json.encode(node_accounts)

    # -------------------------------------------------------------------------
    # 5) Render the final template
    # -------------------------------------------------------------------------
    genesis_data = {
        # ---- header & consensus ----
        "AppVersion":                  chain_cfg["app_version"],
        "ChainID":                     chain_id,
        "GenesisTime":                 _get_genesis_time(plan, chain_cfg["genesis_delay"]),
        "InitialHeight":               chain_cfg["initial_height"],
        "BlockMaxBytes":               chain_cfg["consensus"]["block_max_bytes"],
        "BlockMaxGas":                 chain_cfg["consensus"]["block_max_gas"],
        "EvidenceMaxAgeNumBlocks":     chain_cfg["consensus"]["evidence_max_age_num_blocks"],
        "EvidenceMaxAgeDuration":      chain_cfg["consensus"]["evidence_max_age_duration"],
        "EvidenceMaxBytes":            chain_cfg["consensus"]["evidence_max_bytes"],
        "ValidatorPubKeyTypes":        json.encode(chain_cfg["consensus"]["validator_pub_key_types"]),

        # ---- auth params ----
        "AuthMaxMemoCharacters":       chain_cfg["modules"]["auth"]["max_memo_characters"],
        "AuthTxSigLimit":              chain_cfg["modules"]["auth"]["tx_sig_limit"],
        "AuthTxSizeCostPerByte":       chain_cfg["modules"]["auth"]["tx_size_cost_per_byte"],
        "AuthSigVerifyCostEd25519":    chain_cfg["modules"]["auth"]["sig_verify_cost_ed25519"],
        "AuthSigVerifyCostSecp256k1":  chain_cfg["modules"]["auth"]["sig_verify_cost_secp256k1"],

        # ---- bank / denom ----
        "DenomName":                   chain_cfg["denom"]["name"],
        "DenomDisplay":                chain_cfg["denom"]["display"],
        "DenomSymbol":                 chain_cfg["denom"]["symbol"],
        "DenomDescription":            chain_cfg["denom"]["description"],

        # ---- mint ----
        "MintInflation":               chain_cfg["modules"]["mint"]["inflation"],
        "MintAnnualProvisions":        chain_cfg["modules"]["mint"]["annual_provisions"],
        "MintBlocksPerYear":           chain_cfg["modules"]["mint"]["blocks_per_year"],
        "MintGoalBonded":              chain_cfg["modules"]["mint"]["goal_bonded"],
        "MintInflationMax":            chain_cfg["modules"]["mint"]["inflation_max"],
        "MintInflationMin":            chain_cfg["modules"]["mint"]["inflation_min"],
        "MintInflationRateChange":     chain_cfg["modules"]["mint"]["inflation_rate_change"],

        # ---- THORChain specifics ----
        "Reserve":                     chain_cfg["reserve_amount"],
        "ChainContracts":              contracts_json,
        "NodeAccounts":                nodeacc_json,


        # ---- module‑account & balances ----
        "BondModuleAddr":              BOND_MODULE_ADDR,
        "Accounts":                    accounts_json,
        "Balances":                    balances_json,
    }

    plan.print(genesis_data)

    gen_file = plan.render_templates(
        config={"genesis.json": struct(
            template=read_file("templates/genesis_thorchain.json.tmpl"),
            data   = genesis_data,
        )},
        name="{}-genesis-render".format(chain_cfg["name"]),
    )

    plan.remove_service("genesis-service")

    return {
        "genesis_file": gen_file,
        "mnemonics":    mnemonics,
        "addresses":    addresses,
        "prefunded_addresses": prefunded_addresses,
        "prefunded_mnemonics": prefunded_mnemonics,
    }

def _one_chain_forking(plan, chain_cfg):
    binary          = "thornode"
    config_dir      = "/root/.thornode/config"
    chain_id        = chain_cfg["chain_id"]
    
    # Generate validator keys as before
    _start_genesis_service(plan, chain_cfg, binary, config_dir)
    
    total_count = 0
    for participant in chain_cfg["participants"]:
        total_count += participant["count"]
    
    (mnemonics, addresses, secp_pks, ed_pks, cons_pks) = _generate_validator_keys(
        plan, binary, chain_id, total_count
    )
    
    # Build node_accounts and other dynamic data
    node_accounts = []
    for i in range(total_count):
        node_accounts.append({
            "node_address": addresses[i],
            "version": chain_cfg["app_version"],
            "status": "Active",
            "bond": chain_cfg["participants"][0]["bond_amount"],
            "active_block_height": "0",
            "bond_address": addresses[i],
            "signer_membership": [],
            "validator_cons_pub_key": cons_pks[i],
            "pub_key_set": {
                "secp256k1": secp_pks[i],
                "ed25519": ed_pks[i],
            },
        })
    
    # Prepare template data for consensus and state blocks
    template_data = {
        "BlockMaxBytes": chain_cfg["consensus"]["block_max_bytes"],
        "BlockMaxGas": chain_cfg["consensus"]["block_max_gas"],
        "EvidenceMaxAgeNumBlocks": chain_cfg["consensus"]["evidence_max_age_num_blocks"],
        "EvidenceMaxAgeDuration": chain_cfg["consensus"]["evidence_max_age_duration"],
        "EvidenceMaxBytes": chain_cfg["consensus"]["evidence_max_bytes"],
        "ValidatorPubKeyTypes": json.encode(chain_cfg["consensus"]["validator_pub_key_types"]),
        "BondModuleAddr": BOND_MODULE_ADDR,
    }
    
    # Render consensus and state templates
    consensus_file = plan.render_templates(
        config={"consensus.json": struct(
            template=read_file("templates/consensus_block.json.tmpl"),
            data=template_data,
        )},
        name="{}-consensus-render".format(chain_cfg["name"]),
    )
    
    state_file = plan.render_templates(
        config={"state.json": struct(
            template=read_file("templates/state_block.json.tmpl"),
            data=template_data,
        )},
        name="{}-state-render".format(chain_cfg["name"]),
    )
    
    # Create the patched genesis file
    patched_genesis = _patch_genesis_file(plan, chain_cfg, node_accounts, consensus_file, state_file)
    
    plan.remove_service("genesis-service")
    
    return {
        "genesis_file": patched_genesis,
        "mnemonics": mnemonics,
        "addresses": addresses,
        "prefunded_addresses": [],
        "prefunded_mnemonics": [],
    }

def _patch_genesis_file(plan, chain_cfg, node_accounts, consensus_file, state_file):
    """
    Patch the existing genesis file from the Docker image with user parameters
    """
    # Start a service with the forking Docker image to access the genesis file
    plan.add_service(
        name="genesis-patcher",
        config=ServiceConfig(
            image=chain_cfg["participants"][0]["image"],  # Use the forking image
            files={
                "/tmp/templates": consensus_file,
                "/tmp/state": state_file,
            },
        )
    )
    
    # Copy the original genesis file to working location
    plan.exec("genesis-patcher", ExecRecipe(
        command=["cp", "/tmp/genesis.json", "/tmp/genesis_working.json"]
    ))
    
    # Patch basic parameters
    genesis_time = _get_genesis_time(plan, chain_cfg["genesis_delay"])
    
    patch_commands = [
        # Update basic parameters using streaming jq to reduce memory usage
        "jq --stream '.app_version = \"{}\"' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json".format(chain_cfg["app_version"]),
        "jq --stream '.genesis_time = \"{}\"' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json".format(genesis_time),
        "jq --stream '.chain_id = \"{}\"' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json".format(chain_cfg["chain_id"]),
        "jq --stream '.initial_height = \"{}\"' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json".format(chain_cfg["initial_height"]),
        
        # Replace consensus block using slurp mode for smaller input
        "jq --slurpfile consensus /tmp/templates/consensus.json '.consensus = $consensus[0]' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json",
        
        # Replace node_accounts using compact output
        "jq -c '.app_state.thorchain.node_accounts = {}' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json".format(json.encode(node_accounts)),
        
        # Replace state block using slurp mode
        "jq --slurpfile state /tmp/state/state.json '.app_state.state = $state[0]' /tmp/genesis_working.json > /tmp/genesis_temp.json && mv /tmp/genesis_temp.json /tmp/genesis_working.json",
    ]
    
    # Execute all patch commands
    for cmd in patch_commands:
        plan.exec("genesis-patcher", ExecRecipe(
            command=["/bin/sh", "-c", cmd]
        ))
    
    # Create the final genesis file artifact with the expected naming pattern
    patched_genesis = plan.store_service_files(
        service_name="genesis-patcher",
        src="/tmp/genesis_working.json",
        name="{}-genesis-render".format(chain_cfg["name"])
    )
    
    plan.remove_service("genesis-patcher")
    
    return patched_genesis


################################################################################
# -------- helper functions below (unchanged unless noted) ---------
################################################################################
def _start_genesis_service(plan, chain_cfg, binary, config_dir):
    """
    Launches a tiny container with thornode binaries and an empty /tmp folder.
    """
    plan.add_service(
        name="genesis-service",
        config=ServiceConfig(
            image="registry.gitlab.com/thorchain/thornode:mainnet",
            files={},
        )
    )
    # ensure thornode home exists
    plan.exec("genesis-service", ExecRecipe(command=["mkdir", "-p", config_dir]))


def _generate_validator_keys(plan, binary, chain_id, count):
    """
    Returns 5 parallel arrays (mnemonics, bech32 addresses, secp pk, ed pk, cons pk)
    """
    m, addr, secp, ed, cons = [], [], [], [], []

    for i in range(count):
        kr_flags = "--keyring-backend test"
        # 1. CLI key
        cmd = "{} keys add validator{} {} --output json".format(binary, i, kr_flags)
        plan.print(cmd)
        res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", cmd],
            extract={"addr": "fromjson | .address", "mnemonic": "fromjson | .mnemonic"}
        ))
        addr.append(res["extract.addr"].replace("\n", ""))
        m.append(res["extract.mnemonic"].replace("\n", ""))

        thornode_flags  = "--chain-id {}".format(chain_id)
        _init_empty_chain(plan, binary, res["extract.mnemonic"].replace("\n", ""), thornode_flags)

        # 2. secp256k1 pk
        pk_cmd = "{0} keys show validator{1} --pubkey {2} | {0} pubkey | tr -d '\\n'".format(binary, i, kr_flags)
        plan.print(pk_cmd)
        cons_res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", pk_cmd],
        ))
        secp.append(cons_res["output"])

        # 3. validator consensus pk
        cons_cmd = "{0} tendermint show-validator | {0} pubkey --bech cons | tr -d '\\n'".format(binary)
        plan.print(cons_cmd)
        cons_res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", cons_cmd],
        ))
        cons.append(cons_res["output"])

        # 4. ed25519 pk
        ed_cmd = "{0} tendermint show-validator | {0} pubkey | tr -d '\\n'".format(binary)
        plan.print(ed_cmd)
        ed_res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", ed_cmd]
        ))
        ed.append(ed_res["output"])

    # Create faucet account
    res = plan.exec("genesis-service", ExecRecipe(
        command=["/bin/sh", "-c", "{} keys add faucet --keyring-backend test --output json".format(binary)],
        extract={"addr": "fromjson | .address", "mnemonic": "fromjson | .mnemonic"}
    ))
    addr.append(res["extract.addr"].replace("\n", ""))
    m.append(res["extract.mnemonic"].replace("\n", ""))

    return m, addr, secp, ed, cons


def _init_empty_chain(plan, binary, mnemonic, thornode_flags):
    cmd = "/bin/sh", "-c", "echo {} | {} init local --recover {}".format(mnemonic, binary, thornode_flags)
    plan.print(cmd)
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh", "-c", "echo {} | {} init local --recover {}".format(mnemonic, binary, thornode_flags)]))


def _add_balances(plan, binary, addresses, amounts):
    for a, amt in zip(addresses, amounts):
        cmd = "/bin/sh", "-c", "{} genesis add-genesis-account {} {}rune --keyring-backend test".format(binary, a, amt)
        plan.print(cmd)
        plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", "{} genesis add-genesis-account {} {}rune --keyring-backend test".format(binary, a, amt)]
        ))


def _mk_accounts_array(addrs):
    return [{
        "@type": "/cosmos.auth.v1beta1.BaseAccount",
        "address": a,
        "pub_key": None,
        "account_number": "0",
        "sequence": "0",
    } for a in addrs]


def _mk_balances_array(addrs, amounts):
    balances = []
    n = min(len(addrs), len(amounts))
    for i in range(n):
        balances.append({"address": addrs[i], "coins": [{"denom": "rune", "amount": amounts[i]}]})
    return balances


def _generate_prefunded_addresses(plan, binary, mnemonics):
    """
    Convert mnemonics to addresses for prefunded accounts
    """
    addresses = []
    for i, mnemonic in enumerate(mnemonics):
        kr_flags = "--keyring-backend test"
        # Import the mnemonic and get the address
        cmd = "echo '{}' | {} keys add prefunded{} {} --recover --output json".format(mnemonic, binary, i, kr_flags)
        plan.print(cmd)
        res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", cmd],
            extract={"addr": "fromjson | .address"}
        ))
        addresses.append(res["extract.addr"].replace("\n", ""))
    return addresses


def _get_genesis_time(plan, genesis_delay):
    result = plan.run_python(
        description="Calculating genesis time",
        run="""
import time
from datetime import datetime, timedelta
import sys

padding = int(sys.argv[1])
future_time = datetime.utcnow() + timedelta(seconds=padding)
formatted_time = future_time.strftime('%Y-%m-%dT%H:%M:%SZ')
print(formatted_time, end="")
""",
        args=[str(genesis_delay)]
    )
    return result.output
