"""TWI OB Hunter (tap & close) offline replica + random-zone control. READ-ONLY research (bars only, no orders).

Replicates TWI OB Hunter.mq5 defaults line for line: M15 structure (3-bar fractals, 8 kept, ATR14 = SMA of TR like MT5's iATR),
sweep >= 0.1 ATR and <= 3 ATR beyond the latest unswept swing with a close back inside, BOS close within 8 bars,
OB = last opposite candle in the 9 bars up to the BOS bar, zones aged out after 40 bars / invalidated on a close
0.05 ATR through the far side / capped at 6, one trade per zone, one open trade at a time, Mon-Fri.
Entry: the just-closed M5 candle wicks into the zone and closes back beyond it -> market order at the next M5 open
(long at ask, short at bid), SL beyond the zone + 0.05 ATR, TP 2R. Exits resolved on M1, SL first when a bar hits both,
gaps filled at the open. Spread = the bar's own spread (+6 points on XAUUSD for the live-account markup).

Control: the structure logic is identical, but every new OB is replaced by a "twin" of the same height and direction,
created at the same moment, whose distance from price is drawn at random from the real zones' own distance pool
(in ATR units). Same entries, stops, management, caps. If the real OBs don't beat their twins, the OB isn't the edge.

Data: M1 CSVs from TWIBarsExportTester (C:/Users/aland/stg/obh/<SYM>_M1.csv).
Run: C:/Users/aland/mt5-readonly/.venv/Scripts/python.exe obh_random_control_research.py [SEEDS]
"""
import sys, os
import numpy as np, pandas as pd

DATA = r"C:\Users\aland\stg\obh"
SYMS = {"EURUSD": 0.00001, "GBPUSD": 0.00001, "USDJPY": 0.001, "XAUUSD": 0.01}
EXTRA_SPREAD = {"XAUUSD": 6}
SEEDS = int(sys.argv[1]) if len(sys.argv) > 1 else 50
LB, MAXSW, ATRN, SWMIN, SWMAX, BOSMAX, OBAGE, OBBUF, MAXOB, RR = 3, 8, 14, 0.10, 3.0, 8, 40, 0.05, 6, 2.0


def load(sym):
    df = pd.read_csv(os.path.join(DATA, f"{sym}_M1.csv"))
    df["time"] = pd.to_datetime(df.time_server, format="%Y.%m.%d %H:%M")
    df = df.drop(columns="time_server").sort_values("time").drop_duplicates("time").reset_index(drop=True)
    return df


def resample(m1, rule):
    g = m1.set_index("time").resample(rule, label="left", closed="left")
    out = pd.DataFrame({"open": g.open.first(), "high": g.high.max(), "low": g.low.min(), "close": g.close.last()}).dropna()
    return out.reset_index()


def atr_sma(df, n=ATRN):
    h, l, c = df.high.values, df.low.values, df.close.values
    pc = np.roll(c, 1); pc[0] = c[0]
    tr = np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
    return pd.Series(tr).rolling(n).mean().values


def structure_events(m15):
    """Run the EA's OnStructureBarClose over every M15 bar. Returns per-bar ATR and the OB creation events."""
    H, L, O, C = m15.high.values, m15.low.values, m15.open.values, m15.close.values
    T = m15.time.values
    A = atr_sma(m15)
    highs, lows = [], []  # dicts: p, t, swept
    pend = {-1: None, 1: None}
    events = []  # (bar i, isBull, top, bottom)
    for i in range(LB * 2 + BOSMAX + 5, len(m15)):
        a = A[i]
        if not a > 0:
            continue
        cand = i - LB
        ch, cl = H[cand], L[cand]
        nb = list(range(cand - LB, cand)) + list(range(cand + 1, cand + LB + 1))
        if not any(H[k] > ch for k in nb):
            highs.append(dict(p=ch, t=T[cand], swept=False)); highs[:] = highs[-MAXSW:]
        if not any(L[k] < cl for k in nb):
            lows.append(dict(p=cl, t=T[cand], swept=False)); lows[:] = lows[-MAXSW:]
        h1, l1, c1, t1 = H[i], L[i], C[i], T[i]

        def latest(lst, before):
            for s in reversed(lst):
                if not s["swept"] and s["t"] < before:
                    return s
            return None
        sh = latest(highs, t1)
        if sh is not None and h1 > sh["p"] + a * SWMIN and c1 < sh["p"]:
            sh["swept"] = True
            if not h1 > sh["p"] + a * SWMAX:
                lo = latest(lows, sh["t"])
                if lo is not None and pend[-1] is None:
                    pend[-1] = dict(lvl=lo["p"], w=0)
        sl_ = latest(lows, t1)
        if sl_ is not None and l1 < sl_["p"] - a * SWMIN and c1 > sl_["p"]:
            sl_["swept"] = True
            if not l1 < sl_["p"] - a * SWMAX:
                hi = latest(highs, sl_["t"])
                if hi is not None and pend[1] is None:
                    pend[1] = dict(lvl=hi["p"], w=0)
        for d in (-1, 1):
            p = pend[d]
            if p is None:
                continue
            p["w"] += 1
            if (c1 < p["lvl"]) if d == -1 else (c1 > p["lvl"]):
                for s in range(i, i - BOSMAX - 1, -1):  # shifts 1..1+MaxBarsForBOS
                    if (C[s] > O[s]) if d == -1 else (C[s] < O[s]):
                        events.append((i, d == 1, H[s], L[s])); break
                pend[d] = None
            elif p["w"] > BOSMAX:
                pend[d] = None
    return A, events


