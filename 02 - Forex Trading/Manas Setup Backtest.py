"""Reference backtest of the TWI Manas Setup rules (same logic as TWI Manas Setup.pine). READ-ONLY (bars only).
Sell = the sketch, buy = its mirror, both written once in "D-space" (buy prices negated). Confirmed pivots (L=3, R=3).
Chain: EXTREME (Sweep / Double / Plain) -> BOS (close through the leg-start swing) -> $$ (internal liquidity above the bounce swing)
-> limit at the zone's near edge -> stop beyond the zone + 0.25 ATR -> target = lowest low since the extreme (Structure) or 2R.
R is net of a per-trade cost (price units); a loss is -1R, fill-bar: only the stop counts.
"""
import sys
import numpy as np, pandas as pd
import MetaTrader5 as mt5

COST = {"XAUUSD": 0.5, "EURUSD": 0.00008, "GBPUSD": 0.00010, "USDJPY": 0.008}
SETS = [("XAUUSD", "H1", mt5.TIMEFRAME_H1, 40000), ("XAUUSD", "H4", mt5.TIMEFRAME_H4, 12000), ("USDJPY", "H1", mt5.TIMEFRAME_H1, 40000),
        ("EURUSD", "H1", mt5.TIMEFRAME_H1, 40000), ("GBPUSD", "H1", mt5.TIMEFRAME_H1, 40000)]
if not mt5.initialize():
    print("init failed", mt5.last_error()); sys.exit(1)

L_, R_ = 3, 3
BASE = dict(eqTol=0.3, zoneATR=1.5, slBuf=0.25, minRR=1.0, maxBars=150, maxHold=300, needLiq=True, tp="structure", entryMid=False,
            sweep=True, double=True, plain=True)

def pivots(H, Lo):
    s = pd.Series(H); l = pd.Series(Lo)
    ph = (s > s.shift(1).rolling(L_).max()) & (s > s[::-1].shift(1).rolling(R_).max()[::-1])
    pl = (l < l.shift(1).rolling(L_).min()) & (l < l[::-1].shift(1).rolling(R_).min()[::-1])
    return ph.values, pl.values

def sim(df, atr, d, P, cost):
    H = (df.high.values if d == 1 else -df.low.values); Lo = (df.low.values if d == 1 else -df.high.values); C = d * df.close.values
    n = len(df); phF, plF = pivots(H, Lo)
    st = 0; kind = 0; lastSH = lastSL = None; lastSHi = lastSLi = -1
    ext = extI = zTop = zBot = lvl = lvlI = bosI = liq = lowest = entry = sl = tp = risk = rr = None; fillI = -1
    trades = []; fun = dict(armed=0, bos=0, liq=0, filled=0, skiprr=0, cancel=0)
    def reset():
        nonlocal st, kind, ext, extI, zTop, zBot, lvl, lvlI, bosI, liq, lowest, entry, sl, tp, risk, rr, fillI
        st = 0; kind = 0; ext = extI = zTop = zBot = lvl = lvlI = bosI = liq = lowest = entry = sl = tp = risk = rr = None; fillI = -1
    for i in range(30, n):
        j = i - R_
        ph = H[j] if (j >= L_ and phF[j]) else None
        pl = Lo[j] if (j >= L_ and plF[j]) else None
        a = atr[i]
        if pl is not None:
            lastSL = pl; lastSLi = j
        if ph is not None:
            prevH = lastSH; lastSH = ph; lastSHi = j
            arm = st == 0 or (st == 1 and ph > ext)
            if arm and lastSL is not None:
                zb = max(Lo[j], ph - P["zoneATR"] * a)
                isDbl = prevH is not None and abs(ph - prevH) <= P["eqTol"] * a
                isSwp = prevH is not None and ph > prevH and C[i] < prevH
                k = 2 if isDbl else 1 if isSwp else 3
                ok = (k == 1 and P["sweep"]) or (k == 2 and P["double"]) or (k == 3 and P["plain"])
                if ok and lastSL < zb and lastSLi < j:
                    if st == 1: reset()
                    st = 1; kind = k; ext = ph; extI = j; zTop = ph; zBot = zb; lvl = lastSL; lvlI = lastSLi
                    lowest = Lo[j:i + 1].min(); fun["armed"] += 1
                    bk = -1
                    for kk in range(R_ - 1, -1, -1):
                        if C[i - kk] < lvl: bk = kk; break
                    if bk >= 0:
                        st = 2; bosI = i - bk; fun["bos"] += 1
        if st == 1:
            lowest = min(lowest, Lo[i])
            if C[i] < lvl:
                st = 2; bosI = i; fun["bos"] += 1
            elif C[i] > zTop:
                fun["cancel"] += 1; reset()
            elif i - extI > P["maxBars"]:
                fun["cancel"] += 1; reset()
        if st == 2:
            lowest = min(lowest, Lo[i])
            if ph is not None and (i - R_) > bosI and ph < zBot:
                liq = ph if liq is None else max(liq, ph)
            taken = (not P["needLiq"]) or (liq is not None and H[i] > liq)
            if taken:
                st = 3; fun["liq"] += 1
            elif C[i] > zTop:
                fun["cancel"] += 1; reset()
            elif P["needLiq"] and liq is None and H[i] >= zBot:
                fun["cancel"] += 1; reset()
            elif i - extI > P["maxBars"]:
                fun["cancel"] += 1; reset()
        if st == 3:
            lowest = min(lowest, Lo[i])
            entryD = (zTop + zBot) / 2 if P["entryMid"] else zBot
            if H[i] >= entryD:
                slD = zTop + P["slBuf"] * a; riskD = slD - entryD
                tpD = lowest if P["tp"] == "structure" else entryD - float(P["tp"]) * riskD
                rrD = (entryD - tpD) / riskD if riskD > 0 else None
                if rrD is None or rrD < P["minRR"]:
                    fun["skiprr"] += 1; reset()
                else:
                    st = 4; entry = entryD; sl = slD; tp = tpD; risk = riskD; rr = rrD; fillI = i; fun["filled"] += 1
                    if H[i] >= slD:
                        trades.append((i, -1.0 - cost / risk, kind, d, risk)); reset()
            elif i - extI > P["maxBars"]:
                fun["cancel"] += 1; reset()
        if st == 4 and fillI < i:
            if H[i] >= sl:
                trades.append((i, -1.0 - cost / risk, kind, d, risk)); reset()
            elif Lo[i] <= tp:
                trades.append((i, rr - cost / risk, kind, d, risk)); reset()
            elif i - fillI > P["maxHold"]:
                trades.append((i, (entry - C[i]) / risk - cost / risk, kind, d, risk)); reset()
    return trades, fun

