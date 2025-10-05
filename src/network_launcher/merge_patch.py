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

def merge_accounts(g, patch, mods_changed):
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

def merge_balances(g, patch, mods_changed):
    bals = g["app_state"]["bank"]["balances"]
    by_addr = {}
    for b in bals:
        coins = {}
        for c in b.get("coins", []):
            d = c.get("denom"); amt = c.get("amount")
            if d is not None and amt is not None:
                coins[d] = amt
        addr = b.get("address","")
        if addr:
            by_addr[addr] = coins
    changed = False
    for b in patch:
        addr = b.get("address","")
        coins = b.get("coins", [])
        if addr not in by_addr:
            by_addr[addr] = {}
        for c in coins:
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

def merge_contracts(g, patch, mods_changed):
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

def main():
    if not DIFF.exists() or DIFF.read_text().strip() in ("", "{}"):
        return
    d = json.loads(DIFF.read_text())
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

    if isinstance(app.get("auth",{}).get("accounts"), list):
        merge_accounts(g, app["auth"]["accounts"], mods_changed)
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

    if not mods_changed:
        return

    sed_lines = []
    for mod in sorted(mods_changed):
        payload = json.dumps(g["app_state"][mod], separators=(",",":"))
        pattern = '"%s":[ ]*\\{.*?\\}' % mod
        sed_lines.append('/' + pattern + '/ s//"' + mod + '":' + esc(payload) + '/')

    SED.write_text("\n".join(sed_lines))

if __name__ == "__main__":
    main()
