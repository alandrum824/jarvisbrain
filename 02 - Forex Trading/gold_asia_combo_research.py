"""Asia breakout (proven) + RETEST SNIPER add-on, combined per year, with a coin control. READ-ONLY.

Post-hoc combination (2026-10-13): the base trade is TWI Gold Asia Breakout (gold_breakout_research.asia), the add-on is
the RETEST ALL cell from gold_sniper_research.py (limit at the broken edge after an M5 close beyond it, SL = range
midpoint, TP = measured move). Both were pre-registered separately; COMBINING them is chosen after seeing results, so
this needs the MT5 tester (second engine) before it counts. Equal risk per leg (1R each).
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_breakout_research as g
import gold_sniper_research as sn

if __name__ == "__main__":
    base_m1 = g.load("XAUUSD")
    base = g.asia(base_m1)
    m1 = sn.prep(); days = sn.build_days(m1)
    add = sn.run(m1, days, "RETEST", False)
    comb = pd.concat([base[["year", "d", "R"]], add[["year", "d", "R"]]], ignore_index=True)
    coins = []
    for seed in range(50):
        r1 = np.random.default_rng(1000 + seed); r2 = np.random.default_rng(2000 + seed)
        cb = g.asia(base_m1, r1); ca = sn.run(m1, days, "RETEST", False, r2)
        coins.append(cb.R.sum() + ca.R.sum())
    print("BASE  :", round(base.R.sum(), 1), "R |", {y: round(v, 1) for y, v in base.groupby("year").R.sum().items()})
    print("ADD-ON:", round(add.R.sum(), 1), "R |", {y: round(v, 1) for y, v in add.groupby("year").R.sum().items()})
    g.report("COMBINED", comb, coins)
    yb = base.groupby("year").R.sum(); ya = add.groupby("year").R.sum()
    print("leg correlation of yearly R:", round(np.corrcoef(yb.values, ya.reindex(yb.index).fillna(0).values)[0, 1], 2))
