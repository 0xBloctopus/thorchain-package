def launch_single_node(plan, chain_cfg):
    chain_name = chain_cfg["name"]
    chain_id = chain_cfg["chain_id"]
    binary = "thornode"
    config_folder = "/root/.thornode/config"

    forking_config = chain_cfg.get("forking", {})
    forking_image = forking_config.get("image", "tiljordan/thornode-forking:1.0.15")

    participant = chain_cfg["participants"][0]
    account_balance = int(participant["account_balance"])
    bond_amount = int(participant.get("bond_amount", "500000000000"))
    faucet_amount = int(chain_cfg["faucet"]["faucet_amount"])

    app_version = chain_cfg["app_version"]
    initial_height = str(chain_cfg.get("initial_height", 1))

    # Calculate genesis time
    genesis_delay = chain_cfg.get("genesis_delay", 5)
    plan.add_service(
        name="genesis-time-calc",
        config=ServiceConfig(
            image="python:3.11-alpine",
            entrypoint=["/bin/sh", "-c", "sleep infinity"],
        ),
    )
    genesis_time_result = plan.exec(
        service_name="genesis-time-calc",
        recipe=ExecRecipe(
            command=[
                "python",
                "-c",
                "from datetime import datetime,timedelta;import sys;sys.stdout.write((datetime.utcnow()+timedelta(seconds=%d)).strftime('%%Y-%%m-%%dT%%H:%%M:%%SZ'))"
                % genesis_delay,
            ]
        ),
        description="Compute genesis_time (UTC now + {}s)".format(genesis_delay),
    )
    genesis_time = genesis_time_result["output"].strip().replace("\n", "").replace("\r", "")
    plan.remove_service("genesis-time-calc")

    # Consensus block config
    consensus = chain_cfg.get("consensus", {})
    consensus_block = {
        "block": {
            "max_bytes": str(consensus.get("block_max_bytes", "22020096")),
            "max_gas": str(consensus.get("block_max_gas", "50000000")),
        },
        "evidence": {
            "max_age_num_blocks": str(consensus.get("evidence_max_age_num_blocks", "100000")),
            "max_age_duration": str(consensus.get("evidence_max_age_duration", "172800000000000")),
            "max_bytes": str(consensus.get("evidence_max_bytes", "1048576")),
        },
        "validator": {"pub_key_types": consensus.get("validator_pub_key_types", ["ed25519"])},
    }
    bond_module_addr = "thor17gw75axcnr8747pkanye45pnrwk7p9c3uhzgff"

    # Ports
    ports = {
        "rpc": PortSpec(number=26657, transport_protocol="TCP", wait=None),
        "p2p": PortSpec(number=26656, transport_protocol="TCP", wait=None),
        "grpc": PortSpec(number=9090, transport_protocol="TCP", wait=None),
        "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
        "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None),
    }

    node_name = "{}-node".format(chain_name)

    # Phase A: add service with sleep entrypoint
    base_service = plan.add_service(
        name=node_name,
        config=ServiceConfig(
            image=forking_image,
            ports=ports,
            entrypoint=["/bin/sh", "-lc", "sleep infinity"],
            min_cpu=participant.get("min_cpu", 500),
            min_memory=participant.get("min_memory", 512),
        ),
    )

    # a) Generate validator key
    res = plan.exec(
        node_name,
        ExecRecipe(
            command=[ "/bin/sh","-lc", "{} keys add validator --keyring-backend test --output json".format(binary) ],
            extract={"validator_addr": "fromjson | .address", "validator_mnemonic": "fromjson | .mnemonic"},
        ),
        description="Generate validator key (addr + mnemonic)",
    )
    validator_addr = res["extract.validator_addr"].replace("\n", "")
    validator_mnemonic = res["extract.validator_mnemonic"].replace("\n", "")

    # b) Init node
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "printf '%s' '{}' | {} init thorchain-node --recover --chain-id {}".format(
                    validator_mnemonic, binary, chain_id
                ),
            ],
        ),
        description="Initialize thornode home and config",
    )

    # c) Stage forked genesis (single copy)
    plan.exec(
        node_name,
        ExecRecipe(command=["/bin/sh", "-lc", "cp /tmp/genesis.json {}/genesis.json".format(config_folder)]),
        description="Copy forked genesis into config",
    )

    # d) Get SECP bech32 pk
    secp_res = plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "{0} keys show validator --pubkey --keyring-backend test | {0} pubkey | tr -d '\\n'".format(binary),
            ],
        ),
        description="Derive validator secp256k1 bech32 pubkey",
    )
    secp_pk = secp_res["output"]

    # e) Get validator consensus pubkeys (ed + cons)
    ed_res = plan.exec(
        node_name,
        ExecRecipe(command=["/bin/sh", "-lc", "{0} tendermint show-validator | {0} pubkey | tr -d '\\n'".format(binary)]),
        description="Derive validator ed25519 bech32 pubkey",
    )
    ed_pk = ed_res["output"]
    cons_res = plan.exec(
        node_name,
        ExecRecipe(
            command=["/bin/sh", "-lc", "{0} tendermint show-validator | {0} pubkey --bech cons | tr -d '\\n'".format(binary)]
        ),
        description="Derive validator consensus bech32 pubkey",
    )
    cons_pk = cons_res["output"]

    # f) Create faucet key
    f_res = plan.exec(
        node_name,
        ExecRecipe(
            command=["/bin/sh", "-lc", "{} keys add faucet --keyring-backend test --output json".format(binary)],
            extract={"faucet_addr": "fromjson | .address", "faucet_mnemonic": "fromjson | .mnemonic"},
        ),
        description="Generate faucet key (addr + mnemonic)",
    )
    faucet_addr = f_res["extract.faucet_addr"].replace("\n", "")

    # g) Prepare JSON payloads and compute totals (single Python pass)
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
python3 - << 'PY'
import json
validator_addr = %(validator_addr)r
faucet_addr = %(faucet_addr)r
secp_pk = %(secp_pk)r
ed_pk = %(ed_pk)r
cons_pk = %(cons_pk)r
app_version = %(app_version)r
account_balance = %(account_balance)d
faucet_amount = %(faucet_amount)d
mainnet_rune_supply = 42537131234170029
total_rune_supply = mainnet_rune_supply + account_balance + faucet_amount

