"""ERC (extended range candle) as a filter on the gold Asia breakout (Adam's image 2026-10-13). PRE-REGISTERED:
ERC = the breakout M5 bar closes in the breakout direction with body >= 80% of its range. Cells: ERC, ERC+H1 trend,
vs REF (all breakouts) and FVG+H1 (the v1.04 A+ filter). Same trades/exits as gold_filters_research (1R, flat 16:00 GMT).
Controls: coin (50 seeds) and random-skip (50 seeds)."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_filters_research as gf
import gold_sniper_research as sn
from gold_breakout_research import summ, report

m1 = sn.prep(); days = sn.build_days(m1)
tr = gf.build(m1, days)
g = m1.set_index("utc").resample("5min", label="left", closed="left")
m5 = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()
T5 = m5.utc.values; U = m1.utc.values
erc = []
for r in tr.itertuples():
    b = int(np.searchsorted(T5, U[r.k])) - 1
    rng_ = m5.high.values[b] - m5.low.values[b]; body = m5.close.values[b] - m5.open.values[b]
    erc.append(rng_ > 0 and r.d * body >= 0.8 * rng_)
tr["ERC"] = erc
tr = tr.assign(R=gf.resolve(m1, tr).R.values)
for name, mask in {"REF": np.ones(len(tr), bool), "ERC": tr.ERC.values, "ERC+H1": (tr.ERC & tr.H1TREND).values,
                   "FVG+H1": (tr.FVG & tr.H1TREND).values, "ERC+FVG+H1": (tr.ERC & tr.FVG & tr.H1TREND).values}.items():
    sub = tr[mask]; real = sub[["year", "d", "R"]]
    rng = np.random.default_rng(20261013); coin = [summ(gf.resolve(m1, sub, rng))["tot"] for _ in range(50)]
    print(f"##### {name}: keeps {mask.sum()} of {len(tr)}", flush=True); report(name, real, coin)
    if name != "REF":
        rs = np.random.default_rng(7); skip = [tr.R.values[rs.choice(len(tr), mask.sum(), replace=False)].sum() for _ in range(50)]
        print(f"    SKIP: beats {(np.array(skip) < real.R.sum()).mean():.0%} of random keep-{mask.sum()}", flush=True)
