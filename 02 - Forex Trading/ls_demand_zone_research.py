"""Liquidity Sweep Demand Zone - the @Prop-Firm-Trader diagram Adam sent 2026-10-11. READ-ONLY replay, AAAFx M1 2020-01 -> 2026-10.

Rules, pre-declared before any result (long; short is the exact mirror):
  1. Swings = confirmed pivots (P bars each side; P=3 primary, 5 as a check). Bars = M5 or M15 built from M1 (NY clock).
  2. BOS: a close above the last confirmed swing high. The lowest low between that swing high and the BOS bar is the
     higher low; it must sit above the swing low before that swing high (higher high + higher low = uptrend).
     Demand zone = that higher-low candle, low to high. A zone only exists once the break happened ("not valid" before).
  3. Liquidity: after the BOS, a confirmed swing low that sits ABOVE the zone top (the consolidation lows above the zone).
     Several -> the lowest of them. Trigger line = highest high from that swing low's bar until the sweep.
  4. Sweep: a low below the liquidity level. Tap: a low at or below the zone top (same bar allowed).
  5. Entry: after the tap, the first close back above the trigger line -> market at the next bar open (M1 open + cost).
  6. Kill: a close below the zone bottom; 48 bars after the sweep with no entry; a new BOS replaces the setup.
  7. SL = zone bottom. TP = the high made after the BOS (the peak), must be >= 1R else skipped; comparison: fixed 2R.
  One position at a time, max hold 2 days, SL first on ties, cost = bar spread + 6 pt markup (paid once at entry).
Control: COIN = same entry times, same SL distance, same R target, coin-flip direction (50 seeds).
Pass bar (pre-registered): positive in >= 5 of 7 years, PF >= 1.15, beats >= 95% of coin runs.
"""
import os, sys
import bisect
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_momentum_longrun_research as base

PT, MK, SEEDS, KILL, HOLD = 0.01, 6, 50, 48, 60 * 24 * 2


