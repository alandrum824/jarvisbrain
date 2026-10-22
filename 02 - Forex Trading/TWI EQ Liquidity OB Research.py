"""Pattern research for TWI EQ Liquidity OB v7 (same rules as the Pine). READ-ONLY (bars only, no orders).
Replicates: equal highs/lows on confirmed pivots (3/3) -> close beyond the middle swing (BOS) -> retest of the frozen OB
-> rejection close entry -> stop just beyond the zone (+0.1 ATR) -> TP1 nearest pivot / TP2 previous low/high (origin, >= 3 ATR).
Then measures what price does after entry: MFE, TP1/TP2/stop order, give-back after TP1, sweeps of the equal level,
and three ways to manage the trade. R is net of a per-trade cost (spread, price units).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe "TWI EQ Liquidity OB Research.py"
"""
import sys
import numpy as np, pandas as pd
import MetaTrader5 as mt5

COST = {"US30": 5.2, "XAUUSD": 0.35}
SETS = [("US30", "M5", mt5.TIMEFRAME_M5), ("XAUUSD", "M5", mt5.TIMEFRAME_M5),
        ("US30", "M15", mt5.TIMEFRAME_M15), ("XAUUSD", "M15", mt5.TIMEFRAME_M15)]
P = dict(piv=3, eqTol=0.15, minGap=3, maxGap=60, minDip=0.5, beyond=0.05, bosMax=40, obLook=5, obMax=1.5,
         retestMax=120, invAccept=2, invBuf=0.10, stopBuf=0.10, minRisk=0.15, maxRisk=4.0, minTp=0.5,
         originLook=150, originMin=3.0, maxHold=288, entryZone="top", stopAt="zone", trigger="equal", sweepMax=2.0)
# trigger: "equal" = equal highs/lows (indicator) | "sweep" = Adam's model: a new swing high runs a prior swing high
#          (by 0.05..sweepMax ATR) and closes back below it within the pivot's 3 confirm bars -> CHoCH of the low between -> return -> drop
# entryZone: "top" = OB at the 2nd top (indicator v7) | "advance" = advance water block: last opposite candle before the BOS
# stopAt: "zone" = beyond the entry zone | "top" = beyond the top block (the teacher's stop)


def atr_rma(df, n=14):
    h, l, c = df.high.values, df.low.values, df.close.values
    tr = np.maximum(h - l, np.maximum(abs(h - np.roll(c, 1)), abs(l - np.roll(c, 1))))
    tr[0] = h[0] - l[0]
    a = np.full(len(tr), np.nan)
    a[n - 1] = tr[:n].mean()
    for i in range(n, len(tr)):
        a[i] = (a[i - 1] * (n - 1) + tr[i]) / n
    return a


