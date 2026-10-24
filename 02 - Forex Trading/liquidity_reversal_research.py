"""Replay of the externally supplied TWI_LiquidityReversal.mq5 rules (2026-10-22), bar-for-bar from its OnCalculate:
one protected high + one protected low tracked at a time; pivot depth 3; invalid once any wick reaches the level;
armed after a close <= ref - 1.2 ATR; touch = high within 0.55 ATR below ref (not reaching it); signal = a later bar
within 4 bars closing bearish below the touch candle's low. EA: market entry at the next bar open, SL = ref + 0.12 ATR,
TP = 2R (also 1R), one position, max 2 entries/day (server day), spread <= 65 pts. ATR = SMA(14) of true range (MT5 iATR).
Costs: bar spread + markup; SL first on ties. Coin control 50 seeds."""
import sys, numpy as np, pandas as pd
sys.path.insert(0, r"C:\Users\aland\OneDrive\Desktop\jarvis\Adam\02 - Forex Trading")
import orb_momentum_longrun_research as base
D, ATRP, DISP, ZONE, CONF, MAXREF, BUF = 3, 14, 1.2, 0.55, 4, 100, 0.12

def signals(o, h, l, c):
    n = len(c); tr = np.maximum(h[1:], c[:-1]) - np.minimum(l[1:], c[:-1]); tr = np.concatenate(([h[0]-l[0]], tr))
    atr = pd.Series(tr).rolling(ATRP).mean().values; out = []
    hP = lP = 0; hB = lB = hT = lT = 0; hR = lR = hTL = lTH = 0.0
    for i in range(2 * D + 2, n):
        a = atr[i]
        if not a > 0: continue
        if hP and i - hB > MAXREF: hP = 0
        if lP and i - lB > MAXREF: lP = 0
        p = i - D
        if hP <= 1 and all(h[p] > h[p - d] and h[p] > h[p + d] for d in range(1, D + 1)): hR, hB, hP = h[p], p, 1
        if lP <= 1 and all(l[p] < l[p - d] and l[p] < l[p + d] for d in range(1, D + 1)): lR, lB, lP = l[p], p, 1
        if hP and h[i] >= hR: hP = 0
        if lP and l[i] <= lR: lP = 0
        if hP == 1 and c[i] <= hR - DISP * a: hP = 2
        if lP == 1 and c[i] >= lR + DISP * a: lP = 2
        if hP == 2 and hR - ZONE * a <= h[i] < hR: hT, hTL, hP = i, l[i], 3
        elif hP == 3:
            if i - hT > CONF: hP = 0
            elif i > hT and c[i] < hTL and c[i] < o[i]: out.append((i, -1, hR + BUF * a)); hP = 0
        if lP == 2 and lR < l[i] <= lR + ZONE * a: lT, lTH, lP = i, h[i], 3
        elif lP == 3:
            if i - lT > CONF: lP = 0
            elif i > lT and c[i] > lTH and c[i] > o[i]: out.append((i, 1, lR - BUF * a)); lP = 0
    return out

def run(sym, tf, tpR, coin=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    res = []; busy = -1; day_n = {}
    for i, d, sl in sigs:
        if i + 1 >= len(bt): continue
        k = np.searchsorted(T, bt[i + 1])
        if k >= len(T) or k <= busy or S[k] > 65 and sym == "XAUUSD": continue
        day = str(df.time_server.values[k])[:10]
        if day_n.get(day, 0) >= 2: continue
        dd = d if coin is None else (1 if coin.random() < 0.5 else -1)
        cost = (S[k] + MK) * PT; e = O[k] + (cost if d > 0 else 0)
        dist = (e - sl) * d
        if dist <= 0: continue
        risk = dist + (0 if d > 0 else cost)
        if coin is not None: e = O[k] + (cost if dd > 0 else 0)
        slp = e - dd * dist; tp = e + dd * tpR * risk
        end = min(len(T), k + 60 * 24 * 2); sp = (S[k:end] + MK) * PT
        if dd > 0: slh = L[k:end] <= slp; tph = H[k:end] >= tp
        else: slh = H[k:end] + sp >= slp; tph = L[k:end] + sp <= tp
        hit = np.flatnonzero(slh | tph)
        if len(hit): j = k + hit[0]; px = slp if slh[hit[0]] else tp
        else: j = end - 1; px = C[j] + (0 if dd > 0 else sp[-1])
        res.append((pd.Timestamp(T[k]), dd * (px - e) / risk, dist)); busy = j; day_n[day] = day_n.get(day, 0) + 1
    return pd.DataFrame(res, columns=["time", "R", "dist"])

for sym in sys.argv[1:]:
    PT = base.PT[sym]; MK = base.MARKUP.get(sym, 0); df = base.load(sym)
    for tf in ("5min", "15min"):
        b = df.set_index("ny").resample(tf, label="left", closed="left").agg({"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
        bt = b.index.values; sigs = signals(b.open.values, b.high.values, b.low.values, b.close.values)
        for tpR in (1.0, 2.0):
            r = run(sym, tf, tpR); ys = r.groupby(r.time.dt.year).R.sum(); pf = r.R[r.R > 0].sum() / max(-r.R[r.R < 0].sum(), 1e-9)
            rng = np.random.default_rng(20261022); coins = np.array([run(sym, tf, tpR, coin=rng).R.sum() for _ in range(50)])
            ok = (ys > 0).sum() >= 5 and pf >= 1.15 and (coins < r.R.sum()).mean() >= 0.95
            print(f"{sym} {tf:5s} {tpR:.0f}R: {len(sigs)} sig, {len(r)} tr {r.R.sum():+8.1f}R {r.R.mean():+.3f}/tr PF {pf:.2f} win {(r.R>0).mean():.0%} "
                  f"stop med {r.dist.median()/PT:.0f}pt yrs+ {int((ys>0).sum())}/{len(ys)} coin {(coins<r.R.sum()).mean():.0%} {'PASS' if ok else 'fail'} | "
                  + " ".join(f"{y}:{v:+.0f}" for y, v in ys.items()), flush=True)