node_accounts = [{
  "active_block_height": "0",
  "bond": "%(bond_amount)d",
  "bond_address": validator_addr,
  "node_address": validator_addr,
  "pub_key_set": {"ed25519": ed_pk, "secp256k1": secp_pk},
  "signer_membership": [],
  "status": "Active",
  "validator_cons_pub_key": cons_pk,
  "version": app_version,
}]

accounts = [
  {"@type": "/cosmos.auth.v1beta1.BaseAccount", "account_number": "0", "address": validator_addr, "pub_key": None, "sequence": "0"},
  {"@type": "/cosmos.auth.v1beta1.BaseAccount", "account_number": "0", "address": faucet_addr, "pub_key": None, "sequence": "0"},
]

balances = [
  {"address": validator_addr, "coins": [{"amount": str(account_balance), "denom": "rune"}]},
  {"address": faucet_addr, "coins": [{"amount": str(faucet_amount), "denom": "rune"}]},
]

open("/tmp/node_accounts.json","w").write(json.dumps(node_accounts))
open("/tmp/accounts.json","w").write(json.dumps(accounts))
open("/tmp/balances.json","w").write(json.dumps(balances))
open("/tmp/rune_supply.txt","w").write(str(total_rune_supply))
open("/tmp/consensus_block.json","w").write(json.dumps(%(consensus_block)s))
PY
""" % {
                    "validator_addr": validator_addr,
                    "faucet_addr": faucet_addr,
                    "secp_pk": secp_pk,
                    "ed_pk": ed_pk,
                    "cons_pk": cons_pk,
                    "app_version": app_version,
                    "account_balance": account_balance,
                    "faucet_amount": faucet_amount,
                    "bond_amount": bond_amount,
                    "consensus_block": consensus_block,
                },
            ]
        ),
        description="Prepare small JSON payloads and total RUNE supply",
    )

    # h) Single-pass placeholder replacements in genesis
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                r"""
python3 - << 'PY'
import json
cfg = %(config_folder)r + "/genesis.json"
with open(cfg,'r') as f:
    g = f.read()
consensus_block = open('/tmp/consensus_block.json','r').read().strip()
node_accounts = open('/tmp/node_accounts.json','r').read().strip()
rune_supply = open('/tmp/rune_supply.txt','r').read().strip()
validator_pubkey = json.loads(node_accounts)[0]['pub_key_set']['secp256k1']