def stat(rs):
    rs = np.array(rs)
    if len(rs) == 0: return "  0 trades"
    w = rs[rs > 0].sum(); l = -rs[rs < 0].sum()
    return f"{len(rs):4d} tr win {100*(rs>0).mean():4.1f}% {rs.sum():+7.1f}R avg {rs.mean():+.3f} PF {(w/l if l else float('inf')):4.2f}"

VARS = [("V0 defaults (needs $$, structure target)", {}), ("V1 no $$ requirement", dict(needLiq=False)),
        ("V2 target 2R", dict(tp="2")), ("V3 entry at zone middle", dict(entryMid=True))]
for sym, tfn, tf, cnt in SETS:
    mt5.symbol_select(sym, True)
    df = pd.DataFrame(mt5.copy_rates_from_pos(sym, tf, 0, cnt)); df["time"] = pd.to_datetime(df["time"], unit="s"); df = df.set_index("time")
    c, h, l = df.close, df.high, df.low
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1 / 14, adjust=False).mean().values
    mid = df.index[len(df) // 2]
    print(f"\n#### {sym} {tfn} {df.index[0].date()}..{df.index[-1].date()} (halves split {mid.date()})")
    for name, ov in VARS:
        P = dict(BASE); P.update(ov); allt = []; fun = None
        funs = dict(armed=0, bos=0, liq=0, filled=0, skiprr=0, cancel=0)
        for d in (1, -1):
            t, f = sim(df, atr, d, P, COST[sym]); allt += t
            for k in funs: funs[k] += f[k]
        rs = [t[1] for t in allt]
        sell = [t[1] for t in allt if t[3] == 1]; buy = [t[1] for t in allt if t[3] == -1]
        kinds = {k: [t[1] for t in allt if t[2] == k] for k in (1, 2, 3)}
        h1 = [t[1] for t in allt if df.index[t[0]] < mid]; h2 = [t[1] for t in allt if df.index[t[0]] >= mid]
        print(f"{name}\n   ALL   {stat(rs)} | halves {sum(h1):+.1f}R / {sum(h2):+.1f}R\n   sell  {stat(sell)}\n   buy   {stat(buy)}\n"
              f"   sweep {stat(kinds[1])}\n   double{stat(kinds[2])}\n   plain {stat(kinds[3])}\n   funnel {funs}")
mt5.shutdown()
