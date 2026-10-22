"""Three entry types at the same zone (Adam's "Different types of entries" image, 2026-10-13). READ-ONLY, PRE-REGISTERED.
Zone = the broken edge of the gold Asia range after the first M5 close beyond it (gold_sniper_research.build_days).
All three share: SL = range midpoint, TP = measured move (edge +/- width) skipped if < 1R, flat 16:00 GMT, no entry after 15:00.
  LIMIT    : pending limit at the edge (filled on the first touch) = the existing retest sniper, re-run here as the reference.
  ENGULF   : first M5 bar that touches the edge AND engulfs the previous bar's body in the breakout direction
             (bull: bullish bar, prior bar bearish, close >= prior open, open <= prior close) -> next M5 open.
  STRUCTURE: after the first touch of the edge, pullback high = highest high of the 4 M5 bars ending at the touch;
             the first M5 close above it (bear: below the lowest low) within 12 bars -> next M5 open.
Exits on M1 with real spread +6 pt. Control: 50-seed coin flip. Pass bar = EA Scorecard.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gold_breakout_research import summ, report
import gold_sniper_research as sn
from gold_amd_confirm_research import resolve, MK, PTG


def make(m1, days):
    U = m1.utc.values; O1 = m1.open.values; S = m1.spread.values
    g = m1.set_index("utc").resample("5min", label="left", closed="left")
    m5 = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna().reset_index()
    T5 = m5.utc.values; O5, H5, L5, C5 = (m5[k].values for k in ("open", "high", "low", "close"))
    out = {"LIMIT": [], "ENGULF": [], "STRUCTURE": []}

    def add(name, s, k, ke, entry):
        d, hi, lo, w = s["d"], s["hi"], s["lo"], s["w"]
        edge = hi if d == 1 else lo
        risk = d * (entry - (hi + lo) / 2)
        tpR = d * ((edge + d * w) - entry) / risk if risk > 0 else 0
        if risk > 0 and tpR >= 1:
            out[name].append(dict(year=s["day"].year, d=d, k=k, ke=ke, entry=entry, risk=risk, tpR=tpR))

    for s in days:
        d, hi, lo = s["d"], s["hi"], s["lo"]
        edge = hi if d == 1 else lo
        b = int(np.searchsorted(T5, s["t_place"])) - 1
        e15 = int(np.searchsorted(T5, s["t_cancel"])); ke = int(np.searchsorted(U, s["t_close"]))
        touch = next((j for j in range(b + 1, e15) if (L5[j] <= edge if d == 1 else H5[j] >= edge)), None)
        if touch is None:
            continue
        # LIMIT: filled at the edge on the touch bar (M1 index of the first M1 bar that reaches the edge)
        k0 = int(np.searchsorted(U, T5[touch])); k1 = int(np.searchsorted(U, T5[touch] + np.timedelta64(5, "m")))
        L1, H1 = m1.low.values, m1.high.values
        kf = next((k for k in range(k0, k1) if (L1[k] <= edge if d == 1 else H1[k] + (S[k] + MK) * PTG >= edge)), None)
        if kf is not None and kf < ke - 1:
            add("LIMIT", s, kf, ke, edge + ((S[kf] + MK) * PTG if d == 1 else 0) * 0)  # limit fills at the edge (ask for buys)
        # ENGULF
        for j in range(max(touch, b + 2), e15):
            near = (L5[j] <= edge if d == 1 else H5[j] >= edge)
            if near and d * (C5[j] - O5[j]) > 0 and d * (C5[j - 1] - O5[j - 1]) < 0 and d * (C5[j] - O5[j - 1]) >= 0 and d * (O5[j] - C5[j - 1]) <= 0:
                k = int(np.searchsorted(U, T5[j] + np.timedelta64(5, "m")))
                if k < ke - 1:
                    add("ENGULF", s, k, ke, O1[k] + ((S[k] + MK) * PTG if d == 1 else 0))
                break
        # STRUCTURE
        lvl = H5[touch - 3:touch + 1].max() if d == 1 else L5[touch - 3:touch + 1].min()
        for j in range(touch + 1, min(touch + 13, e15)):
            if d * (C5[j] - lvl) > 0:
                k = int(np.searchsorted(U, T5[j] + np.timedelta64(5, "m")))
                if k < ke - 1:
                    add("STRUCTURE", s, k, ke, O1[k] + ((S[k] + MK) * PTG if d == 1 else 0))
                break
    return {n: pd.DataFrame(v) for n, v in out.items()}


if __name__ == "__main__":
    m1 = sn.prep(); days = sn.build_days(m1)
    for name, tr in make(m1, days).items():
        real = resolve(m1, tr); rng = np.random.default_rng(20261013)
        coin = [summ(resolve(m1, tr, rng))["tot"] for _ in range(50)]
        report(name, real, coin)
        print(f"    median target {tr.tpR.median():.2f}R", flush=True)
