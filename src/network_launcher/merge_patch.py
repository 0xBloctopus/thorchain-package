#!/usr/bin/env python3
import json
from pathlib import Path

CFG = Path("/root/.thornode/config/genesis.json")
DIFF = Path("/tmp/diff.json")
SED = Path("/tmp/genesis_patch.sed")
VAULT_MEMBERSHIP = Path("/tmp/vault_membership.json")

def ensure(obj, path, default):
    cur = obj
    for k in path[:-1]:
        cur = cur.setdefault(k, {})
    cur.setdefault(path[-1], default)

def esc(s):
    b = chr(92)
    return s.replace(b, b + b).replace('/', b + '/').replace('&', b + '&')

def _normalize_string_field(v):
    if isinstance(v, str):
        try:
            dec = json.loads(v)
            if isinstance(dec, (str, int, float, bool)) or dec is None:
                return str(dec) if not isinstance(dec, str) else dec
            return ""
        except Exception:
            return v
    return ""

def _destringify_primitives_inplace(v):
    if isinstance(v, dict):
        for k in list(v.keys()):
            v[k] = _destringify_primitives_inplace(v[k])
        return v
    if isinstance(v, list):
        for i in range(len(v)):
            v[i] = _destringify_primitives_inplace(v[i])
        return v
    if isinstance(v, str):
        s = v.lstrip()
        if s[:1] in "[{":
            try:
                dec = json.loads(v)
                if isinstance(dec, (str, int, float, bool)) or dec is None:
                    return dec
            except Exception:
                return v
        return v
def _stringify_amounts_inplace(v, keys=None):
    if keys is None:
        keys = {
            "amount",
            "LP_units",
            "synth_units",
            "balance_asset",
            "balance_rune",
            "pending_inbound_asset",
            "pending_inbound_rune",
            "reserve",
        }
    if isinstance(v, dict):
        for k in list(v.keys()):
            val = v[k]
            if k in keys and isinstance(val, (int, float)):
                v[k] = str(int(val)) if isinstance(val, float) and val.is_integer() else str(val)
            else:
                _stringify_amounts_inplace(val, keys)
        return v
    if isinstance(v, list):
        for i in range(len(v)):
            _stringify_amounts_inplace(v[i], keys)
        return v
    return v

    return v
def _coerce_thorchain_lists_inplace(app_state):
    tc = (app_state or {}).get("thorchain")
    if not isinstance(tc, dict):
        return
    expected_lists = [
        "pools",
        "liquidity_providers",
        "observed_tx_in_voters",
        "observed_tx_out_voters",
        "tx_outs",
        "node_accounts",
        "vaults",
        "reserve_contributors",
        "last_chain_heights",
        "adv_swap_queue_items",
        "network_fees",
        "chain_contracts",
        "THORNames",
        "mimirs",
        "bond_providers",
        "loans",
        "streaming_swaps",
        "swap_queue_items",
        "swapper_clout",
        "trade_accounts",
        "trade_units",
        "outbound_fee_withheld_rune",
        "outbound_fee_spent_rune",
        "rune_providers",
        "secured_assets",
        "nodeMimirs",
        "loan_total_collateral",
        "affiliate_collectors",
        "tcy_claimers",
        "tcy_stakers",
    ]
    for k in expected_lists:
        v = tc.get(k)
        if not isinstance(v, list):
            tc[k] = []
