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
    req_height = int(forking_config.get("height", 0))
    initial_height = str(req_height + 1) if req_height > 0 else str(chain_cfg.get("initial_height", 1))

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
curl -sS --compressed "$API_BASE/meta" -o /tmp/diffs_meta.json
MIN=$(sed -n 's/.*"min_height":[ ]*\\([0-9]*\\).*/\\1/p' /tmp/diffs_meta.json)
MAX=$(sed -n 's/.*"max_height":[ ]*\\([0-9]*\\).*/\\1/p' /tmp/diffs_meta.json)
: > /tmp/diff.info
echo "API_BASE=$API_BASE" >> /tmp/diff.info
echo "REQ=$REQ MIN=$MIN MAX=$MAX" >> /tmp/diff.info
if [ -z "$REQ" ] || [ "$REQ" = "0" ]; then REQ="$BASE"; fi
if [ "$REQ" -lt "$MIN" ] || [ "$REQ" -gt "$MAX" ]; then
  echo "Requested height $REQ out of bounds [$MIN,$MAX]" >&2; exit 1
fi
MODE="none"
if [ "$REQ" -le "$BASE" ]; then
  echo "{}" > /tmp/diff.json
  MODE="none"
  touch /tmp/diff.ready
else
  # High-level app_state patch endpoint only
  curl -sS --compressed "$API_BASE/patch/since/$REQ" -o /tmp/diff.json
  MODE="appstate"
  touch /tmp/diff.ready
fi
if [ -f /tmp/diff.json ]; then
  echo "MODE=$MODE" >> /tmp/diff.info
  echo -n "diff_size=" >> /tmp/diff.info
  wc -c </tmp/diff.json >> /tmp/diff.info
  head -c 200 /tmp/diff.json > /tmp/diff.head || true
