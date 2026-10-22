"""TWI ORB Momentum v1.20 rules on NEW markets/sessions + coin-flip control. READ-ONLY research (bars only).

Goal (2026-10-11, Adam "how can we pass faster"): find more independent legs, so R/year rises without raising risk.
Rules unchanged from v1.20 (55-min range, first touch in the next 10 min, H1 EMA50 filter, SL 2.2x range, TP 0.75x SL,
one trade per session, no new trade while one is open). Sessions are anchored to their own local open:
  NY 09:30 New York | LON 08:00 London (UTC+0/+1 EU DST) | TKY 09:00 Tokyo = 00:00 UTC (no DST).
PRE-REGISTERED PASS BAR (fixed before any result): beats >= 95% of 50 coin-flip runs AND positive in >= 5 of 7 calendar
years (>= 4 of 5 if the history is shorter) AND net R > 0. ~16 cells are tested, so about one could clear 95% by chance:
any pass still needs an MT5 tester confirmation before it becomes a leg.
Costs: the entry bar's own spread (points x point). Clock: srv_to_ny from orb_momentum_longrun_research (proven AAAFx clock).
"""
import os, sys, datetime as dt
import numpy as np, pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import orb_momentum_longrun_research as base

DATA = base.DATA
PT = {"NAS100": 0.1, "US30": 0.1, "SPX500": 0.01, "GER30": 0.1, "UK100": 0.1, "JPN225": 0.1,
      "AUDUSD": 0.00001, "USDCAD": 0.00001, "AUDJPY": 0.001, "USDJPY": 0.001, "EURUSD": 0.00001}
CELLS = [("NAS100", "NY"), ("US30", "NY"), ("SPX500", "NY"), ("GER30", "LON"), ("UK100", "LON"), ("JPN225", "TKY"),
         ("AUDUSD", "NY"), ("AUDUSD", "LON"), ("AUDUSD", "TKY"), ("USDCAD", "NY"), ("USDCAD", "LON"),
         ("AUDJPY", "TKY"), ("AUDJPY", "LON"), ("USDJPY", "TKY"), ("EURUSD", "TKY"), ("EURUSD", "LON")]
SEEDS = 50


def eu_dst(utc):
    return base.last_sunday(utc.year, 3) + dt.timedelta(hours=1) <= utc < base.last_sunday(utc.year, 10) + dt.timedelta(hours=1)


def session_start_ny(day, sess):
    """day = local calendar date of the session. Returns the NY wall-clock datetime of the open."""
    if sess == "NY":
        return dt.datetime.combine(day, dt.time(9, 30))
    if sess == "LON":
        utc = dt.datetime.combine(day, dt.time(8, 0))
        utc -= dt.timedelta(hours=1 if eu_dst(utc) else 0)
    else:  # TKY 09:00 JST = 00:00 UTC
        utc = dt.datetime.combine(day, dt.time(0, 0))
    return utc + dt.timedelta(hours=base.ny_off(utc))


def run(df, sym, sess, coin_rng=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    eT, eV = base.h1_ema50(df); pt = PT[sym]
    days = pd.date_range(pd.Timestamp(T[0]).normalize(), pd.Timestamp(T[-1]).normalize(), freq="D")
    busy = np.datetime64("1970-01-01"); out = []
    for day in days:
        if day.dayofweek >= 5:
            continue
        st = np.datetime64(session_start_ny(day.date(), sess))
        if st < busy:
            continue
        i0 = np.searchsorted(T, st); i1 = np.searchsorted(T, st + np.timedelta64(55, "m")); i2 = np.searchsorted(T, st + np.timedelta64(65, "m"))
        if i1 - i0 < 33:
            continue
        hi = H[i0:i1].max(); lo = L[i0:i1].min(); size = hi - lo
        if size <= 0:
            continue
        for k in range(i1, i2):
            up = H[k] >= hi; dn = L[k] <= lo
            if not (up or dn):
                continue
            if up and dn:
                break
            d = 1 if up else -1
            if coin_rng is not None:
                d = 1 if coin_rng.random() < 0.5 else -1
            j = np.searchsorted(eT, T[k], side="right") - 2
            if j < 50:
                break
            p = hi if up else lo
            if not ((p > eV[j]) if d > 0 else (p < eV[j])):
                break
            e = (max(hi, O[k]) if d > 0 else min(lo, O[k])) if coin_rng is None else C[k]
            sld = 2.2 * size; sl = e - d * sld; tp = e + d * 0.75 * sld
            cost = S[k] * pt
            end = min(len(T), k + 60 * 24 * 20)
            slh = (L[k:end] <= sl) if d > 0 else (H[k:end] >= sl)
            tph = (H[k:end] >= tp) if d > 0 else (L[k:end] <= tp)
            if coin_rng is None:
                tph[0] = False
            hit = np.flatnonzero(slh | tph)
            if not len(hit):
                break
            q = k + hit[0]; px = sl if slh[hit[0]] else tp
            busy = T[q]; out.append((pd.Timestamp(T[k]), d, (d * (px - e) - cost) / sld, cost / sld))
            break
    return pd.DataFrame(out, columns=["time", "d", "R", "costR"])


if __name__ == "__main__":
    rows = []; cache = {}
    for sym, sess in CELLS:
        if not os.path.exists(os.path.join(DATA, f"{sym}_M1.csv")):
            print(sym, "no data"); continue
        if sym not in cache:
            cache = {sym: base.load(sym)}
        df = cache[sym]
        real = run(df, sym, sess)
        if real.empty:
            print(f"{sym} {sess}: no trades"); continue
        ys = real.groupby(real.time.dt.year).R.sum(); ny = len(ys); posy = int((ys > 0).sum())
        tot = real.R.sum(); pf = real.R[real.R > 0].sum() / max(-real.R[real.R < 0].sum(), 1e-12)
        rng = np.random.default_rng(20261011)
        coins = np.array([run(df, sym, sess, coin_rng=rng).R.sum() for _ in range(SEEDS)])
        beats = (coins < tot).mean()
        need = 5 if ny >= 7 else (4 if ny >= 5 else ny)
        ok = beats >= 0.95 and posy >= need and tot > 0
        real.to_csv(os.path.join(DATA, f"orbmom_new_{sym}_{sess}_trades.csv"), index=False)
        print(f"{'PASS' if ok else 'fail'}  {sym:6s} {sess:3s}: {len(real)} tr from {real.time.min():%Y-%m}, {tot:+.1f}R, {real.R.mean():+.3f}R/tr, PF {pf:.2f}, "
              f"win {(real.R > 0).mean():.0%}, cost {real.costR.median():.3f}R, years+ {posy}/{ny}, coin median {np.median(coins):+.1f}R, beats {beats:.0%}", flush=True)
        print("        " + "  ".join(f"{y}:{r:+.1f}" for y, r in ys.items()), flush=True)
        rows.append(dict(sym=sym, sess=sess, n=len(real), R=tot, avgR=real.R.mean(), pf=pf, years_pos=posy, years=ny, beats=beats, passed=ok))
    pd.DataFrame(rows).to_csv(os.path.join(DATA, "orbmom_newlegs_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "orbmom_newlegs_summary.csv"))
