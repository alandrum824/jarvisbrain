"""Rising / Falling Three Methods on gold (Adam's image 2026-10-13). READ-ONLY replay, PRE-REGISTERED:
  Pattern (bull): bar1 big bullish (body >= 1.0 x ATR14); bars 2-4 small (body < 0.5 x bar1 body), each bearish... per the
  drawing the three are bearish, all highs <= bar1 high and lows >= bar1 low; bar5 bullish and CLOSES above the open of
  the first bearish bar (bar2 open) AND above bar1 close ("has to break the first bear candle's open"). Bear = mirror.
  Entry next bar open; SL = pattern extreme (lowest low of bars 1-5) -/+ 0.1 ATR; TP = 2R. Timeframes M15 and H1,
  gold 2020-26, all hours, one trade at a time, max hold 48 bars. Costs: real spread +6 pt, exits on M1.
  Control: 50-seed coin flip. Pass bar = EA Scorecard.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

MK = 6; PTG = PT["XAUUSD"]


def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    A = atr_rma(H, L, C); out = []
    for j in range(20, len(b) - 1):
        i1 = j - 4
        body1 = C[i1] - O[i1]
        if not A[i1] > 0 or abs(body1) < A[i1]:
            continue
        d = 1 if body1 > 0 else -1
        mids = range(i1 + 1, j)
        ok = all(d * (C[m] - O[m]) < 0 and abs(C[m] - O[m]) < 0.5 * abs(body1) and H[m] <= H[i1] and L[m] >= L[i1] for m in mids)
        if not ok:
            continue
        if d * (C[j] - O[j]) <= 0 or d * (C[j] - O[i1 + 1]) <= 0 or d * (C[j] - C[i1]) <= 0:
            continue
        ext = L[i1:j + 1].min() if d == 1 else H[i1:j + 1].max()
        out.append((b.ny.values[j + 1], d, ext - d * 0.1 * A[j], b.ny.values[min(j + 49, len(b) - 1)], pd.Timestamp(b.ny.values[j]).year))
    return out


def run(m1, sig, rng=None):
    T = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    rows = []; busy = -1
    for t, d, stop, tend, yr in sig:
        k = int(np.searchsorted(T, t)); ke = int(np.searchsorted(T, tend))
        if k <= busy or k >= ke:
            continue
        sp = (S[k] + MK) * PTG
        entry = O[k] + (sp if d == 1 else 0)
        risk = d * (entry - stop)
        if risk <= 0:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            entry = O[k] + (sp if d == 1 else 0)
        sl, tp = entry - d * risk, entry + d * 2 * risk
        h = first_hit(H, L, O, S, k, ke, d, sl, tp, PTG, MK)
        m, px = (ke - 1, C[ke - 1] + (0 if d == 1 else (S[ke - 1] + MK) * PTG)) if h is None else h
        busy = m
        rows.append((yr, d, d * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf in ("15min", "1h"):
        b = bars(m1, tf); sig = signals(b)
        real = run(m1, sig)
        rng = np.random.default_rng(20261013)
        coin = [summ(run(m1, sig, rng))["tot"] for _ in range(50)]
        print(f"##### {tf}: {len(sig)} patterns", flush=True)
        report(f"3METHODS {tf}", real, coin)
