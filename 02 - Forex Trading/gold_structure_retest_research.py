"""Structure retest on gold (Adam's image 2026-10-13). PRE-REGISTERED:
Trend = last two confirmed (3/3 fractal) swing highs AND lows falling (bear) / rising (bull). Key level = the most recent
confirmed swing low (bear) / high (bull). Break = first bar CLOSING beyond the key level by >= 0.3 x ATR14 while the trend
agrees. Retest = sell limit at the broken level (bear; buy limit for bull) valid 48 bars after the break bar, filled only
after price has moved >= 1 ATR away from the level (a real retracement, per the picture). SL = level + 1.0 ATR (bear);
TP 2R; max hold 48 bars after the fill; one at a time. Realistic fills (buy on ask, sell on bid); coin = same price, random
direction. M15 and H1, gold 2020-26, real spread +6 pt, exits M1."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report
from gold_filters_research import swings
from gold_three_areas_research import run

def setups(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    sh, sl = swings(H, L); out = []; used = set(); nxt = 0
    ih_all, il_all = np.flatnonzero(sh), np.flatnonzero(sl)
    for j in range(30, len(b) - 60):
        if j < nxt or not A[j] > 0: continue
        ih = ih_all[ih_all <= j - 4][-2:]; il = il_all[il_all <= j - 4][-2:]
        if len(ih) < 2 or len(il) < 2: continue
        up = H[ih[1]] > H[ih[0]] and L[il[1]] > L[il[0]]; dn = H[ih[1]] < H[ih[0]] and L[il[1]] < L[il[0]]
        for d, ok, idx, lvl in ((1, up, ih[1], H[ih[1]]), (-1, dn, il[1], L[il[1]])):
            if not ok or (d, idx) in used: continue
            if d * (C[j] - lvl) >= 0.3 * A[j]:
                used.add((d, idx)); a = A[j]
                # wait until price moved >= 1 ATR away from the level, then arm the limit
                arm = next((k for k in range(j, min(j + 48, len(b) - 1)) if d * ((H[k] if d == 1 else L[k]) - lvl) >= a), None)
                if arm is not None:
                    out.append(dict(t0=T[arm + 1], t1=T[min(j + 48, len(T) - 1)], d=d, entry=lvl, stop=lvl - d * a, yr=pd.Timestamp(T[j]).year))
                    nxt = j + 1
    return out

if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf, mins in (("15min", 15), ("1h", 60)):
        ss = setups(bars(m1, tf)); print(f"##### {tf}: {len(ss)} setups", flush=True)
        real = run(m1, ss, mins); rng = np.random.default_rng(20261013)
        coin = [summ(run(m1, ss, mins, rng))["tot"] for _ in range(50)]
        report(f"STRUCT_RETEST {tf}", real, coin)
