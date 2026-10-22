"""Manas Setup: are SWEEP setups good, and does the trend direction help? READ-ONLY. Uses the same sim as manas_bt.py, with an
entry-time trend filter: a sell may only fill while the ribbon is stacked bearish (or close < EMA89), a buy only while stacked bullish
(or close > EMA89). Variants fixed in advance; all reported."""
src = open(r"C:\Users\aland\AppData\Local\Temp\claude\C--Users-aland\21f39a62-778d-4fb9-8854-a0aa04671f09\scratchpad\manas_bt.py").read()
head = src[:src.index("VARS = [")]
assert 'if rrD is None or rrD < P["minRR"]:' in head
head = head.replace('if rrD is None or rrD < P["minRR"]:', 'if rrD is None or rrD < P["minRR"] or (P.get("TR") is not None and not P["TR"][d][i - 1]):')
exec(head)
import MetaTrader5 as mt5, pandas as pd, numpy as np

VARS = [("V0 all origins", dict(), None), ("V0 all + EMA89 (prev bar)", dict(), "ema89"), ("V0 sweep + EMA89 (prev bar)", dict(double=False, plain=False), "ema89"),
        ("V1 all origins (no $$)", dict(needLiq=False), None), ("V1 all + EMA89 (prev bar)", dict(needLiq=False), "ema89"),
        ("V1 sweep only", dict(needLiq=False, double=False, plain=False), None), ("V1 sweep + EMA89 (prev bar)", dict(needLiq=False, double=False, plain=False), "ema89"),
        ("V1 sweep + stack (prev bar)", dict(needLiq=False, double=False, plain=False), "stack")]
for sym, tfn, tf, cnt in SETS:
    mt5.symbol_select(sym, True)
    df = pd.DataFrame(mt5.copy_rates_from_pos(sym, tf, 0, cnt)); df["time"] = pd.to_datetime(df["time"], unit="s"); df = df.set_index("time")
    c, h, l = df.close, df.high, df.low
    tr = pd.concat([h - l, (h - c.shift()).abs(), (l - c.shift()).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1 / 14, adjust=False).mean().values
    E = {n: c.ewm(span=n, adjust=False).mean() for n in (8, 13, 21, 34, 55, 89)}
    bull = ((E[8] > E[13]) & (E[13] > E[21]) & (E[21] > E[34]) & (E[34] > E[55]) & (E[55] > E[89])).values
    bear = ((E[8] < E[13]) & (E[13] < E[21]) & (E[21] < E[34]) & (E[34] < E[55]) & (E[55] < E[89])).values
    up89 = (c > E[89]).values
    TRS = {"stack": {1: bear, -1: bull}, "ema89": {1: ~up89, -1: up89}}
    mid = df.index[len(df) // 2]
    print(f"\n#### {sym} {tfn} {df.index[0].date()}..{df.index[-1].date()} (halves split {mid.date()})")
    for name, ov, tr_ in VARS:
        P = dict(BASE); P.update(ov); P["TR"] = TRS[tr_] if tr_ else None
        allt = []
        for d in (1, -1):
            t, f = sim(df, atr, d, P, COST[sym]); allt += t
        rs = np.array([t[1] for t in allt])
        h1 = sum(t[1] for t in allt if df.index[t[0]] < mid); h2 = sum(t[1] for t in allt if df.index[t[0]] >= mid)
        sell = sum(t[1] for t in allt if t[3] == 1); buy = sum(t[1] for t in allt if t[3] == -1)
        if len(rs) == 0: print(f"  {name:28s} no trades"); continue
        w = rs[rs > 0].sum(); ls = -rs[rs < 0].sum()
        print(f"  {name:28s} {len(rs):4d} tr win {100*(rs>0).mean():4.1f}% {rs.sum():+7.1f}R PF {(w/ls if ls else 9.99):4.2f} | halves {h1:+6.1f}/{h2:+6.1f} | sell {sell:+6.1f} buy {buy:+6.1f}")
mt5.shutdown()