else
  echo "no diff.json" >> /tmp/diff.info
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

    # e.1) Apply cumulative KV diffs to genesis if present (after fetching diffs)
    plan.exec(
        node_name,
        ExecRecipe(
            command=[
                "/bin/sh",
                "-lc",
                """
set -e
CFG=%(cfg)s/genesis.json
if [ -f /tmp/diff.ready ] && [ -s /tmp/diff.json ] && [ "$(tr -d '\\n\\r' </tmp/diff.json)" != "{}" ]; then
cat >/tmp/merge_patch.py << 'PY'
import json
from pathlib import Path

cfg = Path("%(cfg)s/genesis.json")
d = json.loads(Path("/tmp/diff.json").read_text())

app = d.get("app_state") or {}
g = json.loads(cfg.read_text())

def ensure(obj, path, default):
    cur = obj
    for k in path[:-1]:
        cur = cur.setdefault(k, {})
    cur.setdefault(path[-1], default)

ensure(g, ["app_state","auth","accounts"], [])
ensure(g, ["app_state","bank","balances"], [])
ensure(g, ["app_state","thorchain","mimirs"], [])
ensure(g, ["app_state","thorchain","vaults"], [])
ensure(g, ["app_state","thorchain","pools"], [])
ensure(g, ["app_state","wasm","codes"], [])
ensure(g, ["app_state","wasm","contracts"], [])

mods_changed = set()

def merge_accounts(g, patch):
    accs = g["app_state"]["auth"]["accounts"]
    idx = {a.get("account_number"): i for i, a in enumerate(accs)}
    changed = False
    for a in patch:
        k = a.get("account_number")
        if k in idx:
            accs[idx[k]] = a
        else:
            accs.append(a)
        changed = True
    if changed:
        mods_changed.add("auth")

def merge_balances(g, patch):
    bals = g["app_state"]["bank"]["balances"]
    by_addr = {}
    for b in bals:
        coins = {}
        for c in b.get("coins", []):
            d = c.get("denom"); amt = c.get("amount")
            if d is not None and amt is not None:
                coins[d] = amt
        by_addr[b.get("address","")] = coins
    changed = False
    for b in patch:
        addr = b.get("address","")
        coins = b.get("coins", [])
        if addr not in by_addr:
            by_addr[addr] = {}
        for c in coins:
            d = c.get("denom"); amt = c.get("amount")
            if d is None or amt is None: continue
            by_addr[addr][d] = amt
            changed = True
    if changed:
        new_bals = []
        for addr, cm in by_addr.items():
            new_bals.append({"address": addr, "coins": [{"denom": d, "amount": a} for d, a in cm.items()]})
        g["app_state"]["bank"]["balances"] = new_bals
        mods_changed.add("bank")

def merge_mimirs(g, patch):
    cur = g["app_state"]["thorchain"]["mimirs"]
    idx = {m.get("key"): i for i, m in enumerate(cur) if isinstance(m, dict)}
    changed = False
    for m in patch:
        k = m.get("key")
        if k in idx:
            cur[idx[k]] = m
        else:
            cur.append(m)
        changed = True
    if changed:
        g["app_state"]["thorchain"]["mimirs"] = cur
        mods_changed.add("thorchain")

def merge_vaults(g, patch):
    vlist = g["app_state"]["thorchain"]["vaults"]
    idx = {v.get("pub_key"): i for i, v in enumerate(vlist)}
    try:
        membership = json.loads(Path("/tmp/vault_membership.json").read_text())
    except Exception:
        membership = []
    changed = False
    for v in patch:
        pk = v.get("pub_key")
        if pk in idx:
            existing = vlist[idx[pk]]
            keep_membership = existing.get("membership", [])
            nv = dict(v)
            nv["membership"] = keep_membership
            vlist[idx[pk]] = nv
        else:
            nv = dict(v)
            nv["membership"] = membership
            vlist.append(nv)
        changed = True
    if changed:
        g["app_state"]["thorchain"]["vaults"] = vlist
        mods_changed.add("thorchain")

def merge_pools(g, patch):
    cur = g["app_state"]["thorchain"]["pools"]
    idx = {p.get("asset"): i for i, p in enumerate(cur) if isinstance(p, dict)}
    changed = False
    for p in patch:
        a = p.get("asset")
        if a in idx:
            cur[idx[a]] = p
        else:
            cur.append(p)
        changed = True
    if changed:
        g["app_state"]["thorchain"]["pools"] = cur
        mods_changed.add("thorchain")

def merge_codes(g, patch):
    codes = g["app_state"]["wasm"]["codes"]
    idx = {str(c.get("code_id")): i for i, c in enumerate(codes)}
    changed = False
    for c in patch:
        cid = str(c.get("code_id"))
        if cid in idx:
            codes[idx[cid]] = c
        else:
            codes.append(c)
        changed = True
    if changed:
        g["app_state"]["wasm"]["codes"] = codes
        mods_changed.add("wasm")

def merge_contracts(g, patch):
    cs = g["app_state"]["wasm"]["contracts"]
    idx = {c.get("contract_address"): i for i, c in enumerate(cs)}
    changed = False
    for c in patch:
        addr = c.get("contract_address")
        if addr in idx:
            cs[idx[addr]] = c
        else:
            cs.append(c)
        changed = True
    if changed:
        g["app_state"]["wasm"]["contracts"] = cs
        mods_changed.add("wasm")

if isinstance(app.get("auth",{}).get("accounts"), list):
    merge_accounts(g, app["auth"]["accounts"])
if isinstance(app.get("bank",{}).get("balances"), list):
    merge_balances(g, app["bank"]["balances"])
th = app.get("thorchain",{})
if isinstance(th.get("mimirs"), list):
    merge_mimirs(g, th["mimirs"])
if isinstance(th.get("vaults"), list):
    merge_vaults(g, th["vaults"])
if isinstance(th.get("pools"), list):
    merge_pools(g, th["pools"])
w = app.get("wasm",{})
if isinstance(w.get("codes"), list):
    merge_codes(g, w["codes"])
if isinstance(w.get("contracts"), list):
    merge_contracts(g, w["contracts"])

def esc(s):
    b = chr(92)
    return s.replace(b, b + b).replace('/', b + '/').replace('&', b + '&')

sed_lines = []
for mod in sorted(mods_changed):
    payload = json.dumps(g["app_state"][mod], separators=(",",":"))
    pattern = '"%%s":[ ]*\\{.*?\\}' %% mod
    sed_lines.append('/' + pattern + '/ s//"' + mod + '":' + esc(payload) + '/')

Path("/tmp/genesis_patch.sed").write_text("\\n".join(sed_lines))
PY
python3 /tmp/merge_patch.py
if [ -s /tmp/genesis_patch.sed ]; then
  sed -i -E -f /tmp/genesis_patch.sed "$CFG"
fi
fi
""" % {"cfg": config_folder}
            ],
        ),
        description="Apply KV diffs to genesis via single sed pass",
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
python3 - << 'PY'
import json, collections
from pathlib import Path

# Injected from launcher
faucet_addr = %r
faucet_amount = %d

# Merge existing balances with faucet balance and compute full supply
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

# Derive denom set from existing balances and build faucet balance file
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
Path("/tmp/faucet_balances_fragment.json").write_text(json.dumps(faucet_balance, separators=(",",":")))

# Merge ensuring single entry for faucet
fb = faucet_balance
addr = fb["address"]
bl = [b for b in bl if not (isinstance(b, dict) and b.get("address")==addr)]
bl.append(fb)
Path("/tmp/merged_balances_fragment.json").write_text(", ".join(json.dumps(x, separators=(',',':')) for x in bl))

# Compute supply from merged balances
tot = collections.defaultdict(int)
for b in bl:
    if not isinstance(b, dict):
        continue
    coins = b.get("coins", [])
    if not isinstance(coins, list):
        continue
    for c in coins:
        try:
            d = str(c["denom"])
            a = int(str(c["amount"]))
            tot[d] += a
        except Exception:
            pass

supply = [{"denom": d, "amount": str(tot[d])} for d in sorted(tot)]
Path("/tmp/supply_fragment.json").write_text(json.dumps(supply, separators=(",",":")))
PY
""" % (faucet_addr, faucet_amount),
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

# Build faucet balance and recompute supply inline via captured Python below

# compute and persist merged balances string and supply json via Python (avoid command substitution pitfalls)
python3 - << 'PY'
import json, collections
from pathlib import Path
faucet_addr = %(faucet_addr)r
faucet_amount = %(faucet_amount)d
def load_list_text(path):
    p=Path(path)
    if not p.exists(): return ""
    return p.read_text().strip()
def load_list(path):
    txt = load_list_text(path)
    if not txt: return []
    try:
        return json.loads(f"[{txt}]")
    except Exception:
        try:
            j=json.loads(txt)
            return j if isinstance(j, list) else [j]
        except Exception:
            return []
bl = load_list("/tmp/balances_fragment.json")
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
                    "initial_height": initial_height,
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
