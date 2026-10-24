"""Adam (2026-10-22): "Add trailing stop loss" - same blocks/touch entries, trailing exits instead of fixed TP.
TRAIL1  : stop trails 1 block-risk behind the best price from the start (initial SL = block far edge), no TP.
BE_T05  : at +1R stop -> breakeven, then trails 0.5R behind the best price, no TP.
BE_2R   : at +1R stop -> breakeven, TP 2R.
Stop for minute j uses the best price up to minute j-1 (no same-minute look-ahead). SL first on ties. Max hold 2 days."""
import sys, numpy as np, pandas as pd
sys.path.insert(0, r"C:\Users\aland\OneDrive\Desktop\jarvis\Adam\02 - Forex Trading")
import reversal_blocks_research as rb, orb_momentum_longrun_research as base
sys.path.insert(0, r"C:\Users\aland\OneDrive\Desktop\jarvis\Adam\02 - Forex Trading")


def sim_trail(df, ents, mode, coin=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    res = []; busy = -1
    for k, d, e0, sl0, _ in ents:
        if k <= busy: continue
        cost = (S[k] + rb.MK) * rb.PT; dist = abs(e0 - sl0)
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        e = e0 + (cost if dd > 0 else 0); risk = dist + cost
        end = min(len(T), k + rb.HOLD); sp = (S[k:end] + rb.MK) * rb.PT
        if dd > 0: fav = (H[k:end] - e); adv = (L[k:end] - e)          # profit in price, best/worst within minute
        else: fav = (e - (L[k:end] + sp)); adv = (e - (H[k:end] + sp))
        fav0 = fav.copy(); fav0[0] = min(fav0[0], 0.0); best = np.maximum.accumulate(fav0); prev = np.concatenate(([0.0], best[:-1])); prev = np.maximum(prev, 0)
        if mode == "TRAIL1":
            stop = np.maximum(-dist, prev - dist); tp = np.inf
        elif mode == "BE_T05":
            stop = np.where(prev >= risk, np.maximum(0.0, prev - 0.5 * risk), -dist); tp = np.inf
        else:
            stop = np.where(prev >= risk, 0.0, -dist); tp = 2 * risk
        slh = adv <= stop; tph = fav >= tp; tph[0] = tph[0] and not slh[0]
        hit = np.flatnonzero(slh | tph)
        if len(hit):
            j = hit[0]; pnl = stop[j] if slh[j] else tp
        else:
            j = end - 1 - k; pnl = dd * (C[end - 1] - e) - (0 if dd > 0 else sp[-1])
        res.append((pd.Timestamp(T[k]), dd, pnl / risk, dist)); busy = k + j
    return pd.DataFrame(res, columns=["time", "d", "R", "dist"])

SEEDS = 20
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
import itertools
def sim_var(df, ents, act, gap, coin=None):
    global MODE_ACT, MODE_GAP
    return sim_trail(df, ents, ("V", act, gap), coin)
_orig = sim_trail
def sim_trail(df, ents, mode, coin=None):
    if not isinstance(mode, tuple): return _orig(df, ents, mode, coin)
    _, act, gap = mode
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    res = []; busy = -1
    for k, d, e0, sl0, _x in ents:
        if k <= busy: continue
        cost = (S[k] + rb.MK) * rb.PT; dist = abs(e0 - sl0)
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        e = e0 + (cost if dd > 0 else 0); risk = dist + cost
        end = min(len(T), k + rb.HOLD); sp = (S[k:end] + rb.MK) * rb.PT
        if dd > 0: fav = H[k:end] - e; adv = L[k:end] - e
        else: fav = e - (L[k:end] + sp); adv = e - (H[k:end] + sp)
        f0 = fav.copy(); f0[0] = min(f0[0], 0.0); best = np.maximum.accumulate(f0)
        prev = np.maximum(np.concatenate(([0.0], best[:-1])), 0)
        stop = np.where(prev >= act * risk, np.maximum(0.0, prev - gap * risk), -dist)
        slh = adv <= stop; hit = np.flatnonzero(slh)
        if len(hit): j = hit[0]; pnl = stop[j]
        else: j = end - 1 - k; pnl = dd * (C[end - 1] - e) - (0 if dd > 0 else sp[-1])
        res.append((pd.Timestamp(T[k]), dd, pnl / risk, dist)); busy = k + j
    return pd.DataFrame(res, columns=["time", "d", "R", "dist"])

def report(tag, r, coins):
    ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
    ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
    print(f"{tag}: {len(r):5d} tr {r.R.sum():+8.1f}R {r.R.mean():+.3f}/tr PF {pf:.2f} win {(r.R>0).mean():.0%} "
          f"yrs+ {int((ys>0).sum())}/{len(ys)} coin {(coins<r.R.sum()).mean():.0%} {'PASS' if ok else 'fail'} | "
          + " ".join(f"{y}:{v:+.0f}" for y, v in ys.items()), flush=True)

for sym in sys.argv[1:]:
    rb.PT = base.PT[sym]; rb.MK = base.MARKUP.get(sym, 0); df = base.load(sym)
    for tf in ("5min", "15min"):
        tfb = rb.bars(df, tf); blks = rb.blocks(tfb, 5); ents = entries_nth(df, tfb, blks, 1, 0.0)
        for act, gap in [(1.0, 0.5), (0.5, 0.5), (1.5, 0.5), (1.0, 0.3), (1.0, 0.75), (1.0, 1.0)]:
            r = sim_trail(df, ents, ("V", act, gap)); rng = np.random.default_rng(20261022)
            coins = np.array([sim_trail(df, ents, ("V", act, gap), coin=rng).R.sum() for _ in range(SEEDS)])
            report(f"{sym} {tf:5s} touch1 BE@{act}R trail {gap}R", r, coins)
