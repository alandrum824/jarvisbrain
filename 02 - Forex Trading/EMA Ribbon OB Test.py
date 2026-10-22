"""Ribbon + order-block (OB) test. READ-ONLY (bars only). Long-only.
Variants fixed BEFORE running; all reported.
Bullish OB (causal, closed bars only): an impulse bar i = bullish, range >= 1.5 x ATR(prev bar), body >= 60% of range,
close above the previous 10-bar high. The OB candle = the last bearish candle (close<open) within the 5 bars before i.
Zone = that candle's low..high. A zone dies when a bar CLOSES below its low, or after 150 bars.
Base: BUY when the 8/13/21/34/55/89 ribbon first stacks bullish (close > EMA8); entry next open; stop 2 ATR; exit EMA8<EMA21.
  A  base BUY only if an active OB top lies within 3 ATR below the signal close ("support nearby")
  B  base BUY only if the signal bar's low is within 0.5 ATR above (or inside) the nearest active OB ("price at the zone")
  C  OB-PULLBACK entry inside a bullish stack: a bar dips into an active OB (low <= zone top, close > zone low) -> enter next open,
     stop = zone low - 0.25 ATR (skip if the stop is < 0.5 ATR away), each zone used once, same exit
  D  base BUY, but the stop sits under the nearest active OB (zone low - 0.25 ATR) when that is 1-4 ATR away, else 2 ATR
"""
import sys
import numpy as np, pandas as pd
import MetaTrader5 as mt5

COST = {"XAUUSD": 0.5, "EURUSD": 0.00008, "GBPUSD": 0.00010, "USDJPY": 0.008}
SETS = [("XAUUSD", "H4", mt5.TIMEFRAME_H4, 12000), ("XAUUSD", "H1", mt5.TIMEFRAME_H1, 40000), ("USDJPY", "H1", mt5.TIMEFRAME_H1, 40000),
        ("EURUSD", "H4", mt5.TIMEFRAME_H4, 12000), ("GBPUSD", "H4", mt5.TIMEFRAME_H4, 12000)]
PER = [8, 13, 21, 34, 55, 89]
if not mt5.initialize():
    print("init failed", mt5.last_error()); sys.exit(1)

def prep(df):
    c, h, l, o = df.close, df.high, df.low, df.open
    E = {n: c.ewm(span=n, adjust=False).mean() for n in PER}
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1 / 14, adjust=False).mean()
    stack = (E[8] > E[13]) & (E[13] > E[21]) & (E[21] > E[34]) & (E[34] > E[55]) & (E[55] > E[89])
    bull = stack & (c > E[8])
    rng = h - l; body = (c - o).abs(); hh10 = h.rolling(10).max().shift(1)
    imp = (c > o) & (rng >= 1.5 * atr.shift(1)) & (body >= 0.6 * rng) & (c > hh10)
    return dict(atr=atr.values, stack=stack.values, new=(bull & ~bull.shift(1, fill_value=False)).values, imp=imp.values,
                e8=E[8].values, e21=E[21].values)