g = g.replace('"__CONSENSUS_BLOCK__"', consensus_block)
g = g.replace('"__NODE_ACCOUNTS__"', node_accounts)
g = g.replace('"__RUNE_SUPPLY__"', rune_supply)
g = g.replace('"__VAULT_MEMBERSHIP__"', '["'+validator_pubkey+'"]')

with open(cfg,'w') as f:
    f.write(g)
PY
""".replace("%(config_folder)r", repr(config_folder)),
            ]
        ),
        description="Apply large-genesis placeholder replacements (single write)",
    )

    # i) Single jq pass for light updates
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
jq --arg app_version %(app_version)s \
   --arg genesis_time %(genesis_time)s \
   --arg chain_id %(chain_id)s \
   --arg initial_height %(initial_height)s \
   --arg bond_addr %(bond_addr)s \
   --argjson accounts "$(cat /tmp/accounts.json)" \
   --argjson balances "$(cat /tmp/balances.json)" \
   '
   .app_version = $app_version |
   .genesis_time = $genesis_time |
   .chain_id = $chain_id |
   .initial_height = $initial_height |
   .app_state.thorchain.reserve = "22000000000000000" |
   .app_state.auth.accounts += $accounts |
   .app_state.auth.accounts += [{
     "@type": "/cosmos.auth.v1beta1.ModuleAccount",
     "base_account": { "account_number": "0", "address": $bond_addr, "pub_key": null, "sequence": "0" },
     "name": "bond", "permissions": []
   }] |
   .app_state.bank.balances += $balances
   ' %(cfg)s/genesis.json > %(cfg)s/genesis.tmp && mv %(cfg)s/genesis.tmp %(cfg)s/genesis.json
""" % {
                    "app_version": json.encode(app_version),
                    "genesis_time": json.encode(genesis_time),
                    "chain_id": json.encode(chain_id),
                    "initial_height": json.encode(initial_height),
                    "bond_addr": json.encode(bond_module_addr),
                    "cfg": config_folder,
                },
            ]
        ),
        description="Apply jq light updates (single pass)",
    )

    # j) Batch config updates
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
APP=%(cfg)s/app.toml
CFG=%(cfg)s/config.toml
sed -i 's/^minimum-gas-prices = ".*"/minimum-gas-prices = "0rune"/' "$APP"
sed -i 's/^enable = false/enable = true/' "$APP"
sed -i 's/^swagger = false/swagger = true/' "$APP"

sed -i 's/^timeout_commit = "5s"/timeout_commit = "1s"/' "$CFG"
sed -i 's/^timeout_propose = "3s"/timeout_propose = "1s"/' "$CFG"

sed -i 's/^addr_book_strict = true/addr_book_strict = false/' "$CFG"
sed -i 's/^pex = true/pex = false/' "$CFG"
sed -i 's/^persistent_peers = ".*"/persistent_peers = ""/' "$CFG"
sed -i 's/^seeds = ".*"/seeds = ""/' "$CFG"

sed -i 's/^laddr = "tcp:\\/\\/127.0.0.1:26657"/laddr = "tcp:\\/\\/0.0.0.0:26657"/' "$CFG"
sed -i 's/^cors_allowed_origins = \\[\\]/cors_allowed_origins = ["*"]/' "$CFG"

sed -i 's/^address = "localhost:9090"/address = "0.0.0.0:9090"/' "$APP"

sed -i 's/^address = "tcp:\\/\\/localhost:1317"/address = "tcp:\\/\\/0.0.0.0:1317"/' "$APP"
sed -i 's/^enabled-unsafe-cors = false/enabled-unsafe-cors = true/' "$APP"

sed -i 's/^prometheus = false/prometheus = true/' "$CFG"
sed -i 's/^prometheus_listen_addr = ":26660"/prometheus_listen_addr = "0.0.0.0:26660"/' "$CFG"
""" % {"cfg": config_folder},
            ]
        ),
        description="Apply node configuration (API/RPC/gRPC/Prometheus/P2P)",
    )

    # Final: start thornode in background so plan continues
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "nohup sh -c \"printf 'validator\\nTestPassword!\\n' | {bin} start\" >/var/log/thornode.out 2>&1 & disown".format(
                    bin=binary
                ),
            ],
        ),
        description="Start thornode in background",
    )

    return {"name": node_name, "ip": base_service.ip_address}
