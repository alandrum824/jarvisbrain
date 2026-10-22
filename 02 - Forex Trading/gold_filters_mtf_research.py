"""Follow-up to gold_filters_research.py (Adam 2026-10-13: "There is also multi timeframe trend detection").
NOT pre-registered with the first set: added after FVG+H1 passed. Same base trades, same COIN and SKIP controls.
Cells: FVG+H4, FVG+H1+H4 (both timeframes agree), H1+H4 (no FVG)."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_filters_research as f
import gold_sniper_research as sn
from gold_breakout_research import summ, report

if __name__ == "__main__":
    m1 = sn.prep(); days = sn.build_days(m1)
    tr = f.build(m1, days)
    tr = tr.assign(R=f.resolve(m1, tr).R.values)
    cells = {"FVG+H4": (tr.FVG & tr.H4TREND).values, "FVG+H1+H4": (tr.FVG & tr.H1TREND & tr.H4TREND).values,
             "H1+H4": (tr.H1TREND & tr.H4TREND).values}
    for name, mask in cells.items():
        sub = tr[mask]; real = sub[["year", "d", "R"]]
        rng = np.random.default_rng(20261013)
        coin = [summ(f.resolve(m1, sub, rng))["tot"] for _ in range(50)]
        print(f"##### {name}: keeps {mask.sum()} of {len(tr)}, avg {real.R.mean():+.3f}R", flush=True)
        report(name, real, coin)
        rs = np.random.default_rng(7)
        skip = [tr.R.values[rs.choice(len(tr), mask.sum(), replace=False)].sum() for _ in range(50)]
        bs = (np.array(skip) < real.R.sum()).mean()
        print(f"    SKIP control: random keep-{mask.sum()} median {np.median(skip):+.1f}R, filter beats {bs:.0%}", flush=True)
        print(f"    long {sub[sub.d==1].R.sum():+.1f}R / short {sub[sub.d==-1].R.sum():+.1f}R", flush=True)