def run(df, X, cost, mode):
    o, h, l, c = df.open.values, df.high.values, df.low.values, df.close.values
    atr, stack, new, imp, e8, e21 = X["atr"], X["stack"], X["new"], X["imp"], X["e8"], X["e21"]
    n = len(df); zones = []; pos = False; trades = []; ent = stop = risk = 0.0; ti = 0
    for i in range(100, n - 1):
        zones = [z for z in zones if c[i] >= z[1] and i - z[2] <= 150]
        if imp[i]:
            for k in range(i - 1, max(i - 6, 0), -1):
                if c[k] < o[k]:
                    zones.append([h[k], l[k], i, False]); break
        if pos:
            if l[i] <= stop:
                trades.append((df.index[ti], -1.0 - cost / risk, risk)); pos = False
            elif e8[i] < e21[i]:
                trades.append((df.index[ti], (c[i] - ent - cost) / risk, risk)); pos = False
        if not pos:
            stop_lvl = None; sig = False
            below = [z for z in zones if z[0] <= c[i]]
            nearest = max(below, key=lambda z: z[0]) if below else None
            if mode == "base" and new[i]:
                sig = True
            elif mode == "A" and new[i]:
                sig = nearest is not None and (c[i] - nearest[0]) <= 3 * atr[i]
            elif mode == "B" and new[i]:
                sig = nearest is not None and (l[i] - nearest[0]) <= 0.5 * atr[i]
            elif mode == "D" and new[i]:
                sig = True
                if nearest is not None:
                    lvl = nearest[1] - 0.25 * atr[i]; d = (c[i] - lvl) / atr[i]
                    if 1.0 <= d <= 4.0: stop_lvl = lvl
            elif mode == "C" and stack[i]:
                cands = [z for z in zones if not z[3] and l[i] <= z[0] and c[i] > z[1]]
                if cands:
                    z = max(cands, key=lambda z: z[0]); lvl = z[1] - 0.25 * atr[i]
                    if (c[i] - lvl) >= 0.5 * atr[i]:
                        sig = True; stop_lvl = lvl; z[3] = True
            if sig:
                e = o[i + 1]; lvl = stop_lvl if stop_lvl is not None else e - 2.0 * atr[i]
                if lvl < e:
                    pos = True; ent = e; stop = lvl; risk = e - lvl; ti = i + 1
    return pd.DataFrame(trades, columns=["t", "r", "risk"])

def stats(t):
    if t.empty: return None
    w = t.r[t.r > 0].sum(); ls = -t.r[t.r < 0].sum(); cum = t.r.cumsum()
    return dict(n=len(t), win=100 * (t.r > 0).mean(), tot=t.r.sum(), avg=t.r.mean(), pf=(w / ls if ls else float("inf")), dd=(cum.cummax() - cum).max(), risk=t.risk.median())

NAMES = {"base": "base (2 ATR stop)", "A": "A  OB within 3 ATR below", "B": "B  signal bar at the OB", "C": "C  OB-pullback entry (OB stop)", "D": "D  base BUY, stop under OB"}
for sym, tfn, tf, cnt in SETS:
    mt5.symbol_select(sym, True)
    df = pd.DataFrame(mt5.copy_rates_from_pos(sym, tf, 0, cnt)); df["time"] = pd.to_datetime(df["time"], unit="s"); df = df.set_index("time")
    X = prep(df); cost = COST[sym]; mid = df.index[len(df) // 2]
    print(f"\n#### {sym} {tfn} {df.index[0].date()}..{df.index[-1].date()} (halves split {mid.date()}); OB zones found: {int(X['imp'].sum())} impulse bars")
    print(f"{'variant':34s} {'n':>4s} {'win%':>5s} {'totR':>7s} {'avgR':>6s} {'PF':>5s} {'maxDD':>6s} {'medStop':>9s} | 1st half R/PF   2nd half R/PF")
    for m in ("base", "A", "B", "C", "D"):
        t = run(df, X, cost, m); s = stats(t)
        if s is None: print(f"{NAMES[m]:34s} no trades"); continue
        a = stats(t[t.t < mid]); b = stats(t[t.t >= mid])
        fh = f"{a['tot']:+6.1f}/{a['pf']:.2f}" if a else "   -   "; sh = f"{b['tot']:+6.1f}/{b['pf']:.2f}" if b else "   -   "
        rk = f"{s['risk']:.2f}" if sym in ("XAUUSD",) else f"{s['risk']*(100 if sym=='USDJPY' else 10000):.0f}pip"
        print(f"{NAMES[m]:34s} {s['n']:4d} {s['win']:5.1f} {s['tot']:+7.1f} {s['avg']:+6.3f} {s['pf']:5.2f} {s['dd']:6.1f} {rk:>9s} | {fh:>14s}  {sh:>14s}")
mt5.shutdown()
