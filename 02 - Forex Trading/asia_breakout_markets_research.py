"""Asia-range breakout (TWI Gold Asia Breakout rules, UNCHANGED) on every other market we hold. READ-ONLY replay.

Adam 2026-10-12: "Figure out what works and build an ea from that". What works so far = a quiet session sets a range,
the next liquid session breaks it, trade WITH the break on a wide stop (gold Asia breakout; ORB Momentum EURUSD/USDJPY/US30).
This scan asks where else the gold rules pay. Rules exactly as gold_breakout_research.asia(): range 00-05 GMT, skip if
width < 0.10 or > 0.80 x daily ATR(14), OCO stops +/-5% of width, SL other side, TP 1R, cancel 15:00, flat 16:00 GMT.
Already done: XAUUSD PASS; EURUSD, GBPUSD fail (stg/trendscalper/asia_fx.py).
PRE-REGISTERED pass bar: >= 5/7 years, PF > 1, beats >= 95% of 50 coin runs, AND both sides positive (not one-way drift).
10 markets -> ~0.5 false passes expected at 95%, so any pass needs the MT5 tester before it becomes a leg.
Costs: bar spread x point (no markup off gold). Clock: the proven AAAFx clock (orb_momentum_longrun_research.load).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe asia_breakout_markets_research.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_breakout_research as g
from orb_momentum_newlegs_research import PT as PT_NEW

g.PT.update(PT_NEW)
MARKETS = ["USDJPY", "AUDUSD", "USDCAD", "AUDJPY", "NAS100", "US30", "SPX500", "GER30", "UK100", "JPN225"]

if __name__ == "__main__":
    out = []
    for sym in MARKETS:
        g.SYM, g.MK = sym, 0
        m1 = g.load(sym)
        real = g.asia(m1)
        rng = np.random.default_rng(20261012)
        coin = [g.summ(g.asia(m1, rng))["tot"] for _ in range(50)]
        print(f"##### {sym}", flush=True)
        row = g.report("ASIA BOTH", real, coin)
        sides = {}
        for d, n in ((1, "LONG"), (-1, "SHORT")):
            x = real[real.d == d]; s = g.summ(x); sides[n] = s["tot"]
            print(f"    {n}: {s['n']} tr {s['tot']:+.1f}R PF {s['pf']:.2f}", flush=True)
        row.update(sym=sym, long_R=sides["LONG"], short_R=sides["SHORT"],
                   passed=bool(row["passed"] and sides["LONG"] > 0 and sides["SHORT"] > 0))
        print(f"    => {'PASS' if row['passed'] else 'fail'} (incl. both sides positive)", flush=True)
        out.append(row)
    pd.DataFrame(out).to_csv(r"C:\Users\aland\stg\obh\asia_breakout_markets.csv", index=False)
    print("saved")
