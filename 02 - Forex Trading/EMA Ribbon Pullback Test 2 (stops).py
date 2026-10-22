"""Ribbon PULLBACK-entry test. READ-ONLY (bars only). Long-only. Variants fixed BEFORE running; all reported.
Ribbon = EMAs 8/13/21/34/55/89. "Stack" = 8>13>21>34>55>89. Entry = next bar open after the signal bar closes; stop 2 ATR(14).
Exit X1 = EMA8 < EMA21 at the close (the base exit). Exit X2 = close < EMA34 (the ribbon's support breaks).
A pullback signal fires only on the first bar the condition becomes true (edge-triggered) and only while flat.
  base  first-stack BUY (close > EMA8), X1                       (what the indicator does today)
  P1    stack and low <= EMA21 and close > EMA8,  X1
  P1x2  same entry, exit X2
  P2    stack and low <= EMA13 and close > EMA8,  X1
  P3    stack and low <= EMA34 and close > EMA21, X1
  P3x2  same entry, exit X2
  P4    reclaim: stack, previous close < EMA8 and this close > EMA8, X1
  P5    stack and low <= EMA55 and close > EMA34, X2
  U1    union: first-stack BUY OR P1, X1
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
    c, h, l = df.close, df.high, df.low
    E = {n: c.ewm(span=n, adjust=False).mean() for n in PER}
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    X = {"atr": tr.ewm(alpha=1 / 14, adjust=False).mean().values}
    stack = (E[8] > E[13]) & (E[13] > E[21]) & (E[21] > E[34]) & (E[34] > E[55]) & (E[55] > E[89])
    bull = stack & (c > E[8])
    X["new"] = (bull & ~bull.shift(1, fill_value=False)).values
    def edge(cond):
        cond = cond & stack
        return (cond & ~cond.shift(1, fill_value=False)).values
    X["P1"] = edge((l <= E[21]) & (c > E[8]))
    X["P2"] = edge((l <= E[13]) & (c > E[8]))
    X["P3"] = edge((l <= E[34]) & (c > E[21]))
    X["P4"] = edge((c.shift(1) < E[8].shift(1)) & (c > E[8]))
    X["P5"] = edge((l <= E[55]) & (c > E[34]))
    for k in (8, 21, 34): X[f"e{k}"] = E[k].values
    return X

VARS = [("base  first-stack BUY, 2 ATR stop", ["new"], "X1", "S2"), ("P1  3-bar-low stop", ["P1"], "X1", "S3"),
        ("P2  2 ATR stop", ["P2"], "X1", "S2"), ("P2  3-bar-low stop", ["P2"], "X1", "S3")]

def run(df, X, cost, sigs, ex, stopmode='S2'):
    o, h, l, c = df.open.values, df.high.values, df.low.values, df.close.values
    atr, e8, e21, e34 = X["atr"], X["e8"], X["e21"], X["e34"]
    S = np.zeros(len(df), dtype=bool)
    for s in sigs: S |= X[s]
    n = len(df); pos = False; trades = []; ent = stop = risk = 0.0; ti = 0
    for i in range(100, n - 1):
        if pos:
            if l[i] <= stop:
                trades.append((df.index[ti], -1.0 - cost / risk, risk)); pos = False
            else:
                out = (e8[i] < e21[i]) if ex == "X1" else (c[i] < e34[i])
                if out:
                    trades.append((df.index[ti], (c[i] - ent - cost) / risk, risk)); pos = False
        if not pos and S[i]:
            e = o[i + 1]
            if stopmode == 'S2':
                risk = 2.0 * atr[i]; stop = e - risk
            else:
                stop = min(l[i - 2:i + 1]) - 0.25 * atr[i]; risk = e - stop
                if not (0.5 * atr[i] <= risk <= 3.0 * atr[i]): continue
            ent = e; pos = True; ti = i + 1
    return pd.DataFrame(trades, columns=["t", "r", "risk"])

def stats(t):
    if t.empty: return None
    w = t.r[t.r > 0].sum(); ls = -t.r[t.r < 0].sum(); cum = t.r.cumsum()
    return dict(n=len(t), win=100 * (t.r > 0).mean(), tot=t.r.sum(), avg=t.r.mean(), pf=(w / ls if ls else float("inf")), dd=(cum.cummax() - cum).max(), risk=t.risk.median(), pts=(t.r * t.risk).sum(), worst=(t.r * t.risk).min())

for sym, tfn, tf, cnt in SETS:
    mt5.symbol_select(sym, True)
    df = pd.DataFrame(mt5.copy_rates_from_pos(sym, tf, 0, cnt)); df["time"] = pd.to_datetime(df["time"], unit="s"); df = df.set_index("time")
    X = prep(df); cost = COST[sym]; mid = df.index[len(df) // 2]
    print(f"\n#### {sym} {tfn} {df.index[0].date()}..{df.index[-1].date()} (halves split {mid.date()})")
    print(f"{'variant':36s} {'n':>4s} {'win%':>5s} {'totR':>7s} {'avgR':>6s} {'PF':>5s} {'maxDD':>6s} {'medStop':>8s} {'netPts':>9s} {'worst':>7s} | 1st half R/PF   2nd half R/PF")
    for name, sigs, ex, sm in VARS:
        t = run(df, X, cost, sigs, ex, sm); s = stats(t)
        if s is None: print(f"{name:36s} no trades"); continue
        a = stats(t[t.t < mid]); b = stats(t[t.t >= mid])
        fh = f"{a['tot']:+6.1f}/{a['pf']:.2f}" if a else "   -   "; sh = f"{b['tot']:+6.1f}/{b['pf']:.2f}" if b else "   -   "
        mult = 1 if sym == "XAUUSD" else (100 if sym == "USDJPY" else 10000)
        unit = "$" if sym == "XAUUSD" else "pip"
        pts = f"{s['pts']*mult:+.0f}{unit}"; wst = f"{s['worst']*mult:.0f}{unit}"
        rk = f"{s['risk']:.2f}" if sym == "XAUUSD" else f"{s['risk']*(100 if sym=='USDJPY' else 10000):.0f}pip"
        print(f"{name:36s} {s['n']:4d} {s['win']:5.1f} {s['tot']:+7.1f} {s['avg']:+6.3f} {s['pf']:5.2f} {s['dd']:6.1f} {rk:>8s} {pts:>9s} {wst:>7s} | {fh:>14s}  {sh:>14s}")
mt5.shutdown()
