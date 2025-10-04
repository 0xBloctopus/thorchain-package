def launch_single_node(plan, chain_cfg):
    chain_name = chain_cfg["name"]
    chain_id = chain_cfg["chain_id"]
    binary = "thornode"
    config_folder = "/root/.thornode/config"

    forking_config = chain_cfg.get("forking", {})
    forking_image = forking_config.get("image", "tiljordan/thornode-forking:1.0.17")

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

    # e.1) Apply cumulative KV diffs to genesis if present
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
CFG=%(cfg)s/genesis.json
if [ -s /tmp/diff.json ] && [ "$(tr -d '\\n\\r' </tmp/diff.json)" != "{}" ]; then
python3 - << 'PY'
import json, re
from pathlib import Path

cfg = Path("%(cfg)s/genesis.json")
diff_path = Path("/tmp/diff.json")
text = cfg.read_text()
raw = diff_path.read_text().strip()

# Try to support two shapes:
# 1) {"patches":[{"key_path":"app_state.bank","value_json":{...}}, ...]}
# 2) {"app_state.bank": {...}, "app_state.auth": {...}, ...}
targets = []
try:
    d = json.loads(raw)
    if isinstance(d, dict) and "patches" in d and isinstance(d["patches"], list):
        for e in d["patches"]:
            key = e.get("key_path")
            val = e.get("value_json", e.get("value"))
            if not key or val is None: continue
            # ignore some keys
            ign = ["thorchain.node_accounts","thorchain.vault_membership","thorchain.vault_memberships","consensus"]
            if any(key.startswith(x) for x in ign): continue
            # collapse to module when inside app_state
            if key.startswith("app_state."):
                module = key.split(".")[1]
                targets.append((module, json.dumps(val, separators=(",",":"))))
    elif isinstance(d, dict):
        for key, val in d.items():
            if not isinstance(key, str): continue
            ign = ["thorchain.node_accounts","thorchain.vault_membership","thorchain.vault_memberships","consensus"]
            if any(key.startswith(x) for x in ign): continue
            if key.startswith("app_state.") and val is not None:
                module = key.split(".")[1]
                targets.append((module, json.dumps(val, separators=(",",":"))))
except Exception:
    targets = []

# Build sed script replacing entire app_state.<module> object
def esc(s: str) -> str:
    return s.replace("\\\\","\\\\\\\\").replace("/", "\\/").replace("&","\\&").replace("$","\\$")

sed_lines = []
seen = set()
for module, payload in targets:
    if module in seen: continue
    seen.add(module)
    # pattern: "<module>": { ... } under app_state; make it non-greedy
    pattern = f'\\"{module}\\":[ ]*\\{{.*?\\}}'
    sed_lines.append(f"/{pattern}/ s//\\\"{module}\\\":{esc(payload)}/")

Path("/tmp/genesis_patch.sed").write_text("\\n".join(sed_lines))
PY
if [ -s /tmp/genesis_patch.sed ]; then
  sed -i -E -f /tmp/genesis_patch.sed "$CFG"
fi
fi
""" % {"cfg": config_folder}
            ],
        ),
        description="Apply KV diffs to genesis via single sed pass",
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
    faucet_mnemonic = f_res["extract.faucet_mnemonic"].replace("\n", "")
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                "printf '%s' '{}' > /tmp/faucet.mnemonic".format(faucet_mnemonic),
            ],
        ),
        description="Persist faucet mnemonic for downstream faucet launcher",
    )

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
                },
            ]
        ),
        description="Prepare small JSON payloads and total RUNE supply",
    )
    # Build faucet balances and supply updates for all denoms at requested height
    # Validate requested fork height and fetch cumulative KV diffs if needed
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
API_BASE="%s"
REQ="%s"
BASE=23010003
curl -sS "$API_BASE/meta" -o /tmp/diffs_meta.json
MIN=$(sed -n 's/.*"min_height":[ ]*\\([0-9]*\\).*/\\1/p' /tmp/diffs_meta.json)
MAX=$(sed -n 's/.*"max_height":[ ]*\\([0-9]*\\).*/\\1/p' /tmp/diffs_meta.json)
if [ -z "$REQ" ] || [ "$REQ" = "0" ]; then REQ="$BASE"; fi
if [ "$REQ" -lt "$MIN" ] || [ "$REQ" -gt "$MAX" ]; then
  echo "Requested height $REQ out of bounds [$MIN,$MAX]" >&2; exit 1
fi
if [ "$REQ" -le "$BASE" ]; then
  echo "{}" > /tmp/diff.json
else
  curl -sS "$API_BASE/since/$REQ" -o /tmp/diff.json
fi
"""
                % (
                    forking_config.get("diffs_api_base", "https://thorchain.bloctopus.io/bloctopus/diffs"),
                    str(forking_config.get("height", 0)),
                ),
            ],
        ),
        description="Fetch diffs meta and cumulative KV patch",
    )

    faucet_height = str(chain_cfg.get("forking", {}).get("height", 23010004))
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
API="https://thornode.ninerealms.com/cosmos/bank/v1beta1/supply?pagination.limit=500"
curl -sS -H "x-cosmos-block-height: %s" "$API" -o /tmp/supply.json
python3 - << 'PY'
import json
from pathlib import Path
faucet = %r
amt = %d
s = json.loads(Path("/tmp/supply.json").read_text() or "{}")
supply = s.get("supply", [])
denoms = [entry.get("denom") for entry in supply if "denom" in entry]
coins = [{"amount": str(amt), "denom": d} for d in denoms]
faucet_balance = {"address": faucet, "coins": coins}
Path("/tmp/faucet_balances_fragment.json").write_text(json.dumps(faucet_balance, separators=(",",":")))
# updated supply entries with faucet amount added
updated=[]
for entry in supply:
    try:
        updated.append({"denom": entry["denom"], "amount": str(int(entry["amount"]) + int(amt))})
    except Exception:
        updated.append(entry)
