"""Roboquant "ORB FINAL" template (Rust, pasted by Adam 2026-10-22). READ-ONLY replay of its rules, not its code.
Template defaults: 09:30-09:45 box on M1; after 09:45 the first M1 CLOSE beyond the box arms a LIMIT at the broken
edge; SL = opposite side, TP = 1R; no entry cut-off and no session flat: the limit and the trade live until the next
session open (09:30), where everything is cancelled/closed. (Its fixed UTC start is a DST bug; this replay uses NY time.)
Cells: AS_CODED (hold to next open) and DISCIPLINED (entries to 12:00, flat 15:59) x TP 1R / 2R / none; NAS100 + gold.
Same pass bar and costs as orb_family_research (buy limits fill on the ask, fill bar can stop out, SL first on ties).
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_family_research as F

SEEDS = 50


def signals(df, s, disciplined):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    sp = (S + F.MK.get(F.SYM, 0)) * F.PT[F.SYM]; out = []
    starts = s.i0.values
    for n, r in enumerate(s.itertuples()):
        i1 = r.i0 + 15
        hi = H[r.i0:i1].max(); lo = L[r.i0:i1].min()
        if hi <= lo:
            continue
        nxt = starts[n + 1] if n + 1 < len(starts) else len(T) - 1
        endE = r.iN if disciplined else nxt          # arming / fill window
        fl = r.iF if disciplined else nxt            # forced exit
        a = np.flatnonzero((C[i1:endE] > hi) | (C[i1:endE] < lo))
        if not len(a):
            continue
        k = i1 + a[0]; d = 1 if C[k] > hi else -1
        for j in range(k + 1, endE):
            if d == 1 and L[j] + sp[j] <= hi:
                out.append(dict(k=j, d=1, e=min(hi, O[j] + sp[j]) - sp[j], sl=lo, lim=True, day=r.day, fl=fl)); break
            if d == -1 and H[j] >= lo:
                out.append(dict(k=j, d=-1, e=max(lo, O[j]), sl=hi, lim=True, day=r.day, fl=fl)); break
    return out


if __name__ == "__main__" and not os.environ.get("RQ_V2"):
    for sym in ("NAS100", "XAUUSD"):
        F.SYM = sym
        df = F.load(sym); s = F.sessions(df)
        print(f"\n== {sym}", flush=True)
        for disc in (False, True):
            sets = signals(df, s, disc)
            for ex, exn in ((1, "1R"), (2, "2R"), (0, "hold")):
                real = F.run(df, sets, ex)
                rng = np.random.default_rng(20261022)
                coin = np.array([F.run(df, sets, ex, rng).R.sum() for _ in range(SEEDS)])
                yr = real.groupby(real.day.dt.year).R.sum(); a = F.stats(real)
                print(f"  {'DISCIPLINED' if disc else 'AS_CODED':11s} {exn:4s}: {a['n']:5d} tr {a['R']:+7.1f}R avg {a['avg']:+.3f} win {a['win']:.0%} "
                      f"PF {a['pf']:.2f} | yrs+ {(yr > 0).sum()}/{len(yr)} | coin {(coin < a['R']).mean():.0%} | " + " ".join(f"{y}:{v:+.1f}" for y, v in yr.items()), flush=True)


# Roboquant's optimised v2 (Adam's screenshots 2026-10-22): "bayesian, 6 params, 200 trials; best: range 15m, SL 6pt,
# TP 8pt", ES 5m tick 2020-06 -> 2026-06, +3155%, PF 1.78, Sharpe 1.72 ("Hypothetical results"). Replayed on SPX500
# (the cash S&P CFD; ES isn't in our data) with fixed 6 / 8 point brackets, template entry (close beyond -> limit at the
# edge), held to the next open as coded, and DISCIPLINED. THROUGH = the limit only fills if price trades 1 tick (0.25)
# through it (no queue-position luck).
def fixed_bracket(sets, slpts, through=0.0, H=None, L=None):
    out = []
    for s in sets:
        if through and not ((L[s["k"]] <= s["e"] - through) if s["d"] == 1 else (H[s["k"]] >= s["e"] + through)):
            continue
        out.append(dict(s, sl=s["e"] - s["d"] * slpts))
    return out


if __name__ == "__main__" and os.environ.get("RQ_V2"):
    F.SYM = "SPX500"; F.PT["SPX500"] = 0.01
    df = F.load("SPX500"); s = F.sessions(df)
    H, L = df.high.values, df.low.values
    print(f"== SPX500 {s.day.min():%Y-%m} to {s.day.max():%Y-%m}", flush=True)
    for disc in (False, True):
        base = signals(df, s, disc)
        for thr in (0.0, 0.25):
            sets = fixed_bracket(base, 6.0, thr, H, L)
            real = F.run(df, sets, 8.0 / 6.0)
            rng = np.random.default_rng(20261022)
            coin = np.array([F.run(df, sets, 8.0 / 6.0, rng).R.sum() for _ in range(SEEDS)])
            yr = real.groupby(real.day.dt.year).R.sum(); a = F.stats(real)
            print(f"  {'DISCIPLINED' if disc else 'AS_CODED':11s} {'THROUGH' if thr else 'TOUCH':7s}: {a['n']:5d} tr {a['R']:+7.1f}R avg {a['avg']:+.3f} win {a['win']:.0%} "
                  f"PF {a['pf']:.2f} | yrs+ {(yr > 0).sum()}/{len(yr)} | coin {(coin < a['R']).mean():.0%} | " + " ".join(f"{y}:{v:+.1f}" for y, v in yr.items()), flush=True)
