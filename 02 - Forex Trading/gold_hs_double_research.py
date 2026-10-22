"""Head & Shoulders and Double Top/Bottom on gold (Adam's images 2026-10-13). READ-ONLY replay, PRE-REGISTERED.
Swings: confirmed 3/3 fractals (known 3 bars after the pivot).
H&S (bearish; inverse = mirror): the last 5 alternating confirmed swings are High LS, Low T1, High HEAD, Low T2, High RS with
  HEAD > LS and HEAD > RS, |LS - RS| <= 1.0 x ATR(14), HEAD - max(LS, RS) >= 0.5 x ATR. Neckline = line through T1 and T2.
  Entry: first bar CLOSE below the neckline (projected to that bar), within 20 bars after RS is confirmed -> next open.
  SL = RS + 0.1 ATR. TP = measured move (HEAD - neckline at the head) from the neckline break, clipped to [1R, 4R].
DOUBLE TOP (bottom = mirror): last 3 alternating swings High T1, Low V, High T2 with |T1 - T2| <= 0.3 x ATR and
  min(T1,T2) - V >= 1.0 x ATR. Entry: first close below V within 20 bars after T2 is confirmed; SL = max(T1,T2) + 0.1 ATR;
  TP = (max(T1,T2) - V) projected below V, clipped to [1R, 4R].
Timeframes M15 and H1, gold 2020-26, one trade at a time per pattern type, max hold 96 bars, real spread +6 pt, exits M1.
Control: 50-seed coin flip. Pass bar = EA Scorecard.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

K = 3


def piv(b):
    H, L = b.high.values, b.low.values; n = len(H); ev = []
    for i in range(K, n - K):
        if H[i] > H[i - K:i].max() and H[i] >= H[i + 1:i + K + 1].max(): ev.append((i + K, i, 1, H[i]))
        if L[i] < L[i - K:i].min() and L[i] <= L[i + 1:i + K + 1].min(): ev.append((i + K, i, -1, L[i]))
    ev.sort()
    # alternate: merge consecutive same-type swings keeping the more extreme
    alt = []
    for e in ev:
        if alt and alt[-1][2] == e[2]:
            if (e[2] == 1 and e[3] > alt[-1][3]) or (e[2] == -1 and e[3] < alt[-1][3]): alt[-1] = e
        else:
            alt.append(e)
    return alt


def signals(b):
    C = b.close.values; A = atr_rma(b.high.values, b.low.values, C, 14)
    sw = piv(b); hs, dbl = [], []
    for n in range(4, len(sw)):
        c5 = sw[n - 4:n + 1]
        conf = c5[-1][0]
        if conf >= len(b) - 2: continue
        a = A[conf]
        if not a > 0: continue
        # H&S (bear if pattern starts with a High)
        typ = c5[0][2]
        if [x[2] for x in c5] == [typ, -typ, typ, -typ, typ]:
            ls, t1, hd, t2, rs = (x[3] for x in c5)
            d = -typ                                      # bearish H&S (typ=+1) -> sell
            if typ * (hd - ls) > 0 and typ * (hd - rs) > 0 and abs(ls - rs) <= a and typ * (hd - (max(ls, rs) if typ == 1 else min(ls, rs))) >= 0.5 * a:
                i1, i2 = c5[1][1], c5[3][1]
                slope = (t2 - t1) / (i2 - i1) if i2 != i1 else 0.0
                neck_at = lambda i: t1 + slope * (i - i1)
                height = abs(hd - neck_at(c5[2][1]))
                for j in range(conf, min(conf + 20, len(b) - 1)):
                    if d * (C[j] - neck_at(j)) > 0:
                        hs.append(dict(j=j, d=d, stop=rs - d * 0.1 * a, target=neck_at(j) + d * height)); break
        # double top/bottom (last 3 swings)
        c3 = sw[n - 2:n + 1]; t = c3[0][2]
        if [x[2] for x in c3] == [t, -t, t]:
            t1, v, t2 = (x[3] for x in c3)
            if abs(t1 - t2) <= 0.3 * a and t * ((min(t1, t2) if t == 1 else max(t1, t2)) - v) >= a:
                d = -t; top = max(t1, t2) if t == 1 else min(t1, t2)
                for j in range(conf, min(conf + 20, len(b) - 1)):
                    if d * (C[j] - v) > 0:
                        dbl.append(dict(j=j, d=d, stop=top - d * 0.1 * a, target=v + d * abs(top - v))); break
    return hs, dbl


def run(m1, b, sig, rng=None):
    T = m1.ny.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    bt = b.ny.values; rows = []; busy = -1; seen = set()
    for s in sig:
        if s["j"] in seen: continue
        seen.add(s["j"])
        k = int(np.searchsorted(T, bt[s["j"] + 1])); ke = int(np.searchsorted(T, bt[min(s["j"] + 97, len(bt) - 1)]))
        if k <= busy or k >= ke: continue
        d = s["d"]; sp = (S[k] + 6) * 0.01; entry = O[k] + (sp if d == 1 else 0)
        risk = d * (entry - s["stop"])
        if risk <= 0: continue
        tpR = min(max(d * (s["target"] - entry) / risk, 1.0), 4.0)
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1; entry = O[k] + (sp if d == 1 else 0)
        h = first_hit(H, L, O, S, k, ke, d, entry - d * risk, entry + d * tpR * risk, 0.01, 6)
        m, px = (ke - 1, C[ke - 1] + (0 if d == 1 else (S[ke - 1] + 6) * 0.01)) if h is None else h
        busy = m; rows.append((pd.Timestamp(bt[s["j"]]).year, d, d * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = load("XAUUSD")
    for tf in ("15min", "1h"):
        b = bars(m1, tf); hs, dbl = signals(b)
        for name, sig in (("H&S", hs), ("DOUBLE", dbl)):
            real = run(m1, b, sig); rng = np.random.default_rng(20261013)
            coin = [summ(run(m1, b, sig, rng))["tot"] for _ in range(50)]
            print(f"##### {name} {tf}: {len(sig)} patterns", flush=True)
            report(f"{name} {tf}", real, coin)
