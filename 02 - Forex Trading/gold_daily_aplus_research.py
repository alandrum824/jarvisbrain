"""Daily base breakout + A+ add-on (FVG + H1 trend) — Adam 2026-10-13: "We want at least one trade per day".
Post-hoc portfolio of two tested legs: base = TWI Gold Asia Breakout OCO (gold_breakout_research.asia),
A+ = FVG+H1 cell (gold_filters_research). Equal 1R per leg. Coin control on both legs together."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_breakout_research as g
import gold_filters_research as f
import gold_sniper_research as sn

if __name__ == "__main__":
    bm1 = g.load("XAUUSD"); base = g.asia(bm1)
    m1 = sn.prep(); days = sn.build_days(m1)
    tr = f.build(m1, days); aplus = tr[(tr.FVG & tr.H1TREND)]
    ap = f.resolve(m1, aplus)
    comb = pd.concat([base[["year", "d", "R"]], ap], ignore_index=True)
    coins = [g.asia(bm1, np.random.default_rng(100 + i)).R.sum() + f.resolve(m1, aplus, np.random.default_rng(200 + i)).R.sum() for i in range(50)]
    ndays = len(days)
    print(f"trading days with a valid range: {ndays}; base trades {len(base)} ({len(base)/ndays:.2f}/day), A+ adds {len(ap)}")
    g.report("BASE+A+", comb, coins)
