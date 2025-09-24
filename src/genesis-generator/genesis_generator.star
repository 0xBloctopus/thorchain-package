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

    # We will patch balances via jq against existing genesis; no CLI add here

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
    # Build JSON fragments for jq patching
    extra_accounts = chain_cfg.get("additional_accounts", [])
    acct_objs = _mk_accounts_array(extra_accounts)
    accounts_json = json.encode(acct_objs)

    # Build balance overrides entries from config
    bal_entries = []
    for addr, amt in chain_cfg.get("balance_overrides", {}).items():
        bal_entries.append({"address": addr, "coins": [{"denom": chain_cfg["denom"]["name"], "amount": "{}".format(amt)}]})
    balances_json = json.encode(bal_entries)

    contracts_json = json.encode(chain_cfg.get("thorchain_additions", {}).get("chain_contracts", chain_cfg.get("chain_contracts", [])))
    nodeacc_json   = json.encode(chain_cfg.get("thorchain_additions", {}).get("node_accounts", []) + node_accounts)

    # -------------------------------------------------------------------------
    # 5) Always patch existing /tmp/genesis.json inside the thornode image
    # -------------------------------------------------------------------------
    header_obj = {
        "app_version": chain_cfg["app_version"],
        "chain_id": chain_id,
        "initial_height": "{}".format(chain_cfg["initial_height"]),
        "genesis_time": _get_genesis_time(plan, chain_cfg["genesis_delay"]),
    }
    header_json = json.encode(header_obj)

    consensus_obj = {
        "block": {
            "max_bytes": "{}".format(chain_cfg["consensus"]["block_max_bytes"]),
            "max_gas": "{}".format(chain_cfg["consensus"]["block_max_gas"]),
        },
        "evidence": {
            "max_age_num_blocks": "{}".format(chain_cfg["consensus"]["evidence_max_age_num_blocks"]),
            "max_age_duration": "{}".format(chain_cfg["consensus"]["evidence_max_age_duration"]),
            "max_bytes": "{}".format(chain_cfg["consensus"]["evidence_max_bytes"]),
        },
        "validator": {
            "pub_key_types": chain_cfg["consensus"]["validator_pub_key_types"],
        },
    }
    consensus_json = json.encode(consensus_obj)
    # Ensure jq present and write patch JSONs inside container
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","apk add --no-cache jq >/dev/null 2>&1 || apt-get update >/dev/null 2>&1 && apt-get install -y jq >/dev/null 2>&1 || true"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","mkdir -p /tmp/patches"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/header.json".format(header_json.replace("'", "\\'"))]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/consensus.json".format(consensus_json.replace("'", "\\'"))]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/accounts.json".format(accounts_json.replace("'", "\\'"))]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/balances.json".format(balances_json.replace("'", "\\'"))]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/node_accounts.json".format(nodeacc_json.replace("'", "\\'"))]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc","printf '%s' '{}' > /tmp/patches/chain_contracts.json".format(contracts_json.replace("'", "\\'"))]))

    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'jq -r ".consensus.params.block.max_bytes" /tmp/genesis.json | head -c 32 || true']))
    # Apply patches sequentially
    # Header fields in four small passes
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; cid=$(jq -r .chain_id /tmp/patches/header.json); jq --arg cid "$cid" \'.chain_id=$cid\' "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; ih=$(jq -r .initial_height /tmp/patches/header.json); jq --arg ih "$ih" \'.initial_height=$ih\' "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; gt=$(jq -r .genesis_time /tmp/patches/header.json); jq --arg gt "$gt" \'.genesis_time=$gt\' "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; appv=$(jq -r .app_version /tmp/patches/header.json); jq --arg appv "$appv" \'.app_version=$appv\' "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Consensus in three passes with filter files
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.consensus.params.block = $c[0].block' > /tmp/patches/consensus_block.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.consensus.params.evidence = $c[0].evidence' > /tmp/patches/consensus_evidence.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.consensus.params.validator = $c[0].validator' > /tmp/patches/consensus_validator.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile c /tmp/patches/consensus.json -f /tmp/patches/consensus_block.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile c /tmp/patches/consensus.json -f /tmp/patches/consensus_evidence.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile c /tmp/patches/consensus.json -f /tmp/patches/consensus_validator.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Accounts upsert via filter file
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.app_state.auth.accounts as $A | reduce $acc[0][] as $x (. ; ([$A[] | .address] | index($x.address)) as $i | if $i==null then (.app_state.auth.accounts += [$x]) else . end)' > /tmp/patches/accounts.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile acc /tmp/patches/accounts.json -f /tmp/patches/accounts.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Balances upsert/overwrite via filter file
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.app_state.bank.balances as $B | reduce $bal[0][] as $x (. ; ([$B[] | .address] | index($x.address)) as $i | if $i==null then (.app_state.bank.balances += [$x]) else (.app_state.bank.balances[$i].coins = $x.coins) end)' > /tmp/patches/balances.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile bal /tmp/patches/balances.json -f /tmp/patches/balances.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Node accounts upsert via filter file
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.app_state.thorchain.node_accounts as $N | reduce $na[0][] as $x (. ; ([$N[] | .node_address] | index($x.node_address)) as $i | if $i==null then (.app_state.thorchain.node_accounts += [$x]) else (.app_state.thorchain.node_accounts[$i] = ($N[$i] + $x)) end)' > /tmp/patches/node_accounts.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile na /tmp/patches/node_accounts.json -f /tmp/patches/node_accounts.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Chain contracts upsert via filter file
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.app_state.thorchain.chain_contracts as $C | reduce $cc[0][] as $x (. ; ([$C[] | (.chain + \":\" + .name)] | index($x.chain + \":\" + $x.name)) as $i | if $i==null then (.app_state.thorchain.chain_contracts += [$x]) else (.app_state.thorchain.chain_contracts[$i] = ($C[$i] + $x)) end)' > /tmp/patches/chain_contracts.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --slurpfile cc /tmp/patches/chain_contracts.json -f /tmp/patches/chain_contracts.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"']))
    # Overwrite state.accounts with bond module account via filter file
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r"printf '%s' '.app_state.state.accounts = [ { \"@type\":\"/cosmos.auth.v1beta1.ModuleAccount\", \"base_account\": { \"account_number\":\"0\", \"address\": $bond, \"pub_key\": null, \"sequence\":\"0\" }, \"name\":\"bond\", \"permissions\": [] } ]' > /tmp/patches/state_accounts.jq"]))
    plan.exec("genesis-service", ExecRecipe(command=["/bin/sh","-lc",r'GEN="/tmp/genesis.json"; TMP="/tmp/genesis.tmp.json"; jq --arg bond "{}" -f /tmp/patches/state_accounts.jq "$GEN" > "$TMP" && mv "$TMP" "$GEN"'.format(BOND_MODULE_ADDR)]))

    # Export patched genesis
    gen_file = plan.store_service_files("genesis-service", "/tmp/genesis.json")

    plan.remove_service("genesis-service")

    return {
        "genesis_file": gen_file,
        "mnemonics":    mnemonics,
        "addresses":    addresses,
        "prefunded_addresses": prefunded_addresses,
        "prefunded_mnemonics": prefunded_mnemonics,
    }


################################################################################
# -------- helper functions below (unchanged unless noted) ---------
################################################################################
def _start_genesis_service(plan, chain_cfg, binary, config_dir):
    """
    Launches a container using the participant image so /tmp/genesis.json is present.
    """
    image = chain_cfg["participants"][0].get("image", "tiljordan/thornode-forking:1.0.14")
    plan.add_service(
        name="genesis-service",
        config=ServiceConfig(
            image=image,
            files={},
            min_cpu=2000,
            min_memory=8192,
        )
    )
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
