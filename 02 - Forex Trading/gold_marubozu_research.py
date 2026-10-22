"""Marubozu on gold (Adam's image 2026-10-13). PRE-REGISTERED: bar body >= 1.0 x ATR14, each wick <= 10% of the bar range.
Entry next open in the bar's direction; SL = the bar's opposite end -/+ 0.1 ATR; TP 1R and 2R; max hold 48 bars; one trade
at a time. M15 and H1, gold 2020-26, real spread +6 pt, exits M1, 50-seed coin (same entry bar, random direction)."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gold_three_methods_research as t
from gold_soldiers_research import run
from pullback_scalper_research import bars, atr_rma
from gold_breakout_research import summ, report

def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); out = []
    for j in range(20, len(b) - 1):
        r = H[j] - L[j]; body = C[j] - O[j]
        if not A[j] > 0 or r <= 0 or abs(body) < A[j]: continue
        if H[j] - max(O[j], C[j]) > 0.1 * r or min(O[j], C[j]) - L[j] > 0.1 * r: continue
        d = 1 if body > 0 else -1
        stop = (L[j] - 0.1 * A[j]) if d == 1 else (H[j] + 0.1 * A[j])
        out.append((b.ny.values[j + 1], d, stop, b.ny.values[min(j + 49, len(b) - 1)], pd.Timestamp(b.ny.values[j]).year))
    return out

if __name__ == "__main__":
    m1 = t.load("XAUUSD")
    for tf in ("15min", "1h"):
        sig = signals(bars(m1, tf)); print(f"##### {tf}: {len(sig)} marubozu", flush=True)
        for tpR in (1.0, 2.0):
            real = run(m1, sig, tpR); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, sig, tpR, rng))["tot"] for _ in range(50)]
            report(f"MARUBOZU {tf} {tpR:.0f}R", real, coin)
