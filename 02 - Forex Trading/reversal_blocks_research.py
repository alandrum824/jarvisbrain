"""TWI Reversal Blocks - the swept-high block from Adam's video screenshots (2026-10-22). READ-ONLY replay, AAAFx M1 2020-01 -> 2026-10.

Blocks are found with the exact rules of `TWI Reversal Blocks.pine` (sell side; buy side is the mirror):
  1. Swings = pivots, P bars each side (P=5 primary, 3 as a check), on M5 (primary) or M15 built from M1 (NY clock).
  2. Liquidity = confirmed swing highs not yet traded through. Sweep pivot = a new swing high whose up-leg (from the last
     swing low before it) traded through an old high formed before that leg.
  3. Rejection = a close below the leg-start low without a high above the sweep high first (100 bars max).
  4. Block = sweep high (top) down to min(swept old high, sweep candle's body top). Newest 3 per side stay live.
Trade (pre-registered before any result): the first touch of a live block after it is confirmed = a limit at the near
edge (sell at the block bottom; fills at the M1 open if it opens beyond it). SL = the far edge. A touch on a bar that also
breaks the block still counts (the limit would have filled), unlike the indicator's tap circle.
Exits: 1R, 2R, LEG (target = the leg-start level the rejection broke). One position at a time, max hold 2 days,
SL first on ties incl. the fill minute, cost = bar spread + 6 pt markup (gold).
Control: COIN = same fills and stop distance, coin-flip direction (50 seeds).
Pass bar (pre-registered): positive in >= 5 of 7 years, PF >= 1.15, beats >= 95% of coin runs.
"""
import os, sys
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_momentum_longrun_research as base

PT, MK, SEEDS, WAIT, KEEP, HOLD = 0.01, 6, 50, 100, 3, 60 * 24 * 2


