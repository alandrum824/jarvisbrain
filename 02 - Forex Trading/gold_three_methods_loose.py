"""Looser Three Methods (follow-up, not pre-registered with the strict one): bar1 body >= 1.0 ATR; then 2-4 small bars
(body < 0.5 x bar1 body, any colour) all inside bar1's range; then a bar closing beyond bar1's close in bar1's direction.
Same entry/stop/2R/exits/coin as gold_three_methods_research.py. M5, M15, H1."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_three_methods_research as t
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report

def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    A = atr_rma(H, L, C); out = []; last = -10
    for j in range(20, len(b) - 1):
        for n in (2, 3, 4):
            i1 = j - n - 1
            body1 = C[i1] - O[i1]
            if not A[i1] > 0 or abs(body1) < A[i1]:
                continue
            d = 1 if body1 > 0 else -1
            mids = range(i1 + 1, j)
            if not all(abs(C[m] - O[m]) < 0.5 * abs(body1) and H[m] <= H[i1] and L[m] >= L[i1] for m in mids):
                continue
            if d * (C[j] - O[j]) <= 0 or d * (C[j] - C[i1]) <= 0 or j - last < 3:
                continue
            ext = L[i1:j + 1].min() if d == 1 else H[i1:j + 1].max()
            out.append((b.ny.values[j + 1], d, ext - d * 0.1 * A[j], b.ny.values[min(j + 49, len(b) - 1)], pd.Timestamp(b.ny.values[j]).year))
            last = j; break
    return out

if __name__ == "__main__":
    m1 = t.load("XAUUSD")
    for tf in ("5min", "15min", "1h"):
        b = bars(m1, tf); sig = signals(b)
        real = t.run(m1, sig)
        rng = np.random.default_rng(20261013)
        coin = [summ(t.run(m1, sig, rng))["tot"] for _ in range(50)]
        print(f"##### {tf}: {len(sig)} patterns", flush=True)
        report(f"3M-LOOSE {tf}", real, coin)
