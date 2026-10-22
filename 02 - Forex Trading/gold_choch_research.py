"""Gold CHoCH -> BOS -> pullback entry (Adam's market-structure screenshots, 2026-10-12). READ-ONLY replay.

The lesson Adam sent: swing highs/lows define trend; a BOS takes out a prior swing WITH the trend; a CHoCH breaks the key
swing AGAINST it; the entry (last image) is the pullback lower high after the CHoCH and the follow-through BOS.
Rules PRE-REGISTERED, nothing tuned:
  Swings: confirmed fractal pivots, 3 bars each side (known 3 bars after the pivot; no look-ahead).
  Bear setup (bull = mirror):
    1. Uptrend: the last two swing highs rising AND the last two swing lows rising.
    2. CHoCH: a close below the last swing low (the HL).
    3. A lower high forms (a confirmed swing high below the pre-CHoCH high).
    4. BOS: a close below the lowest low since the CHoCH.
    5. Entry: the next confirmed swing high (the pullback) that is below that lower high -> SELL at the next bar open.
       Invalidated (reset) if any close goes above the lower high first.
  SL = the pullback swing high + 0.1 ATR(14), at least max(0.5 ATR, 5 x spread); skipped if > 3 ATR. TP = 2R.
  Entries 03:00-15:00 New York, Mon-Fri; flat 16:50 NY; one trade at a time. Exits resolved on M1, real spread +6 pts.
Cells: M5 and M15 signal timeframes (BOTH directions; long/short shown). Control: 50-seed coin flip.
Pass bar (EA Scorecard): >= 5/7 years, PF > 1, beats >= 95% of coin.
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe gold_choch_research.py
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from orb_momentum_longrun_research import load, PT
from pullback_scalper_research import bars, atr_rma, first_hit
from gold_breakout_research import summ, report

K = 3; MK = 6; SEEDS = 50


def signals(b):
    O, H, L, C = (b[k].values for k in ("open", "high", "low", "close"))
    A = atr_rma(H, L, C); t = pd.DatetimeIndex(b.ny.values)
    mins = t.hour * 60 + t.minute; dow = t.dayofweek
    highs, lows = [], []                  # confirmed swings: (index, price)
    st = {1: None, -1: None}              # per direction setup state
    sig = []
    for j in range(2 * K + 1, len(b) - 1):
        p = j - K                          # pivot candidate confirmed at bar j
        if H[p] > H[p - K:p].max() and H[p] >= H[p + 1:j + 1].max():
            highs.append((p, H[p])); newH = True
        else:
            newH = False
        if L[p] < L[p - K:p].min() and L[p] <= L[p + 1:j + 1].min():
            lows.append((p, L[p])); newL = True
        else:
            newL = False
        for d in (-1, 1):                  # -1 = bear setup (sell), 1 = bull setup (buy)
            s = st[d]
            # mirror helpers: for a bear setup the "trend swings" are the up-trend's highs/lows
            sw_ext, sw_key = (highs, lows) if d == -1 else (lows, highs)
            if s is None:
                if len(sw_ext) >= 2 and len(sw_key) >= 2:
                    trend_ok = (sw_ext[-1][1] > sw_ext[-2][1] and sw_key[-1][1] > sw_key[-2][1]) if d == -1 else \
                               (sw_ext[-1][1] < sw_ext[-2][1] and sw_key[-1][1] < sw_key[-2][1])
                    if trend_ok and d * (C[j] - sw_key[-1][1]) > 0 and d * (C[j - 1] - sw_key[-1][1]) <= 0:
                        st[d] = dict(stage="choch", ref=sw_ext[-1][1], ext=(L[j] if d == -1 else H[j]), since=j)
                continue
            # running extreme since the CHoCH (lowest low for a bear setup)
            if s["stage"] == "choch":
                s["ext"] = min(s["ext"], L[j]) if d == -1 else max(s["ext"], H[j])
                newP = newH if d == -1 else newL
                piv = H[p] if d == -1 else L[p]
                if newP and p > s["since"] and d * (piv - s["ref"]) > 0:
                    s.update(stage="lh", lh=piv)
                elif d * (C[j] - s["ref"]) < 0:          # closed back beyond the old extreme: setup dead
                    st[d] = None
                continue
            if d * (C[j] - s["lh"]) < 0:                # close beyond the lower high (bear: above it) -> reset
                st[d] = None; continue
            if s["stage"] == "lh":
                if d * (C[j] - s["ext"]) > 0:           # bear: close below the lowest low since CHoCH = BOS
                    s.update(stage="bos", bos_at=j)
                else:
                    s["ext"] = min(s["ext"], L[j]) if d == -1 else max(s["ext"], H[j])
                continue
            if s["stage"] == "bos":
                newP = newH if d == -1 else newL
                piv = H[p] if d == -1 else L[p]
                if newP and p > s["bos_at"] - K and d * (piv - s["lh"]) > 0:
                    if A[j] > 0 and dow[j] < 5 and 180 <= mins[j] < 900:
                        sig.append(dict(j=j, d=d, stop=piv, atr=A[j], t_entry=b.ny.values[j + 1], year=t[j].year))
                    st[d] = None
    return sig


def run(m1, sig, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    T = m1.ny.values; pt = PT["XAUUSD"]
    rows = []; busy = -1
    for s in sig:
        k = int(np.searchsorted(T, s["t_entry"]))
        if k >= len(T) or k <= busy:
            continue
        d = s["d"]; a = s["atr"]; sp = (S[k] + MK) * pt
        entry = O[k] + (sp if d == 1 else 0)
        risk = max(d * (entry - (s["stop"] - d * 0.1 * a)), 0.5 * a, 5 * sp)
        if risk > 3 * a:
            continue
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            entry = O[k] + (sp if d == 1 else 0)
        sl = entry - d * risk; tp = entry + d * 2 * risk
        day = pd.Timestamp(T[k]).normalize()
        end = int(np.searchsorted(T, (day + pd.Timedelta(hours=16, minutes=50)).to_datetime64()))
        if end <= k:
            continue
        h = first_hit(H, L, O, S, k, end, d, sl, tp, pt, MK)
        if h is None:
            m = end - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * pt)
        else:
            m, px = h
        busy = m
        rows.append((s["year"], d, d * (px - entry) / risk))
    return pd.DataFrame(rows, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = load("XAUUSD")
    out = []
    for tf in ("5min", "15min"):
        b = bars(m1, tf)
        sig = signals(b)
        real = run(m1, sig)
        rng = np.random.default_rng(20261012)
        coin = [summ(run(m1, sig, rng))["tot"] for _ in range(SEEDS)]
        print(f"##### {tf}: {len(sig)} setups", flush=True)
        out.append(report(f"CHOCH {tf}", real, coin))
        for d, n in ((1, "LONG"), (-1, "SHORT")):
            x = real[real.d == d]; s = summ(x)
            print(f"    {n}: {s['n']} tr {s['tot']:+.1f}R PF {s['pf']:.2f} win {s['win']:.0%}", flush=True)
    pd.DataFrame(out).to_csv(r"C:\Users\aland\stg\obh\gold_choch_summary.csv", index=False)
    print("saved")
