"""Three areas to trade after one impulse (Adam's "Different types of areas to trade" image, 2026-10-13). PRE-REGISTERED.
Impulse bar i: body >= 1.5 x ATR14 and leaves an FVG (bull: low[i+1] > high[i-1]). Bear = mirror. Areas (bull):
  DEMAND1: base candle before the impulse (bar i-1): limit at its high, SL below its low - 0.1 ATR.
  GAP    : the FVG (high[i-1] .. low[i+1]): limit at the gap top (low[i+1]), SL below the gap bottom - 0.1 ATR... i.e. below high[i-1].
           Variant GAP_DEEP: SL below the impulse bar low - 0.1 ATR.
  DEMAND2: the pause after the impulse: the first 1-3 bars after i whose range stays above the impulse midpoint; zone =
           their low .. impulse close; limit at the impulse close, SL below the zone low - 0.1 ATR. Requires a new high
           (break of the pause high) before the fill is allowed (the picture's continuation), within 24 bars.
TP 2R, fill window 48 bars after the setup, max hold 48 bars after fill, one trade at a time per area.
Realistic fills: buy limits fill on the ask (low + spread <= price), sell limits on the bid (high >= price); coin enters at
the same price in a random direction. M15 and H1, gold 2020-26, real spread +6 pt, exits M1.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

AREAS = ("DEMAND1", "GAP", "GAP_DEEP", "DEMAND2")

def setups(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    out = {a: [] for a in AREAS}
    for i in range(10, len(b) - 80):
        a = A[i]
        if not a > 0 or abs(C[i] - O[i]) < 1.5 * a: continue
        d = 1 if C[i] > O[i] else -1
        if not ((L[i + 1] > H[i - 1]) if d == 1 else (H[i + 1] < L[i - 1])): continue
        yr = pd.Timestamp(T[i]).year
        def put(name, entry, stop, start):
            out[name].append(dict(t0=T[start], t1=T[min(start + 48, len(T) - 1)], d=d, entry=entry, stop=stop, yr=yr))
        if d == 1:
            put("DEMAND1", H[i - 1], L[i - 1] - 0.1 * a, i + 2)
            put("GAP", L[i + 1], H[i - 1] - 0.1 * a, i + 2)
            put("GAP_DEEP", L[i + 1], L[i] - 0.1 * a, i + 2)
        else:
            put("DEMAND1", L[i - 1], H[i - 1] + 0.1 * a, i + 2)
            put("GAP", H[i + 1], L[i - 1] + 0.1 * a, i + 2)
            put("GAP_DEEP", H[i + 1], H[i] + 0.1 * a, i + 2)
        # DEMAND2: pause bars after the impulse staying beyond the impulse midpoint
        mid = (O[i] + C[i]) / 2; n = 0
        while n < 3 and i + 1 + n < len(b) and d * ((L[i + 1 + n] if d == 1 else H[i + 1 + n]) - mid) > 0 \
                and d * (C[i + 1 + n] - (H[i] if d == 1 else L[i])) <= 0:
            n += 1
        if n >= 1:
            zone = L[i + 1:i + 1 + n].min() if d == 1 else H[i + 1:i + 1 + n].max()
            ph = H[i:i + 1 + n].max() if d == 1 else L[i:i + 1 + n].min()
            j0 = i + 1 + n
            brk = next((j for j in range(j0, min(j0 + 24, len(b) - 1)) if d * (C[j] - ph) > 0), None)
            if brk is not None:
                put("DEMAND2", C[i], zone - d * 0.1 * a, brk + 1)
    return out

def run(m1, ss, mins, rng=None):
    TT = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    rows = []; busy = -1
    for s in ss:
        k0 = int(np.searchsorted(TT, s["t0"])); k1 = int(np.searchsorted(TT, s["t1"]))
        if k0 <= busy or k1 <= k0: continue
        d, e = s["d"], s["entry"]
        risk = d * (e - s["stop"])
        if risk <= 0: continue
        seg = (L[k0:k1] + (S[k0:k1] + 6) * 0.01 <= e) if d == 1 else (H[k0:k1] >= e)
        hit = np.flatnonzero(seg)
        if not len(hit): continue
        k = k0 + hit[0]
        dd = d if rng is None else (1 if rng.random() < 0.5 else -1)
        ke = min(k + 48 * mins, len(C) - 1)
        h = first_hit(H, L, O, S, k + 1, ke, dd, e - dd * risk, e + dd * 2 * risk, 0.01, 6)
        m, px = (ke - 1, C[ke - 1] + (0 if dd == 1 else (S[ke - 1] + 6) * 0.01)) if h is None else h
        busy = m; rows.append((s["yr"], dd, dd * (px - e) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])

if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf, mins in (("15min", 15), ("1h", 60)):
        out = setups(bars(m1, tf))
        for a in AREAS:
            real = run(m1, out[a], mins); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, out[a], mins, rng))["tot"] for _ in range(30)]
            report(f"{a:8s} {tf}", real, coin)
