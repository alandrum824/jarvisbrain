"""Roboquant "9:30 box" ad (Adam 2026-10-22: "H/L first 15m -> break"). READ-ONLY replay, bars only.
Retest cells (limit at the broken edge or box midpoint, NAS100): run with ORB_RETEST=1. An argv flag would break
pullback_scalper_research, which reads sys.argv[1] on import.

PRE-REGISTERED rules (fixed before any result), all times New York:
  Box = high/low of the 09:30-09:45 M1 bars. One trade per day, no new entries after 12:00, flat at 16:00.
  Entry STOP  : first M1 bar after 09:45 that touches an edge -> enter at the edge (or the bar open if it gapped past).
  Entry CLOSE : first M5 close beyond the box -> enter at the next M1 open.
  SL = the opposite side of the box. TP = 1R or 2R.
Cells: XAUUSD, EURUSD, US30, NAS100 x {STOP, CLOSE} x {1R, 2R} = 16.
PASS = PF > 1 AND positive in >= 5 of 7 years (4 of 5 for indices, history from 2022) AND beats >= 95% of 50 coin-flip
runs (same entry bar, price and stop size, random direction). ~16 cells: about one could pass by chance, so a pass still
needs an MT5 tester confirmation.
Costs: the bar's own spread (+6 pt markup on gold); shorts exit on the ask. SL first if one bar hits both.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, DATA
from pullback_scalper_research import first_hit
from gold_breakout_research import report

PT = {"XAUUSD": 0.01, "EURUSD": 0.00001, "US30": 0.1, "NAS100": 0.1}
MK = {"XAUUSD": 6}
SEEDS = 50


def setups(df, entry):
    T = df.ny.values; O, H, L, C = (df[k].values for k in ("open", "high", "low", "close"))
    days = pd.DatetimeIndex(T).normalize().unique(); out = []
    for d in days:
        if d.dayofweek >= 5:
            continue
        b0 = (d + pd.Timedelta(hours=9, minutes=30)).to_datetime64()
        i0 = np.searchsorted(T, b0); i1 = np.searchsorted(T, b0 + np.timedelta64(15, "m"))
        iN = np.searchsorted(T, b0 + np.timedelta64(150, "m")); iF = np.searchsorted(T, b0 + np.timedelta64(390, "m"))
        if i1 - i0 < 12:
            continue
        hi = H[i0:i1].max(); lo = L[i0:i1].min()
        if hi <= lo:
            continue
        if entry == "STOP":
            for k in range(i1, iN):
                up = H[k] >= hi; dn = L[k] <= lo
                if up and dn:
                    break
                if up or dn:
                    dr = 1 if up else -1
                    e = max(hi, O[k]) if up else min(lo, O[k])
                    out.append(dict(k=k, d=dr, e=e, sl=lo if up else hi, fl=iF, stop_entry=True, hi=hi, lo=lo)); break
        else:
            t5 = T[i1:iN]; m5 = (t5.astype("datetime64[m]").astype(np.int64) % 5) == 4
            for k in np.flatnonzero(m5) + i1:
                dr = 1 if C[k] > hi else (-1 if C[k] < lo else 0)
                if dr and k + 1 < len(T):
                    out.append(dict(k=k + 1, d=dr, e=O[k + 1], sl=lo if dr == 1 else hi, fl=iF, stop_entry=False)); break
    return out


def setups_retest(df, sym, where):
    """Adam 2026-10-22 "instant retrace entry": after the first touch of an edge (as STOP), rest a limit at the broken
    edge (EDGE) or the box midpoint (MID) until 12:00. Buy limits fill on the ask, sell limits on the bid. SL = the
    opposite side. Added after the first 16 cells, so these 4 NAS100 cells are extra tests (20 in all)."""
    T = df.ny.values; O, H, L, S = (df[k].values for k in ("open", "high", "low", "spread"))
    sp = (S + MK.get(sym, 0)) * PT[sym]; out = []
    for s in setups(df, "STOP"):
        hi, lo = s["hi"], s["lo"]
        lim = (hi if s["d"] == 1 else lo) if where == "EDGE" else (hi + lo) / 2
        iN = np.searchsorted(T, pd.Timestamp(T[s["k"]]).normalize().to_datetime64() + np.timedelta64(12 * 60, "m"))
        for k in range(s["k"] + 1, iN):
            if s["d"] == 1 and L[k] + sp[k] <= lim:
                out.append(dict(k=k, d=1, e=min(lim, O[k] + sp[k]) - sp[k], sl=lo, fl=s["fl"], stop_entry=True, fill_bar=True)); break
            if s["d"] == -1 and H[k] >= lim:
                out.append(dict(k=k, d=-1, e=max(lim, O[k]), sl=hi, fl=s["fl"], stop_entry=True, fill_bar=True)); break
    return out


def run(df, sym, sets, rr, rng=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    pt = PT[sym]; mk = MK.get(sym, 0); rows = []
    for s in sets:
        k, d, e = s["k"], s["d"], s["e"]
        sld = abs(e - s["sl"])
        if sld <= 0 or s["fl"] <= k:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
        sp = (S[k] + mk) * pt
        if d == 1:
            e = e + sp                                   # buys fill on the ask
        sl = e - d * sld; tp = e + d * rr * sld
        if s.get("fill_bar") and ((L[k] <= sl) if d == 1 else (H[k] + sp >= sl)):
            rows.append((pd.Timestamp(T[k]).year, d, -1.0, sld)); continue   # limit filled and stopped on the same bar
        h = first_hit(H, L, O, S, k + (1 if s["stop_entry"] else 0), s["fl"], d, sl, tp, pt, mk)
        if h is None:
            m = s["fl"] - 1; px = C[m] + (0 if d == 1 else (S[m] + mk) * pt)
        else:
            px = h[1]
        rows.append((pd.Timestamp(T[k]).year, d, d * (px - e) / sld, sld))
    return pd.DataFrame(rows, columns=["year", "d", "R", "sl"])


if __name__ == "__main__" and os.environ.get("ORB_RETEST"):
    df = load("NAS100")
    for where in ("EDGE", "MID"):
        sets = setups_retest(df, "NAS100", where)
        for rr in (1, 2):
            real = run(df, "NAS100", sets, rr)
            rng = np.random.default_rng(20261022)
            coin = [run(df, "NAS100", sets, rr, rng).R.sum() for _ in range(SEEDS)]
            report(f"{where} {rr}R", real, coin)
            print(f"        long {real[real.d == 1].R.sum():+.1f}R  short {real[real.d == -1].R.sum():+.1f}R  median stop {real.sl.median():.4g}", flush=True)
elif __name__ == "__main__" and not os.environ.get("ORB_FADE"):
    res = []
    for sym in PT:
        df = load(sym)
        print(f"\n== {sym} ({df.ny.min():%Y-%m} to {df.ny.max():%Y-%m})", flush=True)
        for entry in ("STOP", "CLOSE"):
            sets = setups(df, entry)
            for rr in (1, 2):
                real = run(df, sym, sets, rr)
                rng = np.random.default_rng(20261022)
                coin = [run(df, sym, sets, rr, rng).R.sum() for _ in range(SEEDS)]
                r = report(f"{entry} {rr}R", real, coin)
                if len(r) and r["years"] < 7:          # short history (indices): 4 of 5 years is the bar
                    r["passed"] = r["pf"] > 1 and r["beats_coin"] >= 0.95 and r["years_pos"] >= r["years"] - 1
                    print(f"        short history -> {'PASS' if r['passed'] else 'fail'}", flush=True)
                print(f"        median stop {real.sl.median():.5g}", flush=True)
                res.append(dict(sym=sym, **r))
    pd.DataFrame(res).to_csv(os.path.join(DATA, "orb_930_box_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "orb_930_box_summary.csv"))


if __name__ == "__main__" and os.environ.get("ORB_FADE"):
    # Adam 2026-10-22: "force trade everyday ... trade opposite way". First touch of an edge -> enter the OTHER way at
    # that price, SL one box-height beyond the edge, TP 1R / 2R, flat 16:00. All 4 markets (8 more cells, 28 in all).
    for sym in PT:
        df = load(sym); base_sets = setups(df, "STOP")
        sets = [dict(s, d=-s["d"], sl=s["e"] + s["d"] * (s["hi"] - s["lo"])) for s in base_sets]
        days = pd.DatetimeIndex(df.ny.values).normalize().unique(); wd = (days.dayofweek < 5).sum()
        print(f"\n== {sym} FADE ({len(sets)} trades on {wd} weekdays)", flush=True)
        for rr in (1, 2):
            real = run(df, sym, sets, rr)
            rng = np.random.default_rng(20261022)
            coin = [run(df, sym, sets, rr, rng).R.sum() for _ in range(SEEDS)]
            report(f"FADE {rr}R", real, coin)
