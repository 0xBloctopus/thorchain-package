BOND_MODULE_ADDR = "tthor17gw75axcnr8747pkanye45pnrwk7p9c3uhzgff"

def generate_genesis_files(plan, parsed_args):
    out = {}

    for chain_cfg in parsed_args["chains"]:
        out[chain_cfg["name"]] = _one_chain(plan, chain_cfg)

    return out


################################################################################
# One‑chain pipeline
################################################################################
def _one_chain(plan, chain_cfg):
    binary          = "thornode"
    config_dir      = "/root/.thornode/config"
    chain_id        = chain_cfg["chain_id"]
    thornode_flags  = "--chain-id {}".format(chain_id)

    total_count = 0
    account_balances = []
    bond_amounts = []

    for participant in chain_cfg["participants"]:
        total_count += participant["count"]
        for _ in range(participant["count"]):
            account_balances.append("{}{}".format(participant["account_balance"], chain_cfg["denom"]["name"]))
            if participant.get("staking", True):
                bond_amounts.append("{}".format(participant["bond_amount"]))

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
        config_dir = config_dir,
        count      = total_count,
    )

    # -------------------------------------------------------------------------
    # 2) Write the *Cosmos* accounts & balances
    # -------------------------------------------------------------------------

    _init_empty_chain(plan, binary, thornode_flags)
    _add_balances(plan, binary, addresses, account_balances)

    # -------------------------------------------------------------------------
    # 3) Build THORChain node_accounts objects
    # -------------------------------------------------------------------------
    node_accounts = []
    for i in range(total_count):
        node_accounts.append({
            "node_address":            addresses[i],
            "version":                 chain_cfg["app_version"],
            "ip_address":              chain_cfg.get("validator_ips", ["127.0.0.1"])[i],
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
    accounts_json  = json.encode(_mk_accounts_array(addresses))
    balances_json  = json.encode(_mk_balances_array(
        addresses,
        account_balances
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
    }


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


def _generate_validator_keys(plan, binary, config_dir, count):
    """
    Returns 5 parallel arrays (mnemonics, bech32 addresses, secp pk, ed pk, cons pk)
    """
    m, addr, secp, ed, cons = [], [], [], [], []

    for i in range(count):
        kr_flags = "--keyring-backend test"
        # 1. CLI key
        cmd = "{} keys add validator{} {} --output json".format(binary, i, kr_flags)
        res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", cmd],
            extract={"addr": "fromjson | .address", "mnemonic": "fromjson | .mnemonic"}
        ))
        addr.append(res["extract.addr"].replace("\n", ""))
        m.append(res["extract.mnemonic"].replace("\n", ""))

        # 2. ed25519 pk
        ed_cmd = "printf '%s\\n%s\\n' '{mn}' '{mn}' | {bin} ed25519 | tr -d '\\n'".format(mn=m[-1], bin=binary)
        ed_res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", ed_cmd]
        ))
        ed.append(ed_res["output"])

        # 4. validator consensus pk
        cons_cmd = "{} keys show validator{} --bech cons --pubkey {}".format(binary, i, kr_flags)
        cons_res = plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", cons_cmd],
            extract={"pk": "fromjson | .key"},
        ))
        cons.append(cons_res["extract.pk"].replace("\n", ""))
        secp.append(cons_res["extract.pk"].replace("\n", ""))

        # Remove auto‑created genesis so we can drop in our rendered one later
        plan.exec("genesis-service", ExecRecipe(
            command=["rm", "-f", "{}/genesis.json".format(config_dir)]
        ))

    return m, addr, secp, ed, cons


def _init_empty_chain(plan, binary, thornode_flags):
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh", "-c", "{} init local {}".format(binary, thornode_flags)]))


def _add_balances(plan, binary, addresses, amounts):
    for a, amt in zip(addresses, amounts):
        plan.exec("genesis-service", ExecRecipe(
            command=["/bin/sh", "-c", "{} genesis add-genesis-account {} {}".format(binary, a, amt)]
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
    count = 0
    for addr in addrs:
        balances.append({"address": addr, "coins": [{"denom": "rune", "amount": amounts[count]}]})
    return balances


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