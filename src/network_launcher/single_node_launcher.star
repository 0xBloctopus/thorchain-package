toolchain = import_module("./toolchain.star")
cli_only_launcher = import_module("./cli_only_launcher.star")
cli_key_manager = import_module("./cli_key_manager.star")

def launch_single_node(plan, chain_cfg):
    chain_name = chain_cfg["name"]
    chain_id = chain_cfg["chain_id"]
    binary = "thornode"
    config_folder = "/root/.thornode/config"

    forking_config = chain_cfg.get("forking", {})
    forking_image = forking_config.get("image", "tiljordan/thornode-forking:1.0.23-23761879")

    participant = chain_cfg["participants"][0]
    node_volume_size = participant.get("persistent_size_mb", chain_cfg.get("node_persistent_size_mb", 16384))
    account_balance = int(participant["account_balance"])
    bond_amount = int(participant.get("bond_amount", "500000000000"))
    faucet_amount = int(chain_cfg["faucet"]["faucet_amount"])
    gomemlimit = participant.get("gomemlimit", "6GiB")

    app_version = chain_cfg["app_version"]

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

    # Upload merge script to be mounted at service creation
    merge_artifact = plan.upload_files(src="/src/network_launcher/merge_patch.py")

    node_name = "{}-node".format(chain_name)

    # Phase A: add service with sleep entrypoint
    base_service = plan.add_service(
        name="base-service",
        config=ServiceConfig(
            image=forking_image,
            ports=ports,
            entrypoint=["/bin/sh", "-lc", "sleep infinity"],
            min_cpu=participant.get("min_cpu", 500),
            min_memory=participant.get("min_memory", 1024),
            files={
                "/merge_patch": merge_artifact,
                "/tmp/execution-data": Directory(
                    persistent_key="node-data",
                    size=node_volume_size,
                )
            },
        ),
    )

    # a) Generate validator key
    res = plan.exec(
        "base-service",
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
        "base-service",
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "printf '%s' '{}' | {} init base-service --recover --chain-id {}".format(
                    validator_mnemonic, binary, chain_id
                ),
            ],
        ),
        description="Initialize thornode home and config",
    )

    # c) Stage forked genesis (single copy)
    plan.exec(
        "base-service",
        ExecRecipe(command=["/bin/sh", "-lc", "cp /tmp/genesis.json {}/genesis.json".format(config_folder)]),
        description="Copy forked genesis into config",
    )


    # d) Get SECP bech32 pk
    secp_res = plan.exec(
        "base-service",
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
        "base-service",
        ExecRecipe(command=["/bin/sh", "-lc", "{0} tendermint show-validator | {0} pubkey | tr -d '\\n'".format(binary)]),
        description="Derive validator ed25519 bech32 pubkey",
    )
    ed_pk = ed_res["output"]
    cons_res = plan.exec(
        "base-service",
        ExecRecipe(
            command=["/bin/sh", "-lc", "{0} tendermint show-validator | {0} pubkey --bech cons | tr -d '\\n'".format(binary)]
        ),
        description="Derive validator consensus bech32 pubkey",
    )
    cons_pk = cons_res["output"]

    # f) Create faucet key
    f_res = plan.exec(
        "base-service",
        ExecRecipe(
            command=["/bin/sh", "-lc", "{} keys add faucet --keyring-backend test --output json".format(binary)],
            extract={"faucet_addr": "fromjson | .address", "faucet_mnemonic": "fromjson | .mnemonic"},
        ),
        description="Generate faucet key (addr + mnemonic)",
    )
    faucet_addr = f_res["extract.faucet_addr"].replace("\n", "")
    faucet_mnemonic = f_res["extract.faucet_mnemonic"].replace("\n", "")
    plan.exec(
        "base-service",
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "printf '%s' '{}' > /tmp/execution-data/faucet.mnemonic".format(faucet_mnemonic),
            ],
        ),
        description="Persist faucet mnemonic for downstream faucet launcher",
    )

    # Extract prefunded accounts from configuration
    prefunded_accounts = chain_cfg.get("prefunded_accounts", {})
    prefunded_list = []
    prefunded_rune_total = 0
    for addr in prefunded_accounts:
        amount = prefunded_accounts[addr]
        amount_int = int(amount)
        prefunded_list.append({"address": addr, "amount": amount_int})
        prefunded_rune_total = prefunded_rune_total + amount_int

    plan.print("Prefunded accounts configured: {}".format(len(prefunded_list)))
    for pf in prefunded_list:
        plan.print("  - {} with {} base units".format(pf["address"][:20] + "...", pf["amount"]))
    if prefunded_rune_total > 0:
        plan.print("Total RUNE distributed to prefunded accounts: {}".format(prefunded_rune_total))

    # g) Prepare JSON payloads and compute totals (single Python pass)
    plan.exec(
        "base-service",
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
prefunded_list = %(prefunded_list)r
prefunded_rune_total = %(prefunded_rune_total)d
mainnet_rune_supply = 42537131234170029
total_rune_supply = mainnet_rune_supply + account_balance + faucet_amount + prefunded_rune_total

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

# Add prefunded accounts
for pf in prefunded_list:
    accounts.append({
        "@type": "/cosmos.auth.v1beta1.BaseAccount",
        "account_number": "0",
        "address": pf["address"],
        "pub_key": None,
        "sequence": "0"
    })
    balances.append({
        "address": pf["address"],
        "coins": [{"amount": str(pf["amount"]), "denom": "rune"}]
    })

open("/tmp/node_accounts.json","w").write(json.dumps(node_accounts))
open("/tmp/accounts.json","w").write(json.dumps(accounts))
open("/tmp/balances.json","w").write(json.dumps(balances))
open("/tmp/accounts_fragment.json","w").write(", ".join(json.dumps(x) for x in accounts))
open("/tmp/balances_fragment.json","w").write(", ".join(json.dumps(x) for x in balances))
open("/tmp/rune_supply.txt","w").write(str(total_rune_supply))
open("/tmp/consensus_block.json","w").write(json.dumps(%(consensus_block)s))
open("/tmp/vault_membership.json","w").write(json.dumps([secp_pk]))
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
                    "prefunded_list": prefunded_list,
                    "prefunded_rune_total": prefunded_rune_total,
                },
            ]
        ),
        description="Prepare small JSON payloads and total RUNE supply",
    )

    # Build faucet balances and supply updates for all denoms
    plan.exec(
        "base-service",
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
curl -sS "https://thornode.ninerealms.com/cosmos/bank/v1beta1/supply?pagination.limit=500" -o /tmp/supply.json
python3 - << 'PY'
import json
from pathlib import Path
faucet_addr = %(faucet_addr)r
faucet_amount = %(faucet_amount)d
prefunded_list = %(prefunded_list)r
# Read supply from ninerealms
try:
    s = json.loads(Path("/tmp/supply.json").read_text() or "{}")
except Exception:
    s = {}
supply_list = s.get("supply", [])
denoms = []
for entry in supply_list:
    if isinstance(entry, dict):
        d = entry.get("denom")
        if isinstance(d, str):
            denoms.append(d)
# Build faucet balance for all denoms
coins = [{"amount": str(faucet_amount), "denom": d} for d in denoms]
faucet_balance = {"address": faucet_addr, "coins": coins}
Path("/tmp/faucet_balances_fragment.json").write_text(json.dumps(faucet_balance, separators=(",",":")))
# Merge into existing balances_fragment (ensure single faucet entry)
arr = []
try:
    existing = Path("/tmp/balances_fragment.json").read_text().strip()
    if existing:
        try:
            arr = json.loads(f"[{existing}]")
        except Exception:
            j = json.loads(existing)
            arr = j if isinstance(j, list) else [j]
except Exception:
    arr = []
arr = [b for b in arr if not (isinstance(b, dict) and b.get("address")==faucet_balance["address"])]
arr.append(faucet_balance)
# Add prefunded accounts with all denoms
for pf in prefunded_list:
    pf_coins = [{"amount": str(pf["amount"]), "denom": d} for d in denoms]
    pf_balance = {"address": pf["address"], "coins": pf_coins}
    # Remove any existing entry for this address
    arr = [b for b in arr if not (isinstance(b, dict) and b.get("address")==pf_balance["address"])]
    arr.append(pf_balance)
Path("/tmp/merged_balances_fragment.json").write_text(", ".join(json.dumps(x, separators=(",",":")) for x in arr))
# Compute updated supply = upstream supply + faucet_amount + prefunded amounts per denom
def add(a,b):
    try:
        return str(int(a)+int(b))
    except Exception:
        return str(a)
updated = []
for entry in supply_list:
    if not isinstance(entry, dict):
        continue
    d = entry.get("denom")
    a = entry.get("amount")
    if isinstance(d, str) and isinstance(a, (str,int)):
        # Add faucet amount
        total = add(str(a), str(faucet_amount))
        # Add all prefunded amounts
        for pf in prefunded_list:
            total = add(total, str(pf["amount"]))
        updated.append({"denom": d, "amount": total})
Path("/tmp/supply_fragment.json").write_text(json.dumps(updated, separators=(",",":")))
PY
""" % {"faucet_addr": faucet_addr, "faucet_amount": faucet_amount, "prefunded_list": prefunded_list},
            ],
        ),
        description="Prepare faucet and prefunded account multi-denom balances and updated supply from ninerealms",
    )


    # h) Single-pass placeholder replacements in genesis via sed
    plan.exec(
        "base-service",
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
CFG=%(cfg)s/genesis.json

# Read JSON fragments and tokens
cb=$(tr -d '\\n\\r' </tmp/consensus_block.json)
na=$(tr -d '\\n\\r' </tmp/node_accounts.json)
vm=$(tr -d '\\n\\r' </tmp/vault_membership.json)
ac=$(tr -d '\\n\\r' </tmp/accounts_fragment.json)
# Prefer merged balances if present (includes all denoms for faucet)
if [ -f /tmp/merged_balances_fragment.json ]; then
  bl=$(tr -d '\\n\\r' </tmp/merged_balances_fragment.json)
else
  bl=$(tr -d '\\n\\r' </tmp/balances_fragment.json)
fi
rs=$(tr -d '\\n\\r' </tmp/rune_supply.txt)
su=$(tr -d '\\n\\r' </tmp/supply_fragment.json)

# escape function
escape() { printf '%%s' "$1" | sed -e 's/[\\/&]/\\\\&/g'; }

# Apply replacements including __SUPPLY__
sed -i \
  -e "s/\\"__CONSENSUS_BLOCK__\\"/$(escape "$cb")/" \
  -e "s/\\"__NODE_ACCOUNTS__\\"/$(escape "$na")/" \
  -e "s/\\"__VAULT_MEMBERSHIP__\\"/$(escape "$vm")/" \
  -e "s/\\"__ACCOUNTS__\\"/$(escape "$ac")/" \
  -e "s/\\"__BALANCES__\\"/$(escape "$bl")/" \
  -e "s/\\"__SUPPLY__\\"/$(escape "$su")/" \
  -e "s/\\"__RUNE_SUPPLY__\\"/$(escape "$rs")/" \
  "$CFG"

# Validate JSON
python3 - << 'PY'
import json, collections
from pathlib import Path
faucet_addr = %(faucet_addr)r
faucet_amount = %(faucet_amount)d
def load_list_text(path):
    p=Path(path)
    if not p.exists(): return ""
    return p.read_text().strip()
def parse_list(txt):
    if not txt:
        return []
    try:
        return json.loads(f"[{txt}]")
    except Exception:
        try:
            j=json.loads(txt)
            return j if isinstance(j, list) else [j]
        except Exception:
            return []
def load_list(path):
    return parse_list(load_list_text(path))
def load_balances():
    merged = parse_list(load_list_text("/tmp/merged_balances_fragment.json"))
    if merged:
        return merged
    return load_list("/tmp/balances_fragment.json")
bl = load_balances()
denoms=set()
for b in bl:
    if isinstance(b, dict):
        for c in (b.get("coins") or []):
            try:
                denoms.add(str(c["denom"]))
            except Exception:
                pass
coins = [{"amount": str(faucet_amount), "denom": d} for d in sorted(denoms)]
faucet_balance = {"address": faucet_addr, "coins": coins}
addr = faucet_balance["address"]
bl = [b for b in bl if not (isinstance(b, dict) and b.get("address")==addr)]
bl.append(faucet_balance)
tot = collections.defaultdict(int)
for b in bl:
    if not isinstance(b, dict): 
        continue
    for c in (b.get("coins") or []):
        try:
            tot[str(c["denom"])] += int(str(c["amount"]))
        except Exception:
            pass
merged_balances_str = ", ".join(json.dumps(x, separators=(',',':')) for x in bl)
supply_arr = [{"denom": d, "amount": str(tot[d])} for d in sorted(tot)]
supply_str = json.dumps(supply_arr, separators=(",",":"))
Path("/tmp/merged_balances_str.txt").write_text(merged_balances_str)
Path("/tmp/supply_str.json").write_text(supply_str)
PY
bl="$(tr -d '\n\r' </tmp/merged_balances_str.txt || true)"
su="$(tr -d '\n\r' </tmp/supply_str.json || true)" 

# Scalars from launcher
GENESIS_TIME=%(genesis_time)s
CHAIN_ID=%(chain_id)s
APP_VERSION=%(app_version)s
RESERVE="$rs"

escape() { printf '%%s' "$1" | sed -e 's/[&/\\\\]/\\\\&/g'; }

sed -i \
  -e "s/\\"__GENESIS_TIME__\\"/\\"$(escape "$GENESIS_TIME")\\"/" \
  -e "s/\\"__CHAIN_ID__\\"/\\"$(escape "$CHAIN_ID")\\"/" \
  -e "s/\\"__APP_VERSION__\\"/\\"$(escape "$APP_VERSION")\\"/" \
  -e "s/\\"__RESERVE__\\"/\\"$(escape "$RESERVE")\\"/" \
  -e "s/\\"__CONSENSUS_BLOCK__\\"/$(escape "$cb")/" \
  -e "s/\\"__NODE_ACCOUNTS__\\"/$(escape "$na")/" \
  -e "s/\\"__VAULT_MEMBERSHIP__\\"/$(escape "$vm")/" \
  -e "s/\\"__ACCOUNTS__\\"/$(escape "$ac")/" \
  -e "s/\\"__BALANCES__\\"/$(escape "$bl")/" \
  -e "s/\\"__SUPPLY__\\"/$(escape "$su")/" \
  "$CFG"
python3 - << 'PY'
import json
from collections import defaultdict
p="%(cfg)s/genesis.json"
with open(p,"r") as f:
    j=json.load(f)
bank=j.get("app_state",{}).get("bank",{})
balances=bank.get("balances",[])
tot=defaultdict(int)
for b in balances:
    if isinstance(b,dict):
        for c in b.get("coins",[]) or []:
            try:
                tot[str(c["denom"])]+=int(str(c["amount"]))
            except Exception:
                pass
bank["supply"]=[{"denom": d, "amount": str(tot[d])} for d in sorted(tot)]
j["app_state"]["bank"]=bank
with open(p,"w") as f:
    json.dump(j,f,separators=(",",":"))
PY

""" % {
                    "cfg": config_folder,
                    "genesis_time": genesis_time,
                    "chain_id": chain_id,
                    "app_version": app_version,
                    "faucet_addr": faucet_addr,
                    "faucet_amount": faucet_amount,
                },
            ]
        ),
        description="Apply placeholders via single sed pass",
    )


    # j) Batch config updates
    plan.exec(
        "base-service",
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
sed -i 's/^pruning = "default"/pruning = "custom"/' "$APP"
sed -i 's/^pruning-keep-recent = "0"/pruning-keep-recent = "64"/' "$APP"
sed -i 's/^pruning-keep-every = "0"/pruning-keep-every = "0"/' "$APP"
sed -i 's/^pruning-interval = "0"/pruning-interval = "20"/' "$APP"
sed -i 's/^snapshot-interval = [0-9][0-9]*/snapshot-interval = 0/' "$APP"
sed -i 's/^iavl-cache-size = [0-9][0-9]*/iavl-cache-size = 131072/' "$APP"

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

    # # Copy thornode folder to persistent volume
    plan.exec(
        "base-service",
        ExecRecipe(
            command=[
                "/bin/sh",
                "-c",
                "set -e; rm -rf /tmp/execution-data/.thornode; cp -a /root/.thornode /tmp/execution-data/.thornode"
            ]
        )
    )

    plan.remove_service(
        "base-service",
        description = "removing base service"
    )

    node_service = plan.add_service(
        name=node_name,
        config=ServiceConfig(
            image=forking_image,
            ports=ports,
            entrypoint=[
                "/bin/sh",
                "-lc",
                "set -e; THOR_HOME=/tmp/execution-data/.thornode; if [ ! -d \"$THOR_HOME\" ]; then echo 'missing thornode home in persistent volume' >&2; exit 1; fi; ln -sfn \"$THOR_HOME\" /root/.thornode; export GOMEMLIMIT='{gomemlimit}'; printf 'validator\\nTestPassword!\\n' | {bin} start --home \"$THOR_HOME\"".format(
                    bin=binary,
                    gomemlimit=gomemlimit,
                )
            ],
            min_cpu=participant.get("min_cpu", 500),
            min_memory=participant.get("min_memory", 1024),
            files={
                "/tmp/execution-data": Directory(
                    persistent_key="node-data",
                    size=5000
                )
            },
        ),
    )

    # Provision companion CLI utility container (optional, disabled by default for cloud efficiency)
    cli_cfg = chain_cfg.get("cli_service", {})
    cli_name = None
    if chain_cfg.get("deploy_cli", False):
        cli_name = cli_cfg.get("name", "{}-cli".format(chain_name))
        cli_payload = {
            "name": cli_name,
            "type": "thorchain",
            "config_type": "cli_only",
            "profile": chain_name,
            "service_name": cli_name,
            "node_service": node_name,
            "chain_id": chain_id,
            "rpc_url": "http://{}:26657".format(node_name),
            "api_url": "http://{}:1317".format(node_name),
            "faucet_url": chain_cfg.get("faucet", {}).get("endpoint", ""),
            "cli_image": cli_cfg.get("image", "fravlaca/thor-cli-toolchain:0.1.0"),
            "persistent_key": cli_cfg.get("persistent_key", "cli-{}-thornode-home".format(chain_name)),
            "persistent_size": cli_cfg.get("persistent_size", 2048),
            "min_cpu": cli_cfg.get("min_cpu", 250),
            "min_memory": cli_cfg.get("min_memory", 256),
            "skip_toolchain_setup": cli_cfg.get("skip_toolchain_setup", False),
            "preload_keys": cli_cfg.get("preload_keys", []),
            "prefunded_accounts": chain_cfg.get("prefunded_accounts", {}),
        }
        cli_only_launcher.launch_cli_only(plan, cli_payload)

        plan.print("CLI container '{}' provisioned".format(cli_name))
    else:
        plan.print("CLI container skipped (use deploy_cli: true to enable)")

    return {
        "name": node_name,
        "ip": node_service.ip_address,
        "cli_service": cli_name,
    }
