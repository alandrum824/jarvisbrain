"""Ribbon + RSI / Bollinger filter test. READ-ONLY (bars only). Long-only (shorts lost in the base test).
All variants were fixed BEFORE running; every one is reported, not just the best.
Base: BUY when the 8/13/21/34/55/89 ribbon first stacks bullish and close > EMA8; entry next open;
stop 2 ATR(14); exit when EMA8 < EMA21 at the close; cost = COST price units per trade.
"""
import sys
import numpy as np, pandas as pd
import MetaTrader5 as mt5

COST = {"XAUUSD": 0.5, "EURUSD": 0.00008, "GBPUSD": 0.00010}
SETS = [("XAUUSD", "H4", mt5.TIMEFRAME_H4, 12000), ("XAUUSD", "H1", mt5.TIMEFRAME_H1, 40000),
        ("EURUSD", "H4", mt5.TIMEFRAME_H4, 12000), ("GBPUSD", "H4", mt5.TIMEFRAME_H4, 12000)]
PER = [8, 13, 21, 34, 55, 89]

if not mt5.initialize():
    print("init failed", mt5.last_error()); sys.exit(1)

def prep(df):
    c, h, l = df.close, df.high, df.low
    X = {}
    E = {n: c.ewm(span=n, adjust=False).mean() for n in PER}
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    X["atr"] = tr.ewm(alpha=1 / 14, adjust=False).mean()
    d = c.diff(); up = d.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean(); dn = (-d.clip(upper=0)).ewm(alpha=1 / 14, adjust=False).mean()
    X["rsi"] = 100 - 100 / (1 + up / dn)
    basis = c.rolling(20).mean(); sd = c.rolling(20).std(ddof=0)
    X["basis"] = basis; ub = basis + 2 * sd; lb = basis - 2 * sd
    X["pctb"] = (c - lb) / (ub - lb); bw = (ub - lb) / basis; X["bw"] = bw
    X["bw_exp"] = bw > bw.shift(20)
    X["bw_sq"] = bw.shift(1) < bw.rolling(100).median().shift(1)   # compressed before the signal bar
    X["ub"] = ub
    stack = (E[8] > E[13]) & (E[13] > E[21]) & (E[21] > E[34]) & (E[34] > E[55]) & (E[55] > E[89])
    bull = stack & (c > E[8])
    X["new"] = bull & ~bull.shift(1, fill_value=False)
    X["e8"], X["e21"] = E[8], E[21]
    return X

# name -> (entry filter(X, i) as boolean Series, extra exit as Series or None, replace_loosen)
VARIANTS = [
    ("0  base (no filter)", lambda X: X["rsi"] > -1, None, False),
    ("1  RSI < 70 at signal", lambda X: X["rsi"] < 70, None, False),
    ("2  RSI < 65 at signal", lambda X: X["rsi"] < 65, None, False),
    ("3  RSI 50-70 at signal", lambda X: (X["rsi"] > 50) & (X["rsi"] < 70), None, False),
    ("4  RSI > 55 (momentum)", lambda X: X["rsi"] > 55, None, False),
    ("5  extra exit: RSI > 80", lambda X: X["rsi"] > -1, lambda X: X["rsi"] > 80, False),
    ("6  BB: close below upper band", lambda X: X["pctb"] < 1.0, None, False),
    ("7  BB: %B < 0.8 (not stretched)", lambda X: X["pctb"] < 0.8, None, False),
    ("8  BB: bands expanding vs 20 bars ago", lambda X: X["bw_exp"], None, False),
    ("9  BB: squeeze before signal", lambda X: X["bw_sq"], None, False),
    ("10 exit on close < BB basis (SMA20)", lambda X: X["rsi"] > -1, lambda X: X["basis"].notna(), True),
]

def run(df, X, cost, filt, extra, replace):
    o, h, l, c = df.open.values, df.high.values, df.low.values, df.close.values
    atr = X["atr"].values; new = X["new"].values & filt(X).fillna(False).values
    e8, e21 = X["e8"].values, X["e21"].values
    ex = extra(X).fillna(False).values if extra is not None else None
    basis = X["basis"].values
    n = len(df); pos = False; trades = []; ent = stop = risk = 0.0; ti = 0
    for i in range(100, n - 1):
        if pos:
            if l[i] <= stop:
                trades.append((df.index[ti], -1.0 - cost / risk)); pos = False
            else:
                if replace: loose = c[i] < basis[i]
                else: loose = e8[i] < e21[i]
                if loose or (ex is not None and not replace and ex[i]):
                    trades.append((df.index[ti], (c[i] - ent - cost) / risk)); pos = False
        if not pos and new[i]:
            pos = True; ent = o[i + 1]; risk = 2.0 * atr[i]; stop = ent - risk; ti = i + 1
    return pd.DataFrame(trades, columns=["t", "r"])

def stats(t):
    if t.empty: return None
    w = t.r[t.r > 0].sum(); ls = -t.r[t.r < 0].sum()
    cum = t.r.cumsum(); dd = (cum.cummax() - cum).max()
    return dict(n=len(t), win=100 * (t.r > 0).mean(), tot=t.r.sum(), avg=t.r.mean(), pf=(w / ls if ls else float("inf")), dd=dd)

for sym, tfn, tf, cnt in SETS:
    mt5.symbol_select(sym, True)
    r = mt5.copy_rates_from_pos(sym, tf, 0, cnt)
    df = pd.DataFrame(r); df["time"] = pd.to_datetime(df["time"], unit="s"); df = df.set_index("time")
    X = prep(df); cost = COST[sym]
    mid = df.index[len(df) // 2]
    print(f"\n#### {sym} {tfn}  {df.index[0].date()}..{df.index[-1].date()}  ({len(df)} bars, halves split {mid.date()})")
    print(f"{'variant':38s} {'n':>4s} {'win%':>5s} {'totR':>7s} {'avgR':>6s} {'PF':>5s} {'maxDD':>6s} | 1st half R/PF   2nd half R/PF")
    for name, filt, extra, rep in VARIANTS:
        t = run(df, X, cost, filt, extra, rep)
        s = stats(t)
        if s is None: print(f"{name:38s} no trades"); continue
        a = stats(t[t.t < mid]); b = stats(t[t.t >= mid])
        fh = f"{a['tot']:+6.1f}/{a['pf']:.2f}" if a else "   -   "
        sh = f"{b['tot']:+6.1f}/{b['pf']:.2f}" if b else "   -   "
        print(f"{name:38s} {s['n']:4d} {s['win']:5.1f} {s['tot']:+7.1f} {s['avg']:+6.3f} {s['pf']:5.2f} {s['dd']:6.1f} | {fh:>14s}  {sh:>14s}")
mt5.shutdown()