def run(df):
    H, L, O, C = df.high.values, df.low.values, df.open.values, df.close.values
    A = atr_rma(df)
    n = len(df); pv = P["piv"]
    phP, phB, plP, plB = [], [], [], []
    setups, trades = [], []
    for i in range(30, n):
        a = A[i]
        if np.isnan(a):
            continue
        tol = P["eqTol"] * a
        pb = i - pv
        isPH = H[pb] > H[pb - pv:pb].max() and H[pb] >= H[pb + 1:i + 1].max()
        isPL = L[pb] < L[pb - pv:pb].min() and L[pb] <= L[pb + 1:i + 1].min()
        for d, isP, PP, PB in ((-1, isPH, phP, phB), (1, isPL, plP, plB)):
            if not isP:
                continue
            p = H[pb] if d == -1 else L[pb]
            for j in range(len(PP) - 1, -1, -1):
                q, qb = PP[j], PB[j]; gap = pb - qb
                if gap < P["minGap"]:
                    continue
                if gap > P["maxGap"]:
                    break
                if P["trigger"] == "sweep":
                    ext = d * (q - p)
                    back = (C[pb:i + 1].min() < q) if d == -1 else (C[pb:i + 1].max() > q)
                    if not (0.05 * a < ext <= P["sweepMax"] * a and back):
                        continue
                    hit = True
                else:
                    hit = abs(p - q) <= tol
                if hit:
                    lvl = (max(p, q) if d == -1 else min(p, q)) if P["trigger"] == "equal" else p
                    lim = lvl + tol if P["trigger"] == "equal" else q
                    seg = slice(qb + 1, pb)
                    if d == -1:
                        clean = not (H[seg] > (lim if d == -1 else lvl + tol)).any(); midv = L[seg].min() if pb - qb > 1 else np.nan
                        midb = qb + 1 + int(L[seg].argmin()) if pb - qb > 1 else -1
                    else:
                        clean = not (L[seg] < (lvl - tol if P["trigger"] == "equal" else lim)).any(); midv = H[seg].max() if pb - qb > 1 else np.nan
                        midb = qb + 1 + int(H[seg].argmax()) if pb - qb > 1 else -1
                    dup = any(s["d"] == d and ((s["st"] <= 2 and abs(s["eq"] - lvl) <= tol) or s["b2"] == qb) for s in setups)
                    if clean and not dup and not np.isnan(midv) and d * (midv - lvl) >= P["minDip"] * a:
                        k = pb
                        for kk in range(pb, max(pb - P["obLook"], 0) - 1, -1):
                            if d * (C[kk] - O[kk]) < 0:
                                k = kk; break
                        zh, zl = H[k], L[k]
                        if zh - zl > P["obMax"] * a:
                            zh, zl = max(O[k], C[k]), min(O[k], C[k])
                        org = np.nan
                        for kk in range(qb, max(qb - P["originLook"], 0) - 1, -1):
                            if kk < qb and not np.isnan(org):
                                beyond = H[kk] > lvl + tol if d == -1 else L[kk] < lvl - tol
                                if beyond and d * (lvl - org) >= P["originMin"] * a:
                                    break
                            v = L[kk] if d == -1 else H[kk]
                            if np.isnan(org) or d * (v - org) > 0:
                                org = v
                        setups.append(dict(d=d, eq=lvl, b1=qb, b2=pb, mid=midv, st=0, zt=zh, zb=zl, org=org, fvg=False,
                                           bos=-1, wrong=0, ret=-1, created=i))
                    break
            PP.append(p); PB.append(pb)
            if len(PP) > 200:
                PP.pop(0); PB.pop(0)
        for s in setups:
            d = s["d"]
            if s["st"] == 0:
                if i - s["b2"] > P["bosMax"]:
                    s["st"] = 5
                elif d * (s["eq"] - C[i]) > tol:
                    s["st"] = 5
                elif d * (C[i] - s["mid"]) > P["beyond"] * a:
                    for k in range(i - s["b2"] - 1):
                        if (d == 1 and L[i - k] > H[i - k - 2]) or (d == -1 and H[i - k] < L[i - k - 2]):
                            s["fvg"] = True
                    s["bos"] = i; s["st"] = 1
                    kk0 = None
                    for kk in range(i - 1, s["b2"], -1):
                        if d * (C[kk] - O[kk]) < 0:
                            kk0 = kk; break
                    if kk0 is None:
                        s["at"], s["ab"] = max(O[i], C[i]), min(O[i], C[i])
                    else:
                        s["at"], s["ab"] = H[kk0], L[kk0]
                        if H[kk0] - L[kk0] > P["obMax"] * a:
                            s["at"], s["ab"] = max(O[kk0], C[kk0]), min(O[kk0], C[kk0])
            if s["st"] in (1, 2):
                zt, zb = (s["at"], s["ab"]) if P["entryZone"] == "advance" else (s["zt"], s["zb"])
                near = zt if d == 1 else zb
                far = (s["zb"] if d == 1 else s["zt"]) if P["stopAt"] == "top" else (zb if d == 1 else zt)
                s["wrong"] = s["wrong"] + 1 if d * (far - C[i]) > P["invBuf"] * a else 0
                if s["wrong"] >= P["invAccept"] or d * (s["eq"] - C[i]) > tol:
                    s["st"] = 4
                elif i - s["bos"] > P["retestMax"]:
                    s["st"] = 5
                else:
                    touched = L[i] <= near if d == 1 else H[i] >= near
                    if s["st"] == 1 and touched and i > s["bos"]:
                        s["st"] = 2; s["ret"] = i
                    if s["st"] == 2 and d * (C[i] - near) > 0 and d * (C[i] - O[i]) > 0:
                        ent = C[i]; stop = far - d * P["stopBuf"] * a; risk = d * (ent - stop)
                        if not (P["minRisk"] * a <= risk <= P["maxRisk"] * a):
                            s["st"] = 5; continue
                        PPs = phP if d == 1 else plP
                        t1 = None
                        for q in PPs:
                            if d * (q - ent) >= P["minTp"] * a and (t1 is None or d * q < d * t1):
                                t1 = q
                        t2 = None
                        if t1 is not None:
                            for q in PPs:
                                if d * (q - t1) >= 0.15 * a and (t2 is None or d * q < d * t2):
                                    t2 = q
                        og = s["org"] if not np.isnan(s["org"]) and d * (s["org"] - ent) >= P["minTp"] * a else None
                        if og is not None:
                            t1 = t1 if (t1 is not None and d * (og - t1) >= 0.15 * a) else og
                            t2 = None if t1 == og else og
                        s["st"] = 3
                        trades.append(dict(i=i, d=d, ent=ent, stop=stop, risk=risk, t1=t1, t2=t2, eq=s["eq"], fvg=s["fvg"],
                                           atr=a, retBars=i - s["bos"], riskATR=risk / a, zoneATR=(s["zt"] - s["zb"]) / a))
        setups = [s for s in setups if s["st"] <= 2]
    return trades, A