def _coerce_thorchain_nested_inplace(app_state):
    tc = (app_state or {}).get("thorchain")
    if not isinstance(tc, dict):
        return
    vlist = tc.get("vaults")
    if isinstance(vlist, list):
        for v in vlist:
            if isinstance(v, dict):
                m = v.get("membership")
                if isinstance(m, str):
                    s = m.strip()
                    try:
                        dec = json.loads(s) if s[:1] in "[{" else []
                    except Exception:
                        dec = []
                    if not isinstance(dec, list):
                        dec = []
                    v["membership"] = dec
                elif not isinstance(m, list):
                    v["membership"] = []
    for key in ("observed_tx_in_voters", "observed_tx_out_voters"):
        voters = tc.get(key)
        if isinstance(voters, list):
            for rec in voters:
                if isinstance(rec, dict):
                    txs = rec.get("txs")
                    if isinstance(txs, str):
                        s = txs.strip()
                        try:
                            dec = json.loads(s) if s[:1] in "[{" else []
                        except Exception:
                            dec = []
                        if not isinstance(dec, list):
                            dec = []
                        rec["txs"] = dec
                    elif not isinstance(txs, list):
                        rec["txs"] = []
    plist = tc.get("pools")
    if isinstance(plist, list):
        for p in plist:
            if isinstance(p, dict):
                for k in ("pending_inbound_tx", "pending_outbound_tx", "pending_liquidity"):
                    val = p.get(k)
                    if isinstance(val, str):
                        s = val.strip()
                        try:
                            dec = json.loads(s) if s[:1] in "[{" else []
                        except Exception:
                            dec = []
                        if not isinstance(dec, list):
                            dec = []
                        p[k] = dec
                    elif val is not None and not isinstance(val, list):
                        p[k] = []



def merge_accounts(g, patch, mods_changed):
    accs = g["app_state"]["auth"]["accounts"]
    accs = [a for a in accs if isinstance(a, dict)]
    idx = {a.get("account_number"): i for i, a in enumerate(accs) if isinstance(a.get("account_number"), (str,int))}
    changed = False
    for a in patch:
        if not isinstance(a, dict):
            continue
        k = a.get("account_number")
        if k in idx:
            accs[idx[k]] = a
        else:
            accs.append(a)
        changed = True
    if changed:
        g["app_state"]["auth"]["accounts"] = accs
        mods_changed.add("auth")

def merge_balances(g, patch, mods_changed):
    bals = g["app_state"]["bank"]["balances"]
    bals = [b for b in bals if isinstance(b, dict)]
    by_addr = {}
    for b in bals:
        addr = b.get("address", "")
        if not addr:
            continue
        cur_coins = b.get("coins", [])
        if not isinstance(cur_coins, list):
            cur_coins = []
        coins_map = {}
        for c in cur_coins:
            if not isinstance(c, dict):
                continue
            d = c.get("denom"); amt = c.get("amount")
            if d is not None and amt is not None:
                coins_map[d] = amt
        by_addr[addr] = coins_map
    changed = False
    for b in patch:
        if not isinstance(b, dict):
            continue
        addr = b.get("address","")
        if not addr:
            continue
        if addr not in by_addr:
            by_addr[addr] = {}
        coins = b.get("coins", [])
        if not isinstance(coins, list):
            coins = []
        for c in coins:
            if not isinstance(c, dict):
                continue
            d = c.get("denom"); amt = c.get("amount")
            if d is None or amt is None:
                continue
            by_addr[addr][d] = amt
            changed = True
    if changed:
        new_bals = []
        for addr, cm in by_addr.items():
            new_bals.append({"address": addr, "coins": [{"denom": d, "amount": a} for d, a in cm.items()]})
        g["app_state"]["bank"]["balances"] = new_bals
        mods_changed.add("bank")

def merge_mimirs(g, patch, mods_changed):
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

def merge_vaults(g, patch, mods_changed):
    vlist = g["app_state"]["thorchain"]["vaults"]
    idx = {v.get("pub_key"): i for i, v in enumerate(vlist)}
    try:
        membership = json.loads(VAULT_MEMBERSHIP.read_text())
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

def merge_pools(g, patch, mods_changed):
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

def merge_codes(g, patch, mods_changed):
    codes = g["app_state"]["wasm"]["codes"]
    codes = [c for c in codes if isinstance(c, dict)]
    idx = {str(c.get("code_id")): i for i, c in enumerate(codes)}
    changed = False
    for c in patch:
        if not isinstance(c, dict):
            continue
        cid = str(c.get("code_id"))
        if cid in idx:
            codes[idx[cid]] = c
        else:
            codes.append(c)
        changed = True
    if changed:
        g["app_state"]["wasm"]["codes"] = codes
        mods_changed.add("wasm")

