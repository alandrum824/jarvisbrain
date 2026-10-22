"""Three White Soldiers / Three Black Crows on gold (Adam's image 2026-10-13). PRE-REGISTERED:
3 consecutive bullish bars, each closing above the prior close, each body >= 0.5 x ATR14 and closing in the top 30% of
its range (crows = mirror). Entry next open; SL = low of the first soldier -0.1 ATR (high of first crow +0.1 ATR); TP 1R
and 2R (both shown); max hold 48 bars; one trade at a time. M15 and H1, gold 2020-26, real spread +6 pt. Coin control."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_three_methods_research as t
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    A = atr_rma(H, L, C); out = []; last = -10
    for j in range(20, len(b) - 1):
        if j - last < 3 or not A[j] > 0: continue
        for d in (1, -1):
            ok = True
            for m in (j - 2, j - 1, j):
                rng_ = H[m] - L[m]
                if rng_ <= 0 or d * (C[m] - O[m]) < 0.5 * A[j] or d * (C[m] - C[m - 1]) <= 0: ok = False; break
                if (d == 1 and C[m] < H[m] - 0.3 * rng_) or (d == -1 and C[m] > L[m] + 0.3 * rng_): ok = False; break
            if ok:
                stop = (L[j - 2] - 0.1 * A[j]) if d == 1 else (H[j - 2] + 0.1 * A[j])
                out.append((b.ny.values[j + 1], d, stop, b.ny.values[min(j + 49, len(b) - 1)], pd.Timestamp(b.ny.values[j]).year))
                last = j; break
    return out

def run(m1, sig, tpR, rng=None):
    T = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    rows = []; busy = -1
    for tt, d, stop, tend, yr in sig:
        k = int(np.searchsorted(T, tt)); ke = int(np.searchsorted(T, tend))
        if k <= busy or k >= ke: continue
        sp = (S[k] + 6) * 0.01; entry = O[k] + (sp if d == 1 else 0); risk = d * (entry - stop)
        if risk <= 0: continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1; entry = O[k] + (sp if d == 1 else 0)
        h = first_hit(H, L, O, S, k, ke, d, entry - d * risk, entry + d * tpR * risk, 0.01, 6)
        m, px = (ke - 1, C[ke - 1] + (0 if d == 1 else (S[ke - 1] + 6) * 0.01)) if h is None else h
        busy = m; rows.append((yr, d, d * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])

if __name__ == "__main__":
    m1 = t.load("XAUUSD")
    for tf in ("15min", "1h"):
        b = bars(m1, tf); sig = signals(b)
        print(f"##### {tf}: {len(sig)} patterns", flush=True)
        for tpR in (1.0, 2.0):
            real = run(m1, sig, tpR); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, sig, tpR, rng))["tot"] for _ in range(50)]
            report(f"SOLDIERS {tf} {tpR:.0f}R", real, coin)