Path("/tmp/supply_fragment.json").write_text(json.dumps(updated, separators=(",",":")))
PY
""" % (faucet_height, faucet_addr, faucet_amount),
            ],
        ),
        description="Prepare faucet multi-denom balances and updated supply",
    )


    # h) Single-pass placeholder replacements in genesis via sed
    plan.exec(
        node_name,
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
bl=$(tr -d '\\n\\r' </tmp/balances_fragment.json)
rs=$(tr -d '\\n\\r' </tmp/rune_supply.txt)
fb=$(tr -d '\\n\\r' </tmp/faucet_balances_fragment.json 2>/dev/null || true)
su=$(tr -d '\\n\\r' </tmp/supply_fragment.json 2>/dev/null || true)

# Merge balances with faucet balance ensuring single entry per address
python3 - << 'PY'
import json
from pathlib import Path
def load_list(path):
    p=Path(path)
    if not p.exists():
        return []
    txt=p.read_text().strip()
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
bl = load_list("/tmp/balances_fragment.json")
try:
    fb = json.loads(Path("/tmp/faucet_balances_fragment.json").read_text().strip() or "{}")
except Exception:
    fb = None
if isinstance(fb, dict) and fb.get("address"):
    addr = fb["address"]
    bl = [b for b in bl if not (isinstance(b, dict) and b.get("address")==addr)]
    bl.append(fb)
Path("/tmp/merged_balances_fragment.json").write_text(", ".join(json.dumps(x, separators=(',',':')) for x in bl))
PY
mb=$(tr -d '\\n\\r' </tmp/merged_balances_fragment.json 2>/dev/null || true)
[ -n "$mb" ] && bl="$mb"

# Scalars from launcher
GENESIS_TIME=%(genesis_time)s
CHAIN_ID=%(chain_id)s
INITIAL_HEIGHT=%(initial_height)s
APP_VERSION=%(app_version)s
RESERVE="$rs"

escape() { printf '%%s' "$1" | sed -e 's/[&/\\\\]/\\\\&/g'; }

sed -i \
  -e "s/\\"__GENESIS_TIME__\\"/\\"$(escape "$GENESIS_TIME")\\"/" \
  -e "s/\\"__CHAIN_ID__\\"/\\"$(escape "$CHAIN_ID")\\"/" \
  -e "s/\\"__INITIAL_HEIGHT__\\"/\\"$(escape "$INITIAL_HEIGHT")\\"/" \
  -e "s/\\"__APP_VERSION__\\"/\\"$(escape "$APP_VERSION")\\"/" \
  -e "s/\\"__RESERVE__\\"/\\"$(escape "$RESERVE")\\"/" \
  -e "s/\\"__CONSENSUS_BLOCK__\\"/$(escape "$cb")/" \
  -e "s/\\"__NODE_ACCOUNTS__\\"/$(escape "$na")/" \
  -e "s/\\"__VAULT_MEMBERSHIP__\\"/$(escape "$vm")/" \
  -e "s/\\"__ACCOUNTS__\\"/$(escape "$ac")/" \
  -e "s/\\"__BALANCES__\\"/$(escape "$bl")/" \
  -e "s/\\"__SUPPLY__\\"/$(escape "$su")/" \
  "$CFG"
""" % {
                    "cfg": config_folder,
                    "genesis_time": genesis_time,
                    "chain_id": chain_id,
                    "initial_height": initial_height,
                    "app_version": app_version,
                },
            ]
        ),
        description="Apply placeholders via single sed pass",
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
                "nohup sh -c \"printf 'validator\\nTestPassword!\\n' | {bin} start\" >/var/log/thornode.out 2>&1 & echo $! >/tmp/thornode.pid; sleep 1".format(
                    bin=binary
                ),
            ],
        ),
        description="Start thornode in background",
    )

    return {"name": node_name, "ip": base_service.ip_address}