def bars(df, tf):
    b = df.set_index("ny").resample(tf, label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
    return b.index.values, b.open.values, b.high.values, b.low.values, b.close.values


def setups(tf_bars, P):
    """Return a list of (bar_index_of_entry_signal, dir, zone_far_edge, peak). Entry is at the next bar's open."""
    t, O, H, L, C = tf_bars
    n = len(t); out = []
    ph, pl = [], []                      # confirmed pivots: (bar, price)
    phb, plb = [], []                    # their bars, for bisect
    used = {1: set(), -1: set()}         # swing already broken once -> no second BOS off it
    st = {1: None, -1: None}             # active setup per direction
    for i in range(n):
        c = i - P                         # pivot candidate confirmed at bar i
        if c >= P:
            if H[c] == H[c - P:c + P + 1].max() and H[c] > H[c - P:c].max(): ph.append((c, H[c])); phb.append(c)
            if L[c] == L[c - P:c + P + 1].min() and L[c] < L[c - P:c].min(): pl.append((c, L[c])); plb.append(c)
        # ---- BOS up / down -> new setup
        if ph and len(pl) >= 1:
            hb, hp = ph[-1]
            if C[i] > hp and hb not in used[1]:
                used[1].add(hb); q = bisect.bisect_left(plb, hb)
                if q > 0 and i > hb + 1:
                    k = hb + int(np.argmin(L[hb:i + 1]))
                    if L[k] > pl[q - 1][1]:
                        st[1] = dict(bos_ref=hb, bos=i, zt=H[k], zb=L[k], peak=H[i], liq=None, lb=None, trig=None,
                                     sweep=None, tap=False)
        if pl and len(ph) >= 1:
            lb_, lp = pl[-1]
            if C[i] < lp and lb_ not in used[-1]:
                used[-1].add(lb_); q = bisect.bisect_left(phb, lb_)
                if q > 0 and i > lb_ + 1:
                    k = lb_ + int(np.argmax(H[lb_:i + 1]))
                    if H[k] < ph[q - 1][1]:
                        st[-1] = dict(bos_ref=lb_, bos=i, zt=L[k], zb=H[k], peak=L[i], liq=None, lb=None, trig=None,
                                      sweep=None, tap=False)
        # ---- advance each setup
        for d in (1, -1):
            s = st[d]
            if s is None or i <= s["bos"]: continue
            hi, lo, cl = (H[i], L[i], C[i]) if d > 0 else (-L[i], -H[i], -C[i])
            zt, zb = (s["zt"], s["zb"]) if d > 0 else (-s["zt"], -s["zb"])
            if cl < zb: st[d] = None; continue                                   # zone broken
            if s["sweep"] is None:
                s["peak"] = max(s["peak"], H[i]) if d > 0 else min(s["peak"], L[i])
                piv = pl if d > 0 else ph
                if piv and piv[-1][0] > s["bos"]:
                    pb, pp = piv[-1]; ppn = pp if d > 0 else -pp
                    if ppn > zt and (s["liq"] is None or ppn < s["liq"]):
                        s["liq"], s["lb"] = ppn, pb
                if s["liq"] is not None:
                    seg = H[s["lb"]:i] if d > 0 else -L[s["lb"]:i]
                    s["trig"] = seg.max() if len(seg) else None
                    if lo < s["liq"] and s["trig"] is not None:
                        s["sweep"] = i
            if s["sweep"] is not None:
                if i - s["sweep"] > KILL: st[d] = None; continue
                if lo <= zt: s["tap"] = True
                if s["tap"] and cl > s["trig"] and i + 1 < n:
                    out.append((i, d, s["zb"], s["peak"]))
                    st[d] = None
    return out


def simulate(df, tfb, sig, tpmode, coin=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    t = tfb[0]; res = []; busy = -1
    for i, d, far, peak in sig:
        k = np.searchsorted(T, t[i + 1])
        if k >= len(T) or k <= busy: continue
        cost = (S[k] + MK) * PT
        e = O[k] + (cost if d > 0 else 0)
        risk = d * (e - far)
        if risk <= 0: continue
        tpR = 2.0 if tpmode == "2R" else d * (peak - e) / risk
        if tpR < 1.0: continue
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        e2 = O[k] + (cost if dd > 0 else 0)
        sl = e2 - dd * risk; tp = e2 + dd * tpR * risk
        end = min(len(T), k + HOLD)
        sp = (S[k:end] + MK) * PT
        if dd > 0: slh = L[k:end] <= sl; tph = H[k:end] >= tp
        else: slh = H[k:end] + sp >= sl; tph = L[k:end] + sp <= tp
        hit = np.flatnonzero(slh | tph)
        if len(hit): px = sl if slh[hit[0]] else tp; j = k + hit[0]
        else: j = end - 1; px = C[j] + (0 if dd > 0 else sp[-1])
        res.append((pd.Timestamp(T[k]), dd, dd * (px - e2) / risk, tpR))
        busy = j
    return pd.DataFrame(res, columns=["time", "d", "R", "tpR"])


if __name__ == "__main__":
    df = base.load("XAUUSD")
    for tf in ("5min", "15min"):
        tfb = bars(df, tf)
        for P in (3, 5):
            sig = setups(tfb, P)
            for tpm in ("peak", "2R"):
                r = simulate(df, tfb, sig, tpm)
                if r.empty: print(tf, P, tpm, "no trades", flush=True); continue
                ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
                rng = np.random.default_rng(20261011)
                coins = np.array([simulate(df, tfb, sig, tpm, coin=rng).R.sum() for _ in range(SEEDS)])
                ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
                print(f"{tf:5s} P{P} TP {tpm:4s}: {len(r)} tr, {r.R.sum():+.1f}R, {r.R.mean():+.3f}R/tr, PF {pf:.2f}, "
                      f"win {(r.R > 0).mean():.0%}, median TP {r.tpR.median():.1f}R, longs {(r.d > 0).mean():.0%}, "
                      f"years+ {int((ys > 0).sum())}/{len(ys)}, beats coin {(coins < r.R.sum()).mean():.0%} -> {'PASS' if ok else 'fail'}", flush=True)
                print("      " + "  ".join(f"{y}:{v:+.1f}" for y, v in ys.items()), flush=True)
                if tf == "5min" and P == 3 and tpm == "peak":
                    r.to_csv(r"C:\Users\aland\stg\obh\ls_dz_XAUUSD_trades.csv", index=False)
