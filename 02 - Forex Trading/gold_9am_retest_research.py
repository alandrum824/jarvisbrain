"""Adam's gold 9:00 AM candle model (2026-10-11): READ-ONLY replay on AAAFx M1 2020-01 -> 2026-10.

Adam: "Mark out first M15 candle, then switch to M5, wait for break and retest and enter targeting previous swing high."
His example: XAUUSD Thu 2026-10-08, long box entry 4133.24 (candle high), SL 4108.26 (candle low), TP 4194.09 (~2.4R),
a prior swing high. Rules as pre-declared before any result:
  1. Range = the 15-minute candle that opens at 09:00 (clocks tested: 09:00 NY, 09:30 NY = Trade with Pat's video, and
     09:00 Pacific = 12:00 NY, which is what Adam's two chart examples match).
  2. Break = the first M5 close beyond the range (above high -> long, below low -> short). Decides the day.
  3. Retest = a later M5 bar trades back to the broken edge; ENTRY when an M5 bar (that bar or a later one) closes back
     beyond the edge in the break direction -> market at the next M5 open.  (Variant LIMIT: buy limit at the edge, filled
     on M1 when touched.)
  4. Cancel: an M5 close back beyond the OTHER side of the range before entry, or no entry within 3 h of the range close.
  5. SL = the other side of the 15m candle (no buffer; spread is charged).
  6. TP = the previous swing high (long) / low (short): the nearest confirmed H1 fractal (2 bars each side) from the prior
     10 days that sits at least 1R beyond entry. No such level -> skip. Comparison column: fixed 2R.
  One trade per day, Mon-Fri, max hold 5 days (closed at market). Costs: bar spread + 6 pt live markup. SL first on ties.
Control: COIN = same entry times, same SL/TP distances, coin-flip direction (50 seeds).
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_momentum_longrun_research as base

PT, MK = 0.01, 6
SEEDS = 50


def h1_swings(df):
    h = df.set_index("ny").resample("1h").agg({"high": "max", "low": "min"}).dropna()
    H, L, T = h.high.values, h.low.values, h.index.values
    sh, sl = [], []
    for i in range(2, len(h) - 2):
        if H[i] > max(H[i - 2:i].max(), H[i + 1:i + 3].max()): sh.append((T[i + 2] + np.timedelta64(1, "h"), H[i]))  # known 2 bars later
        if L[i] < min(L[i - 2:i].min(), L[i + 1:i + 3].min()): sl.append((T[i + 2] + np.timedelta64(1, "h"), L[i]))
    return sh, sl


def target(swings, t_entry, entry, risk, d):
    best = None
    for known, p in swings:
        if known > t_entry or known < t_entry - np.timedelta64(10, "D"): continue
        if d * (p - entry) >= risk and (best is None or d * (p - best) < 0): best = p
    return best


def exit_trade(H, L, C, S, k, d, entry, sl, tp):
    end = min(len(H), k + 60 * 24 * 5)
    sp = (S[k:end] + MK) * PT
    if d > 0: slh = L[k:end] <= sl; tph = H[k:end] >= tp
    else: slh = H[k:end] + sp >= sl; tph = L[k:end] + sp <= tp
    hit = np.flatnonzero(slh | tph)
    if not len(hit): return C[end - 1] + (0 if d > 0 else (S[end - 1] + MK) * PT)
    return sl if slh[hit[0]] else tp


_M5 = {}


def run(df, swings, start_hm, mode="confirm", tpmode="swing", coin=None, fixed=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    if id(df) not in _M5:
        _M5[id(df)] = df.set_index("ny").resample("5min").agg({"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
    m5 = _M5[id(df)]
    t5 = m5.index.values; O5, H5, L5, C5 = m5.open.values, m5.high.values, m5.low.values, m5.close.values
    out = []; busy = np.datetime64("1970-01-01")
    entries = fixed if fixed is not None else None
    days = pd.date_range(pd.Timestamp(T[0]).normalize(), pd.Timestamp(T[-1]).normalize(), freq="D")
    for day in days:
        if day.dayofweek >= 5: continue
        rs = np.datetime64(day + pd.Timedelta(hours=start_hm[0], minutes=start_hm[1])); re_ = rs + np.timedelta64(15, "m")
        if rs < busy: continue
        i0, i1 = np.searchsorted(T, rs), np.searchsorted(T, re_)
        if i1 - i0 < 10: continue
        hi, lo = H[i0:i1].max(), L[i0:i1].min(); risk0 = hi - lo
        if risk0 <= 0: continue
        j = np.searchsorted(t5, re_); jend = np.searchsorted(t5, re_ + np.timedelta64(3, "h"))
        d = 0; touched = False; ent = None
        for q in range(j, min(jend, len(t5) - 1)):
            if d == 0:
                if C5[q] > hi: d = 1
                elif C5[q] < lo: d = -1
                continue
            edge, far = (hi, lo) if d > 0 else (lo, hi)
            if d * (C5[q] - far) < 0: break                       # closed back through the other side
            if not touched and ((L5[q] <= edge) if d > 0 else (H5[q] >= edge)): touched = True
            if touched:
                if mode == "limit":
                    k0 = np.searchsorted(T, t5[q]); k1 = np.searchsorted(T, t5[q] + np.timedelta64(5, "m"))
                    hitm = np.flatnonzero((L[k0:k1] <= edge) if d > 0 else (H[k0:k1] >= edge))
                    if not len(hitm): break
                    ent = (k0 + hitm[0], edge); break
                if d * (C5[q] - edge) > 0:
                    k = np.searchsorted(T, t5[q + 1]); ent = (k, O[k] + ((S[k] + MK) * PT if d > 0 else 0)); break
        if ent is None: continue
        k, e = ent
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        sl = (lo if dd > 0 else hi) if coin is None else e - dd * abs(e - (lo if d > 0 else hi))
        risk = dd * (e - sl)
        if risk <= 0: continue
        if tpmode == "2R": tp = e + dd * 2 * risk
        else:
            sw = swings[0] if dd > 0 else swings[1]
            tp = target(sw, T[k], e, risk, dd)
            if tp is None: continue
        px = exit_trade(H, L, C, S, k, dd, e, sl, tp)
        cost = 0 if mode == "confirm" else (S[k] + MK) * PT
        out.append((pd.Timestamp(T[k]), dd, (dd * (px - e) - cost) / risk, dd * (tp - e) / risk))
        busy = T[min(len(T) - 1, k + 60)]
    return pd.DataFrame(out, columns=["time", "d", "R", "tpR"])


if __name__ == "__main__":
    df = base.load("XAUUSD"); sw = h1_swings(df)
    CELLS = sys.argv[1].split(",") if len(sys.argv) > 1 else ["0900", "0930", "1200"]
    ALL = {"0900": ("9:00 New York", (9, 0)), "0930": ("9:30 New York (Pat)", (9, 30)), "1200": ("9:00 Pacific (12:00 NY)", (12, 0))}
    for lab, hm in (ALL[c] for c in CELLS):
        for mode in ("confirm", "limit"):
            for tpm in ("swing", "2R"):
                r = run(df, sw, hm, mode, tpm)
                if r.empty: print(lab, mode, tpm, "no trades"); continue
                ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
                rng = np.random.default_rng(20261011)
                coins = np.array([run(df, sw, hm, mode, tpm, coin=rng).R.sum() for _ in range(SEEDS)]) if (mode == "confirm") else np.array([np.nan])
                bt = (coins < r.R.sum()).mean() if mode == "confirm" else float("nan")
                print(f"{lab:24s} {mode:7s} TP {tpm:5s}: {len(r)} tr, {r.R.sum():+.1f}R, {r.R.mean():+.3f}R/tr, PF {pf:.2f}, win {(r.R > 0).mean():.0%}, "
                      f"median TP {r.tpR.median():.1f}R, years+ {int((ys > 0).sum())}/{len(ys)}" + (f", beats coin {bt:.0%}" if mode == "confirm" else ""), flush=True)
                print("      " + "  ".join(f"{y}:{v:+.1f}" for y, v in ys.items()), flush=True)
                if hm == (12, 0) and mode == "confirm" and tpm == "swing":
                    r.to_csv(r"C:\Users\aland\stg\obh\gold_9am_pacific_trades.csv", index=False)
