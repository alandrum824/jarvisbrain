"""TWI ORB Momentum v1.20 replay on 2020-2026 + controls. READ-ONLY research (bars only, no orders).

v1.20 rules (see TWI ORB Momentum.md): NY 09:30 (New York time) range = high/low of the first 55 M1 bars; in the next 10
minutes the FIRST touch of an edge enters in that direction (both edges in one bar = no trade); H1 EMA50 trend filter
(the edge must be on the trend side of the last closed H1 EMA50, else the session is done); SL = 2.2 x range, TP = 0.75 x SL;
one trade per session, no new trade while one is open. London 03:00 shown too (it failed out of sample before).
Costs: the entry bar's own spread (points from the M1 export) charged once per trade; SL first when a bar hits both.
Clock: AAAFx server = London time before 2022-03-27, UTC+0 to 2026-03-06, NY+7 after (proven in daily_flipped_zone_research.py).
Control: COIN = same days/times/stops/targets but the direction is a coin flip instead of the touched edge (50 seeds).
  If the touched-edge direction doesn't beat a coin flip, the "momentum" isn't the edge.
Data: C:/Users/aland/stg/obh/<SYM>_M1.csv (TWIBarsExportTester, 2020-01-02 -> 2026-10-09).
"""
import os, bisect, datetime as dt, collections
import numpy as np, pandas as pd

DATA = r"C:\Users\aland\stg\obh"
PT = {"EURUSD": 0.00001, "GBPUSD": 0.00001, "USDJPY": 0.001, "XAUUSD": 0.01}
MARKUP = {"XAUUSD": 6}
CUT = dt.datetime(2026, 3, 7); LONDON_END = dt.datetime(2022, 3, 27)
SEEDS = 50


def nth_sunday(y, m, n):
    d = dt.datetime(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7); return d + dt.timedelta(days=7 * (n - 1))


def last_sunday(y, m):
    d = (dt.datetime(y, m + 1, 1) if m < 12 else dt.datetime(y + 1, 1, 1)) - dt.timedelta(days=1)
    return d - dt.timedelta(days=(d.weekday() + 1) % 7)


def ny_off(utc):
    s = nth_sunday(utc.year, 3, 2) + dt.timedelta(hours=7); e = nth_sunday(utc.year, 11, 1) + dt.timedelta(hours=6)
    return -4 if s <= utc < e else -5


def srv_to_ny(t):
    if t < LONDON_END:
        eu = last_sunday(t.year, 3) + dt.timedelta(hours=1) <= t < last_sunday(t.year, 10) + dt.timedelta(hours=1)
        utc = t - dt.timedelta(hours=1 if eu else 0)
        return utc + dt.timedelta(hours=ny_off(utc))
    return t + dt.timedelta(hours=ny_off(t)) if t < CUT else t - dt.timedelta(hours=7)


def load(sym):
    df = pd.read_csv(os.path.join(DATA, f"{sym}_M1.csv"))
    srv = pd.to_datetime(df.time_server, format="%Y.%m.%d %H:%M")
    # vectorised clock: compute per unique hour to stay fast
    hrs = srv.dt.floor("h"); uh = pd.Series(hrs.unique())
    m = {h: srv_to_ny(h.to_pydatetime()) - h.to_pydatetime() for h in uh}
    df["ny"] = srv + hrs.map(m)
    df = df.sort_values("ny").drop_duplicates("ny").reset_index(drop=True)
    return df


def h1_ema50(df):
    h = df.set_index("ny").close.resample("1h", label="left", closed="left").last().dropna()
    e = h.ewm(span=50, adjust=False).mean()
    return e.index.values, e.values


def run(df, sym, start_hm=(9, 30), trend=True, coin_rng=None):
    T = df.ny.values; O, H, L, C, S = (df[k].values for k in ("open", "high", "low", "close", "spread"))
    eT, eV = h1_ema50(df); pt = PT[sym]; mk = MARKUP.get(sym, 0)
    days = pd.date_range(pd.Timestamp(T[0]).normalize(), pd.Timestamp(T[-1]).normalize(), freq="D")
    busy = np.datetime64("1970-01-01"); out = []
    for day in days:
        if day.dayofweek >= 5:
            continue
        st = np.datetime64(day + pd.Timedelta(hours=start_hm[0], minutes=start_hm[1]))
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
            if trend:
                j = np.searchsorted(eT, T[k], side="right") - 2  # last CLOSED H1 bar
                if j < 50:
                    break
                p = hi if (H[k] >= hi) else lo
                if not ((p > eV[j]) if d > 0 else (p < eV[j])):
                    break
            e = (max(hi, O[k]) if d > 0 else min(lo, O[k])) if coin_rng is None else C[k]
            sld = 2.2 * size; sl = e - d * sld; tp = e + d * 0.75 * sld
            cost = (S[k] + mk) * pt
            end = min(len(T), k + 60 * 24 * 20)
            slh = (L[k:end] <= sl) if d > 0 else (H[k:end] >= sl)
            tph = (H[k:end] >= tp) if d > 0 else (L[k:end] <= tp)
            tph[0] = False if coin_rng is None else tph[0]
            hit = np.flatnonzero(slh | tph)
            if not len(hit):
                break
            q = k + hit[0]; px = sl if slh[hit[0]] else tp
            R = (d * (px - e) - cost) / sld
            busy = T[q]; out.append((pd.Timestamp(T[k]), d, R, d * (px - e) - cost))
            break
    return pd.DataFrame(out, columns=["time", "d", "R", "px"])


def yr_stats(R):
    g = R.groupby(R.time.dt.year)
    return {y: (len(x), x.R.sum(), x.R[x.R > 0].sum() / max(-x.R[x.R < 0].sum(), 1e-12), (x.R > 0).mean()) for y, x in g}


if __name__ == "__main__":
    rows = []
    for sym in PT:
        df = load(sym)
        for sess, hm in (("NY 09:30", (9, 30)), ("London 03:00", (3, 0))):
            real = run(df, sym, hm)
            ys = yr_stats(real)
            tot = real.R.sum(); pf = real.R[real.R > 0].sum() / max(-real.R[real.R < 0].sum(), 1e-12)
            rng = np.random.default_rng(20261011); coins = [run(df, sym, hm, coin_rng=rng).R.sum() for _ in range(SEEDS if sess == "NY 09:30" else 10)]
            beats = (np.array(coins) < tot).mean()
            posy = sum(1 for v in ys.values() if v[1] > 0)
            print(f"\n=== {sym} {sess}: {len(real)} trades, {tot:+.1f}R, PF {pf:.2f}, win {(real.R > 0).mean():.0%}, positive years {posy}/{len(ys)} "
                  f"| coin-flip median {np.median(coins):+.1f}R, real beats {beats:.0%}", flush=True)
            print("   " + "  ".join(f"{y}: {n}tr {r:+.1f}R PF{p:.2f}" for y, (n, r, p, w) in ys.items()), flush=True)
            for y, (n, r, p, w) in ys.items():
                rows.append(dict(sym=sym, sess=sess, year=y, n=n, R=r, pf=p, win=w))
            rows.append(dict(sym=sym, sess=sess, year="ALL", n=len(real), R=tot, pf=pf, win=(real.R > 0).mean(), coin_med=np.median(coins), beats=beats))
            if sym == "EURUSD" and sess == "NY 09:30":
                real.to_csv(os.path.join(DATA, "orbmom_EURUSD_NY_trades.csv"), index=False)
    pd.DataFrame(rows).to_csv(os.path.join(DATA, "orbmom_longrun_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "orbmom_longrun_summary.csv"))
