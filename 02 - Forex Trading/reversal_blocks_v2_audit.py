"""Port of TWI-RB v2 (Pine) with an event log, run on bars dumped from the live TradingView chart.
v1 = same engine with dispATR 0, no overlap merge. Prints every sweep candidate and what happened to it."""
import sys, json, numpy as np, pandas as pd
SW, LIQ, DISP, ATRL, WAIT, OVL, KEEP = 5, 5, 1.5, 14, 100, 0.20, 3

def run(o, h, l, c, t, disp, ovl, log):
    n = len(c); tr = np.maximum(h, np.r_[c[0], c[:-1]]) - np.minimum(l, np.r_[c[0], c[:-1]])
    atr = pd.Series(tr).ewm(alpha=1 / ATRL, adjust=False).mean().values        # Pine ta.atr = RMA
    liq = {1: [], -1: []}; piv = {1: [], -1: []}; pend = {1: [], -1: []}; live = {1: [], -1: []}; ev = []
    def ph(i, L, s):
        p = i - L
        if p - L < 0: return None
        w = s * (h if s > 0 else l)[p - L:p + L + 1]; x = s * (h if s > 0 else l)[p]
        return (h if s > 0 else l)[p] if x == w.max() and x > (s * (h if s > 0 else l)[p - L:p]).max() else None
    for i in range(n):
        for s, X in ((1, h), (-1, l)):
            for q in liq[s]:
                if q[2] is None and s * X[i] > s * q[0]: q[2] = i
            del liq[s][:-40]
        pb = i - SW
        for s in (1, -1):
            p = ph(i, SW, s)
            if p is None: continue
            leg = next((q for q in reversed(piv[-s]) if q[1] < pb), None)
            if leg is not None:
                cand = [q for q in liq[s] if q[2] is not None and q[1] < leg[1] < q[2] <= pb and s * q[0] < s * p]
                if cand:
                    old = max(cand, key=lambda q: s * q[0])
                    body = max(o[pb], c[pb]) if s > 0 else min(o[pb], c[pb])
                    near = min(old[0], body) if s > 0 else max(old[0], body)
                    cl = c[pb + 1:i + 1]; ext = cl.min() if s > 0 else cl.max()
                    pend[s].append(dict(far=p, near=near, trig=leg[0], piv=pb, born=i, old=old, atr=atr[pb], ext=ext,
                                        bos=(ext < leg[0]) if s > 0 else (ext > leg[0])))
            piv[s].append([p, pb]); del piv[s][:-20]
        for s in (1, -1):
            p = ph(i, LIQ, s)
            if p is not None: liq[s].append([p, i - LIQ, None])
        for s in (1, -1):
            keep = []
            for q in pend[s]:
                first = i == q["born"]
                beyond = (not first) and (h[i] > q["far"] if s > 0 else l[i] < q["far"])
                if not first:
                    q["ext"] = min(q["ext"], c[i]) if s > 0 else max(q["ext"], c[i])
                    q["bos"] = q["bos"] or (c[i] < q["trig"] if s > 0 else c[i] > q["trig"])
                move = (q["far"] - q["ext"]) if s > 0 else (q["ext"] - q["far"])
                tag = dict(side="SELL" if s > 0 else "BUY", sweep=q["far"], swept=q["old"][0], sweep_t=t[q["piv"]], swept_t=t[q["old"][1]],
                           legstart=q["trig"], disp_atr=round(move / q["atr"], 2))
                if beyond: ev.append({**tag, "result": "rejected: price took the sweep extreme before confirming", "t": t[i]}); continue
                if i - q["born"] > WAIT: ev.append({**tag, "result": "rejected: not confirmed in time", "t": t[i]}); continue
                if move >= disp * q["atr"] and q["bos"]:
                    top, bot = (q["far"], q["near"]) if s > 0 else (q["near"], q["far"])
                    skip = top <= bot; merged = []
                    if not skip:
                        for b in list(live[s]):
                            ov = min(top, b["top"]) - max(bot, b["bot"]); hh = min(top - bot, b["top"] - b["bot"])
                            if hh > 0 and ov / hh >= ovl:
                                if (top > b["top"]) if s > 0 else (bot < b["bot"]): live[s].remove(b); merged.append(b); b["ev"]["result"] = f"replaced by the more extreme zone confirmed {t[i]}"
                                else: skip = True; tag["result"] = f"merged into the existing zone {b['bot']}-{b['top']}"
                    if skip:
                        if "result" not in tag: tag["result"] = "rejected: zero height"
                        ev.append({**tag, "t": t[i]}); continue
                    e = {**tag, "result": "ACCEPTED", "zone": f"{bot}-{top}", "t": t[i]}; ev.append(e)
                    b = dict(top=top, bot=bot, conf=i, ev=e); live[s].append(b)
                    while len(live[s]) > KEEP: x = live[s].pop(0); x["ev"]["result"] = "ACCEPTED, later dropped (only 3 per side shown)"
                    continue
                keep.append(q)
            pend[s] = keep
            for b in list(live[s]):
                if i > b["conf"] and (c[i] > b["top"] if s > 0 else c[i] < b["bot"]):
                    live[s].remove(b); b["ev"]["result"] = f"ACCEPTED, broken {t[i]}"
    for s in (1, -1):
        for q in pend[s]:
            move = (q["far"] - q["ext"]) if s > 0 else (q["ext"] - q["far"])
            ev.append(dict(side="SELL" if s > 0 else "BUY", sweep=q["far"], swept=q["old"][0], sweep_t=t[q["piv"]], swept_t=t[q["old"][1]],
                           legstart=q["trig"], disp_atr=round(move / q["atr"], 2), t="-",
                           result=("waiting: displacement only %.2f ATR" % (move / q["atr"])) if q["bos"] else "waiting: no structure break yet"))
    return ev

for f in sys.argv[1:]:
    bars = json.load(open(f))["bars"]; df = pd.DataFrame(bars)
    t = pd.to_datetime(df.time, unit="s").dt.tz_localize("UTC").dt.tz_convert("America/Los_Angeles").dt.strftime("%m-%d %H:%M").values
    a = [df[k].values for k in ("open", "high", "low", "close")]
    print(f"\n######## {f.split('/')[-1]}  ({t[0]} -> {t[-1]} PT, {len(df)} bars)")
    for name, disp, ovl in (("v1 (old rules)", 0.0, 9e9), ("v2", DISP, OVL)):
        ev = run(*a, t, disp, ovl, None)
        acc = [e for e in ev if e["result"].startswith("ACCEPTED")]
        live = [e for e in acc if e["result"] == "ACCEPTED"]
        print(f"--- {name}: {len(acc)} zones made, {len(live)} live at the end")
        if name == "v2":
            for e in ev:
                print(f"  {e['side']:4s} sweep {e['sweep']} @ {e['sweep_t']} took {e['swept']} (@ {e['swept_t']}), leg start {e['legstart']}, "
                      f"displacement {e['disp_atr']} ATR -> {e['result']}" + (f" [{e['zone']}, confirmed {e['t']}]" if 'zone' in e else ""))
