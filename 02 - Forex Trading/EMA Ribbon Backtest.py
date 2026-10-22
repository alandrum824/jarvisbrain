"""EMA-ribbon trend buy/sell backtest. READ-ONLY: only pulls bars (copy_rates_from_pos)
and symbol_info from the MT5 terminal. No order functions anywhere.

Ribbon = EMAs 8,13,21,34,55,89. BUY when the ribbon becomes fully stacked bullish
(8>13>21>34>55>89 and close above the 8); SELL mirrored. Exit when EMA8 crosses EMA21
against the trade (the ribbon "loosens"), or the initial stop (STOP_ATR x ATR14) is hit.
Entry = next bar open. Costs = the symbol's current spread, charged once per trade.
Results in R (R = stop distance). If a bar touches the stop it is a loss of -1R (conservative).
"""
import sys, itertools
import numpy as np, pandas as pd
import MetaTrader5 as mt5

PERIODS = [8, 13, 21, 34, 55, 89]
STOP_ATR = 2.0
SYMS = ["XAUUSD", "EURUSD", "GBPUSD", "USDJPY"]
TFS = {"M15": (mt5.TIMEFRAME_M15, 60000), "H1": (mt5.TIMEFRAME_H1, 40000), "H4": (mt5.TIMEFRAME_H4, 12000)}

if not mt5.initialize():
    print("init failed", mt5.last_error()); sys.exit(1)

def ema(s, n): return s.ewm(span=n, adjust=False).mean()

def run(df, spread_px, variant, PERIODS=PERIODS, STOP_ATR=STOP_ATR):
    c, h, l, o = df.close, df.high, df.low, df.open
    E = {n: ema(c, n) for n in PERIODS}
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1 / 14, adjust=False).mean()
    P=PERIODS; bull=(c>E[P[0]])
    for a,b in zip(P,P[1:]): bull = bull & (E[a]>E[b])
    bear=(c<E[P[0]])
    for a,b in zip(P,P[1:]): bear = bear & (E[a]<E[b])
    if variant == "pullback":   # buy the dip: stacked trend + the bar's low tags EMA21 and closes back above EMA8
        bull = bull.shift(1, fill_value=False) & (l <= E[P[2]]) & (c > E[P[0]])
        bear = bear.shift(1, fill_value=False) & (h >= E[P[2]]) & (c < E[P[0]])
    new_bull = bull & ~bull.shift(1, fill_value=False)
    new_bear = bear & ~bear.shift(1, fill_value=False)
    n = len(df); trades = []
    pos = 0; entry = stop = risk = 0.0; ent_i = 0
    for i in range(100, n - 1):
        if pos != 0:
            # stop first (conservative), then ribbon-loosening exit at the close
            hit = (l.iat[i] <= stop) if pos > 0 else (h.iat[i] >= stop)
            if hit:
                trades.append((df.index[ent_i], -1.0 - spread_px / risk, pos)); pos = 0
            else:
                loose = (E[P[0]].iat[i] < E[P[2]].iat[i]) if pos > 0 else (E[P[0]].iat[i] > E[P[2]].iat[i])
                if loose:
                    r = ((c.iat[i] - entry) * pos - spread_px) / risk
                    trades.append((df.index[ent_i], r, pos)); pos = 0
        if pos == 0:
            if new_bull.iat[i]: pos = 1
            elif new_bear.iat[i]: pos = -1
            if pos != 0:
                entry = o.iat[i + 1]; risk = STOP_ATR * atr.iat[i]
                stop = entry - pos * risk; ent_i = i + 1
    return pd.DataFrame(trades, columns=["t", "r", "side"])

def summarize(t):
    if t.empty: return "no trades"
    w = t.r[t.r > 0].sum(); l = -t.r[t.r < 0].sum()
    return f"{len(t):4d} trades  win {100*(t.r>0).mean():4.1f}%  total {t.r.sum():+7.1f}R  avg {t.r.mean():+.3f}R  PF {w/l if l else float('inf'):4.2f}"


def load(sym, tf, cnt):
    r = mt5.copy_rates_from_pos(sym, tf, 0, cnt); df = pd.DataFrame(r); df["time"]=pd.to_datetime(df["time"],unit="s"); return df.set_index("time")
def show(tag, t):
    if t.empty: print(tag, "no trades"); return
    L=t[t.side>0]; S=t[t.side<0]
    print(f"{tag:42s} {summarize(t)} | LONG {len(L)}t {L.r.sum():+.0f}R  SHORT {len(S)}t {S.r.sum():+.0f}R")
for sym in ("XAUUSD","XAGUSD"):
    mt5.symbol_select(sym, True); info=mt5.symbol_info(sym)
    if info is None: print(sym,"n/a"); continue
    df = load(sym, mt5.TIMEFRAME_H4, 12000); sp=info.spread*info.point
    print(f"\n#### {sym} H4 {df.index[0].date()}..{df.index[-1].date()} spread {sp:.3f}")
    for per in ([8,13,21,34,55,89],[5,8,13,21,34,55],[10,20,30,40,50,60],[8,21,55,89,144,200]):
        for st in (1.5,2.0,3.0):
            show(f"ribbon {per} stop {st}ATR", run(df, sp, "flip", per, st))
# also halves of history for the base config
df = load("XAUUSD", mt5.TIMEFRAME_H4, 12000); sp=mt5.symbol_info("XAUUSD").spread*mt5.symbol_info("XAUUSD").point
mid = df.index[len(df)//2]
print("\n#### XAUUSD H4 base config, first half vs second half of history, and ex-2020")
show(f"first half  ..{mid.date()}", run(df[df.index<mid], sp, "flip"))
show(f"second half {mid.date()}..", run(df[df.index>=mid], sp, "flip"))
mt5.shutdown()
