"""Trade with Pat "15 Minute ORB" (youtu.be/deymRD3kSD0) - the strength-based pullback entry. READ-ONLY replay.

Pre-declared rules (2026-10-11, before any result):
  Range = the 09:30-09:45 New York 15-minute candle. Break = first M5 CLOSE beyond it (decides the day).
  Strength = how far that close sits beyond the edge, as a fraction of the range size:
     strong >= 0.5 -> buy limit at the range high | medium 0.2-0.5 -> at the midline |
     weak < 0.2 -> at the demand zone: the last bearish M5 candle between the range start and the breakout whose body top
     is at/below the midline (its body top = the limit); none -> the range low.
  SL = below the lower of the range low and the demand-zone low, minus 0.10 x range size. TP = the recent swing high:
     nearest confirmed H1 fractal (2/2) from the prior 10 days at least 1R beyond the entry; none -> skip.
  Cancel: no fill by 12:00 NY, or an M5 close back beyond the far side of the range before the fill.
  Fill on M1 (strict: the fill bar can stop out). One trade per day, max hold 5 days. Shorts mirror. Spread charged
  (gold +6 pt markup). Control: COIN = same fills/times/distances, coin-flip direction (50 seeds).
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_momentum_longrun_research as base
from gold_9am_retest_research import h1_swings, target

SPEC = {"XAUUSD": (0.01, 6), "NAS100": (0.1, 0)}
SEEDS = 50


def run(df, sw, sym, coin=None, M5=None):
    pt, mk = SPEC[sym]
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    t5, O5, H5, L5, C5 = M5
    out = []; busy = np.datetime64("1970-01-01"); stats = {"strong": 0, "medium": 0, "weak": 0}
    for day in pd.date_range(pd.Timestamp(T[0]).normalize(), pd.Timestamp(T[-1]).normalize(), freq="D"):
        if day.dayofweek >= 5: continue
        rs = np.datetime64(day + pd.Timedelta(hours=9, minutes=30)); re_ = rs + np.timedelta64(15, "m"); cut = np.datetime64(day + pd.Timedelta(hours=12))
        if rs < busy: continue
        i0, i1 = np.searchsorted(T, rs), np.searchsorted(T, re_)
        if i1 - i0 < 10: continue
        hi, lo = H[i0:i1].max(), L[i0:i1].min(); size = hi - lo; mid = (hi + lo) / 2
        if size <= 0: continue
        j0 = np.searchsorted(t5, rs); j = np.searchsorted(t5, re_); jc = np.searchsorted(t5, cut)
        d = 0; qb = None
        for q in range(j, jc):
            if C5[q] > hi: d, qb = 1, q; break
            if C5[q] < lo: d, qb = -1, q; break
        if d == 0: continue
        ext = d * (C5[qb] - (hi if d > 0 else lo)) / size
        kind = "strong" if ext >= 0.5 else "medium" if ext >= 0.2 else "weak"
        zlow = lo if d > 0 else hi
        if kind == "strong": lim = hi if d > 0 else lo
        elif kind == "medium": lim = mid
        else:
            lim = zlow
            for q in range(qb - 1, j0 - 1, -1):
                bt = max(O5[q], C5[q]) if d > 0 else min(O5[q], C5[q])
                if d * (C5[q] - O5[q]) < 0 and d * (bt - mid) <= 0:
                    lim = bt; zlow = min(lo, L5[q]) if d > 0 else max(hi, H5[q]); break
        sl = (min(lo, zlow) - 0.10 * size) if d > 0 else (max(hi, zlow) + 0.10 * size)
        # wait for the fill on M1 until the cut-off; cancel on an M5 close beyond the far side
        k0 = np.searchsorted(T, t5[qb] + np.timedelta64(5, "m")); kc = np.searchsorted(T, cut)
        far = lo if d > 0 else hi; k = None
        for kk in range(k0, kc):
            if (L[kk] <= lim) if d > 0 else (H[kk] + (S[kk] + mk) * pt >= lim): k = kk; break
            if T[kk].astype("datetime64[m]").astype(int) % 5 == 4 and d * (C[kk] - far) < 0: break
        if k is None: continue
        stats[kind] += 1
        e = lim; dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        risk = abs(e - sl); slp = e - dd * risk
        tp = target(sw[0] if dd > 0 else sw[1], T[k], e, risk, dd)
        if tp is None: continue
        end = min(len(T), k + 60 * 24 * 5); sp = (S[k:end] + mk) * pt
        slh = (L[k:end] <= slp) if dd > 0 else (H[k:end] + sp >= slp)
        tph = (H[k:end] >= tp) if dd > 0 else (L[k:end] + sp <= tp)
        tph[0] = False
        hit = np.flatnonzero(slh | tph)
        px = (slp if slh[hit[0]] else tp) if len(hit) else C[end - 1]
        cost = (S[k] + mk) * pt if dd > 0 else 0
        out.append((pd.Timestamp(T[k]), dd, kind, (dd * (px - e) - cost) / risk, dd * (tp - e) / risk))
        busy = T[min(len(T) - 1, (k + hit[0]) if len(hit) else end - 1)]
    return pd.DataFrame(out, columns=["time", "d", "kind", "R", "tpR"]), stats


if __name__ == "__main__":
    for sym in SPEC:
        df = base.load(sym); sw = h1_swings(df)
        m5 = df.set_index("ny").resample("5min").agg({"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
        M5 = (m5.index.values, m5.open.values, m5.high.values, m5.low.values, m5.close.values)
        r, st = run(df, sw, sym, M5=M5)
        ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
        rng = np.random.default_rng(20261011)
        coins = np.array([run(df, sw, sym, coin=rng, M5=M5)[0].R.sum() for _ in range(SEEDS)])
        print(f"{sym} Pat 9:30 strength entry: {len(r)} tr from {r.time.min():%Y-%m}, {r.R.sum():+.1f}R, {r.R.mean():+.3f}R/tr, PF {pf:.2f}, "
              f"win {(r.R > 0).mean():.0%}, median TP {r.tpR.median():.1f}R, years+ {int((ys > 0).sum())}/{len(ys)}, "
              f"coin median {np.median(coins):+.1f}R, beats {(coins < r.R.sum()).mean():.0%} | fills {st}", flush=True)
        print("      " + "  ".join(f"{y}:{v:+.1f}" for y, v in ys.items()))
        for kd in ("strong", "medium", "weak"):
            x = r[r.kind == kd]
            if len(x): print(f"      {kd:6s}: {len(x)} tr, {x.R.sum():+.1f}R, {x.R.mean():+.3f}R/tr, win {(x.R > 0).mean():.0%}", flush=True)
        r.to_csv(rf"C:\Users\aland\stg\obh\pat_strength_{sym}_trades.csv", index=False)
