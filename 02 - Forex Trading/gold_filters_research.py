"""Adam's filters on the proven gold Asia breakout: FVG momentum, structure trend (zones/trendlines), room to the next zone.

Adam 2026-10-13: "we can use zones and tread lines to help determine trend we can use fvg to realize price has real
momentum to leave an fvg keep studying and make it better". READ-ONLY replay, PRE-REGISTERED:
  Base (REF): Asia range 00-05 GMT (ATR filter 0.10-0.80), first M5 CLOSE beyond the range before 15:00 -> enter at the
    next M5 open in that direction; SL = other side of the range -/+ 5% width; TP = 1R; flat 16:00 GMT.
  Filters (each keeps a subset of REF trades):
    FVG     : the breakout bar leaves a fair value gap in the trade direction (bull: low[b] > high[b-2]) = displacement.
    H1TREND : H1 structure agrees: last two confirmed H1 swing highs AND lows rising (buy) / falling (sell); 3/3 fractals.
    H4TREND : same on H4.
    ROOM    : no confirmed H1 swing high (buy) / swing low (sell) of the last 120 H1 bars sitting between entry and 1R
              (i.e. no opposing zone in the way of the target).
    FVG+H1  : FVG and H1TREND together.
  Controls: COIN (same trades, random direction, 50 seeds) and SKIP (keep the same NUMBER of REF trades chosen at
  random, 50 seeds) - a filter must beat >= 95% of random skips on total R to count as adding information.
  Pass bar: >= 5/7 years, PF > 1, beats >= 95% of COIN and >= 95% of SKIP.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pullback_scalper_research import first_hit
from gold_breakout_research import summ, report, atr_rma
import gold_sniper_research as sn

MK = 6; PTG = 0.01; SEEDS = 50


def swings(H, L, k=3):
    n = len(H); sh = np.zeros(n, bool); sl = np.zeros(n, bool)
    for i in range(k, n - k):
        if H[i] > H[i - k:i].max() and H[i] >= H[i + 1:i + k + 1].max(): sh[i] = True
        if L[i] < L[i - k:i].min() and L[i] <= L[i + 1:i + k + 1].min(): sl[i] = True
    return sh, sl


def tf_bars(m1, rule):
    g = m1.set_index("utc").resample(rule, label="left", closed="left")
    b = pd.DataFrame({"high": g.high.max(), "low": g.low.min()}).dropna().reset_index()
    sh, sl = swings(b.high.values, b.low.values)
    return b, sh, sl, pd.Timedelta(rule)


def trend_at(tb, t, k=3):
    """structure trend using swings confirmed (k bars after the pivot closed) before time t."""
    b, sh, sl, dur = tb
    T = b.utc.values
    last = int(np.searchsorted(T, (pd.Timestamp(t) - dur * (k + 1)).to_datetime64(), side="right")) - 1
    if last < 10:
        return 0, None, None
    ih = np.flatnonzero(sh[:last + 1])[-2:]; il = np.flatnonzero(sl[:last + 1])[-2:]
    if len(ih) < 2 or len(il) < 2:
        return 0, ih, il
    H, L = b.high.values, b.low.values
    if H[ih[1]] > H[ih[0]] and L[il[1]] > L[il[0]]: return 1, ih, il
    if H[ih[1]] < H[ih[0]] and L[il[1]] < L[il[0]]: return -1, ih, il
    return 0, ih, il


def build(m1, days):
    U = m1.utc.values; O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    g5 = m1.set_index("utc").resample("5min", label="left", closed="left")
    m5 = pd.DataFrame({"high": g5.high.max(), "low": g5.low.min()}).dropna().reset_index()
    T5, H5, L5 = m5.utc.values, m5.high.values, m5.low.values
    h1 = tf_bars(m1, "1h"); h4 = tf_bars(m1, "4h")
    rows = []
    for s in days:
        d = s["d"]; k = int(np.searchsorted(U, s["t_place"])); ke = int(np.searchsorted(U, s["t_close"]))
        if k >= ke - 1:
            continue
        sp = (S[k] + MK) * PTG
        entry = O[k] + (sp if d == 1 else 0)
        stop = (s["lo"] - 0.05 * s["w"]) if d == 1 else (s["hi"] + 0.05 * s["w"])
        risk = d * (entry - stop)
        if risk <= 0:
            continue
        b = int(np.searchsorted(T5, s["t_place"])) - 1              # breakout M5 bar
        fvg = (L5[b] > H5[b - 2]) if d == 1 else (H5[b] < L5[b - 2])
        tr1, ih, il = trend_at(h1, s["t_place"]); tr4, _, _ = trend_at(h4, s["t_place"])
        # ROOM: any confirmed H1 swing high (buy) / low (sell) in the last 120 H1 bars between entry and 1R target
        hb, hsh, hsl, dur = h1
        last = int(np.searchsorted(hb.utc.values, (pd.Timestamp(s["t_place"]) - dur * 4).to_datetime64(), side="right")) - 1
        lo_i = max(0, last - 120)
        if d == 1:
            lv = hb.high.values[lo_i:last + 1][hsh[lo_i:last + 1]]
            blocked = ((lv > entry) & (lv < entry + risk)).any()
        else:
            lv = hb.low.values[lo_i:last + 1][hsl[lo_i:last + 1]]
            blocked = ((lv < entry) & (lv > entry - risk)).any()
        rows.append(dict(year=s["day"].year, d=d, k=k, ke=ke, entry=entry, risk=risk,
                         FVG=bool(fvg), H1TREND=(tr1 == d), H4TREND=(tr4 == d), ROOM=not blocked))
    return pd.DataFrame(rows)


def resolve(m1, tr, rng=None):
    O, H, L, C, S = (m1[k].values for k in ("open", "high", "low", "close", "spread"))
    out = []
    for r in tr.itertuples():
        d = r.d; entry = r.entry
        if rng is not None:
            d = 1 if rng.random() < 0.5 else -1
            entry = O[r.k] + ((S[r.k] + MK) * PTG if d == 1 else 0)
        sl = entry - d * r.risk; tp = entry + d * r.risk
        h = first_hit(H, L, O, S, r.k, r.ke, d, sl, tp, PTG, MK)
        if h is None:
            m = r.ke - 1; px = C[m] + (0 if d == 1 else (S[m] + MK) * PTG)
        else:
            m, px = h
        out.append((r.year, d, d * (px - entry) / r.risk))
    return pd.DataFrame(out, columns=["year", "d", "R"])


if __name__ == "__main__":
    m1 = sn.prep(); days = sn.build_days(m1)
    tr = build(m1, days)
    ref = resolve(m1, tr)
    tr = tr.assign(R=ref.R.values)
    print(f"REF trades {len(tr)}; filter pass rates: " + ", ".join(f"{c} {tr[c].mean():.0%}" for c in ("FVG", "H1TREND", "H4TREND", "ROOM")), flush=True)
    cells = {"REF": np.ones(len(tr), bool), "FVG": tr.FVG.values, "H1TREND": tr.H1TREND.values, "H4TREND": tr.H4TREND.values,
             "ROOM": tr.ROOM.values, "FVG+H1": (tr.FVG & tr.H1TREND).values}
    for name, mask in cells.items():
        sub = tr[mask]
        real = sub[["year", "d", "R"]]
        rng = np.random.default_rng(20261013)
        coin = [summ(resolve(m1, sub, rng))["tot"] for _ in range(SEEDS)]
        print(f"##### {name}: keeps {mask.sum()} of {len(tr)} ({mask.mean():.0%}), avg {real.R.mean():+.3f}R vs REF {tr.R.mean():+.3f}R", flush=True)
        row = report(name, real, coin)
        if name != "REF":
            rs = np.random.default_rng(7)
            skip = [tr.R.values[rs.choice(len(tr), mask.sum(), replace=False)].sum() for _ in range(SEEDS)]
            bs = (np.array(skip) < real.R.sum()).mean()
            print(f"    SKIP control: random keep-{mask.sum()} median {np.median(skip):+.1f}R, filter beats {bs:.0%} "
                  f"-> {'ADDS INFO' if bs >= 0.95 else 'no better than random skipping'}", flush=True)
