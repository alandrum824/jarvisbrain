"""Real zone vs fake zone (Adam's "Bearish sell traps" image, 2026-10-13). READ-ONLY, PRE-REGISTERED. Bear case; bull = mirror.
Leg: a confirmed 3/3 swing high SH followed by the next confirmed swing low SL with SH - SL >= 3 x ATR14.
  REAL zone = the origin of the leg: sell limit at the body top of the SH bar, stop = SH high + 0.25 ATR.
  FAKE zone = a minor base inside the leg: the LAST bullish bar between SH and SL whose high is in the lower half of the
              leg; sell limit at its high, stop = its high + 0.25 ATR.
Both armed once SL is confirmed (SL bar + 3), valid 96 bars, cancelled if price trades beyond the stop before filling.
TP = the leg low (SL, "target area"); skipped if < 1R. Max hold 96 bars after the fill. Realistic fills (sell limit on the
bid high, buy limit on the ask); coin = same fill price, random direction, same distances. M15 and H1, gold 2020-26,
real spread +6 pt, exits M1."""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report
from gold_hs_double_research import piv

def setups(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close")); A = atr_rma(H, L, C); T = b.ny.values
    sw = piv(b); out = {"REAL": [], "FAKE": []}
    for n in range(1, len(sw)):
        (c0, i0, t0, p0), (c1, i1, t1, p1) = sw[n - 1], sw[n]
        if t0 == t1 or c1 >= len(b) - 100: continue
        d = -t0                                         # swing high then low -> sell retracements (d=-1)
        a = A[c1]
        if not a > 0 or abs(p0 - p1) < 3 * a: continue
        half = (p0 + p1) / 2
        real_e = max(O[i0], C[i0]) if d == -1 else min(O[i0], C[i0])
        out["REAL"].append(dict(arm=c1 + 1, d=d, entry=real_e, stop=p0 - d * 0.25 * a, tp=p1, yr=pd.Timestamp(T[c1]).year))
        cand = [k for k in range(i0 + 1, i1) if d * (C[k] - O[k]) < 0 and ((H[k] < half) if d == -1 else (L[k] > half))]
        if cand:
            k = cand[-1]; e = H[k] if d == -1 else L[k]
            out["FAKE"].append(dict(arm=c1 + 1, d=d, entry=e, stop=e - d * 0.25 * a, tp=p1, yr=pd.Timestamp(T[c1]).year))
    return out

def run(m1, b, ss, rng=None):
    TT = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread")); BT = b.ny.values
    rows = []; busy = -1
    for s in ss:
        k0 = int(np.searchsorted(TT, BT[s["arm"]])); k1 = int(np.searchsorted(TT, BT[min(s["arm"] + 96, len(BT) - 1)]))
        if k0 <= busy or k1 <= k0: continue
        d, e = s["d"], s["entry"]; risk = d * (e - s["stop"]); tpR = d * (s["tp"] - e) / risk if risk > 0 else 0
        if risk <= 0 or tpR < 1: continue
        sp = (S[k0:k1] + 6) * 0.01
        fill = (L[k0:k1] + sp <= e) if d == 1 else (H[k0:k1] >= e)
        dead = (L[k0:k1] <= s["stop"]) if d == 1 else (H[k0:k1] + sp >= s["stop"])
        f = np.flatnonzero(fill); x = np.flatnonzero(dead)
        if not len(f) or (len(x) and x[0] < f[0]): continue
        k = k0 + f[0]
        dd = d if rng is None else (1 if rng.random() < 0.5 else -1)
        ke = min(k + int((BT[1] - BT[0]) / np.timedelta64(1, "m")) * 96, len(C) - 1)
        h = first_hit(H, L, O, S, k + 1, ke, dd, e - dd * risk, e + dd * tpR * risk, 0.01, 6)
        m, px = (ke - 1, C[ke - 1] + (0 if dd == 1 else (S[ke - 1] + 6) * 0.01)) if h is None else h
        busy = m; rows.append((s["yr"], dd, dd * (px - e) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])

if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf in ("15min", "1h"):
        b = bars(m1, tf); out = setups(b)
        for z in ("REAL", "FAKE"):
            real = run(m1, b, out[z]); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, b, out[z], rng))["tot"] for _ in range(30)]
            report(f"{z} zone {tf}", real, coin)
