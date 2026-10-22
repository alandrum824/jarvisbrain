"""Bull/bear flags on gold (Adam's "Trading Patterns" image, 2026-10-13). PRE-REGISTERED:
Pole: net move over 5 bars >= 3 x ATR14 (ending at bar p). Flag: the next 5-15 bars, whose total range (max high - min low)
<= 50% of the pole move and which never retrace beyond the pole midpoint. Entry: first close beyond the flag high (bull)
/ low (bear) in the pole direction -> next open; SL = flag low - 0.1 ATR (bull); TP 2R; max hold 48 bars; one at a time.
M15 and H1, gold 2020-26, real spread +6 pt, exits M1, 50-seed coin."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_three_methods_research as t
from gold_soldiers_research import run
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report

def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    out = []; nxt = 0
    for p in range(20, len(b) - 20):
        if p < nxt or not A[p] > 0: continue
        mv = C[p] - C[p - 5]
        if abs(mv) < 3 * A[p]: continue
        d = 1 if mv > 0 else -1; mid = (C[p] + C[p - 5]) / 2
        for j in range(p + 6, min(p + 17, len(b) - 1)):
            fh, fl = H[p + 1:j].max(), L[p + 1:j].min()
            if fh - fl > 0.5 * abs(mv) or (d == 1 and fl < mid) or (d == -1 and fh > mid): break
            if d * (C[j] - (fh if d == 1 else fl)) > 0:
                stop = (fl - 0.1 * A[j]) if d == 1 else (fh + 0.1 * A[j])
                out.append((T[j + 1], d, stop, T[min(j + 49, len(b) - 1)], pd.Timestamp(T[j]).year)); nxt = j + 1; break
    return out

if __name__ == "__main__":
    m1 = t.load("XAUUSD")
    for tf in ("15min", "1h"):
        sig = signals(bars(m1, tf)); print(f"##### {tf}: {len(sig)} flags", flush=True)
        real = run(m1, sig, 2.0); rng = np.random.default_rng(20261013)
        coin = [summ(run(m1, sig, 2.0, rng))["tot"] for _ in range(50)]
        report(f"FLAG {tf} 2R", real, coin)