def follow(df, trades, cost):
    H, L, C = df.high.values, df.low.values, df.close.values
    n = len(df); out = []
    for t in trades:
        d, e, r = t["d"], t["ent"], t["risk"]
        c = cost / r
        fin = t["t2"] if t["t2"] is not None else t["t1"]
        r1 = d * (t["t1"] - e) / r if t["t1"] is not None else np.nan
        r2 = d * (fin - e) / r if fin is not None else np.nan
        mfe = 0.0; tp1 = tp2 = stop = sweep = False; bTp1 = bStop = bTp2 = None; mfeAtStop = None
        back_to_entry_after_tp1 = False; mae_after_tp1 = 0.0
        end = min(n - 1, t["i"] + P["maxHold"])
        for k in range(t["i"] + 1, end + 1):
            fav = d * ((L[k] if d == -1 else H[k]) - e) / r
            adv = d * ((H[k] if d == -1 else L[k]) - e) / r
            if d * (t["eq"] - (H[k] if d == -1 else L[k])) < 0:
                sweep = True
            if adv <= -1:
                stop = True; bStop = k - t["i"]; mfeAtStop = mfe
                break
            mfe = max(mfe, fav)
            if not tp1 and not np.isnan(r1) and fav >= r1:
                tp1 = True; bTp1 = k - t["i"]
            elif tp1 and adv <= 0:
                back_to_entry_after_tp1 = True
            if not np.isnan(r2) and fav >= r2:
                tp2 = True; bTp2 = k - t["i"]
                break
        last = d * (C[end] - e) / r
        # A: all at TP1   B: all at final target   C: half at TP1, stop to entry, rest to final target
        A_ = (r1 if tp1 else (-1 if stop else last)) - c
        B_ = (r2 if tp2 else (-1 if stop else last)) - c
        if tp1:
            rest = r2 if tp2 else (0.0 if (back_to_entry_after_tp1 or stop) else last)
            C_ = 0.5 * r1 + 0.5 * rest - c
        else:
            C_ = (-1 if stop else last) - c
        out.append(dict(t, stopPx=t["stop"], r1=r1, r2=r2, mfe=mfe, tp1=tp1, tp2=tp2, stop=stop, sweep=sweep, bTp1=bTp1, bStop=bStop,
                        bTp2=bTp2, giveback=back_to_entry_after_tp1, A=A_, B=B_, C=C_, costR=c))
    return pd.DataFrame(out)


