"""EURUSD scalper research: the two scalper classes found on the web, replayed on AAAFx EURUSD 2020-26. READ-ONLY.

Adam 2026-10-12: "Look up eurusd scalper ea and build one". Web survey (vendor/tutorial pages): EURUSD scalpers are either
NIGHT scalpers (mean reversion in the quiet Asian-open hours: Smart Owl, Night Scalper listings) or London EMA-cross
momentum scalpers (Pineify's published example). Rules PRE-REGISTERED below, nothing tuned on this data.
  NIGHT: M5 Bollinger(20, 2). Signal bars 18:30-22:00 New York, Mon-Thu evenings. Close above the upper band -> SELL,
         below the lower band -> BUY (fade). Entry next M5 open. TP 10 pips, SL 20 pips. Flat at 01:00 NY.
  LONDON_EMA (Pineify as published): M5 EMA9 crosses EMA21, signal bars 03:00-07:00 NY (07-12 broker GMT+2/3).
         Entry next M5 open in the cross direction. TP 15 pips, SL 10 pips. Flat at 07:00 NY.
One trade at a time. Costs: real bar spread (long pays the ask on entry, short on exit). SL first if a bar hits both.
Control: 50-seed coin flip (same times, same SL/TP). Pass bar = EA Scorecard (>= 5/7 years, PF > 1, beats >= 95% of coin).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe eurusd_scalper_research.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import bars, ema, first_hit
from gold_breakout_research import summ, report

SYM = "EURUSD"; PIP = 0.0001; SEEDS = 50


def signals(m5, kind):
    C = m5.close.values; t = pd.DatetimeIndex(m5.ny.values)
    mins = t.hour * 60 + t.minute; dow = t.dayofweek
    sig = []
    if kind == "NIGHT":
        mid = pd.Series(C).rolling(20).mean().values; sd = pd.Series(C).rolling(20).std(ddof=0).values
        for j in range(20, len(m5) - 1):
            if dow[j] > 3 or not (18 * 60 + 30 <= mins[j] < 22 * 60):
                continue
            if C[j] > mid[j] + 2 * sd[j]:
                sig.append((j, -1))
            elif C[j] < mid[j] - 2 * sd[j]:
                sig.append((j, 1))
    else:
        e9, e21 = ema(C, 9), ema(C, 21)
        for j in range(22, len(m5) - 1):
            if dow[j] > 4 or not (3 * 60 <= mins[j] < 7 * 60):
                continue
            if e9[j] > e21[j] and e9[j - 1] <= e21[j - 1]:
                sig.append((j, 1))
            elif e9[j] < e21[j] and e9[j - 1] >= e21[j - 1]:
                sig.append((j, -1))
    return sig


def run(m1, m5, sig, kind, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    T = m1.ny.values; pt = PT[SYM]
    tp_p, sl_p = (10 * PIP, 20 * PIP) if kind == "NIGHT" else (15 * PIP, 10 * PIP)
    rows = []; busy = -1
    for j, d in sig:
        te = m5.ny.values[j + 1]
        k = int(np.searchsorted(T, te))
        if k >= len(T) or k <= busy:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
        ts = pd.Timestamp(T[k])
        flat = (ts.normalize() + pd.Timedelta(hours=25 if kind == "NIGHT" else 7))
        end = int(np.searchsorted(T, flat.to_datetime64()))
        if end <= k:
            continue
        entry = O[k] + (S[k] * pt if d == 1 else 0)
        sl = entry - d * sl_p; tp = entry + d * tp_p
        h = first_hit(H, L, O, S, k, end, d, sl, tp, pt, 0)
        if h is None:
            m = end - 1; px = C[m] + (0 if d == 1 else S[m] * pt)
        else:
            m, px = h
        busy = m
        rows.append((ts.year, d, d * (px - entry) / sl_p))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = load(SYM); m5 = bars(m1, "5min")
    out = []
    for kind in ("NIGHT", "LONDON_EMA"):
        sig = signals(m5, kind)
        real = run(m1, m5, sig, kind)
        rng = np.random.default_rng(20261012)
        coin = [summ(run(m1, m5, sig, kind, rng))["tot"] for _ in range(SEEDS)]
        out.append(report(kind, real, coin))
        for d, n in ((1, "LONG"), (-1, "SHORT")):
            x = real[real.d == d]; s = summ(x)
            print(f"    {n}: {s['n']} tr {s['tot']:+.1f}R PF {s['pf']:.2f} win {s['win']:.0%}", flush=True)
    pd.DataFrame(out).to_csv(r"C:\Users\aland\stg\obh\eurusd_scalper_summary.csv", index=False)
    print("saved")