def bars(df, tf):
    b = df.set_index("ny").resample(tf, label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
    return b.index.values, b.open.values, b.high.values, b.low.values, b.close.values


def blocks(tfb, P):
    """Mirror of the Pine engine. Returns dicts: d (-1 sell, +1 buy), top, bot, trig, piv, conf (bar indexes)."""
    t, O, H, L, C = tfb
    n = len(t); out = []
    liq = {1: [], -1: []}          # [price, bar, sweptBar]; key 1 = highs, -1 = lows
    piv = {1: [], -1: []}          # [price, bar]
    pend = {1: [], -1: []}         # key 1 = sell side (from highs)
    live = {1: [], -1: []}
    for i in range(n):
        for l in liq[1]:
            if l[2] is None and H[i] > l[0]: l[2] = i
        for l in liq[-1]:
            if l[2] is None and L[i] < l[0]: l[2] = i
        for s in (1, -1):
            del liq[s][:-40]
        c = i - P
        if c >= P:
            for s, X in ((1, H), (-1, L)):
                w = s * X[c - P:c + P + 1]
                if s * X[c] == w.max() and s * X[c] > (s * X[c - P:c]).max():
                    p = X[c]
                    leg = next((q for q in reversed(piv[-s]) if q[1] < c), None)
                    if leg is not None:
                        cand = [l[0] for l in liq[s] if l[2] is not None and l[1] < leg[1] < l[2] <= c and s * l[0] < s * p]
                        if cand:
                            old = max(cand) if s > 0 else min(cand)
                            body = max(O[c], C[c]) if s > 0 else min(O[c], C[c])
                            near = min(old, body) if s > 0 else max(old, body)
                            pend[s].append(dict(far=p, near=near, trig=leg[0], piv=c, born=i))
                    liq[s].append([p, c, None])
                    piv[s].append([p, c]); del piv[s][:-20]
        for s in (1, -1):
            keep = []
            for q in pend[s]:
                if i == q["born"]:
                    rej = (C[i - P + 1:i + 1].min() < q["trig"]) if s > 0 else (C[i - P + 1:i + 1].max() > q["trig"])
                    beyond = False
                else:
                    rej = C[i] < q["trig"] if s > 0 else C[i] > q["trig"]
                    beyond = H[i] > q["far"] if s > 0 else L[i] < q["far"]
                if beyond or i - q["born"] > WAIT:
                    continue
                if rej:
                    b = dict(d=-s, top=max(q["far"], q["near"]), bot=min(q["far"], q["near"]), trig=q["trig"],
                             piv=q["piv"], conf=i, end=None)
                    out.append(b); live[s].append(b)
                    while len(live[s]) > KEEP:
                        live[s].pop(0)["end"] = i
                else:
                    keep.append(q)
            pend[s] = keep
            still = []
            for b in live[s]:
                if i > b["conf"] and (C[i] > b["top"] if s > 0 else C[i] < b["bot"]):
                    b["end"] = i
                else:
                    still.append(b)
            live[s] = still
    return out


def entries(df, tfb, blks):
    """First M1 touch of each block's near edge between its confirmation and its end (eviction or break)."""
    T = df.ny.values; O, H, L = df.open.values, df.high.values, df.low.values
    t = tfb[0]; n = len(t); res = []
    for b in blks:
        k0 = np.searchsorted(T, t[b["conf"] + 1]) if b["conf"] + 1 < n else len(T)
        k1 = np.searchsorted(T, t[b["end"] + 1]) if b["end"] is not None and b["end"] + 1 < n else len(T)
        if k0 >= k1: continue
        if b["d"] < 0:
            hit = np.flatnonzero(H[k0:k1] >= b["bot"])
            if not len(hit): continue
            k = k0 + hit[0]; e = max(O[k], b["bot"]); sl = b["top"]; tgt = b["trig"]
        else:
            hit = np.flatnonzero(L[k0:k1] <= b["top"])
            if not len(hit): continue
            k = k0 + hit[0]; e = min(O[k], b["top"]); sl = b["bot"]; tgt = b["trig"]
        if (sl - e) * b["d"] >= 0: continue                      # opened beyond the far edge
        res.append((k, b["d"], e, sl, tgt))
    res.sort()
    return res


def simulate(df, ents, ex, coin=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    res = []; busy = -1
    for k, d, e0, sl0, tgt in ents:
        if k <= busy: continue
        cost = (S[k] + MK) * PT
        dist = abs(e0 - sl0)
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        e = e0 + (cost if dd > 0 else 0)                             # buys pay the ask
        risk = dist + cost
        sl = e - dd * dist
        tpR = {"1R": 1.0, "2R": 2.0}.get(ex)
        if tpR is None:
            tpR = d * (tgt - e0) / risk if coin is None else abs(tgt - e0) / risk
            if tpR <= 0: continue
        tp = e + dd * tpR * risk
        end = min(len(T), k + HOLD)
        sp = (S[k:end] + MK) * PT
        if dd > 0: slh = L[k:end] <= sl; tph = H[k:end] >= tp
        else: slh = H[k:end] + sp >= sl; tph = L[k:end] + sp <= tp
        tph[0] = tph[0] and not slh[0]
        hit = np.flatnonzero(slh | tph)
        if len(hit): j = k + hit[0]; px = sl if slh[hit[0]] else tp
        else: j = end - 1; px = C[j] + (0 if dd > 0 else sp[-1])
        res.append((pd.Timestamp(T[k]), dd, dd * (px - e) / risk, tpR, dist))
        busy = j
    return pd.DataFrame(res, columns=["time", "d", "R", "tpR", "dist"])


if __name__ == "__main__":
    df = base.load("XAUUSD")
    for tf, P in (("5min", 5), ("5min", 3), ("15min", 5)):
        tfb = bars(df, tf)
        blks = blocks(tfb, P)
        ents = entries(df, tfb, blks)
        t = tfb[0]
        print(f"\n== {tf} P{P}: {len(blks)} blocks, {len(ents)} touched, median height "
              f"{np.median([b['top'] - b['bot'] for b in blks]):.2f}", flush=True)
        if tf == "5min" and P == 5:
            day = [b for b in blks if str(t[b["piv"]])[:10] == "2026-07-27"]
            for b in day:
                print(f"   07-27 block {'SELL' if b['d'] < 0 else 'BUY '} {b['bot']:.2f}-{b['top']:.2f} sweep bar "
                      f"{str(t[b['piv']])[11:16]} NY, confirmed {str(t[b['conf']])[11:16]}", flush=True)
        for ex in ("1R", "2R", "LEG"):
            r = simulate(df, ents, ex)
            if r.empty: print(ex, "no trades"); continue
            ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
            rng = np.random.default_rng(20261022)
            coins = np.array([simulate(df, ents, ex, coin=rng).R.sum() for _ in range(SEEDS)])
            ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
            print(f"  {ex:3s}: {len(r)} tr, {r.R.sum():+.1f}R, {r.R.mean():+.3f}R/tr, PF {pf:.2f}, win {(r.R > 0).mean():.0%}, "
                  f"sells {(r.d < 0).mean():.0%}, median stop {r.dist.median():.2f}, median TP {r.tpR.median():.1f}R, "
                  f"years+ {int((ys > 0).sum())}/{len(ys)}, beats coin {(coins < r.R.sum()).mean():.0%} -> {'PASS' if ok else 'fail'}", flush=True)
            print("       " + "  ".join(f"{y}:{v:+.1f}" for y, v in ys.items()), flush=True)
            if tf == "5min" and P == 5 and ex == "2R":
                r.to_csv(r"C:\Users\aland\stg\obh\reversal_blocks_XAUUSD_trades.csv", index=False)