def summary(name, df, R):
    if R.empty:
        print(name, "no trades"); return
    print(f"\n=== {name}: {len(R)} trades, {df.time.iloc[0]:%Y-%m-%d} -> {df.time.iloc[-1]:%Y-%m-%d} "
          f"(sells {int((R.d == -1).sum())}, buys {int((R.d == 1).sum())}) ===")
    print(f"  median target size: TP1 {R.r1.median():.2f}R, final {R.r2.median():.2f}R | median cost {R.costR.median():.2f}R | median risk {R.riskATR.median():.2f} ATR")
    print(f"  TP1 before stop {R.tp1.mean():.0%} | final target before stop {R.tp2.mean():.0%} | stopped {R.stop.mean():.0%}")
    print(f"  after TP1, back to entry before the final target: {R[R.tp1].giveback.mean():.0%} of TP1 hits")
    print(f"  equal level swept after entry: {R.sweep.mean():.0%} (of stopped trades: {R[R.stop].sweep.mean():.0%})")
    print(f"  MFE (best run before stop/target/{P['maxHold']} bars): median {R.mfe.median():.2f}R, 25% {R.mfe.quantile(.25):.2f}R, 75% {R.mfe.quantile(.75):.2f}R")
    for k, lab in (("A", "all at TP1"), ("B", "all at prev low/high"), ("C", "half TP1 + BE + rest")):
        x = R[k]; pf = x[x > 0].sum() / max(-x[x < 0].sum(), 1e-9)
        print(f"  {lab:22s}: avg {x.mean():+.3f}R  total {x.sum():+.1f}R  win {(x > 0).mean():.0%}  PF {pf:.2f}")
    for lab, m in (("FVG yes", R.fvg), ("FVG no", ~R.fvg), ("sells", R.d == -1), ("buys", R.d == 1),
                   ("risk<0.6ATR", R.riskATR < 0.6), ("risk>=0.6ATR", R.riskATR >= 0.6),
                   ("retest<=10 bars", R.retBars <= 10), ("retest>10 bars", R.retBars > 10)):
        s = R[m]
        if len(s):
            print(f"    {lab:16s} n={len(s):4d}  C avg {s.C.mean():+.3f}R  B avg {s.B.mean():+.3f}R  TP1 {s.tp1.mean():.0%}  stop {s.stop.mean():.0%}")
    hr = R.assign(h=df.time.iloc[R.i].dt.hour.values).groupby("h").C.agg(["count", "mean"])
    print("  by server hour (C avg R):", " ".join(f"{h}:{int(c)}/{m:+.2f}" for h, (c, m) in hr.iterrows()))


def stats(R):
    if R.empty: return "no trades"
    x = R.C; pf = x[x > 0].sum() / max(-x[x < 0].sum(), 1e-9)
    b = R.B; pfb = b[b > 0].sum() / max(-b[b < 0].sum(), 1e-9)
    return (f"n {len(R):4d} | TP1 {R.tp1.mean():.0%} final {R.tp2.mean():.0%} stop {R.stop.mean():.0%} | risk {R.riskATR.median():.2f}ATR "
            f"| half+BE avg {x.mean():+.3f}R PF {pf:.2f} tot {x.sum():+.0f}R | all-prev-low avg {b.mean():+.3f}R PF {pfb:.2f}")


if not mt5.initialize():
    print("init failed", mt5.last_error()); sys.exit(1)
CONFIGS = [("A equal highs/lows -> advance block, stop above top (indicator v8/v9)", "advance", "top", "equal"),
           ("B SWEEP of a prior high/low -> CHoCH -> advance block, stop above sweep (Adam's model)", "advance", "top", "sweep"),
           ("C SWEEP -> CHoCH -> top block entry, stop above sweep", "top", "zone", "sweep")]
data = {}
for sym, nm, tf in SETS:
    mt5.symbol_select(sym, True)
    df = pd.DataFrame(mt5.copy_rates_from_pos(sym, tf, 0, 99000)); df["time"] = pd.to_datetime(df.time, unit="s"); data[(sym, nm)] = df
mt5.shutdown()
allR = []
for lab, ez, sa, tg in CONFIGS:
    P["entryZone"], P["stopAt"], P["trigger"] = ez, sa, tg
    print(f"\n### {lab}")
    for sym, nm, tf in SETS:
        df = data[(sym, nm)]; tr, _ = run(df); R = follow(df, tr, COST[sym])
        print(f"  {sym:6s} {nm:3s}: {stats(R)}")
        if not R.empty:
            R["set"] = f"{sym} {nm}"; R["cfg"] = lab; R["time"] = df.time.iloc[R.i].values; allR.append(R)
pd.concat(allR).to_csv("C:/Users/aland/stg/eqob_research_trades.csv", index=False)
print("\nsaved C:/Users/aland/stg/eqob_research_trades.csv")