def merge_contracts(g, patch, mods_changed):
    cs = g["app_state"]["wasm"]["contracts"]
    cs = [c for c in cs if isinstance(c, dict)]
    idx = {c.get("contract_address"): i for i, c in enumerate(cs)}
    changed = False
    def sanitize_contract_info(ci):
        if not isinstance(ci, dict):
            return ci
        if "contract" in ci:
            ci.pop("contract", None)
        for key in ("admin", "ibc_port_id"):
            if key in ci:
                ci[key] = _normalize_string_field(ci[key])
        return ci
    for c in patch:
        if not isinstance(c, dict):
            continue
        addr = c.get("contract_address")
        if "contract_info" in c:
            c["contract_info"] = sanitize_contract_info(c["contract_info"])
        if addr in idx:
            cs[idx[addr]] = c
        else:
            cs.append(c)
        changed = True
    if changed:
        g["app_state"]["wasm"]["contracts"] = cs
        mods_changed.add("wasm")

def main():
    if not DIFF.exists():
        print("diff_absent")
        return
    diff_txt = DIFF.read_text().strip()
    if diff_txt in ("", "{}"):
        print("diff_empty")
        return
    d = json.loads(diff_txt)
    app = d.get("app_state") or {}
    g = json.loads(CFG.read_text())

    ensure(g, ["app_state","auth","accounts"], [])
    ensure(g, ["app_state","bank","balances"], [])
    ensure(g, ["app_state","thorchain","mimirs"], [])
    ensure(g, ["app_state","thorchain","vaults"], [])
    ensure(g, ["app_state","thorchain","pools"], [])
    ensure(g, ["app_state","wasm","codes"], [])
    ensure(g, ["app_state","wasm","contracts"], [])

    mods_changed = set()

    # if isinstance(app.get("auth",{}).get("accounts"), list):
    #     merge_accounts(g, app["auth"]["accounts"], mods_changed)
    if isinstance(app.get("bank",{}).get("balances"), list):
        merge_balances(g, app["bank"]["balances"], mods_changed)
    th = app.get("thorchain",{})
    if isinstance(th.get("mimirs"), list):
        merge_mimirs(g, th["mimirs"], mods_changed)
    if isinstance(th.get("vaults"), list):
        merge_vaults(g, th["vaults"], mods_changed)
    if isinstance(th.get("pools"), list):
        merge_pools(g, th["pools"], mods_changed)
    w = app.get("wasm",{})
    if isinstance(w.get("codes"), list):
        merge_codes(g, w["codes"], mods_changed)
    if isinstance(w.get("contracts"), list):
        merge_contracts(g, w["contracts"], mods_changed)
    try:
        all_cs = g["app_state"]["wasm"]["contracts"]
        if isinstance(all_cs, list):
            for i, c in enumerate(all_cs):
                if isinstance(c, dict) and isinstance(c.get("contract_info"), dict):
                    ci = c["contract_info"]
                    if "contract" in ci:
                        ci.pop("contract", None)
                    for key in ("admin", "ibc_port_id"):
                        if key in ci:
                            ci[key] = _normalize_string_field(ci[key])
            mods_changed.add("wasm")
    except Exception:
        pass


    if not mods_changed:
        print("mods_changed=0")
        return

    _coerce_thorchain_lists_inplace(g["app_state"])
    _coerce_thorchain_nested_inplace(g["app_state"])
    g["app_state"] = _destringify_primitives_inplace(g["app_state"])
    _stringify_amounts_inplace(g["app_state"])
    CFG.write_text(json.dumps(g, separators=(",",":")))
    print("mods_changed=%d applied_json=1" % (len(mods_changed)))

if __name__ == "__main__":
    main()