def resolve(m1, k, d, entry, sl, tp, pt, sp):
    """First M1 bar from k on that hits SL or TP. Returns (exit index, exit price)."""
    O, H, L, S = m1.open.values, m1.high.values, m1.low.values, m1.spread.values
    n = len(O); start = k; step = 3000
    while start < n:
        end = min(n, start + step)
        if d == 1:
            slh = L[start:end] <= sl; tph = H[start:end] >= tp
        else:
            ask_h = H[start:end] + (S[start:end] + sp) * pt; ask_l = L[start:end] + (S[start:end] + sp) * pt
            slh = ask_h >= sl; tph = ask_l <= tp
        hit = np.flatnonzero(slh | tph)
        if len(hit):
            m = start + hit[0]
            if d == 1:
                o = O[m]
                if m > k and o <= sl: return m, o
                if m > k and o >= tp: return m, o
                return m, (sl if slh[hit[0]] else tp)
            o = O[m] + (S[m] + sp) * pt
            if m > k and o >= sl: return m, o
            if m > k and o <= tp: return m, o
            return m, (sl if slh[hit[0]] else tp)
        start = end
    return n - 1, (O[n - 1] if d == 1 else O[n - 1] + (S[n - 1] + sp) * pt)


def simulate(m1, m5, m15, A, zone_events, pt, sp):
    """zone_events: list of (struct bar i, isBull, top, bottom). Runs the EA's zone book + M5 tap & close entries."""
    t5 = m5.time.values; t15 = m15.time.values; t1m = m1.time.values
    O5, H5, L5, C5 = m5.open.values, m5.high.values, m5.low.values, m5.close.values
    C15 = m15.close.values
    O1, S1 = m1.open.values, m1.spread.values
    ev_by_bar = {}
    for e in zone_events:
        ev_by_bar.setdefault(e[0], []).append(e)
    dow5 = pd.DatetimeIndex(t5).dayofweek.values
    b15 = (t5.astype("datetime64[m]").astype(np.int64) // 15)
    i15_of = np.searchsorted(t15, t5, side="right") - 1
    zones = []  # [top, bottom, bull, age, filled]
    trades = []
    busy_until = np.datetime64("1970-01-01")
    atr = np.nan
    for j in range(len(m5) - 1):
        nxt = j + 1
        if b15[nxt] != b15[j]:
            i = i15_of[j]
            if i >= 0 and A[i] > 0:
                atr = A[i]; c1 = C15[i]
                for e in ev_by_bar.get(i, ()):
                    zones.append([e[2], e[3], e[1], 0, False])
                keep = []
                for z in zones:
                    z[3] += 1
                    inval = (c1 < z[1] - atr * OBBUF) if z[2] else (c1 > z[0] + atr * OBBUF)
                    if not inval and z[3] <= OBAGE:
                        keep.append(z)
                zones = keep[-MAXOB:] if len(keep) > MAXOB else keep
        now = t5[nxt]
        if not zones or not atr > 0 or now < busy_until:
            continue
        if dow5[nxt] >= 5:
            continue
        lowE, highE, closeE = L5[j], H5[j], C5[j]
        for z in zones:
            if z[4]:
                continue
            top, bot, bull = z[0], z[1], z[2]
            if bull and bot <= lowE <= top and closeE > top:
                d = 1
            elif (not bull) and bot <= highE <= top and closeE < bot:
                d = -1
            else:
                continue
            k = int(np.searchsorted(t1m, now))
            if k >= len(O1):
                break
            bid = O1[k]; ask = bid + (S1[k] + sp) * pt
            if d == 1:
                entry = ask; sl = bot - atr * OBBUF; risk = entry - sl
            else:
                entry = bid; sl = top + atr * OBBUF; risk = sl - entry
            if risk <= 0:
                continue
            tp = entry + d * risk * RR
            m, px = resolve(m1, k, d, entry, sl, tp, pt, sp)
            pl = d * (px - entry)
            trades.append((now, d, entry, sl, tp, risk, pl, pl / risk))
            z[4] = True
            busy_until = t1m[m] + np.timedelta64(1, "m")
            break
    return pd.DataFrame(trades, columns=["time", "d", "entry", "sl", "tp", "risk", "pl", "R"])


def twins(m15, A, events, rng):
    C15 = m15.close.values
    pool = {True: [], False: []}
    for i, bull, top, bot in events:
        pool[bull].append(((C15[i] - top) if bull else (bot - C15[i])) / A[i])
    pool = {k: np.array(v) for k, v in pool.items()}
    out = []
    for i, bull, top, bot in events:
        h = top - bot; dist = rng.choice(pool[bull]) * A[i]
        if bull:
            t = C15[i] - dist; out.append((i, bull, t, t - h))
        else:
            b = C15[i] + dist; out.append((i, bull, b + h, b))
    return out


def summ(R):
    if len(R) == 0:
        return dict(n=0, totR=0.0, avgR=0.0, win=0.0, pfR=0.0, pf_px=0.0)
    r = R.R; p = R.pl
    return dict(n=len(R), totR=r.sum(), avgR=r.mean(), win=(r > 0).mean(),
                pfR=r[r > 0].sum() / max(-r[r < 0].sum(), 1e-12), pf_px=p[p > 0].sum() / max(-p[p < 0].sum(), 1e-12))


if __name__ == "__main__":
    rows = []
    for sym, pt in SYMS.items():
        if not os.path.exists(os.path.join(DATA, f"{sym}_M1.csv")):
            print(sym, "no data"); continue
        m1 = load(sym); m5 = resample(m1, "5min"); m15 = resample(m1, "15min")
        sp = EXTRA_SPREAD.get(sym, 0)
        A, ev = structure_events(m15)
        real = simulate(m1, m5, m15, A, ev, pt, sp)
        real["year"] = pd.to_datetime(real.time).dt.year
        real.to_csv(os.path.join(DATA, f"{sym}_real_trades.csv"), index=False)
        s = summ(real)
        print(f"\n=== {sym}: {m1.time.iloc[0]:%Y-%m-%d} -> {m1.time.iloc[-1]:%Y-%m-%d}, {len(ev)} OB zones, "
              f"REAL {s['n']} trades, {s['totR']:+.1f}R, avg {s['avgR']:+.3f}R, win {s['win']:.1%}, PF(R) {s['pfR']:.2f}, PF(fixed lot) {s['pf_px']:.2f}", flush=True)
        years = sorted(real.year.unique())
        yr_real = {y: summ(real[real.year == y]) for y in years}
        rng = np.random.default_rng(20261010)
        tw_tot, tw_year = [], {y: [] for y in years}
        for sd in range(SEEDS):
            tw = simulate(m1, m5, m15, A, twins(m15, A, ev, rng), pt, sp)
            tw["year"] = pd.to_datetime(tw.time).dt.year
            tw_tot.append(summ(tw))
            for y in years:
                tw_year[y].append(tw[tw.year == y].R.sum())
        tt = np.array([x["totR"] for x in tw_tot]); ta = np.array([x["avgR"] for x in tw_tot])
        pct = (tt < s["totR"]).mean()
        print(f"  TWINS ({SEEDS} seeds): total R median {np.median(tt):+.1f} [5%-95%: {np.percentile(tt,5):+.1f} .. {np.percentile(tt,95):+.1f}], "
              f"avg/trade median {np.median(ta):+.3f}R, trades median {int(np.median([x['n'] for x in tw_tot]))} | REAL beats {pct:.0%} of twins")
        for y in years:
            yr = yr_real[y]; arr = np.array(tw_year[y])
            print(f"   {y}: real {yr['n']:4d} tr {yr['totR']:+7.1f}R (avg {yr['avgR']:+.3f}, win {yr['win']:.0%}, PF {yr['pfR']:.2f}) | "
                  f"twins median {np.median(arr):+7.1f}R | real beats {(arr < yr['totR']).mean():.0%}")
            rows.append(dict(sym=sym, year=y, real_n=yr["n"], real_R=yr["totR"], real_avg=yr["avgR"], real_pf=yr["pfR"],
                             twin_med=np.median(arr), beats=(arr < yr["totR"]).mean()))
        rows.append(dict(sym=sym, year="ALL", real_n=s["n"], real_R=s["totR"], real_avg=s["avgR"], real_pf=s["pfR"],
                         twin_med=np.median(tt), beats=pct))
    pd.DataFrame(rows).to_csv(os.path.join(DATA, "obh_random_control_summary.csv"), index=False)
    print("\nsaved", os.path.join(DATA, "obh_random_control_summary.csv"))
