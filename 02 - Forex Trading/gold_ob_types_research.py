"""Order-block candle types on gold (Adam's "Different OB/Demand type" image, 2026-10-13). READ-ONLY, PRE-REGISTERED.
Impulse bar i: body >= 1.5 x ATR14 and it leaves an FVG (bull: low[i+1] > high[i-1]; checked when bar i+1 closes).
OB = bar i-1 (the candle right before the impulse). Zone = OB high..OB low. Bear = mirror.
OB type of bar i-1 (bull case): NORMAL = bearish body >= 30% of range; PIN = lower wick >= 50% of range;
  DOJI = body <= 10% of range; ENGULF = the impulse's body engulfs the OB's whole range; MANIP = OB low sweeps the low of
  the 5 bars before it. A bar can fall in several types; ALL = every OB.
Entry: buy limit at OB high on the first return within 48 bars after the FVG bar; SL = OB low - 0.1 ATR; TP = 2R;
  max hold 48 bars after the fill; one trade at a time. M15 and H1, gold 2020-26, real spread +6 pt, exits on M1. Coin control.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

TYPES = ("ALL", "NORMAL", "PIN", "DOJI", "ENGULF", "MANIP")

def setups(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values; out = []
    for i in range(10, len(b) - 50):
        a = A[i]
        if not a > 0 or abs(C[i] - O[i]) < 1.5 * a: continue
        d = 1 if C[i] > O[i] else -1
        if not ((L[i + 1] > H[i - 1]) if d == 1 else (H[i + 1] < L[i - 1])): continue
        o = i - 1; r = H[o] - L[o]
        if r <= 0: continue
        body = C[o] - O[o]
        lw = min(O[o], C[o]) - L[o]; uw = H[o] - max(O[o], C[o])
        t = {"ALL": True,
             "NORMAL": d * body < 0 and abs(body) >= 0.3 * r,
             "PIN": (lw if d == 1 else uw) >= 0.5 * r,
             "DOJI": abs(body) <= 0.1 * r,
             "ENGULF": (min(O[i], C[i]) <= L[o] and max(O[i], C[i]) >= H[o]),
             "MANIP": (L[o] < L[o - 5:o].min()) if d == 1 else (H[o] > H[o - 5:o].max())}
        entry = H[o] if d == 1 else L[o]; stop = (L[o] - 0.1 * a) if d == 1 else (H[o] + 0.1 * a)
        out.append(dict(t0=T[i + 2], t1=T[i + 50], d=d, entry=entry, stop=stop, yr=pd.Timestamp(T[i]).year, **t))
    return out

def run(m1, ss, rng=None):
    TT = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    rows = []; busy = -1
    for s in ss:
        k0 = int(np.searchsorted(TT, s["t0"])); k1 = int(np.searchsorted(TT, s["t1"]))
        if k0 <= busy: continue
        d, e = s["d"], s["entry"]
        seg = (L[k0:k1] + (S[k0:k1] + 6) * 0.01 <= e) if d == 1 else (H[k0:k1] >= e)   # buy limit fills on the ask, sell limit on the bid
        hit = np.flatnonzero(seg)
        if not len(hit): continue
        k = k0 + hit[0]; risk = d * (e - s["stop"])
        if risk <= 0: continue
        dd, entry = d, e
        if rng is not None:
            dd = 1 if rng.random() < 0.5 else -1
            entry = e   # coin enters at the same limit price, random direction
        ke = min(k + 48 * (15 if s["tf"] == "15min" else 60), len(C) - 1)
        h = first_hit(H, L, O, S, k + 1, ke, dd, entry - dd * risk, entry + dd * 2 * risk, 0.01, 6)
        m, px = (ke - 1, C[ke - 1] + (0 if dd == 1 else (S[ke - 1] + 6) * 0.01)) if h is None else h
        busy = m; rows.append((s["yr"], dd, dd * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])

if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf in ("15min", "1h"):
        ss = setups(bars(m1, tf))
        for s in ss: s["tf"] = tf
        for t in TYPES:
            sub = [s for s in ss if s[t]]
            real = run(m1, sub); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, sub, rng))["tot"] for _ in range(30)]
            report(f"OB {t:6s} {tf}", real, coin)
