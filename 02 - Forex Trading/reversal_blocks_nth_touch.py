"""Adam's refinement (2026-10-22): skip the first touches, enter on the Nth separate touch of the block.
A 'touch' = a run of signal-TF bars reaching the near edge; a new touch needs price to leave first.
AWAY = how far price must move off the near edge between touches, in block heights (0 = any bar that misses)."""
import sys, numpy as np, pandas as pd
sys.path.insert(0, r"C:\Users\aland\OneDrive\Desktop\jarvis\Adam\02 - Forex Trading")
import reversal_blocks_research as rb, orb_momentum_longrun_research as base

def entries_nth(df, tfb, blks, N, AWAY):
    T = df.ny.values; O, H = df.open.values, df.high.values; L = df.low.values
    t, _, BH, BL, _ = tfb; n = len(t); res = []
    for b in blks:
        hgt = b["top"] - b["bot"]; end = b["end"] if b["end"] is not None else n - 1
        cnt = 0; armed = True; hit_i = None
        for i in range(b["conf"] + 1, min(end, n - 1) + 1):
            touch = BH[i] >= b["bot"] if b["d"] < 0 else BL[i] <= b["top"]
            if touch and armed:
                cnt += 1; armed = False
                if cnt == N: hit_i = i; break
            if not touch and not armed:
                away = (b["bot"] - BL[i]) if b["d"] < 0 else (BH[i] - b["top"])
                if away >= AWAY * hgt: armed = True
        if hit_i is None: continue
        k0 = np.searchsorted(T, t[hit_i]); k1 = np.searchsorted(T, t[hit_i + 1]) if hit_i + 1 < n else len(T)
        if b["d"] < 0:
            h = np.flatnonzero(H[k0:k1] >= b["bot"])
            if not len(h): continue
            k = k0 + h[0]; e = max(O[k], b["bot"])
        else:
            h = np.flatnonzero(L[k0:k1] <= b["top"])
            if not len(h): continue
            k = k0 + h[0]; e = min(O[k], b["top"])
        sl = b["top"] if b["d"] < 0 else b["bot"]
        if (sl - e) * b["d"] >= 0: continue
        res.append((k, b["d"], e, sl, b["trig"]))
    res.sort(); return res

for sym in sys.argv[1:]:
    rb.PT = base.PT[sym]; rb.MK = base.MARKUP.get(sym, 0); df = base.load(sym)
    for tf in ("5min", "15min"):
        tfb = rb.bars(df, tf); blks = rb.blocks(tfb, 5)
        for AWAY in (0.0, 1.0):
            for N in (1, 2, 3):
                ents = entries_nth(df, tfb, blks, N, AWAY)
                for ex in ("1R", "2R"):
                    r = rb.simulate(df, ents, ex)
                    if r.empty: print(sym, tf, AWAY, N, ex, "no trades"); continue
                    ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
                    rng = np.random.default_rng(20261022)
                    coins = np.array([rb.simulate(df, ents, ex, coin=rng).R.sum() for _ in range(rb.SEEDS)])
                    ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
                    print(f"{sym} {tf:5s} away{AWAY:.0f} touch{N} {ex}: {len(r):5d} tr {r.R.sum():+8.1f}R {r.R.mean():+.3f}/tr PF {pf:.2f} "
                          f"win {(r.R>0).mean():.0%} yrs+ {int((ys>0).sum())}/{len(ys)} coin {(coins<r.R.sum()).mean():.0%} {'PASS' if ok else 'fail'}", flush=True)
