"""Replay of GoldORBCore_v1.00.mq5 (Adam's upload 2026-10-13; another AI's build of the "NANDR ORB Core" spec). READ-ONLY.

Rules as coded (defaults), all times UTC:
  Sessions: Daily open 22:00, Tokyo 00:00, London 07:00, NY 12:00, NY-ORB 13:00 (NY-ORB must follow NY's breakout direction).
  Range = high/low of the first 15 minutes (EA uses ask for the high, bid for the low).
  Breakout = an M15 bar closing beyond the range (simple mode). One trade per session per day.
  AS_CODED (InpWaitForRetest=true, ORB_RISK_BOUNDARY_1_2): wait up to 40 M15 bars for price to come back to the broken
     boundary, enter at market there; SL distance = entry - broken boundary (buy), TP = 2x that.
  Alternatives tested on the same breakouts (direct entry at the breakout bar close + 1 bar open):
     DIRECT_OPP_1_1  : SL = opposite boundary, TP 1R.
     DIRECT_MID_1_5  : SL = range midpoint, TP 1.5R.
  Daily bias AUTO with flips allowed lets every direction through, so it is a no-op and isn't modelled.
  Spread cap $0.45, Friday flat 21:00 UTC; trades otherwise run to SL/TP (capped at 3 days).
Costs: real bar spread + 6 pt markup, exits on M1, SL first if a bar hits both. Gold 2020-26. Control: 50-seed coin flip.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import first_hit
from gold_breakout_research import summ, report

MK = 6; SEEDS = 50
SESS = [("DOPEN", 22 * 60), ("TOKYO", 0), ("LONDON", 7 * 60), ("NY", 12 * 60), ("NYORB", 13 * 60)]


def prep():
    m1 = load("XAUUSD")
    u = pd.DatetimeIndex(m1.ny).tz_localize("America/New_York", ambiguous="NaT", nonexistent="NaT").tz_convert("UTC").tz_localize(None)
    m1 = m1.assign(utc=u).dropna(subset=["utc"]).sort_values("utc").reset_index(drop=True)
    return m1


def setups(m1):
    """one record per session-day with a confirmed breakout: entry indices/prices for each variant."""
    U = m1.utc.values; H, L, C, O, S = (m1[k].values for k in ("high", "low", "close", "open", "spread"))
    pt = PT["XAUUSD"]
    days = pd.DatetimeIndex(U).normalize().unique()
    out = []
    for d in days:
        if d.dayofweek >= 5:
            continue
        nydir = 0
        for name, smin in SESS:
            st = d + pd.Timedelta(minutes=smin)
            i0 = int(np.searchsorted(U, st.to_datetime64())); i1 = int(np.searchsorted(U, (st + pd.Timedelta(minutes=15)).to_datetime64()))
            if i1 - i0 < 10:
                continue
            hi = (H[i0:i1] + (S[i0:i1] + MK) * pt).max()          # ask high
            lo = L[i0:i1].min()                                  # bid low
            # walk M15 closes after the range
            j = i1; brk = 0; jb = None
            limit = int(np.searchsorted(U, (st + pd.Timedelta(hours=10)).to_datetime64()))
            while j + 15 <= min(limit, len(U)):
                c = C[j + 14]
                if c > hi: brk, jb = 1, j + 15; break
                if c < lo: brk, jb = -1, j + 15; break
                j += 15
            if not brk:
                continue
            if name == "NYORB" and nydir != 0 and brk != nydir:
                continue
            if name == "NY":
                nydir = brk
            out.append(dict(day=d, sess=name, dir=brk, hi=hi, lo=lo, jb=jb))
    return out


def run(m1, sets, variant, rng=None):
    U = m1.utc.values; H, L, C, O, S = (m1[k].values for k in ("high", "low", "close", "open", "spread"))
    pt = PT["XAUUSD"]; rows = []
    for s in sets:
        d = s["dir"]; hi, lo = s["hi"], s["lo"]; k = s["jb"]
        if k >= len(U):
            continue
        if variant == "AS_CODED":
            # retest: within 40 M15 bars, bid <= hi (buy) / ask >= lo (sell); enter at market on that M1 bar's close
            end = min(len(U), k + 40 * 15)
            if d == 1:
                hit = np.flatnonzero(L[k:end] <= hi)
            else:
                hit = np.flatnonzero(H[k:end] + (S[k:end] + MK) * pt >= lo)
            if not len(hit):
                continue
            k = k + hit[0]
            sp = (S[k] + MK) * pt
            entry_ref = hi if d == 1 else lo                     # price touched the boundary
            entry = entry_ref + (sp if d == 1 else 0)
            sl_dist = entry - hi if d == 1 else lo - entry
            if sl_dist <= 0:
                sl_dist = 3.0                                   # EA's legacy fallback ($3)
            tp_dist = 2 * sl_dist if sl_dist != 3.0 else 3.0
            k = k + 1
        else:
            sp = (S[k] + MK) * pt
            entry = O[k] + (sp if d == 1 else 0)
            if variant == "DIRECT_OPP_1_1":
                sl_dist = entry - lo if d == 1 else hi - entry; tp_dist = sl_dist
            else:
                mid = (hi + lo) / 2
                sl_dist = entry - mid if d == 1 else mid - entry; tp_dist = 1.5 * sl_dist
            if sl_dist <= 0:
                continue
        if sp > 0.45:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            entry = O[min(k, len(O) - 1)] + (sp if d == 1 else 0)
        if k >= len(U) - 2:
            continue
        sl = entry - d * sl_dist; tp = entry + d * tp_dist
        end = min(len(U), k + 3 * 1440)
        h = first_hit(H, L, O, S, k, end, d, sl, tp, pt, MK)
        if h is None:
            m = end - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * pt)
        else:
            m, px = h
        rows.append((pd.Timestamp(U[k]).year, d, d * (px - entry) / sl_dist, sl_dist))
    return pd.DataFrame(rows, columns=["year", "d", "R", "sl"])


if __name__ == "__main__":
    m1 = prep()
    sets = setups(m1)
    print(f"{len(sets)} confirmed session breakouts 2020-26", flush=True)
    for v in ("AS_CODED", "DIRECT_OPP_1_1", "DIRECT_MID_1_5"):
        real = run(m1, sets, v)
        rng = np.random.default_rng(20261013)
        coin = [summ(run(m1, sets, v, rng))["tot"] for _ in range(SEEDS)]
        report(v, real, coin)
        print(f"    median stop ${real.sl.median():.2f}  (share of stops under $1: {(real.sl < 1).mean():.0%})", flush=True)
