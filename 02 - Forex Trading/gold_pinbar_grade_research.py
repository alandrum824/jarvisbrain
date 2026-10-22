"""Pin bar strength grades on gold (Adam's "Pin bar story" image, 2026-10-13). PRE-REGISTERED. Bull (bear = mirror):
bar range >= 1.0 x ATR14, its low is the lowest low of the last 20 bars (rejection at key structure).
Grade by the long wick's share of the range: STRONGEST >= 75%, STRONGER 60-75%, STRONG 45-60%, INDECISION = body in the middle
(both wicks >= 30%). Entry next open; SL = bar low - 0.1 ATR; TP 1R and 2R; max hold 48 bars; one at a time.
M15 and H1, gold 2020-26, real spread +6 pt, exits M1, coin control."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_three_methods_research as t
from gold_soldiers_research import run
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report

def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    out = {g: [] for g in ("STRONGEST", "STRONGER", "STRONG", "INDECISION")}
    for j in range(25, len(b) - 1):
        r = H[j] - L[j]
        if not A[j] > 0 or r < A[j]: continue
        lw = (min(O[j], C[j]) - L[j]) / r; uw = (H[j] - max(O[j], C[j])) / r
        for d, w, other, key in ((1, lw, uw, L[j] <= L[j - 20:j].min()), (-1, uw, lw, H[j] >= H[j - 20:j].max())):
            if not key: continue
            g = "INDECISION" if (w >= 0.3 and other >= 0.3) else "STRONGEST" if w >= 0.75 else "STRONGER" if w >= 0.6 else "STRONG" if w >= 0.45 else None
            if g is None: continue
            stop = (L[j] - 0.1 * A[j]) if d == 1 else (H[j] + 0.1 * A[j])
            out[g].append((T[j + 1], d, stop, T[min(j + 49, len(b) - 1)], pd.Timestamp(T[j]).year)); break
    return out

if __name__ == "__main__":
    m1 = t.load("XAUUSD")
    for tf in ("15min", "1h"):
        out = signals(bars(m1, tf))
        for g, sig in out.items():
            for tpR in (1.0, 2.0):
                real = run(m1, sig, tpR); rng = np.random.default_rng(20261013)
                coin = [summ(run(m1, sig, tpR, rng))["tot"] for _ in range(30)]
                report(f"PIN {g:10s} {tf} {tpR:.0f}R", real, coin)
