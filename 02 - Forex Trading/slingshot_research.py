"""Slingshots_EA_3.02.mq4 (Adam's Google Drive; source = "Exp_Slingshot Rev_1.00 2022.03.04") replayed on AAAFx 2020-26. READ-ONLY.

Rules as coded (defaults): window 04:15 -> 08:30 SERVER time. When bar[1] is the 08:30 bar (so at 08:30 + one chart bar),
compare the closes: close(08:30) < close(04:15) -> BUY, close(08:30) > close(04:15) -> SELL (a FADE of the window move).
Three market orders, SL 30 pips each, TP 1R / 2R / 3R; MaxSpread 6 pips. No time exit (orders run to SL/TP).
Assumptions (not in the code): chart M15 (entry 08:45 server); server = NY+7 (the common GMT+2/+3 broker clock, which the
author's times imply); a trade still open after 5 days is closed at market. R = mean of the three legs.
Control: 50-seed coin flip (same times, same stops/targets).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe slingshot_research.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import first_hit
from gold_breakout_research import summ, report

PIP = {"EURUSD": 0.0001, "GBPUSD": 0.0001, "USDJPY": 0.01}


def run(m1, sym, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    T = m1.ny.values; pt = PT[sym]; pip = PIP[sym]
    srv = pd.DatetimeIndex(T) + pd.Timedelta(hours=7)             # server clock = NY+7
    mins = srv.hour * 60 + srv.minute
    day = srv.normalize()
    rows = []; busy = -1
    dv = day.values
    starts = np.flatnonzero(np.r_[True, dv[1:] != dv[:-1]]); ends = np.r_[starts[1:], len(dv)]
    for s0, s1 in zip(starts, ends):
        if pd.Timestamp(dv[s0]).dayofweek >= 5:
            continue
        idx = np.arange(s0, s1)
        mm = mins[idx]
        a = idx[mm == 4 * 60 + 15 + 14]          # close of the 04:15 M15 bar = M1 bar 04:29
        b = idx[mm == 8 * 60 + 30 + 14]          # close of the 08:30 M15 bar = M1 bar 08:44
        e = idx[mm == 8 * 60 + 45]               # entry: open of the 08:45 bar
        if not (len(a) and len(b) and len(e)):
            continue
        k = e[0]
        if k <= busy or S[k] * pt > 6 * pip:
            continue
        d = 1 if C[b[0]] < C[a[0]] else (-1 if C[b[0]] > C[a[0]] else 0)
        if d == 0:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
        entry = O[k] + (S[k] * pt if d == 1 else 0)
        risk = 30 * pip
        end = min(len(T), k + 5 * 1440)
        legs = []; last = k
        for rr in (1, 2, 3):
            h = first_hit(H, L, O, S, k, end, d, entry - d * risk, entry + d * rr * risk, pt, 0)
            if h is None:
                m = end - 1; px = C[m] + (0 if d == 1 else S[m] * pt)
            else:
                m, px = h
            legs.append(d * (px - entry) / risk); last = max(last, m)
        busy = last
        rows.append((pd.Timestamp(T[k]).year, d, float(np.mean(legs))))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    for sym in PIP:
        m1 = load(sym)
        real = run(m1, sym)
        rng = np.random.default_rng(20261012)
        coin = [summ(run(m1, sym, rng))["tot"] for _ in range(50)]
        print(f"##### {sym}", flush=True)
        report("SLINGSHOT", real, coin)
