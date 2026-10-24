import sys, numpy as np, pandas as pd
sys.path.insert(0, r"C:\Users\aland\OneDrive\Desktop\jarvis\Adam\02 - Forex Trading")
import reversal_blocks_research as rb, orb_momentum_longrun_research as base
sym = sys.argv[1]; rb.PT = base.PT[sym]; rb.MK = base.MARKUP.get(sym, 0)
df = base.load(sym)
for tf, P in (("5min", 5), ("15min", 5)):
    tfb = rb.bars(df, tf); blks = rb.blocks(tfb, P); ents = rb.entries(df, tfb, blks)
    print(f"\n== {sym} {tf} P{P}: {len(blks)} blocks, median height {np.median([b['top']-b['bot'] for b in blks])/rb.PT/10:.1f} pips", flush=True)
    for ex in ("1R", "2R", "LEG"):
        r = rb.simulate(df, ents, ex)
        ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
        rng = np.random.default_rng(20261022)
        coins = np.array([rb.simulate(df, ents, ex, coin=rng).R.sum() for _ in range(rb.SEEDS)])
        ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
        print(f"  {ex:3s}: {len(r)} tr, {r.R.sum():+.1f}R, {r.R.mean():+.3f}R/tr, PF {pf:.2f}, win {(r.R>0).mean():.0%}, "
              f"years+ {int((ys>0).sum())}/{len(ys)}, coin {(coins < r.R.sum()).mean():.0%} -> {'PASS' if ok else 'fail'}", flush=True)
        print("       " + "  ".join(f"{y}:{v:+.1f}" for y, v in ys.items()), flush=True)
        if ex == "1R":
            r0 = r.copy(); big = r0[r0.dist >= 0.0010]
            print(f"       stops >= 10 pips: {len(big)} tr, {big.R.sum():+.1f}R, {big.R.mean():+.3f}R/tr", flush=True)
